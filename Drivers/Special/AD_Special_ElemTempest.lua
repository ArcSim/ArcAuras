-- AD_Special_ElemTempest: the Elemental Tempest tracker, a 333-Maelstrom deck holding 2 procs; a draw is a spender's listed cost read after its cast, a proc SPELL_UPDATE_COOLDOWN 454015 in the same client frame.
-- Registers "elemtempest" on the Special hub; its own player cast events draw; a record's driver.chanceForecast (auto, instant, blast) picks the cost the chance assumes.
-- Ascendance casts spend Maelstrom but grant a free Tempest, so they never draw. Player cast events stay plain in combat.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local TEMPEST_BUFF = 454015
local TEMPEST_CAST = 452201
local DECK_SIZE = 333
local DECK_PROCS = 2
local MAELSTROM_SPENDERS = {
    [8042] = "Earth Shock",
    [462620] = "Earthquake",
    [61882] = "Earthquake",
    [117014] = "Elemental Blast",
}
local ASC_SPELL_ID = 114050
local ELEMENTAL_BLAST = 117014
local EARTH_SHOCK = 8042
local EARTHQUAKE = 462620
local EARTHQUAKE_ALT = 61882
local TEMPEST_NODE_ID = 94892
local MAELSTROM_POWER = 11

local elemTotalMaelstrom = 0
local elemDeckNumber = 1
local elemDeckProcs = 0
-- true only while Elemental Blast is on the cast bar: the one moment the next spend is known
local elemCastingBlast = false
local elemPrevDeckProcs = 0
local elemPrevPrevDeckProcs = 0
local elemGainCount = 0
local elemViolations = 0
local elemEnabled = false
local snap = { deckNumber = 1, prevProcs = 0, totalStacks = 0, procCredited = false }
local openWatches = {}

-- violations are judged a deck late, once a late proc can no longer land
local function AdvanceDeck(cost)
    local before = elemTotalMaelstrom
    elemTotalMaelstrom = elemTotalMaelstrom + cost
    local dBefore = math.floor(before / DECK_SIZE)
    local dAfter = math.floor(elemTotalMaelstrom / DECK_SIZE)
    if dAfter > dBefore then
        local ppViolation = elemPrevPrevDeckProcs ~= 0 and elemPrevPrevDeckProcs ~= DECK_PROCS
        if ppViolation then elemViolations = elemViolations + 1 end
        elemPrevPrevDeckProcs = elemPrevDeckProcs
        elemPrevDeckProcs = elemDeckProcs
        elemDeckProcs = 0
        elemDeckNumber = dAfter + 1
    end
end

local function CreditProc(snapDeck)
    elemGainCount = elemGainCount + 1
    if snapDeck == elemDeckNumber then
        elemDeckProcs = elemDeckProcs + 1
    elseif elemPrevDeckProcs < DECK_PROCS then
        elemPrevDeckProcs = elemPrevDeckProcs + 1
        if elemPrevDeckProcs == DECK_PROCS and elemViolations > 0 then
            elemViolations = elemViolations - 1
        end
    else
        elemDeckProcs = elemDeckProcs + 1
    end
    snap.procCredited = true
    SP.Update("elemtempest")
end

local function GetMaelstromCost(spellID)
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return 0 end
    for _, c in ipairs(costs) do
        if c.type == MAELSTROM_POWER then return tonumber(SP.Plain(c.cost)) or 0 end
    end
    return 0
end

local function OnWatchSUC(sid)
    if SP.SpellID(sid) ~= TEMPEST_BUFF then return end
    for i = 1, #openWatches do
        local w = openWatches[i]
        local age = (GetTime() - w.spendTime) * 1000
        if not w.firedAt and age <= 5 then w.firedAt = GetTime() end
    end
end

