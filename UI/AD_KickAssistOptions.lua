-- AD_KickAssistOptions: the Kick Assist module's card and settings page (retail).
-- Also the marker picker window a ready check opens. The engine is
-- Modules\AD_KickAssist.lua (NS.KickAssist).
local ADDON, NS = ...
local KA = NS.KickAssist
local AT = NS.AT
if not (KA and AT) then return end
local COL = AT.COL
local Tr = AT.Tr
local Events = NS.Events

local KAO = {}
NS.KickAssistOptions = KAO

-- Markers

local SPRITE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- One cell of the 4x4 raid marker sheet.
local function SetMarkerTexture(tex, index)
    tex:SetTexture(SPRITE)
    local col = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    tex:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
end

-- The game's own marker names, already in the player's language.
function KAO.MarkerName(i)
    if i == 0 then return Tr("No marker") end
    local n = _G["RAID_TARGET_" .. i]
    if type(n) == "string" and n ~= "" then return n end
    return Tr("Marker %d"):format(i)
end

function KAO.MarkerItems()
    local out = {}
    for i = 1, 8 do out[#out + 1] = { value = i, text = KAO.MarkerName(i), raw = true } end
    out[#out + 1] = { value = 0, text = KAO.MarkerName(0), raw = true }
    return out
end

-- Feedback on a button's own words for a moment: the UI is the status line.
local function FlashLabel(b, text, back)
    if not b then return end
    b:SetLabel(text)
    local gen = (b._kaGen or 0) + 1
    b._kaGen = gen
    C_Timer.After(1.6, function()
        if b._kaGen == gen then b:SetLabel(back) end
    end)
end

KAO.ANNOUNCE_WORDS = {
    sent = "Sent to your group",
    solo = "Not in a group",
    locked = "Chat is locked in a keystone",
}

-- Drag boxes: a managed macro onto the cursor, made first when missing.

KAO.DRAGS = {
    { slot = "kick", label = "Focus + Kick",
      tip = "Kicks your focus; the first press sets it. Drag it onto an action bar, or click it and then a bar slot." },
    { slot = "focus", label = "Set Focus",
      tip = "Sets your target as your focus and marks it. Drag it onto an action bar, or click it and then a bar slot." },
    { slot = "autotab", label = "Tab Kick",
      tip = "Kicks the nearest casting enemy, then goes back to your target. Drag it onto an action bar." },
}

local DRAG_WORDS = {
    full = "No free macro slots",
    combat = "Not in combat",
}

local function DragIcon(slot)
    if slot == "focus" then return KA.FOCUS_ICON end
    local id = KA.LiveInterruptID()
    local S = C_Spell
    return (id and S and S.GetSpellTexture and S.GetSpellTexture(id)) or 134400
end

function KAO.MakeDragBox(parent, d)
    local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
    box:SetSize(36, 36)
    AT.Skin(box, COL.well, COL.arcDeep)
    box:RegisterForDrag("LeftButton")
    box:RegisterForClicks("LeftButtonUp")
    local ic = box:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 2, -2)
    ic:SetPoint("BOTTOMRIGHT", -2, 2)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.icon = ic
    local lbl = box:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(AT.FONT, 10, "")
    lbl:SetPoint("TOP", box, "BOTTOM", 0, -4)
    lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    lbl:SetText(Tr(d.label))
    box.label = lbl
    box._kaSlot = d.slot
    local function pick()
        AT.CloseDropdown()
        local st = KA.PickupSlot(d.slot)
        local words = DRAG_WORDS[st]
        if words then
            lbl:SetText(Tr(words))
            local gen = (box._kaGen or 0) + 1
            box._kaGen = gen
            C_Timer.After(1.6, function()
                if box._kaGen == gen then lbl:SetText(Tr(d.label)) end
            end)
        end
    end
    box:SetScript("OnDragStart", pick)
    box:SetScript("OnClick", pick)
    box:SetScript("OnEnter", function() box:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    box:SetScript("OnLeave", function() box:SetBackdropBorderColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 1) end)
    AT.Tooltip(box, d.label, d.tip)
    return box
end

function KAO.RefreshDragBox(box)
    box.icon:SetTexture(DragIcon(box._kaSlot))
end

-- The marker picker window

local picker
local PICK_W, PICK_H, CELL, GAP = 300, 380, 36, 12
local PICK_KEY = KA.KEY .. ":picker"

local function PickerCombat()
    if picker then picker:Hide() end
end

local function MakeSel(parent)
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s:SetPoint("TOPLEFT", -2, 2)
    s:SetPoint("BOTTOMRIGHT", 2, -2)
    s:SetBackdrop({ edgeFile = AT.WHITE, edgeSize = 2 })
    s:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s:Hide()
    return s
end

function KAO.RefreshPicker()
    local w = picker
    if not w then return end
    local cur = KA.Get("marker")
    for i = 1, 8 do w.markers[i].sel:SetShown(cur == i) end
    local none = w.none
    local edge = (cur == 0) and COL.arc or COL.steel
    none:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    for _, box in ipairs(w.drags) do KAO.RefreshDragBox(box) end
end

local function PickMarker(i)
    KA.SetMarker(i)
    if picker then FlashLabel(picker.announce, KAO.ANNOUNCE_WORDS[KA.Announce()], "Tell your group") end
end

local function BuildPicker()
    if picker then return picker end
    local w = AT.CreateWindow(nil, { title = "Kick Assist", w = PICK_W, h = PICK_H,
        minW = PICK_W, minH = PICK_H, resizable = false })
    picker = w
    -- hidden until opened: its screen-size events too
    w:UnregisterAllEvents()
    w:HookScript("OnShow", function(self)
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        Events.On("PLAYER_REGEN_DISABLED", PICK_KEY, PickerCombat)
    end)
    w:HookScript("OnHide", function(self)
        self:UnregisterAllEvents()
        Events.Off("PLAYER_REGEN_DISABLED", PICK_KEY)
    end)
    w:HookScript("OnDragStop", function(self)
        local p, _, rp, x, y = self:GetPoint()
        if p then KA.SetPoint(p, rp, x, y) end
    end)

    local head = w:CreateFontString(nil, "OVERLAY")
    head:SetFont(AT.FONT, 11, "")
    head:SetPoint("TOP", 0, -44)
    head:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    head:SetText(Tr("Pick your kick marker"))

    local gridW = 4 * CELL + 3 * GAP
    local x0 = math.floor((PICK_W - gridW) / 2)
    w.markers = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, w)
        b:SetSize(CELL, CELL)
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        b:SetPoint("TOPLEFT", x0 + col * (CELL + GAP), -64 - row * (CELL + GAP))
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        SetMarkerTexture(icon, i)
        b:SetHighlightTexture(AT.WHITE)
        b:GetHighlightTexture():SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 0.15)
        b.sel = MakeSel(b)
        b:SetScript("OnClick", function() PickMarker(i) end)
        AT.Tooltip(b, function() return KAO.MarkerName(i) end, "Your kick marker. Picking it tells your group.")
        w.markers[i] = b
    end
    local none = AT.MakeSmallButton(w, "No marker", 100)
    none:SetPoint("TOP", 0, -160)
    none:SetScript("OnClick", function() KA.SetMarker(0) end)
    w.none = none

    local function Rule(y)
        local t = w:CreateTexture(nil, "ARTWORK")
        t:SetTexture(AT.WHITE)
        t:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
        t:SetPoint("TOPLEFT", 16, y)
        t:SetPoint("TOPRIGHT", -16, y)
        t:SetHeight(AT.Hairline(w))
    end
    Rule(-194)
    local announce = AT.MakeSmallButton(w, "Tell your group", 170)
    announce:SetPoint("TOP", 0, -206)
    announce:SetScript("OnClick", function()
        FlashLabel(announce, KAO.ANNOUNCE_WORDS[KA.Announce()], "Tell your group")
    end)
    w.announce = announce
    Rule(-240)

    local sub = w:CreateFontString(nil, "OVERLAY")
    sub:SetFont(AT.FONT, 10, "")
    sub:SetPoint("TOP", 0, -252)
    sub:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    sub:SetText(Tr("Put a macro on your bars"))
    w.drags = {}
    for i, d in ipairs(KAO.DRAGS) do
        local box = KAO.MakeDragBox(w, d)
        box:SetPoint("TOP", (i - 2) * 84, -270)
        w.drags[i] = box
    end

    local settings = AT.MakeQuietButton(w, "Settings", 92)
    settings:SetPoint("BOTTOMRIGHT", -12, 12)
    settings:SetScript("OnClick", function()
        local O = NS.Options
        if not O then return end
        w:Hide()
        if O.Open then O.Open() end
        if O.Select then O.Select("modules", "kickAssist") end
    end)
    return w
