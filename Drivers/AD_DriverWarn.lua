-- Warning glow: an icon glows while the ammo runs low, the pet's health is low
-- or the pet is not happy, whatever the icon's own state.
-- Factory.ApplyStyle hands every styled icon to Sync, Factory.Release to Drop.
-- Ammo counts and pet happiness are plain in combat and compared here. Pet
-- health is secret: its glow sits in a frame whose alpha UnitHealthPercent sets
-- through a step curve, inside one that pet existence gates.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local DW = {}
NS.DriverWarn = DW

DW.KEY = "adwarn"
DW.LANE = "adw"
-- curve step width: curves interpolate between points
DW.EPS = 0.0001
DW.frames = {}   -- [icon frame] = rec, icons with the warning glow on
DW.curves = {}   -- [percent] = curve: 1 at or below it, 0 above
DW.armed = {}    -- [event] = true
DW.AMMO_EVENTS = { "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }
DW.MOOD_EVENTS = { "UNIT_PET", "UNIT_HAPPINESS" }
DW.HEALTH_EVENTS = { "UNIT_PET", "UNIT_HEALTH", "UNIT_MAXHEALTH" }

function DW.R(rec, k)
    return Store.Resolve(rec, "states", k)
end

function DW.When(rec)
    return DW.R(rec, "warnGlowWhen") or "ammo"
end

function DW.Wanted(rec)
    return rec ~= nil and rec.kind ~= "aura" and DW.R(rec, "warnGlow") == true
end

-- Whether a plain trigger holds: true, false, or nil when its read is secret.
function DW.Lit(rec, when)
    if when == "ammo" then
        local n = NS.Factory.AmmoCount()
        if n == nil then
            if GetInventoryItemID("player", NS.AMMO_SLOT or 0) == nil then return false end
            return nil
        end
        return n <= (DW.R(rec, "warnAmmoBelow") or 400)
    end
    if when == "petMood" then
        local h = NS.Conditions and NS.Conditions.PetMood()
        if h == nil then return false end
        if DW.R(rec, "warnPetMood") == "unhappy" then return h <= 1 end
        return h < 3
    end
    return false
end

function DW.Curve(pct)
    local c = DW.curves[pct]
    if c == nil and C_CurveUtil and C_CurveUtil.CreateCurve then
        c = C_CurveUtil.CreateCurve()
        local p = pct / 100
        c:AddPoint(0, 1)
        c:AddPoint(p, 1)
        c:AddPoint(p + DW.EPS, 0)
        c:AddPoint(1, 0)
        DW.curves[pct] = c
    end
    return c
end

-- Two frames on the icon at its own level: the outer one follows pet existence,
-- the inner one pet health, and the lane draws on the inner one. Their alpha
-- may be secret, so no lane runs on the icon frame itself.
function DW.Gate(f)
    local g = f._adWarnGate
    if not g then
        g = CreateFrame("Frame", nil, f)
        g:EnableMouse(false)
        g.hp = CreateFrame("Frame", nil, g)
        g.hp:EnableMouse(false)
        f._adWarnGate = g
    end
    -- the icon's own size, set outright: ants and flash bake their art from
    -- the frame's size, which anchors alone may not have resolved yet
    local w, h = f:GetSize()
    local plain = type(w) == "number" and type(h) == "number"
        and not (issecretvalue and (issecretvalue(w) or issecretvalue(h)))
    for _, fr in ipairs({ g, g.hp }) do
        fr:ClearAllPoints()
        if plain and w > 0 and h > 0 then
            fr:SetPoint("CENTER", f, "CENTER")
            fr:SetSize(w, h)
        else
            fr:SetAllPoints(f)
        end
    end
    local lvl = f:GetFrameLevel()
    if type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl)) then
        g:SetFrameLevel(lvl)
        g.hp:SetFrameLevel(lvl)
    end
    return g
end

-- Pet health gates by alpha only: nothing compares it.
function DW.PaintGate(f, rec, preview)
    local g = f._adWarnGate
    if not g then return end
    if preview or DW.When(rec) ~= "petHealth" then
        g:SetAlpha(1)
        g.hp:SetAlpha(1)
        return
    end
    local ex = UnitExists("pet")
    if issecretvalue and issecretvalue(ex) then
        if g.SetAlphaFromBoolean then g:SetAlphaFromBoolean(ex, 1, 0) else g:SetAlpha(1) end
    elseif not ex then
        g:SetAlpha(0)
        return
    else
        -- a dead pet wants Revive Pet, not a heal
        local dead = UnitIsDead and UnitIsDead("pet")
        local isDead = not (issecretvalue and issecretvalue(dead)) and dead == true
        g:SetAlpha(isDead and 0 or 1)
    end
    local c = DW.Curve(DW.R(rec, "warnPetHealth") or 50)
    local v = c and UnitHealthPercent and UnitHealthPercent("pet", true, c)
    if v ~= nil then g.hp:SetAlpha(v) else g.hp:SetAlpha(0) end
