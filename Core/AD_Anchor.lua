-- Anchoring: bars, groups and free icons pin to a group, bar, free icon, layout,
-- named frame or the cursor; bars also to the target's nameplate, or by spell to
-- an action button or Cooldown Manager icon (Core\AD_SpellAnchor.lua).
-- An `anchor` section uses only: anchorEnabled, anchorTargetKind/Id/Frame,
-- anchorSrcPoint/DstPoint, anchorOffsetX/Y, anchorMatchWidth(Adjust), bars also
-- anchorMatchHeight(Adjust). A family's anchorTargetKind values are what it may pick.

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
local NO_ID = { frame = true, nameplate = true, mouse = true, action = true, cdm = true }
-- the kinds found by spell, whose spell ids sit in anchorTargetFrame
local SPELL_KIND = { action = true, cdm = true }
-- the kinds whose target is one of the game's frames: nothing of ours hooks it
local GAME_TARGET = { frame = true, action = true, cdm = true }

-- May this record pick that target kind? Its family's schema list answers, so
-- the pick list, the setter and the pin can never disagree.
local allowSets = {}   -- family -> { [kind] = true }
function Anchor.Allows(rec, kind)
    local fam = rec and Store.FamilyOf(rec)
    if not fam then return false end
    local set = allowSets[fam]
    if not set then
        set = {}
        local sec = NS.Schema and NS.Schema[fam] and NS.Schema[fam].anchor
        local def = sec and sec.fields and sec.fields.anchorTargetKind
        for _, v in ipairs((def and def.values) or {}) do set[v] = true end
        allowSets[fam] = set
    end
    return set[kind] == true
end

function Anchor.IsEnabled(rec)
    if rec == nil or R(rec, "anchorEnabled") ~= true then return false end
    -- A group member's cell places it: an anchor it kept from being free
    -- must not pull it out of the group.
    if rec.type == "icon" and rec.groupId ~= nil then return false end
    local kind = R(rec, "anchorTargetKind") or "group"
    -- A kind the family does not offer (an import from elsewhere) places free.
    if not Anchor.Allows(rec, kind) then return false end
    -- Enabled with nothing picked (target id 0 on a record kind) is a half
    -- state a stale save can carry. It places free, so it must read as not
    -- anchored everywhere.
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

local function IsSpellKind(rec)
    return SPELL_KIND[R(rec, "anchorTargetKind") or "group"] == true
end

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

-- The engine's free placement (registered too), for a spell pin whose target
-- leaves the screen between two rebuilds: the frame goes back to its own spot.
local freePlacer
function Anchor.SetFreePlacer(fn) freePlacer = fn end

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

-- The game names the plates it makes NamePlate1, NamePlate2 ... under
-- NamePlateDriverFrame.
local function IsPlateName(n)
    return n == "NamePlateDriverFrame" or n:match("^NamePlate%d+$") ~= nil
end

-- Why a named frame cannot be a target, or nil when it can. A frame pinned to
-- a secret position reads secret sizes itself (GetSize is secret whenever the
-- anchoring is), and our glows, drags and text scaling read them. A plate, or
-- anything inside one, can turn secret at any time, so it is refused by name
-- up the parents. A forbidden frame answers only IsForbidden, so that is asked
-- first, and every other read can be secret.
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
function Anchor.FrameProblem(t)
    if type(t) ~= "table" or not t.GetObjectType then return "missing" end
    local f, depth = t, 0
    while f ~= nil and depth < 32 do
        depth = depth + 1
        if f.IsForbidden then
            local fb = f:IsForbidden()
            if Secret(fb) or fb then return "forbidden" end
        end
        local n = f.GetName and f:GetName()
        if type(n) == "string" and not Secret(n) and IsPlateName(n) then return "plate" end
        if f == UIParent or f == WorldFrame then break end
        local p = f.GetParent and f:GetParent()
        if Secret(p) then return "secret" end
        f = p
    end
    if t.IsAnchoringSecret then
        local s = t:IsAnchoringSecret()
        if Secret(s) or s then return "secret" end
    end
    return nil
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
        if Anchor.FrameProblem(t) then return nil end
        -- an engine-owned frame's shown state can be secret
        local shown = t.IsShown and t:IsShown()
        if Secret(shown) or not shown then return nil end
        return t
    end
    if kind == "nameplate" then return Anchor.TargetPlate() end
    if kind == "mouse" then return EnsureMouseProxy() end
    -- the button or icon holding the spell now; nil while none is on screen
    if SPELL_KIND[kind] then
        local SA = NS.SpellAnchor
        return SA and SA.Resolve(kind, R(rec, "anchorTargetFrame")) or nil
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
            -- a spell pin shown later (a load condition) finds its button now
            if r and Anchor.IsEnabled(r) and IsSpellKind(r) then Anchor.PlaceSpellPin(r, self) end
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

