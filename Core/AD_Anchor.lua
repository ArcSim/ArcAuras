-- Anchoring: bars, groups and free icons pin to a group, bar, layout, named
-- frame or the cursor, and bars to the target's nameplate. An `anchor` section must use
-- these fields: anchorEnabled, anchorTargetKind/Id/Frame, anchorSrcPoint,
-- anchorDstPoint, anchorOffsetX/Y, anchorMatchWidth, anchorMatchWidthAdjust.

local ADDON, NS = ...
local Store = NS.Store

local Anchor = {}
NS.Anchor = Anchor

local providers = {}   -- kind -> function(id) -> frame|nil
local sources = {}     -- recId -> frame, the sources ApplyAll walks

local DEFAULT_SRC, DEFAULT_DST = "TOP", "BOTTOM"

function Anchor.RegisterProvider(kind, fn)
    providers[kind] = fn
end

local function R(rec, field)
    return Store.Resolve(rec, "anchor", field)
end

-- the kinds that name no record: nothing to look up by id
local NO_ID = { frame = true, nameplate = true, mouse = true }

function Anchor.IsEnabled(rec)
    if rec == nil or R(rec, "anchorEnabled") ~= true then return false end
    -- A group member's cell places it: an anchor it kept from being free
    -- must not pull it out of the group.
    if rec.type == "icon" and rec.groupId ~= nil then return false end
    -- Enabled with nothing picked (target id 0 on a record kind) is a half
    -- state a stale save can carry. It places free, so it must read as not
    -- anchored everywhere.
    local kind = R(rec, "anchorTargetKind") or "group"
    if not NO_ID[kind] and (R(rec, "anchorTargetId") or 0) == 0 then return false end
    return true
end

local function TargetRecord(rec)
    local kind = R(rec, "anchorTargetKind") or "group"
    if NO_ID[kind] then return nil end
    return Store.Get(R(rec, "anchorTargetId") or 0)
end

local function IsPlateKind(rec)
    return (R(rec, "anchorTargetKind") or "group") == "nameplate"
end

local function IsMouseKind(rec)
    return (R(rec, "anchorTargetKind") or "group") == "mouse"
end

-- the kinds that follow the cursor: groups, bars and free icons (a layout is
-- only ever a target)
local MOUSE_TYPES = { bar = true, group = true, icon = true }

-- a plain number, or nil when the game keeps it secret
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- the edit session, as the layout engine reports it (registered, so this
-- module never reaches back into the engine)
local editModeCheck
function Anchor.SetEditModeCheck(fn) editModeCheck = fn end
local function Editing() return editModeCheck ~= nil and editModeCheck() == true end

-- the nameplate the current target wears (a forbidden one is never ours)
function Anchor.TargetPlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if plate and not (plate.IsForbidden and plate:IsForbidden()) then return plate end
    return nil
end

-- Mouse cursor
local mouseProxy                 -- the 1x1 frame on the cursor
local mouseFollowers = {}        -- [frame] = true while it is pinned to it
local mouseTicking = false
local mouseLastX, mouseLastY

local function PlaceMouseProxy()
    local x, y = GetCursorPosition()
    if x == mouseLastX and y == mouseLastY then return end
    mouseLastX, mouseLastY = x, y
    local sc = UIParent:GetEffectiveScale()
    if not sc or sc <= 0 then sc = 1 end
    mouseProxy:ClearAllPoints()
    mouseProxy:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
end

-- runs only while some follower is on screen; the last one going stops it, and
-- a follower showing again restarts it (the OnShow hook in Register)
local function MouseTick()
    for fr in pairs(mouseFollowers) do
        if fr:IsVisible() then
            PlaceMouseProxy()
            return
        end
    end
    mouseTicking = false
    mouseProxy:SetScript("OnUpdate", nil)
end

local function ArmMouse()
    if mouseTicking or not mouseProxy then return end
    mouseTicking = true
    mouseLastX, mouseLastY = nil, nil
    PlaceMouseProxy()
    mouseProxy:SetScript("OnUpdate", MouseTick)