end

-- Opens the picker; never in combat, as the options window.
function KA.OpenPicker()
    if not KA.active or InCombatLockdown() then return false end
    local w = BuildPicker()
    local p = KA.GetPoint()
    if p then
        w:ClearAllPoints()
        w:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    end
    KAO.RefreshPicker()
    w:Show()
    w:Raise()
    return true
end

function KA.ClosePicker()
    if picker and picker:IsShown() then picker:Hide() end
end

function KAO.Picker() return picker end

-- The module's page

local MOD = NS.Options and NS.Options.Modules
if not MOD then return end

KAO.TABS = { "Your Marker", "Ready Check", "Kick Macros", "Interrupt Alert" }
KAO.tab = KAO.TABS[1]
local page

KA.onChange = function()
    if picker and picker:IsShown() then KAO.RefreshPicker() end
    if page and page:IsVisible() then AT.LayoutPage(page) end
end

-- The game's spec at index i: id, name, icon, or nil.
local function SpecAt(i)
    local SI = C_SpecializationInfo
    local n = GetNumSpecializations and GetNumSpecializations()
    if type(n) ~= "number" or i > n or not (SI and SI.GetSpecializationInfo) then return nil end
    local id, name, _, icon = SI.GetSpecializationInfo(i)
    if type(id) ~= "number" or type(name) ~= "string" then return nil end
    return id, name, icon
