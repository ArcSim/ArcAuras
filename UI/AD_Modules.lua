-- AD_Modules: the Modules page, one card per module, and each module's own page;
-- the module registry and the one-version "new" marks (Options.NewBadge) live here.
-- AD_Options owns the pane and its header: it calls Fill as the window builds and
-- Refresh whenever the pane shows.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT = NS.AT
local COL = AT.COL
local Store = NS.Store

local MOD = { list = {}, byKey = {}, pages = {}, cards = {} }
Options.Modules = MOD

MOD.CARD_H, MOD.GAP, MOD.MIN_W = 124, 12, 240
-- the status word while a module is on: the Import / Export page's ok green
MOD.ON = { 0.35, 0.85, 0.45 }
MOD.LINE = "Extra features for the whole addon. Switch one on to use it; its settings open from its card."

-- spec = { key, name, desc, glyph, isOn(), setOn(v), build(pg, spec), available(),
-- unavailable, moved, switch }. glyph: bars for DrawGlyph, or a function(box).
-- unavailable: the card's line while available() says no. moved: where its rows
-- used to live, shown while the card wears its mark. switch: the setting key of the
-- page's first row. foreverOnly: a module retail has no use for never registers
-- there. The page reads the list once as the window builds, so a module
-- registers at load.
function MOD.Register(spec)
    if type(spec) ~= "table" or not spec.key or MOD.byKey[spec.key] then return end
    if spec.foreverOnly and NS.IsForever ~= true then return end
    MOD.list[#MOD.list + 1] = spec
    MOD.byKey[spec.key] = spec
end

function MOD.Available(m)
    return (not m.available) or m.available() == true
end

function MOD.Always() return true end

-- The one-version marks

-- The version a mark lasts: the base version, so a hotfix (1.6.0.a) keeps its
-- release's marks, as What's New does.
function MOD.Version()
    local CL = NS.Changelog
    local v = CL and CL.BaseVersion and CL.BaseVersion()
    if type(v) == "string" and v ~= "" and v ~= "?" then return v end
    v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    if type(v) == "string" and v ~= "" then return (v:gsub("%.%a+$", "")) end
end

-- The mark's text while it is up: from the version the player first sees it in
-- (Store.UI().newSeen[key]) until they open what it marks (Options.ClearNew) or
-- the addon updates, else nil. peek asks without marking it seen, for a hint
-- about marks nobody has drawn yet.
function Options.NewBadge(key, peek)
    local ver = MOD.Version()
    local u = Store.UI()
    if not (key and ver and u) then return nil end
    if u.newCleared and u.newCleared[key] then return nil end
    local seen = u.newSeen and u.newSeen[key]
    if seen == nil then
        if not peek then
            u.newSeen = u.newSeen or {}
            u.newSeen[key] = ver
        end
        return "NEW"
    end
    if seen == ver then return "NEW" end
    return nil
end

-- AT.TabRow's badges from { [tab name] = key }: the tabs whose mark is up, or nil.
function Options.NewBadges(map, peek)
    local out
    for name, key in pairs(map or {}) do
        local b = Options.NewBadge(key, peek)
        if b then
            out = out or {}
            out[name] = b
        end
    end
    return out
end

-- Opening what a mark marks takes it down for good: a tab, a sub-tab, a
-- module's page. The version it was first seen in stays on record.
function Options.ClearNew(key)
    local u = Store.UI()
    if not (key and u) then return end
    u.newCleared = u.newCleared or {}
    if u.newCleared[key] then return end
    u.newCleared[key] = true
    local ver = MOD.Version()
    if ver then
        u.newSeen = u.newSeen or {}
        u.newSeen[key] = u.newSeen[key] or ver
    end
end

function MOD.NewKey(m) return "module:" .. m.key end

-- A card whose mark is up and that the Modules page has not shown yet: the
-- rail's Modules row shows a dot until the page opens.
function MOD.AnyNew()
    local u = Store.UI()
    for _, m in ipairs(MOD.list) do
        local key = MOD.NewKey(m)
        if Options.NewBadge(key, true) and not (u and u.newSeen and u.newSeen[key]) then return true end
    end
    return false
end

-- The rail's dot

function MOD.Round(row, tex)
    local mask = row.CreateMaskTexture and row:CreateMaskTexture()
    if not mask then return end
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

-- A round cyan dot at the row's right with a soft ring behind it, while a
-- module card still wears its mark.
function MOD.PaintRailDot(row)
    if not row then return end
    -- kept, so the page can take the dot down the moment it opens
    MOD.railRow = row
    if not row._adDot then
        local dot = row:CreateTexture(nil, "OVERLAY")
        dot:SetSize(6, 6)
        dot:SetPoint("RIGHT", -10, 0)
        dot:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        local halo = row:CreateTexture(nil, "ARTWORK")
        halo:SetSize(12, 12)
        halo:SetPoint("CENTER", dot, "CENTER", 0, 0)
        halo:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.18)
        MOD.Round(row, dot)
        MOD.Round(row, halo)
        row._adDot, row._adHalo = dot, halo
        AT.Tooltip(row, "Modules", function()
            if MOD.AnyNew() then return "Something here is new in this version." end
        end)
    end
    local on = MOD.AnyNew()
    row._adDot:SetShown(on)
    row._adHalo:SetShown(on)