end

local function EnsureMouseProxy()
    if mouseProxy then return mouseProxy end
    mouseProxy = CreateFrame("Frame", nil, UIParent)
    mouseProxy:SetSize(1, 1)
    mouseProxy:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
    return mouseProxy
end

local function UnpinMouse(frame)
    if frame._adMousePin then
        frame._adMousePin = nil
        mouseFollowers[frame] = nil
    end
end

-- Pins one source to the proxy. Cursor coordinates are plain and only our own
-- frames move, so this works in combat. While the options window is open it
-- stays at its own spot instead, so the panel stays clickable. Returns true
-- when pinned.
local function ApplyMouse(rec, frame)
    if Editing() then
        UnpinMouse(frame)
        return false
    end
    EnsureMouseProxy()
    PlaceMouseProxy()
    frame:ClearAllPoints()
    frame:SetPoint(R(rec, "anchorSrcPoint") or DEFAULT_SRC, mouseProxy, "CENTER",
        R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0)
    frame._adMousePin = true
    mouseFollowers[frame] = true
    ArmMouse()
    return true
end

-- Stand-in nameplate for the bar editor's preview, as plain numbers

-- The plate's size in UIParent units (the real target plate's if not secret,
-- else the nameplate size setting, else the classic default) and where the
-- health bar sits in it: above the cast bar's room, as UpdateAnchors in
-- Blizzard_NamePlateUnitFrame lays it out. NamePlateSetupOptions is only read.
function Anchor.PlateShape()
    local w, h, k = 110, 45, 1
    local measured = false
    local se = Plain(UIParent:GetEffectiveScale())
    local plate = Anchor.TargetPlate()
    if plate and se and se > 0 then
        local pw, ph = Plain(plate:GetWidth()), Plain(plate:GetHeight())
        local pe = Plain(plate:GetEffectiveScale())
        if pw and ph and pe and pw > 0 and ph > 0 and pe > 0 then
            w, h, k = pw * pe / se, ph * pe / se, pe / se
            measured = true
        end
    end
    if not measured and C_NamePlate and C_NamePlate.GetNamePlateSize then
        local nw, nh = C_NamePlate.GetNamePlateSize()
        nw, nh = Plain(nw), Plain(nh)
        if nw and nh and nw > 0 and nh > 0 then w, h = nw, nh end
    end
    local o = type(NamePlateSetupOptions) == "table" and NamePlateSetupOptions or nil
    local function Opt(key, def)
        local v = o and Plain(o[key])
        return (type(v) == "number" and v >= 0) and v or def
    end
    return {
        w = w, h = h,
        hpBottom = (Opt("castBarHeight", 10) + Opt("castBarToHealthBarSpacing", 2)) * k,
        hpHeight = math.max(4, Opt("healthBarHeight", 10) * k),
        hpInset = Opt("insetWidth", 6) * k,
    }
end

-- the points and offsets a bar pins to the plate with (the live pin's own
-- defaults), so the preview places it exactly as the game will
function Anchor.PlatePoints(rec)
    return R(rec, "anchorSrcPoint") or DEFAULT_SRC, R(rec, "anchorDstPoint") or DEFAULT_DST,
        R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0
end

-- Walks the chain and refuses a loop. It follows every kind, since a loop can
-- mix them (bar -> group -> bar).
function Anchor.CreatesCycle(startId, targetRec)
    local cursor, guard = targetRec, 0
    while cursor and guard < 16 do
        guard = guard + 1
        if cursor.id == startId then return true end
        if Anchor.IsEnabled(cursor) then
            cursor = TargetRecord(cursor)
        else
            cursor = nil
        end
    end
    -- ran out of guard: treat a chain that deep as a loop rather than risk it
    return cursor ~= nil
end