-- A matched size on this frame's physical pixel grid, so its border stays sharp.
local function SnapSize(frame, v)
    local _, sh = GetPhysicalScreenSize()
    local es = frame:GetEffectiveScale()
    if type(sh) ~= "number" or type(es) ~= "number" or sh <= 0 or es <= 0 then return v end
    local ppu = sh / 768 * es
    return math.floor(v * ppu + 0.5) / ppu
end

-- A group's container padding on each side, which a match leaves out: the
-- match follows its icons' size and spacing. Negative padding lets the icons
-- overhang the frame, so the frame alone would come up short.
local function GroupPadding(rec)
    if (R(rec, "anchorTargetKind") or "group") ~= "group" then return 0 end
    local g = Store.Get(R(rec, "anchorTargetId") or 0)
    if not (g and g.type == "group") then return 0 end
    return tonumber(Store.Resolve(g, "arrangement", "containerPadding")) or 0
end

-- Match width / height take the target's size in this frame's own units, as
-- the two may sit in layouts of different scales. A standing bar swaps them:
-- its width runs along its long side.
local function MatchSize(rec, frame, target)
    local ts, fs = target:GetEffectiveScale(), frame:GetEffectiveScale()
    local k = (type(ts) == "number" and type(fs) == "number" and fs > 0) and ts / fs or 1
    local standing = rec.type == "bar" and Store.BarStanding ~= nil and Store.BarStanding(rec)
    local pad2 = 2 * GroupPadding(rec)
    if R(rec, "anchorMatchWidth") == true then
        local adj = R(rec, "anchorMatchWidthAdjust") or 0
        local v = standing and target:GetHeight() or target:GetWidth()
        if v and v > 0 then
            v = SnapSize(frame, math.max(1, (v - pad2) * k + adj))
            if standing then frame:SetHeight(v) else frame:SetWidth(v) end
        end
    end
    if R(rec, "anchorMatchHeight") == true then
        local adj = R(rec, "anchorMatchHeightAdjust") or 0
        local v = standing and target:GetWidth() or target:GetHeight()
        if v and v > 0 then
            v = SnapSize(frame, math.max(1, (v - pad2) * k + adj))
            if standing then frame:SetWidth(v) else frame:SetHeight(v) end
        end
    end
end

-- Every edge on a physical pixel, as the engine's SnapPlacement does for a free
-- frame: a whole-unit offset is a whole pixel only at UI scale 1, and a TOP or
-- CENTER point puts an odd-sized frame's sides between pixels. A bar between
-- pixels rounds its background and its fill to different edges, so a line of
-- the background shows. The anchor's offset takes the bottom-left's sub-pixel
-- remainder, measured from the typed spot (a re-snap after a size change must
-- not stack on the last shift); a secret or unresolved rect is left there.
local function SnapAnchored(rec, frame, target)
    local src, dst = R(rec, "anchorSrcPoint") or DEFAULT_SRC, R(rec, "anchorDstPoint") or DEFAULT_DST
    local x, y = R(rec, "anchorOffsetX") or 0, R(rec, "anchorOffsetY") or 0
    frame:SetPoint(src, target, dst, x, y)
    local left, bottom = Plain(frame:GetLeft()), Plain(frame:GetBottom())
    local s = Plain(frame:GetEffectiveScale())
    local _, physH = GetPhysicalScreenSize()
    if not (left and bottom and s and physH) or s <= 0 or physH <= 0 then return end
    local px = (768 / physH) / s
    local dx = left - math.floor(left / px + 0.5) * px
    local dy = bottom - math.floor(bottom / px + 0.5) * px
    if dx ~= 0 or dy ~= 0 then frame:SetPoint(src, target, dst, x - dx, y - dy) end
