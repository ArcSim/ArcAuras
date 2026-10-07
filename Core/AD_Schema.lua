-- Option schema: every setting is declared once, and the store resolver,
-- Normalize, the serializer and the options panel derive from it.
-- A value resolves from the record, its layout, newDefaults, dk[kind], then d.
-- Sections with push = true get Push to All and Save as Default.
-- adv = "<word>": a fine-tuning field; the editor draws it last in its block,
-- behind a "More <word> options" fold (UI\AD_EditorTabs.lua).

local ADDON, NS = ...
local Schema = {}
NS.Schema = Schema

Schema.VERSION = 1

-- Retail 12.1.0's aura engine lacks three things 12.1.5 and Forever have: the
-- per-type art style, an applications window on stack bars, and removal of a
-- dispel texture by the texture. Options that need them hide on it.
NS.OldAuraEngine = NS.IsForever ~= true and Enum ~= nil
    and Enum.CustomAuraButtonDispelTypeTextureStyle ~= nil
    and Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset == nil

Schema.ICON_KINDS = { "spell", "item", "trinket", "timer", "totem", "aura", "ammo", "enchant", "special", "groupbuff",
    "stance" }
-- A reminder group (Drivers\AD_DriverReminders.lua) is a pulse window: its
-- members are reminder records, never icons.
Schema.GROUP_KINDS = { "cooldown", "aura", "reminder" }
-- Creatable bar kinds; cooldown and aura bars carry rec.barMode ("duration" or
-- "stack"). The create UI hides swing where C_SwingTimer is missing, but the
-- kind stays valid everywhere, so sync never rewrites a record. Legacy "timer"
-- and "stack" (power) bars stay legal but cannot be created.
Schema.BAR_KINDS = { "cooldown", "aura", "swing", "resource", "health", "cast", "enchant", "range", "text", "texture",
    "wheel", "special", "sound" }
-- A text element's sources (rec.driver.source, Bars\AD_TextElement.lua): each
-- reads plain in combat or reaches the screen through a text sink only.
Schema.TEXT_SOURCES = { "static", "power", "health", "name", "combo", "ammo", "petMood", "range", "clock",
    "spellCd", "spellCharges", "auraTime", "auraStacks", "rules", "custom", "spellText", "auraText" }
Schema.TEXT_SOURCE_LABELS = { static = "Words you type", power = "Your power", health = "Health", name = "Name",
    combo = "Combo points", ammo = "Ammo count", petMood = "Pet happiness", range = "Target range band",
    clock = "Time of day", spellCd = "A spell's cooldown", spellCharges = "A spell's charges",
    auraTime = "An aura's time left", auraStacks = "An aura's stacks", rules = "Custom rules",
    custom = "A Custom Icon or Bar's value", spellText = "A spell's custom text",
    auraText = "An aura's custom text" }
-- A text is for a spell or an aura: its value, or custom words shown on one
-- of its states, the states its icon glows on (rec.driver.when).
Schema.TEXT_SPELL_SOURCES = { "spellCd", "spellCharges", "spellText" }
Schema.TEXT_AURA_SOURCES = { "auraTime", "auraStacks", "auraText" }
Schema.TEXT_SPELL_WHEN = { "ready", "cooldown", "usable", "proc", "always" }
Schema.TEXT_SPELL_WHEN_LABELS = { ready = "When ready", cooldown = "While on cooldown", usable = "When usable",
    proc = "While its proc is up", always = "Always" }
Schema.TEXT_AURA_WHEN = { "up", "time", "missing", "always" }
Schema.TEXT_AURA_WHEN_LABELS = { up = "While the aura is up", time = "When little time is left",
    missing = "While the aura is missing", always = "Always" }
