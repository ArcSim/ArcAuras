-- AD_TextAnchor: one text pinned off its own icon or bar, onto a named frame,
-- the action button holding a spell, or a Cooldown Manager icon (by spell, or
-- by the exact cooldown ID). Core\AD_SpellAnchor.lua finds buttons and icons;
-- this file carries the text there on a frame drawn above the target, and home
-- whenever the target is not on screen. Nothing is written to the game's frames.
local ADDON, NS = ...

local TA = {}
NS.TextAnchor = TA

-- [fontstring] = { owner, slot, kind, spec, point, rel, x, y, home }
TA.live = {}

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

function TA.Pinned(kind) return kind == "frame" or kind == "action" or kind == "cdm" end

-- The frame a pin names, while the text may ride it: on screen, not forbidden,
-- not a nameplate, its place not secret. nil sends the text home.
function TA.Target(kind, spec)
    if kind == "action" or kind == "cdm" then
        local SA = NS.SpellAnchor
        return SA and SA.Resolve(kind, spec) or nil
    end
    if kind ~= "frame" or type(spec) ~= "string" or spec == "" then return nil end
    local f = _G[spec]
    if type(f) ~= "table" or type(f.GetObjectType) ~= "function" then return nil end
    local A = NS.Anchor
    if A and A.FrameProblem and A.FrameProblem(f) then return nil end
    local vis = f.IsVisible and f:IsVisible()
    if Secret(vis) or not vis then return nil end
    return f
end

-- One carrier per text on its owner, a child of the text's home so the owner's
-- alpha and shown state still reach the text wherever it rides.
local function Carrier(owner, slot, home)
    owner._adPins = owner._adPins or {}
    local c = owner._adPins[slot]
    if not c then
        c = CreateFrame("Frame", nil, home)
        owner._adPins[slot] = c
    end
    return c
end

-- Places fs: on the target with point / rel / x / y when its pin resolves,
-- else home (home(), or the same point pair on owner). slot names the text on
-- its owner ("stack", "label2", "bar:stk"); kind / spec come from its fields.
function TA.Place(fs, owner, slot, kind, spec, point, rel, x, y, home)
    if not (fs and owner) then return end
    point = point or "CENTER"
    rel = rel or point
    local target = TA.Pinned(kind) and TA.Target(kind, spec) or nil
    local hp = fs._adPinHome
    if target then
        if not hp then
            hp = fs:GetParent()
            fs._adPinHome = hp
        end
        local c = Carrier(owner, slot, hp)
        c:ClearAllPoints()
        c:SetAllPoints(target)
        local A = NS.Anchor
        if A and A.RaiseOver then A.RaiseOver(c, target) end
        c:Show()
        if fs:GetParent() ~= c then fs:SetParent(c) end
        fs:ClearAllPoints()
        fs:SetPoint(point, c, rel, x or 0, y or 0)
    else
        if hp and fs:GetParent() ~= hp then fs:SetParent(hp) end
        local c = owner._adPins and owner._adPins[slot]
        if c then c:Hide() end
        if home then
            home()
        else
            fs:ClearAllPoints()
            fs:SetPoint(point, owner, rel, x or 0, y or 0)
        end
    end
    if TA.Pinned(kind) then
        local p = TA.live[fs] or {}
        p.owner, p.slot, p.kind, p.spec, p.point, p.rel, p.x, p.y, p.home =
            owner, slot, kind, spec, point, rel, x, y, home
        TA.live[fs] = p
    elseif TA.live[fs] then
        TA.live[fs] = nil
    end
    TA.Arm()
end

-- Every pinned text on owner goes home, its carriers hidden (an icon or bar
-- leaving the screen, or a pooled frame about to serve another record).
function TA.Release(owner)
    for fs, p in pairs(TA.live) do
        if p.owner == owner then
            if fs._adPinHome and fs:GetParent() ~= fs._adPinHome then fs:SetParent(fs._adPinHome) end
            TA.live[fs] = nil
        end
    end
    for _, c in pairs(owner and owner._adPins or {}) do c:Hide() end
    TA.Arm()
end

-- Bars swapped, a spell moved, the Cooldown Manager laid out again: every
-- pinned text looks again (Core\AD_SpellAnchor.lua runs this once per pass).
function TA.Reapply()
    for fs, p in pairs(TA.live) do
        TA.Place(fs, p.owner, p.slot, p.kind, p.spec, p.point, p.rel, p.x, p.y, p.home)
    end
end

-- The finder's events and hooks stay armed while a text needs them.
function TA.Arm()
    local SA = NS.SpellAnchor
    if not (SA and SA.SyncTexts) then return end
    local action, cdm = false, false
    for _, p in pairs(TA.live) do
        if p.kind == "action" then action = true elseif p.kind == "cdm" then cdm = true end
    end
    if action ~= TA.armedAction or cdm ~= TA.armedCDM then
        TA.armedAction, TA.armedCDM = action, cdm
        SA.SyncTexts(action, cdm)
    end
end

-- The status line under a text's pin rows.
function TA.Describe(kind, spec)
    if not TA.Pinned(kind) then return "" end
    local SA = NS.SpellAnchor
    if kind == "frame" then
        if type(spec) ~= "string" or spec == "" then return "Type a frame name or pick one." end
        if TA.Target(kind, spec) then return "On " .. spec .. "." end
        return spec .. " is not shown, so it sits on its own spot."
    end
    local p = SA and SA.Parse(spec)
    if not p then
        return kind == "cdm" and "Type a spell or a cooldown ID, or pick an icon." or "Type a spell or pick a button."
    end
    if p.cid and kind ~= "cdm" then return "A cooldown ID names a Cooldown Manager icon." end
    local what
    if p.cid then
        what = "icon with cooldown ID " .. p.cid
    else
        local nm = SA.NameOf(p.list[1]) or ("spell " .. tostring(p.list[1]))
        what = ((kind == "action") and "action button with " or "Cooldown Manager icon of ") .. nm
    end
    if TA.Target(kind, spec) then return "On the " .. what .. "." end
    return "No " .. what .. " is shown, so it sits on its own spot."
end
