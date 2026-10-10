-- AD_Pins: game frames pinned to a group (group.pins): a unit frame, an action
-- bar or another addon's frame that the group carries along. A pin never links
-- that frame to ours: it is placed on UIParent at the spot the group gives, so
-- a protected frame never makes our group protected too.
-- The spot comes off the group's full grid box (Engine.GroupBox), the box the
-- options window shows: a dynamic group that shrinks moves nothing, so nothing
-- has to move in combat, where the game refuses to move a protected frame.
-- What moves a group out of combat (a rebuild, a drag, an anchor) places its
-- frames again; a frame that had to wait goes when combat ends, and a frame no
-- pin holds any more goes back to where it was.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local Pins = {}
NS.Pins = Pins

-- the most frames one group carries
Pins.MAX = 4

-- A pin is the frame's point on the group's point. These pairs have a name;
-- any other pair (an import) reads as Custom, both points on rows of their own.
Pins.SIDES = {
    { value = "left", text = "Left of the group", src = "RIGHT", dst = "LEFT" },
    { value = "right", text = "Right of the group", src = "LEFT", dst = "RIGHT" },
    { value = "above", text = "Above the group", src = "BOTTOM", dst = "TOP" },
    { value = "below", text = "Below the group", src = "TOP", dst = "BOTTOM" },
    { value = "center", text = "On the group", src = "CENTER", dst = "CENTER" },
}
Pins.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local IS_POINT = {}
for _, p in ipairs(Pins.POINTS) do IS_POINT[p] = true end
-- a new pin sits above the group
Pins.NEW_SRC, Pins.NEW_DST = "BOTTOM", "TOP"

-- Snapping back stops for a frame something else moves this many times within
-- FIGHT_SECONDS: two movers that each put it back would trade it every frame.
Pins.FIGHT_LIMIT, Pins.FIGHT_SECONDS = 6, 2

-- Half a pixel is a tie a float read tips either way; the engine leans the
-- same sliver (Core\AD_LayoutEngine.lua TIE), so a pin snaps as a group does.
local TIE = 0.0058

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function Pins.Src(pin) return IS_POINT[pin.src] and pin.src or Pins.NEW_SRC end
function Pins.Dst(pin) return IS_POINT[pin.dst] and pin.dst or Pins.NEW_DST end

-- the side a pin's points make, or "custom"
function Pins.SideOf(pin)
    local src, dst = Pins.Src(pin), Pins.Dst(pin)
    for _, s in ipairs(Pins.SIDES) do
        if s.src == src and s.dst == dst then return s.value end
    end
    return "custom"
end

-- where a point sits on a w x h box, from its bottom-left
local function PointOff(point, w, h)
    local x = (point:find("LEFT") and 0) or (point:find("RIGHT") and w) or w / 2
    local y = (point:find("BOTTOM") and 0) or (point:find("TOP") and h) or h / 2
    return x, y
end

-- The game refuses to move a protected frame in combat.
local function Locked(f)
    if not InCombatLockdown() then return false end
    local p = f.IsProtected and f:IsProtected()
    return Plain(p) ~= false
end

-- Blizzard's Edit Mode owns its frames while it is open: a pin waits for it to close.
local function BlizzEditing()
    local m = EditModeManagerFrame
    return m ~= nil and m.IsEditModeActive ~= nil and m:IsEditModeActive() == true
end

-- True when the group's own anchor rests on f or on a frame inside it: moving f
-- would move the group, and the pin would chase itself.
local function InChain(grec, f)
    local A = NS.Anchor
    local r, n = grec, 0
    while r and A and n < 16 do
        n = n + 1
        local t = A.Effective(r)
        if not t then return false end
        local p, d = t, 0
        while p and d < 32 do
            if p == f then return true end
            if p == UIParent then break end
            p, d = Plain(p.GetParent and p:GetParent()), d + 1
        end
        r = t._adRecId and Store.Get(t._adRecId) or nil
    end
    return false
end

