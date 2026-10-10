-- AD_SpecialOptions: the Arc Procs rows (internally "special"): the Add window's Arc Procs tab, a special icon's Tracking and Text blocks, a deck bar's Tracking rows and blocks, and the set-pieces rule on every item's Load Conditions tab (retail only).
-- AD_Options calls in behind nil checks (Options.SpecialAddTab / SpecialAddRows / SpecialCanCreate / SpecialMakesBar / SpecialCreate / SpecialWhat / SpecialBarWhat / SpecialIconRows / SpecialTextBlocks / SpecialBarRows / SpecialBarBlocks / SetPiecesRows); every write goes through NS.SpecialIcon, NS.Store and NS.Conditions.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local SO = {}
Options.Special = SO

-- One line per tracker for the Special tab.
SO.NOTES = {
    dw = "A deck of 600 Maelstrom Weapon stacks holding 3 Doom Winds procs.",
    tempest = "A deck of 100 stacks holding 2 Tempest procs.",
    stormunleashed = "A deck of 250 stacks holding 5 Storm Unleashed procs.",
    elemtempest = "A deck of 333 Maelstrom holding 2 Tempest procs.",
    dre = "A deck of 333 stacks holding 2 Ascendance procs.",
    restodre = "The chance climbs 1% per Riptide since the last proc.",
    soulburst = "The chance climbs per qualifying harvest; needs the 2-piece set.",
    pi = "Power Infusion received: an aura icon of the buff on you.",
    ng = "The internal cooldown as a timer: 45 s, less with Natural Harmony.",
}
SO.FORECAST = { "auto", "instant", "blast" }
SO.FORECAST_LABELS = { auto = "Auto (the cast bar decides)", instant = "An instant spender",
    blast = "Elemental Blast" }

-- the tab and its rows exist only where the hub loaded (retail)
function SO.On()
    return NS.IsForever == nil and NS.Special ~= nil
end

function SO.ForClass(def)
    local tag = NS.Store and NS.Store.ClassTag and NS.Store.ClassTag() or nil
    return def.class == nil or def.class == tag
end

-- the class and spec words of a tracker
function SO.WhoWords(def)
    local words = def.class and (def.class:sub(1, 1) .. def.class:sub(2):lower()) or "Every class"
    if def.specs and #def.specs > 0 and GetSpecializationInfoForSpecID then
        local names = {}
        for _, id in ipairs(def.specs) do
            local _, name = GetSpecializationInfoForSpecID(id)
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
        if #names > 0 then words = words .. ", " .. table.concat(names, " / ") end
    end
    return words
end

