-- AD_CDMBar: the Cooldown Manager bar (barKind "cdmbar"), a bar that copies one of the Cooldown Manager's Tracked Bars (retail only).
-- The game fills its own bar item with SetMinMaxValues and SetValue; hooks on those widgets repeat each call onto ours, in combat too, with nothing polled.
-- The repeated numbers may be secret: they only reach secret-safe setters, and the one test is on the literal 0 the game sends when its timer stops.
local ADDON, NS = ...
local hooksecurefunc = NS.Perf and NS.Perf.Hooks("CDMBar") or hooksecurefunc   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("CDMBar") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames and its sweep skips those on the game's aura buttons
if NS.IsForever == true then return end
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R
local IsSecret = issecretvalue or function() return false end

local CB = {}
NS.CDMBars = CB

CB.VIEWER = "BuffBarCooldownViewer"
-- the editor sample: a swing-length timer, a short rest, then again
CB.SAMPLE_LEN, CB.SAMPLE_REST = 2.6, 0.4

-- a game bar widget -> its item frame (a hook stays for the session)
CB.owner = {}
-- a cooldown ID -> the bars copying it, { [entry] = true }
CB.links = {}
-- an item frame -> our child frame that reports its hide
CB.watch = {}

function CB.CooldownID(rec)
    local d = rec and rec.driver
    local id = d and tonumber(d.cooldownID)
    if id and id > 0 then return math.floor(id) end
    return nil
end

-- Formatted C-side, so a secret time left never becomes a Lua number; the
-- castbar's rule, since rounding and a decimals threshold would compare it.
function CB.TimeFmt(rec)
    return (R(rec, "text", "durDecimalsEnabled") == true) and "%.1f" or "%.0f"
end

-- The bars following whatever entry this item shows now: the game hands item
-- frames to other entries, so the item's ID is read on every call.
local function Following(item)
    local id = item and item.cooldownID
    if id == nil or IsSecret(id) then return nil end
    return CB.links[id]
end

-- The timer is idle: the bar stands empty with no time on it.
function CB.Stop(e)
    local fill = e.shell.fill
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    local fs = e.shell.texts.dur
    if fs then fs:SetText("") end
    CB.SetRunning(e, false)
end

-- Hide when inactive follows the copied timer; the visibility pass runs only
-- on a change, never on every repeated call.
function CB.SetRunning(e, on)
    if e.cbRunning == on then return end
    e.cbRunning = on
    e.stateHidden = (not on) and R(e.rec, "behavior", "hideWhenInactive") == true
    K.ApplyVisibility(e)
end

local function OnRange(bar, lo, hi)
    local set = Following(CB.owner[bar])
    if not set then return end
    -- the game stops its timer with a literal 0; a running length may be secret
    local stopped = hi == nil or (not IsSecret(hi) and hi <= 0)
    for e in pairs(set) do
        if stopped then
            if e.cbRunning ~= false then CB.Stop(e) end
        else
            e.shell.fill:SetMinMaxValues(lo, hi)
            if not e.cbRunning then CB.SetRunning(e, true) end
        end
    end
end

local function OnValue(bar, v)
    local set = Following(CB.owner[bar])
    if not set then return end
    for e in pairs(set) do
        if e.cbRunning then
            e.shell.fill:SetValue(v)
            local fs = e.shell.texts.dur
            if fs and fs:IsShown() then fs:SetFormattedText(e.cbFmt or "%.0f", v) end
        end
    end
end

-- An item that hides stops calling (its entry went idle, the viewer hid, a
-- layout pass released it); its ID is still set when the hide lands.
function CB.ItemHidden(item)
    local set = Following(item)
    if not set then return end
    for e in pairs(set) do
        if e.cbRunning ~= false then CB.Stop(e) end
    end
end

-- Widget hooks only: the item's own methods and scripts stay the game's. A
-- child frame of ours reports the hide.
function CB.HookItem(item)
    local bar = type(item) == "table" and item.Bar
    if type(bar) ~= "table" or CB.owner[bar] or type(bar.SetValue) ~= "function" then return end
    CB.owner[bar] = item
    hooksecurefunc(bar, "SetMinMaxValues", OnRange)
    hooksecurefunc(bar, "SetValue", OnValue)
    local watch = CreateFrame("Frame", nil, item)
    watch:SetScript("OnHide", function() CB.ItemHidden(item) end)
    CB.watch[item] = watch
