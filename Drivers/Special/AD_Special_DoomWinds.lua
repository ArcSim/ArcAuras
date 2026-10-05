-- AD_Special_DoomWinds: the Doom Winds tracker, a 600-card deck of Maelstrom Weapon stacks holding 3 procs, read off a Nature wolf's arrival (the wolf path) or the Cooldown Manager's Doom Winds item frame (the CDM path).
-- Registers "dw" on the Special hub; the shared MSW engine's consumes draw; a record's driver.forceCDM picks the CDM path while a wolf talent is taken. Every branch, window and order is ProcTracker's deck file.
-- frame.auraInstanceID is secret even in the open world, so the CDM path keys off which callback fires plus a plain nil-check; it reads Blizzard fields only and hooks frames.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local DW_CDM_ID = 82621
local DW_CAST_ID = 384352
local DW_ICON = 1035054
local DECK_SIZE = 600
local DECK_PROCS = 3
-- Crackling Surge, the Nature wolf's own buff: a Sundering fire wolf never carries it
local WOLF_MARKER_ID = 224127
local RT_NODE_ID = 94889     -- Rolling Thunder
local FS_NODE_ID = 109194    -- Feral Spirit
-- measured wolf arrivals land 85 to 138 ms after the spend; never shrink this
local WOLF_WINDOW = 0.25
-- a re-set this soon after a clear is the Cooldown Manager rebuilding, not a proc
local FLAP_WINDOW = 0.5
local ASC_NODE_ID = 92219
local ASC_ENTRY_ID = 114291
local CDM_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer" }
local CDM_OWNER = "ArcAurasSpecialDW"

local dwTotalStacks = 0
local dwDeckNumber = 1
local dwDeckProcs = 0
local dwPrevProcs = 0
local dwViolations = 0
local dwGainCount = 0
local dwSnapTotal = 0
local dwLastAuraInstID = nil
local dwAuraActive = false
local dwLastClearedAt = 0
local dwCDMFrame = nil
local dwProcThisConsume = false
local dwLastProcTime = 0
local hardCastBuf = {}
local dwEnabled = false
-- talented once this session: ProcTracker's deck registration, sticky from then on
local registered = false
local armed = false
local wolfMode = false
local wolfWatchUntil = 0
local wolfFired = false
local rehookPending = false
local MSW = nil