function Options.SpecialAddTab(tabs)
    if SO.On() then tabs[#tabs + 1] = "Arc Procs" end
end

-- The Arc Procs rows show on their own tab, and under the Icon and Bar tabs'
-- "Arc Proc" kinds.
function SO.Showing(addState)
    return addState.cat == "Arc Procs" or (addState.cat == "Icon" and addState.iconKind == "special")
        or (addState.cat == "Bar" and addState.barKind == "special")
end

-- Made as a deck bar: the Bar tab's kind, or the Special tab picked as one and
-- not added into a group (a bar is always free).
function SO.BarMode(addState)
    if addState.cat == "Bar" then return addState.barKind == "special" end
    if addState.cat ~= "Arc Procs" then return false end
    return addState.specialAs == "bar" and not addState.groupOnly
end

-- The trackers the Special tab offers: the class's, or every one; as deck
-- bars, only those with a deck to draw.
function SO.Offered(addState)
    local list, bars = {}, SO.BarMode(addState)
    NS.Special.Each(function(def, id)
        if (addState.specialAll == true or SO.ForClass(def)) and (not bars or SO.CanBar(def)) then
            list[#list + 1] = { def = def, id = id }
        end
    end)
    return list
end

-- The Add window's Special tab, the template pickers' look (the Wheel and
-- enchant grids): a cell per tracker offered, the pick lit cyan, a tooltip
-- each; a line names the pick, since Tempest and its Elemental twin share
-- their art. Create makes the record.
function Options.SpecialAddRows(pg, owner, addState)
    local AT, COL = NS.AT, NS.AT.COL
    local SP, SI = NS.Special, NS.SpecialIcon
    if not (SP and SI) then return end
    local vis = function() return SO.On() and SO.Showing(addState) and not addState.remGroupId end
    AT.RowDesc(pg, "Pick an Arc Proc, then Create: it lands in the group under Add to, or free.", 20,
        function() return vis() and not SO.BarMode(addState) end)
    AT.RowDesc(pg, "Pick an Arc Proc, then Create: a deck bar fills as the deck is drawn.", 20,
        function() return vis() and SO.BarMode(addState) end)
    -- on its own tab: an icon or a deck bar, first, so the bars are in plain
    -- sight; adding into a group is icons only. A pick with no deck lets go
    -- as a bar.
    local asRow = AT.RowDropdown(pg, owner, "Create as",
        function() return (addState.specialAs == "bar") and "bar" or "icon" end,
        function(v)
            addState.specialAs = (v == "bar") and "bar" or nil
            if SO.BarMode(addState) and not SO.CanBar(addState.specialId and SP.Get(addState.specialId)) then
                addState.specialId = nil
            end
            AT.LayoutPage(pg)
        end,
        function() return { { value = "icon", text = "Icon" }, { value = "bar", text = "Deck bar" } } end,
        function() return vis() and addState.cat == "Arc Procs" and not addState.groupOnly end)
    AT.Tooltip(asRow, "Create as", "A deck bar fills as the deck is drawn, with a mark for each proc.")
    AT.RowToggle(pg, "Show every Arc Proc",
        function() return addState.specialAll == true end,
        function(v)
            addState.specialAll = v or nil
            AT.LayoutPage(pg)
        end,
        vis, "Other classes' Arc Procs too. Each loads only for its own class.")
    local cell, gap, top = Options.TPL_CELL or 32, Options.TPL_GAP or 4, Options.TPL_TOP or 14
    local gridVis = function() return vis() and #SO.Offered(addState) > 0 end
    local row = AT.AddRow(pg, top + cell + gap, gridVis)
    row._tplGrid = true
    local cap = row:CreateFontString(nil, "OVERLAY")
    cap:SetFont(NS.AT.FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText("ARC PROC - click one, then Create")
    row._cells = {}
    local function Cell(i)
        local b = row._cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(cell, cell)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:AddLine(b._title or "", 1, 1, 1)
            GameTooltip:AddLine(b._body or "", COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            addState.specialId = b._adSpecialId
            AT.LayoutPage(pg)
        end)
        row._cells[i] = b
        return b
    end
    row._sync = function()
        local list, cur = SO.Offered(addState), addState.specialId
        for i, it in ipairs(list) do
            local b = Cell(i)
            b.tex:SetTexture(SI.ArtOf(it.def))
            b._adSpecialId, b._picked = it.id, it.id == cur
            b._title = it.def.name
            b._body = SO.WhoWords(it.def) .. ". " .. (SO.NOTES[it.id] or "")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (i - 1) * (cell + gap), -top)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #list + 1, #row._cells do row._cells[i]:Hide() end
    end
    SO.Line(pg, 22, function()
        local def = SO.Picked(addState)
        if not def then return "Nothing picked yet: click an Arc Proc above." end
        return def.name .. "  |cff8fa3b8" .. SO.WhoWords(def) .. "|r   " .. (SO.NOTES[addState.specialId] or "")
    end, gridVis)
    AT.RowDesc(pg, "No Arc Proc is written for your class yet.", 20, function()
        return vis() and not SO.BarMode(addState) and #SO.Offered(addState) == 0
    end)
    AT.RowDesc(pg, "No deck bar is written for your class yet.", 20, function()
        return vis() and SO.BarMode(addState) and #SO.Offered(addState) == 0
    end)
end

-- the trackers with a deck to draw as a bar (the registry's own word)
function SO.CanBar(def)
    return def ~= nil and def.bar == true and not def.isAura
end

-- The pick, when it can be made here: as a deck bar only a tracker with a deck
-- (a pick from the icon kinds can stay behind when the Bar tab opens).
function SO.Picked(addState)
    local def = addState.specialId and NS.Special.Get(addState.specialId)
    if not def or (SO.BarMode(addState) and not SO.CanBar(def)) then return nil end
    return def
end

function Options.SpecialCanCreate(addState)
    return SO.On() and SO.Picked(addState) ~= nil
end

-- Create makes a deck bar: picked as one, for a tracker that has a bar, and
-- not added into a group (a bar is always free).
function Options.SpecialMakesBar(addState)
    local SP = NS.Special
    if not (SO.On() and SO.BarMode(addState)) then return false end
    return SO.CanBar(addState.specialId and SP.Get(addState.specialId))
end

-- the item set of the tracker's pieces, from any piece the client has cached
function SO.SetIDOf(def)
    local GI = C_Item and C_Item.GetItemInfo
    if not (GI and type(def.setItems) == "table") then return nil end
    for itemID in pairs(def.setItems) do
        local setID = select(16, GI(itemID))
        if type(setID) == "number" and not (issecretvalue and issecretvalue(setID)) and setID > 0 then
            return setID
        end
    end
    return nil
end

-- A set's items not in the client's cache yet answer no set: ask for them,
-- and write the set rule once their info lands (the rule waits by record).
SO.setWait = {}
function SO.SetRuleLater(recId, def)
    SO.setWait[recId] = def
    local C = C_Item
    for itemID in pairs(def.setItems) do
        if C and C.RequestLoadItemDataByID then C.RequestLoadItemDataByID(itemID) end
    end
    local f = SO.setFrame
    if not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", function() SO.SetRuleArrived() end)
        SO.setFrame = f
    end
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function SO.SetRuleArrived()
    local Store, Cond = NS.Store, NS.Conditions
    for id, def in pairs(SO.setWait) do
        local setID = SO.SetIDOf(def)
        if setID then
            SO.setWait[id] = nil
            local rec = Store.Get(id)
            if rec and Cond and Cond.SetSetID then
                Cond.SetSetID(rec, setID)
                Cond.SetSetPieces(rec, def.setPieces or 2)
                Store.Dirty("load", id)
            end
        end
    end
    if not next(SO.setWait) and SO.setFrame then SO.setFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

-- A new record loads for the tracker's class and specs (any class and spec
-- for a tracker of no class), its display gates (a talent, the set pieces) as
-- load conditions, its labels as the tracker's templates and its own icon
-- defaults set.
function SO.ScopeToTracker(rec, def)
    local Store, C = NS.Store, NS.Conditions
    rec.c.classes, rec.c.specs = nil, nil
    if def.class then
        if def.specs and #def.specs > 0 and not Store.Specless() then
            local set = {}
            for _, id in ipairs(def.specs) do set[id] = true end
            rec.c.specs = set
        else
            rec.c.classes = { [def.class] = true }
        end
    end
    if def.talentGate and def.talentGate.node then
        Store.SetTalentState(rec, def.talentGate.node, "req", def.talentGate.entry)
    end
    if def.setItems and C and C.SetSetID then
        local setID = SO.SetIDOf(def)
        if setID then
            C.SetSetID(rec, setID)
            C.SetSetPieces(rec, def.setPieces or 2)
        else
            SO.SetRuleLater(rec.id, def)
        end
    end
    if rec.kind == "special" then
        -- the tracker's texts on its own slots 4 to 6, the custom texts free
        for i, tpl in ipairs(def.labels or {}) do
            if i > 3 then break end
            Store.SetOverride(rec, "label", "labelText" .. tostring(i + 3), tpl)
        end
        local d = def.iconDefaults or {}
        if d.strata then Store.SetOverride(rec, "position", "strata", d.strata) end
        if d.cooldownDesaturate ~= nil then Store.SetOverride(rec, "states", "cooldownDesaturate", d.cooldownDesaturate) end
        if d.showEdge ~= nil then Store.SetOverride(rec, "swipe", "showEdge", d.showEdge) end
    end
    Store.Dirty("load", rec.id)
end

function Options.SpecialCreate(addState, dest, layoutId)
    local SP, Store = NS.Special, NS.Store
    local def = SP and SP.Get(addState.specialId)
    if not def then return nil end
    if Options.SpecialMakesBar(addState) then
        local bar = Store.NewBar(layoutId, "special", { tracker = def.id }, def.name)
        if bar then SO.ScopeToTracker(bar, def) end
        return bar
    end
    local kind = def.isAura and "aura" or "special"
    if dest then
        local g = Store.Get(dest)
        if g and not Store.GroupTakes(g, kind) then dest = nil end
    end
    local rec
    if def.isAura then
        local a = def.aura or {}
        rec = Store.NewIcon("aura", { spellID = a.spellID or def.icon, auraType = a.auraType or "buff",
            unit = a.unit or "player" }, dest, layoutId, def.name)
        -- the buff shows while it is up and nothing while it is down
        if rec then Store.SetOverride(rec, "auraMissing", "showWhileMissing", false) end
    else
        rec = Store.NewIcon("special", { tracker = def.id }, dest, layoutId, def.name)
    end
    if not rec then return nil end
    SO.ScopeToTracker(rec, def)
    return rec
end

function Options.SpecialWhat(rec)
    local SI = NS.SpecialIcon
    if SI then return SI.Words(rec) end
    return "Arc Proc: " .. tostring(rec.driver and (rec.driver.tracker or rec.driver.special) or "unknown")
end

-- A deck bar's card line: its tracker's name.
function Options.SpecialBarWhat(rec)
    local SI = NS.SpecialIcon
    local def = SI and SI.Def(rec)
    if def then return def.name end
    return tostring(rec.driver and (rec.driver.tracker or rec.driver.special) or "unknown Arc Proc")
end

-- A dim one-line row whose words come from textFn on every sync.
function SO.Line(pg, h, textFn, visFn)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(pg, h or 22, visFn)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row._sync = function() fs:SetText(textFn() or "") end
    row._adLine = fs
    return row
end

-- ProcTracker's Safe Mythic+ Reset, one switch for every tracker (account-wide).
function SO.SafeResetRow(pg, vis)
    local AT = NS.AT
    return AT.RowToggle(pg, "Safe Mythic+ reset",
        function()
            local SP = NS.Special
            return SP ~= nil and SP.SafeMPlusReset ~= nil and SP.SafeMPlusReset()
        end,
        function(v)
            local SP = NS.Special
            if SP and SP.SetSafeMPlusReset then SP.SetSafeMPlusReset(v) end
        end,
        vis, "On: every Arc Proc resets the moment a key starts, so a reset is never missed. Off: on the gate drop, which keeps the skip working.")
end

-- A special icon's Tracking rows: the tracker, its status, Reset, and the
-- per-tracker settings the registry names.
function Options.SpecialIconRows(pg, ctx, trackVis, owner)
    local AT, COL, Store = NS.AT, NS.AT.COL, NS.Store
    local function SI() return NS.SpecialIcon end
    local function Rec()
        local r = ctx()
        return (r and r.type == "icon" and r.kind == "special") and r or nil
    end
    local function Def()
        local r, S = Rec(), SI()
        return (r and S) and S.Def(r) or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Stamp(row, field, label)
        row._adMeta = { family = "icon", section = "special", field = field, def = { label = label }, baseVis = vis }
    end
    local function Line(h, textFn, visFn) return SO.Line(pg, h, textFn, visFn or vis) end

    AT.Section(pg, "Arc Proc", { visibleFn = vis })
    Line(22, function()
        local def = Def()
        if not def then return "Tracks an unknown Arc Proc: this icon came from a newer version." end
        return "Tracks " .. def.name .. "  (" .. SO.WhoWords(def) .. ")"
    end)
    Line(22, function()
        local r, S = Rec(), SI()
        return (r and S) and ("Status: " .. S.Status(r)) or ""
    end)
    local reset = AT.RowButton(pg, "Reset the count", function()
        local r, S = Rec(), SI()
        if r and S then S.Reset(r) end
    end, vis, 150, nil, true)
    Stamp(reset, "reset", "Reset the count")
    AT.RowDesc(pg, "While this icon is not loaded, its count stops until the next reset.", 20, vis)
    Stamp(SO.SafeResetRow(pg, vis), "safeMPlusReset", "Safe Mythic+ reset")

    -- Doom Winds: the wolf path or the Cooldown Manager's icon
    local dwVis = function()
        local def = Def()
        return vis() and def ~= nil and def.CanSkipCDM ~= nil
            and not (NS.Anchor and NS.Anchor.CDMOff and NS.Anchor.CDMOff())
    end
    local cdm = AT.RowToggle(pg, "Use the Cooldown Manager instead of the wolf",
        function()
            local r = Rec()
            return r ~= nil and r.driver.forceCDM == true
        end,
        function(v)
            local r, S = Rec(), SI()
            if r and S then S.SetDriver(r, "forceCDM", v or nil) end
            AT.LayoutPage(pg)
        end,
        dwVis, "Off: a Nature wolf's arrival credits the proc (Rolling Thunder or Feral Spirit). On: the Cooldown Manager's Doom Winds icon does, which needs the icon shown there.")
    Stamp(cdm, "forceCDM", "Use the Cooldown Manager instead of the wolf")
    local reverify = AT.RowButton(pg, "Find the icon again", function()
        local def, S, r = Def(), SI(), Rec()
        if def and def.Reverify then def.Reverify() end
        if S and r then S.Refeed(r.id) end
    end, function()
        local def = Def()
        return vis() and def ~= nil and def.Reverify ~= nil
    end, 150, nil, true)
    Stamp(reverify, "reverify", "Find the icon again")

    -- the spend the chance assumes
    local spend = AT.RowSlider(pg, "Spender Maelstrom cost",
        function()
            local r = Rec()
            return r and tonumber(r.driver.chanceSpend) or 10
        end,
        function(v)
            local r, S = Rec(), SI()
            if r and S then S.SetDriver(r, "chanceSpend", math.floor(v + 0.5)) end
        end,
        1, 10, 1, false, function()
            local def = Def()
            return vis() and def ~= nil and def.chanceSpend == true
        end)
    Stamp(spend, "chanceSpend", "Spender Maelstrom cost")
    AT.RowDesc(pg, "How many stacks the next spender eats; the chance is for that many draws.", 20, function()
        local def = Def()
        return vis() and def ~= nil and def.chanceSpend == true
    end)
    local fcVis = function()
        local def = Def()
        return vis() and def ~= nil and def.chanceForecast == true
    end
    local forecast = AT.RowDropdown(pg, owner, "Chance assumes",
        function()
            local r = Rec()
            return r and r.driver.chanceForecast or "auto"
        end,
        function(v)
            local r, S = Rec(), SI()
            if r and S then S.SetDriver(r, "chanceForecast", (v ~= "auto") and v or nil) end
        end,
        function()
            local out = {}
            for _, v in ipairs(SO.FORECAST) do out[#out + 1] = { value = v, text = SO.FORECAST_LABELS[v] } end
            return out
        end,
        fcVis)
    Stamp(forecast, "chanceForecast", "Chance assumes")
    Line(22, function()
        local def, r = Def(), Rec()
        if not (def and def.ForecastLabel and r) then return "" end
        return def.ForecastLabel(r.driver) or ""
    end, fcVis)

    -- the set pieces the tracker wants, and where the gate lives
    local setVis = function()
        local def = Def()
        return vis() and def ~= nil and def.Pieces ~= nil
    end
    Line(22, function()
        local def = Def()
        if not (def and def.Pieces) then return "" end
        return ("%d of 5 set pieces equipped."):format(def.Pieces())
    end, setVis)
    AT.RowDesc(pg, "The set gate is the Set Pieces Rule on Load Conditions.", 20, setVis)
    AT.Section(pg, nil)
end

-- A special icon's kind of tracker: a deck (procs drawn from a deck), a
-- counter (a chance that climbs: Resto DRE, Soulburst) or a timer (Nature's
-- Guardian). An unknown tracker (no hub) reads as a deck.
function SO.Shape(rec)
    if not (rec and rec.kind == "special") then return nil end
    local SI = NS.SpecialIcon
    local def = SI and SI.Def and SI.Def(rec)
    if def and def.isTimer then return "timer" end
    if def and def.cap ~= nil and def.procs == nil then return "counter" end
    return "deck"
end
function Options.SpecialIsTimer(rec) return SO.Shape(rec) == "timer" end

-- Each text's usual templates for its Shows pick ("Your own words" types one).
SO.SHOWS = {
    pos = { { "{left}", "Stacks left in the deck" }, { "{drawn}", "Stacks drawn" },
        { "{left}/{size}", "Stacks left, of the deck's size" }, { "{drawn}/{size}", "Stacks drawn, of the deck's size" } },
    procs = { { "{procsLeft}", "Procs left" }, { "{procs}", "Procs used" },
        { "{procsLeft}/{max}", "Procs left, of the deck's" }, { "{procs}/{max}", "Procs used, of the deck's" } },
    count = { { "{count}", "The count" } },
    chance = { { "{chance}", "The chance of a proc" } },
    viol = { { "{viol}", "Violations" } },
}
SO.TOKENS = "{left} {drawn} {size}: the deck. {procs} {procsLeft} {max}: its procs. {chance}: the chance. "
    .. "{viol}: violations. {count}: a counter."

-- A text's Shows pick over its template field: the usual ones, Off (withOff:
-- a text with no switch of its own) and "Your own words", which opens the
-- template to type into. A template that is none of them reads as own words.
function SO.ShowsRows(pg, owner, ctx, vis, section, field, list, withOff)
    local AT, Store = NS.AT, NS.Store
    local own = {}   -- [recId] = true: "Your own words" picked on a usual one
    local function Cur(r)
        local v = r and Store.Resolve(r, section, field)
        return type(v) == "string" and v or ""
    end
    local function Usual(v)
        for _, p in ipairs(list) do
            if p[1] == v then return true end
        end
        return withOff == true and v == ""
    end
    local function Pick(r)
        if not r then return "" end
        local v = Cur(r)
        if own[r.id] or not Usual(v) then return "own" end
        return v
    end
    local row = AT.RowDropdown(pg, owner, "Shows",
        function() return Pick(ctx()) end,
        function(v)
            local r = ctx()
            if not r then return end
            if v == "own" then
                own[r.id] = true
            else
                own[r.id] = nil
                Store.SetOverride(r, section, field, v)
            end
        end,
        function()
            local items = {}
            for _, p in ipairs(list) do items[#items + 1] = { value = p[1], text = p[2] } end
            if withOff then items[#items + 1] = { value = "", text = "Off" } end
            items[#items + 1] = { value = "own", text = "Your own words" }
            return items
        end, vis, function() AT.LayoutPage(pg) end)
    AT.RowInput(pg, "Your own words", function() return Cur(ctx()) end,
        function(v)
            local r = ctx()
            if r then Store.SetOverride(r, section, field, v) end
        end,
        function() return vis() and Pick(ctx()) == "own" end, SO.TOKENS)
    return row
end

-- The Text tab of a special icon: its own texts by name, the custom ones
-- free for anything else. A deck: Deck Position
-- (the stack text), Proc Count (slot 4, Violations on slot 6), Proc Chance
-- (slot 5); a counter: Counter (slot 4), Proc Chance (its stack text). The
-- custom texts 1 to 3 stay free; Nature's Guardian keeps Duration. Built by
-- the icon editor between Count and Custom Text & Keybind, so the sub-tabs
-- come in that order. api: Block, More, SubPush, pg, ctx, win.
function Options.SpecialTextTabs(api)
    local Block, More, SubPush, pg, ctx, win = api.Block, api.More, api.SubPush, api.pg, api.ctx, api.win
    local Store = NS.Store
    local function Shape(want) return function(r) return SO.Shape(r) == want end end
    local deck, counter = Shape("deck"), Shape("counter")
    local function Def(r)
        local SI = NS.SpecialIcon
        return (r and SI and SI.Def) and SI.Def(r) or nil
    end
    local function On(suf)
        local r = ctx()
        local t = r and Store.Resolve(r, "label", "labelText" .. suf)
        return t ~= nil and t ~= ""
    end
    local STACK_LOOK = { "stackFont", "stackSize", "stackColor", "stackOutline", "stackShadow",
        "stackShadowColor", "stackShadowX", "stackShadowY", "stackAnchor", "stackX", "stackY" }
    local function StackWords(word)
        return { stackText = word, stackFont = word .. " font", stackSize = word .. " size",
            stackColor = word .. " color", stackOutline = word .. " outline", stackShadow = word .. " shadow",
            stackShadowColor = word .. " shadow color", stackShadowX = word .. " shadow X",
            stackShadowY = word .. " shadow Y", stackAnchor = word .. " anchor", stackX = word .. " X", stackY = word .. " Y" }
    end
    local function LabelLook(suf)
        return { "labelFont" .. suf, "labelSize" .. suf, "labelColor" .. suf, "labelAnchor" .. suf,
            "labelX" .. suf, "labelY" .. suf, "labelShowReady" .. suf }
    end
    local function LabelWords(suf, word)
        return { ["labelFont" .. suf] = word .. " font", ["labelSize" .. suf] = word .. " size",
            ["labelColor" .. suf] = word .. " color", ["labelAnchor" .. suf] = word .. " anchor",
            ["labelX" .. suf] = word .. " X", ["labelY" .. suf] = word .. " Y",
            ["labelShowReady" .. suf] = "Show " .. word:lower() }
    end
    local PROC_COLORS = { "procColorMode", "procEmptyColor", "procHalfColor", "procFullColor" }
    local CHANCE_COLORS = { "chanceDecimals", "chanceColorMode", "chanceLowPct", "chanceHighPct",
        "chanceColdColor", "chanceMidColor", "chanceHotColor", "chanceLeftCustom", "chanceLeft0Color",
        "chanceLeft1Color", "chanceLeft2Color", "chanceLeft3Color", "chanceLeft4Color", "chanceLeft5Color" }
    -- each text may ride another frame, as the custom texts do
    local function Pin(vis, section, suf, word, stack)
        if not Options.TextPinRows then return end
        Options.TextPinRows(pg, ctx, function()
            local r = ctx()
            if not (vis() and r) then return false end
            if stack then return Store.Resolve(r, "text", "stackText") ~= false end
            return On(suf)
        end, "icon", section, stack and "stackPinTo" or ("labelPinTo" .. suf),
            stack and "stackPinTarget" or ("labelPinTarget" .. suf), win, word)
    end
    local function Opts(applies, labels)
        return { kindOnly = "special", noLook = true, applies = applies, labels = labels, searchLabels = labels ~= nil }
    end

    -- a deck's position: the stack text and its template
    local pos = Block("Text", "Deck Position", "Deck position text", "text", { "stackText" },
        Opts(deck, StackWords("Deck position text")))
    local posOn = function() return pos.vis() and Store.Resolve(ctx(), "text", "stackText") ~= false end
    SO.ShowsRows(pg, win, ctx, posOn, "special", "stackTemplate", SO.SHOWS.pos, false)
    More(pos, "text", STACK_LOOK, { noLook = true, vis = posOn, labels = StackWords("Deck position text"),
        searchLabels = true })
    Pin(posOn, "text", "", "Deck position text", true)
    SubPush("Text", "Deck Position")

    -- a deck's proc count (slot 4), then its violations (slot 6)
    local procs = Block("Text", "Proc Count", "Proc count text", "label", {}, Opts(deck))
    local procsOn = function() return procs.vis() and On("4") end
    SO.ShowsRows(pg, win, ctx, procs.vis, "label", "labelText4", SO.SHOWS.procs, true)
    More(procs, "label", LabelLook("4"), { noLook = true, vis = procsOn, labels = LabelWords("4", "Proc count text") })
    More(procs, "special", PROC_COLORS, { noLook = true, vis = procsOn })
    Pin(procsOn, "label", "4", "Proc count text")
    local viol = Block("Text", "Proc Count", "Violations text", "label", {}, Opts(function(r)
        local d = Def(r)
        return deck(r) and (d == nil or d.viol == true)
    end))
    local violOn = function() return viol.vis() and On("6") end
    SO.ShowsRows(pg, win, ctx, viol.vis, "label", "labelText6", SO.SHOWS.viol, true)
    More(viol, "label", LabelLook("6"), { noLook = true, vis = violOn, labels = LabelWords("6", "Violations text") })
    Pin(violOn, "label", "6", "Violations text")
    SubPush("Text", "Proc Count")

    -- a counter's count (slot 4)
    local cnt = Block("Text", "Counter", "Counter text", "label", {}, Opts(counter))
    local cntOn = function() return cnt.vis() and On("4") end
    SO.ShowsRows(pg, win, ctx, cnt.vis, "label", "labelText4", SO.SHOWS.count, true)
    More(cnt, "label", LabelLook("4"), { noLook = true, vis = cntOn, labels = LabelWords("4", "Counter text") })
    More(cnt, "special", PROC_COLORS, { noLook = true, vis = cntOn })
    Pin(cntOn, "label", "4", "Counter text")
    SubPush("Text", "Counter")

    -- the chance: a deck's slot 5, a counter's stack text
    local ch = Block("Text", "Proc Chance", "Proc chance text", "label", {}, Opts(function(r)
        local d = Def(r)
        return deck(r) and (d == nil or d.chanceSpend == true or d.chanceForecast == true)
    end))
    local chOn = function() return ch.vis() and On("5") end
    SO.ShowsRows(pg, win, ctx, ch.vis, "label", "labelText5", SO.SHOWS.chance, true)
    More(ch, "label", LabelLook("5"), { noLook = true, vis = chOn, labels = LabelWords("5", "Proc chance text") })
    More(ch, "special", CHANCE_COLORS, { noLook = true, vis = chOn })
    Pin(chOn, "label", "5", "Proc chance text")
    local cch = Block("Text", "Proc Chance", "Proc chance text", "text", { "stackText" },
        Opts(counter, StackWords("Proc chance text")))
    local cchOn = function() return cch.vis() and Store.Resolve(ctx(), "text", "stackText") ~= false end
    More(cch, "text", STACK_LOOK, { noLook = true, vis = cchOn, labels = StackWords("Proc chance text"),
        searchLabels = true })
    Pin(cchOn, "text", "", "Proc chance text", true)
    SubPush("Text", "Proc Chance")
end

-- A deck bar's Tracking rows: what it tracks, its status and Reset.
function Options.SpecialBarRows(pg, ctx, trackVis)
    local AT = NS.AT
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "special") and r or nil
    end
    local function Def()
        local r, SI = Rec(), NS.SpecialIcon
        return (r and SI) and SI.Def(r) or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    AT.Section(pg, "Arc Proc", { visibleFn = vis })
    SO.Line(pg, 22, function()
        local def = Def()
        if not def then return "Tracks an unknown Arc Proc: this bar came from a newer version." end
        return "Tracks " .. def.name .. "  (" .. SO.WhoWords(def) .. ")"
    end, vis)
    SO.Line(pg, 22, function()
        local r, SI = Rec(), NS.SpecialIcon
        return (r and SI) and ("Status: " .. SI.Status(r)) or ""
    end, vis)
    local reset = AT.RowButton(pg, "Reset the count", function()
        local r, SI = Rec(), NS.SpecialIcon
        if r and SI then SI.Reset(r) end
    end, vis, 150, nil, true)
    reset._adMeta = { family = "bar", section = "deck", field = "reset", def = { label = "Reset the count" }, baseVis = vis }
    AT.RowDesc(pg, "While this bar is not loaded, its count stops until the next reset.", 20, vis)
    SO.SafeResetRow(pg, vis)._adMeta = { family = "bar", section = "deck", field = "safeMPlusReset",
        def = { label = "Safe Mythic+ reset" }, baseVis = vis }
    AT.Section(pg, nil)
end

-- A deck bar's blocks, through the bar editor's own BarBlock and PushBar so
-- they register, push and search like every block: Deck colors on Appearance >
-- Fill & Colors, Proc marks on Appearance > Ticks, the two texts on Text.
-- Each is the deck section's alone (kinds special), so no other bar shows it.
function Options.SpecialBarBlocks(sub, BarBlock, PushBar, pg, ctx, owner)
    local AT = NS.AT
    if sub == "Fill & Colors" then
        local vis = BarBlock("Deck colors", "deck", "Appearance", {
            "stateFill", "emptyColor", "halfColor", "fullColor", "texEmptyEnabled", "texEmptyColor",
        }, nil, "Fill & Colors", true)
        -- a counter's two ends in the tracker's own words
        local function Words()
            local r, SI = ctx(), NS.SpecialIcon
            local d = (r and SI) and SI.Def(r) or nil
            return d and d.words
        end
        SO.Line(pg, 20, function()
            local w = Words()
            if not (w and w.emptyColor and w.fullColor) then return "" end
            return "Here no procs used means: " .. w.emptyColor .. "; all used: " .. w.fullColor .. "."
        end, function()
            local w = vis() and Words()
            return (w and w.emptyColor and w.fullColor) and true or false
        end)
        return vis
    end
    if sub == "Ticks" then
        return BarBlock("Proc marks", "deck", "Appearance", { "procTicks" }, nil, "Ticks", true)
    end
    if sub == "Text" then
        local note = "Tokens: {left} {drawn} {size} {procs} {procsLeft} {max} {chance} {viol} {count}."
        local posVis = BarBlock("Deck position", "deck", "Text", {
            "posShow", "posTemplate", "posFont", "posSize", "posColorMode", "posColor",
            "posEmptyColor", "posHalfColor", "posFullColor", "posAnchor",
            "posOffsetX", "posOffsetY", "posOutline", "posShadow",
        }, nil, nil, true)
        AT.RowDesc(pg, note, 20, posVis)
        -- each text may ride another frame (Options.TextPinRows)
        local function Pins(vis, pre, show, word)
            if not Options.TextPinRows then return end
            Options.TextPinRows(pg, ctx, function()
                local r = ctx()
                return vis() and r ~= nil and NS.Store.Resolve(r, "deck", show) == true
            end, "bar", "deck", pre .. "PinTo", pre .. "PinTarget", owner, word)
        end
        Pins(posVis, "pos", "posShow", "Deck position")
        PushBar(pg, ctx, "deck", posVis)
        local procVis = BarBlock("Proc count", "deck", "Text", {
            "procShow", "procTemplate", "procFont", "procSize", "procColorMode", "procColor",
            "procEmptyColor", "procHalfColor", "procFullColor", "procAnchor",
            "procOffsetX", "procOffsetY", "procOutline", "procShadow",
        }, nil, nil, true)
        AT.RowDesc(pg, note, 20, procVis)
        Pins(procVis, "proc", "procShow", "Proc count")
        PushBar(pg, ctx, "deck", procVis)
        return posVis, procVis
    end
end

-- The set-pieces rule, a load rule of every item on retail: the sets on the
-- worn gear are offered, the stored one kept.
function Options.SetPiecesRows(pg, ctx, tabVisible, uiStore, owner)
    local AT, COL, C = NS.AT, NS.AT.COL, NS.Conditions
    if NS.IsForever == true or not (C and C.SetRule) then return end
    local vis = function() return tabVisible() and ctx() ~= nil end
    AT.Section(pg, "Set Pieces Rule", { collapsible = true, store = uiStore, visibleFn = vis })
    local row = AT.AddRow(pg, 22, vis)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, 11, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row._sync = function()
        local r = ctx()
        local id, n = C.SetRule(r)
        if not id then
            fs:SetText("No set rule.")
        else
            fs:SetText(("Loads only while you wear at least %d of %s (%d worn now)."):format(
                n, C.SetName(id), C.SetPiecesWorn(id)))
        end
    end
    row._adSearch = function() return { "Set Pieces Rule", "Wearing pieces of a set" } end
    AT.RowDropdown(pg, owner, "Wearing pieces of",
        function()
            local r = ctx()
            return (r and r.c and r.c.setID) or 0
        end,
        function(v)
            local r = ctx()
            if not r then return end
            C.SetSetID(r, (v ~= 0) and v or nil)
            if v ~= 0 and not r.c.setPieces then C.SetSetPieces(r, 2) end
            AT.LayoutPage(pg)
        end,
        function()
            local out = { { value = 0, text = "No set rule" } }
            local r = ctx()
            local have = r and r.c and r.c.setID
            local seen = false
            for _, s in ipairs(C.WornSets()) do
                out[#out + 1] = { value = s.id, text = s.name }
                if s.id == have then seen = true end
            end
            if have and not seen then out[#out + 1] = { value = have, text = C.SetName(have) } end
            return out
        end,
        vis)
    AT.RowDropdown(pg, owner, "At least this many pieces",
        function()
            local r = ctx()
            return (r and r.c and r.c.setPieces) or 2
        end,
        function(v)
            local r = ctx()
            if r then C.SetSetPieces(r, v) end
            AT.LayoutPage(pg)
        end,
        function()
            local out = {}
            for n = 1, 5 do out[#out + 1] = { value = n, text = tostring(n) } end
            return out
        end,
        function()
            local r = ctx()
            return vis() and r.c ~= nil and r.c.setID ~= nil
        end)
    AT.RowDesc(pg, "The sets on the gear you wear now are listed; with fewer pieces on, the item goes inert.", 20, vis)
    AT.Section(pg, nil)
end
