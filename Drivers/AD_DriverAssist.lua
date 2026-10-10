-- AD_DriverAssist: the game's Assisted Combat suggestion on spell icons (retail): the spell its
-- Assisted Highlight picks next lights every icon of that spell with its "While suggested" glow.
-- It follows the game's own change event, so nothing polls; it needs the Assisted Highlight on
-- in the game's options. The suggestion is a plain spell ID, in combat too, and the event runs
-- each listener apart, so nothing of ours reaches the game's own listeners.
-- Factory.ApplyStyle hands every styled icon to Sync, Factory.Release to Drop.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local AS = {}
NS.DriverAssist = AS

AS.LANE = "ads"
AS.KEY = "adassist"
AS.EVENTS = { "AssistedCombatManager.OnAssistedHighlightSpellChange", "AssistedCombatManager.OnSetUseAssistedHighlight" }
AS.frames = {}      -- [icon frame] = rec, icons with the glow switched on
AS.armed = false
AS.inCombat = false

function AS.Available()
    return NS.IsForever ~= true and C_AssistedCombat ~= nil and AssistedCombatManager ~= nil and EventRegistry ~= nil
end

-- The suggestion as the action bars show it, read off the game's manager (a read never taints
-- it): nil while its Assisted Highlight is off.
function AS.Spell()
    local M = AssistedCombatManager
    if not (M and M.useAssistedHighlight) then return nil end
    local sid = M.lastNextCastSpellID
    if issecretvalue and issecretvalue(sid) then return nil end
    return type(sid) == "number" and sid or nil
end

function AS.R(rec, k)
    return Store.Resolve(rec, "states", k)
end

function AS.Wanted(rec)
    return AS.Available() and rec ~= nil and rec.kind == "spell" and AS.R(rec, "assistGlow") == true
end

-- The icon's spell, the one it shows on an icon with several.
function AS.SpellOf(rec)
    if not (rec and type(rec.driver) == "table") then return nil end
    return tonumber(Store.ShownSpell and Store.ShownSpell(rec.driver) or rec.driver.spellID)
end

function AS.On(rec)
    local want = AS.Spell()
    if not want then return false end
    if AS.R(rec, "assistGlowCombatOnly") == true and not AS.inCombat then return false end
    local mine = AS.SpellOf(rec)
    return mine ~= nil and (mine == want or (Store.SpellMatch ~= nil and Store.SpellMatch(mine, want) == true))
end

function AS.Stop(f)
    if not f._adAssistSig then return end
    NS.Factory.StopGlowLane(f, AS.LANE)
    f._adAssistSig = nil
end

-- The options preview (f._adGlowLaneOnly) shows the glow while it picks this lane.
function AS.Apply(f, rec)
    local only = f._adGlowLaneOnly
    local preview = only == "assist"
    local want = AS.Wanted(rec) and (only == nil or preview)
        and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
        and (preview or AS.On(rec))
    if not want then
        AS.Stop(f)
        return
    end
    local R = function(k) return AS.R(rec, k) end
    local c = R("assistGlowColor") or { 1, 1, 1, 1 }
    local inten = R("assistGlowIntensity") or 1
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * inten },
        speed = R("assistGlowSpeed") or 0.25,
        lines = R("assistGlowLines") or 8,
        thickness = R("assistGlowThickness") or 2,
        particles = R("assistGlowParticles") or 4,
        scale = R("assistGlowScale") or 1,
        xo = R("assistGlowXOffset") or 0,
        yo = R("assistGlowYOffset") or 0,
        level = (R("assistGlowLevel") or 7) + NS.Factory.Rise(rec),
        strata = R("assistGlowStrata") or "inherit",
        length = R("assistGlowLength") or 0,
        mx = R("assistGlowMoveX") or 0,
        my = R("assistGlowMoveY") or 0,
    }
    local gtype = NS.Factory.DrawnGlowStyle(R("assistGlowType") or "ants", rec)
    local look = NS.Factory.LaneLook(rec, "states", "assistGlow", gtype, p, inten)
    -- the icon's size and level are in the key: the ants and flashes bake the size in
    local w, h = f:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w, h = 0, 0 end
    local lv = f:GetFrameLevel()
    if issecretvalue and issecretvalue(lv) then lv = -1 end
    local sig = table.concat({ gtype, p.color[1], p.color[2], p.color[3], p.color[4],
        p.speed, p.lines, p.thickness, p.particles, p.scale, p.xo, p.yo, p.level,
        p.strata, p.length, p.mx, p.my, lv or -1,
        string.format("%.2fx%.2f", w or 0, h or 0) }, ":") .. look
    if f._adAssistSig ~= sig then
        NS.Factory.StopGlowLane(f, AS.LANE)
        NS.Factory.StartGlowLane(f, AS.LANE, gtype, p)
        f._adAssistSig = sig
    end
end

function AS.ApplyAll()
    for f, rec in pairs(AS.frames) do AS.Apply(f, rec) end
end

-- The game's suggestion changed, or its Assisted Highlight was switched: every lit icon follows.
function AS.OnChange()
    AS.ApplyAll()
end

function AS.OnCombat(event)
    AS.inCombat = event == "PLAYER_REGEN_DISABLED"
    AS.ApplyAll()
end

-- The game's events and the combat pair, only while an icon has the glow on.
function AS.Arm()
    local want = next(AS.frames) ~= nil and AS.Available()
    if want == AS.armed then return end
    AS.armed = want
    if want then
        for _, e in ipairs(AS.EVENTS) do EventRegistry:RegisterCallback(e, AS.OnChange, AS) end
        AS.inCombat = InCombatLockdown() == true
        Events.On("PLAYER_REGEN_DISABLED", AS.KEY, AS.OnCombat)
        Events.On("PLAYER_REGEN_ENABLED", AS.KEY, AS.OnCombat)
    else
        for _, e in ipairs(AS.EVENTS) do EventRegistry:UnregisterCallback(e, AS) end
        Events.Off("PLAYER_REGEN_DISABLED", AS.KEY)
        Events.Off("PLAYER_REGEN_ENABLED", AS.KEY)
    end
end

function AS.Sync(f, rec)
    if AS.Wanted(rec) then
        AS.frames[f] = rec
    else
        AS.frames[f] = nil
    end
    AS.Arm()
    AS.Apply(f, rec)
end

function AS.Drop(f)
    AS.frames[f] = nil
    AS.Stop(f)
    AS.Arm()
end
