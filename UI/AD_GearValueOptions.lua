-- AD_GearValueOptions: the Gear Value card on the Modules page and its page: the scales, the picked scale, a preview.
-- Reads NS.GearValue at call time; the engine owns the scales, which ones show and the tooltip lines.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local COL, Tr, LAY = AT.COL, AT.Tr, AT.LAY
local MOD = Options.Modules

-- The page's helpers and state on one table, so the file keeps few locals.
local P = { panel = "edit", items = {}, subs = {}, scanDirty = true, tipDirty = true }
NS.GearValuePage = P

-- Two columns, the scale editor and the preview; a narrower page stacks them.
P.COLS, P.GAP, P.MIN_SPAN = { 610, 272 }, 12, 760
P.CONFIRM_FOR = 4
P.STEP_SMALL, P.STEP_BIG, P.BIG_FROM = 0.05, 0.5, 5
P.BOX_W, P.CLUSTER_W = 62, 114
P.PASTE_H = 140
-- the preview tooltip's inset from its row on each side (the row's labels sit at 10)
P.TIP_INSET = 10
-- the weights go two to a row from this row width; the show checks sit this far apart
P.TWO_UP_W, P.CELL_GAP, P.SHOW_GAP, P.SCALE_DD_W = 480, 24, 18, 220
-- Forever has no spec list to read; a scale's spec is the talent tree's English name, as weights strings write it.
P.FOREVER_SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}

function P.Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Capitals the way the theme writes a plain section title: other scripts stay as they are.
function P.Upper(s)
    if type(s) ~= "string" or s:find("[\128-\255]") then return s end
    return s:upper()
end

function P.TextW(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    return type(w) == "number" and w or 0
end

-- A weight as the page writes it: two decimals under 10, one from 10, no trailing zeros.
function P.Num(v)
    v = tonumber(v) or 0
    if v == 0 then return "0" end
    local s = string.format(math.abs(v) >= 10 and "%.1f" or "%.2f", v)
    s = s:gsub("%.?0+$", "")
    return s
end

function P.Relayout()
    if P.page then AT.LayoutPage(P.page) end
end

-- Anything the tooltip lines read changed: the preview shows again.
function P.Changed()
    P.tipDirty = true
    P.Relayout()
end

-- The talent group (Forever) or spec (retail) whose show set the page edits.
function P.Group()
    local G = NS.GearValue
    return P.group or (G and G.Group()) or 1
end

function P.Own(s)
    return s ~= nil and s.kind == "own"
end

-- The picked scale; with none picked, the first one the group shows, else the first.
function P.Cur()
    local G = NS.GearValue
    if not G then return nil end
    local s = P.sel and G.Get(P.sel)
    if s then return s end
    local list = G.Scales()
    local g = P.Group()
    for _, x in ipairs(list) do
        if G.Shown(g, x.id) then s = x break end
    end
    s = s or list[1]
    P.sel = s and s.id or nil
    return s
end

function P.GroupWord(g)
    local G = NS.GearValue
    if G and G.Game() == "retail" then
        local SI = C_SpecializationInfo
        local get = SI and SI.GetSpecializationInfo
        local name
        if get then name = select(2, get(g)) end
        if type(name) == "string" and name ~= "" and not P.Secret(name) then return name end
        return Tr("Spec %d"):format(g)
    end
    -- the game's own words for its two talent groups; an if, since an unset second word must not read as the first
    local word
    if g == 2 then word = DUAL_SPEC_SECONDARY else word = DUAL_SPEC_PRIMARY end
    if type(word) == "string" and word ~= "" then return word end
    return g == 2 and Tr("Secondary") or Tr("Primary")
end

function P.GroupItems()
    local G = NS.GearValue
    local n = 2
    if G and G.Game() == "retail" then
        n = (GetNumSpecializations and GetNumSpecializations()) or 0
        if type(n) ~= "number" or n < 1 then n = 1 end
    end
    local active = G and G.Group()
    local out = {}
    for g = 1, n do
        local word = P.GroupWord(g)
        if g == active then word = Tr("%s (active)"):format(word) end
        out[g] = { value = g, text = word, raw = true }
    end
    return out
end

-- The class's specs as names: the game's list on retail, the talent trees on Forever, then any spec a scale names.
function P.SpecItems()
    local G = NS.GearValue
    local out, seen = {}, {}
    local function add(n)
        if type(n) == "string" and n ~= "" and not P.Secret(n) and not seen[n] then
            seen[n] = true
            out[#out + 1] = { value = n, text = n, raw = true }
        end
    end
    if not G then return out end
    if G.Game() == "retail" then
        local SI = C_SpecializationInfo
        local get = SI and SI.GetSpecializationInfo
        local n = (GetNumSpecializations and GetNumSpecializations()) or 0
        if type(n) ~= "number" then n = 0 end
        for i = 1, n do
            if get then add((select(2, get(i)))) end
        end
    else
        for _, s in ipairs(P.FOREVER_SPECS[G.ClassToken() or ""] or {}) do add(s) end
    end
    for _, s in ipairs(G.Scales()) do add(s.spec) end
    return out
end

-- A button says how it went for a moment, then wears its own word again.
function P.Flash(btn, text, back, secs, after)
    btn:SetLabel(text)
    local gen = (btn._gvGen or 0) + 1
    btn._gvGen = gen
    C_Timer.After(secs, function()
        if btn._gvGen ~= gen then return end
        btn:SetLabel(back)
        if after then after() end
    end)
end

function P.Disarm()
    if not P.delArmed then return end
    P.delArmed = nil
    local b = P.delBtn
    if b then
        b._gvGen = (b._gvGen or 0) + 1
        b:SetLabel("Delete")
    end
end

-- A box still being typed in writes to the scale it was opened on before the page moves on.
function P.Unfocus()
    if P.focusBox then P.focusBox:ClearFocus() end
    if P.nameBox and P.nameBox:HasFocus() then P.nameBox:ClearFocus() end
end

function P.Select(id)
    AT.CloseDropdown()
    P.Unfocus()
    P.Disarm()
    -- another scale: its own goals, from its first
    P.sel, P.goalKind = id, nil
    P.panel = "edit"
    P.Relayout()
end

function P.NewScale()
    local G = NS.GearValue
    if not G then return end
    P.Unfocus()
    local cur = P.Cur()
    local id = G.NewScale(Tr("New scale"), { spec = cur and cur.spec or nil })
    if not id then return end
    P.Disarm()
    P.sel, P.panel = id, "edit"
    P.Changed()
end

function P.CopyOwn()
    local G = NS.GearValue
    local cur = P.Cur()
    if not (G and cur) then return end
    P.Unfocus()
    local id = G.NewScale(Tr("%s, my copy"):format(cur.spec or cur.name or "?"), cur)
    if not id then return end
    P.Disarm()
    P.sel, P.panel = id, "edit"
    P.Changed()
end

function P.DeleteClick(b)
    local G = NS.GearValue
    local cur = P.Cur()
    if not (G and P.Own(cur)) then return end
    if not P.delArmed then
        P.delArmed = true
        P.Flash(b, "Press again to delete", "Delete", P.CONFIRM_FOR, function()
            P.delArmed = nil
            P.Relayout()
        end)
        P.Relayout()
        return
    end
    P.Unfocus()
    P.Disarm()
    G.Delete(cur.id)
    P.sel = nil
    P.Changed()
end

function P.OpenImport()
    P.Unfocus()
    P.Disarm()
    P.panel, P.importWhy = "import", nil
    P.Relayout()
    if P.impBox then P.impBox:SetFocus() end
end

function P.DoImport()
    local G = NS.GearValue
    local box = P.impBox
    if not (G and box) then return end
    local pick, why
    local data = G.Data()
    -- each string brings its scale whole: weights and goals
    for _, r in ipairs(G.ImportAll(box:GetText() or "")) do
        if r.id then
            -- an update keeps the scale's mark and where it shows; the engine keeps
            -- where a new scale came from only as this mark
            if not r.updated then
                local s = data and data.gearScales[r.id]
                if s then s.imported = true end
                if G.Get(r.id) then G.SetShown(P.Group(), r.id, true) end
            end
            if G.Get(r.id) then pick = r.id elseif not pick then why = "class" end
        elseif not why then
            why = r.why or "format"
        end
    end
    if not pick and why ~= "class" then
        P.importWhy = why or "format"
        P.Relayout()
        return
    end
    box:SetText("")
    box:ClearFocus()
    if pick then
        P.sel, P.panel, P.importWhy = pick, "edit", nil
    else
        P.importWhy = "class"
    end
    P.Changed()
end

function P.ImportWhyText()
    if P.importWhy == "class" then return Tr("Imported. It is for another class and shows on that class's characters.") end
    return Tr("That text is not a weights string.")
end

function P.OpenExport()
    local G = NS.GearValue
    local cur = P.Cur()
    if not (G and cur) then return end
    P.Unfocus()
    P.Disarm()
    P.expText = G.Export(cur)
    P.panel = "export"
    P.Relayout()
    local box = P.expBox
    if box then
        box:SetText(P.expText)
        box:SetFocus()
        box:HighlightText()
    end
end

function P.CloseSide()
    if P.impBox then P.impBox:ClearFocus() end
    if P.expBox then P.expBox:ClearFocus() end
    P.panel, P.importWhy = "edit", nil
    P.Relayout()
end

-- Bag and worn gear

-- Gear with a stat the scales can weigh; lines (tooltip data) add the stats a random suffix gives.
function P.Valued(link, data)
    local G = NS.GearValue
    if not G or P.Secret(link) or type(link) ~= "string" then return false end
    local lines = (type(data) == "table" and not P.Secret(data)) and data.lines or nil
    local stats = G.ItemStats(link, lines)
    -- an item with no stats counts once a scale lists it (a trinket that only has a Use)
    return next(stats) ~= nil or G.Listed(link, G.Scales())
end

function P.IsGear(link)
    local G = NS.GearValue
    if not G or P.Secret(link) or type(link) ~= "string" then return false end
    local loc = G.EquipLoc(link)
    return loc ~= nil and G.SLOTS[loc] ~= nil
end

function P.ItemName(link)
    return link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]") or "?"
end

function P.ScanItems()
    local out = {}
    P.items, P.scanDirty = out, nil
    local C, TI = C_Container, C_TooltipInfo
    local last = (type(NUM_BAG_SLOTS) == "number") and NUM_BAG_SLOTS or 4
    if C and C.GetContainerNumSlots and C.GetContainerItemLink then
        for bag = 0, last do
            local n = C.GetContainerNumSlots(bag)
            for slot = 1, (type(n) == "number" and n or 0) do
                local link = C.GetContainerItemLink(bag, slot)
                if P.IsGear(link) and P.Valued(link, TI and TI.GetBagItem and TI.GetBagItem(bag, slot)) then
                    out[#out + 1] = { value = "b:" .. bag .. ":" .. slot, kind = "bag", bag = bag, slot = slot,
                        text = P.ItemName(link), raw = true }
                end
            end
        end
    end
    for slot = 1, 19 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if P.IsGear(link) and P.Valued(link, TI and TI.GetInventoryItem and TI.GetInventoryItem("player", slot)) then
            out[#out + 1] = { value = "w:" .. slot, kind = "worn", slot = slot,
                text = Tr("%s (worn)"):format(P.ItemName(link)), raw = true }
        end
    end
    if not P.Picked() then P.item = out[1] and out[1].value or nil end
    return out
end

function P.Picked()
    for _, it in ipairs(P.items) do
        if it.value == P.item then return it end
    end
    return nil
end

-- Rows

-- A dim line whose words follow the page; it shows while vis() says so.
function P.Line(sp, textFn, vis)
    local row = AT.AddRow(sp, 20, vis)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -2)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.fs = fs
    row._sync = function()
        fs:SetText(textFn() or "")
        fs:SetWidth(math.max(40, (sp:GetWidth() or 0) - 36))
        local want = math.max(20, math.floor((fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- Buttons from the left, wrapping to a new line when the next one would run past the edge.
function P.Buttons(sp, specs, vis)
    local row = AT.AddRow(sp, LAY.rowH + 4, vis)
    row.btns = {}
    for i, s in ipairs(specs) do
        local b = (s.danger and AT.MakeDangerButton or AT.MakeSmallButton)(row, s.label, s.w or 80)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            s.onClick(b)
        end)
        b._gvVis = s.vis
        if s.tip then AT.Tooltip(b, s.label, s.tip) end
        row.btns[i] = b
    end
    row._sync = function()
        local edge = (sp:GetWidth() or 0) - 24 - 10
        local x, line = 10, 0
        for _, b in ipairs(row.btns) do
            if (not b._gvVis) or b._gvVis() then
                local bw = b:GetWidth() or 0
                if x > 10 and x + bw > edge then x, line = 10, line + 1 end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3 - line * (LAY.rowH + 4))
                b:Show()
                x = x + bw + 8
            else
                b:Hide()
            end
        end
        local want = (line + 1) * (LAY.rowH + 4)
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- A multi-line box in a well; readOnly keeps its text, selected for copying.
function P.TextRow(sp, h, readOnly)
    local row = AT.AddRow(sp, h)
    local well = CreateFrame("Frame", nil, row, "BackdropTemplate")
    well:SetPoint("TOPLEFT", 10, -4)
    well:SetPoint("BOTTOMRIGHT", -10, 4)
    AT.Skin(well, COL.well, COL.line2)
    local eb = CreateFrame("EditBox", nil, well)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(AT.FONT, 11, "")
    eb:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    local sc = AT.MakeScroll(well, eb)
    sc:SetPoint("TOPLEFT", 6, -6)
    sc:SetPoint("BOTTOMRIGHT", -10, 6)
    sc:HookScript("OnSizeChanged", function(s, w)
        eb:SetWidth(math.max(60, (w or s:GetWidth() or 200) - 6))
        s:UpdateScroll()
    end)
    eb:SetScript("OnTextChanged", function(s, user)
        if readOnly and user then
            s:SetText(P.expText or "")
            s:HighlightText()
        end
        sc:UpdateScroll()
    end)
    if readOnly then eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end) end
    -- the box spans only its text: a click anywhere in the well types into it
    well:EnableMouse(true)
    well:SetScript("OnMouseUp", function() eb:SetFocus() end)
    row._sync = function() eb:SetWidth(math.max(60, (sp:GetWidth() or 0) - 24 - 20 - 16 - 6)) end
    row.box = eb
    return row
