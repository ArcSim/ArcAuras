-- AD_WheelOptions: the Wheel item's rows: the Add window's Wheel tab, and the editor's Wheel
-- tab with its key, how many spots, and the drag editor (your spells beside the wheel).
-- AD_Options calls in through Options.WheelAddRows / WheelCreate / WheelRows / WheelWhat.
-- Changes save at once; the live wheel (Bars\AD_Wheel.lua) takes them out of combat.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local WO = {}
Options.Wheel = WO

-- held alone, a modifier waits for the key it goes with
WO.MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true }
-- mouse buttons a wheel can open on, as a binding names them
WO.MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
WO.CELL, WO.GAP, WO.COLS = 30, 4, 6
WO.PITCH = WO.CELL + WO.GAP
WO.EDIT_H = 292
WO.DIAL_MAX = 300
WO.AMBER = { 1, 0.78, 0.35 }
WO.HINT = "Drag a spell from the list, your spellbook, your bags or your bars onto a spot. Right-click a spot to empty it."

local function Trim(v) return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- The Add window

function Options.WheelAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Wheel" and not addState.remGroupId end
    AT.RowDesc(pg, "A ring of your spells and items: hold its key, point at one and let go to cast it.", 20, vis)
    AT.RowInput(pg, "Wheel name",
        function() return addState.wheelName or "" end,
        function(v) addState.wheelName = v end,
        vis, "What the sidebar calls it.", "Wheel", true)
    -- a ready-made start; a second click on the pick lets it go
    WO.TemplateGrid(pg, function() return vis() and #WO.Templates() > 0 end,
        function() return addState.wheelTpl or "" end,
        function(v) addState.wheelTpl = (v ~= "") and v or nil end,
        "TEMPLATE - click one to start the wheel with it", true)
end

function Options.WheelCreate(addState, layoutId)
    local WH = NS.Wheels
    local name = Trim(addState.wheelName)
    local tpl = addState.wheelTpl and WO.Template(addState.wheelTpl)
    local rec = NS.Store.NewBar(layoutId, "wheel", { count = WH and WH.COUNT or 6, spots = {} },
        name ~= "" and name or (tpl and tpl.name) or "Wheel")
    if rec and tpl then WO.UseTemplate(rec, tpl.key) end
    addState.wheelName, addState.wheelTpl = nil, nil
    return rec
end

-- The sidebar's words: how full it is and its key.
function Options.WheelWhat(rec)
    local WH = NS.Wheels
    if not WH then return "wheel" end
    local n, used, spots = WH.Count(rec), 0, WH.Spots(rec)
    for spot = 1, n do
        local s = spots[spot]
        if type(s) == "table" and tonumber(s.id) then used = used + 1 end
    end
    local key = WH.KeyOf(rec)
    local kw = key and ((GetBindingText and GetBindingText(key)) or key) or "no key"
    return ("%d of %d spots, %s"):format(used, n, kw)
end

-- the thumbnail: the first thing on the wheel
function Options.WheelThumb(rec)
    local WH = NS.Wheels
    local spots = WH and WH.Spots(rec) or {}
    for spot = 1, (WH and WH.Count(rec) or 0) do
        local s = spots[spot]
        local id = type(s) == "table" and tonumber(s.id)
        if id then
            if s.t == "item" then
                return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
            end
            return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400
        end
    end
    return 134400
end

-- The wheel's data

-- the first empty spot takes it; a full wheel grows by a spot up to the most
-- it can have. False when there is no room.
function WO.AddFirst(rec, t, id)
    local WH = NS.Wheels
    local d = rec.driver
    d.spots = type(d.spots) == "table" and d.spots or {}
    local n = WH.Count(rec)
    for spot = 1, n do
        if not WH.Entry(d.spots[spot]) then
            d.spots[spot] = { t = t, id = id }
            return true
        end
    end
    if n >= WH.MAX then return false end
    d.count = n + 1
    d.spots[n + 1] = { t = t, id = id }
    return true
end