-- the frame a source should pin to, or nil to fall back to free placement
function Anchor.ResolveTarget(rec)
    if not Anchor.IsEnabled(rec) then return nil end
    local kind = R(rec, "anchorTargetKind") or "group"

    if kind == "frame" then
        local name = R(rec, "anchorTargetFrame")
        if type(name) ~= "string" or name == "" then return nil end
        local t = _G[name]
        -- a forbidden frame would taint us the moment we anchor to it
        if type(t) == "table" and t.GetObjectType
            and not (t.IsForbidden and t:IsForbidden())
            and t.IsShown and t:IsShown() then
            return t
        end
        return nil
    end
    if kind == "nameplate" then return Anchor.TargetPlate() end
    if kind == "mouse" then
        if not MOUSE_TYPES[rec.type] then return nil end
        return EnsureMouseProxy()
    end

    local tid = R(rec, "anchorTargetId") or 0
    if tid == 0 or tid == rec.id then return nil end
    local trec = Store.Get(tid)
    if not trec then return nil end                  -- target was deleted
    if Anchor.CreatesCycle(rec.id, trec) then return nil end
    local get = providers[kind]
    if not get then return nil end
    local t = get(tid)
    if t and t.IsShown and t:IsShown() then return t end
    return nil
end

-- register a source for the post-pass. Called by whoever built the frame.
function Anchor.Register(rec, frame)
    if not (rec and frame) then return end
    sources[rec.id] = frame
    -- A cursor follower that was hidden (load conditions, visibility) pins
    -- itself or wakes the ticker as soon as it shows again.
    if not frame._adAnchorShowHooked then
        frame._adAnchorShowHooked = true
        frame:HookScript("OnShow", function(self)
            if self._adMousePin then
                ArmMouse()
                return
            end
            local r = Store.Get(self._adRecId)
            if r and Anchor.IsEnabled(r) and IsMouseKind(r) and not Editing() then
                Anchor.Apply(r, self)
            end
        end)
    end
end

function Anchor.Unregister(id)
    sources[id] = nil
end

function Anchor.ClearSources()
    for k in pairs(sources) do sources[k] = nil end
end

-- Nameplate watch, armed by the first nameplate pin.
local plateWatch = false
local function ReapplyPlates()
    for id, frame in pairs(sources) do
        local rec = Store.Get(id)
        if rec and Anchor.IsEnabled(rec) and IsPlateKind(rec) then
            Anchor.Apply(rec, frame)
        end
    end
end
local function ArmPlateWatch()
    if plateWatch or not (NS.Events and NS.Events.On) then return end
    plateWatch = true
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED" }) do
        -- An event this client does not know throws when registered.
        if (not (C_EventUtils and C_EventUtils.IsEventValid))
            or C_EventUtils.IsEventValid(ev) then
            NS.Events.On(ev, "adanchor_plate", function(event)
                if event == "NAME_PLATE_UNIT_REMOVED" then
                    -- the plate is still assigned while this fires: settle
                    -- on the next frame, when it is really gone
                    NS.Events.Coalesce("adanchor_plate", ReapplyPlates)
                else
                    ReapplyPlates()
                end
            end)
        end
    end
end

-- Pins a source to the target's nameplate, hidden when there is none or while
-- the options window is open (the plate moves with the camera, so the preview
-- shows a stand-in). Only our own frames move or hide, so it works in combat.
-- The plate's position can be secret (IsAnchoringSecret) and so can a frame
-- pinned to it: `_adPlatePin` tells drags, Match width and the bars runtime
-- not to do math on its rect, which would throw. Returns true when pinned.
local function ApplyPlate(rec, frame)
    ArmPlateWatch()
    frame._adPlatePin = nil
    local plate = (not Editing()) and Anchor.TargetPlate() or nil
    if not plate then
        if frame:IsShown() then
            frame._adPlateHid = true
            frame:Hide()
        end
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        R(rec, "anchorSrcPoint") or DEFAULT_SRC,
        plate,
        R(rec, "anchorDstPoint") or DEFAULT_DST,
        R(rec, "anchorOffsetX") or 0,
        R(rec, "anchorOffsetY") or 0)
    frame._adPlatePin = plate
    if frame._adPlateHid then
        frame._adPlateHid = nil
        frame:Show()
    end
    return true