end

function DW.Stop(f)
    if not f._adWarnSig then return end
    local g = f._adWarnGate
    if g then
        NS.Factory.StopGlowLane(g.hp, DW.LANE)
        g:Hide()
    end
    f._adWarnSig = nil
end

-- The options preview (f._adGlowLaneOnly) shows the glow while the preview
-- picks the warning lane, whatever the trigger, and hides it for any other.
function DW.Apply(f, rec)
    local only = f._adGlowLaneOnly
    local preview = only == "warn"
    local want = DW.Wanted(rec) and (only == nil or preview)
        and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
    if want and not preview and DW.R(rec, "warnGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    local when = DW.When(rec)
    if want and not preview and when ~= "petHealth" then
        local lit = DW.Lit(rec, when)
        if lit == nil then lit = f._adWarnSig ~= nil end
        want = lit
    end
    if not want then
        DW.Stop(f)
        return
    end
    local R = function(k) return DW.R(rec, k) end
    local c = R("warnGlowColor") or { 1, 0.3, 0.2, 1 }
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * (R("warnGlowIntensity") or 1) },
        speed = R("warnGlowSpeed") or 0.25,
        lines = R("warnGlowLines") or 8,
        thickness = R("warnGlowThickness") or 2,
        particles = R("warnGlowParticles") or 4,
        scale = R("warnGlowScale") or 1,
        xo = R("warnGlowXOffset") or 0,
        yo = R("warnGlowYOffset") or 0,
        level = R("warnGlowLevel") or 7,
        strata = R("warnGlowStrata") or "inherit",
        length = R("warnGlowLength") or 0,
        mx = R("warnGlowMoveX") or 0,
        my = R("warnGlowMoveY") or 0,
    }
    local gtype = NS.Factory.DrawnGlowStyle(R("warnGlowType") or "flash")
    local g = DW.Gate(f)
    -- the icon's size and level are in the key: ants and flash bake the size in
    local w, h = f:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w, h = 0, 0 end
    local lv = g:GetFrameLevel()
    if issecretvalue and issecretvalue(lv) then lv = -1 end
    local sig = table.concat({ gtype, p.color[1], p.color[2], p.color[3], p.color[4],
        p.speed, p.lines, p.thickness, p.particles, p.scale, p.xo, p.yo, p.level,
        p.strata, p.length, p.mx, p.my, lv or -1,
        string.format("%.2fx%.2f", w or 0, h or 0) }, ":")
    if f._adWarnSig ~= sig then
        NS.Factory.StopGlowLane(g.hp, DW.LANE)
        g:Show()
        NS.Factory.StartGlowLane(g.hp, DW.LANE, gtype, p)
        f._adWarnSig = sig
    end
    g:Show()
    DW.PaintGate(f, rec, preview)
end

function DW.ApplyAll()
    for f, rec in pairs(DW.frames) do DW.Apply(f, rec) end
end

function DW.PaintHealth()
    for f, rec in pairs(DW.frames) do
        if f._adWarnSig and DW.When(rec) == "petHealth" then
            DW.PaintGate(f, rec, f._adGlowLaneOnly == "warn")
        end
    end
end

-- Unit events arrive for every unit; a secret token never names ours.
function DW.OnEvent(event, unit)
    if issecretvalue and issecretvalue(unit) then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == "pet" then DW.PaintHealth() end
        return
    end
    if event == "UNIT_HAPPINESS" and unit ~= "pet" then return end
    if (event == "UNIT_PET" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
    Events.Coalesce(DW.KEY, DW.ApplyAll)
end

-- Events.On registers directly, and Forever throws on an event it lacks.
function DW.Valid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e))
end

-- Only the events the live warning glows need stay registered.
function DW.Arm()
    local want = {}
    for _, rec in pairs(DW.frames) do
        local when = DW.When(rec)
        local list = (when == "petHealth" and DW.HEALTH_EVENTS)
            or (when == "petMood" and DW.MOOD_EVENTS) or DW.AMMO_EVENTS
        for _, e in ipairs(list) do want[e] = true end
    end
    for e in pairs(want) do
        if not DW.armed[e] and DW.Valid(e) then
            Events.On(e, DW.KEY, DW.OnEvent)
            DW.armed[e] = true
        end
    end
    for e in pairs(DW.armed) do
        if not want[e] then
            Events.Off(e, DW.KEY)
            DW.armed[e] = nil
        end
    end
end

function DW.Sync(f, rec)
    if DW.Wanted(rec) then
        DW.frames[f] = rec
    else
        DW.frames[f] = nil
    end
    DW.Apply(f, rec)
    DW.Arm()
end

function DW.Drop(f)
    DW.frames[f] = nil
    DW.Stop(f)
    DW.Arm()
end
