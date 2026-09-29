-- AD_Special_Soulburst: the Demon Hunter Devourer 2-piece tracker, an escalating chance per qualifying harvest (6.63% then +5.19%, capped at 39.49%) that resets on a proc; not a deck.
-- Registers "soulburst" on the Special hub; a Reap, Cull or Eradicate cast counts once it is judged to have consumed 4 or more Soul Fragments; the proc is the spell overlay glow of 473662 alone.
-- The fragment count is unreadable in combat, so the gate is the Void Metamorphosis builder's increase read 1 s after the cast; a restricted read leaves the harvest unknown, which counts.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local SOUL_FRAGMENTS = 1245577
local VOID_META = 1217607
-- the builder rises by one per fragment consumed and swaps carriers inside Void Metamorphosis
local VM_BUILDER = 1225789
local VM_BUILDER_META = 1227702
local SOULBURST_GLOW = 473662
-- Consume Soul fires once per harvest that took at least one soul, never on an empty one
local CONSUME_SOUL = 1223423
local CONSUME_WINDOW = 0.35
local PROC_DEDUP = 0.25
-- a path, not an id: 136194 is also a live spell id and would resolve to its art
local SB_ICON = "Interface\\Icons\\spell_shadow_shadesofdarkness"
local HARVESTS = {
    [1226019] = "Reap",
    [1245453] = "Cull",
    [1225826] = "Eradicate",
}
local THRESHOLD = 4
local CAP_AT = 8
local DECK_PROCS = 1
local BLP_BASE, BLP_STEP, BLP_CAP = 0.0663, 0.0519, 0.3949
local DEVOURER_SPEC_ID = 1480
-- fragments trickle in over 130 to 190 ms after the cast, and a 2-soul Reap
-- has ticked at 233 ms; a back-to-back cast drains the pending one first
local RESOLVE_DELAY = 1.0
local SET_ITEMS = {
    [271540] = true,  -- chest
    [271538] = true,  -- hands
    [271537] = true,  -- head
    [271536] = true,  -- legs
    [271535] = true,  -- shoulders
}
local SET_SLOTS = { 1, 3, 5, 7, 10 }

local sbGated = 0
local sbRaw = 0
local sbTotalProcs = 0
local sbLastFrag = nil
local sbFragStatus = "unknown"
local sbEnabled = false
local sbPending = nil
local sbLastConsumeSoul = 0
local sbHarvestSeq = 0
local sbLastProcAt = 0
local sbProcPending = nil
local eventsOn = false
local started = false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- an absent aura is zero fragments, a normal reading after a full drain
local function ReadFragments()
    local vm = C_UnitAuras.GetPlayerAuraBySpellID(VOID_META)
    local inVoidMeta = (vm ~= nil)
    local a = C_UnitAuras.GetPlayerAuraBySpellID(SOUL_FRAGMENTS)
    if a == nil then return 0, "noaura", inVoidMeta end
    if IsSecret(a) then return nil, "SECRET_STRUCT", inVoidMeta end
    local apps = a.applications
    if apps == nil then return nil, "noapps", inVoidMeta end
    if IsSecret(apps) then return nil, "SECRET_APPS", inVoidMeta end
    return apps, "ok", inVoidMeta
end

-- returns count or nil, a status word, and the carrier read
local function ReadMeta()
    local inVM = C_UnitAuras.GetPlayerAuraBySpellID(VOID_META) ~= nil
    local id = inVM and VM_BUILDER_META or VM_BUILDER
    local a = C_UnitAuras.GetPlayerAuraBySpellID(id)
    if a == nil then return 0, inVM and "empty(vm)" or "empty", id end
    if IsSecret(a) then return nil, "SECRET_STRUCT", id end
    local apps = a.applications
    if apps == nil then return nil, "noapps", id end
    if IsSecret(apps) then return nil, "SECRET_APPS", id end
    return apps, "ok", id
end

-- the active carrier's own ceiling: inside Void Metamorphosis it is lower
local function ReadMetaMax()
    local f = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
    if not f then return nil end
    local inVM = C_UnitAuras.GetPlayerAuraBySpellID(VOID_META) ~= nil
    local v = f(inVM and VM_BUILDER_META or VM_BUILDER)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local function ChanceAt(k)
    if k < 1 then return 0 end
    local c = BLP_BASE + BLP_STEP * (k - 1)
    if c > BLP_CAP then c = BLP_CAP end
    return c