end

-- Places one source. Returns true when it anchored, false when the caller
-- should fall back to its own free placement.
function Anchor.Apply(rec, frame)
    if not (rec and frame) then return false end
    if Anchor.IsEnabled(rec) and IsPlateKind(rec) then
        UnpinMouse(frame)
        return ApplyPlate(rec, frame)
    end
    if Anchor.IsEnabled(rec) and IsMouseKind(rec) and MOUSE_TYPES[rec.type] then
        frame._adPlatePin = nil
        if frame._adPlateHid then
            frame._adPlateHid = nil
            frame:Show()
        end
        return ApplyMouse(rec, frame)
    end
    -- anything else: this frame is on neither the cursor nor a nameplate
    UnpinMouse(frame)
    frame._adPlatePin = nil
    if frame._adPlateHid then
        frame._adPlateHid = nil
        frame:Show()
    end
    local target = Anchor.ResolveTarget(rec)
    if not target then return false end
    frame:ClearAllPoints()
    frame:SetPoint(
        R(rec, "anchorSrcPoint") or DEFAULT_SRC,
        target,
        R(rec, "anchorDstPoint") or DEFAULT_DST,
        R(rec, "anchorOffsetX") or 0,
        R(rec, "anchorOffsetY") or 0)
    if R(rec, "anchorMatchWidth") == true then
        -- A standing bar (taller than wide) matches the target's height, along
        -- its long side; matching the width would lay it flat again.
        local adj = R(rec, "anchorMatchWidthAdjust") or 0
        if rec.type == "bar" and Store.BarStanding and Store.BarStanding(rec) then
            local h = target.GetHeight and target:GetHeight()
            if h and h > 0 then
                frame:SetHeight(math.max(8, h + adj))
            end
        else
            local w = target.GetWidth and target:GetWidth()
            if w and w > 0 then
                frame:SetWidth(math.max(8, w + adj))
            end
        end
    end
    return true
end

-- Post-pass, run once the engine has built every frame and registered each
-- source: a target may not exist yet while its source is built (a later
-- layout, or later in the same rebuild).
function Anchor.ApplyAll()
    for id, frame in pairs(sources) do
        local rec = Store.Get(id)
        if rec and frame.IsShown and frame:IsShown() then
            Anchor.Apply(rec, frame)
        end
    end
end

-- Drag support: dragging an anchored thing edits its offsets, never its free
-- position, so it stays attached to its target.

local function PointXY(f, point)
    if not (f and f.GetLeft) then return nil end
    local l, b = Plain(f:GetLeft()), Plain(f:GetBottom())
    local w, h = Plain(f:GetWidth()), Plain(f:GetHeight())
    -- a secret rect (a nameplate, or anything pinned to one) has no point
    -- we may do math on
    if not (l and b and w and h) then return nil end
    local x = (point:find("LEFT") and l)
        or (point:find("RIGHT") and (l + w))
        or (l + w / 2)
    local y = (point:find("BOTTOM") and b)
        or (point:find("TOP") and (b + h))
        or (b + h / 2)
    return x, y
end
Anchor.PointXY = PointXY

function Anchor.SaveOffsets(rec, frame)
    -- A nameplate pick is placed with its offset sliders: the plate's rect
    -- can be secret, and the bar hides while this window is open.
    if IsPlateKind(rec) or (frame and frame._adPlatePin) then return false end
    -- the cursor: the offsets are typed; a drag (only possible while the
    -- window is open, when it sits at its own spot) moves that spot
    if IsMouseKind(rec) or (frame and frame._adMousePin) then return false end
    local target = Anchor.ResolveTarget(rec)
    if not target then return false end
    local sp = R(rec, "anchorSrcPoint") or DEFAULT_SRC
    local dp = R(rec, "anchorDstPoint") or DEFAULT_DST
    local sx, sy = PointXY(frame, sp)
    local tx, ty = PointXY(target, dp)
    if not (sx and tx) then return false end
    Store.SetOverride(rec, "anchor", "anchorOffsetX", math.floor(sx - tx + 0.5))
    Store.SetOverride(rec, "anchor", "anchorOffsetY", math.floor(sy - ty + 0.5))
    return true
