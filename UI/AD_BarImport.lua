-- AD_BarImport: the "From your action bars" picker and its Store wiring.
-- Options.BarImport is the whole feature; AD_Options / AD_NewLayout only call
-- its OpenForGroup / OpenForStarter entry points.
-- Never opens or creates in combat: Core\AD_BarScan.lua already refuses the
-- scan there, and a fresh group full of icons is not a mid-fight action.
local ADDON, NS = ...
local Store = NS.Store
local AT = NS.AT
local COL = AT.COL

local Options = NS.Options
if not Options then return end

local BI = {}
Options.BarImport = BI

local CELL, GAP, COLS = 32, 4, 11
local PITCH = CELL + GAP

local function IconName(e)
    if e.kind == "item" then
        return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)) or ("Item " .. e.id)
    end
    return (C_Spell.GetSpellName and C_Spell.GetSpellName(e.id)) or ("Spell " .. e.id) -- raw-id: a bar being imported
end

-- Every spell/item icon already in a layout, free or in a group: what the
-- picker starts unticked against.
local function TrackedSet(layout)
    local set = {}
    if not layout then return set end
    local function Mark(rec)
        local d = rec.driver
        if not d then return end
        if rec.kind == "spell" and d.spellID then
            set["spell:" .. d.spellID] = true
        elseif rec.kind == "item" and d.itemID then
            set["item:" .. d.itemID] = true
        end
    end
    local groups, freeIcons = Store.ChildrenOf(layout)
    for _, ic in ipairs(freeIcons) do Mark(ic) end
    for _, g in ipairs(groups) do
        for _, ic in ipairs(Store.IconsOf(g)) do Mark(ic) end
    end
    return set
end

