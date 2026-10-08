-- AD_ImportArcUIOptions: the "Import from Arc UI" card on the New Layout page and its window.
-- It shows the plan's counts and a tree of what can come over (character, spec, profile,
-- then each group, the free icons, the bars, the reminders and the global look), with a
-- checkbox on every row; Import copies the checked parts through ImportArcUI.Apply.
-- UI\AD_NewLayout.lua draws the card this file registers. Retail only, and nothing here
-- runs at login: the plan is built when the window opens.
local ADDON, NS = ...
if NS.IsForever == true then return end

local Options = NS.Options
if not Options then return end

local IW = {}
Options.ImportArcUI = IW

IW.DROP_LINES = 40
IW.NEED_LINES = 8
IW.INDENT = 16
IW.ROW_H = 20

local win, page, plan, status, treeSec
local lines, drops, needs = {}, {}, {}
-- picks: the checked leaf units; open: the unfolded tree nodes; visible: the rows
-- on show this refresh, top to bottom; treeRows: the pooled row frames
local picks, open, visible, treeRows = {}, {}, {}, {}

-- A wrapped text row kept by key, so a refresh only sets the text.
local function Line(pg, key, visibleFn)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(pg, 18, visibleFn)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -2)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row._minH = 18
    row._sync = function()
        local w = pg:GetWidth() or 0
        if w < 60 then pg._sizeUnresolved = true return end
        fs:SetWidth(w - 36)
        local want = math.max(row._minH, math.floor((fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    row.fs = fs
    if key then lines[key] = fs end
    return row
end

local function Sum(t)
    local n = 0
    for _, v in pairs(t or {}) do n = n + v end
    return n
end

local function ListOf(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. t[k] end
    return table.concat(parts, ", ")
end

-- The leaf units under a node (a leaf is its own).
local function Leaves(node, out)
    out = out or {}
    if node.unit then out[#out + 1] = node return out end
    for _, ch in ipairs(node.children or {}) do Leaves(ch, out) end
    return out
end

-- "on" / "off" / "mixed" from the node's leaves still to import; "done" when none is left.
local function NodeState(node)
    local IA = NS.ImportArcUI
    local on, off = 0, 0
    for _, leaf in ipairs(Leaves(node)) do
        if not (IA and IA.UnitDone(leaf.unit)) then
            if picks[leaf.unit] then on = on + 1 else off = off + 1 end
        end
    end
    if on == 0 and off == 0 then return "done" end
    if off == 0 then return "on" end
    if on == 0 then return "off" end
    return "mixed"
end

local function SetNode(node, on)
    local IA = NS.ImportArcUI
    for _, leaf in ipairs(Leaves(node)) do
        if not (IA and IA.UnitDone(leaf.unit)) then picks[leaf.unit] = on or nil end
    end
end

-- The rows on show: every open node's children, top to bottom.
local function Flatten()
    visible = {}
    local function Walk(node, depth)
        visible[#visible + 1] = { node = node, depth = depth }
        if node.children and open[node.id] then
            for _, ch in ipairs(node.children) do Walk(ch, depth + 1) end
        end
    end
    for _, node in ipairs(plan and plan.tree or {}) do Walk(node, 0) end
end

function IW.Toggle(node)
    if node.unit then
        local IA = NS.ImportArcUI
        if IA and IA.UnitDone(node.unit) then return end
        picks[node.unit] = (not picks[node.unit]) or nil
    else
        SetNode(node, NodeState(node) ~= "on")
    end
    IW.Refresh()
end

function IW.Unfold(node)
    if not node.children then return end
    open[node.id] = (not open[node.id]) or nil
    IW.Refresh()
end

-- Pooled tree rows, made inside the tree's section as the plan needs them.
local function TreeRow(i)
    local row = treeRows[i]
    if row then return row end
    local AT, COL = NS.AT, NS.AT.COL
    local saved = page._curSection
    page._curSection = treeSec
    row = AT.AddRow(page, IW.ROW_H, function() return visible[i] ~= nil end)
    page._curSection = saved
    row.arrow = AT.MakeChevron(row)
    row.box = AT.MakeCheckbox(row)
    row.fs = row:CreateFontString(nil, "OVERLAY")
    row.fs:SetFont(NS.AT.FONT, 11, "")
    row.fs:SetJustifyH("LEFT")
    row.fs:SetWordWrap(false)
    row.fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function()
        local v = visible[i]
        if not v then return end
        if v.node.children then IW.Unfold(v.node) else IW.Toggle(v.node) end
    end)
    row.box:SetScript("OnClick", function()
        local v = visible[i]
        if v then IW.Toggle(v.node) end
    end)
    row:HookScript("OnEnter", function() row.box:SetHover(true) end)
    row:HookScript("OnLeave", function() row.box:SetHover(false) end)
    row.box:HookScript("OnEnter", function() row.box:SetHover(true) end)
    row.box:HookScript("OnLeave", function() row.box:SetHover(false) end)
    treeRows[i] = row
    return row
end

local function PaintTree()
    local AT, COL = NS.AT, NS.AT.COL
    local IA = NS.ImportArcUI
    Flatten()
    for i, v in ipairs(visible) do
        local row = TreeRow(i)
        local node = v.node
        local x = 8 + v.depth * IW.INDENT
        row.arrow:ClearAllPoints()
        if node.children then
            row.arrow:SetPoint("LEFT", row, "LEFT", x, 0)
            row.arrow:SetDown(open[node.id] == true)
            row.arrow:SetColor(COL.dim)
            row.arrow:Show()
            x = x + 16
        else
            row.arrow:Hide()
        end
        row.box:ClearAllPoints()
        row.box:SetPoint("LEFT", row, "LEFT", x, 0)
        row.fs:ClearAllPoints()
        row.fs:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
        row.fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        local done = node.unit and IA and IA.UnitDone(node.unit)
        local state = node.unit and (done and "done" or (picks[node.unit] and "on" or "off")) or NodeState(node)
        row.box:SetOn(state ~= "off")
        row.box.check:SetAlpha((state == "mixed" or state == "done") and 0.45 or 1)
        row.box:SetAlpha(state == "done" and 0.6 or 1)
        local label = node.label or "?"
        if state == "done" then label = label .. (node.unit and "  (imported)" or "  (all imported)") end
        row.fs:SetText(label)
        local c = (state == "done") and COL.dim or (node.children and COL.ink or COL.dim)
        if node.unit and state ~= "done" then c = COL.ink end
        row.fs:SetTextColor(c[1], c[2], c[3])
    end
    for i = #visible + 1, #treeRows do treeRows[i]:Hide() end
end

function IW.Build()
    if win then return end
    local AT, COL = NS.AT, NS.AT.COL
    win = AT.CreateWindow("ArcAurasImportArcUI", {
        w = 560, h = 640, minW = 440, minH = 420, maxW = 960, maxH = 1100,
        title = NS.AT.Brand("Arc", " Auras"),
        onResize = function() if page then AT.LayoutPage(page) end end,
    })
    page = AT.NewPage(win)
    AT.MakeScrollable(page)
    page:SetPoint("TOPLEFT", 8, -38)
    page:SetPoint("BOTTOMRIGHT", -8, 8)
    page:Show()

    AT.Section(page, "Import from Arc UI")
    AT.RowDesc(page, "Copies what you pick from your Arc UI setup into Arc Auras: groups with their icons and options, free icons, bars, the Cooldown Reminder and the global look. Arc UI's own data is only read, never changed, so you can keep using it or go back to it.", 34)
    Line(page, "chars")
    Line(page, "layouts")
    Line(page, "groups")
    Line(page, "icons")
    Line(page, "bars")
    Line(page, "skipped")

    AT.Section(page, "What to import")
    treeSec = page._curSection
    AT.RowDesc(page, "Your characters, their specs and profiles. Ticked by default: this character's active profiles, bars, reminders and global look. An account-wide group layout shared by several profiles becomes one Arc Auras layout; each ticked profile adds its own icons to it. Parts already imported stay ticked and dim.", 44)

    AT.Section(page, "Only the game can answer these", { visibleFn = function() return needs[1] ~= nil end })
    for i = 1, IW.NEED_LINES do
        local row = Line(page, nil, function() return needs[i] ~= nil end)
        needs["fs" .. i] = row.fs
    end

    AT.Section(page, "Left out", { visibleFn = function() return drops[1] ~= nil end })
    AT.RowDesc(page, "Arc UI settings with no home in Arc Auras, with how many records carried each. Everything else copies.", 20,
        function() return drops[1] ~= nil end)
    for i = 1, IW.DROP_LINES do
        local row = Line(page, nil, function() return drops[i] ~= nil end)
        drops["fs" .. i] = row.fs
    end
    Line(page, "more", function() return lines.more._text ~= nil and lines.more._text ~= "" end)

    AT.Section(page, nil)
    local actions = AT.RowActions(page, {
        { label = "Import selected", w = 130, onClick = function() IW.DoImport() end,
            visibleFn = function() return plan ~= nil and not (NS.ImportArcUI and NS.ImportArcUI.Done(plan)) end },
        { label = "Select all", w = 90, quiet = true, onClick = function() IW.SelectAll(true) end,
            visibleFn = function() return plan ~= nil end },
        { label = "Select none", w = 96, quiet = true, onClick = function() IW.SelectAll(false) end,
            visibleFn = function() return plan ~= nil end },
        { label = "Close", w = 80, quiet = true, onClick = function() win:Hide() end },
    }, "left")
    IW.actions = actions
    status = Line(page, "status").fs
    status:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    AT.LayoutPage(page)
end

function IW.SelectAll(on)
    for _, node in ipairs(plan and plan.tree or {}) do SetNode(node, on) end
    IW.Refresh()
end

local function PickedCount()
    local n = 0
    for _ in pairs(picks) do n = n + 1 end
    return n
end

-- Fills the rows from the plan and lays the page out.
function IW.Refresh()
    if not win then return end
    local IA = NS.ImportArcUI
    for i = 1, IW.DROP_LINES do drops[i] = nil end
    for i = 1, IW.NEED_LINES do needs[i] = nil end
    local function Set(key, text)
        local fs = lines[key]
        if fs then fs:SetText(text or "") fs._text = text end
    end
    if not plan then
        Set("chars", "Arc UI's saved data was not found. Log in once with Arc UI on, then come back.")
        Set("layouts", "") Set("groups", "") Set("icons", "") Set("bars", "") Set("skipped", "") Set("more", "")
    else
        local c = plan.counts
        Set("chars", ("Characters: %d.  Specs: %d.  Profiles: %d."):format(c.chars, c.specs, c.profiles))
        Set("layouts", ("Layouts: %d (%d account-wide, each made once; %d follow talents, %d kept dormant as spare profiles)."):format(c.layouts, c.globalLayouts or 0, c.talentLayouts, c.dormant))
        Set("groups", ("Groups: %d.  Free icons: %d.  Reminder groups: %d with %d reminders."):format(c.groups, c.freeIcons, c.reminderGroups, c.reminders))
        Set("icons", ("Icons: %d (%s)."):format(c.cdmIcons + c.arcIcons, ListOf(c.icons)))
        Set("bars", ("Bars: %d (%s)."):format(Sum(c.bars), ListOf(c.bars)))
        Set("skipped", ("Left out: %d icons and %d bars (the reasons are listed below)."):format(c.iconsDropped, c.barsDropped))
        local cov = plan.coverage
        local ks = {}
        for k in pairs(cov.ingame) do ks[#ks + 1] = k end
        table.sort(ks)
        for i, k in ipairs(ks) do
            if i > IW.NEED_LINES then break end
            needs[i] = k
            needs["fs" .. i]:SetText(("%s: %d"):format(k, cov.ingame[k]))
        end
        local list = {}
        for k, d in pairs(cov.dropped) do list[#list + 1] = { k = k, n = d.n, why = d.why } end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.k < b.k
        end)
        for i, d in ipairs(list) do
            if i > IW.DROP_LINES then break end
            drops[i] = d.k
            local tag, path = d.k:match("^([%w.]+):(.*)$")
            drops["fs" .. i]:SetText(("%s %s (%d): %s"):format(tag or "", path or d.k, d.n, d.why))
        end
        if #list > IW.DROP_LINES then
            Set("more", ("... and %d more."):format(#list - IW.DROP_LINES))
        else
            Set("more", "")
        end
    end
    PaintTree()
    if not plan then
        status:SetText("")
    elseif IA and IA.Done(plan) then
        status:SetText(("Everything is imported (%d parts). Nothing runs twice."):format(IA.DoneCount()))
    else
        local left = IA and IA.Remaining(plan) or 0
        local total = plan.counts.units or 0
        status:SetText(("%d of %d parts ticked; %d imported before. Import makes new layouts; nothing you have in Arc Auras is touched.")
            :format(PickedCount(), total, total - left))
    end
    NS.AT.LayoutPage(page)
end

function IW.DoImport()
    local IA = NS.ImportArcUI
    if not (IA and plan) then return end
    local lock = rawget(_G, "InCombatLockdown")
    if lock and lock() then
        status:SetText("Not in combat.")
        return
    end
    if PickedCount() == 0 then
        status:SetText("Tick what should come over first.")
        return
    end
    local res, err = IA.Apply(plan, picks)
    if not res then
        status:SetText(err or "The import did not run.")
        return
    end
    picks = {}
    IW.Refresh()
    if Options.RefreshAll then Options.RefreshAll() end
    status:SetText(("Imported %d parts: %d layouts, %d groups, %d icons, %d bars, %d reminders. %d parts left to import.")
        :format(res.units, res.layouts, res.groups, res.icons, res.bars, res.reminders, IA.Remaining(plan)))
    local first = res.firstLayoutId and NS.Store.Get(res.firstLayoutId)
    if first and Options.OpenLayout and IA.Remaining(plan) == 0 then
        win:Hide()
        Options.OpenLayout(first)
    end
end

function IW.Open()
    IW.Build()
    local IA = NS.ImportArcUI
    plan = IA and IA.Preview() or nil
    picks = IA and plan and IA.DefaultPicks(plan) or {}
    open = {}
    local me = IA and IA.CurrentChar()
    for _, node in ipairs(plan and plan.tree or {}) do
        if node.charKey == me then
            open[node.id] = true
            for _, spec in ipairs(node.children) do
                if spec.kind == "spec" or spec.kind == "shared" then open[spec.id] = true end
                for _, p in ipairs(spec.children or {}) do
                    if p.tag == "active" then open[p.id] = true end
                end
            end
        end
    end
    win:Show()
    IW.Refresh()
end

-- The card's line: what the import does, and how much of it is done so far.
function IW.CardDesc()
    local IA = NS.ImportArcUI
    local base = "Pick which Arc UI groups, icons, bars and looks come into Arc Auras."
    local done = IA and IA.DoneCount() or 0
    if done == 0 then return base end
    if plan then
        local left = IA.Remaining(plan)
        if left == 0 then return base .. (" All %d parts imported."):format(done) end
        return base .. (" %d parts imported, %d left."):format(done, left)
    end
    return base .. (" %d parts imported so far."):format(done)
end

-- The card's picture: an Arc UI square handing its icons to an Arc Auras one.
function IW.DrawCard(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local NL = NS.NewLayout
    local W, H = NL.STAGE_W, NL.STAGE_H
    local function Box(x, y, c)
        local f = CreateFrame("Frame", nil, stage, "BackdropTemplate")
        f:SetSize(44, 36)
        f:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -y)
        AT.Skin(f, COL.box, c)
        for i = 1, 3 do
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(c[1], c[2], c[3], 0.9)
            t:SetSize(9, 9)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 5 + (i - 1) * 12, -6)
        end
        return f
    end
    Box(W / 2 - 66, (H - 36) / 2, COL.dim)
    Box(W / 2 + 22, (H - 36) / 2, COL.arc)
    local head = AT.MakeChevron(stage)
    head:SetDir("right")
    head:SetColor(COL.arc)
    head:SetScale(2)
    head:SetPoint("CENTER", stage, "TOPLEFT", (W / 2) / 2, -(H / 2) / 2)
end

if NS.NewLayout and NS.NewLayout.AddOwnCard then
    IW.entry = {
        title = "Import from Arc UI",
        desc = "Pick which Arc UI groups, icons, bars and looks come into Arc Auras.",
        draw = IW.DrawCard,
        pick = function() IW.Open() end,
        -- the card is read when the page fills: refresh its line then
        avail = function()
            local ok = NS.ImportArcUI ~= nil and NS.ImportArcUI.Available()
            if ok then IW.entry.desc = IW.CardDesc() end
            return ok
        end,
    }
    NS.NewLayout.AddOwnCard(IW.entry)
end
