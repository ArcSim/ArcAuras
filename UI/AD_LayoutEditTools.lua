-- AD_LayoutEditTools: the element side of Edit on screen. A press on an
-- element picks it and a drag moves it, snapping to the other elements and
-- the center point; handles size it; Anchor to... ties it to another; Ctrl
-- or Shift picks several. Every write goes through the engine's edit ops as
-- one undo step. LOS.Teardown ends all of it on every exit, twice safe.
local ADDON, NS = ...
local Options = NS.Options
local LOS = Options and Options.LayoutOnScreen
if not LOS then return end
local AT, Store = NS.AT, NS.Store
local COL, WHITE = AT.COL, AT.WHITE
local Tr = AT.Tr
local UIK = LOS.UI

local LT = { handles = {}, links = {}, overlays = {} }
Options.LayoutEditTools = LT
LOS.Tools = LT

-- Sizes are the board's px as UI units, snapped to whole physical pixels.
local GREEN = { 0.373, 0.827, 0.659 }   -- an anchor's link, its point and its target
local SNAP_PX = 6                        -- a drag snaps to a line this many physical pixels off
local START_PX = 3                       -- a press becomes a drag past this many
-- small solid squares; the grab reaches past them so they stay easy to catch
local HANDLE, HANDLE_GRAB = 6, 5
local DOT = 7
local DASH = 3
local TARGET_OUT = 5                     -- the target's outline: 4 off it, 1 wide
local HOVER_T = 2                        -- a target under the cursor: 3 off it, 2 thick
local TAG_H, TAG_LIFT = 18, 38           -- the snap tag, its top this far over the element
local READ_X, READ_Y = 8, 6              -- the readout off the element's bottom right
local GAP, PAD = 12, 12                  -- the strips' items and their padding
local STRIP_W, STRIP_H, MULTI_H, STRIP_UP = 1120, 52, 44, 20
local ROW2_H, CHIP_H, CHIP_GAP = 44, 24, 6   -- the single strip's anchoring row and its chips
local PINS_H, PIN_GAP = 44, 8                -- a pinning group's third row, the gap inside an entry
local NAMES_W = 420
local BANNER_W, BANNER_H, BANNER_DROP = 560, 36, 30
local MULTI_HINT = "Drag any of them to move them together. Arrows nudge them all."
local FX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1,
    BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
    BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
-- a handle: where it sits (y from the bottom), the sides it moves, the point
-- that stays put
local SPOTS = {
    TL = { fx = 0, fy = 1, l = true, t = true, fixed = "BOTTOMRIGHT" },
    T = { fx = 0.5, fy = 1, t = true, fixed = "BOTTOM" },
    TR = { fx = 1, fy = 1, r = true, t = true, fixed = "BOTTOMLEFT" },
    L = { fx = 0, fy = 0.5, l = true, fixed = "RIGHT" },
    R = { fx = 1, fy = 0.5, r = true, fixed = "LEFT" },
    BL = { fx = 0, fy = 0, l = true, b = true, fixed = "TOPRIGHT" },
    B = { fx = 0.5, fy = 0, b = true, fixed = "TOP" },
    BR = { fx = 1, fy = 0, r = true, b = true, fixed = "TOPLEFT" },
}
local SPOT_ALL = { "TL", "T", "TR", "L", "R", "BL", "B", "BR" }
local SPOT_GROUP = { "TL", "TR", "BL", "BR" }

local function Ops() return NS.EditOps end

