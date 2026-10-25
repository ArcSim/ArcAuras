-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- Aura icons on the engine-owned AuraContainer, and the aura overlay on spell
-- icons. The icon frame is a holder wearing the "missing" look; the engine
-- button anchored over it shows while the aura is up and carries every Aura
-- Active option (a gated glow rides a glow-only button, see Glow gates).
-- Presence can be secret, so it is never read.
local ADDON, NS = ...
local hooksecurefunc = NS.Perf and NS.Perf.Hooks("DriverAura") or hooksecurefunc   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("DriverAura") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames and its sweep skips those on the game's aura buttons
local C_Timer = NS.Perf and NS.Perf.Timers("DriverAura") or C_Timer   -- /arcperf times what they run
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local Driver = {}
NS.DriverAura = Driver

-- Capability probe as well as a version gate: Forever (1.60.x, branched from
-- retail 12.1.5) has the AuraContainer engine under a lower build number.
local IS_121 = ((select(4, GetBuildInfo()) or 0) >= 120100)
    or (C_Secrets and C_Secrets.ShouldAurasBeSecret ~= nil)
local FB_OK = UIParent.SetIsFrameBuffer ~= nil and UIParent.SetFlattensRenderLayers ~= nil

local entries = {}        -- [iconId] = { rec, holder, subs={ {unit,key,container,harmful,frame,inStage} }, glows={ same }, parked, gen, stage, staged, erase, fbOn }
local allContainers = {}  -- { {unit=, frame=} } for target-swap refresh
local pendingCreate = {}  -- [iconId] = true, deferred while auras are secret
local combatQueue = {}    -- [entry] = parked flag, filter edits queued in combat
local loadWindowOver = false

-- A frame of ours born on UIParent (a stage, a container) takes the holder's
-- layout scale (Engine.FollowScale; written only on a change).
local function FollowScale(f, holder)
    local E = NS.LayoutEngine
    if E and E.FollowScale and f and holder then E.FollowScale(f, holder) end
end

-- For the combat-only glows. InCombatLockdown is still false while
-- PLAYER_REGEN_DISABLED runs, so the combat events carry it.
local inCombat = InCombatLockdown() and true or false

local function AurasSecretNow()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    -- On Forever the probe can return a secret boolean, which throws on a test.
    -- A secret answer means restrictions are on.
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end

function Driver.IsAvailable() return IS_121 end

-- The holder's height as a plain number, for text scaling (base 36). The
-- holder is our frame; an engine button's size is never read.
local function HolderPx(entry)
    local h = entry and entry.holder
    local px = h and h.GetHeight and h:GetHeight()
    if type(px) ~= "number" or (issecretvalue and issecretvalue(px)) or px <= 0 then
        return 36
    end
    return px
end

-- True when a visible missing look sits under the button; raw settings, so no
-- preview alpha floor. An own Missing look that shows it counts, whatever holds now.
function Driver.GhostShown(rec)
    -- not learned yet: no missing look at all (Store.AuraDormant)
    if rec ~= nil and Store.AuraDormant and Store.AuraDormant(rec) then return false end
    if rec ~= nil and NS.OwnLooks and NS.OwnLooks.ShowsMissing(rec) then return true end
    return rec ~= nil and Store.Resolve(rec, "auraMissing", "showWhileMissing") ~= false
        and (Store.Resolve(rec, "auraMissing", "missingAlpha") or 1) > 0
end

function Driver.EraserAvailable() return FB_OK and IS_121 end

-- True when the icon needs its stage: only such an icon pays for one.
function Driver.NeedsEraser(rec)
    if not (FB_OK and IS_121 and rec) then return false end
    if rec.kind ~= "aura" then
        -- a cooldown icon's aura erases the cooldown's look while its own shows
        -- (none at Active 0: a glow-only aura keeps the cooldown), where the
        -- plate alone would not hide it: a look past the art, or a dimmed aura
        if not Driver.ShapeFor(rec) then return false end
        local aA = Store.Resolve(rec, "auraActive", "activeAlpha") or 1
        if aA <= 0 then return false end
        return aA < 1 or Factory.CooldownLookReaches(rec)
    end
    if Driver.TimeGateFrac(rec) then return true end
    -- the stacks state's cut needs its stage (a glow alone does not)
    local cg = Driver.CountGate(rec)
    if cg and (cg.whole or cg.copy) then return true end
    if not Driver.GhostShown(rec) then return false end
    if Store.Resolve(rec, "appearance", "forceHideIcon") == true then return true end
    if (Store.Resolve(rec, "auraActive", "activeAlpha") or 1) < 1 then return true end
    -- a Missing glow or custom text can sit past the art, which covers only itself
    return Factory.HasMissingGlow(rec) or Factory.HasMissingText(rec)
end

local function AuraButtonOpts(entry)
    local px = HolderPx(entry)
    local h = entry and entry.holder
    local w = h and h.GetWidth and h:GetWidth()
    if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) or w <= 0 then w = px end
    local rec = entry and entry.rec
    -- a spell icon's overlay always has its cooldown under it: the plate
    -- keeps a dimmed aura look from showing the cooldown through
    local ghost = (rec ~= nil and rec.kind ~= "aura") or Driver.GhostShown(rec)
    return { w = w, h = px, ghost = ghost, erase = (entry and entry.erase) == true }
end

-- Tracking shape and filters
-- One button per icon: one unit and aura type, with every tracked spell ID in
-- its candidate filter; the engine picks which match to show. The shape:
--   driver.spellID   primary id (ghost art, name, tooltip)
--   driver.spellIDs  full list, primary first, when there is more than one
--   driver.auraType  "buff" | "debuff" ("petbuff" reads as a pet buff)
--   driver.unit      player | target | focus | pet | party1..party4
--   driver.caster    nil = anyone | "mine" | "others" (ownOnly reads as "mine")

local AURA_UNITS = { player = true, target = true, focus = true, pet = true,
    party1 = true, party2 = true, party3 = true, party4 = true }
Driver.AURA_UNITS = AURA_UNITS

local function ShapeOf(d)
    d = d or {}
    local t = d.auraType or "buff"
    local unit = d.unit
    if not AURA_UNITS[unit] then
        unit = (t == "debuff" and "target") or (t == "petbuff" and "pet") or "player"
    end
    local caster = d.caster
    if caster ~= "mine" and caster ~= "others" then
        caster = d.ownOnly and "mine" or nil
    end
    return unit, t == "debuff", caster
end
Driver.ShapeOf = ShapeOf

local function LaneOf(d)
    local unit, harmful = ShapeOf(d)
    return unit, harmful
end
Driver.LaneOf = LaneOf

-- "You, then your target", the Cooldown Manager's rule: your buff on you, and
-- while you have none, the aura on your target. Your button sits RISE levels
-- above the target's (one over its whole stack: Factory.BUTTON_STACK.gate + 1),
-- so it covers it whenever both are up; presence is never read.
local RISE = 11
Driver.RISE = RISE

-- A cooldown icon's look rides its aura's stage: the aura's buttons sit over
-- the highest level a cooldown glow can take (30, plus RISE), so their eraser
-- reaches every glow under them.
local STAGE_LIFT = 37
Driver.STAGE_LIFT = STAGE_LIFT

local function TwoUnits(d)
    return type(d) == "table" and d.unit == "player" and d.unit2 == "target"
end
Driver.TwoUnits = TwoUnits

