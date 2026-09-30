-- AD_ReminderOptions: the Reminder group's panel, ArcUI v1's Cooldown Reminder options: the group's own tabs and each reminder's editor.
-- AD_Options calls in (every call nil-checked) and hands over its group pane's parts; every runtime action goes through NS.Reminders.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- The reminder editor's parts and state; its page is built on first use.
local RP = { tab = "Triggers", pool = {}, TABS = { "Triggers", "Appearance", "Load Conditions" } }
Options.ReminderPane = RP

-- A Reminder group has no cells, so no grid, icon or dynamic panels: its
-- reminders, how the pulse looks, how it sounds, then what every group has.
RP.GROUP_TABS = { "Reminders", "Appearance", "Sounds", "Position", "Load Conditions" }
-- Appearance: the pulse, then the container's look and the fade rules every
-- group has.
RP.GROUP_SECS = { "Pulse", "Container", "Visibility" }

-- The Appearance and Audio rows, in v1's order.
RP.PULSE = { "iconEnabled", "cancelOnCast", "hideMarker", "queueMode", "stackDirection", "stackSpacing",
    "replaceGuard", "queueMaxLen", "queueInterDelay", "pulseDuration", "size", "iconOpacity",
    "animStyle", "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak",
    "animZoomPopTime", "animZoomSettleTime", "auraSide", "auraSize", "auraSpacing" }
-- The aura reminders' row (Drivers\AD_DriverReminders.lua, RM.PlaceAuras).
RP.AURA_ROW = { "auraSide", "auraSize", "auraSpacing" }
RP.TUNING = { "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak",
    "animZoomPopTime", "animZoomSettleTime" }
RP.AUDIO = { "soundEnabled", "soundChannel", "soundName", "cutoffPreviousSound", "cutoffFadeTime",
    "ttsVoiceOverride", "ttsRateOverride", "ttsRate" }

function Options.GroupTabsFor(g, tabs)
    if g and g.groupKind == "reminder" then return RP.GROUP_TABS end
    return tabs
end

function Options.GroupSecsFor(g, secs)
    if g and g.groupKind == "reminder" then return RP.GROUP_SECS end
    return secs
end

-- The reminder the editor has open.
function RP.Rec()
    local ui = Options.ui
    local r = ui and ui.selRemId and NS.Store.Get(ui.selRemId)
    if r and r.type == "reminder" then return r end
end

function RP.GroupOf(r)
    local g = r and NS.Store.Get(r.groupId)
    if g and g.type == "group" and g.groupKind == "reminder" then return g end
end

-- A button says what happened for a moment, then its own label again.
function RP.Flash(btn, text)
    btn._label = btn._label or btn.fs:GetText()
    btn.fs:SetText(text)
    C_Timer.After(1.2, function() btn.fs:SetText(btn._label) end)
end

-- A trigger in a few words, for the reminder list.
function RP.Words(t)
    local sec = ("%g"):format(tonumber(t.seconds) or 3)
    if t.type == "after_ready" then return sec .. " s after ready" end
    if t.type == "into_cooldown" then return sec .. " s after cast" end
    if t.type == "enchant_missing" then return "When it's missing" end
    if t.type == "enchant_expiring" then
        return ("%g"):format(tonumber(t.seconds) or 60) .. " s before it runs out"
    end
    if t.type == "enchant_charges" then return "At " .. (tonumber(t.count) or 5) .. " charges left" end
    if t.type == "when_usable" then return t.ignoreCooldown and "When usable, cooldown ignored" or "When usable" end
    return NS.Schema.REMINDER_TRIGGER_LABELS[t.type] or tostring(t.type)
end

-- How many appearance settings the reminder sets itself.
function RP.OwnLook(r)
    local o = r and r.o and r.o.pulse
    local n = 0
    for k in pairs(o or {}) do
        if NS.Schema.reminder.pulse.fields[k] then n = n + 1 end
    end
    return n
end

-- A value the reminder sets itself: a thin cyan bar at its row's left edge.
function RP.Mark(row, field)
    local COL = NS.AT.COL
    local bar = row:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.9)
    bar:SetSize(2, 14)
    bar:SetPoint("LEFT", 3, 0)
    bar:Hide()
    row._adOwnMark = bar
    local base = row._sync
    row._sync = function()
        if base then base() end
        local r = RP.Rec()
        local o = r and r.o and r.o.pulse
        bar:SetShown(o ~= nil and o[field] ~= nil)
    end
end

function RP.Summary(r)
    local list = r.triggers or {}
    local s = list[1] and RP.Words(list[1]) or "no trigger"
    if #list > 1 then s = s .. ", +" .. (#list - 1) .. " more" end
    local R = NS.Reminders
    if R and not R.Loaded(r) then s = s .. "  -  not loaded here" end
    return s
end