end

-- Options support: one list builder, so every anchor dropdown offers the same
-- targets under the same legality checks (no self, no cycle).

local KIND_LABEL = { layout = "Layout", group = "Group", bar = "Bar", icon = "Icon" }

function Anchor.TargetChoices(rec, kind)
    local out = {}
    if not (rec and Store.EachRecord) then return out end
    Store.EachRecord(function(id, other)
        if id ~= rec.id and other.type == kind
            and not Anchor.CreatesCycle(rec.id, other) then
            out[#out + 1] = { value = id,
                text = other.name or ((KIND_LABEL[kind] or "Record") .. " " .. id) }
        end
    end)
    table.sort(out, function(a, b) return (a.text or "") < (b.text or "") end)
    return out
end

-- One-pick target selection: an anchor is one choice, not enable, kind and
-- target on three rows. The bar and group panels both use these, so they
-- cannot drift apart.

local PREFIX = { group = "Group", bar = "Bar", layout = "Layout" }
local PICK_ORDER = { "group", "bar", "layout" }

-- everything this record may legally anchor to, in one flat list
function Anchor.PickList(rec)
    local items = { { value = "none", text = "None (free position)" } }
    -- Bars only: a bar's runtime is guarded against a secret rect; a group's
    -- edit-time drop and snap math is not.
    if rec and rec.type == "bar" then
        items[#items + 1] = { value = "nameplate", text = "Target's nameplate" }
    end
    if rec and MOUSE_TYPES[rec.type] then
        items[#items + 1] = { value = "mouse", text = "Mouse cursor" }
    end
    for _, kind in ipairs(PICK_ORDER) do
        for _, it in ipairs(Anchor.TargetChoices(rec, kind)) do
            items[#items + 1] = {
                value = kind .. ":" .. it.value,
                text = (PREFIX[kind] or "?") .. ":  " .. (it.text or ""),
            }
        end
    end
    items[#items + 1] = { value = "frame", text = "Named frame..." }
    return items
end

function Anchor.PickGet(rec)
    if not (rec and Anchor.IsEnabled(rec)) then return "none" end
    local kind = R(rec, "anchorTargetKind") or "group"
    if kind == "frame" or kind == "nameplate" or kind == "mouse" then return kind end
    local id = R(rec, "anchorTargetId") or 0
    if id == 0 then return "none" end
    return kind .. ":" .. id
end

-- One setter writes all three fields, so a pick never lands half-applied.
function Anchor.PickSet(rec, v)
    if not rec then return end
    if v == nil or v == "none" then
        Store.SetOverride(rec, "anchor", "anchorEnabled", false)
        return
    end
    if v == "frame" or (v == "nameplate" and rec.type == "bar")
        or (v == "mouse" and MOUSE_TYPES[rec.type]) then
        Store.SetOverride(rec, "anchor", "anchorEnabled", true)
        Store.SetOverride(rec, "anchor", "anchorTargetKind", v)
        return
    end
    local kind, id = tostring(v):match("^(%a+):(%d+)$")
    if not kind or not PREFIX[kind] then return end
    Store.SetOverride(rec, "anchor", "anchorEnabled", true)
    Store.SetOverride(rec, "anchor", "anchorTargetKind", kind)
    Store.SetOverride(rec, "anchor", "anchorTargetId", tonumber(id))
end

function Anchor.IsFramePick(rec)
    return rec ~= nil and Anchor.IsEnabled(rec)
        and (R(rec, "anchorTargetKind") or "group") == "frame"
end

function Anchor.IsPlatePick(rec)
    return rec ~= nil and Anchor.IsEnabled(rec) and IsPlateKind(rec)
end

function Anchor.IsMousePick(rec)
    return rec ~= nil and Anchor.IsEnabled(rec) and IsMouseKind(rec)
end

-- Everything anchored to this record, sorted by name. Ids are unique across
-- record types, so the target id alone identifies the link.
function Anchor.DependentsOf(rec)
    local out = {}
    if not (rec and Store.EachRecord) then return out end
    Store.EachRecord(function(id, other)
        if id ~= rec.id and Anchor.IsEnabled(other)
            and not NO_ID[R(other, "anchorTargetKind") or "group"]
            and (R(other, "anchorTargetId") or 0) == rec.id then
            out[#out + 1] = other
        end
    end)
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- a one-line summary for the panel: what this is actually pinned to now
function Anchor.DescribePick(rec)
    if not (rec and Anchor.IsEnabled(rec)) then
        return "Not anchored - this uses its own position."
    end
    if Anchor.IsPlatePick(rec) then
        if Editing() then
            return "Pins to your target's nameplate. The preview above shows it on a stand-in; place it with the offsets."
        end
        if Anchor.TargetPlate() then
            return "Pinned to your target's nameplate. Place it with the offsets below."
        end
        return "Pins to your target's nameplate. Nothing targeted now: hidden while you play."
    end
    if Anchor.IsMousePick(rec) then
        if Editing() then
            return "Follows your mouse cursor while you play. While this window is open it sits at its own spot; set where it sits next to the cursor with My point and the offsets."
        end
        return "Follows your mouse cursor."
    end
    if Anchor.IsFramePick(rec) then
        local n = R(rec, "anchorTargetFrame")
        if type(n) ~= "string" or n == "" then
            return "Named frame: no name entered yet, so it stays free."
        end
        return (_G[n] ~= nil) and ("Anchored to the frame " .. n .. ".")
            or ("No frame called " .. n .. " exists, so it stays free.")
    end
    local t = Store.Get(R(rec, "anchorTargetId") or 0)
    if not t then return "That anchor target no longer exists, so it stays free." end
    return "Anchored to " .. (t.name or "it") .. "."
end

-- /arcui plate: what the nameplate pin sees on this client, including whether
-- the plate's position and width read secret. Returns the readout's lines.
function Anchor.PlateReport()
    local function Say(v)
        if issecretvalue and issecretvalue(v) then return "secret" end
        return tostring(v)
    end
    local out = {}
    local plate = Anchor.TargetPlate()
    out[#out + 1] = "target nameplate: " .. (plate and "found" or "none")
    if plate then
        out[#out + 1] = "  its position hidden by the game: "
            .. Say(plate.IsAnchoringSecret and plate:IsAnchoringSecret())
        out[#out + 1] = "  its width readable: " .. Say(Plain(plate:GetWidth()) ~= nil)
    end
    local n = 0
    for id, frame in pairs(sources) do
        local rec = Store.Get(id)
        if rec and Anchor.IsPlatePick(rec) then
            n = n + 1
            local state = (frame._adPlatePin and "pinned")
                or (frame:IsShown() and "at its own spot")
                or (Editing() and "hidden while the options window is open")
                or "hidden"
            out[#out + 1] = "  " .. (rec.name or ("bar " .. id)) .. ": " .. state
                .. ", position hidden " .. Say(frame.IsAnchoringSecret and frame:IsAnchoringSecret())
                .. ", width readable " .. Say(Plain(frame:GetWidth()) ~= nil)
        end
    end
    out[#out + 1] = "bars set to the target's nameplate: " .. n
    return out
end

function Anchor.KindChoices()
    return {
        { value = "group",  text = "Icon group" },
        { value = "bar",    text = "Another bar" },
        { value = "layout", text = "Layout" },
        { value = "frame",  text = "Named frame" },
    }
end
