-- AD_SpecialOptions: the Special Aura rows: the Add window's Special tab, a special icon's Tracking and Text blocks, and the set-pieces rule on every item's Load Conditions tab (retail only).
-- AD_Options calls in behind nil checks (Options.SpecialAddTab / SpecialAddRows / SpecialCanCreate / SpecialCreate / SpecialWhat / SpecialIconRows / SpecialTextBlocks / SetPiecesRows); every write goes through NS.SpecialIcon, NS.Store and NS.Conditions.
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
    if SO.On() then tabs[#tabs + 1] = "Special" end
end

-- The Add window's Special tab: one row per tracker registered for the class
-- (or every tracker), a pick, then Create makes the record.
function Options.SpecialAddRows(pg, owner, addState)
    local AT, COL = NS.AT, NS.AT.COL
    local SP, SI = NS.Special, NS.SpecialIcon
    if not (SP and SI) then return end
    local vis = function() return SO.On() and addState.cat == "Special" and not addState.remGroupId end
    AT.RowDesc(pg, "Pick a tracker, then Create: it lands in the group under Add to, or free.", 20, vis)
    AT.RowToggle(pg, "Show every tracker",
        function() return addState.specialAll == true end,
        function(v)
            addState.specialAll = v or nil
            AT.LayoutPage(pg)
        end,
        vis, "Other classes' trackers too. Each loads only for its own class.")
    SP.Each(function(def, id)
        local rvis = function() return vis() and (addState.specialAll == true or SO.ForClass(def)) end
        local row = AT.AddRow(pg, 42, rvis)
        local art = row:CreateTexture(nil, "ARTWORK")
        art:SetSize(30, 30)
        art:SetPoint("LEFT", 10, 0)
        art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetFont(STANDARD_TEXT_FONT, 12, "")
        name:SetPoint("TOPLEFT", art, "TOPRIGHT", 8, -1)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local note = row:CreateFontString(nil, "OVERLAY")
        note:SetFont(STANDARD_TEXT_FONT, 10, "")
        note:SetPoint("BOTTOMLEFT", art, "BOTTOMRIGHT", 8, 1)
        note:SetPoint("RIGHT", row, "RIGHT", -76, 0)
        note:SetJustifyH("LEFT")
        note:SetWordWrap(false)
        note:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local pick = AT.MakeSmallButton(row, "Pick", 60)
        pick:SetPoint("RIGHT", -10, 0)
        pick:SetScript("OnClick", function()
            AT.CloseDropdown()
            addState.specialId = id
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(pick, def.name, SO.NOTES[id] or "")
        row._adSpecialId = id
        row._adPick = pick
        row._sync = function()
            art:SetTexture(SI.ArtOf(def))
            name:SetText(def.name .. "  |cff8fa3b8" .. SO.WhoWords(def) .. "|r")
            note:SetText(SO.NOTES[id] or "")
            local on = addState.specialId == id
            pick.fs:SetText(on and "Picked" or "Pick")
            if on then
                pick.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
            else
                pick.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            end
        end
    end)
    AT.RowDesc(pg, "No tracker is written for your class yet.", 20, function()
        if not vis() or addState.specialAll then return false end
        local any = false
        SP.Each(function(def) if SO.ForClass(def) then any = true end end)
        return not any
    end)
end

function Options.SpecialCanCreate(addState)
    local SP = NS.Special
    return SO.On() and addState.specialId ~= nil and SP.Get(addState.specialId) ~= nil
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

-- A new record loads for the tracker's class and specs, its display gates
-- (a talent, the set pieces) as load conditions, its labels as the tracker's
-- templates and its own icon defaults set.
function SO.ScopeToTracker(rec, def)
    local Store, C = NS.Store, NS.Conditions
    if def.class then
        rec.c.classes, rec.c.specs = nil, nil
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
        end
    end
    if rec.kind == "special" then
        for i, tpl in ipairs(def.labels or {}) do
            if i > 3 then break end
            Store.SetOverride(rec, "label", "labelText" .. (i == 1 and "" or tostring(i)), tpl)
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
    return "special: " .. tostring(rec.driver and (rec.driver.tracker or rec.driver.special) or "unknown")
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
    local function Line(h, textFn, visFn)
        local row = AT.AddRow(pg, h or 22, visFn or vis)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "")
        fs:SetPoint("LEFT", 10, 0)
        fs:SetPoint("RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        row._sync = function() fs:SetText(textFn() or "") end
        row._adLine = fs
        return row
    end

    AT.Section(pg, "Special Aura", { visibleFn = vis })
    Line(22, function()
        local def = Def()
        if not def then return "Tracks an unknown tracker: this icon came from a newer version." end
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

    -- Doom Winds: the wolf path or the Cooldown Manager's icon
    local dwVis = function()
        local def = Def()
        return vis() and def ~= nil and def.CanSkipCDM ~= nil
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

-- The special icon's Text blocks, through the icon editor's Block: the stack
-- template on Text > Stacks, the proc and chance colours on Custom Text & Keybind.
function Options.SpecialTextBlocks(Block, sub, pg, ctx)
    local AT, COL = NS.AT, NS.AT.COL
    if sub == "Stacks" then
        local def = Block("Text", "Stacks", "Deck text", "special", { "stackTemplate" },
            { kindOnly = "special", noLook = true })
        AT.RowDesc(pg, "Tokens: {left} {drawn} {size} {procs} {procsLeft} {max} {chance} {viol} {count}.", 20, def.vis)
        return def
    end
    if sub == "Custom Text & Keybind" then
        local def = Block("Text", "Custom Text & Keybind", "Proc and chance colors", "special", {
            "procColorMode", "procEmptyColor", "procHalfColor", "procFullColor",
            "chanceDecimals", "chanceColorMode", "chanceLowPct", "chanceHighPct",
            "chanceColdColor", "chanceMidColor", "chanceHotColor",
            "chanceLeftCustom", "chanceLeft0Color", "chanceLeft1Color", "chanceLeft2Color",
            "chanceLeft3Color", "chanceLeft4Color", "chanceLeft5Color",
        }, { kindOnly = "special", noLook = true })
        AT.RowDesc(pg, "A label with {procs}, {procsLeft} or {count} takes the proc count colors; one with {chance} the chance colors.", 20, def.vis)
        -- the tracker's own words for the two ends
        local row = AT.AddRow(pg, 20, def.vis)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "")
        fs:SetPoint("LEFT", 10, 0)
        fs:SetPoint("RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        row._sync = function()
            local r, SI = ctx(), NS.SpecialIcon
            local d = (r and SI) and SI.Def(r) or nil
            local w = d and d.words
            if w and w.emptyColor and w.fullColor then
                fs:SetText("Here none used means: " .. w.emptyColor .. "; all used: " .. w.fullColor .. ".")
            else
                fs:SetText("")
            end
        end
        return def
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
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
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
