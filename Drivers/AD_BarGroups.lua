-- AD_BarGroups: the Bar Group, a group kind that lays its bars in a line.
-- It alone places a Bar Group's bars: the layout engine calls it as the "bar" kind and
-- for each member bar it draws, the bars runtime each time a bar's visibility is set.
-- Packing reads plain flags only (a bar's own hide, its cooldown running, its fade) and
-- moves our own frames, so it holds in combat. Aura bars keep their spot.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("AD_BarGroups") or C_Timer
local CreateFrame = NS.Perf and NS.Perf.Frames("BarGroups") or function(...) return CreateFrame(...) end

local BG = {}
NS.BarGroups = BG

BG.frames = {}     -- [groupId] = the group frame while the group is drawn
BG.editing = {}    -- [groupId] = drawn with the panel open (every bar in its own spot)
BG.sig = {}        -- [barId] = the last empty / busy / faded reading
BG.arrive = {}     -- [groupId] = bar ids in the order they came back (Joins the end)
BG.target = {}     -- [barId] = { x, y } where the bar goes in its group frame
BG.at = {}         -- [barId] = { x, y } where it is now, while it slides
BG.dirty = {}      -- [groupId] = true: re-pack on the next frame

local function Engine() return NS.LayoutEngine end
local function R(rec, f) return NS.Store.Resolve(rec, "barStack", f) end

local function Snap(v, rec)
    local E = Engine()
    return (E and E.Snap) and E.Snap(v, rec) or math.floor(v + 0.5)
end

-- The drawn Bar Group frame a bar sits in, if any.
function BG.FrameFor(rec)
    local g = rec and NS.Store.BarGroupOf(rec.id)
    return g and BG.frames[g.id] or nil
end

-- A bar in a Bar Group that is not drawn: the bar is not drawn either.
function BG.Blocks(rec)
    local g = rec and NS.Store.BarGroupOf(rec.id)
    return g ~= nil and BG.frames[g.id] == nil
end

-- A bar the cooldown family runs (busy = its cooldown, timer, totem or swing runs).
local function Busy(e)
    return e ~= nil and (e.busy or e.running or e.tbRunning or e.cbRunning) and true or false
end

-- Whether a member bar takes a spot in play. Not drawn: none. An aura bar's presence is
-- secret in combat, so it always keeps its spot. Else its own hide (at opacity 0), then
-- the group's Also count as empty.
function BG.Counts(group, rec)
    local E = Engine()
    local f = E and E.GetBarFrame(rec.id)
    if not (f and E.Shows(rec)) then return false end
    if rec.barKind == "aura" then return true end
    local e = NS.Bars and NS.Bars.EntryOf(rec.id)
    if not e then return true end
    if e.stateHidden and (NS.Store.Resolve(rec, "behavior", "hiddenAlpha") or 0) <= 0 then return false end
    local rule = R(group, "collapse")
    if rule == "ready" then return Busy(e) end
    if rule == "cooldown" then return not Busy(e) end
    if rule == "hidden" then
        local a = NS.Conditions and NS.Conditions.AlphaFor(rec) or 1
        if issecretvalue and issecretvalue(a) then return true end
        return a > 0
    end
    return true
end

-- One reading per bar: an edge re-packs its group only when it moved.
local function Reading(group, rec)
    local e = NS.Bars and NS.Bars.EntryOf(rec.id)
    local s = BG.Counts(group, rec) and 1 or 0
    if Busy(e) then s = s + 2 end
    return s
end

-- The bars in the order they line up: list order, or with Joins the end the order they
-- came back in (first-comers keep theirs, newcomers in list order).
local function Ordered(group, bars, counts)
    if R(group, "order") ~= "fcfs" or R(group, "collapse") == "none" then return bars end
    local list = BG.arrive[group.id] or {}
    local keep, has = {}, {}
    for _, id in ipairs(list) do
        if counts[id] then keep[#keep + 1] = id; has[id] = true end
    end
    for _, rec in ipairs(bars) do
        if counts[rec.id] and not has[rec.id] then keep[#keep + 1] = rec.id end
    end
    BG.arrive[group.id] = keep
    local byId, out = {}, {}
    for _, rec in ipairs(bars) do byId[rec.id] = rec end
    for _, id in ipairs(keep) do out[#out + 1] = byId[id] end
    for _, rec in ipairs(bars) do
        if not counts[rec.id] then out[#out + 1] = rec end
    end
    return out
end

-- Where every bar goes, in whole pixels: { [barId] = { x, y, shown } }, the box size and
-- the box's own shift (Shrink the group to fit keeps the bars' place on screen).
function BG.Plan(group, editMode)
    local E = Engine()
    local bars = NS.Store.BarsOf(group)
    local grow = R(group, "grow") or "down"
    local column = grow == "down" or grow == "up"
    local sp = Snap(R(group, "spacing") or 0, group)
    local pad = Snap(R(group, "padding") or 0, group)
    local packs = not editMode and R(group, "closeGaps") == true
    local counts, lens, cross = {}, {}, 0
    for _, rec in ipairs(bars) do
        local w, h = E.BarSize(rec)
        lens[rec.id] = column and h or w
        cross = math.max(cross, column and w or h)
        counts[rec.id] = (not packs) or BG.Counts(group, rec)
    end
    if packs then bars = Ordered(group, bars, counts) end
    -- the full line and the part that shows
    local full, block, nShown = 0, 0, 0
    for i, rec in ipairs(bars) do
        full = full + lens[rec.id] + (i > 1 and sp or 0)
        if counts[rec.id] then
            block = block + lens[rec.id] + (nShown > 0 and sp or 0)
            nShown = nShown + 1
        end
    end
    local align = packs and R(group, "align") or "start"
    local lead = 0
    if align == "center" then lead = Snap((full - block) / 2, group)
    elseif align == "end" then lead = full - block end
    local box, shift = full, 0
    if packs and R(group, "shrink") == true then
        -- the box hugs what shows; with nothing up it keeps one bar's room
        local first = bars[1]
        box = nShown > 0 and block or (first and lens[first.id] or 0)
        local d = lead + (box - full) / 2
        shift = Snap(d, group)
        lead = 0
    end
    local plan, pos = {}, lead
    for _, rec in ipairs(bars) do
        local len = lens[rec.id]
        if counts[rec.id] then
            local s = pos
            local x, y
            if grow == "up" then x, y = pad, -(pad + box - s - len)
            elseif grow == "right" then x, y = pad + s, -pad
            elseif grow == "left" then x, y = pad + box - s - len, -pad
            else x, y = pad, -(pad + s) end
            plan[rec.id] = { x = x, y = y, shown = true }
            pos = pos + len + sp
        else
            plan[rec.id] = { shown = false }
        end
    end
    local w = column and (cross + 2 * pad) or (box + 2 * pad)
    local h = column and (box + 2 * pad) or (cross + 2 * pad)
    -- the shift as the group's own offset (layout units, y up)
    local ox, oy = 0, 0
    if grow == "down" then oy = -shift
    elseif grow == "up" then oy = shift
    elseif grow == "right" then ox = shift
    else ox = -shift end
    return plan, math.max(1, w), math.max(1, h), ox, oy
end

-- The glide: one OnUpdate for every sliding bar, off once the last one lands.
local glider = CreateFrame("Frame")
glider:Hide()
local function Put(f, gf, x, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", gf, "TOPLEFT", x, y)
end
glider:SetScript("OnUpdate", function(self, dt)
    local any = false
    for id, at in pairs(BG.at) do
        local t = BG.target[id]
        local E = Engine()
        local f = E and E.GetBarFrame(id)
        local gf = f and f:GetParent()
        if not (t and f and gf) then
            BG.at[id] = nil
        else
            local k = 1 - math.exp(-(at.rate or 16) * dt)
            at.x = at.x + (t.x - at.x) * k
            at.y = at.y + (t.y - at.y) * k
            if math.abs(t.x - at.x) < 0.5 and math.abs(t.y - at.y) < 0.5 then
                Put(f, gf, t.x, t.y)
                BG.at[id] = nil
            else
                Put(f, gf, at.x, at.y)
                any = true
            end
        end
    end
    if not any then self:Hide() end
end)

-- Moves one bar to its spot: at once, or sliding from where it was if it was showing.
local function Move(group, rec, f, gf, p, slide)
    if not p.shown then
        f:Hide()
        BG.at[rec.id] = nil
        return
    end
    local was = BG.target[rec.id]
    local showing = f:IsShown()
    BG.target[rec.id] = { x = p.x, y = p.y }
    f:Show()
    if slide and was and showing and (was.x ~= p.x or was.y ~= p.y) then
        local at = BG.at[rec.id] or { x = was.x, y = was.y }
        at.rate = 3 / math.max(0.01, R(group, "slideTime") or 0.18)
        BG.at[rec.id] = at
        glider:Show()
        return
    end
    BG.at[rec.id] = nil
    Put(f, gf, p.x, p.y)
end

-- Lays the group out: its frame's size and spot, then every drawn bar.
function BG.Pack(group)
    local gf = BG.frames[group.id]
    if not gf then return end
    local E = Engine()
    local editMode = BG.editing[group.id] == true
    local plan, w, h, ox, oy = BG.Plan(group, editMode)
    gf:SetSize(w, h)
    if E.PlaceGroupRoot then E.PlaceGroupRoot(group, gf, ox, oy) end
    local slide = not editMode and R(group, "closeGaps") == true and R(group, "slide") == true
    for _, rec in ipairs(NS.Store.BarsOf(group)) do
        local f = E.GetBarFrame(rec.id)
        local p = plan[rec.id]
        if f and p and f:GetParent() == gf then Move(group, rec, f, gf, p, slide) end
        BG.sig[rec.id] = Reading(group, rec)
    end
    BG.dirty[group.id] = nil
end

-- The group kind: the engine sizes and spots the frame after place().
function BG.Place(group, gf, editMode)
    BG.frames[group.id] = gf
    if BG.editing[group.id] ~= editMode then BG.arrive[group.id] = nil end
    BG.editing[group.id] = editMode
    local plan, w, h = BG.Plan(group, editMode)
    gf:SetSize(w, h)
    for _, rec in ipairs(NS.Store.BarsOf(group)) do
        local p = plan[rec.id]
        if p and p.shown then BG.target[rec.id] = { x = p.x, y = p.y } end
    end
    BG.Mark(group)
end

function BG.Release(group)
    BG.frames[group.id] = nil
    BG.editing[group.id] = nil
    BG.arrive[group.id] = nil
    local E = Engine()
    for _, rec in ipairs(NS.Store.BarsOf(group)) do
        BG.target[rec.id], BG.at[rec.id], BG.sig[rec.id] = nil, nil, nil
        if E and E.ReleaseBar then E.ReleaseBar(rec.id) end
    end
end

-- The engine drew a member bar inside the group frame: it goes to its spot now, and the
-- whole group is laid out again once this frame's drawing is done.
function BG.PlaceMember(rec, f)
    local g = NS.Store.BarGroupOf(rec.id)
    local gf = g and BG.frames[g.id]
    if not gf then return end
    local t = BG.target[rec.id]
    Put(f, gf, t and t.x or 0, t and t.y or 0)
    BG.Mark(g)
end

-- every group marked since the last pass; the engine also runs it in its post-pass, so a
-- full draw lays its groups out in the same frame
local function Flush()
    BG.flushing = false
    for gid in pairs(BG.dirty) do
        local g = NS.Store.Get(gid)
        if g and BG.frames[gid] then BG.Pack(g) else BG.dirty[gid] = nil end
    end
end

BG.Flush = Flush

function BG.Mark(group)
    BG.dirty[group.id] = true
    if BG.flushing then return end
    BG.flushing = true
    C_Timer.After(0, Flush)
end

-- The bars runtime set a bar's visibility: a member whose reading moved re-packs its group.
function BG.Shown(entry)
    local rec = entry and entry.rec
    local g = rec and NS.Store.BarGroupOf(rec.id)
    if not (g and BG.frames[g.id]) or BG.editing[g.id] then return end
    local s = Reading(g, rec)
    if BG.sig[rec.id] ~= s then
        BG.sig[rec.id] = s
        BG.Mark(g)
    end
end

-- registered once both hosts exist (they load earlier)
if NS.Bars then NS.Bars.ShownHook = BG.Shown end
if NS.LayoutEngine and NS.LayoutEngine.RegisterGroupKind then
    NS.LayoutEngine.RegisterGroupKind("bar", { place = BG.Place, release = BG.Release })
end