end

-- Cards

-- A glyph: flat bars on a 20-unit grid centred in its 34 box, each
-- { x, y, w, h, color key, degrees }, in whole units.
function MOD.DrawGlyph(box, bars)
    for _, b in ipairs(bars) do
        local c = COL[b[5]] or COL.faint
        local t = box:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:SetSize(b[3], b[4])
        t:SetPoint("TOPLEFT", box, "TOPLEFT", 7 + b[1], -(7 + b[2]))
        if b[6] then t:SetRotation(math.rad(b[6])) end
    end
end

-- The Settings button: raised with a cyan label while its module is on, quiet
-- while it is off, the theme's hover either way.
function MOD.PaintButton(b)
    local fill, edge, ink, a = COL.btn, COL.steel, COL.arc, 1
    if b._hot then
        fill, edge, ink = COL.btnHover, COL.arc, COL.ink
    elseif not b._on then
        edge, ink, a = COL.line2, COL.dim, 0
    end
    b:SetBackdropColor(fill[1], fill[2], fill[3], a)
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    b.fs:SetTextColor(ink[1], ink[2], ink[3])
end

-- The card's switch writes the module's own setting, the one its page's first
-- row shows.
function MOD.Flip(c)
    AT.CloseDropdown()
    local m = c._mod
    if not MOD.Available(m) then return end
    local v = not m.isOn()
    m.setOn(v)
    -- a switch flipped is the card seen to: its mark goes
    Options.ClearNew(MOD.NewKey(m))
    PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                 or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    if MOD.listPage then AT.LayoutPage(MOD.listPage) end
end

function MOD.MakeCard(parent, m)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetHeight(MOD.CARD_H)
    AT.Skin(c, COL.panel, COL.line)
    c._mod = m
    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetSize(34, 34)
    box:SetPoint("TOPLEFT", 10, -10)
    AT.Skin(box, COL.well, COL.line2)
    if type(m.glyph) == "function" then m.glyph(box)
    elseif type(m.glyph) == "table" then MOD.DrawGlyph(box, m.glyph) end
    c.glyph = box
    c.name = c:CreateFontString(nil, "OVERLAY")
    c.name:SetFont(AT.FONT, 13, "")
    c.name:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, -3)
    c.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    c.name:SetText(m.name)
    -- the search reads a card by its name
    c._colLabel = c.name
    c.state = c:CreateFontString(nil, "OVERLAY")
    c.state:SetFont(AT.FONT, 9, "")
    c.state:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5)
    c.new = AT.NewChip(c)
    c.new:SetPoint("LEFT", c.name, "RIGHT", 6, 0)
    c.check = AT.MakeCheckbox(c)
    c.check:SetPoint("TOPRIGHT", -10, -18)
    c.check:SetScript("OnClick", function() MOD.Flip(c) end)
    c.check:HookScript("OnEnter", function() c.check:SetHover(true) end)
    c.check:HookScript("OnLeave", function() c.check:SetHover(false) end)
    c.desc = c:CreateFontString(nil, "OVERLAY")
    c.desc:SetFont(AT.FONT, 11, "")
    c.desc:SetPoint("TOPLEFT", 10, -52)
    c.desc:SetPoint("TOPRIGHT", -10, -52)
    c.desc:SetJustifyH("LEFT")
    c.desc:SetJustifyV("TOP")
    c.desc:SetWordWrap(true)
    c.desc:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    c.set = AT.MakeSmallButton(c, "Settings", 80)
    c.set:SetPoint("BOTTOMLEFT", 10, 10)
    c.set:SetScript("OnEnter", function(s) s._hot = true MOD.PaintButton(s) end)
    c.set:SetScript("OnLeave", function(s) s._hot = nil MOD.PaintButton(s) end)
    c.set:SetScript("OnClick", function()
        AT.CloseDropdown()
        Options.Select("modules", m.key)
    end)
    c.moved = c:CreateFontString(nil, "OVERLAY")
    c.moved:SetFont(AT.FONT, 10, "")
    c.moved:SetPoint("LEFT", c.set, "RIGHT", 8, 0)
    c.moved:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    return c
