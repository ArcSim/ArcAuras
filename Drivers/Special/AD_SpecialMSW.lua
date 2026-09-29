-- AD_SpecialMSW: the shared Maelstrom Weapon engine the Enhancement trackers subscribe to: one presence model of aura 344179, a consume or an expiry on removal, the Ascendance and Doom Winds windows.
-- Subscribers call MSW.Subscribe / Unsubscribe and MSW.InitFromLive after subscribing; the hub owns MSW.Reset. Events register only while someone subscribes.
-- The UNIT_AURA payload is never read: its vectors are secret in restricted content. Presence comes from C_UnitAuras.GetPlayerAuraBySpellID, whose fields are guarded before use.
local ADDON, NS = ...
if NS.IsForever == true then return end
local SP = NS.Special
if not SP then return end

local MSW = {}
NS.SpecialMSW = MSW

local MSW_SPELL_ID = 344179
local ASC_SPELL_ID = 114051
local ASC_BUFF_ID = 114049

local MSW_SPENDER_IDS = {
    [188196] = true,    -- Lightning Bolt
    [188443] = true,    -- Chain Lightning
    [1218090] = true,   -- Primordial Storm
    [452201] = true,    -- Tempest
}
-- Stormstrike, Windstrike and Crash Lightning spend only inside a Doom Winds window
local DW_INITIATORS = { [17364] = true, [115356] = true, [187874] = true }
local DW_CAST_ID = 384352

-- apps 0 means the count is unknown: a consume then falls back to 10
local msw = {
    present = false,
    auraInstanceID = nil,   -- kept only when plain, for the == compare
    apps = 0,
    spenderCastID = nil,
    spenderCastTime = 0,
}
local ascendanceActive = false
local dwActive = false

MSW.IsAscActive = function() return ascendanceActive end
MSW.IsDWActive = function() return dwActive end

MSW.OnConsumed = {}   -- functions(stacksSpent, spenderID, ascActive)
MSW.OnExpired = {}    -- functions(instID, stacks)
MSW.OnGained = {}     -- functions(instID, apps)

local registered = false

local function HasSubscribers()
    return #MSW.OnConsumed > 0 or #MSW.OnExpired > 0 or #MSW.OnGained > 0
end

local OnCast, OnAura

local function RefreshRegistration()
    local want = HasSubscribers()
    if want == registered then return end
    registered = want
    if want then
        SP.Listen("UNIT_AURA", "msw", OnAura)
        SP.Listen("UNIT_SPELLCAST_SUCCEEDED", "msw", OnCast)
    else
        SP.Unlisten("UNIT_AURA", "msw")
        SP.Unlisten("UNIT_SPELLCAST_SUCCEEDED", "msw")
    end
end
MSW.RefreshRegistration = RefreshRegistration
MSW.IsTracking = function() return registered end

function MSW.Subscribe(event, fn)
    local t = MSW[event]
    if type(t) ~= "table" then return end
    for _, f in ipairs(t) do if f == fn then return end end
    t[#t + 1] = fn
    RefreshRegistration()
end

function MSW.Unsubscribe(event, fn)
    local t = MSW[event]
    if type(t) ~= "table" then return end
    for i, f in ipairs(t) do
        if f == fn then
            table.remove(t, i)
            RefreshRegistration()
            return
        end
    end
end

local function ReadLive()
    local live = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        and C_UnitAuras.GetPlayerAuraBySpellID(MSW_SPELL_ID)
    if not live then return false, nil, nil end
    local aid, apps
    if not (issecretvalue and issecretvalue(live.auraInstanceID)) then
        aid = live.auraInstanceID
    end
    if not (issecretvalue and issecretvalue(live.applications)) then
        apps = tonumber(live.applications)
    end
    return true, aid, apps
end

function MSW.InitFromLive()
    local present, aid, apps = ReadLive()
    msw.present = present
    msw.auraInstanceID = aid
    msw.apps = (apps and apps > 0) and apps or 0
end

-- subscriber lists survive a reset: trackers re-subscribe on their own
function MSW.Reset()
    msw.present = false
    msw.auraInstanceID = nil
    msw.apps = 0
    msw.spenderCastID = nil
    msw.spenderCastTime = 0
    ascendanceActive = false
    dwActive = false
end

-- a removal is a consume only when a listed spender was cast within 0.3 s
local function FireConsumeOrExpire(stacksSpent, aidGone)
    local now = GetTime()
    local spenderFound = msw.spenderCastID ~= nil and (now - msw.spenderCastTime) < 0.3
    local spenderID = spenderFound and msw.spenderCastID or nil
    msw.spenderCastID = nil
    msw.spenderCastTime = 0
    if spenderFound then
        for _, fn in ipairs(MSW.OnConsumed) do
            fn(stacksSpent, spenderID, ascendanceActive)
        end
    else
        for _, fn in ipairs(MSW.OnExpired) do
            fn(aidGone, stacksSpent)
        end
    end
end

OnCast = function(unit, _, spellArg)
    if SP.Plain(unit) ~= "player" then return end
    local sid = SP.SpellID(spellArg)
    if not sid then return end
    if sid == ASC_SPELL_ID or sid == ASC_BUFF_ID then
        ascendanceActive = true
        C_Timer.After(15, function() ascendanceActive = false end)
    end
    if sid == DW_CAST_ID then
        dwActive = true
        C_Timer.After(10, function() dwActive = false end)
    end
    if MSW_SPENDER_IDS[sid] then
        -- inside Doom Winds a triggered Chain Lightning must not overwrite the initiator
        local isDWInitiator = dwActive and msw.spenderCastID and DW_INITIATORS[msw.spenderCastID]
        if not isDWInitiator then
            msw.spenderCastID = sid
            msw.spenderCastTime = GetTime()
        end
        if msw.present then
            local _p, _aid, apps = ReadLive()
            if apps and apps > (msw.apps or 0) then
                msw.apps = apps
            end
        end
    end
    if dwActive and DW_INITIATORS[sid] then
        msw.spenderCastID = sid
        msw.spenderCastTime = GetTime()
    end
end

OnAura = function()
    local present, aid, apps = ReadLive()
    if present and not msw.present then
        msw.present = true
        msw.auraInstanceID = aid
        msw.apps = (apps and apps > 0) and apps or 0
        for _, fn in ipairs(MSW.OnGained) do
            fn(aid, msw.apps)
        end
    elseif present and msw.present then
        -- both ids plain and different: a consume and a regain landed in one batch
        local replaced = aid ~= nil and msw.auraInstanceID ~= nil and aid ~= msw.auraInstanceID
        if replaced then
            local cached = msw.apps or 0
            local spent = math.min(10, cached > 0 and cached or 10)
            local gone = msw.auraInstanceID
            FireConsumeOrExpire(spent, gone)
            msw.auraInstanceID = aid
            msw.apps = (apps and apps > 0) and apps or 0
            for _, fn in ipairs(MSW.OnGained) do
                fn(aid, msw.apps)
            end
        else
            if apps and apps > 0 then msw.apps = apps end
            if aid ~= nil then msw.auraInstanceID = aid end
        end
    elseif (not present) and msw.present then
        local cached = msw.apps or 0
        local spent = math.min(10, cached > 0 and cached or 10)
        local gone = msw.auraInstanceID
        msw.present = false
        msw.auraInstanceID = nil
        msw.apps = 0
        FireConsumeOrExpire(spent, gone)
    end
end
