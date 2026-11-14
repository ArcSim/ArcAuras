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

-- Three columns at the mockup's widths; a narrower page stacks them.
P.COLS, P.GAP, P.MIN_SPAN = { 268, 330, 272 }, 12, 760
P.CONFIRM_FOR = 4
P.STEP_SMALL, P.STEP_BIG, P.BIG_FROM = 0.05, 0.5, 5
P.BOX_W, P.CLUSTER_W = 62, 114
P.LINE_H, P.CAPTION_H, P.PASTE_H = 28, 22, 140
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
    P.sel = id
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
    local id, why = G.Import(box:GetText() or "")
    if not id then
        P.importWhy = why or "format"
        P.Relayout()
        return
    end
    -- the engine keeps where a scale came from only as this mark
    local data = G.Data()
    local s = data and data.gearScales[id]
    if s then s.imported = true end
    box:SetText("")
    box:ClearFocus()
    if G.Get(id) then
        G.SetShown(P.Group(), id, true)
        P.sel, P.panel, P.importWhy = id, "edit", nil
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
    return next(stats) ~= nil
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

-- The list: a caption per group of scales, a line per scale with its Show check, name and tag.
function P.ScaleLine(row)
    local ln = CreateFrame("Button", nil, row)
    ln.fill = ln:CreateTexture(nil, "BACKGROUND")
    ln.fill:SetTexture(AT.WHITE)
    ln.fill:SetAllPoints()
    ln.bar = ln:CreateTexture(nil, "ARTWORK")
    ln.bar:SetTexture(AT.WHITE)
    ln.bar:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    ln.bar:SetPoint("TOPLEFT", 0, 0)
    ln.bar:SetPoint("BOTTOMLEFT", 0, 0)
    ln.check = AT.MakeCheckbox(ln)
    ln.check:SetPoint("LEFT", 6, 0)
    ln.name = ln:CreateFontString(nil, "OVERLAY")
    ln.name:SetFont(AT.FONT, 12, "")
    ln.name:SetPoint("LEFT", ln.check, "RIGHT", 8, 0)
    ln.name:SetJustifyH("LEFT")
    ln.name:SetWordWrap(true)
    ln.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    ln.tag = CreateFrame("Frame", nil, ln, "BackdropTemplate")
    ln.tag:SetHeight(14)
    ln.tag:SetPoint("RIGHT", -6, 0)
    AT.Skin(ln.tag, { 0, 0, 0, 0 }, COL.line2)
    ln.tag.fs = ln.tag:CreateFontString(nil, "OVERLAY")
    ln.tag.fs:SetFont(AT.FONT, 10, "")
    ln.tag.fs:SetPoint("CENTER", 0, 0)
    ln.tag.fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    ln:SetScript("OnClick", function() P.Select(ln._id) end)
    ln:SetScript("OnEnter", function() ln._hot = true P.PaintLine(ln) end)
    ln:SetScript("OnLeave", function() ln._hot = nil P.PaintLine(ln) end)
    ln.check:SetScript("OnClick", function()
        AT.CloseDropdown()
        local G = NS.GearValue
        if not G then return end
        local g = P.Group()
        local on = not G.Shown(g, ln._id)
        G.SetShown(g, ln._id, on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        P.Changed()
    end)
    ln.check:HookScript("OnEnter", function() ln.check:SetHover(true) end)
    ln.check:HookScript("OnLeave", function() ln.check:SetHover(false) end)
    AT.Tooltip(ln.check, "Show", "Adds this scale's line to gear tooltips for the talent group picked above.")
    return ln
end

function P.PaintLine(ln)
    local sel = ln._id ~= nil and ln._id == P.sel
    local c, a = COL.sel, 0
    if sel then a = 1 elseif ln._hot then c, a = COL.btn, 1 end
    ln.fill:SetVertexColor(c[1], c[2], c[3], a)
    ln.bar:SetWidth(AT.Px(ln) * 2)
    ln.bar:SetShown(sel)
end

function P.Caption(row, i, text, y)
    local fs = row._caps[i]
    if not fs then
        fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 10, "")
        fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        row._caps[i] = fs
    end
    fs:SetText(P.Upper(text))
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 6, y - P.CAPTION_H + 4)
    fs:Show()
    return y - P.CAPTION_H
end