-- Several units (driver.units, in order, the first also driver.unit): one
-- button per unit with the icon's aura type, each a RISE over the next, so the
-- first unit that has the aura covers the rest; presence is never read.
local function UnitList(d)
    if type(d) ~= "table" or type(d.units) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, u in ipairs(d.units) do
        if AURA_UNITS[u] and not seen[u] then
            seen[u] = true
            out[#out + 1] = u
        end
    end
    return #out >= 2 and out or nil
end
Driver.UnitList = UnitList

-- more than one button: you, then your target, or several units
local function MultiUnit(d)
    return TwoUnits(d) or UnitList(d) ~= nil
end
Driver.MultiUnit = MultiUnit

local function LanesFor(d)
    local unit, harmful = LaneOf(d)
    if TwoUnits(d) then
        return { { unit = "player", harmful = false, rise = RISE }, { unit = "target", harmful = harmful } }
    end
    local list = UnitList(d)
    if list then
        local out = {}
        for i, u in ipairs(list) do
            out[i] = { unit = u, harmful = harmful, rise = (#list - i) * RISE }
        end
        return out
    end
    return { { unit = unit, harmful = harmful } }
end
Driver.LanesFor = LanesFor

-- one string per lane set, so a switch between one and two units rewires
local function LaneSig(list)
    local t = {}
    for i, l in ipairs(list) do t[i] = l.unit .. (l.harmful and ":h" or ":b") end
    return table.concat(t, ",")
end

-- lane: anything with .harmful (a lane or a live sub). Caster goes in the
-- filter string (PLAYER: you, your pet or vehicle; !PLAYER: anyone else) and
-- narrows every unit. It is read from the record, so an edit needs no rewire.
local function FilterForLane(d, lane)
    local _, _, caster = ShapeOf(d)
    local f = lane.harmful and "HARMFUL" or "HELPFUL"
    if caster == "mine" then return f .. "|PLAYER" end
    if caster == "others" then return f .. "|!PLAYER" end
    return f
end
Driver.FilterForLane = FilterForLane

-- The aura entry point lives in the Store (ONE RESOLVE PER QUESTION) so every
-- aura reader shares it: the typed IDs (AuraIDList), and with Follow my rank
-- your rank of each (AuraRank), never an override.
local SpellIDList = Store.AuraIDList
Driver.SpellIDList = SpellIDList
Driver.KnownRank = Store.AuraRank
local TrackedIDs = Store.TrackedAuraIDs
Driver.TrackedIDs = TrackedIDs

-- Every tracked id on the one button. No ids gets the never-matching id 0,
-- never an empty set: a HELPFUL slot with no id filter shows an arbitrary buff.
local IncludeMap = Store.AuraIncludeMap
Driver.IncludeMap = IncludeMap

-- An id map as a comparable string. A container rebuilds on every candidate
-- filter it is sent, changed or not, and each rebuild restarts what its
-- buttons show, so a set equal to the last one sent is never sent again.
local function FilterSig(ids)
    local t = {}
    for id in pairs(ids) do t[#t + 1] = tostring(id) end
    table.sort(t)
    return table.concat(t, ",")
end
Driver.FilterSig = FilterSig

-- Glow lanes: in combat the icon's button can't be restyled and never says
-- which id it shows, so a gated glow 1 ("Glow for", "Glow only in combat") and
-- every glow 2-4 ride their own engine button whose filter holds just that
-- glow's ids, in a container we own. Its alpha is the combat switch; a
-- container Show / Hide rebuilds it.

-- "Glow for" choices: one per spell name (its ranks together), in the icon's
-- order, each keyed by its first id.
local function GlowSpellGroups(d)
    local out, byName = {}, {}
    for _, id in ipairs(SpellIDList(d)) do
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed aura's own name, a pick's label
        local key = name or ("#" .. id)
        local g = byName[key]
        if g then
            g.n = g.n + 1
        else
            g = { id = id, name = name or ("Spell " .. id), n = 1 }
            byName[key] = g
            out[#out + 1] = g
        end
    end
    return out
end
Driver.GlowSpellGroups = GlowSpellGroups

-- A gate needs the icon's own button: an aura icon, and not a member of a
-- Dynamic aura group, whose rows draw it in play, nor a type's look on a group
-- showing every aura (_adNoHolder), which has no lane either.
function Driver.GlowLaneOK(rec)
    if not (IS_121 and rec and rec.kind == "aura") or rec._adNoHolder then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    if g and g.groupKind == "aura"
        and Store.Resolve(g, "arrangement", "dynamicLayout") == true then
        return false
    end
    return true
end

-- The icons that can show something over their cooldown ("On this icon"):
-- spells, and items and trinkets (their use spell stands in for the spell),
-- and a Custom Icon's "Aura on this icon".
local OVERLAY_KINDS = { spell = true, item = true, trinket = true, timer = true }
Driver.OVERLAY_KINDS = OVERLAY_KINDS

-- A spell icon's aura overlay draws glow 1 alone, on the overlay's button;
-- Glow only in combat moves it onto a lane of its own.
function Driver.OverlayGlowLaneOK(rec)
    return IS_121 and rec ~= nil and OVERLAY_KINDS[rec.kind] == true and Driver.ShapeFor(rec) ~= nil
end

-- Missing and Always glows: an aura icon's holder draws them, or its Dynamic
-- group's row, so a group member takes them too.
function Driver.HolderGlowOK(rec)
    return IS_121 and rec ~= nil and rec.kind == "aura"
end

-- A type's look on a group showing every aura (_adNoHolder: its button draws
-- every glow, as a row's does) has nothing under the button for a Missing one.
function Driver.MissingGlowOK(rec)
    return FB_OK and Driver.HolderGlowOK(rec) and not rec._adNoHolder
end

-- Glow for and Glow only in combat: a lane of the icon's own, or of its
-- Dynamic group's row.
function Driver.GlowGateOK(rec)
    return Driver.HolderGlowOK(rec)
end

-- Show only when little time is left: an aura icon outside a Dynamic group,
-- on one unit (a several-unit icon's ladder has no rung for it).
function Driver.TimeGateOK(rec)
    return FB_OK and Driver.GlowLaneOK(rec) and not MultiUnit(rec.driver)
end

-- The share of time left the live look shows under, or nil: off, or seconds
-- with no length typed in (the icon then shows the whole time).
function Driver.TimeGateFrac(rec)
    if not (Driver.TimeGateOK(rec)
        and Store.Resolve(rec, "auraActive", "activeTimeOnly") == true) then
        return nil
    end
    local R = function(k) return Store.Resolve(rec, "auraActive", k) end
    local frac
    if (R("activeTimeUnit") or "pct") == "sec" then
        local len = R("activeTimeLen") or 0
        if len <= 0 then return nil end
        frac = (R("activeTimeSec") or 3) / len
    else
        frac = (R("activeTimePct") or 30) / 100
    end
    if frac >= 1 then return nil end
    return frac
end

-- The stacks state: the same icons as the time gate.
function Driver.CountGateOK(rec)
    return Driver.TimeGateOK(rec)
end

-- A count state's rules (Schema.COUNT_RULES but "any").
Driver.COUNT_KINDS = { least = true, most = true, exactly = true, between = true }

-- A count state's look: its opacity, grey, tint (a colour, or nil) and glow.
function Driver.CountLook(rec, sec, pre)
    local R = function(k) return Store.Resolve(rec, sec, pre .. k) end
    local a = tonumber(R("Alpha")) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return { alpha = a, grey = R("Desaturate") == true,
        tint = (R("TintEnabled") == true) and (R("TintColor") or { 1, 0.3, 0.3, 1 }) or nil,
        glow = R("Glow") == true }
end

-- What a state's look asks of its count's window (inside: it covers the look
-- while the rule holds): whole = opacity 0 cuts everything away; copy = the
-- art and border redrawn at its opacity, grey or tint over a cut; glow = its
-- glow shown only there. nil when the look changes nothing.
function Driver.CountCut(s)
    if not s then return nil end
    local L = s.look
    s.inside = true
    s.whole = L.alpha <= 0
    s.copy = not s.whole and (L.alpha < 1 or L.grey or L.tint ~= nil)
    s.glow = not s.whole and L.glow
    if not (s.whole or s.copy or s.glow) then return nil end
    return s
end

-- The stacks state (an aura icon's), or nil (any count, or not offered): when
-- it holds (kind least / most / exactly / between, a and b), the bar's top
-- count, and its look (Driver.CountLook).
function Driver.StacksState(rec)
    if not Driver.CountGateOK(rec) then return nil end
    local R = function(k) return Store.Resolve(rec, "auraActive", k) end
    local kind = R("stacksRule") or "any"
    if not Driver.COUNT_KINDS[kind] then return nil end
    local a = math.max(1, math.floor(tonumber(R("stacksA")) or 3))
    local b = (kind == "between") and math.max(a, math.floor(tonumber(R("stacksB")) or 5)) or a
    -- one past the rule's high end at least, so a count over it reads as over
    local top = math.max(a, b) + 1
    local id = TrackedIDs(rec.driver or {})[1]
    local Max = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
    local m = (id and Max) and Max(id)
    if type(m) == "number" and not (issecretvalue and issecretvalue(m)) and m > top then top = m end
    return { kind = kind, a = a, b = b, max = top, look = Driver.CountLook(rec, "auraActive", "stacks") }
end

-- What the icon's button carries for the stacks state (Driver.CountCut), or nil.
function Driver.CountGate(rec)
    return Driver.CountCut(Driver.StacksState(rec))
end

-- The charges state: spell icons whose spell has charges.
function Driver.ChargeGateOK(rec)
    if not (FB_OK and IS_121 and rec and rec.kind == "spell") then return false end
    local DC = NS.DriverCooldown
    return DC ~= nil and DC.IsCharge ~= nil and DC.IsCharge(rec) == true
end

-- The charges state (a spell icon's), or nil: as the stacks state, its top
-- from the spell's plain charge cap (one past the rule's high end at least).
function Driver.ChargesState(rec)
    if not Driver.ChargeGateOK(rec) then return nil end
    local R = function(k) return Store.Resolve(rec, "states", k) end
    local kind = R("chargesRule") or "any"
    if not Driver.COUNT_KINDS[kind] then return nil end
    local a = math.max(0, math.floor(tonumber(R("chargesA")) or 2))
    local b = (kind == "between") and math.max(a, math.floor(tonumber(R("chargesB")) or 3)) or a
    local DC = NS.DriverCooldown
    local cap = DC and DC.ChargeMax and DC.ChargeMax(rec)
    if not cap or cap < 2 then return nil end
    return { kind = kind, a = a, b = b, max = math.max(cap, math.max(a, b) + 1),
        look = Driver.CountLook(rec, "states", "charges") }
end

-- What the icon's stage carries for the charges state (DriverAura.SyncGate), or nil.
function Driver.ChargeGate(rec)
    return Driver.CountCut(Driver.ChargesState(rec))
end

function Driver.InCombat() return inCombat end

-- With the options window open, glows that wait for combat show, as the
-- preview does, so they can be seen while editing.
local function GlowsForCombat()
    if inCombat then return true end
    local E = NS.LayoutEngine
    return E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true
end

-- How many glows an aura icon has (glow 1 plus the numbered ones).
local function GlowSlots()
    return (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1
end

-- A glow with a strata of its own takes a lane: the icon's button is born in
-- its stage (a Dynamic row's missing piece in one too), which draws everything
-- in it at the stage's strata, so a glow set above its icon would stay with
-- the icon under whatever covers it. Lanes are born outside any stage.
local function OwnGlowStrata(rec, suf)
    local s = Store.Resolve(rec, "auraActive", "activeGlowStrata" .. (suf or ""))
    return s ~= nil and s ~= "inherit"
end

-- The ids glow `slot` (default 1) follows on its own button, or nil: the glow
-- is off, or it is glow 1 with no gate (a pick of every id counts as none)
-- and no strata of its own, which stays on the icon's button. row: a Dynamic
-- row's lane instead, whose button keeps every glow with no gate or strata.
local function LaneIDs(rec, slot, row)
    slot = slot or 1
    local overlay = false
    if row then
        if not Driver.HolderGlowOK(rec) then return nil end
    elseif not Driver.GlowLaneOK(rec) then
        if slot ~= 1 or not Driver.OverlayGlowLaneOK(rec) then return nil end
        overlay = true
    end
    local suf = (slot > 1) and tostring(slot) or ""
    local R = function(k) return Store.Resolve(rec, "auraActive", k .. suf) end
    if R("activeGlow") ~= true then return nil end
    -- With "Show only when little time is left", glow 1 leaves the icon's
    -- button and an Always glow's live half rides a lane.
    local timed = not row and Driver.TimeGateFrac(rec) ~= nil
    -- a Missing or Always glow is the holder's, not a button's
    local when = R("activeGlowWhen")
    if when == "missing" or (when == "both" and not timed) then return nil end
    local d = Driver.ShapeFor(rec) or {}
    local ids = TrackedIDs(d)
    local m, n = {}, 0
    -- an overlay has no Glow for: its glow follows every id it tracks
    local pick = overlay and 0 or (tonumber(R("activeGlowFor")) or 0)
    if pick > 0 then
        for _, id in ipairs(ids) do
            if Store.SameAura(pick, id) then
                m[id] = true
                n = n + 1
            end
        end
    end
    if n == 0 or n == #ids then
        -- no pick, one the icon no longer tracks, or all of them
        if (slot == 1 or row) and R("activeGlowCombatOnly") ~= true and not timed
            and (overlay or not OwnGlowStrata(rec, suf)) then
            return nil
        end
        m = IncludeMap(d)
    end
    return m
end
local function GlowIDs(rec, slot) return LaneIDs(rec, slot, false) end
Driver.GlowIDs = GlowIDs
function Driver.RowGlowIDs(rec, slot) return LaneIDs(rec, slot, true) end

-- True when any glow wants a lane.
local function AnyGlowWanted(rec)
    for k = 1, GlowSlots() do
        if GlowIDs(rec, k) then return true end
    end
    return false
end

local function HasGlowLane(entry, slot)
    for _, g in ipairs(entry.glows or {}) do
        if g.slot == slot then return true end
    end
    return false
end

-- True when glow 1's lane carries it, so the icon's button drops it.
local function GlowMoved(entry)
    return HasGlowLane(entry, 1) and GlowIDs(entry.rec, 1) ~= nil
end

-- The glow button's style options for one lane.
local function GlowOpts(entry, base, g)
    local o = {}
    for k, v in pairs(base) do o[k] = v end
    o.glowSlot = g.slot
    o.glowOn = GlowIDs(entry.rec, g.slot) ~= nil
    -- a lane glows no sooner than its time-gated icon shows
    o.glowCap = Driver.TimeGateFrac(entry.rec)
    return o
end

-- Aura on a spell icon
-- With rec.driver.overlay.on, a spell icon gets an entry like an aura icon's:
-- its button covers the cooldown while the aura is up, styled from the spell
-- icon's record. The overlay table has the aura shape above.

-- What a spell icon's overlay shows: the aura (the engine's), its totem or a
-- set duration on cast (both Drivers\AD_DriverPhase.lua).
local function OverlaySource(ov)
    local s = type(ov) == "table" and ov.source
    if s == "totem" or s == "cast" then return s end
    return "aura"
end
Driver.OverlaySource = OverlaySource

-- the aura shape an entry tracks: an aura icon's driver, a spell, item or
-- trinket icon's overlay while it is on and shows an aura, else nil
local function ShapeFor(rec)
    if not rec then return nil end
    if rec.kind == "aura" then return rec.driver or {} end
    local ov = OVERLAY_KINDS[rec.kind] and rec.driver and rec.driver.overlay
    if type(ov) == "table" and ov.on == true and OverlaySource(ov) == "aura" then return ov end
    return nil
end
Driver.ShapeFor = ShapeFor

-- an icon whose overlay is on (any source) and can run on this client
function Driver.OverlayOn(rec)
    local ov = IS_121 and rec ~= nil and OVERLAY_KINDS[rec.kind] and rec.driver and rec.driver.overlay
    return type(ov) == "table" and ov.on == true
end

-- an icon the aura's button covers while the aura is up; a totem or a set
-- duration runs on the icon's own cooldown instead (Drivers\AD_DriverPhase.lua)
function Driver.ButtonOver(rec)
    return Driver.OverlayOn(rec) and ShapeFor(rec) ~= nil
end

-- How far the holder's texts and glows sit up to stay over a several-unit icon's top button.
function Driver.Rise(rec)
    if not IS_121 then return 0 end
    local top = 0
    for _, l in ipairs(LanesFor(ShapeFor(rec))) do
        if (l.rise or 0) > top then top = l.rise end
    end
    return top
end

-- True when every tracked id is never-secret, the one case a spell-ID filter
-- works on a debuff on a friendly unit. Such filters cover buffs on friendly
-- units and players and debuffs on enemies. Forever rejects any aura it cannot
-- filter by ID (showing nothing); retail 12.1.0 shows the unfiltered aura.
function Driver.IDsNeverSecret(d)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel) then
        return false
    end
    local ids = TrackedIDs(d)
    if #ids == 0 then return false end
    for _, id in ipairs(ids) do
        if C_Secrets.GetSpellAuraSecrecy(id) ~= Enum.SecrecyLevel.NeverSecret then
            return false
        end
    end
    return true
end

-- Containers
-- A container refreshes only on UNIT_AURA for its unit, so a target, focus,
-- pet or roster change needs a nudge. Events are probed: unknown names throw.

-- Each container's slot switches as last set, so a swap nudge skips a
-- container with every slot off (switched on, the game rebuilds it anyway).
-- A container whose switches we never set counts as on.
local slotState = setmetatable({}, { __mode = "k" })   -- [container] = { [key] = on }
local function NoteSlot(c, key, on)
    local t = slotState[c]
    if not t then
        t = {}
        slotState[c] = t
    end
    t[key] = on
end
local function AnySlotOn(c)
    local t = slotState[c]
    if not t then return true end
    for _, on in pairs(t) do
        if on then return true end
    end
    return false
end
Driver.AnySlotOn = AnySlotOn

local function OnIfValid(event, key, fn, units)
    if C_EventUtils and C_EventUtils.IsEventValid
        and not C_EventUtils.IsEventValid(event) then return end
    Events.On(event, key, fn, units)
end

local swapArmed = false
local function ArmTargetSwapRefresh()
    if swapArmed then return end
    swapArmed = true
    local function Refresh(unit)
        for _, rc in ipairs(allContainers) do
            -- a hidden or all-off container rebuilds when it shows or a slot turns on
            if rc.unit == unit and type(rc.frame.UpdateAllAuras) == "function"
                and rc.frame:IsShown() and AnySlotOn(rc.frame) then
                rc.frame:UpdateAllAuras()
            end
        end
        Driver.SyncUnitAlpha(unit)
        -- the bar glows' lanes on that unit (Bars\AD_BarGlow.lua)
        local BG = NS.Bars and NS.Bars.Glow
        if BG and BG.SyncUnit then BG.SyncUnit(unit) end
        local RCm = NS.Bars and NS.Bars.ResColor
        if RCm and RCm.SyncUnit then RCm.SyncUnit(unit) end
    end
    OnIfValid("PLAYER_TARGET_CHANGED", "adaura_swap", function() Refresh("target") end)
    OnIfValid("PLAYER_FOCUS_CHANGED", "adaura_swap", function() Refresh("focus") end)
    if NS.AuraEngine1210 then
        -- 12.1.0 containers never re-read a side change (a duel, mind control) themselves
        local function Turned(_, unit)
            if unit == "target" or unit == "focus" then Refresh(unit) end
        end
        -- every unit's flags change all fight long; only these two refresh a lane
        local sides = { "target", "focus" }
        OnIfValid("UNIT_FACTION", "adaura_swap", Turned, sides)
        OnIfValid("UNIT_FLAGS", "adaura_swap", Turned, sides)
    end
    OnIfValid("UNIT_PET", "adaura_swap", function(_, unit)
        if unit == nil or unit == "player" then Refresh("pet") end
    end, { "player" })
    OnIfValid("GROUP_ROSTER_UPDATE", "adaura_swap", function()
        for i = 1, 4 do Refresh("party" .. i) end
    end)
end

-- Side parks
-- The game's spell-ID check (Blizzard_AuraContainerUtil
-- CanApplyIdentityCandidateFilters) never passes a buff on a unit neither
-- yours nor one you can assist, nor a debuff on one you can assist; a
-- never-secret id is exempt. A target or focus slot in that spot shows nothing
-- yet still works through every aura change on the unit, so it is switched off
-- while the side holds and back on, with the game's full pass, when it turns.
-- Only the container's own slot switch is used: its events cannot be touched
-- (icon-kinds skill, THE MUTE IS IMPOSSIBLE). 12.1.0 shows such auras
-- unfiltered, so it never side-parks.

local SIDE_UNITS = { target = true, focus = true }
local SIDE_UNKNOWN = -1
local sideOf = {}                                       -- [unit] = side last seen
local sideSlots = setmetatable({}, { __mode = "k" })   -- [container] = { [key] = { unit, want, harmful, ids, on } }

-- The two reads that check makes on a unit.
local function SideOf(unit)
    local own = UnitIsPlayerControlledOrGroupMember and UnitIsPlayerControlledOrGroupMember(unit)
    local assist = UnitCanAssist("player", unit, true, true)
    if issecretvalue and (issecretvalue(own) or issecretvalue(assist)) then return SIDE_UNKNOWN end
    return (own and 2 or 0) + (assist and 1 or 0)
end

local function SideBlind(side, harmful, ids)
    if side == SIDE_UNKNOWN then return false end
    local own, assist = side >= 2, side % 2 == 1
    if harmful then
        if not assist then return false end
    elseif own or assist then
        return false
    end
    local CS, SL = C_Secrets, Enum and Enum.SecrecyLevel
    if CS and CS.GetSpellAuraSecrecy and SL then
        for id in pairs(ids) do
            if type(id) == "number" and id > 0 and CS.GetSpellAuraSecrecy(id) == SL.NeverSecret then return false end
        end
    end
    return true
end

-- On a flag or faction change, and when the token names another unit.
function Driver.SideCheck(unit)
    local side = SideOf(unit)
    if side ~= SIDE_UNKNOWN and side == sideOf[unit] then return end
    sideOf[unit] = side
    for c, slots in pairs(sideSlots) do
        for key, r in pairs(slots) do
            if r.unit == unit then
                local on = r.want and not SideBlind(side, r.harmful, r.ids)
                if on ~= r.on then
                    r.on = on
                    c:SetAuraSlotEnabled(key, on)
                    NoteSlot(c, key, on)
                end
            end
        end
    end
end

local sideArmed = false
local function ArmSides()
    if sideArmed then return end
    sideArmed = true
    local function Turned(_, unit)
        if unit == "player" then
            -- the player's own side moves every unit's
            for u in pairs(SIDE_UNITS) do Driver.SideCheck(u) end
        elseif SIDE_UNITS[unit] then
            Driver.SideCheck(unit)
        end
    end
    local units = { "player", "target", "focus" }
    OnIfValid("UNIT_FLAGS", "adaura_side", Turned, units)
    OnIfValid("UNIT_FACTION", "adaura_side", Turned, units)
    OnIfValid("PLAYER_TARGET_CHANGED", "adaura_side", function() Driver.SideCheck("target") end)
    OnIfValid("PLAYER_FOCUS_CHANGED", "adaura_side", function() Driver.SideCheck("focus") end)
end

-- The slot's switch with its side folded in. Returns the switch to set.
local function SideSlot(c, key, unit, want, harmful, ids)
    if not SIDE_UNITS[unit] or NS.AuraEngine1210 then return want end
    ArmSides()
    local slots = sideSlots[c]
    if not slots then
        slots = {}
        sideSlots[c] = slots
    end
    local r = slots[key]
    if not r then
        r = {}
        slots[key] = r
    end
    local side = SideOf(unit)
    if sideOf[unit] == nil then sideOf[unit] = side end
    r.unit, r.want, r.harmful, r.ids = unit, want, harmful == true, ids
    r.on = want and not SideBlind(side, r.harmful, ids)
    return r.on
end

-- For /arcperf: target and focus slots tracked, and how many sit off for the side.
function Driver.SideCensus()
    local n, off = 0, 0
    for _, slots in pairs(sideSlots) do
        for _, r in pairs(slots) do
            n = n + 1
            if r.want and not r.on then off = off + 1 end
        end
    end
    return n, off
end

local function CreateIconContainer(unit, parent)
    if not IS_121 then return nil end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local c = CreateFrame("AuraContainer", nil, parent or UIParent, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraSlot) ~= "function" then return nil end
    c:SetSize(1, 1)
    c:SetPoint("TOP", UIParent, "TOP", 0, -80)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:Show()
    allContainers[#allContainers + 1] = { unit = unit, frame = c }
    if unit ~= "player" then ArmTargetSwapRefresh() end
    return c
end
-- Exported: a group buff's layers hold one per member (Drivers\AD_DriverGroupBuff.lua).
Driver.CreateIconContainer = CreateIconContainer

-- Button wiring. Runs from initializeFrame, the always-legal write window.
-- The engine creates a slot's button once and keeps it, so an edit made while
-- the button is locked lands on a later pass.

local function WireButton(btn)
    if btn._adWired then return end
    btn._adWired = true

    -- StyleAuraButton shows it (opts.erase).
    local eraser = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    eraser:SetColorTexture(0, 0, 0, 0)
    eraser:SetBlendMode("DISABLE")
    eraser:Hide()
    btn._adEraser = eraser

    -- Opaque plate: a dimmed active icon reads dimmed, not blended with the
    -- ghost. It follows parent alpha, since the container carries the icon's
    -- fades; an ignore-parent plate would stay black on a faded icon.
    -- StyleAuraButton decides whether it exists.
    local plate = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    plate:SetAllPoints()
    plate:SetColorTexture(0, 0, 0, 1)
    btn._adPlate = plate

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._adIcon = icon

    -- Reversed swipe. Lua-created cooldowns need a texture file with explicit
    -- white color args (a color-only swipe does not render) and start hidden.
    local swipe = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    swipe:SetAllPoints()
    swipe:SetReverse(true)
    swipe:SetHideCountdownNumbers(false)
    -- Countdown numbers draw only for a total duration above this minimum, and
    -- the default hides a 2s aura; auras never carry the GCD, so 0. Set here in
    -- the init window: the button is forbidden later, in combat and instances.
    if swipe.SetMinimumCountdownDuration then swipe:SetMinimumCountdownDuration(0) end
    swipe:SetDrawEdge(false)
    swipe:SetDrawBling(false)
    swipe:SetSwipeTexture("Interface\\Buttons\\WHITE8X8", 1, 1, 1, 1)
    swipe:SetSwipeColor(0, 0, 0, 0.8)
    swipe:Show()
    btn._adSwipe = swipe

    -- Factory.BUTTON_STACK from the swipe's level: the border's own layer over
    -- the swipe, the button's glows over that, its texts over the glows. A
    -- button no holder anchors (aura group rows, a unit's auras) is born right.
    local S = Factory.BUTTON_STACK
    local edge = CreateFrame("Frame", nil, btn)
    edge:SetAllPoints()
    edge:SetFrameLevel(swipe:GetFrameLevel() + S.edge - S.swipe)
    btn._adEdgeHost = edge
    -- The dispel-type border's own frame on the border's rung: a texture
    -- handed to the engine has its alpha taken over, so the icon's opacity
    -- rides this frame instead (Factory ApplyAuraButtonDispel).
    local dispel = CreateFrame("Frame", nil, edge)
    dispel:SetAllPoints()
    dispel:SetFrameLevel(edge:GetFrameLevel())
    btn._adDispelHost = dispel

    local overlay = CreateFrame("Frame", nil, btn)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(swipe:GetFrameLevel() + S.text - S.swipe)
    btn.TextOverlay = overlay

    local stacks = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    stacks:SetDrawLayer("OVERLAY", 7)
    stacks:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn._adStacks = stacks

    -- rehome the countdown fontstring onto the overlay (born a frame level
    -- below; frame level beats draw layer)
    if swipe.GetCountdownFontString then
        local cfs = swipe:GetCountdownFontString()
        if cfs then
            cfs:SetParent(overlay)
            cfs:SetDrawLayer("OVERLAY", 7)
        end
    end

    -- The engine drives these from secret aura data. Factory.StyleAuraButton
    -- hands over the stack text, with its count formatter.
    btn:SetIcon(icon)
    btn:SetDurationCooldown(swipe)
    btn:EnableMouse(false)
end

-- Exported: aura group rows wire their engine buttons with the same recipe.
Driver.WireButton = WireButton

-- Ladder over the holder (Factory.AURA_LADDER: the missing look's border +1,
-- glows +2, texts +3): the button +4, then its stack (Factory.BUTTON_STACK):
-- swipe, its border, its glows, texts over them, the time-left bar over those.
-- Anchored two-point, never reparented; re-asserted because holder levels move
-- on reparenting and children do not follow a parent's SetFrameLevel. `lift`
-- adds one for a spell overlay, leaving +3 for the spell's charge count.
local function AnchorButton(b, holder, lift)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    local lvl = holder:GetFrameLevel() + Factory.AURA_LADDER.button + (lift or 0)
    b:SetFrameStrata(holder:GetFrameStrata())
    b:SetFrameLevel(lvl)
    -- A plain copy for the glow host's level: a read off the button can be
    -- secret inside the create window.
    b._adLevel = lvl
    -- the low stack while a Before that copy is on (Factory.ButtonStack)
    local S = Factory.ButtonStack(b)
    if b._adSwipe then b._adSwipe:SetFrameLevel(lvl + S.swipe) end
    if b._adEdgeHost then b._adEdgeHost:SetFrameLevel(lvl + S.edge) end
    if b.TextOverlay then b.TextOverlay:SetFrameLevel(lvl + S.text) end
    if b._adTimeGate then b._adTimeGate:SetFrameLevel(lvl + S.gate) end
    if b._adBeforeCopy then b._adBeforeCopy:SetFrameLevel(lvl + Factory.BUTTON_STACK_LOW.copy) end
end
-- Exported: the editor preview's stand-in button takes the same ladder.
Driver.AnchorButton = AnchorButton

-- A button's lift on its holder: a cooldown icon's aura one up, and in its
-- stage over every cooldown glow too.
local function SubLift(e, sub)
    local lift = e.lift or 0
    if lift > 0 and sub.inStage then lift = lift + STAGE_LIFT end
    return lift + (sub.rise or 0)
end

-- How far a holder's texts go up for a staged aura's buttons (Factory.TextRise).
function Driver.TextLift(rec)
    local e = rec and entries[rec.id]
    if not (e and rec.kind ~= "aura" and e.stage and not e.off) then return 0 end
    for _, sub in ipairs(e.subs) do
        if sub.inStage then return STAGE_LIFT end
    end
    return 0
end

-- The stage
-- Containers are born in the stage: the game will not move one while auras are secret.

local function StageLocked(st)
    if not InCombatLockdown() then return false end
    local prot = st.IsProtected and st:IsProtected()
    if issecretvalue and issecretvalue(prot) then return true end
    return prot == true
end

local function EnsureStage(entry, rec)
    if entry.stage then return entry.stage end
    -- an aura icon, an aura over a cooldown, or a charges state's cut
    if not (FB_OK and rec and (rec.kind == "aura" or ShapeFor(rec) or entry.gate)) then return nil end
    local st = CreateFrame("Frame", nil, UIParent)
    st:SetSize(1, 1)
    st:SetPoint("TOP", UIParent, "TOP", 0, -80)
    st:SetFlattensRenderLayers(true)
    -- empty until an attach puts the missing look on it
    st:SetAlpha(0)
    -- What the stage holds hangs off this inner frame, which carries the
    -- icon's alpha: a frame buffer draws its children already faded by its own
    -- alpha and then pastes the picture at that alpha again, so the stage
    -- itself only shows (1) or hides (0).
    local dim = CreateFrame("Frame", nil, st)
    dim:SetAllPoints(st)
    st._adDim = dim
    entry.stage = st
    return st
end

local function AnchorStage(entry)
    local st, holder = entry.stage, entry.holder
    if not (st and holder) then return true end
    if StageLocked(st) then return false end
    st:ClearAllPoints()
    st:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    st:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    st:SetFrameStrata(holder:GetFrameStrata())
    st:SetFrameLevel(holder:GetFrameLevel())
    -- born on UIParent: the holder's layout scale, so the button's texts and
    -- edges count in the holder's units
    FollowScale(st, holder)
    return true
end

-- Attached, the missing look rides the stage; detached, it goes home for the
-- editor preview. A cooldown icon's look does the same under its aura.
local function StageLook(entry, on)
    local f = entry.holder
    if not (f and entry.stage and entry.rec) then return end
    local aura = entry.rec.kind == "aura"
    local move = aura and Factory.StageMissingLook or Factory.StageCooldownLook
    -- a cooldown's move runs again: a piece made since (a shadow switched on)
    -- follows, and its texts with a charges state's cut
    if on and (not entry.staged or not aura) then
        move(f, entry.stage._adDim, entry.gate ~= nil)
        entry.staged = true
    elseif not on and entry.staged then
        move(f, nil)
        entry.staged = false
    end
end

-- The stage keeps its holder's strata and level when they change outside a
-- restyle (a raise, a drag, a new layer); locked in combat, the next restyle does it.
function Driver.FollowHolder(f)
    local e = f and f._adRecId and entries[f._adRecId]
    if not (e and e.stage and e.holder == f and e.staged) or StageLocked(e.stage) then return end
    local s, l = f:GetFrameStrata(), f:GetFrameLevel()
    if issecretvalue and (issecretvalue(s) or issecretvalue(l)) then return end
    if e.stage:GetFrameStrata() ~= s then e.stage:SetFrameStrata(s) end
    if e.stage:GetFrameLevel() ~= l then e.stage:SetFrameLevel(l) end
end

-- On before any button needs it, off only after every button dropped it
-- (DropBuffer). A charges state's cut needs it too; the aura's button keeps its own setting.
local function GateCuts(entry)
    local g = entry.gate
    return g ~= nil and (g.whole or g.copy) == true
end

local function BufferFor(entry, want)
    local st = entry.stage
    if (want or GateCuts(entry)) and not entry.fbOn and not StageLocked(st) then
        st:SetIsFrameBuffer(true)
        entry.fbOn = true
    end
    entry.erase = want and entry.fbOn == true
end

-- The charges state's cut over the whole look (Factory.ApplyChargeGate): only
-- on a stage set up for it (BufferFor), never while the options window is open.
local function SyncChargeGate(entry)
    local st, f, g = entry.stage, entry.holder, entry.gate
    -- nothing to cut and nothing built: most stages
    if not st or (not g and not st._adChargeBar) then return end
    local E = NS.LayoutEngine
    local edit = E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true
    if not (g and f and entry.staged and not edit) then
        Factory.ApplyChargeGate(st, nil)
        if f and f._adChargeBar == st._adChargeBar then f._adChargeBar = nil end
        return
    end
    local o = AuraButtonOpts(entry)
    local lvl = f:GetFrameLevel()
    if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then lvl = nil end
    f._adChargeBar = Factory.ApplyChargeGate(st, g, o.w, o.h, Factory.SpellLookReach(entry.rec, o.h / 36, o.w),
        lvl, entry.rec, f, entry.fbOn == true)
    -- the count now; the cooldown driver's charge updates feed it from here
    Factory.FeedChargeGate(f)
end

local function SyncEraser(entry)
    if not (entry.stage and entry.staged) then
        entry.erase = false
        SyncChargeGate(entry)
        return
    end
    BufferFor(entry, Driver.NeedsEraser(entry.rec))
    SyncChargeGate(entry)
end

local function DropBuffer(entry)
    if entry.fbOn and not entry.erase and not GateCuts(entry)
        and entry.stage and not StageLocked(entry.stage) then
        entry.stage:SetIsFrameBuffer(false)
        entry.fbOn = false
    end
end

-- Slots
-- One container per icon and lane, each given one AddAuraSlot at creation,
-- while its pool is empty: the provider then makes a fresh button, legal from
-- any context. Re-slotting a used container fails. While auras are secret,
-- creation after the load window is blocked, so it waits for a settle edge.

-- A parked slot is switched off too: the game's container listens to its
-- unit's aura events while any of its slots is on, and a parked one (the
-- never-matching id) still worked through every change on that unit. Data
-- only, as the filters are. A slot's one button stays its own while off.
-- unit, harmful, ids: the slot's own, given so a target or focus slot side-parks
local function SlotOn(c, key, on, harmful, ids, unit)
    if c and c.SetAuraSlotEnabled then
        local want = on == true
        if unit and ids then want = SideSlot(c, key, unit, want, harmful, ids) end
        c:SetAuraSlotEnabled(key, want)
        NoteSlot(c, key, want)
    end
end
Driver.SlotOn = SlotOn

-- The glow lanes, made the same way, one per glow that wants one and has none
-- yet (a lane is kept once made: a glow switched off parks it). Their buttons
-- are never wired: the game draws nothing on them, and the glow is all we add.
-- They start at alpha 0; SyncEntryAlpha lets them in. True when every wanted
-- glow has its lanes.
local function EnsureGlowSlots(iconId, entry, startParked)
    if not IS_121 then return false end
    local rec = entry.rec
    local want = {}
    for k = 1, GlowSlots() do
        if GlowIDs(rec, k) and not HasGlowLane(entry, k) then want[#want + 1] = k end
    end
    if #want == 0 then return true end
    if loadWindowOver and AurasSecretNow() then
        entry.glowPending = true
        return false
    end
    entry.glowPending = nil
    entry.glows = entry.glows or {}
    local d = ShapeFor(rec) or {}
    for _, slot in ipairs(want) do
        local gids = GlowIDs(rec, slot)
        for _, lane in ipairs(LanesFor(d)) do
            local c = CreateIconContainer(lane.unit)
            if c then
                c:SetAlpha(0)
                FollowScale(c, entry.holder)
                local key = "adglow" .. slot .. "_" .. tostring(iconId) .. "_" .. lane.unit
                    .. (lane.harmful and "_h" or "_b") .. "_g" .. (entry.gen or 0)
                local ids = (startParked or not gids) and { [0] = true } or gids
                local g = { slot = slot, unit = lane.unit, key = key, container = c,
                    harmful = lane.harmful, rise = lane.rise, filterSig = FilterSig(ids), ids = ids }
                entry.glows[#entry.glows + 1] = g
                c:AddAuraSlot(key, FilterForLane(d, lane), {
                    maxFrameCount = 1,
                    initializeFrame = function(b)
                        b:EnableMouse(false)
                        local e = entries[iconId]
                        if not e then return end
                        g.frame = b
                        if e.holder then AnchorButton(b, e.holder, (e.lift or 0) + (g.rise or 0)) end
                        if e.rec then
                            Factory.StyleAuraGlowButton(b, e.rec, HolderPx(e),
                                GlowOpts(e, AuraButtonOpts(e), g))
                        end
                    end,
                    candidateFilters = { includeSpellIDs = ids },
                })
                SlotOn(c, key, not (startParked or not gids), lane.harmful, ids, lane.unit)
            end
        end
    end
    return true
end

local function EnsureSlots(iconId, rec, startParked)
    local entry = entries[iconId]
    if entry and #entry.subs > 0 then return true end
    if not IS_121 then return false end
    if loadWindowOver and AurasSecretNow() then
        pendingCreate[iconId] = true
        return false
    end

    entry = entry or { subs = {}, gen = 0 }
    entry.rec = rec
    entry.gen = entry.gen or 0
    entry.parked = startParked and true or false
    entries[iconId] = entry

    -- Glow lanes first, so the icon's button is born knowing its glow moved.
    if AnyGlowWanted(rec) then EnsureGlowSlots(iconId, entry, startParked) end

    local d = ShapeFor(rec) or {}
    -- Buttons are set at birth: in an instance they are never restyled.
    local stage = EnsureStage(entry, rec)
    if stage then BufferFor(entry, Driver.NeedsEraser(rec)) end
    for _, lane in ipairs(LanesFor(d)) do
        local c = CreateIconContainer(lane.unit, stage and stage._adDim)
        if c then
            -- in a stage it rides the stage's scale; on UIParent it takes its own
            if not stage then FollowScale(c, entry.holder) end
            -- generation-suffixed key: slots can never be removed; a rewire
            -- parks the old keys and adds fresh ones
            local key = "ad" .. tostring(iconId) .. "_" .. lane.unit
                .. (lane.harmful and "_h" or "_b") .. "_g" .. entry.gen
            -- Parked creation bakes in the never-matching id.
            local ids = startParked and { [0] = true } or IncludeMap(d)
            local sub = { unit = lane.unit, key = key, container = c, harmful = lane.harmful,
                rise = lane.rise, filterSig = FilterSig(ids), ids = ids, inStage = stage ~= nil }
            entry.subs[#entry.subs + 1] = sub
            c:AddAuraSlot(key, FilterForLane(d, lane), {
                maxFrameCount = 1,
                initializeFrame = function(b)
                    WireButton(b)
                    -- its glows draw in the stage (Factory.GlowBlend)
                    b._adFlat = sub.inStage or nil
                    local e = entries[iconId]
                    if not e then return end
                    sub.frame = b
                    if e.holder then AnchorButton(b, e.holder, SubLift(e, sub)) end
                    -- Style the button as it is created; StyleAuraButton (shared with the group
                    -- driver) draws every option on it.
                    local r = e.rec
                    if r then
                        local opts = AuraButtonOpts(e)
                        opts.glowElsewhere = GlowMoved(e)
                        Factory.StyleAuraButton(b, r, HolderPx(e), opts)
                    end
                    b:EnableMouse(false)
                end,
                candidateFilters = { includeSpellIDs = ids },
            })
            SlotOn(c, key, not startParked, lane.harmful, ids, lane.unit)
        end
    end
    entry.own = entry.subs
    return #entry.subs > 0
end

-- Shared containers
-- Every live container on a unit re-reads each aura change there, so icons that
-- ask nothing of a container of their own share one per group (or a layout's
-- free icons) and unit: a slot each, its button pinned onto its own icon, as
-- the own one is. A shared button takes its container's opacity, which follows
-- the group's, so a member may only hide (its slot off), never dim alone; an
-- icon that fades on its own, needs its own stage or has glow lanes
-- keeps its own containers. Both sets are made in the load window: the own, as
-- ever, and a slot in its group's shared ones, all at that container's birth (a
-- container that has lived takes no new slot). The set in use is entry.subs;
-- the other sits parked. An icon made later keeps its own until a reload.

local domains = {}   -- [key] = { key, byUnit = { [unit] = container }, members = { [entry] = true }, parent, alpha }

-- True when an aura icon may ride its group's shared containers.
local function ShareOK(rec)
    if not (IS_121 and rec and rec.kind == "aura") then return false end
    -- Dynamic group rows and type looks draw their own
    if not Driver.GlowLaneOK(rec) then return false end
    if Driver.NeedsEraser(rec) or AnyGlowWanted(rec) or Driver.CountGate(rec) then return false end
    local a = Store.Resolve(rec, "appearance", "alpha") or 1
    if a ~= 1 and a ~= 0 then return false end
    local C = NS.Conditions
    return not (C and C.OwnFadeBinary) or C.OwnFadeBinary(rec)
end
Driver.ShareOK = ShareOK

-- One key per frame its members' holders ride: the group, or a layout's free icons.
local function DomainKey(rec)
    if rec.groupId then return "g" .. tostring(rec.groupId) end
    local lay = Store.LayoutOf and Store.LayoutOf(rec)
    return "l" .. tostring(lay and lay.id or "none")
end
Driver.DomainKey = DomainKey

-- The icon's slots in its group's shared containers, parked: load window only.
local function AddSharedSlots(iconId, entry, rec)
    local dk = DomainKey(rec)
    local dom = domains[dk]
    if dom and dom.sealed then return end
    if not dom then
        dom = { key = dk, byUnit = {}, members = {} }
        domains[dk] = dom
    end
    local d = ShapeFor(rec) or {}
    local never = { [0] = true }
    local share = {}
    for _, lane in ipairs(LanesFor(d)) do
        local c = dom.byUnit[lane.unit]
        if not c then
            c = CreateIconContainer(lane.unit)
            if not c then return end
            dom.byUnit[lane.unit] = c
        end
        local key = "ads" .. tostring(iconId) .. "_" .. lane.unit
            .. (lane.harmful and "_h" or "_b") .. "_g" .. (entry.gen or 0)
        local sub = { unit = lane.unit, key = key, container = c, harmful = lane.harmful,
            rise = lane.rise, filterSig = FilterSig(never), ids = never, dom = dom }
        share[#share + 1] = sub
        c:AddAuraSlot(key, FilterForLane(d, lane), {
            maxFrameCount = 1,
            initializeFrame = function(b)
                WireButton(b)
                local e = entries[iconId]
                if not e then return end
                sub.frame = b
                if e.holder then AnchorButton(b, e.holder, SubLift(e, sub)) end
                local r = e.rec
                if r then
                    local opts = AuraButtonOpts(e)
                    opts.glowElsewhere = GlowMoved(e)
                    opts.erase = false
                    Factory.StyleAuraButton(b, r, HolderPx(e), opts)
                end
                b:EnableMouse(false)
            end,
            candidateFilters = { includeSpellIDs = never },
        })
        SlotOn(c, key, false, lane.harmful, never, lane.unit)
    end
    entry.share = share
end

-- The members' holders all ride one frame: the first to join names it.
local function DomainFits(dom, entry)
    local p = entry.holder and entry.holder:GetParent()
    if not p then return false end
    if dom.parent == nil or next(dom.members) == nil or (next(dom.members) == entry and next(dom.members, entry) == nil) then
        dom.parent = p
        return true
    end
    return dom.parent == p
end

-- The shared containers' opacity is their frame's: written on a change.
local function SyncDomain(dom, holder)
    local p = dom.parent
    local pa = p and (p.GetEffectiveAlpha and p:GetEffectiveAlpha() or p:GetAlpha()) or 1
    if type(pa) ~= "number" or (issecretvalue and issecretvalue(pa)) then pa = 1 end
    if dom.alpha ~= pa then
        dom.alpha = pa
        for _, c in pairs(dom.byUnit) do c:SetAlpha(pa) end
    end
    for _, c in pairs(dom.byUnit) do FollowScale(c, holder) end
    return pa
end

-- For /arcperf and the tests: shared containers, members riding them, slots made.
function Driver.ShareCensus()
    local nc, nm = 0, 0
    for _, dom in pairs(domains) do
        for _ in pairs(dom.byUnit) do nc = nc + 1 end
        for _ in pairs(dom.members) do nm = nm + 1 end
    end
    return nc, nm
end

-- Park and unpark. Filter edits are data-only and legal anywhere, but are
-- queued through combat anyway.

-- One set of an icon's slots; a quiet one (its icon hidden) stays off.
local function ApplySubs(entry, list, parked)
    -- a switched-off overlay reads as no ids: the never-matching sentinel
    local d = (entry.rec and ShapeFor(entry.rec)) or {}
    for _, sub in ipairs(list) do
        local c = sub.container
        -- Re-push the filter string so a Cast by edit reaches a live icon; an
        -- unchanged one is a no-op. The string goes first (unpark order).
        if not parked and c.SetAuraSlotFilterString then
            c:SetAuraSlotFilterString(sub.key, FilterForLane(d, sub))
        end
        local ids = parked and { [0] = true } or IncludeMap(d)
        local sig = FilterSig(ids)
        if sub.filterSig ~= sig then
            sub.filterSig = sig
            c:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = ids })
        end
        sub.ids = ids
        SlotOn(c, sub.key, not parked and not sub.quiet, sub.harmful, ids, sub.unit)
    end
end

local function ApplySlotFilters(entry, parked)
    local d = (entry.rec and ShapeFor(entry.rec)) or {}
    ApplySubs(entry, entry.subs, parked)
    -- glow lanes: each glow's ids while it wants its lane, else parked
    for _, g in ipairs(entry.glows or {}) do
        local c = g.container
        local gids = (not parked) and GlowIDs(entry.rec, g.slot) or nil
        if gids and c.SetAuraSlotFilterString then
            c:SetAuraSlotFilterString(g.key, FilterForLane(d, g))
        end
        local ids = gids or { [0] = true }
        local sig = FilterSig(ids)
        if g.filterSig ~= sig then
            g.filterSig = sig
            c:SetAuraSlotCandidateFilters(g.key, { includeSpellIDs = ids })
        end
        g.ids = ids
        SlotOn(c, g.key, gids ~= nil and not g.quiet, g.harmful, ids, g.unit)
    end
    entry.parked = parked and true or false
end

local function SetParked(entry, parked)
    if InCombatLockdown() then
        combatQueue[entry] = parked
        return
    end
    ApplySlotFilters(entry, parked)
end

-- Which set carries the icon: its group's shared slots while it qualifies,
-- tracks the lanes they were made for and rides that group's frame; else its
-- own. Switched out of combat only (the next settle edge otherwise); the set
-- leaving is parked, the one arriving takes the icon's park state.
local function SyncShare(entry)
    local sh = entry.share
    if not (sh and entry.own) then return end
    local onShare = entry.subs == sh
    local want = not entry.shareBad and ShareOK(entry.rec)
        and LaneSig(sh) == LaneSig(LanesFor(ShapeFor(entry.rec) or {}))
        and DomainFits(sh[1].dom, entry)
    if want == onShare then
        if onShare then sh[1].dom.members[entry] = true end
        return
    end
    if InCombatLockdown() then
        entry.sharePending = true
        return
    end
    entry.sharePending = nil
    ApplySubs(entry, entry.subs, true)
    if onShare then
        sh[1].dom.members[entry] = nil
        entry.subs = entry.own
    else
        entry.subs = sh
        sh[1].dom.members[entry] = true
    end
    ApplySlotFilters(entry, entry.parked)
end
Driver.SyncShare = SyncShare

-- Whether this engine button may be written to in the current context.
local function IsAccessible(b)
    if not b then return false end
    if b.CanBeAccessedInContext then return b:CanBeAccessedInContext() == true end
    return not (b.IsForbidden and b:IsForbidden())
end
Driver.IsAccessible = IsAccessible

-- 12.1.0 skips the spell-ID filter on a debuff of a unit you can assist and on
-- a buff of one you cannot, then shows whatever aura comes first (12.1.5 shows
-- nothing there). Such a target or focus lane stays hidden until the unit turns.
-- d: the aura shape the lane tracks (a bar glow's own, Bars\AD_BarGlow.lua).
function Driver.LaneBlindFor(unit, harmful, d)
    if not NS.AuraEngine1210 or (unit ~= "target" and unit ~= "focus") then return false end
    if not (UnitExists and UnitCanAssist) then return false end
    local on = UnitExists(unit)
    if (issecretvalue and issecretvalue(on)) or on ~= true then return false end
    local assist = UnitCanAssist("player", unit, true, true)
    if issecretvalue and issecretvalue(assist) then return false end
    if (assist == true) ~= (harmful == true) then return false end
    return not Driver.IDsNeverSecret(d or {})
end
local function LaneBlind(unit, harmful, rec)
    return Driver.LaneBlindFor(unit, harmful, ShapeFor(rec))
end
Driver.LaneBlind = LaneBlind

local SyncEntryAlpha

-- An icon coming back: its button fills on the container's next pass, so the
-- missing look under it waits that long instead of showing for a frame.
local function HoldReveal(entry)
    if not entry.stage or entry.revealHold then return end
    entry.revealHold = true
    entry.stage:SetAlpha(0)
    C_Timer.After(0.05, function()
        entry.revealHold = nil
        if entry.holder and not entry.off then SyncEntryAlpha(entry) end
    end)
end

-- A slot that can show nothing (its icon hidden or at 0) is switched off, so
-- it stops reading its unit's auras; on again, the game reads them afresh.
local function SetQuiet(entry, sub, quiet)
    quiet = quiet == true
    -- never set reads as not quiet: a first pass that keeps it on changes nothing
    if (sub.quiet == true) == quiet then return end
    sub.quiet = quiet
    -- parked: its slot is off already, and the unpark reads sub.quiet
    if entry.parked then return end
    SlotOn(sub.container, sub.key, not quiet, sub.harmful, sub.ids, sub.unit)
    if not quiet and not sub.slot then HoldReveal(entry) end
end

-- A shared member at an opacity of its own: back to its own containers.
local function ShareMismatch(entry)
    if entry.shareBad then return end
    entry.shareBad = true
    if InCombatLockdown() then
        entry.sharePending = true
    else
        C_Timer.After(0, function()
            SyncShare(entry)
            if entry.holder and not entry.off then SyncEntryAlpha(entry) end
        end)
    end
end

-- The button hangs off its container, not the holder, so the container mirrors
-- the holder's alpha; a shared container its group's.
SyncEntryAlpha = function(entry)
    local holder = entry.holder
    if not holder then return end
    local ea = holder.GetEffectiveAlpha and holder:GetEffectiveAlpha() or holder:GetAlpha() or 1
    -- A secret alpha reads as 1: Detach zeroes the container, so skipping here
    -- would strand it invisible.
    if issecretvalue and issecretvalue(ea) then ea = 1 end
    -- Play on screen draws a copy over this icon; the real button stays out.
    local a = ea
    local scr = NS.IconScreen
    if scr and entry.rec and scr.On(entry.rec.id) then a = 0 end
    -- its totem shows first, on the icon itself (Drivers\AD_DriverPhase.lua): the aura steps aside
    if holder._adPhaseUp then a = 0 end
    -- not a holder child: a hidden holder hides its missing look here, and
    -- quiets a shared slot (its container stays up for the rest)
    local vis = true
    if holder.IsVisible then
        vis = holder:IsVisible()
        if issecretvalue and issecretvalue(vis) then vis = true end
    end
    if entry.stage then
        entry.stage:SetAlpha((vis and entry.staged and not entry.revealHold) and 1 or 0)
        entry.stage._adDim:SetAlpha(ea)
    end
    -- a switched-off overlay keeps its containers at 0: only a cut's stage follows
    if entry.off then return end
    for _, sub in ipairs(entry.subs) do
        local sa = a
        if LaneBlind(sub.unit, sub.harmful, entry.rec) then sa = 0 end
        if sub.dom then
            local pa = SyncDomain(sub.dom, holder)
            if sa > 0 and math.abs(sa - pa) > 0.01 then ShareMismatch(entry) end
        elseif sub.inStage then
            sub.container:SetAlpha(sa > 0 and 1 or 0)
        else
            sub.container:SetAlpha(sa)
        end
        SetQuiet(entry, sub, sa <= 0 or not vis)
    end
    -- the glow lanes: the icon's alpha while their glow wants them, and a
    -- combat-only glow also waits for combat
    for _, g in ipairs(entry.glows or {}) do
        local rec = entry.rec
        local suf = (g.slot > 1) and tostring(g.slot) or ""
        local ga = a
        if not GlowIDs(rec, g.slot) or LaneBlind(g.unit, g.harmful, rec) then
            ga = 0
        elseif not GlowsForCombat()
            and Store.Resolve(rec, "auraActive", "activeGlowCombatOnly" .. suf) == true then
            ga = 0
        end
        g.container:SetAlpha(ga)
        SetQuiet(entry, g, ga <= 0 or not vis)
    end
end

-- A target or focus swap, or its side turning, on 12.1.0: re-judge its lanes.
function Driver.SyncUnitAlpha(unit)
    if not NS.AuraEngine1210 then return end
    for _, entry in pairs(entries) do
        if entry.holder and not entry.off then
            for _, sub in ipairs(entry.subs) do
                if sub.unit == unit then
                    SyncEntryAlpha(entry)
                    break
                end
            end
        end
    end
end

-- Play on screen starting or stopping on this icon: its container follows.
function Driver.SyncAlpha(id)
    local entry = entries[id]
    if entry and entry.holder and ((#entry.subs > 0 and not entry.off) or entry.gate) then
        SyncEntryAlpha(entry)
    end
end

-- Re-style live buttons where accessible; new ones style in initializeFrame.
local function RestyleEntry(entry)
    -- locked: something this pass could not reach, so it stays on
    local locked = false
    if entry.stage then
        if AnchorStage(entry) then
            -- a switched-off overlay leaves the cooldown's look home
            StageLook(entry, not entry.off)
        else
            entry.stylePending = true
            locked = true
        end
        SyncEraser(entry)
    end
    local px = HolderPx(entry)
    local opts = AuraButtonOpts(entry)
    opts.glowElsewhere = GlowMoved(entry)
    -- the Missing and Always glows are the holder's: our frames, never locked
    if entry.holder and entry.rec and entry.rec.kind == "aura" then
        Factory.ApplyMissingGlows(entry.holder, entry.rec, opts.w, opts.h, GlowsForCombat())
        Factory.ApplyAlwaysGlows(entry.holder, entry.rec, opts.w, opts.h, GlowsForCombat())
    end
    -- both sets, so a switch between them finds its buttons ready
    local other = entry.share and ((entry.subs == entry.share) and entry.own or entry.share) or nil
    for _, list in ipairs({ entry.subs, other }) do
        for _, sub in ipairs(list) do
            local b = sub.frame
            if b then
                if IsAccessible(b) then
                    if not (sub.inStage or sub.dom) then FollowScale(sub.container, entry.holder) end
                    AnchorButton(b, entry.holder, SubLift(entry, sub))
                    local so = opts
                    if sub.dom and opts.erase then
                        so = {}
                        for k, v in pairs(opts) do so[k] = v end
                        so.erase = false
                    end
                    Factory.StyleAuraButton(b, entry.rec, px, so)
                elseif list == entry.subs then
                    entry.stylePending = true
                    locked = true
                end
            end
        end
    end
    for _, g in ipairs(entry.glows or {}) do
        local b = g.frame
        if b then
            if IsAccessible(b) then
                FollowScale(g.container, entry.holder)
                AnchorButton(b, entry.holder, (entry.lift or 0) + (g.rise or 0))
                Factory.StyleAuraGlowButton(b, entry.rec, px, GlowOpts(entry, opts, g))
            else
                entry.stylePending = true
            end
        end
    end
    if not locked then DropBuffer(entry) end
end

-- A hidden holder hides the missing look it lent the stage; shown again, it takes its fade back.
local function HookHolder(f)
    if f._adStageHooked then return end
    f._adStageHooked = true
    f:HookScript("OnHide", function(self)
        local e = entries[self._adRecId]
        if e and e.stage and e.holder == self then
            e.stage:SetAlpha(0)
            -- a shared container stays up for the rest: this icon's slots go quiet
            for _, sub in ipairs(e.subs) do SetQuiet(e, sub, true) end
            for _, g in ipairs(e.glows or {}) do SetQuiet(e, g, true) end
        end
    end)
    f:HookScript("OnShow", function(self)
        local e = entries[self._adRecId]
        if e and e.stage and e.holder == self and (not e.off or e.gate) then SyncEntryAlpha(e) end
    end)
    hooksecurefunc(f, "SetFrameStrata", Driver.FollowHolder)
    hooksecurefunc(f, "SetFrameLevel", Driver.FollowHolder)
end

-- A strata set on a holder's parent reaches the holder without its setter.
function Driver.FollowUnder(frame)
    if not frame then return end
    for _, e in pairs(entries) do
        local h = e.staged and e.holder
        local p = h
        while p and p ~= frame do p = p:GetParent() end
        if p then Driver.FollowHolder(h) end
    end
end

-- The charges state with no aura shown over the icon: its whole look rides a
-- stage of its own (the overlay's, parked, when it has one), made only once a
-- cut is wanted. With the overlay's aura showing, AttachEntry does this.
local function SyncGate(rec, f)
    local entry = entries[rec.id]
    local g = Driver.ChargeGate(rec)
    if not g and not (entry and entry.gate) then return end
    if not entry then
        entry = { rec = rec, subs = {}, parked = false, gen = 0 }
        entries[rec.id] = entry
    end
    entry.gate = g
    if #entry.subs > 0 and not entry.off then
        -- the overlay's stage: the texts follow the cut there, or come home
        if entry.holder == f and entry.stage then
            if entry.staged and AnchorStage(entry) then StageLook(entry, true) end
            SyncEraser(entry)
            if not g then DropBuffer(entry) end
        end
        return
    end
    if not g then
        SyncChargeGate(entry)
        StageLook(entry, false)
        if entry.stage then entry.stage:SetAlpha(0) end
        DropBuffer(entry)
        return
    end
    if entry.holder and entry.holder ~= f then StageLook(entry, false) end
    entry.rec, entry.holder = rec, f
    if not EnsureStage(entry, rec) then return end
    HookHolder(f)
    if AnchorStage(entry) then StageLook(entry, true) end
    SyncEraser(entry)
    SyncEntryAlpha(entry)
end

-- A spell's charge cap moved (a talent): the cut's range and pieces follow.
function Driver.ChargeCapMoved(rec, f)
    if not (IS_121 and rec and f) then return end
    local e = entries[rec.id]
    if (e and e.gate) or Driver.ChargeGate(rec) then SyncGate(rec, f) end
end

-- Driver API, reached through NS.DriverCooldown's Attach and Detach

-- Shared attach for an aura icon and a spell icon's overlay.
local function AttachEntry(rec, f, d)
    local entry = entries[rec.id]
    if not entry then
        entry = { rec = rec, subs = {}, parked = false, gen = 0 }
        entries[rec.id] = entry
    end
    -- a new holder for this record: the old one takes its missing look back
    if entry.holder and entry.holder ~= f then StageLook(entry, false) end
    entry.rec = rec
    entry.holder = f
    entry.off = nil
    -- each attach judges the shared set afresh (an opacity of its own may be gone)
    entry.shareBad = nil
    entry.lift = (rec.kind ~= "aura") and 1 or nil
    -- a spell's charges state cuts the whole look on this stage, the aura's with it
    entry.gate = (rec.kind ~= "aura") and Driver.ChargeGate(rec) or nil
    local unit = LaneOf(d)
    entry.laneUnit = unit

    -- A lane change (new unit, buff to debuff, one unit to two) parks and
    -- retires the old slots, which cannot be removed; fresh ones take the next
    -- generation key. Creation is not combat-safe, so in combat this waits for
    -- a settle edge. Shared slots are never retired (their containers carry
    -- other icons): the icon goes back to its own set, which retires.
    if #entry.subs > 0 and LaneSig(entry.subs) ~= LaneSig(LanesFor(d)) then
        if InCombatLockdown() then
            entry.lanePending = true
        else
            if entry.share and entry.subs == entry.share then
                ApplySubs(entry, entry.share, true)
                entry.share[1].dom.members[entry] = nil
                entry.subs = entry.own or {}
            end
        end
    end
    if #entry.subs > 0 and LaneSig(entry.subs) ~= LaneSig(LanesFor(d)) then
        if not InCombatLockdown() then
            ApplySlotFilters(entry, true)
            entry.retired = entry.retired or {}
            for _, sub in ipairs(entry.subs) do
                sub.container:Hide()
                entry.retired[#entry.retired + 1] = sub
            end
            for _, g in ipairs(entry.glows or {}) do
                g.container:SetAlpha(0)
                g.container:Hide()
                entry.retired[#entry.retired + 1] = g
            end
            entry.subs = {}
            entry.glows = {}
            entry.gen = (entry.gen or 0) + 1
        end
    end

    local fresh = #entry.subs == 0
    if fresh then EnsureSlots(rec.id, rec, false) end
    -- Our own frames, so this runs in combat too.
    if entry.stage then
        HookHolder(f)
        if AnchorStage(entry) then
            StageLook(entry, true)
        else
            entry.stylePending = true
        end
        SyncEraser(entry)
    elseif entry.staged then
        StageLook(entry, false)
    end
    -- its group's shared slots, or its own (Shared containers above)
    SyncShare(entry)

    if not fresh then
        -- a glow set after the slots were made gets its lane now
        if AnyGlowWanted(rec) then EnsureGlowSlots(rec.id, entry, false) end
        -- retarget/reuse: re-push filters (spell ID and caster edits are pure
        -- data) and re-assert anchor + ladder + style on accessible buttons
        SetParked(entry, false)
        if AurasSecretNow() then entry.stylePending = true else RestyleEntry(entry) end
    end
    SyncEntryAlpha(entry)
end

function Driver.Attach(rec, f)
    -- The holder always wears the missing look; the engine button covers it
    -- while the aura is up. No presence read: an aura fetch by name fails
    -- closed while auras are secret (all of combat on Forever).
    Factory.SetState(f, rec, true)
    if not IS_121 then return end
    -- The active glow belongs to the engine button: stop any on the holder.
    Factory.StopAuraGlow(f)
    AttachEntry(rec, f, rec.driver or {})
end

-- A spell, item or trinket icon's aura overlay, called after the cooldown
-- driver's attach; it never sets the holder's state. Off: park the entry and
-- zero its container.
function Driver.AttachOverlay(rec, f)
    if not IS_121 then return end
    local d = ShapeFor(rec)
    if d and OVERLAY_KINDS[rec.kind] then
        AttachEntry(rec, f, d)
        return
    end
    local entry = entries[rec.id]
    if entry and #entry.subs > 0 and not entry.off then
        -- the cooldown's look goes home first, from the holder it rode
        StageLook(entry, false)
        entry.rec, entry.holder, entry.off = rec, f, true
        SetParked(entry, true)
        for _, sub in ipairs(entry.subs) do
            SetQuiet(entry, sub, true)
            sub.container:SetAlpha(0)
        end
        for _, g in ipairs(entry.glows or {}) do
            SetQuiet(entry, g, true)
            g.container:SetAlpha(0)
        end
        if entry.stage then entry.stage:SetAlpha(0) end
    end
    -- no aura over it: a charges state's cut keeps a stage of its own
    if rec.kind == "spell" then SyncGate(rec, f) end
end

function Driver.Detach(id)
    local entry = entries[id]
    if not entry then return end
    if #entry.subs > 0 then
        SetParked(entry, true)
        -- The park can wait out combat and the button is its container's
        -- child, not the holder's: zero the container (legal in combat), or
        -- for a shared one switch this icon's slot off, which is legal too.
        -- SyncEntryAlpha restores either on attach.
        for _, sub in ipairs(entry.subs) do
            SetQuiet(entry, sub, true)
            if not sub.dom then sub.container:SetAlpha(0) end
        end
        for _, g in ipairs(entry.glows or {}) do
            SetQuiet(entry, g, true)
            g.container:SetAlpha(0)
        end
        if entry.share and entry.subs == entry.share then entry.share[1].dom.members[entry] = nil end
    end
    -- the missing look goes home for the editor preview; the stage empties
    StageLook(entry, false)
    SyncChargeGate(entry)
    if entry.stage then entry.stage:SetAlpha(0) end
    if entry.holder then Factory.StopAuraGlow(entry.holder) end
end

function Driver.Refeed(id)
    local entry = entries[id]
    if entry and #entry.subs > 0 then
        SetParked(entry, entry.parked)
    end
end

-- Load-window prebuild, called by AD_Init right after Store.Init: every saved
-- aura icon's slots are made parked at ADDON_LOADED, legal even on a reload
-- into combat or an instance, and a qualifying icon's slots in its group's
-- shared containers with them. The first Attach unparks them.
function Driver.PreBuild()
    if not IS_121 then return end
    if not (Store and Store.EachRecord) then return end
    Store.EachRecord(function(id, rec)
        if rec.type == "icon" and ShapeFor(rec) then
            EnsureSlots(id, rec, true)
            local entry = entries[id]
            if entry and #entry.subs > 0 and not entry.share and ShareOK(rec) then
                AddSharedSlots(id, entry, rec)
            end
        end
    end)
    -- from here on they have lived: no slot is ever added to them again
    for _, dom in pairs(domains) do dom.sealed = true end
end

local function Reattach(rec, holder)
    if rec.kind == "aura" then
        Driver.Attach(rec, holder)
    else
        Driver.AttachOverlay(rec, holder)
    end
end

-- Settle edges: leaving combat and loading screens

local function OnSettleEdge()
    -- flush combat-queued filter edits
    for entry, parked in pairs(combatQueue) do
        ApplySlotFilters(entry, parked)
    end
    wipe(combatQueue)
    -- create slots deferred by secrecy
    if not AurasSecretNow() then
        for iconId in pairs(pendingCreate) do
            pendingCreate[iconId] = nil
            local rec = Store.Get(iconId)
            local entry = entries[iconId]
            if rec and ShapeFor(rec) then
                EnsureSlots(iconId, rec, not (entry and entry.holder))
            end
        end
    end
    -- Work that combat or secrecy deferred: lane swaps and button re-styles.
    for id, entry in pairs(entries) do
        if entry.holder and entry.holder:IsShown() and not entry.off then
            -- a shared / own switch combat held back
            if entry.sharePending and not entry.lanePending then
                SyncShare(entry)
                entry.stylePending = true
                SyncEntryAlpha(entry)
            end
            if entry.lanePending then
                entry.lanePending = nil
                local rec = Store.Get(id)
                if rec then Reattach(rec, entry.holder) end
            elseif #entry.subs > 0 and not AurasSecretNow() then
                -- glow lanes a gate asked for while auras were secret
                if entry.glowPending then
                    local rec = Store.Get(id)
                    if not (rec and AnyGlowWanted(rec)) then
                        entry.glowPending = nil
                    elseif EnsureGlowSlots(id, entry, entry.parked) then
                        ApplySlotFilters(entry, entry.parked)
                        entry.stylePending = true
                        SyncEntryAlpha(entry)
                    end
                end
                if entry.stylePending then
                    entry.stylePending = nil
                    RestyleEntry(entry)
                end
            end
        end
    end
end

-- Combat edges: combat-only glows follow on their containers' alpha.
local function OnCombatEdge(state)
    inCombat = state
    for _, entry in pairs(entries) do
        if entry.glows and #entry.glows > 0 and entry.holder and not entry.off
            and entry.holder:IsShown() then
            SyncEntryAlpha(entry)
        end
        -- the holder's glows are our own frames: they follow here directly
        if entry.holder and not entry.off and entry.rec and entry.rec.kind == "aura" then
            local o = AuraButtonOpts(entry)
            Factory.ApplyMissingGlows(entry.holder, entry.rec, o.w, o.h, GlowsForCombat())
            Factory.ApplyAlwaysGlows(entry.holder, entry.rec, o.w, o.h, GlowsForCombat())
        end
    end
end

Events.On("PLAYER_REGEN_DISABLED", "adaura_glow", function() OnCombatEdge(true) end)
Events.On("PLAYER_REGEN_ENABLED", "adaura_glow", function() OnCombatEdge(false) end)
Events.On("PLAYER_REGEN_ENABLED", "adaura", OnSettleEdge)
Events.On("PLAYER_ENTERING_WORLD", "adaura", OnSettleEdge)
Events.On("PLAYER_LOGIN", "adaura_lw", function()
    loadWindowOver = true
end)
-- Follow my rank: a rank learned (or the spellbook loaded) sends a record's
-- filters again when the ids it follows changed: aura icons, the aura on a
-- spell icon, and aura, text and texture bars. The send waits out combat.
local followSig = {}   -- [record id] = the followed ids last seen
local FOLLOW_BARS = { aura = true, text = true, texture = true }
OnIfValid("SPELLS_CHANGED", "adaura_rank", function()
    wipe(Store.auraRankOf)
    if NS.IsForever ~= true then return end
    Store.EachRecord(function(id, rec)
        local d
        if rec.type == "icon" then
            d = ShapeFor(rec)
        elseif rec.type == "bar" and FOLLOW_BARS[rec.barKind] then
            d = rec.driver
        end
        if d and d.followRank ~= false then
            local sig = table.concat(TrackedIDs(d), ",")
            if followSig[id] ~= sig then
                followSig[id] = sig
                Store.Dirty("style", id)
            end
        end
    end)
end)
-- the engine's visibility pass (conditions -> alpha) fires this after every
-- paint: mirror the holders' effective alpha onto the containers
Events.OnMessage("AD_VISIBILITY", "adaura", function()
    for _, entry in pairs(entries) do
        -- a switched-off overlay keeps its container at 0; a charges state's stage follows
        if entry.holder and ((#entry.subs > 0 and not entry.off) or entry.gate) and entry.holder:IsShown() then
            SyncEntryAlpha(entry)
        end
    end
end)
