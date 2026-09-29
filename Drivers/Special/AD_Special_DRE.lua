-- AD_Special_DRE: the Enhancement Deeply Rooted Elements tracker, a 333-card deck of Maelstrom Weapon stacks holding 2 procs; a proc is SPELL_UPDATE_COOLDOWN 114051 in the same client frame as the consume.
-- Registers "dre" on the Special hub; the shared MSW engine's consumes draw; no draw while the Ascendance flag is up, since the proc cannot land then.
-- One listener serves every consume's 5 ms window, registered only while a window is open.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local ASC_SPELL_ID = 114051
local DRE_ICON = 960689
local DECK_SIZE = 333
local DECK_PROCS = 2
-- the choice node shared with Ascendance: this deck needs the DRE entry
local DRE_NODE_ID = 92219
local DRE_ENTRY_ID = 101816

local dreTotalStacks = 0
local dreDeckNumber = 1
local dreDeckProcs = 0
local drePrevDeckProcs = 0
local dreGainCount = 0
local dreViolations = 0
local dreEnabled = false
local dreSnapTotal = 0
local dreProcThisConsume = false
local dreLastProcTime = 0
local openWatches = {}
local MSW = nil

local function AdvanceDeck(n)
    local before = dreTotalStacks
    dreTotalStacks = dreTotalStacks + n
    local db = math.floor(before / DECK_SIZE)
    local da = math.floor(dreTotalStacks / DECK_SIZE)
    if da > db then
        drePrevDeckProcs = dreDeckProcs
        dreDeckProcs = 0
        dreDeckNumber = da + 1
        if drePrevDeckProcs ~= DECK_PROCS then dreViolations = dreViolations + 1 end
    end
end

local function CreditProc()
    local now = GetTime()
    if now == dreLastProcTime then return end
    if dreProcThisConsume then return end
    dreProcThisConsume = true
    dreLastProcTime = now
    dreGainCount = dreGainCount + 1
    local snapDeck = math.floor(dreSnapTotal / DECK_SIZE)
    local currDeck = math.floor(dreTotalStacks / DECK_SIZE)
    local rolledOver = currDeck > snapDeck
    if rolledOver and dreDeckNumber > 1 and drePrevDeckProcs < DECK_PROCS then
        drePrevDeckProcs = drePrevDeckProcs + 1
        if drePrevDeckProcs == DECK_PROCS and dreViolations > 0 then
            dreViolations = dreViolations - 1
        end
    else
        dreDeckProcs = dreDeckProcs + 1
    end
    SP.Proc("dre")
    SP.Update("dre")
end

local function OnWatchSUC(sid)
    local id = SP.SpellID(sid)
    if not id then return end
    for i = 1, #openWatches do
        local w = openWatches[i]
        local age = (GetTime() - w.consumeTime) * 1000
        if age <= 5 and id == ASC_SPELL_ID and not w.fired then
            w.fired = true
        end
    end
end

local function OpenWatch(w)
    openWatches[#openWatches + 1] = w
    if #openWatches == 1 then SP.Listen("SPELL_UPDATE_COOLDOWN", "dre_watch", OnWatchSUC) end
end

local function CloseWatch(w)
    for i = #openWatches, 1, -1 do
        if openWatches[i] == w then table.remove(openWatches, i) break end
    end
    if #openWatches == 0 then SP.Unlisten("SPELL_UPDATE_COOLDOWN", "dre_watch") end
end

local function OnMSWConsumed(stacksSpent, spenderID, ascActive)
    if not dreEnabled then return end
    if ascActive then return end
    dreSnapTotal = dreTotalStacks
    AdvanceDeck(stacksSpent)
    dreProcThisConsume = false
    local w = { consumeTime = GetTime(), fired = false }
    OpenWatch(w)
    C_Timer.After(0.005, function()
        CloseWatch(w)
        if not dreEnabled then return end
        if w.fired then CreditProc() else SP.Update("dre") end
    end)
end

local function Read(drv)
    local pos = dreTotalStacks % DECK_SIZE
    local spend = (drv and tonumber(drv.chanceSpend)) or 10
    return {
        pos = pos, size = DECK_SIZE, left = DECK_SIZE - pos, drawn = pos,
        procs = dreDeckProcs, max = DECK_PROCS, procsLeft = DECK_PROCS - dreDeckProcs,
        chance = SP.DeckChance(DECK_SIZE, DECK_PROCS, pos, dreDeckProcs, spend),
        viol = dreViolations, deck = dreDeckNumber,
    }
end

local function Reset()
    dreTotalStacks = 0
    dreDeckNumber = 1
    dreDeckProcs = 0
    drePrevDeckProcs = 0
    dreGainCount = 0
    dreViolations = 0
    dreSnapTotal = 0
    dreProcThisConsume = false
    dreLastProcTime = 0
    SP.Update("dre")
end

local function IsDRETalented()
    local ni = SP.NodeInfo(DRE_NODE_ID)
    if not ni or (ni.activeRank or 0) == 0 then return false end
    local activeEntryID = ni.activeEntry and ni.activeEntry.entryID
    return activeEntryID == DRE_ENTRY_ID
end

local function Sync()
    MSW = NS.SpecialMSW
    if not SP.ConfigID() then return end
    local track = IsDRETalented() and SP.Wanted("dre")
    if not track then
        dreEnabled = false
        MSW.Unsubscribe("OnConsumed", OnMSWConsumed)
    else
        dreEnabled = true
        MSW.Subscribe("OnConsumed", OnMSWConsumed)
        MSW.InitFromLive()
    end
end

local function Start()
    MSW = NS.SpecialMSW
    dreEnabled = true
    MSW.Subscribe("OnConsumed", OnMSWConsumed)
    MSW.InitFromLive()
end

local function Stop()
    dreEnabled = false
    if MSW then MSW.Unsubscribe("OnConsumed", OnMSWConsumed) end
end

local function Save()
    if dreTotalStacks == 0 and dreDeckProcs == 0 and dreViolations == 0 and dreGainCount == 0 then return nil end
    return { total = dreTotalStacks, deck = dreDeckNumber, procs = dreDeckProcs, prev = drePrevDeckProcs,
        gains = dreGainCount, viol = dreViolations }
end

local function Load(t)
    if type(t) ~= "table" then return end
    dreTotalStacks = tonumber(t.total) or 0
    dreDeckNumber = tonumber(t.deck) or 1
    dreDeckProcs = tonumber(t.procs) or 0
    drePrevDeckProcs = tonumber(t.prev) or 0
    dreGainCount = tonumber(t.gains) or 0
    dreViolations = tonumber(t.viol) or 0
    dreSnapTotal = dreTotalStacks
end

local function Status()
    return dreEnabled and "tracking" or "not talented"
end

SP.Register({
    id = "dre", name = "DRE Ascendance", class = "SHAMAN", specs = { 263 },
    icon = DRE_ICON, size = DECK_SIZE, procs = DECK_PROCS,
    isTimer = false, bar = true, sound = false, chanceSpend = true, chanceForecast = false, viol = true,
    words = { pos = "Deck position", procs = "Proc count" },
    tokens = SP.DECK_TOKENS,
    labels = { "{procsLeft}", "{chance}", "{viol}" },
    stack = "{left}",
    Gate = IsDRETalented, Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status,
})
