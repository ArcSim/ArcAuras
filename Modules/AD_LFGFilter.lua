-- AD_LFGFilter: the LFG Filter module on WoW Forever. The filter is the load-on-demand addon ArcAuras_LFG; this holds
-- the switch and loads it. It hooks the game's window for the session, so switching off takes effect after a reload.
-- Settings: ArcAurasDB.lfgFilter, account-wide; on unless switched off (off = true).
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("LFGFilter") or C_Timer   -- /arcperf times what they run
local L = {}
NS.LFGFilter = L

local SUB, STANDALONE = "ArcAuras_LFG", "ArcLFGFilter"
local BOOT, WAIT = "adlfg_boot", "adlfg_wait"

local function Loaded(name)
    local A = C_AddOns
    return A ~= nil and A.IsAddOnLoaded ~= nil and A.IsAddOnLoaded(name) == true
end

-- Asked at call time: the standalone loads after this addon.
function L.Standalone() return Loaded(STANDALONE) end
function L.Available() return NS.IsForever == true and not L.Standalone() end
function L.Running() return Loaded(SUB) end

local function DB(create)
    local root = ArcAurasDB
    if type(root) ~= "table" then return nil end
    local t = root.lfgFilter
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        root.lfgFilter = t
    end
    return t
end

function L.IsOn()
    local db = DB()
    return not (db ~= nil and db.off == true)
end

function L.NeedsReload() return L.Running() and not L.IsOn() end

local Events = NS.Events

function L.Start()
    if not (L.Available() and L.IsOn()) or L.Running() then return end
    if InCombatLockdown() then
        Events.On("PLAYER_REGEN_ENABLED", WAIT, function()
            Events.Off("PLAYER_REGEN_ENABLED", WAIT)
            C_Timer.After(0, L.Start)
        end)
        return
    end
    local A = C_AddOns
    if A and A.LoadAddOn then A.LoadAddOn(SUB) end
end

function L.SetOn(v)
    local db = DB(true)
    if not db then return end
    db.off = (not v) or nil
    if v then L.Start() end
    if L.notify then L.notify() end
end

function L.OpenSettings()
    if L.Running() and SlashCmdList.ARCLFG then SlashCmdList.ARCLFG("") end
end

-- At login the saved settings are in; on WoW Forever the client can hand them over a moment later, so the world's
-- first entry looks again.
Events.On("PLAYER_LOGIN", BOOT, function()
    Events.Off("PLAYER_LOGIN", BOOT)
    L.Start()
end)
Events.On("PLAYER_ENTERING_WORLD", BOOT, function()
    Events.Off("PLAYER_ENTERING_WORLD", BOOT)
    Events.Off("PLAYER_LOGIN", BOOT)
    -- not mid-dispatch: loading adds to the event being dispatched
    C_Timer.After(0, L.Start)
end)