-- What a numeric source shows (power, health): the value, its maximum or the
-- percent; a rule-driven one: the stacks, the time left or both.
Schema.TEXT_SHOWS = { "current", "max", "percent" }
Schema.TEXT_SHOW_LABELS = { current = "Current value", max = "Maximum", percent = "Percent" }
Schema.TEXT_READOUTS = { "stacks", "left", "both" }
Schema.TEXT_READOUT_LABELS = { stacks = "The stacks", left = "The time left", both = "Both: stacks (time left)" }
-- A texture's sources (rec.driver.source, Bars\AD_TextureElement.lua): what
-- makes the picture active, and what a fill runs with. An aura's picture is
-- drawn by the game's aura engine, so it follows the aura in combat.
Schema.TEXTURE_SOURCES = { "aura", "spellCd", "rules" }
Schema.TEXTURE_SOURCE_LABELS = { aura = "An aura", spellCd = "A spell's cooldown", rules = "Custom triggers" }
-- a cooldown picture's active state (rec.driver.cdActive, nil = ready)
Schema.TEXTURE_CD_ACTIVE = { "ready", "cooldown" }
Schema.TEXTURE_CD_ACTIVE_LABELS = { ready = "The spell is ready", cooldown = "The spell is on cooldown" }
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
-- A main-hand swing bar's next-swing abilities (rec.driver.swingAbilIDs and
-- their rank picks, swingAbilRanks): how many the editor's list adds, and the
-- highest rank a pick can name.
Schema.SWING_ABIL_MAX = 8
Schema.SWING_ABIL_MAX_RANK = 20
-- A reminder's triggers (rec.triggers on a reminder record, Store.CleanTriggers),
-- ArcUI v1's Cooldown Reminder list: when each fires, and the looks it can pick.
-- Every trigger reads a value that stays plain in combat (a cooldown shadow's
-- IsShown, your own cast's spell ID, a proc overlay's spell ID, a weapon
-- enchant's time left and charges, C_Spell.IsSpellUsable).
Schema.REMINDER_MAX_TRIGGERS = 5
Schema.REMINDER_TRIGGERS = { "on_use", "when_ready", "on_proc", "after_ready", "into_cooldown", "when_usable" }
-- Types only a spell reminder has: an item's use has no usable state to read.
Schema.REMINDER_SPELL_ONLY = { when_usable = true }
-- A weapon enchant reminder's own list (kind "enchant").
Schema.REMINDER_ENCHANT_TRIGGERS = { "enchant_missing", "enchant_expiring", "enchant_charges" }
Schema.REMINDER_TRIGGER_LABELS = { on_use = "On use (when cast)", when_ready = "When ready (cooldown done)",
    on_proc = "On proc (proc glow turns on)", after_ready = "N seconds after ready",
    into_cooldown = "N seconds after cast", enchant_missing = "When it's missing (falls off, or none is on)",
    enchant_expiring = "N seconds before it runs out", enchant_charges = "When N charges are left",
    when_usable = "When usable (can be cast now)" }
Schema.REMINDER_ANIMS = { "default", "fade", "no_fade", "flash", "zoom" }
Schema.REMINDER_ANIM_LABELS = { default = "Default (the reminder's)", fade = "Fade",
    no_fade = "No Fade (snap off)", flash = "Flash (urgent)", zoom = "Zoom (pop in + fade)" }
Schema.REMINDER_GLOWS = { "none", "pixel", "autocast", "button", "proc", "ants" }
Schema.REMINDER_GLOW_LABELS = { none = "None", pixel = "Pixel (marching dots)",
    autocast = "Autocast (sparkles)", button = "Button (action bar)", proc = "Proc (Blizzard)",
    ants = "Ants (border crawl)" }
Schema.REMINDER_GLOW_COLOR = { 0, 0.8, 1, 1 }
-- A reminder's own look (its Appearance tab): the per-pulse fields of the
-- group's `pulse` section. The overlap, the icon switch and the marker stay the
-- group's: they are about the whole window.
Schema.REMINDER_LOOK = { "cancelOnCast", "holdUntilCast", "pulseDuration", "size", "iconOpacity", "animStyle",
    "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak", "animZoomPopTime",
    "animZoomSettleTime" }

-- Custom Icons and Custom Bars (the `timer` icon kind and bar kind): rules on
-- rec.driver.rules (Store.CleanRules), run by Drivers\AD_DriverCustom.lua. Each
-- rule is WHEN (a trigger) -> only if (guards) -> THEN (an action). Every
-- trigger is an event the game keeps plain in combat: UNIT_COMBAT on you and
-- your pet, COMBAT_TEXT_UPDATE's type, your own casts, cooldown and usable
-- edges read off shadow Cooldowns, proc overlays, combat, target and totem events.
Schema.CUSTOM_MAX_RULES = 8
Schema.CUSTOM_SHOW_WHILE = { "timer", "stacks", "either", "always" }
Schema.CUSTOM_SHOW_WHILE_LABELS = { timer = "The timer runs", stacks = "Stacks are above 0",
    either = "The timer runs or stacks are above 0", always = "Always" }
-- Trigger groups, in the dropdown's order; each trigger lists in one group.
Schema.CUSTOM_TRIGGER_GROUPS = {
    { key = "spell", label = "Spells",
        list = { "cast", "cd_start", "cd_end", "spell_update", "usable_on", "usable_off", "proc_on", "proc_off" } },
    { key = "you", label = "You, in melee",
        list = { "dodge", "parry", "block", "miss", "hit", "crit", "absorb", "resist", "immune", "avoided" } },
    { key = "pet", label = "Your pet",
        list = { "pet_dodge", "pet_parry", "pet_block", "pet_hit", "pet_crit" } },
    { key = "text", label = "From the game's combat text",
        list = { "extra_attacks", "reactive", "health_low", "mana_low", "combo_points", "interrupted",
            "energize", "healed", "heal_crit" } },
    { key = "other", label = "Other",
        list = { "combat_start", "combat_end", "target_changed", "totem_placed", "totem_gone", "chain" } },
}
-- Your attacks on the target (UNIT_COMBAT on "target"); listed only once the
-- engine's CUSTOM_TARGET_FEEDBACK switch is on.
Schema.CUSTOM_TARGET_TRIGGERS = { "target_dodge", "target_parry", "target_block", "target_miss",
    "target_hit", "target_crit" }
Schema.CUSTOM_TRIGGER_LABELS = {
    cast = "You cast a spell", cd_start = "A spell's cooldown started", cd_end = "A spell's cooldown ended",
    spell_update = "The game sent a spell update",
    usable_on = "A spell became usable", usable_off = "A spell stopped being usable",
    proc_on = "A proc glow started", proc_off = "A proc glow ended",
    dodge = "You dodged", parry = "You parried", block = "You blocked", miss = "An attack missed you",
    hit = "You were hit", crit = "You took a critical hit", absorb = "You absorbed an attack",
    resist = "You resisted a spell", immune = "You were immune", avoided = "You evaded, deflected or reflected",
    pet_dodge = "Your pet dodged", pet_parry = "Your pet parried", pet_block = "Your pet blocked",
    pet_hit = "Your pet was hit", pet_crit = "Your pet took a critical hit",
    extra_attacks = "You gained extra attacks", reactive = "A reactive ability lit up",
    health_low = "Your health is low", mana_low = "Your mana is low", combo_points = "Your combo points changed",
    interrupted = "Your cast was interrupted", energize = "You gained a resource",
    healed = "You were healed", heal_crit = "You took a critical heal",
    combat_start = "You entered combat", combat_end = "You left combat", target_changed = "Your target changed",
    totem_placed = "A totem was placed", totem_gone = "A totem is gone",
    chain = "Another Custom item's timer ended",
    target_dodge = "Your attack was dodged", target_parry = "Your attack was parried",
    target_block = "Your attack was blocked", target_miss = "Your attack missed",
    target_hit = "You hit the target", target_crit = "You crit the target",
    cond_on = "A condition turns on", cond_off = "A condition turns off",
    aura_gain = "An aura appears", aura_stack = "An aura gains a stack", aura_lost = "An aura drops",
}
Schema.CUSTOM_ACTIONS = { "start", "stop", "add", "remove", "set", "reset", "sound", "speak" }
Schema.CUSTOM_ACTION_LABELS = { start = "Start the timer", stop = "Stop the timer", add = "Add stacks",
    remove = "Remove stacks", set = "Set stacks", reset = "Reset the timer and stacks",
    sound = "Play a sound", speak = "Speak text" }
Schema.CUSTOM_START_MODES = { "restart", "extend", "idle" }
Schema.CUSTOM_START_MODE_LABELS = { restart = "Restart it", extend = "Extend it by the seconds",
    idle = "Only if it is not running" }
Schema.CUSTOM_COMBAT = { "any", "in", "out" }
Schema.CUSTOM_COMBAT_LABELS = { any = "In or out of combat", ["in"] = "In combat", out = "Out of combat" }
Schema.CUSTOM_TIMER_STATES = { "any", "running", "idle" }
Schema.CUSTOM_TIMER_STATE_LABELS = { any = "Running or not", running = "The timer is running",
    idle = "The timer is not running" }
-- The Sound item (bar kind "sound", Bars\AD_SoundItem.lua): rules on the same
-- engine whose only actions are a sound or a spoken line. Its triggers are the
-- Custom ones plus a condition's edge (r.cond, a Conditions key) and an aura's
-- moments, which the game plays itself (r.unit, r.auraIDs; Drivers\AD_AuraSounds.lua).
Schema.SOUND_TRIGGER_GROUPS = (function()
    local out = {}
    for _, g in ipairs(Schema.CUSTOM_TRIGGER_GROUPS) do out[#out + 1] = g end
    out[#out + 1] = { key = "cond", label = "Conditions", list = { "cond_on", "cond_off" } }
    out[#out + 1] = { key = "aura", label = "Auras", list = { "aura_gain", "aura_stack", "aura_lost" } }
    return out
end)()
Schema.SOUND_ACTIONS = { "sound", "speak" }
Schema.SOUND_AURA_UNITS = { "player", "target", "focus", "pet" }
Schema.SOUND_AURA_UNIT_LABELS = { player = "You", target = "Your target", focus = "Your focus", pet = "Your pet" }

-- enchant: a weapon enchant, timed on the swipe; its sounds say applied and
-- fell off (NS.DriverEnchant).
-- special: a Special Aura (Core\AD_SpecialIcon.lua over NS.Special, retail
-- only): a deck's position on the stack text, its procs and chance on the
-- labels, "all procs used" or a running internal cooldown as the cooldown look.
-- stance: the stance you are in, or one stance lit while you are in it
-- (Drivers\AD_DriverStance.lua): in it is the ready look, not in it the
-- cooldown look. It has no swipe, sounds, count or timer.
local CD  = { spell = true, item = true, trinket = true, timer = true, totem = true, enchant = true, special = true }
-- the ready look's grey out, both state tints and the ready glow: the
-- cooldown kinds and a stance icon (In the stance / Not in it)
local CDST = { spell = true, item = true, trinket = true, timer = true, totem = true, enchant = true, special = true,
    stance = true }
-- the cooldown-driven sounds; a special icon's own pair is the proc edge
local USE_CD = { spell = true, item = true, trinket = true, timer = true, enchant = true }
local USE = { spell = true, item = true, trinket = true, timer = true, enchant = true, special = true }
local SP  = { spell = true }
local AU  = { aura = true }
local TOT = { totem = true }
local AA  = { spell = true, aura = true }
local SPC = { special = true }
-- Every kind but aura: holder-only options (keep bright) mean nothing on an
-- engine-drawn aura button.
local NA  = { spell = true, item = true, trinket = true, timer = true, totem = true, ammo = true,
    enchant = true, special = true, stance = true }
-- Stack text: only kinds something writes a count for (spell charges, item and
-- ammo bag counts, aura applications, timer stacks, enchant charges, a deck's
-- position, a group buff's have / total). Trinkets have none.
local STK = { spell = true, item = true, timer = true, aura = true, ammo = true, enchant = true, special = true,
    groupbuff = true }
-- The two-state dim: the cooldown kinds, a group buff (someone lacks it /
-- everyone has it, Drivers\AD_DriverGroupBuff.lua) and a stance icon.
local CDGB = { spell = true, item = true, trinket = true, timer = true, totem = true, enchant = true, special = true,
    groupbuff = true, stance = true }
-- The duration text: kinds with a time to count down (not ammo, not a group
-- buff: their text is a count).
local DUR = { spell = true, item = true, trinket = true, timer = true, totem = true, enchant = true, special = true,
    aura = true }
-- The "while on cooldown" glow: the kinds whose cooldown look means a real
-- cooldown (a totem's or enchant's is "missing", worded apart).
local CDG = { spell = true, item = true, trinket = true, timer = true, special = true }
-- An ammo count: the ammo icon's stack text, a spell icon's ammo text.
local AMMO_CT = { ammo = true, spell = true }
-- The kinds whose custom texts follow their two states (the first two rows
-- of their Conditions table: ready / on cooldown, active / missing, ...).
local TWO = { spell = true, item = true, trinket = true, timer = true, totem = true, ammo = true,
    enchant = true, special = true, groupbuff = true, stance = true }
-- "Minutes and seconds" cutoffs in seconds, for icons and bars alike.
local ABBREV_VALUES = { 0, 120, 300, 600, 3600 }
local ABBREV_LABELS = { [0] = "Off", [120] = "Under 2 minutes", [300] = "Under 5 minutes",
    [600] = "Under 10 minutes", [3600] = "Under 1 hour" }
-- How the GCD and the wand's lock draw on a spell icon. Neither ever counts as
-- a real cooldown, so these are looks only.
local GCD_LOOKS = { "hidden", "edge", "swipe", "both" }
local GCD_LOOK_LABELS = { hidden = "Hidden", edge = "Edge only", swipe = "Swipe", both = "Swipe and edge" }
local GCD_SWIPE_DRAWN = { swipe = true, both = true }
-- Where a text sits (Core\AD_TextAnchor.lua): its own spot, or riding a named
-- frame, the action button holding a spell, or a Cooldown Manager icon (by
-- spell or by cooldown ID). The frame name, spells or "cd:<id>" ride in the
-- text's PinTarget field.
Schema.PIN_TO = { "own", "frame", "action", "cdm" }
-- A resource bar's own look per power (a druid's forms), per spec, or with and
-- without a talent (Core\AD_Looks.lua). Its place, size and rules are the
-- bar's in every look.
Schema.LOOK_MODES = { "power", "spec", "talent" }
Schema.LOOK_SKIP = { size = true, frame = true, anchor = true, behavior = true, mouse = true }
Schema.PIN_LABELS = { own = "Its own spot", frame = "A named frame", action = "An action button",
    cdm = "A Cooldown Manager icon" }
-- The classes that shoot a wand; the wand rows show only there.
local WAND_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true }

local GK_CD = { cooldown = true }
local GK_AU = { aura = true }
local GK_RM = { reminder = true }

local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- What an icon override's number is. Spell, item and icon file IDs overlap, so
-- each `<x>Icon` has an `<x>IconFrom` beside it and nothing is guessed. Icon ID
-- is the default: the tooltip shows icon IDs, and any art has one.
local ICON_FROM = { "icon", "spell", "item" }
local ICON_FROM_LABELS = { icon = "Icon ID", spell = "Spell ID", item = "Item ID" }

-- Glow styles for all four glows (ready, proc, usable, aura active): procloop
-- is the proc glow without its opening burst, ants Blizzard's marching ants,
-- flash the Cooldown Manager's flash, redflash the action bar's blinking red
-- (white keeps its own red). Proc, proc loop and ants run at Blizzard's fixed
-- pace, so Speed shows only for GLOW_SPEED_STYLES.
local GLOW_STYLES = { "button", "pixel", "autocast", "proc", "procloop", "ants", "flash", "redflash" }
local PROC_GLOW_STYLES = { "proc", "procloop", "button", "pixel", "autocast", "ants", "flash", "redflash" }
-- The aura active glow never opens with a burst, so Proc already draws the loop
-- alone there and its twin would only repeat it.
local AURA_GLOW_STYLES = { "button", "pixel", "autocast", "proc", "ants", "flash", "redflash" }
local GLOW_STYLE_LABELS = { button = "Button", pixel = "Pixel", autocast = "Autocast",
    proc = "Proc", procloop = "Proc loop (no burst)", ants = "Marching ants",
    flash = "Cooldown Manager flash", redflash = "Action bar red flash" }
local GLOW_SPEED_STYLES = { button = true, pixel = true, autocast = true, flash = true, redflash = true }

-- What lights the warning glow (Drivers\AD_DriverWarn.lua). Ammo counts and pet
-- happiness are plain in combat; pet health is secret, so a curve sets that
-- glow's opacity instead of a comparison.
Schema.WARN_WHEN = { "ammo", "petHealth", "petMood" }
Schema.WARN_WHEN_LABELS = { ammo = "Ammo is low", petHealth = "Pet health is low",
    petMood = "Pet is not happy" }
-- The warning chip shows for the classes with ammo or a pet to warn about; on
-- retail the three classes with a lasting pet (a death knight's is Unholy's).
Schema.WARN_CLASSES = NS.IsForever == true and { HUNTER = true, WARLOCK = true }
    or { HUNTER = true, WARLOCK = true, DEATHKNIGHT = true }
-- Retail has no ammo or pet happiness: only pet health warns there.
local function ForeverWarn() return NS.IsForever == true end
Schema.WARN_WHEN_IF = { ammo = ForeverWarn, petMood = ForeverWarn }

-- The toggle glow's rows show on a spell icon whose spell toggles: Shoot,
-- Auto Shot or melee Attack (Drivers\AD_DriverToggle.lua).
local function ToggleShows(rec)
    local DT = NS.DriverToggle
    return DT ~= nil and DT.IsToggle ~= nil and DT.IsToggle(rec)
end

-- The Recharging rows show on a spell icon whose spell has charges
-- (Drivers\AD_DriverCooldown.lua IsCharge).
local function ChargeShows(rec)
    local D = NS.DriverCooldown
    return D ~= nil and D.IsCharge ~= nil and D.IsCharge(rec)
end

-- "Show only when little time is left" needs the icon's own button.
local function TimeGateShows(rec)
    local DA = NS.DriverAura
    return DA ~= nil and DA.TimeGateOK ~= nil and DA.TimeGateOK(rec)
end

-- The ammo count's own threshold colours show with the text that carries the
-- count: the ammo icon's stack text, a spell icon's ammo text.
function Schema.AmmoCountShown(rec)
    local Store = NS.Store
    if not (rec and Store) then return false end
    if rec.kind == "ammo" then return Store.Resolve(rec, "text", "stackText") ~= false end
    return Store.Resolve(rec, "text", "ammoText") == true
end

-- A totem icon set to one totem by its spell: it has one buff to be out of
-- range of. A slot icon holds whatever lands in its slot.
function Schema.TotemBySpell(rec)
    if not (rec and rec.kind == "totem" and type(rec.driver) == "table") then return false end
    return tonumber(rec.driver.spellID) ~= nil
end

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
        borderColor = { d = { 0, 0, 0, 1 }, t = "color", alpha = true, label = "Border color", dep = { field = "borderEnabled" } },
        borderThickness = { d = 2, t = "int", min = 1, max = 20, label = "Border thickness", dep = { field = "borderEnabled" } },
        borderInset = { d = 0, t = "int", min = -20, max = 20, label = "Border offset", dep = { field = "borderEnabled" } },
        -- Aura icons: the engine colours the border through the button's own
        -- dispel-type textures. No Lua reads the type, so it works in combat.
        dispelBorder = { d = false, t = "bool", kinds = AU, newAuraEngine = true, label = "Border colour by dispel type",
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
        strata = { adv = "frame", d = "AUTO", t = "enum",
            values = { "AUTO", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
            label = "Frame strata" },
        frameLevel = { adv = "frame", d = 0, t = "int", min = 0, max = 50, label = "Frame level bump" },
    } },
    states = { push = true, inherit = true, fields = {
        readyAlpha    = { d = 1.0,  t = "num", min = 0, max = 1, label = "Ready alpha" },
        -- Not on ammo icons: they never have a cooldown. A group buff's is
        -- "everyone has it", hidden until the user shows it; a stance icon's
        -- is "not in it", dimmed and greyed so the stance you are in stands out.
        cooldownAlpha = { d = 1.0, dk = { groupbuff = 0, stance = 0.6 }, t = "num", min = 0, max = 1, kinds = CDGB,
            label = "On cooldown alpha" },
        cooldownDesaturate = { d = true, t = "bool", kinds = CDGB, label = "Desaturate on cooldown" },
        -- the ready look (a Custom Icon's Active) can grey out too
        readyDesaturate = { d = false, t = "bool", kinds = CDST, label = "Desaturate when ready" },
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
        -- A charge spell that locks itself after each cast (Zenith): its main
        -- cooldown with a charge in hand reads as recharging, unless the cast
        -- spent the last of two (Drivers\AD_DriverCooldown.lua ShadowState).
        ignoreHardICD = { d = false, t = "bool", kinds = SP, showIf = ChargeShows, label = "Ignore hard ICD",
            desc = "For a charge spell that also locks for a while after each cast: show its charges and recharge, not that lock." },
        readyGlow = { d = false, t = "bool", kinds = CDST, label = "Glow when ready" },
        readyGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = CDST, label = "Glow style", dep = { field = "readyGlow" } },
        readyGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", kinds = CDST, label = "Glow color", dep = { field = "readyGlow" } },
        readyGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = CDST, label = "Glow speed",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", anyOf = GLOW_SPEED_STYLES } } },
        readyGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = CDST, label = "Glow lines",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = CDST, label = "Glow thickness",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = CDST, label = "Glow line length (0 = auto)",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "pixel" } } },
        readyGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = CDST, label = "Glow particles",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "autocast" } } },
        readyGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = CDST, label = "Glow intensity",
            dep = { field = "readyGlow" } },
        readyGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = CDST, label = "Glow size",
            dep = { { field = "readyGlow" }, { field = "readyGlowType", value = "autocast" } } },
        readyGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDST, label = "Glow X offset",
            dep = { field = "readyGlow" } },
        readyGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDST, label = "Glow Y offset",
            dep = { field = "readyGlow" } },
        -- Move shifts the glow without resizing it; the X/Y offsets above grow
        -- or shrink it.
        readyGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDST, label = "Glow move X",
            dep = { field = "readyGlow" } },
        readyGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDST, label = "Glow move Y",
            dep = { field = "readyGlow" } },
        readyGlowCombatOnly = { d = false, t = "bool", kinds = CDST, label = "Glow only in combat",
            dep = { field = "readyGlow" } },
        readyGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = CDST, label = "Glow strata",
            dep = { field = "readyGlow" } },
        readyGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = CDST, label = "Glow frame level",
            dep = { field = "readyGlow" } },
        -- Glows while the real cooldown runs (the GCD never counts: the
        -- driver's dim state ignores it); a special icon's "all procs used"
        -- or running internal cooldown is that state too.
        cooldownGlow = { d = false, t = "bool", kinds = CDG, label = "Glow while on cooldown" },
        cooldownGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = CDG, label = "Cooldown glow style", dep = { field = "cooldownGlow" } },
        cooldownGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", kinds = CDG, label = "Cooldown glow color", dep = { field = "cooldownGlow" } },
        cooldownGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = CDG, label = "Cooldown glow speed",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", anyOf = GLOW_SPEED_STYLES } } },
        cooldownGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = CDG, label = "Cooldown glow lines",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", value = "pixel" } } },
        cooldownGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = CDG, label = "Cooldown glow thickness",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", value = "pixel" } } },
        cooldownGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = CDG, label = "Cooldown glow line length (0 = auto)",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", value = "pixel" } } },
        cooldownGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = CDG, label = "Cooldown glow particles",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", value = "autocast" } } },
        cooldownGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = CDG, label = "Cooldown glow intensity",
            dep = { field = "cooldownGlow" } },
        cooldownGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = CDG, label = "Cooldown glow size",
            dep = { { field = "cooldownGlow" }, { field = "cooldownGlowType", value = "autocast" } } },
        cooldownGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDG, label = "Cooldown glow X offset",
            dep = { field = "cooldownGlow" } },
        cooldownGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDG, label = "Cooldown glow Y offset",
            dep = { field = "cooldownGlow" } },
        cooldownGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDG, label = "Cooldown glow move X",
            dep = { field = "cooldownGlow" } },
        cooldownGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = CDG, label = "Cooldown glow move Y",
            dep = { field = "cooldownGlow" } },
        cooldownGlowCombatOnly = { d = false, t = "bool", kinds = CDG, label = "Cooldown glow only in combat",
            dep = { field = "cooldownGlow" } },
        cooldownGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = CDG, label = "Cooldown glow strata",
            dep = { field = "cooldownGlow" } },
        cooldownGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = CDG, label = "Cooldown glow frame level",
            dep = { field = "cooldownGlow" } },
        readyTintEnabled = { d = false, t = "bool", kinds = CDST, label = "Ready tint" },
        readyTintColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = CDST, label = "Ready tint color", dep = { field = "readyTintEnabled" } },
        cooldownTintEnabled = { d = false, t = "bool", kinds = CDST, label = "Cooldown tint" },
        cooldownTintColor = { d = { 0.5, 0.5, 0.5, 1 }, t = "color", kinds = CDST, label = "Cooldown tint color", dep = { field = "cooldownTintEnabled" } },
        -- On by default, mirroring Blizzard's own proc overlay.
        procGlow = { d = true, t = "bool", kinds = SP, label = "Proc glow" },
        procGlowType = { d = "proc", t = "enum", values = PROC_GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP, label = "Proc glow style", dep = { field = "procGlow" } },
        procGlowColor = { d = { 0.95, 0.95, 0.32, 1 }, t = "color", kinds = SP, label = "Proc glow color", dep = { field = "procGlow" } },
        procGlowSpeed = { adv = "glow", d = 0.4, t = "num", min = 0.05, max = 1, kinds = SP, label = "Proc glow speed",
            dep = { { field = "procGlow" }, { field = "procGlowType", anyOf = GLOW_SPEED_STYLES } } },
        procGlowLines = { adv = "glow", d = 10, t = "int", min = 1, max = 16, kinds = SP, label = "Proc glow lines",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = SP, label = "Proc glow thickness",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = SP, label = "Proc glow line length (0 = auto)",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "pixel" } } },
        procGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = SP, label = "Proc glow particles",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "autocast" } } },
        procGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = SP, label = "Proc glow size",
            dep = { { field = "procGlow" }, { field = "procGlowType", value = "autocast" } } },
        procGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = SP, label = "Proc glow intensity",
            dep = { field = "procGlow" } },
        procGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow X offset",
            dep = { field = "procGlow" } },
        procGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow Y offset",
            dep = { field = "procGlow" } },
        procGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow move X",
            dep = { field = "procGlow" } },
        procGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Proc glow move Y",
            dep = { field = "procGlow" } },
        procGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = SP, label = "Proc glow strata",
            dep = { field = "procGlow" } },
        procGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = SP, label = "Proc glow frame level",
            dep = { field = "procGlow" } },
        -- On by default, like Blizzard's action buttons.
        resourceTintEnabled = { d = true, t = "bool", kinds = SP, label = "No-resource tint" },
        resourceTintColor = { d = { 0.35, 0.45, 1, 1 }, t = "color", kinds = SP, label = "No-resource tint color", dep = { field = "resourceTintEnabled" } },
        resourceDesaturate = { d = false, t = "bool", kinds = SP, label = "Desaturate on no resource" },
        unusableTintEnabled = { d = true, t = "bool", kinds = SP, label = "Unusable tint" },
        unusableTintColor = { d = { 0.45, 0.45, 0.45, 1 }, t = "color", kinds = SP, label = "Unusable tint color", dep = { field = "unusableTintEnabled" } },
        unusableDesaturate = { d = false, t = "bool", kinds = SP, label = "Desaturate while unusable" },
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
        usableGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = SP, label = "Usable glow speed",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", anyOf = GLOW_SPEED_STYLES } } },
        usableGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = SP, label = "Usable glow lines",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = SP, label = "Usable glow thickness",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = SP, label = "Usable glow line length (0 = auto)",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "pixel" } } },
        usableGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = SP, label = "Usable glow particles",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "autocast" } } },
        usableGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = SP, label = "Usable glow size",
            dep = { { field = "usableGlow" }, { field = "usableGlowType", value = "autocast" } } },
        usableGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = SP, label = "Usable glow intensity",
            dep = { field = "usableGlow" } },
        usableGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow X offset",
            dep = { field = "usableGlow" } },
        usableGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow Y offset",
            dep = { field = "usableGlow" } },
        usableGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow move X",
            dep = { field = "usableGlow" } },
        usableGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Usable glow move Y",
            dep = { field = "usableGlow" } },
        usableGlowCombatOnly = { d = false, t = "bool", kinds = SP, label = "Usable glow only in combat",
            dep = { field = "usableGlow" } },
        usableGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = SP, label = "Usable glow strata",
            dep = { field = "usableGlow" } },
        usableGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = SP, label = "Usable glow frame level",
            dep = { field = "usableGlow" } },
        -- Glows while the ammo runs low, the pet's health is low or the pet is
        -- not happy (Drivers\AD_DriverWarn.lua), whatever the icon's own state.
        warnGlow = { d = false, t = "bool", kinds = NA, classOnly = Schema.WARN_CLASSES, label = "Warning glow" },
        warnGlowWhen = { d = NS.IsForever == true and "ammo" or "petHealth", t = "enum", values = Schema.WARN_WHEN,
            labels = Schema.WARN_WHEN_LABELS, valueIf = Schema.WARN_WHEN_IF,
            kinds = NA, classOnly = Schema.WARN_CLASSES, label = "Glow when", dep = { field = "warnGlow" } },
        warnAmmoBelow = { d = 400, t = "int", min = 1, max = 2000, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Ammo at or below", dep = { { field = "warnGlow" }, { field = "warnGlowWhen", value = "ammo" } } },
        warnPetHealth = { d = 50, t = "int", min = 1, max = 99, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Pet health at or below (%)",
            dep = { { field = "warnGlow" }, { field = "warnGlowWhen", value = "petHealth" } } },
        warnPetMood = { d = "notHappy", t = "enum", values = { "notHappy", "unhappy" },
            labels = { notHappy = "Content or unhappy", unhappy = "Unhappy" },
            kinds = NA, classOnly = Schema.WARN_CLASSES, label = "Glow while the pet is",
            dep = { { field = "warnGlow" }, { field = "warnGlowWhen", value = "petMood" } } },
        warnGlowType = { d = "flash", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = NA,
            classOnly = Schema.WARN_CLASSES, label = "Warning glow style", dep = { field = "warnGlow" } },
        warnGlowColor = { d = { 1, 0.3, 0.2, 1 }, t = "color", kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow color", dep = { field = "warnGlow" } },
        warnGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow speed",
            dep = { { field = "warnGlow" }, { field = "warnGlowType", anyOf = GLOW_SPEED_STYLES } } },
        warnGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow lines", dep = { { field = "warnGlow" }, { field = "warnGlowType", value = "pixel" } } },
        warnGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow thickness", dep = { { field = "warnGlow" }, { field = "warnGlowType", value = "pixel" } } },
        warnGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow line length (0 = auto)",
            dep = { { field = "warnGlow" }, { field = "warnGlowType", value = "pixel" } } },
        warnGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow particles", dep = { { field = "warnGlow" }, { field = "warnGlowType", value = "autocast" } } },
        warnGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow size", dep = { { field = "warnGlow" }, { field = "warnGlowType", value = "autocast" } } },
        warnGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow intensity", dep = { field = "warnGlow" } },
        warnGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow X offset", dep = { field = "warnGlow" } },
        warnGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow Y offset", dep = { field = "warnGlow" } },
        warnGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow move X", dep = { field = "warnGlow" } },
        warnGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow move Y", dep = { field = "warnGlow" } },
        warnGlowCombatOnly = { d = false, t = "bool", kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow only in combat", dep = { field = "warnGlow" } },
        warnGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, kinds = NA,
            classOnly = Schema.WARN_CLASSES, label = "Warning glow strata", dep = { field = "warnGlow" } },
        warnGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = NA, classOnly = Schema.WARN_CLASSES,
            label = "Warning glow frame level", dep = { field = "warnGlow" } },
        -- Glows while the spell's toggle is on, as the action bar flashes it:
        -- Shoot or Auto Shot repeating, melee Attack swinging. White keeps the
        -- red flash's own red.
        toggleGlow = { d = false, t = "bool", kinds = SP, showIf = ToggleShows, label = "Glow while toggled on",
            desc = "Glows while Shoot, Auto Shot or melee Attack is on, as your action bar flashes it." },
        toggleGlowType = { d = "redflash", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP,
            showIf = ToggleShows, label = "Toggle glow style", dep = { field = "toggleGlow" } },
        toggleGlowColor = { d = { 1, 1, 1, 1 }, t = "color", kinds = SP, showIf = ToggleShows,
            label = "Toggle glow color", dep = { field = "toggleGlow" } },
        toggleGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow speed",
            dep = { { field = "toggleGlow" }, { field = "toggleGlowType", anyOf = GLOW_SPEED_STYLES } } },
        toggleGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow lines", dep = { { field = "toggleGlow" }, { field = "toggleGlowType", value = "pixel" } } },
        toggleGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow thickness", dep = { { field = "toggleGlow" }, { field = "toggleGlowType", value = "pixel" } } },
        toggleGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow line length (0 = auto)",
            dep = { { field = "toggleGlow" }, { field = "toggleGlowType", value = "pixel" } } },
        toggleGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow particles", dep = { { field = "toggleGlow" }, { field = "toggleGlowType", value = "autocast" } } },
        toggleGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow size", dep = { { field = "toggleGlow" }, { field = "toggleGlowType", value = "autocast" } } },
        toggleGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow intensity", dep = { field = "toggleGlow" } },
        toggleGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow X offset", dep = { field = "toggleGlow" } },
        toggleGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow Y offset", dep = { field = "toggleGlow" } },
        toggleGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow move X", dep = { field = "toggleGlow" } },
        toggleGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow move Y", dep = { field = "toggleGlow" } },
        toggleGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" },
            kinds = SP, showIf = ToggleShows, label = "Toggle glow strata", dep = { field = "toggleGlow" } },
        toggleGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = SP, showIf = ToggleShows,
            label = "Toggle glow frame level", dep = { field = "toggleGlow" } },
        -- Toggled on as a state of its own: Shoot, Auto Shot or Attack on.
        toggleAlphaEnabled = { d = false, t = "bool", kinds = SP, showIf = ToggleShows, label = "Toggled-on alpha" },
        toggleAlpha = { d = 1, t = "num", min = 0, max = 1, kinds = SP, showIf = ToggleShows, label = "Toggled-on alpha value",
            dep = { field = "toggleAlphaEnabled" } },
        toggleDesaturate = { d = false, t = "bool", kinds = SP, showIf = ToggleShows, label = "Desaturate while toggled on" },
        toggleTintEnabled = { d = false, t = "bool", kinds = SP, showIf = ToggleShows, label = "Toggled-on tint" },
        toggleTintColor = { d = { 1, 0.35, 0.35, 1 }, t = "color", kinds = SP, showIf = ToggleShows,
            label = "Toggled-on tint color", dep = { field = "toggleTintEnabled" } },
        rangeTint = { d = false, t = "bool", kinds = SP, label = "Out-of-range tint" },
        rangeTintColor = { d = { 0.85, 0.2, 0.2, 1 }, t = "color", kinds = SP, label = "Out-of-range color", dep = { field = "rangeTint" } },
        -- Out of range as a full state: its own alpha (full by default, so a
        -- ready spell still never dims for range alone), grey out and glow.
        rangeAlpha = { d = 1, t = "num", min = 0, max = 1, kinds = SP, label = "Out-of-range alpha" },
        rangeDesaturate = { d = false, t = "bool", kinds = SP, label = "Desaturate while out of range" },
        rangeGlow = { d = false, t = "bool", kinds = SP, label = "Glow while out of range" },
        rangeGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP,
            label = "Out-of-range glow style", dep = { field = "rangeGlow" } },
        rangeGlowColor = { d = { 0.85, 0.2, 0.2, 1 }, t = "color", kinds = SP, label = "Out-of-range glow color",
            dep = { field = "rangeGlow" } },
        rangeGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = SP, label = "Out-of-range glow speed",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", anyOf = GLOW_SPEED_STYLES } } },
        rangeGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = SP, label = "Out-of-range glow lines",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", value = "pixel" } } },
        rangeGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = SP, label = "Out-of-range glow thickness",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", value = "pixel" } } },
        rangeGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = SP,
            label = "Out-of-range glow line length (0 = auto)",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", value = "pixel" } } },
        rangeGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = SP, label = "Out-of-range glow particles",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", value = "autocast" } } },
        rangeGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = SP, label = "Out-of-range glow size",
            dep = { { field = "rangeGlow" }, { field = "rangeGlowType", value = "autocast" } } },
        rangeGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = SP, label = "Out-of-range glow intensity",
            dep = { field = "rangeGlow" } },
        rangeGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Out-of-range glow X offset",
            dep = { field = "rangeGlow" } },
        rangeGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Out-of-range glow Y offset",
            dep = { field = "rangeGlow" } },
        rangeGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Out-of-range glow move X",
            dep = { field = "rangeGlow" } },
        rangeGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, label = "Out-of-range glow move Y",
            dep = { field = "rangeGlow" } },
        rangeGlowCombatOnly = { d = false, t = "bool", kinds = SP, label = "Out-of-range glow only in combat",
            dep = { field = "rangeGlow" } },
        rangeGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" },
            kinds = SP, label = "Out-of-range glow strata", dep = { field = "rangeGlow" } },
        rangeGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = SP, label = "Out-of-range glow frame level",
            dep = { field = "rangeGlow" } },
        -- Recharging: a charge spell with a charge left and another on its way.
        -- Off, it looks as On cooldown (or Ready with Wait for no charges).
        rechargeAlphaEnabled = { d = false, t = "bool", kinds = SP, showIf = ChargeShows, label = "Recharging alpha" },
        rechargeAlpha = { d = 1, t = "num", min = 0, max = 1, kinds = SP, showIf = ChargeShows,
            label = "Recharging alpha value", dep = { field = "rechargeAlphaEnabled" } },
        rechargeDesaturate = { d = false, t = "bool", kinds = SP, showIf = ChargeShows, label = "Desaturate while recharging" },
        rechargeTintEnabled = { d = false, t = "bool", kinds = SP, showIf = ChargeShows, label = "Recharging tint" },
        rechargeTintColor = { d = { 1, 0.85, 0.4, 1 }, t = "color", kinds = SP, showIf = ChargeShows,
            label = "Recharging tint color", dep = { field = "rechargeTintEnabled" } },
        rechargeGlow = { d = false, t = "bool", kinds = SP, showIf = ChargeShows, label = "Glow while recharging" },
        rechargeGlowType = { d = "button", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = SP,
            showIf = ChargeShows, label = "Recharging glow style", dep = { field = "rechargeGlow" } },
        rechargeGlowColor = { d = { 1, 0.85, 0.4, 1 }, t = "color", kinds = SP, showIf = ChargeShows,
            label = "Recharging glow color", dep = { field = "rechargeGlow" } },
        rechargeGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow speed",
            dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", anyOf = GLOW_SPEED_STYLES } } },
        rechargeGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow lines", dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", value = "pixel" } } },
        rechargeGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow thickness",
            dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", value = "pixel" } } },
        rechargeGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow line length (0 = auto)",
            dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", value = "pixel" } } },
        rechargeGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow particles",
            dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", value = "autocast" } } },
        rechargeGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow size",
            dep = { { field = "rechargeGlow" }, { field = "rechargeGlowType", value = "autocast" } } },
        rechargeGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow intensity", dep = { field = "rechargeGlow" } },
        rechargeGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow X offset", dep = { field = "rechargeGlow" } },
        rechargeGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow Y offset", dep = { field = "rechargeGlow" } },
        rechargeGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow move X", dep = { field = "rechargeGlow" } },
        rechargeGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow move Y", dep = { field = "rechargeGlow" } },
        rechargeGlowCombatOnly = { d = false, t = "bool", kinds = SP, showIf = ChargeShows,
            label = "Recharging glow only in combat", dep = { field = "rechargeGlow" } },
        rechargeGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" },
            kinds = SP, showIf = ChargeShows, label = "Recharging glow strata", dep = { field = "rechargeGlow" } },
        rechargeGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, kinds = SP, showIf = ChargeShows,
            label = "Recharging glow frame level", dep = { field = "rechargeGlow" } },
        -- A totem's Out of range look: while the totem is out and its buff is
        -- not on you (Drivers\AD_TotemRange.lua). The game draws it, so it
        -- holds in combat.
        totemRangeDesaturate = { d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Grey out while out of totem range" },
        totemRangeTint = { d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Out of totem range tint" },
        totemRangeTintColor = { d = { 0.85, 0.2, 0.2, 1 }, t = "color", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Out of totem range tint color", dep = { field = "totemRangeTint" } },
        totemRangeGlow = { d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Glow while out of totem range" },
        totemRangeGlowType = { d = "flash", t = "enum", values = GLOW_STYLES, labels = GLOW_STYLE_LABELS, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow style", dep = { field = "totemRangeGlow" } },
        totemRangeGlowColor = { d = { 1, 0.3, 0.2, 1 }, t = "color", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Out of range glow color", dep = { field = "totemRangeGlow" } },
        totemRangeGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow speed",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", anyOf = GLOW_SPEED_STYLES } } },
        totemRangeGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow lines",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", value = "pixel" } } },
        totemRangeGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow thickness",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", value = "pixel" } } },
        totemRangeGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow line length (0 = auto)",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", value = "pixel" } } },
        totemRangeGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow particles",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", value = "autocast" } } },
        totemRangeGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow size",
            dep = { { field = "totemRangeGlow" }, { field = "totemRangeGlowType", value = "autocast" } } },
        totemRangeGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow intensity", dep = { field = "totemRangeGlow" } },
        totemRangeGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow X offset", dep = { field = "totemRangeGlow" } },
        totemRangeGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow Y offset", dep = { field = "totemRangeGlow" } },
        totemRangeGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow move X", dep = { field = "totemRangeGlow" } },
        totemRangeGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, kinds = TOT,
            showIf = Schema.TotemBySpell, label = "Out of range glow move Y", dep = { field = "totemRangeGlow" } },
    } },
    -- Up to three custom texts per icon, each shown or hidden by state.
    label = { push = true, inherit = true, fields = {
        labelText = { inherit = false, d = "", t = "text", label = "Custom text" },
        -- Custom text 1's font; texts 2 and 3 use it until they pick their own.
        labelFont = { d = "", t = "text", font = true, label = "Custom text font",
            dep = { field = "labelText", nonempty = true } },
        labelFont2 = { d = "", t = "text", font = true, label = "Custom text 2 font",
            dep = { field = "labelText2", nonempty = true } },
        labelFont3 = { d = "", t = "text", font = true, label = "Custom text 3 font",
            dep = { field = "labelText3", nonempty = true } },
        -- Each text may ride another frame (Schema.PIN_TO); its offsets then
        -- count from that frame's anchor point.
        labelPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Custom text pinned to", dep = { field = "labelText", nonempty = true } },
        labelPinTarget = { inherit = false, d = "", t = "text", label = "Custom text pin target",
            dep = { field = "labelText", nonempty = true } },
        labelPinTo2 = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Custom text 2 pinned to", dep = { field = "labelText2", nonempty = true } },
        labelPinTarget2 = { inherit = false, d = "", t = "text", label = "Custom text 2 pin target",
            dep = { field = "labelText2", nonempty = true } },
        labelPinTo3 = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Custom text 3 pinned to", dep = { field = "labelText3", nonempty = true } },
        labelPinTarget3 = { inherit = false, d = "", t = "text", label = "Custom text 3 pin target",
            dep = { field = "labelText3", nonempty = true } },
        labelSize = { d = 12, t = "int", min = 6, max = 32, label = "Custom text size", dep = { field = "labelText", nonempty = true } },
        labelColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Custom text color", dep = { field = "labelText", nonempty = true } },
        labelAnchor = { d = "CENTER", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Custom text anchor", dep = { field = "labelText", nonempty = true } },
        labelX = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text X", dep = { field = "labelText", nonempty = true } },
        labelY = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text Y", dep = { field = "labelText", nonempty = true } },
        -- The two-state kinds: one dropdown in the kind's own state words writes
        -- both (statePick, UI\AD_Options.lua); both on = always.
        labelShowReady = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text",
            statePick = "labelShowCooldown", rangePick = "labelShowRange", dep = { field = "labelText", nonempty = true } },
        labelShowCooldown = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text on cooldown",
            pickedBy = "labelShowReady", dep = { field = "labelText", nonempty = true } },
        -- A totem set to one totem: shown only while out of its range, in the
        -- Out of range look (Drivers\AD_TotemRange.lua); the same dropdown
        -- writes it (rangePick).
        labelShowRange = { inherit = false, d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Show custom text only while out of totem range", pickedBy = "labelShowReady",
            dep = { field = "labelText", nonempty = true } },
        -- Drawn on the engine button, so it holds in combat. One dropdown writes both (showPick).
        labelActiveOnly = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text",
            showPick = "labelMissingOnly", dep = { field = "labelText", nonempty = true } },
        labelMissingOnly = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text only while the aura is missing",
            pickedBy = "labelActiveOnly", dep = { field = "labelText", nonempty = true } },
        labelText2 = { inherit = false, d = "", t = "text", label = "Custom text 2" },
        labelSize2 = { d = 12, t = "int", min = 6, max = 32, label = "Custom text 2 size", dep = { field = "labelText2", nonempty = true } },
        labelColor2 = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Custom text 2 color", dep = { field = "labelText2", nonempty = true } },
        labelAnchor2 = { d = "TOP", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Custom text 2 anchor", dep = { field = "labelText2", nonempty = true } },
        labelX2 = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text 2 X", dep = { field = "labelText2", nonempty = true } },
        labelY2 = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text 2 Y", dep = { field = "labelText2", nonempty = true } },
        labelShowReady2 = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text 2",
            statePick = "labelShowCooldown2", rangePick = "labelShowRange2", dep = { field = "labelText2", nonempty = true } },
        labelShowCooldown2 = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text 2 on cooldown",
            pickedBy = "labelShowReady2", dep = { field = "labelText2", nonempty = true } },
        labelShowRange2 = { inherit = false, d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Show custom text 2 only while out of totem range", pickedBy = "labelShowReady2",
            dep = { field = "labelText2", nonempty = true } },
        labelActiveOnly2 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text 2",
            showPick = "labelMissingOnly2", dep = { field = "labelText2", nonempty = true } },
        labelMissingOnly2 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text 2 only while the aura is missing",
            pickedBy = "labelActiveOnly2", dep = { field = "labelText2", nonempty = true } },
        labelText3 = { inherit = false, d = "", t = "text", label = "Custom text 3" },
        labelSize3 = { d = 12, t = "int", min = 6, max = 32, label = "Custom text 3 size", dep = { field = "labelText3", nonempty = true } },
        labelColor3 = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Custom text 3 color", dep = { field = "labelText3", nonempty = true } },
        labelAnchor3 = { d = "BOTTOM", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Custom text 3 anchor", dep = { field = "labelText3", nonempty = true } },
        labelX3 = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text 3 X", dep = { field = "labelText3", nonempty = true } },
        labelY3 = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Custom text 3 Y", dep = { field = "labelText3", nonempty = true } },
        labelShowReady3 = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text 3",
            statePick = "labelShowCooldown3", rangePick = "labelShowRange3", dep = { field = "labelText3", nonempty = true } },
        labelShowCooldown3 = { inherit = false, d = true, t = "bool", kinds = TWO, label = "Show custom text 3 on cooldown",
            pickedBy = "labelShowReady3", dep = { field = "labelText3", nonempty = true } },
        labelShowRange3 = { inherit = false, d = false, t = "bool", kinds = TOT, showIf = Schema.TotemBySpell,
            label = "Show custom text 3 only while out of totem range", pickedBy = "labelShowReady3",
            dep = { field = "labelText3", nonempty = true } },
        labelActiveOnly3 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text 3",
            showPick = "labelMissingOnly3", dep = { field = "labelText3", nonempty = true } },
        labelMissingOnly3 = { inherit = false, d = false, t = "bool", kinds = AU, label = "Show custom text 3 only while the aura is missing",
            pickedBy = "labelActiveOnly3", dep = { field = "labelText3", nonempty = true } },
    } },
    -- Transition sounds. A sound cannot be unplayed, so the driver fires only
    -- on verified transitions. Each trigger is a toggle plus a t = "sound"
    -- field: a name from NS.Sounds, or "" for none.
    alerts = { push = true, kinds = { spell = true, item = true, trinket = true, timer = true, enchant = true,
        special = true, aura = true }, fields = {
        soundChannel = { d = "Master", t = "enum", values = { "Master", "SFX", "Music", "Ambience", "Dialog" },
            labels = { Master = "Master (ignores the other sliders)", SFX = "Sound Effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" },
            label = "Sound channel" },
        readySoundEnabled = { d = false, t = "bool", kinds = USE_CD, label = "Play a sound when ready" },
        readySound = { d = "", t = "sound", kinds = USE_CD, label = "Ready sound", dep = { field = "readySoundEnabled" } },
        -- From shadow edges, never secret numbers: cooldown start, recharge
        -- start, and a charge returning while the spell stays castable.
        cooldownSoundEnabled = { d = false, t = "bool", kinds = USE_CD, label = "Play a sound when the cooldown starts" },
        cooldownSound = { d = "", t = "sound", kinds = USE_CD, label = "Cooldown-start sound", dep = { field = "cooldownSoundEnabled" } },
        -- A special icon's moments: the tracker's proc edge (NS.Special.Proc),
        -- and the draw its chance reads as 100%.
        procSoundEnabled = { d = false, t = "bool", kinds = SPC, label = "Play a sound on proc" },
        procSound = { d = "", t = "sound", kinds = SPC, label = "Proc sound", dep = { field = "procSoundEnabled" } },
        sureSoundEnabled = { d = false, t = "bool", kinds = SPC, label = "Play a sound when the next draw is guaranteed" },
        sureSound = { d = "", t = "sound", kinds = SPC, label = "Guaranteed sound", dep = { field = "sureSoundEnabled" } },
        rechargeSoundEnabled = { d = false, t = "bool", kinds = SP, label = "Play a sound when recharging starts" },
        rechargeSound = { d = "", t = "sound", kinds = SP, label = "Recharge-start sound", dep = { field = "rechargeSoundEnabled" } },
        chargeGainedSoundEnabled = { d = false, t = "bool", kinds = SP, label = "Play a sound when a charge returns" },
        chargeGainedSound = { d = "", t = "sound", kinds = SP, label = "Charge-gained sound", dep = { field = "chargeGainedSoundEnabled" } },
        -- The moment it can be pressed: usable (IsSpellUsable, plain) and off
        -- its real cooldown. A reactive spell (Mongoose Bite) rings on the dodge.
        usableSoundEnabled = { d = false, t = "bool", kinds = SP, label = "Play a sound when usable" },
        usableSound = { d = "", t = "sound", kinds = SP, label = "Usable sound", dep = { field = "usableSoundEnabled" } },
        -- An aura icon's moments, played by the game (Drivers\AD_AuraSounds.lua):
        -- in combat too, for any caster's copy; `files`: a sound file, no kit.
        auraGainSoundEnabled = { d = false, t = "bool", kinds = { aura = true }, label = "Play a sound when the aura appears" },
        auraGainSound = { d = "", t = "sound", files = true, kinds = { aura = true }, label = "Appear sound",
            dep = { field = "auraGainSoundEnabled" } },
        auraStackSoundEnabled = { d = false, t = "bool", kinds = { aura = true }, label = "Play a sound when it gains a stack" },
        auraStackSound = { d = "", t = "sound", files = true, kinds = { aura = true }, label = "Stack sound",
            dep = { field = "auraStackSoundEnabled" } },
        auraLostSoundEnabled = { d = false, t = "bool", kinds = { aura = true }, label = "Play a sound when the aura drops" },
        auraLostSound = { d = "", t = "sound", files = true, kinds = { aura = true }, label = "Drop sound",
            dep = { field = "auraLostSoundEnabled" } },
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
        keybindColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Keybind color", dep = { field = "keybindEnabled" } },
        keybindAnchor = { d = "TOPLEFT", t = "enum",
            values = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
            label = "Keybind anchor", dep = { field = "keybindEnabled" } },
        keybindX = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Keybind X", dep = { field = "keybindEnabled" } },
        keybindY = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Keybind Y", dep = { field = "keybindEnabled" } },
        keybindPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Keybind pinned to", dep = { field = "keybindEnabled" } },
        keybindPinTarget = { inherit = false, d = "", t = "text", label = "Keybind pin target",
            dep = { field = "keybindEnabled" } },
    } },
    -- Things that run out: an item's bag count, the quiver. Counts are compared
    -- only when plain; a secret count keeps the last known state.
    outOfStock = { push = true, inherit = true, kinds = { item = true, trinket = true, ammo = true }, fields = {
        outDesaturate = { d = true, t = "bool", kinds = { item = true, ammo = true }, label = "Desaturate when out of stock" },
        outAlphaEnabled = { d = false, t = "bool", kinds = { item = true, ammo = true }, label = "Out-of-stock alpha" },
        outAlpha = { d = 0.4, t = "num", min = 0, max = 1, kinds = { item = true, ammo = true }, label = "Out-of-stock alpha value", dep = { field = "outAlphaEnabled" } },
        -- Show: Always, while in stock (hidden while missing) or only when out
        -- (its partner). An item is missing when its guarded bag count is
        -- empty, a trinket when nothing is equipped in its slot.
        hideWhenMissing = { d = false, t = "bool", label = "Show", showPick = "showOnlyWhenOut",
            pickWords = function(rec)
                if rec and rec.kind == "trinket" then return { up = "While equipped" } end
                return { up = "While in stock", missing = "Only when out of stock" }
            end },
        showOnlyWhenOut = { d = false, t = "bool", kinds = { item = true, ammo = true },
            label = "Only when out of stock", pickedBy = "hideWhenMissing" },
    } },
    -- A trinket slot that shows only on-use trinkets: a passive one (no use
    -- spell) hides and gives up its cell in a dynamic group, as a missing one.
    trinket = { push = true, kinds = { trinket = true }, fields = {
        onlyOnUse = { d = false, t = "bool", label = "Only on-use trinkets (hide passive ones)" },
    } },
    -- A group buff (Drivers\AD_DriverGroupBuff.lua): counted between pulls, secret in combat.
    groupBuff = { push = true, kinds = { groupbuff = true }, fields = {
        -- a buff the whole group needs, or one kept on one member
        remind = { d = "lacks", t = "enum", values = { "lacks", "nobody" },
            labels = { lacks = "Anyone lacks it", nobody = "Nobody has it" }, label = "Remind while",
            desc = "Anyone lacks it: a buff the whole group needs. Nobody has it: a buff you keep on one member, such as Beacon of Light, Earth Shield, Source of Magic or a Soulstone." },
        combatShow = { d = false, t = "bool", label = "Show in combat",
            desc = "In combat the game hides buffs, so the count stops; this shows the icon, without a count, while it reminds, drawn by the game." },
        -- the count text's words: have / total, how many lack it, or have
        countShows = { d = "haveTotal", t = "enum", values = { "haveTotal", "missing", "have" },
            labels = { haveTotal = "Have / total (3/5)", missing = "Missing (2)", have = "Have (3)" },
            label = "Count shows", dep = { section = "text", field = "stackText" } },
    } },
    -- A stance icon (Drivers\AD_DriverStance.lua): the stance you are in, or
    -- one stance (rec.driver.spellID) lit while you are in it. Per icon.
    stance = { kinds = { stance = true }, fields = {
        shows = { d = "current", t = "enum", values = { "current", "one" },
            labels = { current = "Your current stance", one = "One stance" }, label = "Shows",
            desc = "Your current stance: the stance, form or aura you are in, greyed while in none. One stance: that one, lit while you are in it." },
    } },
    -- A totem's pulse: a bar under the art that refills at every pulse,
    -- counted from when the totem went down (NS.DriverTotem).
    pulse = { push = true, inherit = true, kinds = { totem = true }, fields = {
        pulseShow = { d = false, t = "bool", label = "Show the pulse timer" },
        -- 0 takes the totem's own pulse, for the totems that pulse.
        pulseInterval = { d = 0, t = "num", min = 0, max = 10, step = 0.5, fmt = "%.1f",
            label = "Seconds between pulses (0 = the totem's own)", dep = { field = "pulseShow" } },
        pulseColor = { d = { 1, 0.82, 0.2, 1 }, t = "color", alpha = true, label = "Pulse bar color",
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
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "icon", "layout", "frame", "mouse" },
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
        gcdSwipeColor = { d = { 0, 0, 0, 0.5 }, t = "color", alpha = true, kinds = { spell = true },
            label = "GCD swipe color", dep = { field = "gcdSwipe", anyOf = GCD_SWIPE_DRAWN } },
        -- a wand shot exists on WoW Forever only
        wandSwipe = { foreverOnly = true, d = "hidden", t = "enum", values = GCD_LOOKS, labels = GCD_LOOK_LABELS,
            kinds = { spell = true }, classOnly = WAND_CLASSES, label = "Wand GCD" },
        wandSwipeColor = { foreverOnly = true, d = { 0, 0, 0, 0.5 }, t = "color", alpha = true, kinds = { spell = true },
            classOnly = WAND_CLASSES, label = "Wand swipe color",
            dep = { field = "wandSwipe", anyOf = GCD_SWIPE_DRAWN } },
        -- While a charge spell still has a charge (recharging), these two hold
        -- back the dark fill or the edge until every charge is spent.
        swipeWaitForNoCharges = { d = false, t = "bool", kinds = { spell = true }, label = "Swipe only when no charges", dep = { field = "showSwipe" } },
        showEdge  = { d = true,  t = "bool", label = "Swipe edge" },
        edgeWaitForNoCharges = { d = false, t = "bool", kinds = { spell = true }, label = "Edge only when no charges", dep = { field = "showEdge" } },
        showBling = { d = true,  t = "bool", label = "Finish flash" },
        reverse   = { d = false, t = "bool", label = "Reverse swipe", dep = { field = "showSwipe" } },
        swipeColor = { d = { 0, 0, 0, 0.8 }, t = "color", alpha = true, label = "Swipe color", dep = { field = "showSwipe" } },
        -- 1.8 matches the Cooldown Manager's edge. CooldownFrameTemplate's own
        -- 1.0 draws a stubby line that stops short of the icon corner.
        edgeScale = { d = 1.8, t = "num", min = 0.1, max = 3, label = "Edge scale", dep = { field = "showEdge" } },
        edgeColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Edge color", dep = { field = "showEdge" } },
        swipeInset = { d = 0, t = "int", min = -20, max = 40, label = "Swipe inset",
            dep = { { field = "showSwipe" }, { field = "separateInsets", value = false } } },
        separateInsets = { d = false, t = "bool", label = "Separate inset W/H", dep = { field = "showSwipe" } },
        swipeInsetX = { adv = "inset", d = 0, t = "int", min = -20, max = 40, label = "Swipe inset W",
            dep = { { field = "showSwipe" }, { field = "separateInsets" } } },
        swipeInsetY = { adv = "inset", d = 0, t = "int", min = -20, max = 40, label = "Swipe inset H",
            dep = { { field = "showSwipe" }, { field = "separateInsets" } } },
    } },
    auraMissing = { push = true, inherit = true, kinds = AU, fields = {
        -- dyn: a Dynamic aura group packs what shows, so there it starts off,
        -- unless the icon is set up for its missing state (Store.MissingSetUp)
        showWhileMissing = { d = true, dyn = false, t = "bool", label = "Show while missing",
            dynUnless = function(rec) return NS.Store.MissingSetUp(rec) end },
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
        -- The twin of auraMissing.missingPreserveText: a dimmed (not hidden)
        -- active look keeps its texts bright. A spell icon's aura phase follows
        -- the spell's own states.preserveDurationText instead.
        activePreserveText = { d = true, t = "bool", kinds = AU, label = "Keep texts bright while active" },
        activeDesaturate = { d = false, t = "bool", label = "Desaturate while active" },
        activeTintEnabled = { d = false, t = "bool", label = "Active tint" },
        activeTintColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Active tint color", dep = { field = "activeTintEnabled" } },
        -- Engine-driven like the glow's time gate (DriverAura.TimeGateFrac):
        -- not in a Dynamic group, nor on a "you, then your target" icon.
        activeTimeOnly = { d = false, t = "bool", kinds = AU, showIf = TimeGateShows,
            label = "Show only when little time is left",
            desc = "While the aura is up, the icon stays hidden until little time is left. Works in combat." },
        activeTimeUnit = { d = "pct", t = "enum", values = { "pct", "sec" }, kinds = AU, showIf = TimeGateShows,
            labels = { pct = "Percent of the aura", sec = "Seconds" },
            label = "Time left in", dep = { field = "activeTimeOnly" } },
        activeTimePct = { d = 30, t = "int", min = 1, max = 99, kinds = AU, showIf = TimeGateShows,
            label = "Show under this % left",
            dep = { { field = "activeTimeOnly" }, { field = "activeTimeUnit", value = "pct" } } },
        activeTimeSec = { d = 3, t = "num", min = 0.5, max = 120, step = 0.5, fmt = "%g", kinds = AU,
            showIf = TimeGateShows, label = "Show under this many seconds left",
            dep = { { field = "activeTimeOnly" }, { field = "activeTimeUnit", value = "sec" } } },
        activeTimeLen = { d = 0, t = "int", min = 0, max = 600, kinds = AU, showIf = TimeGateShows,
            label = "The aura lasts (seconds)",
            desc = "The aura's full length, which the game keeps from addons: seconds need it, percent does not. 0 = not set: always shown.",
            dep = { { field = "activeTimeOnly" }, { field = "activeTimeUnit", value = "sec" } } },
        activeGlow = { d = false, t = "bool", label = "Glow while active" },
        -- The gates ride a lane: the icon's own (DriverAura) or its Dynamic
        -- row's (AD_DriverAuraRows). The pick is one of the icon's spells, its
        -- ranks by name; 0 = any of them.
        activeGlowFor = { inherit = false, d = 0, t = "id", auraSpellPick = true,
            kinds = AU, label = "Glow for",
            showIf = function(rec)
                local DA = NS.DriverAura
                return DA ~= nil and DA.GlowGateOK(rec) and #DA.GlowSpellGroups(rec.driver) > 1
            end,
            desc = "Any of the icon's spells, or only one of them (its ranks together). Works in combat.",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", notValue = "missing" },
                { field = "activeGlowWhen", notValue = "both" } } },
        activeGlowCombatOnly = { d = false, t = "bool", kinds = AU,
            label = "Glow only in combat",
            showIf = function(rec)
                local DA = NS.DriverAura
                return DA ~= nil and DA.GlowGateOK(rec)
            end,
            desc = "The glow waits for combat; out of combat the icon shows without it.",
            dep = { field = "activeGlow" } },
        -- Engine-driven, no reads. Forever opens no pandemic window: "pandemic" draws the last 30%.
        activeGlowWhen = { d = "always", t = "enum", values = { "always", "pandemic", "time", "missing", "both" },
            labels = { always = "While the aura is up", pandemic = "In the last 30%",
                time = "When little time is left", missing = "While the aura is missing", both = "Always" },
            valueIf = { pandemic = function() return false end,
                missing = function(r)
                    local DA = NS.DriverAura
                    return DA ~= nil and DA.MissingGlowOK ~= nil and DA.MissingGlowOK(r)
                end,
                both = function(r)
                    local DA = NS.DriverAura
                    return DA ~= nil and DA.HolderGlowOK ~= nil and DA.HolderGlowOK(r)
                end },
            desc = "While the aura is up, only once little time is left, only while the aura is missing, or always. Works in combat.",
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
        activeGlowSpeed = { adv = "glow", d = 0.25, t = "num", min = 0.05, max = 1, label = "Active glow speed",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", anyOf = GLOW_SPEED_STYLES } } },
        activeGlowLines = { adv = "glow", d = 8, t = "int", min = 1, max = 16, label = "Active glow lines",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        activeGlowThickness = { adv = "glow", d = 2, t = "int", min = 1, max = 20, label = "Active glow thickness",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        -- On the live button this picks one of the dash texture's 8 bands.
        activeGlowLength = { adv = "glow", d = 0, t = "int", min = 0, max = 40, label = "Active glow line length (0 = auto)",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "pixel" } } },
        activeGlowParticles = { adv = "glow", d = 4, t = "int", min = 1, max = 16, label = "Active glow particles",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "autocast" } } },
        activeGlowIntensity = { adv = "glow", d = 1, t = "num", min = 0.1, max = 1, label = "Active glow intensity",
            dep = { field = "activeGlow" } },
        activeGlowScale = { adv = "glow", d = 1, t = "num", min = 0.5, max = 2, label = "Active glow size",
            dep = { { field = "activeGlow" }, { field = "activeGlowType", value = "autocast" } } },
        activeGlowXOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, label = "Active glow X offset",
            dep = { field = "activeGlow" } },
        activeGlowYOffset = { adv = "glow", d = 0, t = "int", min = -20, max = 20, label = "Active glow Y offset",
            dep = { field = "activeGlow" } },
        activeGlowMoveX = { adv = "glow", d = 0, t = "int", min = -20, max = 20, label = "Active glow move X",
            dep = { field = "activeGlow" } },
        activeGlowMoveY = { adv = "glow", d = 0, t = "int", min = -20, max = 20, label = "Active glow move Y",
            dep = { field = "activeGlow" } },
        -- a Missing glow keeps its place on the aura icon's ladder: these two
        -- do not apply to it
        activeGlowStrata = { adv = "glow", d = "inherit", t = "enum", values = { "inherit", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Active glow strata",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", notValue = "missing" } } },
        activeGlowLevel = { adv = "glow", d = 7, t = "int", min = 1, max = 30, label = "Active glow frame level",
            dep = { { field = "activeGlow" }, { field = "activeGlowWhen", notValue = "missing" } } },
    } },
    -- The engine button's swipe is our own Cooldown widget, so its look is
    -- plain writes; spell icons with the aura overlay use it too.
    auraSwipe = { push = true, inherit = true, kinds = AA, fields = {
        swipeShow = { d = true, t = "bool", label = "Aura swipe" },
        -- Colour and direction default per kind (two fields, one label): aura
        -- icons get the reversed dark swipe, a spell's aura phase the Cooldown
        -- Manager's unreversed gold (CooldownViewerConstants.ITEM_AURA_COLOR).
        swipeColor = { d = { 0, 0, 0, 0.8 }, t = "color", alpha = true, kinds = AU, label = "Aura swipe color", dep = { field = "swipeShow" } },
        overlaySwipeColor = { d = { 1, 0.95, 0.57, 0.7 }, t = "color", alpha = true, kinds = SP, label = "Aura swipe color",
            dep = { field = "swipeShow" } },
        swipeReverse = { d = true, t = "bool", kinds = AU, label = "Reverse aura swipe", dep = { field = "swipeShow" } },
        overlaySwipeReverse = { d = false, t = "bool", kinds = SP, label = "Reverse aura swipe",
            dep = { field = "swipeShow" } },
        swipeEdge = { d = false, t = "bool", label = "Aura swipe edge" },
        -- As on the cooldown swipe: 1.8 is the Cooldown Manager's edge length.
        edgeColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Aura edge color", dep = { field = "swipeEdge" } },
        edgeScale = { d = 1.8, t = "num", min = 0.1, max = 3, label = "Aura edge scale", dep = { field = "swipeEdge" } },
        swipeBling = { d = false, t = "bool", label = "Aura finish flash" },
    } },
    text = { push = true, inherit = true, fields = {
        durationText = { kinds = DUR, d = true, t = "bool", label = "Duration text" },
        -- "global" follows Settings > Timers.
        durationRounding = { kinds = DUR, d = "global", t = "enum", values = { "global", "up", "down" },
            labels = { global = "Same as Settings", up = "Round up", down = "Round down" },
            label = "Round timer numbers", dep = { field = "durationText" } },
        durationSize = { kinds = DUR, d = 14, t = "int", min = 6, max = 32, label = "Duration text size", dep = { field = "durationText" } },
        durationColor = { kinds = DUR, d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Duration text color", dep = { field = "durationText" } },
        -- A baked NumericRuleFormatter renders the countdown from the real
        -- remaining time, so it works on secret durations with no ticker. M:SS
        -- ("1:30") from 60 s up to this many seconds, "12 m" above; 0 = off.
        durationAbbrev = { kinds = DUR, d = 600, t = "enum", values = ABBREV_VALUES, labels = ABBREV_LABELS,
            label = "Minutes and seconds (1:30)", dep = { field = "durationText" } },
        durationShadow = { kinds = DUR, adv = "text", d = false, t = "bool", label = "Duration text shadow", dep = { field = "durationText" } },
        durationDecimals = { kinds = DUR, d = false, t = "bool", label = "Decimal seconds", dep = { field = "durationText" } },
        durationDecimalThreshold = { kinds = DUR, d = 10, t = "int", min = 2, max = 60, label = "Decimals under (seconds)",
            dep = { { field = "durationText" }, { field = "durationDecimals" } } },
        durationOutline = { kinds = DUR, adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" },
            label = "Duration text outline", dep = { field = "durationText" } },
        durationFont = { kinds = DUR, d = "", t = "text", font = true, label = "Duration text font", dep = { field = "durationText" } },
        durationAnchor = { kinds = DUR, d = "CENTER", t = "enum",
            values = { "CENTER", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            label = "Duration text anchor", dep = { field = "durationText" } },
        durationX = { kinds = DUR, adv = "text", d = 0, t = "int", min = -50, max = 50, label = "Duration text X", dep = { field = "durationText" } },
        durationY = { kinds = DUR, adv = "text", d = 0, t = "int", min = -50, max = 50, label = "Duration text Y", dep = { field = "durationText" } },
        -- Whether a charge is left comes from the shadow.
        hideDurWithCharges = { d = false, t = "bool", kinds = SP, label = "Hide duration while charges remain",
            dep = { field = "durationText" } },
        -- Bands bake into the countdown formatter as color escapes, so the
        -- engine colors the text from the real remaining time. A band colors
        -- values under its seconds (0 = off); above them, the plain color.
        -- durBandCount bands are in play: one when switched on, "+ Add band"
        -- for more (Schema.OLD_BANDS keeps the looks from before the count).
        durationColorBands = { kinds = DUR, d = false, t = "bool", label = "Color by remaining time",
            dep = { field = "durationText" } },
        durBand1Sec = { kinds = DUR, d = 5, t = "int", min = 0, max = 3600, label = "Band 1: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand1Color = { kinds = DUR, d = { 0.9, 0.15, 0.15, 1 }, t = "color", label = "Band 1 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        durBand2Sec = { kinds = DUR, d = 60, t = "int", min = 0, max = 3600, label = "Band 2: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" }, { field = "durBandCount", min = 2 } } },
        durBand2Color = { kinds = DUR, d = { 0.95, 0.75, 0.2, 1 }, t = "color", label = "Band 2 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" }, { field = "durBandCount", min = 2 } } },
        durBand3Sec = { kinds = DUR, d = 10, t = "int", min = 0, max = 3600, label = "Band 3: under (seconds)",
            dep = { { field = "durationText" }, { field = "durationColorBands" }, { field = "durBandCount", min = 3 } } },
        durBand3Color = { kinds = DUR, d = { 1, 0.5, 0.1, 1 }, t = "color", label = "Band 3 color",
            dep = { { field = "durationText" }, { field = "durationColorBands" }, { field = "durBandCount", min = 3 } } },
        durBandCount = { kinds = DUR, d = 1, t = "int", min = 1, max = 3, adds = "band", label = "Number of time bands",
            dep = { { field = "durationText" }, { field = "durationColorBands" } } },
        stackText = { d = true, t = "bool", kinds = STK, label = "Stack text" },
        stackSize = { d = 14, t = "int", min = 6, max = 32, kinds = STK, label = "Stack text size", dep = { field = "stackText" } },
        stackColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, kinds = STK, label = "Stack text color", dep = { field = "stackText" } },
        stackOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = STK, label = "Stack text outline", dep = { field = "stackText" } },
        stackFont = { d = "", t = "text", font = true, kinds = STK, label = "Stack text font", dep = { field = "stackText" } },
        stackAnchor = { d = "BOTTOMRIGHT", dk = { groupbuff = "CENTER" }, t = "enum",
            values = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM", "CENTER" },
            kinds = STK, label = "Stack text anchor", dep = { field = "stackText" } },
        stackX = { adv = "text", d = 0, t = "int", min = -200, max = 200, kinds = STK, label = "Stack text X", dep = { field = "stackText" } },
        stackY = { adv = "text", d = 0, t = "int", min = -200, max = 200, kinds = STK, label = "Stack text Y", dep = { field = "stackText" } },
        stackShadow = { adv = "text", d = false, t = "bool", kinds = STK, label = "Stack text shadow", dep = { field = "stackText" } },
        -- not an aura's: the game's button draws that count, and it cannot move in combat
        stackPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            kinds = { spell = true, item = true, timer = true, ammo = true, enchant = true, special = true, groupbuff = true },
            label = "Stack text pinned to", dep = { field = "stackText" } },
        stackPinTarget = { inherit = false, d = "", t = "text",
            kinds = { spell = true, item = true, timer = true, ammo = true, enchant = true, special = true, groupbuff = true },
            label = "Stack text pin target", dep = { field = "stackText" } },
        hideChargeAtZero = { d = false, t = "bool", kinds = SP, label = "Hide charge count at zero", dep = { field = "stackText" } },
        -- The engine prints an aura's count only above 1 unless it is handed a
        -- NumericRuleFormatter. The same formatter carries a color escape per
        -- breakpoint, so the count stays secret and the engine colors it.
        stackShowSingle = { d = false, t = "bool", kinds = AU, label = "Show count at 1 stack", dep = { field = "stackText" } },
        -- stkBandCount bands are in play: one when switched on (from 3
        -- stacks, green), "+ Add band" for more.
        stackColorBands = { inherit = false, d = false, t = "bool", kinds = AU, label = "Color by stack count", dep = { field = "stackText" } },
        stkBand1Min = { inherit = false, d = 3, t = "int", min = 1, max = 50, kinds = AU, label = "Band 1: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand1Color = { inherit = false, d = { 0.48, 0.85, 0.56, 1 }, t = "color", kinds = AU, label = "Band 1 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        stkBand2Min = { inherit = false, d = 6, t = "int", min = 1, max = 50, kinds = AU, label = "Band 2: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" }, { field = "stkBandCount", min = 2 } } },
        stkBand2Color = { inherit = false, d = { 0.95, 0.75, 0.2, 1 }, t = "color", kinds = AU, label = "Band 2 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" }, { field = "stkBandCount", min = 2 } } },
        stkBand3Min = { inherit = false, d = 10, t = "int", min = 1, max = 50, kinds = AU, label = "Band 3: from (stacks)",
            dep = { { field = "stackText" }, { field = "stackColorBands" }, { field = "stkBandCount", min = 3 } } },
        stkBand3Color = { inherit = false, d = { 0.9, 0.15, 0.15, 1 }, t = "color", kinds = AU, label = "Band 3 color",
            dep = { { field = "stackText" }, { field = "stackColorBands" }, { field = "stkBandCount", min = 3 } } },
        stkBandCount = { inherit = false, d = 1, t = "int", min = 1, max = 3, kinds = AU, adds = "band",
            label = "Number of stack bands", dep = { { field = "stackText" }, { field = "stackColorBands" } } },
        -- The equipped ammo count on a spell icon, styled apart from the stack
        -- text: a charge spell can show both, hence the opposite corner. The
        -- count is plain in combat (no secrecy annotation; Blizzard's item
        -- buttons compare it). Ammo exists on WoW Forever only.
        ammoText = { foreverOnly = true, d = false, t = "bool", kinds = SP, label = "Ammo stack text" },
        ammoSize = { foreverOnly = true, d = 14, t = "int", min = 6, max = 32, kinds = SP, label = "Ammo text size", dep = { field = "ammoText" } },
        ammoColor = { foreverOnly = true, d = { 1, 1, 1, 1 }, t = "color", alpha = true, kinds = SP, label = "Ammo text color", dep = { field = "ammoText" } },
        ammoOutline = { foreverOnly = true, adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = SP, label = "Ammo text outline", dep = { field = "ammoText" } },
        ammoFont = { foreverOnly = true, d = "", t = "text", font = true, kinds = SP, label = "Ammo text font", dep = { field = "ammoText" } },
        ammoAnchor = { foreverOnly = true, d = "BOTTOMLEFT", t = "enum",
            values = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT", "TOP", "BOTTOM", "CENTER" },
            kinds = SP, label = "Ammo text anchor", dep = { field = "ammoText" } },
        ammoX = { foreverOnly = true, adv = "text", d = 0, t = "int", min = -50, max = 50, kinds = SP, label = "Ammo text X", dep = { field = "ammoText" } },
        ammoY = { foreverOnly = true, adv = "text", d = 0, t = "int", min = -50, max = 50, kinds = SP, label = "Ammo text Y", dep = { field = "ammoText" } },
        ammoShadow = { foreverOnly = true, adv = "text", d = false, t = "bool", kinds = SP, label = "Ammo text shadow", dep = { field = "ammoText" } },
        -- Threshold colours for the ammo count (Factory.AmmoCountColor). The
        -- count is plain in combat, so Lua compares it; the lowest threshold
        -- it is at or below wins.
        ammoCountColors = { foreverOnly = true, d = false, t = "bool", kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "Color by ammo count" },
        ammoCountSteps = { foreverOnly = true, d = 1, t = "int", min = 1, max = 3, kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            adds = "threshold", label = "Number of ammo thresholds", dep = { field = "ammoCountColors" } },
        ammoCount1 = { foreverOnly = true, d = 400, t = "int", min = 1, max = 2000, kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "First ammo threshold (at or below)", dep = { field = "ammoCountColors" } },
        ammoCount1Color = { foreverOnly = true, d = { 1, 0.55, 0.1, 1 }, t = "color", kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "First ammo threshold color", dep = { field = "ammoCountColors" } },
        ammoCount2 = { foreverOnly = true, d = 200, t = "int", min = 1, max = 2000, kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "Second ammo threshold (at or below)",
            dep = { { field = "ammoCountColors" }, { field = "ammoCountSteps", min = 2 } } },
        ammoCount2Color = { foreverOnly = true, d = { 1, 0.15, 0.15, 1 }, t = "color", kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "Second ammo threshold color",
            dep = { { field = "ammoCountColors" }, { field = "ammoCountSteps", min = 2 } } },
        ammoCount3 = { foreverOnly = true, d = 100, t = "int", min = 1, max = 2000, kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "Third ammo threshold (at or below)",
            dep = { { field = "ammoCountColors" }, { field = "ammoCountSteps", min = 3 } } },
        ammoCount3Color = { foreverOnly = true, d = { 0.65, 0, 0, 1 }, t = "color", kinds = AMMO_CT, showIf = Schema.AmmoCountShown,
            label = "Third ammo threshold color",
            dep = { { field = "ammoCountColors" }, { field = "ammoCountSteps", min = 3 } } },
    } },
    -- A Special Aura's texts (Core\AD_SpecialIcon.lua): the stack text and the
    -- labels are templates over the tracker's tokens; the label holding the
    -- proc count and the one holding the chance take these colours. The
    -- defaults are ProcTracker's, which the migration bridge fills.
    special = { push = true, kinds = SPC, fields = {
        stackTemplate = { inherit = false, d = "", t = "text", label = "Stack text template",
            desc = "What the stack text shows. Tokens: {left} {drawn} {size} {procs} {procsLeft} {max} {chance} {viol} {count}. Empty: the tracker's own.",
            hint = "The tracker's own" },
        procColorMode = { d = "state", t = "enum", values = { "state", "fixed" },
            labels = { state = "By procs used", fixed = "The label's own color" }, label = "Proc count color" },
        procEmptyColor = { d = { 0, 1, 0, 1 }, t = "color", label = "Proc count color: none used",
            dep = { field = "procColorMode", value = "state" } },
        procHalfColor = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Proc count color: some used",
            dep = { field = "procColorMode", value = "state" } },
        procFullColor = { d = { 1, 0, 0, 1 }, t = "color", label = "Proc count color: all used",
            dep = { field = "procColorMode", value = "state" } },
        chanceDecimals = { d = true, t = "bool", label = "Chance with a decimal under 10%" },
        chanceColorMode = { d = "fixed", t = "enum", values = { "fixed", "procs", "chance" },
            labels = { fixed = "The label's own color", procs = "By procs left", chance = "By the chance" },
            label = "Chance color" },
        chanceLowPct = { d = 3, t = "int", min = 0, max = 100, label = "Cold below (%)",
            dep = { field = "chanceColorMode", value = "chance" } },
        chanceHighPct = { d = 10, t = "int", min = 0, max = 100, label = "Hot from (%)",
            dep = { field = "chanceColorMode", value = "chance" } },
        chanceColdColor = { d = { 0.6, 0.6, 0.6, 1 }, t = "color", label = "Cold chance color",
            dep = { field = "chanceColorMode", value = "chance" } },
        chanceMidColor = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Mid chance color",
            dep = { field = "chanceColorMode", value = "chance" } },
        chanceHotColor = { d = { 0, 1, 0, 1 }, t = "color", label = "Hot chance color",
            dep = { field = "chanceColorMode", value = "chance" } },
        -- By procs left: green with every proc left, red at none, gold between,
        -- unless a colour per count is chosen (decks hold at most five).
        chanceLeftCustom = { d = false, t = "bool", label = "Custom color per procs left",
            dep = { field = "chanceColorMode", value = "procs" } },
        chanceLeft0Color = { d = { 1, 0, 0, 1 }, t = "color", label = "Chance color at 0 procs left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
        chanceLeft1Color = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Chance color at 1 proc left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
        chanceLeft2Color = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Chance color at 2 procs left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
        chanceLeft3Color = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Chance color at 3 procs left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
        chanceLeft4Color = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Chance color at 4 procs left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
        chanceLeft5Color = { d = { 1, 0.82, 0, 1 }, t = "color", label = "Chance color at 5 procs left",
            dep = { { field = "chanceColorMode", value = "procs" }, { field = "chanceLeftCustom" } } },
    } },
    -- Not schema sections: the driver (rec.driver, validated per kind by the
    -- driver module; retargeting re-keys it, never the record id) and
    -- conditions (rec.c, Core\AD_Conditions.lua). Neither is pushable.
}

