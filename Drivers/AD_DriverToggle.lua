-- Toggled on: a spell icon's state while its toggle is on, as the action bar
-- flashes it: Shoot or Auto Shot repeating, melee Attack swinging. Its glow
-- is drawn here; its alpha, grey and tint by Factory.SetState (f._adToggled).
-- Factory.ApplyStyle hands every styled icon to Sync, Factory.Release to Drop.
-- The auto attack conditions read the same state through Use.
-- The game reports both toggles with plain events, in combat too.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local DT = {}
NS.DriverToggle = DT

DT.KEY = "adtoggle"
DT.LANE = "adt"
DT.ATTACK = 6603
-- the auto-repeat spells the options know before one is cast: Auto Shot, Shoot
DT.REPEAT = { [75] = true, [5019] = true }
DT.EVENTS = { "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" }
DT.frames = {}   -- [icon frame] = rec, icons with the toggle glow or a toggled-on look
-- [owner] = fn, readers besides the icons (the auto attack conditions)
DT.users = {}
DT.repeating = false
DT.attacking = false
DT.armed = false

function DT.R(rec, k)
    return Store.Resolve(rec, "states", k)
end

-- A plain true from the game, never a secret one.
function DT.Yes(v)
    return not (issecretvalue and issecretvalue(v)) and v == true
end

-- "attack", "repeat" or nil: which toggle a spell icon's spell is.
function DT.Kind(rec)
    if not (rec and rec.kind == "spell" and type(rec.driver) == "table") then return nil end
    local sid = tonumber(rec.driver.spellID)
    if not sid then return nil end
    if sid == DT.ATTACK then return "attack" end
    if DT.REPEAT[sid] then return "repeat" end
    if C_Spell and C_Spell.IsAutoRepeatSpell and DT.Yes(C_Spell.IsAutoRepeatSpell(sid)) then return "repeat" end
    return nil
end

function DT.IsToggle(rec)
    return DT.Kind(rec) ~= nil
end

-- the toggled-on row on Conditions changes something
function DT.StateSet(rec)
    return DT.R(rec, "toggleAlphaEnabled") == true or DT.R(rec, "toggleDesaturate") == true
        or DT.R(rec, "toggleTintEnabled") == true
end

function DT.Wanted(rec)
    return DT.IsToggle(rec) and (DT.R(rec, "toggleGlow") == true or DT.StateSet(rec))
end

-- The state on the frame: repainted when it flips and the look depends on it.
function DT.Paint(f, rec)
    local on = DT.Wanted(rec) and DT.On(rec) or nil
    if f._adToggled == on then return end
    f._adToggled = on
    if DT.StateSet(rec) then
        NS.Factory.SetState(f, rec, f._adOnCooldown, f._adDesatState)
    end
end

function DT.On(rec)
    local k = DT.Kind(rec)
    if k == "attack" then return DT.attacking end
    if k == "repeat" then return DT.repeating end
    return false
end

function DT.Stop(f)
    if not f._adToggleSig then return end
    NS.Factory.StopGlowLane(f, DT.LANE)
    f._adToggleSig = nil
end