local function BufPush(buf)
    buf[#buf + 1] = GetTime()
    if #buf > 10 then table.remove(buf, 1) end
end

local function BufCheck(buf, window)
    local now = GetTime()
    for i = #buf, 1, -1 do
        if (now - buf[i]) <= window then return true end
        if (now - buf[i]) > window then table.remove(buf, i) end
    end
    return false
end

-- true (same), false (different, or nothing stored) or nil (a side secret); with
-- nothing stored the flap test never runs, exactly as in ProcTracker
local function SameAuraID(a, b)
    if a == nil or b == nil then return false end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return nil end
    return a == b
end

-- a stored secret would poison every later compare into unknowable
local function StorableAID(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function AdvanceDeck(n)
    local before = dwTotalStacks
    dwTotalStacks = dwTotalStacks + n
    local db = math.floor(before / DECK_SIZE)
    local da = math.floor(dwTotalStacks / DECK_SIZE)
    if da > db then
        dwPrevProcs = dwDeckProcs
        dwDeckProcs = 0
        dwDeckNumber = da + 1
        if dwPrevProcs ~= DECK_PROCS then dwViolations = dwViolations + 1 end
    end
end

local function OnDWGain()
    if not dwEnabled then return end
    local now = GetTime()
    if now == dwLastProcTime then return end
    if dwProcThisConsume then return end
    dwProcThisConsume = true
    dwGainCount = dwGainCount + 1
    dwLastProcTime = now
    local snapDeck = math.floor(dwSnapTotal / DECK_SIZE)
    local currDeck = math.floor(dwTotalStacks / DECK_SIZE)
    local rolledOver = currDeck > snapDeck
    if rolledOver and dwDeckNumber > 1 and dwPrevProcs < DECK_PROCS then
        -- the spend that crossed the boundary procced: the closed deck gets it
        dwPrevProcs = dwPrevProcs + 1
        if dwPrevProcs == DECK_PROCS and dwViolations > 0 then
            dwViolations = dwViolations - 1
        end
    else
        dwDeckProcs = dwDeckProcs + 1
    end
    SP.Proc("dw")
    SP.Update("dw")
end

-- the hard-cast buffer is pruned on every check, so it runs first
local function GateGain()
    if BufCheck(hardCastBuf, 0.5) then return end
    if NS.SpecialMSW.IsAscActive() then return end
    OnDWGain()
end

local function OnWolfSUC(sid)
    if GetTime() > wolfWatchUntil then return end
    if wolfFired then return end
    if SP.SpellID(sid) ~= WOLF_MARKER_ID then return end
    wolfFired = true
end

-- Opened by a spend, the only thing that rolls the deck. Ascendance's own
-- Doom Winds never opens one, a hard cast is filtered by GateGain, and a
-- Sundering wolf carries the wrong buff. The event listens while a window is
-- open, and a window outlives a stop, as ProcTracker's always-on watcher did.
local function WolfWindowOpen()
    if not wolfMode then return end
    wolfFired = false
    wolfWatchUntil = GetTime() + WOLF_WINDOW
    SP.Listen("SPELL_UPDATE_COOLDOWN", "dw_wolf", OnWolfSUC)
    C_Timer.After(WOLF_WINDOW, function()
        wolfWatchUntil = 0
        SP.Unlisten("SPELL_UPDATE_COOLDOWN", "dw_wolf")
        if not (dwEnabled and wolfMode) then return end
        if wolfFired then GateGain() end
    end)
end

-- Which callback fires is the signal: Blizzard calls OnAuraInstanceInfoSet
-- only when its own compare saw a different instance; OnUnitAuraAddedEvent
-- fires on every active frame for any added batch and only resyncs here.
local function HookDWFrame(frame)
    if frame._arcSpecialDWHooked then return end
    frame._arcSpecialDWHooked = true

    hooksecurefunc(frame, "OnAuraInstanceInfoSet", function(self)
        if self ~= dwCDMFrame then return end
        local instID = self.auraInstanceID
        if not instID then return end
        local same = SameAuraID(instID, dwLastAuraInstID)
        if same == true then return end
        if same == nil and (GetTime() - dwLastClearedAt) <= FLAP_WINDOW then return end
        dwAuraActive = true
        dwLastAuraInstID = StorableAID(instID)
        if wolfMode then return end
        GateGain()
    end)

    hooksecurefunc(frame, "OnAuraInstanceInfoCleared", function(self)
        if self ~= dwCDMFrame then return end
        dwAuraActive = false
        dwLastClearedAt = GetTime()
        -- the last id stays: a flap is a clear then a set of the same instance
    end)

    hooksecurefunc(frame, "OnUnitAuraAddedEvent", function(self)
        if self ~= dwCDMFrame then return end
        local instID = self.auraInstanceID
        if not instID then return end
        if dwAuraActive then return end
        dwAuraActive = true
        dwLastAuraInstID = StorableAID(instID)
    end)

    hooksecurefunc(frame, "OnUnitAuraUpdatedEvent", function(self)
        if self ~= dwCDMFrame then return end
        local instID = self.auraInstanceID
        if not instID then return end
        if not dwAuraActive then
            dwAuraActive = true
            dwLastAuraInstID = StorableAID(instID)
            return
        end
        -- the buff's own instance refreshed while up: a back-to-back proc
        local same = SameAuraID(instID, dwLastAuraInstID)
        if same == false then dwLastAuraInstID = StorableAID(instID) end
        if wolfMode then return end
        GateGain()
    end)
end

-- Every viewer's item frames share the aura callbacks, and the player may
-- keep Doom Winds in any of them.
local function FindDWCDMFrame()
    for _, viewerName in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if frame.cooldownID == DW_CDM_ID then return frame end
            end
        end
    end
    return nil
end

local function RehookDWCDMFrame()
    if dwCDMFrame and dwCDMFrame.cooldownID ~= DW_CDM_ID then
        dwCDMFrame = nil
    end
    local frame = FindDWCDMFrame()
    if frame then
        if frame ~= dwCDMFrame then
            dwCDMFrame = frame
            frame._arcSpecialDWHooked = nil
            -- a rebind is not a gain: resync the state without counting
            dwAuraActive = frame.auraInstanceID ~= nil
        end
        HookDWFrame(frame)
    end
end

-- a Cooldown Manager settings change re-deals its frames: rebind now and once
-- more a second later, while this deck reads the Cooldown Manager
local function ScheduleRehook()
    if not registered or rehookPending then return end
    rehookPending = true
    if not wolfMode then RehookDWCDMFrame() end
    SP.Update("dw")
    C_Timer.After(1.0, function()
        rehookPending = false
        if not wolfMode then RehookDWCDMFrame() end
        SP.Update("dw")
    end)
end

local function OnMSWConsumed(stacksSpent, spenderID, ascActive)
    if not dwEnabled then return end
    -- the deck is frozen while Ascendance runs
    if ascActive then return end
    dwSnapTotal = dwTotalStacks
    AdvanceDeck(stacksSpent)
    dwProcThisConsume = false
    WolfWindowOpen()
    SP.Update("dw")
end

local function OnCast(unit, _, spellArg)
    if SP.Plain(unit) ~= "player" then return end
    local sid = SP.SpellID(spellArg)
    if not sid then return end
    if sid == DW_CAST_ID then BufPush(hardCastBuf) end
end

local function OnOverrideUpdated()
    RehookDWCDMFrame()
end

local function ForceCDM()
    return SP.Flag("dw", "forceCDM")
end

local WOLF_TALENTS = {
    { node = RT_NODE_ID, name = "Rolling Thunder" },
    { node = FS_NODE_ID, name = "Feral Spirit" },
}

-- the name of the talent supplying the wolf, or nil
local function ActiveWolfTalent()
    for _, t in ipairs(WOLF_TALENTS) do
        local ni = SP.NodeInfo(t.node)
        if ni and (ni.activeRank or 0) > 0 then
            if ni.subTreeID == nil or ni.subTreeActive == true then return t.name end
        end
    end
    return nil
end

local function HasWolfTalent()
    return ActiveWolfTalent() ~= nil
end

-- the choice node shared with Deeply Rooted Elements: Ascendance's entry only
local function IsDWTalented()
    local ni = SP.NodeInfo(ASC_NODE_ID)
    if not ni or (ni.activeRank or 0) == 0 then return false end
    local activeEntryID = ni.activeEntry and ni.activeEntry.entryID
    return activeEntryID == ASC_ENTRY_ID
end

local function OnEnable()
    dwEnabled = true
    wolfMode = HasWolfTalent() and not ForceCDM()
    MSW.Subscribe("OnConsumed", OnMSWConsumed)
    RehookDWCDMFrame()
    C_Timer.After(1, function() RehookDWCDMFrame(); SP.Update("dw") end)
    C_Timer.After(3, function() RehookDWCDMFrame(); SP.Update("dw") end)
    MSW.InitFromLive()
end

local function TryRegister()
    if registered or not IsDWTalented() then return end
    registered = true
    OnEnable()
end

-- the talent API is not ready on a zone change: leave the state alone then
local function ApplyTalentVisibility()
    if not registered then return end
    if not SP.ConfigID() then return end
    local talented = IsDWTalented()
    local wantWolf = talented and HasWolfTalent() and not ForceCDM()
    if wantWolf ~= wolfMode then wolfMode = wantWolf end
    if not wolfMode then RehookDWCDMFrame() end
    local track = talented and SP.Wanted("dw")
    if not track then
        dwEnabled = false
        MSW.Unsubscribe("OnConsumed", OnMSWConsumed)
    else
        dwEnabled = true
        MSW.Subscribe("OnConsumed", OnMSWConsumed)
        MSW.InitFromLive()
    end
end

local function Sync()
    MSW = NS.SpecialMSW
    TryRegister()
    ApplyTalentVisibility()
end

-- ProcTracker listens for these from load whether the deck counts or not; from
-- the first start on, so a stop and a start never lose a hard cast or a rebind
local function Start()
    MSW = NS.SpecialMSW
    if armed then return end
    armed = true
    SP.Listen("UNIT_SPELLCAST_SUCCEEDED", "dw", OnCast)
    SP.Listen("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "dw", OnOverrideUpdated)
    local ER = EventRegistry
    if ER and ER.RegisterCallback then
        ER:RegisterCallback("CooldownViewerSettings.OnDataChanged", ScheduleRehook, CDM_OWNER)
    end
end

-- nothing reads the deck any more: it stops drawing, its open windows run out
local function Stop()
    dwEnabled = false
    if MSW then MSW.Unsubscribe("OnConsumed", OnMSWConsumed) end
end

local function Read(drv)
    local pos = dwTotalStacks % DECK_SIZE
    local spend = (drv and tonumber(drv.chanceSpend)) or 10
    return {
        pos = pos, size = DECK_SIZE, left = DECK_SIZE - pos, drawn = pos,
        procs = dwDeckProcs, max = DECK_PROCS, procsLeft = DECK_PROCS - dwDeckProcs,
        chance = SP.DeckChance(DECK_SIZE, DECK_PROCS, pos, dwDeckProcs, spend),
        viol = dwViolations, deck = dwDeckNumber,
        -- on the Cooldown Manager path with no Doom Winds icon bound, no proc counts
        cdmWarn = dwEnabled and not wolfMode and not (dwCDMFrame ~= nil and dwCDMFrame.cooldownID == DW_CDM_ID),
    }
end

local function Reset()
    dwTotalStacks = 0
    dwDeckNumber = 1
    dwDeckProcs = 0
    dwPrevProcs = 0
    dwViolations = 0
    dwGainCount = 0
    dwSnapTotal = 0
    dwLastAuraInstID = nil
    dwAuraActive = dwCDMFrame ~= nil and dwCDMFrame.auraInstanceID ~= nil
    dwProcThisConsume = false
    dwLastProcTime = 0
    hardCastBuf = {}
    wolfFired = false
    wolfWatchUntil = 0
    SP.Unlisten("SPELL_UPDATE_COOLDOWN", "dw_wolf")
    SP.Update("dw")
end

local function Save()
    if dwTotalStacks == 0 and dwDeckProcs == 0 and dwViolations == 0 and dwGainCount == 0 then return nil end
    return { total = dwTotalStacks, deck = dwDeckNumber, procs = dwDeckProcs, prev = dwPrevProcs,
        viol = dwViolations, gains = dwGainCount }
end

local function Load(t)
    if type(t) ~= "table" then return end
    dwTotalStacks = tonumber(t.total) or 0
    dwDeckNumber = tonumber(t.deck) or 1
    dwDeckProcs = tonumber(t.procs) or 0
    dwPrevProcs = tonumber(t.prev) or 0
    dwViolations = tonumber(t.viol) or 0
    dwGainCount = tonumber(t.gains) or 0
    dwSnapTotal = dwTotalStacks
end

local function CDMTracking()
    if not dwCDMFrame then return false end
    return dwCDMFrame.cooldownID == DW_CDM_ID
end

local function Status()
    if not dwEnabled then return "not talented" end
    if wolfMode then return "wolf path (" .. (ActiveWolfTalent() or "wolf talent") .. ")" end
    return CDMTracking() and "Cooldown Manager path, bound" or "Cooldown Manager path, no Doom Winds icon found"
end

SP.Register({
    id = "dw", name = "Doom Winds", class = "SHAMAN", specs = { 263 },
    talentGate = { node = ASC_NODE_ID, entry = ASC_ENTRY_ID },
    icon = DW_ICON, size = DECK_SIZE, procs = DECK_PROCS,
    isTimer = false, bar = true, sound = true, chanceSpend = true, chanceForecast = false, viol = true,
    words = { pos = "Deck position", procs = "Proc count" },
    tokens = SP.DECK_TOKENS,
    labels = { "{procsLeft}", "{chance}", "{viol}" },
    stack = "{left}",
    anchorPresets = {
        cdm = {
            { id = 12821, name = "Ascendance (cooldown icon)" },
            { id = 13163, name = "Ascendance (buff icon)" },
            { id = 82621, name = "Doom Winds (buff icon)" },
        },
        action = { { name = "Ascendance", ids = { 114051, 384352 } } },
    },
    driverFlags = { "forceCDM" },
    -- ProcTracker's talent frame for this deck, plus its login pass
    syncEvents = { TRAIT_CONFIG_UPDATED = true, PLAYER_TALENT_UPDATE = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
        ACTIVE_TALENT_GROUP_CHANGED = true, PLAYER_LOGIN = true },
    Gate = IsDWTalented, Read = Read, Start = Start, Stop = Stop, Sync = Sync, Reset = Reset,
    Save = Save, Load = Load, Status = Status,
    CDMTracking = CDMTracking, CanSkipCDM = HasWolfTalent, SkipCDMReason = ActiveWolfTalent,
    Reverify = RehookDWCDMFrame,
})