-- The scan, joined with this layout's already-tracked spells/items: everything
-- starts ticked except those, since they would just duplicate an icon that's
-- already there. nil + a reason only when the scan itself refuses (combat).
function BI.Rows(layoutId)
    local entries, reason = NS.BarScan.Read()
    if not entries then return nil, reason end
    local tracked = TrackedSet(Store.Get(layoutId))
    local rows = {}
    for _, e in ipairs(entries) do
        local isTracked = tracked[e.kind .. ":" .. e.id] == true
        rows[#rows + 1] = { entry = e, tracked = isTracked, ticked = not isTracked }
    end
    return rows
end

function BI.SetAllTicked(rows, on)
    for _, r in ipairs(rows) do r.ticked = on and true or false end
end

-- Grows the group by whole rows (Store.GridEdge, the same arrow the panel's
-- own grow buttons use) until it has room for addCount more icons, or until
-- the grid hits its cap and GridEdge itself refuses.
local function EnsureCapacity(groupId, addCount)
    if addCount <= 0 then return end
    local g = Store.Get(groupId)
    if not g then return end
    local rows = Store.Resolve(g, "arrangement", "rows") or 1
    local cols = math.max(1, Store.Resolve(g, "arrangement", "cols") or 6)
    local live = 0
    for _, rec in ipairs(Store.IconsOf(g)) do
        if Store.IsLoaded(rec) then live = live + 1 end
    end
    while (rows * cols - live) < addCount do
        if not Store.GridEdge(groupId, "bottom", true) then break end
        rows = rows + 1
    end
end

-- Creates every ticked row into one group (Store.GroupTakes decides; an aura
-- or reminder group refuses, so nothing is created). New icons get no cell,
-- so they take the first free ones the next render, which is why capacity is
-- grown first.
function BI.CreateInto(rows, destGroupId)
    local g = Store.Get(destGroupId)
    if not g or g.type ~= "group" or not Store.GroupTakes(g, "spell") then
        return 0
    end
    local ticked = {}
    for _, r in ipairs(rows) do
        if r.ticked then ticked[#ticked + 1] = r end
    end
    EnsureCapacity(destGroupId, #ticked)
    local created = 0
    for _, r in ipairs(ticked) do
        local e = r.entry
        local driver = (e.kind == "item") and { itemID = e.id } or { spellID = e.id }
        if Store.NewIcon(e.kind, driver, destGroupId, g.layoutId, IconName(e)) then
            created = created + 1
        end
    end
    return created
end

-- The Starter template split: ticked Action Bar 1 entries go to the Cooldowns
-- group, every other bar's (including the form/stealth page) to Utility,
-- nothing goes to Buffs.
function BI.CreateStarter(rows, cooldownGroupId, utilityGroupId)
    local cdRows, utilRows = {}, {}
    for _, r in ipairs(rows) do
        if r.entry.bar == "Action Bar 1" then cdRows[#cdRows + 1] = r
        else utilRows[#utilRows + 1] = r end
    end
    local a = BI.CreateInto(cdRows, cooldownGroupId)
    local b = BI.CreateInto(utilRows, utilityGroupId)
    return a + b
end

-- One icon cell: the art, a corner checkbox, and a tooltip noting when it is
-- already in the layout. The whole cell (not just the checkbox) toggles it,
-- so a shaky click still lands.
local function MakeCell(parent, row, onToggle)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(CELL, CELL)
    AT.Skin(b, COL.well, COL.line)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 2, -2)
    b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local e = row.entry
    if e.kind == "item" then
        b.tex:SetTexture((C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)) or 134400)
    else
        b.tex:SetTexture((C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id)) or 134400) -- raw-id: a bar being imported
    end
    b.cb = AT.MakeCheckbox(b)
    b.cb:SetPoint("BOTTOMRIGHT", 2, -2)
    function b.Paint()
        b.cb:SetOn(row.ticked)
        local c = row.ticked and COL.arc or COL.line
        b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    local function Toggle()
        row.ticked = not row.ticked
        b.Paint()
        if onToggle then onToggle() end
    end
    b:SetScript("OnClick", Toggle)
    b.cb:SetScript("OnClick", Toggle)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if e.kind == "item" and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(e.id)
        elseif GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(e.id) -- raw-id: a bar being imported
        end
        if row.tracked then
            GameTooltip:AddLine("Already in this layout", COL.dim[1], COL.dim[2], COL.dim[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end)
    b.Paint()
    row._cell = b
    return b
end

-- One section per bar label; rows already come out of BI.Rows in bar order,
-- so a run of identical labels is always contiguous and becomes one section.
local function BuildGrid(pg, rows, onToggle)
    local i = 1
    while i <= #rows do
        local bar = rows[i].entry.bar
        AT.Section(pg, bar)
        local hostRow
        local col = 0
        local j = i
        while j <= #rows and rows[j].entry.bar == bar do
            if col == 0 then hostRow = AT.AddRow(pg, PITCH) end
            local cell = MakeCell(hostRow, rows[j], onToggle)
            cell:SetPoint("TOPLEFT", col * PITCH, 0)
            col = (col + 1) % COLS
            j = j + 1
        end
        i = j
    end
end

-- Builds and shows the picker window fresh each time; any window from an
-- earlier open just gets hidden, so only one is ever on screen.
local function OpenPicker(rows, onCreate)
    if BI._win then BI._win:Hide() end
    local win = AT.CreateWindow(nil, {
        w = 460, h = 520, minW = 420, minH = 320, resizable = false,
        title = AT.Brand("From", " Your Action Bars"),
    })
    BI._win = win
    local pg = AT.NewPage(win)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 10, -40)
    pg:SetPoint("BOTTOMRIGHT", -10, 40)
    pg:Show()

    AT.RowDesc(pg, "Untick spells without a cooldown - there is no reliable way to check that here.", 28)
    if #rows == 0 then
        AT.RowDesc(pg, "Nothing found on your action bars.", 20)
    end

    local createBtn
    local function SyncCount()
        local n = 0
        for _, r in ipairs(rows) do if r.ticked then n = n + 1 end end
        createBtn.fs:SetText(n == 0 and "Create" or ("Create " .. n .. (n == 1 and " Icon" or " Icons")))
        createBtn:SetEnabled(n > 0)
    end
    BuildGrid(pg, rows, SyncCount)

    local btnRow = AT.AddRow(pg, 30)
    local allBtn = AT.MakeQuietButton(btnRow, "Select All", 84)
    allBtn:SetPoint("LEFT", 10, 0)
    allBtn:SetScript("OnClick", function()
        BI.SetAllTicked(rows, true)
        for _, r in ipairs(rows) do if r._cell then r._cell.Paint() end end
        SyncCount()
    end)
    local noneBtn = AT.MakeQuietButton(btnRow, "Select None", 92)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    noneBtn:SetScript("OnClick", function()
        BI.SetAllTicked(rows, false)
        for _, r in ipairs(rows) do if r._cell then r._cell.Paint() end end
        SyncCount()
    end)
    createBtn = AT.MakeSmallButton(btnRow, "Create", 120)
    createBtn:SetPoint("RIGHT", -10, 0)
    createBtn.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    createBtn:SetScript("OnClick", function()
        AT.CloseDropdown()
        onCreate(rows)
        win:Hide()
    end)

    SyncCount()
    AT.LayoutPage(pg)
    win:Show()
end

-- Group-tab Create toggle and the group editor's own "+ From Action Bars"
-- button: one destination group, cooldown groups only.
function BI.OpenForGroup(group)
    if InCombatLockdown() then return end
    if not (group and Store.GroupTakes(group, "spell")) then return end
    local rows, reason = BI.Rows(group.layoutId)
    if not rows then return end
    OpenPicker(rows, function(pickedRows) BI.CreateInto(pickedRows, group.id) end)
end

-- The Starter card's second button: Action Bar 1 to Cooldowns, everything
-- else to Utility, nothing to Buffs.
function BI.OpenForStarter(layoutRec)
    if InCombatLockdown() then return end
    if not layoutRec then return end
    local starterRows = Store.STARTER_ROWS
    local cdId, utilId
    for i, mid in ipairs(layoutRec.members or {}) do
        local row = starterRows and starterRows[i]
        if row and row.name == "Cooldowns" then cdId = mid end
        if row and row.name == "Utility" then utilId = mid end
    end
    if not (cdId and utilId) then return end
    local rows, reason = BI.Rows(layoutRec.id)
    if not rows then return end
    OpenPicker(rows, function(pickedRows) BI.CreateStarter(pickedRows, cdId, utilId) end)
end
