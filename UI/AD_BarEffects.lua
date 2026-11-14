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

BX.SIDE_W, BX.GAP = 224, 10
BX.ROW_H, BX.ADD_H, BX.CHIP_H, BX.TEXT_X = 56, 26, 16, 58
-- the icon Effects tab's measures: title strip, folder tab, the panel's inset
BX.STRIP_H, BX.TAB_H, BX.PAD = 22, 26, 10
-- the page's 18 between sections: 10 under the head, none under the tab
BX.GAP_FIX, BX.GAP_TAB = 8, 18
BX.TAB = "Effects"

local function R(r, section, field) return Store.Resolve(r, section, field) end
local function On(r, section, field) return R(r, section, field) == true end

-- the steps of a saved band list, in their own colours
local function Steps(r, section, prefix, count, unit)
    local out = {}
    local n = tonumber(R(r, section, count)) or 1
    for i = 2, 1 + n do
        local v = tonumber(R(r, section, prefix .. i .. "Value"))
        if v and v > 0 then
            out[#out + 1] = { text = string.format("%g", v) .. (unit or ""), color = R(r, section, prefix .. i .. "Color") }
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
        on = function(r) return On(r, "stackcolors", "scEnabled") or On(r, "stackcolors", "maxColorEnabled") end,
        chips = function(r) return Steps(r, "stackcolors", "sc", "scCount") end,
        off = { { "stackcolors", "scEnabled" }, { "stackcolors", "maxColorEnabled" } } },
    ["Points"] = { when = "Colors each point by its place", line = "Colors each point by its place",
        on = function(r) return On(r, "stackcolors", "scEnabled") end,
        chips = function(r) return Steps(r, "stackcolors", "sc", "scCount") end,
        off = { { "stackcolors", "scEnabled" }, { "stackcolors", "maxColorEnabled" } } },
    ["Time left"] = { when = "Colors the bar at each time left", line = "Colors the bar at each time left",
        on = function(r) return On(r, "thresholds", "threshEnabled") end,
        chips = function(r) return Steps(r, "thresholds", "thresh", "threshCount", On(r, "thresholds", "threshAsSeconds") and " s" or "%") end,
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

function BX.Listed(r, avail)
    local out = {}
    for _, s in ipairs(avail) do
        if BX.IsListed(r, s) then out[#out + 1] = s end
    end
    return out
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

-- Builds the list, the head and the picker. avail(): the Effects tab's
-- sub-tabs for the open bar; secs(): the editor's sub-tab picks.
function BX.Build(pg, ctx, vis, avail, secs, under)
    local function Relay() AT.LayoutPage(pg) end
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
    local Kit = Options.EffectsTab.Kit
    local GREEN, GREEN_EDGE = { 0.482, 0.847, 0.561 }, { 0.243, 0.478, 0.267 }
    local add = CreateFrame("Button", nil, col)
    add:SetSize(BX.SIDE_W - 20, BX.ADD_H)
    add._dash = Kit.DashEdge(add)
    add._dash:Lay(BX.SIDE_W - 20, BX.ADD_H, GREEN_EDGE)
    add.fs = Font(add, 12, GREEN)
    add.fs:SetPoint("LEFT", 10, 0)
    add.fs:SetText(Tr("+ Add a trigger"))
    add:SetScript("OnEnter", function() add._dash:Lay(BX.SIDE_W - 20, BX.ADD_H, GREEN) end)
    add:SetScript("OnLeave", function() add._dash:Lay(BX.SIDE_W - 20, BX.ADD_H, BX.picking and GREEN or GREEN_EDGE) end)
    add:SetScript("OnClick", function()
        AT.CloseDropdown()
        BX.picking = not BX.picking
        Relay()
    end)
    AT.Tooltip(add, "Add a trigger", "What else can change this bar's look or glow.")
    BX.add = add

    local function Row(i)
        local rw = rows[i]
        if rw then return rw end
        rw = CreateFrame("Button", nil, col)
        rw._fill = Tex(rw)
        rw._fill:SetAllPoints()
        rw._edge = Tex(rw, "BORDER")
        rw._edge:SetPoint("TOPLEFT")
        rw._edge:SetPoint("BOTTOMLEFT")
        rw._edge:SetWidth(2)
        rw._miniBg = Tex(rw, "BORDER")
        rw._miniBg:SetSize(38, 10)
        rw._miniBg:SetPoint("LEFT", 10, 0)
        rw._miniBg:SetVertexColor(0, 0, 0, 1)
        rw._miniFill = Tex(rw, "ARTWORK")
        rw._miniFill:SetPoint("TOPLEFT", rw._miniBg, "TOPLEFT", 1, -1)
        rw._miniFill:SetPoint("BOTTOMRIGHT", rw._miniBg, "BOTTOMRIGHT", -1, 1)
        rw._name = Font(rw, 13)
        rw._chipPool = {}
        rw:SetScript("OnClick", function(self)
            AT.CloseDropdown()
            BX.picking = false
            secs()[BX.TAB] = self._sub
            Relay()
        end)
        rows[i] = rw
        return rw
    end

    -- a chip: a square of its colour and its words, in a thin box
    local function Chip(rw, j)
        local c = rw._chipPool[j]
        if c then return c end
        c = CreateFrame("Frame", nil, rw, "BackdropTemplate")
        AT.Skin(c, COL.well, COL.line2)
        c:SetBackdropColor(0, 0, 0, 0)
        c:SetHeight(BX.CHIP_H)
        c._dot = Tex(c, "ARTWORK")
        c._dot:SetSize(8, 8)
        c._dot:SetPoint("LEFT", 4, 0)
        c._fs = Font(c, 10, COL.dim)
        rw._chipPool[j] = c
        return c
    end
    -- lays a row's chips under its name and returns how many lines they took
    local function LayChips(rw, list, width)
        local x, line = 0, 0
        for j, ch in ipairs(list) do
            local c = Chip(rw, j)
            c._fs:SetText(ch.text)
            local hasDot = ch.color ~= nil
            c._dot:SetShown(hasDot)
            if hasDot then c._dot:SetVertexColor(ch.color[1], ch.color[2], ch.color[3], 1) end
            local lead = hasDot and 16 or 5
            c._fs:ClearAllPoints()
            c._fs:SetPoint("LEFT", lead, 0)
            local w = math.ceil(lead + (c._fs:GetStringWidth() or 0) + 5)
            if x > 0 and x + w > width then
                x, line = 0, line + 1
            end
            c:SetWidth(w)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", rw._name, "BOTTOMLEFT", x, -3 - line * (BX.CHIP_H + 3))
            c:Show()
            x = x + w + 4
        end
        for j = #list + 1, #rw._chipPool do rw._chipPool[j]:Hide() end
        return #list > 0 and line + 1 or 0
    end

    AT.SetLead(pg, col, BX.SIDE_W, BX.GAP, vis, function()
        local r = ctx()
        if not r then return 0 end
        local a = avail(BX.TAB)
        local cur = BX.Normalize(r, a, secs())
        local list = BX.Listed(r, a)
        local y = -1
        for i, s in ipairs(list) do
            local rw = Row(i)
            local on = s == cur and not BX.picking
            rw._sub = s
            rw:ClearAllPoints()
            rw:SetPoint("TOPLEFT", col, "TOPLEFT", 1, y)
            rw:SetPoint("TOPRIGHT", col, "TOPRIGHT", -1, y)
            local d = BX.Def(s)
            local list = d.chips and d.chips(r)
            local lines = LayChips(rw, type(list) == "table" and list or {}, BX.SIDE_W - BX.TEXT_X - 10)
            -- the name and its chips as one block, centred on the row's height,
            -- with the swatch on the same middle
            local block = 16 + (lines > 0 and (3 + lines * (BX.CHIP_H + 3) - 3) or 0)
            local rowH = math.max(BX.ROW_H, block + 16)
            rw:SetHeight(rowH)
            local top = math.floor((rowH - block) / 2)
            rw._name:ClearAllPoints()
            rw._name:SetPoint("TOPLEFT", BX.TEXT_X, -top)
            rw._name:SetPoint("RIGHT", -8, 0)
            rw._name:SetHeight(16)
            rw._name:SetJustifyV("MIDDLE")
            local mc = BX.MiniColor(r, s)
            rw._miniFill:SetVertexColor(mc[1], mc[2], mc[3], 1)
            local bg = on and COL.panel or COL.well
            rw._fill:SetVertexColor(bg[1], bg[2], bg[3], 1)
            rw._edge:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            rw._edge:SetShown(on)
            local ink = on and COL.ink or COL.dim
            rw._name:SetTextColor(ink[1], ink[2], ink[3])
            rw._name:SetText(Tr(s))
            rw:Show()
            y = y - rowH
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", col, "TOPLEFT", 9, y - 9)
        add:SetShown(#BX.Offered(r, a) > 0)
        local h = -y + (add:IsShown() and (9 + BX.ADD_H + 9) or 1)
        col:SetHeight(h)
        if BX.LayBody then BX.LayBody() end
        return h
    end)

    -- the open trigger's head: its name, when it holds, Remove trigger
    local function HeadVis()
        if not vis() then return false end
        local r = ctx()
        if not r then return false end
        BX.Ensure(r, avail, secs())
        return not BX.picking and secs()[BX.TAB] ~= nil
    end
    AT.Section(pg, nil, { visibleFn = HeadVis })
    local head = AT.AddRow(pg, 44, HeadVis)
    BX.head = head
    head._fill = Tex(head)
    head._fill:SetAllPoints()
    head._fill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    head._edge = Kit.Edges(head)
    head._name = Font(head, 14, COL.ink)
    head._name:SetPoint("LEFT", 12, 0)
    head._when = Font(head, 11, COL.faint)
    head._when:SetPoint("LEFT", head._name, "RIGHT", 10, 0)
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
        BX.AskRemove(sub, function()
            -- the bar and trigger it was asked for, even if the panel moved on
            BX.Remove(r, sub, secs(), avail(BX.TAB))
            Store.Dirty("style", r.id)
            Relay()
        end)
    end)
    head._sync = function()
        local s = secs()[BX.TAB]
        if not s then return end
        head._name:SetText(Tr(s))
        head._when:SetText(Tr(BX.Def(s).when or ""))
        head._rm:SetShown(BX.Removable(s))
        head._edge:Lay()
        head._edge:Color(COL.line)
    end
    -- the trigger's effect: a folder tab open into its panel, as on an icon;
    -- While's rules are the page's own sections under its head instead
    local function FolderVis()
        if not HeadVis() then return false end
        return BX.Def(secs()[BX.TAB]).folder ~= false
    end
    AT.Section(pg, nil, { visibleFn = FolderVis })
    fxSec = pg._curSection
    local fxRow = AT.AddRow(pg, BX.TAB_H + BX.PAD, FolderVis)
    BX.fxRow = fxRow
    local tab = CreateFrame("Frame", nil, fxRow)
    BX.fxTab = tab
    tab:SetHeight(BX.TAB_H)
    tab:SetPoint("BOTTOMLEFT", BX.PAD, 0)
    tab._fill = Tex(tab)
    tab._fill:SetAllPoints()
    tab._fill:SetVertexColor(COL.box[1], COL.box[2], COL.box[3], 1)
    tab._edge = Kit.Edges(tab)
    tab._top = Tex(tab, "ARTWORK")
    tab._top:SetPoint("TOPLEFT", 1, -1)
    tab._top:SetPoint("TOPRIGHT", -1, -1)
    tab._top:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    tab._fs = Font(tab, 11, COL.ink)
    tab._fs:SetPoint("LEFT", 27, 0)
    tab._glyph = Options.EditorTabs.Glyph(tab, "look")
    tab._glyph:SetScale(0.86)
    tab._glyph:SetPoint("LEFT", 9 / 0.86, 0)
    tab._glyph:SetColor(COL.arc)
    fxRow._sync = function()
        local s = secs()[BX.TAB]
        if not (s and FolderVis()) then return end
        tab._fs:SetText(Tr(BX.Def(s).tab or "Look"))
        tab:SetWidth(math.ceil(27 + (tab._fs:GetStringWidth() or 0) + 12))
        tab._top:SetHeight(2 * AT.Hairline(tab))
        tab._edge:Lay()
        tab._edge:Color(COL.line, { t = true, l = true, r = true })
    end

    -- the panel round a trigger's blocks: the page lays its sections edge to
    -- edge, so they are set in here once the page has placed them
    local body = CreateFrame("Frame", nil, pg)
    BX.body = body
    body:SetFrameLevel(math.max(0, (pg:GetFrameLevel() or 1)))
    body._fill = Tex(body)
    body._fill:SetAllPoints()
    body._fill:SetVertexColor(COL.panel[1], COL.panel[2], COL.panel[3], 1)
    body._edge = Kit.Edges(body)
    body:Hide()
    local accentF = CreateFrame("Frame", nil, pg)
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
        body:SetShown(first ~= nil)
        accentF:SetShown(first ~= nil)
        if not first then return end
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
        body:SetPoint("BOTTOMRIGHT", last.box, "BOTTOMRIGHT", BX.PAD, -BX.PAD)
        body._edge:Lay()
        body._edge:Color(COL.line)
        local top = first.hit or first.band or first.box
        accentF:ClearAllPoints()
        accentF:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
        accentF:SetPoint("BOTTOMLEFT", last.box, "BOTTOMLEFT", 0, 0)
        accentF:SetWidth(3 * AT.Hairline(accentF))
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
-- colour, a quiet x), the fill colour's row first where cfg.base, + Add.
function BX.StepsRows(pg, ctx, vis, cfg)
    local Schema = NS.Schema
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
        row._adMeta = { family = "bar", section = cfg.section, field = vf, def = defs[vf], baseVis = vis }
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
        local x = AT.MakeQuietButton(row, "x", 20)
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
    local add = AT.MakeSmallButton(row, Tr(cfg.addWord), 120)
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
        base = "From 1", addWord = "+ Add color", top = function(r)
            local n = NS.Bars and NS.Bars.MaxStacksFor and NS.Bars.MaxStacksFor(r)
            return tonumber(n) or 99
        end },
    time = { section = "thresholds", prefix = "thresh", count = "threshCount", max = 3, label = "Time left under",
        addWord = "+ Add threshold",
        unit = function(r) return On(r, "thresholds", "threshAsSeconds") and "s" or "%" end,
        step = function(r) return r.barKind == "swing" and 0.1 or 1 end },
    health = { section = "healththresholds", prefix = "hpth", count = "hpthCount", max = 3, label = "Threshold (%)",
        base = "Normal", addWord = "+ Add threshold" },
}

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