end

local ApplyProc

-- The attempt is counted before a waiting proc resets the counter, since
-- the proc lands while the fragments are still arriving.
local function ResolvePending()
    if not sbPending then return end
    local p = sbPending
    sbPending = nil
    local after, status = ReadFragments()
    local before = p.before
    local delta
    if type(before) == "number" and type(after) == "number" then
        delta = before - after
        if delta < 0 then delta = 0 end
    end
    local metaAfter, metaAfterStatus, metaAfterCarrier = ReadMeta()
    local metaDelta
    -- only two readings of the same carrier can be differenced
    if p.metaCarrier == metaAfterCarrier
       and type(p.meta) == "number" and type(metaAfter) == "number" then
        metaDelta = metaAfter - p.meta
    elseif p.metaCarrier ~= metaAfterCarrier then
        metaAfterStatus = "carrier-swapped"
    end
    local qualifies
    if metaDelta ~= nil and metaDelta >= 0 then
        -- an increase that stops at the cap is a floor, not a measurement
        local atCap = (p.metaMax ~= nil) and (p.meta + THRESHOLD > p.metaMax)
        if metaDelta >= THRESHOLD then
            qualifies = true
        elseif not atCap then
            qualifies = false
        end
    elseif metaDelta ~= nil and metaDelta < 0 then
        qualifies = nil
    elseif delta ~= nil and p.beforeStatus == "ok" and status == "ok" then
        qualifies = (delta >= THRESHOLD)
    elseif type(before) == "number" and p.beforeStatus == "ok" then
        -- fewer than the threshold held means fewer consumed; the converse is unknown
        if before < THRESHOLD then qualifies = false end
    end
    -- at the cap the delta reads 0 either way; no Consume Soul settles the zero case
    local sawConsume = (p.castAt ~= nil) and (sbLastConsumeSoul >= p.castAt - CONSUME_WINDOW)
    if qualifies == nil and not sawConsume then
        qualifies = false
    end
    sbRaw = sbRaw + 1
    if qualifies ~= false then sbGated = sbGated + 1 end
    sbLastFrag, sbFragStatus = after, status
    SP.Update("soulburst")
    if sbProcPending then
        local src = sbProcPending
        sbProcPending = nil
        ApplyProc(src)
    end
end

local function OnHarvestCast(name)
    if not sbEnabled then return end
    if sbPending then ResolvePending() end
    local before, beforeStatus, vm = ReadFragments()
    local meta, metaStatus, metaCarrier = ReadMeta()
    sbPending = {
        name = name, before = before, beforeStatus = beforeStatus, vm = vm,
        meta = meta, metaStatus = metaStatus, metaCarrier = metaCarrier,
        metaMax = ReadMetaMax(), castAt = GetTime(),
    }
    sbHarvestSeq = sbHarvestSeq + 1
    C_Timer.After(RESOLVE_DELAY, ResolvePending)
    SP.Update("soulburst")
end

ApplyProc = function(source)
    sbTotalProcs = sbTotalProcs + 1
    sbGated, sbRaw = 0, 0
    SP.Proc("soulburst")
    SP.Update("soulburst")
end

-- a proc that lands while a harvest is measuring waits for it
local function CreditProc(source)
    if not sbEnabled then return end
    local now = GetTime()
    if now - sbLastProcAt < PROC_DEDUP then return end
    sbLastProcAt = now
    if sbPending then
        sbProcPending = source
        return
    end
    ApplyProc(source)
end

local function GetDeckPos()
    return (sbGated > CAP_AT) and CAP_AT or sbGated
end

-- two honest states: climbing, and pinned at the cap
local function GetProcs()
    return (sbGated >= CAP_AT) and DECK_PROCS or 0
end

local function Read()
    local pos = GetDeckPos()
    local procs = GetProcs()
    local chance = ChanceAt(sbGated + 1) * 100
    return {
        pos = pos, size = CAP_AT, left = CAP_AT - pos, drawn = pos,
        procs = procs, max = DECK_PROCS, procsLeft = DECK_PROCS - procs,
        count = sbGated, raw = sbRaw, chance = chance, viol = 0, totalProcs = sbTotalProcs,
        pending = sbPending ~= nil,
        text = { pos = string.format("%.0f%%", chance), procs = tostring(sbGated) },
    }
end