end

-- seen: the page is on screen, so a mark drawn now counts as seen.
function MOD.PaintCard(c, seen)
    local m = c._mod
    local avail = MOD.Available(m)
    local on = avail and m.isOn() == true
    local edge = on and COL.arcDeep or COL.line
    c:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    c.state:SetText(on and "ON" or "OFF")
    local sc = on and MOD.ON or COL.faint
    c.state:SetTextColor(sc[1], sc[2], sc[3])
    c.check:SetShown(avail)
    c.check:SetOn(on)
    c.desc:SetText((not avail and m.unavailable) or m.desc or "")
    local badge = Options.NewBadge(MOD.NewKey(m), not seen)
    if badge then c.new:SetText(badge) end
    c.new:SetShown(badge ~= nil)
    c.moved:SetText((badge and m.moved) or "")
    c.set._on = on
    MOD.PaintButton(c.set)
end

-- The narrowest a card may be with its name, mark and switch clear of each other.
function MOD.NeedW(cards)
    local need = MOD.MIN_W
    for _, c in ipairs(cards) do
        local fs = c.name
        local nw = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
            or fs:GetStringWidth() or 0
        local w = 10 + 34 + 10 + math.ceil(nw) + 12 + 18 + 10
        if c.new:IsShown() then w = w + 6 + (c.new:GetWidth() or 0) end
        if w > need then need = w end
    end
    return need
end

-- Two cards to a line when both fit, else one. A row sits 12 inside the page and
-- the cards start on the label margin, so a page w wide gives them w - 44.
function MOD.Grid(row, pageW, seen)
    for _, c in ipairs(row._cards) do MOD.PaintCard(c, seen) end
    if pageW < 60 then row._pg._sizeUnresolved = true return end
    local usable = math.floor(pageW - 44)
    local cols = (usable >= 2 * MOD.NeedW(row._cards) + MOD.GAP) and 2 or 1
    local cw = math.floor((usable - (cols - 1) * MOD.GAP) / cols)
    for i, c in ipairs(row._cards) do
        local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
        c:SetWidth(cw)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + col * (cw + MOD.GAP), -4 - r * (MOD.CARD_H + MOD.GAP))
    end
    local n = math.max(1, math.ceil(#row._cards / cols))
    local want = 4 + n * MOD.CARD_H + (n - 1) * MOD.GAP + 6
    if row._h ~= want then row._h = want row:SetHeight(want) end
end

-- The pane

-- "< Modules" on a module page's header, before the module's name.
function MOD.MakeBack(h)
    local b = CreateFrame("Button", nil, h)
    b:SetHeight(20)
    b:SetPoint("LEFT", 0, 0)
    b.chev = AT.MakeChevron(b)
    b.chev:SetDir("left")
    b.chev:SetPoint("LEFT", 0, 0)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(AT.FONT, 12, "")
    b.fs:SetPoint("LEFT", b.chev, "RIGHT", 2, 0)
    b.fs:SetText("Modules")
    local function paint(hot)
        local c = hot and COL.ink or COL.arc
        b.fs:SetTextColor(c[1], c[2], c[3])
        b.chev:SetColor(c)
    end
    paint(false)
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", function()
        AT.CloseDropdown()
        Options.Select("modules")
    end)
    b:Hide()
    MOD.back = b
    return b
end

-- m: the module whose page shows, nil for the list. The back link counts as a
-- header button, so a narrow pane shortens the name before it runs under.
function MOD.SetHeader(m)
    local h, b = MOD.header, MOD.back
    if not (h and b) then return end
    h.name:ClearAllPoints()
    if m then
        local tw = (b.fs.GetUnboundedStringWidth and b.fs:GetUnboundedStringWidth())
            or b.fs:GetStringWidth() or 0
        if type(tw) ~= "number" or tw <= 0 then tw = 46 end
        b:SetWidth(14 + math.ceil(tw) + 4)
        b:Show()
        h.name:SetPoint("LEFT", b, "RIGHT", 10, 0)
        h.name:SetText(m.name)
        h._btns = { b }
    else
        b:Hide()
        h.name:SetPoint("LEFT", 4, 0)
        h.name:SetText("Modules")
        h._btns = nil
    end
    Options.FitHeader(h)
end

function MOD.BuildPage(pane, m)
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 0, -36)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    MOD.pages[m.key] = pg
    if m.build then m.build(pg, m) end
    return pg
