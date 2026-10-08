-- AD_SoundItem: the Sound item, a bar kind with no place on screen whose whole job is the alert.
-- Its rules run on the custom rule engine (NS.DriverCustom), which asks SN.MayCue before each cue; its aura rules are registered with the game through NS.AuraSounds.
-- Every trigger it offers reads plain in combat; a secret payload is unknown and fires nothing, and the game plays an aura's moment itself.
local ADDON, NS = ...

local SN = {}
NS.SoundItems = SN

SN.KEY = "adsound"
-- the same rule again this soon is one moment reported twice
SN.REFIRE = 0.08
-- the least time between two cues of one item
SN.GAP = 1.5
-- a rule's Quiet for (seconds) until it is given its own
SN.QUIET = 4
-- the game takes 0 to 5 seconds between plays of an aura's sound
SN.THROTTLE_MAX = 5
-- Play in: the switch that silences the item there
SN.SKIP = { solo = "skipSolo", party = "skipParty", raid = "skipRaid" }
-- an aura rule's moment as the game names it (Enum.UnitAuraSoundTrigger)
SN.AURA_MOMENT = { aura_gain = "Added", aura_stack = "ApplicationsIncreased", aura_lost = "Removed" }
SN.live = {}   -- [record id] = the record while it loads

function SN.Is(rec)
    return type(rec) == "table" and rec.type == "bar" and rec.barKind == "sound"
end

function SN.Rules(rec)
    local d = rec and rec.driver
    return (d and type(d.rules) == "table") and d.rules or {}
end

function SN.QuietOf(r)
    local q = tonumber(r and r.quiet)
    if not q then return SN.QUIET end
    return (q > 0) and q or 0
end

-- Where you are, by the conditions module's own group reads taken fresh (the
-- pass's memo can be older than the roster); nil without the module.
function SN.GroupNow()
    local C = NS.Conditions
    if not (C and C.ByKey) then return nil end
    local raid, party = C.ByKey("raid"), C.ByKey("party")
    if raid and raid.read() == true then return "raid" end
    if party and party.read() == true then return "party" end
    return "solo"
end

function SN.GroupOK(rec)
    local g = SN.GroupNow()
    if not g then return true end
    local d = rec.driver or {}
    return d[SN.SKIP[g]] ~= true
end

-- A cue may play: not the same rule again at once, in a group it plays in,
-- past the rule's Quiet for and past the item's least gap since its last cue.
function SN.MayCue(st, r, i)
    local now = GetTime()
    local c = st.cue
    if not c then
        c = { heard = {}, played = {} }
        st.cue = c
    end
    local heard = c.heard[i]
    if heard and now - heard < SN.REFIRE then return false end
    c.heard[i] = now
    if not SN.GroupOK(st.rec) then return false end
    local played = c.played[i]
    if played and now - played < SN.QuietOf(r) then return false end
    if c.last and now - c.last < SN.GAP then return false end
    c.played[i] = now
    c.last = now
    return true
end

-- Aura rules: the game plays them, for any caster's copy, in combat too. What
-- the item's own guards can still say is said when the sounds register: its
-- Play in gate, and each rule's Quiet for as the game's throttle.

function SN.HasAura(rec)
    for _, r in ipairs(SN.Rules(rec)) do
        if SN.AURA_MOMENT[r.when] then return true end
    end
    return false
end

-- The game's throttle for a rule, where the client knows the field (WoW Forever
-- and retail past 12.1.0); it takes five seconds at most.
function SN.Throttle(r)
    if NS.OldAuraEngine == true then return nil end
    return math.min(SN.QuietOf(r), SN.THROTTLE_MAX)
end

-- The game sound channel the item plays on (its own pick, Master by default).
SN.CHANNELS = { Master = true, SFX = true, Music = true, Ambience = true, Dialog = true }
function SN.Channel(rec)
    local ch = rec and rec.driver and rec.driver.channel
    return SN.CHANNELS[ch] and ch or "Master"
end

-- What the item wants registered, in NS.AuraSounds' slot shape:
-- [slot] = { trigger, info, signature }, one per moment, spell ID and unit.
function SN.AuraWanted(rec)
    local out = {}
    local AS = NS.AuraSounds
    local E = Enum and Enum.UnitAuraSoundTrigger
    if not (AS and AS.File and E) or not SN.GroupOK(rec) then return out end
    for i, r in ipairs(SN.Rules(rec)) do
        local moment = SN.AURA_MOMENT[r.when]
        local trig = moment and E[moment]
        local file = (trig ~= nil and r.act == "sound") and AS.File(r.sound) or nil
        local ch = SN.Channel(rec)
        if file ~= nil then
            local unit = r.unit or "player"
            local th = SN.Throttle(r)
            -- the typed auras and, on ranked realms, your rank of each (the
            -- aura icons' own rule)
            local ids = NS.Store.TrackedAuraIDs({ spellIDs = type(r.auraIDs) == "table" and r.auraIDs or nil })
            for _, id in ipairs(ids) do
                local info = { unitToken = unit, spellID = id, outputChannel = ch, throttleSeconds = th }
                if type(file) == "number" then info.soundFileID = file else info.soundFileName = file end
                out[moment .. ":" .. id .. ":" .. unit .. ":" .. i] = { trig, info, tostring(file) .. "|" .. ch .. "|" .. tostring(th) }
            end
        end
    end
    return out
end

-- A roster change moves the Play in gate of the aura rules, so their sounds
-- re-register (adding waits for the end of combat, removing never does).
function SN.SyncArm()
    local want = false
    for _, rec in pairs(SN.live) do
        if SN.HasAura(rec) then want = true end
    end
    if want == (SN.armed == true) then return end
    SN.armed = want
    if want then
        NS.Events.On("GROUP_ROSTER_UPDATE", SN.KEY, function()
            local AS = NS.AuraSounds
            if AS and AS.Queue then AS.Queue() end
        end)
    else
        NS.Events.Off("GROUP_ROSTER_UPDATE", SN.KEY)
    end
end

-- The bar kind: the bars runtime hands every (re)style of a Sound item here.
-- Its holder never shows (noHolder): there is nothing to see.

function SN.Ensure(e)
    local rec = e.rec
    e.stateHidden = true
    local loaded = NS.Store.IsLoaded(rec)
    SN.live[rec.id] = loaded and rec or nil
    local CU = NS.DriverCustom
    if CU and CU.AttachSound then CU.AttachSound(rec, e) end
    local AS = NS.AuraSounds
    if AS then
        if loaded then AS.Attach(rec) else AS.Detach(rec.id) end
    end
    SN.SyncArm()
end

function SN.Release(e)
    local id = e.rec and e.rec.id
    if id == nil then return end
    SN.live[id] = nil
    local CU = NS.DriverCustom
    if CU and CU.DetachSound then CU.DetachSound(id) end
    local AS = NS.AuraSounds
    if AS then AS.Detach(id) end
    SN.SyncArm()
end

function SN.Diag(e)
    local rec = e.rec
    local n, aura = 0, 0
    for _, r in ipairs(SN.Rules(rec)) do
        n = n + 1
        if SN.AURA_MOMENT[r.when] then aura = aura + 1 end
    end
    local CU = NS.DriverCustom
    return ("sound %d rules (%d aura), %s"):format(n, aura,
        (CU and CU.live[rec.id]) and "live" or "idle")
end

local Bars = NS.Bars
if Bars and Bars.RegisterKind then
    Bars.RegisterKind("sound", { Ensure = SN.Ensure, Release = SN.Release, Diag = SN.Diag, noHolder = true })
end
