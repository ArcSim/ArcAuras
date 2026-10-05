-- AD_TalentPickerRetail: the retail talent picker: class, hero and spec panels drawn from the catalog's retail panels.
-- AD_Options' OpenTalentPicker hands retail to Options.OpenRetailTalentPicker; a click writes the edited record's load talents, or one talent target's pick (TR.Get / TR.Set).
-- Talent, spec and hero changes happen out of combat, so the picker only ever edits the released WHO layer.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TR = {}
Options.TalentPickerRetail = TR

TR.PAD, TR.HDR, TR.ICON, TR.BAND = 12, 24, 40, 18
-- each panel's share of the canvas width, the two gutters aside
TR.SHARE = { class = 0.36, hero = 0.26 }
TR.RED = { 0.95, 0.38, 0.38 }

local win, canvas, lineHost, search, count, empty
local ctxFn
local query = ""
local panels, bands, nodes, hubs, lines = {}, {}, {}, {}, {}

function TR.Record() return ctxFn and ctxFn() end

-- What the picker edits: a record's load talents, or a talent target that
-- holds one pick of its own (a rule's guard, a look's talent; see
-- Options.TalentPickRow), with its own reads and writes.
function TR.Get(rec, nodeID)
    if rec.talentTarget then return rec.State(nodeID) end
    return NS.Store.TalentState(rec, nodeID)
end
function TR.Set(rec, nodeID, state, entryID)
    if rec.talentTarget then rec.Set(nodeID, state, entryID) return end
    NS.Store.SetTalentState(rec, nodeID, state, entryID)
end
function TR.List(rec)
    if rec.talentTarget then return rec.List() end
    return NS.Store.TalentList(rec)
end

-- The state a button shows: the node's, unless the record names another
-- option of the same choice node.
function TR.StateOf(rec, nodeID, entryID)
    local state, named = TR.Get(rec, nodeID)
    if entryID and named and named ~= entryID then return nil end
    return state
end

-- taken for a button: the node counts, and an option is the active one
function TR.Taken(e, entryID)
    if not e.taken then return false end
    if entryID then return e.activeEntryID == entryID end
    return true
end

function TR.Panel(i)
    local AT, COL = NS.AT, NS.AT.COL
    local p = panels[i]
    if p then return p end
    local box = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    AT.Skin(box, COL.box or COL.well, COL.line)
    box:SetFrameLevel(canvas:GetFrameLevel() + 1)
    local bar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TR.HDR)
    AT.Skin(bar, COL.panel, COL.panel)
    local rule = bar:CreateTexture(nil, "OVERLAY")
    rule:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.9)
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFont(STANDARD_TEXT_FONT, 12, "")
    name:SetPoint("LEFT", 8, 0)
    name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    local pts = bar:CreateFontString(nil, "OVERLAY")
    pts:SetFont(STANDARD_TEXT_FONT, 11, "")
    pts:SetPoint("RIGHT", -8, 0)
    pts:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local note = box:CreateFontString(nil, "OVERLAY")
    note:SetFont(STANDARD_TEXT_FONT, 11, "")
    note:SetPoint("CENTER", 0, -TR.HDR / 2)
    note:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    note:Hide()
    p = { box = box, name = name, pts = pts, note = note }
    panels[i] = p
    return p
end

-- a hero tree's name line inside the hero panel
function TR.Band(i)
    local COL = NS.AT.COL
    local b = bands[i]
    if b then return b end
    local fs = canvas:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local state = canvas:CreateFontString(nil, "OVERLAY")
    state:SetFont(STANDARD_TEXT_FONT, 10, "")
    state:SetJustifyH("RIGHT")
    b = { fs = fs, state = state }
    bands[i] = b
    return b
end

-- a node's centre, the anchor for connector lines (a choice node's two
-- buttons sit either side of it)
function TR.Hub(i)
    local h = hubs[i]
    if h then return h end
    h = CreateFrame("Frame", nil, canvas)
    h:SetSize(1, 1)
    hubs[i] = h
    return h
end