-- Why a named frame can't be pinned to this group, or nil when it can:
-- "empty" (no name), "missing" (no such frame now) or "refused" (one of ours,
-- the whole screen, a frame the game shields, or the group's own anchor).
function Pins.Problem(grec, name)
    if type(name) ~= "string" or name == "" then return "empty" end
    -- a raw read: a name nothing made reads nil, whatever sits on _G's metatable
    local f = rawget(_G, name)
    if type(f) ~= "table" or not f.GetObjectType then return "missing" end
    if f == UIParent or f == WorldFrame then return "refused" end
    local FP = NS.FramePicker
    if FP and FP.OwnKind and FP.OwnKind(name) then return "refused" end
    local A = NS.Anchor
    local why = A and A.FrameProblem(f)
    if why == "missing" then return "missing" end
    if why then return "refused" end
    if not (f.SetPoint and f.ClearAllPoints and f.GetEffectiveScale and f.GetNumPoints) then return "refused" end
    if InChain(grec, f) then return "refused" end
    return nil
end

-- The group's frame while it can carry pins, else nil and why: "hidden" (not
-- on screen) or "moves" (it rides the cursor or a nameplate, which move every
-- frame, combat too).
local function CarrierOf(grec)
    local E = NS.LayoutEngine
    local gf = E and E.GetGroupFrame and E.GetGroupFrame(grec.id)
    if not (gf and gf:IsShown()) then return nil, "hidden" end
    local lf = gf:GetParent()
    if not (lf and lf:IsShown()) then return nil, "hidden" end
    local A = NS.Anchor
    if A and (A.IsPlatePick(grec) or A.IsMousePick(grec)) then return nil, "moves" end
    return gf
end

