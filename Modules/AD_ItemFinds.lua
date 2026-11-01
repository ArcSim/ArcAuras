-- AD_ItemFinds: the item finder on WoW Forever, sharing only unless the player picks the full finder. It is the
-- load-on-demand addon ArcAuras_Finds (Forever only, its own save); this holds the switches and loads it at login.
-- Settings: ArcAurasDB.itemFinds, account-wide; on unless switched off (off = true), full = true for the full finder.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("ItemFinds") or C_Timer   -- /arcperf times what they run
local F = {}
NS.ItemFinds = F

local SUB, FULL = "ArcAuras_Finds", "ForeverItemFinder"
local BOOT = "aditemfinds_boot"

local function Loaded(name)
    local A = C_AddOns
    return A ~= nil and A.IsAddOnLoaded ~= nil and A.IsAddOnLoaded(name) == true
end

-- Asked at call time: the full finder loads after this addon, and shares for the player when it is there.
function F.Standalone() return Loaded(FULL) end
function F.Available() return NS.IsForever == true and not F.Standalone() end

local function DB(create)
    local root = ArcAurasDB
    if type(root) ~= "table" then return nil end
    local t = root.itemFinds
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        root.itemFinds = t
    end
    return t
end

function F.IsOn()
    local db = DB()
    return not (db ~= nil and db.off == true)
end

-- Switched off and on again in one session: the engine starts again only after a reload.
function F.NeedsReload()
    return F.IsOn() and ArcAurasFinds ~= nil and ArcAurasFinds.State() == "stopped"
end

function F.Running()
    return ArcAurasFinds ~= nil and ArcAurasFinds.State() ~= "stopped"
end

function F.Start()
    if not (F.Available() and F.IsOn()) or Loaded(SUB) then return end
    local A = C_AddOns
    if A and A.LoadAddOn then A.LoadAddOn(SUB) end
end

function F.SetOn(v)
    local db = DB(true)
    if not db then return end
    db.off = (not v) or nil
    if v then
        F.Start()
    elseif ArcAurasFinds then
        ArcAurasFinds.Stop()
    end
    if F.notify then F.notify() end
end

function F.Count() return ArcAurasFinds and ArcAurasFinds.Count() or 0 end

-- The full finder (its window, map marks and pop-ups) instead of sharing only; off unless picked (itemFinds.full).
-- The engine reads it when it loads, so a change takes effect after a reload.
function F.IsFull()
    local db = DB()
    return db ~= nil and db.full == true
end

function F.SetFull(v)
    local db = DB(true)
    if not db then return end
    db.full = (v and true) or nil
    if F.notify then F.notify() end
end

function F.FullLoaded() return F.Running() and ArcAurasFinds.Full() == true end
function F.FullNeedsReload() return F.Running() and F.IsFull() ~= F.FullLoaded() end
function F.Open() if F.FullLoaded() then ArcAurasFinds.Open() end end

-- At login the saved settings are in; on WoW Forever the client can hand them over a moment later, so the world's
-- first entry looks again.
local Events = NS.Events
Events.On("PLAYER_LOGIN", BOOT, function()
    Events.Off("PLAYER_LOGIN", BOOT)
    F.Start()
end)
Events.On("PLAYER_ENTERING_WORLD", BOOT, function()
    Events.Off("PLAYER_ENTERING_WORLD", BOOT)
    Events.Off("PLAYER_LOGIN", BOOT)
    -- not mid-dispatch: loading adds to the event being dispatched
    C_Timer.After(0, F.Start)
end)