end

-- What item tooltips show: a check per scale for the group picked in Show for, laid left to right and wrapping.
function P.ShowItem(row)
    local it = CreateFrame("Button", nil, row)
    it:SetHeight(LAY.rowH)
    it.check = AT.MakeCheckbox(it)
    it.check:SetPoint("LEFT", 0, 0)
    it.name = it:CreateFontString(nil, "OVERLAY")
    it.name:SetFont(AT.FONT, 12, "")
    it.name:SetPoint("LEFT", it.check, "RIGHT", 6, 0)
    it.name:SetJustifyH("LEFT")
    it.name:SetWordWrap(false)
    it.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local function toggle()
        AT.CloseDropdown()
        local G = NS.GearValue
        if not G then return end
        local g = P.Group()
        local on = not G.Shown(g, it._id)
        G.SetShown(g, it._id, on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        P.Changed()
    end
    it:SetScript("OnClick", toggle)
    it.check:SetScript("OnClick", toggle)
    it:SetScript("OnEnter", function() it.check:SetHover(true) end)
    it:SetScript("OnLeave", function() it.check:SetHover(false) end)
    AT.Tooltip(it, "Show", "Adds this scale's line to gear tooltips for the talent group picked above.")
    return it
end

function P.LayShow(sp, row)
    local G = NS.GearValue
    local list = G and G.Scales() or {}
    local g = P.Group()
    local edge = math.floor((sp:GetWidth() or 0) - 24 - 10)
    local x, line = 10, 0
    for i, s in ipairs(list) do
        local it = row._items[i]
        if not it then
            it = P.ShowItem(row)
            row._items[i] = it
        end
        it._id = s.id
        it.check:SetOn(G.Shown(g, s.id))
        it.name:SetText(s.name or "?")
        local w = 18 + 6 + math.ceil(P.TextW(it.name)) + 4
        if x > 10 and x + w > edge then x, line = 10, line + 1 end
        it:SetWidth(w)
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", row, "TOPLEFT", x, -line * LAY.rowH)
        it:Show()
        x = x + w + P.SHOW_GAP
    end
    for i = #list + 1, #row._items do row._items[i]:Hide() end
    local want = (#list > 0) and (line + 1) * LAY.rowH or 1
    if row._h ~= want then row._h = want row:SetHeight(want) end
end

function P.ShowRow(sp, vis)
    local row = AT.AddRow(sp, LAY.rowH, vis)
    row._items = {}
    row._sync = function() P.LayShow(sp, row) end
    P.showRow = row
    return row
end

-- Which goals get a line under item tooltips: a field that opens a tick per goal; Off until one is ticked.
function P.GoalLinesText()
    local G = NS.GearValue
    local on = {}
    for _, k in ipairs(G and G.GoalKinds() or {}) do
        if G.GoalLineOn(k.key) then on[#on + 1] = G.GoalName(k.key) end
    end
    if #on == 0 then return Tr("Off") end
    if #on == 1 then return on[1] end
    return on[1] .. " +" .. (#on - 1)
end

function P.OpenGoalLines(field)
    local G = NS.GearValue
    if AT.openDropdown and AT.openDropdown._owner == field then
        AT.CloseDropdown()
        return
    end
    AT.CloseDropdown()
    if not G then return end
    local kinds = G.GoalKinds()
    local list = CreateFrame("Frame", nil, MOD.win or field, "BackdropTemplate")
    list:SetFrameLevel(field:GetFrameLevel() + 30)
    list:SetWidth(field:GetWidth() or LAY.fieldW)
    list:SetHeight(math.max(1, #kinds) * 22 + 2)
    AT.Skin(list, COL.panel, COL.focus)
    list:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -1)
    list._owner = field
    list:EnableMouse(true)
    list.rows = {}
    for i, k in ipairs(kinds) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
        row:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
        row:SetHighlightTexture(AT.WHITE)
        row:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.5)
        local cb = AT.MakeCheckbox(row)
        cb:SetPoint("LEFT", 8, 0)
        cb:EnableMouse(false)
        local t = row:CreateFontString(nil, "OVERLAY")
        t:SetFont(AT.FONT, 11, "")
        t:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        t:SetPoint("RIGHT", -6, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        t:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        t:SetText(G.GoalName(k.key))
        cb:SetOn(G.GoalLineOn(k.key))
        -- the list stays open while ticking
        row:SetScript("OnClick", function()
            G.SetGoalLine(k.key, not G.GoalLineOn(k.key))
            cb:SetOn(G.GoalLineOn(k.key))
            P.Changed()
        end)
        row.cb, row.t, row.key = cb, t, k.key
        list.rows[i] = row
    end
    AT.openDropdown = list
end

function P.GoalLinesRow(sp, vis)
    local row = AT.AddRow(sp, LAY.rowH, vis)
    local lbl = AT.RowLabel(row, "Goal lines")
    local field = CreateFrame("Button", nil, row, "BackdropTemplate")
    field:SetSize(LAY.fieldW, 20)
    field:SetPoint("LEFT", row._ctrlX, 0)
    AT.Skin(field, COL.well)
    field.fs = field:CreateFontString(nil, "OVERLAY")
    field.fs:SetFont(AT.FONT, 11, "")
    field.fs:SetPoint("LEFT", 8, 0)
    field.fs:SetPoint("RIGHT", -18, 0)
    field.fs:SetJustifyH("LEFT")
    field.fs:SetWordWrap(false)
    field.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    AT.MakeChevron(field):SetPoint("RIGHT", -5, 0)
    field:SetScript("OnEnter", function() field:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
    field:SetScript("OnLeave", function() field:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    field:SetScript("OnClick", function() P.OpenGoalLines(field) end)
    AT.Tooltip(field, "Goal lines", "A line under item tooltips for each goal you tick: how far your gear is from it. The goals count either way.")
    row._colLabel, row._colCtrl = lbl, field
    row._sync = function() field.fs:SetText(P.GoalLinesText()) end
    P.goalLinesField = field
    return row
end

-- The scale the editor works on, picked from every scale of this class.
function P.ScaleItems()
    local G = NS.GearValue
    local out = {}
    for _, s in ipairs(G and G.Scales() or {}) do out[#out + 1] = { value = s.id, text = s.name or "?", raw = true } end
    return out
end

function P.ScaleRow(sp, vis)
    -- a one-word label: through Tr here so the key list reads it
    local row = AT.RowDropdown(sp, MOD.win, Tr("Scale"), function()
        local c = P.Cur()
        return c and c.id
    end, function(v) P.Select(v) end, P.ScaleItems, vis)
    local dd = row._colCtrl
    dd:SetWidth(P.SCALE_DD_W)
    AT.Tooltip(dd, "Scale", "The scale to look at and change. What tooltips show is ticked above.")
    local new = AT.MakeSmallButton(row, "New scale", 80)
    new:SetPoint("LEFT", dd, "RIGHT", 8, 0)
    new:SetScript("OnClick", function()
        AT.CloseDropdown()
        P.NewScale()
    end)
    local imp = AT.MakeSmallButton(row, "Import", 64)
    imp:SetPoint("LEFT", new, "RIGHT", 8, 0)
    imp:SetScript("OnClick", function()
        AT.CloseDropdown()
        P.OpenImport()
    end)
    local sync = row._sync
    row._sync = function()
        sync()
        -- the box shows no scale while there is none to pick
        local has = P.Cur() ~= nil
        dd:SetShown(has)
        row._colLabel:SetShown(has)
        new:ClearAllPoints()
        if has then new:SetPoint("LEFT", dd, "RIGHT", 8, 0) else new:SetPoint("LEFT", row, "LEFT", 10, 0) end
    end
    P.scaleDD, P.newBtn, P.impBtn = dd, new, imp
    return row
end

-- The weights, two to a row where the column is wide enough, else one under the other: a head, then a cell per
-- stat with - / value / + on scales of your own.
function P.Pairs(sp)
    local w = math.floor((sp:GetWidth() or 0) - 24)
    local two = w >= P.TWO_UP_W
    local cw = two and math.floor((w - 20 - P.CELL_GAP) / 2) or (w - 20)
    return two, cw, w
end

function P.HeadRow(sp)
    local row = AT.AddRow(sp, 22)
    row._heads = {}
    for i = 1, 2 do
        local h = {}
        for j, word in ipairs({ Tr("Stat"), Tr("A point") }) do
            local fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 10, "")
            fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
            fs:SetText(P.Upper(word))
            h[j] = fs
        end
        row._heads[i] = h
    end
    row._sync = function()
        local two, cw = P.Pairs(sp)
        local own = P.Own(P.Cur())
        for i, h in ipairs(row._heads) do
            local x = 10 + (i - 1) * (cw + P.CELL_GAP)
            local shown = i == 1 or two
            h[1]:ClearAllPoints()
            h[1]:SetPoint("LEFT", row, "LEFT", x, 0)
            -- over the box: centred on the cluster when it has - / +, else on the box alone
            local cl = x + cw - P.CLUSTER_W
            h[2]:ClearAllPoints()
            if own then h[2]:SetPoint("CENTER", row, "LEFT", cl + P.CLUSTER_W / 2, 0)
            else h[2]:SetPoint("RIGHT", row, "LEFT", cl + P.BOX_W, 0) end
            h[1]:SetShown(shown)
            h[2]:SetShown(shown)
        end
    end
    P.headRow = row
    return row
end

-- A cell's number on a scale and its writer: a weight, or what spec (get, put, step, label) says.
function P.CellGet(cell, s)
    if cell._spec then return cell._spec.get(s) or 0 end
    return (s and s.w and s.w[cell._key]) or 0
end

function P.CellPut(cell, id, v)
    local G = NS.GearValue
    if not G then return false end
    if cell._spec then return cell._spec.put(id, v) end
    return G.SetWeight(id, cell._key, v)
end

function P.Nudge(row, dir)
    AT.CloseDropdown()
    local cur = P.Cur()
    if not P.Own(cur) then return end
    local now = P.CellGet(row, cur)
    local step
    if row._spec then step = row._spec.step else step = (math.abs(now) >= P.BIG_FROM) and P.STEP_BIG or P.STEP_SMALL end
    local nv = math.floor((now + dir * step) * 100 + 0.5) / 100
    if nv < 0 then nv = 0 end
    if P.CellPut(row, cur.id, nv) then P.Changed() end
end

function P.CommitWeight(row)
    local id = row._editId
    row._editId = nil
    local G = NS.GearValue
    local s = id and G and G.Get(id)
    if not P.Own(s) then return end
    local now = P.CellGet(row, s)
    local n = tonumber(((row.val:GetText() or ""):gsub(",", ".")))
    if n == nil or n < 0 or n == now then
        AT.BoxText(row.val, P.Num(now))
        return
    end
    if P.CellPut(row, id, n) then P.Changed() end
end

-- One stat's cell: its name, then - / box / + at the cell's right edge. spec: a number that is not a weight.
function P.WeightCell(row, stat, spec)
    local cell = CreateFrame("Frame", nil, row)
    cell._key, cell._spec = stat[1], spec
    local lbl = cell:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(AT.FONT, 12, "")
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    lbl:SetText(Tr(stat[2]))
    local cl = CreateFrame("Frame", nil, cell)
    cl:SetSize(P.CLUSTER_W, 22)
    local minus = AT.MakeSmallButton(cl, "-", 22)
    minus:SetPoint("LEFT", 0, 0)
    minus:SetScript("OnClick", function() P.Nudge(cell, -1) end)
    local val = CreateFrame("EditBox", nil, cl, "BackdropTemplate")
    val:SetSize(P.BOX_W, 20)
    AT.Skin(val, COL.well)
    val:SetFont(AT.FONT, 11, "")
    val:SetJustifyH("RIGHT")
    val:SetTextInsets(6, 6, 0, 0)
    val:SetAutoFocus(false)
    val:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    val:SetScript("OnEscapePressed", function(s)
        AT.BoxText(s, P.Num(P.CellGet(cell, P.Cur())))
        s:ClearFocus()
    end)
    val:SetScript("OnEditFocusGained", function(s)
        local cur = P.Cur()
        cell._editId = P.Own(cur) and cur.id or nil
        P.focusBox = s
        s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    val:SetScript("OnEditFocusLost", function(s)
        if P.focusBox == s then P.focusBox = nil end
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        P.CommitWeight(cell)
    end)
    local plus = AT.MakeSmallButton(cl, "+", 22)
    plus:SetPoint("LEFT", P.BOX_W + 30, 0)
    plus:SetScript("OnClick", function() P.Nudge(cell, 1) end)
    cell.minus, cell.val, cell.plus, cell.label, cell.cluster = minus, val, plus, lbl, cl
    return cell
end

-- Fills a cell from the picked scale and lays it at x, cw wide; returns the height its name needs.
function P.SyncCell(cell, x, y, cw)
    local cur = P.Cur()
    local own = P.Own(cur)
    local v = P.CellGet(cell, cur)
    -- a stat the scale leaves out reads dim
    local ink = (v == 0) and COL.faint or COL.ink
    local lbl, val = cell.label, cell.val
    if cell._spec and cell._spec.label then lbl:SetText(cell._spec.label()) end
    lbl:SetTextColor(ink[1], ink[2], ink[3])
    val:SetTextColor(ink[1], ink[2], ink[3])
    if not own and val:HasFocus() then val:ClearFocus() end
    if not val:HasFocus() then AT.BoxText(val, P.Num(v)) end
    val:EnableMouse(own)
    val:ClearAllPoints()
    val:SetPoint("LEFT", cell.cluster, "LEFT", own and 26 or 0, 0)
    cell.minus:SetShown(own)
    cell.plus:SetShown(own)
    local room = math.max(40, cw - P.CLUSTER_W - 8)
    lbl:SetWidth(room)
    local h = math.max(LAY.rowH, math.ceil(P.TextW(lbl) / room) * 14 + 10)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", cell:GetParent(), "TOPLEFT", x, -y)
    cell:SetSize(cw, h)
    lbl:ClearAllPoints()
    lbl:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cell.cluster:ClearAllPoints()
    cell.cluster:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    cell:Show()
    return h
end

-- A row of two stats; one under the other on a narrow column. specs: numbers that are not weights.
function P.WeightRow(sp, a, b, specA, specB)
    local row = AT.AddRow(sp, LAY.rowH)
    row.cells = { P.WeightCell(row, a, specA) }
    if b then row.cells[2] = P.WeightCell(row, b, specB) end
    row._sync = function()
        local two, cw = P.Pairs(sp)
        local h
        if two then
            h = P.SyncCell(row.cells[1], 10, 0, cw)
            if row.cells[2] then h = math.max(h, P.SyncCell(row.cells[2], 10 + cw + P.CELL_GAP, 0, cw)) end
            -- both cells as tall as the taller name
            for _, c in ipairs(row.cells) do c:SetHeight(h) end
        else
            h = P.SyncCell(row.cells[1], 10, 0, cw)
            if row.cells[2] then h = h + P.SyncCell(row.cells[2], 10, h, cw) end
        end
        if row._h ~= h then row._h = h row:SetHeight(h) end
    end
    for _, c in ipairs(row.cells) do
        if not c._spec then P.weights[#P.weights + 1] = c end
    end
    return row
end

-- What the scale's points are worth in DPS, for the auction house's DPS gains: a row of the weights' grid.
P.DPS_STEP, P.BASE_STEP = 0.01, 5
function P.DpsRow(sp)
    local function get(field)
        return function(s)
            local G = NS.GearValue
            if not G then return nil end
            -- both values: `G and G.Dps(s)` would keep only the first
            local per, base = G.Dps(s)
            if field == "per" then return per end
            return base
        end
    end
    local function put(field)
        return function(id, v) return NS.GearValue.SetDps(id, field, v) end
    end
    local per = { get = get("per"), put = put("per"), step = P.DPS_STEP, label = function()
        local G, c = NS.GearValue, P.Cur()
        local unit = G and c and G.Unit(c)
        return unit and Tr("DPS per %s"):format(Tr(unit)) or Tr("DPS per point")
    end }
    local base = { get = get("base"), put = put("base"), step = P.BASE_STEP }
    -- a one-word label: through Tr here so the key list reads it
    local row = P.WeightRow(sp, { "dpsper", "DPS per point" }, { "dpsbase", Tr("Your DPS") }, per, base)
    AT.Tooltip(row.cells[1].val, "DPS per point", "What one point of this scale adds to your DPS, from a simulator. The auction house can show gains in DPS with it.")
    AT.Tooltip(row.cells[2].val, "Your DPS", "Your DPS in a simulator. The auction house's percent gain is a share of it.")
    P.dpsCells = row.cells
    return row
end

-- Goals: part of the picked scale. A stat picked in the dropdown, its goal (and for regen what Spirit and
-- Intellect count toward it), each a - / box / + like a weight; a bar of what the worn gear gives.
P.GOAL_STEPS = { spi = 0.05, int = 0.025 }
P.goalRows = {}

-- The stat the Goals section shows: the one picked, else the first with a goal, else the first.
function P.GoalKind()
    local G = NS.GearValue
    if not G then return nil end
    if P.goalKind and G.GoalKind(P.goalKind) then return P.goalKind end
    local kinds = G.GoalKinds()
    for _, k in ipairs(kinds) do
        if G.Goal(P.Cur(), k.key) then return k.key end
    end
    return kinds[1] and kinds[1].key
end

function P.GoalKindItems()
    local G = NS.GearValue
    local out = {}
    for _, k in ipairs(G and G.GoalKinds() or {}) do
        out[#out + 1] = { value = k.key, text = G.GoalName(k.key), raw = true }
    end
    return out
end

function P.Rate(v)
    v = tonumber(v) or 0
    if v == 0 then return "0" end
    local s = string.format("%.3f", v):gsub("%.?0+$", "")
    return s
end

function P.GoalText(field, v)
    if field ~= "goal" then return P.Rate(v) end
    if v <= 0 then return Tr("Off") end
    local G, key = NS.GearValue, P.GoalKind()
    return G.GoalNum(v, key) .. G.GoalUnit(key)
end

function P.GoalNow(field)
    local G = NS.GearValue
    return G and G.GoalSettings(P.Cur(), P.GoalKind())[field] or 0
end

function P.SetGoal(field, v)
    local G, c = NS.GearValue, P.Cur()
    if G and P.Own(c) and G.SetGoal(c.id, P.GoalKind(), field, v) then P.Changed() end
end

function P.GoalStep(field)
    if field ~= "goal" then return P.GOAL_STEPS[field] end
    local G = NS.GearValue
    local k = G and G.GoalKind(P.GoalKind())
    return k and k.step or 1
end

function P.GoalRow(sp, label, field, tip, vis)
    local row = AT.AddRow(sp, LAY.rowH, vis)
    local lbl = AT.RowLabel(row, label)
    local cl = CreateFrame("Frame", nil, row)
    cl:SetSize(P.CLUSTER_W, 22)
    local minus = AT.MakeSmallButton(cl, "-", 22)
    minus:SetPoint("LEFT", 0, 0)
    local val = CreateFrame("EditBox", nil, cl, "BackdropTemplate")
    val:SetSize(P.BOX_W, 20)
    val:SetPoint("LEFT", cl, "LEFT", 26, 0)
    AT.Skin(val, COL.well)
    val:SetFont(AT.FONT, 11, "")
    val:SetJustifyH("RIGHT")
    val:SetTextInsets(6, 6, 0, 0)
    val:SetAutoFocus(false)
    local plus = AT.MakeSmallButton(cl, "+", 22)
    plus:SetPoint("LEFT", P.BOX_W + 30, 0)
    local function nudge(dir)
        AT.CloseDropdown()
        local v = math.floor((P.GoalNow(field) + dir * P.GoalStep(field)) * 1000 + 0.5) / 1000
        P.SetGoal(field, math.max(0, v))
    end
    minus:SetScript("OnClick", function() nudge(-1) end)
    plus:SetScript("OnClick", function() nudge(1) end)
    val:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    val:SetScript("OnEscapePressed", function(s)
        s._skip = true
        s:ClearFocus()
    end)
    -- typing shows the bare number; the box reads "64 MP5" / "Off" again once it lets go
    val:SetScript("OnEditFocusGained", function(s)
        s._skip = nil
        P.focusBox = s
        AT.BoxText(s, P.Rate(P.GoalNow(field)))
        s:HighlightText()
        s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    val:SetScript("OnEditFocusLost", function(s)
        if P.focusBox == s then P.focusBox = nil end
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        local n = tonumber((((s:GetText() or ""):gsub(",", ".")):match("%d+%.?%d*") or ""))
        local now = P.GoalNow(field)
        if not s._skip and n and n ~= now then
            P.SetGoal(field, n)
            return
        end
        AT.BoxText(s, P.GoalText(field, now))
    end)
    if tip then AT.Tooltip(row, label, tip) end
    row.minus, row.val, row.plus = minus, val, plus
    row._colLabel, row._colCtrl = lbl, cl
    row._sync = function()
        if not val:HasFocus() then AT.BoxText(val, P.GoalText(field, P.GoalNow(field))) end
    end
    P.goalRows[field] = row
    return row
end

-- What the worn gear gives against the goal: label, a bar in whole pixels (corner-anchored fill, its width
-- from the row's known width, never read back), the numbers. Green from the goal up.
P.BAR_H, P.BAR_GAP = 12, 8
function P.WornRow(sp)
    local row = AT.AddRow(sp, LAY.rowH, function() return P.GoalNow("goal") > 0 end)
    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(AT.FONT, 12, "")
    lbl:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    lbl:SetPoint("LEFT", 10, 0)
    lbl:SetText(Tr("Worn"))
    local bar = CreateFrame("Frame", nil, row, "BackdropTemplate")
    AT.Skin(bar, COL.well, COL.line2)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(AT.WHITE)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.bar, row.fill, row.text, row.label = bar, fill, fs, lbl
    P.wornRow = row
    row._sync = function()
        local G = NS.GearValue
        local key = P.GoalKind()
        local s = G and key and G.GoalSettings(P.Cur(), key)
        if not (s and s.goal > 0) then return end
        -- hit counts talents and auras too: not only what is worn
        local k = G.GoalKind(key)
        lbl:SetText((k and k.total) and Tr("Total") or Tr("Worn"))
        local worn = G.WornAmount(s)
        local done = worn ~= nil and worn >= s.goal
        local ink = done and MOD.ON or COL.ink
        fs:SetText((worn and G.GoalNum(worn, key) or "?") .. " / " .. G.GoalNum(s.goal, key) .. G.GoalUnit(key))
        fs:SetTextColor(ink[1], ink[2], ink[3])
        local px = AT.Px(row)
        local function snap(v) return math.floor(v / px + 0.5) * px end
        local left = snap(10 + P.TextW(lbl) + P.BAR_GAP)
        local w = snap(math.max(20, (sp:GetWidth() or 0) - 24 - left - P.TextW(fs) - P.BAR_GAP - 10))
        local h = snap(P.BAR_H)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", left, -snap((LAY.rowH - P.BAR_H) / 2))
        bar:SetSize(w, h)
        local inner = w - 2 * px
        local fw = snap(inner * math.max(0, math.min(1, (worn or 0) / s.goal)))
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", bar, "TOPLEFT", px, -px)
        fill:SetSize(math.max(px, fw), h - 2 * px)
        local c = done and MOD.ON or COL.arc
        fill:SetVertexColor(c[1], c[2], c[3], 1)
        fill:SetShown(fw > 0)
    end
    return row
end

-- The preview: the picked item's own tooltip, drawn in the page with the lines of the group picked in Show for.
function P.ItemRow(sp)
    local row = AT.AddRow(sp, LAY.rowH, function() return #P.items > 0 end)
    local lbl = AT.RowLabel(row, "Item")
    local dd = AT.MakeDropdown(MOD.win, row, 160, function() return P.items end, function() return P.item end,
        function(v)
            P.item = v
            P.tipDirty = true
            P.Relayout()
        end)
    -- bags change while the page is open: read them again as the list opens
    local open = dd:GetScript("OnClick")
    dd:SetScript("OnClick", function(...)
        P.ScanItems()
        if open then open(...) end
    end)
    row._colLabel, row._colCtrl = lbl, dd
    row._sync = function()
        -- to the row's right edge less the tooltip's inset, so the box and the tooltip under it end together
        local w = math.floor((sp:GetWidth() or 0) - 24 - (10 + P.TextW(lbl) + 16) - P.TIP_INSET)
        dd:SetWidth(math.max(80, w))
        dd.Refresh()
    end
    P.itemDD = dd
    return row
end

function P.ShowTip(row, it, minW)
    local tip = P.tip
    tip:SetOwner(tip:GetParent(), "ANCHOR_NONE")
    -- as wide as the row less its insets, so its edges line up with the Item row's; set before the item lays it out
    if tip.SetMinimumWidth then tip:SetMinimumWidth(minW or 0) end
    tip._gvMinW = minW
    -- under the page's dropdown lists, which open over it
    tip:SetFrameStrata(row:GetFrameStrata())
    tip:SetFrameLevel(row:GetFrameLevel() + 2)
    -- the engine's post-call adds this group's lines; kept for the tooltip's own later refreshes
    tip._adGearGroup = P.Group()
    if it.kind == "bag" then
        tip:SetBagItem(it.bag, it.slot)
    else
        tip:SetInventoryItem("player", it.slot)
    end
    tip:Show()
    tip._gvItem = it.value
    P.tipDirty = nil
end

-- Sets the preview tooltip afresh a frame after the page is on screen and once more a beat later (item data that
-- was not loaded yet), whatever the tooltip says about being shown.
P.RESHOW_AGAIN = 0.25
function P.Reshow()
    -- the page and its row both come up on an open: one pass for both
    if P.reshowing then return end
    P.reshowing = true
    local function again(last)
        if last then P.reshowing = nil end
        if P.page and P.page:IsVisible() and P.tipRow and P.tipRow:IsVisible() and P.Picked() then
            P.tipDirty = true
            P.Relayout()
        end
    end
    C_Timer.After(0, function() again(false) end)
    C_Timer.After(P.RESHOW_AGAIN, function() again(true) end)
end

function P.TipRow(sp)
    local row = AT.AddRow(sp, 40, function() return #P.items > 0 end)
    -- the client's tooltip code finds a tooltip's lines by its name, and a section
    -- clips what it holds: a named tooltip on the window itself (it raises with
    -- the window and takes its scale), laid over the row and hidden with it
    P.tip = CreateFrame("GameTooltip", "ArcAurasGearValuePreview", MOD.win or UIParent, "GameTooltipTemplate")
    P.tip:Hide()
    P.tipRow = row
    row:HookScript("OnHide", function() P.tip:Hide() end)
    -- the first open lays the page out before the window is on screen, and a tooltip
    -- set then can report shown yet draw nothing: once the row is up, set it again
    row:HookScript("OnShow", function() P.Reshow() end)
    -- item data that arrives late refreshes the tooltip at a new size: the row follows it
    P.tip:HookScript("OnSizeChanged", function()
        if not P.laying and P.page and P.page:IsVisible() then P.Relayout() end
    end)
    row._sync = function()
        local tip = P.tip
        local it = P.Picked()
        if not it then
            tip:Hide()
            return
        end
        local avail = math.floor((sp:GetWidth() or 0) - 24 - 2 * P.TIP_INSET)
        if P.tipDirty or tip._gvItem ~= it.value or not tip:IsShown() or tip._gvMinW ~= avail then
            P.ShowTip(row, it, avail)
        end
        -- a tooltip wider than the column shrinks to fit rather than run under the edge
        local w, h = tip:GetWidth() or 0, tip:GetHeight() or 0
        local s = (w > avail and avail > 0) and (avail / w) or 1
        tip:SetScale(s)
        tip:ClearAllPoints()
        tip:SetPoint("TOPLEFT", row, "TOPLEFT", P.TIP_INSET / s, -4 / s)
        local want = math.max(40, math.ceil(h * s) + 8)
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- The picked scale on tabs: its weights, its goals, its extras, one at a time so the column never outgrows the window.
-- The tabs sit on the top edge of the box they open, the open one filled like the box so the two join; the box's own
-- title hides under them (the open tab names it).
P.TABS = { "Weights", "Goals", "Extras" }
-- the strip translates each name; a one-word name reaches the key list only through a Tr literal
Tr("Extras")
P.TAB_H = 24
P.tabHeads = {}
function P.Tab() return P.tab or "Weights" end

function P.PickTab(name)
    AT.CloseDropdown()
    P.Unfocus()
    P.tab = name
    P.Relayout()
end

-- A tab strip for the section just begun, shown while vis() says so.
function P.TabHead(sp, vis)
    local sec = sp._sections[#sp._sections]
    local strip = AT.TabRow(sec.band or sp)
    strip._openFill = COL.box
    -- the box's top edge is the strip's foot
    strip._line:SetAlpha(0)
    strip:Hide()
    P.tabHeads[#P.tabHeads + 1] = { sec = sec, strip = strip, vis = vis }
    return strip
end

-- Run after the columns are laid: each strip on its box's top edge, the open tab down over the box's edge by one
-- screen pixel so no line runs under it.
function P.SyncTabs()
    for _, h in ipairs(P.tabHeads) do
        local on = h.vis() == true
        local sec, strip = h.sec, h.strip
        if on then
            local hw = AT.Hairline(strip)
            strip:ClearAllPoints()
            strip:SetPoint("TOPLEFT", sec.box, "TOPLEFT", 0, P.TAB_H - hw)
            strip:SetPoint("TOPRIGHT", sec.box, "TOPRIGHT", 0, P.TAB_H - hw)
            strip:SetHeight(P.TAB_H)
            strip:SetFrameLevel(sec.box:GetFrameLevel() + 4)
            strip:Set(P.TABS, P.Tab(), P.PickTab, 11)
        end
        strip:SetShown(on)
        if sec.title then sec.title:SetAlpha(on and 0 or 1) end
        if sec.hr then sec.hr:SetAlpha(on and 0 or 1) end
        if sec.band then
            local f, e = COL.head, COL.line
            sec.band:SetBackdropColor(f[1], f[2], f[3], on and 0 or 1)
            sec.band:SetBackdropBorderColor(e[1], e[2], e[3], on and 0 or 1)
        end
    end
end

-- The strip shown now, if any.
function P.TabStrip()
    for _, h in ipairs(P.tabHeads) do
        if h.strip:IsShown() then return h.strip, h.sec end
    end
    return nil
end

-- Extras: what the player adds and puts a value on, per scale: an item's effect, a set's bonuses.

function P.ExtrasCount(kind)
    local G, c = NS.GearValue, P.Cur()
    if not (G and c) then return 0 end
    local n = 0
    for _ in pairs(G.Extras(c)[kind]) do n = n + 1 end
    return n
end

function P.SetName(sid)
    local get = C_Item and C_Item.GetItemSetInfo
    local name = get and get(sid)
    if type(name) == "string" and not P.Secret(name) and name ~= "" then return name end
    return Tr("Set %d"):format(sid)
end

-- An item known by ID: its name and its effect lines, asking the game for them when they are not loaded yet.
function P.ItemByID(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link = nil, nil
    if get then name, link = get(id) end
    if type(name) ~= "string" or P.Secret(name) then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        if not P.loadAgain then
            P.loadAgain = true
            C_Timer.After(0.5, function()
                P.loadAgain = nil
                if P.page and P.page:IsVisible() then P.Relayout() end
            end)
        end
        return nil
    end
    local TI = C_TooltipInfo
    local data = TI and TI.GetItemByID and TI.GetItemByID(id)
    local lines = (not P.Secret(data) and type(data) == "table") and data.lines or nil
    return name, link or ("item:" .. id), lines
end

-- What the Add dropdowns offer: the items in the bags and worn with an effect, or the sets they belong to, that the
-- scale does not list yet.
function P.AddChoices(kind)
    local G, c = NS.GearValue, P.Cur()
    local out, seen = {}, {}
    P.setPieces = {}
    if not (G and c) then return out end
    local x = G.Extras(c)
    local function consider(link, data)
        if type(link) ~= "string" or P.Secret(link) then return end
        local lines = (not P.Secret(data) and type(data) == "table") and data.lines or nil
        if kind == "items" then
            local id = G.ItemID(link)
            if id and not seen[id] and x.items[id] == nil and #G.EffectLines(lines) > 0 then
                seen[id] = true
                out[#out + 1] = { value = id, text = P.ItemName(link), raw = true }
            end
        else
            local sid = G.SetOf(link)
            if sid and not seen[sid] and x.sets[sid] == nil then
                seen[sid] = true
                P.setPieces[sid] = G.ItemID(link)
                out[#out + 1] = { value = sid, text = P.SetName(sid), raw = true }
            end
        end
    end
    local C, TI = C_Container, C_TooltipInfo
    local last = (type(NUM_BAG_SLOTS) == "number") and NUM_BAG_SLOTS or 4
    if C and C.GetContainerNumSlots and C.GetContainerItemLink then
        for bag = 0, last do
            local n = C.GetContainerNumSlots(bag)
            for slot = 1, (type(n) == "number" and n or 0) do
                consider(C.GetContainerItemLink(bag, slot), TI and TI.GetBagItem and TI.GetBagItem(bag, slot))
            end
        end
    end
    for slot = 1, 19 do
        consider(GetInventoryItemLink and GetInventoryItemLink("player", slot),
            TI and TI.GetInventoryItem and TI.GetInventoryItem("player", slot))
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    -- an empty list would open as nothing at all: say why instead (picking it does nothing)
    if #out == 0 then
        out[1] = { value = 0, raw = true, text = (kind == "items") and Tr("No items with an effect in your bags or worn gear.")
            or Tr("No set pieces in your bags or worn gear.") }
    end
    return out
end

function P.AddExtra(kind, v)
    local G, c = NS.GearValue, P.Cur()
    if not (G and P.Own(c)) or v == 0 then return end
    local done
    if kind == "items" then
        done = G.SetItemExtra(c.id, v, true)
    else
        done = G.SetSetExtra(c.id, v, P.setPieces and P.setPieces[v])
    end
    if done then P.Changed() end
end

function P.AddRow(sp, kind, vis)
    local row = AT.AddRow(sp, LAY.rowH, vis)
    local word = (kind == "items") and Tr("Add item") or Tr("Add set")
    local dd = AT.MakeDropdown(MOD.win, row, 200, function() return P.AddChoices(kind) end, function() return word end,
        function(v) P.AddExtra(kind, v) end)
    dd:SetPoint("LEFT", row, "LEFT", 10, 0)
    if kind == "items" then
        AT.Tooltip(dd, "Add item", "An item of yours with an effect. Its value counts on this scale beside its stats.")
    else
        AT.Tooltip(dd, "Add set", "A set you have a piece of. Each bonus counts on this scale by the pieces you wear.")
    end
    row._sync = function() dd.Refresh() end
    P["add_" .. kind] = dd
    return row
end

-- One value line: a label, - / box / + in the scale's unit, where the value comes from, and an x for a list entry.
P.EX_STEP, P.EX_LINE = 0.5, 14
function P.ValueLine(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(LAY.rowH)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFont(AT.FONT, 12, "")
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(true)
    f.label:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    f.minus = AT.MakeSmallButton(f, "-", 22)
    f.val = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    f.val:SetSize(P.BOX_W, 20)
    AT.Skin(f.val, COL.well)
    f.val:SetFont(AT.FONT, 11, "")
    f.val:SetJustifyH("RIGHT")
    f.val:SetTextInsets(6, 6, 0, 0)
    f.val:SetAutoFocus(false)
    f.plus = AT.MakeSmallButton(f, "+", 22)
    f.tag = f:CreateFontString(nil, "OVERLAY")
    f.tag:SetFont(AT.FONT, 11, "")
    f.tag:SetJustifyH("LEFT")
    f.kill = AT.MakeSmallButton(f, "x", 22)
    f.val:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    f.val:SetScript("OnEscapePressed", function(s)
        s._skip = true
        s:ClearFocus()
    end)
    f.val:SetScript("OnEditFocusGained", function(s)
        s._skip = nil
        P.focusBox = s
        s:HighlightText()
        s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    f.val:SetScript("OnEditFocusLost", function(s)
        if P.focusBox == s then P.focusBox = nil end
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        local n = tonumber((((s:GetText() or ""):gsub(",", ".")):match("%d+%.?%d*") or ""))
        if not s._skip and n and f._set and n ~= f._now then
            f._set(n)
            return
        end
        AT.BoxText(s, P.Num(f._now or 0))
    end)
    f.minus:SetScript("OnClick", function()
        AT.CloseDropdown()
        if f._set then f._set(math.max(0, math.floor(((f._now or 0) - P.EX_STEP) * 10 + 0.5) / 10)) end
    end)
    f.plus:SetScript("OnClick", function()
        AT.CloseDropdown()
        if f._set then f._set(math.floor(((f._now or 0) + P.EX_STEP) * 10 + 0.5) / 10) end
    end)
    f.kill:SetScript("OnClick", function()
        AT.CloseDropdown()
        if f._kill then f._kill() end
    end)
    return f
end

-- Lays a value line at y on the list row's width; the label wraps to the room left. Returns its height.
-- The tag column fits the widest of its words in the client's language, so none is cut.
function P.TagW(fs)
    local w = 30
    for _, word in ipairs({ "None", "Typed", "Auto" }) do
        fs:SetText(Tr(word))
        w = math.max(w, math.ceil(P.TextW(fs)) + 2)
    end
    return w
end

function P.PlaceLine(row, f, y, w, label, now, from, set, kill)
    local px = AT.Px(row)
    local function snap(v) return math.floor(v / px + 0.5) * px end
    P.tagW = P.tagW or P.TagW(f.tag)
    local right = 10 + 22 + 4 + P.tagW + 4 + 22 + 4 + P.BOX_W + 4 + 22
    local labelW = math.max(40, w - 10 - right - 8)
    f.label:SetText(label)
    f.label:SetWidth(labelW)
    local lines = math.max(1, math.ceil(P.TextW(f.label) / labelW))
    local h = snap(math.max(LAY.rowH, lines * P.EX_LINE + 8))
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -y)
    f:SetSize(w, h)
    f.label:ClearAllPoints()
    f.label:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.kill:ClearAllPoints()
    f.kill:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.kill:SetShown(kill ~= nil)
    f.tag:ClearAllPoints()
    f.tag:SetPoint("RIGHT", f.kill, "LEFT", -4, 0)
    f.tag:SetWidth(P.tagW)
    f.plus:ClearAllPoints()
    f.plus:SetPoint("RIGHT", f.tag, "LEFT", -4, 0)
    f.val:ClearAllPoints()
    f.val:SetPoint("RIGHT", f.plus, "LEFT", -4, 0)
    f.minus:ClearAllPoints()
    f.minus:SetPoint("RIGHT", f.val, "LEFT", -4, 0)
    f._now, f._set, f._kill = now, set, kill
    if not f.val:HasFocus() then AT.BoxText(f.val, P.Num(now)) end
    local word, c = Tr("None"), COL.faint
    if from == "typed" then word, c = Tr("Typed"), COL.ink elseif from == "auto" then word, c = Tr("Auto"), MOD.ON end
    f.tag:SetText(word)
    f.tag:SetTextColor(c[1], c[2], c[3])
    f:Show()
    return h
end

-- A note above an entry: the item's name and its effect, or a set's name and pieces worn; wraps to the width.
function P.PlaceNote(row, fs, y, w, text, ink)
    fs:SetWidth(math.max(40, w - 20))
    fs:SetText(text)
    fs:SetTextColor(ink[1], ink[2], ink[3])
    local lines = math.max(1, math.ceil(P.TextW(fs) / math.max(40, w - 20)))
    local h = lines * P.EX_LINE + 6
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -(y + 4))
    fs:Show()
    return h
end

-- The bonus in the stat's own name when it is a stat ("(3) +18 Spell Power"), else its words.
function P.BonusLabel(b)
    local G = NS.GearValue
    local key, v = G.StatOfText(b.text)
    local info = key and G.StatInfo(key)
    if info and not info.pct then return ("(%d) +%s %s"):format(b.at, P.Num(v), Tr(info[2])) end
    return ("(%d) %s"):format(b.at, b.text)
end

function P.ExtrasRow(sp, kind, vis)
    local row = AT.AddRow(sp, 10, function() return vis() and P.ExtrasCount(kind) > 0 end)
    row._lines, row._notes = {}, {}
    row._sync = function() P.LayExtras(sp, row, kind) end
    P["extras_" .. kind] = row
    return row
end

function P.LayExtras(sp, row, kind)
    local G, c = NS.GearValue, P.Cur()
    if not (G and c) then return end
    local w = math.floor((sp:GetWidth() or 0) - 24)
    local nl, nn, y = 0, 0, 0
    local function Line()
        nl = nl + 1
        row._lines[nl] = row._lines[nl] or P.ValueLine(row)
        return row._lines[nl]
    end
    local function Note()
        nn = nn + 1
        if not row._notes[nn] then
            local fs = row:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 11, "")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            row._notes[nn] = fs
        end
        return row._notes[nn]
    end
    local x = G.Extras(c)
    local ids = {}
    for id in pairs(x[kind]) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if kind == "items" then
            local name, link, lines = P.ItemByID(id)
            local fx = lines and table.concat(G.EffectLines(lines), " ") or ""
            y = y + P.PlaceNote(row, Note(), y, w, (name or ("#" .. id)) .. ((fx ~= "") and (": " .. fx) or ""), COL.dim)
            local now, typed, read = G.ItemExtra(c, link or ("item:" .. id), lines)
            y = y + P.PlaceLine(row, Line(), y, w, Tr("Counts as"), now, typed and "typed" or (read and "auto" or "none"),
                function(v) if G.SetItemExtra(c.id, id, v) then P.Changed() end end,
                function() if G.SetItemExtra(c.id, id, nil) then P.Changed() end end)
        else
            local worn = G.WornSetCounts()[id] or 0
            local _, _, pieceLines = P.ItemByID(x.sets[id].item or 0)
            local size = G.SetSize(pieceLines)
            local count = size and Tr("%d / %d worn"):format(worn, size) or Tr("%d worn"):format(worn)
            y = y + P.PlaceNote(row, Note(), y, w, P.Upper(P.SetName(id) .. "  " .. count), COL.faint)
            local list = G.SetBonusList(c, id)
            if #list == 0 then
                -- the piece is not loaded yet (or never will be): the set can still come off
                y = y + P.PlaceLine(row, Line(), y, w, Tr("Bonuses not read yet"), 0, "none", nil,
                    function() if G.SetSetExtra(c.id, id, nil) then P.Changed() end end)
            end
            for i, b in ipairs(list) do
                -- the set's x sits on its first bonus
                y = y + P.PlaceLine(row, Line(), y, w, P.BonusLabel(b), b.value, b.typed and "typed" or (b.read and "auto" or "none"),
                    function(v) if G.SetBonusValue(c.id, id, b.at, v) then P.Changed() end end,
                    (i == 1) and function() if G.SetSetExtra(c.id, id, nil) then P.Changed() end end or nil)
            end
        end
        y = y + 4
    end
    for i = nl + 1, #row._lines do row._lines[i]:Hide() end
    for i = nn + 1, #row._notes do row._notes[i]:Hide() end
    local h = math.max(10, y)
    if row._h ~= h then
        row._h = h
        row:SetHeight(h)
    end
end

function P.BuildExtras(sp, vis)
    AT.Section(sp, Tr("Effects"), { visibleFn = vis })
    P.TabHead(sp, vis)
    P.ExtrasRow(sp, "items", vis)
    AT.RowDesc(sp, "None yet: add one of your items to put a value on its effect.", 20,
        function() return vis() and P.ExtrasCount("items") == 0 end)
    P.AddRow(sp, "items", vis)
    AT.Section(sp, Tr("Set bonuses"), { visibleFn = vis })
    P.ExtrasRow(sp, "sets", vis)
    AT.RowDesc(sp, "None yet: add a set you have a piece of.", 20, function() return vis() and P.ExtrasCount("sets") == 0 end)
    P.AddRow(sp, "sets", vis)
end

-- Building the columns. One-word titles go through Tr here so the key list reads them.

-- The picked scale's goals (one package with its weights).
function P.BuildGoals(sp, vis)
    AT.Section(sp, Tr("Goals"), { visibleFn = vis })
    P.TabHead(sp, vis)
    local row = AT.RowDropdown(sp, MOD.win, "Stat", P.GoalKind, function(v)
        P.goalKind = v
        P.Changed()
    end, P.GoalKindItems)
    AT.Tooltip(row._colCtrl, "Stat", "Pick a stat to set its goal. Each stat keeps its own.")
    P.goalDD = row._colCtrl
    local function regen() return P.GoalKind() == "regen" end
    -- a one-word label: through Tr here so the key list reads it
    P.GoalRow(sp, Tr("Goal"), "goal", "The amount to reach; hit counts your talents too. This scale counts the stat fully until then, nothing after.")
    P.GoalRow(sp, "Spirit counts as", "spi", "How much MP5 one Spirit is worth toward the goal.", regen)
    P.GoalRow(sp, "Intellect counts as", "int", "How much MP5 one Intellect is worth toward the goal.", regen)
    P.WornRow(sp)
end

function P.BuildScale(sp)
    local function edit() return P.panel == "edit" end
    local function own() return P.Own(P.Cur()) end
    local function default()
        local c = P.Cur()
        return c ~= nil and c.kind ~= "own"
    end
    -- the scale editor: which scale, its name and spec, what to do with it, then its tabs as the box's last row
    AT.Section(sp, Tr("Scales"), { visibleFn = edit })
    P.ScaleRow(sp)
    local row = AT.RowInput(sp, "Name",
        function()
            local c = P.Cur()
            return c and c.name or ""
        end,
        function(v)
            local G, c = NS.GearValue, P.Cur()
            if G and P.Own(c) and v ~= c.name and G.SetName(c.id, v) then P.Changed() end
        end, own)
    P.nameBox = row._colCtrl
    AT.RowDropdown(sp, MOD.win, "Spec",
        function()
            local c = P.Cur()
            return c and c.spec
        end,
        function(v)
            local G, c = NS.GearValue, P.Cur()
            if G and P.Own(c) and G.SetSpec(c.id, v) then P.Changed() end
        end, P.SpecItems, own)
    AT.RowDesc(sp, "Ships with Arc Auras. Copy it to change a weight.", 20, default)
    AT.RowDesc(sp, "No scale yet. Make one with New scale, or import one.", 20, function() return P.Cur() == nil end)
    local acts = P.Buttons(sp, {
        { label = "Copy as your own", onClick = P.CopyOwn, w = 92 },
        { label = "Export", onClick = P.OpenExport, w = 64 },
        { label = "Delete", onClick = P.DeleteClick, danger = true, vis = own, w = 64,
            tip = "Deletes this scale for every character. Press twice." },
    }, function() return P.Cur() ~= nil end)
    P.delBtn = acts.btns[3]

    -- an own scale on tabs; a default shows its weights alone, under their title
    local function tabsOn() return edit() and own() end
    local function onTab(t) return function() return tabsOn() and P.Tab() == t end end
    AT.Section(sp, Tr("Weights"), { visibleFn = function()
        return edit() and P.Cur() ~= nil and (not own() or P.Tab() == "Weights")
    end })
    P.TabHead(sp, onTab("Weights"))
    P.HeadRow(sp)
    local G = NS.GearValue
    local stats = G and G.Stats() or {}
    P.weights = {}
    for i = 1, #stats, 2 do P.WeightRow(sp, stats[i], stats[i + 1]) end
    P.DpsRow(sp)
    P.BuildGoals(sp, onTab("Goals"))
    P.BuildExtras(sp, onTab("Extras"))

    AT.Section(sp, "Import", { visibleFn = function() return P.panel == "import" end })
    AT.RowDesc(sp, "Paste weights strings. A scale with the same name is updated, its goals too.", 20)
    P.impBox = P.TextRow(sp, P.PASTE_H, false).box
    P.Line(sp, P.ImportWhyText, function() return P.importWhy ~= nil end)
    P.Buttons(sp, {
        { label = "Import", onClick = P.DoImport, w = 64 },
        { label = "Cancel", onClick = P.CloseSide, w = 64 },
    })

    AT.Section(sp, "Export", { visibleFn = function() return P.panel == "export" end })
    AT.RowDesc(sp, "Copy it into a simulator or share it.", 20)
    P.expBox = P.TextRow(sp, P.PASTE_H, true).box
    P.Buttons(sp, { { label = "Close", onClick = P.CloseSide, w = 64 } })
end

function P.BuildPreview(sp)
    AT.Section(sp, Tr("Preview"))
    P.ItemRow(sp)
    AT.RowDesc(sp, "No gear with stats in your bags or worn.", 20, function() return #P.items == 0 end)
    P.TipRow(sp)
end

-- Laying out the columns

-- Column widths for a span: the editor takes what the preview leaves, in proportion.
function P.Widths(span)
    if span < P.MIN_SPAN then return { span, span }, false end
    local c = P.COLS
    local inner = span - P.GAP
    local z = math.floor(inner * c[2] / (c[1] + c[2]))
    return { inner - z, z }, true
end

-- How far below its top a column's lowest shown box ends.
function P.Extent(sp)
    local ext = 0
    for _, sec in ipairs(sp._sections) do
        local box = sec.box
        if box:IsShown() then
            local _, _, _, _, y = box:GetPoint(1)
            local b = -(y or 0) + (box:GetHeight() or 0)
            if b > ext then ext = b end
        end
    end
    return ext
end

-- The host row holds the columns. Each column is a page of its own; its boxes line up with the page's
-- sections: a column page sits 6 left of and 6 above where its first box starts.
function P.LayHost()
    local pg, row = P.page, P.host
    local W = pg:GetWidth() or 0
    if W < 60 then
        pg._sizeUnresolved = true
        return
    end
    local extra = pg._scroll and AT.ScrollExtra() or 0
    local widths, wide = P.Widths(math.floor(W - 12 - extra))
    if P.scanDirty then P.ScanItems() end
    P.laying = true
    local x, y, h = 0, 0, 0
    for i, sp in ipairs(P.subs) do
        local w = widths[i]
        sp:ClearAllPoints()
        sp:SetWidth(w + 12)
        sp:SetPoint("TOPLEFT", row, "TOPLEFT", -12 + x, 6 - y)
        AT.LayoutPage(sp)
        if sp._sizeUnresolved then pg._sizeUnresolved = true end
        local ext = P.Extent(sp)
        sp:SetHeight(math.max(1, ext + 4))
        if wide then
            x = x + w + P.GAP
            if ext - 6 > h then h = ext - 6 end
        elseif ext > 0 then
            h = y + ext - 6
            y = y + ext - 4 + LAY.gap
        end
    end
    P.laying = nil
    P.SyncTabs()
    h = math.max(10, math.ceil(h))
    if row._h ~= h then row._h = h row:SetHeight(h) end
end

function P.Build(pg, m)
    P.page = pg
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Gear value in tooltips", m.isOn, m.setOn, nil,
        "Gear tooltips show each scale you pick: what the item is worth to its weights, and the change from what you wear.")
    MOD.Stamp(row, m, m.switch, "bool", nil, true)
    -- what item tooltips show: the talent group, then a check per scale
    row = AT.RowDropdown(pg, MOD.win, "Show for", P.Group, function(v)
        P.group = v
        P.Changed()
    end, P.GroupItems, m.isOn)
    AT.Tooltip(row._colCtrl, "Show for", "Each talent group shows its own scales. Pick the one to set here; the preview shows its lines.")
    P.showFor = row._colCtrl
    P.ShowRow(pg, m.isOn)
    P.GoalLinesRow(pg, m.isOn)
    AT.Section(pg, nil)
    local host = AT.AddRow(pg, 40, m.isOn)
    P.host = host
    for i = 1, #P.COLS do
        local sp = AT.NewPage(host)
        sp._bg:Hide()
        sp:Show()
        P.subs[i] = sp
    end
    P.BuildScale(P.subs[1])
    P.BuildPreview(P.subs[2])
    host._sync = function() P.LayHost() end
    -- opening the page shows the active group and reads the bags afresh
    pg:HookScript("OnShow", function()
        P.group, P.goalKind, P.scanDirty, P.tipDirty = nil, nil, true, true
        P.Reshow()
    end)
end

MOD.Register({
    key = "gearValue",
    switch = (NS.GearValue and NS.GearValue.SETTING) or "tooltipGearValue",
    name = "Gear Value",
    desc = "Item tooltips show what gear is worth to your own stat weights, against what you wear.",
    -- bars rising from a baseline
    glyph = {
        { 1, 18, 18, 1, "dim" }, { 3, 12, 3, 6 }, { 8, 8, 3, 10, "dim" }, { 13, 3, 3, 15, "arc" },
    },
    isOn = function()
        local G = NS.GearValue
        return G ~= nil and G.Enabled() == true
    end,
    setOn = function(v)
        local G = NS.GearValue
        NS.Store.SetSetting((G and G.SETTING) or "tooltipGearValue", v and true or nil)
        Options.RefreshAll()
    end,
    build = function(pg, m) P.Build(pg, m) end,
})
