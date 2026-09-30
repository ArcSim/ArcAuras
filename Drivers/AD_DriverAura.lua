-- Aura icons on the engine-owned AuraContainer, and the aura overlay on spell
-- icons. The icon frame is a holder wearing the "missing" look; the engine
-- button anchored over it shows while the aura is up and carries every Aura
-- Active option (a gated glow rides a glow-only button, see Glow gates).
-- Presence can be secret, so it is never read.

local ADDON, NS = ...
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

-- True when a visible missing look sits under the button; raw settings, so no preview alpha floor.
function Driver.GhostShown(rec)
    return rec ~= nil and Store.Resolve(rec, "auraMissing", "showWhileMissing") ~= false
        and (Store.Resolve(rec, "auraMissing", "missingAlpha") or 1) > 0
end

function Driver.EraserAvailable() return FB_OK and IS_121 end

-- True when the icon needs the eraser: only such an icon pays for a frame buffer.
function Driver.NeedsEraser(rec)
    if not (FB_OK and IS_121 and rec and rec.kind == "aura") then return false end
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

local function LanesFor(d)
    local unit, harmful = LaneOf(d)
    return { { unit = unit, harmful = harmful } }
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

-- the tracked ids in order, primary first, deduped, plain positive numbers
local function SpellIDList(d)
    local out, seen = {}, {}
    local function add(v)
        v = tonumber(v)
        if v and v > 0 and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    d = d or {}
    add(d.spellID)
    if type(d.spellIDs) == "table" then
        for _, v in ipairs(d.spellIDs) do add(v) end
    end
    return out
end
Driver.SpellIDList = SpellIDList

-- Every tracked id on the one button. No ids gets the never-matching id 0,
-- never an empty set: a HELPFUL slot with no id filter shows an arbitrary buff.
local function IncludeMap(d)
    local m = {}
    for _, id in ipairs(SpellIDList(d)) do m[id] = true end
    if next(m) == nil then m[0] = true end
    return m
end
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
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
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
-- Dynamic aura group, whose rows draw it in play.
function Driver.GlowLaneOK(rec)
    if not (IS_121 and rec and rec.kind == "aura") then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    if g and g.groupKind == "aura"
        and Store.Resolve(g, "arrangement", "dynamicLayout") == true then
        return false
    end
    return true
end

-- "While the aura is missing" needs the eraser and an aura icon with its own button.
function Driver.MissingGlowOK(rec)
    return FB_OK and Driver.GlowLaneOK(rec)
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

-- The ids glow `slot` (default 1) follows on its own button, or nil: the glow
-- is off, or it is glow 1 with no gate (a pick of every id counts as none),
-- which stays on the icon's button.
local function GlowIDs(rec, slot)
    slot = slot or 1
    if not Driver.GlowLaneOK(rec) then return nil end
    local suf = (slot > 1) and tostring(slot) or ""
    local R = function(k) return Store.Resolve(rec, "auraActive", k .. suf) end
    if R("activeGlow") ~= true then return nil end
    -- a Missing or Always glow is the holder's, not a button's
    local when = R("activeGlowWhen")
    if when == "missing" or when == "both" then return nil end
    local ids = SpellIDList(rec.driver)
    local m, n = {}, 0
    local pick = tonumber(R("activeGlowFor")) or 0
    if pick > 0 then
        local want = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(pick)
        for _, id in ipairs(ids) do
            if id == pick or (want ~= nil and C_Spell.GetSpellName(id) == want) then
                m[id] = true
                n = n + 1
            end
        end
    end
    if n == 0 or n == #ids then
        -- no pick, one the icon no longer tracks, or all of them
        if slot == 1 and R("activeGlowCombatOnly") ~= true then return nil end
        m = IncludeMap(rec.driver)
    end
    return m
end
Driver.GlowIDs = GlowIDs

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
    return o
end

-- Aura on a spell icon
-- With rec.driver.overlay.on, a spell icon gets an entry like an aura icon's:
-- its button covers the cooldown while the aura is up, styled from the spell
-- icon's record. The overlay table has the aura shape above.

