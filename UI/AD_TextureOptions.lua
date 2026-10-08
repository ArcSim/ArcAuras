-- AD_TextureOptions: a texture's Add window tab, its Tracking rows (what drives it: an aura, a spell's cooldown or custom triggers), its tab list and the picture picker the Appearance block draws.
-- AD_Options calls in behind nil checks; the runtime is Bars\AD_TextureElement.lua, the triggers are UI\AD_TextOptions.lua's shared block.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TPO = {}
Options.TextureElement = TPO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function TPO.Runtime() return NS.TextureElements end

-- The sources this client can feed: an engine a source needs must be there.
function TPO.SourceItems()
    local S = NS.Schema
    local out = {}
    for _, s in ipairs(S.TEXTURE_SOURCES or {}) do
        local ok = true
        if s == "aura" then
            ok = NS.DriverAura ~= nil and NS.DriverAura.IsAvailable ~= nil and NS.DriverAura.IsAvailable() == true
        elseif s == "rules" then
            ok = NS.DriverCustom ~= nil
        elseif s == "spellCd" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXTURE_SOURCE_LABELS[s] or s } end
    end
    return out
end

local function ParseSpell(text)
    local CO = Options.Custom
    if CO and CO.ParseSpell then return CO.ParseSpell(text) end
    local id = tonumber(Trim(text))
    return (id and id > 0) and math.floor(id) or nil
end

local function SpellName(id)
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
    return nm
end

function TPO.InLibrary(v)
    local n = tonumber(v)
    return n ~= nil and Options.TEXTURE_NAMES ~= nil and Options.TEXTURE_NAMES[n] ~= nil
end

-- What a picture value is called: the spell's icon (empty), a library name, or
-- a picture of your own.
function TPO.PictureName(v)
    v = tostring(v or "")
    if v == "" then return "The spell's icon" end
    local n = tonumber(v)
    local nm = n and Options.TEXTURE_NAMES and Options.TEXTURE_NAMES[n]
    if nm then return nm end
    return "Your own: " .. v
end

-- What SetTexture takes for a value: the spell's icon when it is empty.
function TPO.ArtOf(v, spellID)
    v = tostring(v or "")
    if v ~= "" then return tonumber(v) or v end
    local icon = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) -- raw-id: the picker's preview of a typed spell
    if icon ~= nil and not (issecretvalue and issecretvalue(icon)) then return icon end
    return 134400
end

function TPO.DefaultName(source, spellID)
    local nm = SpellName(spellID)
    if source == "rules" then return "Custom texture" end
    if nm ~= "" then return nm end
    return (source == "spellCd") and "Cooldown texture" or "Aura texture"
end

-- The sidebar's and cards' one line.
function Options.TextureWhat(rec)
    local T = TPO.Runtime()
    return T and T.Describe(rec) or "texture"
end