-- The bottom-left a pin puts its frame at, as offsets from UIParent's
-- bottom-left in the frame's own units, on a whole physical pixel; nil while a
-- size or a spot reads secret. Offsets are UIParent units, as a typed X / Y.
function Pins.Spot(gid, f, pin)
    local E = NS.LayoutEngine
    local gl, gb, gw, gh = E.GroupBox(gid)
    local gf = E.GetGroupFrame(gid)
    if not (gl and gf) then return nil end
    local gs = Plain(gf:GetEffectiveScale())
    local fs = Plain(f:GetEffectiveScale())
    local fw, fh = Plain(f:GetWidth()), Plain(f:GetHeight())
    local us = UIParent:GetEffectiveScale()
    local _, physH = GetPhysicalScreenSize()
    if not (gs and fs and fw and fh and us and physH) or gs <= 0 or fs <= 0 or physH <= 0 then return nil end
    -- screen units (a frame's units times its scale), the space all frames share
    local dx, dy = PointOff(Pins.Dst(pin), gw * gs, gh * gs)
    local sx, sy = PointOff(Pins.Src(pin), fw * fs, fh * fs)
    local x = gl * gs + dx - sx + (tonumber(pin.x) or 0) * us
    local y = gb * gs + dy - sy + (tonumber(pin.y) or 0) * us
    -- 768 screen units span the screen's height in physical pixels
    local px = 768 / physH
    x = math.floor(x / px + 0.5 - TIE) * px
    y = math.floor(y / px + 0.5 + TIE) * px
    local ul, ub = Plain(UIParent:GetLeft()) or 0, Plain(UIParent:GetBottom()) or 0
    return (x - ul * us) / fs, (y - ub * us) / fs
end

-- Run-time state, keyed by the game's frames (read, never written to):
local home = {}      -- frame -> its points before the first pin moved it
local placedAt = {}  -- frame -> { x, y } the offsets a pin last set
local live = {}      -- frame -> { gid, i, snap, fights, fightAt } the pin holding it
local hooked = {}    -- frame -> true once its SetPoint is hooked (snap back)
local carriers = {}  -- group frame -> true once its SetPoint is hooked
local status = {}    -- [groupId] = { [i] = word } for the options rows
local busy = false   -- our own SetPoint is running
local waiting = false
local anyMissing = false   -- a named frame did not exist at the last pass

-- What each pin is doing now, for its row: "pinned", "missing", "combat",
-- "taken", "hidden", "moves", "refused", "fight", "edit", "wait" or "empty".
function Pins.Status(gid, i)
    local s = status[gid]
    return s and s[i] or nil
end

local listeners = {}
-- fn runs after a pass that may have changed a pin's word
function Pins.OnChange(key, fn) listeners[key] = fn end
local function Changed()
    for _, fn in pairs(listeners) do fn() end
end

-- still sitting where the last pin put it
local function Still(f)
    local at = placedAt[f]
    if not at or Plain(f:GetNumPoints()) ~= 1 then return false end
    local p, rel, rp, x, y = f:GetPoint(1)
    x, y = Plain(x), Plain(y)
    return p == "BOTTOMLEFT" and rel == UIParent and rp == "BOTTOMLEFT" and x ~= nil and y ~= nil
        and math.abs(x - at[1]) < 0.001 and math.abs(y - at[2]) < 0.001
end

-- Keeps the frame's points the first time a pin moves it; false when they
-- can't be read, and then it is not moved.
local function KeepHome(f)
    if home[f] then return true end
    local n = Plain(f:GetNumPoints())
    if not n then return false end
    local pts = {}
    for i = 1, n do
        local p, rel, rp, x, y = f:GetPoint(i)
        if not (Plain(p) and Plain(rp) and Plain(x) and Plain(y)) then return false end
        pts[i] = { p, rel, rp, x, y }
    end
    home[f] = pts
    return true
end

-- Back where it was before the first pin; false while combat holds it.
local function GoHome(f)
    local pts = home[f]
    if pts then
        if Locked(f) then return false end
        busy = true
        f:ClearAllPoints()
        for _, p in ipairs(pts) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        busy = false
    end
    home[f], placedAt[f] = nil, nil
    return true
end

-- Puts f at (x, y) unless it is there already. A size its two points gave
-- becomes its own first, or a single point would leave it no size at all.
local function Put(f, x, y)
    local at = placedAt[f]
    if at and math.abs(at[1] - x) < 0.001 and math.abs(at[2] - y) < 0.001 and Still(f) then return "pinned" end
    if Locked(f) then return "combat" end
    if not KeepHome(f) then return "refused" end
    local n = Plain(f:GetNumPoints())
    if n and n > 1 then
        local w, h = Plain(f:GetWidth()), Plain(f:GetHeight())
        if w and h and w > 0 and h > 0 then f:SetSize(w, h) end
    end
    busy = true
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    busy = false
    placedAt[f] = { x, y }
    return "pinned"
end

local function WaitForCombat()
    if waiting then return end
    waiting = true
    Events.On("PLAYER_REGEN_ENABLED", "adpins", function()
        Events.Off("PLAYER_REGEN_ENABLED", "adpins")
        waiting = false
        Pins.ApplyAll()
    end)
end

local function SetWord(gid, i, word)
    status[gid] = status[gid] or {}
    status[gid][i] = word
end

-- Places one held frame from its pin; its word.
local function Place(f, l, pin)
    if BlizzEditing() then return "edit" end
    local x, y = Pins.Spot(l.gid, f, pin)
    if not x then return "wait" end
    local word = Put(f, x, y)
    if word == "combat" then WaitForCombat() end
    return word
end

-- Snap back: something else moved a held frame. Placing waits a frame, so a
-- mover setting several points in a row is done before the frame goes back.
function Pins.SnapAll()
    local now = GetTime()
    for f, l in pairs(live) do
        if l.snap and not Still(f) then
            if l.fightAt and now - l.fightAt < Pins.FIGHT_SECONDS then
                l.fights = l.fights + 1
            else
                l.fightAt, l.fights = now, 1
            end
            if l.fights > Pins.FIGHT_LIMIT then
                l.snap = false
                SetWord(l.gid, l.i, "fight")
            else
                local grec = Store.Get(l.gid)
                local pin = grec and type(grec.pins) == "table" and grec.pins[l.i]
                if type(pin) == "table" then SetWord(l.gid, l.i, Place(f, l, pin)) end
            end
        end
    end
    Changed()
end

local function Moved(self)
    if busy then return end
    local l = live[self]
    if l and l.snap then Events.Coalesce("adpins_snap", Pins.SnapAll) end
end

local function HookFrame(f)
    if hooked[f] then return end
    hooked[f] = true
    hooksecurefunc(f, "SetPoint", Moved)
    if f.SetAllPoints then hooksecurefunc(f, "SetAllPoints", Moved) end
end

-- A group frame that moves (a rebuild, an anchor, a snap) moves its frames:
-- one pass the next frame, however many times it was placed.
local function HookCarrier(gf)
    if carriers[gf] then return end
    carriers[gf] = true
    hooksecurefunc(gf, "SetPoint", function()
        if next(live) then Events.Coalesce("adpins_follow", Pins.Follow) end
    end)
end

-- Places every held frame again from its group's spot, holding no new ones.
function Pins.Follow()
    for f, l in pairs(live) do
        local grec = Store.Get(l.gid)
        local pin = grec and type(grec.pins) == "table" and grec.pins[l.i]
        if type(pin) == "table" and pin.frame and rawget(_G, pin.frame) == f then
            SetWord(l.gid, l.i, Place(f, l, pin))
        end
    end
    Changed()
end

-- The full pass, at the end of every rebuild: each shown group places the
-- frames it pins (the first group to name a frame holds it), and every frame
-- no pin holds goes back to where it was.
function Pins.ApplyAll()
    for k in pairs(status) do status[k] = nil end
    local seen = {}
    anyMissing = false
    for _, layout in ipairs(Store.Layouts()) do
        local groups = Store.ChildrenOf(layout)
        for _, grec in ipairs(groups) do
            local list = grec.pins
            if type(list) == "table" and #list > 0 then
                local gf, why = CarrierOf(grec)
                if gf then HookCarrier(gf) end
                for i = 1, math.min(#list, Pins.MAX) do
                    local pin = list[i]
                    local word
                    if type(pin) ~= "table" then
                        word = "empty"
                    else
                        word = Pins.Problem(grec, pin.frame) or why
                    end
                    local f = not word and rawget(_G, pin.frame) or nil
                    if f and seen[f] then word = "taken" end
                    if word == "missing" then anyMissing = true end
                    if not word then
                        seen[f] = true
                        local l = live[f]
                        if not (l and l.gid == grec.id and l.i == i) then
                            l = { gid = grec.id, i = i, fights = 0 }
                            live[f] = l
                        end
                        l.snap = pin.snap == true
                        if l.snap then HookFrame(f) end
                        word = Place(f, l, pin)
                    end
                    SetWord(grec.id, i, word)
                end
            end
        end
    end
    for f in pairs(live) do
        if not seen[f] then live[f] = nil end
    end
    for f in pairs(home) do
        if not seen[f] and not GoHome(f) then WaitForCombat() end
    end
    Changed()
end

-- A drag moves a group with no SetPoint of ours: while the button is down,
-- held frames follow every frame; nothing runs once it is up.
local driver
local function DragTick()
    if not IsMouseButtonDown("LeftButton") then driver:SetScript("OnUpdate", nil) end
    Pins.Follow()
end
function Pins.DragStart()
    if not next(live) then return end
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", DragTick)
end
function Pins.DragStop()
    if driver then driver:SetScript("OnUpdate", nil) end
    if next(live) then Events.Coalesce("adpins_follow", Pins.Follow) end
end

-- A held frame that Blizzard (a layout change, its Edit Mode) or another mover
-- placed while the pin waited goes back there, not to where it first was.
local function RetakeHomes()
    for f in pairs(placedAt) do
        if not Still(f) then
            local keep = home[f]
            home[f] = nil
            if not KeepHome(f) then home[f] = keep end
            placedAt[f] = nil
        end
    end
end

function Pins.Init()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            RetakeHomes()
            Events.Coalesce("adpins_apply", Pins.ApplyAll)
        end, Pins)
    end
    local ev = "EDIT_MODE_LAYOUTS_UPDATED"
    if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev) then
        Events.On(ev, "adpins", function()
            if not next(placedAt) then return end
            RetakeHomes()
            Events.Coalesce("adpins_apply", Pins.ApplyAll)
        end)
    end
    -- an addon that loads later may bring a named frame
    Events.On("ADDON_LOADED", "adpins", function()
        if anyMissing then Events.Coalesce("adpins_apply", Pins.ApplyAll) end
    end)
