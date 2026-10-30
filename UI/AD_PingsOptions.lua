-- AD_PingsOptions: the Arc Pings module's card and settings page. The runtime
-- is Modules\AD_Pings.lua (NS.Pings), read at call time.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local COL = AT.COL
local Tr = AT.Tr
local MOD = Options.Modules

-- the page's own state: the open tab, the piece being edited, a refused add
local UI = { tab = "Ping Keys", piece = "sender", msg = nil }
local RED, YELLOW = { 1, 0.33, 0.33 }, { 1, 0.82, 0 }
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local CELL, POOL, MIN_ROWS = 32, 60, 3

local function Pg() return NS.Pings end
local function PK() return NS.Pings and NS.Pings.PK end
local function Get(k) local p = Pg() return p and p.Get(k) end
local function Set(k, v) local p = Pg() if p then p.Set(k, v) end end
local function Avail() local p = Pg() return p ~= nil and p.Available() end
local function IsOn() return Avail() and Pg().IsOn() end

local function Why()
    local p = Pg()
    if p and p.HasAPI() and p.Standalone() then
        return Tr("Arc Pings is installed: set it up there (/arcpings).")
    end
    return Tr("Needs the game's ping system, which this game version does not have.")
end

-- A key as the game names it (Shift-F, Mouse Button 4).
local function KeyText(k)
    if not k or k == "" then return Tr("Not set") end
    return (GetBindingText and GetBindingText(k)) or k
end

local function Chord(key)
    if CreateKeyChordStringUsingMetaKeyState then return CreateKeyChordStringUsingMetaKeyState(key) end
    local s = ""
    if IsAltKeyDown and IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