end

-- The list and every module's page, built into the host's pane once.
function MOD.Fill(pane, header, win)
    MOD.pane, MOD.header, MOD.win = pane, header, win
    header.name:SetText("Modules")
    header.chip1:Hide()
    header.chip2:Hide()
    MOD.MakeBack(header)
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 0, -36)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    pg:Show()
    MOD.listPage = pg
    AT.Section(pg, "Modules")
    MOD.listSec = pg._sections[#pg._sections]
    AT.RowDesc(pg, MOD.LINE, 20)
    local row = AT.AddRow(pg, MOD.CARD_H + 10)
    row._cards = {}
    for i, m in ipairs(MOD.list) do
Options.BuildYield()
        row._cards[i] = MOD.MakeCard(row, m)
        MOD.cards[i] = row._cards[i]
    end
    row._sync = function() MOD.Grid(row, pg:GetWidth() or 0, pg:IsVisible()) end
    MOD.grid = row
    Options.SEARCH_SRC = Options.SEARCH_SRC or {}
    Options.SEARCH_SRC.modules = { page = pg }
    for _, m in ipairs(MOD.list) do
        Options.BuildYield()
        MOD.BuildPage(pane, m)
    end
end

-- The list, or the module page ui.selId names; a key no module has shows the list.
function MOD.Refresh()
    local list = MOD.listPage
    if not list then return end
    local ui = Options.ui or {}
    local m = (ui.selType == "modules" and ui.selId and MOD.byKey[ui.selId]) or nil
    local show = (m and MOD.pages[m.key]) or list
    list:SetShown(show == list)
    for _, pg in pairs(MOD.pages) do pg:SetShown(pg == show) end
    MOD.SetHeader((show ~= list) and m or nil)
    -- a module's page opened takes its card's mark down
    if show ~= list and show:IsVisible() then Options.ClearNew(MOD.NewKey(m)) end
    -- the search's jump flashes its row on the page shown now
    if Options.SEARCH_SRC and Options.SEARCH_SRC.modules then
        Options.SEARCH_SRC.modules.page = show
    end
    AT.LayoutPage(show)
    -- the cards just drawn count as seen: the rail's dot goes with them
    if MOD.railRow then MOD.PaintRailDot(MOD.railRow) end
end

-- Search

-- Found by the search while the module is off; the jump then flashes the
-- module's switch, which the search finds by field and section. The label is
-- the row's own; t is the row's kind in schema words ("bool", "num", ...).
function MOD.Stamp(row, m, field, t, baseVis, isSwitch)
    local fs = row._colLabel or (row.button and row.button.fs)
    row._adMeta = { family = "modules", section = m.key, field = field,
        def = { label = fs and fs:GetText(), t = t,
            dep = (not isSwitch) and { field = m.switch, label = m.name } or nil },
        baseVis = baseVis or MOD.Always }
end

-- Every card (its words are its description), then each module's page the way
-- the index reads any page. fn(row, sec, sub, words, key).
function MOD.SearchWalk(fn)
    if not MOD.listPage then return end
    for _, c in ipairs(MOD.cards) do fn(c, MOD.listSec, nil, c._mod.desc, nil) end
    local walk = Options.Search and Options.Search.WalkPage
    if not walk then return end
    for _, m in ipairs(MOD.list) do
        local pg = MOD.pages[m.key]
        if pg then
            walk(pg, function(row, sec) fn(row, sec, m.name, nil, m.key) end)
        end
    end
end

-- The modules. Their rows moved here as they were: the same labels, tooltips,
-- setting keys and behaviour.

-- Core\AD_PressHighlight.lua reads these settings at every press.
function MOD.PressRows(pg, m)
    local PH = NS.PressHighlight
    local win = MOD.win
    local phOn = m.isOn
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Highlight icons when you press their button", m.isOn, m.setOn, nil,
        "When you press an action button, cast a spell through a macro or use a trinket, every icon of that ability on screen lights up for a moment: feedback on the icon you are watching, not the bar. Spells, items and trinkets; every rank of a spell counts as the same ability.")
    MOD.Stamp(row, m, m.switch, "bool", nil, true)
    row = AT.RowDropdown(pg, win, "Highlight lasts",
        function() return Store.GetSetting("pressMode") or "flash" end,
        function(v) Store.SetSetting("pressMode", (v == "hold") and "hold" or nil) end,
        function()
            return {
                { value = "flash", text = "A short flash" },
                { value = "hold", text = "While the button is held" },
            }
        end,
        phOn)
    MOD.Stamp(row, m, "pressMode", "enum")
    row = AT.RowSlider(pg, "Flash length (s)",
        function() return Store.GetSetting("pressDuration") or (PH and PH.DEFAULT_DURATION) or 0.1 end,
        function(v) Store.SetSetting("pressDuration", v) end,
        0.05, 0.5, 0.05, "%g", phOn)
    AT.Tooltip(row, "Flash length (s)",
        "How long a flash shows. While the button is held, the highlight also stays at least this long, so a click (which casts when you let go) still shows.")
    MOD.Stamp(row, m, "pressDuration", "num")
    row = AT.RowDropdown(pg, win, "Look",
        function() return Store.GetSetting("pressLook") or "fill" end,
        function(v)
            Store.SetSetting("pressLook", (v ~= "fill") and v or nil)
            Options.RefreshAll()
        end,
        function() return PH and PH.LOOKS or {} end,
        phOn)
    MOD.Stamp(row, m, "pressLook", "enum")
    row = AT.RowColor(pg, "Highlight color",
        function()
            local c = Store.GetSetting("pressColor") or (PH and PH.DEFAULT_COLOR) or { 1, 1, 0 }
            return { c[1], c[2], c[3] }
        end,
        function(c) Store.SetSetting("pressColor", { c[1], c[2], c[3] }) end,
        phOn)
    MOD.Stamp(row, m, "pressColor", "color")
    row = AT.RowSlider(pg, "Highlight opacity",
        function() return Store.GetSetting("pressAlpha") or (PH and PH.DEFAULT_ALPHA) or 0.45 end,
        function(v) Store.SetSetting("pressAlpha", v) end,
        0.05, 1, 0.05, true, phOn)
    MOD.Stamp(row, m, "pressAlpha", "num")
    local looked = function() return (Store.GetSetting("pressLook") or "fill") ~= "fill" end
    row = AT.RowToggle(pg, "Tint the look with the color",
        function() return Store.GetSetting("pressTint") == true end,
        function(v) Store.SetSetting("pressTint", v and true or nil) end,
        function() return phOn() and looked() end,
        "Colors the button-frame looks with the highlight color instead of their own gold and white.")
    MOD.Stamp(row, m, "pressTint", "bool", looked)
