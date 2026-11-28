-- AD_StateFx: the glows and sounds of the states that had only a look (Can't
-- use it, Not enough resource, Out of stock, In stock, No weapon) and the
-- sounds of the states whose drivers play none (out of range, toggled on, a
-- spell's proc, suggested, a warning, a totem or stance going on and off, a
-- special icon's procs all used). Their fields are Schema.STATE_GLOWS and
-- Schema.STATE_SOUNDS; Factory's StateTail calls SF.Sync after each state
-- paint, the assist and warning drivers after theirs. Every state read here
-- is a plain flag the drivers already set on our own frame, in combat too.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("StateFx") or C_Timer   -- /arcperf times what they run

local SF = {}
NS.StateFx = SF

local Store = NS.Store

local function R(rec, sec, k) return Store.Resolve(rec, sec, k) end

-- castable as the usability looks read it: off cooldown, or a charge left
-- (unless the usability rules wait for ready)
local function Castable(f, rec)
    local rech = f._adRecharging == true
    if f._adOnCooldown == true and not rech then return false end
    if rech and R(rec, "states", "usabilityReadyOnly") == true then return false end
    return true
end

local function Suggested(rec)
    local AS = NS.DriverAssist
    if not (AS and AS.Spell and AS.SpellOf) then return false end
    local want = AS.Spell()
    if not want then return false end
    local mine = AS.SpellOf(rec)
    return mine ~= nil and (mine == want or (Store.SpellMatch ~= nil and Store.SpellMatch(mine, want) == true))
end

-- each state's test on the icon's frame; nil = not known yet
SF.HOLDS = {
    unusable = function(f, rec) return Castable(f, rec) and f._adUsability == "unusable" end,
    nomana = function(f, rec) return Castable(f, rec) and f._adUsability == "nomana" end,
    range = function(f, rec) return Castable(f, rec) and f._adUsability == "range" end,
    toggle = function(f) return f._adToggled == true end,
    proc = function(f) return f._adProcLit == true end,
    assist = function(f, rec) return Suggested(rec) end,
    -- the warnings Lua reads (ammo, the pet's mood); a pet's health is the game's to draw
    warn = function(f, rec)
        local DW = NS.DriverWarn
        if not (DW and DW.Lit and DW.When) then return nil end
        local when = DW.When(rec)
        if when == "petHealth" then return nil end
        return DW.Lit(rec, when)
    end,
    out = function(f) return f._adItemEmpty == true end,
    stock = function(f)
        if f._adItemEmpty == nil then return nil end
        return f._adItemEmpty == false
    end,
    noWeapon = function(f) return f._adNoWeapon == true end,
    ready = function(f)
        if f._adOnCooldown == nil then return nil end
        return f._adOnCooldown == false
    end,
    cooldown = function(f)
        if f._adOnCooldown == nil then return nil end
        return f._adOnCooldown == true
    end,
}

-- the glows: Schema.STATE_GLOWS, by their state's test
SF.GLOWS = {}
for _, g in ipairs(NS.Schema.STATE_GLOWS or {}) do
    SF.GLOWS[#SF.GLOWS + 1] = { pre = g.pre, kinds = g.kinds, lane = "adsf_" .. g.pre, color = g.color,
        holds = SF.HOLDS[g.pre] }
end

-- the sounds: { the state's test, its switch, its sound, the kinds it plays on }
SF.SOUNDS = {}
for _, s in ipairs(NS.Schema.STATE_SOUNDS or {}) do
    SF.SOUNDS[#SF.SOUNDS + 1] = { key = s.pre, en = s.pre .. "SoundEnabled", snd = s.pre .. "Sound", kinds = s.kinds }
end
-- moments whose rows other kinds already have, played here for these kinds
SF.SOUNDS[#SF.SOUNDS + 1] = { key = "proc", en = "procSoundEnabled", snd = "procSound", kinds = { spell = true } }
SF.SOUNDS[#SF.SOUNDS + 1] = { key = "ready", en = "readySoundEnabled", snd = "readySound",
    kinds = { totem = true, stance = true } }
SF.SOUNDS[#SF.SOUNDS + 1] = { key = "cooldown", en = "cooldownSoundEnabled", snd = "cooldownSound",
    kinds = { totem = true, stance = true, special = true } }

-- A glow lane on the icon, as the Recharging glow draws its own.
local function Glow(f, rec, g)
    local F = NS.Factory
    local pre = g.pre
    local sw = pre .. "Glow"
    local preview = f._adGlowLaneOnly == pre
    local want = g.kinds[rec.kind] == true
        and F.LookGlow(f, sw, R(rec, "states", sw) == true)
        and (preview or g.holds(f, rec) == true)
        and R(rec, "appearance", "forceHideIcon") ~= true
        and F.LaneAllowed(f, pre) and not F.GlowHidden(f)
    if want and not preview and R(rec, "states", pre .. "GlowCombatOnly") == true and not InCombatLockdown() then
        want = false
    end
    local on = f._adSfGlow
    if not want then
        if on and on[pre] then
            F.StopGlowLane(f, g.lane)
            on[pre] = nil
        end
        return
    end
    local function V(part, d)
        local v = R(rec, "states", pre .. part)
        if v == nil then return d end
        return v
    end
    local c = V("GlowColor", g.color)
    local inten = V("GlowIntensity", 1)
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * inten },
        speed = V("GlowSpeed", 0.25), lines = V("GlowLines", 8), thickness = V("GlowThickness", 2),
        particles = V("GlowParticles", 4), scale = V("GlowScale", 1),
        xo = V("GlowXOffset", 0), yo = V("GlowYOffset", 0),
        level = V("GlowLevel", 7) + F.Rise(rec), strata = V("GlowStrata", "inherit"),
        length = V("GlowLength", 0), mx = V("GlowMoveX", 0), my = V("GlowMoveY", 0),
    }
    local gtype = F.DrawnGlowStyle(V("GlowType", "button"), rec)
    local look = F.LaneLook(rec, "states", sw, gtype, p, inten)
    -- the icon's size and level are in the key: ants and flashes bake the size in
    local w, h = f:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w, h = 0, 0 end
    local lv = f:GetFrameLevel()
    if issecretvalue and issecretvalue(lv) then lv = -1 end
    local sig = table.concat({ gtype, p.color[1], p.color[2], p.color[3], p.color[4], p.speed, p.lines,
        p.thickness, p.particles, p.scale, p.xo, p.yo, p.level, p.strata, p.length, p.mx, p.my, lv or -1,
        string.format("%.2fx%.2f", w or 0, h or 0) }, ":") .. look
    on = on or {}
    f._adSfGlow = on
    if on[pre] == sig then return end
    if on[pre] then F.StopGlowLane(f, g.lane) end
    F.StartGlowLane(f, g.lane, gtype, p)
    on[pre] = sig
end

function SF.Glows(f, rec)
    if not (f and rec) or rec.kind == "aura" then return end
    for i = 1, #SF.GLOWS do Glow(f, rec, SF.GLOWS[i]) end
end

-- A sound on the state's start: an icon's real frame only (never a preview),
-- never its first read, and only if the state still holds a moment later (a
-- read that flickers for a frame plays nothing).
SF.SETTLE = 0.15
local function Play(f, rec, s)
    local id, gen = f._adRecId, f._adSfGen
    C_Timer.After(SF.SETTLE, function()
        -- the frame went back to the pool, or carries another icon now
        if f._adRecId ~= id or f._adSfGen ~= gen then return end
        if SF.HOLDS[s.key](f, rec) ~= true then return end
        local D = NS.DriverCooldown
        if D and D.PlayAlert then D.PlayAlert(rec, s.en, s.snd) end
    end)
end

function SF.Sounds(f, rec)
    if not (f and rec) or not f._adRecId or f._adPreview then return end
    local prev = f._adSfPrev
    for i = 1, #SF.SOUNDS do
        local s = SF.SOUNDS[i]
        if s.kinds[rec.kind] and R(rec, "alerts", s.en) == true then
            prev = prev or {}
            f._adSfPrev = prev
            local now = SF.HOLDS[s.key](f, rec)
            if now ~= nil then
                if now == true and prev[s.key] == false then Play(f, rec, s) end
                prev[s.key] = now
            end
        elseif prev then
            prev[s.key] = nil
        end
    end
end

function SF.Sync(f, rec)
    SF.Glows(f, rec)
    SF.Sounds(f, rec)
end

-- a frame back in the pool: its lanes off, its moments forgotten
function SF.Drop(f)
    local on = f and f._adSfGlow
    if on then
        for _, g in ipairs(SF.GLOWS) do
            if on[g.pre] then NS.Factory.StopGlowLane(f, g.lane) end
        end
        f._adSfGlow = nil
    end
    if f then
        f._adSfPrev = nil
        f._adSfGen = (f._adSfGen or 0) + 1
    end
end
