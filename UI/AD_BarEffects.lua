-- AD_BarEffects: the bar editor's Effects tab. A list of triggers down the left (the page's lead
-- column), the picked trigger's head and its blocks on the right, + Add a trigger under the list.
-- A trigger is a sub-tab of the Effects tab: its rows stay the bar editor's own blocks.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL = AT.COL
local Tr = AT.Tr

local BX = {}
Options.BarEffects = BX

-- the icon Effects tab's measures (the board's px / 1.17): the list, a row at
-- its least, + Add a trigger, a trigger's small bar and the text after it
BX.SIDE_W, BX.GAP = 224, 10
BX.ROW_H, BX.ADD_H, BX.CELLS_W, BX.CELLS_H = 48, 26, 44, 12
BX.TEXT_X = 10 + BX.CELLS_W + 9
-- a row's name line, chip line, the gap between chip lines, its top and bottom padding
BX.NAME_LH, BX.CHIP_LH, BX.CHIP_GAP_Y, BX.ROW_PAD_Y = 15, 14, 2, 7
-- title strip, the head at its least, folder tabs (idle, open), a card's
-- strip, the panel's inset, the room under a card's last row
BX.STRIP_H, BX.HEAD_H, BX.TAB_H, BX.TAB_ON_H, BX.CARD_STRIP, BX.PAD, BX.CARD_FOOT = 22, 38, 23, 26, 26, 10, 6
-- the page's 18 between sections: 10 under the head, none under the tab
BX.GAP_FIX, BX.GAP_TAB = 8, 18
BX.TAB = "Effects"

local function R(r, section, field) return Store.Resolve(r, section, field) end
local function On(r, section, field) return R(r, section, field) == true end