end

-- A match follows its target live (a group grows with its auras, a pips bar
-- with its maximum), not only at the next rebuild. Our own frames only: a
-- named frame is Blizzard's, and nothing of ours hooks it.
local matchers = {}   -- target frame -> { [source recId] = true }
local function FollowSize(rec, target)
    local set = matchers[target]
    if not set then
        set = {}
        matchers[target] = set
        target:HookScript("OnSizeChanged", function(t)
            for id in pairs(matchers[t]) do
                local r, f = Store.Get(id), sources[id]
                -- a source that moved to another target left a stale entry
                if r and f and f:IsShown() and Anchor.ResolveTarget(r) == t then
                    MatchSize(r, f, t)
                    SnapAnchored(r, f, t)
                end
            end
        end)
    end
    set[rec.id] = true
end

-- A spell pin draws over the button or icon it rides: the target's strata when
-- that is higher (not while the options window is open, which holds displays at
-- MEDIUM), and a level above the target's own layers.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
Anchor.ABOVE_TARGET = 10
local function RaiseOver(frame, target)
    local ts = Plain(target:GetFrameStrata())
    local fs = frame:GetFrameStrata()
    if ts and not Editing() and (STRATA_RANK[ts] or 0) > (STRATA_RANK[fs] or 0) then
        frame:SetFrameStrata(ts)
        fs = ts
    end
    local tl = Plain(target:GetFrameLevel())
    if ts == fs and type(tl) == "number" then
        local want = math.min(9000, tl + Anchor.ABOVE_TARGET)
        if (frame:GetFrameLevel() or 0) < want then frame:SetFrameLevel(want) end
    end
end

-- Places one source. Returns true when it anchored, false when the caller
-- should fall back to its own free placement.
function Anchor.Apply(rec, frame)
    if not (rec and frame) then return false end
    if Anchor.IsEnabled(rec) and IsPlateKind(rec) then
        UnpinMouse(frame)
        return ApplyPlate(rec, frame)
    end
    if Anchor.IsEnabled(rec) and IsMouseKind(rec) then
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
    local kind = R(rec, "anchorTargetKind") or "group"
    if SPELL_KIND[kind] then RaiseOver(frame, target) end
    if R(rec, "anchorMatchWidth") == true or R(rec, "anchorMatchHeight") == true then
        MatchSize(rec, frame, target)
        if not GAME_TARGET[kind] then FollowSize(rec, target) end
    end
    SnapAnchored(rec, frame, target)
    return true
end

-- A spell pin, placed: on its target, else back at its own spot.
function Anchor.PlaceSpellPin(rec, frame)
    if Anchor.Apply(rec, frame) then return true end
    if freePlacer then freePlacer(rec, frame) end
    return false
end

-- Every shown bar that rides a spell's button or icon looks again
-- (Core\AD_SpellAnchor.lua asks after a bar or Cooldown Manager change).
function Anchor.ReapplySpellPins()
    for id, frame in pairs(sources) do
        local rec = Store.Get(id)
        if rec and frame:IsShown() and Anchor.IsEnabled(rec) and IsSpellKind(rec) then
            Anchor.PlaceSpellPin(rec, frame)
        end
    end
end

