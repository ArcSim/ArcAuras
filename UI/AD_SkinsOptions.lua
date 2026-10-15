-- AD_SkinsOptions: bar skins in the options (Core\AD_BarSkins.lua). The bar
-- editor's skin strip (one row under its tabs on Appearance and Text: Skin and
-- its dropdown, then when the picked skin switches on), the marks on the rows
-- below while a skin is edited, the New skin popover, and the Skins page under
-- ADDON in the sidebar. Called behind nil checks by UI\AD_Options.lua.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL = AT.COL

local SO = {}
Options.SkinsUI = SO

local function Hex(h)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
-- the approved board's colours for what the theme has no role for
local C = {
    label = Hex("A9B8CD"), row = Hex("C9D4E5"), pick = Hex("5B9DF0"), faint = Hex("7B8CA5"),
    green = Hex("6FCB7F"), greenEdge = Hex("3E7A44"), red = Hex("E07A6A"), onBg = Hex("1A3253"),
    offInk = Hex("8C9BB3"), offEdge = Hex("2D3D5C"), offBg = Hex("121A28"), saveEdge = Hex("3E6E9A"),
    head = Hex("1A2539"), slate = Hex("6F9797"), slateEdge = Hex("223049"), rowLine = Hex("1B2638"),
}
SO.C = C
-- the board's sizes in panel units (it draws at 1.2x the panel)
SO.STRIP_H, SO.DD_H, SO.GAP = 34, 20, 7
SO.SKIN_W, SO.CLASS_W, SO.SPEC_W, SO.TALENT_W = 184, 106, 114, 126
SO.MENU_W, SO.ITEM_H, SO.CAP_H, SO.SEP_H, SO.POP_W = 266, 21, 17, 7, 284
SO.LIST_W, SO.LIST_ROW_H = 247, 55

local function BS() return NS.BarSkins end
local Tr = function(s) return AT.Tr and AT.Tr(s) or s end

