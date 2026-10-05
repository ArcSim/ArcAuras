-- AD_Special_Tempest: the Enhancement Tempest tracker, a 100-card deck of Maelstrom Weapon stacks holding 2 procs; a proc is SPELL_UPDATE_COOLDOWN 454015 in the same client frame as the consume.
-- Registers "tempest" on the Special hub; the shared MSW engine's consumes draw; one listener serves every consume's window, registered only while a window is open.
-- The 5 ms window is a same-frame test, since GetTime() is the frame's start: it is the only thing that separates a deck proc from an Awakening Storms gain. Never widen it.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local TEMPEST_BUFF = 454015
local TEMPEST_CAST = 452201
local DECK_SIZE = 100
local DECK_PROCS = 2
local TEMPEST_NODE_ID = 94892

local tempTotalStacks = 0
local tempDeckNumber = 1
local tempDeckProcs = 0
local tempPrevDeckProcs = 0
local tempGainCount = 0
local tempMSWConsumed = 0
local tempViolations = 0
local tempEnabled = false
-- talented once this session: ProcTracker's deck registration, sticky from then on
local registered = false
local snap = { deckNumber = 1, prevProcs = 0, totalStacks = 0, procCredited = false }
local openWatches = {}
local MSW = nil

local function AdvanceDeck(n)
    local before = tempTotalStacks
    tempTotalStacks = tempTotalStacks + n
    local dBefore = math.floor(before / DECK_SIZE)
    local dAfter = math.floor(tempTotalStacks / DECK_SIZE)
    if dAfter > dBefore then
        tempPrevDeckProcs = tempDeckProcs
        tempDeckProcs = 0
        tempDeckNumber = dAfter + 1
        -- judged after the proc window closes, so a proc on the crossing
        -- spend is back-credited first; only an undercount is a violation
        C_Timer.After(0.01, function()
            if tempPrevDeckProcs < DECK_PROCS then tempViolations = tempViolations + 1 end
        end)
    end
end

local function CreditProc()
    if snap.procCredited then return end
    snap.procCredited = true
    tempGainCount = tempGainCount + 1
    if snap.deckNumber == tempDeckNumber then
        tempDeckProcs = tempDeckProcs + 1
    elseif tempPrevDeckProcs < DECK_PROCS then
        tempPrevDeckProcs = tempPrevDeckProcs + 1
        if tempPrevDeckProcs == DECK_PROCS and tempViolations > 0 then
            tempViolations = tempViolations - 1
        end
    else
        tempDeckProcs = tempDeckProcs + 1
    end
    SP.Proc("tempest")
    SP.Update("tempest")
end

local function OnWatchSUC(sid)
    if SP.SpellID(sid) ~= TEMPEST_BUFF then return end
    for i = 1, #openWatches do
        local w = openWatches[i]
        local age = (GetTime() - w.consumeTime) * 1000
        if not w.firedAt and age <= 5 then w.firedAt = GetTime() end
    end
end

