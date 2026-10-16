-- AD_TotemOptions: a totem icon's Tracking rows. What it follows (one totem by
-- its spell, a totem slot, or the totem bar's pick for an element), the click
-- and the key that drop the bar's pick (Drivers\AD_TotemButton.lua), and the
-- buff its Out of range state watches (Drivers\AD_TotemRange.lua).
-- AD_Options calls Options.TotemTrackRows while it builds the icon pane.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- The bar's order: Earth, Fire, Water, Air (slots 2, 1, 3, 4).
local BAR_ORDER = { 2, 1, 3, 4 }
-- held alone, a modifier waits for the key it goes with
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true }

-- A spell-tracked totem that lands a moment after the cast (Summon Hawk flies
-- in first): how long a cast waits for its slot (driver.slotWait, nil = the
-- short default) and Show from the cast (driver.fromCast), in
-- Drivers\AD_DriverTotem.lua. Rec: the icon or bar being edited; vis: its spell
-- rows show. Shared by the totem bars.
-- Ready-made totem icons, picked in the Add window ("TEMPLATE - click one,
-- then Create", as the item lists are): a click fills the spell and Which one;
-- Create adds the wait for its slot and the name while the picks still match.
Options.TOTEM_TEMPLATES = {
    -- two hawks out at once, each landing a moment after the cast
    { key = "hawk1", spell = 1293241, which = 1, wait = 1.5 },
    { key = "hawk2", spell = 1293241, which = 2, wait = 1.5 },
}

-- the ones this client knows (a spell it has no name for is not offered)
function Options.TotemTemplates()
    local DT = NS.DriverTotem
    local out = {}
    for _, t in ipairs(Options.TOTEM_TEMPLATES) do
        if DT and DT.SpellName(t.spell) then out[#out + 1] = t end -- raw-id: the template's own spell
    end
    return out
end

function Options.TotemTemplateName(t)
    local DT = NS.DriverTotem
    local nm = DT and DT.SpellName(t.spell) or tostring(t.spell) -- raw-id: the template's own spell
    return ("%s (%s)"):format(nm, Options.TotemWhichWord(t.which))
end

-- the template the Add window's picks match now, or nil
function Options.TotemTemplateFor(sid, which)
    sid, which = tonumber(sid), tonumber(which) or 0
    if not sid then return nil end
    for _, t in ipairs(Options.TotemTemplates()) do
        if t.spell == sid and t.which == which then return t end -- raw-id: the template's own spell
    end
    return nil
end

Options.TT_CELL, Options.TT_PITCH, Options.TT_CAP = 32, 36, 13

-- The Add window's squares: one per template, its spell's art with its Which
-- number in the corner; the one the picks match stays cyan.
function Options.TotemTemplateRows(pg, owner, addState, vis)
    local AT, COL = NS.AT, NS.AT.COL
    local cell, pitch, top = Options.TT_CELL, Options.TT_PITCH, Options.TT_CAP
    local row = AT.AddRow(pg, pitch + 8 + top, function() return vis() and #Options.TotemTemplates() > 0 end)
    row._tplGrid = true
    local cap = row:CreateFontString(nil, "OVERLAY")
    cap:SetFont(AT.FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText(AT.Tr("TEMPLATE - click one, then Create"))
    row._cap = cap
    local cells = {}
    local function Lit(t)
        return t ~= nil and Options.TotemTemplateFor(addState.totemSpell, addState.totemWhich) == t
    end
    local function Cell(i)
        if cells[i] then return cells[i] end
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(cell, cell)
        b:SetPoint("LEFT", row, "LEFT", 10 + (i - 1) * pitch, -top / 2)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.num = b:CreateFontString(nil, "OVERLAY")
        b.num:SetFont(AT.FONT, 11, "OUTLINE")
        b.num:SetPoint("BOTTOMRIGHT", -2, 2)
        function b.Edge(hot)
            local c = (Lit(b._t) and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            local t = b._t
            if not t then return end
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(Options.TotemTemplateName(t), COL.ink[1], COL.ink[2], COL.ink[3])
            GameTooltip:AddLine(AT.Tr("Fills in the spell and Which one; Create adds a %s s wait for its slot.")
                :format(("%g"):format(t.wait)), COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local t = b._t
            if not t then return end
            AT.CloseDropdown()
            addState.totemSpell, addState.totemWhich = tostring(t.spell), t.which
            AT.LayoutPage(pg)
        end)
        cells[i] = b
        return b
    end
    row._cells = cells
    row._sync = function()
        local list = Options.TotemTemplates()
        for i, t in ipairs(list) do
            local b = Cell(i)
            b._t, b._adTpl = t, t.key
            b.tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(t.spell)) or 134400) -- raw-id: the template's own spell
            b.num:SetText(tostring(t.which))
            b.Edge(false)
            b:Show()
        end
        for i = #list + 1, #cells do
            cells[i]._t, cells[i]._adTpl = nil, nil
            cells[i]:Hide()
        end
    end
    return row
end

-- How a Which pick counts (driver.whichBy): the slots in use, lowest first
-- (nil), or the order they came out ("order"). Rec / vis as below; it shows
-- only with a Which pick.
function Options.TotemWhichByRow(pg, Rec, vis, owner)
    local AT, Store = NS.AT, NS.Store
    local DT = NS.DriverTotem
    if not DT then return end
    local row = AT.RowDropdown(pg, owner, "Counted by",
        function()
            local r = Rec()
            return (r and DT.ByOrder(r.driver)) and "order" or "slot"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.whichBy = (v == "order") and "order" or nil
            Store.Dirty("style", r.id)
        end,
        function()
            return { { value = "slot", text = "Slots in use" }, { value = "order", text = "Order out" } }
        end,
        function()
            local r = Rec()
            return vis() and r ~= nil and DT.Which(r.driver) ~= nil
        end)
    -- one literal, so the translator finds the whole sentence
    AT.Tooltip(row, "Counted by",
        "Slots in use: First is the lowest totem slot, and the one left moves up. Order out: each keeps its icon until it ends.")
end

function Options.TotemTimingRows(pg, Rec, vis, owner)
    local AT, Store = NS.AT, NS.Store
    local DT = NS.DriverTotem
    if not DT then return end
    local Tr = AT.Tr
    local function Secs(v) return Tr("%s s"):format(("%g"):format(v)) end

    local wait = AT.RowDropdown(pg, owner, "Wait for its slot",
        function()
            local r = Rec()
            local v = r and tonumber(r.driver.slotWait)
            return (v and v > 0) and v or 0
        end,
        function(v)
            local r = Rec()
            if not r then return end
            v = tonumber(v) or 0
            r.driver.slotWait = (v > 0) and v or nil
            Store.Dirty("style", r.id)
        end,
        function()
            local out = { { value = 0, text = Secs(DT.PAIR_WINDOW), raw = true } }
            for _, s in ipairs(DT.WAITS) do out[#out + 1] = { value = s, text = Secs(s), raw = true } end
            return out
        end,
        vis)
    AT.Tooltip(wait, "Wait for its slot",
        "How long after your cast it may land and still light this in combat. One that flies in first needs longer (Summon Hawk: 1.5 s).")

    AT.RowToggle(pg, "Show from the cast",
        function()
            local r = Rec()
            return r ~= nil and r.driver.fromCast == true
        end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.fromCast = v and true or nil
            Store.Dirty("style", r.id)
        end,
        vis, "Lights the moment you cast, timed from the cast, until it lands in its slot. Needs one cast out of combat to learn its time.")
end

-- ctx: the selected icon. vis: the Tracking tab shows. owner: the window the
-- dropdown lists open on. refresh: the panel's full refresh.
function Options.TotemTrackRows(pg, ctx, vis, owner, refresh)
    local AT, Store, Schema = NS.AT, NS.Store, NS.Schema
    local COL = AT.COL
    local DT = NS.DriverTotem
    -- one totem icon; several at once share no driver to write
    local function Rec()
        local r = ctx()
        if not (r and r.kind == "totem" and type(r.driver) == "table" and not r._adMulti) then return nil end
        return r
    end
    local function Mode(r)
        local d = r.driver
        if d.bar then return "bar" end
        if d.spellID or d.follow == "spell" then return "spell" end
        return "slot"
    end
    local function Shows(mode)
        return function()
            local r = Rec()
            return vis() and r ~= nil and Mode(r) == mode
        end
    end
    local spellVis, slotVis, barVis = Shows("spell"), Shows("slot"), Shows("bar")
    -- an element's English word (a key), or the slot's number where the
    -- driver names none, translated already (raw = true)
    local function Element(slot)
        local w = DT and DT.ELEMENTS and DT.ELEMENTS[slot]
        if w then return w, false end
        return AT.Tr("Slot %d"):format(tonumber(slot) or 1), true
    end

    local follow = AT.RowDropdown(pg, owner, "Follow",
        function() local r = Rec() return r and Mode(r) or "slot" end,
        function(v)
            local r = Rec()
            if not r then return end
            local d = r.driver
            if v == "spell" then
                d.bar, d.follow = nil, "spell"
            elseif v == "bar" then
                d.bar, d.follow, d.spellID, d.which, d.whichBy, d.slotWait, d.fromCast = true, nil, nil, nil, nil, nil, nil
            else
                d.bar, d.follow, d.spellID, d.which, d.whichBy, d.slotWait, d.fromCast = nil, nil, nil, nil, nil, nil, nil
            end
            if DT then DT.Track(r) end
            Store.Dirty("tree")
            refresh()
        end,
        function()
            local items = { { value = "spell", text = "One totem, by its spell ID" },
                { value = "slot", text = "A totem slot" } }
            if DT and DT.HasBar and DT.HasBar() then
                items[#items + 1] = { value = "bar", text = "My totem bar's pick" }
            end
            return items
        end,
        function() return vis() and Rec() ~= nil end)
    AT.Tooltip(follow, "Follow", "One totem: any rank, any slot. A totem slot: whatever is in it. My totem bar's pick: its totem, shown with none down; click drops it.")

    -- One totem: the spell that puts it down.
    AT.RowInput(pg, "Spell ID",
        function()
            local r = Rec()
            return r and r.driver.spellID and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local sid = tonumber(v)
            if sid and sid > 0 then
                r.driver.spellID = sid
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: the typed ID names the record
                if nm then r.name = nm end
            else
                r.driver.spellID = nil
            end
            if DT then DT.Track(r) end
            Store.Dirty("tree")
            refresh()
        end,
        spellVis,
        "The spell that puts it down: the icon follows that totem or guardian, any rank, into whatever slot it lands.",
        "Type the spell ID")
    -- a spell with several out at once: one icon per slot
    local inSlot = AT.RowDropdown(pg, owner, "Which one",
        function()
            local r = Rec()
            return (r and DT and DT.Which(r.driver)) or 0
        end,
        function(v)
            local r = Rec()
            if not r then return end
            v = tonumber(v) or 0
            r.driver.which = (v >= 1) and v or nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.TotemWhichItems() end,
        spellVis)
    AT.Tooltip(inSlot, "Which one", Options.TOTEM_WHICH_TIP)
    Options.TotemWhichByRow(pg, Rec, spellVis, owner)
    -- when it lands after the cast: measured, waited for, or shown from the cast
    Options.TotemTimingRows(pg, Rec, function() return spellVis() and Rec().driver.spellID ~= nil end, owner)

    local slotRow = AT.RowDropdown(pg, owner, "Totem slot",
        function() local r = Rec() return r and (r.driver.slot or 1) end,
        function(v)
            local r = Rec()
            if r then r.driver.slot = v Store.Dirty("style", r.id) end
        end,
        function() return Options.TotemSlotItems() end,
        slotVis)
    AT.Tooltip(slotRow, "Totem slot", Options.TotemSlotTip)

    -- The totem bar's pick for an element.
    local elRow = AT.RowDropdown(pg, owner, "Element",
        function() local r = Rec() return r and (r.driver.slot or 1) end,
        function(v)
            local r = Rec()
            if r then r.driver.slot = v Store.Dirty("style", r.id) end
        end,
        function()
            local out = {}
            for _, s in ipairs(BAR_ORDER) do
                local w, raw = Element(s)
                out[#out + 1] = { value = s, text = w, raw = raw or nil }
            end
            return out
        end,
        barVis)
    AT.Tooltip(elRow, "Element", "The totem bar button this icon follows.")

    -- what the icon shows, in words
    local barRow = AT.AddRow(pg, 22, barVis)
    local barFS = barRow:CreateFontString(nil, "OVERLAY")
    barFS:SetFont(NS.AT.FONT, 11, "")
    barFS:SetPoint("TOPLEFT", 10, -4)
    barFS:SetJustifyH("LEFT")
    barFS:SetJustifyV("TOP")
    barFS:SetWordWrap(true)
    barFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    barRow._sync = function()
        local r = Rec()
        if not (r and DT) then return end
        local slot = r.driver.slot or 1
        local el, elRaw = Element(slot)
        local text
        local Tr = NS.AT.Tr
        local elWord = elRaw and el or Tr(el)
        local elLow = elRaw and el or Tr(el:lower())
        -- the element's word mid-line is a key of its own, lower case
        if not DT.BarAction(slot) then
            text = Tr("Your totem bar is not up yet: it comes with your first totem.")
        else
            local sid = DT.BarPick(slot)
            if sid then
                text = Tr("Shows %s, your totem bar's %s pick, while no %s totem is down."):format(
                    DT.SpellName(sid) or Tr("that totem"), elWord, elLow) -- raw-id: the totem bar slot's own spell
            else
                text = Tr("Your totem bar has no %s totem picked yet: pick one in its flyout."):format(elWord)
            end
        end
        barFS:SetText(text)
        local w = barRow:GetWidth() or 0
        if w < 90 then w = (pg:GetWidth() or 0) - 24 end
        if w > 90 then barFS:SetWidth(w - 24) end
        local want = math.max(22, math.floor((barFS:GetStringHeight() or 12) + 10))
        if barRow._h ~= want then
            barRow._h = want
            barRow:SetHeight(want)
        end
    end

    AT.RowToggle(pg, "Click to drop it",
        function() local r = Rec() return r ~= nil and r.driver.click == true end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.click = v and true or nil
            Store.Dirty("style", r.id)
        end,
        barVis,
        "Clicking the icon drops the totem it shows, in combat too. Set out of combat; while this window is open the icon stays draggable.")

    -- The key: click the box, then press it; right-click clears it.
    local keyRow = AT.AddRow(pg, 26, barVis)
    keyRow._colLabel = AT.RowLabel(keyRow, "Key to drop it")
    local kb = AT.MakeSmallButton(keyRow, "Not set", 150)
    kb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    keyRow._colCtrl = kb
    local capturing = false
    local function KeyWords(r)
        local k = r and r.driver.key
        if type(k) ~= "string" or k == "" then return NS.AT.Tr("Not set") end
        return (GetBindingText and GetBindingText(k)) or k
    end
    local function Stop()
        capturing = false
        kb:SetScript("OnKeyDown", nil)
        kb:EnableKeyboard(false)
        kb.fs:SetText(KeyWords(Rec()))
    end
    kb:SetScript("OnClick", function(_, button)
        local r = Rec()
        if not r then return end
        if button == "RightButton" then
            r.driver.key = nil
            Stop()
            Store.Dirty("style", r.id)
            return
        end
        -- a binding is set out of combat only
        if InCombatLockdown() then
            kb.fs:SetText(NS.AT.Tr("Leave combat first"))
            return
        end
        capturing = true
        kb.fs:SetText(NS.AT.Tr("Press a key..."))
        kb:EnableKeyboard(true)
        kb:SetPropagateKeyboardInput(false)
        kb:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then Stop() return end
            if MODIFIERS[key] then return end
            local r2 = Rec()
            if r2 then
                r2.driver.key = (CreateKeyChordStringUsingMetaKeyState
                    and CreateKeyChordStringUsingMetaKeyState(key)) or key
                Store.Dirty("style", r2.id)
            end
            Stop()
        end)
    end)
    kb:HookScript("OnHide", function() if capturing then Stop() end end)
    keyRow._sync = function()
        if not capturing then kb.fs:SetText(KeyWords(Rec())) end
    end
    AT.Tooltip(kb, "Key to drop it", "Click, then press a key (with Shift, Ctrl or Alt if you like). Right-click clears it. The key drops this totem, not its usual action.")

    -- One totem: the buff its Out of range look waits on, looked up by name.
    local function rangeVis()
        local r = Rec()
        return vis() and r ~= nil and Schema.TotemBySpell(r)
    end
    AT.RowInput(pg, "Its buff",
        function()
            local r = Rec()
            return r and r.driver.rangeBuff or ""
        end,
        function(v)
            local r = Rec()
            local TR = NS.TotemRange
            if not (r and TR) then return end
            v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            r.driver.rangeBuff = v ~= "" and v or nil
            local name = TR.BuffName(r)
            if name and r.driver.rangeBuffFor ~= name then TR.Find(r) end
            Store.Dirty("style", r.id)
            refresh()
        end,
        rangeVis,
        "The buff this totem gives you, as its tooltip names it. The Out of range look shows while the totem is out and you lack it.",
        function()
            local r = Rec()
            return (r and NS.TotemRange and NS.TotemRange.AutoName(r)) or ""
        end)
    -- what the look waits on, and a new search when nothing was found
    local rangeRow = AT.AddRow(pg, 24, rangeVis)
    local rangeFS = rangeRow:CreateFontString(nil, "OVERLAY")
    rangeFS:SetFont(NS.AT.FONT, 11, "")
    rangeFS:SetPoint("TOPLEFT", 10, -4)
    rangeFS:SetJustifyH("LEFT")
    rangeFS:SetJustifyV("TOP")
    rangeFS:SetWordWrap(true)
    rangeFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local rangeFind = AT.MakeSmallButton(rangeRow, "Look up", 64)
    rangeFind:SetPoint("TOPRIGHT", -8, -2)
    rangeFind:SetHeight(18)
    rangeFind.fs:SetFont(NS.AT.FONT, 10, "")
    AT.Tooltip(rangeFind, "Look up", "Searches the spell list for the buff by its name.")
    rangeFind:SetScript("OnClick", function()
        local r = Rec()
        if r and NS.TotemRange then NS.TotemRange.Find(r) end
        AT.LayoutPage(pg)
    end)
    rangeRow._sync = function()
        local r = Rec()
        local TR = NS.TotemRange
        if not (r and TR) then return end
        rangeFS:SetText(TR.StatusText(r))
        rangeFind:SetShown(TR.IDs(r) == nil and not TR.Searching(r))
        local w = rangeRow:GetWidth() or 0
        if w < 90 then w = (pg:GetWidth() or 0) - 24 end
        if w > 90 then rangeFS:SetWidth(w - 90) end
        local want = math.max(24, math.floor((rangeFS:GetStringHeight() or 12) + 10))
        if rangeRow._h ~= want then
            rangeRow._h = want
            rangeRow:SetHeight(want)
        end
    end
end
