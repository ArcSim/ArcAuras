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
-- rec = { id, type = "layout"|"group"|"icon"|"bar", name, v = schema version,
--   layout: pos={x,y}, members={childId,...},
--           inh = { [family] = { [section] = { [field] = value } } }
--           (the layout tier: looks its icons, groups and bars follow)
--   group:  layoutId, groupKind="cooldown"|"aura", pos={x,y},
--           members={iconId,...}
--   icon:   kind, driver={...}, and groupId + gpos={row,col} in a group,
--           or layoutId + pos={x,y} when free
--   bar:    layoutId, barKind, barMode, driver={...}, pos={x,y}
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

function Store.CurSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    local id = GetSpecializationInfo(idx)
    return id
end

-- Spec-less realms (WoW Forever) list no specializations. Load conditions there
-- are class checkboxes writing c.classes, and a c.specs gate from a retail
-- import is ignored, since one that can never pass would hide the record for
-- good. Class 1 (Warrior) exists on every client: its spec count is the probe.
local speclessCache
local function Specless()
    if speclessCache == nil then
        speclessCache = NS.IsForever == true
            or ((GetNumSpecializationsForClassID
                and GetNumSpecializationsForClassID(1)) or 0) == 0
    end
    return speclessCache
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

-- Normalize enforces the schema: drops dangling member ids, clamps typed fields
-- and discards overrides for unknown fields. Runs at login and after every
-- import. The folds run before the unknown-field strip at the end of the loop,
-- which would otherwise drop the retired keys they carry.
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
    for id, rec in pairs(DB.records) do
        rec.id = id
        rec.o = rec.o or {}
        rec.c = rec.c or {}
        if NS.IsForever == true and rec.c.chars then FoldCharKeys(rec.c.chars) end
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
                and rec.barKind ~= "cast" then
                rec.barKind = "cooldown"
            end
            if rec.barKind == "cooldown" or rec.barKind == "aura" then
                if rec.barMode ~= "stack" then rec.barMode = "duration" end
            else
                rec.barMode = nil
            end
            rec.pos = rec.pos or {}
            rec.pos.x = tonumber(rec.pos.x) or 0
            rec.pos.y = tonumber(rec.pos.y) or 0
            rec.driver = rec.driver or {}
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
        -- Per-record schema version that versioned folds key off; a new one
        -- bumps it and runs before this stamp.
        rec.v = 2
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
end

function Store.KindOf(rec)
    if rec.type == "icon" then return rec.kind end
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
    return def and def.d
end

function Store.SetOverride(rec, section, field, value)
    -- the layout editor's rows write through a proxy (Store.LayoutProxy):
    -- the value lands in the layout, for everything inside it
    if rec._adLayoutTier then
        Store.SetLayoutValue(rec._adLayout, rec._adFamily, section, field, value)
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
    if def.dk then return nil, false end
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
    if c.specs and not Specless() then
        local spec = Store.CurSpecID()
        if not (spec and c.specs[spec]) then return false end
    end
    -- Talents: the build-level gate, and the only one that means anything on
    -- a spec-less client. "all" needs every listed talent taken, "any" needs
    -- one. An empty set never gates.
    if c.talents and next(c.talents) then
        local cat = NS.TalentCatalog
        if cat then
            local anyTaken, allTaken = false, true
            for nodeID in pairs(c.talents) do
                if cat.IsTaken(nodeID) then anyTaken = true else allTaken = false end
            end
            if (c.talentMode == "any" and not anyTaken)
                or (c.talentMode ~= "any" and not allTaken) then
                return false
            end
        end
    end
    return true
end

-- Talent conditions

function Store.ToggleTalent(rec, nodeID)
    local c = rec.c
    c.talents = c.talents or {}
    if c.talents[nodeID] then c.talents[nodeID] = nil else c.talents[nodeID] = true end
    if not next(c.talents) then c.talents = nil end
    Store.Dirty("load")
end

function Store.ClearTalents(rec)
    if not rec.c.talents then return end
    rec.c.talents = nil
    Store.Dirty("load")
end

function Store.SetTalentMode(rec, mode)
    rec.c.talentMode = (mode == "any") and "any" or nil   -- "all" is the default
    Store.Dirty("load")
end

-- The chosen nodes, sorted by name, each with taken and known flags.
function Store.TalentList(rec)
    local out = {}
    local cat = NS.TalentCatalog
    for nodeID in pairs(rec.c.talents or {}) do
        local known = cat and cat.Known(nodeID)
        out[#out + 1] = {
            nodeID = nodeID,
            name = known and known.name or ("Talent " .. nodeID),
            icon = known and known.icon or 134400,
            taken = cat and cat.IsTaken(nodeID) or false,
            known = known ~= nil,
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
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
            local n = (GetNumSpecializationsForClassID
                and GetNumSpecializationsForClassID(classID)) or 0
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
    local full = true
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        for _, sp in ipairs(cls.specs) do
            if not set[sp.id] then full = false end
        end
    end
    rec.c.classes = nil
    rec.c.specs = full and nil or set
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
    local full = true
    for _, cls in ipairs(Store.ClassSpecMatrix()) do
        if not set[cls.tag] then full = false end
    end
    rec.c.specs = nil
    rec.c.classes = full and nil or set
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
    if not c.specs and not c.chars and not c.classes and not c.factions then
        return "Shared", false
    end
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
            for specID in pairs(c.specs) do
                local _, name = GetSpecializationInfoByID(specID)
                parts[#parts + 1] = name or tostring(specID)
            end
            table.sort(parts)
        end
    end
    if c.chars then parts[#parts + 1] = "chars" end
    if c.factions then
        local list = {}
        for fac in pairs(c.factions) do list[#list + 1] = fac end
        table.sort(list)
        parts[#parts + 1] = (#list == 0) and "nowhere" or table.concat(list, ", ")
    end
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
-- units match. A spot a sibling holds steps down by `step`; a layout frame with
-- no rect yet falls back to the layout's own centre.
local function CenterSpot(layoutId, step)
    local x, y = 0, 0
    local taken = {}
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
        local layout = DB.records[layoutId]
        for _, mid in ipairs(layout and layout.members or {}) do
            local m = DB.records[mid]
            if m and type(m.pos) == "table" then taken[#taken + 1] = m.pos end
        end
    else
        for _, r in pairs(DB.records) do
            if r.type == "layout" and type(r.pos) == "table" then taken[#taken + 1] = r.pos end
        end
    end
    local guard = 0
    while guard < 50 do
        local hit = false
        for _, p in ipairs(taken) do
            if math.abs((tonumber(p.x) or 0) - x) < 4 and math.abs((tonumber(p.y) or 0) - y) < 4 then
                hit = true
                break
            end
        end
        if not hit then break end
        y = y - step
        guard = guard + 1
    end
    return x, y
end

function Store.NewLayout(name)
    local id = NewId()
    local sx, sy = CenterSpot(nil, 60)
    DB.records[id] = {
        id = id, type = "layout",
        name = name or ("Layout " .. id),
        pos = { x = sx, y = sy },
        members = {}, o = {}, c = {},
    }
    Store.Dirty("tree")
    return DB.records[id]
end

-- Creation default for NewIcon and NewBar: the new record loads only for its
-- creator's spec (class on spec-less realms, where a spec set could never
-- pass); the user widens it from Load Conditions. Groups and layouts stay
-- shared: only the leaves are locked.
local function ScopeToCreator(rec)
    if Specless() then
        local tag = ClassTag()
        if tag then rec.c.classes = { [tag] = true } end
        return
    end
    local spec = Store.CurSpecID()
    if spec then rec.c.specs = { [spec] = true } end
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

function Store.NewGroup(layoutId, name, groupKind)
    local layout = Store.Get(layoutId)
    if not layout or layout.type ~= "layout" then return nil end
    local id = NewId()
    local sx, sy = CenterSpot(layoutId, 40)
    DB.records[id] = {
        id = id, type = "group",
        name = name or ("Group " .. id),
        groupKind = groupKind == "aura" and "aura" or "cooldown",
        layoutId = layoutId,
        pos = { x = sx, y = sy },
        members = {}, o = {}, c = {},
    }
    layout.members[#layout.members + 1] = id
    Store.Dirty("tree")
    return DB.records[id]
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
        -- Aura groups are aura-only; cooldown groups accept everything (aura
        -- icons sit in them as solid slots).
        if group.groupKind == "aura" and kind ~= "aura" then return nil end
        rec.groupId = destGroupId
        group.members[#group.members + 1] = id
    else
        local layout = Store.Get(layoutId)
        if not layout or layout.type ~= "layout" then return nil end
        rec.layoutId = layoutId
        local sx, sy = CenterSpot(layoutId, 42)
        rec.pos = { x = sx, y = sy }
        layout.members[#layout.members + 1] = id
    end
    DB.records[id] = rec
    Store.Dirty("tree")
    return rec
end

-- Bars are always free layout children, never group members: group attachment
-- is the anchor section. driver by kind: cooldown {spellID}, aura {spellID,
-- auraType, unit, caster, maxStacks}, swing {swingType}, resource {powerType},
-- health and cast {unit}, legacy timer {spellID, duration, triggerType},
-- legacy stack {powerType}; the bars runtime validates it. barMode
-- ("duration"|"stack") is the cooldown/aura sub-type, fixed at creation.
function Store.NewBar(layoutId, barKind, driver, name, barMode)
    local layout = Store.Get(layoutId)
    if not layout or layout.type ~= "layout" then return nil end
    if barKind ~= "timer" and barKind ~= "stack" and barKind ~= "swing"
        and barKind ~= "aura" and barKind ~= "resource" and barKind ~= "health"
        and barKind ~= "cast" then
        barKind = "cooldown"
    end
    local id = NewId()
    local rec = {
        id = id, type = "bar", barKind = barKind,
        name = name or ("Bar " .. id),
        layoutId = layoutId,
        driver = driver or {}, o = {}, c = {},
    }
    if barKind == "cooldown" or barKind == "aura" then
        rec.barMode = (barMode == "stack") and "stack" or "duration"
    end
    ScopeToCreator(rec)
    -- Creation template, written on the record only: the schema defaults
    -- stay off and a saved default wins.
    if barKind == "cooldown" or barKind == "aura" then
        TemplateSet(rec, "icon", "iconShow", true)
    end
    -- Name text shows on spell bars. A resource or swing bar's name is just its
    -- power or hand, and a player health bar's is your own, so it stays off
    -- there; other health bars show their unit's live name.
    local hpUnit = barKind == "health" and (rec.driver.unit or "player") or nil
    if barKind ~= "resource" and barKind ~= "swing" and hpUnit ~= "player" then
        TemplateSet(rec, "text", "nameShow", true)
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
    local sx, sy = CenterSpot(layoutId, 42)
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
    elseif rec.type == "icon" then
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
-- free spot on a layout (layoutId + pos); aura groups take aura icons only.
-- With no cell, the icon takes the first free cell on the next render.
function Store.MoveIcon(iconId, destGroupId, layoutId, pos, cell)
    local rec = Store.Get(iconId)
    if not rec or rec.type ~= "icon" then return false end
    local dest
    if destGroupId then
        dest = Store.Get(destGroupId)
        if not dest or dest.type ~= "group" then return false end
        if dest.groupKind == "aura" and rec.kind ~= "aura" then return false end
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

-- deep copy under a fresh id; the caller wires parents and children
local function CloneRecord(rec, map, made)
    local c = CopyDeep(rec)
    c.id = NewId()
    map[rec.id] = c.id
    made[#made + 1] = c
    return c
end

local function Nudge(pos, dx, dy)
    return { x = (tonumber(pos and pos.x) or 0) + dx, y = (tonumber(pos and pos.y) or 0) + dy }
end

-- clone every icon of `group` under its clone `gc`
local function CloneIcons(group, gc, map, made)
    gc.members = {}
    for _, iid in ipairs(group.members or {}) do
        local icon = DB.records[iid]
        if icon and icon.type == "icon" then
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
    else
        return nil
    end
    DB.records[copy.id] = copy
    for _, r in ipairs(made) do RemapAnchors(r, map, true) end
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
function Store.Export(ids)
    if type(ids) ~= "table" then ids = { ids } end
    local LD = GetDeflate()
    if not LD then return nil, "LibDeflate did not load" end
    local seen, recs = {}, {}
    local function add(rec)
        if not rec or seen[rec.id] then return end
        seen[rec.id] = true
        recs[#recs + 1] = CopyDeep(rec)
        if rec.type == "group" then
            for _, mid in ipairs(rec.members or {}) do add(DB.records[mid]) end
        end
    end
    for _, id in ipairs(ids) do add(DB.records[id]) end
    if #recs == 0 then return nil, "nothing ticked to export" end
    for _, rec in ipairs(recs) do
        if rec.type == "layout" then
            local m = {}
            for _, mid in ipairs(rec.members or {}) do
                if seen[mid] then m[#m + 1] = mid end
            end
            rec.members = m
        else
            -- its layout is not in the string: its looks travel baked in
            local orig = DB.records[rec.id]
            local lay = orig and Store.LayoutOf(orig)
            if lay and not seen[lay.id] then BakeLook(rec, orig) end
        end
    end
    local payload = { v = 1, kind = "adlayout", records = recs }
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
-- Returns { layouts = {..}, items = {..}, target = rec }, or nil and a reason.
function Store.Import(text, targetLayoutId)
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

    local VALID = { layout = true, group = true, icon = true, bar = true }
    local map, newRecs, layouts = {}, {}, {}
    for _, rec in ipairs(payload.records) do
        if type(rec) == "table" and rec.id ~= nil and VALID[rec.type] then
            local nid = NewId()
            map[rec.id] = nid
            rec.id = nid
            newRecs[#newRecs + 1] = rec
            if rec.type == "layout" then layouts[#layouts + 1] = rec end
        end
    end
    if #newRecs == 0 then return nil, "string holds nothing to import" end

    -- layouts first, so loose records have somewhere to land
    for _, rec in ipairs(layouts) do
        if type(rec.members) ~= "table" then rec.members = {} end
        rec.name = tostring(rec.name or "Layout") .. " (import)"
        rec.pos = type(rec.pos) == "table" and rec.pos or {}
        rec.pos.x = (tonumber(rec.pos.x) or 0) + 24
        rec.pos.y = (tonumber(rec.pos.y) or 0) - 24
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
    Store.Normalize()
    Store.Dirty("tree")
    return { layouts = layouts, items = items, target = target }
end

-- One-layout form of Import: the first imported layout, or where the loose
-- items landed.
function Store.ImportLayout(text)
    local res, err = Store.Import(text)
    if not res then return nil, err end
    return res.layouts[1] or res.target
end
