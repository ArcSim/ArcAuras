-- AD_Special_NaturesGuardian: the Nature's Guardian tracker, the talent's internal cooldown as a timer: 45 s from the heal's SPELL_UPDATE_COOLDOWN, 10 s less on Elemental and 15 s less on Restoration with Natural Harmony.
-- Registers "ng" on the Special hub; Read() carries the running cooldown's expiry and duration for a display to push into its own Cooldown with plain numbers.
-- The game never publishes this cooldown: the trigger is the only thing taken from it, and the clock is GetTime(), so nothing here is secret anywhere.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

-- the heal effect is the id whose cooldown event fires; the passive talent never does
local NG_EFFECT = 31616
local NG_ICON = 136060
local NG_NODE_ID = 103613
local NG_ENTRY_ID = 127890
local NH_NODE_ID = 94858
local NH_ENTRY_ID = 117455
local NH_FALLBACK = 10
local NG_ICD_BASE = 45
-- the client sends a burst of cooldown updates on load and on every zone change
local NG_SUPPRESS_SECONDS = 2
local NH_BY_SPEC = {
    [262] = 10,
    [264] = 15,
}

local ngEnabled = false
local ngOnCD = false
local ngExpiry = 0
local ngDuration = NG_ICD_BASE
local ngSuppressUntil = 0

local function HasNGTalent()
    local node = SP.NodeInfo(NG_NODE_ID)
    if not node then return false end
    if node.activeEntry and node.activeEntry.entryID == NG_ENTRY_ID then
        return (node.activeEntry.rank or 0) > 0
    end
    return false
end

local function HasNaturalHarmony()
    local node = SP.NodeInfo(NH_NODE_ID)
    if not node then return false end
    if node.activeEntry and node.activeEntry.entryID == NH_ENTRY_ID then
        return (node.activeEntry.rank or 0) > 0
    end
    return false
end

local function HarmonyReduction()
    local specID = SP.SpecID()
    return (specID and NH_BY_SPEC[specID]) or NH_FALLBACK
end

-- the length a cooldown starting this instant would have
local function CurrentICD()
    if not HasNaturalHarmony() then return NG_ICD_BASE end
    return NG_ICD_BASE - HarmonyReduction()
end

-- a bulk cooldown broadcast carries no spell id at all
local function SafeSpellID(v)
    local n = SP.SpellID(v)
    return (n and n > 0) and n or nil
end

local function Refresh()
    if not ngEnabled then return end
    ngOnCD = (ngExpiry - GetTime()) > 0
    SP.Update("ng")
end

local function ArmFlip(delay)
    C_Timer.After(delay, function()
        if (ngExpiry - GetTime()) <= 0 then Refresh() end
    end)
end

local function StartICD()
    ngDuration = CurrentICD()
    ngExpiry = GetTime() + ngDuration
    Refresh()
    ArmFlip(ngDuration + 0.1)
end

local function OnSUC(arg1, arg2)
    if not ngEnabled then return end
    if GetTime() < ngSuppressUntil then return end
    local id = SafeSpellID(arg1) or SafeSpellID(arg2)
    if id ~= NG_EFFECT then return end
    -- a refire restarts the clock rather than extending it
    StartICD()
end

local function OnWorld()
    ngSuppressUntil = GetTime() + NG_SUPPRESS_SECONDS
    Refresh()
end

-- a running sweep keeps the duration it started with: a talent swap must
-- not rescale it
local function Read()
    local remaining = ngExpiry - GetTime()
    if remaining < 0 then remaining = 0 end
    return {
        active = ngOnCD, remaining = remaining, duration = ngDuration, expiry = ngExpiry,
        icd = CurrentICD(), pos = 0, size = 1, procs = 0, max = 1, left = 1, procsLeft = 1,
    }
end

local function Reset()
    ngOnCD = false
    ngExpiry = 0
    ngDuration = CurrentICD()
    Refresh()
end

-- talent and world changes re-read the clock, after the hub's own world redraw
local TALENT_EVENTS = { "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD" }

local function Start()
    ngEnabled = true
    SP.Listen("SPELL_UPDATE_COOLDOWN", "ng", OnSUC)
    SP.Listen("PLAYER_ENTERING_WORLD", "ng", OnWorld)
    for _, e in ipairs(TALENT_EVENTS) do SP.Listen(e, "ng_talent", Refresh) end
    Refresh()
end

local function Stop()
    ngEnabled = false
    SP.Unlisten("SPELL_UPDATE_COOLDOWN", "ng")
    SP.Unlisten("PLAYER_ENTERING_WORLD", "ng")
    for _, e in ipairs(TALENT_EVENTS) do SP.Unlisten(e, "ng_talent") end
end

local function Save()
    if (ngExpiry - GetTime()) <= 0 then return nil end
    return { expiry = ngExpiry, duration = ngDuration }
end

-- GetTime() runs on across a /reload, so a saved expiry still means the same moment
local function Load(t)
    if type(t) ~= "table" then return end
    ngExpiry = tonumber(t.expiry) or 0
    ngDuration = tonumber(t.duration) or NG_ICD_BASE
    local remaining = ngExpiry - GetTime()
    if remaining > 0 then ArmFlip(remaining + 0.1) end
end

local function Status()
    if not ngEnabled then return "idle" end
    if not HasNGTalent() then return "talent not taken" end
    return ngOnCD and "on cooldown" or "ready"
end

SP.Register({
    id = "ng", name = "Nature's Guardian", class = "SHAMAN", specs = nil,
    icon = NG_ICON, size = nil, procs = nil,
    isTimer = true, bar = false, sound = false, chanceSpend = false, chanceForecast = false, viol = false,
    iconDefaults = { strata = "MEDIUM", cooldownDesaturate = true, showEdge = true },
    tokens = {},
    labels = {},
    stack = "",
    talentGate = { node = NG_NODE_ID, entry = NG_ENTRY_ID },
    -- the timer's recipe, for the Custom Icon the ProcTracker import builds
    icd = { spell = NG_EFFECT, base = NG_ICD_BASE,
        harmony = { node = NH_NODE_ID, entry = NH_ENTRY_ID, bySpec = NH_BY_SPEC, fallback = NH_FALLBACK } },
    Gate = HasNGTalent, Talented = HasNGTalent, Read = Read, Start = Start, Stop = Stop,
    Reset = Reset, Save = Save, Load = Load, Status = Status,
    CurrentICD = CurrentICD, IsOnCooldown = function() return ngOnCD end,
})