local function OpenWatch(w)
    openWatches[#openWatches + 1] = w
    if #openWatches == 1 then SP.Listen("SPELL_UPDATE_COOLDOWN", "elem_watch", OnWatchSUC) end
end

local function CloseWatch(w)
    for i = #openWatches, 1, -1 do
        if openWatches[i] == w then table.remove(openWatches, i) break end
    end
    if #openWatches == 0 then SP.Unlisten("SPELL_UPDATE_COOLDOWN", "elem_watch") end
end

local function OnMaelstromSpent(spellID, cost, isASC)
    if not elemEnabled then return end
    snap.deckNumber = elemDeckNumber
    snap.prevProcs = elemPrevDeckProcs
    snap.totalStacks = elemTotalMaelstrom
    snap.procCredited = false
    local snapDeckAtSpend = elemDeckNumber
    if not isASC then
        AdvanceDeck(cost)
        snap.totalStacks = elemTotalMaelstrom
        snap.deckNumber = elemDeckNumber
    end
    if isASC then return end
    local w = { spendTime = GetTime() }
    OpenWatch(w)
    C_Timer.After(0.005, function()
        CloseWatch(w)
        if not elemEnabled then return end
        if w.firedAt then CreditProc(snapDeckAtSpend) else SP.Update("elemtempest") end
    end)
end

local function OnCast(unit, _, spellArg)
    if SP.Plain(unit) ~= "player" then return end
    local spellID = SP.SpellID(spellArg)
    if not spellID then return end
    if spellID == ELEMENTAL_BLAST and elemCastingBlast then
        elemCastingBlast = false
    end
    if spellID == ASC_SPELL_ID then
        OnMaelstromSpent(spellID, GetMaelstromCost(spellID), true)
        return
    end
    if MAELSTROM_SPENDERS[spellID] then
        OnMaelstromSpent(spellID, GetMaelstromCost(spellID), false)
    end
end

local function CastBar(casting)
    return function(unit, _, spellArg)
        if SP.Plain(unit) ~= "player" then return end
        if SP.SpellID(spellArg) ~= ELEMENTAL_BLAST then return end
        if casting ~= elemCastingBlast then
            elemCastingBlast = casting
            SP.Update("elemtempest")
        end
    end
end
local OnCastStart, OnCastEnd = CastBar(true), CastBar(false)

-- Eye of the Storm's discounts ride along: every cost is read live
local function InstantCost()
    for _, id in ipairs({ EARTH_SHOCK, EARTHQUAKE, EARTHQUAKE_ALT }) do
        local c = GetMaelstromCost(id)
        if c and c > 0 then return c end
    end
    return 60
end

local function BlastCost()
    local c = GetMaelstromCost(ELEMENTAL_BLAST)
    return (c and c > 0) and c or 90
end

local function ForecastMode(drv)
    local mode = drv and drv.chanceForecast
    if mode ~= "blast" and mode ~= "instant" then return "auto" end
    return mode
end

local function ForecastCost(drv)
    local mode = ForecastMode(drv)
    if mode == "blast" then return BlastCost() end
    if mode == "instant" then return InstantCost() end
    if elemCastingBlast then return BlastCost() end
    return InstantCost()
end

local function ForecastLabel(drv)
    local mode = ForecastMode(drv)
    if mode == "blast" then return "Elemental Blast (" .. BlastCost() .. ")" end
    if mode == "instant" then return "Instant (" .. InstantCost() .. ")" end
    return "Instant (" .. InstantCost() .. "), Elemental Blast (" .. BlastCost() .. ") while casting"
end

local function Read(drv)
    local pos = elemTotalMaelstrom % DECK_SIZE
    return {
        pos = pos, size = DECK_SIZE, left = DECK_SIZE - pos, drawn = pos,
        procs = elemDeckProcs, max = DECK_PROCS, procsLeft = DECK_PROCS - elemDeckProcs,
        chance = SP.DeckChance(DECK_SIZE, DECK_PROCS, pos, elemDeckProcs, ForecastCost(drv)),
        deck = elemDeckNumber, casting = elemCastingBlast, forecast = ForecastLabel(drv),
    }
end

local function Reset()
    elemTotalMaelstrom = 0
    elemDeckNumber = 1
    elemDeckProcs = 0
    elemCastingBlast = false
    elemPrevDeckProcs = 0
    elemPrevPrevDeckProcs = 0
    elemGainCount = 0
    elemViolations = 0
    snap.deckNumber = 1
    snap.prevProcs = 0
    snap.totalStacks = 0
    snap.procCredited = false
    SP.Update("elemtempest")
end

local function IsTempestTalented()
    if SP.SpecID() ~= 262 then return false end
    local ni = SP.NodeInfo(TEMPEST_NODE_ID)
    if not ni or (ni.activeRank or 0) == 0 then return false end
    if ni.subTreeID then return ni.subTreeActive == true end
    return true
end

local function Sync()
    elemEnabled = IsTempestTalented() and SP.Wanted("elemtempest")
end

local function Start()
    elemEnabled = true
    SP.Listen("UNIT_SPELLCAST_SUCCEEDED", "elem", OnCast)
    SP.Listen("UNIT_SPELLCAST_START", "elem", OnCastStart)
    SP.Listen("UNIT_SPELLCAST_STOP", "elem", OnCastEnd)
    SP.Listen("UNIT_SPELLCAST_INTERRUPTED", "elem", OnCastEnd)
end

local function Stop()
    elemEnabled = false
    SP.Unlisten("UNIT_SPELLCAST_SUCCEEDED", "elem")
    SP.Unlisten("UNIT_SPELLCAST_START", "elem")
    SP.Unlisten("UNIT_SPELLCAST_STOP", "elem")
    SP.Unlisten("UNIT_SPELLCAST_INTERRUPTED", "elem")
end

local function Save()
    if elemTotalMaelstrom == 0 and elemDeckProcs == 0 and elemViolations == 0 and elemGainCount == 0 then return nil end
    return { total = elemTotalMaelstrom, deck = elemDeckNumber, procs = elemDeckProcs, prev = elemPrevDeckProcs,
        prevPrev = elemPrevPrevDeckProcs, gains = elemGainCount, viol = elemViolations }
end

local function Load(t)
    if type(t) ~= "table" then return end
    elemTotalMaelstrom = tonumber(t.total) or 0
    elemDeckNumber = tonumber(t.deck) or 1
    elemDeckProcs = tonumber(t.procs) or 0
    elemPrevDeckProcs = tonumber(t.prev) or 0
    elemPrevPrevDeckProcs = tonumber(t.prevPrev) or 0
    elemGainCount = tonumber(t.gains) or 0
    elemViolations = tonumber(t.viol) or 0
    snap.deckNumber, snap.prevProcs, snap.totalStacks = elemDeckNumber, elemPrevDeckProcs, elemTotalMaelstrom
end

local function Status()
    return elemEnabled and "tracking" or "not talented"
end

SP.Register({
    id = "elemtempest", name = "Tempest (Elemental)", class = "SHAMAN", specs = { 262 },
    icon = TEMPEST_CAST, size = DECK_SIZE, procs = DECK_PROCS,
    isTimer = false, bar = true, sound = false, chanceSpend = false, chanceForecast = true, viol = false,
    words = { pos = "Deck position", procs = "Proc count" },
    tokens = SP.DECK_TOKENS,
    labels = { "{procsLeft}", "{chance}" },
    stack = "{left}",
    driverFlags = { "chanceForecast" },
    Gate = IsTempestTalented, Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status, ForecastLabel = ForecastLabel,
})