local function OpenWatch(w)
    openWatches[#openWatches + 1] = w
    if #openWatches == 1 then SP.Listen("SPELL_UPDATE_COOLDOWN", "tempest_watch", OnWatchSUC) end
end

local function CloseWatch(w)
    for i = #openWatches, 1, -1 do
        if openWatches[i] == w then table.remove(openWatches, i) break end
    end
    if #openWatches == 0 then SP.Unlisten("SPELL_UPDATE_COOLDOWN", "tempest_watch") end
end

local function OnMSWConsumed(stacksSpent, spenderID, ascActive)
    if not tempEnabled then return end
    snap.deckNumber = tempDeckNumber
    snap.prevProcs = tempPrevDeckProcs
    snap.totalStacks = tempTotalStacks
    snap.procCredited = false
    tempMSWConsumed = tempMSWConsumed + stacksSpent
    AdvanceDeck(stacksSpent)
    local w = { consumeTime = GetTime() }
    OpenWatch(w)
    C_Timer.After(0.005, function()
        CloseWatch(w)
        if not tempEnabled then return end
        if w.firedAt then CreditProc() else SP.Update("tempest") end
    end)
end

local function Read(drv)
    local pos = tempTotalStacks % DECK_SIZE
    local spend = (drv and tonumber(drv.chanceSpend)) or 10
    return {
        pos = pos, size = DECK_SIZE, left = DECK_SIZE - pos, drawn = pos,
        procs = tempDeckProcs, max = DECK_PROCS, procsLeft = DECK_PROCS - tempDeckProcs,
        chance = SP.DeckChance(DECK_SIZE, DECK_PROCS, pos, tempDeckProcs, spend),
        viol = tempViolations, deck = tempDeckNumber, spent = tempMSWConsumed,
    }
end

local function Reset()
    tempTotalStacks, tempDeckNumber = 0, 1
    tempDeckProcs, tempPrevDeckProcs = 0, 0
    tempGainCount, tempViolations, tempMSWConsumed = 0, 0, 0
    snap.deckNumber, snap.prevProcs = 1, 0
    snap.totalStacks, snap.procCredited = 0, false
    local M = NS.SpecialMSW
    if M then M.InitFromLive() end
    SP.Update("tempest")
end

local function IsTempestTalented()
    if SP.SpecID() ~= 263 then return false end
    local ni = SP.NodeInfo(TEMPEST_NODE_ID)
    if not ni or (ni.activeRank or 0) == 0 then return false end
    -- a hero node counts only inside the active hero tree
    if ni.subTreeID then return ni.subTreeActive == true end
    return true
end

-- ProcTracker's registration: once talented, the deck draws and refreshes its
-- readout one and three seconds on
local function TryRegister()
    if registered or not IsTempestTalented() then return end
    registered = true
    tempEnabled = true
    MSW.Subscribe("OnConsumed", OnMSWConsumed)
    C_Timer.After(1, function() SP.Update("tempest") end)
    C_Timer.After(3, function() SP.Update("tempest") end)
    MSW.InitFromLive()
end

-- the talent API is not ready on a zone change: leave the state alone then
local function ApplyTalentVisibility()
    if not registered then return end
    if not SP.ConfigID() then return end
    local track = IsTempestTalented() and SP.Wanted("tempest")
    if not track then
        tempEnabled = false
        MSW.Unsubscribe("OnConsumed", OnMSWConsumed)
    else
        tempEnabled = true
        MSW.Subscribe("OnConsumed", OnMSWConsumed)
        MSW.InitFromLive()
    end
end

local function Sync()
    MSW = NS.SpecialMSW
    TryRegister()
    ApplyTalentVisibility()
end

local function Start()
    MSW = NS.SpecialMSW
end

-- nothing reads the deck any more: it stops drawing, its open windows run out
local function Stop()
    tempEnabled = false
    if MSW then MSW.Unsubscribe("OnConsumed", OnMSWConsumed) end
end

local function Save()
    if tempTotalStacks == 0 and tempDeckProcs == 0 and tempViolations == 0 and tempGainCount == 0 then return nil end
    return { total = tempTotalStacks, deck = tempDeckNumber, procs = tempDeckProcs, prev = tempPrevDeckProcs,
        gains = tempGainCount, spent = tempMSWConsumed, viol = tempViolations }
end

local function Load(t)
    if type(t) ~= "table" then return end
    tempTotalStacks = tonumber(t.total) or 0
    tempDeckNumber = tonumber(t.deck) or 1
    tempDeckProcs = tonumber(t.procs) or 0
    tempPrevDeckProcs = tonumber(t.prev) or 0
    tempGainCount = tonumber(t.gains) or 0
    tempMSWConsumed = tonumber(t.spent) or 0
    tempViolations = tonumber(t.viol) or 0
    snap.deckNumber, snap.prevProcs, snap.totalStacks = tempDeckNumber, tempPrevDeckProcs, tempTotalStacks
end

local function Status()
    return tempEnabled and "tracking" or "not talented"
end

SP.Register({
    id = "tempest", name = "Tempest", class = "SHAMAN", specs = { 263 },
    talentGate = { node = TEMPEST_NODE_ID },
    icon = TEMPEST_CAST, size = DECK_SIZE, procs = DECK_PROCS,
    isTimer = false, bar = true, sound = false, chanceSpend = true, chanceForecast = false, viol = true,
    words = { pos = "Deck position", procs = "Proc count" },
    tokens = SP.DECK_TOKENS,
    labels = { "{procsLeft}", "{chance}", "{viol}" },
    stack = "{left}",
    -- ProcTracker's talent frame for this deck, plus its login pass
    syncEvents = { TRAIT_CONFIG_UPDATED = true, PLAYER_TALENT_UPDATE = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
        ACTIVE_TALENT_GROUP_CHANGED = true, PLAYER_SPECIALIZATION_CHANGED = true, PLAYER_LOGIN = true },
    Gate = IsTempestTalented, Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status,
})