-- what the game's cursor holds, as a spot: a spell from the spellbook or a
-- bar, an item from the bags or a bar
function WO.FromCursor()
    if not GetCursorInfo then return nil end
    local kind, a, _, sid = GetCursorInfo()
    if kind == "spell" then
        local id = tonumber(sid)
        if id and id > 0 then return { t = "spell", id = id } end
    elseif kind == "item" then
        local id = tonumber(a)
        if id and id > 0 then return { t = "item", id = id } end
    end
    return nil
end

-- A spell typed in: an ID, or the name of a spell you know.
function WO.ParseSpell(v)
    v = Trim(v)
    if v == "" then return nil end
    local id = tonumber(v:match("^(%d+)$") or v:match("spell:(%d+)"))
    if id and id > 0 then return id end
    local CS = C_Spell
    if CS and CS.GetSpellIDForSpellIdentifier then
        local found = CS.GetSpellIDForSpellIdentifier(v)
        if not (issecretvalue and issecretvalue(found)) and type(found) == "number" and found > 0 then
            return found
        end
    end
    return nil
end

function WO.ParseItem(v)
    v = Trim(v)
    local id = tonumber(v:match("^(%d+)$") or v:match("item:(%d+)"))
    if id and id > 0 then return id end
    return nil
end

-- Templates: ready-made wheels, as Forever's game data numbers the spells. A
-- spot casts your top rank by name, so each keeps rank 1. Retail numbers its
-- aspects and trackings apart, so it gets none yet. art: the picker's icon.
WO.TEMPLATE_LIST = {
    { key = "aspects", name = "Aspects", class = "HUNTER", art = 13165,
        desc = "Monkey, Hawk, Cheetah, Beast, Pack and Wild, in the order you learn them.",
        spells = { 13163, 13165, 5118, 13161, 13159, 20043 } },
    { key = "tracking", name = "Tracking", class = "HUNTER", art = 1494,
        desc = "Your eight trackings, in the order you learn them.",
        spells = { 1494, 19883, 19884, 19885, 19880, 19878, 19882, 19879 } },
    { key = "imbues", name = "Imbues", class = "SHAMAN", art = 8232,
        desc = "Rockbiter, Flametongue, Frostbrand and Windfury, in the order you learn them.",
        spells = { 8017, 8024, 8033, 8232 } },
}