-- The editor tabs: Triggers only for a picture with custom triggers.
function Options.TextureTabs(rec)
    local tabs = { "Tracking" }
    if rec.driver and rec.driver.source == "rules" then tabs[#tabs + 1] = "Triggers" end
    for _, t in ipairs({ "Appearance", "Conditions", "Position", "Load Conditions" }) do tabs[#tabs + 1] = t end
    return tabs
end

-- The picture picker: every library picture as a thumbnail, by group, with a
-- search over names and IDs. A click uses one at once and the window stays
-- open to try others. It edits the one thing it was opened for and closes
-- with the window that opened it, or when its row goes away.
TPO.CELL, TPO.GAP, TPO.HEAD = 64, 6, 26

function TPO.BuildPicker()
    if TPO.win then return TPO.win end
    local AT, COL = NS.AT, NS.AT.COL
    local win = AT.CreateWindow("ArcAurasPicturePicker", {
        w = 600, h = 560, minW = 420, minH = 360, maxW = 1400, maxH = 1200,
        title = NS.AT.Brand("Choose", " a Picture"),
    })
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 8, -38)
    body:SetPoint("BOTTOMRIGHT", -8, 8)
    local search = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", 0, 0)
    AT.Skin(search, COL.well)
    search:SetFont(NS.AT.FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(NS.AT.FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search by name or ID")
    search:SetScript("OnTextChanged", function(self)
        hint:SetShown((self:GetText() or "") == "")
        TPO.LayoutPicker()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    local done = AT.MakeSmallButton(body, "Done", 70)
    done:SetPoint("TOPRIGHT", 0, 0)
    done:SetHeight(20)
    done.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    done:SetScript("OnClick", function() win:Hide() end)
    local count = body:CreateFontString(nil, "OVERLAY")
    count:SetFont(NS.AT.FONT, 11, "")
    count:SetPoint("LEFT", search, "RIGHT", 12, 0)
    count:SetPoint("RIGHT", done, "LEFT", -12, 0)
    count:SetJustifyH("LEFT")
    count:SetWordWrap(false)
    count:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local host, content = AT.MakeScroll(body)
    host:SetPoint("TOPLEFT", 0, -30)
    host:SetPoint("BOTTOMRIGHT", -6, 0)
    -- the width decides how many fit a line: lay out again whenever it moves
    host:HookScript("OnSizeChanged", function() TPO.LayoutPicker() end)
    local empty = body:CreateFontString(nil, "OVERLAY")
    empty:SetFont(NS.AT.FONT, 12, "")
    empty:SetPoint("CENTER", host, "CENTER", 0, 0)
    empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    empty:SetText("No picture matches.")
    empty:Hide()
    win:HookScript("OnHide", function() TPO.pick = nil end)
    TPO.win, TPO.searchBox, TPO.countFS, TPO.scroll, TPO.content, TPO.emptyFS = win, search, count, host, content, empty
    TPO.tiles, TPO.heads = {}, {}
    return win
end

-- One thumbnail: the picture in a box, its name and ID on hover, a click uses it.
function TPO.Tile(i)
    local t = TPO.tiles[i]
    if t then return t end
    local AT, COL = NS.AT, NS.AT.COL
    t = CreateFrame("Button", nil, TPO.content, "BackdropTemplate")
    t:SetSize(TPO.CELL, TPO.CELL)
    AT.Skin(t, COL.box, COL.line)
    t.art = t:CreateTexture(nil, "ARTWORK")
    t.art:SetPoint("TOPLEFT", 6, -6)
    t.art:SetPoint("BOTTOMRIGHT", -6, 6)
    t:SetScript("OnEnter", function(self)
        if not self.sel then self:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end
    end)
    t:SetScript("OnLeave", function(self) TPO.PaintTile(self) end)
    AT.Tooltip(t, function() return t.name end, function() return t.sub end)
    t:SetScript("OnClick", function(self) TPO.Use(self.value) end)
    TPO.tiles[i] = t
    return t
end

-- The picked one stands out in the accent colour.
function TPO.PaintTile(t)
    local COL = NS.AT.COL
    local p = TPO.pick
    t.sel = p ~= nil and t.value == tostring(p.get() or "")
    local bg, line = t.sel and COL.panel or COL.box, t.sel and COL.arc or COL.line
    t:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    t:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

-- A group's title line over its pictures, in the panels' section style.
function TPO.Head(i)
    local h = TPO.heads[i]
    if h then return h end
    local AT, COL = NS.AT, NS.AT.COL
    h = CreateFrame("Frame", nil, TPO.content)
    h:SetHeight(TPO.HEAD)
    h.fs = h:CreateFontString(nil, "OVERLAY")
    h.fs:SetFont(NS.AT.FONT, 11, "")
    h.fs:SetPoint("BOTTOMLEFT", 2, 8)
    h.fs:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetTexture(AT.WHITE)
    h.line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    h.line:SetPoint("BOTTOMLEFT", 0, 4)
    h.line:SetPoint("BOTTOMRIGHT", 0, 4)
    h.line:SetHeight(AT.Hairline and AT.Hairline(h) or 1)
    TPO.heads[i] = h
    return h
end

-- The groups the picker shows: the spell's icon and your own picture (when
-- one is set) first, then the library.
function TPO.PickerGroups(p)
    local cur = tostring(p.get() or "")
    local basics = { { value = "", name = "The spell's icon", art = p.spellArt(), sub = "Follows the spell it tracks." } }
    if cur ~= "" and not TPO.InLibrary(cur) then
        basics[#basics + 1] = { value = cur, name = "Your own", art = tonumber(cur) or cur, sub = cur }
    end
    local out = { { name = "Basics", list = basics } }
    for _, g in ipairs(Options.TEXTURE_LIBRARY or {}) do
        local list = {}
        for _, pic in ipairs(g.pictures) do
            list[#list + 1] = { value = tostring(pic.id), name = pic.name, art = pic.id,
                sub = g.name .. ", ID " .. pic.id }
        end
        out[#out + 1] = { name = g.name, list = list }
    end
    return out
end

-- Lays the pictures out for the window's width: a title line per group with
-- a match, then its thumbnails, wrapping. The search keeps names or IDs that
-- hold what is typed.
function TPO.LayoutPicker()
    local p, win = TPO.pick, TPO.win
    if not (p and win and win:IsShown()) then return end
    local q = Trim(TPO.searchBox:GetText()):lower()
    local width = TPO.scroll:GetWidth() or 0
    local step = TPO.CELL + TPO.GAP
    local per = math.max(1, math.floor((width + TPO.GAP) / step))
    TPO.content:SetWidth(math.max(1, width))
    local y, ti, hi, found, total, selY = 0, 0, 0, 0, 0, nil
    for _, g in ipairs(TPO.PickerGroups(p)) do
        local shown = {}
        for _, it in ipairs(g.list) do
            if g.name ~= "Basics" then total = total + 1 end
            if q == "" or it.name:lower():find(q, 1, true) or it.value:find(q, 1, true) then
                shown[#shown + 1] = it
            end
        end
        if #shown > 0 then
            hi = hi + 1
            local h = TPO.Head(hi)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", TPO.content, "TOPLEFT", 0, -y)
            h:SetPoint("RIGHT", TPO.content, "RIGHT", 0, 0)
            h.fs:SetText(g.name:upper())
            h:Show()
            y = y + TPO.HEAD
            for i, it in ipairs(shown) do
                ti = ti + 1
                local t = TPO.Tile(ti)
                t.value, t.name, t.sub = it.value, it.name, it.sub
                t.art:SetTexture(it.art)
                local ty = y + math.floor((i - 1) / per) * step
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", TPO.content, "TOPLEFT", ((i - 1) % per) * step, -ty)
                TPO.PaintTile(t)
                if t.sel then selY = ty end
                t:Show()
            end
            y = y + math.ceil(#shown / per) * step + 4
            found = found + #shown
        end
    end
    for i = ti + 1, #TPO.tiles do TPO.tiles[i]:Hide() end
    for i = hi + 1, #TPO.heads do TPO.heads[i]:Hide() end
    TPO.content:SetHeight(math.max(1, y))
    TPO.scroll:UpdateScroll()
    TPO.emptyFS:SetShown(found == 0)
    local what = (q == "") and (total .. " pictures") or (found == 1 and "1 match" or (found .. " matches"))
    TPO.countFS:SetText((p.what and p.what ~= "" and (p.what .. ": ") or "") .. what)
    p.laidFor = tostring(p.get() or "")
    return selY
end

-- Brings the picked picture into view.
function TPO.ScrollToPick(selY)
    local host = TPO.scroll
    if not (selY and host) then return end
    local viewH = host:GetHeight() or 0
    local cur = host:GetVerticalScroll() or 0
    if selY >= cur and selY + TPO.CELL <= cur + viewH then return end
    local over = (TPO.content:GetHeight() or 0) - viewH
    local want = math.max(0, math.min(over, selY - TPO.HEAD))
    host:SetVerticalScroll(want)
    host:UpdateScroll()
end

function TPO.Use(v)
    local p = TPO.pick
    if not p then return end
    p.set(v)
    TPO.LayoutPicker()
end

-- p: get() the value, set(v) a pick, spellArt() the spell's icon tile's art,
-- what (the name in the window's line), owner (the window that opened it, it
-- closes with it), row (the chooser row that opened it), rec (the record).
function TPO.OpenPicker(p)
    TPO.BuildPicker()
    local owner = p.owner
    if owner and owner.HookScript and not owner._adPickerHooked then
        owner._adPickerHooked = true
        owner:HookScript("OnHide", function() TPO.ClosePicker() end)
    end
    TPO.pick = p
    TPO.searchBox:SetText("")
    TPO.win:Show()
    TPO.win:Raise()
    TPO.ScrollToPick(TPO.LayoutPicker())
end

function TPO.ClosePicker()
    if TPO.win and TPO.win:IsShown() then TPO.win:Hide() end
    TPO.pick = nil
end

-- The chooser: a preview of what shows now and its name, and a button (or a
-- click on the preview) that opens the picker. c = { get, set, spellID, what,
-- rec, visible }; set receives the picked value.
function TPO.ChooserRow(pg, owner, label, c)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(pg, 48, c.visible)
    local lbl = AT.RowLabel(row, label)
    local box = CreateFrame("Button", nil, row, "BackdropTemplate")
    box:SetSize(44, 44)
    box:SetPoint("LEFT", row._ctrlX, 0)
    AT.Skin(box, COL.well, COL.line)
    local art = box:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    local nameFS = row:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(NS.AT.FONT, 12, "")
    nameFS:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, -2)
    nameFS:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local btn = AT.MakeSmallButton(row, "Choose picture", 120)
    btn:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 10, 1)
    local function Open()
        AT.CloseDropdown()
        TPO.OpenPicker({
            get = c.get,
            set = function(v)
                c.set(v)
                AT.LayoutPage(pg)
            end,
            spellArt = function() return TPO.ArtOf("", c.spellID and c.spellID()) end,
            what = c.what and c.what() or nil,
            owner = owner, row = row, rec = c.rec and c.rec() or nil,
        })
    end
    box:SetScript("OnClick", Open)
    btn:SetScript("OnClick", Open)
    box:SetScript("OnEnter", function() box:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    box:SetScript("OnLeave", function() box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    AT.Tooltip(box, label, "Click to choose from every picture.")
    -- a hidden section's rows are not synced: the row's own hide (its section,
    -- tab or window going away) closes the picker it opened
    row:HookScript("OnHide", function()
        local p = TPO.pick
        if p and p.row == row then TPO.ClosePicker() end
    end)
    -- the preview leads: the page pins it to the label column, and the name
    -- and the button ride on its right
    row._colLabel, row._colCtrl, row._colTrail = lbl, box, 10 + btn:GetWidth()
    row.button = btn
    row._sync = function()
        local v = c.get()
        art:SetTexture(TPO.ArtOf(v, c.spellID and c.spellID()))
        nameFS:SetText(TPO.PictureName(v))
        -- the picker follows its row: gone or on another record, it closes
        local p = TPO.pick
        if p and p.row == row then
            local vis = (not c.visible) or c.visible()
            if not vis or (c.rec and p.rec ~= c.rec()) then
                TPO.ClosePicker()
            elseif p.laidFor ~= tostring(v or "") then
                TPO.LayoutPicker()
            end
        end
    end
    return row
end

-- The picture field (SectionRows draws it for `picture`): the chooser, and a
-- box under it for a picture of your own (a FileDataID or a file path).
function Options.PictureRow(pg, owner, label, section, field, ctx, visible)
    local AT, Store = NS.AT, NS.Store
    local function Cur()
        local r = ctx()
        local v = r and Store.Resolve(r, section, field)
        return (v ~= nil) and tostring(v) or ""
    end
    local row = TPO.ChooserRow(pg, owner, label, {
        get = Cur,
        set = function(v)
            local r = ctx()
            if r then Store.SetOverride(r, section, field, tostring(v or "")) end
        end,
        -- the spell the live picture wears: a cooldown's rank and override,
        -- an aura's first aura (each question's own entry)
        spellID = function()
            local r = ctx()
            if not (r and r.driver) then return nil end
            local TP = NS.TextureElements
            if TP and TP.Source(r) == "spellCd" then return TP.EffSpell(r) end
            return Store.TrackedAuraIDs(r.driver)[1]
        end,
        what = function()
            local r = ctx()
            return r and r.name or nil
        end,
        rec = ctx,
        visible = visible,
    })
    AT.RowInput(pg, "Picture ID or path",
        function()
            local v = Cur()
            return (v ~= "" and not TPO.InLibrary(v)) and v or ""
        end,
        function(v)
            local r = ctx()
            if not r then return end
            Store.SetOverride(r, section, field, Trim(v))
            AT.LayoutPage(pg)
        end,
        visible, "A picture of your own: its FileDataID, or its path such as Interface/AddOns/MyMedia/glow. Enter applies it; empty = pick one above.",
        "e.g. 450917")
    return row
end

-- The Add window's tab: what drives it, the aura or spell, the picture and a
-- name; the rest is set in the editor once it exists.
function Options.TextureAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Texture" end
    local function Src() return addState.texSource or "aura" end
    AT.RowDesc(pg, "A picture on screen: it shows with an aura, a cooldown or your own triggers, or fills like a bar.", 20, vis)
    AT.RowDropdown(pg, owner, "Picture driven by",
        Src,
        function(v) addState.texSource = v end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    AT.RowInput(pg, "Aura or spell",
        function() return addState.texSpell or "" end,
        function(v)
            addState.texSpell = v
            -- the page again, so Create is judged with it
            AT.LayoutPage(pg)
        end,
        function() return vis() and Src() ~= "rules" end,
        "The aura's spell ID, or the spell whose cooldown it follows: an ID, a link or the name of a spell you know. Enter applies it.",
        "e.g. 1459")
    TPO.ChooserRow(pg, owner, "Picture to show", {
        get = function() return addState.texImage or "" end,
        set = function(v) addState.texImage = v end,
        spellID = function()
            return (Src() ~= "rules") and ParseSpell(addState.texSpell or "") or nil
        end,
        what = function() return "New texture" end,
        visible = vis,
    })
    AT.RowInput(pg, "Texture name",
        function() return addState.texName or "" end,
        function(v) addState.texName = v end,
        vis, "What the sidebar calls it.",
        function() return TPO.DefaultName(Src(), ParseSpell(addState.texSpell or "")) end, true)
end

-- An aura or a cooldown needs its spell; custom triggers are set afterwards.
function Options.TextureCanCreate(addState)
    if (addState.texSource or "aura") == "rules" then return true end
    return ParseSpell(addState.texSpell or "") ~= nil
end

function Options.TextureCreate(addState, layoutId)
    local Store = NS.Store
    local s = addState.texSource or "aura"
    local driver = { source = s }
    local sid
    if s == "rules" then
        driver.rules = {}
    else
        sid = ParseSpell(addState.texSpell or "")
        driver.spellID = sid
    end
    local name = Trim(addState.texName)
    if name == "" then name = TPO.DefaultName(s, sid) end
    local rec = Store.NewBar(layoutId, "texture", driver, name)
    local img = Trim(addState.texImage)
    if rec and img ~= "" then Store.SetOverride(rec, "texlook", "image", img) end
    return rec
end

-- The Tracking rows. ctx(): the open bar; trackVis: the Tracking tab.
function Options.TextureTrackRows(pg, ctx, trackVis, owner)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "texture" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TPO.Runtime()
        return (r and T) and T.Source(r) or "aura"
    end
    local function Is(want)
        return function()
            local r = Rec()
            return vis() and r ~= nil and Source(r) == want
        end
    end
    -- a driver edit: the record in place, then the page again at once
    local function Set(field, value)
        local r = Rec()
        if not r then return end
        if r.driver[field] == value then return end
        r.driver[field] = value
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end

    AT.Section(pg, "What drives it", { visibleFn = vis })
    local srcRow = AT.RowDropdown(pg, owner, "Driven by",
        function() return Source(Rec()) end,
        function(v)
            local r = Rec()
            if not r or Source(r) == v then return end
            r.driver.source = v
            if v == "rules" and type(r.driver.rules) ~= "table" then r.driver.rules = {} end
            Store.Dirty("tree", r.id)
        end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    -- the search finds the row on every texture (its own field name)
    srcRow._adMeta = { family = "bar", section = "texlook", field = "textureSource",
        def = { label = "Driven by" }, baseVis = vis }

    -- an aura on a unit: the aura icons' shape
    local auraVis = Is("aura")
    AT.RowInput(pg, "Aura to watch",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            local ids = (r and DA) and DA.SpellIDList(r.driver) or {}
            return table.concat(ids, ", ")
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            local old = NS.DriverAura and table.concat(NS.DriverAura.SpellIDList(r.driver), ",") or ""
            if table.concat(ids, ",") == old then return end
            Options.SetAuraSpellIDs(r.driver, ids)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        auraVis, "The aura's spell IDs, separated by commas or spaces; any of them shows the picture.", "e.g. 1459, 10157")
    AT.RowDropdown(pg, owner, "Buff or debuff to watch",
        function()
            local r = Rec()
            return (r and r.driver.auraType == "debuff") and "debuff" or "buff"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local DA = NS.DriverAura
            local unit = DA and DA.ShapeOf(r.driver) or "player"
            r.driver.auraType = v
            if not Options.AuraUnitAllowed(r.driver, unit, v) then unit = "target" end
            r.driver.unit = unit
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura on whom",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            return (r and DA) and (DA.ShapeOf(r.driver)) or "player"
        end,
        function(v) Set("unit", v) end,
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return {} end
            return Options.AuraUnitItems(r.driver, nil, (DA.ShapeOf(r.driver)))
        end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura put there by",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return "any" end
            local _, _, caster = DA.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v) Set("caster", (v ~= "any") and v or nil) end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)
    AT.RowDesc(pg, "The game draws it with the aura, in combat too. Buffs work on you, your pet and friendly units; debuffs on a hostile target or focus.", 20, auraVis)

    -- a spell's cooldown
    local cdVis = Is("spellCd")
    local spellRow = AT.RowInput(pg, "Spell to watch",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = ParseSpell(v)
            if Trim(v) ~= "" and not id then return end
            Set("spellID", id)
        end,
        cdVis, "A spell ID, a link, or the name of a spell you know. Enter applies it.", "e.g. 17364")
    local nameFS = spellRow:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(NS.AT.FONT, 11, "")
    if spellRow._colCtrl then nameFS:SetPoint("LEFT", spellRow._colCtrl, "RIGHT", 8, 0) end
    nameFS:SetPoint("RIGHT", spellRow, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local sync = spellRow._sync
    spellRow._sync = function()
        if sync then sync() end
        local r = Rec()
        nameFS:SetText(r and SpellName(r.driver.spellID) or "")
    end
    AT.RowToggle(pg, "Use my current rank",
        function()
            local r = Rec()
            return r ~= nil and NS.Store.AutoRankOn(r.driver)
        end,
        -- on by default: only off is stored
        function(v) if v then Set("autoRank", nil) else Set("autoRank", false) end end,
        function() return cdVis() and NS.IsForever == true end,
        "On ranked realms, follow whichever rank of this spell you know now.")
    AT.RowDropdown(pg, owner, "Picture active while",
        function()
            local r = Rec()
            return (r and r.driver.cdActive) or "ready"
        end,
        function(v) Set("cdActive", (v ~= "ready") and v or nil) end,
        function()
            local out = {}
            for _, k in ipairs(S.TEXTURE_CD_ACTIVE) do
                out[#out + 1] = { value = k, text = S.TEXTURE_CD_ACTIVE_LABELS[k] or k }
            end
            return out
        end,
        function()
            local r = Rec()
            return cdVis() and r ~= nil and not (TPO.Runtime() and TPO.Runtime().FillMode(r))
        end)
    AT.RowDesc(pg, "A fill runs while the spell is on cooldown (a charge spell: while a charge comes back) and stands full when it is ready.", 20,
        function()
            local r = Rec()
            return cdVis() and r ~= nil and TPO.Runtime() ~= nil and TPO.Runtime().FillMode(r)
        end)

    -- custom triggers: the rows live on the Triggers tab
    AT.RowDesc(pg, "Its triggers are on the Triggers tab: they decide when the picture shows, and a fill runs with their timer.", 20,
        Is("rules"))
    AT.Section(pg, nil)
end