local function Text(parent, size, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Width(fs)
    if not (fs and fs.GetObjectType and fs:GetObjectType() == "FontString") then return 0 end
    return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

local function Dot(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(AT.WHITE)
    t:SetSize(size, size)
    t:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    local m = parent.CreateMaskTexture and parent:CreateMaskTexture()
    if m then
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    return t
end

local function Tick(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetAtlas("checkmark-minimal")
    t:SetDesaturated(true)
    t:SetVertexColor(C.pick[1], C.pick[2], C.pick[3], 1)
    t:SetSize(12, 12)
    return t
end

local function Line(parent, c)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(AT.WHITE)
    t:SetVertexColor(c[1], c[2], c[3], 1)
    return t
end

-- Classes, specs, talents in words

local function ClassInfo(tag)
    for _, c in ipairs(Store.ClassSpecMatrix()) do
        if c.tag == tag then return c end
    end
    return nil
end

function SO.ClassName(tag)
    local c = ClassInfo(tag)
    return c and c.name or tostring(tag)
end

function SO.ClassColor(tag)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
    if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
    return COL.ink
end

local function SpecsOf(tag)
    local c = ClassInfo(tag)
    return c and c.specs or {}
end

function SO.TalentName(e)
    local n = Options.TalentPickName and Options.TalentPickName(e.talentNode, e.talentEntry)
    if n then return n end
    local LK = NS.Looks
    return (LK and LK.TalentName(e)) or ("Talent " .. tostring(e.talentNode))
end

-- an entry's conditions in words, the dropdown's faint line
function SO.CondWords(e)
    local w = {}
    if e.cls then w[#w + 1] = SO.ClassName(e.cls) end
    if e.specs then
        local names = {}
        for _, s in ipairs(SpecsOf(e.cls)) do
            if e.specs[s.id] then names[#names + 1] = s.name end
        end
        if #names > 0 then w[#w + 1] = table.concat(names, ", ") end
    end
    if e.talentNode then
        w[#w + 1] = Tr(e.without and "without %s" or "with %s"):format(SO.TalentName(e))
    end
    if #w == 0 then return Tr("always") end
    return table.concat(w, ", ")
end

function SO.SkinName(e)
    local sk = BS().SkinOf(e)
    return sk and sk.name or Tr("Missing skin")
end

function SO.SpecWords(e)
    if not (e and e.specs) then return Tr("Any spec") end
    local names = {}
    for _, s in ipairs(SpecsOf(e.cls)) do
        if e.specs[s.id] then names[#names + 1] = s.name end
    end
    if #names == 1 then return names[1] end
    if #names == 0 then return Tr("Any spec") end
    return Tr("%d specs"):format(#names)
end

function SO.TalentWords(e)
    if not (e and e.talentNode) then return Tr("Any talent") end
    return Tr(e.without and "Without %s" or "With %s"):format(SO.TalentName(e))
end

-- Talents pick on your own tree: an entry held to another class has none.
function SO.TalentOK(e)
    local B = BS()
    return e ~= nil and (e.cls == nil or e.cls == B.MyClass())
end

-- The bars a skin strip shows on: those with a fill (not text, texture,
-- wheel or sound bars), one at a time. A resource bar with a look per power,
-- spec or talent keeps that instead: two looks picked at once would fight
-- over every write.
function SO.Offered(rec)
    if not (rec and rec.type == "bar" and not rec._adMulti) then return false end
    if rec.looks and rec.looks.by then return false end
    local fill = NS.Schema.bar.fill
    return NS.Schema.Applies(nil, fill, Store.KindOf(rec), rec.barMode)
end

-- Dropdown fields and their menus

local function MakeDD(parent, w)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, SO.DD_H)
    AT.Skin(b, COL.well)
    b._w = w
    b.text = Text(b, 11, COL.ink)
    b.text:SetPoint("LEFT", 8, 0)
    b.dot = Dot(b, 5)
    b.dot:Hide()
    local arrow = AT.MakeChevron(b)
    arrow:SetPoint("RIGHT", -5, 0)
    b:SetScript("OnEnter", function()
        if b._off then return end
        b:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    b:SetScript("OnLeave", function() b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    -- the value, its colour and the changed dot after it; long values shorten
    function b:Set(text, ink, dot)
        local c = ink or COL.ink
        self.text:SetText(text or "")
        self.text:SetTextColor(c[1], c[2], c[3])
        local room = self._w - 26 - (dot and 11 or 0)
        local tw = math.min(Width(self.text), room)
        self.text:SetWidth(room)
        self.dot:ClearAllPoints()
        self.dot:SetPoint("LEFT", self, "LEFT", 8 + tw + 6, 0)
        self.dot:SetShown(dot == true)
    end
    -- greyed while its pick does not apply yet (the board's 0.45)
    function b:SetOff(off)
        self._off = off or nil
        self:SetAlpha(off and 0.45 or 1)
    end
    return b
end

-- One menu row: a tick, the words, a changed dot, a faint line at the right;
-- or a caption, or a separator.
local function MenuRow(f)
    local r = CreateFrame("Button", nil, f)
    r:SetHighlightTexture(AT.WHITE)
    local hl = r:GetHighlightTexture()
    if hl then hl:SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.5) end
    r.tick = Tick(r)
    r.tick:SetPoint("LEFT", 6, 0)
    r.label = Text(r, 11, C.row)
    r.label:SetPoint("LEFT", 24, 0)
    r.dot = Dot(r, 5)
    r.sub = Text(r, 10, C.faint)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetJustifyH("RIGHT")
    r.cap = Text(r, 9, C.faint)
    r.cap:SetPoint("LEFT", 8, -1)
    r.line = Line(r, C.offEdge)
    r.line:SetHeight(1)
    r.line:SetPoint("LEFT", 0, 0)
    r.line:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnClick", function()
        local it = r._it
        if not (it and it.fn) then return end
        if not it.keep then AT.CloseDropdown() end
        it.fn()
        if it.keep and f:IsShown() then SO.PaintMenu(f) end
    end)
    return r
end

function SO.PaintMenu(f)
    local items = f._itemsFn() or {}
    for _, r in ipairs(f._rows) do r:Hide() end
    local y = 3
    for i, it in ipairs(items) do
        local r = f._rows[i]
        if not r then
            r = MenuRow(f)
            f._rows[i] = r
        end
        r._it = it
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -y)
        r:SetPoint("TOPRIGHT", -1, -y)
        local h
        r.tick:Hide(); r.label:Hide(); r.dot:Hide(); r.sub:Hide(); r.cap:Hide(); r.line:Hide()
        if it.sep then
            h = SO.SEP_H
            r.line:Show()
            r:EnableMouse(false)
        elseif it.cap then
            h = SO.CAP_H
            r.cap:SetText(Tr(it.cap))
            r.cap:Show()
            r:EnableMouse(false)
        else
            h = SO.ITEM_H
            r:EnableMouse(true)
            local c = it.ink or (it.picked and C.pick) or C.row
            r.label:SetText(it.label or "")
            r.label:SetTextColor(c[1], c[2], c[3])
            r.label:Show()
            r.tick:SetShown(it.picked == true)
            r.sub:SetText(it.sub or "")
            r.sub:SetShown((it.sub or "") ~= "")
            -- the words end before the faint line, the line before the edge
            local lw = Width(r.label)
            local subRoom = f._w - 24 - lw - 18 - (it.dot and 12 or 0)
            r.sub:SetWidth(math.max(20, subRoom))
            r.label:SetWidth(math.min(lw, f._w - 34))
            if it.dot then
                r.dot:ClearAllPoints()
                r.dot:SetPoint("LEFT", r.label, "LEFT", math.min(lw, f._w - 34) + 6, 0)
                r.dot:Show()
            end
        end
        r:SetHeight(h)
        r:Show()
        y = y + h
    end
    f:SetSize(f._w, y + 3)
end

-- Opens a menu under `btn` (a second click on it closes it). itemsFn() is read
-- on every paint: { label, sub, ink, picked, dot, fn, keep } | { sep = true }
-- | { cap = words }. One menu at a time, closed like the theme's dropdowns.
function SO.OpenMenu(btn, owner, w, itemsFn)
    if AT.openDropdown and AT.openDropdown._owner == btn then
        AT.CloseDropdown()
        return
    end
    AT.CloseDropdown()
    local f = SO.menu
    if not f then
        f = CreateFrame("Frame", nil, owner, "BackdropTemplate")
        AT.Skin(f, COL.panel, COL.focus)
        f:EnableMouse(true)
        f._rows = {}
        SO.menu = f
    end
    f:SetParent(owner)
    f:SetFrameLevel((owner:GetFrameLevel() or 0) + 30)
    f._owner, f._itemsFn, f._w = btn, itemsFn, w
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
    SO.PaintMenu(f)
    f:Show()
    AT.openDropdown = f
end

-- Popovers: New skin, Rename, Export, Import

local function Chip(parent, label)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.text = Text(b, 10, C.offInk)
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(Tr(label))
    b:SetSize(math.max(30, math.ceil(Width(b.text)) + 14), 18)
    AT.Skin(b, C.offBg, C.offEdge)
    function b:Paint(on)
        local ink, edge, bg = C.offInk, C.offEdge, C.offBg
        if on then ink, edge, bg = C.pick, C.pick, C.onBg end
        self.text:SetTextColor(ink[1], ink[2], ink[3])
        self:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    return b
end

local function Input(parent, h)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetHeight(h or 20)
    AT.Skin(e, COL.well)
    e:SetFont(AT.FONT, 11, "")
    e:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    e:SetTextInsets(7, 7, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function() AT.CloseDropdown() end)
    return e
end

-- Places chips left to right from (x0, y0) on `host`, starting a new line when
-- the next would pass `right`; returns the number of lines.
function SO.FlowChips(chips, host, x0, y0, right, h, gap)
    local x, line = x0, 0
    for _, ch in ipairs(chips) do
        local cw = ch:GetWidth() or 0
        if x > x0 and x + cw > right then
            x = x0
            line = line + 1
        end
        ch:ClearAllPoints()
        ch:SetPoint("TOPLEFT", host, "TOPLEFT", x, y0 - line * (h + gap))
        x = x + cw + gap
    end
    return line + 1
end

-- spec: { title, mode = "name" | "string", name, parts (a set, or nil for no
-- Holds row), text, readOnly, ok, onOk(value, parts) -> err }
function SO.OpenPopover(anchor, owner, spec)
    AT.CloseDropdown()
    local p = SO.pop
    if not p then
        p = CreateFrame("Frame", nil, owner, "BackdropTemplate")
        AT.Skin(p, COL.panel, C.offEdge)
        p:EnableMouse(true)
        p.head = CreateFrame("Frame", nil, p, "BackdropTemplate")
        p.head:SetPoint("TOPLEFT", 1, -1)
        p.head:SetPoint("TOPRIGHT", -1, -1)
        p.head:SetHeight(20)
        AT.Skin(p.head, C.head, C.head)
        p.headLine = Line(p.head, C.offEdge)
        p.headLine:SetHeight(1)
        p.headLine:SetPoint("BOTTOMLEFT", 0, 0)
        p.headLine:SetPoint("BOTTOMRIGHT", 0, 0)
        p.title = Text(p.head, 10, C.label)
        p.title:SetPoint("LEFT", 8, 0)
        p.nameLbl = Text(p, 12, C.row)
        p.nameLbl:SetText(Tr("Name"))
        p.input = Input(p, 20)
        p.holdsLbl = Text(p, 12, C.row)
        p.holdsLbl:SetText(Tr("Holds"))
        p.chips = {}
        local B = BS()
        for i, part in ipairs(B.PARTS) do
            local ch = Chip(p, B.PART_WORDS[part])
            ch:SetScript("OnClick", function()
                p._parts[part] = (not p._parts[part]) or nil
                ch:Paint(p._parts[part] == true)
            end)
            p.chips[i] = ch
        end
        p.status = Text(p, 10, C.red)
        p.cancel = AT.MakeQuietButton(p, "Cancel", 64)
        p.cancel:SetScript("OnClick", function() AT.CloseDropdown() end)
        p.ok = AT.MakeSmallButton(p, "Save", 64)
        local function SaveLook()
            p.ok:SetBackdropColor(C.onBg[1], C.onBg[2], C.onBg[3], 1)
            p.ok:SetBackdropBorderColor(C.saveEdge[1], C.saveEdge[2], C.saveEdge[3], 1)
        end
        SaveLook()
        p.ok:HookScript("OnLeave", SaveLook)
        local function Ok()
            local s = p._spec
            if not s then return end
            local err = s.onOk(p.input:GetText(), p._parts)
            if err then
                p.status:SetText(Tr(err))
                p.status:Show()
                return
            end
            AT.CloseDropdown()
        end
        p.ok:SetScript("OnClick", Ok)
        p.input:SetScript("OnEnterPressed", Ok)
        p:SetScript("OnHide", function() p.input:ClearFocus() end)
        SO.pop = p
    end
    p._spec = spec
    p:SetParent(owner)
    p:SetFrameLevel((owner:GetFrameLevel() or 0) + 30)
    p._owner = anchor
    local w = spec.w or SO.POP_W
    p.title:SetText(Tr(spec.title))
    p.status:SetText("")
    p.status:Hide()
    p.ok:SetLabel(spec.ok or "Save", 64)
    p._parts = {}
    for k, v in pairs(spec.parts or {}) do p._parts[k] = v end
    -- rows top to bottom
    local y = -(20 + 9)
    local stringMode = spec.mode == "string"
    p.nameLbl:SetShown(not stringMode)
    p.input:ClearAllPoints()
    if stringMode then
        p.input:SetPoint("TOPLEFT", 10, y)
        p.input:SetPoint("TOPRIGHT", -10, y)
    else
        p.nameLbl:ClearAllPoints()
        p.nameLbl:SetPoint("TOPLEFT", 10, y - 4)
        p.input:SetPoint("TOPLEFT", 54, y)
        p.input:SetPoint("TOPRIGHT", -10, y)
    end
    p.input:SetText(spec.text or spec.name or "")
    y = y - 20 - 8
    local holds = spec.parts ~= nil
    p.holdsLbl:SetShown(holds)
    for i, ch in ipairs(p.chips) do
        ch:SetShown(holds)
        if holds then ch:Paint(p._parts[BS().PARTS[i]] == true) end
    end
    if holds then
        p.holdsLbl:ClearAllPoints()
        p.holdsLbl:SetPoint("TOPLEFT", 10, y - 3)
        -- the chips wrap onto more lines rather than run past the edge
        local lines = SO.FlowChips(p.chips, p, 54, y, w - 10, 18, 4)
        y = y - lines * 18 - (lines - 1) * 4 - 8
    end
    p.status:ClearAllPoints()
    p.status:SetPoint("TOPLEFT", 10, y)
    p.status:SetPoint("TOPRIGHT", -10, y)
    if spec.note then
        p.status:SetText(Tr(spec.note))
        p.status:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
        p.status:Show()
        y = y - 14
    else
        p.status:SetTextColor(C.red[1], C.red[2], C.red[3])
    end
    p.ok:ClearAllPoints()
    p.ok:SetPoint("TOPRIGHT", -10, y - 2)
    p.cancel:ClearAllPoints()
    p.cancel:SetPoint("RIGHT", p.ok, "LEFT", -5, 0)
    p.ok:SetShown(spec.onOk ~= nil)
    p.cancel:SetLabel(spec.onOk and "Cancel" or "Close", 64)
    if not spec.onOk then
        p.cancel:ClearAllPoints()
        p.cancel:SetPoint("TOPRIGHT", -10, y - 2)
    end
    p:SetSize(w, -y + 2 + 20 + 10)
    p:ClearAllPoints()
    p:SetPoint(spec.point or "TOPLEFT", anchor, spec.rel or "BOTTOMLEFT", 0, -4)
    p:Show()
    AT.openDropdown = p
    p.input:SetFocus()
    p.input:HighlightText()
end

-- The bar editor's skin strip

-- "+ New skin from this look": a name (the bar's, and the picked skin's), the
-- parts it holds, Save.
function SO.OpenSaveAs(rec, anchor, owner)
    local B = BS()
    local e = B.EditEntry(rec)
    local name = tostring(rec.name or "")
    if e then name = name .. " " .. SO.SkinName(e) end
    local parts = {}
    for _, p in ipairs(B.PARTS) do parts[p] = true end
    SO.OpenPopover(anchor, owner, { title = "NEW SKIN", name = B.FreeName(name), parts = parts, ok = "Save",
        onOk = function(text, picked)
            if not next(picked) then return "Pick at least one part." end
            local sid = B.NewFromLook(rec, text, picked)
            if not sid then return "This bar wears as many skins as it can." end
        end })
end

-- The skin dropdown's menu: the bar's own look first, this bar's skins with
-- when each switches on, then adding one, a new one from this look, and what
-- to do with this bar's changes over the picked skin.
function SO.SkinMenu(rec, anchor, owner)
    local B = BS()
    local items = {}
    local cur = B.editing[rec.id]
    items[#items + 1] = { label = Tr("Bar's own"), sub = Tr("when no skin applies"),
        picked = (cur == nil or cur == B.BASE), fn = function() B.SetEditing(rec, B.BASE) end }
    for _, e in ipairs(rec.skins or {}) do
        local id = e.id
        items[#items + 1] = { label = SO.SkinName(e), dot = B.Changed(e), sub = SO.CondWords(e),
            picked = cur == id, ink = (B.SkinOf(e) == nil) and C.faint or nil,
            fn = function() B.SetEditing(rec, id) end }
    end
    items[#items + 1] = { sep = true }
    items[#items + 1] = { cap = "ADD A SKIN" }
    for _, it in ipairs(B.List()) do
        local sid = it.sid
        items[#items + 1] = { label = it.skin.name, fn = function()
            local ne = B.AddEntry(rec, sid)
            if ne then B.SetEditing(rec, ne.id) end
        end }
    end
    items[#items + 1] = { label = Tr("+ New skin from this look"), ink = C.green,
        fn = function() SO.OpenSaveAs(rec, anchor, owner) end }
    local e = B.EditEntry(rec)
    if e and B.Changed(e) then
        local n = #B.WornBy(e.skin)
        items[#items + 1] = { sep = true }
        items[#items + 1] = { label = Tr(n == 1 and "Save to skin (%d bar)" or "Save to skin (%d bars)"):format(n),
            fn = function() B.SaveToSkin(rec, e) end }
        items[#items + 1] = { label = Tr("Reset to skin"), fn = function() B.ResetToSkin(rec, e) end }
    end
    if e then
        local id = e.id
        items[#items + 1] = { sep = true }
        items[#items + 1] = { label = Tr("Remove this skin from the bar"), ink = C.red,
            fn = function() B.RemoveEntry(rec, id) end }
    end
    return items
end

function SO.ClassMenu(rec, e)
    local B = BS()
    local items = { { label = Tr("Any class"), picked = e.cls == nil, fn = function() B.SetClass(rec, e, nil) end } }
    for _, c in ipairs(Store.ClassSpecMatrix()) do
        local tag = c.tag
        items[#items + 1] = { label = c.name, ink = SO.ClassColor(tag), picked = e.cls == tag,
            fn = function() B.SetClass(rec, e, tag) end }
    end
    return items
end

-- several specs may be picked: a pick keeps the menu open
function SO.SpecMenu(rec, e)
    local B = BS()
    local items = { { label = Tr("Any spec"), picked = e.specs == nil, fn = function() B.ClearSpecs(rec, e) end } }
    for _, s in ipairs(SpecsOf(e.cls)) do
        local id = s.id
        items[#items + 1] = { label = s.name, picked = e.specs ~= nil and e.specs[id] == true, keep = true,
            fn = function() B.ToggleSpec(rec, e, id) end }
    end
    return items
end

-- The talent the entry follows, picked on the Load Conditions talent tree.
function SO.TalentTarget(rec, e)
    local B = BS()
    return {
        talentTarget = true, noExclude = true,
        State = function(node)
            if e.talentNode ~= node then return nil end
            return "req", e.talentEntry
        end,
        Set = function(node, state, entry)
            if state == nil then
                if e.talentNode == node then B.SetTalent(rec, e, nil) end
            else
                B.SetTalent(rec, e, node, entry)
            end
        end,
        List = function() return e.talentNode and { { nodeID = e.talentNode } } or {} end,
        Clear = function() B.SetTalent(rec, e, nil) end,
    }
end

function SO.TalentMenu(rec, e)
    local B = BS()
    local items = { { label = Tr("Any talent"), picked = e.talentNode == nil, fn = function() B.SetTalent(rec, e, nil) end } }
    if e.talentNode then
        local n = SO.TalentName(e)
        items[#items + 1] = { label = Tr("With %s"):format(n), picked = not e.without,
            fn = function() B.SetWithout(rec, e, false) end }
        items[#items + 1] = { label = Tr("Without %s"):format(n), picked = e.without == true,
            fn = function() B.SetWithout(rec, e, true) end }
        items[#items + 1] = { sep = true }
    end
    items[#items + 1] = { label = Tr(e.talentNode and "Choose another talent" or "Choose a talent"),
        fn = function()
            local t = SO.TalentTarget(rec, e)
            if Options.OpenTalentPicker then Options.OpenTalentPicker(function() return t end) end
        end }
    return items
end

-- The strip: a row under the editor's tabs on Appearance and Text. sel() is
-- the bar in the editor, tabFn() its open tab, owner the window.
function Options.SkinStrip(pg, sel, tabFn, owner)
    local function Rec()
        local r = sel()
        if not (BS() and SO.Offered(r)) then return nil end
        return r
    end
    local function vis()
        local t = tabFn()
        return (t == "Appearance" or t == "Text") and Rec() ~= nil
    end
    local row = AT.AddRow(pg, SO.STRIP_H + 2, vis)
    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 8, 0)
    box:SetPoint("BOTTOMRIGHT", -8, 2)
    AT.Skin(box, COL.box, COL.box)
    local rule = Line(box, COL.line2)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    local mid = -SO.STRIP_H / 2
    local lbl = Text(box, 11, C.label)
    lbl:SetText(Tr("Skin"))
    lbl:SetPoint("LEFT", box, "TOPLEFT", 10, mid)
    local dd = MakeDD(box, SO.SKIN_W)
    dd:SetPoint("LEFT", lbl, "RIGHT", SO.GAP, 0)
    local div = Line(box, COL.line2)
    div:SetSize(1, 18)
    div:SetPoint("LEFT", dd, "RIGHT", SO.GAP, 0)
    local note = Text(box, 11, C.faint)
    note:SetText(Tr("when no skin applies"))
    note:SetPoint("LEFT", div, "RIGHT", SO.GAP, 0)
    local when = Text(box, 11, C.label)
    when:SetText(Tr("when"))
    local cls = MakeDD(box, SO.CLASS_W)
    cls:SetPoint("LEFT", when, "RIGHT", SO.GAP, 0)
    local spec = MakeDD(box, SO.SPEC_W)
    spec:SetPoint("LEFT", cls, "RIGHT", SO.GAP, 0)
    local tal = MakeDD(box, SO.TALENT_W)
    row._adSkin = { box = box, dd = dd, note = note, when = when, cls = cls, spec = spec, tal = tal, lbl = lbl }

    local function E()
        local r = Rec()
        return r, r and BS().EditEntry(r)
    end
    dd:SetScript("OnClick", function()
        local r = Rec()
        if r then SO.OpenMenu(dd, owner, SO.MENU_W, function() return SO.SkinMenu(r, dd, owner) end) end
    end)
    cls:SetScript("OnClick", function()
        local r, e = E()
        if e then SO.OpenMenu(cls, owner, 150, function() return SO.ClassMenu(r, e) end) end
    end)
    spec:SetScript("OnClick", function()
        local r, e = E()
        if e and e.cls and not spec._off then SO.OpenMenu(spec, owner, SO.SPEC_W + 30, function() return SO.SpecMenu(r, e) end) end
    end)
    tal:SetScript("OnClick", function()
        local r, e = E()
        if e and SO.TalentOK(e) then SO.OpenMenu(tal, owner, 210, function() return SO.TalentMenu(r, e) end) end
    end)
    AT.Tooltip(dd, "Skin", "The look the rows below change. Bar's own is the look when no skin applies; a skin switches on when its conditions hold, the first from the top.")
    AT.Tooltip(cls, "Class", "The class this skin switches on for.")
    AT.Tooltip(spec, "Spec", function()
        local _, e = E()
        if e and not e.cls then return Tr("Pick a class first: its specs are listed then.") end
        return Tr("The specs this skin switches on in. Pick several or Any spec.")
    end)
    AT.Tooltip(tal, "Talent", function()
        local _, e = E()
        if e and not SO.TalentOK(e) then return Tr("Talents are picked on your own class's tree.") end
        return Tr("Switches the skin on with a talent, or without it.")
    end)

    row._sync = function()
        local B = BS()
        if not B then return end
        local any = sel()
        -- only the bar in the editor shows a forced look
        for id in pairs(B.editing) do
            if not (any and id == any.id) then B.StopEditing() break end
        end
        local r = Rec()
        if not (r and vis()) then return end
        -- what you see is what you edit: the skin in play, else the bar's own
        if r.skins and B.editing[r.id] == nil then
            local a = B.Active(r)
            B.SetEditing(r, a and a.id or B.BASE)
        end
        local e = B.EditEntry(r)
        dd:Set(e and SO.SkinName(e) or Tr("Bar's own"), nil, e ~= nil and B.Changed(e))
        note:SetShown(e == nil)
        local specsOn = B.SpecsOK()
        when:SetShown(e ~= nil)
        cls:SetShown(e ~= nil)
        spec:SetShown(e ~= nil and specsOn)
        tal:SetShown(e ~= nil)
        tal:ClearAllPoints()
        tal:SetPoint("LEFT", specsOn and spec or cls, "RIGHT", SO.GAP, 0)
        if e then
            cls:Set(e.cls and SO.ClassName(e.cls) or Tr("Any class"), e.cls and SO.ClassColor(e.cls) or nil)
            spec:Set(SO.SpecWords(e))
            spec:SetOff(e.cls == nil)
            tal:Set(SO.TalentWords(e))
            tal:SetOff(not SO.TalentOK(e))
        end
        -- a narrow editor takes the conditions onto a second line
        local w = box:GetWidth()
        if not w or w <= 0 then w = (pg:GetWidth() or 0) - 16 end
        local need = 10 + Width(lbl) + SO.GAP + SO.SKIN_W + SO.GAP + 1 + SO.GAP + Width(when) + SO.GAP
            + SO.CLASS_W + SO.GAP + (specsOn and (SO.SPEC_W + SO.GAP) or 0) + SO.TALENT_W + 10
        local two = e ~= nil and w > 0 and w < need
        when:ClearAllPoints()
        if two then
            when:SetPoint("LEFT", box, "TOPLEFT", 10, mid - SO.STRIP_H + 6)
        else
            when:SetPoint("LEFT", div, "RIGHT", SO.GAP, 0)
        end
        div:SetShown(not two)
        local want = (two and (2 * SO.STRIP_H - 6) or SO.STRIP_H) + 2
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
    end
    -- the editor's editing state ends with the editor
    pg:HookScript("OnHide", function()
        local B = BS()
        if B then B.StopEditing() end
    end)
    return row
end

-- Marks on the rows below while a skin is edited: "every look" on a row the
-- skin does not hold (it stays the same in every look), a dot before the
-- control of a row this bar changes over its skin. They are painted after the
-- bar editor's page is laid out, when every row has its place.
local function PaintMarks(row, every, dot)
    if (every or dot) and not row._adSkinTag then
        local tag = CreateFrame("Frame", nil, row, "BackdropTemplate")
        AT.Skin(tag, COL.box, COL.line2)
        tag.text = Text(tag, 10, C.faint)
        tag.text:SetPoint("CENTER", 0, 0)
        tag.text:SetText(Tr("every look"))
        tag:SetSize(math.ceil(Width(tag.text)) + 12, 15)
        tag:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        tag:Hide()
        row._adSkinTag = tag
        row._adSkinDot = Dot(row, 5)
        row._adSkinDot:Hide()
    end
    local tag = row._adSkinTag
    if not tag then return end
    if every then
        -- only where it clears the row's control
        local left, right = tag:GetLeft(), nil
        for _, c in ipairs({ row:GetChildren() }) do
            if c ~= tag and c:IsShown() then
                local cr = c:GetRight()
                if cr and (not right or cr > right) then right = cr end
            end
        end
        every = not (left and right and left < right + 6)
    end
    tag:SetShown(every == true)
    local d = row._adSkinDot
    if dot and row._ctrlX then
        d:ClearAllPoints()
        d:SetPoint("CENTER", row, "LEFT", row._ctrlX - 8, 0)
        d:Show()
    else
        d:Hide()
    end
end

-- [page] = { sel, tab } for the pages that carry marks (the bar editor's)
SO.markPages = {}

local function MarkRow(row, B, sk, e, on)
    local m = row._adMeta
    if not (m and m.family == "bar" and m.section and m.field and (on or row._adSkinTag)) then return end
    local every, dot = false, false
    if on and row:IsVisible() then
        if B.Held(sk, m.section, m.field) then
            dot = B.ChangedField(e, m.section, m.field)
        else
            every = true
        end
    end
    PaintMarks(row, every, dot)
end

function SO.Marks(pg)
    local spec = SO.markPages[pg]
    local B = BS()
    if not (spec and B) then return end
    local r = spec.sel()
    local e = SO.Offered(r) and B.EditEntry(r) or nil
    local t = spec.tab()
    local sk = e and B.SkinOf(e)
    local on = sk ~= nil and (t == "Appearance" or t == "Text")
    for _, row in ipairs(pg._rows or {}) do MarkRow(row, B, sk, e, on) end
    for _, sec in ipairs(pg._sections or {}) do
        for _, row in ipairs(sec.rows) do MarkRow(row, B, sk, e, on) end
    end
end

function Options.SkinMarks(pg, sel, tabFn)
    SO.markPages[pg] = { sel = sel, tab = tabFn }
end

-- after every layout of a page with marks; hooked at load, so a timing probe
-- that wraps LayoutPage later keeps it
hooksecurefunc(AT, "LayoutPage", function(pg)
    if SO.markPages[pg] then SO.Marks(pg) end
end)

-- The Skins page

local function ResolveTexture(key)
    local Bars = NS.Bars
    if not key or key == "" or key == "Flat" then return AT.WHITE end
    local b = Bars and Bars.BUILTIN_TEXTURES and Bars.BUILTIN_TEXTURES[key]
    if b then return b end
    local lsm = Bars and Bars.GetLSM and Bars.GetLSM()
    local path = lsm and lsm:Fetch("statusbar", key, true)
    return path or AT.WHITE
end

-- A sample bar in a skin's look (fill, texture, background, border, texts).
local function SampleBar(parent, w, h, withText)
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s:SetSize(w, h)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", 0, 0)
    s.fill:SetPoint("BOTTOMLEFT", 0, 0)
    s.edge = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.edge:SetPoint("TOPLEFT", -1, 1)
    s.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    if withText then
        s.name = s:CreateFontString(nil, "OVERLAY")
        s.name:SetPoint("LEFT", 5, 0)
        s.dur = s:CreateFontString(nil, "OVERLAY")
        s.dur:SetPoint("RIGHT", -5, 0)
    end
    function s:Paint(sid, frac, word)
        local B = BS()
        local V = function(sec, f) return B.SkinValue(sid, sec, f) end
        local sk = B.Lib()[sid]
        local parts = sk and sk.parts or {}
        local fc = parts.colors and V("fill", "color") or { 0.2, 0.6, 1, 1 }
        self.fill:SetTexture(ResolveTexture(parts.texture and V("fill", "texture") or ""))
        self.fill:SetVertexColor(fc[1], fc[2], fc[3], fc[4] or 1)
        self.fill:SetWidth(math.max(1, math.floor(self:GetWidth() * (frac or 0.6))))
        local grad = parts.colors and V("fill", "useGradient")
        local gc = V("fill", "gradientColor")
        if self.fill.SetGradient and CreateColor then
            if grad and gc then
                self.fill:SetGradient("HORIZONTAL", CreateColor(fc[1], fc[2], fc[3], fc[4] or 1),
                    CreateColor(gc[1], gc[2], gc[3], gc[4] or 1))
            else
                self.fill:SetGradient("HORIZONTAL", CreateColor(fc[1], fc[2], fc[3], fc[4] or 1),
                    CreateColor(fc[1], fc[2], fc[3], fc[4] or 1))
            end
        end
        local bgOn = not parts.background or V("look", "bgShow")
        local bc = parts.background and V("look", "bgColor") or { 0.4, 0.42, 0.46 }
        self.bg:SetTexture(AT.WHITE)
        self.bg:SetVertexColor(bc[1], bc[2], bc[3], bgOn and (parts.background and V("look", "bgAlpha") or 0.9) or 0)
        local edgeOn = parts.border and V("look", "borderEnabled")
        if edgeOn then
            local ec = V("look", "borderColor") or { 0, 0, 0, 1 }
            self.edge:SetBackdrop({ edgeFile = AT.WHITE, edgeSize = 1 })
            self.edge:SetBackdropBorderColor(ec[1], ec[2], ec[3], ec[4] or 1)
            self.edge:Show()
        else
            self.edge:Hide()
        end
        if self.name then
            local Bars = NS.Bars
            local font = parts.texts and V("text", "font") or ""
            local path = (Bars and Bars.ResolveFont and Bars.ResolveFont(font)) or AT.FONT
            for _, fs in ipairs({ self.name, self.dur }) do
                fs:SetFont(path, 11, "")
                fs:SetShadowColor(0, 0, 0, 1)
                fs:SetShadowOffset(1, -1)
            end
            local nc = parts.texts and V("text", "nameColor") or { 1, 1, 1, 1 }
            local dc = parts.texts and V("text", "durColor") or { 1, 1, 1, 1 }
            self.name:SetText(word or "")
            self.name:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
            self.dur:SetText("10.8")
            self.dur:SetTextColor(dc[1], dc[2], dc[3], dc[4] or 1)
        end
    end
    return s
end

-- "N bars on M classes" (a bar held to no class counts as every class).
function SO.UseWords(sid)
    local B = BS()
    local list = B.WornBy(sid)
    if #list == 0 then return Tr("not worn") end
    local classes, open = {}, false
    for _, r in ipairs(list) do
        local tags, limited = Store.ClassesOf(r)
        if not limited then open = true end
        for _, tag in ipairs(tags) do classes[tag] = true end
    end
    local bars = Tr(#list == 1 and "%d bar" or "%d bars"):format(#list)
    local n = 0
    for _ in pairs(classes) do n = n + 1 end
    if open or n == 0 then return bars end
    return bars .. " " .. Tr(n == 1 and "on %d class" or "on %d classes"):format(n)
end

-- A worn-by chip's second word: the class the bar holds to, in its colour.
function SO.Owner(rec)
    local tags, limited = Store.ClassesOf(rec)
    if not limited then return Tr("every class"), C.faint end
    if #tags == 1 then return SO.ClassName(tags[1]), SO.ClassColor(tags[1]) end
    return Tr("%d classes"):format(#tags), C.faint
end

local page   -- the page's parts, once built

local function Sel()
    local B = BS()
    if not B then return nil end
    local lib = B.Lib()
    if SO.sel and lib[SO.sel] then return SO.sel end
    local list = B.List()
    SO.sel = list[1] and list[1].sid or nil
    return SO.sel
end

local function ListRow(parent, i)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(SO.LIST_ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * SO.LIST_ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * SO.LIST_ROW_H)
    AT.Skin(r, COL.box, COL.box)
    r.edge = Line(r, COL.arc)
    r.edge:SetWidth(2)
    r.edge:SetPoint("TOPLEFT", 0, 0)
    r.edge:SetPoint("BOTTOMLEFT", 0, 0)
    r.sep = Line(r, C.rowLine)
    r.sep:SetHeight(1)
    r.sep:SetPoint("BOTTOMLEFT", 0, 0)
    r.sep:SetPoint("BOTTOMRIGHT", 0, 0)
    r.name = Text(r, 12, C.row)
    r.name:SetPoint("TOPLEFT", 10, -10)
    r.use = Text(r, 10, C.faint)
    r.use:SetPoint("TOPRIGHT", -10, -11)
    r.use:SetJustifyH("RIGHT")
    r.bar = SampleBar(r, SO.LIST_W - 52, 12, false)
    r.bar:SetPoint("TOPLEFT", 10, -33)
    r:SetScript("OnClick", function()
        SO.sel = r._sid
        SO.Refresh()
    end)
    return r
end

function SO.Fill(pane, h, owner)
    local B = BS()
    page = { pane = pane, h = h, owner = owner, rows = {} }
    h.name:SetText(Tr("Skins"))
    if h.chip1 and h.chip1.Set then h.chip1:Set(Tr("every character"), C.offInk) end
    if h.chip2 and h.chip2.Set then h.chip2:Set("", C.offInk) end
    -- the header's actions: + New Skin (green, the board's) and Import
    local imp = AT.MakeSmallButton(pane, "Import", 60)
    imp:SetPoint("TOPRIGHT", -4, -2)
    local new = AT.MakeSmallButton(pane, "+ New Skin", 84)
    new:SetPoint("RIGHT", imp, "LEFT", -5, 0)
    new.fs:SetTextColor(C.green[1], C.green[2], C.green[3])
    local function GreenEdge() new:SetBackdropBorderColor(C.greenEdge[1], C.greenEdge[2], C.greenEdge[3], 1) end
    GreenEdge()
    new:HookScript("OnLeave", GreenEdge)
    h._btns = { new, imp }
    new:SetScript("OnClick", function()
        local parts = {}
        for _, p in ipairs(B.PARTS) do parts[p] = true end
        SO.OpenPopover(new, owner, { title = "NEW SKIN", name = B.FreeName(Tr("New skin")), parts = parts,
            point = "TOPRIGHT", rel = "BOTTOMRIGHT",
            onOk = function(text, picked)
                if not next(picked) then return "Pick at least one part." end
                SO.sel = B.Create(text, picked, nil)
                SO.Refresh()
            end })
    end)
    imp:SetScript("OnClick", function()
        SO.OpenPopover(imp, owner, { title = "IMPORT A SKIN", mode = "string", text = "", ok = "Import", w = 340,
            point = "TOPRIGHT", rel = "BOTTOMRIGHT",
            onOk = function(text)
                local sid, err = B.ImportString(text)
                if not sid then return err or "Import failed." end
                SO.sel = sid
                SO.Refresh()
            end })
    end)
    AT.Tooltip(new, "+ New Skin", "A skin made from the default look. A bar's Skin dropdown makes one from that bar's look.")
    AT.Tooltip(imp, "Import", "Paste a skin string someone shared.")

    -- the list of skins on the left
    local list = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 6, -40)
    list:SetPoint("BOTTOMLEFT", 6, 6)
    list:SetWidth(SO.LIST_W)
    AT.Skin(list, COL.box, C.offEdge)
    local lh = CreateFrame("Frame", nil, list, "BackdropTemplate")
    lh:SetPoint("TOPLEFT", 1, -1)
    lh:SetPoint("TOPRIGHT", -1, -1)
    lh:SetHeight(21)
    AT.Skin(lh, C.head, C.head)
    local lhl = Line(lh, C.offEdge)
    lhl:SetHeight(1)
    lhl:SetPoint("BOTTOMLEFT", 0, 0)
    lhl:SetPoint("BOTTOMRIGHT", 0, 0)
    local lt = Text(lh, 10, C.label)
    lt:SetPoint("LEFT", 8, 0)
    lt:SetText(Tr("SKINS"))
    page.count = Text(lh, 11, COL.ink)
    page.count:SetPoint("RIGHT", -8, 0)
    local host, content = AT.MakeScroll(list)
    host:SetPoint("TOPLEFT", 1, -22)
    host:SetPoint("BOTTOMRIGHT", -1, 1)
    page.host, page.content = host, content
    page.empty = Text(list, 11, C.faint)
    page.empty:SetPoint("TOPLEFT", 10, -32)
    page.empty:SetPoint("TOPRIGHT", -10, -32)
    page.empty:SetWordWrap(true)
    page.empty:SetText(Tr("No skins yet. Make one with + New Skin, or from a bar's Skin dropdown."))
    Options.BuildYield()

    -- the picked skin on the right
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 6 + SO.LIST_W + 6, -36)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    pg:Show()
    page.pg = pg
    local has = function() return Sel() ~= nil end

    local nameRow = AT.AddRow(pg, 30, has)
    local nm = Text(nameRow, 15, COL.ink)
    nm:SetPoint("LEFT", 10, 0)
    local del = AT.MakeQuietButton(nameRow, "Delete Skin", 56)
    del:SetPoint("RIGHT", -8, 0)
    local exp = AT.MakeSmallButton(nameRow, "Export", 56)
    exp:SetPoint("RIGHT", del, "LEFT", -5, 0)
    local dup = AT.MakeSmallButton(nameRow, "Duplicate", 70)
    dup:SetPoint("RIGHT", exp, "LEFT", -5, 0)
    local ren = AT.MakeSmallButton(nameRow, "Rename", 60)
    ren:SetPoint("RIGHT", dup, "LEFT", -5, 0)
    nameRow._sync = function()
        local sid = Sel()
        local sk = sid and B.Lib()[sid]
        nm:SetText(sk and sk.name or "")
        local room = (nameRow:GetWidth() or 0) - 10 - 60 - 70 - 56 - 56 - 30
        if room > 40 then nm:SetWidth(math.min(Width(nm) + 2, room)) end
    end
    ren:SetScript("OnClick", function()
        local sid = Sel()
        local sk = sid and B.Lib()[sid]
        if not sk then return end
        SO.OpenPopover(ren, owner, { title = "RENAME", name = sk.name, point = "TOPRIGHT", rel = "BOTTOMRIGHT",
            onOk = function(text) B.Rename(sid, text) SO.Refresh() end })
    end)
    dup:SetScript("OnClick", function()
        local sid = Sel()
        local nid = sid and B.Duplicate(sid)
        if nid then SO.sel = nid SO.Refresh() end
    end)
    exp:SetScript("OnClick", function()
        local sid = Sel()
        local s, err = sid and B.ExportString(sid)
        SO.OpenPopover(exp, owner, { title = "EXPORT", mode = "string", text = s or "", w = 340,
            note = s and "Copy it with Ctrl+C." or (err or "Export failed."), point = "TOPRIGHT", rel = "BOTTOMRIGHT" })
    end)
    del:SetScript("OnClick", function()
        local sid = Sel()
        local sk = sid and B.Lib()[sid]
        if not sk then return end
        StaticPopupDialogs["ARCUIV2_SKIN_DELETE"] = StaticPopupDialogs["ARCUIV2_SKIN_DELETE"] or {
            button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        local d = StaticPopupDialogs["ARCUIV2_SKIN_DELETE"]
        d.text = Tr("Delete the skin \"%s\"? The bars that wear it keep its look as their own."):format(sk.name)
        d.OnAccept = function()
            B.Delete(sid)
            SO.sel = nil
            SO.Refresh()
        end
        StaticPopup_Show("ARCUIV2_SKIN_DELETE")
    end)
    AT.Tooltip(del, "Delete Skin", "The bars that wear it keep its look as their own.")
    AT.Tooltip(exp, "Export", "A string to share this skin.")
    Options.BuildYield()

    -- the preview: a sample bar on the slate the bar editor's preview uses
    local prev = AT.AddRow(pg, 76, has)
    local slate = CreateFrame("Frame", nil, prev, "BackdropTemplate")
    slate:SetPoint("TOPLEFT", 8, -4)
    slate:SetPoint("BOTTOMRIGHT", -8, 2)
    AT.Skin(slate, C.slate, C.slateEdge)
    local sample = SampleBar(slate, 195, 19, true)
    sample:SetPoint("CENTER", 0, 0)
    prev._sync = function()
        local sid = Sel()
        if not sid then return end
        local worn = B.WornBy(sid)
        sample:Paint(sid, 0.6, worn[1] and worn[1].name or Tr("Sample"))
    end

    -- In this skin: the parts it holds
    local partsRow = AT.AddRow(pg, 30, has)
    local pl = Text(partsRow, 11, C.label)
    -- on the first line of chips, however many lines they take
    pl:SetPoint("LEFT", partsRow, "TOPLEFT", 10, -15)
    pl:SetText(Tr("In this skin"))
    local chips = {}
    for i, part in ipairs(B.PARTS) do
        local ch = Chip(partsRow, B.PART_WORDS[part])
        ch:SetHeight(20)
        ch:SetScript("OnClick", function()
            local sid = Sel()
            local sk = sid and B.Lib()[sid]
            if sk then B.SetPart(sid, part, not (sk.parts and sk.parts[part])) SO.Refresh() end
        end)
        AT.Tooltip(ch, B.PART_WORDS[part], "On: the skin sets it for every bar that wears it. Off: each bar keeps its own.")
        chips[i] = ch
    end
    partsRow._sync = function()
        local sid = Sel()
        local sk = sid and B.Lib()[sid]
        for i, part in ipairs(B.PARTS) do chips[i]:Paint(sk ~= nil and sk.parts[part] == true) end
        -- a narrow page wraps the chips; the row grows with them
        local w = partsRow:GetWidth() or 0
        if w <= 0 then w = (pg:GetWidth() or 0) - 4 end
        if w <= 0 then w = 600 end
        local lines = SO.FlowChips(chips, partsRow, 87, -5, w - 10, 20, 5)
        local want = lines * 20 + (lines - 1) * 5 + 10
        if partsRow._h ~= want then
            partsRow._h = want
            partsRow:SetHeight(want)
        end
    end
    Options.BuildYield()

    -- the parts' rows, as the bar editor words them; a part left out reads
    -- "each bar's own"
    local function In(part)
        return function()
            local sid = Sel()
            local sk = sid and B.Lib()[sid]
            return sk ~= nil and sk.parts[part] == true
        end
    end
    local function Out(part)
        local inn = In(part)
        return function() return Sel() ~= nil and not inn() end
    end
    local function Get(section, field) return function() return B.SkinValue(Sel(), section, field) end end
    local function Put(section, field)
        return function(v)
            local sid = Sel()
            if sid then B.SetSkinValue(sid, section, field, v) SO.Refresh() end
        end
    end
    local function ColorRow(label, part, section, field)
        AT.RowColor(pg, label, function() return Get(section, field)() or { 1, 1, 1, 1 } end,
            function(c)
                local old = Get(section, field)() or {}
                Put(section, field)({ c[1], c[2], c[3], c[4] or old[4] or 1 })
            end, In(part))
    end
    local function OffRow(label, part)
        local row = AT.AddRow(pg, AT.LAY.rowH, Out(part))
        local l = AT.RowLabel(row, label)
        if l and l.SetTextColor then l:SetTextColor(C.faint[1], C.faint[2], C.faint[3]) end
        local t = Text(row, 11, C.faint)
        t:SetFont(AT.FONT, 11, "")
        t:SetText(Tr("each bar's own"))
        t:SetPoint("LEFT", row._ctrlX or AT.LAY.ctrl, 0)
        row._sync = function() t:SetPoint("LEFT", row._ctrlX or AT.LAY.ctrl, 0) end
    end
    local has2 = has
    AT.Section(pg, "Fill", { visibleFn = has2 })
    ColorRow("Fill color", "colors", "fill", "color")
    OffRow("Fill color", "colors")
    AT.RowDropdown(pg, owner, "Bar texture",
        function()
            local v = B.SkinValue(Sel(), "fill", "texture")
            return (v == nil or v == "") and "Flat" or v
        end,
        function(v) Put("fill", "texture")(v == "Flat" and "" or v) end,
        function() return Options.MediaItems("statusbar") end, In("texture"))
    OffRow("Bar texture", "texture")
    AT.RowToggle(pg, "Gradient fill", function() return Get("fill", "useGradient")() == true end,
        function(v) Put("fill", "useGradient")(v == true) end, In("colors"))
    OffRow("Gradient fill", "colors")
    Options.BuildYield()
    AT.Section(pg, "Background", { visibleFn = has2 })
    ColorRow("Background color", "background", "look", "bgColor")
    OffRow("Background color", "background")
    Options.BuildYield()
    AT.Section(pg, "Border", { visibleFn = has2 })
    AT.RowToggle(pg, "Border", function() return Get("look", "borderEnabled")() == true end,
        function(v) Put("look", "borderEnabled")(v == true) end, In("border"))
    OffRow("Border", "border")
    ColorRow("Border color", "border", "look", "borderColor")
    OffRow("Border color", "border")
    Options.BuildYield()
    AT.Section(pg, "Texts", { visibleFn = has2 })
    AT.RowDropdown(pg, owner, "Font", function() return B.SkinValue(Sel(), "text", "font") end,
        Put("text", "font"), Options.FontItems, In("texts"))
    OffRow("Font", "texts")
    ColorRow("Name color", "texts", "text", "nameColor")
    OffRow("Name color", "texts")
    ColorRow("Duration color", "texts", "text", "durColor")
    OffRow("Duration color", "texts")
    Options.BuildYield()

    -- WORN BY: a chip per bar (and the class it holds to); a click opens the bar
    local wornHead = AT.AddRow(pg, 24, has)
    local wh = CreateFrame("Frame", nil, wornHead, "BackdropTemplate")
    wh:SetPoint("TOPLEFT", 8, -2)
    wh:SetPoint("BOTTOMRIGHT", -8, 0)
    AT.Skin(wh, C.head, C.offEdge)
    local wt = Text(wh, 10, C.label)
    wt:SetPoint("LEFT", 8, 0)
    wt:SetText(Tr("WORN BY"))
    local wu = Text(wh, 11, COL.ink)
    wu:SetPoint("RIGHT", -8, 0)
    wornHead._sync = function()
        local sid = Sel()
        wu:SetText(sid and SO.UseWords(sid) or "")
    end
    local wornBox = AT.AddRow(pg, 40, has)
    local wb = CreateFrame("Frame", nil, wornBox, "BackdropTemplate")
    wb:SetPoint("TOPLEFT", 8, 0)
    wb:SetPoint("BOTTOMRIGHT", -8, 0)
    AT.Skin(wb, COL.box, C.offEdge)
    local none = Text(wb, 11, C.faint)
    none:SetPoint("TOPLEFT", 10, -12)
    none:SetText(Tr("No bar wears it yet"))
    local wchips = {}
    wornBox._sync = function()
        local sid = Sel()
        local list = sid and B.WornBy(sid) or {}
        for _, c in ipairs(wchips) do c:Hide() end
        none:SetShown(#list == 0)
        local w = (wb:GetWidth() or 0)
        if w <= 0 then w = (pg:GetWidth() or 400) - 16 end
        local x, y, lineH = 8, -8, 20
        for i, rec in ipairs(list) do
            local c = wchips[i]
            if not c then
                c = CreateFrame("Button", nil, wb, "BackdropTemplate")
                c:SetHeight(lineH)
                AT.Skin(c, C.head, C.offEdge)
                c.a = Text(c, 11, COL.ink)
                c.a:SetPoint("LEFT", 8, 0)
                c.b = Text(c, 11, C.faint)
                c.b:SetPoint("LEFT", c.a, "RIGHT", 6, 0)
                c:SetScript("OnClick", function() if c._id then Options.Select("bar", c._id) end end)
                wchips[i] = c
            end
            c._id = rec.id
            c.a:SetText(tostring(rec.name or ""))
            local word, ink = SO.Owner(rec)
            c.b:SetText(word)
            c.b:SetTextColor(ink[1], ink[2], ink[3])
            local cw = math.ceil(Width(c.a) + Width(c.b)) + 22
            if x > 8 and x + cw > w - 8 then
                x = 8
                y = y - lineH - 5
            end
            c:SetWidth(cw)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x, y)
            c:Show()
            x = x + cw + 5
        end
        local want = (#list == 0) and 40 or (-y + lineH + 8)
        if wornBox._h ~= want then
            wornBox._h = want
            wornBox:SetHeight(want)
        end
    end
end

local function PaintList()
    local B = BS()
    local list = B.List()
    local sel = Sel()
    page.count:SetText(tostring(#list))
    page.empty:SetShown(#list == 0)
    for _, r in ipairs(page.rows) do r:Hide() end
    for i, it in ipairs(list) do
        local r = page.rows[i]
        if not r then
            r = ListRow(page.content, i)
            page.rows[i] = r
        end
        r._sid = it.sid
        local on = it.sid == sel
        local bg = on and C.onBg or COL.box
        r:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        r:SetBackdropBorderColor(bg[1], bg[2], bg[3], 1)
        r.edge:SetShown(on)
        r.name:SetText(it.skin.name)
        local ink = on and COL.ink or C.row
        r.name:SetTextColor(ink[1], ink[2], ink[3])
        r.use:SetText(SO.UseWords(it.sid))
        r.name:SetWidth(math.max(40, SO.LIST_W - 30 - Width(r.use)))
        r.bar:Paint(it.sid, 0.64)
        r:Show()
    end
    page.content:SetSize(SO.LIST_W - 2, math.max(1, #list * SO.LIST_ROW_H))
    if page.host.UpdateScroll then page.host:UpdateScroll() end
end

function SO.Refresh()
    if not (page and BS()) then return end
    PaintList()
    AT.LayoutPage(page.pg)
    if Options.FitHeader then Options.FitHeader(page.h) end
end