-- the templates for this client and your class
function WO.Templates()
    if NS.IsForever ~= true then return {} end
    local cls = NS.Store.ClassTag and NS.Store.ClassTag()
    local out = {}
    for _, t in ipairs(WO.TEMPLATE_LIST) do
        if t.class == nil or t.class == cls then out[#out + 1] = t end
    end
    return out
end

function WO.Template(key)
    for _, t in ipairs(WO.Templates()) do
        if t.key == key then return t end
    end
    return nil
end

-- A template onto a wheel: its spells from spot 1, and that many spots, in
-- place of what was on it. Returns the template.
function WO.UseTemplate(rec, key)
    local WH, t = NS.Wheels, WO.Template(key)
    if not (t and rec and type(rec.driver) == "table") then return nil end
    local spots = {}
    for i, id in ipairs(t.spells) do spots[i] = { t = "spell", id = id } end
    rec.driver.spots = spots
    rec.driver.count = math.max(WH.MIN, math.min(WH.MAX, #t.spells))
    return t
end

-- a name the wheel was given (the default or a template's), so a template may
-- rename it; a name of the player's own stays
function WO.NameIsAuto(rec)
    local n = rec and rec.name
    if type(n) ~= "string" or n == "" or n == "Wheel" then return true end
    for _, t in ipairs(WO.TEMPLATE_LIST) do
        if n == t.name then return true end
    end
    return false
end

-- The template picker, the enchant one's look: a cell per template, the pick
-- lit cyan, a tooltip each. get() / set(key) hold the pick; with toggle, a
-- click on the pick lets it go.
function WO.TemplateGrid(pg, vis, get, set, caption, toggle)
    local AT = NS.AT
    local COL = AT.COL
    local cell, gap, top = Options.TPL_CELL or 32, Options.TPL_GAP or 4, Options.TPL_TOP or 14
    local row = AT.AddRow(pg, top + cell + gap, vis)
    row._tplGrid = true
    local cap = row:CreateFontString(nil, "OVERLAY")
    cap:SetFont(STANDARD_TEXT_FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText(caption)
    row._cells = {}
    local function Cell(i)
        local b = row._cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(cell, cell)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.arcDeep) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:AddLine(b._title or "", 1, 1, 1)
            GameTooltip:AddLine(b._body or "", COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            set((toggle and b._picked) and "" or b._key)
            if row._sync then row._sync() end
        end)
        row._cells[i] = b
        return b
    end
    row._sync = function()
        local list, cur = WO.Templates(), get() or ""
        for i, t in ipairs(list) do
            local b = Cell(i)
            b.tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(t.art)) or 134400)
            b._key, b._picked = t.key, t.key == cur
            b._title, b._body = t.name, t.desc .. " One you have not learned yet stays grey until you do."
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (i - 1) * (cell + gap), -top)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #list + 1, #row._cells do row._cells[i]:Hide() end
    end
    return row
end

-- The editor: the wheel drawn into the options (the live dial, scaled to fit),
-- every spot shown (an empty one as a faint ring). A spell dragged from the
-- list, or a spot dragged off the wheel, lands on the spot under the cursor;
-- a spot dragged off the wheel, or onto the X, leaves it.

local Editor = {}
Editor.__index = Editor

function WO.NewEditor(parent)
    local WH = NS.Wheels
    local ed = setmetatable({ marks = {} }, Editor)
    ed.host = CreateFrame("Frame", nil, parent)
    ed.dial = WH.NewDial(ed.host)
    ed.dial.ring:SetPoint("TOPLEFT", ed.host, "TOPLEFT", 0, 0)
    -- a spell or item dropped from the game's cursor onto any spot
    ed.host:EnableMouse(true)
    ed.host:SetScript("OnReceiveDrag", function() ed:CursorDrop() end)
    ed.host:SetScript("OnMouseUp", function() if GetCursorInfo and GetCursorInfo() then ed:CursorDrop() end end)
    return ed
end

-- the faint ring that marks an empty spot
function Editor:Mark(spot)
    if self.marks[spot] then return self.marks[spot] end
    local m = self.dial.ring:CreateTexture(nil, "ARTWORK", nil, 1)
    m:SetAtlas("Radial_Wheel_Select_Close")
    self.marks[spot] = m
    return m
end

-- redraw from the record, scaled to fit a square fit units wide
function Editor:Draw(rec, fit)
    local WH = NS.Wheels
    self.rec = rec
    local d = self.dial
    local n = WH.Count(rec)
    WH.FillDial(d, WH.Entries(rec), n, WH.Look(rec), false)
    local g = d.geo
    local w = g.half * 2
    self.host:SetSize(w, w)
    self.host:SetScale(fit / w)
    for spot, m in pairs(self.marks) do
        if spot > n then m:Hide() end
    end
    for spot = 1, n do
        local m, a = self:Mark(spot), WH.Angle(spot, n)
        m:ClearAllPoints()
        m:SetPoint("CENTER", d.ring, "CENTER", g.S(g.r * math.cos(a)), g.S(g.r * math.sin(a)))
        m:SetSize(g.sel, g.sel)
        m:SetShown(d.shown[spot] == nil)
    end
    -- a placed one is picked up straight off the wheel
    for spot, s in pairs(d.slots) do
        if not s._edWired then
            s._edWired = true
            s:EnableMouse(true)
            s:RegisterForDrag("LeftButton")
            s:SetScript("OnDragStart", function()
                local e = d.shown[spot]
                if e then self:BeginDrag(e, spot) end
            end)
            s:SetScript("OnDragStop", function() self:EndDrag() end)
            s:SetScript("OnReceiveDrag", function() self:CursorDrop() end)
            s:SetScript("OnMouseUp", function(_, button)
                if GetCursorInfo and GetCursorInfo() then
                    self:CursorDrop()
                elseif button == "RightButton" and d.shown[spot] then
                    self:Set(spot, nil)
                end
            end)
            s:SetScript("OnEnter", function() self:Tip(s, spot) end)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    self:Hover(self.hover)
end

function Editor:Tip(owner, spot)
    local e = self.dial.shown[spot]
    if not e then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.t == "item" and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(e.id)
    elseif GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(e.id)
    end
    if not e.act then GameTooltip:AddLine("Not learned yet: it casts once you learn it.", 1, 0.5, 0.3, true) end
    GameTooltip:AddLine("Drag it to move it. Right-click to take it off.", 0.55, 0.65, 0.78, true)
    GameTooltip:Show()
end

-- light the spot a drag would land on (nil: none)
function Editor:Hover(spot)
    self.hover = spot
    local d = self.dial
    if not d.geo then return end
    NS.Wheels.PaintDial(d, (type(spot) == "number" and d.shown[spot]) and spot or nil)
    d.closeRing:SetShown(spot == "x")
    for s, m in pairs(self.marks) do
        local on = (s == spot)
        m:SetDesaturated(not on)
        m:SetAlpha(on and 1 or 0.35)
    end
end

-- where the cursor is on the editor: a spot (1..n), "x" on the middle, or nil
-- off the wheel; read from the drawn ring, laid out long before a drag
function Editor:SpotAtCursor()
    local ring, g = self.dial.ring, self.dial.geo
    local rx, ry = ring:GetCenter()
    if not (rx and g) then return nil end
    local s = ring:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local dx, dy = x / s - rx, y / s - ry
    local d2 = dx * dx + dy * dy
    if d2 > g.half * g.half then return nil end
    if d2 < g.dead * g.dead then return "x" end
    return NS.Wheels.Slice(dx, dy, self.dial.n)
end

-- one spot's contents (nil empties it), saved at once
function Editor:Set(spot, v)
    local rec = self.rec
    if not (rec and rec.driver) then return end
    rec.driver.spots = type(rec.driver.spots) == "table" and rec.driver.spots or {}
    rec.driver.spots[spot] = v
    NS.Store.Dirty("style", rec.id)
    if self.onChange then self.onChange() end
end

-- the game's cursor let go over the wheel
function Editor:CursorDrop()
    local v = WO.FromCursor()
    if not v then return end
    local at = self:SpotAtCursor()
    if type(at) ~= "number" then return end
    ClearCursor()
    self:Set(at, v)
end

-- the icon under the cursor while one is dragged
function WO.Ghost()
    if WO.ghost then return WO.ghost end
    local gh = CreateFrame("Frame", nil, UIParent)
    gh:SetFrameStrata("TOOLTIP")
    gh:SetSize(32, 32)
    gh.icon = gh:CreateTexture(nil, "ARTWORK")
    gh.icon:SetAllPoints()
    gh.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = gh:CreateMaskTexture()
    mask:SetTexture(NS.Wheels.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(gh.icon)
    gh.icon:AddMaskTexture(mask)
    gh:Hide()
    WO.ghost = gh
    return gh
end

-- pick one up (from: the spot it was dragged off, nil from the list)
function Editor:BeginDrag(e, from)
    local gh = WO.Ghost()
    self.drag = { t = e.t, id = e.id, from = from }
    gh.icon:SetTexture(e.icon)
    gh.icon:SetDesaturated(e.act == nil)
    -- the ghost follows the cursor only while a drag is on
    gh:SetScript("OnUpdate", function()
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        gh:ClearAllPoints()
        gh:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        local at = self:SpotAtCursor()
        if at ~= self.hover then self:Hover(at) end
    end)
    gh:Show()
end

-- the window closing mid-drag: drop nothing
function Editor:CancelDrag()
    if not self.drag then return end
    self.drag = nil
    if WO.ghost then
        WO.ghost:SetScript("OnUpdate", nil)
        WO.ghost:Hide()
    end
    self:Hover(nil)
end

-- drop it: on a spot it goes there (from another spot, the two swap); off the
-- wheel or onto the X, one dragged off a spot leaves the wheel
function Editor:EndDrag()
    local drag = self.drag
    if not drag then return end
    self:CancelDrag()
    local at = self:SpotAtCursor()
    local rec = self.rec
    if not (rec and rec.driver) then return end
    local spots = type(rec.driver.spots) == "table" and rec.driver.spots or {}
    rec.driver.spots = spots
    if type(at) == "number" then
        if drag.from == nil then
            spots[at] = { t = drag.t, id = drag.id }
        elseif at ~= drag.from then
            spots[at], spots[drag.from] = spots[drag.from], spots[at]
        else
            return
        end
    elseif drag.from then
        spots[drag.from] = nil
    else
        return
    end
    NS.Store.Dirty("style", rec.id)
    if self.onChange then self.onChange() end
end

-- The Wheel tab's editor row: your spells (a search over a grid) on the left,
-- the wheel on the right.
function WO.EditorRow(pg, Rec, vis)
    local AT = NS.AT
    local COL = AT.COL
    local row = AT.AddRow(pg, WO.EDIT_H, vis)
    local gridW = WO.COLS * WO.PITCH - WO.GAP
    local search = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    search:SetSize(gridW, 20)
    search:SetPoint("TOPLEFT", 10, -4)
    AT.Skin(search, COL.well)
    search:SetFont(STANDARD_TEXT_FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search your spells")
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    local scroll, grid = AT.MakeScroll(row)
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    scroll:SetSize(gridW + 8, WO.EDIT_H - 34)
    local empty = row:CreateFontString(nil, "OVERLAY")
    empty:SetFont(STANDARD_TEXT_FONT, 11, "")
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -4)
    empty:SetWidth(gridW)
    empty:SetJustifyH("LEFT")
    empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    local ed = WO.NewEditor(row)
    row._editor = ed
    ed.onChange = function() AT.LayoutPage(pg) end
    row:HookScript("OnHide", function() ed:CancelDrag() end)

    local cells = {}
    local function Cell(i)
        if cells[i] then return cells[i] end
        local b = CreateFrame("Button", nil, grid, "BackdropTemplate")
        b:SetSize(WO.CELL, WO.CELL)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:RegisterForClicks("LeftButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            local e = self._e
            if e then ed:BeginDrag({ t = "spell", id = e.spellID, icon = e.texture, act = "spell" }, nil) end
        end)
        b:SetScript("OnDragStop", function() ed:EndDrag() end)
        -- a click puts it on the first empty spot
        b:SetScript("OnClick", function(self)
            local r, e = Rec(), self._e
            if not (r and e) then return end
            if WO.AddFirst(r, "spell", e.spellID) then
                row._full = nil
                NS.Store.Dirty("style", r.id)
            else
                row._full = true
            end
            AT.LayoutPage(pg)
        end)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
            local e = self._e
            if e and GameTooltip.SetSpellByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(e.spellID)
                GameTooltip:AddLine("Drag it onto a spot, or click to add it.", 0.55, 0.65, 0.78, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            GameTooltip:Hide()
        end)
        cells[i] = b
        return b
    end

    local function FillGrid()
        local Cat = NS.SpellCatalog
        local all = Cat and Cat.All() or {}
        local q = Trim(search:GetText())
        hint:SetShown(q == "")
        local list = (q == "") and all or Cat.Search(q, #all)
        for i, e in ipairs(list) do
            local b = Cell(i)
            b._e = e
            b.tex:SetTexture(e.texture)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ((i - 1) % WO.COLS) * WO.PITCH, -math.floor((i - 1) / WO.COLS) * WO.PITCH)
            b:Show()
        end
        for i = #list + 1, #cells do
            cells[i]._e = nil
            cells[i]:Hide()
        end
        local rows = math.ceil(#list / WO.COLS)
        grid:SetSize(gridW, math.max(1, rows * WO.PITCH - WO.GAP))
        scroll:UpdateScroll()
        empty:SetShown(#list == 0)
        empty:SetText((#all == 0) and "No spells listed yet." or "No spell of yours matches.")
    end
    search:SetScript("OnTextChanged", function() FillGrid() end)

    row._sync = function()
        local r = Rec()
        if not r then return end
        FillGrid()
        -- the wheel takes what the list leaves, up to its cap
        local w = row:GetWidth() or 0
        if w < 100 then w = (pg:GetWidth() or 0) - 24 end
        local left = 10 + gridW + 8 + 24
        local fit = math.max(160, math.min(WO.DIAL_MAX, w - left - 12, WO.EDIT_H - 8))
        ed:Draw(r, fit)
        -- placed at the scale Draw gave it: its offsets are in its own units
        local sc = ed.host:GetScale() or 1
        ed.host:ClearAllPoints()
        ed.host:SetPoint("TOPLEFT", row, "TOPLEFT", left / sc, -((WO.EDIT_H - fit) / 2) / sc)
    end
    return row
end

-- The Wheel tab. ctx(): the open bar; vis(): the Wheel tab shows; owner: the
-- window the dropdown lists open on.
function Options.WheelRows(pg, ctx, vis, owner)
    local AT, Store, WH = NS.AT, NS.Store, NS.Wheels
    if not WH then return end
    local COL = AT.COL
    -- one wheel; several at once share no contents to edit
    local function Rec()
        local r = ctx()
        if not (WH.IsWheel(r) and not r._adMulti and type(r.driver) == "table") then return nil end
        return r
    end
    local rvis = function() return vis() and Rec() ~= nil end

    AT.Section(pg, "Key", { visibleFn = rvis })
    -- click the box, then press the key; right-click clears it
    local keyRow = AT.AddRow(pg, 26, rvis)
    keyRow._colLabel = AT.RowLabel(keyRow, "Key to open it")
    local kb = AT.MakeSmallButton(keyRow, "Not set", 150)
    kb:RegisterForClicks("AnyUp")
    keyRow._colCtrl = kb
    local capturing = false
    local function KeyWords(r)
        local k = r and WH.KeyOf(r)
        if not k then return "Not set" end
        return (GetBindingText and GetBindingText(k)) or k
    end
    local function Stop()
        capturing = false
        kb:SetScript("OnKeyDown", nil)
        kb:EnableKeyboard(false)
        kb.fs:SetText(KeyWords(Rec()))
    end
    local function Take(key)
        local r = Rec()
        if r then
            r.wheelKey = (CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key)) or key
            Store.Dirty("style", r.id)
        end
        Stop()
    end
    kb:SetScript("OnClick", function(_, button)
        local r = Rec()
        if not r then return end
        if capturing then
            -- a mouse button while waiting is the key
            local mk = WO.MOUSE_KEYS[button]
            if mk then Take(mk) elseif button == "RightButton" then Stop() end
            return
        end
        if button == "RightButton" then
            r.wheelKey = nil
            Stop()
            Store.Dirty("style", r.id)
            return
        end
        if button ~= "LeftButton" then return end
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
            if WO.MODIFIERS[key] then return end
            Take(key)
        end)
    end)
    kb:HookScript("OnHide", function() if capturing then Stop() end end)
    keyRow._sync = function()
        if not capturing then kb.fs:SetText(KeyWords(Rec())) end
    end
    AT.Tooltip(kb, "Key to open it", "Click, then press a key or mouse button 3 to 5 (with Shift, Ctrl or Alt if you like). "
        .. "Right-click clears it. While Arc Auras is loaded, the key opens this wheel instead of its usual action.")

    -- another wheel on the same key: only one of them opens
    local function Clash(r)
        local k = r and WH.KeyOf(r)
        if not k then return nil end
        local other
        Store.EachRecord(function(id, o)
            if id ~= r.id and WH.IsWheel(o) and WH.KeyOf(o) == k then other = o.name or "Another wheel" end
        end)
        return other
    end
    local clashVis = function() return rvis() and Clash(Rec()) ~= nil end
    local clashRow = AT.AddRow(pg, 20, clashVis)
    local clashFS = clashRow:CreateFontString(nil, "OVERLAY")
    clashFS:SetFont(STANDARD_TEXT_FONT, 11, "")
    clashFS:SetPoint("LEFT", 10, 0)
    clashFS:SetPoint("RIGHT", -10, 0)
    clashFS:SetJustifyH("LEFT")
    clashFS:SetWordWrap(false)
    clashFS:SetTextColor(WO.AMBER[1], WO.AMBER[2], WO.AMBER[3])
    clashRow._sync = function()
        local o = Clash(Rec())
        clashFS:SetText(o and ("\"" .. o .. "\" has this key too: only one of them opens.") or "")
    end

    AT.Section(pg, "Spells and Items", { visibleFn = rvis })
    local countRow = AT.RowDropdown(pg, owner, "Spots on the wheel",
        function() local r = Rec() return r and WH.Count(r) or WH.COUNT end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.count = v
            Store.Dirty("style", r.id)
        end,
        function()
            local out = {}
            for n = WH.MIN, WH.MAX do out[#out + 1] = { value = n, text = tostring(n) } end
            return out
        end,
        rvis)
    AT.Tooltip(countRow, "Spots on the wheel", "3 to 10, spot 1 at the top. Fewer spots keep what sat on the others: it comes back with more.")

    local edRow = WO.EditorRow(pg, Rec, rvis)

    -- one line under the editor: how to use it, or why a click added nothing
    local noteRow = AT.AddRow(pg, 20, rvis)
    local noteFS = noteRow:CreateFontString(nil, "OVERLAY")
    noteFS:SetFont(STANDARD_TEXT_FONT, 11, "")
    noteFS:SetPoint("TOPLEFT", 10, -3)
    noteFS:SetJustifyH("LEFT")
    noteFS:SetJustifyV("TOP")
    noteFS:SetWordWrap(true)
    noteRow._sync = function()
        local w = noteRow:GetWidth() or 0
        if w < 90 then w = (pg:GetWidth() or 0) - 24 end
        if w > 90 then noteFS:SetWidth(w - 24) end
        local c = edRow._full and WO.AMBER or COL.dim
        noteFS:SetTextColor(c[1], c[2], c[3])
        noteFS:SetText(edRow._full and "The wheel is full: empty a spot first." or WO.HINT)
        local want = math.max(20, math.floor((noteFS:GetStringHeight() or 12) + 8))
        if noteRow._h ~= want then
            noteRow._h = want
            noteRow:SetHeight(want)
        end
    end

    local function AddTyped(t, id)
        local r = Rec()
        if not (r and id) then return end
        if WO.AddFirst(r, t, id) then
            edRow._full = nil
            Store.Dirty("style", r.id)
        else
            edRow._full = true
        end
        AT.LayoutPage(pg)
    end
    AT.RowInput(pg, "Add a spell",
        function() return "" end,
        function(v) if Trim(v) ~= "" then AddTyped("spell", WO.ParseSpell(v)) end end,
        rvis, "A spell ID, or the name of a spell you know. It goes on the first empty spot; one you have not learned yet shows grey until you do.",
        "ID or name")
    AT.RowInput(pg, "Add an item",
        function() return "" end,
        function(v) if Trim(v) ~= "" then AddTyped("item", WO.ParseItem(v)) end end,
        rvis, "An item ID, such as a potion or a trinket. It goes on the first empty spot and is used like /use.",
        "Item ID")

    -- a ready-made wheel: pick one, then Use (pick then act); the pick belongs
    -- to one wheel and resets on another
    local tplVis = function() return rvis() and #WO.Templates() > 0 end
    WO.TemplateGrid(pg, tplVis,
        function()
            local p, r = Options.ui.wheelTpl, Rec()
            return (p and r and p.id == r.id and p.key) or ""
        end,
        function(v)
            local r = Rec()
            Options.ui.wheelTpl = r and { id = r.id, key = v } or nil
        end,
        "TEMPLATE - pick one, then Use template", false)
    local useRow = AT.RowButton(pg, "Use template", function()
        local r, p = Rec(), Options.ui.wheelTpl
        if not (r and p and p.id == r.id) then return end
        local auto = WO.NameIsAuto(r)
        local t = WO.UseTemplate(r, p.key)
        if not t then return end
        if auto then Store.Rename(r.id, t.name) end
        Options.ui.wheelTpl = nil
        edRow._full = nil
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end, tplVis, 120)
    AT.Tooltip(useRow.button, "Use template", "Puts the picked template's spells on the wheel, in place of what is on it now.")
end