-- Glows 2 to 4 on an aura icon: glow 1's fields again, numbered and per icon
-- (a layout's looks carry glow 1 only). Each rides its own glow lane
-- (DriverAura); in a Dynamic aura group the row's button draws them.
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
    local function glowOK(rec)
        local DA = NS.DriverAura
        return DA ~= nil and DA.HolderGlowOK(rec)
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
            def.showIf = src.showIf or glowOK
            fields[name .. suf] = def
        end
    end
end

-- A special icon's own texts (Core\AD_SpecialIcon.lua): label slots 4 to 6,
-- the proc count (a counter's count), the chance and the violations, so its
-- three custom texts stay free. Custom text 2's fields again, numbered and
-- worded; special icons only, never a layout's look.
Schema.SPECIAL_TEXTS = {
    { suf = "4", word = "Proc count text", anchor = "CENTER" },
    { suf = "5", word = "Proc chance text", anchor = "TOP" },
    { suf = "6", word = "Violations text", anchor = "BOTTOM" },
}
do
    local fields = Schema.icon.label.fields
    local BASES = { "labelText", "labelFont", "labelPinTo", "labelPinTarget", "labelSize", "labelColor",
        "labelAnchor", "labelX", "labelY", "labelShowReady", "labelShowCooldown" }
    for _, t in ipairs(Schema.SPECIAL_TEXTS) do
        local suf = t.suf
        for _, base in ipairs(BASES) do
            local src = fields[base .. "2"]
            local def = {}
            for k, v in pairs(src) do def[k] = v end
            if type(src.d) == "table" then
                def.d = {}
                for i, v in ipairs(src.d) do def.d[i] = v end
            end
            def.inherit = false
            def.kinds = SPC
            local lbl = (src.label or base):gsub("^Custom text 2", t.word, 1)
            def.label = (lbl:gsub("custom text 2", t.word:lower(), 1))
            if src.dep then def.dep = { field = "labelText" .. suf, nonempty = true } end
            if base == "labelAnchor" then def.d = t.anchor end
            if base == "labelShowReady" then
                def.statePick, def.rangePick = "labelShowCooldown" .. suf, nil
            end
            if base == "labelShowCooldown" then def.pickedBy = "labelShowReady" .. suf end
            fields[base .. suf] = def
        end
    end
end

-- An aura group showing every aura on one unit (Drivers\AD_DriverUnitAuras.lua)
-- shows at most this many per half: Rows by Columns, clamped. The game makes
-- buttons in batches of 10 as auras need them, each dressed as it is made.
Schema.UNIT_AURA_MAX = 40
-- Enemy nameplates get one container per plate token; the game numbers up to 40.
Schema.UNIT_AURA_PLATES = 40

-- The game hides an aura by spell ID only for buffs on you or your pet and
-- debuffs on a unit you cannot assist (a target, a focus, an enemy plate);
-- elsewhere an exclude list is skipped, so the hidden aura would still show.
function Schema.UnitAuraHideOK(unit, harmful)
    if harmful then return unit == "target" or unit == "focus" or unit == "nameplate" end
    return unit == "player" or unit == "pet"
end

-- The unit and type a show-all group reads, and whether it shows both
-- halves: enemy nameplates carry debuffs only, whatever Aura type a group set
-- before it moved to them.
function Schema.UnitAuraShape(rec)
    local Store = NS.Store
    local unit = Store.Resolve(rec, "unitAuras", "unit")
    if unit == "nameplate" then return unit, true, false end
    local t = Store.Resolve(rec, "unitAuras", "auraType")
    return unit, t == "debuff", t == "both"
end

-- With both halves, the list is offered when the game honours it for one.
function Schema.UnitAuraHideShown(rec)
    local Store = NS.Store
    if not (rec and Store) then return false end
    local unit, harmful, both = Schema.UnitAuraShape(rec)
    if both then return Schema.UnitAuraHideOK(unit, false) or Schema.UnitAuraHideOK(unit, true) end
    return Schema.UnitAuraHideOK(unit, harmful)
end

function Schema.UnitAuraOffPlates(rec)
    return NS.Store.Resolve(rec, "unitAuras", "unit") ~= "nameplate"
end

-- Max shown, retired for Rows by Columns: a saved cap under one line becomes
-- that many columns, so the box and the cap stay as they were; a longer one
-- becomes the rows it filled. Before the strip drops the key.
function Schema.FoldUnitAuraCap(rec)
    local u = rec.type == "group" and rec.o and rec.o.unitAuras
    local ms = u and tonumber(u.maxShown)
    if not ms then return end
    u.maxShown = nil
    if u.rows ~= nil then return end
    ms = math.max(1, math.floor(ms))
    local a = rec.o.arrangement
    local cols = math.max(1, math.floor(tonumber(a and a.cols) or Schema.iconGroup.arrangement.fields.cols.d))
    if ms < cols then
        rec.o.arrangement = a or {}
        rec.o.arrangement.cols = ms
        u.rows = 1
    else
        u.rows = math.min(math.ceil(ms / cols), Schema.iconGroup.unitAuras.fields.rows.max)
    end
end

Schema.iconGroup = {
    -- The grid kinds only: a reminder group has no cells.
    arrangement = { push = true, inherit = true, kinds = { cooldown = true, aura = true }, fields = {
        rows = { inherit = false, d = 1, t = "int", min = 1, max = 20, label = "Rows",
            desc = "At least this many rows: icons that do not fit add more.",
            showIf = function(rec) return not (NS.Store.ShowsAll and NS.Store.ShowsAll(rec)) end },
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
        dynamicLayout = { inherit = false, d = false, t = "bool", label = "Close gaps",
            desc = "Empty spots close up while you play: a spot with no icon, or with an icon that is not loaded." },
        -- A Dynamic aura group's direction (Drivers\AD_DriverAuraRows.lua):
        -- Horizontal packs each grid row sideways (Left / Center / Right),
        -- Vertical each column (Up / Center / Down). The alignment value is
        -- read per direction (AR.Pack).
        dynamicAxis = { inherit = false, d = "horizontal", t = "enum", kinds = GK_AU,
            values = { "horizontal", "vertical" },
            labels = { horizontal = "Horizontal", vertical = "Vertical" },
            label = "Pack direction",
            desc = "Horizontal packs each row sideways; Vertical packs each column up or down." },
        -- Time left: one engine aura group per unit holds every member's
        -- spells and the game sorts it (AR.PlaceFlows), so it sorts in combat
        -- with nothing read; the members share one look and only auras that
        -- are up show. Only where the game has the aura engine.
        dynamicSort = { inherit = false, d = "editor", t = "enum", kinds = GK_AU,
            values = { "editor", "time" },
            labels = { editor = "Editor's order", time = "Time left" },
            label = "Order", dep = { field = "dynamicLayout" },
            showIf = function() return NS.DriverAuraGroups ~= nil and NS.DriverAuraGroups.IsAvailable() end,
            desc = "Editor's order keeps your order. Time left puts the aura closest to running out first; auras that never end come last." },
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
            labels = { none = "Nothing else", ready = "Ready icons",
                cooldown = "Icons on cooldown", hidden = "Icons at opacity 0" },
            label = "Also count as empty", dep = { field = "dynamicLayout" },
            desc = "Icons in this state give up their spot too, and take one again when it ends." },
        dynamicOrder = { inherit = false, d = "priority", t = "enum", values = { "priority", "fcfs" }, kinds = GK_CD,
            labels = { priority = "Takes its spot back", fcfs = "Joins the end" },
            label = "A returning icon", dep = { { field = "dynamicLayout" },
                { field = "dynamicCollapse", notValue = "none" } },
            desc = "Where an icon goes when it shows again. Only for a single row or column." },
        dynamicShrink = { d = false, t = "bool", kinds = GK_CD,
            label = "Shrink the group to fit", dep = { field = "dynamicLayout" },
            desc = "The group's box hugs the icons that are showing; anything anchored to it moves with it." },
        smoothMovement = { d = false, t = "bool", kinds = GK_CD,
            label = "Slide into place", dep = { field = "dynamicLayout" },
            desc = "Icons glide to their new spot instead of jumping." },
        -- Seconds. fmt keeps the generic slider from showing 0..1 as a percent.
        smoothDuration = { d = 0.18, t = "num", min = 0.05, max = 0.4, kinds = GK_CD,
            label = "Slide time (s)", fmt = "%.2f",
            dep = { { field = "dynamicLayout" }, { field = "smoothMovement" } } },
    } },
    look = { push = true, inherit = true, kinds = { cooldown = true, aura = true, reminder = true }, fields = {
        showBorder = { d = false, t = "bool", label = "Container border" },
        showBackground = { d = false, t = "bool", label = "Container background" },
        borderColor = { d = { 0.11, 0.16, 0.25, 1 }, t = "color", alpha = true, label = "Border color" },
        bgColor = { d = { 0, 0, 0, 0.6 }, t = "color", alpha = true, label = "Background color" },
        -- The fill inside the green outline while the window is open. A
        -- Reminder group's is clear, so its dim marker is all that shows.
        editFill = { d = { 0, 0, 0, 0.5 }, dk = { reminder = { 0, 0, 0, 0 } }, t = "color", alpha = true,
            label = "Background while editing",
            desc = "The fill behind this group while the options window is open; opacity 0 means none." },
    } },
    -- Keybind text on every member, ORed with each icon's own switch (styling
    -- stays on the icon). Cooldown groups only: auras have no binding.
    keybind = { push = true, inherit = true, kinds = GK_CD, fields = {
        showKeybinds = { d = false, t = "bool", label = "Show keybinds on all icons" },
    } },
    -- What an aura group shows: its own aura icons by spell ID, or every aura on
    -- one unit, drawn by the game (Store.ShowsAll). What the group is, so no
    -- push bar and no layout look.
    unitAuras = { kinds = GK_AU, fields = {
        -- only where the game has the aura engine
        shows = { d = "tracked", t = "enum", values = { "tracked", "unit" },
            labels = { tracked = "Tracked auras", unit = "All auras on a unit" }, label = "Shows",
            showIf = function() return NS.DriverAuraGroups ~= nil and NS.DriverAuraGroups.IsAvailable() end,
            desc = "Tracked auras: the aura icons you add to this group, matched by spell ID. All auras on a unit: every buff or debuff on one unit, drawn by the game, with no icons to add." },
        unit = { d = "player", t = "enum", values = { "player", "pet", "target", "focus", "nameplate" },
            labels = { player = "Player", pet = "Pet", target = "Target", focus = "Focus",
                nameplate = "Enemy nameplates" }, label = "Unit",
            valueIf = { focus = function()
                return not (C_EventUtils and C_EventUtils.IsEventValid)
                    or C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")
            end },
            dep = { field = "shows", value = "unit" } },
        -- enemy nameplates show debuffs only in this version; both halves share
        -- the unit's container as two aura groups
        auraType = { d = "buff", t = "enum", values = { "buff", "debuff", "both" },
            labels = { buff = "Buffs", debuff = "Debuffs", both = "Buffs and debuffs" }, label = "Aura type",
            valueIf = { buff = Schema.UnitAuraOffPlates, both = Schema.UnitAuraOffPlates },
            dep = { field = "shows", value = "unit" } },
        caster = { d = "any", t = "enum", values = { "any", "mine", "others" },
            labels = { any = "Anyone", mine = "Me (or my pet)", others = "Anyone but me" }, label = "Cast by",
            dep = { field = "shows", value = "unit" } },
        -- The grid: Rows by the arrangement's Columns is the cap, per half.
        rows = { d = 1, t = "int", min = 1, max = 10, label = "Rows",
            desc = "How many rows of auras show, each Columns wide; up to 40 auras. The rest show as others end.",
            dep = { field = "shows", value = "unit" } },
        fill = { d = "across", t = "enum", values = { "across", "down" },
            labels = { across = "Fill across first", down = "Fill down first" }, label = "Fill order",
            desc = "Across fills a row, then starts the next. Down fills a column, then starts the next.",
            dep = { { field = "shows", value = "unit" }, { field = "unit", notValue = "nameplate" } } },
        debuffLine = { d = true, t = "bool", label = "Debuffs start a new line",
            desc = "On: the debuffs start on the line after the buffs. Off: they follow straight on.",
            dep = { { field = "shows", value = "unit" }, { field = "auraType", value = "both" },
                { field = "unit", notValue = "nameplate" } } },
        order = { d = "default", t = "enum", values = { "default", "time" },
            labels = { default = "Game default", time = "Time left" }, label = "Order",
            desc = "Game default puts your own auras first. Time left puts the aura closest to running out first; auras that never end come last.",
            dep = { field = "shows", value = "unit" } },
        -- offered only where the game honours it (Schema.UnitAuraHideOK)
        hideSpells = { d = "", t = "text", label = "Hide these spells", hint = "Spell IDs, comma separated",
            desc = "Spell IDs to leave out of this group, separated by commas or spaces.",
            showIf = Schema.UnitAuraHideShown, dep = { field = "shows", value = "unit" } },
        -- The game's own dispel-type filter (the container's includeDispelTypes):
        -- any unit, enemies too, in combat; none ticked = every aura.
        dispelMagic = { d = false, t = "bool", label = "Magic", dep = { field = "shows", value = "unit" },
            desc = "Show Magic auras. Tick any dispel types to show only those; none ticked shows every aura." },
        dispelCurse = { d = false, t = "bool", label = "Curse", dep = { field = "shows", value = "unit" },
            desc = "Show Curse auras. Tick any dispel types to show only those; none ticked shows every aura." },
        dispelDisease = { d = false, t = "bool", label = "Disease", dep = { field = "shows", value = "unit" },
            desc = "Show Disease auras. Tick any dispel types to show only those; none ticked shows every aura." },
        dispelPoison = { d = false, t = "bool", label = "Poison", dep = { field = "shows", value = "unit" },
            desc = "Show Poison auras. Tick any dispel types to show only those; none ticked shows every aura." },
        -- Enemy nameplates: a row per plate, on the plate's edge. The pool of
        -- plate rows is Nameplates covered deep, grown out of combat.
        plateCount = { d = 20, t = "int", min = 1, max = Schema.UNIT_AURA_PLATES, label = "Nameplates covered",
            desc = "How many nameplates get a row, in the order the game numbers them. Each one keeps a set of frames ready.",
            dep = { { field = "shows", value = "unit" }, { field = "unit", value = "nameplate" } } },
        plateEdge = { d = "top", t = "enum", values = { "top", "bottom" },
            labels = { top = "Top", bottom = "Bottom" }, label = "Attach to the plate",
            dep = { { field = "shows", value = "unit" }, { field = "unit", value = "nameplate" } } },
        plateX = { d = 0, t = "int", min = -200, max = 200, label = "Offset X",
            dep = { { field = "shows", value = "unit" }, { field = "unit", value = "nameplate" } } },
        plateY = { d = 0, t = "int", min = -200, max = 200, label = "Offset Y",
            dep = { { field = "shows", value = "unit" }, { field = "unit", value = "nameplate" } } },
    } },
    -- Debuff type looks on a group showing every aura on a unit: parts the game
    -- shows on its buttons only for the dispel types given them
    -- (Drivers\AD_TypeLooks.lua), and with a full look per type one engine
    -- aura group per type (Drivers\AD_DriverUnitAuras.lua). Per group: no
    -- layout look, no push. Each type's own fields are added after this table
    -- from Schema.TYPE_LOOKS; a type's full look lives in rec.fullLooks.
    typeLook = { kinds = GK_AU, fields = {
        looks = { d = "off", t = "enum", values = { "off", "parts", "full" }, newAuraEngine = true,
            labels = { off = "Off", parts = "Colors and badges", full = "Full look per type" },
            -- kept in the list while picked, so the box never shows a bare key
            valueIf = { full = function(rec)
                return Schema.TypeFullOK(rec) or NS.Store.Resolve(rec, "typeLook", "looks") == "full"
            end },
            label = "Debuff type looks",
            desc = "Colors and badges keeps the game's order. Full look per type also gives each type its own size, swipe, texts and glows, in the order you pick.",
            dep = { section = "unitAuras", field = "shows", value = "unit" } },
        washAlpha = { d = 0.3, t = "num", min = 0.05, max = 1, step = 0.05, label = "Color wash strength",
            dep = { { field = "looks", anyOf = { parts = true, full = true } },
                { section = "unitAuras", field = "shows", value = "unit" } } },
        labelSize = { d = 12, t = "int", min = 6, max = 32, label = "Label size",
            dep = { { field = "looks", anyOf = { parts = true, full = true } },
                { section = "unitAuras", field = "shows", value = "unit" } } },
        labelAnchor = { d = "BOTTOMRIGHT", t = "enum", values = POINTS,
            labels = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Center",
                RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" },
            label = "Label position",
            dep = { { field = "looks", anyOf = { parts = true, full = true } },
                { section = "unitAuras", field = "shows", value = "unit" } } },
        glowSize = { d = 1.4, t = "num", min = 1, max = 2.5, step = 0.05, fmt = "%.2f", label = "Glow size",
            desc = "How far the glow reaches past the icon: 1 sits on its edge.",
            dep = { { field = "looks", anyOf = { parts = true, full = true } },
                { section = "unitAuras", field = "shows", value = "unit" } } },
        ownLine = { d = false, t = "bool", label = "Each type on its own line",
            desc = "Each type starts a new line. Off: the types follow straight on, with no gap between them.",
            showIf = function(rec) return Schema.TypeFullOK(rec) end,
            dep = { { field = "looks", value = "full" }, { section = "unitAuras", field = "shows", value = "unit" } } },
        -- The types' keys in the order they show, comma separated; "" or a
        -- short list reads as the strip's order (TL.Order). A bespoke row
        -- moves the picked type (UI\AD_UnitAuraOptions.lua).
        order = { d = "", t = "text", hidden = true, label = "Type order",
            showIf = function(rec) return Schema.TypeFullOK(rec) end,
            dep = { { field = "looks", value = "full" }, { section = "unitAuras", field = "shows", value = "unit" } } },
    } },
    -- A reminder group's pulse (Drivers\AD_DriverReminders.lua), ArcUI v1's
    -- Cooldown Reminder window: each reminder that fires pulses at the group's
    -- spot, and one already up is replaced, queued or stacked beside it. The
    -- keys and ranges are v1's. Per group, so no layout look.
    pulse = { push = true, kinds = GK_RM, fields = {
        iconEnabled = { d = true, t = "bool", label = "Show pulse icon" },
        -- On by default, as in v1: an approved exception to new switches
        -- starting off.
        cancelOnCast = { d = true, t = "bool", label = "Cancel pulse on cast" },
        -- The pulse holds at full, no fade, until the cast or its trigger's
        -- "Clear when" ends it (RM.HOLD_MAX as a backstop). An "On use"
        -- pulse keeps its time: its cast is the reminder.
        holdUntilCast = { d = false, t = "bool", label = "Stay until cast",
            desc = "The pulse stays at full, with no fade and no time limit, until you cast the spell (or use the item), or until its trigger's Clear when option ends it. On use pulses and previews still run their time." },
        hideMarker = { d = false, t = "bool", label = "Hide preview icon while editing",
            desc = "While this window is open, a dim copy of the first reminder's icon marks where pulses land. On shows only the outline and name tab." },
        queueMode = { d = "queue", t = "enum", values = { "replace", "queue", "stack" },
            labels = { replace = "Replace", queue = "Queue", stack = "Stack (side-by-side)" },
            label = "Overlap Behavior" },
        stackDirection = { d = "right", t = "enum", values = { "left", "right" },
            labels = { left = "Left", right = "Right" }, label = "Stack Direction",
            dep = { field = "queueMode", value = "stack" } },
        stackSpacing = { d = 4, t = "int", min = -32, max = 96, label = "Stack Spacing",
            dep = { field = "queueMode", value = "stack" } },
        replaceGuard = { d = 0.4, t = "num", min = 0, max = 2, step = 0.05, fmt = "%.2f",
            label = "Replace Guard (seconds)", dep = { field = "queueMode", value = "replace" } },
        queueMaxLen = { d = 3, t = "int", min = 1, max = 10, label = "Queue Max Length",
            dep = { field = "queueMode", value = "queue" } },
        queueInterDelay = { d = 0, t = "num", min = 0, max = 2, step = 0.05, fmt = "%.2f",
            label = "Queue Gap (seconds)", dep = { field = "queueMode", value = "queue" } },
        -- input: typed, not slid, so a pulse can run long
        pulseDuration = { d = 2, t = "num", min = 0.1, max = 600, step = 0.05, fmt = "%.2f", input = true,
            label = "Pulse Duration (seconds)" },
        size = { d = 80, t = "int", min = 32, max = 256, label = "Icon Size" },
        iconOpacity = { d = 1, t = "num", min = 0.1, max = 1, step = 0.05, label = "Icon Opacity" },
        animStyle = { d = "fade", t = "enum", values = { "fade", "no_fade", "flash", "zoom" },
            labels = { fade = "Fade", no_fade = "No Fade (snap off)", flash = "Flash (urgent)",
                zoom = "Zoom (pop in + fade)" },
            label = "Default Animation" },
        animFadeSmoothing = { d = "OUT", t = "enum", values = { "NONE", "OUT", "IN", "IN_OUT" },
            labels = { NONE = "Linear", OUT = "Ease Out", IN = "Ease In", IN_OUT = "Ease In/Out" },
            label = "Fade Curve", dep = { field = "animStyle", value = "fade" } },
        animFlashSpeed = { d = 0.10, t = "num", min = 0.03, max = 0.30, step = 0.01, fmt = "%.2f",
            label = "Flash Step Speed", dep = { field = "animStyle", value = "flash" } },
        animZoomStart = { d = 0.70, t = "num", min = 0.30, max = 1, step = 0.05, fmt = "%.2f",
            label = "Zoom Start Scale", dep = { field = "animStyle", value = "zoom" } },
        animZoomPeak = { d = 1.15, t = "num", min = 1, max = 1.50, step = 0.05, fmt = "%.2f",
            label = "Zoom Peak Scale", dep = { field = "animStyle", value = "zoom" } },
        animZoomPopTime = { d = 0.12, t = "num", min = 0.04, max = 0.40, step = 0.01, fmt = "%.2f",
            label = "Zoom Pop Speed", dep = { field = "animStyle", value = "zoom" } },
        animZoomSettleTime = { d = 0.08, t = "num", min = 0.02, max = 0.30, step = 0.01, fmt = "%.2f",
            label = "Zoom Settle Speed", dep = { field = "animStyle", value = "zoom" } },
        -- Aura reminders (aura icons made for the group) sit in a row beside
        -- the pulse area, each shown by the game while its aura is missing;
        -- the pulse keeps its own spot. The spacing also parts row and pulse.
        auraSide = { d = "below", t = "enum", values = { "below", "above", "left", "right" },
            labels = { below = "Below the pulse", above = "Above the pulse", left = "Left of the pulse",
                right = "Right of the pulse" },
            label = "Aura reminders sit" },
        auraSize = { d = 40, t = "int", min = 16, max = 128, label = "Aura reminder size" },
        auraSpacing = { d = 4, t = "int", min = 0, max = 40, label = "Aura reminder spacing" },
    } },
    -- A reminder group's sounds and speech. The default sound is v1's Default
    -- (the Drumroll Ding kit); a trigger plays it only once its sound is on.
    audio = { push = true, kinds = GK_RM, fields = {
        soundEnabled = { d = true, t = "bool", label = "Enable sound" },
        -- values and labels: the alerts channel's, set below the table
        soundChannel = { d = "Master", t = "enum", label = "Sound Channel" },
        soundName = { d = "kit:12867", t = "sound", label = "Default Alert Sound" },
        cutoffPreviousSound = { d = false, t = "bool", label = "Cut off previous sound" },
        cutoffFadeTime = { d = 0.1, t = "num", min = 0, max = 0.5, step = 0.05, fmt = "%.2f",
            label = "Cutoff fade-out (seconds)", dep = { field = "cutoffPreviousSound" } },
        ttsVoiceOverride = { d = "default", t = "enum", values = { "default", "male", "female" },
            labels = { default = "Default (WoW setting)", male = "Male", female = "Female" },
            label = "Voice" },
        ttsRateOverride = { d = false, t = "bool", label = "Override speech rate" },
        ttsRate = { d = 0, t = "int", min = -10, max = 10, label = "Speech Rate",
            dep = { field = "ttsRateOverride" } },
    } },
    frame = { fields = {
        strata = { adv = "frame", d = "MEDIUM", t = "enum",
            values = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Frame strata" },
        level = { adv = "frame", d = 1, t = "int", min = 1, max = 100, label = "Frame level" },
    } },
    -- Anchoring (Core\AD_Anchor.lua). Dragging an anchored group edits the
    -- offsets; pos is never written while anchored. The target fields are
    -- hidden: the Anchoring tab draws its own rows.
    anchor = { fields = {
        anchorEnabled = { d = false, t = "bool", hidden = true, label = "Anchor this group" },
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "icon", "layout", "frame", "mouse" },
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
    -- A reminder group's pulses never take the mouse.
    mouse = { push = true, kinds = { cooldown = true, aura = true }, fields = {
        clickThrough = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Click-through" },
        showTooltip = { d = "inherit", t = "enum", values = { "inherit", "on", "off" },
            label = "Show tooltips" },
    } },
}

-- The dispel types a group's type looks know, in the strip's order, with the
-- game's own colours (Blizzard's debuff type colours). "None" is an aura with
-- no type; it has no badge art.
Schema.TYPE_LOOKS = {
    { key = "Magic", label = "Magic", color = { 0.2, 0.6, 1, 1 } },
    { key = "Curse", label = "Curse", color = { 0.6, 0, 1, 1 } },
    { key = "Disease", label = "Disease", color = { 0.6, 0.4, 0, 1 } },
    { key = "Poison", label = "Poison", color = { 0, 0.6, 0, 1 } },
    { key = "None", label = "No type", color = { 0.8, 0, 0, 1 }, noBadge = true },
}
do
    local fields = Schema.iconGroup.typeLook.fields
    local dep = { { field = "looks", anyOf = { parts = true, full = true } },
        { section = "unitAuras", field = "shows", value = "unit" } }
    local never = function() return false end
    for _, t in ipairs(Schema.TYPE_LOOKS) do
        local k, name = t.key, t.label
        fields["border" .. k] = { d = t.noBadge and "normal" or "color", t = "enum",
            values = { "normal", "color", "blizzard", "blizzardBadge", "badge" },
            labels = { normal = "Normal look", color = "Your color", blizzard = "Blizzard border",
                blizzardBadge = "Blizzard border with badge", badge = "Badge only" },
            valueIf = t.noBadge and { blizzardBadge = never, badge = never } or nil,
            label = name .. " border",
            desc = "Normal look keeps the group's border. Your color uses this type's color below. The Blizzard ones are the game's own debuff borders.",
            dep = dep }
        fields["color" .. k] = { d = { t.color[1], t.color[2], t.color[3], 1 }, t = "color", label = name .. " color",
            desc = "This type's border, color wash, label and glow use it.", dep = dep }
        fields["wash" .. k] = { d = false, t = "bool", label = name .. " color wash",
            desc = "Tints the icon in this type's color. Color wash strength is under All.", dep = dep }
        fields["label" .. k] = { d = "", t = "text", label = name .. " label", hint = "A short word, like " .. name:sub(1, 1),
            desc = "A word on the icon in this type's color. Size and position are under All.", dep = dep }
        fields["glow" .. k] = { d = false, t = "bool", label = name .. " glow",
            desc = "A soft glow around the icon in this type's color. Glow size is under All.", dep = dep }
    end