function TR.Node(i)
    local AT, COL = NS.AT, NS.AT.COL
    local node = nodes[i]
    if node then return node end
    local ring = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    AT.Skin(ring, COL.arc, COL.arc)
    ring:SetFrameLevel(canvas:GetFrameLevel() + 6)
    ring:Hide()
    local btn = CreateFrame("Button", nil, canvas, "BackdropTemplate")
    AT.Skin(btn, COL.well, COL.line)
    btn:SetFrameLevel(ring:GetFrameLevel() + 1)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
    ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
    local ic = btn:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 2, -2)
    ic:SetPoint("BOTTOMRIGHT", -2, 2)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local rank = btn:CreateFontString(nil, "OVERLAY")
    rank:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    rank:SetPoint("BOTTOMRIGHT", -1, 1)
    rank:SetTextColor(0.95, 0.97, 1)
    node = { btn = btn, ring = ring, ic = ic, rank = rank }
    -- the cross of an excluded node
    if btn.CreateLine then
        for k, corners in ipairs({ { "TOPLEFT", "BOTTOMRIGHT" }, { "TOPRIGHT", "BOTTOMLEFT" } }) do
            local ln = btn:CreateLine(nil, "OVERLAY")
            ln:SetColorTexture(TR.RED[1], TR.RED[2], TR.RED[3], 0.9)
            ln:SetThickness(2)
            ln:SetStartPoint(corners[1], 4, k == 1 and -4 or -4)
            ln:SetEndPoint(corners[2], -4, k == 1 and 4 or 4)
            ln:Hide()
            node["x" .. k] = ln
        end
    end
    btn:SetScript("OnEnter", function()
        local e = node.entry
        if not e then return end
        btn:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local opt = node.opt
        GameTooltip:AddLine(opt and opt.name or e.name, 1, 1, 1)
        local rk = e.rank or 0
        local taken = TR.Taken(e, node.entryID)
        if opt then
            GameTooltip:AddLine("One option of a choice talent", 0.7, 0.78, 0.88)
            GameTooltip:AddLine(taken and "This option is active" or "This option is not active",
                taken and 0.48 or 0.95, taken and 0.85 or 0.62, taken and 0.56 or 0.30)
        elseif e.maxRanks and e.maxRanks > 1 then
            GameTooltip:AddLine(("Rank %d of %d"):format(rk, e.maxRanks), 0.7, 0.78, 0.88)
        elseif taken then
            GameTooltip:AddLine("Taken", 0.48, 0.85, 0.56)
        else
            GameTooltip:AddLine("Not taken", 0.95, 0.62, 0.30)
        end
        if node.dim then
            GameTooltip:AddLine("This hero tree is not the one chosen.", 0.95, 0.62, 0.30)
        end
        -- the game's own talent text, the rank you have or the first
        local entryID = node.entryID or e.entryID
        if entryID and GameTooltip.AppendInfo then
            GameTooltip:AddLine(" ")
            GameTooltip:AppendInfo("GetTraitEntry", entryID, (taken and rk > 0) and rk or 1)
            if not opt and taken and e.maxRanks and rk < e.maxRanks then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Next rank:", 1, 1, 1)
                GameTooltip:AppendInfo("GetTraitEntry", entryID, rk + 1)
            end
        elseif e.spellID and C_Spell.GetSpellDescription then
            local d = C_Spell.GetSpellDescription(opt and opt.spellID or e.spellID)
            if d ~= nil and not (issecretvalue and issecretvalue(d)) and d ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(d, 1, 0.82, 0, true)
            end
        end
        GameTooltip:AddLine(" ")
        local rec = TR.Record()
        local state = rec and TR.StateOf(rec, e.nodeID, node.entryID) or nil
        local one = rec ~= nil and rec.talentTarget == true
        if state == "req" then
            GameTooltip:AddLine(not one and "Required: click to exclude it instead."
                or (rec.noExclude and "Picked: click to drop it." or "Taken: click for Not taken instead."),
                0.247, 0.788, 0.949)
        elseif state == "not" then
            GameTooltip:AddLine(one and "Not taken: click to drop it." or "Excluded: click to drop the condition.",
                TR.RED[1], TR.RED[2], TR.RED[3])
        else
            GameTooltip:AddLine(one and "Click to pick this talent." or "Click to require this talent.",
                0.247, 0.788, 0.949)
        end
        GameTooltip:AddLine("Right-click clears it.", 0.55, 0.65, 0.78)
        GameTooltip:AddLine("Node " .. e.nodeID, 0.4, 0.47, 0.57)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        TR.Paint()
    end)
    -- left click cycles required, excluded, off; a right click clears
    btn:SetScript("OnClick", function(_, button)
        local rec, e = TR.Record(), node.entry
        if not (rec and e) then return end
        local cur = TR.StateOf(rec, e.nodeID, node.entryID)
        local nxt
        if button ~= "RightButton" then
            if cur == nil then nxt = "req" elseif cur == "req" and not rec.noExclude then nxt = "not" end
        end
        TR.Set(rec, e.nodeID, nxt, node.entryID)
        TR.Paint()
        Options.RefreshAll()
    end)
    nodes[i] = node
    return node