-- The tabs that have something to set: Spells while ping keys are on, the
-- window's tabs while the feed is.
local function Tabs()
    local t = { "Ping Keys" }
    if Get("pkEnabled") then t[#t + 1] = "Spells" end
    t[#t + 1] = "Feed"
    if Get("enabled") then
        t[#t + 1] = "Window"; t[#t + 1] = "Look"; t[#t + 1] = "Layout"; t[#t + 1] = "Entries"
    end
    return t
end
local function CurTab()
    for _, n in ipairs(Tabs()) do
        if n == UI.tab then return n end
    end
    UI.tab = "Ping Keys"
    return UI.tab
end

-- Status lines

local function StatusText()
    local p, pk = Pg(), PK()
    if not (p and pk) then return "" end
    local list = pk.List()
    local total, resolved = #list, pk.ResolvedCount()
    local key = Get("pkKey")
    if not p.CanBind() then
        return Tr("Ping keys need the game's secure key bindings, which this game version does not have."), RED
    end
    if not Get("pkEnabled") then return Tr("Ping keys are off."), COL.dim end
    if InCombatLockdown() then return Tr("In combat: ping key changes apply when combat ends."), YELLOW end
    if total > p.PK_MAX then
        return Tr("%d spells saved, but only the first %d can ping."):format(total, p.PK_MAX), RED
    end
    if Get("pkOnlySelected") ~= true then
        if not key or key == "" then return Tr("Set a ping key above."), RED end
        if total > 0 then
            return Tr("Hold %s over any bound spell to ping it. %d of %d picked spells ping their own way.")
                :format(KeyText(key), resolved, total), MOD.ON
        end
        return Tr("Hold %s over any bound spell to ping it."):format(KeyText(key)), MOD.ON
    end
    if total == 0 then return Tr("No spells picked yet: pick them on the Spells tab."), COL.dim end
    if resolved == 0 then return Tr("None of the picked spells can ping: open one on the Spells tab to see why."), RED end
    if not pk.AutoOn() then
        return Tr("%d of %d picked spells ping. Auto-Ping is off."):format(resolved, total), MOD.ON
    end
    return Tr("%d of %d picked spells ping."):format(resolved, total), MOD.ON
end

local function InfoText()
    if UI.msg then return UI.msg, RED end
    local pk = PK()
    local sel = pk and pk.Selected()
    if not sel then return "" end
    local t = pk.Tracked(sel.id)
    if not t then return Tr("Not pinging. Tick Ping this to add it."), COL.dim end
    if not pk.EntryOn(t) then return Tr("Added, but switched off."), COL.dim end
    local mode = pk.EntryMode(t)
    local barKey = sel.key
    local text, col
    if mode == "own" then
        if t.ownKey and t.ownKey ~= "" then
            text, col = Tr("Press %s to ping it. Nothing is cast."):format(KeyText(t.ownKey)), COL.dim
        else
            text, col = Tr("This way of pinging needs a key: set one below."), RED
        end
    elseif not barKey then
        text, col = Tr("It has no key on your bars: bind one, or give it its own key."), RED
    elseif mode == "always" then
        text, col = Tr("Casts and pings on %s."):format(KeyText(barKey)), COL.dim
    else
        local pkk = pk.PingKeyFor(t)
        if not pkk then
            text, col = Tr("No ping key set."), RED
        else
            text, col = Tr("Hold %s, then press %s."):format(KeyText(pkk), KeyText(barKey)), COL.dim
        end
    end
    if not pk.MatchesBar(t) then
        text, col = Tr("Paused: that bar slot holds something else right now. Put the spell back and it pings again."), YELLOW
    end
    return text, col
end

-- Row helpers

-- A line of words that wraps and sizes its row; fn() -> text, colour.
local function TextRow(pg, vis, fn)
    local row = AT.AddRow(pg, 22, vis)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    row._sync = function()
        local text, col = fn()
        col = col or COL.dim
        fs:SetText(text or "")
        fs:SetTextColor(col[1], col[2], col[3])
        local w = pg:GetWidth() or 0
        if w < 60 then pg._sizeUnresolved = true return end
        fs:SetWidth(w - 36)
        local want = math.max(22, math.floor((fs:GetStringHeight() or 12) + 10))
        if row._h ~= want then row._h = want; row:SetHeight(want) end
    end
    row._fs = fs
    return row
end

-- Click, then press a key (with Shift, Ctrl or Alt) or mouse button 3 to 5;
-- right-click clears it. Out of combat only, as the wheel's key is.
local function KeyRow(pg, label, get, set, vis, tip)
    local row = AT.AddRow(pg, 26, vis)
    row._colLabel = AT.RowLabel(row, label)
    local kb = AT.MakeSmallButton(row, "Not set", 150)
    kb:RegisterForClicks("AnyUp")
    row._colCtrl = kb
    local capturing = false
    local function Stop()
        capturing = false
        kb:SetScript("OnKeyDown", nil)
        kb:EnableKeyboard(false)
        kb:SetLabel(KeyText(get()))
    end
    local function Take(k)
        set(k)
        Stop()
        AT.LayoutPage(pg)
    end
    kb:SetScript("OnClick", function(_, button)
        AT.CloseDropdown()
        if capturing then
            local mk = MOUSE_KEYS[button]
            if mk then Take(Chord(mk)) elseif button == "RightButton" then Stop() end
            return
        end
        if button == "RightButton" then
            Take(nil)
            return
        end
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            kb:SetLabel("Leave combat first")
            return
        end
        capturing = true
        kb:SetLabel("Press a key...")
        kb:EnableKeyboard(true)
        kb:SetPropagateKeyboardInput(false)
        kb:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then Stop() return end
            if MODIFIERS[key] then return end
            Take(Chord(key))
        end)
    end)
    kb:HookScript("OnHide", function() if capturing then Stop() end end)
    row._sync = function() if not capturing then kb:SetLabel(KeyText(get())) end end
    if tip then
        AT.Tooltip(row, label, tip)
        AT.Tooltip(kb, label, tip)
    end
    return row, kb
end

-- The page

local function Build(pg, m)
    local win = MOD.win
    local function InTab(name, extra)
        return function()
            return IsOn() and CurTab() == name and ((not extra) or extra() == true)
        end
    end
    -- the search finds a row on any tab: its jump opens that tab first
    local function Stamp(row, field, t, tab, base)
        MOD.Stamp(row, m, field, t, base)
        row._adMeta.reveal = function() UI.tab = tab end
        return row
    end
    local function Bool(tab, label, key, desc, extra)
        local row = AT.RowToggle(pg, label, function() return Get(key) == true end,
            function(v) Set(key, v and true or false) end, InTab(tab, extra), desc)
        return Stamp(row, key, "bool", tab, extra)
    end
    local function Slider(tab, label, key, lo, hi, step, pct, extra, desc)
        local row = AT.RowSlider(pg, label, function() return Get(key) end,
            function(v) Set(key, v) end, lo, hi, step, pct, InTab(tab, extra))
        if desc then AT.Tooltip(row, label, desc) end
        return Stamp(row, key, "num", tab, extra)
    end
    local function Drop(tab, label, key, items, extra, desc, onSelect)
        local row = AT.RowDropdown(pg, win, label, function() return Get(key) end,
            function(v) Set(key, v) end, function() return items end, InTab(tab, extra), onSelect)
        if desc then AT.Tooltip(row, label, desc) end
        return Stamp(row, key, "enum", tab, extra)
    end
    local function Color(tab, label, key, extra)
        local row = AT.RowColor(pg, label, function()
                local c = Get(key) or { 1, 1, 1 }
                return { c[1], c[2], c[3] }
            end,
            function(c) Set(key, { c[1], c[2], c[3] }) end, InTab(tab, extra))
        return Stamp(row, key, "color", tab, extra)
    end
    local pkOn = function() return Get("pkEnabled") == true end

    -- the module switch, why it may not be there, and the tabs
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Use Arc Pings", m.isOn, m.setOn, Avail,
        "Ping your cooldowns with a key, see your group's pings in a feed window, and hear an alert. Each part has its own switch.")
    MOD.Stamp(row, m, m.switch, "bool", Avail, true)
    AT.RowDesc(pg, "Needs the game's ping system, which this game version does not have.", 20,
        function() local p = Pg() return not (p and p.HasAPI()) end)
    AT.RowDesc(pg, "Arc Pings is installed: set it up there (/arcpings).", 20,
        function() local p = Pg() return p ~= nil and p.HasAPI() and p.Standalone() end)
    local blizzOff = function() return IsOn() and not Pg().BlizzOK() end
    AT.RowDesc(pg, "The game's Enable Pings or Show Pings in Chat setting is off, so no pings reach the feed.", 20, blizzOff)
    AT.RowButton(pg, "Turn on the game's ping settings", function()
        Pg().FixBlizz()
        AT.LayoutPage(pg)
    end, blizzOff, 220)
    local tabRow = AT.AddRow(pg, 30, IsOn)
    tabRow._strip = AT.TabRow(tabRow)
    tabRow._strip._openFill = COL.panel
    tabRow._strip:SetPoint("TOPLEFT", 8, 0)
    tabRow._strip:SetPoint("BOTTOMRIGHT", -8, 2)
    tabRow._sync = function()
        if not IsOn() then return end
        local h = tabRow._strip:Set(Tabs(), CurTab(), function(name)
            UI.tab = name
            pg._scrollOff = 0
            AT.LayoutPage(pg)
        end, 11)
        local want = (h or 24) + 6
        if tabRow._h ~= want then tabRow._h = want; tabRow:SetHeight(want) end
    end
    pg._adTabRow = tabRow

    -- PING KEYS
    local T = "Ping Keys"
    AT.Section(pg, "Ping Key")
    Bool(T, "Ping keys", "pkEnabled",
        "Hold the ping key and press a spell's own key to ping it instead of casting it. Nothing is rebound while this is off.")
    row = KeyRow(pg, "Ping key", function() return Get("pkKey") end, function(k) Set("pkKey", k or "") end,
        InTab(T, pkOn), "Hold this and press a spell's key to ping the spell. Click, then press a key; right-click clears it.")
    Stamp(row, "pkKey", "key", T, pkOn)
    Bool(T, "Only the spells I pick", "pkOnlySelected",
        "The ping key works on every spell you have bound. Turn this on to keep it to the spells you pick on the Spells tab.", pkOn)
    AT.Section(pg, "Auto-Ping")
    row = AT.RowToggle(pg, "Ping without holding", function() return PK().AutoOn() end,
        function(v) PK().SetAutoOn(v) end, InTab(T, pkOn),
        "Switches every spell set to ping each time you press its key. Spells on a key of their own ignore it.")
    Stamp(row, "pkAutoOn", "bool", T, pkOn)
    row = KeyRow(pg, "Toggle key", function() return Get("pkToggleKey") end, function(k) Set("pkToggleKey", k or "") end,
        InTab(T, pkOn), "Flips Ping without holding, in combat too. Click, then press a key; right-click clears it.")
    Stamp(row, "pkToggleKey", "key", T, pkOn)
    AT.Section(pg, "Status")
    pg._adStatus = TextRow(pg, InTab(T), StatusText)

    -- SPELLS
    T = "Spells"
    local spellsVis = InTab(T, pkOn)
    AT.Section(pg, "Your Spells")
    local bar = AT.AddRow(pg, 28, spellsVis)
    local search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
    search:SetSize(150, 20)
    search:SetPoint("LEFT", 10, 0)
    AT.Skin(search, COL.well)
    search:SetFont(AT.FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(AT.FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText(Tr("Search your bars"))
    local VIEWS = { { value = "all", text = "All" }, { value = "on", text = "Pinging" }, { value = "off", text = "Not pinging" } }
    local view = AT.MakeDropdown(win, bar, 130, function() return VIEWS end,
        function() return PK().GetCatView() end,
        function(v) PK().SetCatView(v); AT.LayoutPage(pg) end)
    view:SetPoint("LEFT", search, "RIGHT", 10, 0)
    AT.Tooltip(view, "Show", "All the spells on your bars, only those that ping, or only those that do not.")
    local rescan = AT.MakeSmallButton(bar, "Rescan bars", 110)
    rescan:SetPoint("LEFT", view, "RIGHT", 10, 0)
    rescan:SetScript("OnClick", function()
        AT.CloseDropdown()
        PK().CatalogDirty()
        AT.LayoutPage(pg)
    end)
    AT.Tooltip(rescan, "Rescan bars", "Reads your action bars again after you move or rebind a spell.")
    search:SetScript("OnTextChanged", function(self)
        local s = self:GetText() or ""
        hint:SetShown(s == "")
        local pk = PK()
        if pk and pk.CatSearch() ~= s then
            pk.SetCatSearch(s)
            AT.LayoutPage(pg)
        end
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    bar._sync = function() view.Refresh() end
    pg._adSearch = search

    local count = TextRow(pg, spellsVis, function()
        local pk = PK()
        local all, shown = pk.Catalog(), pk.CatalogFiltered()
        if pk.GetCatView() ~= "all" or pk.CatSearch() ~= "" then
            return Tr("%d of %d shown."):format(math.min(#shown, POOL), #all)
        end
        local keyed = 0
        for _, e in ipairs(all) do if e.key then keyed = keyed + 1 end end
        return Tr("%d on your bars, %d with a key. %d of %d ping slots used."):format(#all, keyed, #pk.List(), Pg().PK_MAX)
    end)
    pg._adCount = count

    local grid = AT.AddRow(pg, MIN_ROWS * CELL + 8, spellsVis)
    grid._cells = {}
    for i = 1, POOL do
        local b = CreateFrame("Button", nil, grid, "BackdropTemplate")
        b:SetSize(28, 28)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- a dot: green while it pings, grey while added but switched off
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetSize(6, 6)
        b.dot:SetPoint("TOPRIGHT", -2, -2)
        b.dot:SetTexture(AT.WHITE)
        b:SetScript("OnClick", function(self)
            local e = self._entry
            if not e then return end
            AT.CloseDropdown()
            UI.msg = nil
            PK().Select(e.id)
            AT.LayoutPage(pg)
        end)
        b:SetScript("OnEnter", function(self)
            local e = self._entry
            if not e then return end
            self:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(e.name or "?", 1, 1, 1)
            if e.key then
                GameTooltip:AddLine(Tr("Key: %s"):format(KeyText(e.key)), 0.75, 0.82, 0.92)
            else
                GameTooltip:AddLine(Tr("No key: a ping key cannot reach it."), RED[1], RED[2], RED[3])
            end
            local t = PK().Tracked(e.id)
            if t then
                if PK().EntryOn(t) then
                    GameTooltip:AddLine(Tr("Pinging"), MOD.ON[1], MOD.ON[2], MOD.ON[3])
                else
                    GameTooltip:AddLine(Tr("Added, switched off"), COL.dim[1], COL.dim[2], COL.dim[3])
                end
            end
            GameTooltip:AddLine(Tr("Click to choose how it pings."), COL.arc[1], COL.arc[2], COL.arc[3])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            local sel = PK().SelectedID()
            local c = (self._entry and sel == self._entry.id) and COL.arc or COL.line
            self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            GameTooltip:Hide()
        end)
        b:Hide()
        grid._cells[i] = b
    end
    grid._sync = function()
        if not spellsVis() then return end
        local pk = PK()
        local list = pk.CatalogFiltered()
        local rowW = grid:GetWidth() or 0
        if rowW < 50 then rowW = (pg:GetWidth() or 0) - 24 end
        if rowW < 50 then pg._sizeUnresolved = true end
        local cols = math.max(6, math.floor((rowW - 20 + 4) / CELL))
        local sel = pk.SelectedID()
        for i, b in ipairs(grid._cells) do
            local e = list[i]
            b._entry = e
            if e then
                local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", grid, "TOPLEFT", 10 + col * CELL, -4 - r * CELL)
                b.tex:SetTexture(e.icon or 134400)
                -- no key: nothing a ping key can reach, so faded
                b.tex:SetDesaturated(e.key == nil)
                b.tex:SetAlpha(e.key and 1 or 0.45)
                local t = pk.Tracked(e.id)
                local dc = (t and pk.EntryOn(t)) and MOD.ON or COL.faint
                b.dot:SetVertexColor(dc[1], dc[2], dc[3], 1)
                b.dot:SetShown(t ~= nil)
                local bc = (sel == e.id) and COL.arc or COL.line
                b:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
                b:Show()
            else
                b:Hide()
            end
        end
        local used = math.max(MIN_ROWS, math.ceil(math.min(#list, POOL) / cols))
        local want = used * CELL + 8
        if grid._h ~= want then grid._h = want; grid:SetHeight(want) end
    end
    pg._adGrid = grid

    row = AT.RowInput(pg, "Add by spell ID", function() return "" end, function(text)
        text = (text or ""):gsub("%s+", "")
        if text == "" then return end
        local ok, why = PK().AddSpell(text)
        if ok then UI.msg = nil
        elseif why == "full" then UI.msg = Tr("All %d ping slots are used: remove a spell first."):format(Pg().PK_MAX)
        else UI.msg = Tr("That is not a spell ID.") end
        AT.LayoutPage(pg)
    end, spellsVis, "Adds a spell that is not on your bars, by its ID. Give it its own key below to ping it.", "Spell ID")
    Stamp(row, "pkAddSpell", "text", T, pkOn)

    -- the selected spell's editor; its rows need a picked spell
    AT.Section(pg, "Selected Spell")
    local function Sel() return PK().Selected() end
    local function SelT() local s = Sel() return s and PK().Tracked(s.id) end
    local selVis = InTab(T, function() return pkOn() and (Sel() ~= nil or UI.msg ~= nil) end)
    local trackedVis = InTab(T, function() return pkOn() and SelT() ~= nil end)
    local head = AT.AddRow(pg, 30, spellsVis)
    head.empty = head:CreateFontString(nil, "OVERLAY")
    head.empty:SetFont(AT.FONT, 11, "")
    head.empty:SetPoint("LEFT", 10, 0)
    head.empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    head.empty:SetText(Tr("Click a spell above to choose how it pings."))
    head.icon = head:CreateTexture(nil, "ARTWORK")
    head.icon:SetSize(22, 22)
    head.icon:SetPoint("LEFT", 10, 0)
    head.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    head.name = head:CreateFontString(nil, "OVERLAY")
    head.name:SetFont(AT.FONT, 12, "")
    head.name:SetPoint("LEFT", head.icon, "RIGHT", 8, 0)
    head.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    head.del = AT.MakeQuietButton(head, "Remove", 80)
    head.del:SetPoint("RIGHT", -12, 0)
    head.check = AT.MakeCheckbox(head)
    head.check:SetPoint("RIGHT", head.del, "LEFT", -16, 0)
    head.onFS = head:CreateFontString(nil, "OVERLAY")
    head.onFS:SetFont(AT.FONT, 12, "")
    head.onFS:SetPoint("RIGHT", head.check, "LEFT", -8, 0)
    head.onFS:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    head.onFS:SetText(Tr("Ping this"))
    AT.Tooltip(head.check, "Ping this", "Adds the spell to your ping spells, or switches it off and keeps its settings.")
    AT.Tooltip(head.del, "Remove", "Takes the spell off your ping spells, with its settings.")
    head.check:SetScript("OnClick", function()
        AT.CloseDropdown()
        local t = SelT()
        local nv = not (t ~= nil and PK().EntryOn(t))
        local ok, why = PK().SetSelectedEnabled(nv)
        UI.msg = (not ok and why == "full")
            and Tr("All %d ping slots are used: remove a spell first."):format(Pg().PK_MAX) or nil
        PlaySound(nv and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
        AT.LayoutPage(pg)
    end)
    head.check:HookScript("OnEnter", function() head.check:SetHover(true) end)
    head.check:HookScript("OnLeave", function() head.check:SetHover(false) end)
    head.del:SetScript("OnClick", function()
        AT.CloseDropdown()
        UI.msg = nil
        PK().RemoveSelected()
        AT.LayoutPage(pg)
    end)
    head._sync = function()
        local s = spellsVis() and Sel() or nil
        head.empty:SetShown(s == nil)
        for _, f in ipairs({ head.icon, head.name, head.check, head.onFS }) do f:SetShown(s ~= nil) end
        local t = s and PK().Tracked(s.id)
        head.del:SetShown(t ~= nil)
        if s then
            head.icon:SetTexture(s.icon or 134400)
            head.name:SetText(s.name or "?")
            head.check:SetOn(t ~= nil and PK().EntryOn(t))
        end
    end
    pg._adHead = head

    local MODES = {
        { value = "key", text = "I hold the ping key" },
        { value = "always", text = "Every time I press its key" },
        { value = "own", text = "Its own key, ping only" },
    }
    row = AT.RowDropdown(pg, win, "Pings when", function() return PK().EntryMode(SelT()) end,
        function(v) PK().SetField("mode", v) end, function() return MODES end, trackedVis)
    AT.Tooltip(row, "Pings when", "Hold: its key still casts, and holding the ping key pings instead. Every press: casts and pings. Its own key: pings and casts nothing.")
    Stamp(row, "pkMode", "enum", T, pkOn)
    local EVERY = {
        { value = 1, text = "Every press" }, { value = 2, text = "Every 2nd press" },
        { value = 3, text = "Every 3rd press" }, { value = 4, text = "Every 4th press" },
        { value = 5, text = "Every 5th press" },
    }
    local isAlways = InTab(T, function()
        local t = pkOn() and SelT()
        return t ~= nil and t ~= false and PK().EntryMode(t) == "always"
    end)
    row = AT.RowDropdown(pg, win, "Presses per ping", function() local t = SelT() return tonumber(t and t.every) or 1 end,
        function(v) PK().SetField("every", v) end, function() return EVERY end, isAlways)
    AT.Tooltip(row, "Presses per ping", "Keeps a mashed key from flooding the group. It counts presses, not time, and the cast always goes through.")
    Stamp(row, "pkEvery", "enum", T, pkOn)
    local function ModeVis(mode)
        return InTab(T, function()
            local t = pkOn() and SelT()
            return t ~= nil and t ~= false and PK().EntryMode(t) == mode
        end)
    end
    row = KeyRow(pg, "Ping key for this spell", function() local t = SelT() return t and t.pingKey end,
        function(k) PK().SetField("pingKey", k) end, ModeVis("key"),
        "Hold this instead of the main ping key to ping this spell. Not set uses the main ping key. Right-click clears it.")
    Stamp(row, "pkPingKey", "key", T, pkOn)
    row = KeyRow(pg, "Key that pings it", function() local t = SelT() return t and t.ownKey end,
        function(k) PK().SetField("ownKey", k) end, ModeVis("own"),
        "This key pings the spell and casts nothing. Right-click clears it.")
    Stamp(row, "pkOwnKey", "key", T, pkOn)
    pg._adInfo = TextRow(pg, selVis, InfoText)

    -- FEED
    T = "Feed"
    local feedOn = function() return Get("enabled") == true end
    AT.Section(pg, "Feed")
    Bool(T, "Show the ping feed", "enabled", "A window that lists your group's pings as they come in.")
    row = AT.RowButton(pg, "Show a test ping", function() Pg().TestPing() end, InTab(T, feedOn), 150)
    Stamp(row, "pingTest", nil, T, feedOn)
    AT.Section(pg, "Show In")
    for _, s in ipairs({
        { "Open world", "showInWorld", "Anywhere outside an instance." },
        { "Dungeons", "showInDungeon", "Normal, Heroic and Mythic dungeons. Mythic+ has its own switch." },
        { "Mythic+", "showInMythicPlus" },
        { "Raids", "showInRaid" },
        { "Battlegrounds", "showInBattleground" },
        { "Arenas", "showInArena" },
        { "Scenarios and delves", "showInScenario", "Scenarios, delves and follower dungeons." },
    }) do
        Bool(T, s[1], s[2], s[3], feedOn)
    end

    -- WINDOW
    T = "Window"
    AT.Section(pg, "Position")
    row = AT.RowSlider(pg, "X position", function() return (Pg().WindowPos()) end,
        function(v) Pg().SetWindowPos(v, nil) end, -960, 960, 1, nil, InTab(T))
    AT.Tooltip(row, "X position", "From the centre of the screen; below zero is left.")
    Stamp(row, "posX", "num", T)
    row = AT.RowSlider(pg, "Y position", function() return select(2, Pg().WindowPos()) end,
        function(v) Pg().SetWindowPos(nil, v) end, -540, 540, 1, nil, InTab(T))
    AT.Tooltip(row, "Y position", "From the centre of the screen; below zero is down. The edge the feed grows from stays here.")
    Stamp(row, "posY", "num", T)
    Bool(T, "Lock position", "locked", "Locked, the window cannot be dragged. Unlocked, it shows an edge so you can place it.")
    Bool(T, "Drag while this page is open", "panelDrag", "While this page is open the window can be dragged, locked or not.")
    AT.Section(pg, "Size")
    Slider(T, "Width", "width", 160, 900, 10, nil, nil, "A longer line widens the window for as long as it shows.")
    Slider(T, "Height", "height", 0, 800, 10, nil, nil, "0 hugs the entries. More keeps the window at least that tall.")
    Slider(T, "Scale", "windowScale", 0.5, 2, 0.05, true)
    Bool(T, "Same size when empty", "staticSize",
        "The window keeps the size for Max entries shown and stays on screen when empty, instead of growing with each ping.")
    AT.Section(pg, "Frame")
    Bool(T, "Title while unlocked", "showTitle", "Shows Arc Pings above the window while it is unlocked or this page is open.")
    Drop(T, "Window layer", "strata", {
        { value = "BACKGROUND", text = "Background" }, { value = "LOW", text = "Low" },
        { value = "MEDIUM", text = "Medium" }, { value = "HIGH", text = "High" }, { value = "DIALOG", text = "Dialog" },
    }, nil, "Which other windows the feed sits above or below.")

    -- LOOK
    T = "Look"
    local bgOn = function() return Get("showBackground") == true end
    local edgeOn = function() return Get("showBorder") == true end
    AT.Section(pg, "Backdrop")
    Bool(T, "Show background", "showBackground")
    Color(T, "Background color", "colBg", bgOn)
    Slider(T, "Background opacity", "bgAlpha", 0, 1, 0.05, true, bgOn)
    Bool(T, "Show border", "showBorder", "The border always shows while the window is unlocked.")
    Color(T, "Border color", "colBorder", edgeOn)
    AT.Section(pg, "Text")
    Slider(T, "Font size", "fontSize", 8, 24, 1)
    Drop(T, "Font outline", "fontOutline", {
        { value = "NONE", text = "None" }, { value = "OUTLINE", text = "Outline" },
        { value = "THICKOUTLINE", text = "Thick outline" },
    })
    Bool(T, "Newest entries on top", "newestOnTop", "Off puts the newest entry at the bottom, and the window grows upward.")

    -- LAYOUT: one piece edited at a time
    T = "Layout"
    AT.Section(pg, "Pieces")
    Bool(T, "Show timestamp", "showTimestamp")
    Bool(T, "Show sender", "showSender")
    Slider(T, "Space above", "rowPadTop", 0, 40, 1, nil, nil, "Room above each entry's pieces.")
    Slider(T, "Space below", "rowPadBottom", 0, 40, 1, nil, nil, "Room below each entry's pieces.")
    AT.Section(pg, "Edit a Piece")
    local PIECES = Pg().PIECES
    local function Piece() return PIECES[UI.piece] or PIECES.time end
    local function PieceShown()
        local pc = Piece()
        return (not pc.showKey) or Get(pc.showKey) == true
    end
    local function PKey(f) return Piece()[f] end
    local pieceItems = {}
    for _, k in ipairs(Pg().PIECE_ORDER) do pieceItems[#pieceItems + 1] = { value = k, text = PIECES[k].label } end
    row = AT.RowDropdown(pg, win, "Piece", function() return UI.piece end,
        function(v) UI.piece = v end, function() return pieceItems end, InTab(T),
        function() AT.LayoutPage(pg) end)
    AT.Tooltip(row, "Piece", "The part of each entry the rows below place.")
    Stamp(row, "piece", "enum", T)
    AT.RowDesc(pg, "This piece is hidden: show it above to place it.", 20,
        InTab(T, function() return not PieceShown() end))
    local pieceVis = function() return PieceShown() end
    local ANCHORS = { { value = "row", text = "Free, on the line" }, { value = "time", text = "Timestamp" },
        { value = "sender", text = "Sender" }, { value = "text", text = "Ping text" } }
    row = AT.RowDropdown(pg, win, "Anchor to", function() return Get(PKey("anchorKey")) or "row" end,
        function(v) Set(PKey("anchorKey"), v) end, function()
            local out = {}
            for _, a in ipairs(ANCHORS) do
                if a.value ~= UI.piece then out[#out + 1] = a end
            end
            return out
        end, InTab(T, function() return PieceShown() and PKey("anchorKey") ~= nil end),
        function() AT.LayoutPage(pg) end)
    AT.Tooltip(row, "Anchor to", "Places this piece beside another piece instead of on the line itself.")
    Stamp(row, "pieceAnchor", "enum", T, function() return PKey("anchorKey") ~= nil end)
    local FREE = { left = "Left", center = "Center", right = "Right", top = "Top", bottom = "Bottom" }
    local NEXT = { left = "Left of it", center = "Centered on it", right = "Right of it", top = "Above it", bottom = "Below it" }
    row = AT.RowDropdown(pg, win, "Position", function() return Get(PKey("posKey")) or "left" end,
        function(v) Set(PKey("posKey"), v) end, function()
            local ak = PKey("anchorKey")
            local anchored = ak ~= nil and (Get(ak) or "row") ~= "row"
            local out = {}
            for _, v in ipairs({ "left", "center", "right", "top", "bottom" }) do
                -- the ping text spans the line: left, center or right only
                if not (UI.piece == "text" and (v == "top" or v == "bottom")) then
                    out[#out + 1] = { value = v, text = (anchored and NEXT[v]) or FREE[v] }
                end
            end
            return out
        end, InTab(T, pieceVis))
    Stamp(row, "piecePos", "enum", T)
    row = AT.RowSlider(pg, "X offset", function() return Get(PKey("xKey")) end,
        function(v) Set(PKey("xKey"), v) end, -600, 900, 1, nil, InTab(T, pieceVis))
    Stamp(row, "pieceX", "num", T)
    row = AT.RowSlider(pg, "Y offset", function() return Get(PKey("yKey")) end,
        function(v) Set(PKey("yKey"), v) end, -200, 200, 1, nil, InTab(T, pieceVis))
    Stamp(row, "pieceY", "num", T)
    row = AT.RowSlider(pg, "Own font size", function() return Get(PKey("sizeKey")) end,
        function(v) Set(PKey("sizeKey"), v) end, 0, 48, 1, nil, InTab(T, pieceVis))
    AT.Tooltip(row, "Own font size", "0 follows the font size on the Look tab.")
    Stamp(row, "pieceSize", "num", T)
    row = AT.RowColor(pg, "Color", function()
            local c = Get(PKey("colorKey")) or { 1, 1, 1 }
            return { c[1], c[2], c[3] }
        end,
        function(c) Set(PKey("colorKey"), { c[1], c[2], c[3] }) end, InTab(T, pieceVis))
    Stamp(row, "pieceColor", "color", T)
    local acts = AT.AddRow(pg, 28, InTab(T))
    local resetPiece = AT.MakeSmallButton(acts, "Reset this piece", 140)
    resetPiece:SetPoint("LEFT", 10, 0)
    AT.Tooltip(resetPiece, "Reset this piece", "Puts the piece above back where it ships, with its color and size.")
    resetPiece:SetScript("OnClick", function()
        AT.CloseDropdown()
        Pg().ResetPiece(UI.piece)
        AT.LayoutPage(pg)
    end)
    local resetAll = AT.MakeQuietButton(acts, "Reset whole layout", 150)
    resetAll:SetPoint("LEFT", resetPiece, "RIGHT", 8, 0)
    AT.Tooltip(resetAll, "Reset whole layout", "Every piece back where it ships, both shown, the default spacing. Asks for a second click.")
    -- two clicks: every piece's place goes at once
    local confirm = false
    resetAll:SetScript("OnClick", function()
        AT.CloseDropdown()
        if not confirm then
            confirm = true
            resetAll:SetLabel("Click again to reset")
            C_Timer.After(3, function()
                confirm = false
                resetAll:SetLabel("Reset whole layout")
            end)
            return
        end
        confirm = false
        resetAll:SetLabel("Reset whole layout")
        Pg().ResetLayout()
        AT.LayoutPage(pg)
    end)
    pg._adResetPiece, pg._adResetAll = resetPiece, resetAll

    -- ENTRIES, their animations and the alert
    T = "Entries"
    AT.Section(pg, "Entries")
    Slider(T, "Max entries shown", "maxEntries", 1, 20, 1)
    Slider(T, "Entry duration (s)", "entrySeconds", 0, 60, 1, nil, nil, "0 keeps a ping until newer ones push it out.")
    AT.Section(pg, "Animations")
    Drop(T, "New ping animation", "animStyle", {
        { value = "none", text = "None" }, { value = "fade", text = "Fade in" }, { value = "pulse", text = "Pulse" },
        { value = "flash", text = "Flash" }, { value = "zoom", text = "Zoom in" },
    })
    Slider(T, "Entrance length (s)", "animInSecs", 0.1, 2, 0.1, nil, function() return Get("animStyle") ~= "none" end)
    Drop(T, "Expire animation", "animOutStyle", { { value = "none", text = "None" }, { value = "fade", text = "Fade out" } })
    Slider(T, "Fade-out length (s)", "animOutSecs", 0.1, 3, 0.1, nil, function() return Get("animOutStyle") == "fade" end)
    AT.Section(pg, "Alerts")
    local alertOn = function() return Get("alertsEnabled") == true end
    Bool(T, "Sound when a ping comes in", "alertsEnabled", "Plays a sound for each ping the feed shows, in combat too.")
    row = AT.RowDropdown(pg, win, "Sound", function() return Get("alertSound") or "" end,
        function(v) Set("alertSound", v) end,
        function() return (NS.Sounds and NS.Sounds.Items()) or { { value = "", text = "None" } } end,
        InTab(T, alertOn),
        function(v) if NS.Sounds and NS.Sounds.Preview then NS.Sounds.Preview(v, "Master") end end)
    Stamp(row, "alertSound", "enum", T, alertOn)
    Slider(T, "Quiet time between sounds (s)", "alertThrottle", 0, 10, 0.5, nil, alertOn,
        "However many pings arrive, the sound plays at most once in this time.")
    row = AT.RowButton(pg, "Play the sound", function() Pg().PlaySound(Get("alertSound")) end, InTab(T, alertOn), 150)
    Stamp(row, "alertTest", nil, T, alertOn)

    -- this page open shows the window with a sample line
    pg:HookScript("OnShow", function()
        local p = Pg()
        if not p then return end
        if p.PK then p.PK.CatalogDirty() end
        p.SetPanelOpen(true)
    end)
    pg:HookScript("OnHide", function()
        local p = Pg()
        if p then p.SetPanelOpen(false) end
    end)
    local p = Pg()
    if p then
        p.notify = function()
            if pg:IsVisible() then AT.LayoutPage(pg) end
        end
    end
end

local spec
spec = {
    key = "pings",
    switch = "on",
    name = "Arc Pings",
    desc = "Ping your cooldowns to the group with a key, and see and hear your group's pings.",
    -- the game's ping marker: a diamond round a dot
    glyph = {
        { 0, 5, 12, 2, "arc", 45 }, { 8, 5, 12, 2, "arc", -45 },
        { 8, 13, 12, 2, "arc", 45 }, { 0, 13, 12, 2, "arc", -45 },
        { 8, 8, 4, 4, "ink" },
    },
    available = function()
        local ok = Avail()
        spec.unavailable = (not ok) and Why() or nil
        return ok
    end,
    isOn = function() return Pg() ~= nil and Pg().IsOn() end,
    setOn = function(v)
        if Pg() then Pg().SetOn(v) end
    end,
    build = function(pg, m) Build(pg, m) end,
}
MOD.Register(spec)
