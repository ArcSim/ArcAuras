-- AD_Special_StormUnleashed: the Storm Unleashed tracker, a 250-card deck of Maelstrom Weapon stacks holding 5 procs; a proc is SPELL_UPDATE_COOLDOWN for the hidden gain-only marker 1252413 within 50 ms of a consume.
-- Registers "stormunleashed" on the Special hub; the shared MSW engine's consumes draw; Ascendance is not suppressed, since the deck rolls on every spend.
-- The buff 1262830 is never watched: its cooldown update fires on gain, loss and expiry alike, and counting it finished a 250-card deck at 6 of 5.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local SU_GAIN_ID = 1252413
local SU_ICON = 7636566
local DECK_SIZE = 250
local DECK_PROCS = 5
-- any rank grants the 2% per stack this deck models; an entry test buys nothing
local SU_NODE_ID = 110401
-- the marker lands in the spend's own frame; 50 ms is generous
local PROC_WINDOW = 0.05

local suTotalStacks = 0
local suDeckNumber = 1
local suDeckProcs = 0
local suPrevProcs = 0
local suViolations = 0
local suGainCount = 0
local suSnapTotal = 0
local suProcThisConsume = false
local suLastProcTime = 0
local suEnabled = false
-- talented once this session: ProcTracker's deck registration, sticky from then on
local registered = false
local sucWatchUntil = 0
local sucGainFired = false
local MSW = nil

local function AdvanceDeck(n)
    local before = suTotalStacks
    suTotalStacks = suTotalStacks + n
    local db = math.floor(before / DECK_SIZE)
    local da = math.floor(suTotalStacks / DECK_SIZE)
    if da > db then
        suPrevProcs = suDeckProcs
        suDeckProcs = 0
        suDeckNumber = da + 1
        if suPrevProcs ~= DECK_PROCS then suViolations = suViolations + 1 end
    end
end

local function OnSUGain()
    if not suEnabled then return end
    local now = GetTime()
    if now == suLastProcTime then return end
    if suProcThisConsume then return end
    suProcThisConsume = true
    suGainCount = suGainCount + 1
    suLastProcTime = now
    local snapDeck = math.floor(suSnapTotal / DECK_SIZE)
    local currDeck = math.floor(suTotalStacks / DECK_SIZE)
    local rolledOver = currDeck > snapDeck
    if rolledOver and suDeckNumber > 1 and suPrevProcs < DECK_PROCS then
        -- the spend that crossed the boundary procced: the closed deck gets it
        suPrevProcs = suPrevProcs + 1
        if suPrevProcs == DECK_PROCS and suViolations > 0 then
            suViolations = suViolations - 1
        end
    else
        suDeckProcs = suDeckProcs + 1
    end
    SP.Proc("stormunleashed")
    SP.Update("stormunleashed")
end

local function OnSUC(sid)
    if GetTime() > sucWatchUntil then return end
    if sucGainFired then return end
    if SP.SpellID(sid) ~= SU_GAIN_ID then return end
    sucGainFired = true
end

-- The event listens while a window is open, and a window outlives a stop, as
-- ProcTracker's always-on watcher did.
local function OnMSWConsumed(stacksSpent, spenderID, ascActive)
    if not suEnabled then return end
    suSnapTotal = suTotalStacks
    AdvanceDeck(stacksSpent)
    suProcThisConsume = false
    sucGainFired = false
    sucWatchUntil = GetTime() + PROC_WINDOW
    SP.Listen("SPELL_UPDATE_COOLDOWN", "su_watch", OnSUC)
    C_Timer.After(PROC_WINDOW, function()
        sucWatchUntil = 0
        SP.Unlisten("SPELL_UPDATE_COOLDOWN", "su_watch")
        if not suEnabled then return end
        if sucGainFired then OnSUGain() else SP.Update("stormunleashed") end
    end)
end