end
Schema.TYPE_KEYS = {}
for _, t in ipairs(Schema.TYPE_LOOKS) do Schema.TYPE_KEYS[t.key] = true end

-- A full look per type splits one half into an engine aura group per type:
-- Buffs or Debuffs alone (a group per type cannot start the debuffs on a new
-- line once its first type is empty), off the plates (a group per type on
-- every plate is too many frames). Elsewhere the types show Colors and badges.
function Schema.TypeFullOK(rec)
    local unit, _, both = Schema.UnitAuraShape(rec)
    return unit ~= "nameplate" and both ~= true
end

-- What a type's full look may set: the icon look rows a show-all group's
-- buttons honour (Factory.StyleAuraButton), by block, in the order the type's
-- rows show them (UI\AD_UnitAuraOptions.lua). Glows add every numbered glow's
-- fields but Glow for and only in combat, which need a lane of the icon's own.
Schema.TYPE_FULL_BLOCKS = {
    -- worded apart from the group's own Icon scale on the same sub-tab
    { tab = "Icon", title = "Size", section = "position",
        fields = { "useGroupScale", "iconScale", "iconWidth", "iconHeight" },
        labels = { useGroupScale = "Use the group's size", iconScale = "This type's scale",
            iconWidth = "This type's width (0 = auto)", iconHeight = "This type's height (0 = auto)" } },
    { tab = "Icon", title = "Look", section = "appearance", fields = { "zoom", "aspectRatio", "padding" } },
    { tab = "Icon", title = "Art", section = "appearance", fields = { "forceHideIcon", "customIconFrom", "customIcon" } },
    { tab = "Icon", title = "Border", section = "appearance",
        fields = { "borderEnabled", "borderColor", "borderThickness", "borderInset", "dispelBorder" } },
    { tab = "Icon", title = "Shadow", section = "appearance", fields = { "shadowEnabled", "shadowSize" } },
    { tab = "Icon", title = "Swipe", section = "auraSwipe",
        fields = { "swipeShow", "swipeColor", "swipeReverse", "swipeEdge", "edgeColor", "edgeScale", "swipeBling" } },
    { tab = "Icon", title = "While the aura is up", section = "auraActive",
        fields = { "activeAlpha", "activeDesaturate", "activeTintEnabled", "activeTintColor", "activePreserveText" } },
    { tab = "Glows", glows = true, section = "auraActive" },
    { tab = "Text", title = "Duration text", section = "text",
        fields = { "durationText", "durationRounding", "durationFont", "durationSize", "durationColor",
            "durationOutline", "durationShadow", "durationAnchor", "durationX", "durationY" } },
    { tab = "Text", title = "Format", section = "text",
        fields = { "durationAbbrev", "durationDecimals", "durationDecimalThreshold" } },
    { tab = "Text", title = "Color by time left", section = "text",
        fields = { "durationColorBands", "durBand1Sec", "durBand1Color", "durBand2Sec", "durBand2Color",
            "durBand3Sec", "durBand3Color", "durBandCount" } },
    { tab = "Text", title = "Stacks", section = "text",
        fields = { "stackText", "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
            "stackAnchor", "stackX", "stackY", "stackShowSingle" } },
    { tab = "Text", title = "Color by count", section = "text",
        fields = { "stackColorBands", "stkBand1Min", "stkBand1Color", "stkBand2Min", "stkBand2Color",
            "stkBand3Min", "stkBand3Color", "stkBandCount" } },
}
Schema.TYPE_FULL_GLOW_SKIP = { activeGlowFor = true, activeGlowCombatOnly = true }

