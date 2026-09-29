-- AD_Special_RestoDRE: the Restoration Deeply Rooted Elements tracker, an escalating chance of 1% per Riptide since the last proc, guaranteed by the 100th; not a deck.
-- Registers "restodre" on the Special hub; each Riptide cast is a draw (two on every 4th cast with Primal Tide Core); a proc is SPELL_UPDATE_COOLDOWN 114052 within 0.5 s of the last Riptide, which the 0.75 s GCD floor makes unambiguous.
-- Detection gates on the spec alone; the talent only gates the display, since a proc is what proves the talent. Nothing here reads an aura.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local RIPTIDE_ID = 61295
local ASC_RESTO = 114052
local DRE_SPELL = 378270
local DRE_NODE_ID = 81051
local DRE_ENTRY_ID = 101937
local RESTO_SPEC = 264
-- every 4th Riptide applies a second one whose draw fires no cast event: it is counted
local PTC_NODE_ID = 80976
local PTC_ENTRY_ID = 101842
local PTC_EVERY = 4
local PROC_WINDOW = 0.5
local BASE_CHANCE = 0.01
local CAP_AT = 100
local DRE_ICON = 960689

local registered = false
local sinceProc = 0
local totalProcs = 0
local lastRiptideAt = 0
local ascUntil = 0
local sawAProc = false
local castCount = 0

-- the trait tree first; a proc seen is proof too, since the spellbook has
-- reported a taken talent as unknown
local function HasDRE()
    local node = SP.NodeInfo(DRE_NODE_ID)
    if node then
        if node.activeEntry then
            return node.activeEntry.entryID == DRE_ENTRY_ID and (node.activeEntry.rank or 0) > 0
        end
        return false
    end
    if sawAProc then return true end
    if IsPlayerSpell then return IsPlayerSpell(DRE_SPELL) and true or false end
    return false
end

local function HasPTC()
    local node = SP.NodeInfo(PTC_NODE_ID)
    if not node or not node.activeEntry then return false end
    if node.activeEntry.entryID ~= PTC_ENTRY_ID then return false end
    return (node.activeEntry.rank or 0) > 0
end

local function DrawsForNextCast()
    if HasPTC() and ((castCount + 1) % PTC_EVERY == 0) then return 2 end
    return 1
end

local function IsResto()
    return SP.SpecID() == RESTO_SPEC
end

local function ChanceAt(n)
    local c = BASE_CHANCE * n
    return (c > 1) and 1 or c
end

-- the chance of the next draw, not the next cast, so counter and percentage
-- always agree: every failed draw is one more point
local function GetChanceValue()
    return ChanceAt(sinceProc + 1) * 100
end

local function Read()
    return {
        pos = sinceProc, size = CAP_AT, left = CAP_AT - sinceProc, drawn = sinceProc,
        procs = 0, max = 1, procsLeft = 1, count = sinceProc,
        chance = GetChanceValue(), viol = 0, totalProcs = totalProcs,
        nextDraws = DrawsForNextCast(),
        text = { pos = string.format("%.0f%%", GetChanceValue()), procs = tostring(sinceProc) },
    }
end

local function Reset()
    sinceProc, totalProcs, lastRiptideAt, ascUntil = 0, 0, 0, 0
    castCount = 0
    SP.Update("restodre")
end

local function OnCast(unit, _, spellArg)
    if not registered or not IsResto() then return end
    if SP.Plain(unit) ~= "player" then return end
    if SP.SpellID(spellArg) ~= RIPTIDE_ID then return end
    lastRiptideAt = GetTime()
    castCount = castCount + 1
    -- a Riptide during Ascendance still rolls, its proc merely invisible
    sinceProc = sinceProc + (HasPTC() and (castCount % PTC_EVERY == 0) and 2 or 1)
    SP.Update("restodre")
end

local function OnSUC(sid)
    if not registered or not IsResto() then return end
    if SP.SpellID(sid) ~= ASC_RESTO then return end
    if lastRiptideAt == 0 then return end
    -- outside the window this is a hand-pressed Ascendance
    if (GetTime() - lastRiptideAt) > PROC_WINDOW then return end
    sawAProc = true
    totalProcs = totalProcs + 1
    -- a Primal Tide Core cast rolled twice and one draw failed: that failure
    -- opens the new count
    local wasPTCCast = HasPTC() and (castCount % PTC_EVERY == 0)
    sinceProc = wasPTCCast and 1 or 0
    ascUntil = GetTime() + 6.0
    SP.Update("restodre")
end

-- a spec or talent change redraws, since the display gate reads the talent
local SPEC_EVENTS = { "PLAYER_LOGIN", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }

local function OnSpec()
    SP.Update("restodre")
end

local function Start()
    registered = true
    SP.Listen("UNIT_SPELLCAST_SUCCEEDED", "restodre", OnCast)
    SP.Listen("SPELL_UPDATE_COOLDOWN", "restodre", OnSUC)
    for _, e in ipairs(SPEC_EVENTS) do SP.Listen(e, "restodre_spec", OnSpec) end
end

local function Stop()
    registered = false
    SP.Unlisten("UNIT_SPELLCAST_SUCCEEDED", "restodre")
    SP.Unlisten("SPELL_UPDATE_COOLDOWN", "restodre")
    for _, e in ipairs(SPEC_EVENTS) do SP.Unlisten(e, "restodre_spec") end
end

-- the display gate a record may ask for: the spec, and the talent unless the
-- record turned that requirement off
local function ShowGate(drv)
    if not IsResto() then return false end
    if drv and drv.requireTalent == false then return true end
    return HasDRE()
end

local function Save()
    if sinceProc == 0 and totalProcs == 0 and castCount == 0 and not sawAProc then return nil end
    return { since = sinceProc, procs = totalProcs, casts = castCount, seen = sawAProc or nil,
        lastRiptide = lastRiptideAt, ascUntil = ascUntil }
end

local function Load(t)
    if type(t) ~= "table" then return end
    sinceProc = tonumber(t.since) or 0
    totalProcs = tonumber(t.procs) or 0
    castCount = tonumber(t.casts) or 0
    sawAProc = t.seen == true
    lastRiptideAt = tonumber(t.lastRiptide) or 0
    ascUntil = tonumber(t.ascUntil) or 0
end

local function Status()
    if not (registered and IsResto()) then return "needs Restoration" end
    return HasDRE() and "tracking" or "tracking, talent not taken"
end

SP.Register({
    id = "restodre", name = "Deeply Rooted Elements", class = "SHAMAN", specs = { 264 },
    icon = DRE_ICON, size = CAP_AT, procs = nil, cap = CAP_AT,
    isTimer = false, bar = true, sound = false, chanceSpend = false, chanceForecast = false, viol = false,
    words = {
        pos = "Proc chance", procs = "Riptides since last proc",
        emptyColor = "Chance still climbing", fullColor = "Guaranteed (100%)",
    },
    tokens = { "chance", "count", "pos", "size" },
    labels = { "{count}" },
    stack = "{chance}",
    anchorPresets = {
        cdm = { { id = 29968, name = "Riptide" }, { id = 29973, name = "Ascendance" } },
        action = { { name = "Riptide", ids = { RIPTIDE_ID } }, { name = "Ascendance", ids = { ASC_RESTO } } },
    },
    talentGate = { node = DRE_NODE_ID, entry = DRE_ENTRY_ID },
    Gate = IsResto, Talented = HasDRE, ShowGate = ShowGate, Read = Read, Start = Start, Stop = Stop,
    Sync = nil, Reset = Reset, Save = Save, Load = Load, Status = Status,
})