local function Read(drv)
    local pos = suTotalStacks % DECK_SIZE
    local spend = (drv and tonumber(drv.chanceSpend)) or 10
    return {
        pos = pos, size = DECK_SIZE, left = DECK_SIZE - pos, drawn = pos,
        procs = suDeckProcs, max = DECK_PROCS, procsLeft = DECK_PROCS - suDeckProcs,
        chance = SP.DeckChance(DECK_SIZE, DECK_PROCS, pos, suDeckProcs, spend),
        viol = suViolations, deck = suDeckNumber,
    }
end

local function Reset()
    suTotalStacks = 0
    suDeckNumber = 1
    suDeckProcs = 0
    suPrevProcs = 0
    suViolations = 0
    suGainCount = 0
    suSnapTotal = 0
    suProcThisConsume = false
    suLastProcTime = 0
    sucGainFired = false
    sucWatchUntil = 0
    SP.Unlisten("SPELL_UPDATE_COOLDOWN", "su_watch")
    SP.Update("stormunleashed")
end

local function IsSUTalented()
    if SP.SpecID() ~= 263 then return false end
    if not SP.ConfigID() then return false end
    local ni = SP.NodeInfo(SU_NODE_ID)
    if not ni or (ni.activeRank or 0) == 0 then return false end
    if ni.subTreeID then return ni.subTreeActive == true end
    return true
end

-- ProcTracker's registration: once talented, the deck draws
local function TryRegister()
    if registered or not IsSUTalented() then return end
    registered = true
    suEnabled = true
    MSW.Subscribe("OnConsumed", OnMSWConsumed)
    MSW.InitFromLive()
end

-- the talent API is not ready on a zone change: leave the state alone then
local function ApplyTalentVisibility()
    if not registered then return end
    if not SP.ConfigID() then return end
    local track = IsSUTalented() and SP.Wanted("stormunleashed")
    if not track then
        suEnabled = false
        MSW.Unsubscribe("OnConsumed", OnMSWConsumed)
    else
        suEnabled = true
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

-- nothing reads the deck any more: it stops drawing, its open window runs out
local function Stop()
    suEnabled = false
    if MSW then MSW.Unsubscribe("OnConsumed", OnMSWConsumed) end
end

local function Save()
    if suTotalStacks == 0 and suDeckProcs == 0 and suViolations == 0 and suGainCount == 0 then return nil end
    return { total = suTotalStacks, deck = suDeckNumber, procs = suDeckProcs, prev = suPrevProcs,
        viol = suViolations, gains = suGainCount }
end

local function Load(t)
    if type(t) ~= "table" then return end
    suTotalStacks = tonumber(t.total) or 0
    suDeckNumber = tonumber(t.deck) or 1
    suDeckProcs = tonumber(t.procs) or 0
    suPrevProcs = tonumber(t.prev) or 0
    suViolations = tonumber(t.viol) or 0
    suGainCount = tonumber(t.gains) or 0
    suSnapTotal = suTotalStacks
end

local function Status()
    return suEnabled and "tracking" or "not talented"
end

SP.Register({
    id = "stormunleashed", name = "Storm Unleashed", class = "SHAMAN", specs = { 263 },
    talentGate = { node = SU_NODE_ID },
    icon = SU_ICON, size = DECK_SIZE, procs = DECK_PROCS,
    isTimer = false, bar = true, sound = false, chanceSpend = true, chanceForecast = false, viol = true,
    words = { pos = "Deck position", procs = "Proc count" },
    tokens = SP.DECK_TOKENS,
    labels = { "{procsLeft}", "{chance}", "{viol}" },
    stack = "{left}",
    -- ProcTracker's talent frame for this deck, plus its login pass
    syncEvents = { TRAIT_CONFIG_UPDATED = true, PLAYER_TALENT_UPDATE = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
        ACTIVE_TALENT_GROUP_CHANGED = true, PLAYER_SPECIALIZATION_CHANGED = true, PLAYER_LOGIN = true },
    Gate = IsSUTalented, Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status,
})