-- the aura shape an entry tracks: an aura icon's driver, a spell icon's
-- overlay while it is on, else nil
local function ShapeFor(rec)
    if not rec then return nil end
    if rec.kind == "aura" then return rec.driver or {} end
    local ov = rec.kind == "spell" and rec.driver and rec.driver.overlay
    if type(ov) == "table" and ov.on == true then return ov end
    return nil
end
Driver.ShapeFor = ShapeFor

-- a spell icon whose aura overlay is on and can run on this client
function Driver.OverlayOn(rec)
    return IS_121 and rec ~= nil and rec.kind == "spell" and ShapeFor(rec) ~= nil
end

-- True when every tracked id is never-secret, the one case a spell-ID filter
-- works on a debuff on a friendly unit. Such filters cover buffs on friendly
-- units and players and debuffs on enemies. Forever rejects any aura it cannot
-- filter by ID (showing nothing); retail 12.1.0 shows the unfiltered aura.
function Driver.IDsNeverSecret(d)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel) then
        return false
    end
    local ids = SpellIDList(d)
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

local function OnIfValid(event, key, fn)
    if C_EventUtils and C_EventUtils.IsEventValid
        and not C_EventUtils.IsEventValid(event) then return end
    Events.On(event, key, fn)
end

local swapArmed = false
local function ArmTargetSwapRefresh()
    if swapArmed then return end
    swapArmed = true
    local function Refresh(unit)
        for _, rc in ipairs(allContainers) do
            if rc.unit == unit and type(rc.frame.UpdateAllAuras) == "function" then
                rc.frame:UpdateAllAuras()
            end
        end
    end
    OnIfValid("PLAYER_TARGET_CHANGED", "adaura_swap", function() Refresh("target") end)
    OnIfValid("PLAYER_FOCUS_CHANGED", "adaura_swap", function() Refresh("focus") end)
    OnIfValid("UNIT_PET", "adaura_swap", function(_, unit)
        if unit == nil or unit == "player" then Refresh("pet") end
    end)
    OnIfValid("GROUP_ROSTER_UPDATE", "adaura_swap", function()
        for i = 1, 4 do Refresh("party" .. i) end
    end)
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

    -- Shown only while the stage buffers (StyleAuraButton, opts.erase).
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

    -- texts above the swipe (a child Cooldown renders over button textures)
    local overlay = CreateFrame("Frame", nil, btn)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(swipe:GetFrameLevel() + 1)
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

-- Ladder over the holder (Factory.AURA_LADDER: the missing look's border and
-- labels +1, its glows +2): button +3, swipe +4, texts +5.
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
    if b._adSwipe then b._adSwipe:SetFrameLevel(lvl + 1) end
    if b.TextOverlay then b.TextOverlay:SetFrameLevel(lvl + 2) end
end
-- Exported: the editor preview's stand-in button takes the same ladder.
Driver.AnchorButton = AnchorButton

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
    if not (FB_OK and rec and rec.kind == "aura") then return nil end
    local st = CreateFrame("Frame", nil, UIParent)
    st:SetSize(1, 1)
    st:SetPoint("TOP", UIParent, "TOP", 0, -80)
    st:SetFlattensRenderLayers(true)
    -- empty until an attach puts the missing look on it
    st:SetAlpha(0)
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
    return true
end

-- Attached, the missing look rides the stage; detached, it goes home for the editor preview.
local function StageLook(entry, on)
    local f = entry.holder
    if not (f and entry.stage) then return end
    if on and not entry.staged and entry.rec and entry.rec.kind == "aura" then
        Factory.StageMissingLook(f, entry.stage)
        entry.staged = true
    elseif not on and entry.staged then
        Factory.StageMissingLook(f, nil)
        entry.staged = false
    end
end

-- Buffer on before any eraser shows, off only after every button dropped it (DropBuffer).
local function BufferFor(entry, want)
    local st = entry.stage
    if want and not entry.fbOn and not StageLocked(st) then
        st:SetIsFrameBuffer(true)
        entry.fbOn = true
    end
    entry.erase = want and entry.fbOn == true
end

local function SyncEraser(entry)
    if not (entry.stage and entry.staged) then
        entry.erase = false
        return
    end
    BufferFor(entry, Driver.NeedsEraser(entry.rec))