-- The spell finder's events and hooks follow the pins that exist.
function Anchor.SyncSpellPins()
    local SA = NS.SpellAnchor
    if not (SA and SA.Sync) then return end
    local wantAction, wantCDM = false, false
    for id in pairs(sources) do
        local rec = Store.Get(id)
        if rec and Anchor.IsEnabled(rec) then
            local kind = R(rec, "anchorTargetKind") or "group"
            if kind == "action" then wantAction = true end
            if kind == "cdm" then wantCDM = true end
        end
    end
    SA.Sync(wantAction, wantCDM)
end

-- Post-pass, run once the engine has built every frame and registered each
-- source: a target may not exist yet while its source is built (a later
-- layout, or later in the same rebuild). A target that is itself anchored is
-- placed first, so a match reads its final size, not the one its own match
-- is about to change.
function Anchor.ApplyAll()
    local done = {}
    local function Place(id, frame)
        if done[id] then return end
        done[id] = true
        local rec = Store.Get(id)
        if not (rec and frame.IsShown and frame:IsShown()) then return end
        local tid = Anchor.IsEnabled(rec) and not NO_ID[R(rec, "anchorTargetKind") or "group"]
            and R(rec, "anchorTargetId")
        if tid and sources[tid] then Place(tid, sources[tid]) end
        Anchor.Apply(rec, frame)
    end
    for id, frame in pairs(sources) do Place(id, frame) end
    Anchor.SyncSpellPins()
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

-- A grouped icon is never a target: its group's cell places it.
-- A bar kind with no place on screen (a wheel opens at the cursor) is no target.
function Anchor.Placeless(rec)
    local B = NS.Bars
    local K = rec and rec.type == "bar" and B and B.KINDS and B.KINDS[rec.barKind]
    return type(K) == "table" and K.noHolder == true
end

function Anchor.TargetChoices(rec, kind)
    local out = {}
    if not (rec and Store.EachRecord) then return out end
    Store.EachRecord(function(id, other)
        if id ~= rec.id and other.type == kind
            and not (kind == "icon" and other.groupId ~= nil)
            and not Anchor.Placeless(other)
            and not Anchor.CreatesCycle(rec.id, other) then
            out[#out + 1] = { value = id,
                text = other.name or ((KIND_LABEL[kind] or "Record") .. " " .. id) }
        end
    end)
    table.sort(out, function(a, b) return (a.text or "") < (b.text or "") end)
    return out
end

-- One-pick target selection: an anchor is one choice, not enable, kind and
-- target on three rows. Every anchor panel lists and writes picks through
-- these, so no family can drift from another.

local PREFIX = { group = "Group", bar = "Bar", icon = "Icon", layout = "Layout" }
local PICK_ORDER = { "group", "bar", "icon", "layout" }
-- The picks that name no record, in list order. Only bars offer the plate: a
-- bar's runtime is guarded against a secret rect, and an icon's glows and
-- text scaling are not.
local SPECIAL_PICKS = {
    { value = "nameplate", text = "Target's nameplate" },
    { value = "mouse", text = "Mouse cursor" },
    { value = "action", text = "Action bar button (by spell)" },
    { value = "cdm", text = "Cooldown Manager icon (by spell)" },
}

