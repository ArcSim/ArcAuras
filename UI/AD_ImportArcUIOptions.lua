-- AD_ImportArcUIOptions: Import from Arc UI, the "Arc UI" tab of the Import / Export
-- page (UI\AD_Options.lua hosts it through IW.TabShown, IW.BuildPane and IW.Refresh).
-- Left, the characters with Arc UI data, yours first; right, the picked one's Icons (a
-- box per spec listing every Arc UI profile, its groups as chips), Bars (a box per
-- kind, a row per bar) and Textures; the foot bar sums up the picks and Import runs
-- ImportArcUI.Apply. A part imported before can be picked again: it comes in as a
-- fresh copy. The New Layout card, the login offer and /arcui2 arcui open the tab.
-- Retail only; at login only the offer's quick gate runs (Store.UI().arcuiOffer).
local ADDON, NS = ...
if NS.IsForever == true then return end

local Options = NS.Options
if not Options then return end

local IW = {}
Options.ImportArcUI = IW

-- Sizes in UI units: the design board draws its window at 1.17 times these.
IW.CHARS_W = 214      -- the CHARACTERS box
IW.CHAR_H = 22        -- a character row
IW.HEAD_H = 26        -- a box's header strip, as the page's own boxes
IW.NOTE_H = 26        -- the tab's one-line note, then the boxes
IW.GAP = 10           -- between the columns, and over the foot bar
IW.BOX_GAP = 8        -- between the right column's boxes
IW.SUB_H = 26         -- the Icons / Bars / Textures strip
IW.ROW_H = 24         -- a profile row
IW.BAR_H = 22         -- a bar row
IW.TEX_H = 30         -- a texture row
IW.CHIP_H = 20
IW.CHIP_X = 32        -- the chips start under the profile's name
IW.FOOT_H = 40        -- the foot bar, Import on it
IW.LIST_FOOT_H = 28   -- Tick all and Untick all under the characters
IW.SWATCH_W, IW.SWATCH_H = 40, 10
IW.THUMB_W, IW.THUMB_H = 44, 26
-- a box lists its own kind and the kinds Arc UI made from the same tab (a summon's or a
-- mirrored aura bar comes in as a Cooldown Manager bar)
IW.BAR_BOXES = { { "aura", "AURA BARS", also = { cdmbar = true } }, { "cooldown", "COOLDOWN BARS" },
    { "resource", "RESOURCE BARS" }, { "cast", "CAST BARS" }, { "timer", "TIMER BARS" } }
IW.TABS = { { "icons", "Icons" }, { "bars", "Bars" }, { "tex", "Textures" } }
IW.LATER_TIP = "Arc Auras takes this kind with a later update of the import."

local pane, plan, offer
local picks, opened = {}, {}
local sel, sub = nil, "icons"
-- the foot bar's lines after an import or a refusal: { text, text2, bad }
local said
local W = { chars = {}, boxes = {}, rows = {}, chips = {} }
-- for harnesses: the widgets, and the state they paint
IW.W = W
function IW.Get()
    return { plan = plan, picks = picks, sel = sel, sub = sub, said = said, opened = opened, pane = pane }
end

-- the page's parts, shared with the Proc Tracker tab (UI\AD_Options.lua)
local function Font(parent, size, col) return Options.ImportKit.Line(parent, size, col) end
local function Box(parent) return Options.ImportKit.Box(parent, "") end
local function Check(parent) return Options.ImportKit.Check(parent) end
local function Pill(parent)
    local p = Options.ImportKit.Pill(parent)
    local set = p.Set
    -- a tag by its name: "use", "done", "later", "you"
    function p:Set(kind) set(self, Options.ImportKit.TAGS[kind]) end
    return p