-- [section] = { [field] = true }: the fields a type's full look keeps
-- (Store.CleanTypeLooks drops the rest).
Schema.TYPE_FULL_FIELDS = {}
do
    local out = Schema.TYPE_FULL_FIELDS
    local function Add(section, field)
        local sec = Schema.icon[section]
        if not (sec and sec.fields[field]) then return end
        out[section] = out[section] or {}
        out[section][field] = true
    end
    for _, b in ipairs(Schema.TYPE_FULL_BLOCKS) do
        if b.glows then
            for k = 1, Schema.AURA_GLOW_SLOTS or 1 do
                local suf = (k > 1) and tostring(k) or ""
                for _, name in ipairs(Schema.AURA_GLOW_FIELDS) do
                    if not Schema.TYPE_FULL_GLOW_SKIP[name] then Add(b.section, name .. suf) end
                end
            end
        else
            for _, f in ipairs(b.fields) do Add(b.section, f) end
        end
    end
end

-- A reminder group plays on the same channels as the alerts.
do
    local from = Schema.icon.alerts.fields.soundChannel
    local to = Schema.iconGroup.audio.fields.soundChannel
    to.values, to.labels = from.values, from.labels
end

-- A reminder record (a Reminder group's member) keeps its triggers as a list
-- (rec.triggers, Store.CleanTriggers), not as schema rows. Its `pulse` section
-- is its own look, the group's field definitions shared; a field it leaves
-- unset reads its group's value (Store.Resolve).
Schema.reminder = { pulse = { fields = {} } }
for _, k in ipairs(Schema.REMINDER_LOOK) do
    Schema.reminder.pulse.fields[k] = Schema.iconGroup.pulse.fields[k]
end

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

-- A resource bar's chosen power (nil: Automatic, or not a resource bar), and
-- the gates its power-specific rows read.
function Schema.ResPower(rec)
    if not rec or rec.barKind ~= "resource" then return nil end
    local pt = rec.driver and tonumber(rec.driver.powerType)
    if pt == nil or pt < 0 then return nil end
    return pt
end
-- runes and essence come back one point at a time
function Schema.Recharges(rec)
    local pt = Schema.ResPower(rec)
    return pt == 5 or pt == 19
end
-- point powers that fold: not those whose cells run timers or fill in tenths
function Schema.Foldable(rec)
    local pt = Schema.ResPower(rec)
    local RP = NS.Bars and NS.Bars.ResPowers
    return pt ~= nil and pt ~= 5 and pt ~= 19 and pt ~= 7 and RP ~= nil and RP.IsPoint(pt)
end
function Schema.HasBlizzardBar(rec)
    local pt = Schema.ResPower(rec)
    local RC = NS.Bars and NS.Bars.ResCells
    return pt ~= nil and RC ~= nil and RC.HasBlizzardBar(pt)
end
-- Timer (custom) bars write their rule-driven stacks as the stack text.
local BK_CST  = { cooldown = true, stack = true, aura = true, enchant = true, timer = true }
-- Hide-at-zero needs our own writer to pass the count through the secret-safe
-- truncator; the engine writes an aura bar's stack text.
local BK_STKZ = { cooldown = true, stack = true, timer = true }
local BK_TMSW = { timer = true, swing = true, aura = true, enchant = true }
-- Aura bars too: SetDurationBar takes direction and interpolation from the
-- caller, so fillMode and smoothing work on aura duration bars.
local BK_FILL = { cooldown = true, timer = true, swing = true, aura = true, enchant = true, special = true }
-- Smoothing also reaches resource and health bars (StatusBar:SetValue takes an
-- interpolation on 12.x). Timer and swing fills are per-frame GetTime math with
-- nothing to interpolate, so they are left out.
local BK_SMOOTH = { cooldown = true, aura = true, resource = true, health = true }
-- Every kind but range bars, whose plate is always full in its band's colour: no
-- fill colour, fill direction or tick marks there.
local BK_NOTRANGE = { cooldown = true, aura = true, timer = true, stack = true, swing = true,
    resource = true, health = true, cast = true, enchant = true, special = true }
-- The kinds whose tick marks follow the tick mode; a deck bar's marks are its
-- procs (Bars\AD_SpecialBar.lua), so it has no mode to pick.
local BK_TICKMODE = { cooldown = true, aura = true, timer = true, stack = true, swing = true,
    resource = true, health = true, cast = true, enchant = true }
-- Every kind that draws a bar: a text element (Bars\AD_TextElement.lua) is one
-- string in a box, with no fill, chrome or text runs of the bar's.
local BK_DRAWN = { cooldown = true, aura = true, timer = true, stack = true, swing = true,
    resource = true, health = true, cast = true, enchant = true, range = true, special = true }

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

-- Every position offset defaults to 0: 0 means on the anchor point, nothing
-- hidden. These were the old defaults, which a record from before keeps
-- (Store.KeepOldOffsets): { section, field, old, the anchor an X runs along
-- (an outer top or bottom anchor drops it), a switch that must be on }.
Schema.OLD_OFFSETS = {
    icon = {
        { "keybind", "keybindX", 2 }, { "keybind", "keybindY", -2 },
        { "text", "stackX", -2 }, { "text", "stackY", 2 },
        { "text", "ammoX", 2 }, { "text", "ammoY", 2 },
    },
    bar = {
        { "text", "durOffsetX", -3, "durAnchor" }, { "text", "stkOffsetX", 3, "stkAnchor" },
        { "text", "res2OffsetX", -3, "res2Anchor" }, { "text", "res3OffsetX", 3, "res3Anchor" },
        { "text", "hpOffsetX", -3, "hpAnchor" }, { "text", "hp2OffsetX", 3, "hp2Anchor" },
        { "text", "nameOffsetY", 1 },
        { "anchor", "anchorOffsetY", -2, nil, "anchorEnabled" },
    },
}

-- The color band sets that became a count (one band when switched on, "+ Add
-- band" for more) and the looks they had before, for
-- Store.KeepOldBands: the count field, the old count when it had a default
-- (oldCount), else the old per-band values and colors (value / color name a
-- band's fields, %d its number) - a band counted when its value was above 0.
Schema.OLD_BANDS = {
    icon = {
        { section = "text", toggle = "durationColorBands", count = "durBandCount",
            value = "durBand%dSec", color = "durBand%dColor",
            vals = { 5, 60, 0 }, cols = { { 0.9, 0.15, 0.15, 1 }, { 0.95, 0.75, 0.2, 1 }, { 1, 1, 1, 1 } } },
        { section = "text", toggle = "stackColorBands", count = "stkBandCount",
            value = "stkBand%dMin", color = "stkBand%dColor",
            vals = { 1, 3, 6 }, cols = { { 1, 1, 1, 1 }, { 0.48, 0.85, 0.56, 1 }, { 0.9, 0.15, 0.15, 1 } } },
    },
    bar = {
        { section = "thresholds", toggle = "threshEnabled", count = "threshCount", oldCount = 2 },
    },
}

-- Live slider bounds: a field may carry minFn / maxFn (record -> number), which
-- the editor's number rows re-read on every sync. The stack threshold sliders
-- use this one to run up to the bar's own maximum.
Schema.MaxStacksFn = function(rec)
    local B = NS.Bars
    return (B and B.MaxStacksFor and B.MaxStacksFor(rec)) or 5
end

-- An aura bar's max-stacks fill needs the applications window 12.1.0 lacks;
-- a resource bar draws its own and keeps it.
Schema.NewEngineFill = function(rec)
    return not (NS.OldAuraEngine and NS.Store and NS.Store.KindOf(rec) == "aura")
end

-- A text element's format rows show by its source (a count, an amount, a time):
-- the runtime classifies (Bars\AD_TextElement.lua); without it every row shows.
local function TextSourceIs(what)
    return function(rec)
        local T = NS.TextElements
        if not (T and T[what]) then return true end
        return T[what](rec) == true
    end
end
Schema.TextNumeric = TextSourceIs("NumericSource")
Schema.TextCounted = TextSourceIs("CountedSource")
Schema.TextTimed = TextSourceIs("TimedSource")
Schema.TextValue = TextSourceIs("ValueSource")

local READOUT_VALUES = { "value", "abbreviated", "valuemax", "percent", "none" }
local READOUT_LABELS = { value = "Value", abbreviated = "Short value (5.2k)", valuemax = "Value / max",
    percent = "Percent", none = "Nothing" }

-- A deck bar's fill wears its procs' colours while Color by procs used is on,
-- so its own Fill color shows only with that off (Bars\AD_SpecialBar.lua).
Schema.DeckFillColorShows = function(rec)
    if not (rec and rec.barKind == "special") then return true end
    return NS.Store ~= nil and NS.Store.Resolve(rec, "deck", "stateFill") == false
end
-- What an empty deck text template shows: the tracker's own words.
Schema.DeckTemplateHint = function(which)
    return function(rec)
        local SBm = NS.SpecialBars
        return SBm and SBm.TemplateHint(rec, which) or ""
    end
end
-- The numbers of a custom tick list in the order typed: one parse for the
-- marks (Bars\AD_Bars.lua TickFractions) and the panel's colour rows, so
-- Color each tick's "Tick n color" is always the nth number drawn.
function Schema.TickValues(s)
    local out = {}
    for v in tostring(s or ""):gmatch("[%d%.]+") do
        local n = tonumber(v)
        if n then out[#out + 1] = n end
    end
    return out
end
-- Color each tick's rows past the first: one per number in the list.
local function EachTickDep(n)
    return { { field = "tickColorEach" }, { field = "ticksShow" }, { field = "tickMode", value = "custom" },
        { field = "tickValues", listMin = n } }
end

Schema.bar = {
    size = { push = true, fields = {
        -- Both run to 600 because a standing bar is thin and tall, and down to
        -- 1 because a one-pixel line is a legal bar (the renderers clamp their
        -- own insets, never this size).
        width   = { d = 193, t = "int", min = 1, max = 600, label = "Bar width" },
        height  = { d = 24, t = "int", min = 1, max = 600, label = "Bar height" },
        -- Multiplies width and height rather than calling SetScale.
        scale   = { d = 1, t = "num", min = 0.25, max = 4, label = "Bar scale" },
        opacity = { d = 1, t = "num", min = 0.1, max = 1, label = "Opacity" },
    } },
    fill = { push = true, inherit = true, kinds = BK_DRAWN, fields = {
        -- Health bars. Health is secret on Forever: the gradient goes through
        -- UnitHealthPercent and a colour curve, class vs reaction through
        -- SetVertexColorFromBoolean (a creature has no class colour).
        colorMode = { inherit = false, d = "fill", t = "enum", values = { "fill", "class", "reaction", "gradient" },
            labels = { fill = "Fill color", class = "Class color (reaction for creatures)",
                reaction = "Reaction color", gradient = "Health gradient" },
            kinds = BK_HP, label = "Color by" },
        -- Only used while colorMode is "fill"; every other bar kind resolves
        -- colorMode to that default.
        color       = { inherit = false, d = { 0.247, 0.788, 0.949, 1 }, t = "color", alpha = true, label = "Fill color",
            kinds = BK_NOTRANGE, dep = { field = "colorMode", value = "fill" }, showIf = Schema.DeckFillColorShows },
        gradLowColor = { d = { 1, 0.15, 0.15, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Empty health color",
            dep = { field = "colorMode", value = "gradient" } },
        gradMidColor = { d = { 1, 0.82, 0.1, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Half health color",
            dep = { field = "colorMode", value = "gradient" } },
        gradHighColor = { d = { 0.2, 0.85, 0.3, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Full health color",
            dep = { field = "colorMode", value = "gradient" } },
        -- Cast bars: channels and uninterruptible casts can have their own
        -- colour; SetVertexColorFromBoolean applies it, since whether a cast
        -- can be interrupted is secret for a target or focus in combat.
        castChannelOn = { d = false, t = "bool", kinds = BK_CAST, label = "Own color for channels" },
        castChannelColor = { d = { 0.36, 0.85, 0.46, 1 }, t = "color", alpha = true, kinds = BK_CAST, label = "Channel color",
            dep = { field = "castChannelOn" } },
        castLockOn = { d = false, t = "bool", kinds = BK_CAST, label = "Own color when it can't be interrupted",
            desc = "Casts you cannot interrupt take this color. In combat the game hides whether a target's cast can be interrupted from addons, so this can only change how the bar looks." },
        castLockColor = { d = { 0.62, 0.64, 0.68, 1 }, t = "color", alpha = true, kinds = BK_CAST, label = "Can't be interrupted color",
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
        swingOffhandColor = { d = { 1, 0.75, 0.3, 1 }, t = "color", alpha = true, kinds = { swing = true },
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
        swingOffhandLabelColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingOffhand" }, { field = "swingOffhandLabel" } }, label = "Off-hand label color" },
        -- Swing bars: two halves that close in and meet as the swing lands, and
        -- ticks where a set time is left (Bars\AD_SwingClosing.lua). The
        -- off-hand track splits the fill its own way, so the two never show together.
        swingClosing = { d = false, t = "bool", kinds = { swing = true },
            dep = { field = "swingOffhand", value = false }, label = "Fill closes in from both ends" },
        -- The panel draws the tick rows under the custom ticks (Appearance >
        -- Ticks), so their words say swing and never repeat a custom tick row's.
        swingTicks = { d = false, t = "bool", kinds = { swing = true }, label = "Tick before the swing lands" },
        swingTickTime = { d = 0.5, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g",
            kinds = { swing = true }, dep = { field = "swingTicks" }, label = "Time before it lands (s)" },
        swingTickColor = { d = { 1, 1, 1, 0.9 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { field = "swingTicks" }, label = "Swing tick color" },
        -- Up to three ticks: tick 1 is the pair above, so saved bars read the
        -- same; ticks 2 and 3 default to a GCD line and a seal-twist line.
        swingTickCount = { d = 1, t = "enum", values = { 1, 2, 3 }, labels = { "1 tick", "2 ticks", "3 ticks" },
            kinds = { swing = true }, dep = { field = "swingTicks" }, label = "Number of swing ticks" },
        swingTick2Time = { d = 1.5, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 2 } },
            label = "Swing tick 2 time before it lands (s)" },
        swingTick2Color = { d = { 0.4, 1, 0.4, 0.9 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 2 } }, label = "Swing tick 2 color" },
        swingTick3Time = { d = 0.4, t = "num", min = 0.1, max = 1.5, step = 0.05, fmt = "%g", kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 3 } },
            label = "Swing tick 3 time before it lands (s)" },
        swingTick3Color = { d = { 1, 0.45, 0.9, 0.9 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingTicks" }, { field = "swingTickCount", min = 3 } }, label = "Swing tick 3 color" },
        -- Swing and timer bars: a bright line on the fill's moving edge while
        -- it runs (Bars\AD_BarSpark.lua), on each half with the closing fill.
        edgeSpark = { d = false, t = "bool", kinds = { swing = true, timer = true },
            kindModes = { timer = { duration = true } }, label = "Spark" },
        edgeSparkColor = { d = { 1, 1, 1, 0.9 }, t = "color", alpha = true, kinds = { swing = true, timer = true },
            kindModes = { timer = { duration = true } }, dep = { field = "edgeSpark" }, label = "Spark color" },
        edgeSparkWidth = { d = 3, t = "int", min = 2, max = 16, kinds = { swing = true, timer = true },
            kindModes = { timer = { duration = true } }, dep = { field = "edgeSpark" }, label = "Spark width" },
        -- Main-hand swing bars: each next-swing ability marked where it comes off
        -- cooldown (Bars\AD_SwingAbilities.lua). The spell IDs live on the driver
        -- (rec.driver.swingAbilIDs), so the editor draws that row itself.
        swingAbilities = { d = false, t = "bool", kinds = { swing = true }, label = "Show next-swing abilities" },
        -- Which markers show (all of them unless switched off) and what each
        -- looks like; a colour's opacity reaches its tick, icon and count.
        swingAbilCD = { d = true, t = "bool", kinds = { swing = true }, dep = { field = "swingAbilities" },
            label = "Cooldown markers",
            desc = "Where an ability comes off cooldown: this swing, or a later one marked +1, +2." },
        swingAbilBadge = { d = true, t = "bool", kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilCD" } }, label = "Swing count (+1, +2)",
            desc = "The number beside a marker that comes back in a later swing." },
        swingAbilFar = { d = true, t = "bool", kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilCD" } }, label = "Further out marker",
            desc = "At the end of the swing while an ability comes back later than the swings you look ahead." },
        swingAbilReady = { d = true, t = "bool", kinds = { swing = true }, dep = { field = "swingAbilities" },
            label = "Ready marker", desc = "Once an ability is off cooldown." },
        swingAbilQueued = { d = true, t = "bool", kinds = { swing = true }, dep = { field = "swingAbilities" },
            label = "Queued marker", desc = "While an ability waits to go off with your next swing." },
        swingAbilPlace = { d = "stay", t = "enum", values = { "stay", "jump", "follow" },
            labels = { stay = "Stays where it came back", jump = "Jumps to where the swing lands",
                follow = "Queued rides the swing" },
            kinds = { swing = true }, dep = { field = "swingAbilities" }, label = "Ready and queued place" },
        -- The swing a queued marker rides; asked only with the off-hand track on.
        swingAbilFollow = { d = "mh", t = "enum", values = { "mh", "oh", "first" },
            labels = { mh = "Main hand", oh = "Off hand", first = "Whichever lands first" },
            kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilPlace", value = "follow" },
                { field = "swingOffhand" } },
            label = "Queued rides" },
        swingAbilAhead = { d = 4, t = "enum", values = { 1, 2, 3, 4, 5, 6 },
            labels = { "1 swing", "2 swings", "3 swings", "4 swings", "5 swings", "6 swings" },
            kinds = { swing = true }, dep = { { field = "swingAbilities" }, { field = "swingAbilCD" } },
            label = "Swings to look ahead" },
        swingAbilIconSize = { d = 25, t = "int", min = 8, max = 48, kinds = { swing = true },
            dep = { field = "swingAbilities" }, label = "Ability icon size" },
        swingAbilTint = { d = "state", t = "enum", values = { "state", "own" },
            labels = { state = "Marker color", own = "Spell's own colors" },
            kinds = { swing = true }, dep = { field = "swingAbilities" }, label = "Icon color",
            desc = "Marker color tints the icon. Spell's own colors keeps the real icon, with the marker color as its outline." },
        swingAbilColorNow = { d = { 1, 0.82, 0.2, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilCD" } }, label = "This swing color" },
        swingAbilColorLater = { d = { 1, 0.55, 0.15, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilCD" } }, label = "Later swings color" },
        swingAbilColorFar = { d = { 0.9, 0.25, 0.25, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilCD" }, { field = "swingAbilFar" } },
            label = "Further out color" },
        swingAbilColorReady = { d = { 0.3, 0.95, 0.35, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilReady" } }, label = "Ready color" },
        swingAbilColorQueued = { d = { 0.247, 0.788, 0.949, 1 }, t = "color", alpha = true, kinds = { swing = true },
            dep = { { field = "swingAbilities" }, { field = "swingAbilQueued" } }, label = "Queued color" },
        -- Stack bars use this for the slot recharge animation too.
        smoothing   = { d = true, t = "bool", kinds = BK_SMOOTH, label = "Smooth fill" },
        useGradient = { d = true, t = "bool", label = "Gradient fill" },
        -- VERTICAL fades toward the bottom, HORIZONTAL toward the far end.
        gradientDir = { d = "VERTICAL", t = "enum", values = { "VERTICAL", "HORIZONTAL" },
            label = "Gradient direction", dep = { field = "useGradient" } },
        gradientColor = { d = { 0, 0, 0, 0.45 }, t = "color", alpha = true, label = "Gradient end color",
            dep = { field = "useGradient" } },
        fillInset   = { d = 0, t = "int", min = 0, max = 12, label = "Fill padding" },
        -- A built-in key, or a LibSharedMedia key when an LSM addon is loaded
        -- (never bundled). Hidden: the bar editor draws its own dropdown.
        texture = { d = "", t = "text", hidden = true, media = "statusbar", label = "Bar texture" },
        rotateTexture = { d = false, t = "bool", label = "Rotate texture" },
    } },
    -- One section, two editor blocks: Background and Border.
    look = { push = true, inherit = true, kinds = BK_DRAWN, fields = {
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
        borderColor     = { d = { 0, 0, 0, 1 }, t = "color", alpha = true, label = "Border color", dep = { field = "borderEnabled" } },
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
        dividerColor = { d = { 0.039, 0.067, 0.125, 1 }, t = "color", alpha = true, kinds = { stack = true },
            label = "Divider color", dep = { field = "segmentsShow" } },
        -- Physical pixels: the gap between charge slots, or a power-stack bar's
        -- divider width (dk: 2 there, the width its dividers draw by default).
        segmentSpacing = { d = 1, dk = { stack = 2 }, t = "int", min = 1, max = 10, label = "Segment spacing", dep = { field = "segmentsShow" } },
        -- Keyed off the ready state, which is not secret; never a count read.
        fullColorEnabled = { d = false, t = "bool", kinds = BK_CD, label = "Full charges color" },
        fullColor = { d = { 0.482, 0.847, 0.561, 1 }, t = "color", alpha = true, kinds = BK_CD, label = "Full charges color value", dep = { field = "fullColorEnabled" } },
        -- Recharge overlay tint; off uses the fill color.
        rechargeColorEnabled = { d = false, t = "bool", kinds = BK_CD, label = "Recharge color" },
        rechargeColor = { d = { 0.247, 0.788, 0.949, 0.55 }, t = "color", alpha = true, kinds = BK_CD, label = "Recharge color value", dep = { field = "rechargeColorEnabled" } },
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
        pointColor = { d = { 0.247, 0.788, 0.949, 1 }, t = "color", alpha = true, label = "Point color",
            dep = { { field = "style", value = "pips" }, { field = "usePowerColor", value = false } } },
        -- The point colour showing faintly through an empty cell; 0, the
        -- default, leaves the Background colour reading as itself.
        pipEmptyTint = { d = 0, t = "num", min = 0, max = 1, label = "Empty pip tint",
            dep = { field = "style", value = "pips" } },
        -- Runes: Blizzard's order (ready first, then the soonest back) or rune
        -- i in cell i.
        runeOrder = { d = "ready", t = "enum", values = { "ready", "fixed" },
            labels = { ready = "Ready runes first", fixed = "Rune 1 to 6" }, label = "Rune order",
            showIf = function(rec) return Schema.ResPower(rec) == 5 end },
        -- A recharging rune or the essence point that is filling, in either
        -- style: how it fills, which way, and its colour (off = the point's
        -- own colour at half brightness).
        rechargeFill = { d = "up", t = "enum", values = { "up", "down" },
            labels = { up = "Fills up", down = "Empties" }, label = "Recharge fill",
            showIf = function(rec) return Schema.Recharges(rec) end },
        rechargeDir = { d = "bar", t = "enum", values = { "bar", "right", "left", "up", "down" },
            labels = { bar = "With the bar", right = "Left to right", left = "Right to left",
                up = "Bottom to top", down = "Top to bottom" }, label = "Recharge direction",
            showIf = function(rec) return Schema.Recharges(rec) end },
        rechargeColorEnabled = { d = false, t = "bool", label = "Recharge color",
            desc = "Off: a recharging point is its own color at half brightness.",
            showIf = function(rec) return Schema.Recharges(rec) end },
        rechargeColor = { d = { 0.4, 0.4, 0.4, 1 }, t = "color", alpha = true, label = "Recharge color value",
            dep = { field = "rechargeColorEnabled" },
            showIf = function(rec) return Schema.Recharges(rec) end },
        -- Rogue charged combo points: lit in this colour, and at half
        -- brightness while not yet reached.
        chargedShow = { d = false, t = "bool", label = "Charged points",
            showIf = function(rec) return Schema.ResPower(rec) == 4 and NS.IsForever ~= true end },
        chargedColor = { d = { 0.169, 0.733, 0.992, 1 }, t = "color", alpha = true, label = "Charged color",
            dep = { field = "chargedShow" },
            showIf = function(rec) return Schema.ResPower(rec) == 4 and NS.IsForever ~= true end },
        -- Half the points, the second half lit over the first in its own
        -- colour (Maelstrom Weapon's 5 + 5).
        foldOn = { d = false, t = "bool", label = "Fold in half",
            desc = "Half the points; past the middle they light again in the second half color.",
            showIf = function(rec) return Schema.Foldable(rec) end },
        foldColor = { d = { 1, 0.5, 0, 1 }, t = "color", alpha = true, label = "Second half color",
            dep = { field = "foldOn" }, showIf = function(rec) return Schema.Foldable(rec) end },
        -- Blizzard's own class bar under the player frame, faded out while
        -- this bar is loaded.
        hideBlizzard = { inherit = false, d = false, t = "bool", label = "Hide Blizzard's class bar",
            desc = "Fades out the game's own bar for this resource while this bar is loaded.",
            showIf = function(rec) return Schema.HasBlizzardBar(rec) end },
    } },
    -- Side icon. On a cast bar it shows the spell being cast, on a deck bar its
    -- tracker's art.
    icon = { push = true, inherit = true, kinds = { cooldown = true, aura = true, cast = true, enchant = true, timer = true,
        special = true }, fields = {
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
        iconBorderColor = { d = { 0, 0, 0, 1 }, t = "color", alpha = true, label = "Icon border color",
            dep = { { field = "iconShow" }, { field = "iconBorderEnabled" } } },
        iconBorderThickness = { d = 1, t = "int", min = 1, max = 10, label = "Icon border thickness",
            dep = { { field = "iconShow" }, { field = "iconBorderEnabled" } } },
        -- Not on cast bars: their icon is whatever is being cast.
        iconOverride = { inherit = false, d = 0, t = "id", kinds = { cooldown = true, aura = true, timer = true, special = true },
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
    text = { push = true, inherit = true, kinds = BK_DRAWN, fields = {
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
        durOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_DURC, label = "Duration offset X" },
        durOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_DURC, label = "Duration offset Y" },
        durPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS, kinds = BK_DURC, label = "Duration text pinned to" },
        durPinTarget = { inherit = false, d = "", t = "text", kinds = BK_DURC, label = "Duration text pin target" },
        durColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_DURC, label = "Duration color" },
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
        stkOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_CST, label = "Stack offset X" },
        stkOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_CST, label = "Stack offset Y" },
        stkPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS, kinds = BK_CST, label = "Stack text pinned to" },
        stkPinTarget = { inherit = false, d = "", t = "text", kinds = BK_CST, label = "Stack text pin target" },
        stkColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_CST, label = "Stack color" },
        stkHideAtZero = { d = true, t = "bool", kinds = BK_STKZ, label = "Stack hides at zero" },
        -- The "/max" suffix, built by the stack-mode slot pass. maxCharges is
        -- not secret; the count is never read.
        stkShowMax = { d = false, t = "bool", kinds = BK_CD, label = "Stack shows max",
            kindModes = { cooldown = { stack = true } } },
        -- Resource bars: the power value; resFormat picks what it shows.
        resShow = { d = true, t = "bool", kinds = BK_RES, label = "Resource text" },
        resSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Resource text size" },
        resOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_RES, label = "Resource outline" },
        resColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_RES, label = "Resource color" },
        resAnchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_RES, label = "Resource anchor" },
        resOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Resource offset X" },
        resOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Resource offset Y" },
        resPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS, kinds = BK_RES, label = "Resource text pinned to" },
        resPinTarget = { inherit = false, d = "", t = "text", kinds = BK_RES, label = "Resource text pin target" },
        -- What text 1 says. abbreviated takes secrets; percent runs a 0..100
        -- curve and a rule formatter; valuemax formats the value against the
        -- plain max. All of it works in combat.
        resFormat = { d = "value", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Resource text shows", dep = { field = "resShow" } },
        -- Texts 2 and 3 have their own format, size, colour and place; outline
        -- and shadow come from text 1.
        resCount = { inherit = false, d = 1, t = "int", min = 1, max = 3, kinds = BK_RES, adds = "resource text",
            label = "Number of resource texts", dep = { field = "resShow" } },
        res2Format = { d = "percent", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Text 2 shows", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Text 2 size", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_RES, label = "Text 2 color", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2Anchor = { d = "RIGHT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_RES, label = "Text 2 anchor", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2OffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 2 offset X", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res2OffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 2 offset Y", dep = { { field = "resShow" }, { field = "resCount", min = 2 } } },
        res3Format = { d = "valuemax", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_RES, label = "Text 3 shows", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Text 3 size", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_RES, label = "Text 3 color", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3Anchor = { d = "LEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_RES, label = "Text 3 anchor", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3OffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 3 offset X", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        res3OffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Text 3 offset Y", dep = { { field = "resShow" }, { field = "resCount", min = 3 } } },
        -- Destruction reads its shards in tenths (3.4); this keeps whole shards.
        resWholeShards = { d = false, t = "bool", kinds = BK_RES, label = "Whole shards only",
            showIf = function(rec) return Schema.ResPower(rec) == 7 end },
        -- Runes and essence: each recharging point counts down on its own cell
        -- (pips) or its stretch of the bar, rendered C-side from the same timer
        -- that fills it.
        rcShow = { d = false, t = "bool", kinds = BK_RES, label = "Recharge text",
            showIf = function(rec) return Schema.Recharges(rec) end },
        rcSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_RES, label = "Recharge text size",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_RES,
            label = "Recharge outline", dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcShadow = { adv = "text", d = false, t = "bool", kinds = BK_RES, label = "Recharge shadow",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, kinds = BK_RES, label = "Recharge text color",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcAnchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_RES,
            label = "Recharge text anchor", dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Recharge offset X",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_RES, label = "Recharge offset Y",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcDecimalsEnabled = { d = false, t = "bool", kinds = BK_RES, label = "Recharge decimals",
            dep = { field = "rcShow" }, showIf = function(rec) return Schema.Recharges(rec) end },
        rcDecimalThreshold = { d = 3, t = "int", min = 2, max = 60, kinds = BK_RES, label = "Decimals below (s)",
            dep = { { field = "rcShow" }, { field = "rcDecimalsEnabled" } },
            showIf = function(rec) return Schema.Recharges(rec) end },
        -- Health bars. Health is secret: only SetText, SetFormattedText and
        -- AbbreviateNumbers handle it, never Lua maths.
        hpShow = { d = true, t = "bool", kinds = BK_HP, label = "Health text" },
        hpFormat = { d = "value", t = "enum",
            values = { "value", "abbreviated", "valuemax", "percent", "none" },
            labels = { value = "Value", abbreviated = "Short value (5.2k)", valuemax = "Value / max",
                percent = "Percent", none = "Nothing" },
            kinds = BK_HP, label = "Health text shows", dep = { field = "hpShow" } },
        hpSize = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Health text size" },
        hpOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_HP, label = "Health outline" },
        hpColor = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Health text color" },
        hpAnchor = { d = "RIGHT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS, kinds = BK_HP, label = "Health anchor" },
        hpOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Health offset X" },
        hpOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Health offset Y" },
        hpPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS, kinds = BK_HP, label = "Health text pinned to" },
        hpPinTarget = { inherit = false, d = "", t = "text", kinds = BK_HP, label = "Health text pin target" },
        hpShadow = { adv = "text", d = false, t = "bool", kinds = BK_HP, label = "Health shadow" },
        -- Texts 2 and 3, as on resource bars.
        hpCount = { inherit = false, d = 1, t = "int", min = 1, max = 3, kinds = BK_HP, adds = "health text",
            label = "Number of health texts", dep = { field = "hpShow" } },
        hp2Format = { d = "percent", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_HP, label = "Text 2 shows", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Text 2 size", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Text 2 color", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2Anchor = { d = "LEFT", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_HP, label = "Text 2 anchor", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2OffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 2 offset X", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp2OffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 2 offset Y", dep = { { field = "hpShow" }, { field = "hpCount", min = 2 } } },
        hp3Format = { d = "valuemax", t = "enum", values = READOUT_VALUES, labels = READOUT_LABELS,
            kinds = BK_HP, label = "Text 3 shows", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Size = { d = 12, t = "int", min = 6, max = 32, kinds = BK_HP, label = "Text 3 size", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Color = { d = { 0.95, 0.97, 1, 1 }, t = "color", alpha = true, kinds = BK_HP, label = "Text 3 color", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3Anchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            kinds = BK_HP, label = "Text 3 anchor", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3OffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 3 offset X", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
        hp3OffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, kinds = BK_HP, label = "Text 3 offset Y", dep = { { field = "hpShow" }, { field = "hpCount", min = 3 } } },
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
        nameOffsetX = { adv = "text", d = 0, t = "int", min = -100, max = 100, label = "Name offset X" },
        nameOffsetY = { adv = "text", d = 0, t = "int", min = -100, max = 100, label = "Name offset Y" },
        namePinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS, label = "Name text pinned to" },
        namePinTarget = { inherit = false, d = "", t = "text", label = "Name text pin target" },
        nameColor = { d = { 0.7, 0.78, 0.88, 1 }, t = "color", alpha = true, label = "Name color" },
        readyShow = { d = false, t = "bool", kinds = BK_CD, label = "Ready text" },
        readyText = { inherit = false, d = "Ready", t = "text", kinds = BK_CD, label = "Ready text string", dep = { field = "readyShow" } },
        readyColor = { d = { 0.482, 0.847, 0.561, 1 }, t = "color", alpha = true, kinds = BK_CD, label = "Ready color", dep = { field = "readyShow" } },
        -- Per-text outlines; the ready text takes the duration text's styling.
        durOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_DURC, label = "Duration outline" },
        stkOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, kinds = BK_CST, label = "Stack outline" },
        nameOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" }, label = "Name outline" },
        -- Per-text drop shadow (black, 1px down and right); ready follows dur.
        durShadow = { adv = "text", d = false, t = "bool", kinds = BK_DURC, label = "Duration shadow" },
        stkShadow = { adv = "text", d = false, t = "bool", kinds = BK_CST, label = "Stack shadow" },
        resShadow = { adv = "text", d = false, t = "bool", kinds = BK_RES, label = "Resource shadow" },
        nameShadow = { adv = "text", d = false, t = "bool", label = "Name shadow" },
    } },
    -- Cooldown bars evaluate durObj curves (useChargeDur fixed at setup); timer
    -- and swing bars compare plain seconds in the GetTime loop; aura duration
    -- bars get engine-driven colour layers, so their time never reaches Lua.
    thresholds = { push = true, kinds = { cooldown = true, timer = true, aura = true, swing = true },
        kindModes = { aura = { duration = true }, timer = { duration = true } }, fields = {
        threshEnabled = { d = false, t = "bool", label = "Threshold colors" },
        -- Bands in play (of three); the others hide and the runtime skips them.
        -- adds: the panel grows the count with an "Add threshold" button. One
        -- to start (it was two: Schema.OLD_BANDS keeps those).
        threshCount = { d = 1, t = "int", min = 1, max = 3, adds = "threshold", label = "Number of thresholds", dep = { field = "threshEnabled" } },
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
        thresh2Color = { d = { 0.95, 0.76, 0.31, 1 }, t = "color", alpha = true, label = "Threshold 2 color", dep = { field = "threshEnabled" } },
        thresh3Value = { d = 5, dk = { swing = 0.5 }, t = "num", min = 0, max = 600, step = 0.1, fmt = "%g",
            label = "Threshold 3 value",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 2 } } },
        thresh3Color = { d = { 0.95, 0.40, 0.40, 1 }, t = "color", alpha = true, label = "Threshold 3 color",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 2 } } },
        thresh4Value = { d = 0, t = "num", min = 0, max = 600, step = 0.1, fmt = "%g",
            label = "Threshold 4 value",
            dep = { { field = "threshEnabled" }, { field = "threshCount", min = 3 } } },
        thresh4Color = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Threshold 4 color",
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
        scPosition = { d = false, t = "bool", kinds = { aura = true }, newAuraEngine = true,
            label = "Keep each stack's own color (segmented)" },
        scEnabled = { d = false, t = "bool", label = "Color by stack count" },
        -- Colour 1 is the fill colour; each extra colour takes over from a
        -- stack count, on a slider from 2 to the bar's maximum (maxFn).
        scCount = { d = 2, t = "int", min = 1, max = 3, adds = "color", label = "Extra colors (after the fill color)", dep = { field = "scEnabled" } },
        sc2Value = { d = 3, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 2 from stack", dep = { field = "scEnabled" } },
        sc2Color = { d = { 1, 1, 0, 1 }, t = "color", alpha = true, label = "Color 2", dep = { field = "scEnabled" } },
        sc3Value = { d = 5, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 3 from stack",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 2 } } },
        sc3Color = { d = { 1, 0.5, 0, 1 }, t = "color", alpha = true, label = "Color 3",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 2 } } },
        sc4Value = { d = 7, t = "int", min = 2, max = 99, maxFn = Schema.MaxStacksFn, label = "Color 4 from stack",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 3 } } },
        sc4Color = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, label = "Color 4",
            dep = { { field = "scEnabled" }, { field = "scCount", min = 3 } } },
        maxColorEnabled = { d = false, t = "bool", showIf = Schema.NewEngineFill, label = "Max stacks color" },
        maxColor = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, showIf = Schema.NewEngineFill,
            label = "Max stacks color value", dep = { field = "maxColorEnabled" } },
    } },
    -- Primary resource bars: colour by power percent. UnitPowerPercent
    -- evaluates a colour curve client-side, so the possibly secret value never
    -- reaches Lua: one call per power event. "below" colours at or under the
    -- value (a mana warning), "above" at or over it.
    powerthresholds = { push = true, kinds = BK_RES, fields = {
        pthEnabled = { d = false, t = "bool", label = "Threshold colors" },
        -- Bands in play, one by default; the runtime reads only these.
        pthCount = { d = 1, t = "int", min = 1, max = 3, adds = "threshold", label = "Number of thresholds", dep = { field = "pthEnabled" } },
        -- Values in power units instead of percent (45 energy, 2000 mana): the
        -- plain cached max converts them, so the same percent curve serves both
        -- and the secret value never reaches Lua.
        pthAbsolute = { d = false, t = "bool", label = "Thresholds in power units", dep = { field = "pthEnabled" } },
        pthDirection = { d = "below", t = "enum", values = { "below", "above" }, label = "Color when power is", dep = { field = "pthEnabled" } },
        pth2Value = { d = 50, t = "int", min = 0, max = 20000, label = "Threshold 2 value", dep = { field = "pthEnabled" } },
        pth2Color = { d = { 1, 1, 0, 1 }, t = "color", alpha = true, label = "Threshold 2 color", dep = { field = "pthEnabled" } },
        pth3Value = { d = 25, t = "int", min = 0, max = 20000, label = "Threshold 3 value",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 2 } } },
        pth3Color = { d = { 1, 0.5, 0, 1 }, t = "color", alpha = true, label = "Threshold 3 color",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 2 } } },
        pth4Value = { d = 10, t = "int", min = 0, max = 20000, label = "Threshold 4 value",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 3 } } },
        pth4Color = { d = { 1, 0, 0, 1 }, t = "color", alpha = true, label = "Threshold 4 color",
            dep = { { field = "pthEnabled" }, { field = "pthCount", min = 3 } } },
        pthFullEnabled = { d = false, t = "bool", label = "Full power color" },
        pthFullColor = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, label = "Full power color value", dep = { field = "pthFullEnabled" } },
        pthText = { d = false, t = "bool", label = "Color the text too", dep = { field = "pthEnabled" } },
    } },
    -- Health bars: colour by health percent (execute range, low-health
    -- warning). UnitHealthPercent evaluates the colour curve C-side from the
    -- secret value: no compare, one call per health event.
    healththresholds = { push = true, kinds = BK_HP, fields = {
        hpthEnabled = { d = false, t = "bool", label = "Threshold colors" },
        hpthCount = { d = 1, t = "int", min = 1, max = 3, adds = "threshold", label = "Number of thresholds", dep = { field = "hpthEnabled" } },
        hpthDirection = { d = "below", t = "enum", values = { "below", "above" },
            labels = { below = "At or below the value", above = "At or above the value" },
            label = "Color when health is", dep = { field = "hpthEnabled" } },
        hpth2Value = { d = 35, t = "int", min = 1, max = 99, label = "First threshold (%)", dep = { field = "hpthEnabled" } },
        hpth2Color = { d = { 1, 0.55, 0.1, 1 }, t = "color", alpha = true, label = "First threshold color", dep = { field = "hpthEnabled" } },
        hpth3Value = { d = 20, t = "int", min = 1, max = 99, label = "Second threshold (%)",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 2 } } },
        hpth3Color = { d = { 1, 0.15, 0.15, 1 }, t = "color", alpha = true, label = "Second threshold color",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 2 } } },
        hpth4Value = { d = 10, t = "int", min = 1, max = 99, label = "Third threshold (%)",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 3 } } },
        hpth4Color = { d = { 0.65, 0, 0, 1 }, t = "color", alpha = true, label = "Third threshold color",
            dep = { { field = "hpthEnabled" }, { field = "hpthCount", min = 3 } } },
        hpthText = { d = false, t = "bool", label = "Color the health text too", dep = { field = "hpthEnabled" } },
        -- The last threshold's band pulses. Health is secret, so the pulse
        -- sits in a frame whose alpha a step curve sets (HB.PaintPulse).
        hpthPulse = { d = false, t = "bool", label = "Pulse at the last threshold", dep = { field = "hpthEnabled" } },
    } },
    -- Tick marks, laid out on size or setting changes, never per update. "all":
    -- one per unit while the bar's max is a small integer (stacks, small power
    -- maxes, seconds up to 60), else percent. "percent": every N%. "custom": a
    -- typed list in the bar's unit or in percent, plus cost ticks on resource
    -- bars. "pertick": one per tick, player castbars only. Cooldown stack bars
    -- have none: their slot gaps are the marks.
    ticks = { push = true, inherit = true, kinds = BK_NOTRANGE, kindModes = { cooldown = { duration = true } }, fields = {
        ticksShow = { inherit = false, d = false, t = "bool", label = "Tick marks" },
        -- A deck bar's marks are its procs: the mode and its values are not its.
        tickMode = { inherit = false, kinds = BK_TICKMODE, d = "percent", t = "enum", values = { "all", "percent", "custom", "pertick" }, label = "Tick mode", dep = { field = "ticksShow" },
            labels = { all = "Every point", percent = "Every X percent", custom = "Custom values", pertick = "One per tick" },
            -- valueIf (record -> bool) hides a value from the editor's list. A target's or
            -- focus's channel is secret in combat, so only a player castbar can mark ticks.
            valueIf = { pertick = function(r) return r.barKind == "cast" and ((r.driver and r.driver.unit) or "player") == "player" end } },
        tickPercent = { inherit = false, kinds = BK_TICKMODE, d = 25, t = "int", min = 5, max = 50, label = "Tick every (%)",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "percent" } } },
        -- labelFn (record -> words or nil): on a swing bar the list says where
        -- it counts from, the fill's start: the swing's start, or its landing
        -- on a drain bar. The swing ticks always count back from the landing.
        tickValues = { inherit = false, kinds = BK_TICKMODE, d = "", t = "text", label = "Custom ticks (comma list)",
            labelFn = function(r)
                local S = NS.Store
                if not (S and r and r.barKind == "swing") then return nil end
                local unit = S.Resolve(r, "ticks", "tickAsPercent") == true and "percent" or "seconds"
                if S.Resolve(r, "fill", "fillMode") == "drain" then
                    return "Custom ticks, " .. unit .. " before the swing lands"
                end
                return "Custom ticks, " .. unit .. " from the swing's start"
            end,
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickAsPercent = { inherit = false, kinds = BK_TICKMODE, d = false, t = "bool", label = "Custom ticks are percent",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickScale = { inherit = false, kinds = BK_TICKMODE, d = 0, t = "int", min = 0, max = 3600, label = "Custom tick scale (0 = auto)",
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
        tickColor = { d = { 0, 0, 0, 1 }, t = "color", alpha = true, label = "Tick color", dep = { field = "ticksShow" } },
        -- Custom values only: the nth number typed wears tick colour n (the
        -- Tick color is the first; numbers past six wear the sixth). Per bar
        -- like the list it numbers, and off by default, so a saved bar keeps
        -- its one colour.
        tickColorEach = { inherit = false, kinds = BK_TICKMODE, d = false, t = "bool", label = "Color each tick",
            desc = "Each number in the custom list wears its own colour, in the order you typed them; the Tick color is the first.",
            dep = { { field = "ticksShow" }, { field = "tickMode", value = "custom" } } },
        tickColor2 = { inherit = false, kinds = BK_TICKMODE, d = { 0.4, 1, 0.4, 1 }, t = "color", alpha = true,
            label = "Tick 2 color", dep = EachTickDep(2) },
        tickColor3 = { inherit = false, kinds = BK_TICKMODE, d = { 1, 0.45, 0.9, 1 }, t = "color", alpha = true,
            label = "Tick 3 color", dep = EachTickDep(3) },
        tickColor4 = { inherit = false, kinds = BK_TICKMODE, d = { 1, 0.82, 0, 1 }, t = "color", alpha = true,
            label = "Tick 4 color", dep = EachTickDep(4) },
        tickColor5 = { inherit = false, kinds = BK_TICKMODE, d = { 0.25, 0.8, 1, 1 }, t = "color", alpha = true,
            label = "Tick 5 color", dep = EachTickDep(5) },
        tickColor6 = { inherit = false, kinds = BK_TICKMODE, d = { 1, 0.4, 0.2, 1 }, t = "color", alpha = true,
            label = "Tick 6 color", dep = EachTickDep(6) },
        -- Physical pixels, down to one: LayoutTicks puts every edge on a whole pixel.
        tickThickness = { d = 2, t = "int", min = 1, max = 10, label = "Tick thickness", dep = { field = "ticksShow" } },
        tickHeight = { d = 100, t = "int", min = 10, max = 100, label = "Tick height (%)", dep = { field = "ticksShow" } },
        tickHeightAnchor = { d = "center", t = "enum", values = { "center", "start", "end" }, label = "Tick height anchor", dep = { field = "ticksShow" } },
    } },
    -- Deck bars (Bars\AD_SpecialBar.lua): a Special Aura tracker's deck. The fill
    -- colour by procs used, a mark where each proc landed, and two texts (the
    -- deck position and the proc count), each with its own font, place and
    -- colours. "state" colours: none used / some used / all used. An empty
    -- template shows the tracker's own text.
    deck = { push = true, kinds = { special = true }, fields = {
        stateFill = { d = true, t = "bool", label = "Color by procs used",
            desc = "The fill shows how many of this deck's procs are used: none, some or all. Off: the Fill color." },
        emptyColor = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, label = "No procs used color", dep = { field = "stateFill" } },
        halfColor = { d = { 1, 0.82, 0, 1 }, t = "color", alpha = true, label = "Some procs used color", dep = { field = "stateFill" } },
        fullColor = { d = { 1, 0, 0, 1 }, t = "color", alpha = true, label = "All procs used color", dep = { field = "stateFill" } },
        texEmptyEnabled = { d = false, t = "bool", label = "Dim fill while no procs used", dep = { field = "stateFill" } },
        texEmptyColor = { d = { 0.15, 0.15, 0.15, 0.6 }, t = "color", alpha = true, label = "Dim fill color",
            dep = { { field = "stateFill" }, { field = "texEmptyEnabled" } } },
        procTicks = { d = true, t = "bool", label = "Mark each proc",
            desc = "A tick where each proc of this deck landed. A new deck clears them.",
            dep = { section = "ticks", field = "ticksShow" } },
        posShow = { d = false, t = "bool", label = "Deck position text" },
        posTemplate = { inherit = false, d = "", t = "text", label = "Deck position shows", dep = { field = "posShow" },
            hintFn = Schema.DeckTemplateHint("pos"),
            desc = "Tokens: {left} {drawn} {size} {procs} {procsLeft} {max} {chance} {viol} {count}. Empty: the tracker's own." },
        posFont = { d = "", t = "text", font = true, label = "Deck position font", dep = { field = "posShow" } },
        posSize = { d = 14, t = "int", min = 6, max = 64, label = "Deck position size", dep = { field = "posShow" } },
        posOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" },
            labels = { OUTLINE = "Outline", THICKOUTLINE = "Thick outline", NONE = "None" },
            label = "Deck position outline", dep = { field = "posShow" } },
        posShadow = { adv = "text", d = false, t = "bool", label = "Deck position shadow", dep = { field = "posShow" } },
        posAnchor = { d = "CENTER", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            label = "Deck position anchor", dep = { field = "posShow" } },
        posOffsetX = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Deck position offset X",
            dep = { field = "posShow" } },
        posOffsetY = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Deck position offset Y",
            dep = { field = "posShow" } },
        posPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Deck position pinned to", dep = { field = "posShow" } },
        posPinTarget = { inherit = false, d = "", t = "text", label = "Deck position pin target", dep = { field = "posShow" } },
        posColorMode = { d = "fixed", t = "enum", values = { "fixed", "state" },
            labels = { fixed = "One color", state = "Procs used" }, label = "Deck position color by",
            dep = { field = "posShow" } },
        posColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Deck position color",
            dep = { { field = "posShow" }, { field = "posColorMode", value = "fixed" } } },
        posEmptyColor = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, label = "Deck position, no procs used",
            dep = { { field = "posShow" }, { field = "posColorMode", value = "state" } } },
        posHalfColor = { d = { 1, 0.82, 0, 1 }, t = "color", alpha = true, label = "Deck position, some procs used",
            dep = { { field = "posShow" }, { field = "posColorMode", value = "state" } } },
        posFullColor = { d = { 1, 0, 0, 1 }, t = "color", alpha = true, label = "Deck position, all procs used",
            dep = { { field = "posShow" }, { field = "posColorMode", value = "state" } } },
        procShow = { d = true, t = "bool", label = "Proc count text" },
        procTemplate = { inherit = false, d = "", t = "text", label = "Proc count shows", dep = { field = "procShow" },
            hintFn = Schema.DeckTemplateHint("proc"),
            desc = "Tokens: {left} {drawn} {size} {procs} {procsLeft} {max} {chance} {viol} {count}. Empty: the tracker's own." },
        procFont = { d = "", t = "text", font = true, label = "Proc count font", dep = { field = "procShow" } },
        procSize = { d = 14, t = "int", min = 6, max = 64, label = "Proc count size", dep = { field = "procShow" } },
        procOutline = { adv = "text", d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" },
            labels = { OUTLINE = "Outline", THICKOUTLINE = "Thick outline", NONE = "None" },
            label = "Proc count outline", dep = { field = "procShow" } },
        procShadow = { adv = "text", d = false, t = "bool", label = "Proc count shadow", dep = { field = "procShow" } },
        procAnchor = { d = "TOP", t = "enum", values = TEXT_ANCHORS, labels = TEXT_ANCHOR_LABELS,
            label = "Proc count anchor", dep = { field = "procShow" } },
        procOffsetX = { adv = "text", d = 0, t = "int", min = -200, max = 200, label = "Proc count offset X",
            dep = { field = "procShow" } },
        procOffsetY = { adv = "text", d = 2, t = "int", min = -200, max = 200, label = "Proc count offset Y",
            dep = { field = "procShow" } },
        procPinTo = { inherit = false, d = "own", t = "enum", values = Schema.PIN_TO, labels = Schema.PIN_LABELS,
            label = "Proc count pinned to", dep = { field = "procShow" } },
        procPinTarget = { inherit = false, d = "", t = "text", label = "Proc count pin target", dep = { field = "procShow" } },
        procColorMode = { d = "state", t = "enum", values = { "fixed", "state" },
            labels = { fixed = "One color", state = "Procs used" }, label = "Proc count color by",
            dep = { field = "procShow" } },
        procColor = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Proc count color",
            dep = { { field = "procShow" }, { field = "procColorMode", value = "fixed" } } },
        procEmptyColor = { d = { 0, 1, 0, 1 }, t = "color", alpha = true, label = "Proc count, no procs used",
            dep = { { field = "procShow" }, { field = "procColorMode", value = "state" } } },
        procHalfColor = { d = { 1, 0.82, 0, 1 }, t = "color", alpha = true, label = "Proc count, some procs used",
            dep = { { field = "procShow" }, { field = "procColorMode", value = "state" } } },
        procFullColor = { d = { 1, 0, 0, 1 }, t = "color", alpha = true, label = "Proc count, all procs used",
            dep = { { field = "procShow" }, { field = "procColorMode", value = "state" } } },
    } },
    -- Primary resource bars: the cost of the spell being cast, anchored to the
    -- fill's edge rather than computed from the secret value.
    predict = { push = true, inherit = true, kinds = BK_RES, fields = {
        predictEnabled = { d = false, t = "bool", label = "Show spell cost while casting" },
        predictColor = { d = { 1, 1, 1, 1 }, t = "color", label = "Cost color", dep = { field = "predictEnabled" } },
        predictAlpha = { d = 0.5, t = "num", min = 0.1, max = 1, label = "Cost opacity", dep = { field = "predictEnabled" } },
    } },
    -- Mana bars: the five-second rule, a spark crossing the bar while spirit
    -- regen waits after a spell that costs mana (Bars\AD_ManaRegen.lua). WoW
    -- Forever only: retail mana regen neither pauses nor ticks.
    regen = { push = true, inherit = true, kinds = BK_RES, fields = {
        fsrOn = { foreverOnly = true, d = false, t = "bool", label = "Five-second rule",
            desc = "After a spell that costs mana, a spark crosses the bar for the 5 seconds before spirit regen resumes." },
        fsrShow = { foreverOnly = true, d = "always", t = "enum", values = { "always", "ooc" },
            labels = { always = "Always", ooc = "Only out of combat" }, label = "Show", dep = { field = "fsrOn" } },
        fsrColor = { foreverOnly = true, d = { 1, 0.82, 0.25, 0.95 }, t = "color", alpha = true, label = "Spark color", dep = { field = "fsrOn" } },
        fsrWidth = { foreverOnly = true, d = 2, t = "int", min = 1, max = 12, label = "Spark width", dep = { field = "fsrOn" } },
        fsrDir = { foreverOnly = true, d = "down", t = "enum", values = { "down", "up" },
            labels = { down = "Counting down", up = "Counting up" }, label = "Spark moves",
            desc = "Counting down: the spark starts at the bar's full end and moves back. Counting up: the other way.",
            dep = { field = "fsrOn" } },
        fsrSound = { foreverOnly = true, d = "", t = "sound", label = "Sound when regen resumes", dep = { field = "fsrOn" } },
        fsrText = { foreverOnly = true, d = false, t = "bool", label = "Countdown text", dep = { field = "fsrOn" } },
        fsrTextPos = { foreverOnly = true, d = "right", t = "enum", values = { "left", "center", "right" },
            labels = { left = "Left", center = "Center", right = "Right" }, label = "Countdown position",
            dep = { { field = "fsrOn" }, { field = "fsrText" } } },
        fsrTextSize = { foreverOnly = true, d = 11, t = "int", min = 6, max = 24, label = "Countdown size",
            dep = { { field = "fsrOn" }, { field = "fsrText" } } },
        -- The regen ticks, every 2 s: found from mana events away from your
        -- casts; the next tick's mana comes from GetManaRegen, fed unread.
        tickSpark = { foreverOnly = true, d = false, t = "bool", label = "Tick spark",
            desc = "A spark crosses the bar every 2 seconds and lands on each mana tick." },
        tickSparkColor = { foreverOnly = true, d = { 0.9, 0.95, 1, 0.9 }, t = "color", alpha = true, label = "Tick spark color",
            dep = { field = "tickSpark" } },
        tickSparkWidth = { foreverOnly = true, d = 2, t = "int", min = 1, max = 12, label = "Tick spark width", dep = { field = "tickSpark" } },
        incoming = { foreverOnly = true, d = false, t = "bool", label = "Incoming mana",
            desc = "The mana the next tick adds glows past the fill, brightens as the tick nears, then lands. Empty while the five-second rule runs." },
        incomingColor = { foreverOnly = true, d = { 0.52, 0.72, 0.92, 0.85 }, t = "color", alpha = true, label = "Incoming color",
            dep = { field = "incoming" } },
        incomingFlash = { foreverOnly = true, d = false, t = "bool", label = "Flash when a tick lands", dep = { field = "incoming" } },
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
        -- The whole shield from the bar's far end, clipped to the health fill:
        -- only the part past full health shows, drawn by the game, no maths.
        -- On by default, unlike other new switches: a shield on a full-health
        -- unit is otherwise invisible. Works with the glow.
        absorbOver = { d = true, t = "bool", label = "Show over-shield inside the bar",
            dep = { field = "absorbShow" },
            desc = "The part of a shield that doesn't fit past full health draws over the end of the health, so a shield on a full-health unit still shows." },
        healAbsorbShow = { d = false, t = "bool", label = "Heal absorbs" },
        healAbsorbColor = { d = { 0.55, 0.05, 0.2, 1 }, t = "color", label = "Heal absorb color", dep = { field = "healAbsorbShow" } },
        healAbsorbAlpha = { d = 0.7, t = "num", min = 0.1, max = 1, label = "Heal absorb opacity", dep = { field = "healAbsorbShow" } },
    } },
    -- Cast bars (Bars\AD_Castbar.lua). Name, time, icon and colours live in the
    -- shared blocks. What a target's or focus's cast hides in combat (its time,
    -- whether it can be interrupted) reaches only secret-safe sinks.
    cast = { push = true, inherit = true, kinds = BK_CAST, fields = {
        sparkOn = { d = false, t = "bool", label = "Spark" },
        sparkColor = { d = { 1, 1, 1, 0.9 }, t = "color", alpha = true, label = "Spark color", dep = { field = "sparkOn" } },
        sparkWidth = { d = 3, t = "int", min = 1, max = 16, label = "Spark width", dep = { field = "sparkOn" } },
        holdOn = { d = false, t = "bool", label = "Hold interrupted and failed casts",
            desc = "An interrupted or failed cast stays up for a moment in its color, with the reason as its name. A finished cast always goes at once." },
        holdTime = { d = 0.6, t = "num", min = 0.1, max = 3, step = 0.1, fmt = "%g", label = "Hold for (s)",
            dep = { field = "holdOn" } },
        holdFailColor = { d = { 1, 0.55, 0.1, 1 }, t = "color", alpha = true, label = "Failed color", dep = { field = "holdOn" } },
        holdIntColor = { d = { 0.9, 0.2, 0.2, 1 }, t = "color", alpha = true, label = "Interrupted color", dep = { field = "holdOn" } },
        fadeOut = { d = 0, t = "num", min = 0, max = 2, step = 0.1, fmt = "%g", label = "Fade out (s)",
            desc = "How long the bar takes to fade away when a cast ends (after the hold, when that is on). 0 = it goes at once." },
        -- Which casts show
        hideChannels = { inherit = false, d = false, t = "bool", label = "Hide channels" },
        lockHide = { inherit = false, d = false, t = "bool", label = "Hide casts that can't be interrupted",
            desc = "In combat the game hides whether a target's cast can be interrupted from addons, so the bar still hides those casts but cannot do anything else about them (no sound, no alert)." },
        -- Your casts only: the editor offers these on a player castbar.
        latencyOn = { d = false, t = "bool", label = "Latency zone",
            desc = "The end of your cast that your connection's delay covers: start the next cast once the fill reaches it." },
        latencyColor = { d = { 1, 0.25, 0.2, 0.55 }, t = "color", alpha = true, label = "Latency color", dep = { field = "latencyOn" } },
        -- Where the game's spell queue window opens (the SpellQueueWindow
        -- setting before the cast ends); never on channels.
        queueTickOn = { d = false, t = "bool", label = "Spell queue tick",
            desc = "A mark where your next spell can be queued: press it past the mark and it goes off as soon as this cast ends." },
        queueTickColor = { d = { 0.35, 0.85, 1, 1 }, t = "color", alpha = true, label = "Queue tick color",
            dep = { field = "queueTickOn" } },
        -- physical pixels, down to one, like the tick marks
        queueTickWidth = { d = 2, t = "int", min = 1, max = 8, label = "Queue tick width",
            dep = { field = "queueTickOn" } },
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
    -- Text elements (Bars\AD_TextElement.lua): one string in a box. The value
    -- comes from the source on Tracking (rec.driver); every read the game
    -- keeps secret goes straight into a text sink.
    textel = { push = true, inherit = true, kinds = { text = true }, fields = {
        -- "" = the game's default face; a built-in or a LibSharedMedia font.
        font = { d = "", t = "text", font = true, label = "Font" },
        size = { d = 14, t = "int", min = 6, max = 64, label = "Text size" },
        outline = { d = "OUTLINE", t = "enum", values = { "OUTLINE", "THICKOUTLINE", "NONE" },
            labels = { OUTLINE = "Outline", THICKOUTLINE = "Thick outline", NONE = "None" }, label = "Outline" },
        shadow = { d = false, t = "bool", label = "Shadow" },
        color = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Text color" },
        justifyH = { d = "CENTER", t = "enum", values = { "LEFT", "CENTER", "RIGHT" },
            labels = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }, label = "Align" },
        justifyV = { d = "MIDDLE", t = "enum", values = { "TOP", "MIDDLE", "BOTTOM" },
            labels = { TOP = "Top", MIDDLE = "Middle", BOTTOM = "Bottom" }, label = "Vertical align" },
        bgShow = { d = false, t = "bool", label = "Box background" },
        bgColor = { d = { 0, 0, 0, 0.5 }, t = "color", alpha = true, label = "Box background color",
            dep = { field = "bgShow" } },
        -- The words around the value: this element's own, never a layout look.
        -- A countdown the game draws itself (a spell's or an aura's time) has none.
        prefix = { inherit = false, d = "", t = "text", label = "Prefix", showIf = Schema.TextValue,
            desc = "Words before the value. Not on a countdown the game draws (a spell's time left, an aura's)." },
        suffix = { inherit = false, d = "", t = "text", label = "Suffix", showIf = Schema.TextValue,
            desc = "Words after the value. Not on a countdown the game draws (a spell's time left, an aura's)." },
        numFormat = { d = "plain", t = "enum", values = { "plain", "abbreviated" },
            labels = { plain = "As is", abbreviated = "Short (5.2k)" }, label = "Number format",
            showIf = Schema.TextNumeric },
        blankAtZero = { d = false, t = "bool", label = "Blank at zero", showIf = Schema.TextCounted,
            desc = "Show nothing while the count is 0 (charges, combo points, ammo, stacks)." },
        decimals = { d = false, t = "bool", label = "Show tenths", showIf = Schema.TextTimed },
        decimalsBelow = { d = 10, t = "int", min = 2, max = 60, label = "Tenths below (seconds)",
            dep = { field = "decimals" }, showIf = Schema.TextTimed },
        abbrev = { d = 600, t = "enum", values = ABBREV_VALUES, labels = ABBREV_LABELS,
            label = "Show minutes (1:30)", showIf = Schema.TextTimed },
        rounding = { d = "global", t = "enum", values = { "global", "up", "down" },
            labels = { global = "Same as Settings", up = "Round up", down = "Round down" },
            label = "Rounding", showIf = Schema.TextTimed },
    } },
    -- A texture's picture (Bars\AD_TextureElement.lua): the whole picture while
    -- it is active, or a fill that runs like a bar. Turning, flipping and zoom
    -- reach the whole picture only: a fill's picture stays upright.
    texlook = { push = true, inherit = true, kinds = { texture = true }, fields = {
        -- "" = the tracked spell's icon; else a FileDataID or a file path
        image = { inherit = false, d = "", t = "text", picture = true, label = "Picture" },
        color = { d = { 1, 1, 1, 1 }, t = "color", alpha = true, label = "Picture color" },
        blend = { d = "BLEND", t = "enum", values = { "BLEND", "ADD" },
            labels = { BLEND = "Normal", ADD = "Glow (brightens what is behind)" }, label = "Picture blend" },
        desat = { d = false, t = "bool", label = "Grey out the picture" },
        mode = { d = "show", t = "enum", values = { "show", "fill" },
            labels = { show = "The whole picture", fill = "A fill, like a bar" }, label = "Picture shows as" },
        fillDir = { d = "RIGHT", t = "enum", values = { "RIGHT", "LEFT", "UP", "DOWN" },
            labels = { RIGHT = "Left to right", LEFT = "Right to left", UP = "Bottom to top", DOWN = "Top to bottom" },
            label = "Fill direction of the picture", dep = { field = "mode", value = "fill" } },
        fillMode = { d = "drain", t = "enum", values = { "drain", "fill" },
            labels = { drain = "Drain: the time left", fill = "Fill up: the time passed" },
            label = "Picture fill follows", dep = { field = "mode", value = "fill" } },
        bgShow = { d = false, t = "bool", label = "Dim copy behind",
            desc = "The picture again, dimmed, behind it: the empty part of a fill, and all that shows while it is not active." },
        bgAlpha = { d = 0.3, t = "num", min = 0, max = 1, label = "Dim copy opacity", dep = { field = "bgShow" } },
        -- off: the dim copy wears the picture's colour
        bgTint = { d = false, t = "bool", label = "Tint the dim copy", dep = { field = "bgShow" } },
        bgColor = { d = { 1, 1, 1 }, t = "color", label = "Dim copy tint",
            dep = { { field = "bgShow" }, { field = "bgTint" } } },
        bgDesat = { d = false, t = "bool", label = "Grey the dim copy", dep = { field = "bgShow" } },
        bgDesatAmount = { d = 100, t = "int", min = 5, max = 100, label = "Dim copy grey (%)",
            dep = { { field = "bgShow" }, { field = "bgDesat" } } },
        rotation = { d = 0, t = "int", min = -180, max = 180, label = "Turn the picture (degrees)",
            dep = { field = "mode", value = "show" } },
        flipH = { d = false, t = "bool", label = "Flip the picture left to right", dep = { field = "mode", value = "show" } },
        flipV = { d = false, t = "bool", label = "Flip the picture upside down", dep = { field = "mode", value = "show" } },
        zoom = { d = 0, t = "int", min = 0, max = 45, label = "Picture zoom (%)", dep = { field = "mode", value = "show" } },
        -- Crop cuts an edge off where it is: the rest keeps its size and place.
        cropL = { d = 0, t = "int", min = 0, max = 90, label = "Crop the left edge (%)", dep = { field = "mode", value = "show" } },
        cropR = { d = 0, t = "int", min = 0, max = 90, label = "Crop the right edge (%)", dep = { field = "mode", value = "show" } },
        cropT = { d = 0, t = "int", min = 0, max = 90, label = "Crop the top edge (%)", dep = { field = "mode", value = "show" } },
        cropB = { d = 0, t = "int", min = 0, max = 90, label = "Crop the bottom edge (%)", dep = { field = "mode", value = "show" } },
        pulse = { d = false, t = "bool", label = "Pulse while it shows",
            desc = "The picture grows and shrinks gently, in combat too." },
        pulseSize = { d = 15, t = "int", min = 2, max = 60, label = "Pulse size (%)", dep = { field = "pulse" } },
        pulseTime = { d = 1, t = "num", min = 0.2, max = 4, step = 0.1, fmt = "%.1f", label = "One pulse (seconds)",
            dep = { field = "pulse" } },
    } },
    -- A wheel's look (Bars\AD_Wheel.lua): it opens at the cursor, so it has no
    -- place, bar size or chrome of its own.
    wheel = { kinds = { wheel = true }, fields = {
        size = { d = 100, t = "int", min = 60, max = 160, step = 5, label = "Wheel size (%)" },
        names = { d = true, t = "bool", label = "Show names",
            desc = "Each spell's or item's name beside its icon." },
        cooldowns = { d = true, t = "bool", label = "Show cooldowns",
            desc = "A swipe over each icon while it is on cooldown." },
        counts = { d = true, t = "bool", label = "Show item counts",
            desc = "How many you carry, on items that stack, such as potions." },
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
        -- A health bar's click area: a secure unit button over the bar that
        -- targets the unit, opens its menu and takes click-cast bindings, in
        -- combat too (Bars\AD_ClickUnit.lua). A party member's bar is a unit
        -- frame, so it starts on, unlike other new switches.
        clickable = { d = false, du = { party1 = true, party2 = true, party3 = true, party4 = true },
            t = "bool", kinds = BK_HP, label = "Clickable (target on click)" },
    } },
    frame = { fields = {
        strata = { adv = "frame", d = "MEDIUM", t = "enum",
            values = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }, label = "Frame strata" },
        level = { adv = "frame", d = 10, t = "int", min = 1, max = 100, label = "Frame level" },
    } },
    -- Anchoring (Core\AD_Anchor.lua). These field names are shared by every
    -- anchorable family: don't rename them here or add a second set.
    anchor = { fields = {
        anchorEnabled = { d = false, t = "bool", hidden = true, label = "Anchor this bar" },
        -- "nameplate" is the current target's nameplate; "action" / "cdm" the
        -- action bar button or Cooldown Manager icon holding the spell typed in
        -- anchorTargetFrame (bars only).
        anchorTargetKind = { d = "group", t = "enum", values = { "group", "bar", "icon", "layout", "frame", "nameplate", "mouse",
            "action", "cdm" },
            labels = { group = "Group", bar = "Bar", icon = "Icon", layout = "Layout", frame = "Named frame",
                nameplate = "Target's nameplate", mouse = "Mouse cursor", action = "Action bar button",
                cdm = "Cooldown Manager icon" },
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
        anchorOffsetY = { d = 0, t = "int", min = -500, max = 500,
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