end

-- Core\AD_TooltipIDs.lua reads these as each tooltip builds.
function MOD.TooltipRows(pg, m)
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "IDs in tooltips", m.isOn, m.setOn, nil,
        "Appends an Arc ID block to game tooltips everywhere - spell, aura, item, toy, mount, currency, achievement and quest IDs, each with its icon ID (and the icon the button actually shows when that differs), the Cooldown Manager's cooldown ID for spells, auras and equipped trinkets, plus talent node / entry IDs on the talent tree. Works on action bars, buffs, bags and the spellbook, not just Arc Auras icons.")
    MOD.Stamp(row, m, m.switch, "bool", nil, true)
    -- The block's parts: each on unless switched off, stored only when off. An
    -- if, not `(not v) and false or nil`: that idiom always yields nil.
    for _, p in ipairs({
        { "Data", "Spell and item IDs", "The ID of what the tooltip shows: a spell, aura, item, toy, mount, currency, achievement or quest." },
        { "Icons", "Icon IDs", "The icon's file ID, the base icon when an override swapped the art, and the icon the button shows when that differs." },
        { "CDM", "Cooldown Manager IDs", "The Cooldown Manager's cooldown IDs for spells, auras and equipped trinkets: one line per category, with runs of IDs shortened to a range." },
        { "Talent", "Talent IDs", "Node, entry and definition IDs on talent tree buttons." },
    }) do
        local key = "tooltipIDs" .. p[1]
        row = AT.RowToggle(pg, p[2],
            function() return Store.GetSetting(key) ~= false end,
            function(v)
                if v then Store.SetSetting(key, nil) else Store.SetSetting(key, false) end
            end,
            m.isOn, p[3])
        MOD.Stamp(row, m, key, "bool")
    end
    -- Core\AD_TooltipIDs.lua: off unless picked
    row = AT.RowDropdown(pg, MOD.win, "Item level",
        function() return Store.GetSetting("tooltipItemLevel") or "off" end,
        function(v) Store.SetSetting("tooltipItemLevel", (v ~= "off") and v or nil) end,
        function()
            return {
                { value = "off", text = "Off" },
                { value = "name", text = "After the name" },
                { value = "under", text = "Under the name" },
                { value = "block", text = "In the IDs block" },
            }
        end,
        m.isOn)
    AT.Tooltip(row, "Item level", "Your gear's item level, as each game reports it. After the name reads Name (34); under the name adds an Item Level line.")
    MOD.Stamp(row, m, "tooltipItemLevel", "enum")
    row = AT.RowToggle(pg, "Only while holding Shift",
        function() return Store.GetSetting("tooltipIDsShift") == true end,
        function(v) Store.SetSetting("tooltipIDsShift", v and true or nil) end,
        m.isOn, "The ID block shows only when Shift is held as the tooltip opens.")
    MOD.Stamp(row, m, "tooltipIDsShift", "bool")
    -- QOL\AD_ImbueTooltip.lua: off unless switched on
    row = AT.RowToggle(pg, "Imbue damage with your weapon",
        function() return Store.GetSetting("tooltipImbueDamage") == true end,
        function(v) Store.SetSetting("tooltipImbueDamage", v and true or nil) end,
        m.isOn, "Rockbiter, Flametongue and Windfury Weapon, sharpening stones and weightstones: what each adds per hit and per second with your main-hand weapon, to compare them.")
    MOD.Stamp(row, m, "tooltipImbueDamage", "bool")