-- An aura reminder (an aura icon in the group's row) in a few words.
function RP.AuraSummary(r)
    local Store = NS.Store
    local a = Store.Resolve(r, "auraActive", "activeAlpha") or 1
    local s = (a <= 0) and "Shows while the aura is missing" or "An aura icon: its Active opacity is above 0"
    if not Store.IsLoaded(r) then s = s .. "  -  not loaded here" end
    return s
end

-- The member the Reminder tab names and opens: the one open now, else one this
-- group had open (a reminder first), else its first; nil when it has none.
function RP.Current(g)
    local ui, Store = Options.ui, NS.Store
    local ic = ui.selIconId and Store.Get(ui.selIconId)
    if not (ic and ic.type == "icon" and ic.groupId == g.id) then ic = nil end
    local r = RP.Rec()
    if r and r.groupId ~= g.id then r = nil end
    if ui.grpMode == "ico" and ic then return ic end
    if ui.grpMode == "rem" and r then return r end
    return r or ic or Store.GroupMembers(g)[1]
end

-- Opens a member in the pane: a reminder in its own editor, an aura reminder
-- in the icon editor.
function RP.Open(rec)
    local ui = Options.ui
    if rec.type == "icon" then
        ui.selIconId, ui.grpMode = rec.id, "ico"
    else
        ui.selRemId, ui.grpMode = rec.id, "rem"
    end
end

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A typed spell: an ID, a pasted link, or a name from your spellbook.
function RP.ParseSpell(text)
    text = Trim(text)
    if text == "" then return nil end
    local id = tonumber(text) or tonumber(text:match("Hspell:(%d+)"))
    if not id and NS.SpellCatalog then
        local hit = NS.SpellCatalog.Search(text, 1)[1]
        id = hit and hit.spellID
    end
    if not id or id <= 0 then return nil end
    id = math.floor(id)
    if C_Spell.DoesSpellExist and not C_Spell.DoesSpellExist(id) then return nil end
    return id
end

function RP.ParseItem(text)
    text = Trim(text)
    local id = tonumber(text) or tonumber(text:match("Hitem:(%d+)"))
    if not id or id <= 0 then return nil end
    id = math.floor(id)
    if C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(id) then return nil end
    return id
end

-- This group's reminder of that spell, item or hand, when it has one: v1 kept
-- one per spell, and one reminder holds up to five triggers.
function RP.Existing(g, kind, id)
    local key = (kind == "item" and "itemID") or (kind == "enchant" and "hand") or "spellID"
    for _, r in ipairs(NS.Store.RemindersOf(g)) do
        if r.kind == kind and r.driver and r.driver[key] == id then return r end
    end
end

-- A new reminder for the group, named after its spell, item or hand, opened
-- in its editor; one the group already has opens instead. An enchant's id is
-- its hand, "main" or "off".
function RP.Create(g, kind, id)
    if kind == "enchant" then
        id = (id == "off") and "off" or "main"
    else
        id = tonumber(id)
        if not (id and id > 0) then return nil end
        id = math.floor(id)
    end
    local have = RP.Existing(g, kind, id)
    if have then
        Options.SelectIconHome(have)
        return have
    end
    local name
    if kind == "item" then
        name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    elseif kind ~= "enchant" then
        name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    end
    if issecretvalue and issecretvalue(name) then name = nil end
    local rec = NS.Store.NewReminder(g.id, kind, id, (type(name) == "string" and name ~= "") and name or nil)
    if rec then Options.SelectIconHome(rec) end
    return rec
end

-- The group's Reminders, Appearance and Audio tabs, on the group editor's
-- page. tabFn(): the open tab. kit: the page's SectionRows and PushBar, and
-- the window the dropdown lists open on; the reminder editor builds its
-- Appearance rows with it too (RP.rowKit).
function Options.ReminderGroupRows(pg, ctx, tabFn, kit)
    RP.rowKit = kit
    local AT = NS.AT
    local COL = AT.COL
    local Store = NS.Store
    local function G()
        local g = ctx()
        return (g and g.groupKind == "reminder") and g or nil
    end
    local function On(tab)
        return function() return tabFn() == tab and G() ~= nil end
    end
    -- the pulse's rows are Appearance's Pulse sub-tab (kit.subFn: the pick)
    local onLook = On("Appearance")
    local function lookVis()
        return onLook() and ((not kit.subFn) or kit.subFn() == "Pulse")
    end
    local remVis, audVis = On("Reminders"), On("Sounds")
    -- the reminders that pulse, and every member (aura reminders are icons)
    local function Count()
        local g = G()
        return g and #Store.RemindersOf(g) or 0
    end
    local function Members()
        local g = G()
        return g and #Store.GroupMembers(g) or 0
    end
    local function Auras()
        local g = G()
        return g and #Store.IconsOf(g) or 0
    end

    AT.Section(pg, "Reminders", { visibleFn = remVis })
    AT.RowDesc(pg, "No reminders yet: pick a spell below, add one by ID, or press + Add Reminder.", 20,
        function() return remVis() and Members() == 0 end)
    local act = AT.AddRow(pg, 28, remVis)
    local test = AT.MakeSmallButton(act, "Test Alert", 90)
    test:SetPoint("LEFT", 10, 0)
    test:SetScript("OnClick", function()
        AT.CloseDropdown()
        local g, R = G(), NS.Reminders
        if g and R and not R.Test(g) then RP.Flash(test, "Add one first") end
    end)
    AT.Tooltip(test, "Test Alert", "Plays the first reminder once, with this group's look and sound.")
    local add = AT.MakeSmallButton(act, "+ Add Reminder", 110)
    add:SetPoint("LEFT", test, "RIGHT", 8, 0)
    add.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    add:SetScript("OnClick", function()
        AT.CloseDropdown()
        local g = G()
        if g then Options.OpenAdd(g.layoutId, g.id) end
    end)
    AT.Tooltip(add, "+ Add Reminder", "Opens the Add window for a spell, an item, a weapon enchant or a missing aura to be reminded of.")
    act.button = test

    -- Spell Catalog: your spellbook as a grid, as in the Add window. A click
    -- picks a spell; Create Reminder makes it.
    AT.Section(pg, "Spell Catalog", { visibleFn = remVis })
    AT.RowInput(pg, "Search",
        function() return RP.query or "" end,
        function(v)
            RP.query = v
            AT.LayoutPage(pg)
        end,
        remVis, "Filters the spellbook below by name, or by the start of a spell ID.", "Name or spell ID", true)
    local CELL, GAP, MAXROWS, TOP = 32, 4, 6, 14
    local PITCH = CELL + GAP
    local grid = AT.AddRow(pg, TOP + PITCH, remVis)
    RP.grid = grid
    local cap = grid:CreateFontString(nil, "OVERLAY")
    cap:SetFont(STANDARD_TEXT_FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText("FROM YOUR SPELLBOOK - click one, then Create Reminder")
    local scroll, inner = AT.MakeScroll(grid)
    scroll:SetPoint("TOPLEFT", 8, -TOP)
    scroll:SetPoint("BOTTOMRIGHT", -12, GAP)
    local empty = grid:CreateFontString(nil, "OVERLAY")
    empty:SetFont(STANDARD_TEXT_FONT, 11, "")
    empty:SetPoint("LEFT", scroll, "TOPLEFT", 2, -CELL / 2)
    empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local cells = {}
    grid._cells = cells
    local function Cell(i)
        local b = cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, inner, "BackdropTemplate")
        b:SetSize(CELL, CELL)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- a spell this group already reminds of wears the group colour's dot
        local m = Options.GROUP_COLORS.reminder
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetSize(6, 6)
        b.dot:SetPoint("TOPRIGHT", -2, -2)
        b.dot:SetColorTexture(m[1], m[2], m[3], 1)
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.arcDeep) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            local e = b._e
            if not e then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(e.spellID)
            GameTooltip:AddLine("Spell ID: " .. e.spellID, COL.arc[1], COL.arc[2], COL.arc[3])
            if b._have then GameTooltip:AddLine("This group reminds you of it already.", 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local e = b._e
            if not e then return end
            AT.CloseDropdown()
            RP.pick = (RP.pick ~= e.spellID) and e.spellID or nil
            AT.LayoutPage(pg)
        end)
        cells[i] = b
        return b
    end
    -- The height follows the whole catalog, not the matches, so typing never
    -- moves the rows below; past MAXROWS rows the grid scrolls.
    grid._sync = function()
        local g = G()
        if not (g and NS.SpellCatalog) then return end
        local w = grid:GetWidth() or 0
        if w < 60 then w = (pg:GetWidth() or 0) - 24 end
        if w < 60 then
            pg._sizeUnresolved = true
            return
        end
        local cols = math.max(1, math.floor((w - 20 + GAP) / PITCH))
        local all = NS.SpellCatalog.All()
        local want = TOP + PITCH * math.min(MAXROWS, math.max(1, math.ceil(#all / cols)))
        if grid._h ~= want then
            grid._h = want
            grid:SetHeight(want)
        end
        local results = NS.SpellCatalog.Search(RP.query, #all)
        for i, e in ipairs(results) do
            local b = Cell(i)
            b._e, b._picked = e, e.spellID == RP.pick
            b._have = RP.Existing(g, "spell", e.spellID) ~= nil
            b.tex:SetTexture(e.texture)
            b.dot:SetShown(b._have)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ((i - 1) % cols) * PITCH, -math.floor((i - 1) / cols) * PITCH)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #results + 1, #cells do
            cells[i]._e = nil
            cells[i]:Hide()
        end
        local rows = math.ceil(#results / cols)
        inner:SetSize(cols * PITCH - GAP, math.max(1, rows * PITCH - GAP))
        scroll:UpdateScroll()
        empty:SetShown(#results == 0)
        empty:SetText((#all == 0) and "No spells listed yet: add one by ID below."
            or "Nothing in your spellbook matches: a spell ID below still works.")
    end

    -- the picked spell and what the button will do with it
    local pick = AT.AddRow(pg, 30, function() return remVis() and RP.pick ~= nil end)
    local ptex = pick:CreateTexture(nil, "ARTWORK")
    ptex:SetSize(22, 22)
    ptex:SetPoint("LEFT", 10, 0)
    ptex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local make = AT.MakeSmallButton(pick, "Create Reminder", 124)
    make:SetPoint("RIGHT", -12, 0)
    make.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    local pfs = pick:CreateFontString(nil, "OVERLAY")
    pfs:SetFont(STANDARD_TEXT_FONT, 12, "")
    pfs:SetPoint("LEFT", ptex, "RIGHT", 8, 0)
    pfs:SetPoint("RIGHT", make, "LEFT", -8, 0)
    pfs:SetJustifyH("LEFT")
    pfs:SetWordWrap(false)
    pfs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    pick._sync = function()
        local g, id = G(), RP.pick
        if not (g and id) then return end
        ptex:SetTexture(C_Spell.GetSpellTexture(id) or 134400)
        local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if type(nm) ~= "string" then nm = "Spell " .. id end
        pfs:SetText(nm .. "  (ID " .. id .. ")")
        make.fs:SetText(RP.Existing(g, "spell", id) and "Edit Reminder" or "Create Reminder")
    end
    make:SetScript("OnClick", function()
        AT.CloseDropdown()
        local g, id = G(), RP.pick
        if not (g and id) then return end
        RP.pick = nil
        RP.Create(g, "spell", id)
    end)

    local info = AT.AddRow(pg, 26, remVis)
    local ifs = info:CreateFontString(nil, "OVERLAY")
    ifs:SetFont(STANDARD_TEXT_FONT, 11, "")
    ifs:SetPoint("LEFT", 10, 0)
    ifs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local rescan = AT.MakeQuietButton(info, "Rescan", 70)
    rescan:SetPoint("RIGHT", -12, 0)
    rescan:SetScript("OnClick", function()
        AT.CloseDropdown()
        if not NS.SpellCatalog then return end
        RP.Flash(rescan, NS.SpellCatalog.Rescan() .. " spells")
        AT.LayoutPage(pg)
    end)
    AT.Tooltip(rescan, "Rescan", "Reads your spellbook again, after you learn or swap spells. Skipped in combat.")
    info._sync = function()
        if not NS.SpellCatalog then return end
        local all = NS.SpellCatalog.All()
        local shown = #NS.SpellCatalog.Search(RP.query, #all)
        ifs:SetText((shown < #all) and ("Showing " .. shown .. " of " .. #all .. " spells")
            or (#all .. " spells"))
    end
    info.button = rescan

    -- Add by ID: a spell the catalog does not list, or an item.
    local function ByID(label, key, kind, desc, hint)
        local row = AT.RowInput(pg, label,
            function() return RP[key] or "" end,
            function(v) RP[key] = v end,
            remVis, desc, hint, true)
        local b = AT.MakeSmallButton(row, "Add", 52)
        b:SetPoint("LEFT", row._colCtrl, "RIGHT", 6, 0)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            local g = G()
            if not g then return end
            local id = ((kind == "item") and RP.ParseItem or RP.ParseSpell)(RP[key])
            if not id then
                RP.Flash(b, "Unknown")
                return
            end
            RP[key] = nil
            row._colCtrl:SetText("")
            RP.Create(g, kind, id)
        end)
        AT.Tooltip(b, "Add", "Makes a reminder of it in this group, or opens the one it has.")
    end
    ByID("Add Spell ID", "addSpell", "spell",
        "A spell ID, a spell link, or the name of a spell in your spellbook: for spells the catalog does not list.",
        "Spell ID or name")
    ByID("Add Item ID", "addItem", "item",
        "An item ID or an item link. A trinket or other gear reminds you only while you wear it.",
        "Item ID")
    -- a weapon enchant, by the hand picker the enchant icons use
    local encRow = AT.RowDropdown(pg, kit.win, "Add Weapon Enchant",
        function() return RP.addHand or "main" end,
        function(v) RP.addHand = v end,
        function() return Options.EnchantHandItems() end,
        remVis)
    local encAdd = AT.MakeSmallButton(encRow, "Add", 52)
    encAdd:SetPoint("LEFT", encRow._colCtrl, "RIGHT", 6, 0)
    encAdd:SetScript("OnClick", function()
        AT.CloseDropdown()
        local g = G()
        if g then RP.Create(g, "enchant", RP.addHand or "main") end
    end)
    AT.Tooltip(encAdd, "Add", "Makes a reminder of the enchant on that weapon (an imbue, a poison, an oil or a stone), or opens the one it has.")

    -- Active Reminders: each with its triggers in words (an aura reminder
    -- with when it shows); Edit opens it.
    local listVis = function() return remVis() and Members() > 0 end
    AT.Section(pg, "Active Reminders", { visibleFn = listVis })
    local LINE = 36
    local list = AT.AddRow(pg, LINE, listVis)
    local lines = {}
    local function Line(i)
        local L = lines[i]
        if L then return L end
        L = CreateFrame("Frame", nil, list)
        L:SetHeight(LINE - 2)
        L.tex = L:CreateTexture(nil, "ARTWORK")
        L.tex:SetSize(26, 26)
        L.tex:SetPoint("LEFT", 6, 0)
        L.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        L.edit = AT.MakeSmallButton(L, "Edit", 56)
        L.edit:SetPoint("RIGHT", -6, 0)
        L.name = L:CreateFontString(nil, "OVERLAY")
        L.name:SetFont(STANDARD_TEXT_FONT, 12, "")
        L.name:SetPoint("TOPLEFT", L.tex, "TOPRIGHT", 8, 0)
        L.name:SetPoint("RIGHT", L.edit, "LEFT", -8, 0)
        L.name:SetJustifyH("LEFT")
        L.name:SetWordWrap(false)
        L.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        L.sub = L:CreateFontString(nil, "OVERLAY")
        L.sub:SetFont(STANDARD_TEXT_FONT, 10, "")
        L.sub:SetPoint("BOTTOMLEFT", L.tex, "BOTTOMRIGHT", 8, 0)
        L.sub:SetPoint("RIGHT", L.edit, "LEFT", -8, 0)
        L.sub:SetJustifyH("LEFT")
        L.sub:SetWordWrap(false)
        L.sub:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lines[i] = L
        return L
    end
    list._lines = lines
    list._sync = function()
        local g = G()
        local recs = g and Store.GroupMembers(g) or {}
        for i, r in ipairs(recs) do
            local L = Line(i)
            L:ClearAllPoints()
            L:SetPoint("TOPLEFT", 0, -(i - 1) * LINE)
            L:SetPoint("TOPRIGHT", 0, -(i - 1) * LINE)
            L.tex:SetTexture(NS.Factory.GetTexture(r))
            L.name:SetText(r.name or "?")
            L.sub:SetText((r.type == "icon") and RP.AuraSummary(r) or RP.Summary(r))
            L.edit:SetScript("OnClick", function()
                AT.CloseDropdown()
                Options.SelectIconHome(r)
            end)
            L:Show()
        end
        for i = #recs + 1, #lines do lines[i]:Hide() end
        local want = math.max(LINE, #recs * LINE)
        if list._h ~= want then
            list._h = want
            list:SetHeight(want)
        end
    end

    -- Appearance: v1's pulse window. The group's own frame is its spot, so
    -- Lock position and Show Anchor are this window's edit mode.
    local function Rows(fields) kit.SectionRows(pg, "iconGroup", "pulse", ctx, lookVis, fields) end
    AT.Section(pg, "Pulse", { visibleFn = lookVis })
    local function Marked() return Store.Resolve(G(), "pulse", "hideMarker") ~= true end
    AT.RowDesc(pg, "While this window is open a dim icon marks the spot; drag its name tab to move it.", 20,
        function() return lookVis() and Marked() end)
    AT.RowDesc(pg, "While this window is open the outline marks the spot; drag its name tab to move it.", 20,
        function() return lookVis() and not Marked() end)
    Rows({ "iconEnabled", "cancelOnCast", "holdUntilCast", "hideMarker" })
    AT.Section(pg, "Overlap", { visibleFn = lookVis })
    Rows({ "queueMode", "stackDirection", "stackSpacing", "replaceGuard", "queueMaxLen", "queueInterDelay" })
    AT.Section(pg, "Size and Time", { visibleFn = lookVis })
    Rows({ "pulseDuration", "size", "iconOpacity" })
    AT.RowActions(pg, {
        { label = "Preview Alert", w = 110, onClick = function()
            local g, R = G(), NS.Reminders
            if g and R then R.Test(g) end
        end },
        { label = "Preview Multiple", w = 124, onClick = function()
            local g, R = G(), NS.Reminders
            if g and R then R.PreviewMultiple(g) end
        end },
    }, "left", function() return lookVis() and Count() > 0 end)
    AT.Section(pg, "Animation Tuning", { visibleFn = lookVis })
    Rows({ "animStyle", "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak",
        "animZoomPopTime", "animZoomSettleTime" })
    AT.RowButton(pg, "Reset", function()
        local g = G()
        if g then Store.ResetSection(g, "pulse", RP.TUNING) end
        AT.LayoutPage(pg)
    end, function()
        local g = G()
        return lookVis() and Store.Resolve(g, "pulse", "animStyle") ~= "no_fade"
    end, 70, "Reset animation tuning", true)
    -- the aura reminders' row, once the group has one
    local rowVis = function() return lookVis() and Auras() > 0 end
    AT.Section(pg, "Aura Reminders", { visibleFn = rowVis })
    AT.RowDesc(pg, "Each shows in its own slot while its aura is missing; the pulse keeps its spot.", 20, rowVis)
    kit.SectionRows(pg, "iconGroup", "pulse", ctx, rowVis, RP.AURA_ROW)
    AT.Section(pg, nil, { visibleFn = lookVis })
    kit.PushBar(pg, ctx, "pulse", lookVis, RP.PULSE)

    -- Audio: the group's sound and speech; each trigger picks its own.
    local function ARows(fields) kit.SectionRows(pg, "iconGroup", "audio", ctx, audVis, fields) end
    AT.Section(pg, "Audio", { visibleFn = audVis })
    AT.RowDesc(pg, "New triggers start silent: turn Play sound on in each reminder's triggers.", 20, audVis)
    ARows({ "soundEnabled", "soundChannel", "soundName", "cutoffPreviousSound", "cutoffFadeTime" })
    AT.Section(pg, "Text to Speech", { visibleFn = audVis })
    AT.RowDesc(pg, "The text to speak is set on each trigger.", 20, audVis)
    ARows({ "ttsVoiceOverride", "ttsRateOverride", "ttsRate" })
    AT.RowButton(pg, "Preview Voice", function()
        local g, R = G(), NS.Reminders
        if g and R then R.Speak(g, "Cooldown Reminder test") end
    end, audVis, 110, "Hear the voice")
    AT.Section(pg, nil, { visibleFn = audVis })
    kit.PushBar(pg, ctx, "audio", audVis, RP.AUDIO)
    AT.Section(pg, nil)
end

-- The reminder editor: its band, then Triggers (v1's per-reminder editor)
-- and Load Conditions. kit: Options.GroupPaneKit.
function RP.Build(kit)
    local AT = NS.AT
    local COL = AT.COL
    local Store, S = NS.Store, NS.Schema
    local owner = kit.win
    local MAXT = S.REMINDER_MAX_TRIGGERS
    local pg = AT.NewPage(kit.pane)
    AT.MakeScrollable(pg)
    RP.page = pg
    local Rec = RP.Rec
    local function G() return RP.GroupOf(Rec()) end
    local function Set(i, field, value)
        local r, R = Rec(), NS.Reminders
        if r and R then R.SetTrigger(r, i, field, value) end
        AT.LayoutPage(pg)
    end

    -- the band: art, name, and the reminder's own actions
    local head = AT.AddRow(pg, 34)
    local icon = kit.IconButton(head, 26)
    icon:SetPoint("LEFT", head, "TOPLEFT", 8, -17)
    icon:EnableMouse(false)
    local del = AT.MakeSmallButton(head, "Delete", 56)
    del:SetPoint("RIGHT", -8, 0)
    del:SetScript("OnClick", function()
        AT.CloseDropdown()
        Options.ConfirmDelete(Rec())
    end)
    local exp = AT.MakeSmallButton(head, "Export", 56)
    exp:SetPoint("RIGHT", del, "LEFT", -5, 0)
    exp:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = Rec()
        if r then Options.OpenExport(r.id) end
    end)
    AT.Tooltip(exp, "Export", "Opens Import / Export with just this reminder ticked and its share string ready to copy: its triggers, load conditions and its own appearance.")
    local dup = AT.MakeSmallButton(head, "Duplicate", 66)
    dup:SetPoint("RIGHT", exp, "LEFT", -5, 0)
    dup:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = Rec()
        local c = r and Store.Duplicate(r.id)
        if c then Options.SelectIconHome(c) end
    end)
    AT.Tooltip(dup, "Duplicate", "Makes a copy of this reminder, every trigger included, in the same group.")
    local ren = AT.MakeSmallButton(head, "Rename", 58)
    ren:SetPoint("RIGHT", dup, "LEFT", -5, 0)
    AT.Tooltip(ren, "Rename", "Edits the name in place. Enter saves, Escape cancels.")
    local name = head:CreateFontString(nil, "OVERLAY")
    name:SetFont(STANDARD_TEXT_FONT, 13, "")
    name:SetPoint("LEFT", head, "TOPLEFT", 42, -17)
    name:SetPoint("RIGHT", ren, "LEFT", -10, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    local box = CreateFrame("EditBox", nil, head, "BackdropTemplate")
    box:SetHeight(20)
    box:SetPoint("LEFT", name, "LEFT", -6, 0)
    box:SetPoint("RIGHT", ren, "LEFT", -10, 0)
    AT.Skin(box, COL.well)
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    box:Hide()
    local function Editing(on)
        name:SetShown(not on)
        box:SetShown(on)
    end
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function()
        box._cancel = true
        box:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function()
        if not box:IsShown() then return end
        local r = Rec()
        if r and not box._cancel then Store.Rename(r.id, box:GetText()) end
        box._cancel = nil
        Editing(false)
    end)
    ren:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = Rec()
        if not r then return end
        box:SetText(r.name or "")
        Editing(true)
        box:SetFocus()
        box:HighlightText()
    end)
    head._sync = function()
        local r = Rec()
        if not r then return end
        icon.tex:SetTexture(NS.Factory.GetTexture(r))
        name:SetText("Editing:  " .. (r.name or "?"))
    end
    RP.head = head

    local tabRow = AT.AddRow(pg, 30)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        local h = tabRow._strip:Set(RP.TABS, RP.tab, function(t)
            RP.tab = t
            AT.LayoutPage(pg)
        end)
        local want = (h or 24) + 6
        if tabRow._h ~= want then
            tabRow._h = want
            tabRow:SetHeight(want)
        end
    end

    local trigVis = function() return RP.tab == "Triggers" and Rec() ~= nil end
    AT.Section(pg, "Reminder", { visibleFn = trigVis })
    -- what it watches, in words
    local what = AT.AddRow(pg, 22, trigVis)
    local wfs = what:CreateFontString(nil, "OVERLAY")
    wfs:SetFont(STANDARD_TEXT_FONT, 11, "")
    wfs:SetPoint("LEFT", 10, 0)
    wfs:SetPoint("RIGHT", -10, 0)
    wfs:SetJustifyH("LEFT")
    wfs:SetWordWrap(false)
    wfs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    what._sync = function()
        local r = Rec()
        if not r then return end
        local d = r.driver or {}
        if r.kind == "enchant" then
            wfs:SetText("Watches the " .. ((d.hand == "off") and "Off Hand" or "Main Hand") .. " enchant")
            return
        end
        local item = r.kind == "item"
        local id = item and d.itemID or d.spellID
        local nm
        if item then
            nm = id and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        else
            nm = id and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        end
        -- an item not cached yet has no name: the ID alone says which
        nm = (type(nm) == "string" and nm ~= "") and (nm .. "  ") or ""
        wfs:SetText("Watches the " .. (item and "item " or "spell ") .. nm .. "(ID " .. tostring(id) .. ")")
    end
    AT.RowDesc(pg, "A trinket or other gear reminds you only while you wear it.", 20, function()
        local r = Rec()
        return trigVis() and r.kind == "item"
    end)
    local prev = AT.RowButton(pg, "Preview Alert", function()
        local r, R = Rec(), NS.Reminders
        if r and R then R.Preview(r) end
    end, trigVis, 110, "Trigger 1, as it will fire")
    AT.Tooltip(prev.button, "Preview Alert", "Fires the first trigger once, as it will in play, even where the conditions would keep it quiet.")

    -- the trigger types of the reminder's kind: a weapon enchant has its own,
    -- and an item lacks the spell-only ones
    local function TypeItems()
        local r = Rec()
        local items = {}
        for _, v in ipairs((r and r.kind == "enchant") and S.REMINDER_ENCHANT_TRIGGERS or S.REMINDER_TRIGGERS) do
            if not (r and r.kind == "item" and S.REMINDER_SPELL_ONLY[v]) then
                items[#items + 1] = { value = v, text = S.REMINDER_TRIGGER_LABELS[v] }
            end
        end
        return items
    end
    local function ListItems(values, labels)
        return function()
            local items = {}
            for _, v in ipairs(values) do items[#items + 1] = { value = v, text = labels[v] or v } end
            return items
        end
    end
    local curve = S.iconGroup.pulse.fields.animFadeSmoothing
    local CurveItems = ListItems(curve.values, curve.labels)
    local AnimItems = ListItems(S.REMINDER_ANIMS, S.REMINDER_ANIM_LABELS)
    local GlowItems = ListItems(S.REMINDER_GLOWS, S.REMINDER_GLOW_LABELS)
    local function SoundItems()
        local items = (NS.Sounds and NS.Sounds.Items()) or {}
        items[1] = { value = "", text = "Default (the group's)" }
        return items
    end

    -- One trigger's rows, in v1's order.
    local function Slot(i)
        local function T()
            local r = Rec()
            return r and r.triggers and r.triggers[i]
        end
        local tv = function() return trigVis() and T() ~= nil end
        -- the reminder's value (its own, else the group's) while the trigger
        -- sets none
        local function Eff(key)
            local t, r = T(), Rec()
            return (t and t[key]) or (r and Store.Resolve(r, "pulse", key))
        end
        local function Anim()
            local t = T()
            return (t and t.animStyle) or Eff("animStyle") or "fade"
        end
        local soundVis = function()
            local t = T()
            return tv() and not t.soundDisabled
        end
        local ovVis = function(style)
            return function()
                local t = T()
                return tv() and t.overrideAnim == true and (style == nil or Anim() == style)
            end
        end

        AT.Section(pg, "Trigger " .. i, { visibleFn = tv })
        AT.RowDropdown(pg, owner, "When does this trigger fire?",
            function()
                local t = T()
                return t and t.type or "when_ready"
            end,
            function(v) Set(i, "type", v) end,
            TypeItems, tv)
        -- { label, its type, the default, the most }: an enchant can run for
        -- half an hour, so its warning can come that early
        for _, sec in ipairs({ { "Seconds after ready", "after_ready", 3, 600 },
            { "Seconds after cast", "into_cooldown", 3, 600 },
            { "Seconds before it runs out", "enchant_expiring", 60, 3600 } }) do
            AT.RowInput(pg, sec[1],
                function()
                    local t = T()
                    return ("%g"):format(tonumber(t and t.seconds) or sec[3])
                end,
                function(v)
                    local n = tonumber(v)
                    if n and n > 0 then Set(i, "seconds", math.max(0.1, math.min(sec[4], n))) end
                end,
                function()
                    local t = T()
                    return tv() and t.type == sec[2]
                end,
                "How long, in seconds; decimals work (1.5). Enter applies it.")
        end
        AT.RowInput(pg, "Charges left",
            function()
                local t = T()
                return tostring(tonumber(t and t.count) or 5)
            end,
            function(v)
                local n = tonumber(v)
                if n and n >= 1 then Set(i, "count", math.floor(math.min(999, n))) end
            end,
            function()
                local t = T()
                return tv() and t.type == "enchant_charges"
            end,
            "It fires once the enchant has this many charges or fewer left. Enter applies it.")
        local function TypeIs(a, b)
            return function()
                local t = T()
                return tv() and (t.type == a or t.type == b)
            end
        end
        AT.RowToggle(pg, "Fire even while on cooldown",
            function()
                local t = T()
                return t ~= nil and t.ignoreCooldown == true
            end,
            function(v) Set(i, "ignoreCooldown", v or nil) end,
            TypeIs("when_usable"),
            "Fires the moment the spell's own requirement is met (a dodge, a proc that activates it, enough mana), even while it is still cooling down.")
        -- "Clear when it ends", in the words of each type's moment
        local function ClearRow(label, ty, desc)
            AT.RowToggle(pg, label,
                function()
                    local t = T()
                    return t ~= nil and t.clearOnEnd == true
                end,
                function(v) Set(i, "clearOnEnd", v or nil) end,
                TypeIs(ty), desc)
        end
        ClearRow("Clear when no longer usable", "when_usable",
            "Once the spell stops being usable, the pulse this trigger started leaves the screen, the queue and the hold.")
        ClearRow("Clear when the proc ends", "on_proc",
            "Once the proc glow goes, the pulse this trigger started leaves the screen, the queue and the hold.")
        AT.RowToggle(pg, "Play sound",
            function()
                local t = T()
                return t ~= nil and not t.soundDisabled
            end,
            function(v) Set(i, "soundDisabled", (not v) or nil) end,
            tv, "Off: this trigger pulses silently. A new trigger starts silent.")
        AT.RowToggle(pg, "Show icon",
            function()
                local t = T()
                return t ~= nil and t.showIcon ~= false
            end,
            function(v)
                if v then Set(i, "showIcon", nil) else Set(i, "showIcon", false) end
            end,
            tv, "Off: this trigger plays its sound or speech only, with no pulse.")
        AT.RowToggle(pg, "Only fire when proc is active",
            function()
                local t = T()
                return t ~= nil and t.requireProc == true
            end,
            function(v) Set(i, "requireProc", v or nil) end,
            function()
                local t = T()
                return tv() and t.type ~= "on_proc" and Rec().kind ~= "enchant"
            end,
            "Fires only while the spell's proc glow is up, on top of the trigger's own timing. An item checks its use spell.")
        local srow = AT.RowDropdown(pg, owner, "Sound",
            function()
                local t = T()
                return (t and t.sound) or ""
            end,
            function(v) Set(i, "sound", (type(v) == "string" and v ~= "") and v or nil) end,
            SoundItems, soundVis)
        local play = AT.MakeSmallButton(srow, "Play", 52)
        play:SetPoint("LEFT", srow._colCtrl, "RIGHT", 6, 0)
        play:SetScript("OnClick", function()
            AT.CloseDropdown()
            local t, g = T(), G()
            if not (t and g and NS.Sounds) then return end
            NS.Sounds.Preview(t.sound or Store.Resolve(g, "audio", "soundName"),
                Store.Resolve(g, "audio", "soundChannel"))
        end)
        AT.Tooltip(play, "Play", "Hear this trigger's sound once, on the group's sound channel.")
        local trow = AT.RowInput(pg, "Speak this text",
            function()
                local t = T()
                return (t and t.tts) or ""
            end,
            function(v)
                v = Trim(v)
                Set(i, "tts", (v ~= "") and v:sub(1, 200) or nil)
            end,
            soundVis, "Text to speech: when set, it is spoken instead of the sound.", "Optional")
        local speak = AT.MakeSmallButton(trow, "Speak", 56)
        speak:SetPoint("LEFT", trow._colCtrl, "RIGHT", 6, 0)
        speak:SetScript("OnClick", function()
            AT.CloseDropdown()
            local t, g, R = T(), G(), NS.Reminders
            if not (t and g and R) then return end
            if not R.Speak(g, t.tts) then RP.Flash(speak, "No text") end
        end)
        AT.Tooltip(speak, "Speak", "Hear this trigger's text once, in the group's voice.")
        AT.RowDropdown(pg, owner, "Animation",
            function()
                local t = T()
                return (t and t.animStyle) or "default"
            end,
            function(v) Set(i, "animStyle", (v ~= "default") and v or nil) end,
            AnimItems, tv)
        local prow = AT.RowSlider(pg, "Priority",
            function()
                local t = T()
                return (t and t.priority) or 0
            end,
            function(v)
                v = math.floor((tonumber(v) or 0) + 0.5)
                Set(i, "priority", (v >= 1) and v or nil)
            end,
            0, 5, 1, false, tv)
        prow:EnableMouse(true)
        AT.Tooltip(prow, "Priority", "0 is normal. A higher priority takes over a lower one on screen, never gives way to it, and is the last out of a full queue or stack. Equal ones follow the group's Overlap Behavior.")
        AT.RowDropdown(pg, owner, "Glow",
            function()
                local t = T()
                return (t and t.glowType) or "none"
            end,
            function(v) Set(i, "glowType", (v ~= "none") and v or nil) end,
            GlowItems, tv)
        -- The picker's opacity slider: RM.StartGlow hands the alpha to the glow.
        AT.RowColor(pg, "Glow color",
            function()
                local t = T()
                local c = (t and t.glowColor) or S.REMINDER_GLOW_COLOR
                return { c[1], c[2], c[3], c[4] or 1 }
            end,
            function(c)
                local t = T()
                local a = c[4] or (t and t.glowColor and t.glowColor[4]) or 1
                Set(i, "glowColor", { c[1], c[2], c[3], a })
            end,
            function()
                local t = T()
                return tv() and t.glowType ~= nil
            end, { alpha = true })
        AT.RowToggle(pg, "Override timing and tuning",
            function()
                local t = T()
                return t ~= nil and t.overrideAnim == true
            end,
            function(v) Set(i, "overrideAnim", v or nil) end,
            tv, "On: this trigger has its own pulse duration and animation tuning. Off drops them, and the reminder's apply.")
        local function OvSlider(label, key, lo, hi, step, style)
            AT.RowSlider(pg, label,
                function() return Eff(key) or lo end,
                function(v) Set(i, key, math.floor(v * 100 + 0.5) / 100) end,
                lo, hi, step, "%.2f", ovVis(style))
        end
        -- typed, like the reminder's own duration: a pulse can run long
        AT.RowInput(pg, "Pulse Duration (override)",
            function() return string.format("%.2f", Eff("pulseDuration") or 2) end,
            function(v)
                local n = tonumber(v)
                if n then Set(i, "pulseDuration", math.floor(math.max(0.1, math.min(600, n)) * 100 + 0.5) / 100) end
            end,
            ovVis(), "Seconds this trigger's pulse runs, from 0.1 up to 600.")
        AT.RowDropdown(pg, owner, "Fade Curve (override)",
            function() return Eff("animFadeSmoothing") or "OUT" end,
            function(v) Set(i, "animFadeSmoothing", v) end,
            CurveItems, ovVis("fade"))
        OvSlider("Flash Step Speed (override)", "animFlashSpeed", 0.03, 0.30, 0.01, "flash")
        OvSlider("Zoom Start Scale (override)", "animZoomStart", 0.30, 1, 0.05, "zoom")
        OvSlider("Zoom Peak Scale (override)", "animZoomPeak", 1, 1.50, 0.05, "zoom")
        OvSlider("Zoom Pop Speed (override)", "animZoomPopTime", 0.04, 0.40, 0.01, "zoom")
        OvSlider("Zoom Settle Speed (override)", "animZoomSettleTime", 0.02, 0.30, 0.01, "zoom")
        AT.RowActions(pg, {
            { label = "Remove this trigger", w = 140, quiet = true, onClick = function()
                local r, R = Rec(), NS.Reminders
                if r and R then R.RemoveTrigger(r, i) end
                AT.LayoutPage(pg)
            end },
        }, "left", function()
            local r = Rec()
            return tv() and #r.triggers > 1
        end)
    end
    for i = 1, MAXT do
        Options.BuildYield()
        Slot(i)
    end
    local addVis = function()
        local r = Rec()
        return trigVis() and #(r.triggers or {}) < MAXT
    end
    AT.Section(pg, nil, { visibleFn = addVis })
    AT.RowActions(pg, {
        { label = "+ Add Trigger", w = 110, onClick = function()
            local r, R = Rec(), NS.Reminders
            if r and R then R.AddTrigger(r) end
            AT.LayoutPage(pg)
        end },
    }, "left", addVis)

    -- Appearance: the reminder's own look (Schema.REMINDER_LOOK). Each row reads
    -- the group's value until set here; Use group appearance drops them all.
    local apVis = function() return RP.tab == "Appearance" and Rec() ~= nil end
    local SR = RP.rowKit and RP.rowKit.SectionRows
    if SR then
        local function Rows(fields) SR(pg, "reminder", "pulse", Rec, apVis, fields) end
        AT.Section(pg, "Pulse", { visibleFn = apVis })
        local st = AT.AddRow(pg, 24, apVis)
        local sfs = st:CreateFontString(nil, "OVERLAY")
        sfs:SetFont(STANDARD_TEXT_FONT, 11, "")
        sfs:SetPoint("LEFT", 10, 0)
        sfs:SetJustifyH("LEFT")
        sfs:SetWordWrap(false)
        local back = AT.MakeQuietButton(st, "Use group appearance", 150)
        back:SetPoint("RIGHT", -12, 0)
        st._sync = function()
            local n = RP.OwnLook(Rec())
            if n == 0 then
                sfs:SetText("Follows the group's appearance.")
                sfs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
                sfs:SetPoint("RIGHT", -12, 0)
                back:Hide()
            else
                sfs:SetText((n == 1) and "1 setting differs from the group; a cyan bar marks it."
                    or (n .. " settings differ from the group; a cyan bar marks each."))
                sfs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
                sfs:SetPoint("RIGHT", back, "LEFT", -8, 0)
                back:Show()
            end
        end
        back:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = Rec()
            if r then Store.ResetSection(r, "pulse") end
            AT.LayoutPage(pg)
        end)
        AT.Tooltip(back, "Use group appearance", "Drops this reminder's own appearance settings, so every one of them follows the group again.")
        RP.lookStatus = st
        Rows({ "cancelOnCast", "holdUntilCast" })
        AT.Section(pg, "Size and Time", { visibleFn = apVis })
        Rows({ "pulseDuration", "size", "iconOpacity" })
        local lp = AT.RowButton(pg, "Preview Alert", function()
            local r, R = Rec(), NS.Reminders
            if r and R then R.PreviewLook(r) end
        end, apVis, 110, "With the look set here")
        AT.Tooltip(lp.button, "Preview Alert", "Plays this reminder once with the look set here, even where the conditions would keep it quiet.")
        AT.Section(pg, "Animation Tuning", { visibleFn = apVis })
        Rows({ "animStyle", "animFadeSmoothing", "animFlashSpeed", "animZoomStart", "animZoomPeak",
            "animZoomPopTime", "animZoomSettleTime" })
        for _, sec in ipairs(pg._sections) do
            for _, row in ipairs(sec.rows) do
                local m = row._adMeta
                if m and m.family == "reminder" then RP.Mark(row, m.field) end
            end
        end
    end

    kit.ConditionRows(pg, Rec, function() return RP.tab == "Load Conditions" and Rec() ~= nil end)
    return pg
end

-- The group pane for a Reminder group: its reminders and aura reminders on the
-- strip, Group Settings | Reminder, and the page for the one open: a
-- reminder's own editor, or the icon editor for an aura reminder.
function Options.RefreshReminderPane(group)
    local kit, ui = Options.GroupPaneKit, Options.ui
    if not (kit and ui and group) then return end
    local AT, Store = NS.AT, NS.Store
    local list = Store.GroupMembers(group)
    -- the open aura reminder must be this group's, else the group
    if ui.grpMode == "ico" then
        local ic = ui.selIconId and Store.Get(ui.selIconId)
        if not (ic and ic.type == "icon" and ic.groupId == group.id) then ui.grpMode = "grp" end
    end
    -- the open reminder must be this group's: else its first, else the group
    if ui.grpMode == "rem" then
        local r = RP.Rec()
        if not (r and r.groupId == group.id) then
            local first = Store.RemindersOf(group)[1]
            ui.selRemId = first and first.id or nil
            if not ui.selRemId then ui.grpMode = "grp" end
        end
    end
    for _, b in ipairs(kit.stripPool) do b:Hide() end
    for i, r in ipairs(list) do
        local b = RP.pool[i]
        if not b then
            b = kit.IconButton(kit.strip, 32)
            RP.pool[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", 8 + (i - 1) * 37, 0)
        b.tex:SetTexture(NS.Factory.GetTexture(r))
        local icon = r.type == "icon"
        b:SetSelected((icon and ui.grpMode == "ico" and ui.selIconId == r.id)
            or (not icon and ui.grpMode == "rem" and ui.selRemId == r.id))
        b:SetScript("OnClick", function()
            RP.Open(r)
            Options.RefreshAll()
        end)
        b:Show()
    end
    for i = #list + 1, #RP.pool do RP.pool[i]:Hide() end
    kit.strip.add:ClearAllPoints()
    kit.strip.add:SetPoint("LEFT", 8 + #list * 37, 0)
    local cur = RP.Current(group)
    local remTab = cur and ("Reminder: " .. (cur.name or "?")) or "Reminder: none"
    kit.switch:Set({ "Group Settings", remTab }, (ui.grpMode == "grp") and "Group Settings" or remTab,
        function(tab)
            if tab == "Group Settings" then
                ui.grpMode = "grp"
            else
                local c = RP.Current(group)
                if c then RP.Open(c) end
            end
            Options.RefreshAll()
        end, 11)
    local rem, ico = ui.grpMode == "rem", ui.grpMode == "ico"
    -- an aura reminder edits in the icon editor, under its preview, as in any group
    local iconPage = kit.iconPage
    iconPage:SetShown(ico)
    local prevH = kit.AttachPreview(kit.pane, -116, ico)
    if ico then
        iconPage:SetParent(kit.pane)
        iconPage:ClearAllPoints()
        iconPage:SetPoint("TOPLEFT", 0, -116 - (prevH or 0))
        iconPage:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    kit.groupPage:SetShown(not (rem or ico))
    if rem and not RP.page then RP.Build(kit) end
    if RP.page then
        RP.page:ClearAllPoints()
        RP.page:SetPoint("TOPLEFT", 0, -116)
        RP.page:SetPoint("BOTTOMRIGHT", 0, 0)
        RP.page:SetShown(rem)
    end
    AT.LayoutPage((rem and RP.page) or (ico and iconPage) or kit.groupPage)
end

-- Another group kind is open: none of this shows.
function Options.HideReminderPane()
    if RP.page then RP.page:Hide() end
    for _, b in ipairs(RP.pool) do b:Hide() end
end