-- The options preview (f._adGlowLaneOnly) shows the glow while it picks the
-- toggle lane, toggled on or not, and hides it for any other.
function DT.Apply(f, rec)
    local only = f._adGlowLaneOnly
    local preview = only == "toggle"
    local want = DT.IsToggle(rec) and DT.R(rec, "toggleGlow") == true and (only == nil or preview)
        and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
        and (preview or DT.On(rec))
    if not want then
        DT.Stop(f)
        return
    end
    local R = function(k) return DT.R(rec, k) end
    local c = R("toggleGlowColor") or { 1, 1, 1, 1 }
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * (R("toggleGlowIntensity") or 1) },
        speed = R("toggleGlowSpeed") or 0.25,
        lines = R("toggleGlowLines") or 8,
        thickness = R("toggleGlowThickness") or 2,
        particles = R("toggleGlowParticles") or 4,
        scale = R("toggleGlowScale") or 1,
        xo = R("toggleGlowXOffset") or 0,
        yo = R("toggleGlowYOffset") or 0,
        level = (R("toggleGlowLevel") or 7) + NS.Factory.Rise(rec),
        strata = R("toggleGlowStrata") or "inherit",
        length = R("toggleGlowLength") or 0,
        mx = R("toggleGlowMoveX") or 0,
        my = R("toggleGlowMoveY") or 0,
    }
    local gtype = NS.Factory.DrawnGlowStyle(R("toggleGlowType") or "redflash")
    -- the icon's size and level are in the key: our flashes and ants bake the size in
    local w, h = f:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w, h = 0, 0 end
    local lv = f:GetFrameLevel()
    if issecretvalue and issecretvalue(lv) then lv = -1 end
    local sig = table.concat({ gtype, p.color[1], p.color[2], p.color[3], p.color[4],
        p.speed, p.lines, p.thickness, p.particles, p.scale, p.xo, p.yo, p.level,
        p.strata, p.length, p.mx, p.my, lv or -1,
        string.format("%.2fx%.2f", w or 0, h or 0) }, ":")
    if f._adToggleSig ~= sig then
        NS.Factory.StopGlowLane(f, DT.LANE)
        NS.Factory.StartGlowLane(f, DT.LANE, gtype, p)
        f._adToggleSig = sig
    end
end

function DT.ApplyAll()
    for f, rec in pairs(DT.frames) do
        DT.Paint(f, rec)
        DT.Apply(f, rec)
    end
end

-- Melee Attack reads as the current spell while it swings; an auto-repeat
-- spell waits for its next start, as nothing reads which one repeats.
function DT.Read()
    DT.attacking = C_Spell ~= nil and C_Spell.IsCurrentSpell ~= nil
        and DT.Yes(C_Spell.IsCurrentSpell(DT.ATTACK))
end

function DT.OnEvent(event)
    if event == "START_AUTOREPEAT_SPELL" then
        DT.repeating = true
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        DT.repeating = false
    elseif event == "PLAYER_ENTER_COMBAT" then
        DT.attacking = true
    elseif event == "PLAYER_LEAVE_COMBAT" then
        DT.attacking = false
    end
    DT.ApplyAll()
    for _, fn in pairs(DT.users) do fn() end
end

-- Events.On registers directly, and a client throws on an event it lacks.
function DT.Valid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e))
end

-- The events stay registered only while an icon or a reader wants them.
function DT.Arm()
    local want = next(DT.frames) ~= nil or next(DT.users) ~= nil
    if want == DT.armed then return end
    DT.armed = want
    for _, e in ipairs(DT.EVENTS) do
        if want then
            if DT.Valid(e) then Events.On(e, DT.KEY, DT.OnEvent) end
        else
            Events.Off(e, DT.KEY)
        end
    end
    if want then
        DT.repeating = false
        DT.Read()
    end
end

function DT.Sync(f, rec)
    if DT.Wanted(rec) then
        DT.frames[f] = rec
    else
        DT.frames[f] = nil
    end
    DT.Arm()
    DT.Paint(f, rec)
    DT.Apply(f, rec)
end

function DT.Drop(f)
    DT.frames[f] = nil
    f._adToggled = nil
    DT.Stop(f)
    DT.Arm()
end

-- A reader's fn runs after every change, and once when its use arms the
-- events, as the state is only known from then on. A nil fn drops it.
function DT.Use(owner, fn)
    if DT.users[owner] == fn then return end
    DT.users[owner] = fn
    local was = DT.armed
    DT.Arm()
    if fn and DT.armed and not was then fn() end
end

-- Melee Attack swinging, an auto-repeat spell repeating: false while nothing
-- keeps the events armed.
function DT.Swinging() return DT.armed and DT.attacking == true end
function DT.Shooting() return DT.armed and DT.repeating == true end
