-- AD_AuraSounds: an aura icon's sounds (the aura appears, gains a stack,
-- drops), and a Sound item's aura rules (Bars\AD_SoundItem.lua says which).
-- The game plays them itself (C_UnitAuras.AddAuraSound), so they
-- sound in combat with nothing read; this file only registers them: one per
-- tracked spell ID and moment, on the icon's unit, while the icon is attached.
-- The game takes sound files only (no built-in kit) and has no caster filter,
-- so any caster's copy of the aura counts. Registering waits for the end of
-- combat (in an instance the game blocks it) and of an encounter; removing
-- never waits. The game keeps registrations through a /reload, so ours all go
-- at logout.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local AS = {}
NS.AuraSounds = AS

AS.KEY = "adaurasnd"
AS.live = {}      -- [recId] = rec, the attached aura icons
AS.reg = {}       -- [recId] = { [slot] = { id = auraSoundID, sig = file and channel } }
AS.pending = false
AS.armed = false

-- one card per moment: the sound field and the game's trigger
AS.MOMENTS = {
    { field = "auraGainSound", trigger = "Added" },
    { field = "auraStackSound", trigger = "ApplicationsIncreased" },
    { field = "auraLostSound", trigger = "Removed" },
}
-- Enum.AddOnRestrictionType's values, for a client without the table
AS.RESTRICT = { Combat = 0, Encounter = 1, ChallengeMode = 2 }

local function Valid(e)
    local EU = C_EventUtils
    return not (EU and EU.IsEventValid) or EU.IsEventValid(e) == true
end

function AS.Available()
    local U = C_UnitAuras
    return U ~= nil and U.AddAuraSound ~= nil and U.RemoveAuraSound ~= nil
        and Enum ~= nil and Enum.UnitAuraSoundTrigger ~= nil
end

local function Active(name)
    local R = C_RestrictedActions
    if not (R and R.IsAddOnRestrictionActive) then return false end
    local E = Enum and Enum.AddOnRestrictionType
    local v = R.IsAddOnRestrictionActive((E and E[name]) or AS.RESTRICT[name])
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end

function AS.CanAdd()
    if InCombatLockdown() then return false end
    return not (Active("Encounter") or (Active("Combat") and Active("ChallengeMode")))
end

-- A stored sound's file: a path or a file ID; nil for none or a built-in kit.
function AS.File(name)
    local S = NS.Sounds
    if not (S and S.PathFor) then return nil end
    return S.PathFor(name)
end

-- What an icon wants registered: [slot] = { trigger, info, sig }, a slot
-- per moment, spell ID and unit, its sig the file and channel. Empty = nothing.
function AS.Wanted(rec)
    -- a Sound item's aura rules say it in their own shape (Bars\AD_SoundItem.lua)
    local SN = NS.SoundItems
    if SN and SN.Is(rec) then return SN.AuraWanted(rec) end
    local out = {}
    local D = NS.DriverAura
    if not (D and D.ShapeOf) then return out end
    local d = rec.driver or {}
    -- the ids the icon watches: your rank of each while it follows your rank
    local ids = Store.TrackedAuraIDs(d)
    local unit = D.ShapeOf(d)
    local ch = Store.Resolve(rec, "alerts", "soundChannel") or "Master"
    for _, m in ipairs(AS.MOMENTS) do
        if Store.Resolve(rec, "alerts", m.field .. "Enabled") == true then
            local file = AS.File(Store.Resolve(rec, "alerts", m.field))
            local trig = Enum.UnitAuraSoundTrigger[m.trigger]
            if file ~= nil and trig ~= nil then
                for _, id in ipairs(ids) do
                    local info = { unitToken = unit, spellID = id, outputChannel = ch }
                    if type(file) == "number" then info.soundFileID = file else info.soundFileName = file end
                    out[m.trigger .. ":" .. id .. ":" .. unit] = { trig, info, tostring(file) .. "|" .. ch }
                end
            end
        end
    end
    return out
end

local function Remove(slots, slot)
    C_UnitAuras.RemoveAuraSound(slots[slot].id)
    slots[slot] = nil
end

-- One icon: what it no longer wants goes now (removing is never refused);
-- what is new or changed registers when allowed, a changed one keeping its
-- old sound until then. A refusal waits for the retry.
function AS.SyncOne(id, want, can)
    local slots = AS.reg[id] or {}
    for slot in pairs(slots) do
        if not want[slot] then Remove(slots, slot) end
    end
    for slot, w in pairs(want) do
        local have = slots[slot]
        if not (have and have.sig == w[3]) then
            if can then
                if have then Remove(slots, slot) end
                local sid = C_UnitAuras.AddAuraSound(w[1], w[2])
                if sid ~= nil then slots[slot] = { id = sid, sig = w[3] } else AS.pending = true end
            else
                AS.pending = true
            end
        end
    end
    AS.reg[id] = next(slots) and slots or nil
end

function AS.Retry()
    if AS.pending then AS.Queue() end
end

-- The retry events, only while a registration waits.
function AS.Arm(on)
    if AS.armed == on then return end
    AS.armed = on
    if on then
        Events.On("PLAYER_REGEN_ENABLED", AS.KEY, AS.Retry)
        if Valid("ADDON_RESTRICTION_STATE_CHANGED") then
            Events.On("ADDON_RESTRICTION_STATE_CHANGED", AS.KEY, AS.Retry)
        end
    else
        Events.Off("PLAYER_REGEN_ENABLED", AS.KEY)
        Events.Off("ADDON_RESTRICTION_STATE_CHANGED", AS.KEY)
    end
end

-- Registrations follow the attached icons: a released one goes quiet at once.
function AS.Sync()
    if not AS.Available() then return end
    local can = AS.CanAdd()
    AS.pending = false
    for id in pairs(AS.reg) do
        if not AS.live[id] then AS.SyncOne(id, {}, can) end
    end
    for id, rec in pairs(AS.live) do AS.SyncOne(id, AS.Wanted(rec), can) end
    AS.Arm(AS.pending)
end

-- next frame: a rebuild detaches and re-attaches in one go, which changes nothing
function AS.Queue() Events.Coalesce("adaurasnd_sync", AS.Sync) end

-- the cooldown driver's attach and detach, for every aura icon; a Sound item's
-- runtime the same for its aura rules
function AS.Attach(rec)
    local SN = NS.SoundItems
    local takes = rec ~= nil and ((rec.type == "icon" and rec.kind == "aura") or (SN ~= nil and SN.Is(rec)))
    if not (takes and Store.Get(rec.id) == rec) then return end
    AS.live[rec.id] = rec
    AS.Queue()
end

function AS.Detach(id)
    if AS.live[id] == nil then return end
    AS.live[id] = nil
    AS.Queue()
end

Events.OnMessage("AD_DIRTY", AS.KEY, function()
    if next(AS.live) or next(AS.reg) then AS.Queue() end
end)

-- a reload fires this too, and would otherwise register every sound again
function AS.DropAll()
    for id in pairs(AS.reg) do AS.SyncOne(id, {}, false) end
end
Events.On("PLAYER_LOGOUT", AS.KEY, AS.DropAll)