local function Reset()
    sbGated, sbRaw = 0, 0
    sbTotalProcs = 0
    sbPending = nil
    sbProcPending = nil
    sbLastProcAt = 0
    SP.Update("soulburst")
end

local function IsDevourer()
    local _, class = UnitClass("player")
    if class ~= "DEMONHUNTER" then return false end
    return SP.SpecID() == DEVOURER_SPEC_ID
end

-- no API counts equipped set pieces: the set's item ids, stable across difficulties
local function SetPieceCount()
    local n = 0
    for i = 1, #SET_SLOTS do
        local itemID = GetInventoryItemID("player", SET_SLOTS[i])
        if itemID and SET_ITEMS[itemID] then n = n + 1 end
    end
    return n
end

local function Has2pc() return SetPieceCount() >= 2 end

local function ShowGate(drv)
    if not IsDevourer() then return false end
    if drv and drv.requireSet == false then return true end
    return Has2pc()
end

local function OnSUC(a1)
    if not sbEnabled then return end
    if IsSecret(a1) then return end
    if a1 == CONSUME_SOUL then sbLastConsumeSoul = GetTime() end
end

local function OnGlow(a1)
    if not sbEnabled then return end
    if IsSecret(a1) then return end
    if a1 == SOULBURST_GLOW then CreditProc("glow") end
end

local function OnCast(unit, _, spellID)
    if not sbEnabled then return end
    if SP.Plain(unit) ~= "player" then return end
    if IsSecret(spellID) then return end
    local name = HARVESTS[spellID]
    if name then OnHarvestCast(name) end
end

local function SetEvents(on)
    if on == eventsOn then return end
    eventsOn = on
    if on then
        SP.Listen("UNIT_SPELLCAST_SUCCEEDED", "soulburst", OnCast)
        SP.Listen("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "soulburst", OnGlow)
        SP.Listen("SPELL_UPDATE_COOLDOWN", "soulburst", OnSUC)
    else
        SP.Unlisten("UNIT_SPELLCAST_SUCCEEDED", "soulburst")
        SP.Unlisten("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "soulburst")
        SP.Unlisten("SPELL_UPDATE_COOLDOWN", "soulburst")
    end
end

-- the spec drives detection; the set only gates the display
local function Sync()
    local specOK = started and IsDevourer()
    sbEnabled = specOK
    SetEvents(specOK)
    if not specOK then
        sbGated, sbRaw = 0, 0
        sbPending = nil
        sbProcPending = nil
    end
end

local function Start()
    started = true
    Sync()
end

local function Stop()
    started = false
    sbEnabled = false
    SetEvents(false)
end

local function Save()
    if sbGated == 0 and sbRaw == 0 and sbTotalProcs == 0 then return nil end
    return { gated = sbGated, raw = sbRaw, procs = sbTotalProcs, lastProc = sbLastProcAt, lastConsume = sbLastConsumeSoul }
end

local function Load(t)
    if type(t) ~= "table" then return end
    sbGated = tonumber(t.gated) or 0
    sbRaw = tonumber(t.raw) or 0
    sbTotalProcs = tonumber(t.procs) or 0
    sbLastProcAt = tonumber(t.lastProc) or 0
    sbLastConsumeSoul = tonumber(t.lastConsume) or 0
end

local function Status()
    if not sbEnabled then return "needs Devourer" end
    local n = SetPieceCount()
    return string.format("tracking, %d/5 pieces equipped", n)
end

SP.Register({
    id = "soulburst", name = "Soulburst", class = "DEMONHUNTER", specs = { 1480 },
    icon = SB_ICON, size = CAP_AT, procs = nil, cap = CAP_AT,
    isTimer = false, bar = true, sound = false, chanceSpend = false, chanceForecast = false, viol = false,
    words = {
        pos = "Proc chance", procs = "Harvest counter",
        emptyColor = "Chance still climbing", fullColor = "Max chance reached",
    },
    tokens = { "chance", "count", "pos", "size" },
    labels = { "{count}" },
    stack = "{chance}",
    driverFlags = { "requireSet" },
    -- the set's item ids, for the display's set-pieces load condition
    setItems = SET_ITEMS, setPieces = 2,
    Gate = IsDevourer, ShowGate = ShowGate, Pieces = SetPieceCount, Has2pc = Has2pc,
    Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status, ChanceAt = ChanceAt,
    Fragments = function() return sbLastFrag, sbFragStatus end,
})
