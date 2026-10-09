-- Toggled on: a spell icon's state while its toggle is on, as the action bar
-- shows it: Shoot or Auto Shot repeating, melee Attack swinging, a pet spell
-- on autocast. Its glow is drawn here; its alpha, grey and tint by
-- Factory.SetState (f._adToggled).
-- Factory.ApplyStyle hands every styled icon to Sync, Factory.Release to Drop.
-- The auto attack conditions read the same state through Use.
-- The game reports all three with plain events and values, in combat too.

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
-- a pet spell's autocast changes with its pet bar, and with the pet
DT.PET_EVENTS = { "PET_BAR_UPDATE", "UNIT_PET" }
DT.PET_SLOTS = 10   -- the pet bar's buttons
DT.frames = {}   -- [icon frame] = rec, icons with the toggle glow or a toggled-on look
-- [owner] = fn, readers besides the icons (the auto attack conditions)
DT.users = {}
DT.repeating = false
DT.attacking = false
DT.armed = false
DT.petArmed = false
-- [spell ID] = true once seen able to autocast: its rows stay while the pet is away
DT.petCan = {}
DT.bar = {}      -- the pet bar's autocast spells, { id, on }, read once a frame
DT.barAt = nil

function DT.R(rec, k)
    return Store.Resolve(rec, "states", k)
end

-- A plain true from the game, never a secret one.
function DT.Yes(v)
    return not (issecretvalue and issecretvalue(v)) and v == true
end

-- A spell icon's spell ID, or nil for any other icon.
function DT.SpellID(rec)
    if not (rec and rec.kind == "spell" and type(rec.driver) == "table") then return nil end
    return tonumber(rec.driver.spellID)
end

-- "attack", "repeat", "autocast" or nil: which toggle a spell icon's spell is.
function DT.Kind(rec)
    local sid = DT.SpellID(rec)
    if not sid then return nil end
    if sid == DT.ATTACK then return "attack" end
    if DT.REPEAT[sid] then return "repeat" end
    -- the game is asked about the spell the icon reads (rank, override)
    local eff = Store.RecordSpellID(rec.driver)
    if eff and C_Spell and C_Spell.IsAutoRepeatSpell and DT.Yes(C_Spell.IsAutoRepeatSpell(eff)) then return "repeat" end
    if DT.petCan[sid] or DT.Auto(sid, eff) then
        DT.petCan[sid] = true
        return "autocast"
    end
    return nil
end

function DT.IsToggle(rec)
    return DT.Kind(rec) ~= nil
end

-- The pet bar's spells that can autocast, read at most once a frame (the pet
-- events clear barAt). A token (Attack, Follow) never autocasts.
function DT.ReadBar()
    local now = GetTime()
    if DT.barAt == now then return DT.bar end
    DT.barAt = now
    local bar = {}
    if GetPetActionInfo then
        for i = 1, DT.PET_SLOTS do
            local _, _, isToken, _, can, on, id = GetPetActionInfo(i)
            if DT.Yes(can) and not DT.Yes(isToken) and type(id) == "number"
                and not (issecretvalue and issecretvalue(id)) then
                bar[#bar + 1] = { id = id, on = DT.Yes(on) }
            end
        end
    end
    DT.bar = bar
    return bar
end

-- A pet spell that casts itself: can it, and is it on now? C_Spell answers by
-- ID with two plain booleans; the pet bar answers where the client lacks that
-- and for another rank of the spell (Store.SpellMatch). No pet out: neither.
function DT.Auto(sid, eff)
    local get = C_Spell and C_Spell.GetSpellAutoCast
    if get then
        local can, on = get(eff or sid)
        if not DT.Yes(can) and eff and eff ~= sid then can, on = get(sid) end
        if DT.Yes(can) then return true, DT.Yes(on) end
    end
    for _, slot in ipairs(DT.ReadBar()) do
        if Store.SpellMatch(sid, slot.id, eff) then return true, slot.on end
    end
    return false, false
end

-- A spell the player does not know may be a pet's whose pet is not out yet
-- (a login, a dismissed pet), so its icon is followed until the pet shows.
function DT.MaybePet(rec)
    local sid = DT.SpellID(rec)
    if not sid then return false end
    return Store.KnowsSpell(sid) ~= true
end

-- A followed icon listens to the pet bar's events, not the swing's.
function DT.PetIcon(rec)
    local k = DT.Kind(rec)
    if k then return k == "autocast" end
    return DT.MaybePet(rec)
end

-- the toggled-on row on Conditions changes something
function DT.StateSet(rec)
    return DT.R(rec, "toggleAlphaEnabled") == true or DT.R(rec, "toggleDesaturate") == true
        or DT.R(rec, "toggleTintEnabled") == true
end

-- A set toggle look is followed on a toggle spell, and on a spell that may be
-- a pet's (its rows were set while the pet was out).
function DT.Wanted(rec)
    if not (DT.R(rec, "toggleGlow") == true or DT.StateSet(rec)) then return false end
    return DT.IsToggle(rec) or DT.MaybePet(rec)
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
    if k == "autocast" then
        local _, on = DT.Auto(DT.SpellID(rec), Store.RecordSpellID(rec.driver))
        return on
    end
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

-- A pet spell's state is read live, so a change only repaints. Another
-- unit's pet is not ours.
function DT.OnPet(event, unit)
    if event == "UNIT_PET" and unit ~= "player" then return end
    DT.barAt = nil
    DT.ApplyAll()
end

function DT.Listen(list, on, fn)
    for _, e in ipairs(list) do
        if on then
            if DT.Valid(e) then Events.On(e, DT.KEY, fn) end
        else
            Events.Off(e, DT.KEY)
        end
    end
end

-- Each set of events stays registered only while something wants it: the
-- swing and repeat events for their icons and the readers, the pet bar's for
-- the pet spells' icons.
function DT.Arm()
    local swing, pet = next(DT.users) ~= nil, false
    for _, rec in pairs(DT.frames) do
        if DT.PetIcon(rec) then pet = true else swing = true end
    end
    if pet ~= DT.petArmed then
        DT.petArmed = pet
        DT.Listen(DT.PET_EVENTS, pet, DT.OnPet)
    end
    if swing == DT.armed then return end
    DT.armed = swing
    DT.Listen(DT.EVENTS, swing, DT.OnEvent)
    if swing then
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