-- everything this record may legally anchor to, in one flat list
function Anchor.PickList(rec)
    local items = { { value = "none", text = "None (free position)" } }
    if not rec then return items end
    for _, s in ipairs(SPECIAL_PICKS) do
        if Anchor.Allows(rec, s.value) then items[#items + 1] = { value = s.value, text = s.text } end
    end
    for _, kind in ipairs(PICK_ORDER) do
        if Anchor.Allows(rec, kind) then
            for _, it in ipairs(Anchor.TargetChoices(rec, kind)) do
                items[#items + 1] = {
                    value = kind .. ":" .. it.value,
                    text = (PREFIX[kind] or "?") .. ":  " .. (it.text or ""),
                }
            end
        end
    end
    if Anchor.Allows(rec, "frame") then
        items[#items + 1] = { value = "frame", text = "Named frame..." }
    end
    return items
end

function Anchor.PickGet(rec)
    if not (rec and Anchor.IsEnabled(rec)) then return "none" end
    local kind = R(rec, "anchorTargetKind") or "group"
    if NO_ID[kind] then return kind end
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
    if NO_ID[v] then
        if not Anchor.Allows(rec, v) then return end
        -- a frame name and a spell list share anchorTargetFrame: a switch
        -- between those kinds starts it empty
        local old = R(rec, "anchorTargetKind") or "group"
        if old ~= v and GAME_TARGET[old] and GAME_TARGET[v] then
            Store.SetOverride(rec, "anchor", "anchorTargetFrame", "")
        end
        Store.SetOverride(rec, "anchor", "anchorEnabled", true)
        Store.SetOverride(rec, "anchor", "anchorTargetKind", v)
        return
    end
    local kind, id = tostring(v):match("^(%a+):(%d+)$")
    if not kind or not PREFIX[kind] or not Anchor.Allows(rec, kind) then return end
    Store.SetOverride(rec, "anchor", "anchorEnabled", true)
    Store.SetOverride(rec, "anchor", "anchorTargetKind", kind)
    Store.SetOverride(rec, "anchor", "anchorTargetId", tonumber(id))
end

-- The Arc Auras frames Pick Frame can offer for rec (UI\AD_FramePicker.lua),
-- as frame -> { value, text } in PickList's words, for every target rec may
-- pick. rec's own frame and a target that would close a loop map to { why }
-- instead, so the picker stops there rather than walking on to the layout
-- behind. A grouped icon is left out: its walk goes on to its group.
function Anchor.PickFrames(rec)
    local map = {}
    if not (rec and Store.EachRecord) then return map end
    for _, kind in ipairs(PICK_ORDER) do
        local get = providers[kind]
        if get and Anchor.Allows(rec, kind) then
            Store.EachRecord(function(id, other)
                if other.type ~= kind or (kind == "icon" and other.groupId ~= nil) then return end
                local f = get(id)
                if not f then return end
                if id == rec.id then
                    map[f] = { why = "self" }
                elseif Anchor.CreatesCycle(rec.id, other) then
                    map[f] = { why = "loop" }
                else
                    map[f] = { value = kind .. ":" .. id,
                        text = PREFIX[kind] .. ":  " .. (other.name or ((KIND_LABEL[kind] or "Record") .. " " .. id)) }
                end
            end)
        end
    end
    return map
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

function Anchor.IsSpellPick(rec)
    return rec ~= nil and Anchor.IsEnabled(rec) and IsSpellKind(rec)
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
    if Anchor.IsSpellPick(rec) then
        local SA = NS.SpellAnchor
        local p = SA and SA.Parse(R(rec, "anchorTargetFrame"))
        if not p then return "No spell entered yet, so it stays at its own spot." end
        local nm = SA.NameOf(p.list[1]) or ("spell " .. p.list[1])
        local t = Anchor.ResolveTarget(rec)
        if R(rec, "anchorTargetKind") == "action" then
            if t then
                local n = t.GetName and t:GetName()
                if Secret(n) or type(n) ~= "string" then n = nil end
                return "On the action button holding " .. nm .. (n and (" (" .. n .. ")") or "") .. "."
            end
            return nm .. " is not on a shown action button now, so it stays at its own spot."
        end
        if t then return "On the Cooldown Manager icon for " .. nm .. "." end
        return nm .. " is not in your Cooldown Manager now, so it stays at its own spot."
    end
    if Anchor.IsFramePick(rec) then
        local n = R(rec, "anchorTargetFrame")
        if type(n) ~= "string" or n == "" then
            return "Named frame: no name entered yet, so it stays free."
        end
        local why = Anchor.FrameProblem(_G[n])
        if why == "missing" then return "No frame called " .. n .. " exists, so it stays free." end
        if why == "plate" then return n .. " is a nameplate, so it stays free." end
        if why then return "The game protects " .. n .. ", so it stays free." end
        if Anchor.ResolveTarget(rec) == nil then return n .. " is hidden now, so it stays free." end
        return "Anchored to the frame " .. n .. "."
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
