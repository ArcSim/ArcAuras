-- Account-wide record store for layouts, groups, icons and bars. A value
-- resolves rec.o -> its layout's inh -> newDefaults[familyKey] -> the schema
-- default (no global tier); a record shows everywhere unless rec.c narrows it.
--
-- ArcAurasDB = {
--   nextId      = counter, only ever incremented; ids are never reused
--   records     = { [id] = rec }
--   newDefaults = { [familyKey] = { [section] = { [field] = value } } }
--   settings    = addon-wide settings
--   ui          = panel state (expanded nodes, selection)
-- }
-- rec = { id, type = "layout"|"group"|"icon"|"bar"|"reminder", name, v = schema version,
--   layout: pos={x,y}, members={childId,...},
--           inh = { [family] = { [section] = { [field] = value } } }
--           (the layout tier: looks its icons, groups and bars follow)
--   group:  layoutId, groupKind="cooldown"|"aura"|"reminder", pos={x,y},
--           members={iconId,...} (a reminder group's are reminder ids and
--           its aura reminders' icon ids)
--   icon:   kind, driver={...}, and groupId + gpos={row,col} in a group,
--           or layoutId + pos={x,y} when free
--   reminder: groupId (a reminder group), kind="spell"|"item"|"enchant",
--           driver={spellID|itemID|hand}, triggers={...} (Store.CleanTriggers)
--   bar:    layoutId, barKind, barMode, driver={...}, pos={x,y}; a wheel
--           also wheelKey, its key, which no string or copy carries
--   o = { [section] = { [field] = value } }  sparse overrides
--   c = { specs, classes, chars, talents, factions = set|nil, talentMode,
--         plus the conditions module's loadWhen/loadNever/showWhen/fadeWhen =
--         set|nil, loadWhenAll/showWhenAll, fadeAlpha/fadeTime/fadeDelay } }

local ADDON, NS = ...
local Schema = NS.Schema
local Events = NS.Events

local Store = {}
NS.Store = Store

local DB   -- ArcAurasDB, valid after Store.Init

-- The character identity behind "Only this character". Retail: "Name-Realm"
-- (the home realm is stable). Forever: the bare name. Names are unique there,
-- UnitName("player") returns the whole "First Last", and GetRealmName() shifts
-- with the server/shard hierarchy as you zone or join and leave groups, so a
-- realm-keyed lock would hide its record at random. Cached once a real name
-- reads back.
local charKey
local function CharKey()
    if charKey then return charKey end
    local name = UnitName("player")
    -- Secret check first: a secret must not reach the comparisons below.
    if issecretvalue and issecretvalue(name) then return "?" end
    if name == nil or name == "" or name == UNKNOWNOBJECT then return "?" end
    if NS.IsForever == true then
        charKey = name
    else
        local realm = GetRealmName()
        if not realm or realm == "" then return name .. "-?" end
        charKey = name .. "-" .. realm
    end
    return charKey
end
Store.CharKey = CharKey

-- Forever locks are keyed by the bare name (above). Folds "Name-Realm" keys
-- (older saves, retail imports) down to the name. Names
-- never contain "-", so the first hyphen is always the name/realm seam.
local function FoldCharKeys(chars)
    local stale
    for k in pairs(chars) do
        if type(k) == "string" and k:find("-", 1, true) then
            stale = stale or {}
            stale[#stale + 1] = k
        end
    end
    if not stale then return end
    for _, k in ipairs(stale) do
        chars[k] = nil
        chars[k:match("^([^-]*)")] = true
    end
end

local function ClassTag()
    local _, tag = UnitClass("player")
    return tag
end
Store.ClassTag = ClassTag

-- Spec reads go through C_SpecializationInfo: the bare globals are deprecated
-- aliases that exist only while a CVar keeps them. A starter spec (below
-- level 10) sits past the class's spec count and no matrix box shows it, so it
-- reads as no spec at all.
local function SpecIndex()
    local SI = C_SpecializationInfo
    local idx = SI and SI.GetSpecialization and SI.GetSpecialization()
    if type(idx) ~= "number" then return nil end
    local n = GetNumSpecializations and GetNumSpecializations()
    if type(n) == "number" and idx > n then return nil end
    return idx
end

function Store.CurSpecID()
    local idx = SpecIndex()
    if not idx then return nil end
    local id = C_SpecializationInfo.GetSpecializationInfo(idx)
    return type(id) == "number" and id > 0 and id or nil
end

-- "TANK", "HEALER" or "DAMAGER" for the current spec; nil while unknown.
function Store.CurSpecRole()
    local idx = SpecIndex()
    if not idx then return nil end
    local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(idx)
    return type(role) == "string" and role or nil
end

-- The active hero talent tree's subTreeID, or nil before one is chosen.
function Store.CurHeroID()
    local CT = C_ClassTalents
    local id = CT and CT.GetActiveHeroTalentSpec and CT.GetActiveHeroTalentSpec()
    return type(id) == "number" and id or nil
end

-- WoW Forever is spec-less: load conditions there are class checkboxes
-- writing c.classes, and a retail record's spec, role and hero keys are
-- ignored, since a gate that can never pass would hide the record for good.
-- The flavor flag alone decides: Forever ships the spec API too, and it
-- answers nothing useful there.
local function Specless()
    return NS.IsForever == true
end
Store.Specless = Specless

-- Init and normalize

function Store.Init()
    ArcAurasDB = ArcAurasDB or {}
    DB = ArcAurasDB
    -- An Arc UI Forever setup moves in whole, before the defaults below fill gaps.
    if NS.Migrate then NS.Migrate.FromArcUI(DB) end
    DB.nextId = DB.nextId or 0
    DB.records = DB.records or {}
    DB.newDefaults = DB.newDefaults or {}
    DB.ui = DB.ui or { expanded = {} }
    DB.ui.expanded = DB.ui.expanded or {}
    DB.settings = DB.settings or {}
    if DB.settings.showTooltips == nil then DB.settings.showTooltips = true end
    if DB.settings.clickThrough == nil then DB.settings.clickThrough = true end
    Store.Normalize()
end

-- Called at PLAYER_LOGIN. If the client (re)assigns the SavedVariables global
-- after our ADDON_LOADED init (a late apply), every read and write would go to
-- an orphaned table while the real data sits in the global: re-point and
-- normalize again.
function Store.AdoptLiveSV()
    if ArcAurasDB ~= DB then
        Store.Init()
        return true
    end
    return false
end

function Store.GetSetting(k)
    return DB and DB.settings and DB.settings[k]
end

function Store.SetSetting(k, v)
    if not (DB and DB.settings) then return end
    DB.settings[k] = v
    Store.Dirty("style")
end

-- Whether an element that fails Store.IsLoaded shows while editing (its eye
-- button). settings.unloadedShow[id] is the element's own choice; one whose eye
-- was never clicked follows settings.showUnloaded ("Show unloaded items while
-- editing"). Ids are never reused, so a deleted record's entry is inert.
function Store.UnloadedShown(rec)
    if not (rec and DB and DB.settings) then return false end
    local own = DB.settings.unloadedShow and DB.settings.unloadedShow[rec.id]
    if own ~= nil then return own == true end
    return DB.settings.showUnloaded == true
end

function Store.SetUnloadedShown(rec, on)
    if not (rec and DB and DB.settings) then return end
    DB.settings.unloadedShow = DB.settings.unloadedShow or {}
    DB.settings.unloadedShow[rec.id] = on and true or false
    Store.Dirty("style", rec.id)
end

-- the Settings switch is the show-all / hide-all: flipping it sends every
-- element's eye back to following it
function Store.ResetUnloadedShown()
    if not (DB and DB.settings) then return end
    DB.settings.unloadedShow = nil
    Store.Dirty("style")
end

-- A loaded element hidden on screen while the panel is open, so what sits
-- under it can be edited (its eye). Never saved: closing the panel clears it.
local editHidden = {}

function Store.EditHidden(rec)
    return rec ~= nil and editHidden[rec.id] == true
end

function Store.SetEditHidden(rec, on)
    if not rec then return end
    editHidden[rec.id] = on and true or nil
    Store.Dirty("style", rec.id)
end

function Store.ClearEditHidden()
    if next(editHidden) == nil then return end
    wipe(editHidden)
    Store.Dirty("style")
end

-- Folds dynamicCooldowns into dynamicCollapse on a group arrangement table (a
-- record's overrides or a saved default bucket): true ("show only icons on
-- cooldown") becomes "ready". An explicit dynamicCollapse wins.
local function FoldDynamicCooldowns(a)
    if a.dynamicCooldowns == nil then return end
    if a.dynamicCooldowns == true and a.dynamicCollapse == nil then
        a.dynamicCollapse = "ready"
    end
    a.dynamicCooldowns = nil
end

-- Folds the "hide when" keys (group and layout Visibility, bar Behavior's
-- combat hides) into the conditions module's c.fadeWhen. The hides were
-- alpha-only, so a fade to the hidden opacity (fade time 0 by default) looks
-- the same; "all must match" has no fade twin, so it reads as any-match. Kept
-- here, not in that module, so it runs even when the module has not loaded.
local HIDE_WHEN_KEYS = {
    hideInCombat = "inCombat", hideOutOfCombat = "outOfCombat",
    hideMounted = "mounted", hideInVehicle = "vehicle", hideDead = "dead",
    hideResting = "resting", hideSolo = "solo", hideInGroup = "party",
    hideInRaid = "raid", hideInInstance = "instance",
    hideInEncounter = "encounter", hideInPetBattle = "petBattle",
    hidePvP = "pvp", hideNoTarget = "noTarget", hideHasTarget = "hasTarget",
    hideCasting = "casting", hideNotCasting = "notCasting",
    hideStealthed = "stealthed", hideFlying = "flying",
    hideSwimming = "swimming", hideAlways = "always",
    hideInCasterForm = "formCaster", hideInCatForm = "formCat",
    hideInBearForm = "formBear", hideInMoonkinForm = "formMoonkin",
    hideInTravelForm = "formTravel", hideInTreeForm = "formTree",
    hideInBattleStance = "stanceBattle", hideInDefensiveStance = "stanceDefensive",
    hideInBerserkerStance = "stanceBerserker", hideInNoStance = "stanceNone",
    hideInShadowform = "shadowform", hideInNoShadowform = "noShadowform",
}

local function FoldHideWhen(rec)
    local o, c = rec.o, rec.c
    local src
    if rec.type == "group" or rec.type == "layout" then
        src = o.visibility
    elseif rec.type == "bar" then
        src = o.behavior
    end
    if type(src) ~= "table" then return end
    local any = false
    for old, new in pairs(HIDE_WHEN_KEYS) do
        if src[old] == true then
            c.fadeWhen = c.fadeWhen or {}
            c.fadeWhen[new] = true
            any = true
        end
    end
    if any and c.fadeAlpha == nil and tonumber(src.hiddenAlpha) then
        c.fadeAlpha = tonumber(src.hiddenAlpha)
    end
    if rec.type == "bar" then
        -- Only the combat hides retire. Hidden opacity stays (the fade got a
        -- copy) because the bar's state hides still use it.
        src.hideInCombat, src.hideOutOfCombat = nil, nil
        if next(src) == nil then o.behavior = nil end
    else
        o.visibility = nil
    end
end

-- Folds the Segments block of a resource or aura bar below rec.v 2: a counted
-- bar (aura stacks, combo points) that showed dividers gets tick marks in
-- "Every point" mode, and an aura bar with segmentsShow false gets
-- stackcolors.scPosition = false. Ticks come on once: a later "off" stores
-- nothing, and the stamp keeps this from re-arming them.
local function FoldBarMarks(rec)
    if rec.type ~= "bar" or (rec.v or 1) >= 2 then return end
    local o = rec.o
    if rec.barKind == "resource" or rec.barKind == "aura" then
        local seg = o.segments
        local shown = not seg or seg.segmentsShow ~= false
        local d = rec.driver or {}
        local counted = (rec.barKind == "aura" and rec.barMode == "stack")
            or (rec.barKind == "resource" and d.powerType == 4)
        if counted and shown then
            o.ticks = o.ticks or {}
            if o.ticks.ticksShow == nil then o.ticks.ticksShow = true end
            if o.ticks.tickMode == nil then o.ticks.tickMode = "all" end
            if seg and seg.dividerColor and o.ticks.tickColor == nil then
                o.ticks.tickColor = seg.dividerColor
            end
        end
        if rec.barKind == "aura" and seg and seg.segmentsShow == false then
            o.stackcolors = o.stackcolors or {}
            if o.stackcolors.scPosition == nil then o.stackcolors.scPosition = false end
        end
        o.segments = nil
    end
end

-- Folds a resource bar's resource.textFormat into text.resFormat. It must run
-- before the unknown-field strip in Normalize drops the retired key. It acts
-- only while that key exists, so it needs no version stamp.
local function FoldResFormat(rec)
    if rec.type ~= "bar" then return end
    local res = rec.o and rec.o.resource
    if not (res and res.textFormat ~= nil) then return end
    rec.o.text = rec.o.text or {}
    if rec.o.text.resFormat == nil then rec.o.text.resFormat = res.textFormat end
    res.textFormat = nil
    if next(res) == nil then rec.o.resource = nil end
end

-- Folds an aura icon's old label switches into "only while the aura is up":
-- "on cooldown" off meant exactly that on an aura icon. It acts only while the
-- old keys exist, so it needs no version stamp.
-- Snaps a stored "M:SS until" seconds value onto the dropdown's choices. 60
-- or less never showed M:SS, so it takes the default; above that, the nearest
-- choice. A value already on the list stays, so no version stamp.
local function FoldAbbrevIn(text)
    local v = text and text.durationAbbrev
    if type(v) ~= "number" then return end
    local def = Schema.icon.text.fields.durationAbbrev
    local best, gap
    for _, c in ipairs(def.values) do
        if c == v then return end
        if c > 60 and (not gap or math.abs(c - v) < gap) then best, gap = c, math.abs(c - v) end
    end
    if v <= 60 or best == def.d then best = nil end
    text.durationAbbrev = best
end

local function FoldDurationAbbrev(rec)
    if rec.type == "icon" and rec.o.text then
        FoldAbbrevIn(rec.o.text)
        if next(rec.o.text) == nil then rec.o.text = nil end
    elseif rec.type == "layout" and rec.inh and rec.inh.icon and rec.inh.icon.text then
        FoldAbbrevIn(rec.inh.icon.text)
        if next(rec.inh.icon.text) == nil then rec.inh.icon.text = nil end
    end
end

-- Folds the retired "Hide GCD swipe" switch into the GCD look: off drew the GCD
-- as an edge, on is the new default. It acts only while the old key exists, so
-- it needs no version stamp.
local function FoldGCDSwipeIn(swipe)
    if not (swipe and swipe.noGCDSwipe ~= nil) then return end
    if swipe.noGCDSwipe == false and swipe.gcdSwipe == nil then swipe.gcdSwipe = "edge" end
    swipe.noGCDSwipe = nil
end

local function FoldGCDSwipe(rec)
    if rec.type == "icon" and rec.o.swipe then
        FoldGCDSwipeIn(rec.o.swipe)
        if next(rec.o.swipe) == nil then rec.o.swipe = nil end
    elseif rec.type == "layout" and rec.inh and rec.inh.icon and rec.inh.icon.swipe then
        FoldGCDSwipeIn(rec.inh.icon.swipe)
        if next(rec.inh.icon.swipe) == nil then rec.inh.icon.swipe = nil end
    end
end

local function FoldAuraLabels(rec)
    if rec.type ~= "icon" or rec.kind ~= "aura" then return end
    local lab = rec.o and rec.o.label
    if not lab then return end
    for _, suf in ipairs({ "", "2", "3" }) do
        local rdy, cd = lab["labelShowReady" .. suf], lab["labelShowCooldown" .. suf]
        if cd == false and rdy ~= false and lab["labelActiveOnly" .. suf] == nil then
            lab["labelActiveOnly" .. suf] = true
        end
        lab["labelShowReady" .. suf], lab["labelShowCooldown" .. suf] = nil, nil
    end
    if next(lab) == nil then rec.o.label = nil end
end

-- the families a layout's inh can carry (Schema family keys)
local LAYOUT_FAMILIES = { icon = true, iconGroup = true, bar = true }

-- one stored value against its schema field: the typed coercion Normalize
-- gives a record's overrides and a layout's values alike (nil = drop it)
local function CleanValue(def, v)
    if def.t == "id" then return tonumber(v) end
    if def.t == "text" or def.t == "sound" then
        if type(v) ~= "string" then return nil end
        if #v > 120 then return v:sub(1, 120) end
        return v
    end
    if def.t == "num" or def.t == "int" then
        v = tonumber(v)
        if not v then return nil end
        if def.min and v < def.min then v = def.min end
        if def.max and v > def.max then v = def.max end
        if def.t == "int" then v = math.floor(v + 0.5) end
        return v
    end
    return v
end

-- Cleans a layout's inh like overrides, keeping only the fields that inherit.
local function CleanLayoutValues(rec)
    if rec.inh == nil then return end
    if type(rec.inh) ~= "table" then rec.inh = nil return end
    for family, secs in pairs(rec.inh) do
        local fam = LAYOUT_FAMILIES[family] and Schema[family]
        if not fam or type(secs) ~= "table" then
            rec.inh[family] = nil
        else
            for section, values in pairs(secs) do
                local sec = fam[section]
                if not sec or type(values) ~= "table" then
                    secs[section] = nil
                else
                    for field, v in pairs(values) do
                        local def = sec.fields and sec.fields[field]
                        if not (def and Schema.Inherits(def, sec)) then
                            values[field] = nil
                        else
                            values[field] = CleanValue(def, v)
                        end
                    end
                    if next(values) == nil then secs[section] = nil end
                end
            end
            if next(secs) == nil then rec.inh[family] = nil end
        end
    end
    if next(rec.inh) == nil then rec.inh = nil end
end

-- A who-set kept usable: keys of one type (a whole positive number, or a
-- string) with true as the value. An empty set stays: it means nowhere, like
-- an empty class set.
local function CleanSet(t, keyType)
    if type(t) ~= "table" then return nil end
    for k, v in pairs(t) do
        local bad = type(k) ~= keyType or v ~= true
        if not bad and keyType == "number" and (k <= 0 or k % 1 ~= 0) then bad = true end
        if bad then t[k] = nil end
    end
    return t
end

-- The who keys, shape-checked on both flavors and never dropped by flavor: a
-- retail record's spec, role and hero sets ride through a Forever save, and
-- a Forever record's talent nodes through a retail one.
local function CleanWho(rec)
    local c = rec.c
    c.classes = CleanSet(c.classes, "string")
    c.specs = CleanSet(c.specs, "number")
    c.roles = CleanSet(c.roles, "string")
    c.heroes = CleanSet(c.heroes, "number")
    c.talents = CleanSet(c.talents, "number")
    c.talentsNot = CleanSet(c.talentsNot, "number")
    -- talent sets never gate while empty, so an empty one is nothing
    if c.talents and next(c.talents) == nil then c.talents = nil end
    if c.talentsNot and next(c.talentsNot) == nil then c.talentsNot = nil end
    -- a named choice belongs to a node in one of the two sets
    if c.talentEntry ~= nil then
        if type(c.talentEntry) ~= "table" then
            c.talentEntry = nil
        else
            for k, v in pairs(c.talentEntry) do
                local listed = (c.talents and c.talents[k]) or (c.talentsNot and c.talentsNot[k])
                if not listed or type(v) ~= "number" or v <= 0 or v % 1 ~= 0 then
                    c.talentEntry[k] = nil
                end
            end
            if next(c.talentEntry) == nil then c.talentEntry = nil end
        end
    end
    if c.talentMode ~= nil and c.talentMode ~= "any" then c.talentMode = nil end
    -- the Known Spell rule: a mode, a whole positive spell ID, the rank switch
    if c.knownMode ~= "known" and c.knownMode ~= "unknown" then c.knownMode = nil end
    local ks = tonumber(c.knownSpell)
    c.knownSpell = (ks and ks > 0) and math.floor(ks) or nil
    if c.knownRank ~= true then c.knownRank = nil end
end

-- Normalize enforces the schema: drops dangling member ids, clamps typed fields
-- and discards overrides for unknown fields. Runs at login and after every
-- import. The folds run before the unknown-field strip at the end of the loop,
-- which would otherwise drop the retired keys they carry.
-- Permanent item IDs (rec.uid): kept for life and carried in exports, so a
-- later string can find the items an earlier one made. 12 random characters
-- (62^12 values), redrawn when this account already has the draw.
local UID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function ValidUid(u)
    return type(u) == "string" and #u >= 8 and #u <= 24 and u:find("^[0-9A-Za-z]+$") ~= nil
end

local function UidSet()
    local s = {}
    for _, r in pairs(DB.records) do
        if ValidUid(r.uid) then s[r.uid] = true end
    end
    return s
end

local function NewUid(taken)
    taken = taken or UidSet()
    while true do
        local t = {}
        for i = 1, 12 do
            local n = math.random(1, 62)
            t[i] = UID_CHARS:sub(n, n)
        end
        local u = table.concat(t)
        if not taken[u] then
            taken[u] = true
            return u
        end
    end
end

-- Every record has one and no two share one: the oldest record keeps a shared
-- ID, the others and any malformed one get fresh ones.
local function EnsureUids()
    local ids = {}
    for id in pairs(DB.records) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local taken = {}
    for _, id in ipairs(ids) do
        local r = DB.records[id]
        if ValidUid(r.uid) and not taken[r.uid] then taken[r.uid] = true else r.uid = nil end
        -- the export time of the string it came in with (0: an older string)
        local imp = tonumber(r.imported)
        r.imported = (imp and imp >= 0) and imp or nil
    end
    for _, id in ipairs(ids) do
        local r = DB.records[id]
        if not r.uid then r.uid = NewUid(taken) end
    end
end
Store.ValidUid = ValidUid

-- The share format this version writes and reads: a string that needs more is
-- refused by name. Raise it only when an older version would import a new
-- string wrongly, never for new settings an older one can simply skip.
Store.FORMAT = 1

function Store.AddonVersion()
    local G = C_AddOns and C_AddOns.GetAddOnMetadata
    local v = G and G(ADDON, "Version")
    return (type(v) == "string" and v:find("^%d") ~= nil) and v or nil
end

local function VersionNums(v)
    if type(v) ~= "string" then return nil end
    local t = {}
    for n in v:gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return #t > 0 and t or nil
end

-- The version that made a string, when it is newer than this one: what this
-- version does not know yet is left out of an import.
function Store.NewerMaker(made)
    local a, b = VersionNums(made), VersionNums(Store.AddonVersion())
    if not (a and b) then return nil end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return (x > y) and made or nil end
    end
    return nil
end

function Store.Normalize()
    -- Save-as-Default buckets are not records, so the loop below never sees
    -- them: their one retired key is folded here.
    local nd = DB.newDefaults and DB.newDefaults["iconGroup:cooldown"]
    if nd and nd.arrangement then FoldDynamicCooldowns(nd.arrangement) end
    for _, bucket in pairs(DB.newDefaults or {}) do
        if type(bucket) == "table" then
            FoldAbbrevIn(bucket.text)
            FoldGCDSwipeIn(bucket.swipe)
        end
    end
    -- A reminder lives only in a reminder group, and a reminder group holds
    -- reminders and aura reminders (aura icons, Store.NewAuraReminder) only:
    -- an orphaned reminder goes, and any other icon found in one (an early
    -- build filled them with icons) becomes a free icon of its layout.
    for id, rec in pairs(DB.records) do
        if rec.type == "reminder" then
            local g = DB.records[rec.groupId]
            if not (g and g.type == "group" and g.groupKind == "reminder") then DB.records[id] = nil end
        end
    end
    for _, g in pairs(DB.records) do
        if g.type == "group" and g.groupKind == "reminder" and type(g.members) == "table" then
            local lay = DB.records[g.layoutId]
            for i = #g.members, 1, -1 do
                local mid = g.members[i]
                local m = DB.records[mid]
                if m and m.type == "icon" and m.kind ~= "aura" then
                    table.remove(g.members, i)
                    if lay and type(lay.members) == "table" then
                        m.groupId, m.gpos, m.layoutId = nil, nil, lay.id
                        m.pos = { x = 0, y = -60 }
                        lay.members[#lay.members + 1] = mid
                    else
                        DB.records[mid] = nil
                    end
                end
            end
        end
    end
    for id, rec in pairs(DB.records) do
        rec.id = id
        rec.o = rec.o or {}
        rec.c = rec.c or {}
        if NS.IsForever == true and rec.c.chars then FoldCharKeys(rec.c.chars) end
        -- A reminder: a spell or an item with a whole positive ID, or a weapon
        -- enchant on a hand, its triggers kept usable for its kind. It has no
        -- cell and no position of its own.
        if rec.type == "reminder" then
            rec.gpos, rec.pos, rec.layoutId = nil, nil, nil
            if rec.kind ~= "item" and rec.kind ~= "enchant" then rec.kind = "spell" end
            local d = type(rec.driver) == "table" and rec.driver or {}
            if rec.kind == "enchant" then
                rec.driver = { hand = (d.hand == "off") and "off" or "main" }
            else
                local key = (rec.kind == "item") and "itemID" or "spellID"
                local n = tonumber(d[key])
                rec.driver = { [key] = (n and n > 0) and math.floor(n) or nil }
            end
            rec.triggers = Store.CleanTriggers(rec.triggers, rec.kind)
        end
        -- Bars are always free layout children: no grid cell, and pos must be
        -- plain numbers. A malformed kind falls back to cooldown.
        if rec.type == "bar" then
            rec.gpos = nil
            -- "swing" and "aura" stay legal where the client lacks their
            -- backends: validity is per schema, not per client, or syncing
            -- between machines would rewrite records. "timer" and power
            -- "stack" are dormant legacy kinds: legal, but not creatable.
            if rec.barKind ~= "timer" and rec.barKind ~= "stack"
                and rec.barKind ~= "swing" and rec.barKind ~= "aura"
                and rec.barKind ~= "resource" and rec.barKind ~= "health"
                and rec.barKind ~= "cast" and rec.barKind ~= "enchant"
                and rec.barKind ~= "range" and rec.barKind ~= "text"
                and rec.barKind ~= "texture" and rec.barKind ~= "wheel" then
                rec.barKind = "cooldown"
            end
            -- a timer (custom) bar fills with its timer or with its stacks
            if rec.barKind == "cooldown" or rec.barKind == "aura" or rec.barKind == "timer" then
                if rec.barMode ~= "stack" then rec.barMode = "duration" end
            else
                rec.barMode = nil
            end
            rec.pos = rec.pos or {}
            rec.pos.x = tonumber(rec.pos.x) or 0
            rec.pos.y = tonumber(rec.pos.y) or 0
            rec.driver = rec.driver or {}
            if rec.barKind == "timer" then Store.CleanCustom(rec.driver, true) end
            -- A range bar: an unknown preset falls to the class default at
            -- runtime, its spell is a positive ID or nothing, and a custom
            -- preset keeps its own bands only while one is left.
            if rec.barKind == "range" then
                local d = rec.driver
                local p = d.preset
                if p ~= "hunter" and p ~= "melee" and p ~= "caster" and p ~= "custom" then d.preset = nil end
                local sid = tonumber(d.spellID)
                d.spellID = (sid and sid > 0) and math.floor(sid) or nil
                d.bands = Store.CleanRangeBands(d.bands)
                if d.preset == "custom" and not d.bands then d.preset = nil end
            end
            -- A swing bar's ability colours: every rule kept, its fields made
            -- usable (Bars\AD_SwingColors.lua reads them as they are).
            if rec.barKind == "swing" then
                rec.driver.swingColors = Store.CleanSwingColors(rec.driver.swingColors)
                -- the out-of-range check's own spell: a whole positive ID or none
                local rs = tonumber(rec.driver.rangeSpell)
                rec.driver.rangeSpell = (rs and rs > 0) and math.floor(rs) or nil
            end
            -- A health bar's unit token is handed to every health call, so
            -- an unknown one (hand-edited or damaged) falls back to the
            -- player rather than reaching the API.
            if rec.barKind == "health" then
                local ok = false
                for _, u in ipairs(NS.Schema.HEALTH_UNITS or {}) do
                    if rec.driver.unit == u then ok = true break end
                end
                if not ok then rec.driver.unit = "player" end
            end
            if rec.barKind == "cast" then
                local ok = false
                for _, u in ipairs(NS.Schema.CAST_UNITS or {}) do
                    if rec.driver.unit == u then ok = true break end
                end
                if not ok then rec.driver.unit = "player" end
            end
            -- a text element: its source and the fields that source reads
            if rec.barKind == "text" then Store.CleanText(rec.driver) end
            if rec.barKind == "texture" then Store.CleanTexture(rec.driver) end
            if rec.barKind == "wheel" then Store.CleanWheel(rec) end
        end
        if rec.type == "icon" and rec.kind == "timer" then
            rec.driver = rec.driver or {}
            Store.CleanCustom(rec.driver, false)
        end
        -- gpos is an icon's persistent (row, col) in its group's static
        -- grid; anything malformed auto-places on the next render.
        if rec.gpos then
            local r0, c0 = tonumber(rec.gpos.row), tonumber(rec.gpos.col)
            if r0 and c0 and r0 >= 0 and c0 >= 0 then
                rec.gpos.row = math.floor(r0)
                rec.gpos.col = math.floor(c0)
            else
                rec.gpos = nil
            end
        end
        if rec.members then
            local clean = {}
            for _, mid in ipairs(rec.members) do
                if DB.records[mid] then clean[#clean + 1] = mid end
            end
            rec.members = clean
        end
        -- Folds a group's slotSize (square px) into iconSize, which uses the
        -- same 36-base unit.
        if rec.type == "group" and rec.o.arrangement and rec.o.arrangement.slotSize then
            if rec.o.arrangement.iconSize == nil then
                rec.o.arrangement.iconSize = rec.o.arrangement.slotSize
            end
            rec.o.arrangement.slotSize = nil
        end
        -- Folds "Only show icons on cooldown" into "Icons drop out when",
        -- before the unknown-field strip below drops the retired key.
        if rec.type == "group" and rec.o.arrangement then
            FoldDynamicCooldowns(rec.o.arrangement)
        end
        -- Folds a bar's group-only anchor keys into the anchor* fields
        -- AD_Anchor reads. It runs before the unknown-field strip below,
        -- which would drop them and leave every anchored bar free.
        if rec.type == "bar" and rec.o and rec.o.anchor then
            local a = rec.o.anchor
            if a.toGroupId ~= nil then
                if a.toGroupId ~= 0 then
                    a.anchorEnabled = true
                    a.anchorTargetKind = "group"
                    a.anchorTargetId = a.toGroupId
                end
                a.toGroupId = nil
            end
            local moved = { point = "anchorSrcPoint", relPoint = "anchorDstPoint",
                offsetX = "anchorOffsetX", offsetY = "anchorOffsetY",
                matchWidth = "anchorMatchWidth",
                matchWidthAdjust = "anchorMatchWidthAdjust" }
            for from, to in pairs(moved) do
                if a[from] ~= nil then
                    if a[to] == nil then a[to] = a[from] end
                    a[from] = nil
                end
            end
        end
        -- These fold before the strip below drops the retired keys they read.
        FoldHideWhen(rec)
        FoldBarMarks(rec)
        FoldResFormat(rec)
        FoldAuraLabels(rec)
        FoldDurationAbbrev(rec)
        FoldGCDSwipe(rec)
        Schema.FoldUnitAuraCap(rec)
        -- A record from before every offset default went to 0 keeps its
        -- look: all of them once, then an import from an older string (it
        -- carries its v; a new record has none until this stamp).
        if (rec.v or 0) < 3 and (not DB.offsetsZero or rec.v ~= nil) then Store.KeepOldOffsets(rec) end
        -- The same for the color bands that became a count (v 4).
        if (rec.v or 0) < 4 and (not DB.bandCounts or rec.v ~= nil) then Store.KeepOldBands(rec) end
        -- Per-record schema version that versioned folds key off; a new one
        -- bumps it and runs before this stamp.
        rec.v = 4
        CleanWho(rec)
        if NS.Conditions then NS.Conditions.Normalize(rec) end
        -- Only a layout carries looks for the things inside it.
        if rec.type == "layout" then CleanLayoutValues(rec) else rec.inh = nil end
        local family = Store.FamilyOf(rec)
        if family then
            local fam = Schema[family]
            for section, values in pairs(rec.o) do
                local sec = fam[section]
                if not sec then
                    rec.o[section] = nil
                else
                    for field, v in pairs(values) do
                        local def = sec.fields and sec.fields[field]
                        if not def then
                            values[field] = nil
                        else
                            values[field] = CleanValue(def, v)
                        end
                    end
                    if next(values) == nil then rec.o[section] = nil end
                end
            end
        end
    end
    -- a custom item's saved runtime state goes with its record
    if type(DB.runtime) == "table" then
        for _, perChar in pairs(DB.runtime) do
            if type(perChar) == "table" then
                for id in pairs(perChar) do
                    if not DB.records[id] then perChar[id] = nil end
                end
            end
        end
    end
    DB.offsetsZero = true
    DB.bandCounts = true
    EnsureUids()
end

-- Identity

local function NewId()
    DB.nextId = DB.nextId + 1
    return DB.nextId
end


function Store.Get(id) return id and DB.records[id] or nil end

function Store.FamilyOf(rec)
    if rec.type == "icon" then return "icon" end
    if rec.type == "group" then return "iconGroup" end
    if rec.type == "layout" then return "layout" end
    if rec.type == "bar" then return "bar" end
    if rec.type == "reminder" then return "reminder" end
end

function Store.KindOf(rec)
    if rec.type == "icon" or rec.type == "reminder" then return rec.kind end
    if rec.type == "group" then return rec.groupKind end
    if rec.type == "bar" then return rec.barKind end
end

-- familyKey buckets newDefaults per kind where kinds differ
local function FamilyKey(rec)
    local kind = Store.KindOf(rec)
    return Store.FamilyOf(rec) .. (kind and (":" .. kind) or "")
end

-- Layout tier: a layout's inh[family][section][field] holds the looks its
-- icons, groups and bars follow wherever they set nothing of their own. Only
-- fields Schema.Inherits allows get there (SetLayoutValue refuses the rest,
-- Normalize drops them). A grouped icon follows its group's layout.
local FAMILY_OF_TYPE = { icon = "icon", group = "iconGroup", bar = "bar" }
local TYPE_OF_FAMILY = { icon = "icon", iconGroup = "group", bar = "bar" }

-- the looks `rec`'s layout sets for its family, or nil (the hot path:
-- Resolve asks this for every value an item does not set itself)
local function InhOf(rec)
    local lid = rec.layoutId
    if lid == nil then
        local gid = rec.groupId
        if gid == nil then return nil end
        local g = DB.records[gid]
        lid = g and g.layoutId
        if lid == nil then return nil end
    end
    local lay = DB.records[lid]
    local inh = lay and lay.inh
    return inh and inh[FAMILY_OF_TYPE[rec.type]]
end

-- Writes each old offset default (Schema.OLD_OFFSETS) a record relied on as
-- its own value, so it looks as it did. Not a bar text's X along an outer top
-- or bottom edge: that old inset was the misalignment being fixed. An anchor
-- offset only while anchored. A value set anywhere (the record, its layout, a
-- saved default) is left alone.
local OUTER_EDGE = { OUTERTOP = true, OUTERBOTTOM = true, OUTERTOPLEFT = true, OUTERTOPRIGHT = true,
    OUTERBOTTOMLEFT = true, OUTERBOTTOMRIGHT = true }
function Store.KeepOldOffsets(rec)
    if rec.type ~= "icon" and rec.type ~= "bar" then return end
    local family = Store.FamilyOf(rec)
    local list, fam = Schema.OLD_OFFSETS[family], Schema[family]
    if not (list and fam and rec.o) then return end
    local inh, nd = InhOf(rec), DB.newDefaults and DB.newDefaults[FamilyKey(rec)]
    local kind = Store.KindOf(rec)
    for _, e in ipairs(list) do
        local section, field = e[1], e[2]
        local sec = fam[section]
        local def = sec and sec.fields[field]
        local own = rec.o[section]
        local set = (own and own[field] ~= nil) or (inh and inh[section] and inh[section][field] ~= nil)
            or (nd and nd[section] and nd[section][field] ~= nil)
        local keep = def ~= nil and not set and Schema.Applies(def, sec, kind, rec.barMode)
        if keep and e[4] and OUTER_EDGE[Store.Resolve(rec, section, e[4])] then keep = false end
        if keep and e[5] and Store.Resolve(rec, section, e[5]) ~= true then keep = false end
        if keep then
            rec.o[section] = own or {}
            rec.o[section][field] = e[3]
        end
    end
end

-- Color bands became a count (one band when switched on, "+ Add band" for
-- more) and some band defaults moved (Schema.OLD_BANDS). A record
-- that colored before keeps what it showed: its count (the old default, or
-- every band whose value was above 0) and each shown band's old value and
-- color where nothing was set. Only the record is written; a count set
-- anywhere (record, layout, saved default) is left alone.
local function SameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for i = 1, 4 do
        if (a[i] or 1) ~= (b[i] or 1) then return false end
    end
    return true
end
function Store.KeepOldBands(rec)
    if rec.type ~= "icon" and rec.type ~= "bar" then return end
    local family = Store.FamilyOf(rec)
    local list, fam = Schema.OLD_BANDS and Schema.OLD_BANDS[family], Schema[family]
    if not (list and fam and rec.o) then return end
    local inh, nd = InhOf(rec), DB.newDefaults and DB.newDefaults[FamilyKey(rec)]
    local kind = Store.KindOf(rec)
    -- a value set on the record, its layout or a saved default, else nil
    local function SetVal(section, field)
        local t = rec.o[section]
        if t and t[field] ~= nil then return t[field] end
        t = inh and inh[section]
        if t and t[field] ~= nil then return t[field] end
        t = nd and nd[section]
        if t and t[field] ~= nil then return t[field] end
    end
    local function Put(section, field, v)
        rec.o[section] = rec.o[section] or {}
        rec.o[section][field] = v
    end
    for _, b in ipairs(list) do
        local section = b.section
        local sec = fam[section]
        local cdef = sec and sec.fields[b.count]
        if cdef and Schema.Applies(cdef, sec, kind, rec.barMode)
            and Store.Resolve(rec, section, b.toggle) == true and SetVal(section, b.count) == nil then
            local n = b.oldCount
            if not n then
                n = 0
                for i = 1, 3 do
                    local v = SetVal(section, b.value:format(i))
                    if v == nil then v = b.vals[i] end
                    if (tonumber(v) or 0) > 0 then n = i end
                end
                -- the shown bands keep their old defaults where nothing was set
                for i = 1, n do
                    for _, e in ipairs({ { b.value:format(i), b.vals[i] }, { b.color:format(i), b.cols[i] } }) do
                        local def = sec.fields[e[1]]
                        if def and SetVal(section, e[1]) == nil and not SameValue(def.d, e[2]) then
                            Put(section, e[1], type(e[2]) == "table" and { e[2][1], e[2][2], e[2][3], e[2][4] } or e[2])
                        end
                    end
                end
            end
            if n > 0 and n ~= cdef.d then Put(section, b.count, n) end
        end
    end
end

-- the layout whose looks `rec` follows (nil for a layout itself)
function Store.LayoutOf(rec)
    if not rec or rec.type == "layout" or rec._adLayoutTier then return nil end
    local lid = rec.layoutId
    if lid == nil and rec.groupId then
        local g = DB.records[rec.groupId]
        lid = g and g.layoutId
    end
    local lay = lid and DB.records[lid]
    if lay and lay.type == "layout" then return lay end
end

-- Resolution: record -> layout -> newDefaults -> schema default

function Store.Resolve(rec, section, field)
    local o = rec.o[section]
    if o and o[field] ~= nil then return o[field] end
    -- A reminder follows its group field by field: what it leaves unset reads
    -- the group's value, live, so SetOverride keeps it sparse against that.
    if rec.type == "reminder" then
        local g = DB.records[rec.groupId]
        local gs = g and g.type == "group" and Schema.iconGroup[section]
        if gs and gs.fields[field] then return Store.Resolve(g, section, field) end
    end
    local li = InhOf(rec)
    li = li and li[section]
    if li and li[field] ~= nil then return li[field] end
    local nd = DB.newDefaults[FamilyKey(rec)]
    nd = nd and nd[section]
    if nd and nd[field] ~= nil then return nd[field] end
    local fam = Schema[Store.FamilyOf(rec)]
    local def = fam and fam[section] and fam[section].fields[field]
    -- Per-kind default (`dk = { kind = value }`), e.g. a swing bar fills while
    -- the other timed bars drain. It sits after the saved default and before
    -- the plain one, so a hand-set value wins and SetOverride, which compares
    -- against this, keeps the record sparse.
    if def and def.dk then
        local v = def.dk[Store.KindOf(rec)]
        if v ~= nil then return v end
    end
    -- Per-unit default (`du = { unit = value }`, on rec.driver.unit), same
    -- place and rules as dk: a party member's health bar starts clickable.
    if def and def.du then
        local d = rec.driver
        local v = d and d.unit and def.du[d.unit]
        if v ~= nil then return v end
    end
    return def and def.d
end

function Store.SetOverride(rec, section, field, value)
    -- the layout editor's rows write through a proxy (Store.LayoutProxy):
    -- the value lands in the layout, for everything inside it
    if rec._adLayoutTier then
        Store.SetLayoutValue(rec._adLayout, rec._adFamily, section, field, value)
        return
    end
    -- a multi proxy (Store.MultiProxy): the write lands on every record of
    -- the selection the field applies to, each through its own SetOverride,
    -- so records stay sparse and Dirty fires once per record; a table value
    -- is copied per record, so no two records share one colour
    if rec._adMulti then
        for _, id in ipairs(rec._adIds) do
            local r = DB.records[id]
            if r and Store.MultiTakes(rec, r, section, field) then
                local v = value
                if type(v) == "table" then
                    v = {}
                    for k, x in pairs(value) do v[k] = x end
                end
                Store.SetOverride(r, section, field, v)
            end
        end
        return
    end
    rec.o[section] = rec.o[section] or {}
    -- storing the resolved-default value is a no-op: keep the record sparse
    local without = rec.o[section][field]
    rec.o[section][field] = nil
    local base = Store.Resolve(rec, section, field)
    if value == base then
        if next(rec.o[section]) == nil then rec.o[section] = nil end
    else
        rec.o[section] = rec.o[section] or {}
        rec.o[section][field] = value
    end
    if without ~= value then Store.Dirty("style", rec.id) end
end

function Store.ClearSection(rec, section)
    if rec.o[section] then
        rec.o[section] = nil
        Store.Dirty("style", rec.id)
    end
end

-- Standing bars: a bar stands when taller than wide. That is derived, never
-- stored, so it cannot drift or be copied onto a bar without its size.
function Store.BarStanding(rec)
    local w = Store.Resolve(rec, "size", "width") or 0
    local h = Store.Resolve(rec, "size", "height") or 0
    return h > w
end

-- Stands a bar up or lays it down: width and height swap, a side icon moves to
-- the matching end (a vertical fill starts at the bottom, a horizontal one at
-- the left: LEFT <-> BOTTOM, RIGHT <-> TOP), and the gradient and texture turn.
-- No-op if it has that shape already or is a pips bar (cells size themselves).
function Store.SetBarStanding(rec, stand)
    if not rec or rec.type ~= "bar" then return end
    stand = stand == true
    if Store.BarStanding(rec) == stand then return end
    if rec.barKind == "resource" and Store.Resolve(rec, "resource", "style") == "pips" then return end
    local w = Store.Resolve(rec, "size", "width")
    local h = Store.Resolve(rec, "size", "height")
    Store.SetOverride(rec, "size", "width", h)
    Store.SetOverride(rec, "size", "height", w)
    if Schema.Applies(nil, Schema.bar.icon, Store.KindOf(rec), rec.barMode) then
        local turn = stand and { LEFT = "BOTTOM", RIGHT = "TOP" } or { BOTTOM = "LEFT", TOP = "RIGHT" }
        local side = Store.Resolve(rec, "icon", "iconSide")
        if side and turn[side] then Store.SetOverride(rec, "icon", "iconSide", turn[side]) end
    end
    local gd = Store.Resolve(rec, "fill", "gradientDir")
    Store.SetOverride(rec, "fill", "gradientDir", gd == "HORIZONTAL" and "VERTICAL" or "HORIZONTAL")
    Store.SetOverride(rec, "fill", "rotateTexture", Store.Resolve(rec, "fill", "rotateTexture") ~= true)
end

-- Mouse tiers: an icon frame's mouse behavior is the icon's own tri-state, then
-- its group's, its layout's, then the two addon settings. "inherit" (the
-- default everywhere) defers to the tier above.
local function MouseTri(rec, field)
    if not rec then return nil end
    local v = Store.Resolve(rec, "mouse", field)
    if v == "on" then return true end
    if v == "off" then return false end
    return nil
end

function Store.MouseFor(rec)
    local grp = rec.groupId and DB.records[rec.groupId] or nil
    local lid = rec.layoutId or (grp and grp.layoutId)
    local lay = lid and DB.records[lid] or nil
    local tips = MouseTri(rec, "showTooltip")
    if tips == nil then tips = MouseTri(grp, "showTooltip") end
    if tips == nil then tips = MouseTri(lay, "showTooltip") end
    if tips == nil then tips = Store.GetSetting("showTooltips") ~= false end
    local thru = MouseTri(rec, "clickThrough")
    if thru == nil then thru = MouseTri(grp, "clickThrough") end
    if thru == nil then thru = MouseTri(lay, "clickThrough") end
    if thru == nil then thru = Store.GetSetting("clickThrough") ~= false end
    return tips, thru
end

-- Push model

-- Every push, save, reset and forget takes `fields`, the fields its sub-panel
-- shows, so a push never drags a neighbouring sub-panel's rows along (two
-- blocks can share one schema section: Background and Border both live in a
-- bar's `look`). nil means the whole section.
local function FieldList(sec, fields)
    if fields then return fields end
    local list = {}
    for field in pairs(sec.fields) do list[#list + 1] = field end
    return list
end

-- Copies this record's resolved `fields` of `section` onto every target they
-- apply to (by kind and mode). Returns how many targets took at least one.
local function PushInto(rec, section, targets, fields)
    local family = Store.FamilyOf(rec)
    local sec = Schema[family][section]
    if not (sec and sec.push) then return 0 end
    local list = FieldList(sec, fields)
    local touched = 0
    for _, target in ipairs(targets) do
        if target ~= rec and Store.FamilyOf(target) == family
            and Schema.Applies(nil, sec, Store.KindOf(target), target.barMode) then
            local hit = false
            for _, field in ipairs(list) do
                local def = sec.fields[field]
                if def and Schema.Applies(def, sec, Store.KindOf(target), target.barMode) then
                    Store.SetOverride(target, section, field, Store.Resolve(rec, section, field))
                    hit = true
                end
            end
            if hit then touched = touched + 1 end
        end
    end
    if touched > 0 then Store.Dirty("style") end
    return touched
end

-- ... onto every record of the family (the [Push to All] button)
function Store.PushToAll(rec, section, fields)
    local targets = {}
    for _, target in pairs(DB.records) do targets[#targets + 1] = target end
    return PushInto(rec, section, targets, fields)
end

-- ... onto the given record ids only (the [Push to v] pick)
function Store.PushTo(rec, section, ids, fields)
    local targets = {}
    for _, id in ipairs(ids or {}) do
        local t = DB.records[id]
        if t then targets[#targets + 1] = t end
    end
    return PushInto(rec, section, targets, fields)
end

-- Saves this record's resolved `fields` as its family key's new-record defaults.
-- nil rebuilds the whole section's bucket; a list merges into it.
function Store.SaveAsDefault(rec, section, fields)
    local family = Store.FamilyOf(rec)
    local sec = Schema[family][section]
    if not (sec and sec.push) then return end
    local key = FamilyKey(rec)
    DB.newDefaults[key] = DB.newDefaults[key] or {}
    local bucket = fields and (DB.newDefaults[key][section] or {}) or {}
    for _, field in ipairs(FieldList(sec, fields)) do
        if sec.fields[field] then
            bucket[field] = Store.Resolve(rec, section, field)
        end
    end
    DB.newDefaults[key][section] = bucket
end

-- this record's `fields` back to the resolved defaults (a saved default
-- still applies; the addon default when there is none) - the [Reset] button
function Store.ResetSection(rec, section, fields)
    local o = rec.o[section]
    if not o then return false end
    local family = Store.FamilyOf(rec)
    local sec = Schema[family] and Schema[family][section]
    if not sec then return false end
    local changed = false
    for _, field in ipairs(FieldList(sec, fields)) do
        if o[field] ~= nil then
            o[field] = nil
            changed = true
        end
    end
    if next(o) == nil then rec.o[section] = nil end
    if changed then Store.Dirty("style", rec.id) end
    return changed
end

-- Drops the saved default for `fields`, so new records get the addon defaults.
function Store.ForgetDefault(rec, section, fields)
    local nd = DB.newDefaults[FamilyKey(rec)]
    local bucket = nd and nd[section]
    if not bucket then return false end
    local sec = Schema[Store.FamilyOf(rec)][section]
    if not sec then return false end
    local changed = false
    for _, field in ipairs(FieldList(sec, fields)) do
        if bucket[field] ~= nil then
            bucket[field] = nil
            changed = true
        end
    end
    if next(bucket) == nil then nd[section] = nil end
    return changed
end

-- True when any of these rows has a saved default (gates the Forget button).
function Store.HasDefault(rec, section, fields)
    local nd = DB.newDefaults[FamilyKey(rec)]
    local bucket = nd and nd[section]
    if not bucket then return false end
    local sec = Schema[Store.FamilyOf(rec)][section]
    if not sec then return false end
    for _, field in ipairs(FieldList(sec, fields)) do
        if bucket[field] ~= nil then return true end
    end
    return false
end

-- Layout tier: writing, counting, resetting

-- What every item of `family` falls back to without a layout value, when that
-- is one value for all of them (no per-kind default, no saved default for any
-- kind). Storing exactly that changes nothing, so it stays unstored.
local function LayoutBase(family, section, field, def)
    if def.dk or def.du then return nil, false end
    for key, bucket in pairs(DB.newDefaults) do
        if key == family or key:sub(1, #family + 1) == family .. ":" then
            local b = bucket[section]
            if b and b[field] ~= nil then return nil, false end
        end
    end
    return def.d, true
end

-- Sets (nil drops) one look the layout hands to everything inside it; only
-- fields that inherit. Restyles every item of the layout.
function Store.SetLayoutValue(layout, family, section, field, value)
    if not (layout and layout.type == "layout" and LAYOUT_FAMILIES[family]) then return false end
    local sec = Schema[family] and Schema[family][section]
    local def = sec and sec.fields[field]
    if not (def and Schema.Inherits(def, sec)) then return false end
    -- the family table is never pruned here: the editor's proxy reads it
    layout.inh = layout.inh or {}
    layout.inh[family] = layout.inh[family] or {}
    local fi = layout.inh[family]
    local vals = fi[section] or {}
    local old = vals[field]
    local base, uniform = LayoutBase(family, section, field, def)
    if value == nil or (uniform and value == base) then
        vals[field] = nil
    else
        vals[field] = value
    end
    fi[section] = (next(vals) ~= nil) and vals or nil
    if old ~= vals[field] then Store.Dirty("style") end
    return true
end

function Store.LayoutValue(layout, family, section, field)
    local fi = layout and layout.inh and layout.inh[family]
    local vals = fi and fi[section]
    if vals then return vals[field] end
end

-- Editor proxy: a stand-in record whose overrides are the layout's values for
-- one family, so the item editors' generic rows can edit a layout (SetOverride
-- routes its writes here). .o re-points on every call, so a Normalize that
-- pruned the table never leaves a stale one behind.
local proxies = setmetatable({}, { __mode = "k" })
function Store.LayoutProxy(layout, family)
    if not (layout and layout.type == "layout" and LAYOUT_FAMILIES[family]) then return nil end
    layout.inh = layout.inh or {}
    layout.inh[family] = layout.inh[family] or {}
    local byFam = proxies[layout]
    if not byFam then
        byFam = {}
        proxies[layout] = byFam
    end
    local px = byFam[family]
    if not px then
        px = { type = TYPE_OF_FAMILY[family], _adLayoutTier = true, _adLayout = layout,
            _adFamily = family, c = {} }
        byFam[family] = px
    end
    px.o = layout.inh[family]
    return px
end

-- Editor proxy for several records at once (UI\AD_MultiSelect.lua's Edit
-- together): reads are the first record's, a write lands on every record the
-- field applies to (SetOverride). One table, its fields re-pointed on every
-- call, so the rows' ctx() allocates nothing. applies(rec, section, field,
-- def): the caller's row test; without one, the schema's kind gate.
local multiProxy = { _adMulti = true }
function Store.MultiProxy(ids, applies)
    local first = ids and DB.records[ids[1]]
    if not first then return nil end
    local px = multiProxy
    px._adIds, px._adApplies = ids, applies
    px.type, px.kind, px.barKind, px.barMode = first.type, first.kind, first.barKind, first.barMode
    px.groupKind, px.layoutId, px.groupId = first.groupKind, first.layoutId, first.groupId
    px.o, px.c, px.driver = first.o, first.c, first.driver
    return px
end

-- Whether record `r` takes a write of `field` made through a multi proxy.
function Store.MultiTakes(px, r, section, field)
    if Store.FamilyOf(r) ~= Store.FamilyOf(px) then return false end
    local fam = Schema[Store.FamilyOf(r)]
    local sec = fam and fam[section]
    local def = sec and sec.fields[field]
    if not def then return false end
    if px._adApplies then return px._adApplies(r, section, field, def) == true end
    return Schema.Applies(def, sec, Store.KindOf(r), r.barMode)
end

-- the rows of `fields` (nil = the whole section) the layout sets
local function LayoutSetFields(layout, family, section, fields)
    local out = {}
    local sec = Schema[family] and Schema[family][section]
    local fi = layout and layout.inh and layout.inh[family]
    local vals = sec and fi and fi[section]
    if not vals then return out, sec end
    for _, f in ipairs(FieldList(sec, fields)) do
        if vals[f] ~= nil then out[#out + 1] = f end
    end
    return out, sec
end

-- Every item of `family` that follows `layout`, grouped icons included.
function Store.LayoutItems(layout, family)
    local out = {}
    if not (layout and layout.type == "layout") then return out end
    local groups, freeIcons, bars = Store.ChildrenOf(layout)
    if family == "icon" then
        for _, ic in ipairs(freeIcons) do out[#out + 1] = ic end
        for _, g in ipairs(groups) do
            for _, ic in ipairs(Store.IconsOf(g)) do out[#out + 1] = ic end
        end
    elseif family == "iconGroup" then
        for _, g in ipairs(groups) do out[#out + 1] = g end
    elseif family == "bar" then
        for _, b in ipairs(bars) do out[#out + 1] = b end
    end
    return out
end

function Store.LayoutSetCount(layout, family, section, fields)
    return #(LayoutSetFields(layout, family, section, fields))
end

-- For the count warning: how many of the layout's items keep their own value
-- for a row the layout sets, so they do not follow it.
function Store.LayoutOwnCount(layout, family, section, fields)
    local list, sec = LayoutSetFields(layout, family, section, fields)
    if #list == 0 then return 0 end
    local n = 0
    for _, item in ipairs(Store.LayoutItems(layout, family)) do
        local o = item.o[section]
        if o then
            for _, fld in ipairs(list) do
                if o[fld] ~= nil and Schema.Applies(sec.fields[fld], sec, Store.KindOf(item), item.barMode) then
                    n = n + 1
                    break
                end
            end
        end
    end
    return n
end

-- ... and make them follow: drop their own values for the rows the layout
-- sets. Returns how many items changed.
function Store.FollowLayout(layout, family, section, fields)
    local list = LayoutSetFields(layout, family, section, fields)
    if #list == 0 then return 0 end
    local n = 0
    for _, item in ipairs(Store.LayoutItems(layout, family)) do
        local o = item.o[section]
        if o then
            local hit = false
            for _, fld in ipairs(list) do
                if o[fld] ~= nil then
                    o[fld] = nil
                    hit = true
                end
            end
            if next(o) == nil then item.o[section] = nil end
            if hit then n = n + 1 end
        end
    end
    if n > 0 then Store.Dirty("style") end
    return n
end

-- the layout stops setting these rows (its items fall back to their own
-- defaults). Returns true when anything was set.
function Store.ClearLayoutValues(layout, family, section, fields)
    local list = LayoutSetFields(layout, family, section, fields)
    if #list == 0 then return false end
    local vals = layout.inh[family][section]
    for _, fld in ipairs(list) do vals[fld] = nil end
    if next(vals) == nil then layout.inh[family][section] = nil end
    Store.Dirty("style")
    return true
end

-- An item's view: its layout, how many of these rows (that apply to it) the
-- layout sets, and how many of those the item changes here.
function Store.LayoutStatus(rec, section, fields)
    local lay = Store.LayoutOf(rec)
    if not lay then return nil, 0, 0 end
    local family = Store.FamilyOf(rec)
    local list, sec = LayoutSetFields(lay, family, section, fields)
    local o = rec.o[section]
    local setN, ownN = 0, 0
    for _, fld in ipairs(list) do
        if Schema.Applies(sec.fields[fld], sec, Store.KindOf(rec), rec.barMode) then
            setN = setN + 1
            if o and o[fld] ~= nil then ownN = ownN + 1 end
        end
    end
    return lay, setN, ownN
end

-- the item's "Reset to layout": drop its own values for the rows its layout
-- sets (a row the layout leaves alone keeps the item's value)
function Store.ResetToLayout(rec, section, fields)
    local lay = Store.LayoutOf(rec)
    local o = rec and rec.o[section]
    if not (lay and o) then return false end
    local list = LayoutSetFields(lay, Store.FamilyOf(rec), section, fields)
    local changed = false
    for _, fld in ipairs(list) do
        if o[fld] ~= nil then
            o[fld] = nil
            changed = true
        end
    end
    if next(o) == nil then rec.o[section] = nil end
    if changed then Store.Dirty("style", rec.id) end
    return changed
end

-- Load conditions (the sharing model)

-- A required node is met when taken and, when the record names a choice, when
-- that entry is the active one. Negated, the same test serves the excluded set.
local function TalentMet(c, cat, nodeID)
    if not cat.IsTaken(nodeID) then return false end
    local want = c.talentEntry and c.talentEntry[nodeID]
    if want and cat.ActiveEntry then return cat.ActiveEntry(nodeID) == want end
    return true
end

-- Known-spell gates: "Only load once learned" (driver.onlyKnown, a Tracking
-- toggle) and the Known Spell rule (c.knownMode / knownSpell / knownRank, Load
-- Conditions). One spellbook read: true / false, or nil when the answer is
-- secret. The spellbook API carries no secret return on either client; the
-- pet's book counts too.
local function BookHas(id)
    local function Answer(v)
        if issecretvalue and issecretvalue(v) then return nil end
        return v == true
    end
    local SB = C_SpellBook
    if not (SB and SB.IsSpellKnown) then
        if IsPlayerSpell then return Answer(IsPlayerSpell(id)) end
        return true
    end
    local bank = Enum and Enum.SpellBookSpellBank
    local a = Answer(SB.IsSpellKnown(id, bank and bank.Player))
    if a ~= false then return a end
    if SB.IsSpellInSpellBook then
        a = Answer(SB.IsSpellInSpellBook(id, bank and bank.Player, true))
        if a ~= false then return a end
    end
    if bank and bank.Pet then return Answer(SB.IsSpellKnown(id, bank.Pet)) end
    return false
end

local function PlainNum(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end

-- Whether the player knows a spell: true / false, or nil when it cannot be
-- told (a secret or malformed ID, a secret read never answered before), which
-- never gates. On ranked realms any rank counts, found by its name, unless
-- `exact` (this rank: this spell ID); a replacement form counts through its
-- base. The last answer per spell is kept: a secret read reuses it, and
-- Store.KnownChanged compares with it.
Store.knownSeen, Store.knownExactSeen = {}, {}
function Store.KnowsSpell(sid, exact)
    sid = PlainNum(sid)
    if not sid then return nil end
    local known = BookHas(sid)
    local CS = C_Spell
    if known == false and not exact then
        if NS.IsForever == true and CS and CS.GetSpellName and CS.GetSpellIDForSpellIdentifier then
            local nm = CS.GetSpellName(sid)
            if not (issecretvalue and issecretvalue(nm)) and type(nm) == "string" and nm ~= "" then
                local rid = PlainNum(CS.GetSpellIDForSpellIdentifier(nm))
                if rid and rid ~= sid then known = BookHas(rid) end
            end
        end
        if known == false and CS and CS.GetBaseSpell then
            local base = PlainNum(CS.GetBaseSpell(sid))
            if base and base ~= sid then known = BookHas(base) end
        end
    end
    local seen = exact and Store.knownExactSeen or Store.knownSeen
    if known == nil then return seen[sid] end
    seen[sid] = known
    return known
end

-- SPELLS_CHANGED (AD_Conditions): true when a spell some record waits on has a
-- new answer, so the load pass runs again. Re-reading refreshes the answers.
function Store.KnownChanged()
    local changed = false
    for sid, was in pairs(Store.knownSeen) do
        if Store.KnowsSpell(sid) ~= was then changed = true end
    end
    for sid, was in pairs(Store.knownExactSeen) do
        if Store.KnowsSpell(sid, true) ~= was then changed = true end
    end
    return changed
end

-- The Known Spell rule's setters: "known" / "unknown" / nil, the spell, the
-- exact-rank switch. Each is a load pass.
function Store.SetKnownMode(rec, mode)
    if mode ~= "known" and mode ~= "unknown" then mode = nil end
    if rec.c.knownMode == mode then return end
    rec.c.knownMode = mode
    Store.Dirty("load")
end

function Store.SetKnownSpell(rec, id)
    id = tonumber(id)
    id = (id and id > 0) and math.floor(id) or nil
    if rec.c.knownSpell == id then return end
    rec.c.knownSpell = id
    Store.Dirty("load")
end

function Store.SetKnownRank(rec, on)
    on = (on == true) or nil
    if rec.c.knownRank == on then return end
    rec.c.knownRank = on
    Store.Dirty("load")
end

function Store.IsLoaded(rec)
    local c = rec.c
    if c.classes then
        local tag = ClassTag()
        if not (tag and c.classes[tag]) then return false end
    end
    if c.chars and not c.chars[CharKey()] then return false end
    -- faction (the conditions module caches the plain read; unknown = pass)
    if c.factions and NS.Conditions then
        local fac = NS.Conditions.PlayerFaction()
        if fac and not c.factions[fac] then return false end
    end
    -- Spec, role and hero talent are retail's; a spec-less client ignores them.
    -- All three change out of combat only, so releasing on a miss is safe.
    if not Specless() then
        if c.specs then
            local spec = Store.CurSpecID()
            if not (spec and c.specs[spec]) then return false end
        end
        if c.roles then
            local role = Store.CurSpecRole()
            if not (role and c.roles[role]) then return false end
        end
        if c.heroes then
            local hero = Store.CurHeroID()
            if not (hero and c.heroes[hero]) then return false end
        end
    end
    -- Talents: the build-level gate, and the only one that means anything on
    -- a spec-less client. "all" needs every required node taken and every
    -- excluded one absent; "any" needs one of either. Empty sets never gate.
    if (c.talents and next(c.talents)) or (c.talentsNot and next(c.talentsNot)) then
        local cat = NS.TalentCatalog
        if cat then
            local anyHit, allOK = false, true
            for nodeID in pairs(c.talents or {}) do
                if TalentMet(c, cat, nodeID) then anyHit = true else allOK = false end
            end
            for nodeID in pairs(c.talentsNot or {}) do
                if not TalentMet(c, cat, nodeID) then anyHit = true else allOK = false end
            end
            if (c.talentMode == "any" and not anyHit)
                or (c.talentMode ~= "any" and not allOK) then
                return false
            end
        end
    end
    -- Known spells: the Tracking toggle, then the Known Spell rule (any record).
    -- An answer that cannot be told never gates.
    local d = rec.driver
    if d and d.onlyKnown == true and d.spellID
        and Store.KnowsSpell(d.spellID, d.knownExact == true) == false then
        return false
    end
    local km = c.knownMode
    if (km == "known" or km == "unknown") and c.knownSpell then
        local has = Store.KnowsSpell(c.knownSpell, c.knownRank == true)
        if has ~= nil and has ~= (km == "known") then return false end
    end
    return true
end

-- Talent conditions

-- A node's state on a record: "req" (must have), "not" (must not have) or nil,
-- plus the choice entry the record names for it, if any.
function Store.TalentState(rec, nodeID)
    local c = rec.c
    local entry = c.talentEntry and c.talentEntry[nodeID]
    if c.talents and c.talents[nodeID] then return "req", entry end
    if c.talentsNot and c.talentsNot[nodeID] then return "not", entry end
    return nil, entry
end

local function SetWhoKey(c, list, nodeID, on)
    local set = c[list]
    if on then
        set = set or {}
        set[nodeID] = true
    elseif set then
        set[nodeID] = nil
    end
    if set and next(set) == nil then set = nil end
    c[list] = set
end

-- Writes a node's state; a node is never in both sets. entryID (a choice
-- node's option) rides along with a state and goes with it.
function Store.SetTalentState(rec, nodeID, state, entryID)
    local c = rec.c
    SetWhoKey(c, "talents", nodeID, state == "req")
    SetWhoKey(c, "talentsNot", nodeID, state == "not")
    if state and entryID then
        c.talentEntry = c.talentEntry or {}
        c.talentEntry[nodeID] = entryID
    elseif c.talentEntry then
        c.talentEntry[nodeID] = nil
        if next(c.talentEntry) == nil then c.talentEntry = nil end
    end
    Store.Dirty("load")
end

function Store.RemoveTalent(rec, nodeID)
    Store.SetTalentState(rec, nodeID, nil)
end

function Store.ToggleTalent(rec, nodeID)
    local state = Store.TalentState(rec, nodeID)
    Store.SetTalentState(rec, nodeID, (state ~= "req") and "req" or nil)
end

function Store.ClearTalents(rec)
    local c = rec.c
    if not (c.talents or c.talentsNot or c.talentEntry) then return end
    c.talents, c.talentsNot, c.talentEntry = nil, nil, nil
    Store.Dirty("load")
end

function Store.SetTalentMode(rec, mode)
    rec.c.talentMode = (mode == "any") and "any" or nil   -- "all" is the default
    Store.Dirty("load")
end

-- The chosen nodes, sorted by name, each with taken and known flags; an
-- excluded node carries excluded = true, a named choice its entry and name.
function Store.TalentList(rec)
    local out = {}
    local cat = NS.TalentCatalog
    local c = rec.c
    local function add(nodeID, excluded)
        local known = cat and cat.Known(nodeID)
        local entry = c.talentEntry and c.talentEntry[nodeID]
        local name = known and known.name or ("Talent " .. nodeID)
        local icon = known and known.icon or 134400
        local ei = entry and cat and cat.EntryInfo and cat.EntryInfo(nodeID, entry)
        if ei then
            if ei.name and ei.name ~= name then name = name .. ": " .. ei.name end
            icon = ei.icon or icon
        end
        local taken = cat and cat.IsTaken(nodeID) or false
        if taken and entry and cat.ActiveEntry then taken = cat.ActiveEntry(nodeID) == entry end
        out[#out + 1] = {
            nodeID = nodeID, name = name, icon = icon, taken = taken,
            known = known ~= nil, excluded = excluded or nil, entryID = entry,
        }
    end
    for nodeID in pairs(c.talents or {}) do add(nodeID, false) end
    for nodeID in pairs(c.talentsNot or {}) do
        if not (c.talents and c.talents[nodeID]) then add(nodeID, true) end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Role and hero talent conditions (retail). Both follow the matrix's rule:
-- every box checked is no restriction, the set materializes on the first
-- uncheck and collapses to nil when every box is back. An empty set is nowhere.

Store.ROLES = { "TANK", "HEALER", "DAMAGER" }

function Store.RoleOn(rec, role)
    local set = rec and rec.c and rec.c.roles
    if type(set) ~= "table" then return true end
    return set[role] == true
end

function Store.ToggleRole(rec, role)
    if not rec then return end
    local set, full = {}, true
    for _, r in ipairs(Store.ROLES) do
        if Store.RoleOn(rec, r) then set[r] = true end
    end
    if set[role] then set[role] = nil else set[role] = true end
    for _, r in ipairs(Store.ROLES) do
        if not set[r] then full = false end
    end
    rec.c.roles = (not full) and set or nil
    Store.Dirty("load")
end

-- The hero trees the set is measured against: the player's class's, from the
-- talent catalog ({ id, name, ... } each); none before the trees are known.
function Store.HeroTrees()
    local cat = NS.TalentCatalog
    return (cat and cat.HeroTrees and cat.HeroTrees()) or {}
end

function Store.HeroOn(rec, id)
    local set = rec and rec.c and rec.c.heroes
    if type(set) ~= "table" then return true end
    return set[id] == true
end

function Store.ToggleHero(rec, id)
    if not rec then return end
    local trees = Store.HeroTrees()
    local set, full = {}, true
    for _, t in ipairs(trees) do
        if Store.HeroOn(rec, t.id) then set[t.id] = true end
    end
    if set[id] then set[id] = nil else set[id] = true end
    for _, t in ipairs(trees) do
        if not set[t.id] then full = false end
    end
    rec.c.heroes = (not full) and set or nil
    Store.Dirty("load")
end

-- Class/spec load matrix: every class and its specs, for the load-conditions
-- UI and the toggle logic below.

-- Class IDs to walk. On WoW Forever they keep their retail numbers with gaps:
-- GetNumClasses() returns 9, but the classes are 1-5, 7-9 and 11: counting to
-- it misses Druid, and a class edit would stop the record loading for Druids.
-- Forever has C_SpecializationInfo.GetAllClassIDs() ({1,2,3,4,5,7,8,9,11});
-- retail lacks it, and there GetNumClasses() is the highest ID.
local function ClassIDs()
    local all = C_SpecializationInfo and C_SpecializationInfo.GetAllClassIDs
        and C_SpecializationInfo.GetAllClassIDs()
    if type(all) == "table" and #all > 0 then return all end
    local ids = {}
    for ci = 1, (GetNumClasses and GetNumClasses() or 0) do ids[#ids + 1] = ci end
    return ids
end

local classMatrix
function Store.ClassSpecMatrix()
    if classMatrix then return classMatrix end
    classMatrix = {}
    for _, ci in ipairs(ClassIDs()) do
        local name, tag, classID = GetClassInfo(ci)
        if name and tag and classID then
            local specs = {}
            -- the flavor decides the matrix's shape, never a spec count probe
            local SI = C_SpecializationInfo
            local n = 0
            if not Specless() and SI and SI.GetNumSpecializationsForClassID then
                n = SI.GetNumSpecializationsForClassID(classID) or 0
            end
            for si = 1, n do
                local sid, sname = GetSpecializationInfoForClassID(classID, si)
                if sid then
                    specs[#specs + 1] = { id = sid, name = sname or ("Spec " .. si) }
                end
            end
            classMatrix[#classMatrix + 1] =
                { classID = classID, tag = tag, name = name, specs = specs }
        end
    end
    return classMatrix
end

-- effective state = what the player experiences. No conditions = on
-- everywhere; a legacy c.classes gate reads as "all that class's specs".
local function EffSpecOn(rec, classTag, specID)
    local c = rec.c
    if c.classes and not c.classes[classTag] then return false end
    if c.specs then return c.specs[specID] == true end
    return true
end

-- Class-level effective state (spec-less realms): c.classes is the layer, and
-- a c.specs remnant from a retail import is ignored, matching IsLoaded.
local function EffClassOn(rec, classTag)
    local c = rec.c
    if c.classes then return c.classes[classTag] == true end
    return true
end

function Store.SpecConditionState(rec, classTag, specID)
    return EffSpecOn(rec, classTag, specID)
end

function Store.ClassConditionState(rec, classTag)
    if Specless() then
        local on = EffClassOn(rec, classTag)
        return on, on
    end
    local any, all = false, true
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if cls.tag == classTag then
            for _, sp in ipairs(cls.specs) do
                if EffSpecOn(rec, classTag, sp.id) then any = true else all = false end
            end
        end
    end
    return any, all
end

-- Writers materialize the effective set across every class, edit it, then
-- collapse a full set back to nil (everywhere). A legacy class layer folds
-- into the spec set on the first matrix write.
local function MaterializeSpecSet(rec)
    local set = {}
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        for _, sp in ipairs(cls.specs) do
            if EffSpecOn(rec, cls.tag, sp.id) then set[sp.id] = true end
        end
    end
    return set
end

local function WriteSpecSet(rec, set)
    -- with no class known there is no "every box" to be full of
    local matrix = Store.ClassSpecMatrix()
    local full = #matrix > 0
    for _, cls in ipairs(matrix) do
        for _, sp in ipairs(cls.specs) do
            if not set[sp.id] then full = false end
        end
    end
    rec.c.classes = nil
    -- a full set is no restriction: stored, it would leave out any spec added
    -- later and read as a list instead of Shared
    if full then rec.c.specs = nil else rec.c.specs = set end
    Store.Dirty("load")
end

-- Class-set twins of the spec writers, for spec-less realms. The first matrix
-- write folds any imported spec layer away (it is ignored here).
local function MaterializeClassSet(rec)
    local set = {}
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if EffClassOn(rec, cls.tag) then set[cls.tag] = true end
    end
    return set
end

local function WriteClassSet(rec, set)
    local matrix = Store.ClassSpecMatrix()
    local full = #matrix > 0
    for _, cls in ipairs(matrix) do
        if not set[cls.tag] then full = false end
    end
    rec.c.specs = nil
    if full then rec.c.classes = nil else rec.c.classes = set end
    Store.Dirty("load")
end

function Store.SetSpecCondition(rec, specID, on)
    local set = MaterializeSpecSet(rec)
    set[specID] = on and true or nil
    WriteSpecSet(rec, set)
end

-- Whole-matrix writer: true clears every restriction (everywhere); false
-- writes an explicit empty set (nowhere), so the user can then tick just
-- the classes or specs they want.
function Store.SetAllSpecs(rec, on)
    rec.c.classes = nil
    rec.c.specs = nil
    if not on then
        if Specless() then rec.c.classes = {} else rec.c.specs = {} end
    end
    Store.Dirty("load")
end

-- The boxes a record allows, as IsLoaded reads them, or nil for everywhere:
-- a spec-less client the class set itself, retail the effective spec boxes
-- (a legacy class layer folds in).
local function AllowedSet(rec)
    if Specless() then return rec.c.classes end
    if not (rec.c.classes or rec.c.specs) then return nil end
    return MaterializeSpecSet(rec)
end

-- A group's icons and reminders whose own class and spec boxes leave out
-- some the group allows: an import made on one class keeps its boxes on every
-- item, so ticking another class on the group alone does not load them there.
-- A group that loads everywhere leaves its items' own boxes alone.
function Store.ClassSpecStrays(group)
    local out = {}
    if not (group and group.type == "group" and group.c) then return out end
    local want = AllowedSet(group)
    if not want then return out end
    for _, rec in ipairs(Store.GroupMembers(group)) do
        local have = rec.c and AllowedSet(rec)
        if have then
            for k, on in pairs(want) do
                if on and not have[k] then
                    out[#out + 1] = rec
                    break
                end
            end
        end
    end
    return out
end

-- Gives each record the group's class and spec boxes: one copy, no link.
function Store.MatchClassSpecs(group, recs)
    local function Copy(t)
        if type(t) ~= "table" then return nil end
        local o = {}
        for k, v in pairs(t) do o[k] = v end
        return o
    end
    for _, rec in ipairs(recs or {}) do
        if rec.c then
            rec.c.classes = Copy(group.c.classes)
            rec.c.specs = Copy(group.c.specs)
        end
    end
    Store.Dirty("load")
end

function Store.SetClassSpecs(rec, classTag, on)
    if Specless() then
        local set = MaterializeClassSet(rec)
        set[classTag] = on and true or nil
        WriteClassSet(rec, set)
        return
    end
    local set = MaterializeSpecSet(rec)
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if cls.tag == classTag then
            for _, sp in ipairs(cls.specs) do
                set[sp.id] = on and true or nil
            end
        end
    end
    WriteSpecSet(rec, set)
end

-- derived badge text: no conditions = Shared; else the spec names
function Store.BadgeText(rec)
    local c = rec.c
    local parts = {}
    if c.classes then
        -- class sets are first-class on spec-less realms: name them
        local n = 0
        for _ in pairs(c.classes) do n = n + 1 end
        if n == 0 then
            parts[#parts + 1] = "nowhere"
        elseif n > 3 then
            parts[#parts + 1] = n .. " classes"
        else
            for tag in pairs(c.classes) do
                local nm
                for _, cls in ipairs(Store.ClassSpecMatrix()) do
                    if cls.tag == tag then nm = cls.name end
                end
                parts[#parts + 1] = nm or tag
            end
            table.sort(parts)
        end
    end
    if c.specs and Specless() then
        -- retail import remnant: ignored by IsLoaded here, so say nothing
    elseif c.specs then
        -- matrix sets can span many classes: compress long lists
        local n = 0
        for _ in pairs(c.specs) do n = n + 1 end
        if n == 0 then
            parts[#parts + 1] = "nowhere"
        elseif n > 4 then
            parts[#parts + 1] = n .. " specs"
        else
            local names = {}
            local byID = GetSpecializationInfoForSpecID or GetSpecializationInfoByID
            for specID in pairs(c.specs) do
                local name
                if byID then
                    local _, nm = byID(specID)
                    name = nm
                end
                names[#names + 1] = name or tostring(specID)
            end
            table.sort(names)
            for _, nm in ipairs(names) do parts[#parts + 1] = nm end
        end
    end
    -- role and hero sets are ignored on a spec-less client, like the specs
    if c.roles and not Specless() then
        local words = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
        local names = {}
        for role in pairs(c.roles) do names[#names + 1] = words[role] or role end
        table.sort(names)
        parts[#parts + 1] = (#names == 0) and "nowhere" or table.concat(names, ", ")
    end
    if c.heroes and not Specless() then
        local n, names = 0, {}
        local cat = NS.TalentCatalog
        for id in pairs(c.heroes) do
            n = n + 1
            local nm = cat and cat.HeroName and cat.HeroName(id)
            names[#names + 1] = nm or ("hero " .. id)
        end
        if n == 0 then
            parts[#parts + 1] = "nowhere"
        elseif n > 2 then
            parts[#parts + 1] = n .. " hero trees"
        else
            table.sort(names)
            parts[#parts + 1] = table.concat(names, ", ")
        end
    end
    if c.chars then parts[#parts + 1] = "chars" end
    if c.factions then
        local list = {}
        for fac in pairs(c.factions) do list[#list + 1] = fac end
        table.sort(list)
        parts[#parts + 1] = (#list == 0) and "nowhere" or table.concat(list, ", ")
    end
    if #parts == 0 then return "Shared", false end
    return table.concat(parts, ", "), true
end

function Store.ToggleCharCondition(rec)
    local c = rec.c
    local me = CharKey()
    if not c.chars then
        c.chars = { [me] = true }
    elseif c.chars[me] then
        c.chars = nil                    -- back to all characters
    else
        c.chars[me] = true
    end
    Store.Dirty("load")
end

-- Drops the whole character lock. A server rename or transfer orphans CharKey
-- snapshots, and an orphaned lock hides the record on every character; the
-- options panel offers this as the way out when it detects that state.
function Store.ClearCharCondition(rec)
    if rec.c.chars then
        rec.c.chars = nil
        Store.Dirty("load")
    end
end

-- Creating, moving and deleting records

-- Where a new thing appears: the screen centre in its parent's coordinates (a
-- layout's pos is from the screen centre; a group's, free icon's or bar's from
-- its layout's centre). No engine frame carries its own scale, so GetCenter
-- units match. Always the centre, even on top of another item: a new item
-- must be found where the player looks, never stepped down the screen. A
-- layout frame with no rect yet falls back to the layout's own centre.
local function CenterSpot(layoutId)
    local x, y = 0, 0
    if layoutId then
        local LE = NS.LayoutEngine
        local lf = LE and LE.GetLayoutFrame and LE.GetLayoutFrame(layoutId)
        if lf and lf.GetCenter then
            local ux, uy = UIParent:GetCenter()
            local lx, ly = lf:GetCenter()
            if ux and lx then
                x = math.floor(ux - lx + 0.5)
                y = math.floor(uy - ly + 0.5)
            end
        end
    end
    return x, y
end

function Store.NewLayout(name)
    local id = NewId()
    local sx, sy = CenterSpot(nil)
    DB.records[id] = {
        id = id, type = "layout",
        name = name or ("Layout " .. id),
        pos = { x = sx, y = sy },
        members = {}, o = {}, c = {},
    }
    Store.Dirty("tree")
    return DB.records[id]
end

-- The starter layout: three empty groups in a column under the character,
-- where cooldown rows usually sit. Offsets and icon sizes are for a screen
-- 1080 units tall and scale with this one, so the column lands in the same
-- place at any UI scale.
local STARTER_ROWS = {
    { name = "Cooldowns", kind = "cooldown", y = -275, size = 42 },
    { name = "Utility", kind = "cooldown", y = -320, size = 36 },
    { name = "Buffs", kind = "aura", y = -365, size = 32 },
}
-- the New Layout page draws the template's preview from these
Store.STARTER_ROWS = STARTER_ROWS

function Store.NewStarterLayout(name)
    local rec = Store.NewLayout(name or "Starter Layout")
    -- the screen centre exactly: the placement is the point of the template
    rec.pos = { x = 0, y = 0 }
    local h = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = 768 end
    local k = h / 1080
    for _, row in ipairs(STARTER_ROWS) do
        local g = Store.NewGroup(rec.id, row.name, row.kind)
        g.pos = { x = 0, y = math.floor(row.y * k + 0.5) }
        local px = math.floor(row.size * k + 0.5)
        Store.SetOverride(g, "arrangement", "iconWidth", px)
        Store.SetOverride(g, "arrangement", "iconHeight", px)
    end
    return rec
end

-- Creation default for NewIcon and NewBar: the new record loads only for its
-- creator's spec (class on spec-less realms, where a spec set could never
-- pass); the user widens it from Load Conditions. Groups and layouts stay
-- shared: only the leaves are locked.
local function ScopeToCreator(rec)
    local spec = (not Specless()) and Store.CurSpecID() or nil
    if spec then
        rec.c.specs = { [spec] = true }
        return
    end
    -- spec-less realms, and a retail starter spec no matrix box shows
    local tag = ClassTag()
    if tag then rec.c.classes = { [tag] = true } end
end

-- A creation-template value: the record gets it unless a saved default or its
-- layout's look sets that field; both win over the template.
local function TemplateSet(rec, section, field, value)
    local nd = DB.newDefaults[FamilyKey(rec)]
    if nd and nd[section] and nd[section][field] ~= nil then return end
    local li = InhOf(rec)
    if li and li[section] and li[section][field] ~= nil then return end
    rec.o[section] = rec.o[section] or {}
    rec.o[section][field] = value
end

-- ArcUI v1's pulse spot, 120 above the screen centre, measured from the
-- layout's centre as CenterSpot does (no step-down: it is the one spot).
local function PulseSpot(layoutId)
    local x, y = 0, 0
    local LE = NS.LayoutEngine
    local lf = LE and LE.GetLayoutFrame and LE.GetLayoutFrame(layoutId)
    if lf and lf.GetCenter then
        local ux, uy = UIParent:GetCenter()
        local lx, ly = lf:GetCenter()
        if ux and lx then
            x = math.floor(ux - lx + 0.5)
            y = math.floor(uy - ly + 0.5)
        end
    end
    return x, y + 120
end

function Store.NewGroup(layoutId, name, groupKind)
    local layout = Store.Get(layoutId)
    if not layout or layout.type ~= "layout" then return nil end
    local id = NewId()
    local kind = (groupKind == "aura" or groupKind == "reminder") and groupKind or "cooldown"
    local sx, sy
    if kind == "reminder" then
        sx, sy = PulseSpot(layoutId)
    else
        sx, sy = CenterSpot(layoutId)
    end
    local rec = {
        id = id, type = "group",
        name = name or ("Group " .. id),
        groupKind = kind,
        layoutId = layoutId,
        pos = { x = sx, y = sy },
        members = {}, o = {}, c = {},
    }
    DB.records[id] = rec
    -- v1's pulse window sat over the rest of the UI
    if kind == "reminder" then TemplateSet(rec, "frame", "strata", "HIGH") end
    layout.members[#layout.members + 1] = id
    Store.Dirty("tree")
    return rec
end

-- An aura group that shows every aura on one unit (Drivers\AD_DriverUnitAuras.lua)
-- instead of its own aura icons; the icons it had stay its members, undrawn.
function Store.ShowsAll(group)
    return group ~= nil and group.type == "group" and group.groupKind == "aura"
        and Store.Resolve(group, "unitAuras", "shows") == "unit"
end

-- Which icons a group takes: an aura group aura icons (none while it shows
-- every aura on a unit), a cooldown group any (aura icons sit in it as solid
-- slots), a reminder group none (its members are made for it: reminders by
-- Store.NewReminder, aura reminders by Store.NewAuraReminder; its row is no
-- grid, so nothing drags or moves in).
function Store.GroupTakes(group, kind)
    if not group then return false end
    if group.groupKind == "aura" then return kind == "aura" and not Store.ShowsAll(group) end
    if group.groupKind == "reminder" then return false end
    return true
end

-- A reminder group's reminders, in its member order.
function Store.RemindersOf(group)
    local out = {}
    for _, mid in ipairs(group.members or {}) do
        local rec = DB.records[mid]
        if rec and rec.type == "reminder" then out[#out + 1] = rec end
    end
    return out
end

-- A new trigger: ArcUI v1's (when ready, 3 seconds for the timed types) with
-- its sound off until picked, as every new option starts off. A weapon
-- enchant's starts on "when it's missing".
function Store.NewTrigger(kind)
    if kind == "enchant" then return { type = "enchant_missing", soundDisabled = true } end
    return { type = "when_ready", seconds = 3, soundDisabled = true }
end

-- A reminder made for a reminder group: kind "spell" or "item" and its ID, or
-- "enchant" and its hand ("main" or "off"). It loads for its creator's class
-- or spec, like a new icon, and starts with one trigger. Returns the record,
-- or nil (not a reminder group, no ID).
function Store.NewReminder(groupId, kind, id, name)
    local g = Store.Get(groupId)
    if not (g and g.type == "group" and g.groupKind == "reminder") then return nil end
    local driver
    if kind == "enchant" then
        local hand = (id == "off") and "off" or "main"
        driver = { hand = hand }
        name = name or ((hand == "off") and "Off Hand Enchant" or "Main Hand Enchant")
    else
        kind = (kind == "item") and "item" or "spell"
        id = tonumber(id)
        if not (id and id > 0) then return nil end
        id = math.floor(id)
        driver = { [(kind == "item") and "itemID" or "spellID"] = id }
        name = name or (((kind == "item") and "Item " or "Spell ") .. id)
    end
    local rid = NewId()
    local rec = {
        id = rid, type = "reminder", kind = kind, groupId = groupId,
        name = name, driver = driver,
        triggers = { Store.NewTrigger(kind) },
        o = {}, c = {},
    }
    ScopeToCreator(rec)
    g.members[#g.members + 1] = rid
    DB.records[rid] = rec
    Store.Dirty("tree")
    return rec
end

-- An aura reminder: an aura icon made for a reminder group, in the row beside
-- its pulse (Drivers\AD_DriverReminders.lua), showing only while its aura is
-- missing (Active opacity 0). Store.GroupTakes lets nothing else into a
-- reminder group, so this is the only way in. driver: an aura icon's.
function Store.NewAuraReminder(groupId, driver, name)
    local g = Store.Get(groupId)
    if not (g and g.type == "group" and g.groupKind == "reminder") then return nil end
    local id = NewId()
    local rec = {
        id = id, type = "icon", kind = "aura", groupId = groupId,
        name = name or ("Icon " .. id),
        driver = driver or {}, o = {}, c = {},
    }
    ScopeToCreator(rec)
    g.members[#g.members + 1] = id
    DB.records[id] = rec
    Store.SetOverride(rec, "auraActive", "activeAlpha", 0)
    Store.Dirty("tree")
    return rec
end

-- A reminder's triggers, cleaned: at most Schema.REMINDER_MAX_TRIGGERS, each
-- with a type its kind has and its outputs in range. A list left empty gets
-- one new trigger, so a reminder always has something to fire.
function Store.CleanTriggers(list, kind)
    local ench = kind == "enchant"
    local function Num(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        if v < lo then v = lo elseif v > hi then v = hi end
        return v
    end
    local function Str(v, max)
        if type(v) ~= "string" or v == "" then return nil end
        return v:sub(1, max)
    end
    local types, anims, glows, curves = {}, {}, {}, { NONE = true, OUT = true, IN = true, IN_OUT = true }
    for _, v in ipairs(ench and Schema.REMINDER_ENCHANT_TRIGGERS or Schema.REMINDER_TRIGGERS) do types[v] = true end
    -- an item's use has no usable state to read
    if kind == "item" then
        for v in pairs(Schema.REMINDER_SPELL_ONLY) do types[v] = nil end
    end
    for _, v in ipairs(Schema.REMINDER_ANIMS) do anims[v] = true end
    for _, v in ipairs(Schema.REMINDER_GLOWS) do glows[v] = true end
    local out = {}
    for _, t in ipairs(type(list) == "table" and list or {}) do
        if #out >= Schema.REMINDER_MAX_TRIGGERS then break end
        if type(t) == "table" then
            local ty = types[t.type] and t.type or (ench and "enchant_missing" or "when_ready")
            -- an enchant can run for half an hour, so its warning can be that early
            local long = ty == "enchant_expiring"
            local c = {
                type = ty,
                seconds = Num(t.seconds, 0.1, long and 3600 or 600) or (long and 60 or 3),
                soundDisabled = (t.soundDisabled == true) and true or nil,
                -- a weapon enchant has no proc glow to wait for
                requireProc = (not ench and t.requireProc == true) and true or nil,
                sound = Str(t.sound, 120),
                tts = Str(t.tts, 200),
                animStyle = (anims[t.animStyle] and t.animStyle ~= "default") and t.animStyle or nil,
                glowType = (glows[t.glowType] and t.glowType ~= "none") and t.glowType or nil,
            }
            -- nil = shown (v1's own reading); only an explicit false hides it
            if t.showIcon == false then c.showIcon = false end
            if ty == "enchant_charges" then c.count = math.floor(Num(t.count, 1, 999) or 5) end
            -- "Fire even while on cooldown" is When usable's alone; "Clear when
            -- it ends" belongs to the two types whose moment can end
            if ty == "when_usable" and t.ignoreCooldown == true then c.ignoreCooldown = true end
            if (ty == "when_usable" or ty == "on_proc") and t.clearOnEnd == true then c.clearOnEnd = true end
            local p = Num(t.priority, 0, 5)
            c.priority = (p and p >= 1) and math.floor(p + 0.5) or nil
            if type(t.glowColor) == "table" then
                c.glowColor = { Num(t.glowColor[1], 0, 1) or 0, Num(t.glowColor[2], 0, 1) or 0,
                    Num(t.glowColor[3], 0, 1) or 0, Num(t.glowColor[4], 0, 1) or 1 }
            end
            if t.overrideAnim == true then
                c.overrideAnim = true
                c.pulseDuration = Num(t.pulseDuration, 0.1, 600)
                c.animFadeSmoothing = curves[t.animFadeSmoothing] and t.animFadeSmoothing or nil
                c.animFlashSpeed = Num(t.animFlashSpeed, 0.03, 0.30)
                c.animZoomStart = Num(t.animZoomStart, 0.30, 1)
                c.animZoomPeak = Num(t.animZoomPeak, 1, 1.50)
                c.animZoomPopTime = Num(t.animZoomPopTime, 0.04, 0.40)
                c.animZoomSettleTime = Num(t.animZoomSettleTime, 0.02, 0.30)
            end
            out[#out + 1] = c
        end
    end
    if #out == 0 then out[1] = Store.NewTrigger(kind) end
    return out
end

-- destGroupId places the icon in a group; destGroupId == nil makes it a
-- free-position icon of layoutId
function Store.NewIcon(kind, driver, destGroupId, layoutId, name)
    local id = NewId()
    local rec = {
        id = id, type = "icon", kind = kind,
        name = name or ("Icon " .. id),
        driver = driver or {}, o = {}, c = {},
    }
    ScopeToCreator(rec)
    if destGroupId then
        local group = Store.Get(destGroupId)
        if not group or group.type ~= "group" then return nil end
        if not Store.GroupTakes(group, kind) then return nil end
        rec.groupId = destGroupId
        group.members[#group.members + 1] = id
    else
        local layout = Store.Get(layoutId)
        if not layout or layout.type ~= "layout" then return nil end
        rec.layoutId = layoutId
        local sx, sy = CenterSpot(layoutId)
        rec.pos = { x = sx, y = sy }
        layout.members[#layout.members + 1] = id
    end
    -- a duration runs out towards 0, so its swipe fills as it goes; a spell
    -- or item cooldown keeps the normal one (it clears when usable)
    if kind == "totem" or kind == "enchant" or kind == "timer" then
        TemplateSet(rec, "swipe", "reverse", true)
    end
    -- an ammo count is the icon's number: a new one starts in the centre
    if kind == "ammo" then TemplateSet(rec, "text", "stackAnchor", "CENTER") end
    DB.records[id] = rec
    Store.Dirty("tree")
    return rec
end

-- A range bar's own bands, cleaned: each { text, color, off, checks }, a check
-- { kind = "spell", id, want } or { kind = "yd", yd, want } with yd one of
-- Schema.RANGE_YARDS; at most RANGE_MAX_BANDS bands of RANGE_MAX_CHECKS checks.
-- A spell check with no ID yet is dropped. nil when no band is left.
function Store.CleanRangeBands(list)
    if type(list) ~= "table" then return nil end
    local yards = {}
    for _, y in ipairs(Schema.RANGE_YARDS or {}) do yards[y] = true end
    local maxB, maxC = Schema.RANGE_MAX_BANDS or 8, Schema.RANGE_MAX_CHECKS or 4
    local function Unit(v, dflt)
        v = tonumber(v)
        if not v then return dflt end
        return math.max(0, math.min(1, v))
    end
    local out = {}
    for _, b in ipairs(list) do
        if type(b) == "table" and #out < maxB then
            local c = type(b.color) == "table" and b.color or {}
            local nb = {
                text = (type(b.text) == "string") and b.text:sub(1, 40) or "",
                color = { Unit(c[1], 0.5), Unit(c[2], 0.5), Unit(c[3], 0.5), Unit(c[4], 1) },
                off = (b.off == true) or nil,
                checks = {},
            }
            for _, k in ipairs(type(b.checks) == "table" and b.checks or {}) do
                if type(k) == "table" and #nb.checks < maxC then
                    local want = k.want == true
                    if k.kind == "spell" then
                        local id = tonumber(k.id)
                        if id and id > 0 then
                            nb.checks[#nb.checks + 1] = { kind = "spell", id = math.floor(id), want = want }
                        end
                    elseif k.kind == "yd" and yards[tonumber(k.yd) or 0] then
                        nb.checks[#nb.checks + 1] = { kind = "yd", yd = tonumber(k.yd), want = want }
                    end
                end
            end
            out[#out + 1] = nb
        end
    end
    if #out == 0 then return nil end
    return out
end

-- A swing bar's ability colours (rec.driver.swingColors), in priority order:
-- at most Schema.SWING_COLOR_MAX rules, each a positive spell ID or none yet
-- (kept, so a rule being set up survives), when it applies ("queued" or
-- "cast") and a colour. nil when there are none.
function Store.CleanSwingColors(list)
    if type(list) ~= "table" then return nil end
    local max = Schema.SWING_COLOR_MAX or 8
    local d = Schema.SWING_COLOR_DEFAULT or { 1, 0.55, 0.15, 1 }
    local function Unit(v, dflt)
        v = tonumber(v)
        if not v then return dflt end
        return math.max(0, math.min(1, v))
    end
    local out = {}
    for _, r in ipairs(list) do
        if type(r) == "table" and #out < max then
            local id = tonumber(r.id)
            local c = type(r.color) == "table" and r.color or {}
            out[#out + 1] = {
                id = (id and id > 0) and math.floor(id) or nil,
                when = (r.when == "cast") and "cast" or "queued",
                color = { Unit(c[1], d[1]), Unit(c[2], d[2]), Unit(c[3], d[3]), Unit(c[4], 1) },
            }
        end
    end
    if #out == 0 then return nil end
    return out
end

-- A custom item's rules (rec.driver.rules on a timer icon or bar), cleaned: at
-- most Schema.CUSTOM_MAX_RULES, each with a known trigger and action, every
-- number in range. nil stays nil (a record that never had rules); an empty
-- list stays a list, so a bar whose migrated rule was removed is not folded again.
function Store.CleanRules(list)
    if type(list) ~= "table" then return nil end
    local whens = {}
    for _, g in ipairs(Schema.CUSTOM_TRIGGER_GROUPS) do
        for _, k in ipairs(g.list) do whens[k] = true end
    end
    for _, k in ipairs(Schema.CUSTOM_TARGET_TRIGGERS) do whens[k] = true end
    local acts, modes = {}, {}
    for _, v in ipairs(Schema.CUSTOM_ACTIONS) do acts[v] = true end
    for _, v in ipairs(Schema.CUSTOM_START_MODES) do modes[v] = true end
    local function Whole(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        v = math.floor(v)
        if v < lo or v > hi then return nil end
        return v
    end
    local function Num(v, lo, hi)
        v = tonumber(v)
        if not v then return nil end
        if v < lo then v = lo elseif v > hi then v = hi end
        return v
    end
    local function Str(v, max)
        if type(v) ~= "string" or v == "" then return nil end
        return v:sub(1, max)
    end
    local out = {}
    for _, r in ipairs(list) do
        if type(r) == "table" and #out < Schema.CUSTOM_MAX_RULES then
            local c = {
                when = whens[r.when] and r.when or "cast",
                spellID = Whole(r.spellID, 1, 1e9),
                pet = (r.pet == true) and true or nil,
                ignoreCooldown = (r.ignoreCooldown == true) and true or nil,
                slot = Whole(r.slot, 1, 4),
                srcId = Whole(r.srcId, 1, 1e12),
                combat = (r.combat == "in" or r.combat == "out") and r.combat or nil,
                talent = Whole(r.talent, 1, 1e9),
                spellReady = Whole(r.spellReady, 1, 1e9),
                stacksMin = Whole(r.stacksMin, 0, 999),
                stacksMax = Whole(r.stacksMax, 0, 999),
                withinRule = Whole(r.withinRule, 1, Schema.CUSTOM_MAX_RULES),
                timer = (r.timer == "running" or r.timer == "idle") and r.timer or nil,
                act = acts[r.act] and r.act or "start",
                secs = Num(r.secs, 0, 3600),
                mode = modes[r.mode] and r.mode or nil,
                n = Whole(r.n, 1, 999),
                restartToo = (r.restartToo == true) and true or nil,
                sound = Str(r.sound, 120),
                text = Str(r.text, 200),
            }
            if c.withinRule then c.withinSecs = Num(r.withinSecs, 0.1, 600) or 1 end
            out[#out + 1] = c
        end
    end
    return out
end

-- A custom item's driver made usable: the art spell, how it shows, its default
-- seconds, its stack cap, the clear-on-end switch and its rules. A bar from
-- before the rule engine (a spell and seconds, its trigger "cast" or unset)
-- becomes one rule that does the same; its aura triggers never worked and fold
-- to nothing.
function Store.CleanCustom(d, isBar)
    local sid = tonumber(d.spellID)
    d.spellID = (sid and sid > 0) and math.floor(sid) or nil
    local dur = tonumber(d.duration)
    d.duration = (dur and dur > 0) and math.min(dur, 3600) or nil
    local ms = tonumber(d.maxStacks)
    d.maxStacks = (ms and ms >= 1) and math.floor(math.min(ms, 999)) or nil
    d.clearOnEnd = (d.clearOnEnd == true) and true or nil
    local ok = false
    for _, v in ipairs(Schema.CUSTOM_SHOW_WHILE) do
        if d.showWhile == v then ok = true end
    end
    if not ok then d.showWhile = nil end
    if isBar and d.rules == nil then
        local trig = d.triggerType
        if (trig == nil or trig == "cast") and d.spellID and d.duration then
            d.rules = { { when = "cast", spellID = d.spellID, act = "start", secs = d.duration, mode = "restart" } }
        elseif trig ~= nil then
            d.rules = {}
        end
    end
    d.triggerType = nil
    d.rules = Store.CleanRules(d.rules)
end

-- A text element's driver made usable (Bars\AD_TextElement.lua): a known source
-- (else the typed words), its value choice, whole positive ids, the aura shape
-- the aura driver reads, and its own rules through CleanCustom when it has any.
local TEXT_SOURCE_SET, TEXT_SHOW_SET, TEXT_UNIT_SET = {}, {}, {}
for _, s in ipairs(Schema.TEXT_SOURCES or {}) do TEXT_SOURCE_SET[s] = true end
-- the health bars' units: you, your target, focus, pet and party members 1-4
for _, u in ipairs(Schema.HEALTH_UNITS or { "player", "target", "focus", "pet" }) do TEXT_UNIT_SET[u] = true end
for _, s in ipairs(Schema.TEXT_SHOWS or {}) do TEXT_SHOW_SET[s] = true end
for _, s in ipairs(Schema.TEXT_READOUTS or {}) do TEXT_SHOW_SET[s] = true end
-- the states custom words show on, per source (nil = the first: ready, up)
local TEXT_WHEN_SET = { spellText = {}, auraText = {} }
for _, w in ipairs(Schema.TEXT_SPELL_WHEN or {}) do TEXT_WHEN_SET.spellText[w] = true end
for _, w in ipairs(Schema.TEXT_AURA_WHEN or {}) do TEXT_WHEN_SET.auraText[w] = true end
function Store.CleanText(d)
    if not TEXT_SOURCE_SET[d.source] then d.source = "static" end
    d.text = (type(d.text) == "string" and d.text ~= "") and d.text:sub(1, 120) or nil
    local whenSet = TEXT_WHEN_SET[d.source]
    if not (whenSet and whenSet[d.when]) then d.when = nil end
    -- "When little time is left": a share of the aura (1-99%), or seconds
    -- against the aura's length typed in
    if d.timeUnit ~= "sec" then d.timeUnit = nil end
    local pct = tonumber(d.timePct)
    d.timePct = (pct and pct >= 1 and pct <= 99) and math.floor(pct) or nil
    local sec = tonumber(d.timeSec)
    d.timeSec = (sec and sec > 0) and math.min(3600, sec) or nil
    local len = tonumber(d.auraLen)
    d.auraLen = (len and len > 0) and math.min(36000, len) or nil
    local function Whole(v)
        v = tonumber(v)
        return (v and v > 0) and math.floor(v) or nil
    end
    -- mana is power 0, so the power keeps 0; nothing below 0 (the picker's Automatic)
    local pt = tonumber(d.powerType)
    d.powerType = (pt and pt >= 0) and math.floor(pt) or nil
    if not TEXT_SHOW_SET[d.show] then d.show = nil end
    if not TEXT_UNIT_SET[d.unit] then d.unit = nil end
    d.spellID = Whole(d.spellID)
    d.autoRank = (d.autoRank == true) and true or nil
    -- the aura shape: a list only past one id, the primary in spellID
    if type(d.spellIDs) == "table" then
        local out, seen = {}, {}
        for _, v in ipairs(d.spellIDs) do
            local n = Whole(v)
            if n and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        if not d.spellID then d.spellID = out[1] end
        d.spellIDs = (#out > 1) and out or nil
    else
        d.spellIDs = nil
    end
    if d.auraType ~= "buff" and d.auraType ~= "debuff" then d.auraType = nil end
    if d.caster ~= "mine" and d.caster ~= "others" then d.caster = nil end
    d.rangeFrom = Whole(d.rangeFrom)
    d.srcId = Whole(d.srcId)
    if d.source == "rules" or d.rules ~= nil then
        if d.source == "rules" and type(d.rules) ~= "table" then d.rules = {} end
        Store.CleanCustom(d, false)
    else
        d.duration, d.maxStacks, d.clearOnEnd, d.showWhile = nil, nil, nil, nil
    end
end

-- A texture's driver made usable (Bars\AD_TextureElement.lua): a known source,
-- whole positive ids, the aura shape the aura driver reads, the cooldown's
-- active state, and its own rules through CleanCustom when it has any.
local TEXTURE_SOURCE_SET = {}
for _, s in ipairs(Schema.TEXTURE_SOURCES or {}) do TEXTURE_SOURCE_SET[s] = true end
local TEXTURE_UNIT_SET = { player = true, target = true, focus = true, pet = true,
    party1 = true, party2 = true, party3 = true, party4 = true }
-- A wheel (Bars\AD_Wheel.lua): 3 to 10 spots, each a spell or an item by a
-- whole positive ID, and its key a binding name or none.
function Store.CleanWheel(rec)
    local d = rec.driver
    local n = tonumber(d.count)
    d.count = n and math.max(3, math.min(10, math.floor(n))) or nil
    local out = {}
    if type(d.spots) == "table" then
        for spot, v in pairs(d.spots) do
            local k = tonumber(spot)
            local id = type(v) == "table" and tonumber(v.id) or nil
            if k and k >= 1 and k <= 10 and k == math.floor(k) and id and id > 0
                and (v.t == "spell" or v.t == "item") then
                out[k] = { t = v.t, id = math.floor(id) }
            end
        end
    end
    d.spots = out
    local key = rec.wheelKey
    if type(key) ~= "string" or key == "" or #key > 40 or key:find("%c") then rec.wheelKey = nil end
end

function Store.CleanTexture(d)
    if not TEXTURE_SOURCE_SET[d.source] then d.source = "aura" end
    local function Whole(v)
        v = tonumber(v)
        return (v and v > 0) and math.floor(v) or nil
    end
    d.spellID = Whole(d.spellID)
    d.autoRank = (d.autoRank == true) and true or nil
    if type(d.spellIDs) == "table" then
        local out, seen = {}, {}
        for _, v in ipairs(d.spellIDs) do
            local n = Whole(v)
            if n and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        if not d.spellID then d.spellID = out[1] end
        d.spellIDs = (#out > 1) and out or nil
    else
        d.spellIDs = nil
    end
    if d.auraType ~= "buff" and d.auraType ~= "debuff" then d.auraType = nil end
    if not TEXTURE_UNIT_SET[d.unit] then d.unit = nil end
    if d.caster ~= "mine" and d.caster ~= "others" then d.caster = nil end
    if d.cdActive ~= "cooldown" then d.cdActive = nil end
    if d.source == "rules" or d.rules ~= nil then
        if d.source == "rules" and type(d.rules) ~= "table" then d.rules = {} end
        Store.CleanCustom(d, false)
    else
        d.duration, d.maxStacks, d.clearOnEnd, d.showWhile = nil, nil, nil, nil
    end
end

-- Bars are always free layout children, never group members: group attachment
-- is the anchor section. driver by kind: cooldown {spellID}, aura {spellID, auraType,
-- unit, caster, maxStacks}, swing {swingType, swingAbilIDs, swingColors, rangeSpell},
-- resource {powerType}, health and cast {unit}, range {preset, spellID, bands}, legacy
-- timer {spellID, duration, triggerType}, legacy stack {powerType}; the bars runtime
-- validates it. barMode ("duration"|"stack") is the cooldown/aura sub-type, fixed at creation.
function Store.NewBar(layoutId, barKind, driver, name, barMode)
    local layout = Store.Get(layoutId)
    if not layout or layout.type ~= "layout" then return nil end
    if barKind ~= "timer" and barKind ~= "stack" and barKind ~= "swing"
        and barKind ~= "aura" and barKind ~= "resource" and barKind ~= "health"
        and barKind ~= "cast" and barKind ~= "enchant" and barKind ~= "range"
        and barKind ~= "text" and barKind ~= "texture" and barKind ~= "wheel" then
        barKind = "cooldown"
    end
    local id = NewId()
    local rec = {
        id = id, type = "bar", barKind = barKind,
        name = name or ("Bar " .. id),
        layoutId = layoutId,
        driver = driver or {}, o = {}, c = {},
    }
    if barKind == "cooldown" or barKind == "aura" or barKind == "timer" then
        rec.barMode = (barMode == "stack") and "stack" or "duration"
    end
    ScopeToCreator(rec)
    -- Creation template, written on the record only: the schema defaults
    -- stay off and a saved default wins.
    if barKind == "cooldown" or barKind == "aura" or barKind == "enchant" then
        TemplateSet(rec, "icon", "iconShow", true)
    end
    -- Name text shows on spell bars. A resource or swing bar's name is just its
    -- power or hand, and a player health bar's is your own, so it stays off
    -- there; other health bars show their unit's live name.
    local hpUnit = barKind == "health" and (rec.driver.unit or "player") or nil
    if barKind ~= "resource" and barKind ~= "swing" and barKind ~= "text" and barKind ~= "texture"
        and barKind ~= "wheel" and hpUnit ~= "player" then
        TemplateSet(rec, "text", "nameShow", true)
    end
    -- A text element is born as a small box; its look is the schema's (white, 14).
    if barKind == "text" then
        TemplateSet(rec, "size", "width", 140)
        TemplateSet(rec, "size", "height", 24)
    end
    -- A texture is born as a square picture.
    if barKind == "texture" then
        TemplateSet(rec, "size", "width", 64)
        TemplateSet(rec, "size", "height", 64)
    end
    -- A health bar is born green with incoming heals and absorb shields on;
    -- both are one click off in Heals & Shields (the schema defaults stay off).
    if barKind == "health" then
        TemplateSet(rec, "fill", "color", { 0.18, 0.8, 0.3, 1 })
        TemplateSet(rec, "healpred", "healShow", true)
        TemplateSet(rec, "healpred", "absorbShow", true)
        TemplateSet(rec, "healpred", "absorbOverflow", true)
    end
    -- A castbar is born looking like one; every piece is still one click away,
    -- as the schema defaults stay off. A target or focus bar also greys and
    -- shields casts you cannot interrupt. The player's bar does not: nobody
    -- interrupts your casts, so the grey would read as a fault.
    if barKind == "cast" then
        TemplateSet(rec, "size", "width", 220)
        TemplateSet(rec, "size", "height", 20)
        TemplateSet(rec, "fill", "color", { 1, 0.7, 0.1, 1 })
        TemplateSet(rec, "fill", "castChannelOn", true)
        TemplateSet(rec, "look", "borderThickness", 2)
        TemplateSet(rec, "icon", "iconShow", true)
        TemplateSet(rec, "icon", "iconFollowBar", true)
        TemplateSet(rec, "text", "nameAnchor", "LEFT")
        TemplateSet(rec, "text", "nameOffsetX", 4)
        TemplateSet(rec, "text", "nameOffsetY", 0)
        TemplateSet(rec, "text", "nameColor", { 1, 1, 1, 1 })
        TemplateSet(rec, "text", "durDecimalsEnabled", true)
        TemplateSet(rec, "cast", "sparkOn", true)
        TemplateSet(rec, "cast", "holdOn", true)
        if (rec.driver.unit or "player") ~= "player" then
            TemplateSet(rec, "fill", "castLockOn", true)
            TemplateSet(rec, "icon", "iconShield", true)
        end
    end
    -- A range bar reads its band's name, white and centred on the plate.
    if barKind == "range" then
        TemplateSet(rec, "look", "borderThickness", 3)
        TemplateSet(rec, "text", "nameAnchor", "CENTER")
        TemplateSet(rec, "text", "nameOffsetX", 0)
        TemplateSet(rec, "text", "nameOffsetY", 0)
        TemplateSet(rec, "text", "nameSize", 12)
        TemplateSet(rec, "text", "nameColor", { 1, 1, 1, 1 })
    end
    if rec.barMode == "stack" then TemplateSet(rec, "text", "stkAnchor", "CENTER") end
    -- A counted bar (combo points, aura stacks) is born with one tick mark per
    -- point; mana-sized powers stay clean.
    if (barKind == "aura" and rec.barMode == "stack")
        or (barKind == "resource" and rec.driver.powerType == 4) then
        TemplateSet(rec, "ticks", "ticksShow", true)
        TemplateSet(rec, "ticks", "tickMode", "all")
    end
    -- at the screen centre; a bar already there pushes the new one down
    -- one row (24px bar + the name above it + a gap = 42)
    local sx, sy = CenterSpot(layoutId)
    rec.pos = { x = sx, y = sy }
    layout.members[#layout.members + 1] = id
    DB.records[id] = rec
    Store.Dirty("tree")
    return rec
end

local function removeFrom(list, id)
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i) end
    end
end

function Store.Delete(id)
    local rec = Store.Get(id)
    if not rec then return end
    if rec.type == "layout" then
        for _, mid in ipairs(rec.members or {}) do
            local child = DB.records[mid]
            if child then
                if child.type == "group" then
                    for _, iid in ipairs(child.members or {}) do
                        DB.records[iid] = nil
                    end
                end
                DB.records[mid] = nil
            end
        end
    elseif rec.type == "group" then
        for _, iid in ipairs(rec.members or {}) do
            DB.records[iid] = nil
        end
        local layout = Store.Get(rec.layoutId)
        if layout then removeFrom(layout.members, id) end
    elseif rec.type == "icon" or rec.type == "reminder" then
        if rec.groupId then
            local group = Store.Get(rec.groupId)
            if group then removeFrom(group.members, id) end
        elseif rec.layoutId then
            local layout = Store.Get(rec.layoutId)
            if layout then removeFrom(layout.members, id) end
        end
    elseif rec.type == "bar" then
        -- bars have no members: just unlink from the layout
        local layout = Store.Get(rec.layoutId)
        if layout then removeFrom(layout.members, id) end
    end
    DB.records[id] = nil
    Store.Dirty("tree")
end

-- Moves an icon into a group (destGroupId, optional cell {row, col}) or to a
-- free spot on a layout (layoutId + pos); a group takes what Store.GroupTakes
-- allows. With no cell, the icon takes the first free cell on the next render.
function Store.MoveIcon(iconId, destGroupId, layoutId, pos, cell)
    local rec = Store.Get(iconId)
    if not rec or rec.type ~= "icon" then return false end
    local dest
    if destGroupId then
        dest = Store.Get(destGroupId)
        if not dest or dest.type ~= "group" then return false end
        if not Store.GroupTakes(dest, rec.kind) then return false end
    else
        local layout = Store.Get(layoutId)
        if not layout or layout.type ~= "layout" then return false end
    end
    if rec.groupId then
        local g = Store.Get(rec.groupId)
        if g then removeFrom(g.members, iconId) end
    elseif rec.layoutId then
        local l = Store.Get(rec.layoutId)
        if l then removeFrom(l.members, iconId) end
    end
    if destGroupId then
        rec.groupId, rec.layoutId, rec.pos = destGroupId, nil, nil
        rec.gpos = cell and { row = cell.row, col = cell.col } or nil
        dest.members[#dest.members + 1] = iconId
    else
        rec.groupId = nil
        rec.gpos = nil
        rec.layoutId = layoutId
        rec.pos = {
            x = math.floor(((pos and pos.x) or 0) + 0.5),
            y = math.floor(((pos and pos.y) or 0) + 0.5),
        }
        local layout = Store.Get(layoutId)
        layout.members[#layout.members + 1] = iconId
    end
    Store.Dirty("tree")
    return true
end

-- exchange two members' grid cells (the static-grid swap drop)
function Store.SwapCells(groupId, idA, idB)
    local a, b = Store.Get(idA), Store.Get(idB)
    if not (a and b and a.groupId == groupId and b.groupId == groupId) then
        return false
    end
    a.gpos, b.gpos = b.gpos, a.gpos
    Store.Dirty("tree")
    return true
end

-- exchange two members' positions inside one group (the drop "swap" mode)
function Store.SwapInGroup(groupId, idA, idB)
    local g = Store.Get(groupId)
    if not (g and g.members) then return false end
    local ia, ib
    for i, mid in ipairs(g.members) do
        if mid == idA then ia = i end
        if mid == idB then ib = i end
    end
    if not (ia and ib) then return false end
    g.members[ia], g.members[ib] = g.members[ib], g.members[ia]
    Store.Dirty("tree")
    return true
end

-- Rename, duplicate, re-home

-- Any record. Everything finds records by id, never by name (no driver, bar or
-- engine path reads rec.name), so a rename is display-only: the rail, cards,
-- headers and on-screen handles follow on the tree refresh.
function Store.Rename(id, name)
    local rec = Store.Get(id)
    if not rec then return false end
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    if #name > 60 then name = name:sub(1, 60) end
    if rec.name == name then return true end
    rec.name = name
    Store.Dirty("tree", id)
    return true
end

local function CopyDeep(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = CopyDeep(val) end
    return t
end

-- Re-points anchor targets that travelled with a copy or an import (map = old
-- id -> new id). A target outside the copied set stays when `keep` (a
-- same-account duplicate still sees the original) and is dropped otherwise: a
-- foreign id would anchor to whatever local record happens to own it.
local function RemapAnchors(rec, map, keep)
    local a = rec.o and rec.o.anchor
    if type(a) ~= "table" then return end
    if a.anchorTargetKind == "frame" then return end
    local tid = tonumber(a.anchorTargetId)
    if not tid or tid == 0 then return end
    if map[tid] then
        a.anchorTargetId = map[tid]
    elseif not keep then
        a.anchorTargetId = nil
        a.anchorEnabled = nil
    end
end

-- A custom item's "another item's timer ended" rules name a record by id: the
-- same rule as anchors (a copied source re-points, an outside one is kept on a
-- duplicate and dropped on an import).
local function RemapRules(rec, map, keep)
    local d = rec.driver
    if type(d) ~= "table" then return end
    local rules = d.rules
    if type(rules) == "table" then
        for _, r in ipairs(rules) do
            if type(r) == "table" and r.when == "chain" then
                local sid = tonumber(r.srcId)
                if sid and map[sid] then
                    r.srcId = map[sid]
                elseif sid and not keep then
                    r.srcId = nil
                end
            end
        end
    end
    -- a text element pointing at a custom item or a range bar: the same rule
    if rec.type == "bar" and rec.barKind == "text" then
        for _, k in ipairs({ "srcId", "rangeFrom" }) do
            local id = tonumber(d[k])
            if id and map[id] then
                d[k] = map[id]
            elseif id and not keep then
                d[k] = nil
            end
        end
    end
end

-- deep copy under a fresh id; the caller wires parents and children
local function CloneRecord(rec, map, made)
    local c = CopyDeep(rec)
    c.id = NewId()
    -- one key opens one wheel: a copy starts without it
    c.wheelKey = nil
    -- a copy is the player's own new item: its own ID, from no pack
    c.uid = NewUid()
    c.imported = nil
    map[rec.id] = c.id
    made[#made + 1] = c
    return c
end

local function Nudge(pos, dx, dy)
    return { x = (tonumber(pos and pos.x) or 0) + dx, y = (tonumber(pos and pos.y) or 0) + dy }
end

-- clone every icon (a reminder group: every reminder) of `group` under its
-- clone `gc`
local function CloneIcons(group, gc, map, made)
    gc.members = {}
    for _, iid in ipairs(group.members or {}) do
        local icon = DB.records[iid]
        if icon and (icon.type == "icon" or icon.type == "reminder") then
            local ic = CloneRecord(icon, map, made)
            ic.groupId = gc.id
            gc.members[#gc.members + 1] = ic.id
            DB.records[ic.id] = ic
        end
    end
end

-- Copy and paste in one step: a layout with everything in it, a group with its
-- icons, or a lone icon or bar, under fresh ids with " copy" on the name and
-- nudged off the original. Anchors between copied records re-point to the
-- copies; anchors to anything else hold. Returns the copy, or nil.
function Store.Duplicate(id)
    local rec = Store.Get(id)
    if not rec then return nil end
    local map, made = {}, {}
    local copy = CloneRecord(rec, map, made)
    copy.name = tostring(rec.name or "") .. " copy"
    if rec.type == "layout" then
        copy.members = {}
        copy.pos = Nudge(rec.pos, 24, -24)
        for _, mid in ipairs(rec.members or {}) do
            local child = DB.records[mid]
            if child then
                local cc = CloneRecord(child, map, made)
                cc.layoutId = copy.id
                copy.members[#copy.members + 1] = cc.id
                if child.type == "group" then CloneIcons(child, cc, map, made) end
                DB.records[cc.id] = cc
            end
        end
    elseif rec.type == "group" then
        local layout = Store.Get(rec.layoutId)
        if not layout then return nil end
        copy.pos = Nudge(rec.pos, 24, -24)
        CloneIcons(rec, copy, map, made)
        layout.members[#layout.members + 1] = copy.id
    elseif rec.type == "icon" then
        if rec.groupId then
            local g = Store.Get(rec.groupId)
            if not g then return nil end
            copy.gpos = nil
            g.members[#g.members + 1] = copy.id
        else
            local l = Store.Get(rec.layoutId)
            if not l then return nil end
            copy.pos = Nudge(rec.pos, 42, 0)
            l.members[#l.members + 1] = copy.id
        end
    elseif rec.type == "bar" then
        local l = Store.Get(rec.layoutId)
        if not l then return nil end
        copy.pos = Nudge(rec.pos, 0, -22)
        l.members[#l.members + 1] = copy.id
    elseif rec.type == "reminder" then
        local g = Store.Get(rec.groupId)
        if not g then return nil end
        g.members[#g.members + 1] = copy.id
    else
        return nil
    end
    DB.records[copy.id] = copy
    for _, r in ipairs(made) do
        RemapAnchors(r, map, true)
        RemapRules(r, map, true)
    end
    Store.Dirty("tree")
    return copy
end

-- Puts a group, bar or icon into `layoutId` before the member `beforeId`, or at
-- the end when nil (an unknown beforeId, or the record itself, also appends).
-- This is the writer behind the rail's drop line: a reorder inside one layout,
-- or a landing in another at that exact spot. Groups and bars keep pos,
-- settings and members; an icon becomes a free icon there at its old offset (a
-- group icon has none, so it takes the free-icon default).
function Store.PlaceInLayout(id, layoutId, beforeId)
    local rec, dest = Store.Get(id), Store.Get(layoutId)
    if not (rec and dest and dest.type == "layout") then return false end
    if rec.type ~= "group" and rec.type ~= "bar" and rec.type ~= "icon" then return false end
    if rec.type == "icon" and rec.groupId then
        local g = Store.Get(rec.groupId)
        if g then removeFrom(g.members, id) end
        rec.groupId, rec.gpos = nil, nil
        local p = rec.pos
        rec.pos = {
            x = math.floor((tonumber(p and p.x) or 0) + 0.5),
            y = math.floor((tonumber(p and p.y) or -60) + 0.5),
        }
    else
        local src = Store.Get(rec.layoutId)
        if src then removeFrom(src.members, id) end
    end
    rec.layoutId = layoutId
    local at = #dest.members + 1
    if beforeId and beforeId ~= id then
        for i, mid in ipairs(dest.members) do
            if mid == beforeId then at = i break end
        end
    end
    table.insert(dest.members, at, id)
    Store.Dirty("tree")
    return true
end

-- Re-home a group, bar or icon under another layout, at the end (the
-- editors' "Move to" and a drop on a layout's header row). A no-op when it
-- already lives there as a layout child.
function Store.MoveToLayout(id, layoutId)
    local rec = Store.Get(id)
    if not rec then return false end
    if rec.type == "icon" then
        if not rec.groupId and rec.layoutId == layoutId then return true end
    elseif rec.layoutId == layoutId then
        return true
    end
    return Store.PlaceInLayout(id, layoutId, nil)
end

-- Moves a selection at once (UI\AD_MultiSelect.lua): target = { layoutId }
-- puts each record free in that layout as Move to does, { groupId } puts
-- icons into that group (Store.GroupTakes decides). An icon whose group is in
-- the set rides with its group and is not moved on its own; a layout or a
-- reminder never moves. Returns the ids moved and the ids refused.
function Store.MoveMany(ids, target)
    local set, moved, refused = {}, {}, {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    for _, id in ipairs(ids or {}) do
        local rec = DB.records[id]
        local ok = false
        if rec and (rec.type == "group" or rec.type == "bar" or rec.type == "icon") then
            if rec.type == "icon" and rec.groupId and set[rec.groupId] then
                ok = nil
            elseif target.groupId then
                ok = Store.MoveIcon(id, target.groupId)
            elseif target.layoutId then
                ok = Store.MoveToLayout(id, target.layoutId)
            end
        end
        if ok then moved[#moved + 1] = id elseif ok == false then refused[#refused + 1] = id end
    end
    return moved, refused
end

-- Copies a selection at once (UI\AD_MultiSelect.lua's Copy and Duplicate):
-- target = { layoutId } / { groupId } as MoveMany, or nil for each copy
-- beside its original as Store.Duplicate makes it. A group brings its icons
-- (an icon or reminder whose group is in the set rides with that copy); a
-- layout never copies, a reminder only beside its original. One id map over
-- the whole set, so anchors and chain rules between selected records re-point
-- to the copies. A copy that lands where its original lives takes " copy" and
-- Duplicate's nudge; one that lands elsewhere keeps its name and position, as
-- a move would. Returns the copies and the ids refused.
function Store.CopyMany(ids, target)
    local set, map, made, copies, refused = {}, {}, {}, {}, {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    local toGroup = target and target.groupId and Store.Get(target.groupId)
    local toLayout = target and target.layoutId and Store.Get(target.layoutId)
    if toGroup and toGroup.type ~= "group" then toGroup = nil end
    if toLayout and toLayout.type ~= "layout" then toLayout = nil end
    -- the copy's home and whether that is its original's own, or nil when
    -- the target cannot take it
    local function Home(rec)
        if not target then
            if rec.groupId then return Store.Get(rec.groupId), true end
            return Store.Get(rec.layoutId), true
        end
        if toGroup then
            if rec.type ~= "icon" or not Store.GroupTakes(toGroup, rec.kind) then return nil end
            return toGroup, rec.groupId == toGroup.id
        end
        if not toLayout or rec.type == "reminder" then return nil end
        if rec.type == "icon" then return toLayout, not rec.groupId and rec.layoutId == toLayout.id end
        return toLayout, rec.layoutId == toLayout.id
    end
    for _, id in ipairs(ids or {}) do
        local rec = DB.records[id]
        local t = rec and rec.type
        local ok = false
        if (t == "icon" or t == "reminder") and rec.groupId and set[rec.groupId] then
            ok = nil
        elseif t == "group" or t == "bar" or t == "icon" or t == "reminder" then
            local home, same = Home(rec)
            if home and home.members then
                local c = CloneRecord(rec, map, made)
                if same then c.name = tostring(rec.name or "") .. " copy" end
                if t == "group" then
                    c.layoutId = home.id
                    if same then c.pos = Nudge(rec.pos, 24, -24) end
                    CloneIcons(rec, c, map, made)
                elseif t == "bar" then
                    c.layoutId = home.id
                    if same then c.pos = Nudge(rec.pos, 0, -22) end
                elseif home.type == "group" then
                    -- into a group: the first free cell on the next render
                    c.groupId, c.layoutId, c.pos, c.gpos = home.id, nil, nil, nil
                else
                    -- free in a layout; a grouped icon takes PlaceInLayout's spot
                    local p = rec.pos
                    if same then
                        c.pos = Nudge(p, 42, 0)
                    elseif rec.groupId then
                        c.pos = {
                            x = math.floor((tonumber(p and p.x) or 0) + 0.5),
                            y = math.floor((tonumber(p and p.y) or -60) + 0.5),
                        }
                    end
                    c.groupId, c.gpos, c.layoutId = nil, nil, home.id
                end
                home.members[#home.members + 1] = c.id
                DB.records[c.id] = c
                copies[#copies + 1] = c
                ok = true
            end
        end
        if ok == false then refused[#refused + 1] = id end
    end
    for _, r in ipairs(made) do
        RemapAnchors(r, map, true)
        RemapRules(r, map, true)
    end
    if #copies > 0 then Store.Dirty("tree") end
    return copies, refused
end

-- Grow arrows add or remove one row or column on a visual edge: "bottom",
-- "left" or "right" (no top pair, the title bar owns that edge). Growth
-- directions flip logical to visual, so a visual edge is either the start of
-- its logical axis (index 0: every cell shifts one step) or its end (nothing
-- shifts). The engine then moves the group half a step so the icons stay put.
local GRID_MAX = 20   -- the schema's rows/cols max

local function GridSize(g)
    return math.max(1, Store.Resolve(g, "arrangement", "rows") or 1),
        math.max(1, Store.Resolve(g, "arrangement", "cols") or 6)
end

-- axis ("row" | "col") and whether the edge is that axis's logical start
local function EdgeAxis(g, edge)
    if edge == "bottom" then
        return "row", Store.Resolve(g, "arrangement", "growthV") == "UP"
    end
    local leftFill = Store.Resolve(g, "arrangement", "growthH") == "LEFT"
    if edge == "left" then return "col", not leftFill end
    return "col", leftFill
end

-- can this arrow act? ok, reason ("max" | "min" | "full"), loaded count
function Store.GridEdgeCheck(groupId, edge, add)
    local g = Store.Get(groupId)
    if not (g and g.type == "group") then return false end
    local rows, cols = GridSize(g)
    local axis = EdgeAxis(g, edge)
    local n = (axis == "row") and rows or cols
    if add then
        if n >= GRID_MAX then return false, "max" end
        return true
    end
    if n <= 1 then return false, "min" end
    -- an aura group's live row simply wraps, so it never runs out of cells
    if g.groupKind == "aura" then return true end
    -- Never shrink below the icons: the static grid would grow the line back,
    -- so the click would look like it did nothing. Unloaded icons do not
    -- count; they re-home when they return.
    local live = 0
    for _, rec in ipairs(Store.IconsOf(g)) do
        if Store.IsLoaded(rec) then live = live + 1 end
    end
    local cap = (axis == "row") and ((rows - 1) * cols) or (rows * (cols - 1))
    if live > cap then return false, "full", live end
    return true
end

-- Grow-arrow writer: resizes the axis and keeps every cell on its visual spot.
-- Icons in a removed line get gpos = nil and take the first free cell on the
-- next render.
function Store.GridEdge(groupId, edge, add)
    if not Store.GridEdgeCheck(groupId, edge, add) then return false end
    local g = Store.Get(groupId)
    local rows, cols = GridSize(g)
    local axis, atStart = EdgeAxis(g, edge)
    local field = (axis == "row") and "row" or "col"
    local last = ((axis == "row") and rows or cols) - 1
    for _, rec in ipairs(Store.IconsOf(g)) do
        local gp = rec.gpos
        if gp and gp[field] then
            if add then
                if atStart then gp[field] = gp[field] + 1 end
            elseif gp[field] == (atStart and 0 or last) then
                rec.gpos = nil
            elseif atStart and gp[field] > 0 then
                gp[field] = gp[field] - 1
            end
        end
    end
    Store.SetOverride(g, "arrangement", (axis == "row") and "rows" or "cols",
        last + 1 + (add and 1 or -1))
    Store.Dirty("tree")
    return true
end

-- Queries

function Store.Layouts()
    local out = {}
    for _, rec in pairs(DB.records) do
        if rec.type == "layout" then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Store.ChildrenOf(layout)
    local groups, freeIcons, bars = {}, {}, {}
    for _, mid in ipairs(layout.members or {}) do
        local rec = DB.records[mid]
        if rec then
            if rec.type == "group" then groups[#groups + 1] = rec
            elseif rec.type == "icon" then freeIcons[#freeIcons + 1] = rec
            elseif rec.type == "bar" then bars[#bars + 1] = rec end
        end
    end
    return groups, freeIcons, bars
end

function Store.IconsOf(group)
    local out = {}
    for _, mid in ipairs(group.members or {}) do
        local rec = DB.records[mid]
        if rec and rec.type == "icon" then out[#out + 1] = rec end
    end
    return out
end

-- A group's icons and reminders in its member order: what the panel lists
-- under it (a reminder group holds both, its aura reminders being icons).
function Store.GroupMembers(group)
    local out = {}
    for _, mid in ipairs(group.members or {}) do
        local rec = DB.records[mid]
        if rec and (rec.type == "icon" or rec.type == "reminder") then out[#out + 1] = rec end
    end
    return out
end

-- A layout's children in its own member order, kinds mixed: the panel's order
-- (rail, layout page, export picker), which the rail drag rearranges. The
-- engine reads ChildrenOf, split by kind, so drawing never depends on it.
function Store.MembersOf(layout)
    local out = {}
    for _, mid in ipairs(layout.members or {}) do
        local rec = DB.records[mid]
        if rec and (rec.type == "group" or rec.type == "icon" or rec.type == "bar") then
            out[#out + 1] = rec
        end
    end
    return out
end

function Store.UI() return DB.ui end

-- A custom item's live state for this character (its timer's end and its
-- stacks), kept so a /reload picks it up where it was. Written by
-- Drivers\AD_DriverCustom.lua; plain numbers only.
function Store.Runtime(recId)
    local rt = DB.runtime
    local perChar = rt and rt[CharKey()]
    return perChar and perChar[recId] or nil
end

function Store.SetRuntime(recId, state)
    if not recId then return end
    DB.runtime = DB.runtime or {}
    local key = CharKey()
    local perChar = DB.runtime[key]
    if not perChar then
        if state == nil then return end
        perChar = {}
        DB.runtime[key] = perChar
    end
    perChar[recId] = state
end

-- iterate every record (drivers prebuild from this at ADDON_LOADED)
function Store.EachRecord(fn)
    for id, rec in pairs(DB.records) do
        fn(id, rec)
    end
end

-- Change notification

-- what: "tree" (records added/removed/moved), "style" (option values),
-- "load" (conditions). One coalesced rebuild per frame.
function Store.Dirty(what, id)
    Events.Fire("AD_DIRTY", what, id)
end

-- Import and export use their own serializer: foreign text must never reach
-- loadstring. Tokens:
--   n<num>;  b1/b0  s<len>:<bytes>  t <k><v>... e
-- Only string/number keys and string/number/boolean/table values survive, the
-- shapes records hold. The result is LibDeflate-compressed, EncodeForPrint'ed
-- and prefixed "!AUI2!"; import also accepts the older "!AD1!" (same payload).

local function SerVal(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "b1" or "b0"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        out[#out + 1] = "t"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number")
                and (vt == "string" or vt == "number"
                     or vt == "boolean" or vt == "table") then
                SerVal(k, out)
                SerVal(val, out)
            end
        end
        out[#out + 1] = "e"
    end
end

local function DeserVal(str, pos, depth)
    depth = (depth or 0) + 1
    if depth > 32 or not pos or pos > #str then return nil, nil, "corrupt data" end
    local c = str:sub(pos, pos)
    if c == "n" then
        local e = str:find(";", pos + 1, true)
        if not e then return nil, nil, "corrupt number" end
        local num = tonumber(str:sub(pos + 1, e - 1))
        if not num then return nil, nil, "corrupt number" end
        return num, e + 1
    elseif c == "b" then
        return str:sub(pos + 1, pos + 1) == "1", pos + 2
    elseif c == "s" then
        local col = str:find(":", pos + 1, true)
        if not col then return nil, nil, "corrupt string" end
        local len = tonumber(str:sub(pos + 1, col - 1))
        if not len or len < 0 or len > #str then return nil, nil, "corrupt string" end
        local s = str:sub(col + 1, col + len)
        if #s ~= len then return nil, nil, "truncated string" end
        return s, col + len + 1
    elseif c == "t" then
        local tbl = {}
        pos = pos + 1
        local guard = 0
        while true do
            if pos > #str then return nil, nil, "unterminated table" end
            if str:sub(pos, pos) == "e" then return tbl, pos + 1 end
            guard = guard + 1
            if guard > 200000 then return nil, nil, "corrupt table" end
            local k, np, err = DeserVal(str, pos, depth)
            if err then return nil, nil, err end
            local v
            v, np, err = DeserVal(str, np, depth)
            if err then return nil, nil, err end
            if k ~= nil then tbl[k] = v end
            pos = np
        end
    end
    return nil, nil, "corrupt token"
end

local function GetDeflate()
    return (LibStub and LibStub:GetLibrary("LibDeflate", true)) or _G.LibDeflate
end

-- An item exported without its layout must look the same wherever it lands, so
-- the copy takes the layout's value for every row that applies to its kind and
-- that it does not set itself. `orig` is the live record it was copied from.
-- A character list names the maker's characters: never anyone else's.
local function DropPersonal(rec)
    if type(rec.c) == "table" then rec.c.chars = nil end
    -- a wheel's key is its maker's own binding
    rec.wheelKey = nil
end

-- The maker's Save as Default looks (newDefaults) sit under every record's own
-- and its layout's, and no string carries them: an exported record takes the
-- ones it follows. `lay`: its layout when that travels too (its looks win).
local function BakeDefaults(copy, orig, lay)
    local nd = DB.newDefaults and DB.newDefaults[FamilyKey(orig)]
    if type(nd) ~= "table" then return end
    local fam = Schema[Store.FamilyOf(orig)]
    local famKey = FAMILY_OF_TYPE[orig.type]
    local linh = lay and type(lay.inh) == "table" and famKey and lay.inh[famKey] or nil
    copy.o = copy.o or {}
    for section, vals in pairs(nd) do
        local sec = fam and fam[section]
        if sec and type(vals) == "table" then
            for field, v in pairs(vals) do
                local def = sec.fields[field]
                local byLayout = linh and linh[section] and linh[section][field] ~= nil
                if def and not byLayout and Schema.Applies(def, sec, Store.KindOf(orig), orig.barMode) then
                    local o = copy.o[section] or {}
                    if o[field] == nil then o[field] = CopyDeep(v) end
                    copy.o[section] = o
                end
            end
        end
    end
end

local function BakeLook(copy, orig)
    local fi = InhOf(orig)
    if not fi then return end
    local fam = Schema[Store.FamilyOf(orig)]
    copy.o = copy.o or {}
    for section, vals in pairs(fi) do
        local sec = fam and fam[section]
        if sec then
            for field, v in pairs(vals) do
                local def = sec.fields[field]
                if def and Schema.Applies(def, sec, Store.KindOf(orig), orig.barMode) then
                    local o = copy.o[section] or {}
                    if o[field] == nil then o[field] = CopyDeep(v) end
                    copy.o[section] = o
                end
            end
        end
    end
end

-- Exports any set of records: each id, and a group's icons with it. A layout
-- in the set carries its own settings, position and conditions; which of its
-- children come along is the caller's pick, so its member list is trimmed to
-- the set. Whole records go (o, c, gpos, driver), so an import is a faithful
-- clone. Returns the string and the record count, or nil and a reason.
-- keep (optional): a record test; one that fails it stays out of the string,
-- and so does a left-out icon of a group that goes in.
function Store.Export(ids, keep)
    if type(ids) ~= "table" then ids = { ids } end
    local LD = GetDeflate()
    if not LD then return nil, "LibDeflate did not load" end
    local seen, recs = {}, {}
    local taken
    local function add(rec)
        if not rec or seen[rec.id] then return end
        if keep and not keep(rec) then return end
        seen[rec.id] = true
        -- the ID is saved on the item itself, so every later export of it
        -- carries the same one
        if not ValidUid(rec.uid) then
            taken = taken or UidSet()
            rec.uid = NewUid(taken)
        end
        recs[#recs + 1] = CopyDeep(rec)
        if rec.type == "group" then
            for _, mid in ipairs(rec.members or {}) do add(DB.records[mid]) end
        end
    end
    for _, id in ipairs(ids) do add(DB.records[id]) end
    if #recs == 0 then return nil, "nothing ticked to export" end
    for _, rec in ipairs(recs) do
        -- a layout or group lists only the members that travel with it
        if rec.type == "layout" or rec.type == "group" then
            local m = {}
            for _, mid in ipairs(rec.members or {}) do
                if seen[mid] then m[#m + 1] = mid end
            end
            rec.members = m
        end
        if rec.type ~= "layout" then
            -- its layout is not in the string: its looks travel baked in
            local orig = DB.records[rec.id]
            local lay = orig and Store.LayoutOf(orig)
            if lay and not seen[lay.id] then BakeLook(rec, orig) end
            -- so do the maker's own saved defaults, which no string carries
            if orig then BakeDefaults(rec, orig, lay and seen[lay.id] and lay or nil) end
        end
        DropPersonal(rec)
    end
    -- at: when it was made, so a later string can tell newer from older;
    -- made / need: the version that made it and the format it needs
    local payload = { v = 1, kind = "adlayout", records = recs, at = time and time() or 0,
        made = Store.AddonVersion(), need = Store.FORMAT }
    local out = {}
    SerVal(payload, out)
    local comp = LD:CompressDeflate(table.concat(out))
    return "!AUI2!" .. LD:EncodeForPrint(comp), #recs
end

function Store.ExportLayout(layoutId)
    local layout = DB.records[layoutId]
    if not layout or layout.type ~= "layout" then return nil, "no such layout" end
    local ids = { layoutId }
    for _, mid in ipairs(layout.members or {}) do ids[#ids + 1] = mid end
    return Store.Export(ids)
end

-- Every imported id is remapped to a fresh one, so imports never collide with
-- existing records, and Normalize() clamps every override against the schema,
-- so a tampered string degrades to defaults. Each layout in the string becomes
-- a new one; anything whose parent is not in it lands in the target:
-- `targetLayoutId`, else the first imported layout, else a new "Imported" one.
-- `opts.emptyGroups` brings each group in without its icons. A reminder that
-- comes without its group joins `opts.reminderGroupId` (a Reminder group),
-- else a new one in the target.
-- Returns { layouts, items, target, dropped = icons and reminders left out,
-- reminders, reminderGroup, refused = names of reminders the group had }, or
-- nil and a reason.
-- The string's payload, or nil and a reason. A string that needs a newer
-- format than this version reads (payload.need) is refused by name; one
-- made by a newer version still imports, what this one does not know left
-- out (Store.NewerMaker says so).
local function DecodeString(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then return nil, "paste an export string first" end
    local body
    if text:sub(1, 6) == "!AUI2!" then
        body = text:sub(7)
    elseif text:sub(1, 5) == "!AD1!" then
        body = text:sub(6)
    else
        return nil, "not an Arc Auras export string"
    end
    local LD = GetDeflate()
    if not LD then return nil, "LibDeflate did not load" end
    local comp = LD:DecodeForPrint(body)
    if not comp then return nil, "corrupt string (bad characters)" end
    local raw = LD:DecompressDeflate(comp)
    if not raw then return nil, "corrupt string (bad compression)" end
    local payload, _, err = DeserVal(raw, 1)
    if err or type(payload) ~= "table" or payload.v ~= 1
        or payload.kind ~= "adlayout" or type(payload.records) ~= "table" then
        return nil, err or "corrupt string (bad payload)"
    end
    local need = tonumber(payload.need)
    if need and need > Store.FORMAT then
        return nil, ("this string was made with Arc Auras %s and needs a newer version: update Arc Auras to import it")
            :format(tostring(payload.made or "(newer)"))
    end
    return payload
end

function Store.Import(text, targetLayoutId, opts)
    local payload, err = DecodeString(text)
    if not payload then return nil, err end

    local VALID = { layout = true, group = true, icon = true, bar = true, reminder = true }
    -- opts.emptyGroups: a group in the string arrives without its icons (an
    -- icon exported alone, its group left home, still comes in). A reminder
    -- exported alone is set aside for a Reminder group here (`lone`).
    local dropIn, groupsIn, lone = {}, {}, {}
    for _, rec in ipairs(payload.records) do
        if type(rec) == "table" and rec.type == "group" and rec.id ~= nil then
            groupsIn[rec.id] = true
            if opts and opts.emptyGroups then dropIn[rec.id] = true end
        end
    end
    local map, newRecs, layouts, dropped = {}, {}, {}, 0
    -- An item keeps the ID it came with, so a later version of the string
    -- can find it; one this account already has (the same string twice, or
    -- a player's own export back) comes in as a copy with a fresh ID, and
    -- opts.asCopy gives every item a fresh one (a copy linked to no pack).
    local taken = UidSet()
    local at = tonumber(payload.at)
    at = (at and at >= 0) and math.floor(at) or 0
    local copied = {}
    for _, rec in ipairs(payload.records) do
        if type(rec) == "table" then
            if ValidUid(rec.uid) and not taken[rec.uid] and not (opts and opts.asCopy) then
                taken[rec.uid] = true
            else
                rec.uid = NewUid(taken)
                copied[rec] = true
            end
            rec.imported = at
            DropPersonal(rec)
        end
    end
    for _, rec in ipairs(payload.records) do
        if type(rec) == "table" and rec.id ~= nil and VALID[rec.type] then
            if (rec.type == "icon" or rec.type == "reminder") and rec.groupId ~= nil and dropIn[rec.groupId] then
                dropped = dropped + 1
            elseif rec.type == "reminder" and not groupsIn[rec.groupId] then
                lone[#lone + 1] = rec
            else
                local nid = NewId()
                map[rec.id] = nid
                rec.id = nid
                newRecs[#newRecs + 1] = rec
                if rec.type == "layout" then layouts[#layouts + 1] = rec end
            end
        end
    end
    if #newRecs == 0 and #lone == 0 then return nil, "string holds nothing to import" end

    -- layouts first, so loose records have somewhere to land. A first import
    -- is the pack as its maker left it (a later update compares against it);
    -- a copy of one already here is named so and nudged off it.
    for _, rec in ipairs(layouts) do
        if type(rec.members) ~= "table" then rec.members = {} end
        rec.pos = type(rec.pos) == "table" and rec.pos or {}
        if copied[rec] then
            rec.name = tostring(rec.name or "Layout") .. " (import)"
            rec.pos.x = (tonumber(rec.pos.x) or 0) + 24
            rec.pos.y = (tonumber(rec.pos.y) or 0) - 24
        elseif rec.name == nil then
            rec.name = "Layout"
        end
        DB.records[rec.id] = rec
    end
    local target = Store.Get(targetLayoutId)
    if target and target.type ~= "layout" then target = nil end
    local items = {}
    for _, rec in ipairs(newRecs) do
        if type(rec.members) == "table" then
            local m = {}
            for _, old in ipairs(rec.members) do
                if map[old] then m[#m + 1] = map[old] end
            end
            rec.members = m
        end
        if rec.groupId ~= nil then rec.groupId = map[rec.groupId] end
        if rec.layoutId ~= nil then rec.layoutId = map[rec.layoutId] end
        RemapAnchors(rec, map, false)
        RemapRules(rec, map, false)
        if rec.type ~= "layout" and not rec.groupId and not rec.layoutId then
            -- a loose record (its parent is not in the string): a free
            -- child of the target layout rather than vanishing
            if not target then
                target = layouts[1] or Store.NewLayout("Imported")
                if type(target.members) ~= "table" then target.members = {} end
            end
            rec.layoutId = target.id
            rec.gpos = nil
            if rec.type == "icon" and type(rec.pos) ~= "table" then
                rec.pos = { x = 0, y = -60 }
            end
            target.members[#target.members + 1] = rec.id
            items[#items + 1] = rec
        end
        if rec.type ~= "layout" then DB.records[rec.id] = rec end
    end
    -- A lone reminder joins the picked Reminder group, else a new one placed
    -- like any. A group keeps one reminder per spell, item or hand (the Add
    -- window's rule): one it has already stays out, named in `refused`.
    local reminders, refused, rgroup = {}, {}, nil
    if #lone > 0 then
        rgroup = Store.Get(opts and opts.reminderGroupId)
        if not (rgroup and rgroup.type == "group" and rgroup.groupKind == "reminder") then rgroup = nil end
        local function Key(r)
            local d = type(r.driver) == "table" and r.driver or {}
            if r.kind == "enchant" then return "enchant:" .. ((d.hand == "off") and "off" or "main") end
            local item = r.kind == "item"
            local n = tonumber(d[item and "itemID" or "spellID"])
            return (item and "item:" or "spell:") .. tostring(n and math.floor(n) or "?")
        end
        for _, rec in ipairs(lone) do
            local have = false
            for _, r in ipairs(rgroup and Store.RemindersOf(rgroup) or {}) do
                if Key(r) == Key(rec) then have = true end
            end
            if have then
                refused[#refused + 1] = tostring(rec.name or "?")
            else
                if not rgroup then
                    if not target then
                        target = layouts[1] or Store.NewLayout("Imported")
                        if type(target.members) ~= "table" then target.members = {} end
                    end
                    rgroup = Store.NewGroup(target.id, "Reminders", "reminder")
                end
                rec.id = NewId()
                rec.groupId = rgroup.id
                rgroup.members[#rgroup.members + 1] = rec.id
                DB.records[rec.id] = rec
                reminders[#reminders + 1] = rec
            end
        end
        if #newRecs == 0 and #reminders == 0 then
            return nil, ("\"%s\" already has a reminder for %s: pick another Reminder group, or a new one.")
                :format(tostring(rgroup and rgroup.name or "?"), table.concat(refused, ", "))
        end
    end
    Store.Normalize()
    Store.Dirty("tree")
    return { layouts = layouts, items = items, target = target, dropped = dropped,
        reminders = reminders, reminderGroup = rgroup, refused = refused }
end

-- One-layout form of Import: the first imported layout, or where the loose
-- items landed.
function Store.ImportLayout(text)
    local res, err = Store.Import(text)
    if not res then return nil, err end
    return res.layouts[1] or res.target
end

-- Pack updates: a string's items find the ones an earlier version of it made
-- (rec.uid). The player updates the chosen parts of each in place, adds what
-- is new and removes pack items the string no longer has, or imports a copy.
-- The parts follow the editor tabs; Size & Position (placement, anchors,
-- sizes, strata, mouse) starts off, so the player's own placement stays.
Store.UPDATE_PARTS = { "tracking", "appearance", "showhide", "glows", "sounds", "text", "load", "names",
    "arrange", "position" }
Store.UPDATE_PART_LABELS = { tracking = "Tracking", appearance = "Appearance", showhide = "Show & Hide",
    glows = "Glows", sounds = "Sounds", text = "Text", load = "Load Conditions", names = "Names",
    arrange = "Group layout", position = "Size & Position" }
Store.UPDATE_PART_OFF = { position = true }

-- Every settings section's part, by family; t_adupdate fails on a section
-- missing here, so no setting is ever skipped by an update.
local PART_OF_SECTION = {
    icon = { alerts = "sounds", anchor = "position", appearance = "appearance", auraActive = "showhide",
        auraMissing = "showhide", auraSwipe = "appearance", groupBuff = "tracking", keybind = "text",
        label = "text", mouse = "position", outOfStock = "showhide", position = "position",
        pulse = "appearance", special = "appearance", states = "showhide", swipe = "appearance",
        text = "text", trinket = "tracking" },
    bar = { abilcolors = "appearance", anchor = "position", behavior = "showhide", cast = "appearance",
        fill = "appearance", frame = "position", healpred = "appearance", healththresholds = "appearance",
        icon = "appearance", look = "appearance", powerthresholds = "appearance", predict = "appearance",
        range = "appearance", regen = "appearance", resource = "appearance", segments = "appearance",
        size = "position",
        stackcolors = "appearance", texlook = "appearance", text = "text", textel = "text",
        thresholds = "appearance", ticks = "appearance", wheel = "appearance" },
    iconGroup = { anchor = "position", arrangement = "arrange", audio = "sounds", frame = "position",
        keybind = "text", look = "appearance", mouse = "position", pulse = "appearance",
        unitAuras = "tracking" },
    layout = { mouse = "position" },
    reminder = { pulse = "appearance" },
}
-- fields whose part is not their section's
local PART_OF_FIELD = {
    ["bar.size.opacity"] = "appearance", ["bar.behavior.clickable"] = "position",
    ["bar.behavior.gcdMode"] = "tracking", ["iconGroup.arrangement.iconSize"] = "position",
    ["iconGroup.arrangement.iconWidth"] = "position", ["iconGroup.arrangement.iconHeight"] = "position",
    ["iconGroup.pulse.size"] = "position", ["reminder.pulse.size"] = "position",
}
Store.PART_OF_SECTION = PART_OF_SECTION

-- nil: a section no part knows (kept as the player has it)
function Store.PartOf(family, section, field)
    local p = field and PART_OF_FIELD[family .. "." .. section .. "." .. field]
    if p then return p end
    if type(field) == "string" then
        if field:find("Glow", 1, true) then return "glows" end
        if field:find("[Ss]ound") or field:find("^tts") then return "sounds" end
    end
    local fam = PART_OF_SECTION[family]
    return fam and fam[section] or nil
end

-- the record's own keys; placement (pos, gpos, groupId, layoutId) and the
-- member order are handled apart
local PART_OF_KEY = { name = "names", driver = "tracking", triggers = "tracking", kind = "tracking",
    barKind = "tracking", barMode = "tracking", groupKind = "tracking" }

-- conditions: the fade and show rules are Show & Hide, the rest is Load;
-- a character list is the player's own (nil: never updated)
local function CondPart(key)
    if key == "chars" then return nil end
    if key:find("^fade") or key:find("^showWhen") or key:find("^range") then return "showhide" end
    return "load"
end

local function SameData(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not SameData(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- One part of a record as flat keys, for telling what an update changes.
-- uidOf: a member id's uid, so a member order reads the same on both sides.
local function PartSlice(rec, part, uidOf)
    local fam = Store.FamilyOf(rec)
    local out = {}
    for k, p in pairs(PART_OF_KEY) do
        if p == part and rec[k] ~= nil then out["." .. k] = rec[k] end
    end
    for s, vals in pairs(type(rec.o) == "table" and rec.o or {}) do
        if type(vals) == "table" then
            for f, v in pairs(vals) do
                if Store.PartOf(fam, s, f) == part then out[s .. "." .. f] = v end
            end
        end
    end
    for k, v in pairs(type(rec.c) == "table" and rec.c or {}) do
        if CondPart(k) == part then out["c." .. k] = v end
    end
    if rec.type == "layout" and type(rec.inh) == "table" then
        for fk, secs in pairs(rec.inh) do
            for s, vals in pairs(type(secs) == "table" and secs or {}) do
                for f, v in pairs(type(vals) == "table" and vals or {}) do
                    if Store.PartOf(fk, s, f) == part then out["inh." .. fk .. "." .. s .. "." .. f] = v end
                end
            end
        end
    end
    if part == "position" then
        out[".pos"], out[".gpos"] = rec.pos, rec.gpos
        out[".groupId"], out[".layoutId"] = rec.groupId, rec.layoutId
    elseif part == "arrange" and type(rec.members) == "table" then
        -- the order of the members both sides have (uidOf skips the rest):
        -- items added or dropped are Add / Remove, never a change of order
        local m = {}
        for _, mid in ipairs(rec.members) do
            local u = uidOf(mid)
            if u then m[#m + 1] = u end
        end
        out[".members"] = m
    end
    return out
end

-- A copy of an incoming record whose links read as local ids: anchors, rules,
-- its container (one not in the string reads as the player's own, since an
-- update cannot move it there), members through their uids.
local function LocalView(inc, loc, map)
    local v = CopyDeep(inc)
    DropPersonal(v)
    RemapAnchors(v, map, false)
    RemapRules(v, map, false)
    for _, k in ipairs({ "groupId", "layoutId" }) do
        if v[k] ~= nil then v[k] = map[v[k]] end
    end
    if v.groupId == nil and v.layoutId == nil and inc.groupId == nil and inc.layoutId == nil then
        v.groupId, v.layoutId = loc.groupId, loc.layoutId
    elseif (inc.groupId ~= nil and v.groupId == nil) or (inc.layoutId ~= nil and v.layoutId == nil) then
        v.groupId, v.layoutId = loc.groupId, loc.layoutId
    end
    return v
end

local SHARE_TYPES = { layout = true, group = true, icon = true, bar = true, reminder = true }

-- What a string would do here, without doing it: nil and a reason for a bad
-- string, else { items = { { inc, loc, status = new / changed / same, parts }
-- }, gone = records, counts, relation = new / same / older / update, at,
-- localAt, made, newer }. relation "new": nothing of it is here (a plain
-- import); "older": made before the copy here was.
function Store.PlanUpdate(text)
    local payload, err = DecodeString(text)
    if not payload then return nil, err end
    local byUid = {}
    for _, r in pairs(DB.records) do
        if ValidUid(r.uid) then byUid[r.uid] = r end
    end
    local inc, inUids = {}, {}
    for _, r in ipairs(payload.records) do
        if type(r) == "table" and r.id ~= nil and SHARE_TYPES[r.type] then
            inc[#inc + 1] = r
            if ValidUid(r.uid) then inUids[r.uid] = true end
        end
    end
    -- incoming id -> local id; a new record reads as a mark of its own, so a
    -- link to it always differs from the player's
    local map, incUid = {}, {}
    for _, r in ipairs(inc) do
        local loc = ValidUid(r.uid) and byUid[r.uid] or nil
        map[r.id] = (loc and loc.type == r.type) and loc.id or ("new:" .. tostring(r.id))
        incUid[r.id] = r.uid
    end
    local at = tonumber(payload.at)
    local plan = { payload = payload, items = {}, gone = {}, map = map,
        at = (at and at >= 0) and math.floor(at) or 0, made = payload.made,
        newer = Store.NewerMaker(payload.made), matched = 0, changed = 0, new = 0, same = 0 }
    local localAt
    -- the layouts here that the string carries: an item under one of them was
    -- exported with its looks inherited, any other with them baked in
    local layIn = {}
    for _, r in ipairs(inc) do
        if r.type == "layout" and type(map[r.id]) == "number" then layIn[map[r.id]] = true end
    end
    for _, r in ipairs(inc) do
        local lid = map[r.id]
        local loc = type(lid) == "number" and DB.records[lid] or nil
        local item = { inc = r, loc = loc, name = r.name, type = r.type, parts = {} }
        if loc then
            plan.matched = plan.matched + 1
            local view = LocalView(r, loc, map)
            -- the local side read as an export of it would read (the maker's
            -- own items inherit what their string carries baked in)
            local mine = loc
            if loc.type ~= "layout" then
                mine = CopyDeep(loc)
                local lay = Store.LayoutOf(loc)
                local carried = lay and layIn[lay.id]
                if lay and not carried then BakeLook(mine, loc) end
                BakeDefaults(mine, loc, carried and lay or nil)
            end
            -- a container's order counts only the members it holds on both
            -- sides (one kept elsewhere by the player is not a change)
            local here, there = {}, {}
            for _, mid in ipairs(type(loc.members) == "table" and loc.members or {}) do
                local m = DB.records[mid]
                if m and m.uid then here[m.uid] = true end
            end
            for _, mid in ipairs(type(r.members) == "table" and r.members or {}) do
                if incUid[mid] then there[incUid[mid]] = true end
            end
            local localUid = function(mid)
                local m = DB.records[mid]
                local u = m and m.uid
                return (u and there[u]) and u or nil
            end
            local viewUid = function(mid)
                local u = incUid[mid]
                return (u and here[u]) and u or nil
            end
            local any = false
            for _, p in ipairs(Store.UPDATE_PARTS) do
                if not SameData(PartSlice(mine, p, localUid), PartSlice(view, p, viewUid)) then
                    item.parts[p] = true
                    any = true
                end
            end
            item.status = any and "changed" or "same"
            if any then plan.changed = plan.changed + 1 else plan.same = plan.same + 1 end
            local la = tonumber(loc.imported)
            if la and la > 0 and (not localAt or la > localAt) then localAt = la end
        else
            item.status = "new"
            plan.new = plan.new + 1
        end
        plan.items[#plan.items + 1] = item
    end
    -- the pack's own items the string no longer has, inside what it matched
    local seen = {}
    for _, item in ipairs(plan.items) do
        local loc = item.loc
        if loc and (loc.type == "layout" or loc.type == "group") then
            for _, mid in ipairs(loc.members or {}) do
                local m = DB.records[mid]
                if m and not seen[mid] and m.imported ~= nil and not inUids[m.uid] then
                    seen[mid] = true
                    plan.gone[#plan.gone + 1] = m
                end
            end
        end
    end
    plan.localAt = localAt
    if plan.matched == 0 then
        plan.relation = "new"
    elseif plan.changed == 0 and plan.new == 0 and #plan.gone == 0 then
        plan.relation = "same"
    elseif localAt and plan.at > 0 and plan.at < localAt then
        plan.relation = "older"
    else
        plan.relation = "update"
    end
    return plan
end

local function Contains(list, id)
    for _, v in ipairs(list or {}) do
        if v == id then return true end
    end
    return false
end

-- Size & Position's placement: the container the string puts it in (when
-- that container is in the string) and its spot there.
local function Place(loc, view)
    if loc.type == "icon" then
        if view.groupId ~= nil and view.groupId ~= loc.groupId then
            if not Store.MoveIcon(loc.id, view.groupId, nil, nil, view.gpos) then return end
        elseif view.groupId == nil and view.layoutId ~= nil and (loc.groupId ~= nil or loc.layoutId ~= view.layoutId) then
            if not Store.MoveIcon(loc.id, nil, view.layoutId, view.pos) then return end
        end
    elseif (loc.type == "bar" or loc.type == "group") and view.layoutId ~= nil and view.layoutId ~= loc.layoutId then
        Store.MoveToLayout(loc.id, view.layoutId)
    end
    if loc.groupId ~= nil then
        loc.gpos = CopyDeep(view.gpos)
    else
        loc.pos = CopyDeep(view.pos)
    end
end

-- One part of a matched record, from its local view.
local function ApplyPart(loc, view, part, map)
    local fam = Store.FamilyOf(loc)
    for k, p in pairs(PART_OF_KEY) do
        if p == part then loc[k] = CopyDeep(view[k]) end
    end
    local secs = {}
    for s in pairs(type(loc.o) == "table" and loc.o or {}) do secs[s] = true end
    for s in pairs(type(view.o) == "table" and view.o or {}) do secs[s] = true end
    for s in pairs(secs) do
        local lo, vo = loc.o and loc.o[s], view.o and view.o[s]
        local fields = {}
        for f in pairs(type(lo) == "table" and lo or {}) do fields[f] = true end
        for f in pairs(type(vo) == "table" and vo or {}) do fields[f] = true end
        for f in pairs(fields) do
            if Store.PartOf(fam, s, f) == part then
                local v = type(vo) == "table" and vo[f] or nil
                loc.o = loc.o or {}
                if v == nil then
                    if type(loc.o[s]) == "table" then loc.o[s][f] = nil end
                else
                    loc.o[s] = type(loc.o[s]) == "table" and loc.o[s] or {}
                    loc.o[s][f] = CopyDeep(v)
                end
            end
        end
        if loc.o and type(loc.o[s]) == "table" and next(loc.o[s]) == nil then loc.o[s] = nil end
    end
    local keys = {}
    for k in pairs(type(loc.c) == "table" and loc.c or {}) do keys[k] = true end
    for k in pairs(type(view.c) == "table" and view.c or {}) do keys[k] = true end
    for k in pairs(keys) do
        if CondPart(k) == part then
            loc.c = loc.c or {}
            loc.c[k] = CopyDeep(view.c and view.c[k])
        end
    end
    if loc.type == "layout" then
        local fks = {}
        for fk in pairs(type(loc.inh) == "table" and loc.inh or {}) do fks[fk] = true end
        for fk in pairs(type(view.inh) == "table" and view.inh or {}) do fks[fk] = true end
        for fk in pairs(fks) do
            local ls = loc.inh and loc.inh[fk] or {}
            local vs = view.inh and view.inh[fk] or {}
            local ss = {}
            for s in pairs(ls) do ss[s] = true end
            for s in pairs(vs) do ss[s] = true end
            for s in pairs(ss) do
                local fields = {}
                for f in pairs(type(ls[s]) == "table" and ls[s] or {}) do fields[f] = true end
                for f in pairs(type(vs[s]) == "table" and vs[s] or {}) do fields[f] = true end
                for f in pairs(fields) do
                    if Store.PartOf(fk, s, f) == part then
                        local v = type(vs[s]) == "table" and vs[s][f] or nil
                        loc.inh = loc.inh or {}
                        loc.inh[fk] = loc.inh[fk] or {}
                        loc.inh[fk][s] = loc.inh[fk][s] or {}
                        loc.inh[fk][s][f] = CopyDeep(v)
                    end
                end
            end
        end
    end
    if part == "position" then
        Place(loc, view)
    elseif part == "arrange" and type(loc.members) == "table" then
        -- the string's order for members in both, the player's own after them
        local order, set = {}, {}
        for _, iid in ipairs(type(view.members) == "table" and view.members or {}) do
            local lid = map[iid]
            if type(lid) == "number" and Contains(loc.members, lid) and not set[lid] then
                order[#order + 1] = lid
                set[lid] = true
            end
        end
        for _, id in ipairs(loc.members) do
            if not set[id] then order[#order + 1] = id end
        end
        loc.members = order
    end
end

-- Applies a plan. opts: parts = { [part] = true } (default: every part but
-- Size & Position), add (new items, default on), remove (the pack items the
-- string dropped, default on), skip = { [uid] = true } (items left alone),
-- targetLayoutId (where new loose items land). A group that holds the
-- player's own items is never removed. Returns { updated, added, removed,
-- target }.
function Store.ApplyUpdate(plan, opts)
    opts = opts or {}
    local parts = opts.parts
    if not parts then
        parts = {}
        for _, p in ipairs(Store.UPDATE_PARTS) do
            if not Store.UPDATE_PART_OFF[p] then parts[p] = true end
        end
    end
    local map = {}
    for _, item in ipairs(plan.items) do
        if item.loc then map[item.inc.id] = item.loc.id end
    end
    local adds = {}
    if opts.add ~= false then
        for i, item in ipairs(plan.items) do
            if item.status == "new" then
                map[item.inc.id] = NewId()
                adds[#adds + 1] = { item = item, i = i }
            end
        end
    end
    local RANK = { layout = 1, group = 2 }
    table.sort(adds, function(a, b)
        local ra, rb = RANK[a.item.type] or 3, RANK[b.item.type] or 3
        if ra ~= rb then return ra < rb end
        return a.i < b.i
    end)
    local target = Store.Get(opts.targetLayoutId)
    if target and target.type ~= "layout" then target = nil end
    if not target then
        for _, item in ipairs(plan.items) do
            if item.loc and item.loc.type == "layout" then target = item.loc break end
        end
    end
    local taken = UidSet()
    local res = { updated = 0, added = 0, removed = 0 }
    for _, a in ipairs(adds) do
        local rec = CopyDeep(a.item.inc)
        rec.id = map[a.item.inc.id]
        if ValidUid(rec.uid) and not taken[rec.uid] then taken[rec.uid] = true else rec.uid = NewUid(taken) end
        rec.imported = plan.at
        DropPersonal(rec)
        RemapAnchors(rec, map, false)
        RemapRules(rec, map, false)
        -- a new container fills as its items arrive; matched ones join it
        -- only through Size & Position
        if type(rec.members) == "table" then rec.members = {} end
        rec.groupId = rec.groupId ~= nil and map[rec.groupId] or nil
        rec.layoutId = rec.layoutId ~= nil and map[rec.layoutId] or nil
        DB.records[rec.id] = rec
        if rec.type ~= "layout" then
            local parent = (rec.groupId and DB.records[rec.groupId]) or (rec.layoutId and DB.records[rec.layoutId])
            if not parent then
                target = target or Store.NewLayout("Imported")
                if type(target.members) ~= "table" then target.members = {} end
                rec.groupId, rec.gpos, rec.layoutId = nil, nil, target.id
                if type(rec.pos) ~= "table" then rec.pos = { x = 0, y = -60 } end
                parent = target
            end
            parent.members = type(parent.members) == "table" and parent.members or {}
            if not Contains(parent.members, rec.id) then parent.members[#parent.members + 1] = rec.id end
        end
        res.added = res.added + 1
    end
    for _, item in ipairs(plan.items) do
        local loc = item.loc
        if loc and DB.records[loc.id] == loc then
            if item.status == "changed" and not (opts.skip and opts.skip[item.inc.uid]) then
                local view = LocalView(item.inc, loc, map)
                local touched = false
                for _, p in ipairs(Store.UPDATE_PARTS) do
                    if parts[p] and item.parts[p] then
                        ApplyPart(loc, view, p, map)
                        touched = true
                    end
                end
                if touched then res.updated = res.updated + 1 end
            end
            loc.imported = plan.at
        end
    end
    if opts.remove ~= false then
        for _, m in ipairs(plan.gone) do
            local keep = false
            if m.type == "group" then
                for _, mid in ipairs(m.members or {}) do
                    local r = DB.records[mid]
                    if r and r.imported == nil then keep = true end
                end
            end
            if not keep and m.type ~= "layout" and DB.records[m.id] == m then
                Store.Delete(m.id)
                res.removed = res.removed + 1
            elseif keep then
                -- the pack let it go and the player's own items live in it:
                -- it is theirs now, never offered for removal again
                m.imported = nil
            end
        end
    end
    res.target = target
    Store.Normalize()
    Store.Dirty("tree")
    return res
end