end

local function DropBuffer(entry)
    if entry.fbOn and not entry.erase
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
                local key = "adglow" .. slot .. "_" .. tostring(iconId) .. "_" .. lane.unit
                    .. (lane.harmful and "_h" or "_b") .. "_g" .. (entry.gen or 0)
                local ids = (startParked or not gids) and { [0] = true } or gids
                local g = { slot = slot, unit = lane.unit, key = key, container = c,
                    harmful = lane.harmful, filterSig = FilterSig(ids) }
                entry.glows[#entry.glows + 1] = g
                c:AddAuraSlot(key, FilterForLane(d, lane), {
                    maxFrameCount = 1,
                    initializeFrame = function(b)
                        b:EnableMouse(false)
                        local e = entries[iconId]
                        if not e then return end
                        g.frame = b
                        if e.holder then AnchorButton(b, e.holder, e.lift) end
                        if e.rec then
                            Factory.StyleAuraGlowButton(b, e.rec, HolderPx(e),
                                GlowOpts(e, AuraButtonOpts(e), g))
                        end
                    end,
                    candidateFilters = { includeSpellIDs = ids },
                })
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
    -- Buttons know at birth whether they erase: in an instance they are never restyled.
    local stage = (rec.kind == "aura") and EnsureStage(entry, rec) or nil
    if stage then BufferFor(entry, Driver.NeedsEraser(rec)) end
    for _, lane in ipairs(LanesFor(d)) do
        local c = CreateIconContainer(lane.unit, stage)
        if c then
            -- generation-suffixed key: slots can never be removed; a rewire
            -- parks the old keys and adds fresh ones
            local key = "ad" .. tostring(iconId) .. "_" .. lane.unit
                .. (lane.harmful and "_h" or "_b") .. "_g" .. entry.gen
            -- Parked creation bakes in the never-matching id.
            local ids = startParked and { [0] = true } or IncludeMap(d)
            local sub = { unit = lane.unit, key = key, container = c, harmful = lane.harmful,
                filterSig = FilterSig(ids), inStage = stage ~= nil }
            entry.subs[#entry.subs + 1] = sub
            c:AddAuraSlot(key, FilterForLane(d, lane), {
                maxFrameCount = 1,
                initializeFrame = function(b)
                    WireButton(b)
                    local e = entries[iconId]
                    if not e then return end
                    sub.frame = b
                    if e.holder then AnchorButton(b, e.holder, e.lift) end
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
        end
    end
    return #entry.subs > 0
end

-- Park and unpark. Filter edits are data-only and legal anywhere, but are
-- queued through combat anyway.

local function ApplySlotFilters(entry, parked)
    -- a switched-off overlay reads as no ids: the never-matching sentinel
    local d = (entry.rec and ShapeFor(entry.rec)) or {}
    for _, sub in ipairs(entry.subs) do
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
    end
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

-- Whether this engine button may be written to in the current context.
local function IsAccessible(b)
    if not b then return false end
    if b.CanBeAccessedInContext then return b:CanBeAccessedInContext() == true end
    return not (b.IsForbidden and b:IsForbidden())
end
Driver.IsAccessible = IsAccessible

-- The button hangs off its container, not the holder, so the container mirrors the holder's alpha.
local function SyncEntryAlpha(entry)
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
    if entry.stage then
        -- not a holder child: a hidden holder hides its missing look here
        local vis = holder:IsVisible()
        if issecretvalue and issecretvalue(vis) then vis = true end
        entry.stage:SetAlpha((vis and entry.staged) and ea or 0)
    end
    for _, sub in ipairs(entry.subs) do
        if sub.inStage then
            sub.container:SetAlpha(a > 0 and 1 or 0)
        else
            sub.container:SetAlpha(a)
        end
    end
    -- the glow lanes: the icon's alpha while their glow wants them, and a
    -- combat-only glow also waits for combat
    for _, g in ipairs(entry.glows or {}) do
        local rec = entry.rec
        local suf = (g.slot > 1) and tostring(g.slot) or ""
        local ga = a
        if not GlowIDs(rec, g.slot) then
            ga = 0
        elseif not GlowsForCombat()
            and Store.Resolve(rec, "auraActive", "activeGlowCombatOnly" .. suf) == true then
            ga = 0
        end
        g.container:SetAlpha(ga)
    end
end

-- Play on screen starting or stopping on this icon: its container follows.
function Driver.SyncAlpha(id)
    local entry = entries[id]
    if entry and entry.holder and #entry.subs > 0 and not entry.off then
        SyncEntryAlpha(entry)
    end
end

-- Re-style live buttons where accessible; new ones style in initializeFrame.
local function RestyleEntry(entry)
    -- locked: something this pass could not reach, so the buffer stays on
    local locked = false
    if entry.stage then
        if AnchorStage(entry) then
            StageLook(entry, true)
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
    for _, sub in ipairs(entry.subs) do
        local b = sub.frame
        if b then
            if IsAccessible(b) then
                AnchorButton(b, entry.holder, entry.lift)
                Factory.StyleAuraButton(b, entry.rec, px, opts)
            else
                entry.stylePending = true
                locked = true
            end
        end
    end
    for _, g in ipairs(entry.glows or {}) do
        local b = g.frame
        if b then
            if IsAccessible(b) then
                AnchorButton(b, entry.holder, entry.lift)
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
        if e and e.stage and e.holder == self then e.stage:SetAlpha(0) end
    end)
    f:HookScript("OnShow", function(self)
        local e = entries[self._adRecId]
        if e and e.stage and e.holder == self and not e.off then SyncEntryAlpha(e) end
    end)
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
    entry.lift = (rec.kind ~= "aura") and 1 or nil
    local unit, harmful = LaneOf(d)
    entry.laneUnit = unit

    -- A lane change (new unit, or buff to debuff) parks and retires the old
    -- slots, which cannot be removed; fresh ones take the next generation key.
    -- Creation is not combat-safe, so in combat this waits for a settle edge.
    local first = entry.subs[1]
    if first and (first.unit ~= unit or first.harmful ~= harmful) then
        if InCombatLockdown() then
            entry.lanePending = true
        else
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
    if entry.stage and rec.kind == "aura" then
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

-- A spell icon's aura overlay, called after the cooldown driver's attach; it
-- never sets the holder's state. Off: park the entry and zero its container.
function Driver.AttachOverlay(rec, f)
    if not IS_121 then return end
    local d = ShapeFor(rec)
    if d and rec.kind == "spell" then
        AttachEntry(rec, f, d)
        return
    end
    local entry = entries[rec.id]
    if entry and #entry.subs > 0 and not entry.off then
        entry.rec, entry.holder, entry.off = rec, f, true
        SetParked(entry, true)
        for _, sub in ipairs(entry.subs) do sub.container:SetAlpha(0) end
        for _, g in ipairs(entry.glows or {}) do g.container:SetAlpha(0) end
    end
end

function Driver.Detach(id)
    local entry = entries[id]
    if not entry then return end
    if #entry.subs > 0 then
        SetParked(entry, true)
        -- The park can wait out combat and the button is its container's
        -- child, not the holder's: zero the container (legal in combat).
        -- SyncEntryAlpha restores it on attach.
        for _, sub in ipairs(entry.subs) do sub.container:SetAlpha(0) end
        for _, g in ipairs(entry.glows or {}) do g.container:SetAlpha(0) end
    end
    -- the missing look goes home for the editor preview; the stage empties
    StageLook(entry, false)
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
-- into combat or an instance. The first Attach unparks them.
function Driver.PreBuild()
    if not IS_121 then return end
    if not (Store and Store.EachRecord) then return end
    Store.EachRecord(function(id, rec)
        if rec.type == "icon" and ShapeFor(rec) then
            EnsureSlots(id, rec, true)
        end
    end)
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
-- the engine's visibility pass (conditions -> alpha) fires this after every
-- paint: mirror the holders' effective alpha onto the containers
Events.OnMessage("AD_VISIBILITY", "adaura", function()
    for _, entry in pairs(entries) do
        -- a switched-off overlay keeps its container at 0
        if entry.holder and #entry.subs > 0 and not entry.off and entry.holder:IsShown() then
            SyncEntryAlpha(entry)
        end
    end
end)
