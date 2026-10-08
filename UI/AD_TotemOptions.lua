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
    local function Element(slot)
        return (DT and DT.ELEMENTS and DT.ELEMENTS[slot]) or ("Slot " .. tostring(slot))
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
                d.bar, d.follow, d.spellID = true, nil, nil
            else
                d.bar, d.follow, d.spellID = nil, nil, nil
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
    AT.Tooltip(follow, "Follow", "One totem: that totem, any rank, in whatever slot it lands. A totem slot: "
        .. "whatever is in it. My totem bar's pick: the totem your totem bar drops for an element, shown "
        .. "while none is down; a click or a key can drop it.")

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
            for _, s in ipairs(BAR_ORDER) do out[#out + 1] = { value = s, text = Element(s) } end
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
        local el = Element(slot)
        local text
        if not DT.BarAction(slot) then
            text = "Your totem bar is not up yet: it comes with your first totem."
        else
            local sid = DT.BarPick(slot)
            if sid then
                text = ("Shows %s, your totem bar's %s pick, while no %s totem is down."):format(
                    DT.SpellName(sid) or "that totem", el, el:lower()) -- raw-id: the totem bar slot's own spell
            else
                text = ("Your totem bar has no %s totem picked yet: pick one in its flyout."):format(el)
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
        if type(k) ~= "string" or k == "" then return "Not set" end
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
            kb.fs:SetText("Leave combat first")
            return
        end
        capturing = true
        kb.fs:SetText("Press a key...")
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
    AT.Tooltip(kb, "Key to drop it", "Click, then press the key (with Shift, Ctrl or Alt if you like). "
        .. "Right-click clears it. While Arc Auras is loaded the key drops this totem instead of its usual action.")

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
        "The buff this totem puts on you, as its tooltip names it. The Out of range look shows while the totem is out and this buff is not on you. Empty: the totem's name without Totem.",
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