end

-- The viewer's layout pass makes new items; hooked once the first bar links.
function CB.OnLayout()
    if next(CB.links) then CB.Scan() end
end

function CB.Scan()
    local v = _G[CB.VIEWER]
    if type(v) ~= "table" or type(v.GetChildren) ~= "function" then return end
    if not CB.viewerHooked and type(v.RefreshLayout) == "function" then
        CB.viewerHooked = true
        hooksecurefunc(v, "RefreshLayout", CB.OnLayout)
    end
    local kids = { v:GetChildren() }
    for i = 1, #kids do CB.HookItem(kids[i]) end
end

-- The game's item for this entry, if its Tracked Bars show one.
function CB.ItemFor(id)
    if not id then return nil end
    for _, item in pairs(CB.owner) do
        if item.cooldownID == id then return item end
    end
    return nil
end

function CB.Unlink(e)
    local set = e.cbID and CB.links[e.cbID]
    if set then
        set[e] = nil
        if next(set) == nil then CB.links[e.cbID] = nil end
    end
end

-- Kind registry hooks

-- A rebuild keeps a running copy as it is: the next call from the game is a
-- frame away, and resetting here would blink a bar that hides when idle.
function CB.Ensure(e)
    if e.isPreview then return end
    local id = CB.CooldownID(e.rec)
    if e.cbID ~= id or e.cbRunning == nil then
        CB.Unlink(e)
        e.cbID = id
        if id then
            local set = CB.links[id] or {}
            CB.links[id] = set
            set[e] = true
        end
        e.cbRunning = nil
        CB.Stop(e)
    end
    e.cbFmt = CB.TimeFmt(e.rec)
    if id then CB.Scan() end
    e.stateHidden = (not e.cbRunning) and R(e.rec, "behavior", "hideWhenInactive") == true
    K.ApplyVisibility(e)
end

function CB.Refresh(e)
    if e.isPreview then return end
    e.stateHidden = (not e.cbRunning) and R(e.rec, "behavior", "hideWhenInactive") == true
    K.ApplyVisibility(e)
end

function CB.Release(e)
    CB.Unlink(e)
    e.cbID, e.cbRunning = nil, nil
end

-- The style pass keeps the text format current; an idle bar shows no time.
function CB.Styled(e)
    e.cbFmt = CB.TimeFmt(e.rec)
    if e.isPreview or e.cbRunning then return end
    local fs = e.shell.texts.dur
    if fs then fs:SetText("") end
end

function CB.Diag(e)
    local n = 0
    for _ in pairs(CB.owner) do n = n + 1 end
    return ("%s [cdmbar %s] item=%s running=%s hooked=%d"):format(tostring(e.rec.name), tostring(e.cbID),
        tostring(CB.ItemFor(e.cbID) ~= nil), tostring(e.cbRunning == true), n)
end

-- Editor preview: a sample timer, part way through or running out and again.

function CB.PreviewModes()
    return {
        { key = "static", text = "Preview", tip = "The bar part way through its timer." },
        { key = "loop", text = "Timer loop", tip = "A 2.6 second timer that runs out and starts again." },
    }
end

function CB.PreviewApply(e, loop, t)
    local len = CB.SAMPLE_LEN
    local left = len * 0.6
    if loop then
        local at = (t or 0) % (len + CB.SAMPLE_REST)
        left = (at < len) and (len - at) or 0
    end
    local fill = e.shell.fill
    fill:SetMinMaxValues(0, len)
    fill:SetValue(left)
    local fs = e.shell.texts.dur
    if fs and fs:IsShown() then
        if left > 0 then fs:SetFormattedText(CB.TimeFmt(e.rec), left) else fs:SetText("") end
    end
end

Bars.RegisterKind("cdmbar", {
    Ensure = CB.Ensure,
    Refresh = CB.Refresh,
    Release = CB.Release,
    Styled = CB.Styled,
    Diag = CB.Diag,
    PreviewModes = CB.PreviewModes,
    PreviewApply = CB.PreviewApply,
})
