-- AD_Special_PowerInfusion: Power Infusion received, spell 10060 on the player: the game's own aura container draws it and C_UnitAuras.AddAuraSound plays the sound, since the buff is secret in combat and no Lua read can see it land.
-- Registers "pi" on the Special hub as the aura-icon convenience (every class); its detection is the engine's, so Read() only names the aura. PI.SyncSound keeps one engine sound registration: a first one is tried anywhere, a change waits for out of combat with auras plain.
-- The engine takes a sound file path or file ID, never a sound kit.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local PI_SPELL = 10060
local SETTLE_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END" }

local PI = {}
local want = nil          -- { fileName or fileID, channel, spellID } or nil
local soundIDs = {}
local soundSig = nil
local pendingSound = false
local settleArmed = false

local function AurasSecretNow()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end

local function CanChangeRegistrations()
    if InCombatLockdown() then return false end
    return not AurasSecretNow()
end

local function SoundSig(d)
    if not d then return "off" end
    return table.concat({ d.spellID, tostring(d.fileName or d.fileID), d.channel }, ":")
end

local function Available()
    return C_UnitAuras and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger and true or false
end

local RefreshEvents

-- A first registration may be tried anywhere: a refusal returns nil and
-- costs nothing. Changing one waits for a quiet moment, so a working sound
-- is never removed for a new one the game then refuses.
function PI.SyncSound()
    if not Available() then return end
    local d = want
    local sig = SoundSig(d)
    if sig == soundSig then
        pendingSound = false
        RefreshEvents()
        return
    end
    if #soundIDs > 0 and not CanChangeRegistrations() then
        pendingSound = true
        RefreshEvents()
        return
    end
    for i = 1, #soundIDs do C_UnitAuras.RemoveAuraSound(soundIDs[i]) end
    soundIDs = {}
    soundSig = nil
    pendingSound = false
    if d then
        local info = { unitToken = "player", spellID = d.spellID, outputChannel = d.channel } -- raw-id: the special's own fixed aura
        if d.fileName then info.soundFileName = d.fileName else info.soundFileID = d.fileID end
        local id = C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added, info)
        if id then
            soundIDs[1] = id
            soundSig = sig
        else
            pendingSound = true
        end
    else
        soundSig = sig
    end
    RefreshEvents()
end

-- what the sound should be: a file path or a file ID, a channel and the spell
function PI.SetSound(fileName, fileID, channel, spellID)
    if not (fileName or fileID) then
        want = nil
    else
        want = { fileName = fileName, fileID = fileID, channel = channel or "Master", spellID = spellID or PI_SPELL }
    end
    PI.SyncSound()
end

function PI.SoundState()
    return soundSig, pendingSound
end

local function OnSettle()
    if pendingSound then PI.SyncSound() end
    RefreshEvents()
end

-- the settle events listen only while a registration waits
RefreshEvents = function()
    local on = pendingSound
    if on == settleArmed then return end
    settleArmed = on
    for _, e in ipairs(SETTLE_EVENTS) do
        if on then SP.Listen(e, "pi_sound", OnSettle) else SP.Unlisten(e, "pi_sound") end
    end
end

local function Read()
    return { aura = PI_SPELL, pos = 0, size = 1, procs = 0, max = 1, left = 1, procsLeft = 1 }
end

SP.Register({
    id = "pi", name = "Power Infusion", class = nil, specs = nil,
    icon = PI_SPELL, size = nil, procs = nil,
    isTimer = false, isAura = true, bar = false, sound = false, engineSound = true,
    chanceSpend = false, chanceForecast = false, viol = false,
    aura = { spellID = PI_SPELL, auraType = "buff", unit = "player" },
    tokens = {},
    labels = {},
    stack = "",
    Read = Read, SyncSound = PI.SyncSound, SetSound = PI.SetSound, SoundState = PI.SoundState,
    Status = function() return soundSig and ("sound registered") or (pendingSound and "sound waiting for a quiet moment" or "no sound") end,
})