-- the steps of a saved band list, in their own colours; fmt words each value
local function Steps(r, section, prefix, count, unit, fmt)
    local out = {}
    local n = tonumber(R(r, section, count)) or 1
    for i = 2, 1 + n do
        local v = tonumber(R(r, section, prefix .. i .. "Value"))
        if v and v > 0 then
            local text = string.format("%g", v) .. (unit or "")
            if fmt then text = Tr(fmt):format(text) end
            out[#out + 1] = { text = text, color = R(r, section, prefix .. i .. "Color"), v = v }
        end
    end
    return out
end
BX.Steps = Steps

-- A trigger's small bar in the list: its last step's colour, else the bar's.
function BX.MiniColor(r, sub)
    local d = BX.Def(sub)
    local list = d.chips and d.chips(r)
    local last = type(list) == "table" and list[#list]
    return (last and last.color) or R(r, "fill", "color") or COL.arc
end

local function GlowCount(r)
    local n = 0
    local G = r.driver and r.driver.glows
    if type(G) == "table" then for _ in pairs(G) do n = n + 1 end end
    return n
end
local function HasFade(r)
    local c = r.c or {}
    return next(c.fadeWhen or {}) ~= nil or next(c.showWhen or {}) ~= nil
end

-- A trigger: a sub-tab's words, whether it does something (it lists itself
-- then), its line of chips, and the fields Remove trigger turns off.
BX.TRIGGERS = {
    ["Stacks"] = { when = "Colors the bar at each stack count", line = "Colors the bar at each stack count",
        strip = "at each stack count",
        on = function(r) return On(r, "stackcolors", "scEnabled") or On(r, "stackcolors", "maxColorEnabled") end,
        chips = function(r)
            local out = Steps(r, "stackcolors", "sc", "scCount", nil, "From %s")
            if On(r, "stackcolors", "maxColorEnabled") then
                out[#out + 1] = { text = Tr("Max stacks"), color = R(r, "stackcolors", "maxColor") }
            end
            return out
        end,
        off = { { "stackcolors", "scEnabled" }, { "stackcolors", "maxColorEnabled" } } },
    ["Points"] = { when = "Colors each point by its place", line = "Colors each point by its place",
        on = function(r) return On(r, "stackcolors", "scEnabled") end,
        chips = function(r) return Steps(r, "stackcolors", "sc", "scCount") end,
        off = { { "stackcolors", "scEnabled" }, { "stackcolors", "maxColorEnabled" } } },
    ["Time left"] = { when = "Colors the bar at each time left", line = "Colors the bar at each time left",
        strip = "at each time left",
        on = function(r) return On(r, "thresholds", "threshEnabled") end,
        chips = function(r)
            return Steps(r, "thresholds", "thresh", "threshCount", On(r, "thresholds", "threshAsSeconds") and " s" or "%", "Under %s")
        end,
        off = { { "thresholds", "threshEnabled" } } },
    ["Health"] = { when = "Colors the bar at each health percent", line = "Colors the bar at each health percent",
        on = function(r) return On(r, "healththresholds", "hpthEnabled") end,
        chips = function(r) return Steps(r, "healththresholds", "hpth", "hpthCount", "%") end,
        off = { { "healththresholds", "hpthEnabled" } } },
    ["An ability"] = { when = "While an ability is queued or after its cast", line = "While it is queued, or after its cast",
        on = function(r) return On(r, "abilcolors", "abilColorsOn") end,
        off = { { "abilcolors", "abilColorsOn" } } },
    ["Charges"] = { when = "While it recharges or has full charges", line = "Only on a spell with charges",
        on = function(r) return On(r, "segments", "fullColorEnabled") or On(r, "segments", "rechargeColorEnabled") end,
        off = { { "segments", "fullColorEnabled" }, { "segments", "rechargeColorEnabled" } } },
    ["Ready"] = { when = "While the spell is ready", line = "While the spell is ready",
        on = function(r) return On(r, "behavior", "hideWhenReady") or On(r, "behavior", "hideWhenFullCharges") end,
        off = { { "behavior", "hideWhenReady" }, { "behavior", "hideWhenFullCharges" } } },
    ["Not active"] = { when = "While it is not running", line = "While it is not running",
        on = function(r) return On(r, "behavior", "hideWhenInactive") end,
        off = { { "behavior", "hideWhenInactive" } } },
    ["Glows"] = { when = "Glows by any aura or spell", line = "Glows by any aura or spell",
        on = function(r) return GlowCount(r) > 0 end },
    ["While"] = { when = "Fades it while a condition is true", line = "Fades or shows it while a condition is true",
        on = HasFade, remove = function(r) BX.ClearWhile(r) end, tab = "When" },
    ["Windup"] = { when = "While the shot winds up or waits to fire" },
    ["Channeling"] = { when = "While you channel", line = "While you channel",
        on = function(r) return On(r, "fill", "castChannelOn") end, off = { { "fill", "castChannelOn" } } },
    ["Can't be interrupted"] = { when = "While the cast can't be interrupted", line = "While the cast can't be interrupted",
        on = function(r) return On(r, "fill", "castLockOn") end, off = { { "fill", "castLockOn" } } },
    ["Cast ended"] = { when = "When a cast is interrupted or fails", line = "When a cast is interrupted or fails",
        on = function(r) return On(r, "cast", "holdOn") end, off = { { "cast", "holdOn" } } },
    ["Which casts"] = { when = "Hides some casts", line = "Hides channels or casts that can't be interrupted",
        on = function(r) return On(r, "cast", "hideChannels") or On(r, "cast", "lockHide") end,
        off = { { "cast", "hideChannels" }, { "cast", "lockHide" } } },
    ["Between casts"] = { when = "While you are not casting" },
    ["Empowered stages"] = { when = "Colors each stage of an empowered cast", line = "Colors each stage of an empowered cast",
        on = function(r) return On(r, "fill", "castStageColors") end, off = { { "fill", "castStageColors" } } },
    ["Procs used"] = { when = "Colors the bar by the procs used" },
    ["Stack Pictures"] = { when = "A picture per stack count", line = "A picture per stack count",
        on = function(r) return (tonumber(R(r, "texstate", "stackBands")) or 0) > 0 end, off = { { "texstate", "stackBands", 0 } } },
    ["Time Left"] = { when = "A look under a time left", line = "A look under a time left",
        on = function(r) return On(r, "texstate", "timeOn") end, off = { { "texstate", "timeOn" } } },
    ["By Value"] = { when = "Shown at or above a value, or below it", line = "Shown at or above a value, or below it",
        on = function(r) return R(r, "texstate", "valShow") ~= "any" end, off = { { "texstate", "valShow", "any" } } },
}
BX.TRIGGERS["Channeling"].add = { { "fill", "castChannelOn" } }
BX.TRIGGERS["Can't be interrupted"].add = { { "fill", "castLockOn" } }
BX.TRIGGERS["Cast ended"].add = { { "cast", "holdOn" } }
BX.TRIGGERS["Empowered stages"].add = { { "fill", "castStageColors" } }
BX.TRIGGERS["Stack Pictures"].add = { { "texstate", "stackBands", 1 } }
BX.TRIGGERS["Time Left"].add = { { "texstate", "timeOn" } }
BX.TRIGGERS["By Value"].add = { { "texstate", "valShow", "above" } }

-- what adding a trigger switches on (a trigger with no switch of its own has none)
for name, fields in pairs({
    ["Stacks"] = { "stackcolors", "scEnabled" }, ["Points"] = { "stackcolors", "scEnabled" },
    ["Time left"] = { "thresholds", "threshEnabled" }, ["Health"] = { "healththresholds", "hpthEnabled" },
    ["An ability"] = { "abilcolors", "abilColorsOn" }, ["Ready"] = { "behavior", "hideWhenReady" },
    ["Not active"] = { "behavior", "hideWhenInactive" },
}) do
    BX.TRIGGERS[name].add = { fields }
end
-- Time left comes back with its fill color, whatever was taken off it before
BX.TRIGGERS["Time left"].add[2] = { "thresholds", "threshFill" }

-- the triggers added this session and not switched on yet, per bar
BX.shown = {}
local function ShownOf(r)
    local key = r.id or r
    BX.shown[key] = BX.shown[key] or {}
    return BX.shown[key]
end

function BX.Def(sub) return BX.TRIGGERS[sub] or {} end

function BX.IsListed(r, sub)
    if ShownOf(r)[sub] then return true end
    local d = BX.Def(sub)
    if d.on then return d.on(r) == true end
    return true
end

-- The listed triggers, the ones that can move in the bar's saved order (the
-- others keep their places)
function BX.Listed(r, avail)
    local out = {}
    for _, s in ipairs(avail) do
        if BX.IsListed(r, s) then out[#out + 1] = s end
    end
    local ord = BX.Orderable(r, avail)
    if #ord < 2 then return out end
    local moves = {}
    for _, s in ipairs(ord) do moves[s] = true end
    local seq, k = Store.BarFxSeq(r, ord), 0
    for i, s in ipairs(out) do
        if moves[s] then
            k = k + 1
            out[i] = seq[k]
        end
    end
    return out
end

-- Order: the triggers whose order changes the picture, top first in their
-- default order. Only an aura stack bar's Time left and Stacks today: a time
-- band and a stack colour both paint its fill, the higher one wins.
function BX.Orderable(r, avail)
    if not r or r._adMulti or r.barKind ~= "aura" or r.barMode ~= "stack" then return {} end
    local have = {}
    if avail then for _, s in ipairs(avail) do have[s] = true end end
    for _, s in ipairs({ "Time left", "Stacks" }) do
        if (avail and not have[s]) or not BX.IsListed(r, s) then return {} end
    end
    return { "Time left", "Stacks" }
end

-- the order with sub moved one step (dir "up" / "down"), or nil where it cannot go
function BX.MoveSeq(r, sub, dir, avail)
    local ord = BX.Orderable(r, avail)
    if #ord < 2 then return nil end
    local seq = Store.BarFxSeq(r, ord)
    local i
    for n, s in ipairs(seq) do if s == sub then i = n end end
    if not i then return nil end
    local j = i + ((dir == "up") and -1 or 1)
    if not seq[j] then return nil end
    seq[i], seq[j] = seq[j], seq[i]
    return seq
end
function BX.CanMove(r, sub, dir, avail) return BX.MoveSeq(r, sub, dir, avail) ~= nil end
-- one step up or down; the order is written whole
function BX.Move(r, sub, dir, avail)
    local seq = BX.MoveSeq(r, sub, dir, avail)
    if not seq then return false end
    Store.SetOverride(r, "fill", "fxOrder", table.concat(seq, ","))
    Store.Dirty("style", r.id)
    return true
end

-- Effects: Time left takes a fill color and a text color, Stacks its fill
-- color. Every other trigger has one tab of its own and no effects to add.
BX.FX_WORD = { fill = "Fill color", text = "Text color", look = "Look" }
BX.FX_OF = { ["Time left"] = { "fill", "text" }, ["Stacks"] = { "fill" } }
-- the effects a trigger has, in tab order; nil for a trigger with one fixed tab
function BX.Effects(r, sub)
    if sub == "Time left" then
        local out = {}
        if R(r, "thresholds", "threshFill") ~= false then out[#out + 1] = "fill" end
        if On(r, "thresholds", "threshText") then out[#out + 1] = "text" end
        return out
    end
    if BX.FX_OF[sub] then return { "fill" } end
    return nil
end
-- what + Add effect offers: the effects it can take and has not
function BX.Missing(r, sub)
    local out, have = {}, {}
    for _, e in ipairs(BX.Effects(r, sub) or {}) do have[e] = true end
    for _, e in ipairs(BX.FX_OF[sub] or {}) do
        if not have[e] then out[#out + 1] = e end
    end
    return out
end
local FX_FIELD = { fill = "threshFill", text = "threshText" }

-- the open effect tab per bar and trigger, for the session
BX.fxPick = {}
local function PickOf(r)
    local key = r.id or r
    BX.fxPick[key] = BX.fxPick[key] or {}
    return BX.fxPick[key]
end
-- the open tab: the picked effect while it is there, else the first one;
-- "look" on a trigger with one tab, nil while it has none
function BX.FxOpen(r, sub)
    local list = BX.Effects(r, sub)
    if not list then return "look" end
    local want = PickOf(r)[sub]
    for _, e in ipairs(list) do if e == want then return e end end
    return list[1]
end
function BX.PickFx(r, sub, fx) PickOf(r)[sub] = fx end

function BX.AddEffect(r, sub, fx)
    local f = sub == "Time left" and FX_FIELD[fx]
    if f then Store.SetOverride(r, "thresholds", f, true) end
    BX.PickFx(r, sub, fx)
    Store.Dirty("style", r.id)
end

-- Takes an effect off a trigger; its last one takes the trigger off the list
-- (Stacks' fill color is its trigger). True when the trigger went.
function BX.RemoveEffect(r, sub, fx, secs, avail)
    local list = BX.Effects(r, sub) or {}
    local others = 0
    for _, e in ipairs(list) do if e ~= fx then others = others + 1 end end
    if others == 0 then
        BX.Remove(r, sub, secs, avail)
        Store.Dirty("style", r.id)
        return true
    end
    local f = sub == "Time left" and FX_FIELD[fx]
    if f then Store.SetOverride(r, "thresholds", f, false) end
    Store.Dirty("style", r.id)
    return false
end

function BX.Offered(r, avail)
    local out = {}
    for _, s in ipairs(avail) do
        if not BX.IsListed(r, s) then out[#out + 1] = s end
    end
    return out
end

BX.picking = false

-- The open trigger follows what exists: a search jump to one not listed
-- lists it; with nothing listed the picker opens.
function BX.Normalize(r, avail, secs)
    -- an open picker belongs to the bar it opened on
    local who = r.id or r
    if BX.pickFor ~= who then
        BX.pickFor = who
        BX.picking = false
    end
    local cur = secs[BX.TAB]
    local known = false
    for _, s in ipairs(avail) do if s == cur then known = true end end
    if known then
        ShownOf(r)[cur] = ShownOf(r)[cur] or (not BX.IsListed(r, cur)) or nil
    else
        cur = BX.Listed(r, avail)[1]
        secs[BX.TAB] = cur
    end
    if cur == nil then BX.picking = true end
    return cur
end

-- The blocks ask before the list is laid: the first one to ask settles the
-- open trigger, and asks again only for another bar or another pick.
function BX.Ensure(r, availFn, secs)
    local who = r.id or r
    local cur = secs[BX.TAB]
    if cur ~= nil and BX.okFor == who and BX.okSub == cur then return end
    BX.Normalize(r, availFn(BX.TAB), secs)
    BX.okFor, BX.okSub = who, secs[BX.TAB]
end

function BX.Add(r, sub, secs)
    ShownOf(r)[sub] = true
    for _, f in ipairs(BX.Def(sub).add or {}) do
        local v = f[3]
        if v == nil then v = true end
        Store.SetOverride(r, f[1], f[2], v)
    end
    secs[BX.TAB] = sub
    BX.picking = false
end

-- Takes a trigger off the list: its switches off, nothing else forgotten.
function BX.Remove(r, sub, secs, avail)
    ShownOf(r)[sub] = nil
    -- a trigger with rows and no switch: its own file clears them
    if BX.Def(sub).remove then BX.Def(sub).remove(r) end
    for _, f in ipairs(BX.Def(sub).off or {}) do
        local v = f[3]
        if v == nil then v = false end
        Store.SetOverride(r, f[1], f[2], v)
    end
    secs[BX.TAB] = nil
    secs[BX.TAB] = BX.Listed(r, avail)[1]
end

function BX.Removable(sub) return BX.Def(sub).off ~= nil or BX.Def(sub).remove ~= nil end

-- A trigger whose Remove deletes rows asks first; one that only switches off
-- can be added back as it was.
-- A section of the open trigger's panel: titled, a card, or a block drawn with no title.
function BX.IsBlock(sec, fxSec)
    if sec == fxSec or not (sec.boxed or sec.fxBlock or sec.card) then return false end
    return sec.box:IsShown() and (sec.visibleFn == nil or sec.visibleFn() == true)
end

BX.POPUP = "ARCAURAS_REMOVE_TRIGGER"
function BX.AskRemove(sub, done)
    if not BX.Def(sub).remove then
        done()
        return
    end
    StaticPopupDialogs[BX.POPUP] = StaticPopupDialogs[BX.POPUP] or {
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local d = StaticPopupDialogs[BX.POPUP]
    d.text = Tr("Delete every row of %s? This can't be undone."):format(Tr(sub))
    d.button1, d.button2 = Tr("Delete"), CANCEL
    d.OnAccept = done
    StaticPopup_Show(BX.POPUP)
end

-- a fixed tab's glyph: While's rules are a When (the icon tab's funnel)
function BX.FixedGlyph(sub) return BX.Def(sub).tab == "When" and "when" or "look" end

-- A trigger's chips in the list: each effect's glyph and word, then its steps
-- with their colours. A trigger with one fixed tab shows that tab's word.
function BX.ChipsOf(r, sub)
    local out = {}
    local list = BX.Effects(r, sub)
    if list then
        for _, e in ipairs(list) do out[#out + 1] = { fx = e, text = Tr(BX.FX_WORD[e]) } end
        if #list == 0 then return out end
    else
        out[1] = { fx = BX.FixedGlyph(sub), text = Tr(BX.Def(sub).tab or "Look") }
    end
    local d = BX.Def(sub)
    local steps = d.chips and d.chips(r)
    for _, c in ipairs(type(steps) == "table" and steps or {}) do out[#out + 1] = c end
    return out
end

-- A trigger's small bar: the bar as its last step paints it, whole, since a
-- step recolours the whole bar (Time left: the shortest step, Stacks: the
-- highest). A bar coloured by position keeps each cell's own colour.
function BX.Cells(r, sub)
    local fill = R(r, "fill", "color") or COL.arc
    local out = {}
    if sub == "Time left" then
        local best
        if R(r, "thresholds", "threshFill") ~= false then
            for _, s in ipairs(Steps(r, "thresholds", "thresh", "threshCount")) do
                if not best or s.v < best.v then best = s end
            end
        end
        for i = 1, 10 do out[i] = (best and best.color) or fill end
        return out
    end
    if sub == "Stacks" then
        local B = NS.Bars
        local M = tonumber(B and B.MaxStacksFor and B.MaxStacksFor(r)) or 10
        local steps = Steps(r, "stackcolors", "sc", "scCount")
        local maxC = On(r, "stackcolors", "maxColorEnabled") and R(r, "stackcolors", "maxColor")
        if not (r.barKind == "aura" and B and B.StackSegmented and B.StackSegmented(r)) then
            local best
            for _, x in ipairs(steps) do
                if not best or x.v > best.v then best = x end
            end
            for i = 1, 10 do out[i] = maxC or (best and best.color) or fill end
            return out
        end
        for i = 1, 10 do
            local s, best = math.floor(i * M / 10 + 0.5), nil
            for _, x in ipairs(steps) do
                if s >= x.v and (not best or x.v > best.v) then best = x end
            end
            out[i] = (maxC and s >= M and maxC) or (best and best.color) or fill
        end
        return out
    end
    local c = BX.MiniColor(r, sub)
    for i = 1, 10 do out[i] = c end
    return out
end

local function Tex(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(AT.WHITE)
    return t
end
local function Font(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetJustifyH("LEFT")
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    return fs
end

-- Effect glyphs drawn from bars, as the editor's own: a bar with its fill
-- edge for Fill color, a letter T for Text color; any other kind is the editor's.
local GLYPH = {
    fill = { { 12.4, 1.4, 0, 2.5 }, { 12.4, 1.4, 0, -2.5 }, { 1.4, 5, -5.5, 0 }, { 1.4, 5, 5.5, 0 }, { 1.4, 5, 1, 0 } },
    text = { { 8, 1.5, 0, 4 }, { 1.5, 8.5, 0, -0.25 } },
}
function BX.Glyph(parent, kind)
    local G = GLYPH[kind]
    if not G then return Options.EditorTabs.Glyph(parent, kind) end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(14, 14)
    f._bars = {}
    for _, b in ipairs(G) do
        local t = Tex(f, "OVERLAY")
        t:SetSize(b[1], b[2])
        t:SetPoint("CENTER", b[3], b[4])
        f._bars[#f._bars + 1] = t
    end
    function f:SetColor(c, a)
        for _, t in ipairs(self._bars) do t:SetVertexColor(c[1], c[2], c[3], a or 1) end
    end
    f:SetColor(COL.ink)
    return f
end

-- A trigger's small bar: ten cells in a black frame, a pixel between them,
-- every edge on a whole pixel. Paint returns its height.
local function CellBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    f._bg = Tex(f, "BORDER")
    f._bg:SetAllPoints()
    f._bg:SetVertexColor(0, 0, 0, 1)
    f._cells = {}
    for i = 1, 10 do f._cells[i] = Tex(f, "ARTWORK") end
    function f:Paint(colors)
        local px = AT.Px(self)
        local cw = math.max(1, math.floor((BX.CELLS_W / px - 13) / 10))
        local H = math.max(5, math.floor(BX.CELLS_H / px + 0.5))
        self:SetSize((13 + 10 * cw) * px, H * px)
        for i, t in ipairs(self._cells) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", self, "TOPLEFT", (2 + (i - 1) * (cw + 1)) * px, -2 * px)
            t:SetSize(cw * px, (H - 4) * px)
            local c = colors[i] or COL.arc
            t:SetVertexColor(c[1], c[2], c[3], 1)
        end
        return H * px
    end
    return f
end
BX.CellBar = CellBar

-- whole pixels down from a frame's top that centre bh in its h
local function MidY(f, h, bh)
    local px = AT.Px(f)
    return -math.floor((h - bh) / 2 / px + 0.5) * px
end

-- Builds the list, the head, the effect tabs and card, and the picker.
-- avail(): the Effects tab's sub-tabs for the open bar; secs(): the editor's
-- sub-tab picks; under: the editor's tab row; owner: the window (menus).
function BX.Build(pg, ctx, vis, avail, secs, under, owner)
    local function Relay() AT.LayoutPage(pg) end
    local EF = Options.EffectsTab
    local Kit = EF.Kit
    local GREEN, GREEN_EDGE = Kit.GREEN, Kit.GREEN_EDGE
    local fxSec
    -- the page under the tab row: the window's darker ground, as on an icon
    local ground
    if under then
        ground = pg:CreateTexture(nil, "BACKGROUND", nil, -7)
        ground:SetTexture(AT.WHITE)
        ground:SetVertexColor(COL.bg[1], COL.bg[2], COL.bg[3], 1)
        ground:SetPoint("TOPLEFT", under, "BOTTOMLEFT", -2, 2)
        ground:SetPoint("BOTTOMRIGHT", pg, "BOTTOMRIGHT", 0, 0)
        ground:Hide()
    end
    BX.ground = ground
    function BX.SyncGround()
        local on = ground ~= nil and vis() == true
        if ground then ground:SetShown(on) end
        return on
    end
    -- the title strip over both columns, one of the page's top rows
    local section = pg._curSection
    pg._curSection = nil
    local strip = AT.AddRow(pg, BX.STRIP_H + 9, vis)
    pg._curSection = section
    BX.strip = strip
    local stripBand = CreateFrame("Frame", nil, strip, "BackdropTemplate")
    AT.Skin(stripBand, COL.head, COL.line)
    stripBand:SetPoint("TOPLEFT", 4, 0)
    stripBand:SetPoint("TOPRIGHT", -4, 0)
    stripBand:SetHeight(BX.STRIP_H)
    local stripWords = Font(stripBand, 12, COL.title)
    stripWords:SetPoint("LEFT", 9, 0)
    stripWords:SetText(Tr("What it does, and when"))
    local col = CreateFrame("Frame", nil, pg, "BackdropTemplate")
    AT.Skin(col, COL.well, COL.line)
    BX.col = col
    local rows = {}
    BX.rows = rows
    -- measuring only: a chip's words, the head's when, a name
    local m10, m11, m13 = Font(col, 10), Font(col, 11), Font(col, 13)
    m10:Hide()
    m11:Hide()
    m13:Hide()
    local function W10(t) m10:SetText(t) return Kit.Measure(m10) end
    local function W11(t) m11:SetText(t) return Kit.Measure(m11) end
    local function W13(t) m13:SetText(t) return Kit.Measure(m13) end

    -- + Add a trigger under the list: a dashed green edge, lit while hovered
    -- or while its picker is open
    local add = CreateFrame("Button", nil, col)
    add:SetSize(BX.SIDE_W - 20, BX.ADD_H)
    add._fill = Tex(add)
    add._fill:SetAllPoints()
    add._dash = Kit.DashEdge(add)
    add.fs = Font(add, 12, GREEN)
    add.fs:SetPoint("LEFT", 10, 0)
    add.fs:SetText(Tr("+ Add a trigger"))
    local function PaintAdd(hot)
        add._fill:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], hot and 1 or 0)
        add._dash:Lay(BX.SIDE_W - 20, BX.ADD_H, hot and GREEN or GREEN_EDGE)
    end
    PaintAdd(false)
    add:SetScript("OnEnter", function() PaintAdd(true) end)
    add:SetScript("OnLeave", function() PaintAdd(BX.picking) end)
    add:SetScript("OnClick", function()
        AT.CloseDropdown()
        BX.picking = not BX.picking
        Relay()
    end)
    AT.Tooltip(add, "Add a trigger", "What else can change this bar's look or glow.")
    BX.add = add

    -- over the list while its order can change: which way wins
    local cap = Font(col, 10, COL.faint)
    cap:SetText(Tr("Higher wins"))
    local capChev = AT.MakeChevron(col)
    capChev:SetDir("up")
    capChev:SetColor(COL.faint)
    capChev:SetPoint("LEFT", col, "TOPLEFT", 8, -Kit.ORDER_CAP_H / 2)
    cap:SetPoint("LEFT", capChev, "RIGHT", 2, 0)
    BX.orderCap, BX.orderChev = cap, capChev

    local function NameInk(rw)
        local c = (rw._on or rw._hot) and COL.ink or Kit.MidInk()
        rw._name:SetTextColor(c[1], c[2], c[3])
    end
    local function Row(i)
        local rw = rows[i]
        if rw then return rw end
        rw = CreateFrame("Button", nil, col)
        rw._fill = Tex(rw)
        rw._fill:SetAllPoints()
        rw._e = Kit.Edges(rw)
        rw._bar = CellBar(rw)
        rw._name = Font(rw, 13)
        rw._name:SetWordWrap(false)
        rw._segs, rw._gl, rw._dots = {}, {}, {}
        -- the order's up and down (higher wins)
        for _, dir in ipairs({ "up", "down" }) do
            local b = Kit.OrderArrow(rw, dir)
            b:SetScript("OnClick", function(self)
                local r = ctx()
                if r and self._can and BX.Move(r, rw._sub, self._dir, avail(BX.TAB)) then Relay() end
            end)
            AT.Tooltip(b, dir == "up" and "Move up" or "Move down", "Higher wins: the higher trigger's look shows while both hold.")
            rw[dir == "up" and "_up" or "_dn"] = b
        end
        rw:SetScript("OnClick", function(self)
            AT.CloseDropdown()
            BX.picking = false
            secs()[BX.TAB] = self._sub
            Relay()
        end)
        rw:SetScript("OnEnter", function(self)
            self._hot = true
            NameInk(self)
        end)
        rw:SetScript("OnLeave", function(self)
            self._hot = nil
            NameInk(self)
        end)
        rows[i] = rw
        return rw
    end

    -- a row's chips under its name, as the icon tab's: an effect's glyph and
    -- word, a step's colour and words
    local GLYPH_S = 9 / 14
    local function Seg(rw, i)
        local fs = rw._segs[i]
        if not fs then
            fs = Font(rw, 10)
            rw._segs[i] = fs
        end
        return fs
    end
    local function SegGlyph(rw, i, fx)
        rw._gl[i] = rw._gl[i] or {}
        local g = rw._gl[i][fx]
        if not g then
            g = BX.Glyph(rw, fx)
            g:SetScale(GLYPH_S)
            rw._gl[i][fx] = g
        end
        return g
    end
    local function Dot(rw, i)
        local d = rw._dots[i]
        if not d then
            d = { edge = Tex(rw, "BORDER"), fill = Tex(rw, "ARTWORK") }
            d.edge:SetVertexColor(0, 0, 0, 1)
            rw._dots[i] = d
        end
        return d
    end
    local function PaintChips(rw, pieces, x0, top)
        local function LineY(k)
            return -(top + BX.NAME_LH + 3 + (k - 1) * (BX.CHIP_LH + BX.CHIP_GAP_Y) + BX.CHIP_LH / 2)
        end
        local px = AT.Px(rw)
        local ds = math.floor(7 / px + 0.5) * px
        local dots, glyphs, n = {}, {}, 0
        for i, p in ipairs(pieces) do
            n = i
            local yc = LineY(p.line)
            local fs = Seg(rw, i)
            fs:SetText(p.text)
            fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", rw, "TOPLEFT", x0 + p.x + p.lead, yc)
            fs:Show()
            if p.lead > 0 and p.chip.fx then
                local g = SegGlyph(rw, i, p.chip.fx)
                g:ClearAllPoints()
                g:SetPoint("LEFT", rw, "TOPLEFT", (x0 + p.x) / GLYPH_S, yc / GLYPH_S)
                g:SetColor(COL.title)
                glyphs[g] = true
            elseif p.lead > 0 and p.chip.color then
                local d, c = Dot(rw, i), p.chip.color
                d.fill:SetVertexColor(c[1], c[2], c[3], 1)
                d.fill:SetSize(ds, ds)
                d.fill:ClearAllPoints()
                d.fill:SetPoint("LEFT", rw, "TOPLEFT", x0 + p.x + px, yc)
                d.edge:SetSize(ds + 2 * px, ds + 2 * px)
                d.edge:ClearAllPoints()
                d.edge:SetPoint("CENTER", d.fill, "CENTER", 0, 0)
                d.fill:Show()
                d.edge:Show()
                dots[i] = true
            end
        end
        if #pieces == 0 then
            n = 1
            local fs = Seg(rw, 1)
            fs:SetText(Tr("No effect yet"))
            fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", rw, "TOPLEFT", x0, LineY(1))
            fs:Show()
        end
        for i = n + 1, #rw._segs do rw._segs[i]:Hide() end
        for i, d in pairs(rw._dots) do
            if not dots[i] then
                d.fill:Hide()
                d.edge:Hide()
            end
        end
        for _, set in pairs(rw._gl) do
            for _, g in pairs(set) do g:SetShown(glyphs[g] == true) end
        end
    end

    AT.SetLead(pg, col, BX.SIDE_W, BX.GAP, vis, function()
        local r = ctx()
        if not r then return 0 end
        local a = avail(BX.TAB)
        local cur = BX.Normalize(r, a, secs())
        local list = BX.Listed(r, a)
        local movable = {}
        for _, s in ipairs(BX.Orderable(r, a)) do movable[s] = true end
        local order = next(movable) ~= nil
        cap:SetShown(order)
        capChev:SetShown(order)
        local px = AT.Hairline(col)
        local rowW = BX.SIDE_W - 2 * px
        local y = -(px + (order and Kit.ORDER_CAP_H or 0))
        for i, s in ipairs(list) do
            local rw = Row(i)
            local on = s == cur and not BX.picking
            rw._sub, rw._on = s, on
            local arrows = movable[s] == true
            local textW = rowW - BX.TEXT_X - 9 - (arrows and Kit.ARROW_W or 0)
            local pieces, lines = EF.FlowChips(BX.ChipsOf(r, s), textW, W10)
            local cl = math.max(1, lines)
            local block = BX.NAME_LH + 3 + cl * BX.CHIP_LH + (cl - 1) * BX.CHIP_GAP_Y
            local h = math.max(BX.ROW_H, BX.ROW_PAD_Y + block + BX.ROW_PAD_Y)
            rw._h, rw._block = h, block
            rw:ClearAllPoints()
            rw:SetPoint("TOPLEFT", col, "TOPLEFT", px, y)
            rw:SetSize(rowW, h)
            -- the open one: an accent edge on its left, lines above and below
            local bg = on and COL.panel or COL.well
            rw._fill:SetVertexColor(bg[1], bg[2], bg[3], on and 1 or 0)
            rw._e:Lay()
            rw._e:Color(COL.line, { t = on, b = on, l = on })
            rw._e.l:SetWidth(2 * px)
            rw._e.l:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            local bh = rw._bar:Paint(BX.Cells(r, s))
            rw._bar:ClearAllPoints()
            rw._bar:SetPoint("TOPLEFT", rw, "TOPLEFT", 10, MidY(rw, h, bh))
            -- the name and its chips as one block on the row's middle
            local top = math.floor((h - block) / 2)
            rw._name:ClearAllPoints()
            rw._name:SetPoint("TOPLEFT", rw, "TOPLEFT", BX.TEXT_X, -top)
            rw._name:SetWidth(textW)
            rw._name:SetHeight(BX.NAME_LH)
            rw._name:SetText(Tr(s))
            NameInk(rw)
            PaintChips(rw, pieces, BX.TEXT_X, top)
            for _, b in ipairs({ rw._up, rw._dn }) do
                b:SetShown(arrows)
                if arrows then
                    b._can = BX.CanMove(r, s, b._dir, a)
                    Kit.ArrowInk(b, b:IsMouseOver())
                    b:ClearAllPoints()
                    b:SetPoint("RIGHT", rw, "RIGHT", -4, (b._dir == "up") and 7 or -7)
                end
            end
            rw:Show()
            y = y - h
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", col, "TOPLEFT", 10, y - 9)
        add:SetShown(#BX.Offered(r, a) > 0)
        PaintAdd(BX.picking)
        local h = -y + (add:IsShown() and (9 + BX.ADD_H + 9) or 1)
        col:SetHeight(h)
        if BX.LayBody then BX.LayBody() end
        return h
    end)

    -- the open trigger's head: its small bar, name, when it holds, Remove trigger
    local function HeadVis()
        if not vis() then return false end
        local r = ctx()
        if not r then return false end
        BX.Ensure(r, avail, secs())
        return not BX.picking and secs()[BX.TAB] ~= nil
    end
    AT.Section(pg, nil, { visibleFn = HeadVis })
    local head = AT.AddRow(pg, BX.HEAD_H, HeadVis)
    BX.head = head
    head._fill = Tex(head)
    head._fill:SetAllPoints()
    head._fill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    head._edge = Kit.Edges(head)
    head._bar = CellBar(head)
    head._name = Font(head, 13, COL.ink)
    head._name:SetWordWrap(false)
    head._when = Font(head, 11, COL.faint)
    head._when:SetWordWrap(true)
    head._rm = Kit.QuietX(head)
    head._rm:SetWords(Tr("Remove trigger"))
    head._rm:SetPoint("RIGHT", -9, 0)
    AT.Tooltip(head._rm, "Remove this trigger", function()
        return BX.Def(secs()[BX.TAB]).remove and "Deletes its rows and takes it off the list."
            or "Turns off everything on it and takes it off the list."
    end)
    head._rm:SetScript("OnClick", function()
        local r = ctx()
        if not r then return end
        local sub = secs()[BX.TAB]
        AT.CloseDropdown()
        BX.AskRemove(sub, function()
            -- the bar and trigger it was asked for, even if the panel moved on
            BX.Remove(r, sub, secs(), avail(BX.TAB))
            Store.Dirty("style", r.id)
            Relay()
        end)
    end)
    head._sync = function()
        local s, r = secs()[BX.TAB], ctx()
        if not (s and r) then return end
        local name, when = Tr(s), Tr(BX.Def(s).when or "")
        head._name:SetText(name)
        head._when:SetText(when)
        head._rm:SetShown(BX.Removable(s))
        local w = head:GetWidth() or 0
        if w <= 60 then w = math.max(200, (pg:GetWidth() or 0) - (pg._leadX or 0) - 24) end
        local x0 = BX.TEXT_X
        local right = w - 9 - (head._rm:IsShown() and (head._rm:GetWidth() + 8) or 0)
        local room = math.max(40, right - x0)
        local nw = W13(name)
        local ww = when ~= "" and W11(when) or 0
        -- the when beside the name while both fit, else under it, wrapping
        local stacked = when ~= "" and nw + 8 + ww > room
        local wl = stacked and EF.WrapLines(when, room, W11) or 1
        local h = stacked and math.max(BX.HEAD_H, 5 + BX.NAME_LH + 2 + wl * 13 + 5) or BX.HEAD_H
        head._name:ClearAllPoints()
        head._when:ClearAllPoints()
        if stacked then
            local top = math.floor((h - (BX.NAME_LH + 2 + wl * 13)) / 2)
            head._name:SetPoint("TOPLEFT", x0, -top)
            head._when:SetPoint("TOPLEFT", x0, -(top + BX.NAME_LH + 2))
            head._when:SetWidth(room)
        else
            head._name:SetPoint("LEFT", x0, 0)
            head._when:SetPoint("LEFT", x0 + nw + 8, 0)
            head._when:SetWidth(math.max(1, room - nw - 8))
        end
        head._stacked = stacked
        if head._h ~= h then
            head._h = h
            head:SetHeight(h)
        end
        local bh = head._bar:Paint(BX.Cells(r, s))
        head._bar:ClearAllPoints()
        head._bar:SetPoint("TOPLEFT", head, "TOPLEFT", 10, MidY(head, h, bh))
        head._edge:Lay()
        head._edge:Color(COL.line)
    end

    -- the trigger's effects: a folder tab each, + Add effect after them, and
    -- the open one's card strip (what it does, Remove), as on an icon
    local function FolderVis()
        if not HeadVis() then return false end
        return BX.Def(secs()[BX.TAB]).folder ~= false
    end
    AT.Section(pg, nil, { visibleFn = FolderVis })
    fxSec = pg._curSection
    local fxRow = AT.AddRow(pg, BX.PAD + BX.TAB_ON_H + BX.CARD_STRIP, FolderVis)
    BX.fxRow = fxRow
    -- the card's left in the row: the panel's inset less the row's own
    local CARD_X = BX.PAD - 6
    local TABS_Y = -(BX.PAD + BX.TAB_ON_H)
    local tabs = {}
    BX.fxTabs = tabs
    local function Tab(i)
        local t = tabs[i]
        if t then return t end
        t = CreateFrame("Button", nil, fxRow)
        t._fill = Tex(t)
        t._fill:SetAllPoints()
        t._edge = Kit.Edges(t)
        t._top = Tex(t, "ARTWORK")
        t._top:SetPoint("TOPLEFT", 1, -1)
        t._top:SetPoint("TOPRIGHT", -1, -1)
        t._fs = Font(t, 11)
        t._glyphs = {}
        t:SetScript("OnClick", function(self)
            local r, s = ctx(), secs()[BX.TAB]
            if not (r and s and self._fx) then return end
            AT.CloseDropdown()
            BX.PickFx(r, s, self._fx)
            Relay()
        end)
        tabs[i] = t
        return t
    end
    BX.fxTab = Tab(1)

    -- + Add effect: the effects this trigger can take and has not
    local addFx = CreateFrame("Button", nil, fxRow)
    addFx.fs = Font(addFx, 12, GREEN)
    addFx.fs:SetText(Tr("+ Add effect"))
    addFx.fs:SetPoint("CENTER", 0, 0)
    local addDash = Kit.DashEdge(addFx)
    local fxMenu = Kit.Menu(fxRow, owner)
    BX.addFx, BX.fxMenu = addFx, fxMenu
    local function PaintAddFx(hot)
        addDash:Lay(addFx:GetWidth() or 0, 23, hot and GREEN or GREEN_EDGE)
    end
    addFx:SetScript("OnEnter", function() PaintAddFx(true) end)
    addFx:SetScript("OnLeave", function() PaintAddFx(fxMenu:IsShown()) end)
    fxMenu:HookScript("OnHide", function() PaintAddFx(false) end)
    addFx:SetScript("OnClick", function()
        if AT.openDropdown == fxMenu then
            AT.CloseDropdown()
            return
        end
        AT.CloseDropdown()
        local r, s = ctx(), secs()[BX.TAB]
        if not (r and s) then return end
        local list = BX.Missing(r, s)
        for n, fx in ipairs(list) do
            local b = fxMenu:Item(n, 22)
            b._fx = fx
            b._fs:SetText(Tr(BX.FX_WORD[fx]))
            b._g = b._g or {}
            if not b._g[fx] then
                b._g[fx] = BX.Glyph(b, fx)
                b._g[fx]:SetScale(0.8)
                b._g[fx]:SetPoint("LEFT", 9 / 0.8, 0)
            end
            for k, g in pairs(b._g) do g:SetShown(k == fx) end
            b._g[fx]:SetColor(COL.title)
            b._fs:ClearAllPoints()
            b._fs:SetPoint("LEFT", 9 + 11 + 7, 0)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 1, -3 - (n - 1) * 22)
            b:SetPoint("TOPRIGHT", -1, -3 - (n - 1) * 22)
            b:SetScript("OnClick", function(self)
                local rr, ss = ctx(), secs()[BX.TAB]
                AT.CloseDropdown()
                if not (rr and ss) then return end
                BX.AddEffect(rr, ss, self._fx)
                Relay()
            end)
            b:Show()
        end
        for i = #list + 1, #fxMenu._items do fxMenu._items[i]:Hide() end
        fxMenu:SetSize(154, #list * 22 + 6)
        fxMenu:ClearAllPoints()
        fxMenu:SetPoint("TOPLEFT", addFx, "BOTTOMLEFT", 0, -4)
        fxMenu:Show()
        AT.openDropdown = fxMenu
        PaintAddFx(true)
    end)
    AT.Tooltip(addFx, "Add effect", "Give this trigger a fill color or a text color.")

    -- the open effect's strip: its words, and Remove where it can go alone
    local band = Tex(fxRow)
    band:SetVertexColor(COL.head[1], COL.head[2], COL.head[3], 1)
    local bandLine = Tex(fxRow, "BORDER")
    bandLine:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    local cardWords = Font(fxRow, 11, COL.faint)
    cardWords:SetWordWrap(false)
    local cardRm = Kit.QuietX(fxRow)
    cardRm:SetScript("OnClick", function()
        local r, s = ctx(), secs()[BX.TAB]
        if not (r and s and cardRm._fx) then return end
        AT.CloseDropdown()
        BX.RemoveEffect(r, s, cardRm._fx, secs(), avail(BX.TAB))
        Relay()
    end)
    local empty = Font(fxRow, 11, COL.faint)
    empty:SetWordWrap(true)
    BX.cardWords, BX.cardRm, BX.emptyNote = cardWords, cardRm, empty
    local EMPTY = "Nothing on this trigger yet. + Add effect gives it a fill color or a text color."
    fxRow._sync = function()
        local r, s = ctx(), secs()[BX.TAB]
        if not (r and s and FolderVis()) then return end
        local hl = AT.Hairline(fxRow)
        local list = BX.Effects(r, s)
        local fixed = list == nil
        if fixed then list = { BX.FixedGlyph(s) } end
        local open = BX.FxOpen(r, s)
        local mid = Kit.MidInk()
        local x = CARD_X
        for i, fx in ipairs(list) do
            local t = Tab(i)
            local on = fixed or fx == open
            t._fx = (not fixed) and fx or nil
            t._fs:SetText(Tr(fixed and (BX.Def(s).tab or "Look") or BX.FX_WORD[fx]))
            local ink = on and COL.ink or mid
            t._fs:SetTextColor(ink[1], ink[2], ink[3])
            local g = t._glyphs[fx]
            if not g then
                g = BX.Glyph(t, fx)
                g:SetScale(0.86)
                g:SetPoint("LEFT", 9 / 0.86, 0)
                t._glyphs[fx] = g
            end
            for k, gg in pairs(t._glyphs) do gg:SetShown(k == fx) end
            g:SetColor(on and COL.arc or mid)
            t._fs:ClearAllPoints()
            t._fs:SetPoint("LEFT", 9 + 12 + 6, 0)
            local tw = math.ceil(9 + 12 + 6 + Kit.Measure(t._fs) + 9)
            -- the open tab reaches one line into the card, over its top edge
            t:SetSize(tw, on and (BX.TAB_ON_H + 1) or BX.TAB_H)
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", fxRow, "TOPLEFT", x, TABS_Y - (on and 1 or 0))
            local fill = on and COL.box or COL.well
            t._fill:SetVertexColor(fill[1], fill[2], fill[3], 1)
            t._edge:Lay()
            t._edge:Color(COL.line, on and { t = true, l = true, r = true } or nil)
            t._top:SetHeight(2 * hl)
            t._top:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            t._top:SetShown(on)
            t:SetFrameLevel(fxRow:GetFrameLevel() + (on and 2 or 1))
            t:Show()
            x = x + tw + 3
        end
        for i = #list + 1, #tabs do tabs[i]:Hide() end
        local miss = fixed and {} or BX.Missing(r, s)
        addFx:SetShown(#miss > 0)
        if #miss > 0 then
            addFx:SetSize(Kit.Measure(addFx.fs) + 20, 23)
            PaintAddFx(fxMenu:IsShown())
            addFx:ClearAllPoints()
            addFx:SetPoint("BOTTOMLEFT", fxRow, "TOPLEFT", x + (#list > 0 and 5 or 0), TABS_Y + 3)
        else
            fxMenu:Hide()
        end
        local has = #list > 0
        BX.hasCard = has
        band:SetShown(has)
        bandLine:SetShown(has)
        cardWords:SetShown(has)
        empty:SetShown(not has)
        local h
        if has then
            local accent = 3 * hl
            band:ClearAllPoints()
            band:SetPoint("TOPLEFT", fxRow, "TOPLEFT", CARD_X + accent, TABS_Y - hl)
            band:SetPoint("TOPRIGHT", fxRow, "TOPRIGHT", -CARD_X - hl, TABS_Y - hl)
            band:SetHeight(BX.CARD_STRIP - hl)
            bandLine:ClearAllPoints()
            bandLine:SetPoint("TOPLEFT", fxRow, "TOPLEFT", CARD_X + accent, TABS_Y - BX.CARD_STRIP)
            bandLine:SetPoint("TOPRIGHT", fxRow, "TOPRIGHT", -CARD_X - hl, TABS_Y - BX.CARD_STRIP)
            bandLine:SetHeight(hl)
            local d = BX.Def(s)
            cardWords:SetText(Tr(d.strip or d.when or ""))
            cardWords:ClearAllPoints()
            cardWords:SetPoint("LEFT", fxRow, "TOPLEFT", CARD_X + 3 + 10, TABS_Y - BX.CARD_STRIP / 2)
            -- an effect goes on its own; a trigger's one fixed tab goes with it
            cardRm:SetShown(not fixed and open ~= nil)
            if cardRm:IsShown() then
                cardRm._fx = open
                cardRm:SetWords(Tr(open == "text" and "Remove text color" or "Remove fill color"))
                cardRm:ClearAllPoints()
                cardRm:SetPoint("RIGHT", fxRow, "TOPRIGHT", -CARD_X - 7, TABS_Y - BX.CARD_STRIP / 2)
            end
            h = BX.PAD + BX.TAB_ON_H + BX.CARD_STRIP
        else
            cardRm:Hide()
            local w = fxRow:GetWidth() or 0
            if w <= 60 then w = math.max(200, (pg:GetWidth() or 0) - (pg._leadX or 0) - 24) end
            local words = Tr(EMPTY)
            empty:SetText(words)
            empty:SetWidth(w - 2 * CARD_X)
            empty:ClearAllPoints()
            empty:SetPoint("TOPLEFT", fxRow, "TOPLEFT", CARD_X, TABS_Y - 10)
            h = BX.PAD + BX.TAB_ON_H + 10 + EF.WrapLines(words, w - 2 * CARD_X, W11) * 14 + 2
        end
        if fxRow._h ~= h then
            fxRow._h = h
            fxRow:SetHeight(h)
        end
    end

    -- the panel round the tabs and the card: the page lays its sections edge
    -- to edge, so the card's sections are set in here once it has placed them.
    -- It and its edge hang on the trigger column, so they leave with the tab:
    -- their own layout only runs while the tab shows.
    local body = CreateFrame("Frame", nil, col)
    BX.body = body
    body:SetFrameLevel(math.max(0, (pg:GetFrameLevel() or 1)))
    body._fill = Tex(body)
    body._fill:SetAllPoints()
    body._fill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    body._edge = Kit.Edges(body)
    body:Hide()
    -- the card: its fill and edges on the panel's own frame, under the rows
    local cardRect = CreateFrame("Frame", nil, body)
    BX.card = cardRect
    local cardFill = Tex(body, "BORDER")
    cardFill:SetAllPoints(cardRect)
    cardFill:SetVertexColor(COL.box[1], COL.box[2], COL.box[3], 1)
    local cardEdge = { t = Tex(body, "ARTWORK"), b = Tex(body, "ARTWORK"), l = Tex(body, "ARTWORK"), r = Tex(body, "ARTWORK") }
    for _, t in pairs(cardEdge) do t:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1) end
    BX.cardFill, BX.cardEdge = cardFill, cardEdge
    local accentF = CreateFrame("Frame", nil, col)
    accentF:SetFrameLevel((pg:GetFrameLevel() or 1) + 8)
    accentF._tex = Tex(accentF, "ARTWORK")
    accentF._tex:SetAllPoints()
    accentF._tex:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    accentF:Hide()
    BX.accent = accentF
    local function Inset(f, dx, dy)
        local p1, rel1, rp1, x1, y1 = f:GetPoint(1)
        local p2, rel2, rp2, x2, y2 = f:GetPoint(2)
        if type(y1) ~= "number" or type(y2) ~= "number" then return end
        f:ClearAllPoints()
        f:SetPoint(p1, rel1, rp1, x1 + dx, y1 + dy)
        f:SetPoint(p2, rel2, rp2, x2 - dx, y2 + dy)
    end
    local function ShowCard(on)
        cardFill:SetShown(on)
        for _, t in pairs(cardEdge) do t:SetShown(on) end
        accentF:SetShown(on)
    end
    function BX.LayBody()
        local open = FolderVis()
        local first, last
        if open then
            for _, sec in ipairs(pg._sections) do
                if BX.IsBlock(sec, fxSec) then
                    first = first or sec
                    last = sec
                end
            end
        end
        body:SetShown(open)
        if not open then
            ShowCard(false)
            return
        end
        Inset(fxSec.box, 0, BX.GAP_FIX)
        for _, sec in ipairs(pg._sections) do
            if BX.IsBlock(sec, fxSec) then
                Inset(sec.box, BX.PAD, BX.GAP_FIX + BX.GAP_TAB)
                if sec.band then Inset(sec.band, BX.PAD, BX.GAP_FIX + BX.GAP_TAB) end
                -- a fold's header bar (While's condition lists) goes in with its box
                if sec.hit then Inset(sec.hit, BX.PAD, BX.GAP_FIX + BX.GAP_TAB) end
            end
        end
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", fxSec.box, "TOPLEFT", 0, 0)
        if last then
            body:SetPoint("BOTTOMRIGHT", last.box, "BOTTOMRIGHT", BX.PAD, -(BX.CARD_FOOT + BX.PAD))
        else
            body:SetPoint("BOTTOMRIGHT", fxSec.box, "BOTTOMRIGHT", 0, -BX.PAD)
        end
        body._edge:Lay()
        body._edge:Color(COL.line)
        local card = BX.hasCard == true
        ShowCard(card)
        if not card then return end
        local hl = AT.Hairline(body)
        cardRect:ClearAllPoints()
        cardRect:SetPoint("TOPLEFT", fxRow, "TOPLEFT", CARD_X, TABS_Y)
        if last then
            cardRect:SetPoint("BOTTOMRIGHT", last.box, "BOTTOMRIGHT", 0, -BX.CARD_FOOT)
        else
            cardRect:SetPoint("BOTTOMRIGHT", fxRow, "BOTTOMRIGHT", -CARD_X, 0)
        end
        local e = cardEdge
        e.t:ClearAllPoints()
        e.t:SetPoint("TOPLEFT", cardRect, "TOPLEFT", 0, 0)
        e.t:SetPoint("TOPRIGHT", cardRect, "TOPRIGHT", 0, 0)
        e.t:SetHeight(hl)
        e.b:ClearAllPoints()
        e.b:SetPoint("BOTTOMLEFT", cardRect, "BOTTOMLEFT", 0, 0)
        e.b:SetPoint("BOTTOMRIGHT", cardRect, "BOTTOMRIGHT", 0, 0)
        e.b:SetHeight(hl)
        e.l:ClearAllPoints()
        e.l:SetPoint("TOPLEFT", cardRect, "TOPLEFT", 0, 0)
        e.l:SetPoint("BOTTOMLEFT", cardRect, "BOTTOMLEFT", 0, 0)
        e.l:SetWidth(hl)
        e.r:ClearAllPoints()
        e.r:SetPoint("TOPRIGHT", cardRect, "TOPRIGHT", 0, 0)
        e.r:SetPoint("BOTTOMRIGHT", cardRect, "BOTTOMRIGHT", 0, 0)
        e.r:SetWidth(hl)
        accentF:ClearAllPoints()
        accentF:SetPoint("TOPLEFT", cardRect, "TOPLEFT", 0, 0)
        accentF:SetPoint("BOTTOMLEFT", cardRect, "BOTTOMLEFT", 0, 0)
        accentF:SetWidth(3 * hl)
    end

    -- + Add a trigger: a tile per trigger not listed yet
    local function PickVis() return vis() and BX.picking and ctx() ~= nil end
    AT.Section(pg, "Add a trigger", { visibleFn = PickVis })
    local picker = AT.AddRow(pg, 60, PickVis)
    BX.picker = picker
    local tiles = {}
    BX.tiles = tiles
    local function Tile(i)
        local t = tiles[i]
        if t then return t end
        t = CreateFrame("Button", nil, picker, "BackdropTemplate")
        AT.Skin(t, COL.well, COL.line)
        t._name = Font(t, 13, COL.ink)
        t._name:SetPoint("TOPLEFT", 9, -7)
        t._line = Font(t, 10, COL.faint)
        t._line:SetPoint("TOPLEFT", t._name, "BOTTOMLEFT", 0, -2)
        t._line:SetPoint("RIGHT", -6, 0)
        t._line:SetWordWrap(true)
        t:SetScript("OnClick", function(self)
            local r = ctx()
            if not r then return end
            BX.Add(r, self._sub, secs())
            Relay()
        end)
        tiles[i] = t
        return t
    end
    picker._sync = function()
        local r = ctx()
        if not (r and PickVis()) then return end
        local list = BX.Offered(r, avail(BX.TAB))
        local TW, TH, G = 224, 48, 8
        local W = picker:GetWidth() or 0
        local perRow = math.max(1, math.floor((W + G) / (TW + G)))
        for i, s in ipairs(list) do
            local t = Tile(i)
            t._sub = s
            t:SetSize(TW, TH)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) % perRow * (TW + G), -math.floor((i - 1) / perRow) * (TH + G))
            t._name:SetText(Tr(s))
            t._line:SetText(Tr(BX.Def(s).line or ""))
            t:Show()
        end
        for i = #list + 1, #tiles do tiles[i]:Hide() end
        local lines = math.ceil(#list / perRow)
        local h = math.max(1, lines * (TH + G))
        if picker._h ~= h then
            picker._h = h
            picker:SetHeight(h)
        end
    end
end

-- A colour step's swatch: a pick writes, a cancel puts back what was there.
local function PickColor(get, set)
    AT.CloseDropdown()
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local c = get()
    local was = { c[1], c[2], c[3], c[4] or 1 }
    local ready, last = false, nil
    local function pick()
        if not ready then return end
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local v = { r, g, b, ColorPickerFrame:GetColorAlpha() or was[4] }
        if last and last[1] == v[1] and last[2] == v[2] and last[3] == v[3] and last[4] == v[4] then return end
        last = v
        set(v)
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3], hasOpacity = true, opacity = was[4],
        swatchFunc = pick, opacityFunc = pick, cancelFunc = function() set(was) end,
    })
    ready = true
end

local function Count(r, cfg)
    local n = tonumber(R(r, cfg.section, cfg.count)) or cfg.max
    return math.floor(math.max(1, math.min(cfg.max, n)))
end
BX.Count = Count
BX.PickColor = PickColor

-- A step's two fields; i counts from 1, the saved fields from 2 (1 is the fill).
local function ValueField(cfg, i) return cfg.prefix .. (i + 1) .. "Value" end
local function ColorField(cfg, i) return cfg.prefix .. (i + 1) .. "Color" end

-- Removing a step moves the later ones up, so the saved steps stay in a run.
function BX.RemoveStep(r, cfg, i)
    local n = Count(r, cfg)
    if n <= 1 then return false end
    for k = i, n - 1 do
        Store.SetOverride(r, cfg.section, ValueField(cfg, k), R(r, cfg.section, ValueField(cfg, k + 1)))
        Store.SetOverride(r, cfg.section, ColorField(cfg, k), R(r, cfg.section, ColorField(cfg, k + 1)))
    end
    Store.SetOverride(r, cfg.section, cfg.count, n - 1)
    return true
end

-- The steps of one value in a small table: a row per step (its value, its
-- colour, a red x), the fill colour's row first where cfg.base, + Add.
-- copy: the same steps drawn again on another card (the search finds the first).
function BX.StepsRows(pg, ctx, vis, cfg, copy)
    local Schema = NS.Schema
    local Kit = Options.EffectsTab.Kit
    local function Relay() AT.LayoutPage(pg) end
    if cfg.base then
        local row = AT.AddRow(pg, 26, vis)
        AT.RowLabel(row, Tr(cfg.base))
        local sw = AT.MakeSwatch(row)
        sw:SetPoint("LEFT", row._ctrlX, 0)
        sw:EnableMouse(false)
        row._sync = function()
            local r = ctx()
            local c = r and R(r, "fill", "color")
            if c then sw:SetColor(c) end
        end
    end
    local defs = Schema.bar[cfg.section].fields
    for i = 1, cfg.max do
        if Options.BuildYield then Options.BuildYield() end
        local function Vis()
            if not vis() then return false end
            local r = ctx()
            return r ~= nil and i <= Count(r, cfg)
        end
        local vf, cf = ValueField(cfg, i), ColorField(cfg, i)
        local row = AT.AddRow(pg, 26, Vis)
        AT.RowLabel(row, Tr(cfg.label))
        if not copy then row._adMeta = { family = "bar", section = cfg.section, field = vf, def = defs[vf], baseVis = vis } end
        local function Step(r) return (cfg.step and cfg.step(r)) or 1 end
        local function Max(r) return (cfg.top and cfg.top(r)) or defs[vf].max or 99 end
        local function Put(r, v)
            local lo = defs[vf].min or 0
            v = math.max(lo, math.min(Max(r), v))
            Store.SetOverride(r, cfg.section, vf, v)
            Relay()
        end
        local dec = AT.MakeSmallButton(row, "-", 20)
        dec:SetPoint("LEFT", row._ctrlX, 0)
        local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        box:SetSize(44, 20)
        AT.Skin(box, COL.well)
        box:SetFont(AT.FONT, 11, "")
        box:SetJustifyH("CENTER")
        box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        box:SetAutoFocus(false)
        box:SetPoint("LEFT", dec, "RIGHT", 2, 0)
        local inc = AT.MakeSmallButton(row, "+", 20)
        inc:SetPoint("LEFT", box, "RIGHT", 2, 0)
        local unit = Font(row, 11, COL.dim)
        unit:SetPoint("LEFT", inc, "RIGHT", 6, 0)
        unit:SetWidth(22)
        local sw = AT.MakeSwatch(row)
        sw:SetPoint("LEFT", inc, "RIGHT", 32, 0)
        local x = Kit.RedX(row, 17)
        x:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        AT.Tooltip(x, "Remove this step")
        dec:SetScript("OnClick", function()
            local r = ctx()
            if r then Put(r, (tonumber(R(r, cfg.section, vf)) or 0) - Step(r)) end
        end)
        inc:SetScript("OnClick", function()
            local r = ctx()
            if r then Put(r, (tonumber(R(r, cfg.section, vf)) or 0) + Step(r)) end
        end)
        box:SetScript("OnEnterPressed", function(self)
            local r, v = ctx(), tonumber(self:GetText())
            self:ClearFocus()
            if r and v then Put(r, v) end
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() Relay() end)
        sw:SetScript("OnClick", function()
            local r = ctx()
            if not r then return end
            PickColor(function() return R(r, cfg.section, cf) end, function(v)
                Store.SetOverride(r, cfg.section, cf, v)
                Relay()
            end)
        end)
        x:SetScript("OnClick", function()
            local r = ctx()
            if r and BX.RemoveStep(r, cfg, i) then Relay() end
        end)
        row._sync = function()
            local r = ctx()
            if not (r and Vis()) then return end
            if not box:HasFocus() then box:SetText(string.format("%g", tonumber(R(r, cfg.section, vf)) or 0)) end
            unit:SetText(cfg.unit and cfg.unit(r) or "")
            sw:SetColor(R(r, cfg.section, cf) or { 1, 1, 1, 1 })
            x:SetShown(Count(r, cfg) > 1)
        end
    end
    local function AddVis()
        if not vis() then return false end
        local r = ctx()
        return r ~= nil and Count(r, cfg) < cfg.max
    end
    local row = AT.AddRow(pg, 30, AddVis)
    -- the add in green on a green edge, as + Add a trigger
    local add = CreateFrame("Button", nil, row, "BackdropTemplate")
    AT.Skin(add, { 0, 0, 0 }, Kit.GREEN_EDGE)
    add:SetBackdropColor(0, 0, 0, 0)
    add.fs = Font(add, 12, Kit.GREEN)
    add.fs:SetPoint("CENTER", 0, 0)
    add.fs:SetText(Tr(cfg.addWord))
    add:SetSize(Kit.Measure(add.fs) + 24, 22)
    local function Edge(c) add:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
    add:SetScript("OnEnter", function() Edge(Kit.GREEN) end)
    add:SetScript("OnLeave", function() Edge(Kit.GREEN_EDGE) end)
    add:SetPoint("LEFT", 10, 0)
    add:SetScript("OnClick", function()
        local r = ctx()
        if not r then return end
        Store.SetOverride(r, cfg.section, cfg.count, Count(r, cfg) + 1)
        Relay()
    end)
end

-- the three step tables the editor's blocks draw
BX.STEPS = {
    stacks = { section = "stackcolors", prefix = "sc", count = "scCount", max = 3, label = "From stack",
        base = "From 1", addWord = "+ Add step", top = function(r)
            local n = NS.Bars and NS.Bars.MaxStacksFor and NS.Bars.MaxStacksFor(r)
            return tonumber(n) or 99
        end },
    time = { section = "thresholds", prefix = "thresh", count = "threshCount", max = 3, label = "Time left under",
        addWord = "+ Add step",
        unit = function(r) return On(r, "thresholds", "threshAsSeconds") and "s" or "%" end,
        step = function(r) return r.barKind == "swing" and 0.1 or 1 end },
    health = { section = "healththresholds", prefix = "hpth", count = "hpthCount", max = 3, label = "Threshold (%)",
        base = "Normal", addWord = "+ Add threshold" },
}

-- Time left's two cards. Fill color: the aura's length, the steps and how
-- they count. Text color: the same steps. The card is the switch: no row
-- for Color duration text too. SectionRows: the editor's row builder.
function BX.TimeRows(pg, ctx, vis, SectionRows)
    local function Card(fx)
        return function()
            if not vis() then return false end
            local r = ctx()
            return r ~= nil and BX.FxOpen(r, "Time left") == fx
        end
    end
    local fillVis, textVis = Card("fill"), Card("text")
    SectionRows(pg, "bar", "thresholds", ctx, fillVis, { "threshRef" })
    BX.StepsRows(pg, ctx, fillVis, BX.STEPS.time)
    SectionRows(pg, "bar", "thresholds", ctx, fillVis, { "threshAsSeconds", "threshCdSeconds" })
    BX.StepsRows(pg, ctx, textVis, BX.STEPS.time, true)
end

-- Remove trigger on While: its conditions, both lists' Any / All, the range
-- rule and the Fill color go; the fade's opacity and time stay as they were.
function BX.ClearWhile(r)
    local C = NS.Conditions
    if not (r and r.c) then return end
    for _, list in ipairs({ "showWhen", "fadeWhen" }) do
        if C and C.Clear then C.Clear(r, list) else r.c[list] = nil end
        r.c[list .. "All"] = nil
    end
    if C and C.SetRangeMode then C.SetRangeMode(r, "off") else r.c.rangeMode = nil end
    r.c.fadeTint = nil
    Store.Dirty("style", r.id)
    if C and C.Queue then C.Queue() end
end

-- While's Look: the bar's Fill color while the conditions hold (Bars\AD_BarTint.lua).
function BX.WhileTint(r) return r and r.c and r.c.fadeTint or nil end
function BX.SetWhileTint(r, color)
    r.c = r.c or {}
    r.c.fadeTint = color or nil
    Store.Dirty("style", r.id)
    local C = NS.Conditions
    if C and C.Queue then C.Queue() end
end

function BX.WhileRows(pg, ctx, vis)
    local function Vis()
        if not vis() then return false end
        local r = ctx()
        local T = NS.Bars and NS.Bars.Tint
        return r ~= nil and not r._adMulti and T ~= nil and T.Allowed(r)
    end
    AT.Section(pg, "Look while it holds", { visibleFn = Vis })
    AT.RowToggle(pg, "Fill color",
        function() local r = ctx() return r ~= nil and BX.WhileTint(r) ~= nil end,
        function(on)
            local r = ctx()
            if not r then return end
            BX.SetWhileTint(r, on and (BX.WhileTint(r) or { 0.357, 0.616, 0.941, 1 }) or nil)
            AT.LayoutPage(pg)
        end, Vis)
    AT.RowColor(pg, "Color",
        function() local r = ctx() return (r and BX.WhileTint(r)) or { 0.357, 0.616, 0.941, 1 } end,
        function(c) local r = ctx() if r then BX.SetWhileTint(r, c) end end,
        function()
            if not Vis() then return false end
            local r = ctx()
            return r ~= nil and BX.WhileTint(r) ~= nil
        end, { alpha = true })
end
