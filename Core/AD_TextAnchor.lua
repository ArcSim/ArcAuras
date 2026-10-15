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

function TA.Pinned(kind) return kind == "frame" or kind == "action" or kind == "cdm" or kind == "item" end

-- One of our own items ("icon:12", "bar:5", "group:3"): its kind and record id.
function TA.ItemSpec(spec)
    if type(spec) ~= "string" then return nil end
    local kind, id = spec:match("^(%a+):(%d+)$")
    if not kind then return nil end
    return kind, tonumber(id)
end

-- An item's frame showing or hiding moves the texts riding it (between
-- layout passes too); hooked once on our own frame.
local function Watch(f)
    if f._adPinWatch then return end
    f._adPinWatch = true
    local again = function()
        if NS.Events and NS.Events.Coalesce then
            NS.Events.Coalesce("adtext_items", TA.ReapplyItems)
        else
            TA.ReapplyItems()
        end
    end
    f:HookScript("OnShow", again)
    f:HookScript("OnHide", again)
end

-- The frame a pin names, while the text may ride it: on screen, not forbidden,
-- not a nameplate, its place not secret. nil sends the text home.
function TA.Target(kind, spec)
    if kind == "item" then
        local k, id = TA.ItemSpec(spec)
        local A = NS.Anchor
        local f = k and A and A.FrameOf and A.FrameOf(k, id)
        if not f then return nil end
        Watch(f)
        local vis = f:IsVisible()
        if Secret(vis) or not vis then return nil end
        return f
    end
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
    -- the editor's stage keeps its texts on its icon: pinned out to the live
    -- target they would leave the stage (Play on screen keeps the real pin)
    if owner._adOnStage == true then kind = nil end
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

-- A text with a strata of its own draws on a frame of its own: a child of its
-- home, so the home's alpha and shown state still reach it, at the home's
-- level. "inherit" (or nil) keeps it on its home. Called each style pass,
-- after the text is placed: a parent's SetFrameStrata resets its children. A
-- pinned text rides its carrier over the target and is left alone; the
-- editor's stage keeps every text with its icon.
function TA.Strata(owner, fs, slot, strata, home)
    if not (owner and fs and home) or TA.live[fs] then return end
    if owner._adOnStage == true then strata = nil end
    local want = home
    if strata and strata ~= "inherit" then
        owner._adTxtStrata = owner._adTxtStrata or {}
        local h = owner._adTxtStrata[slot]
        if not h then
            h = CreateFrame("Frame", nil, home)
            h:SetAllPoints(home)
            owner._adTxtStrata[slot] = h
        elseif h:GetParent() ~= home then
            h:SetParent(home)
            h:ClearAllPoints()
            h:SetAllPoints(home)
        end
        h:SetFrameStrata(strata)
        local lvl = home:GetFrameLevel()
        if type(lvl) == "number" and not Secret(lvl) then h:SetFrameLevel(lvl) end
        h:Show()
        TA.strataHosts[h] = strata
        want = h
    elseif owner._adTxtStrata and owner._adTxtStrata[slot] then
        TA.strataHosts[owner._adTxtStrata[slot]] = nil
    end
    if fs._adPinHome then fs._adPinHome = want end
    if fs:GetParent() ~= want then fs:SetParent(want) end
end

-- [host] = strata: every text frame with a strata of its own.
TA.strataHosts = setmetatable({}, { __mode = "k" })

-- A frame that holds only texts (a range bar's band labels) takes the strata
-- itself; "inherit" gives it back its home's.
function TA.HostStrata(h, strata, home)
    if not (h and home) then return end
    if strata and strata ~= "inherit" then
        h:SetFrameStrata(strata)
        TA.strataHosts[h] = strata
    elseif TA.strataHosts[h] then
        TA.strataHosts[h] = nil
        h:SetFrameStrata(home:GetFrameStrata())
    end
end

-- A frame's SetFrameStrata resets every frame under it. Whoever sets one
-- outside a style pass (an icon's layer in a Dynamic reflow, an anchor raising
-- a frame over its target) calls this to put the texts under it back.
function TA.Restrata(frame)
    if not frame or next(TA.strataHosts) == nil then return end
    local own = frame._adTxtStrata
    if own then
        for _, h in pairs(own) do
            local s = TA.strataHosts[h]
            if s then h:SetFrameStrata(s) end
        end
        return
    end
    for h, s in pairs(TA.strataHosts) do
        local p = h:GetParent()
        while p and p ~= frame do p = p:GetParent() end
        if p then h:SetFrameStrata(s) end
    end
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

-- The texts riding our own items look again: after a layout pass (the
-- target's frame may be new) and when one of those frames shows or hides.
function TA.ReapplyItems()
    for fs, p in pairs(TA.live) do
        if p.kind == "item" then
            TA.Place(fs, p.owner, p.slot, p.kind, p.spec, p.point, p.rel, p.x, p.y, p.home)
        end
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
-- The editor's line, in the client's words: one whole line per case, the
-- frame or spell name filled in (NS.AT read late: a core-only load has no theme).
function TA.Describe(kind, spec)
    if not TA.Pinned(kind) then return "" end
    local AT = NS.AT
    local Tr = (AT and AT.Tr) or function(s) return s end
    local SA = NS.SpellAnchor
    if kind == "frame" then
        if type(spec) ~= "string" or spec == "" then return Tr("Type a frame name or pick one.") end
        if TA.Target(kind, spec) then return Tr("On %s."):format(spec) end
        return Tr("%s is not shown, so it sits on its own spot."):format(spec)
    end
    if kind == "item" then
        local _, id = TA.ItemSpec(spec)
        local rec = id and NS.Store and NS.Store.Get(id)
        if not rec then return Tr("Pick an icon or bar on screen.") end
        local name = rec.name or "?"
        if TA.Target(kind, spec) then return Tr("On %s."):format(name) end
        return Tr("%s is not shown, so it sits on its own spot."):format(name)
    end
    local p = SA and SA.Parse(spec)
    if not p then
        return Tr(kind == "cdm" and "Type a spell or a cooldown ID, or pick an icon." or "Type a spell or pick a button.")
    end
    if p.cid and kind ~= "cdm" then return Tr("A cooldown ID names a Cooldown Manager icon.") end
    local on = TA.Target(kind, spec)
    if p.cid then
        return (on and Tr("On the icon with cooldown ID %s.")
            or Tr("No icon with cooldown ID %s is shown, so it sits on its own spot.")):format(p.cid)
    end
    local nm = SA.NameOf(p.list[1]) or Tr("spell %s"):format(tostring(p.list[1]))
    if kind == "action" then
        return (on and Tr("On the action button with %s.")
            or Tr("No action button with %s is shown, so it sits on its own spot.")):format(nm)
    end
    return (on and Tr("On the Cooldown Manager icon of %s.")
        or Tr("No Cooldown Manager icon of %s is shown, so it sits on its own spot.")):format(nm)
end