end

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- The leaf units under a node (a leaf is its own).
local function Leaves(node, out)
    out = out or {}
    if node.unit then out[#out + 1] = node return out end
    for _, ch in ipairs(node.children or {}) do Leaves(ch, out) end
    return out
end

-- "on" every leaf picked, "part" some, "off" none
local function State(list)
    local on = 0
    for _, lf in ipairs(list) do if picks[lf.unit] then on = on + 1 end end
    if on == 0 then return "off" end
    return (on == #list) and "on" or "part"
end

local function SetAll(list, on)
    for _, lf in ipairs(list) do picks[lf.unit] = on or nil end
end

local function Kids(node, kind)
    local out = {}
    for _, ch in ipairs(node and node.children or {}) do if ch.kind == kind then out[#out + 1] = ch end end
    return out
end

local function CharNode(key)
    for _, node in ipairs(plan and plan.tree or {}) do if node.charKey == key then return node end end
    return nil
end

-- The characters, yours first, then by name (the plan's order).
local function Order()
    local IA = NS.ImportArcUI
    local me = IA and IA.CurrentChar()
    local out = {}
    for _, node in ipairs(plan and plan.tree or {}) do if node.charKey == me then out[1] = node end end
    for _, node in ipairs(plan and plan.tree or {}) do if node.charKey ~= me then out[#out + 1] = node end end
    return out, me
end

local function Live(unit)
    local IA = NS.ImportArcUI
    return IA ~= nil and IA.UnitLive(unit, plan)
end

local function AnyLive(list)
    for _, lf in ipairs(list) do if Live(lf.unit) then return true end end
    return false
end

local function ClassColor(tag)
    local all = rawget(_G, "RAID_CLASS_COLORS")
    local cc = tag and all and all[tag]
    if cc then return { cc.r, cc.g, cc.b } end
    return NS.AT.COL.ink
end

local function ClassName(tag)
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    return (tag and names and names[tag]) or ""
end

-- Where a bar or texture loads, from its spec ids: "All specs" with none or all.
local function SpecsText(node, specs)
    if type(specs) ~= "table" or next(specs) == nil then return "All specs" end
    local ids = {}
    for id in pairs(specs) do ids[#ids + 1] = id end
    local total = rawget(_G, "GetNumSpecializationsForClassID")
    total = node.classID and total and total(node.classID)
    if total and #ids >= total then return "All specs" end
    table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local byId = rawget(_G, "GetSpecializationInfoByID")
    local names = {}
    for _, id in ipairs(ids) do
        local name
        if byId then name = select(2, byId(id)) end
        names[#names + 1] = name or tostring(id)
    end
    return table.concat(names, ", ")
end

-- A bar row's words after its name, as the board writes them.
local function BarDetail(B)
    local d = B.driver or {}
    if B.barKind == "aura" then
        local who = (d.unit == "pet") and "Pet buff" or (d.auraType == "debuff") and "Debuff" or "Buff"
        return who .. ", " .. ((B.barMode == "duration") and "duration" or "stacks")
    elseif B.barKind == "cooldown" then
        return (B.barMode == "stack") and "Charges" or "Cooldown"
    elseif B.barKind == "resource" then
        return (d.powerType == -1) and "Follows the power in use" or ""
    elseif B.barKind == "cast" then
        return (d.unit == "focus") and "Focus" or (d.unit == "target") and "Target" or "You"
    elseif B.barKind == "cdmbar" then
        return "Cooldown Manager bar"
    end
    return ""
end

-- A bar's look in small: its colour, as a fill or as its stacks, charges or points.
local function BarSwatch(B)
    local o, d = B.o or {}, B.driver or {}
    local fill = o.fill and o.fill.color
    local col
    if type(fill) == "table" and type(fill[1]) == "number" then col = { fill[1], fill[2], fill[3] } end
    if not col and B.barKind == "resource" then
        local P = NS.Bars and NS.Bars.POWER_ALL and NS.Bars.POWER_ALL[d.powerType]
        if P then col = P.color end
    end
    col = col or { 0.3, 0.6, 0.9 }
    local cells = 0
    if B.barKind == "aura" and B.barMode ~= "duration" then
        cells = math.min(math.max(tonumber(d.maxStacks) or 5, 2), 10)
    elseif B.barKind == "cooldown" and B.barMode == "stack" then
        cells = 2
    elseif B.barKind == "resource" and o.resource and o.resource.style == "pips" then
        cells = (d.powerType == 5) and 6 or 5
    end
    return { color = col, cells = cells }
end

-- The groups and icons a profile brings: what is picked, or all of it with none picked.
local function ProfileCounts(leaves)
    local any = false
    for _, lf in ipairs(leaves) do if picks[lf.unit] then any = true end end
    local groups, inGroups, icons = 0, 0, 0
    for _, lf in ipairs(leaves) do
        local counted = not any or picks[lf.unit] == true
        if lf.kind == "group" then
            groups = groups + 1
            if counted then inGroups = inGroups + 1 end
        end
        if counted then icons = icons + (lf.n or 0) end
    end
    local g = Plural(groups, "group", "groups")
    if any and inGroups < groups then g = inGroups .. " of " .. g end
    return g .. " · " .. Plural(icons, "icon", "icons")
end

local function ProfileTip(spec, p)
    local sname = spec.label or ""
    local tip
    if p.tag == "active" then
        tip = ("In use on %s in Arc UI: loads on %s."):format(sname, sname)
    else
        tip = "A spare profile in Arc UI: its groups and icons come in switched off; turn them on in their Load tab."
    end
    if p.linked then tip = tip .. (" Its groups come from Arc UI's shared layout '%s'."):format(p.linked) end
    return tip
end

-- Any tick clears what the foot bar said after the last import.
local function Touch()
    said = nil
    IW.Refresh()
end

-- Pooled rows, chips and boxes of the right column.
local function CharRow(i)
    local r = W.chars[i]
    if r then return r end
    local AT, COL = NS.AT, NS.AT.COL
    r = CreateFrame("Button", nil, W.charList)
    r:SetHeight(IW.CHAR_H)
    r:SetHighlightTexture(AT.WHITE)
    r:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(COL.sel[1], COL.sel[2], COL.sel[3], 1)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT", 0, 0)
    r.bar:SetPoint("BOTTOMLEFT", 0, 0)
    r.bar:SetWidth(2)
    r.bar:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    r.check = Check(r)
    r.check:SetPoint("LEFT", 8, 0)
    r.name = Font(r, 12, COL.ink)
    r.name:SetPoint("LEFT", r.check, "RIGHT", 7, 0)
    r.you = Pill(r)
    r.you:Set("you")
    r.you:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.realm = Font(r, 11, COL.faint)
    r.check:SetScript("OnClick", function() if r.onTick then r.onTick() end end)
    r:SetScript("OnClick", function() if r.onPick then r.onPick() end end)
    r:HookScript("OnEnter", function() r.check:SetHover(true) end)
    r:HookScript("OnLeave", function() r.check:SetHover(false) end)
    W.chars[i] = r
    return r
end

local function Row(i)
    local r = W.rows[i]
    if r then return r end
    local AT, COL = NS.AT, NS.AT.COL
    r = CreateFrame("Button", nil, W.body)
    r:SetHighlightTexture(AT.WHITE)
    r:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    r.check = Check(r)
    r.check:SetPoint("LEFT", 10, 0)
    r.swatch = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.swatch:SetSize(IW.SWATCH_W, IW.SWATCH_H)
    AT.Skin(r.swatch, COL.well, COL.line2)
    r.fill = r.swatch:CreateTexture(nil, "ARTWORK")
    r.fill:SetPoint("TOPLEFT", 2, -2)
    r.fill:SetPoint("BOTTOMLEFT", 2, 2)
    r.cells = {}
    r.thumb = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.thumb:SetSize(IW.THUMB_W, IW.THUMB_H)
    AT.Skin(r.thumb, COL.well, COL.line2)
    r.art = r.thumb:CreateTexture(nil, "ARTWORK")
    r.art:SetPoint("CENTER")
    r.name = Font(r, 12, COL.ink)
    r.detail = Font(r, 11, COL.faint)
    r.pills = { Pill(r), Pill(r) }
    r.right = Font(r, 11, COL.dim)
    r.right:SetJustifyH("RIGHT")
    r.chev = CreateFrame("Button", nil, r)
    r.chev:SetSize(20, 20)
    r.chev:SetPoint("RIGHT", -4, 0)
    r.chev.arrow = AT.MakeChevron(r.chev)
    r.chev.arrow:SetPoint("CENTER")
    r.check:SetScript("OnClick", function() if r.onTick then r.onTick() end end)
    r:SetScript("OnClick", function() if r.onTick then r.onTick() end end)
    r.chev:SetScript("OnClick", function() if r.onChev then r.onChev() end end)
    r:HookScript("OnEnter", function() r.check:SetHover(r.onTick ~= nil) end)
    r:HookScript("OnLeave", function() r.check:SetHover(false) end)
    AT.Tooltip(r, function() return r.tipT end, function() return r.tipB end)
    W.rows[i] = r
    return r
end

local function Chip(i)
    local c = W.chips[i]
    if c then return c end
    local AT, COL = NS.AT, NS.AT.COL
    c = CreateFrame("Button", nil, W.body, "BackdropTemplate")
    c:SetHeight(IW.CHIP_H)
    AT.Skin(c, COL.sel, COL.steel)
    c.fs = Font(c, 11, COL.ink)
    c.fs:SetPoint("CENTER", 0, 0)
    function c:Paint()
        if self.lit then
            self:SetBackdropColor(COL.sel[1], COL.sel[2], COL.sel[3], 1)
            self:SetBackdropBorderColor(COL.steel[1], COL.steel[2], COL.steel[3], 1)
            self.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        else
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            self.fs:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        end
    end
    c:SetScript("OnClick", function() if c.onClick then c.onClick() end end)
    c:SetScript("OnEnter", function() c:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    c:SetScript("OnLeave", function() c:Paint() end)
    -- only a chip that left something out says so (c.tipB)
    AT.Tooltip(c, function() return c.tipT end, function() return c.tipB end)
    W.chips[i] = c
    return c
end

local function PaintSwatch(r, s)
    local COL = NS.AT.COL
    local innerW = IW.SWATCH_W - 4
    for _, t in ipairs(r.cells) do t:Hide() end
    if s.cells > 0 then
        r.fill:Hide()
        local cw = (innerW - (s.cells - 1)) / s.cells
        local lit = math.max(1, math.floor(s.cells * 0.6 + 0.5))
        for j = 1, s.cells do
            local t = r.cells[j]
            if not t then
                t = r.swatch:CreateTexture(nil, "ARTWORK")
                r.cells[j] = t
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", r.swatch, "TOPLEFT", 2 + (j - 1) * (cw + 1), -2)
            t:SetSize(cw, IW.SWATCH_H - 4)
            local c = (j <= lit) and s.color or COL.head
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:Show()
        end
    else
        r.fill:SetColorTexture(s.color[1], s.color[2], s.color[3], 1)
        r.fill:SetWidth(math.floor(innerW * 0.65 + 0.5))
        r.fill:Show()
    end
end

-- A texture's own picture, fitted to its shape.
local function PaintThumb(r, t)
    local sc = math.min((IW.THUMB_W - 6) / t.w, (IW.THUMB_H - 6) / t.h)
    r.art:SetSize(math.max(4, t.w * sc), math.max(4, t.h * sc))
    if t.art and t.atlas then
        r.art:SetAtlas(t.art)
    elseif t.art then
        r.art:SetTexture(t.art)
    else
        local COL = NS.AT.COL
        r.art:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.5)
    end
end

-- One row's parts, left to right: tick, swatch or picture, name, words, tags, then the
-- right-hand words and the chevron. o.check nil hides the tick; o.noTick dims it.
local function PaintRow(r, x, y, w, h, o)
    local COL = NS.AT.COL
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", W.body, "TOPLEFT", x, -y)
    r:SetSize(w, h)
    r:SetFrameLevel(W.body:GetFrameLevel() + 3)
    local anchor, gap = nil, 9
    if o.check then
        r.check:SetState(o.check)
        r.check:SetAlpha(o.noTick and 0.35 or 1)
        r.check:EnableMouse(not o.noTick)
        r.check:Show()
        anchor = r.check
    else
        r.check:Hide()
    end
    r.swatch:Hide()
    r.thumb:Hide()
    local function Next(region, dx)
        region:ClearAllPoints()
        if anchor then region:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
        else region:SetPoint("LEFT", r, "LEFT", 12, 0) end
        anchor = region
    end
    if o.swatch then
        Next(r.swatch, gap)
        r.swatch:Show()
        PaintSwatch(r, o.swatch)
    elseif o.thumb then
        Next(r.thumb, gap)
        r.thumb:Show()
        PaintThumb(r, o.thumb)
    end
    Next(r.name, gap)
    r.name:SetText(o.name or "")
    local nc = o.nameCol or COL.ink
    r.name:SetTextColor(nc[1], nc[2], nc[3])
    if o.detail and o.detail ~= "" then
        Next(r.detail, 8)
        r.detail:SetText(o.detail)
        r.detail:Show()
    else
        r.detail:Hide()
    end
    for i, p in ipairs(r.pills) do
        local kind = o.pills and o.pills[i]
        if kind then
            p:Set(kind)
            Next(p, 8)
            p:Show()
        else
            p:Hide()
        end
    end
    r.right:ClearAllPoints()
    r.right:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    r.right:SetPoint("RIGHT", r, "RIGHT", o.chev and -28 or -12, 0)
    r.right:SetText(o.right or "")
    if o.chev then
        r.chev.arrow:SetDown(o.chev == "open")
        r.chev:Show()
    else
        r.chev:Hide()
    end
    r.onTick = (not o.noTick) and o.onTick or nil
    r.onChev = o.onChev
    r.tipT, r.tipB = o.tipT, o.tipB
    r:Show()
end

-- The right column for the picked character: Icons, Bars or Textures. Boxes stack
-- down the body; with a scroll the body narrows for its track.
local function PaintBody(w)
    local COL = NS.AT.COL
    for _, b in ipairs(W.boxes) do b:Hide() end
    for _, r in ipairs(W.rows) do r:Hide() r.onTick, r.onChev, r.tipT, r.tipB = nil, nil, nil, nil end
    for _, c in ipairs(W.chips) do c:Hide() c.onClick = nil end
    W.body:SetWidth(w)
    local node = CharNode(sel)
    local y, nb, nr, nc = 0, 0, 0, 0
    local function NewBox(title, right, leaves)
        nb = nb + 1
        local b = W.boxes[nb]
        if not b then
            b = Box(W.body)
            W.boxes[nb] = b
        end
        b:SetFrameLevel(W.body:GetFrameLevel() + 1)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", W.body, "TOPLEFT", 0, -y)
        b:SetWidth(w)
        b.title:SetText(title)
        b.right:SetText(right or "")
        -- two or more ticks in a box: one on its head ticks or unticks them all
        local many = leaves ~= nil and #leaves >= 2
        if many and not b.tick then
            b.tick = Check(b.head)
            b.tick:SetPoint("LEFT", 8, 0)
            NS.AT.Tooltip(b.tick, "Everything in this box", "Ticks them all, or unticks them all when all are ticked.")
        end
        if b.tick then
            b.tick:SetShown(many)
            b.tick.onTick = nil
            if many then
                local st = State(leaves)
                b.tick:SetState(st)
                b.tick.onTick = function()
                    SetAll(leaves, st ~= "on")
                    Touch()
                end
                b.tick:SetScript("OnClick", function(self) if self.onTick then self.onTick() end end)
            end
        end
        b.title:ClearAllPoints()
        b.title:SetPoint("LEFT", many and 30 or 10, 0)
        b:Show()
        b._top = y
        y = y + IW.HEAD_H + 2
        return b
    end
    local function EndBox(b)
        y = y + 2
        b:SetHeight(y - b._top)
        y = y + IW.BOX_GAP
    end
    local function NextRow()
        nr = nr + 1
        return Row(nr)
    end
    if not node then
        W.body:SetHeight(1)
        return 0
    end
    if sub == "icons" then
        for _, spec in ipairs(Kids(node, "spec")) do
            local profs = spec.children or {}
            local all = {}
            for _, p in ipairs(profs) do Leaves(p, all) end
            local b = NewBox(string.upper(spec.label or ""), Plural(#profs, "profile", "profiles"), all)
            for _, p in ipairs(profs) do
                local leaves = Leaves(p)
                local st = State(leaves)
                local tags = {}
                if p.tag == "active" then tags[#tags + 1] = "use" end
                if AnyLive(leaves) then tags[#tags + 1] = "done" end
                local isOpen = opened[p.id] == true
                PaintRow(NextRow(), 1, y, w - 2, IW.ROW_H, { check = st, name = p.name,
                    nameCol = (st ~= "off") and COL.ink or COL.dim, pills = tags, right = ProfileCounts(leaves),
                    chev = isOpen and "open" or "shut", tipT = p.name, tipB = ProfileTip(spec, p),
                    onTick = function()
                        SetAll(leaves, st ~= "on")
                        Touch()
                    end,
                    onChev = function()
                        opened[p.id] = (not opened[p.id]) or nil
                        IW.Refresh()
                    end })
                y = y + IW.ROW_H
                if isOpen then
                    -- its groups as chips, wrapping under the name
                    local cx, cy = IW.CHIP_X, y + 1
                    for _, lf in ipairs(leaves) do
                        nc = nc + 1
                        local c = Chip(nc)
                        c:SetFrameLevel(W.body:GetFrameLevel() + 3)
                        local label
                        if lf.kind == "free" then label = "Free icons " .. tostring(lf.n or 0)
                        elseif (lf.n or 0) > 0 then label = tostring(lf.name) .. " " .. lf.n
                        else label = tostring(lf.name) .. " · empty" end
                        c.fs:SetText(label)
                        local hid = tonumber(lf.cdmHidden) or 0
                        c.tipT = (hid > 0) and tostring(lf.name) or nil
                        c.tipB = (hid > 0) and ((hid == 1) and "1 icon in it is set to not displayed in your Cooldown Manager, so it stays out."
                            or ("%d icons in it are set to not displayed in your Cooldown Manager, so they stay out."):format(hid)) or nil
                        local cw = math.ceil(c.fs:GetStringWidth() or 40) + 18
                        if cx + cw > w - 10 and cx > IW.CHIP_X then
                            cx = IW.CHIP_X
                            cy = cy + IW.CHIP_H + 5
                        end
                        c:ClearAllPoints()
                        c:SetPoint("TOPLEFT", W.body, "TOPLEFT", cx, -cy)
                        c:SetWidth(cw)
                        c.lit = picks[lf.unit] == true
                        c:Paint()
                        c.onClick = function()
                            picks[lf.unit] = (not picks[lf.unit]) or nil
                            Touch()
                        end
                        c:Show()
                        cx = cx + cw + 5
                    end
                    y = cy + IW.CHIP_H + 8
                end
            end
            EndBox(b)
        end
        -- the rest that rides with the icons
        local also = {}
        for _, lf in ipairs(Kids(Kids(node, "shared")[1], "reminders")) do also[#also + 1] = lf end
        for _, lf in ipairs(Kids(node, "look")) do also[#also + 1] = lf end
        for _, lf in ipairs(Kids(node, "press")) do also[#also + 1] = lf end
        if #also > 0 then
            local b = NewBox("ALSO", nil, also)
            for _, lf in ipairs(also) do
                local on = picks[lf.unit] == true
                local detail, tip, label = "", nil, lf.name or lf.label
                if lf.kind == "reminders" then
                    detail = Plural(lf.n or 0, "reminder", "reminders")
                    tip = "Its reminders and their pulse, sound and glow."
                elseif lf.kind == "look" then
                    local look = plan.looks and plan.looks[node.charKey]
                    detail = ("from its profile '%s'"):format(tostring(look and look.profile or "Default"))
                    tip = "Untick to keep the Arc Auras look."
                else
                    detail = "switched on"
                    tip = "Switches it on with the same look."
                end
                PaintRow(NextRow(), 1, y, w - 2, IW.ROW_H, { check = on and "on" or "off", name = label,
                    nameCol = on and COL.ink or COL.dim, pills = Live(lf.unit) and { "done" } or nil, right = detail,
                    tipT = label, tipB = tip,
                    onTick = function()
                        picks[lf.unit] = (not on) or nil
                        Touch()
                    end })
                y = y + IW.ROW_H
            end
            EndBox(b)
        end
    elseif sub == "bars" then
        local bars = Kids(Kids(node, "shared")[1], "bar")
        local any = false
        for _, BX in ipairs(IW.BAR_BOXES) do
            local list = {}
            for _, lf in ipairs(bars) do
                local k = lf.bar.barKind
                if k == BX[1] or (BX.also and BX.also[k]) then list[#list + 1] = { leaf = lf } end
            end
            for _, l in ipairs(node.later or {}) do if l.kind == BX[1] then list[#list + 1] = { later = l } end end
            if #list > 0 then
                any = true
                local lv = {}
                for _, e in ipairs(list) do if e.leaf then lv[#lv + 1] = e.leaf end end
                local b = NewBox(BX[2], tostring(#list), lv)
                for _, e in ipairs(list) do
                    if e.leaf then
                        local lf, B = e.leaf, e.leaf.bar
                        local on = picks[lf.unit] == true
                        PaintRow(NextRow(), 1, y, w - 2, IW.BAR_H, { check = on and "on" or "off", swatch = BarSwatch(B),
                            name = lf.name, nameCol = on and COL.ink or COL.dim, detail = BarDetail(B),
                            pills = Live(lf.unit) and { "done" } or nil, right = SpecsText(node, B.c and B.c.specs),
                            onTick = function()
                                picks[lf.unit] = (not on) or nil
                                Touch()
                            end })
                    else
                        PaintRow(NextRow(), 1, y, w - 2, IW.BAR_H, { check = "off", noTick = true,
                            swatch = { color = COL.faint, cells = 0 }, name = e.later.name, nameCol = COL.faint,
                            pills = { "later" }, tipT = e.later.name, tipB = e.later.why or IW.LATER_TIP })
                    end
                    y = y + IW.BAR_H
                end
                EndBox(b)
            end
        end
        if not any then
            local b = NewBox("BARS")
            PaintRow(NextRow(), 1, y, w - 2, 30, { name = tostring(node.name) .. " has no bars in Arc UI.", nameCol = COL.faint })
            y = y + 30
            EndBox(b)
        end
    else
        local list = node.textures or {}
        local lv = {}
        for _, t in ipairs(list) do if t.unit then lv[#lv + 1] = { unit = t.unit } end end
        local b = NewBox("TEXTURES", tostring(#list), lv)
        for _, t in ipairs(list) do
            local detail = (t.debuff and "Debuff" or "Buff") .. " · " .. t.w .. " x " .. t.h
            if t.unit then
                local on = picks[t.unit] == true
                PaintRow(NextRow(), 1, y, w - 2, IW.TEX_H, { check = on and "on" or "off", thumb = t, name = t.name,
                    nameCol = on and COL.ink or COL.dim, detail = detail, pills = Live(t.unit) and { "done" } or nil,
                    right = SpecsText(node, t.specs),
                    onTick = function()
                        picks[t.unit] = (not on) or nil
                        Touch()
                    end })
            else
                PaintRow(NextRow(), 1, y, w - 2, IW.TEX_H, { check = "off", noTick = true, thumb = t, name = t.name,
                    nameCol = COL.dim, detail = detail, pills = { "later" }, right = SpecsText(node, t.specs),
                    tipT = t.name, tipB = t.why or IW.LATER_TIP })
            end
            y = y + IW.TEX_H
        end
        if #list == 0 then
            PaintRow(NextRow(), 1, y, w - 2, 30, { name = tostring(node.name) .. " has no textures in Arc UI.", nameCol = COL.faint })
            y = y + 30
        end
        EndBox(b)
    end
    y = y - IW.BOX_GAP
    W.body:SetHeight(math.max(1, y))
    return y
end

local function PaintChars()
    local AT, COL = NS.AT, NS.AT.COL
    local order, me = Order()
    local myRealm
    for _, node in ipairs(order) do if node.charKey == me then myRealm = node.realm end end
    -- a long list scrolls: the list steps in for the track, else rows run edge to edge
    local listH = (W.charsBox:GetHeight() or 0) - IW.HEAD_H - IW.LIST_FOOT_H - 5
    local over = #order * IW.CHAR_H > listH + 1
    local inset = over and (AT.ScrollW + 2) or 1
    W.charHost:SetPoint("BOTTOMRIGHT", W.charsBox, "BOTTOMRIGHT", -inset, IW.LIST_FOOT_H + 3)
    local w = (W.charsBox:GetWidth() or IW.CHARS_W) - 1 - inset
    W.charList:SetWidth(math.max(60, w))
    for i, node in ipairs(order) do
        local r = CharRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", W.charList, "TOPLEFT", 0, -(i - 1) * IW.CHAR_H)
        r:SetWidth(math.max(60, w))
        local leaves = Leaves(node)
        local st = State(leaves)
        r.check:SetState(st)
        r.name:SetText(node.name or node.label or "?")
        local cc = ClassColor(node.classTag)
        r.name:SetTextColor(cc[1], cc[2], cc[3])
        local isMe = node.charKey == me
        r.you:SetShown(isMe)
        r.realm:ClearAllPoints()
        r.realm:SetPoint("LEFT", isMe and r.you or r.name, "RIGHT", 6, 0)
        r.realm:SetText((isMe or node.realm == myRealm) and "" or (node.realm or ""))
        local isSel = node.charKey == sel
        r.sel:SetShown(isSel)
        r.bar:SetShown(isSel)
        r.onPick = function()
            sel = node.charKey
            IW.Refresh()
        end
        r.onTick = function()
            SetAll(leaves, st ~= "on")
            sel = node.charKey
            Touch()
        end
        r:Show()
    end
    for i = #order + 1, #W.chars do W.chars[i]:Hide() end
    W.charList:SetHeight(math.max(1, #order * IW.CHAR_H))
    W.charHost:UpdateScroll()
    W.charsBox.right:SetText(tostring(#order))
end

-- The Icons / Bars / Textures strip: each tab carries how much of it is picked; the
-- picked character's name sits at its right end.
local function PaintStrip(node)
    local AT, COL = NS.AT, NS.AT.COL
    local hex = AT.Hex(COL.faint)
    local function Mark(text) return "  |cff" .. hex .. text .. "|r" end
    local icons, iconsOn, bars, barsOn = 0, 0, 0, 0
    for _, spec in ipairs(Kids(node, "spec")) do
        for _, p in ipairs(spec.children or {}) do
            icons = icons + 1
            if State(Leaves(p)) ~= "off" then iconsOn = iconsOn + 1 end
        end
    end
    local also = Kids(Kids(node, "shared")[1], "reminders")
    for _, lf in ipairs(Kids(node, "look")) do also[#also + 1] = lf end
    for _, lf in ipairs(Kids(node, "press")) do also[#also + 1] = lf end
    for _, lf in ipairs(also) do
        icons = icons + 1
        if picks[lf.unit] then iconsOn = iconsOn + 1 end
    end
    local tex, texOn = 0, 0
    for _, lf in ipairs(Kids(Kids(node, "shared")[1], "bar")) do
        if lf.bar.barKind == "texture" then
            tex = tex + 1
            if picks[lf.unit] then texOn = texOn + 1 end
        else
            bars = bars + 1
            if picks[lf.unit] then barsOn = barsOn + 1 end
        end
    end
    -- a texture the import cannot make yet still counts toward the list
    local listed = node and #(node.textures or {}) or 0
    local labels = {
        icons = "Icons" .. Mark(iconsOn .. "/" .. icons),
        bars = "Bars" .. Mark(barsOn .. "/" .. bars),
        tex = "Textures" .. Mark((tex > 0) and (texOn .. "/" .. listed) or tostring(listed)),
    }
    local names = {}
    for _, t in ipairs(IW.TABS) do names[#names + 1] = labels[t[1]] end
    W.strip:Set(names, labels[sub], function(n)
        for _, t in ipairs(IW.TABS) do
            if n == labels[t[1]] then IW.SetSub(t[1]) end
        end
    end, 11)
    if node then
        local cc = ClassColor(node.classTag)
        W.who:SetText(node.name or "")
        W.who:SetTextColor(cc[1], cc[2], cc[3])
        local _, me = Order()
        local mine = CharNode(me)
        local words = ClassName(node.classTag)
        if node.realm and node.realm ~= "" and not (mine and mine.realm == node.realm) then
            words = (words ~= "" and (words .. " · ") or "") .. node.realm
        end
        W.whoSub:SetText(words)
    else
        W.who:SetText("")
        W.whoSub:SetText("")
    end
end

-- What Import brings, in a line, and whether some of it is here already.
local function PaintFoot()
    local COL = NS.AT.COL
    local nProf, nBars, nTex, nRem, look, press, again = 0, 0, 0, 0, false, false, 0
    local who = {}
    for _, node in ipairs(plan and plan.tree or {}) do
        local any = false
        for _, spec in ipairs(Kids(node, "spec")) do
            for _, p in ipairs(spec.children or {}) do
                local picked, here = false, false
                for _, lf in ipairs(Leaves(p)) do
                    if picks[lf.unit] then
                        picked = true
                        if Live(lf.unit) then here = true end
                    end
                end
                if picked then
                    nProf, any = nProf + 1, true
                    if here then again = again + 1 end
                end
            end
        end
        local function One(lf)
            if not picks[lf.unit] then return false end
            any = true
            if Live(lf.unit) then again = again + 1 end
            return true
        end
        for _, lf in ipairs(Kids(Kids(node, "shared")[1], "bar")) do
            if One(lf) then
                if lf.bar.barKind == "texture" then nTex = nTex + 1 else nBars = nBars + 1 end
            end
        end
        for _, lf in ipairs(Kids(Kids(node, "shared")[1], "reminders")) do if One(lf) then nRem = nRem + 1 end end
        for _, lf in ipairs(Kids(node, "look")) do if One(lf) then look = true end end
        for _, lf in ipairs(Kids(node, "press")) do if One(lf) then press = true end end
        if any then who[#who + 1] = node.name or node.label end
    end
    local text, text2, col = "", "", COL.ink
    if said then
        text, text2 = said.text or "", said.text2 or ""
        col = said.bad and { 1, 0.45, 0.4 } or { 0.498, 0.824, 0.557 }
    elseif #who == 0 then
        text, col = "Nothing ticked yet.", COL.dim
    else
        local bits = {}
        if nProf > 0 then bits[#bits + 1] = Plural(nProf, "profile", "profiles") end
        if nBars > 0 then bits[#bits + 1] = Plural(nBars, "bar", "bars") end
        if nTex > 0 then bits[#bits + 1] = Plural(nTex, "texture", "textures") end
        if nRem > 0 then bits[#bits + 1] = (nRem == 1) and "the Cooldown Reminder" or (nRem .. " Cooldown Reminders") end
        if look then bits[#bits + 1] = "the icon look" end
        if press then bits[#bits + 1] = "the press highlight" end
        local list = bits[1] or ""
        if #bits > 1 then list = table.concat(bits, ", ", 1, #bits - 1) .. " and " .. bits[#bits] end
        text = ("Brings %s from %s."):format(list, (#who == 1) and who[1] or (#who .. " characters"))
        if again > 0 then
            text2 = ((again == 1) and "1 of them is" or (again .. " of them are"))
                .. " in Arc Auras already: importing again adds a second copy."
        end
    end
    W.sum:SetText(text)
    W.sum:SetTextColor(col[1], col[2], col[3])
    W.sum2:SetText(text2)
    W.sum:ClearAllPoints()
    W.sum:SetPoint("LEFT", W.foot, "LEFT", 12, (text2 ~= "") and 7 or 0)
    W.sum:SetPoint("RIGHT", W.importBtn, "LEFT", -12, (text2 ~= "") and 7 or 0)
    W.sum2:SetShown(text2 ~= "")
    W.importBtn:SetAlpha(#who > 0 and 1 or 0.45)
    W.importBtn:EnableMouse(#who > 0)
end

-- The tab whole: the state Arc UI's data is in, then the two columns and the foot.
function IW.Paint()
    if not pane then return end
    local IA = NS.ImportArcUI
    local ok = IA ~= nil and IA.Available() and plan ~= nil and #(plan.tree or {}) > 0
    W.charsBox:SetShown(ok)
    W.right:SetShown(ok)
    W.foot:SetShown(ok)
    W.offBtn:Hide()
    -- still reading: the Loading veil covers the tab, nothing under it yet
    if not ok and plan == nil and IA ~= nil and IA.Available() then
        W.off:Hide()
        return
    end
    if not ok then
        if IA and IA.Available() then
            W.off:SetText("Arc UI has nothing set up to copy.")
        else
            W.off:SetText("Arc UI's settings can't be read while it is turned off. Turn it on and reload, then come back here.")
            W.offBtn:Show()
        end
        W.off:Show()
        return
    end
    W.off:Hide()
    PaintChars()
    local node = CharNode(sel)
    PaintStrip(node)
    -- the boxes run the column's width; taller than the column, they step in for
    -- the scroll track
    local full = W.right:GetWidth() or 0
    if full < 100 then full = 500 end
    W.bodyHost:SetPoint("BOTTOMRIGHT", W.right, "BOTTOMRIGHT", 0, 0)
    local h = PaintBody(full)
    local viewH = (W.right:GetHeight() or 0) - IW.SUB_H - IW.BOX_GAP
    if h > viewH + 1 then
        local inset = NS.AT.ScrollW + 2
        W.bodyHost:SetPoint("BOTTOMRIGHT", W.right, "BOTTOMRIGHT", -inset, 0)
        PaintBody(full - inset)
    end
    W.bodyHost:UpdateScroll()
    PaintFoot()
end

-- The plan of every character, with this character's in-use profiles, bars and
-- looks ticked.
function IW.ReadPlan()
    local IA = NS.ImportArcUI
    if not (IA and IA.Available()) then return end
    plan = IA.Preview()
    picks = plan and IA.DefaultPicks(plan) or {}
    local me = IA.CurrentChar()
    sel = CharNode(me) and me or (plan and plan.tree[1] and plan.tree[1].charKey) or nil
    -- the first profile opens to show its groups
    local node = CharNode(sel)
    local spec = node and Kids(node, "spec")[1]
    local first = spec and spec.children and spec.children[1]
    opened = {}
    if first then opened[first.id] = true end
end

-- Reads Arc UI's data the first time the tab shows. A big save takes a while,
-- so the read runs in the window's slices behind its Loading veil, never in
-- one frame.
function IW.Refresh()
    if not pane then return end
    local IA = NS.ImportArcUI
    if not plan and IA and IA.Available() then
        if Options.WhenWork then
            Options.WhenWork("arcuiPlan", IW.ReadPlan, IW.Paint)
        else
            IW.ReadPlan()
        end
    end
    IW.Paint()
end

-- The tab shows while Arc UI is here: loaded (its data read) or installed and off.
function IW.TabShown()
    local IA = NS.ImportArcUI
    if not IA then return false end
    if IA.Available() then return true end
    local A = rawget(_G, "C_AddOns")
    return A ~= nil and A.DoesAddOnExist ~= nil and A.DoesAddOnExist("ArcUI") == true
end

function IW.TickAll(on)
    for _, node in ipairs(plan and plan.tree or {}) do SetAll(Leaves(node), on) end
    Touch()
end

-- The right column's tab: "icons", "bars" or "tex".
function IW.SetSub(key)
    sub = key
    IW.Refresh()
end

function IW.BuildPane(parent)
    if pane then return pane end
    local AT, COL = NS.AT, NS.AT.COL
    pane = CreateFrame("Frame", nil, parent)
    W.note = Font(pane, 12, COL.ink)
    W.note:SetPoint("TOPLEFT", 4, -2)
    W.note:SetText("Pick what comes over from Arc UI. Arc UI stays as it is, and you can import again any time.")
    -- CHARACTERS: the list, Tick all and Untick all on its foot
    local cb = Box(pane)
    cb.title:SetText("CHARACTERS")
    cb:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -IW.NOTE_H)
    cb:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 6 + IW.FOOT_H + IW.GAP)
    cb:SetWidth(IW.CHARS_W)
    W.charsBox = cb
    local lf = CreateFrame("Frame", nil, cb)
    lf:SetPoint("BOTTOMLEFT", 1, 1)
    lf:SetPoint("BOTTOMRIGHT", -1, 1)
    lf:SetHeight(IW.LIST_FOOT_H)
    lf.line = lf:CreateTexture(nil, "ARTWORK")
    lf.line:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 1)
    lf.line:SetPoint("TOPLEFT", 0, 0)
    lf.line:SetPoint("TOPRIGHT", 0, 0)
    lf.line:SetHeight(AT.Hairline(lf))
    local all = AT.MakeQuietButton(lf, "Tick all", 62)
    all:SetHeight(20)
    all:SetPoint("LEFT", 8, 0)
    all:SetScript("OnClick", function() IW.TickAll(true) end)
    local none = AT.MakeQuietButton(lf, "Untick all", 74)
    none:SetHeight(20)
    none:SetPoint("LEFT", all, "RIGHT", 6, 0)
    none:SetScript("OnClick", function() IW.TickAll(false) end)
    W.charHost, W.charList = AT.MakeScroll(cb)
    W.charHost:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -(IW.HEAD_H + 2))
    W.charHost:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, IW.LIST_FOOT_H + 3)
    -- the right column: the strip, then the boxes
    local right = CreateFrame("Frame", nil, pane)
    right:SetPoint("TOPLEFT", cb, "TOPRIGHT", IW.GAP, 0)
    right:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 6 + IW.FOOT_H + IW.GAP)
    W.right = right
    local strip = AT.TabRow(right)
    strip:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
    strip:SetHeight(IW.SUB_H)
    W.strip = strip
    W.whoSub = Font(right, 11, COL.dim)
    W.whoSub:SetPoint("RIGHT", right, "TOPRIGHT", -2, -12)
    W.who = Font(right, 12, COL.ink)
    W.who:SetPoint("RIGHT", W.whoSub, "LEFT", -7, 0)
    W.bodyHost, W.body = AT.MakeScroll(right)
    W.bodyHost:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -(IW.SUB_H + IW.BOX_GAP))
    W.bodyHost:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    -- the foot bar: what Import brings, then Import
    local fb = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    AT.Skin(fb, COL.box, COL.line2)
    fb:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 6)
    fb:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 6)
    fb:SetHeight(IW.FOOT_H)
    W.foot = fb
    local imp = AT.MakeSmallButton(fb, "Import", 84)
    imp:SetHeight(24)
    imp:SetPoint("RIGHT", -8, 0)
    imp:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    imp:SetScript("OnLeave", function()
        imp:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        imp:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end)
    imp:SetScript("OnClick", function() IW.DoImport() end)
    W.importBtn = imp
    W.sum = Font(fb, 12, COL.ink)
    W.sum2 = Font(fb, 11, COL.dim)
    W.sum2:SetPoint("LEFT", fb, "LEFT", 12, -8)
    W.sum2:SetPoint("RIGHT", imp, "LEFT", -12, -8)
    -- Arc UI off, or nothing to copy: one line where the boxes would be
    W.off = Font(pane, 12, COL.dim)
    W.off:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -(IW.NOTE_H + 4))
    W.off:SetPoint("RIGHT", pane, "RIGHT", -10, 0)
    W.off:SetWordWrap(true)
    W.offBtn = AT.MakeSmallButton(pane, "Turn Arc UI on and reload", 190)
    W.offBtn:SetPoint("TOPLEFT", W.off, "BOTTOMLEFT", 0, -10)
    W.offBtn:SetScript("OnClick", function()
        local A = rawget(_G, "C_AddOns")
        if not (A and A.EnableAddOn) then return end
        A.EnableAddOn("ArcUI")
        if ReloadUI then ReloadUI() end
    end)
    -- a new width wraps the chips and moves the scroll tracks
    pane:SetScript("OnSizeChanged", function() IW.Paint() end)
    pane:SetScript("OnShow", function() IW.Refresh() end)
    return pane
end

function IW.DoImport()
    local IA = NS.ImportArcUI
    if not (IA and plan) then return end
    local lock = rawget(_G, "InCombatLockdown")
    if lock and lock() then
        said = { text = "Not in combat.", bad = true }
        IW.Paint()
        return
    end
    if next(picks) == nil then return end
    local res, err = IA.Apply(plan, picks)
    if not res then
        said = { text = err or "The import did not run.", bad = true }
        IW.Paint()
        return
    end
    -- imported: the login offer has done its job
    local ui = NS.Store.UI and NS.Store.UI()
    if ui then ui.arcuiOffer = "done" end
    picks = {}
    local n = res.layouts or 0
    local text
    if n == 0 then text = "Imported into the layouts your earlier import made."
    elseif n == 1 then text = "Imported: 1 new layout is in the sidebar."
    else text = ("Imported: %d new layouts are in the sidebar."):format(n) end
    said = { text = text, text2 = "Not right? Delete the layout and import it again." }
    if Options.RefreshAll then Options.RefreshAll() end
    IW.Paint()
end

-- Opens the tab: the card, the login offer and /arcui2 arcui come here.
function IW.Open()
    if offer and offer:IsShown() then offer:Hide() end
    if Options.OpenImportTab then Options.OpenImportTab("arcui") end
end

-- The login offer: a small window, its three answers. "Not now" asks again at
-- the next login.
function IW.BuildOffer()
    if offer then return offer end
    local AT = NS.AT
    offer = AT.CreateWindow("ArcAurasImportArcUIOffer", {
        w = 460, h = 190, minW = 460, minH = 190, maxW = 460, maxH = 190,
        title = NS.AT.Brand("Arc", " Auras"),
    })
    local pg = AT.NewPage(offer)
    pg:SetPoint("TOPLEFT", 8, -38)
    pg:SetPoint("BOTTOMRIGHT", -8, 8)
    pg:Show()
    AT.Section(pg, "Your Arc UI setup")
    AT.RowDesc(pg, "Arc UI is now Arc Auras. Pick which of your groups, icons and bars come over, placed as they are.", 34)
    AT.RowActions(pg, {
        { label = "Start the import", w = 140, onClick = function()
            offer:Hide()
            IW.Open()
        end },
        { label = "Not now", w = 90, onClick = function() offer:Hide() end },
        { label = "Don't ask again", w = 130, quiet = true, onClick = function()
            local ui = NS.Store.UI and NS.Store.UI()
            if ui then ui.arcuiOffer = "never" end
            offer:Hide()
        end },
    }, "left")
    AT.LayoutPage(pg)
    return offer
end

-- Asks only when the Arc UI loaded is the stand-in (it marks itself X-Bridge),
-- its save holds a setup, and no import or "Don't ask again" has answered yet.
-- A player still on the full Arc UI is never asked.
function IW.ShouldOffer()
    local IA, Store = NS.ImportArcUI, NS.Store
    local ui = Store and Store.UI and Store.UI()
    if not (IA and ui) or ui.arcuiOffer ~= nil then return false end
    local A = rawget(_G, "C_AddOns")
    if not (A and A.IsAddOnLoaded and A.GetAddOnMetadata and A.IsAddOnLoaded("ArcUI")) then return false end
    if A.GetAddOnMetadata("ArcUI", "X-Bridge") ~= "1" then return false end
    return IA.Available() and IA.DoneCount() == 0 and IA.HasSetup(rawget(_G, "ArcUIDB"))
end

-- The ProcTracker move's windows open at login too, and so can the panel: this
-- offer waits until they close, so two windows never sit on top of each other.
IW.WAIT_BEHIND = { "ArcAurasPTMove", "ArcAurasPTMoved", "ArcUIv2Options" }
local asked
local waitHooks = {}
local offerEv = CreateFrame("Frame")

-- Shown once a session at most; never in combat (it waits for the fight to end).
function IW.OfferOnLogin()
    if asked or not IW.ShouldOffer() then return end
    if InCombatLockdown and InCombatLockdown() then
        offerEv:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- the import is open already: nothing left to ask this session
    if pane and pane:IsVisible() then
        asked = true
        return
    end
    for _, name in ipairs(IW.WAIT_BEHIND) do
        local w = rawget(_G, name)
        if w and w:IsShown() then
            if not waitHooks[w] then
                waitHooks[w] = true
                -- a frame later: closing the offer opens its window first
                w:HookScript("OnHide", function() C_Timer.After(0, IW.OfferOnLogin) end)
            end
            return
        end
    end
    asked = true
    IW.BuildOffer():Show()
end

-- After the first PLAYER_ENTERING_WORLD (the game closes windows opened before
-- it), a second after the ProcTracker move's turn.
offerEv:RegisterEvent("PLAYER_ENTERING_WORLD")
offerEv:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(4, IW.OfferOnLogin)
    else
        IW.OfferOnLogin()
    end
end)

-- The card's line: what the import does, and what is in Arc Auras from it now.
function IW.CardDesc()
    local IA = NS.ImportArcUI
    local base = "Pick which Arc UI groups, icons, bars and looks come into Arc Auras."
    local done = IA and IA.DoneCount() or 0
    if done == 0 or not plan then return base end
    local here = 0
    for unit in pairs(plan.leaves or {}) do if IA.UnitLive(unit, plan) then here = here + 1 end end
    if here == 0 then return base end
    return base .. (" %d parts are in Arc Auras; import again any time."):format(here)
end

-- The card's picture: Arc UI's own icon handing its icons to an Arc Auras square.
IW.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\ArcUI_Icon_128"
function IW.DrawCard(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local NL = NS.NewLayout
    local W2, H = NL.STAGE_W, NL.STAGE_H
    local function Square(x, y, c)
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
    NL.SourceIcon(stage, IW.ICON)
    Square(W2 / 2 + 22, (H - 36) / 2, COL.arc)
    local head = AT.MakeChevron(stage)
    head:SetDir("right")
    head:SetColor(COL.arc)
    head:SetScale(2)
    head:SetPoint("CENTER", stage, "TOPLEFT", (W2 / 2) / 2, -(H / 2) / 2)
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