end

-- QOL\AD_AutoRank.lua acts on the switch; the button is a one-time catch-up.
function MOD.RankRows(pg, m)
    local AR = NS.AutoRank
    local ranked = m.available
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Auto-rank action bar spells", m.isOn, m.setOn, ranked,
        "When you learn a new rank, every action bar button that held the previous top rank moves up to the new one. Lower ranks you placed on purpose are left alone. Macros are never touched. Bars only change out of combat.")
    MOD.Stamp(row, m, m.switch, "bool", ranked, true)
    local upRow = AT.RowButton(pg, "Upgrade all bars now", function()
        if not AR then return end
        local n, why = AR.UpgradeAll()
        local b = pg._upBtn
        if not b then return end
        if n then b.fs:SetText(n == 1 and "Upgraded 1 button" or ("Upgraded " .. n .. " buttons"))
        elseif why == "combat" then b.fs:SetText("Not in combat")
        elseif why == "cursor" then b.fs:SetText("Empty your cursor first")
        else return end
        C_Timer.After(1.6, function() b.fs:SetText("Upgrade all bars now") end)
    end, function() return ranked() and m.isOn() end, 170)
    pg._upBtn = upRow.button
    if pg._upBtn then
        AT.Tooltip(pg._upBtn, "Upgrade all bars now", "One-time catch-up: moves EVERY action bar spell to the top rank you know, including lower ranks you placed on purpose.")
    end
    MOD.Stamp(upRow, m, "autoRankUpgrade", nil, ranked)
    AT.RowDesc(pg, "Spell ranks only exist on WoW Forever.", 20, function() return not ranked() end)
end

-- Core\AD_Skins.lua reads the skins and the Factory paints them; this card
-- switches them on and says where a skin is picked. Off by default: on gives
-- every icon a skin.
function MOD.MasqueRows(pg, m)
    local has = m.available
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Skin icons with Masque", m.isOn, m.setOn, has,
        "Each icon group, and your free icons, gets a skin you pick in Masque's options: picture size and crop, border, backdrop and gloss.")
    MOD.Stamp(row, m, m.switch, "bool", has, true)
    AT.RowDesc(pg, "Pick each group's skin in Masque's options: /msq.", 20,
        function() return has() and m.isOn() end)
    AT.RowDesc(pg, "Needs the Masque addon.", 20, function() return not has() end)