end

-- Several buttons on one line at the right edge, kept so each can flash its words.
local function ActionRow(pg, list, vis)
    local row = AT.AddRow(pg, 28, vis)
    local made = {}
    for i, s in ipairs(list) do
        local b = (s.quiet and AT.MakeQuietButton or AT.MakeSmallButton)(row, s.label, s.w or 150)
        b:SetScript("OnClick", function() AT.CloseDropdown() s.onClick(b) end)
        made[i] = { b = b, vis = s.vis }
    end
    row._sync = function()
        local prev
        for _, e in ipairs(made) do
            if (not e.vis) or e.vis() then
                e.b:ClearAllPoints()
                if prev then e.b:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                else e.b:SetPoint("RIGHT", -12, 0) end
                e.b:Show()
                prev = e.b
            else
                e.b:Hide()
            end
        end
    end
    row._kaButtons = made
    return row
end

local SAVE_WORDS = {
    edited = "Saved", created = "Saved", combat = "Saved: applies after combat",
    full = "No free macro slots",
}

local function Build(pg, m)
    page = pg
    local win = MOD.win
    local avail = m.available
    local function on() return avail() and m.isOn() end
    local function In(tab, extra)
        return function() return on() and KAO.tab == tab and (not extra or extra()) end
    end
    -- every row is found by the search; the jump opens its tab first
    local function Stamp(row, field, t, tab)
        MOD.Stamp(row, m, field, t, avail)
        if tab and row._adMeta then row._adMeta.reveal = function() KAO.tab = tab end end
        return row
    end
    local T1, T2, T3, T4 = KAO.TABS[1], KAO.TABS[2], KAO.TABS[3], KAO.TABS[4]
    local row

    AT.Section(pg, m.name)
    row = AT.RowToggle(pg, "Kick marker, macros and interrupt alert", m.isOn, m.setOn, avail,
        "Your kick marker told to your group and kept in your kick macros, and an alert when your focus casts while your kick is ready.")
    MOD.Stamp(row, m, m.switch, "bool", avail, true)
    AT.RowDesc(pg, "Kick Assist is installed: set it up there with /ka.", 20, function() return not avail() end)
    local tabRow = AT.AddRow(pg, 30, on)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        if not on() then return end
        local h = tabRow._strip:Set(KAO.TABS, KAO.tab, function(name)
            AT.CloseDropdown()
            KAO.tab = name
            AT.LayoutPage(pg)
        end, 11)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want tabRow:SetHeight(want) end
    end
    KAO.tabRow = tabRow

    -- Your Marker
    AT.Section(pg, "Your kick marker")
    row = AT.RowDropdown(pg, win, "Kick marker", function() return KA.Get("marker") end,
        function(v) KA.SetMarker(v) end, KAO.MarkerItems, In(T1))
    AT.Tooltip(row._colCtrl, "Kick marker", "The marker your kick macros put on your focus and your group message names.")
    Stamp(row, "marker", "enum", T1)
    row = AT.RowButton(pg, "Open", function() KA.OpenPicker() end, In(T1), 92, "The marker picker")
    AT.Tooltip(row.button, "The marker picker", "The window a ready check opens: your marker, a group message and macros to drag onto your bars.")
    Stamp(row, "picker", nil, T1)

    AT.Section(pg, "Runs in these specs")
    for i = 1, 4 do
        local function spec() return (SpecAt(i)) end
        row = AT.RowToggle(pg, "",
            function() local id = spec() return id == nil or KA.SpecOn(id) end,
            function(v) KA.SetSpec(spec(), v) end,
            In(T1, function() return spec() ~= nil end))
        local function title() local _, name = SpecAt(i) return name end
        local tip = "Off: no ready check picker, group message or interrupt alert in this spec. Your macros still update."
        AT.Tooltip(row, title, tip)
        AT.Tooltip(row._colCtrl, title, tip)
        local lbl, base = row._colLabel, row._sync
        row._sync = function()
            local _, name, icon = SpecAt(i)
            if name then
                lbl:SetText(icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t  " .. name) or name)
            end
            base()
        end
        row._sync()
        Stamp(row, "specs." .. i, "bool", T1)
    end

    AT.Section(pg, "Shared across characters")
    row = AT.RowToggle(pg, "Same setup on every character", KA.AccountWide, KA.SetAccountWide, In(T1),
        "One setup for all your characters, and your kick macros become account macros. Your kick spell stays per character.")
    Stamp(row, "accountWide", "bool", T1)

    -- Ready Check
    AT.Section(pg, "On a ready check")
    row = AT.RowToggle(pg, "Open the marker picker",
        function() return KA.Get("showOnReadyCheck") == true end,
        function(v) KA.Set("showOnReadyCheck", v and true or false) end, In(T2),
        "In the instances below, out of combat.")
    Stamp(row, "showOnReadyCheck", "bool", T2)
    row = AT.RowToggle(pg, "Only when someone calls your marker",
        function() return KA.Get("smartOpen") == true end,
        function(v) KA.Set("smartOpen", v and true or false) end,
        In(T2, function() return KA.Get("showOnReadyCheck") == true end),
        "Waits a few seconds and opens the picker only if another player posts your marker in group chat.")
    Stamp(row, "smartOpen", "bool", T2)
    row = AT.RowToggle(pg, "Tell your group your marker",
        function() return KA.Get("announceOnReadyCheck") == true end,
        function(v) KA.Set("announceOnReadyCheck", v and true or false) end, In(T2),
        "Posts your message to group chat. Skipped once a keystone starts, when the game locks addon chat.")
    Stamp(row, "announceOnReadyCheck", "bool", T2)

    AT.Section(pg, "In these instances")
    for _, key in ipairs(KA.CONTEXT_ORDER) do
        row = AT.RowToggle(pg, KA.CONTEXT_LABELS[key],
            function() return KA.ContextOn(key) end,
            function(v) KA.SetContext(key, v) end, In(T2))
        Stamp(row, "contexts." .. key, "bool", T2)
    end

    AT.Section(pg, "Your group message")
    row = AT.RowInput(pg, "Group message", function() return KA.Get("message") end,
        function(v)
            v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
            KA.Set("message", (v ~= "") and v or nil)
        end, In(T2), "%MARKER% becomes your marker's icon in chat.")
    Stamp(row, "message", "text", T2)
    local sendBtn
    row = AT.RowButton(pg, "Tell your group", function()
        FlashLabel(sendBtn, KAO.ANNOUNCE_WORDS[KA.Announce()], "Tell your group")
    end, In(T2), 170, "Send it now")
    sendBtn = row.button
    Stamp(row, "announceNow", nil, T2)

    -- Kick Macros
    AT.Section(pg, "Your kick spell")
    row = AT.RowInput(pg, "Kick spell",
        function() local c = KA.Char() return (c and c.customKick) or "" end,
        function(v) KA.SetCustomKick(v) end, In(T3),
        "Blank uses your spec's kick. Type a spell name or ID to use another, like a pet's. Kept per character.",
        function()
            local n = KA.DefaultInterruptName()
            if n then return n, true end
            return "No kick in this spec"
        end)
    Stamp(row, "customKick", "text", T3)
    row = AT.RowButton(pg, "Use my class default", function()
        KA.SetCustomKick("")
        AT.LayoutPage(pg)
    end, In(T3, function() return KA.CustomKick() ~= nil end), 150, nil, true)
    Stamp(row, "customKickReset", nil, T3)

    -- A typed name and the text wait for Save, so nothing writes a macro mid-edit.
    local editSlot, pendingName, draft = "kick", nil, nil
    local body
    local function Reset()
        pendingName, draft = nil, nil
        if body then body:ClearFocus() end
    end
    AT.Section(pg, "Edit a macro")
    row = AT.RowDropdown(pg, win, "Macro to edit", function() return editSlot end,
        function(v) if KA.SLOT_CFG[v] then editSlot = v Reset() end end,
        function()
            local out = {}
            for _, k in ipairs(KA.SLOT_ORDER) do out[#out + 1] = { value = k, text = KA.SLOT_CFG[k].label } end
            return out
        end, In(T3), function() AT.LayoutPage(pg) end)
    Stamp(row, "macroSlot", "enum", T3)
    row = AT.RowInput(pg, "Macro name", function() return pendingName or KA.SlotName(editSlot) end,
        function(v)
            local nm = tostring(v or ""):match("^%s*(.-)%s*$") or ""
            pendingName = (nm ~= "" and nm ~= KA.SlotName(editSlot)) and nm or nil
        end, In(T3), "The macro this keeps updated. A new name takes over when you save.")
    Stamp(row, "macroName", "text", T3)
    local function CurrentText()
        if draft then return draft end
        return KA.SlotBody(editSlot)
    end
    row = AT.RowDropdown(pg, win, "Start from a template",
        function()
            local cur = CurrentText()
            for i, t in ipairs(KA.TEMPLATES[editSlot] or {}) do
                if t.body == cur then return i end
            end
            return Tr("Your own text")
        end,
        function(v)
            local t = (KA.TEMPLATES[editSlot] or {})[v]
            if not t then return end
            draft = t.body
            if body then body:SetText(t.body) body:SetCursorPosition(0) end
        end,
        function()
            local out = {}
            for i, t in ipairs(KA.TEMPLATES[editSlot] or {}) do out[#out + 1] = { value = i, text = t.name } end
            return out
        end, In(T3))
    AT.Tooltip(row._colCtrl, "Start from a template", "Puts a ready-made macro in the box below. Save to use it.")
    Stamp(row, "macroTemplate", "enum", T3)
    row = AT.RowDropdown(pg, win, "Copy from a macro",
        function() return Tr("Pick a macro") end,
        function(v)
            local idx = tonumber(v)
            if not idx then return end
            local _, _, text = GetMacroInfo(idx)
            if type(text) ~= "string" then return end
            draft = text
            if body then body:SetText(text) body:SetCursorPosition(0) end
        end,
        function()
            -- read live: the player's macros change outside this window
            local out = {}
            local numAccount, numChar = GetNumMacros()
            for i = 1, (numAccount or 0) do
                local n = GetMacroInfo(i)
                if type(n) == "string" and n ~= "" then out[#out + 1] = { value = i, text = n, raw = true } end
            end
            for i = 1, (numChar or 0) do
                local idx = KA.ACCT_MACRO_CAP + i
                local n = GetMacroInfo(idx)
                if type(n) == "string" and n ~= "" then out[#out + 1] = { value = idx, text = n, raw = true } end
            end
            if #out == 0 then out[1] = { value = "", text = "You have no macros yet" } end
            return out
        end, In(T3))
    AT.Tooltip(row._colCtrl, "Copy from a macro", "Copies one of your macros into the box below as a start. It never takes that macro over.")
    Stamp(row, "macroCopy", "enum", T3)

    -- The macro text: a tall row, the row engine has no multi-line field.
    do
        local tall = AT.AddRow(pg, 118, In(T3))
        local lbl = tall:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(AT.FONT, 11, "")
        lbl:SetPoint("TOPLEFT", 10, -1)
        lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        lbl:SetText(Tr("Macro text: {interrupt} and {marker} fill in for you"))
        local well = CreateFrame("Frame", nil, tall, "BackdropTemplate")
        well:SetPoint("TOPLEFT", 10, -16)
        well:SetPoint("BOTTOMRIGHT", -12, 4)
        AT.Skin(well, COL.well)
        local sf = CreateFrame("ScrollFrame", nil, well)
        sf:SetPoint("TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", -4, 4)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(255)
        eb:SetAutoFocus(false)
        eb:SetFont(AT.FONT, 12, "")
        eb:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        -- a 0 width draws nothing; the scroll frame's size sets the real one
        eb:SetWidth(1)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then draft = self:GetText() end
        end)
        eb:SetScript("OnEditFocusGained", function() well:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
        eb:SetScript("OnEditFocusLost", function() well:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
        sf:SetScrollChild(eb)
        sf:SetScript("OnSizeChanged", function(_, w) if w and w > 1 then eb:SetWidth(w) end end)
        well:EnableMouse(true)
        well:SetScript("OnMouseDown", function() eb:SetFocus() end)
        body = eb
        tall._sync = function()
            if not eb:HasFocus() then
                eb:SetText(CurrentText())
                eb:SetCursorPosition(0)
                sf:SetVerticalScroll(0)
            end
            local w = sf:GetWidth() or 0
            if w > 1 then eb:SetWidth(w) end
        end
        tall._colLabel = lbl
        Stamp(tall, "macroBody", "text", T3)
        tall._colLabel = nil
        KAO.body = eb
    end
    row = ActionRow(pg, {
        { label = "Save the macro", onClick = function(b)
            local st = KA.ApplySlot(editSlot, pendingName or KA.SlotName(editSlot), CurrentText())
            Reset()
            FlashLabel(b, SAVE_WORDS[st] or "Saved", "Save the macro")
            AT.LayoutPage(pg)
        end },
        { label = "Add the marker line", quiet = true, w = 160,
          vis = function() return editSlot == "kick" or editSlot == "focus" end,
          onClick = function()
            draft = KA.ManageMarkerInBody(CurrentText())
            if body then body:SetText(draft) body:SetCursorPosition(0) end
          end },
    }, In(T3))
    row._colLabel = row._kaButtons[1].b.fs
    Stamp(row, "macroSave", nil, T3)
    row._colLabel = nil
    KAO.actions = row

    AT.Section(pg, "Put a macro on your bars")
    do
        local drag = AT.AddRow(pg, 64, In(T3))
        drag._kaBoxes = {}
        for i, d in ipairs(KAO.DRAGS) do
            local box = KAO.MakeDragBox(drag, d)
            -- each box centred in a 96 wide cell from the label margin
            box:SetPoint("TOPLEFT", 10 + (i - 1) * 96 + 30, -4)
            drag._kaBoxes[i] = box
        end
        drag._sync = function()
            for _, box in ipairs(drag._kaBoxes) do KAO.RefreshDragBox(box) end
        end
        drag._colLabel = drag._kaBoxes[1].label
        Stamp(drag, "macroDrag", nil, T3)
        drag._colLabel = nil
        KAO.dragRow = drag
    end

    -- Interrupt Alert
    local function alertOn() return KA.Get("interruptAlert") == true end
    local function speech() return KA.Get("interruptAlertTTS") == true end
    AT.Section(pg, "Interrupt alert")
    row = AT.RowToggle(pg, "Alert when your focus casts and your kick is ready",
        function() return alertOn() end,
        function(v) KA.Set("interruptAlert", v and true or false) KA.SyncAlert() end, In(T4),
        "Plays the moment your focus starts casting while your kick is off cooldown, in combat too. Any cast counts.")
    Stamp(row, "interruptAlert", "bool", T4)
    row = AT.RowDropdown(pg, win, "Alert with", function() return speech() and "speech" or "sound" end,
        function(v) KA.Set("interruptAlertTTS", v == "speech") end,
        function()
            return { { value = "sound", text = "A sound" }, { value = "speech", text = "Spoken words" } }
        end, In(T4, alertOn), function() AT.LayoutPage(pg) end)
    Stamp(row, "interruptAlertTTS", "enum", T4)
    local function soundOn() return alertOn() and not speech() end
    local function speechOn() return alertOn() and speech() end
    row = AT.RowDropdown(pg, win, "Alert sound",
        function() return KA.Get("interruptAlertSound") end,
        function(v) KA.Set("interruptAlertSound", type(v) == "string" and v or "") end,
        function()
            local items = NS.Sounds and NS.Sounds.Items() or { { value = "", text = "None" } }
            local O = NS.Options
            if O and O.KeepSound then items = O.KeepSound(items, KA.Get("interruptAlertSound")) end
            return items
        end, In(T4, soundOn))
    local play = AT.MakeSmallButton(row, "Play", 52)
    play:SetPoint("LEFT", row._colCtrl, "RIGHT", 6, 0)
    play:SetScript("OnClick", function()
        AT.CloseDropdown()
        if NS.Sounds then NS.Sounds.Preview(KA.Get("interruptAlertSound"), KA.Get("interruptAlertChannel")) end
    end)
    AT.Tooltip(play, "Play", "Hear the alert sound once, on its channel.")
    Stamp(row, "interruptAlertSound", "sound", T4)
    row = AT.RowDropdown(pg, win, "Sound channel",
        function() return KA.Get("interruptAlertChannel") end,
        function(v) KA.Set("interruptAlertChannel", v) end,
        function()
            local S = NS.Sounds
            local out = {}
            for _, c in ipairs((S and S.CHANNELS) or { "Master" }) do
                out[#out + 1] = { value = c, text = (S and S.CHANNEL_LABELS and S.CHANNEL_LABELS[c]) or c }
            end
            return out
        end, In(T4, soundOn))
    Stamp(row, "interruptAlertChannel", "enum", T4)
    row = AT.RowInput(pg, "Words to speak", function() return KA.Get("interruptAlertText") end,
        function(v)
            v = tostring(v or ""):match("^%s*(.-)%s*$") or ""
            KA.Set("interruptAlertText", (v ~= "") and v or nil)
        end, In(T4, speechOn), "Spoken with the voice picked for Arc Auras' speech.")
    local say = AT.MakeSmallButton(row, "Play", 52)
    say:SetPoint("LEFT", row._colCtrl, "RIGHT", 6, 0)
    say:SetScript("OnClick", function() AT.CloseDropdown() KA.Speak() end)
    AT.Tooltip(say, "Play", "Hear the words once.")
    Stamp(row, "interruptAlertText", "text", T4)
end

MOD.Register({
    key = "kickAssist",
    switch = "kick.on",
    name = "Kick Assist",
    desc = "Pick your kick marker, keep your kick macros in sync, get an alert when your focus casts.",
    unavailable = "Kick Assist is installed: set it up there with /ka.",
    -- a stop sign: a frame struck through
    glyph = {
        { 2, 2, 16, 2, "arc" }, { 2, 16, 16, 2, "arc" }, { 2, 2, 2, 16, "arc" }, { 16, 2, 2, 16, "arc" },
        { 1, 9, 18, 2, "ink", -45 },
    },
    available = function() return not KA.StandaloneLoaded() end,
    isOn = function() return KA.IsOn() end,
    setOn = function(v) KA.SetOn(v) end,
    build = Build,
})
