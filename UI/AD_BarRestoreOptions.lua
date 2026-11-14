-- AD_BarRestoreOptions: the Action Bar Restore card on the Modules page and its page (WoW Forever only).
-- Reads NS.BarRestore at call time; the engine owns the saves and the named profiles.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local COL, Tr = AT.COL, AT.Tr
local MOD = Options.Modules

local function BR() return NS.BarRestore end

-- Names listed after a load before the rest is a count.
local MAX_NAMES = 6
local BACK_AFTER = 1.6
local CONFIRM_FOR = 4
local BTN_W = 170

local function GroupWord(g)
    local b = BR()
    return b and b.SpecWord(g) or "?"
end

local function When(t)
    local fmt = date or (os and os.date)
    return (type(t) == "number" and fmt) and fmt("%Y-%m-%d %H:%M", t) or "?"
end

-- The picked entry: { value, kind, g, mine, name, saved } and the save itself.
local function Picked()
    local b = BR()
    local v = b and b.Pick()
    local info = v and b.Info(v)
    return info, info and b.SaveOf(v) or nil
end

local function Active()
    local b = BR()
    return b and b.Group()
end

-- A dim line whose words follow the engine; it shows while textFn has something to say.
local function LiveLine(pg, textFn, vis)
    local row = AT.AddRow(pg, 20, function() return vis() and textFn() ~= nil end)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -2)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row.fs = fs
    row._sync = function()
        if not vis() then return end
        fs:SetText(textFn() or "")
        local w = pg:GetWidth() or 0
        if w < 60 then pg._sizeUnresolved = true return end
        fs:SetWidth(w - 36)
        local want = math.max(20, math.floor((fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- RowButton's shape with the theme's red button.
local function DangerRow(pg, label, onClick, vis, w, rowLabel)
    local row = AT.AddRow(pg, nil, vis)
    local b = AT.MakeDangerButton(row, label, w)
    b:SetScript("OnClick", function() AT.CloseDropdown(); onClick() end)
    if rowLabel then row._colLabel = AT.RowLabel(row, rowLabel) end
    row._colCtrl, row.button = b, b
    return row
end

-- A button says how it went for a moment, then wears its own word again.
local function Flash(btn, text, back, secs, after)
    if not btn then return end
    btn:SetLabel(text)
    local gen = (btn._brGen or 0) + 1
    btn._brGen = gen
    C_Timer.After(secs or BACK_AFTER, function()
        if btn._brGen ~= gen then return end
        btn:SetLabel(back)
        if after then after() end
    end)
end

local function SourceText(s)
    if s.kind == "profile" then return s.name or "?" end
    local word = GroupWord(s.g)
    if not s.mine then return Tr("%s on %s"):format(word, s.name or "?") end
    if s.g == Active() then word = Tr("%s (active)"):format(word) end
    if not s.saved then return Tr("%s, not saved yet"):format(word) end
    return word
end

local function BarsText(bars)
    if type(bars) ~= "table" then return nil end
    local on = {}
    for i = 1, 7 do
        if bars[i] == true then on[#on + 1] = tostring(i + 1) end
    end
    if #on == 0 then return Tr("Bars 2 to 8 off.") end
    return Tr("Bars on: %s."):format(table.concat(on, ", "))
end

-- What the picked save holds, in whole sentences.
local function InfoText()
    local info, save = Picked()
    if not info then return nil end
    local parts = {}
    if not save then
        parts[1] = Tr("Not saved yet.")
    else
        local n = save.n or 0
        parts[1] = n == 1 and Tr("Saved %s: 1 button."):format(When(save.t))
            or Tr("Saved %s: %d buttons."):format(When(save.t), n)
        parts[#parts + 1] = BarsText(save.bars)
        if type(save.layout) == "table" and save.layout.name then
            parts[#parts + 1] = Tr("Edit Mode layout: %s."):format(save.layout.name)
        end
    end
    if info.kind == "spec" and info.mine and info.g ~= Active() then
        parts[#parts + 1] = Tr("Save it while in %s."):format(GroupWord(info.g))
    end
    return table.concat(parts, " ")
end

local function DiffText()
    local b = BR()
    local v = b and b.Pick()
    if not v then return nil end
    if b.Pending() then return Tr("Loads when combat ends.") end
    local n = b.Differs(v)
    if n == nil then return nil end
    if n == 0 then return Tr("Your bars match this save.") end
    if n == 1 then return Tr("1 button differs from this save.") end
    return Tr("%d buttons differ from this save."):format(n)
end

-- What the last load could not do, in whole sentences.
local function ResultText()
    local b = BR()
    local last = b and b.last
    if not last then return nil end
    if last.why == "cursor" then return Tr("Not loaded after combat: your cursor was holding something.") end
    local parts = {}
    local m = last.missed
    if type(m) == "table" and #m > 0 then
        local shown = {}
        for i = 1, math.min(#m, MAX_NAMES) do shown[i] = m[i] end
        local list = table.concat(shown, ", ")
        parts[1] = #m > MAX_NAMES and Tr("Could not place: %s and %d more."):format(list, #m - MAX_NAMES)
            or Tr("Could not place: %s."):format(list)
    end
    local name = last.layoutName or "?"
    if last.layout == "switched" then
        parts[#parts + 1] = Tr("Switched to the Edit Mode layout %s."):format(name)
    elseif last.layout == "gone" then
        parts[#parts + 1] = Tr("The Edit Mode layout %s is gone."):format(name)
    elseif last.layout == "editmode" then
        parts[#parts + 1] = Tr("Close Edit Mode, then load again to switch layouts.")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

local function Build(pg, m)
    local function On() return m.isOn() end
    local function IsProfile() local info = Picked() return On() and info ~= nil and info.kind == "profile" end
    local function CanSave()
        local info = Picked()
        if not (On() and info) then return false end
        return info.kind == "profile" or (info.mine == true and info.g == Active())
    end
    local function CanLoad() local _, save = Picked() return On() and save ~= nil end
    local function NeedsReload() local b = BR() return On() and b ~= nil and b.NeedsReload() end

    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Save and load action bars", m.isOn, m.setOn, MOD.Always,
        "Keeps each spec's action bars and the profiles you make. When the game loads saved buttons empty, a box offers to put them back.")
    MOD.Stamp(row, m, m.switch, "bool", MOD.Always, true)

    AT.Section(pg, Tr("Profiles"), { visibleFn = On })
    row = AT.RowDropdown(pg, MOD.win, Tr("Profile"),
        function() local b = BR() return b and b.Pick() end,
        function(v)
            local b = BR()
            if b then b.SetPick(v) end
            pg._brDelete = nil
            AT.LayoutPage(pg)
        end,
        function()
            local b, items = BR(), {}
            if not b then return items end
            for _, s in ipairs(b.Sources()) do items[#items + 1] = { value = s.value, text = SourceText(s) } end
            return items
        end, On)
    AT.Tooltip(row, "Profile", "Primary and Secondary are your spec saves. Profiles have their own names, and any character can load one.")
    MOD.Stamp(row, m, "barRestorePick", "enum", On)

    row = AT.RowInput(pg, "Name",
        function() local info = Picked() return info and info.name or "" end,
        function(v)
            local b = BR()
            if b and b.Rename(b.Pick(), v) then AT.LayoutPage(pg) end
        end, IsProfile, "Type a new name and press Enter.")
    MOD.Stamp(row, m, "barRestoreName", "text", IsProfile)

    LiveLine(pg, InfoText, On)
    LiveLine(pg, DiffText, CanLoad)

    local saveRow
    saveRow = AT.RowButton(pg, Tr("Save"), function()
        local b = BR()
        if not b then return end
        local n, why, fewer = b.Save(b.Pick(), pg._brConfirm == true)
        pg._brConfirm = nil
        local btn = saveRow.button
        if n then
            Flash(btn, n == 1 and "Saved 1 button" or Tr("Saved %d buttons"):format(n), "Save")
        elseif why == "fewer" then
            pg._brConfirm = true
            Flash(btn, Tr("%d fewer: press again"):format(fewer), "Save", CONFIRM_FOR,
                function() pg._brConfirm = nil end)
        elseif why == "combat" then
            Flash(btn, "Not in combat", "Save")
        elseif why == "empty" then
            Flash(btn, "Your bars are empty", "Save")
        else
            Flash(btn, "Try again in a moment", "Save")
        end
        AT.LayoutPage(pg)
    end, CanSave, BTN_W, "Your bars now")
    AT.Tooltip(saveRow.button, "Save", "Saves the buttons, which of bars 2 to 8 are on, and your Edit Mode layout into the profile picked above.")
    MOD.Stamp(saveRow, m, "barRestoreSave", nil, CanSave)

    local loadRow
    loadRow = AT.RowButton(pg, "Load", function()
        local b = BR()
        local v = b and b.Pick()
        if not v then return end
        local n, why = b.Load(v)
        local btn = loadRow.button
        if n then
            Flash(btn, n == 1 and "Placed 1 button" or Tr("Placed %d buttons"):format(n), "Load")
        elseif why == "combat" then
            Flash(btn, "After combat", "Load")
        elseif why == "cursor" then
            Flash(btn, "Empty your cursor first", "Load")
        end
        AT.LayoutPage(pg)
    end, CanLoad, BTN_W, "Put it on your bars")
    AT.Tooltip(loadRow.button, "Load", "Fills the buttons this save has, turns bars 2 to 8 on or off as saved, and switches to its Edit Mode layout.")
    MOD.Stamp(loadRow, m, "barRestoreLoad", nil, CanLoad)
    LiveLine(pg, ResultText, CanLoad)

    LiveLine(pg, function() return Tr("Bars 2 to 8 change after a reload.") end, NeedsReload)
    row = AT.RowButton(pg, Tr("Reload"), function() ReloadUI() end, NeedsReload, BTN_W)
    AT.Tooltip(row.button, "Reload", "The game draws bars 2 to 8 when the interface reloads.")
    MOD.Stamp(row, m, "barRestoreReload", nil, NeedsReload)

    local newRow
    newRow = AT.RowButton(pg, "New profile", function()
        local b = BR()
        if not b then return end
        local v, why = b.NewProfile()
        if v then
            pg._brDelete = nil
            AT.LayoutPage(pg)
        elseif why == "combat" then
            Flash(newRow.button, "Not in combat", "New profile")
        elseif why == "empty" then
            Flash(newRow.button, "Your bars are empty", "New profile")
        end
    end, On, BTN_W, "From your bars now")
    AT.Tooltip(newRow.button, "New profile", "Makes a profile from your bars now. Rename it in the Name box.")
    MOD.Stamp(newRow, m, "barRestoreNew", nil, On)

    local delRow
    delRow = DangerRow(pg, "Delete", function()
        local b = BR()
        if not b then return end
        if not pg._brDelete then
            pg._brDelete = true
            Flash(delRow.button, "Press again to delete", "Delete", CONFIRM_FOR, function() pg._brDelete = nil end)
            return
        end
        pg._brDelete = nil
        b.Delete(b.Pick())
        delRow.button:SetLabel("Delete")
        AT.LayoutPage(pg)
    end, IsProfile, BTN_W, "This profile")
    AT.Tooltip(delRow.button, "Delete", "Deletes this profile for every character. Press twice.")
    MOD.Stamp(delRow, m, "barRestoreDelete", nil, IsProfile)

    local b = BR()
    if b then
        b.Watch(function()
            if pg:IsVisible() then AT.LayoutPage(pg) end
        end)
    end
end

MOD.Register({
    key = "barRestore",
    switch = "barRestore",
    name = "Action Bar Restore",
    desc = "Saves your action bars per spec and as named profiles, and puts them back when the game loads them empty.",
    foreverOnly = true,
    -- three buttons with an arrow coming down into them
    glyph = function(box)
        MOD.DrawGlyph(box, { { 2, 12, 4, 4, "arc" }, { 8, 12, 4, 4, "arc" }, { 14, 12, 4, 4, "arc" },
            { 2, 18, 16, 1, "dim" } })
        local down = AT.MakeChevron(box)
        down:SetDir("down")
        down:SetColor(COL.arc)
        down:SetPoint("CENTER", box, "TOPLEFT", 17, -11)
    end,
    isOn = function() local b = BR() return b ~= nil and b.IsOn() end,
    setOn = function(v)
        local b = BR()
        if b then b.SetOn(v) end
        Options.RefreshAll()
    end,
    build = function(pg, m) Build(pg, m) end,
})