end

MOD.Register({
    key = "pressHighlight",
    switch = "pressHighlight",
    name = "Button Press Highlight",
    desc = "Lights up an icon the moment you press its button, cast it from a macro or use a trinket.",
    moved = "from Settings",
    glyph = {
        { 5, 5, 10, 2, "arc" }, { 5, 13, 10, 2, "arc" }, { 5, 5, 2, 10, "arc" }, { 13, 5, 2, 10, "arc" },
        { 9, 0, 2, 3 }, { 9, 17, 2, 3 }, { 0, 9, 3, 2 }, { 17, 9, 3, 2 },
        { 0, 1, 4, 2, "faint", -45 }, { 16, 1, 4, 2, "faint", 45 },
        { 0, 17, 4, 2, "faint", 45 }, { 16, 17, 4, 2, "faint", -45 },
    },
    isOn = function() return Store.GetSetting("pressHighlight") == true end,
    setOn = function(v)
        Store.SetSetting("pressHighlight", v and true or nil)
        local PH = NS.PressHighlight
        if not v and PH then PH.ReleaseAll() end
        Options.RefreshAll()
    end,
    build = function(pg, m) MOD.PressRows(pg, m) end,
})

MOD.Register({
    key = "tooltipIDs",
    switch = "tooltipIDs",
    name = "Tooltip IDs",
    desc = "Adds spell, item, icon and Cooldown Manager IDs to game tooltips.",
    moved = "from Settings",
    glyph = {
        { 2, 3, 16, 2, "arc" }, { 2, 15, 16, 2, "arc" }, { 2, 3, 2, 14, "arc" }, { 16, 3, 2, 14, "arc" },
        { 6, 7, 8, 2 }, { 6, 11, 5, 2 },
    },
    -- on until switched off: a fresh or unloaded SavedVariables file shows IDs
    isOn = function() return Store.GetSetting("tooltipIDs") ~= false end,
    setOn = function(v)
        Store.SetSetting("tooltipIDs", v and true or false)
        if v and NS.TooltipIDs then NS.TooltipIDs.Install() end
    end,
    build = function(pg, m) MOD.TooltipRows(pg, m) end,
})

MOD.Register({
    key = "autoRank",
    switch = "autoRankBars",
    name = "Auto-rank Action Bars",
    desc = "When you learn a new rank, your action bar buttons move up to it, out of combat.",
    unavailable = "Spell ranks only exist on WoW Forever.",
    foreverOnly = true,
    moved = "from QOL",
    glyph = function(box)
        MOD.DrawGlyph(box, { { 3, 17, 14, 2 }, { 5, 10, 2, 6 }, { 9, 7, 2, 9 }, { 13, 10, 2, 6 } })
        local up = AT.MakeChevron(box)
        up:SetDir("up")
        up:SetColor(COL.arc)
        up:SetPoint("CENTER", box, "TOPLEFT", 17, -10)
    end,
    available = function()
        local AR = NS.AutoRank
        return AR ~= nil and AR.Supported() == true
    end,
    isOn = function() return Store.GetSetting("autoRankBars") == true end,
    setOn = function(v) Store.SetSetting("autoRankBars", v and true or false) end,
    build = function(pg, m) MOD.RankRows(pg, m) end,
})

MOD.Register({
    key = "masque",
    switch = "masqueSkins",
    name = "Masque Skins",
    desc = "Your Masque skins on Arc Auras icons, aura icons included: pick one per icon group in Masque.",
    unavailable = "Needs the Masque addon.",
    -- an icon in a skin's frame, its gloss along the top
    glyph = {
        { 2, 2, 16, 2, "arc" }, { 2, 16, 16, 2, "arc" }, { 2, 2, 2, 16, "arc" }, { 16, 2, 2, 16, "arc" },
        { 6, 6, 8, 8, "dim" }, { 6, 6, 8, 2, "ink" },
    },
    available = function() return NS.Skins ~= nil and NS.Skins.Lib() ~= nil end,
    isOn = function() return Store.GetSetting("masqueSkins") == true end,
    setOn = function(v)
        if NS.Skins then NS.Skins.SetOn(v) end
        Options.RefreshAll()
    end,
    build = function(pg, m) MOD.MasqueRows(pg, m) end,
})