function P.TagOf(s)
    if s.kind == "default" then return Tr("Default") end
    if s.imported then return Tr("Imported") end
    return Tr("Yours")
end

function P.LayList(sp, row)
    local G = NS.GearValue
    local list = G and G.Scales() or {}
    local defs, own = {}, {}
    for _, s in ipairs(list) do
        if s.kind == "default" then defs[#defs + 1] = s else own[#own + 1] = s end
    end
    P.Cur()
    local g = P.Group()
    local w = math.floor((sp:GetWidth() or 0) - 24)
    local y, li = -2, 0
    for _, fs in ipairs(row._caps) do fs:Hide() end
    local function lay(s)
        li = li + 1
        local ln = row._lines[li]
        if not ln then
            ln = P.ScaleLine(row)
            row._lines[li] = ln
        end
        ln._id = s.id
        ln.check:SetOn(G.Shown(g, s.id))
        ln.tag.fs:SetText(P.TagOf(s))
        local tw = math.ceil(P.TextW(ln.tag.fs)) + 10
        ln.tag:SetWidth(tw)
        ln.name:SetText(s.name or "?")
        ln.name:SetWidth(math.max(20, w - (6 + 18 + 8) - (tw + 6 + 8)))
        local h = math.max(P.LINE_H, math.ceil(ln.name:GetStringHeight() or 12) + 12)
        ln:ClearAllPoints()
        ln:SetPoint("TOPLEFT", row, "TOPLEFT", 0, y)
        ln:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, y)
        ln:SetHeight(h)
        ln:Show()
        P.PaintLine(ln)
        y = y - h
    end
    -- a caption only over a group that has scales
    if #defs > 0 then
        y = P.Caption(row, 1, Tr("Defaults"), y)
        for _, s in ipairs(defs) do lay(s) end
    end
    if #own > 0 then
        y = P.Caption(row, 2, Tr("Yours"), y)
        for _, s in ipairs(own) do lay(s) end
    end
    for i = li + 1, #row._lines do row._lines[i]:Hide() end
    local want = math.max(6, math.ceil(-y + 4))
    if row._h ~= want then row._h = want row:SetHeight(want) end
end

function P.ListRow(sp)
    local row = AT.AddRow(sp, 40)
    row._lines, row._caps = {}, {}
    row._sync = function() P.LayList(sp, row) end
    P.list = row
    return row
end

-- The weights: a column head, then a row per stat with - / value / + on scales of your own.
function P.HeadRow(sp)
    local row = AT.AddRow(sp, 22)
    local lbl = AT.RowLabel(row, "Stat")
    lbl:SetFont(AT.FONT, 10, "")
    lbl:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    lbl:SetText(P.Upper(Tr("Stat")))
    local ctrl = CreateFrame("Frame", nil, row)
    ctrl:SetSize(P.CLUSTER_W, 16)
    local fs = ctrl:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 10, "")
    fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    fs:SetText(P.Upper(Tr("A point")))
    row._colLabel, row._colCtrl = lbl, ctrl
    row._sync = function()
        fs:ClearAllPoints()
        if P.Own(P.Cur()) then fs:SetPoint("CENTER", ctrl, "LEFT", P.CLUSTER_W / 2, 0)
        else fs:SetPoint("RIGHT", ctrl, "LEFT", P.BOX_W, 0) end
    end
    return row
end

function P.Nudge(row, dir)
    AT.CloseDropdown()
    local G = NS.GearValue
    local cur = P.Cur()
    if not (G and P.Own(cur)) then return end
    local now = (cur.w and cur.w[row._key]) or 0
    local step = (math.abs(now) >= P.BIG_FROM) and P.STEP_BIG or P.STEP_SMALL
    local nv = math.floor((now + dir * step) * 100 + 0.5) / 100
    if nv < 0 then nv = 0 end
    G.SetWeight(cur.id, row._key, nv)
    P.Changed()
end

function P.CommitWeight(row)
    local id = row._editId
    row._editId = nil
    local G = NS.GearValue
    local s = id and G and G.Get(id)
    if not P.Own(s) then return end
    local now = (s.w and s.w[row._key]) or 0
    local n = tonumber(((row.val:GetText() or ""):gsub(",", ".")))
    if n == nil or n < 0 or n == now then
        AT.BoxText(row.val, P.Num(now))
        return
    end
    G.SetWeight(id, row._key, n)
    P.Changed()