end

-- Editing the list. Each change rebuilds, and the rebuild places the frames.

function Pins.List(grec)
    if type(grec.pins) ~= "table" then grec.pins = {} end
    return grec.pins
end

function Pins.Count(grec)
    return (grec and type(grec.pins) == "table") and math.min(#grec.pins, Pins.MAX) or 0
end

function Pins.Add(grec)
    local list = Pins.List(grec)
    if #list >= Pins.MAX then return nil end
    local pin = { frame = "", src = Pins.NEW_SRC, dst = Pins.NEW_DST, x = 0, y = 0 }
    list[#list + 1] = pin
    Store.Dirty("style", grec.id)
    return pin
end

function Pins.Remove(grec, i)
    local list = Pins.List(grec)
    if not list[i] then return end
    table.remove(list, i)
    if #list == 0 then grec.pins = nil end
    Store.Dirty("style", grec.id)
end

-- One field of pin i: frame, src, dst, x, y or snap; side writes src and dst.
function Pins.Set(grec, i, field, v)
    local pin = Pins.List(grec)[i]
    if type(pin) ~= "table" then return end
    if field == "side" then
        for _, s in ipairs(Pins.SIDES) do
            if s.value == v then pin.src, pin.dst = s.src, s.dst end
        end
    elseif field == "frame" then
        pin.frame = type(v) == "string" and v:match("^%s*(.-)%s*$") or ""
    elseif field == "src" or field == "dst" then
        if IS_POINT[v] then pin[field] = v end
    elseif field == "x" or field == "y" then
        pin[field] = math.floor((tonumber(v) or 0) + 0.5)
    elseif field == "snap" then
        pin.snap = (v == true) or nil
    end
    Store.Dirty("style", grec.id)
end