end

-- per-node state only: rings, crosses, colour, the search dim
function TR.Paint()
    if not (win and win:IsShown()) then return end
    local COL = NS.AT.COL
    local rec = TR.Record()
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local req, exc = 0, 0
    local list = rec and TR.List(rec) or {}
    for _, e in ipairs(list) do
        if e.excluded then exc = exc + 1 else req = req + 1 end
    end
    if rec and rec.talentTarget then
        local pick = list[1]
        if not pick then
            count:SetText("Nothing picked yet - click a talent to pick it"
                .. (rec.noExclude and "." or ", again for Not taken."))
        else
            local _, entry = TR.Get(rec, pick.nodeID)
            count:SetText((pick.excluded and "Not taken: " or "Picked: ")
                .. (Options.TalentPickName(pick.nodeID, entry) or ""))
        end
    elseif req + exc == 0 then
        count:SetText("Nothing required yet - click a talent to require it, again to exclude it.")
    else
        local parts = {}
        if req > 0 then parts[#parts + 1] = req .. " required" end
        if exc > 0 then parts[#parts + 1] = exc .. " excluded" end
        count:SetText(table.concat(parts, ", "))
    end
    for _, node in ipairs(nodes) do
        local e = node.entry
        if e and node.btn:IsShown() then
            local state = rec and TR.StateOf(rec, e.nodeID, node.entryID) or nil
            local taken = TR.Taken(e, node.entryID)
            local words = node.opt and node.opt.name:lower() or e.nameLower
            local hit = (q == "") or (words:find(q, 1, true) ~= nil)
            local rc = (state == "not") and TR.RED or COL.arc
            node.ring:SetShown(state ~= nil)
            node.ring:SetBackdropColor(rc[1], rc[2], rc[3], 1)
            node.ring:SetBackdropBorderColor(rc[1], rc[2], rc[3], 1)
            local bc = (state == "req" and COL.arc) or (state == "not" and TR.RED)
                or (taken and COL.line2 or COL.line)
            node.btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
            node.ic:SetDesaturated(not taken)
            -- always opaque; a search miss darkens, an unchosen hero tree dims
            local v = hit and (node.dim and 0.55 or 1) or 0.3
            node.ic:SetVertexColor(v, v, v)
            node.btn:SetAlpha(1)
            node.ring:SetAlpha(1)
            if node.x1 then
                node.x1:SetShown(state == "not")
                node.x2:SetShown(state == "not")
            end
        end
    end
end

-- Places one tree's nodes in a box: its own scale, centred, a choice node as
-- two half-shifted buttons. Returns the count of nodes and hubs used.
function TR.Place(list, b, l, top, w, h, dim, ni, hi, byID)
    if #list == 0 or not b.minX then return ni, hi end
    local spanX, spanY = (b.maxX - b.minX) / 10, (b.maxY - b.minY) / 10
    local s = math.min((w - TR.PAD * 2) / (spanX + TR.ICON), (h - TR.PAD * 2) / (spanY + TR.ICON))
    if s > 1.4 then s = 1.4 elseif s < 0.25 then s = 0.25 end
    local size = math.max(14, math.floor(TR.ICON * s + 0.5))
    local ox = l + math.floor((w - (spanX * s + size)) / 2)
    local oy = top + math.floor((h - (spanY * s + size)) / 2)
    for _, e in ipairs(list) do
        local cx = math.floor(ox + size / 2 + (e.posX - b.minX) / 10 * s + 0.5)
        local cy = math.floor(oy + size / 2 + (e.posY - b.minY) / 10 * s + 0.5)
        hi = hi + 1
        local hub = TR.Hub(hi)
        hub:ClearAllPoints()
        hub:SetPoint("CENTER", canvas, "TOPLEFT", cx, -cy)
        hub:Show()
        byID[e.nodeID] = { hub = hub, e = e }
        local opts = e.entries
        if opts then
            for oi, opt in ipairs(opts) do
                ni = ni + 1
                local node = TR.Node(ni)
                node.entry, node.opt, node.entryID, node.dim = e, opt, opt.entryID, dim
                node.btn:SetSize(size, size)
                node.btn:ClearAllPoints()
                node.btn:SetPoint("CENTER", canvas, "TOPLEFT",
                    cx + ((oi == 1) and -math.floor(size / 2) or math.floor(size / 2)), -cy)
                node.ic:SetTexture(opt.icon)
                node.rank:SetText("")
                node.btn:Show()
            end
        else
            ni = ni + 1
            local node = TR.Node(ni)
            node.entry, node.opt, node.entryID, node.dim = e, nil, nil, dim
            node.btn:SetSize(size, size)
            node.btn:ClearAllPoints()
            node.btn:SetPoint("CENTER", canvas, "TOPLEFT", cx, -cy)
            node.ic:SetTexture(e.icon)
            node.rank:SetText((e.maxRanks and e.maxRanks > 1 and (e.rank or 0) > 0)
                and (e.rank .. "/" .. e.maxRanks) or "")
            node.rank:SetShown(size >= 26)
            node.btn:Show()
        end
    end
    return ni, hi
end

function TR.Spent(list)
    local n = 0
    for _, e in ipairs(list) do
        if e.taken then n = n + (e.rank or 0) end
    end
    return n
end

function TR.Layout()
    if not win then return end
    local COL = NS.AT.COL
    local cat = NS.TalentCatalog
    local P = cat and cat.Panels and cat.Panels()
    local have = P ~= nil and (#P.class.list + #P.spec.list + #P.hero) > 0
    empty:SetShown(not have)
    if not have then
        for _, node in ipairs(nodes) do node.btn:Hide(); node.ring:Hide() end
        for _, hub in ipairs(hubs) do hub:Hide() end
        for _, ln in ipairs(lines) do ln:Hide() end
        for _, p in ipairs(panels) do p.box:Hide() end
        for _, b in ipairs(bands) do b.fs:Hide(); b.state:Hide() end
        count:SetText("")
        return
    end
    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if cw < 60 or ch < 60 then return end

    local avail = cw - TR.PAD * 2
    local wClass = math.floor(avail * TR.SHARE.class)
    local wHero = math.floor(avail * TR.SHARE.hero)
    local wSpec = avail - wClass - wHero
    local bodyH = ch - TR.HDR - 2
    local ni, hi, bi = 0, 0, 0
    local byID = {}
    local cols = {
        { name = P.class.name, list = P.class.list, bounds = P.class.bounds, w = wClass },
        { name = "Hero Talents", hero = P.hero, w = wHero },
        { name = P.spec.name, list = P.spec.list, bounds = P.spec.bounds, w = wSpec },
    }
    local l = 0
    for i, col in ipairs(cols) do
        local p = TR.Panel(i)
        p.box:ClearAllPoints()
        p.box:SetPoint("TOPLEFT", canvas, "TOPLEFT", l, 0)
        p.box:SetSize(col.w, ch)
        p.name:SetText(string.upper(col.name or ""))
        p.box:Show()
        local bodyW = col.w - 2
        if col.hero then
            local n = #col.hero
            p.note:SetShown(n == 0)
            if n == 0 then p.note:SetText("No hero talents yet.") end
            local spent = 0
            local gap = 8
            local bandH = n > 0 and math.floor((bodyH - gap * (n - 1)) / n) or 0
            for k, h in ipairs(col.hero) do
                bi = bi + 1
                local band = TR.Band(bi)
                local top = TR.HDR + 1 + (k - 1) * (bandH + gap)
                band.fs:ClearAllPoints()
                band.fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", l + 8, -(top + 3))
                band.fs:SetText(h.name)
                band.fs:Show()
                band.state:ClearAllPoints()
                band.state:SetPoint("TOPRIGHT", canvas, "TOPLEFT", l + col.w - 8, -(top + 4))
                if h.active then
                    band.state:SetText("chosen")
                    band.state:SetTextColor(0.48, 0.85, 0.56)
                else
                    band.state:SetText("not chosen")
                    band.state:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
                end
                band.state:Show()
                ni, hi = TR.Place(h.list, h.bounds, l + 1, top + TR.BAND, bodyW,
                    bandH - TR.BAND, not h.active, ni, hi, byID)
                spent = spent + TR.Spent(h.list)
            end
            p.pts:SetText(spent > 0 and (spent .. " points") or "")
        else
            p.note:Hide()
            ni, hi = TR.Place(col.list, col.bounds, l + 1, TR.HDR + 1, bodyW, bodyH, false, ni, hi, byID)
            local spent = TR.Spent(col.list)
            p.pts:SetText(spent > 0 and (spent .. " points") or "")
        end
        l = l + col.w + TR.PAD
    end
    for i = #cols + 1, #panels do panels[i].box:Hide() end
    for i = bi + 1, #bands do bands[i].fs:Hide(); bands[i].state:Hide() end
    for i = ni + 1, #nodes do
        nodes[i].entry = nil
        nodes[i].btn:Hide()
        nodes[i].ring:Hide()
    end
    for i = hi + 1, #hubs do hubs[i]:Hide() end

    -- connector lines between placed nodes, lit where both ends are taken
    local li = 0
    if lineHost.CreateLine then
        for _, from in pairs(byID) do
            for _, target in ipairs(from.e.edges or {}) do
                local to = byID[target]
                if to then
                    li = li + 1
                    local ln = lines[li]
                    if not ln then
                        ln = lineHost:CreateLine(nil, "OVERLAY")
                        lines[li] = ln
                    end
                    ln:SetThickness(2)
                    if from.e.taken and to.e.taken then
                        ln:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 0.55)
                    else
                        ln:SetColorTexture(COL.line2[1], COL.line2[2], COL.line2[3], 0.8)
                    end
                    ln:SetStartPoint("CENTER", from.hub)
                    ln:SetEndPoint("CENTER", to.hub)
                    ln:Show()
                end
            end
        end
    end
    for i = li + 1, #lines do lines[i]:Hide() end
    TR.Paint()
end

function TR.Build()
    if win then return end
    local AT, COL = NS.AT, NS.AT.COL
    win = AT.CreateWindow("ArcAurasTalentPicker", {
        w = 1120, h = 640, minW = 700, minH = 440, maxW = 1800, maxH = 1300,
        title = "|cff3fc9f2Arc|r|cffd5e2f2 Talents|r",
        onResize = function() TR.Layout() end,
    })

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 8, -38)
    body:SetPoint("BOTTOMRIGHT", -8, 8)

    search = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", 0, 0)
    AT.Skin(search, COL.well)
    search:SetFont(STANDARD_TEXT_FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search talents")
    search:SetScript("OnTextChanged", function(self)
        query = self:GetText() or ""
        hint:SetShown(query == "")
        TR.Paint()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    count = body:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 11, "")
    count:SetPoint("LEFT", search, "RIGHT", 12, 0)
    count:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])

    local clear = AT.MakeSmallButton(body, "Clear all", 80)
    clear:SetPoint("TOPRIGHT", 0, 0)
    clear:SetHeight(20)
    clear:SetScript("OnClick", function()
        local rec = TR.Record()
        if not rec then return end
        if rec.talentTarget then rec.Clear() else NS.Store.ClearTalents(rec) end
        TR.Paint()
        Options.RefreshAll()
    end)
    AT.Tooltip(clear, "Clear all", "Drops every talent requirement and exclusion from this one.")

    local done = AT.MakeSmallButton(body, "Done", 70)
    done:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    done:SetHeight(20)
    done.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    done:SetScript("OnClick", function() win:Hide() end)

    -- no box of its own: the three panels are the boxes, edge to edge
    canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", 0, -28)
    canvas:SetPoint("BOTTOMRIGHT", 0, 0)
    canvas:SetClipsChildren(true)

    lineHost = CreateFrame("Frame", nil, canvas)
    lineHost:SetAllPoints()
    lineHost:SetFrameLevel(canvas:GetFrameLevel() + 4)

    empty = canvas:CreateFontString(nil, "OVERLAY")
    empty:SetFont(STANDARD_TEXT_FONT, 12, "")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    empty:SetText("No talent tree on this character yet.")
    empty:Hide()

    win:HookScript("OnShow", function() TR.Layout() end)
end

function Options.OpenRetailTalentPicker(fn)
    TR.Build()
    ctxFn = fn
    query = ""
    search:SetText("")
    if NS.TalentCatalog then NS.TalentCatalog.Rescan() end
    win:Show()
    TR.Layout()
end

-- The picker edits one record, so it closes with the panel that chose it.
function Options.CloseRetailTalentPicker()
    if win and win:IsShown() then win:Hide() end
end