local function Num(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

local function Round(v) return math.floor(v + 0.5) end

local function FullWidth(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    return math.ceil(w)
end

function LT.Busy() return LT.drag ~= nil or LT.pickFor ~= nil end

-- the cursor in UIParent units
function LT.Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale() or 1
    if not (x and y) or s <= 0 then return nil end
    return x / s, y / s
end

-- An element's rect in UIParent units: the edit ops' read, else the engine's.
function LT.Rect(id)
    local EO = Ops()
    if EO and EO.Rect then
        local l, b, w, h = EO.Rect(id)
        if type(l) == "table" then
            l, b, w, h = l.left or l[1], l.bottom or l[2], l.width or l[3], l.height or l[4]
        end
        if Num(l) and Num(b) and Num(w) and Num(h) then return { left = l, bottom = b, width = w, height = h } end
    end
    return LT.ctx and LT.ctx.byId[id] or nil
end

-- { w, h } for bars and free icons, { icon } for a group, nil without the ops
function LT.SizeOf(id)
    local EO = Ops()
    local s = EO and EO.Size and EO.Size(id)
    if type(s) ~= "table" then return nil end
    if Num(s.icon) then return { icon = s.icon } end
    local w, h = s.w or s[1], s.h or s[2]
    if Num(w) and Num(h) then return { w = w, h = h } end
    return nil
end

function LT.IsGroup(id)
    local EO = Ops()
    local k = EO and EO.Kind and EO.Kind(id)
    if not k then
        local rec = Store.Get(id)
        k = rec and rec.type
    end
    return k == "group"
end

-- The edit ops' sizes are UIParent units. step: one setting in them (the
-- layout's scale times the element's own); show: what a shown number counts
-- in, so W and H read as the panel's settings and a group's icon size in
-- pixels at 100%.
function LT.Units(id)
    local rec = Store.Get(id)
    local E = NS.LayoutEngine
    local k = (rec and E and E.ScaleOf and tonumber(E.ScaleOf(rec))) or 1
    local function Get(section, field)
        return Store.Resolve and tonumber(Store.Resolve(rec, section, field)) or nil
    end
    if not rec then return k, k end
    if rec.type == "bar" then
        local u = k * (Get("size", "scale") or 1)
        return u, u
    elseif rec.type == "icon" then
        local u = k * (Get("position", "iconScale") or 1)
        return u, u
    elseif rec.type == "group" and rec.groupKind ~= "reminder" then
        return k * (Get("arrangement", "iconWidth") or 36) / 36, k
    end
    return k, k
end

-- a size as the strip and the readout show it
function LT.SizeWords(id)
    local s = LT.SizeOf(id)
    if not s then return nil end
    local _, show = LT.Units(id)
    if show <= 0 then show = 1 end
    if s.icon then return Tr("Icon size %s"):format(Round(s.icon / show)), s end
    return Round(s.w / show) .. " x " .. Round(s.h / show), s
end

function LT.Name(id)
    local r = LT.ctx and LT.ctx.byId[id]
    local rec = Store.Get(id)
    return (r and r.name) or (rec and rec.name) or ""
end

-- the kind's words and colour, as the Overview's map shows them
function LT.KindOf(id)
    local r = LT.ctx and LT.ctx.byId[id]
    local OV = Options.LayoutOverview
    if OV and OV.KindOf then
        local text, c = OV.KindOf(r or { id = id })
        if text then return text, c or COL.dim end
    end
    return tostring((r and r.kind) or "Element"), COL.dim
end

function LT.AnchorInfo(id)
    local EO = Ops()
    local info = id ~= nil and EO and EO.AnchorInfo and EO.AnchorInfo(id)
    if type(info) ~= "table" or info.to == nil then return nil end
    return info
end

-- The press: picks at once (Ctrl or Shift adds or drops one, a plain press
-- on a picked one keeps the set), then the held mouse may become a drag of
-- the set. Waiting for an anchor's target, the press picks the target.
function LT.Press(f, button)
    if button ~= "LeftButton" or not LOS.open or InCombatLockdown() or LT.drag then return end
    local id = f and f.recId
    if id == nil then return end
    if LT.pickFor ~= nil then return LT.PickTarget(id) end
    -- an unanswered cross counts as Put it back
    LOS.PutBack()
    if not LOS.open then return end
    local cur, rest, has = LOS.Picked(), {}, false
    for _, x in ipairs(cur) do
        if x == id then has = true else rest[#rest + 1] = x end
    end
    if (IsControlKeyDown and IsControlKeyDown()) or IsShiftKeyDown() then
        if has then
            local more = {}
            for i = 2, #rest do more[#more + 1] = rest[i] end
            LOS.SetPicks(rest[1], more)
            return LOS.Redraw()
        end
        LOS.SetPicks(id, cur)
    elseif has then
        LOS.SetPicks(id, rest)
    else
        LOS.SetPicks(id, {})
    end
    -- a locked one anywhere in the set holds the whole set
    local x, y = LT.Cursor()
    local frozen = (x == nil) or Store.Locked(LOS.Layout())
    for _, pid in ipairs(LOS.Picked()) do
        if Store.Locked(Store.Get(pid)) then frozen = true end
    end
    LT.drag = { mode = "move", id = id, x0 = x, y0 = y, lid = LOS.layoutId, frozen = frozen }
    LT.Hold(true)
    LOS.Redraw()
end

-- What X and Y read for id: while a move drags it, what the drop will save
-- (the saved numbers plus the move in the layout's units, or screen units
-- when measured from the screen's middle); else the saved numbers.
function LT.Measure(id)
    local EO = Ops()
    local x, y
    if EO and EO.Measure then x, y = EO.Measure(id) end
    if not (Num(x) and Num(y)) then return nil end
    local d = LT.drag
    if d and d.mode == "move" and d.shown and d.id == id and d.dx then
        local k = LOS.GetScale(LOS.Layout() or {})
        local u = Store.UI()
        if not LT.AnchorInfo(id) and u and u.posFrom == "screen" then k = 1 end
        if k > 0 then x, y = x + d.dx / k, y + d.dy / k end
    end
    return x, y
end

-- a handle's press: one undo step from here to the drop
function LT.HandleDown(h, button)
    if button ~= "LeftButton" or not LOS.open or InCombatLockdown() or LT.drag or LT.pickFor ~= nil then return end
    local id = LOS.selId
    if id == nil or #LOS.more > 0 then return end
    LOS.PutBack()
    if not LOS.open then return end
    local s0, r0 = LT.SizeOf(id), LT.Rect(id)
    local x, y = LT.Cursor()
    if not (s0 and r0 and x) then return end
    LT.drag = { mode = "resize", id = id, spot = h.spot, x0 = x, y0 = y, size0 = s0, r0 = r0,
        lid = LOS.layoutId, step = LOS.Begin("resize") }
    UIK.ResizeCursor(true)
    LT.Hold(true)
    LOS.Redraw()
end

-- the frame whose OnUpdate runs only while the mouse is held
function LT.Hold(on)
    if not LT.driver then
        if not on then return end
        LT.driver = CreateFrame("Frame", nil, LOS.root)
    end
    LT.driver:SetScript("OnUpdate", on and LT.Tick or nil)
end

function LT.Tick()
    local d = LT.drag
    if not d then return LT.Hold(false) end
    if not LOS.open then return LT.Cancel() end
    -- a release the press's frame never heard still ends the drag
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return LT.Release() end
    local x, y = LT.Cursor()
    if not (x and d.x0) then return end
    if d.mode == "move" then return LT.MoveTo(d, x - d.x0, y - d.y0) end
    return LT.SizeTo(d, x - d.x0, y - d.y0)
end

-- The nearest line within thr of any of own, as { d, at, word }.
function LT.Best(own, cands, thr)
    local b
    for _, o in ipairs(own) do
        for _, c in ipairs(cands or {}) do
            local at = tonumber(c.at or c[1])
            if at then
                local dd = at - o
                if math.abs(dd) <= thr and (not b or math.abs(dd) < math.abs(b.d)) then
                    b = { d = dd, at = at, word = c.word or c[2] }
                end
            end
        end
    end
    return b
end

-- A move: the pressed element's edges and middles snap to the nearest line
-- (Alt holds them free); the set previews the move, nothing saved yet.
function LT.MoveTo(d, dx, dy)
    local EO = Ops()
    if d.frozen or not (EO and EO.Preview) then return end
    if not d.started then
        local px = START_PX * AT.Px(UIParent)
        if dx * dx + dy * dy < px * px then return end
        local picks = LOS.Picked()
        d.started = true
        d.ids = (EO.Movers and EO.Movers(picks)) or picks
        d.r0 = LT.Rect(d.id)
        d.lines = EO.SnapLines and EO.SnapLines(d.lid, picks)
    end
    local r, lines = d.r0, d.lines
    d.gx, d.gy, d.snapText = nil, nil, nil
    if r and type(lines) == "table" and not (IsAltKeyDown and IsAltKeyDown()) then
        local thr = SNAP_PX * AT.Px(UIParent)
        local l, b = r.left + dx, r.bottom + dy
        local bx = LT.Best({ l, l + r.width / 2, l + r.width }, lines.xs, thr)
        local by = LT.Best({ b, b + r.height / 2, b + r.height }, lines.ys, thr)
        local words = {}
        if bx then
            dx, d.gx = dx + bx.d, bx.at
            words[#words + 1] = bx.word
        end
        if by then
            dy, d.gy = dy + by.d, by.at
            words[#words + 1] = by.word
        end
        if #words > 0 then
            local both = (#words == 2) and Tr("%s and %s"):format(words[1], words[2]) or words[1]
            d.snapText = Tr("Lines up with %s"):format(both)
        end
    end
    if d.dx == dx and d.dy == dy and d.shown then return end
    -- a refused preview (a lock the press could not see) holds the drag
    if EO.Preview(d.ids, dx, dy) == false then
        d.frozen = true
        return LOS.Redraw()
    end
    d.dx, d.dy, d.shown = dx, dy, true
    LOS.Redraw()
end

-- A handle drag: the size the press had plus the cursor's travel (a group's
-- icon by its width), in whole settings. Each new setting is written once,
-- the opposite side or corner fixed.
function LT.SizeTo(d, dx, dy)
    local EO = Ops()
    local s0, r0, sp = d.size0, d.r0, SPOTS[d.spot]
    if not (EO and sp) then return end
    local u = LT.Units(d.id)
    if not (u and u > 0) then u = 1 end
    if s0.icon then
        if not EO.SetGroupIcon or r0.width <= 0 then return end
        local w1 = r0.width + (sp.l and -dx or dx)
        local n = math.max(1, Round(s0.icon * w1 / r0.width / u))
        if n == d.want then return end
        d.want = n
        if EO.SetGroupIcon(d.id, n * u, sp.fixed) ~= false then d.wrote = true end
    else
        if not EO.Resize or s0.w <= 0 or s0.h <= 0 or r0.width <= 0 or r0.height <= 0 then return end
        local kx, ky = r0.width / s0.w, r0.height / s0.h
        local w, h = s0.w, s0.h
        if sp.l then w = s0.w - dx / kx elseif sp.r then w = s0.w + dx / kx end
        if sp.t then h = s0.h + dy / ky elseif sp.b then h = s0.h - dy / ky end
        w, h = math.max(1, Round(w / u)), math.max(1, Round(h / u))
        if d.want and d.want[1] == w and d.want[2] == h then return end
        d.want = { w, h }
        if EO.Resize(d.id, w * u, h * u, sp.fixed) ~= false then d.wrote = true end
    end
    LOS.Redraw()
end

-- The drop: a move saves as one step, then the preview lets go; a handle
-- drag closes its step. A press that never moved only picked.
function LT.Release(_, button)
    if button ~= nil and button ~= "LeftButton" then return end
    local d = LT.drag
    if not d then return end
    LT.drag = nil
    LT.Hold(false)
    local EO = Ops()
    if d.mode == "move" then
        if d.started and d.shown and EO then
            if EO.Move then LOS.Change(EO.Move, d.ids, d.dx, d.dy) end
            if EO.EndPreview then EO.EndPreview() end
        end
    else
        if d.step then LOS.End("resize") end
        local over = false
        for _, h in ipairs(LT.handles) do
            if h:IsShown() and h.IsMouseOver and h:IsMouseOver() then over = true end
        end
        UIK.ResizeCursor(over)
    end
    if LOS.open then LOS.Redraw() end
end

-- A drag ended by an exit or Escape saves nothing: a move's preview goes,
-- a handle drag's written steps go back with one undo of its own step.
function LT.Cancel()
    local d = LT.drag
    if not d then return end
    LT.drag = nil
    LT.Hold(false)
    local EO = Ops()
    if d.mode == "move" then
        if d.started and d.shown and EO and EO.EndPreview then EO.EndPreview() end
        return
    end
    local kept = d.step and LOS.End("resize")
    UIK.ResizeCursor(false)
    if kept and EO and EO.Undo then EO.Undo(d.lid) end
end

-- Anchors

function LT.CanTarget(target)
    local EO = Ops()
    return LT.pickFor ~= nil and target ~= nil and EO ~= nil and EO.CanAnchor ~= nil
        and EO.CanAnchor(LT.pickFor, target) == true
end

function LT.StartPick()
    local EO = Ops()
    if LOS.selId == nil or #LOS.more > 0 or LT.drag or not (EO and EO.Anchor) or InCombatLockdown() then return end
    LOS.PutBack()
    LT.pickFor = LOS.selId
    LOS.Redraw()
end

function LT.CancelPick()
    LT.pickFor, LT.hoverId = nil, nil
end

-- the target clicked: anchored as one step, facing points; refused ones do nothing
function LT.PickTarget(target)
    local id, EO = LT.pickFor, Ops()
    if id == nil or not LOS.open or InCombatLockdown() or not LT.CanTarget(target) then return end
    LT.CancelPick()
    LOS.Change(EO.Anchor, id, target)
    LOS.SetPicks(id, {})
    LOS.Redraw()
end

-- Sides in words. src is the element's point, dst the target's; a line-up
-- adds a corner word to both: LEFT / RIGHT for Above and Below, TOP /
-- BOTTOM for Left of and Right of.
local SIDE_PTS = { above = { "BOTTOM", "TOP" }, below = { "TOP", "BOTTOM" }, left = { "RIGHT", "LEFT" },
    right = { "LEFT", "RIGHT" }, ontop = { "CENTER", "CENTER" } }
local ACROSS = { above = "h", below = "h", left = "v", right = "v" }
local LINE_WORD = { left = "LEFT", right = "RIGHT", top = "TOP", bottom = "BOTTOM" }
local SIDE_ORDER = { "above", "below", "left", "right", "ontop" }
local SIDE_WORD = { above = "Above", below = "Below", left = "Left of", right = "Right of", ontop = "On top" }
local LINE_LABEL = { left = "Left edges", middle = "Middles", right = "Right edges", top = "Tops", bottom = "Bottoms" }

-- the line-up a side can take: keys for its three chips, the middle second
function LT.LineUps(side)
    if ACROSS[side] == "h" then return { "left", "middle", "right" } end
    if ACROSS[side] == "v" then return { "top", "middle", "bottom" } end
    return {}
end

function LT.SidePoints(side, align)
    local p = SIDE_PTS[side]
    if not p then return nil end
    local w = LINE_WORD[align or ""]
    if not w then return p[1], p[2] end
    if ACROSS[side] == "h" and (align == "left" or align == "right") then return p[1] .. w, p[2] .. w end
    if ACROSS[side] == "v" and (align == "top" or align == "bottom") then return w .. p[1], w .. p[2] end
    return p[1], p[2]
end

-- a point as its up-down part and its left-right part
local function Split(pt)
    if pt == "CENTER" then return "", "" end
    local v = pt:match("^TOP") or pt:match("^BOTTOM") or ""
    return v, pt:sub(#v + 1)
end

-- the side and line-up a point pair means; nil for a pair no side makes
function LT.SideOf(src, dst)
    if type(src) ~= "string" or type(dst) ~= "string" then return nil end
    if src == "CENTER" and dst == "CENTER" then return "ontop", nil end
    local sv, sh = Split(src)
    local dv, dh = Split(dst)
    if sh == dh then
        local align = (sh == "LEFT" and "left") or (sh == "RIGHT" and "right") or (sh == "" and "middle") or nil
        if align and sv == "BOTTOM" and dv == "TOP" then return "above", align end
        if align and sv == "TOP" and dv == "BOTTOM" then return "below", align end
    end
    if sv == dv then
        local align = (sv == "TOP" and "top") or (sv == "BOTTOM" and "bottom") or (sv == "" and "middle") or nil
        if align and sh == "RIGHT" and dh == "LEFT" then return "left", align end
        if align and sh == "LEFT" and dh == "RIGHT" then return "right", align end
    end
    return nil
end

-- The offsets a side closes up to: the gap along its axis stays only when it
-- already faces that way, the other axis lines up at 0, On top sits at 0, 0.
function LT.CloseUp(side, x, y)
    if side == "above" then return 0, (y >= 0) and y or 0 end
    if side == "below" then return 0, (y <= 0) and y or 0 end
    if side == "right" then return (x >= 0) and x or 0, 0 end
    if side == "left" then return (x <= 0) and x or 0, 0 end
    return 0, 0
end

-- A side or a line-up clicked: the new points keep it in place, then it
-- closes up to that side, all one undo step. A side keeps the line-up when
-- its axis can, else Middles; a line-up keeps the side.
function LT.Sit(side, align)
    local id, EO = LOS.selId, Ops()
    local info = LT.AnchorInfo(id)
    if not (info and info.to ~= "other" and EO and EO.SetPoints and EO.Move) or InCombatLockdown() then return end
    local curSide, curAlign = LT.SideOf(info.src, info.dst)
    side = side or curSide
    if not SIDE_PTS[side] then return end
    if align == nil then
        align = "middle"
        for _, a in ipairs(LT.LineUps(side)) do
            if a == curAlign then align = a end
        end
    end
    local src, dst = LT.SidePoints(side, align)
    local mine = LOS.Begin("sit")
    if EO.SetPoints(id, src, dst) == true then
        local now = LT.AnchorInfo(id)
        local x, y = now and tonumber(now.x), now and tonumber(now.y)
        if x and y then
            local wx, wy = LT.CloseUp(side, x, y)
            -- anchor offsets count in the layout's units; the move takes UIParent's
            local E = NS.LayoutEngine
            local rec = Store.Get(id)
            local k = (rec and E and E.ScaleOf and tonumber(E.ScaleOf(rec))) or 1
            local dx, dy = wx - x, wy - y
            if dx ~= 0 or dy ~= 0 then EO.Move({ id }, dx * k, dy * k) end
        end
    end
    if mine then LOS.End("sit") end
    LOS.Redraw()
end

function LT.Free()
    local id, EO = LOS.selId, Ops()
    if id == nil or not (EO and EO.Free) or InCombatLockdown() then return end
    LOS.Change(EO.Free, id)
    LOS.Redraw()
end

-- A stepper: one setting, one undo step, the top left fixed. The ops round
-- to the nearest setting, so the step is a setting's size on screen.
function LT.Step(field, delta)
    local id, EO = LOS.selId, Ops()
    local s = id ~= nil and LT.SizeOf(id)
    if not (s and EO) or InCombatLockdown() then return end
    local u = LT.Units(id)
    if not (u and u > 0) then u = 1 end
    if field == "icon" then
        if s.icon and EO.SetGroupIcon then
            LOS.Change(EO.SetGroupIcon, id, math.max(u, s.icon + delta * u), "TOPLEFT")
        end
    elseif s.w and EO.Resize then
        local w, h = s.w, s.h
        if field == "w" then w = math.max(u, w + delta * u) else h = math.max(u, h + delta * u) end
        LOS.Change(EO.Resize, id, w, h, "TOPLEFT")
    end
    LOS.Redraw()
end

-- Keys and the background

-- arrows move the picked set, one step a press; false when nothing is picked
function LT.NudgePicked(dx, dy)
    if LOS.selId == nil then return false end
    if LT.drag then return true end
    local EO = Ops()
    if EO and EO.Move and not InCombatLockdown() then
        local picks = LOS.Picked()
        LOS.Change(EO.Move, (EO.Movers and EO.Movers(picks)) or picks, dx, dy)
        LOS.Redraw()
    end
    return true
end

-- a delete question, a drag, then an anchor pick, then the picks; false
-- when none was there
function LT.Escape()
    if LT.asking and LT.HideAsk() then return true end
    if LT.drag then
        LT.Cancel()
    elseif LT.pickFor ~= nil then
        LT.CancelPick()
    elseif LOS.selId ~= nil then
        LOS.SetPicks(nil, {})
    else
        return false
    end
    LOS.Redraw()
    return true
end

function LT.Unpick()
    LT.CancelPick()
    LOS.SetPicks(nil, {})
    LOS.Redraw()
end

-- a click on the layout's empty space: an anchor pick ends, else the picks go
function LT.Background()
    if not LOS.open or LT.drag then return end
    if LT.pickFor ~= nil then
        LT.CancelPick()
        LOS.Redraw()
    else
        LT.Unpick()
    end
end

-- Hover while waiting for a target: a dashed cyan outline on what it allows.
function LT.Hover(f, on)
    local id = f and f.recId
    if on and LT.CanTarget(id) then
        LT.hoverId = id
    elseif LT.hoverId == id then
        LT.hoverId = nil
    end
    LT.DrawHover()
end

function LT.HoverPoint(on)
    if on and LT.CanTarget("point") then
        LT.hoverId = "point"
    elseif LT.hoverId == "point" then
        LT.hoverId = nil
    end
    LT.DrawHover()
end

-- Drawing on the mode's root: everything in whole physical pixels off the
-- layout's centre, as the outlines are.

local function Overlay(kind, level)
    local f = CreateFrame(kind or "Frame", nil, LOS.root)
    f.lift = level
    f:Hide()
    LT.overlays[#LT.overlays + 1] = f
    return f
end

local function Fill(f, layer, col)
    local t = f:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    t:SetVertexColor(col[1], col[2], col[3], 1)
    return t
end

-- a square of col inside a 1-pixel edge of edge
local function Square(level, col, edge)
    local f = Overlay("Frame", level)
    f.edge = Fill(f, "BACKGROUND", edge)
    f.edge:SetAllPoints()
    f.inner = Fill(f, "ARTWORK", col)
    return f
end

local function Tag(level, fill)
    local f = Overlay("Frame", level)
    AT.Skin(f, fill, COL.arc)
    f:SetClampedToScreen(true)
    f.fs = UIK.Text(f, 11, COL.ink)
    f.fs:SetPoint("CENTER")
    return f
end

function LT.Build()
    if LT.over then return end
    -- the guides' and the link's holders span the screen, so they have a box
    -- of their own; their pieces are placed off the root like the rest
    LT.over = Overlay("Frame", 8)
    LT.over:SetAllPoints(UIParent)
    LT.guideX = Fill(LT.over, "OVERLAY", COL.arc)
    LT.guideY = Fill(LT.over, "OVERLAY", COL.arc)
    LT.guideX:SetAlpha(0.85)
    LT.guideY:SetAlpha(0.85)
    LT.link = Overlay("Frame", 8)
    LT.link:SetAllPoints(UIParent)
    LT.target = Overlay("Frame", 4)
    LT.dotOwn = Square(9, COL.arc, COL.bg)
    LT.dotTarget = Square(9, GREEN, COL.bg)
    LT.hov = Overlay("Frame", 9)
    LT.snapTag = Tag(21, COL.sel)
    LT.readout = Tag(21, COL.bg)
end

function LT.Handle(i)
    local h = LT.handles[i]
    if h then return h end
    h = Square(12, COL.arc, COL.bg)
    h:EnableMouse(true)
    h:SetHitRectInsets(-HANDLE_GRAB, -HANDLE_GRAB, -HANDLE_GRAB, -HANDLE_GRAB)
    h:SetScript("OnMouseDown", function(self, button) LT.HandleDown(self, button) end)
    h:SetScript("OnMouseUp", function(self, button) LT.Release(self, button) end)
    h:SetScript("OnEnter", function(self)
        self.inner:SetVertexColor(COL.ink[1], COL.ink[2], COL.ink[3], 1)
        if not LT.drag then UIK.ResizeCursor(true) end
    end)
    h:SetScript("OnLeave", function(self)
        self.inner:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        if not LT.drag then UIK.ResizeCursor(false) end
    end)
    LT.handles[i] = h
    return h
end

-- the region's box at whole pixels l, b (from the screen's bottom left), w x h
local function Place(region, ctx, l, b, w, h)
    local P = ctx.P
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", LOS.root, "CENTER", l * P - ctx.ox, b * P - ctx.oy)
    region:SetSize(w * P, h * P)
end

-- an element's rect in whole pixels: left, bottom, right, top
local function Px(ctx, r)
    local P = ctx.P
    local function S(v) return math.floor(v / P + 0.5) end
    return S(r.left), S(r.bottom), S(r.left + r.width), S(r.bottom + r.height)
end

local function Lift(f, ctx) f:SetFrameLevel(ctx.base + f.lift) end

function LT.Draw(ctx)
    LT.ctx = ctx
    LT.Build()
    if LT.pickFor ~= nil and not ctx.byId[LT.pickFor] then LT.CancelPick() end
    if LT.hoverId ~= nil and LT.hoverId ~= "point" and not ctx.byId[LT.hoverId] then LT.hoverId = nil end
    LT.DrawHandles(ctx)
    LT.DrawLink(ctx)
    LT.DrawDrag(ctx)
    LT.DrawHover()
    LT.DrawPins(ctx)
    LT.SyncBanner()
    LT.SyncStrips()
end

-- Pinned game frames: what the group's "Frames that move with it" rows hold.

-- the pins that name a frame, { i, pin } in the group's order; a read only
function LT.PinsOf(id)
    local P, rec = NS.Pins, id ~= nil and Store.Get(id)
    if not (P and rec and rec.type == "group" and type(rec.pins) == "table") then return {} end
    local n = (P.Count and P.Count(rec)) or #rec.pins
    local out = {}
    for i = 1, n do
        local pin = rec.pins[i]
        if type(pin) == "table" and type(pin.frame) == "string" and pin.frame ~= "" then
            out[#out + 1] = { i = i, pin = pin }
        end
    end
    return out
end

-- a pin's side as the panel words it
function LT.PinSide(pin)
    local P = NS.Pins
    local v = P and P.SideOf and P.SideOf(pin)
    for _, s in ipairs((P and P.SIDES) or {}) do
        if s.value == v then return s.text end
    end
    return "Custom points"
end

local PIN_FALLBACK = { pinned = { text = "Pinned", col = { 0.48, 0.85, 0.56 } },
    missing = { text = "Not there", col = COL.faint } }

-- what the pin is doing now, as the panel's word and colour; nil before a pass
function LT.PinWord(gid, i)
    local P = NS.Pins
    local w = P and P.Status and P.Status(gid, i)
    if not w then return nil end
    local words = Options.PIN_WORDS or PIN_FALLBACK
    return words[w] or PIN_FALLBACK[w]
end

-- a named game frame's rect in UIParent units while it is there and shown
function LT.FrameRect(name)
    local f = rawget(_G, name)
    if type(f) ~= "table" or not (f.IsVisible and f.GetLeft and f.GetEffectiveScale) or not f:IsVisible() then
        return nil
    end
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    local fs, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (Num(l) and Num(b) and Num(w) and Num(h) and Num(fs) and Num(us)) or us <= 0 then return nil end
    local k = fs / us
    return { left = l * k, bottom = b * k, width = w * k, height = h * k }
end

-- The picked group's pinned frames that are there and shown: a dim dashed
-- outline 2 off each and its name tag above, no mouse (they are the game's).
function LT.DrawPins(ctx)
    local id, n = LOS.selId, 0
    local list = (id ~= nil and #LOS.more == 0) and LT.PinsOf(id) or {}
    LT.pinBoxes = LT.pinBoxes or {}
    local P = ctx.P
    local function S(v) return math.floor(v / P + 0.5) end
    local o, th = S(3), S(14)
    for _, e in ipairs(list) do
        local r = LT.FrameRect(e.pin.frame)
        if r then
            n = n + 1
            local bx = LT.pinBoxes[n]
            if not bx then
                bx = Overlay("Frame", 4)
                bx.tag = Overlay("Frame", 10)
                bx.tag.bg = Fill(bx.tag, "BACKGROUND", COL.bg)
                bx.tag.bg:SetAllPoints()
                bx.tag.bg:SetAlpha(0.85)
                bx.tag.fs = UIK.Text(bx.tag, 11, COL.dim)
                bx.tag.fs:SetPoint("LEFT", 5, 0)
                LT.pinBoxes[n] = bx
            end
            local L, B, R, T = Px(ctx, r)
            local w, h = (R - L) + 2 * o, (T - B) + 2 * o
            Place(bx, ctx, L - o, B - o, w, h)
            UIK.Dashes(bx, w, h, P, COL.dim)
            Lift(bx, ctx)
            bx:Show()
            local tg = bx.tag
            tg.fs:SetText(e.pin.frame .. " (moves with it)")
            Place(tg, ctx, L, T + o, S(UIK.Width(tg.fs) + 10), th)
            Lift(tg, ctx)
            tg:Show()
        end
    end
    for i = n + 1, #LT.pinBoxes do
        LT.pinBoxes[i]:Hide()
        LT.pinBoxes[i].tag:Hide()
    end
end

-- one element picked, not waiting for a target, not locked: a group's four
-- corners (its icon size), else all eight
function LT.DrawHandles(ctx)
    local id = LOS.selId
    local r = id ~= nil and ctx.byId[id]
    local spots = {}
    if r and #LOS.more == 0 and LT.pickFor == nil and not Store.Locked(Store.Get(id)) and LT.SizeOf(id) then
        spots = LT.IsGroup(id) and SPOT_GROUP or SPOT_ALL
    end
    local P = ctx.P
    -- odd, so the square centres on the outline's own pixel
    local hs = math.max(5, math.floor(HANDLE / P + 0.5))
    if hs % 2 == 0 then hs = hs + 1 end
    local off = math.floor(hs / 2)
    local L, B, R, T
    if r then L, B, R, T = Px(ctx, r) end
    for i, key in ipairs(spots) do
        local h, sp = LT.Handle(i), SPOTS[key]
        h.spot = key
        local x, y = L + Round((R - L) * sp.fx), B + Round((T - B) * sp.fy)
        Place(h, ctx, x - off, y - off, hs, hs)
        h.inner:ClearAllPoints()
        h.inner:SetPoint("TOPLEFT", P, -P)
        h.inner:SetPoint("BOTTOMRIGHT", -P, P)
        Lift(h, ctx)
        h:Show()
    end
    for i = #spots + 1, #LT.handles do LT.handles[i]:Hide() end
end

-- the center point in UIParent units: the container's centre
function LT.PointAt(ctx)
    local E = NS.LayoutEngine
    local box = E and E.GetLayoutFrame and LOS.layoutId and E.GetLayoutFrame(LOS.layoutId)
    if box or not ctx.layout then return ctx.ox, ctx.oy end
    local px, py = LOS.Point(ctx.layout)
    return ctx.ox + px, ctx.oy + py
end

-- dashes along a whole-pixel line from (x, y), len pixels, from the link's pool
local function DashLine(ctx, n, x, y, len, horiz)
    local d = math.max(1, math.floor(DASH / ctx.P + 0.5))
    for k = 0, len - 1, 2 * d do
        n = n + 1
        local t = LT.links[n]
        if not t then
            t = Fill(LT.link, "OVERLAY", GREEN)
            LT.links[n] = t
        end
        local m = math.min(d, len - k)
        if horiz then Place(t, ctx, x + k, y, m, 1) else Place(t, ctx, x, y + k, 1, m) end
        t:Show()
    end
    return n
end

-- The picked element's anchor: a dashed green line along the target's row
-- then up its own column, a cyan dot on its point, a green one on the
-- target's, and the target's dashed green outline 4 off it.
function LT.DrawLink(ctx)
    local id = LOS.selId
    local info = (#LOS.more == 0 and LT.pickFor == nil) and LT.AnchorInfo(id) or nil
    local r = info and ctx.byId[id]
    local tr
    if r and FX[info.src] and FX[info.dst] then
        if info.to == "point" then
            local x, y = LT.PointAt(ctx)
            tr = { left = x, bottom = y, width = 0, height = 0 }
        elseif info.to ~= "other" then
            tr = ctx.byId[info.to]
        end
    end
    local n = 0
    if tr then
        local L, B, R, T = Px(ctx, r)
        local x1, y1 = L + Round((R - L) * FX[info.src]), B + Round((T - B) * FY[info.src])
        local tl, tb, trr, tt = Px(ctx, tr)
        local x2, y2 = tl + Round((trr - tl) * FX[info.dst]), tb + Round((tt - tb) * FY[info.dst])
        n = DashLine(ctx, n, math.min(x1, x2), y2, math.abs(x1 - x2), true)
        n = DashLine(ctx, n, x1, math.min(y1, y2), math.abs(y1 - y2), false)
        local ds = math.floor(DOT / ctx.P + 0.5)
        local off = math.floor(ds / 2)
        for _, dt in ipairs({ { LT.dotOwn, x1, y1 }, { LT.dotTarget, x2, y2 } }) do
            local f = dt[1]
            Place(f, ctx, dt[2] - off, dt[3] - off, ds, ds)
            f.inner:ClearAllPoints()
            f.inner:SetPoint("TOPLEFT", ctx.P, -ctx.P)
            f.inner:SetPoint("BOTTOMRIGHT", -ctx.P, ctx.P)
            Lift(f, ctx)
            f:Show()
        end
        Lift(LT.link, ctx)
        LT.link:Show()
        if info.to ~= "point" then
            local t = math.floor(TARGET_OUT / ctx.P + 0.5)
            local w, h = (trr - tl) + 2 * t, (tt - tb) + 2 * t
            Place(LT.target, ctx, tl - t, tb - t, w, h)
            UIK.Dashes(LT.target, w, h, ctx.P, GREEN)
            Lift(LT.target, ctx)
            LT.target:Show()
        else
            LT.target:Hide()
        end
    else
        LT.link:Hide()
        LT.dotOwn:Hide()
        LT.dotTarget:Hide()
        LT.target:Hide()
    end
    for i = n + 1, #LT.links do LT.links[i]:Hide() end
end

-- While a drag runs: a guide across the screen per snapped axis, the
-- "Lines up with" tag over the element and the readout off its bottom right.
function LT.DrawDrag(ctx)
    local d = LT.drag
    local r = d and ctx.byId[d.id]
    local P = ctx.P
    local function S(v) return math.floor(v / P + 0.5) end
    local moving = d and d.mode == "move" and d.started and d.shown
    local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    LT.guideX:SetShown(moving and d.gx ~= nil)
    if moving and d.gx then Place(LT.guideX, ctx, S(d.gx), 0, 1, S(H)) end
    LT.guideY:SetShown(moving and d.gy ~= nil)
    if moving and d.gy then Place(LT.guideY, ctx, 0, S(d.gy), S(W), 1) end
    Lift(LT.over, ctx)
    LT.over:SetShown(moving and (d.gx ~= nil or d.gy ~= nil))
    local L, B, R, T
    if r then L, B, R, T = Px(ctx, r) end
    local st = LT.snapTag
    if moving and r and d.snapText then
        st.fs:SetText(d.snapText)
        local h = S(TAG_H)
        Place(st, ctx, L, T + S(TAG_LIFT) - h, S(UIK.Width(st.fs) + 12), h)
        Lift(st, ctx)
        st:Show()
    else
        st:Hide()
    end
    local rd, text = LT.readout, nil
    if r and d.mode == "resize" then
        text = LT.SizeWords(d.id)
    elseif r and d.mode == "move" and not d.frozen then
        local x, y = LT.Measure(d.id)
        if x then text = "X " .. Round(x) .. "  Y " .. Round(y) end
    end
    if text then
        rd.fs:SetText(text)
        local h = S(TAG_H)
        Place(rd, ctx, R + S(READ_X), B - S(READ_Y) - h, S(UIK.Width(rd.fs) + 12), h)
        Lift(rd, ctx)
        rd:Show()
    else
        rd:Hide()
    end
end

-- 3 off the thing, 2 thick: the element's press frame is 3 off it already
function LT.DrawHover()
    local hv, ctx = LT.hov, LT.ctx
    if not (hv and ctx) then return end
    local id = LT.pickFor ~= nil and LT.hoverId or nil
    local anchor
    if id == "point" then
        anchor = LOS.marker
    elseif id ~= nil then
        anchor = ctx.frames[id]
    end
    if not (anchor and anchor:IsShown()) then return hv:Hide() end
    local P = ctx.P
    local extra = HOVER_T
    if id == "point" then extra = math.floor(3 / P + 0.5) + HOVER_T end
    local w = Round((anchor:GetWidth() or 0) / P) + 2 * extra
    local h = Round((anchor:GetHeight() or 0) / P) + 2 * extra
    hv:ClearAllPoints()
    hv:SetPoint("TOPLEFT", anchor, "TOPLEFT", -extra * P, extra * P)
    hv:SetSize(w * P, h * P)
    UIK.Dashes(hv, w, h, P, COL.arc, HOVER_T)
    Lift(hv, ctx)
    hv:Show()
end

-- Chrome: the banner and the bottom strips, panel pieces at the window's
-- size and on the pixel grid.

function LT.SyncBanner()
    local id, tb = LT.pickFor, LOS.toolbar
    if id == nil or not (LOS.open and tb) then
        if LT.banner then LT.banner:Hide() end
        return
    end
    local bn = LT.banner
    if not bn then
        bn = CreateFrame("Frame", nil, UIParent)
        bn:SetFrameStrata("FULLSCREEN_DIALOG")
        AT.Skin(bn, COL.sel, COL.arc)
        bn.fs = UIK.Text(bn, 14, COL.ink)
        bn.fs:SetPoint("CENTER")
        LT.banner = bn
    end
    bn.fs:SetText(Tr("Click what %s should anchor to. Esc cancels."):format(LT.Name(id)))
    bn:SetScale(tb:GetScale() or 1)
    local P = AT.Px(bn)
    local function S(v) return math.floor(v / P + 0.5) end
    bn:SetSize(S(math.max(BANNER_W, UIK.Width(bn.fs) + 30)) * P, S(BANNER_H) * P)
    bn:ClearAllPoints()
    bn:SetPoint("TOP", tb, "BOTTOM", 0, -BANNER_DROP)
    AT.SnapWindow(bn)
    bn:Show()
end

local function Text(parent, size, col, words)
    local fs = UIK.Text(parent, size, col)
    if words then fs:SetText(Tr(words)) end
    return fs
end

local function Box(parent)
    local b = CreateFrame("Frame", nil, parent)
    AT.Skin(b, COL.well, COL.line2)
    b.fs = UIK.Text(b, 13, COL.ink)
    b.fs:SetPoint("CENTER")
    return b
end

local function Small(parent, glyph, onClick)
    local b = AT.MakeSmallButton(parent, glyph, 20)
    b.fs:SetFont(AT.FONT, 13, "")
    b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    b:SetScript("OnClick", onClick)
    return b
end

local function Rule(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    return t
end

-- A lit chip wears the selected look, kept through the button's own hover;
-- an unlit one the theme's small button with dim words. on nil repaints.
function LT.PaintChip(b, on)
    if on ~= nil then
        b._on = on == true
        if not b._on then
            b:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
            b:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
        end
    end
    if b._on then
        b:SetBackdropColor(COL.sel[1], COL.sel[2], COL.sel[3], 1)
        b:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        b.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    else
        b.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    end
end

local function Chip(parent, words, onClick)
    local b = AT.MakeSmallButton(parent, words)
    b.fs:SetFont(AT.FONT, 13, "")
    b:SetScript("OnClick", onClick)
    b:HookScript("OnEnter", function(self) LT.PaintChip(self) end)
    b:HookScript("OnLeave", function(self) LT.PaintChip(self) end)
    LT.PaintChip(b, false)
    return b
end

local function Chrome()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    AT.Skin(f, COL.bg, COL.arc)
    f:Hide()
    return f
end

function LT.BuildStrips()
    if LT.strip then return end
    local st = Chrome()
    LT.strip = st
    st.swatch = CreateFrame("Frame", nil, st)
    AT.Skin(st.swatch, COL.dim, { 0, 0, 0 })
    st.name = Text(st, 15, COL.ink)
    st.kind = CreateFrame("Frame", nil, st)
    AT.Skin(st.kind, { 0, 0, 0, 0 }, COL.line2)
    st.kind.fs = Text(st.kind, 11, COL.dim)
    st.kind.fs:SetPoint("CENTER")
    st.rules = { Rule(st), Rule(st), Rule(st) }
    st.hair = Rule(st)
    st.from = Text(st, 14, COL.dim)
    st.xL, st.xBox = Text(st, 14, COL.faint, "X"), Box(st)
    st.yL, st.yBox = Text(st, 14, COL.faint, "Y"), Box(st)
    st.icL = Text(st, 14, COL.dim, "Icon size")
    st.icMinus = Small(st, "-", function() LT.Step("icon", -1) end)
    st.icBox = Box(st)
    st.icPlus = Small(st, "+", function() LT.Step("icon", 1) end)
    st.wL = Text(st, 14, COL.dim, "W")
    st.wMinus = Small(st, "-", function() LT.Step("w", -1) end)
    st.wBox = Box(st)
    st.wPlus = Small(st, "+", function() LT.Step("w", 1) end)
    st.hL = Text(st, 14, COL.dim, "H")
    st.hMinus = Small(st, "-", function() LT.Step("h", -1) end)
    st.hBox = Box(st)
    st.hPlus = Small(st, "+", function() LT.Step("h", 1) end)
    -- Delete is quiet and set apart from Edit by a rule: the one that destroys
    st.del = LT.DeleteButton(st, function() LT.DeleteOne() end)
    st.delRule = Rule(st)
    st.edit = UIK.Button(st, "Edit", 28, 14, function() LOS.Edit(LOS.selId) end)
    st.close = UIK.Square(st, "x", function() LT.Unpick() end)
    -- row 2: the anchoring in words
    st.sits = Text(st, 14, COL.dim, "Sits")
    st.sides = {}
    for i, side in ipairs(SIDE_ORDER) do
        st.sides[i] = Chip(st, SIDE_WORD[side], function() LT.Sit(side, nil) end)
        st.sides[i].side = side
    end
    st.target = Text(st, 14, COL.ink)
    st.custom = Text(st, 14, COL.faint, "by its own points (Position > Anchor)")
    st.lined = Text(st, 14, COL.dim, "Lined up by")
    st.lines = {}
    for i = 1, 3 do
        st.lines[i] = Chip(st, "", function(self) LT.Sit(nil, self.align) end)
    end
    st.other = Text(st, 14, COL.dim)
    st.freeL = Text(st, 14, COL.faint, "Free in the layout")
    st.free = (AT.MakeQuietButton or AT.MakeSmallButton)(st, "Free it")
    st.free.fs:SetFont(AT.FONT, 13, "")
    st.free:SetScript("OnClick", function() LT.Free() end)
    st.anchor = UIK.Button(st, "Anchor to...", 28, 14, function() LT.StartPick() end)
    -- row 3, a group with pinned frames only: each frame, its side, its word
    st.hair2 = Rule(st)
    st.movesL = Text(st, 14, COL.dim, "Moves with it")
    st.pinRows = {}
    for i = 1, (NS.Pins and NS.Pins.MAX) or 4 do
        st.pinRows[i] = { name = Text(st, 14, COL.ink), side = Text(st, 14, COL.dim), word = Text(st, 13, COL.faint),
            rule = Rule(st) }
    end
    st.more = Text(st, 14, COL.faint)
    st.editFrames = (AT.MakeQuietButton or AT.MakeSmallButton)(st, "Edit frames")
    st.editFrames.fs:SetFont(AT.FONT, 13, "")
    st.editFrames:SetScript("OnClick", function() LT.EditFrames(LOS.selId) end)
    st.parts = { st.swatch, st.name, st.kind, st.rules[1], st.rules[2], st.rules[3], st.hair, st.from, st.xL,
        st.xBox, st.yL, st.yBox, st.icL, st.icMinus, st.icBox, st.icPlus, st.wL, st.wMinus, st.wBox, st.wPlus,
        st.hL, st.hMinus, st.hBox, st.hPlus, st.edit, st.close, st.sits, st.target, st.custom, st.lined,
        st.other, st.freeL, st.free, st.anchor, st.hair2, st.movesL, st.more, st.editFrames, st.del, st.delRule }
    for _, b in ipairs(st.sides) do st.parts[#st.parts + 1] = b end
    for _, b in ipairs(st.lines) do st.parts[#st.parts + 1] = b end
    for _, e in ipairs(st.pinRows) do
        for _, k in ipairs({ "name", "side", "word", "rule" }) do st.parts[#st.parts + 1] = e[k] end
    end

    local mt = Chrome()
    LT.multi = mt
    mt.count = Text(mt, 15, COL.ink)
    mt.names = Text(mt, 14, COL.dim)
    if mt.names.SetWordWrap then mt.names:SetWordWrap(false) end
    mt.rule = Rule(mt)
    mt.hint = Text(mt, 13, COL.faint, MULTI_HINT)
    mt.del = LT.DeleteButton(mt, function() LT.DeleteMany() end)
    mt.close = UIK.Square(mt, "x", function() LT.Unpick() end)
end

-- Lays items left to right from x pixels, centred on a band H tall whose top
-- is top pixels down the strip; each item { region, w, h, text, gapAfter } in
-- pixels, gap apart unless it says its own. A text item sits on the band's
-- middle line; every box lands on a whole pixel.
local function Flow(parent, items, x, gap, H, P, top)
    top = top or 0
    for _, it in ipairs(items) do
        local rg, w, h = it[1], it[2], it[3]
        rg:ClearAllPoints()
        if it[4] then
            rg:SetPoint("LEFT", parent, "TOPLEFT", x * P, -(top + H / 2) * P)
        else
            rg:SetPoint("TOPLEFT", parent, "TOPLEFT", x * P, -(top + math.floor((H - h) / 2)) * P)
            rg:SetSize(w * P, h * P)
        end
        rg:Show()
        x = x + w + (it[5] or gap)
    end
    return x
end

local function Span(items, gap)
    local w = 0
    for i, it in ipairs(items) do
        w = w + it[2]
        if i < #items then w = w + (it[5] or gap) end
    end
    return w
end

-- Lays a strip at scale s by lay(P) (it returns the width), then fits it on
-- the screen and puts it at the bottom on the pixel grid.
local function PlaceStrip(f, lay)
    f:SetScale(LOS.ChromeScale(STRIP_W))
    local w = lay(AT.Px(f))
    local s = LOS.ChromeScale(w)
    if math.abs(s - (f:GetScale() or 1)) > 1e-6 then
        f:SetScale(s)
        lay(AT.Px(f))
    end
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, STRIP_UP)
    AT.SnapWindow(f)
    f:Show()
end

function LT.SyncStrips()
    local picks = LOS.Picked()
    local idle = not LOS.open or LT.pickFor ~= nil
    if not idle and #picks == 1 then
        LT.LayStrip(picks[1])
    elseif LT.strip then
        LT.strip:Hide()
    end
    if not idle and #picks > 1 then
        LT.LayMulti(picks)
    elseif LT.multi then
        LT.multi:Hide()
    end
end

-- One picked, two rows in every state so it never jumps. Row 1: swatch,
-- name, kind; where X and Y count from and their values; its size; Edit and
-- x on the right. Row 2, under a hairline: its anchoring in words (free, a
-- side and a line-up, its own points, or a frame outside the layout), then
-- Free it and Anchor to... on the right.
function LT.LayStrip(id)
    LT.BuildStrips()
    local st, EO = LT.strip, Ops()
    local text, color = LT.KindOf(id)
    st.swatch:SetBackdropColor(color[1], color[2], color[3], 1)
    st.name:SetText(LT.Name(id))
    st.kind.fs:SetText(Tr(text))
    local info = LT.AnchorInfo(id)
    local u = Store.UI()
    local from = "From the center point"
    if info then
        from = "From its anchor"
    elseif u and u.posFrom == "screen" then
        from = "From the middle of your screen"
    end
    st.from:SetText(Tr(from))
    local mx, my = LT.Measure(id)
    st.xBox.fs:SetText(mx and tostring(Round(mx)) or "")
    st.yBox.fs:SetText(my and tostring(Round(my)) or "")
    local size = LT.SizeOf(id)
    local _, show = LT.Units(id)
    if not (show and show > 0) then show = 1 end
    local canAnchor = EO ~= nil and EO.Anchor ~= nil
    local pins = LT.PinsOf(id)
    -- row 2's state: free, a side, its own points (custom) or outside
    local side, align
    if info and info.to ~= "other" then
        side, align = LT.SideOf(info.src, info.dst)
        -- a name as named; the center point in the client's words
        local word = (info.to == "point") and Tr("the center point") or (info.name or LT.Name(info.to))
        st.target:SetText(side and word or Tr("on %s"):format(word))
        for _, b in ipairs(st.sides) do LT.PaintChip(b, b.side == side) end
        for i, a in ipairs(LT.LineUps(side)) do
            st.lines[i].align = a
            st.lines[i].fs:SetText(Tr(LINE_LABEL[a]))
            LT.PaintChip(st.lines[i], a == align)
        end
    elseif info then
        st.other:SetText(Tr("Anchored to %s"):format(info.name or Tr("another frame")))
    end
    PlaceStrip(st, function(P)
        local function S(v) return math.floor(v / P + 0.5) end
        local H, H2, gap, cg = S(STRIP_H), S(ROW2_H), S(GAP), S(CHIP_GAP)
        local ruleH, ruleH2 = H - 2 * S(PAD - 3), H2 - 2 * S(PAD - 3)
        local items, row2 = {}, {}
        local function add(rg, w, h) items[#items + 1] = { rg, w, h } end
        local function words(fs) items[#items + 1] = { fs, S(UIK.Width(fs)), nil, true } end
        local function box(b, w) add(b, S(w), S(22)) end
        local function stepper(b) add(b, S(20), S(22)) end
        local function say(fs) row2[#row2 + 1] = { fs, S(UIK.Width(fs)), nil, true } end
        local function chip(b, last)
            row2[#row2 + 1] = { b, S(UIK.Width(b.fs) + 20), S(CHIP_H), nil, (not last) and cg or nil }
        end
        for _, p in ipairs(st.parts) do p:Hide() end
        add(st.swatch, S(12), S(12))
        words(st.name)
        add(st.kind, S(UIK.Width(st.kind.fs) + 12), S(15))
        add(st.rules[1], 1, ruleH)
        words(st.from)
        words(st.xL)
        box(st.xBox, 46)
        words(st.yL)
        box(st.yBox, 46)
        if size and size.icon then
            st.icBox.fs:SetText(tostring(Round(size.icon / show)))
            add(st.rules[2], 1, ruleH)
            words(st.icL)
            stepper(st.icMinus)
            box(st.icBox, 34)
            stepper(st.icPlus)
        elseif size then
            st.wBox.fs:SetText(tostring(Round(size.w / show)))
            st.hBox.fs:SetText(tostring(Round(size.h / show)))
            add(st.rules[2], 1, ruleH)
            words(st.wL)
            stepper(st.wMinus)
            box(st.wBox, 38)
            stepper(st.wPlus)
            words(st.hL)
            stepper(st.hMinus)
            box(st.hBox, 34)
            stepper(st.hPlus)
        end
        -- it names what it deletes, as the panel's Delete buttons do
        st.del.fs:SetText(Tr(Options.DeleteLabel and Options.DeleteLabel(Store.Get(id)) or "Delete"))
        LT.PaintDelete(st.del, { id })
        local right = { { st.del, S(UIK.Width(st.del.fs) + 26), S(28) }, { st.delRule, 1, ruleH },
            { st.edit, S(UIK.Width(st.edit.fs) + 30), S(28) }, { st.close, S(26), S(26) } }
        if info and info.to ~= "other" then
            say(st.sits)
            for i, b in ipairs(st.sides) do chip(b, i == #st.sides) end
            say(st.target)
            if not side then
                say(st.custom)
            elseif side ~= "ontop" then
                row2[#row2 + 1] = { st.rules[3], 1, ruleH2 }
                say(st.lined)
                for i = 1, 3 do chip(st.lines[i], i == 3) end
            end
        elseif info then
            say(st.other)
        else
            say(st.freeL)
        end
        local right2 = {}
        if info then right2[#right2 + 1] = { st.free, S(UIK.Width(st.free.fs) + 26), S(28) } end
        if canAnchor then right2[#right2 + 1] = { st.anchor, S(UIK.Width(st.anchor.fs) + 30), S(28) } end
        local pad = S(PAD) + 1
        local W = math.max(S(STRIP_W), pad + Span(items, gap) + 2 * gap + Span(right, gap) + pad,
            pad + Span(row2, gap) + 2 * gap + Span(right2, gap) + pad)
        Flow(st, items, pad, gap, H, P)
        Flow(st, right, W - pad - Span(right, gap), gap, H, P)
        -- the hairline between the rows, inside the padding
        st.hair:ClearAllPoints()
        st.hair:SetPoint("TOPLEFT", st, "TOPLEFT", pad * P, -H * P)
        st.hair:SetSize((W - 2 * pad) * P, P)
        st.hair:Show()
        Flow(st, row2, pad, gap, H2, P, H + 1)
        Flow(st, right2, W - pad - Span(right2, gap), gap, H2, P, H + 1)
        local tall = H + 1 + H2
        if #pins > 0 then tall = LT.LayPins(st, pins, id, W, tall, P) end
        st:SetSize(W * P, tall * P)
        return W * P
    end)
end

-- Row 3 under a second hairline, from top pixels down: "Moves with it",
-- then frame, side and word per pin, a rule between, as many as the width
-- holds and "+N more" for the rest; Edit frames on the right. The strip never
-- widens for it. Returns the strip's height with it.
function LT.LayPins(st, pins, gid, W, top, P)
    local function S(v) return math.floor(v / P + 0.5) end
    local H3, gap, inner, pad = S(PINS_H), S(GAP), S(PIN_GAP), S(PAD) + 1
    st.hair2:ClearAllPoints()
    st.hair2:SetPoint("TOPLEFT", st, "TOPLEFT", pad * P, -top * P)
    st.hair2:SetSize((W - 2 * pad) * P, P)
    st.hair2:Show()
    local function words(fs, after) return { fs, S(UIK.Width(fs)), nil, true, after } end
    local items = { words(st.movesL) }
    local right = { { st.editFrames, S(UIK.Width(st.editFrames.fs) + 26), S(28) } }
    local room = W - 2 * pad - Span(items, gap) - gap - 2 * gap - Span(right, gap)
    local used, shown = 0, 0
    for i, e in ipairs(pins) do
        local row = st.pinRows[i]
        if not row then break end
        row.name:SetText(e.pin.frame)
        row.side:SetText(Tr(LT.PinSide(e.pin)))
        local w = LT.PinWord(gid, e.i)
        row.word:SetText(Tr(w and w.text or ""))
        local c = (w and w.col) or COL.faint
        row.word:SetTextColor(c[1], c[2], c[3])
        local ew = S(UIK.Width(row.name)) + inner + S(UIK.Width(row.side))
        if w then ew = ew + inner + S(UIK.Width(row.word)) end
        local sep = (i > 1) and (2 * gap + 1) or 0
        local rest = #pins - i
        local keep = 0
        if rest > 0 then
            st.more:SetText(Tr("+%d more"):format(rest))
            keep = gap + S(UIK.Width(st.more))
        end
        if used + sep + ew + keep > room then break end
        used, shown = used + sep + ew, i
    end
    for i = 1, shown do
        local row = st.pinRows[i]
        if i > 1 then items[#items + 1] = { row.rule, 1, H3 - 2 * S(PAD - 3) } end
        local hasWord = row.word:GetText() ~= ""
        items[#items + 1] = words(row.name, inner)
        items[#items + 1] = words(row.side, hasWord and inner or nil)
        if hasWord then items[#items + 1] = words(row.word) end
    end
    if shown < #pins then
        st.more:SetText(Tr("+%d more"):format(#pins - shown))
        items[#items + 1] = words(st.more)
    end
    local band = top + 1
    Flow(st, items, pad, gap, H3, P, band)
    Flow(st, right, W - pad - Span(right, gap), gap, H3, P, band)
    return band + H3
end

-- Edit frames: the mode ends and the group opens on Position > Anchor, where
-- its "Frames that move with it" rows are.
function LT.EditFrames(id)
    local rec = id ~= nil and Store.Get(id)
    LOS.Close()
    if not (rec and rec.type == "group") then return end
    local ui = Options.ui
    if ui then ui.grpMode, ui.grpTab, ui.grpPosSec = "grp", "Position", "Anchor" end
    Options.Select("group", rec.id)
end

-- Several picked: how many, their names (cut at the board's width), the
-- hint, then Delete N and x.
function LT.LayMulti(picks)
    LT.BuildStrips()
    local mt = LT.multi
    local names = {}
    for _, id in ipairs(picks) do names[#names + 1] = LT.Name(id) end
    mt.count:SetText(Tr("%d picked"):format(#picks))
    mt.names:SetText(table.concat(names, ", "))
    mt.del.fs:SetText(Tr("Delete %d"):format(#picks))
    LT.PaintDelete(mt.del, picks)
    PlaceStrip(mt, function(P)
        local function S(v) return math.floor(v / P + 0.5) end
        local H, gap = S(MULTI_H), S(GAP)
        local nw = math.min(S(FullWidth(mt.names)), S(NAMES_W))
        mt.names:SetWidth(nw * P)
        local items = {
            { mt.count, S(UIK.Width(mt.count)), nil, true },
            { mt.names, nw, nil, true },
            { mt.rule, 1, H - 2 * S(PAD - 3) },
            { mt.hint, S(UIK.Width(mt.hint)), nil, true },
        }
        local right = { { mt.del, S(UIK.Width(mt.del.fs) + 26), S(28) }, { mt.close, S(26), S(26) } }
        local pad = S(PAD) + 1
        local W = math.max(S(STRIP_W), pad + Span(items, gap) + 2 * gap + Span(right, gap) + pad)
        Flow(mt, items, pad, gap, H, P)
        Flow(mt, right, W - pad - Span(right, gap), gap, H, P)
        mt:SetSize(W * P, H * P)
        return W * P
    end)
end

-- Deleting. Never undoable: after any delete the history goes, so no step
-- can put back a record that is gone. Refused in combat and under a lock.

local MANY = "ARCUIV2_ONSCREEN_DELETE"
local LOCKED_TIP = "Locked: unlock it to delete it."
-- what a group takes with it, a count and its noun: one whole line per form
local INSIDE_WORD = {
    icon = function(k) return (k == 1 and Tr("%d icon") or Tr("%d icons")):format(k) end,
    reminder = function(k) return (k == 1 and Tr("%d reminder") or Tr("%d reminders")):format(k) end,
}

-- a lock on any of ids (the record, its group or its layout)
function LT.AnyLocked(ids)
    for _, id in ipairs(ids) do
        if Store.Locked(Store.Get(id)) then return true end
    end
    return false
end

function LT.DeleteButton(parent, onClick)
    local b = (AT.MakeQuietButton or AT.MakeSmallButton)(parent, "Delete")
    b.fs:SetFont(AT.FONT, 13, "")
    b:SetScript("OnClick", onClick)
    if AT.Tooltip then
        AT.Tooltip(b, "Delete", function() return b._locked and LOCKED_TIP or nil end)
    end
    return b
end

-- dimmed while a pick is locked
function LT.PaintDelete(b, ids)
    b._locked = LT.AnyLocked(ids)
    b:SetAlpha(b._locked and 0.4 or 1)
end

function LT.CanDelete(ids)
    if not LOS.open or InCombatLockdown() or #ids == 0 or LT.AnyLocked(ids) then return false end
    for _, id in ipairs(ids) do
        if not Store.Get(id) then return false end
    end
    return true
end

-- One picked: the panel's own question. Its Yes deletes and re-selects the
-- record's layout, the one being edited, so the mode stays; the mode's own
-- follow-up rides after it.
function LT.DeleteOne()
    local id = LOS.selId
    if id == nil or #LOS.more > 0 or not Options.ConfirmDelete or not LT.CanDelete({ id }) then return end
    LT.Cancel()
    LT.CancelPick()
    Options.ConfirmDelete(Store.Get(id))
    local d = StaticPopupDialogs and StaticPopupDialogs.ARCUIV2_DELETE
    if d then
        local accept = d.OnAccept
        d.OnAccept = function(...)
            if accept then accept(...) end
            LT.Deleted()
        end
        LT.asking = "ARCUIV2_DELETE"
    end
end

-- the question for several: how many, and what their groups take with them
function LT.DeleteText(ids)
    local picked, inside, groups = {}, { icon = 0, reminder = 0 }, 0
    for _, id in ipairs(ids) do picked[id] = true end
    for _, id in ipairs(ids) do
        local r = Store.Get(id)
        if r and r.type == "group" then
            groups = groups + 1
            for _, mid in ipairs(r.members or {}) do
                local m = Store.Get(mid)
                if m and not picked[mid] and inside[m.type] then inside[m.type] = inside[m.type] + 1 end
            end
        end
    end
    local parts = {}
    for _, t in ipairs({ "icon", "reminder" }) do
        local k = inside[t]
        if k > 0 then parts[#parts + 1] = INSIDE_WORD[t](k) end
    end
    local text = Tr("Delete %d elements?"):format(#ids)
    if #parts > 0 then
        local what = (#parts == 2) and Tr("%s and %s"):format(parts[1], parts[2]) or parts[1]
        text = text .. "\n" .. (groups == 1 and Tr("The group takes its %s with it.")
            or Tr("The groups take their %s with them.")):format(what)
    end
    return text
end

-- Several picked: the mode's own question; Yes deletes them as they stood.
function LT.DeleteMany()
    local ids = LOS.Picked()
    if #ids < 2 or not LT.CanDelete(ids) or not (StaticPopupDialogs and StaticPopup_Show) then return end
    LT.Cancel()
    StaticPopupDialogs[MANY] = StaticPopupDialogs[MANY] or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local d = StaticPopupDialogs[MANY]
    d.text = LT.DeleteText(ids)
    d.OnAccept = function() LT.DeleteNow(ids) end
    LT.asking = MANY
    StaticPopup_Show(MANY)
end

function LT.DeleteNow(ids)
    if not LT.CanDelete(ids) then return end
    for _, id in ipairs(ids) do Store.Delete(id) end
    -- the panel's pick lands on the layout when it was one of them
    local ui = Options.ui
    if ui and ui.selIconId and not Store.Get(ui.selIconId) then
        ui.selIconId, ui.grpMode = nil, "grp"
    end
    if ui and ui.selId and not Store.Get(ui.selId) and Store.Get(LOS.layoutId) then
        Options.Select("layout", LOS.layoutId)
    end
    LT.Deleted()
end

-- after any delete: no history, the picks that went let go, all redrawn
function LT.Deleted()
    LT.asking = nil
    local EO = Ops()
    if EO and EO.ClearHistory then EO.ClearHistory() end
    if LOS.open then LOS.Redraw() end
end

-- the question still up goes unanswered; true when one was up
function LT.HideAsk()
    local which = LT.asking
    LT.asking = nil
    if not which then return false end
    local up = not StaticPopup_Visible or StaticPopup_Visible(which)
    if StaticPopup_Hide then StaticPopup_Hide(which) end
    return up and true or false
end

-- The one teardown's part: a drag ends unsaved, the anchor pick and the
-- hover go, a delete question goes unanswered, and everything this file put
-- on screen hides.
function LT.Teardown()
    LT.HideAsk()
    LT.Cancel()
    LT.CancelPick()
    if LT.driver then LT.driver:SetScript("OnUpdate", nil) end
    for _, h in ipairs(LT.handles) do h:Hide() end
    for _, t in ipairs(LT.links) do t:Hide() end
    for _, f in ipairs(LT.overlays) do f:Hide() end
    if LT.banner then LT.banner:Hide() end
    if LT.strip then LT.strip:Hide() end
    if LT.multi then LT.multi:Hide() end
end
