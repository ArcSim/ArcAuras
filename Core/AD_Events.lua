-- The shared event frame and dispatcher. An event stays registered while
-- it has at least one subscriber.

local ADDON, NS = ...
local Events = {}
NS.Events = Events

local frame = CreateFrame("Frame")
local subs = {}      -- [event] = { [key] = fn }
local counts = {}    -- [event] = number of subscribers

frame:SetScript("OnEvent", function(_, event, ...)
    local list = subs[event]
    if not list then return end
    -- /arcperf (Core\AD_Perf.lua): each handler timed while it is on
    local P = NS.Perf
    if P and P.on then
        for key, fn in pairs(list) do P.Top(P.Key("event", event, key), fn, event, ...) end
        return
    end
    for _, fn in pairs(list) do
        fn(event, ...)
    end
end)

function Events.On(event, key, fn)
    if not subs[event] then
        subs[event] = {}
        counts[event] = 0
    end
    if not subs[event][key] then
        counts[event] = counts[event] + 1
    end
    subs[event][key] = fn
    if counts[event] == 1 then
        frame:RegisterEvent(event)
    end
end

function Events.Off(event, key)
    local list = subs[event]
    if not (list and list[key]) then return end
    list[key] = nil
    counts[event] = counts[event] - 1
    if counts[event] <= 0 then
        frame:UnregisterEvent(event)
        subs[event] = nil
        counts[event] = nil
    end
end

-- Internal messages (not game events), subscribed by key like events.
local msgs = {}      -- [message] = { [key] = fn }

function Events.OnMessage(message, key, fn)
    msgs[message] = msgs[message] or {}
    msgs[message][key] = fn
end

function Events.Fire(message, ...)
    local list = msgs[message]
    if not list then return end
    local P = NS.Perf
    if P and P.on then
        for key, fn in pairs(list) do P.Call(P.Key("message", message, key), fn, message, ...) end
        return
    end
    for _, fn in pairs(list) do
        fn(message, ...)
    end
end

-- Next-frame coalescer: each key runs at most once per frame, however many
-- times it was requested.
local pending = {}   -- [key] = fn
local queued = false

-- Named, so the deep profiler can time everything queued work runs.
function Events.RunPending()
    queued = false
    local run = pending
    pending = {}
    local P = NS.Perf
    if P and P.on then
        for key, f in pairs(run) do P.Top(P.Key("next frame", "", key), f) end
        return
    end
    for _, f in pairs(run) do
        f()
    end
end

function Events.Coalesce(key, fn)
    pending[key] = fn
    if queued then return end
    queued = true
    C_Timer.After(0, Events.RunPending)
end

-- Coalescing with a cap, for event storms (SPELL_UPDATE_USABLE comes ten
-- times a second while power moves). The first request runs the next frame.
-- Out of combat a later one waits until gap seconds after the last run; in
-- combat, or when urgent, it runs the next frame. The last request always runs.
local capped = {}    -- [key] = { at = last run, gen, armed, fn, run }

function Events.CoalesceCapped(key, fn, gap, urgent)
    local c = capped[key]
    if not c then
        c = { at = -math.huge, gen = 0 }
        c.run = function()
            c.at = GetTime()
            c.fn()
        end
        capped[key] = c
    end
    c.fn = fn
    local wait = c.at + gap - GetTime()
    if urgent or wait <= 0 or InCombatLockdown() then
        -- an armed timer stands down
        c.gen, c.armed = c.gen + 1, false
        Events.Coalesce(key, c.run)
        return
    end
    if c.armed then return end
    c.armed = true
    local gen = c.gen
    C_Timer.After(wait, function()
        if c.gen ~= gen then return end
        c.armed = false
        Events.Coalesce(key, c.run)
    end)
end