end

function P.WeightRow(sp, stat)
    local row = AT.AddRow(sp, LAY.rowH)
    row._key = stat[1]
    local lbl = AT.RowLabel(row, stat[2])
    local cl = CreateFrame("Frame", nil, row)
    cl:SetSize(P.CLUSTER_W, 22)
    local minus = AT.MakeSmallButton(cl, "-", 22)
    minus:SetPoint("LEFT", 0, 0)
    minus:SetScript("OnClick", function() P.Nudge(row, -1) end)
    local val = CreateFrame("EditBox", nil, cl, "BackdropTemplate")
    val:SetSize(P.BOX_W, 20)
    AT.Skin(val, COL.well)
    val:SetFont(AT.FONT, 11, "")
    val:SetJustifyH("RIGHT")
    val:SetTextInsets(6, 6, 0, 0)
    val:SetAutoFocus(false)
    val:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    val:SetScript("OnEscapePressed", function(s)
        local cur = P.Cur()
        AT.BoxText(s, P.Num(cur and cur.w and cur.w[row._key] or 0))
        s:ClearFocus()
    end)
    val:SetScript("OnEditFocusGained", function(s)
        local cur = P.Cur()
        row._editId = P.Own(cur) and cur.id or nil
        P.focusBox = s
        s:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    val:SetScript("OnEditFocusLost", function(s)
        if P.focusBox == s then P.focusBox = nil end
        s:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        P.CommitWeight(row)
    end)
    local plus = AT.MakeSmallButton(cl, "+", 22)
    plus:SetPoint("LEFT", P.BOX_W + 30, 0)
    plus:SetScript("OnClick", function() P.Nudge(row, 1) end)
    row.minus, row.val, row.plus = minus, val, plus
    row._colLabel, row._colCtrl = lbl, cl
    row._sync = function()
        local cur = P.Cur()
        local own = P.Own(cur)
        local v = (cur and cur.w and cur.w[row._key]) or 0
        -- a stat the scale leaves out reads dim
        local ink = (v == 0) and COL.faint or COL.ink
        lbl:SetTextColor(ink[1], ink[2], ink[3])
        val:SetTextColor(ink[1], ink[2], ink[3])
        if not own and val:HasFocus() then val:ClearFocus() end
        if not val:HasFocus() then AT.BoxText(val, P.Num(v)) end
        val:EnableMouse(own)
        val:ClearAllPoints()
        val:SetPoint("LEFT", cl, "LEFT", own and 26 or 0, 0)
        minus:SetShown(own)
        plus:SetShown(own)
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
        local w = math.floor((sp:GetWidth() or 0) - 24 - (10 + P.TextW(lbl) + 16) - 12)
        dd:SetWidth(math.max(80, math.min(240, w)))
        dd.Refresh()
    end
    P.itemDD = dd
    return row
end

function P.ShowTip(row, it)
    local tip = P.tip
    tip:SetOwner(row, "ANCHOR_NONE")
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

function P.TipRow(sp)
    local row = AT.AddRow(sp, 40, function() return #P.items > 0 end)
    P.tip = CreateFrame("GameTooltip", nil, row, "GameTooltipTemplate")
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
        if P.tipDirty or tip._gvItem ~= it.value or not tip:IsShown() then P.ShowTip(row, it) end
        -- a tooltip wider than the column shrinks to fit rather than run under the edge
        local avail = (sp:GetWidth() or 0) - 24 - 8
        local w, h = tip:GetWidth() or 0, tip:GetHeight() or 0
        local s = (w > avail and avail > 0) and (avail / w) or 1
        tip:SetScale(s)
        tip:ClearAllPoints()
        tip:SetPoint("TOPLEFT", row, "TOPLEFT", 4 / s, -4 / s)
        local want = math.max(40, math.ceil(h * s) + 8)
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- Building the columns

function P.BuildScales(sp)
    AT.Section(sp, "Scales")
    local row = AT.RowDropdown(sp, MOD.win, "Show for", P.Group, function(v)
        P.group = v
        P.Changed()
    end, P.GroupItems)
    AT.Tooltip(row._colCtrl, "Show for", "Each talent group shows its own scales. Pick the one to set here; the preview shows its lines.")
    P.ListRow(sp)
    P.Buttons(sp, {
        { label = "New scale", onClick = P.NewScale },
        { label = "Import", onClick = P.OpenImport },
    })
end

function P.BuildScale(sp)
    local function edit() return P.panel == "edit" end
    local function own() return P.Own(P.Cur()) end
    local function default()
        local c = P.Cur()
        return c ~= nil and c.kind ~= "own"
    end
    AT.Section(sp, "Scale", { visibleFn = edit })
    P.headSec = sp._sections[#sp._sections]
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

    AT.Section(sp, "Weights", { visibleFn = function() return edit() and P.Cur() ~= nil end })
    P.HeadRow(sp)
    local G = NS.GearValue
    P.weights = {}
    for _, st in ipairs(G and G.Stats() or {}) do P.weights[#P.weights + 1] = P.WeightRow(sp, st) end
    local acts = P.Buttons(sp, {
        { label = "Copy as your own", onClick = P.CopyOwn, w = 92 },
        { label = "Export", onClick = P.OpenExport, w = 64 },
        { label = "Delete", onClick = P.DeleteClick, danger = true, vis = own, w = 64,
            tip = "Deletes this scale for every character. Press twice." },
    })
    P.delBtn = acts.btns[3]

    AT.Section(sp, "Import", { visibleFn = function() return P.panel == "import" end })
    AT.RowDesc(sp, "Paste a stat weights string from a simulator.", 20)
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
    AT.Section(sp, "Preview")
    P.ItemRow(sp)
    AT.RowDesc(sp, "No gear with stats in your bags or worn.", 20, function() return #P.items == 0 end)
    P.TipRow(sp)
end

-- Laying out the columns

-- Column widths for a span: the mockup's at its width, in proportion otherwise.
function P.Widths(span)
    if span < P.MIN_SPAN then return { span, span, span }, false end
    local c = P.COLS
    local inner = span - 2 * P.GAP
    local total = c[1] + c[2] + c[3]
    local a = math.floor(inner * c[1] / total)
    local z = math.floor(inner * c[3] / total)
    return { a, inner - a - z, z }, true
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

-- The picked scale names its section; a long name stops at the column's edge.
function P.SyncTitle(w)
    local sec = P.headSec
    if not (sec and sec.title) then return end
    local cur = P.Cur()
    local t = cur and cur.name or Tr("Scale")
    if not sec.band then t = P.Upper(t) end
    sec.title:SetText(t)
    sec.title:SetWordWrap(false)
    sec.title:SetWidth(math.max(20, w - 24))
end

-- The host row holds the three columns. Each column is a page of its own; its boxes line up with the page's
-- sections: a column page sits 6 left of and 6 above where its first box starts.
function P.LayHost()
    local pg, row = P.page, P.host
    local W = pg:GetWidth() or 0
    if W < 60 then
        pg._sizeUnresolved = true
        return
    end
    local extra = pg._scroll and AT.ScrollExtra() or 0
    local widths, three = P.Widths(math.floor(W - 12 - extra))
    if P.scanDirty then P.ScanItems() end
    P.SyncTitle(widths[2])
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
        if three then
            x = x + w + P.GAP
            if ext - 6 > h then h = ext - 6 end
        elseif ext > 0 then
            h = y + ext - 6
            y = y + ext - 4 + LAY.gap
        end
    end
    P.laying = nil
    h = math.max(10, math.ceil(h))
    if row._h ~= h then row._h = h row:SetHeight(h) end
end

function P.Build(pg, m)
    P.page = pg
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Gear value in tooltips", m.isOn, m.setOn, nil,
        "Gear tooltips show each scale you pick: what the item is worth to its weights, and the change from what you wear.")
    MOD.Stamp(row, m, m.switch, "bool", nil, true)
    AT.Section(pg, nil)
    local host = AT.AddRow(pg, 40, m.isOn)
    P.host = host
    for i = 1, 3 do
        local sp = AT.NewPage(host)
        sp._bg:Hide()
        sp:Show()
        P.subs[i] = sp
    end
    P.BuildScales(P.subs[1])
    P.BuildScale(P.subs[2])
    P.BuildPreview(P.subs[3])
    host._sync = function() P.LayHost() end
    -- opening the page shows the active group and reads the bags afresh
    pg:HookScript("OnShow", function()
        P.group, P.scanDirty, P.tipDirty = nil, true, true
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
