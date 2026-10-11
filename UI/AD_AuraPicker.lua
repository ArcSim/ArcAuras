-- AD_AuraPicker: the Add window's aura squares. Ready-made auras first, then
-- the auras your Cooldown Manager tracks for this spec, then the auras its
-- cooldown spells carry (NS.CDMMirror.AuraEntries). Typing in the aura's name
-- box filters them; a click fills the aura form (IDs, type, unit, who casts)
-- and Create stays the commit. The Cooldown Manager is read out of combat only.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local AP = {}
Options.AuraPicker = AP

AP.CELL, AP.GAP, AP.ROWS, AP.TOP, AP.HEAD = 32, 4, 8, 14, 14
AP.PITCH = AP.CELL + AP.GAP
-- a square the Cooldown Manager does not show, or a spell not learned
AP.DIM = 0.45

-- Ready-made auras any class can use. Every version of the buff rides one
-- icon, and anyone may cast it. retail: Forever has no such buff.
-- show: the spells whose names the name stands for; tipFmt and tipIDs: the
-- hover line, its spells named by the game on another language.
AP.TEMPLATES = {
    { key = "lust", name = "Bloodlust / Heroism", spellID = 2825, auraType = "buff", caster = "any", retail = true,
      show = { 2825, 32182 },
      find = "bloodlust heroism time warp primal rage fury of the aspects harrier's cry drums",
      tip = "Any lust on you: Bloodlust, Heroism, Time Warp, Primal Rage, Fury of the Aspects, Harrier's Cry and the drums, on one icon.",
      tipFmt = "Any lust on you: %s and the drums, on one icon.",
      tipIDs = { 2825, 32182, 80353, 264667, 390386, 466904 },
      ids = { 2825, 32182, 80353, 264667, 390386, 466904, 90355, 160452, 146555, 178207,
          230935, 256740, 309658, 381301, 444257, 1243972 } },
}

local function EnglishClient()
    local loc = GetLocale and GetLocale()
    return loc == nil or loc == "enUS" or loc == "enGB"
end

-- Lower case for matching, accented and Cyrillic capitals too (the options
-- search's fold); the English letters alone without it.
function AP.Fold(s)
    local S = Options.Search
    if S and S.Fold then return S.Fold(s) end
    return tostring(s or ""):lower()
end

-- The game's names for these spells on this client, or nil when one has none.
function AP.LiveNames(ids)
    local f = C_Spell and C_Spell.GetSpellName
    if not f then return nil end
    local out = {}
    for _, id in ipairs(ids or {}) do
        local nm = f(id) -- raw-id: a template's own spells, for their names
        if type(nm) ~= "string" or nm == "" or (issecretvalue and issecretvalue(nm)) then return nil end
        out[#out + 1] = nm
    end
    return out
end

-- A template's name, hover line and search words: the English as written on
-- an English client; on another, the game's names for its spells (English
-- when it has none) and the English words still find it.
function AP.Words(t)
    if EnglishClient() then return t.name, t.tip, t.find end
    local name, tip, find = t.name, t.tip, t.find
    local shown = AP.LiveNames(t.show)
    if shown then name = table.concat(shown, " / ") end
    local named = t.tipFmt and AP.LiveNames(t.tipIDs)
    if named then
        local fmt = (NS.L and NS.L[t.tipFmt]) or t.tipFmt
        tip = fmt:format(table.concat(named, ", "))
    end
    local all = AP.LiveNames(t.ids) or shown or {}
    find = AP.Fold((find or "") .. " " .. table.concat(all, " "))
    return name, tip, find
end

AP.TITLES = {
    tpl = "TEMPLATES",
    cdm = "TRACKED BY THE COOLDOWN MANAGER",
    spell = "AURAS ON YOUR SPELLS",
}

-- the templates as squares, their art read once
function AP.TemplateEntries()
    if AP.tpl then return AP.tpl end
    local out = {}
    local f = C_Spell and C_Spell.GetSpellTexture
    for _, t in ipairs(AP.TEMPLATES) do
        if not (t.retail and NS.IsForever == true) then
            local tex = f and f(t.spellID) -- raw-id: a template's own art
            if issecretvalue and issecretvalue(tex) then tex = nil end
            local ids = {}
            for i, id in ipairs(t.ids) do ids[i] = id end
            local name, tip, find = AP.Words(t)
            out[#out + 1] = { template = true, key = t.key, name = name, en = t.name, spellID = t.spellID, ids = ids,
                auraType = t.auraType, caster = t.caster, tip = tip, find = find,
                texture = tex, known = true, shown = true }
        end
    end
    AP.tpl = out
    return out
end

-- the three parts in order, and why the Cooldown Manager's may be short
function AP.Lists(fresh)
    local M = NS.CDMMirror
    local tracked, spells, why = {}, {}, nil
    if M and M.AuraEntries then tracked, spells, why = M.AuraEntries(fresh) end
    return {
        { key = "tpl", list = AP.TemplateEntries() },
        { key = "cdm", list = tracked },
        { key = "spell", list = spells },
    }, why
end

-- the line under the Cooldown Manager's title when it gave no aura at all
function AP.Note(parts, why)
    if #parts[2].list > 0 or #parts[3].list > 0 then return nil end
    if why == "combat" then return Tr("Leave combat to read your Cooldown Manager.") end
    return Tr("Your Cooldown Manager lists no auras here.")
end

-- The name box's text: letters filter by name (a template by its own words
-- too); IDs keep every square and light the one they start with. A letter of
-- another script (Cyrillic, Hangul) counts too.
function AP.Query(text)
    text = tostring(text or "")
    if text:find("%a") or text:find("[\128-\255]") then
        return (AP.Fold(text):gsub("^%s+", ""):gsub("%s+$", "")), nil
    end
    return nil, tonumber(text:match("%d+") or "")
end

function AP.Matches(e, query)
    if not query or query == "" then return true end
    if AP.Fold(e.name or ""):find(query, 1, true) then return true end
    return e.find ~= nil and e.find:find(query, 1, true) ~= nil
end

-- the height of every square and title, matched or not, so typing never
-- moves the rows below
function AP.Height(parts, cols, note)
    local h = 0
    for _, p in ipairs(parts) do
        local n = #p.list
        if n > 0 then
            h = h + AP.HEAD + math.ceil(n / cols) * AP.PITCH
        elseif p.key == "cdm" and note then
            h = h + AP.HEAD + AP.PITCH
        end
    end
    return math.max(AP.PITCH, h) - AP.GAP
end

-- A pick into the aura form: its IDs as a list, its side, the unit that side
-- lives on (a debuff on your target, a buff on you) and who casts it (you,
-- unless a template says anyone). A template names the icon after itself.
function AP.Fill(addState, e)
    addState.auraID = table.concat(e.ids, ", ")
    -- the icon's stored name stays the template's English words
    addState.auraName = e.template and (e.en or e.name) or nil
    local t = (e.auraType == "debuff") and "debuff" or "buff"
    addState.auraType = t
    addState.auraUnit = (t == "debuff") and "target" or "player"
    addState.auraCaster = e.caster or "mine"
end

-- The row: vis says when it shows, getText reads the name box, onFill runs
-- after a pick (the window re-lays out and judges Create). Returns its
-- refresh, for the name box's keystrokes.
function Options.AuraPickerRow(pg, owner, addState, vis, getText, onFill)
    local AT = NS.AT
    local COL = AT.COL
    local row = AT.AddRow(pg, AP.TOP + AP.PITCH, vis)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(AT.FONT, 9, "")
    label:SetPoint("TOPLEFT", 10, -2)
    label:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    label:SetText(Tr("PICK AN AURA - click to fill"))
    row._scroll, row._grid = AT.MakeScroll(row)
    row._scroll:SetPoint("TOPLEFT", 8, -AP.TOP)
    row._scroll:SetPoint("BOTTOMRIGHT", -12, AP.GAP)
    local grid = row._grid
    local heads = {}
    for i, key in ipairs({ "tpl", "cdm", "spell" }) do
        local fs = grid:CreateFontString(nil, "OVERLAY")
        fs:SetFont(AT.FONT, 9, "")
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        fs:SetText(Tr(AP.TITLES[key]))
        fs:Hide()
        heads[i] = fs
    end
    row._heads = heads
    local note = grid:CreateFontString(nil, "OVERLAY")
    note:SetFont(AT.FONT, 11, "")
    note:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    note:Hide()
    row._note = note
    row._empty = row:CreateFontString(nil, "OVERLAY")
    row._empty:SetFont(AT.FONT, 11, "")
    row._empty:SetPoint("LEFT", row._scroll, "TOPLEFT", 2, -AP.CELL / 2)
    row._empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row._empty:SetText(Tr("Nothing here matches: the name search below still works."))
    row._empty:Hide()
    local cells = {}
    row._cells = cells
    -- the window opening reads the Cooldown Manager again: its settings
    -- window saves the arrangement with no event
    row._fresh = true
    owner:HookScript("OnShow", function() row._fresh = true end)
    local function Cell(i)
        local b = cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, grid, "BackdropTemplate")
        b:SetSize(AP.CELL, AP.CELL)
        AT.Skin(b, COL.well, COL.line)
        -- inset past the edge so the art never covers the border
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- the pick stays cyan under the cursor too
        function b.Edge(hot)
            local c = (b._picked and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            local e = b._e
            if not e then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            if e.template then
                GameTooltip:SetText(e.name, COL.ink[1], COL.ink[2], COL.ink[3])
                GameTooltip:AddLine(Tr(e.tip), COL.dim[1], COL.dim[2], COL.dim[3], true)
            else
                GameTooltip:SetSpellByID(e.spellID) -- raw-id: a Cooldown Manager entry
            end
            -- a template's words name its buffs; its IDs are no help there
            local n = #e.ids
            if not e.template then
                local ids = table.concat(e.ids, ", ", 1, math.min(n, 12)) .. ((n > 12) and ", ..." or "")
                GameTooltip:AddLine((n > 1 and Tr("Spell IDs: %s") or Tr("Spell ID: %s")):format(ids),
                    COL.arc[1], COL.arc[2], COL.arc[3], true)
            end
            if not e.known then
                GameTooltip:AddLine(Tr("Not learned"), COL.dim[1], COL.dim[2], COL.dim[3])
            elseif not e.shown then
                GameTooltip:AddLine(Tr("Not shown by your Cooldown Manager"), COL.dim[1], COL.dim[2], COL.dim[3])
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local e = b._e
            if not e then return end
            AP.Fill(addState, e)
            if onFill then onFill() end
        end)
        cells[i] = b
        return b
    end
    local function Update(inLayout)
        if not vis() then return end
        local fresh = row._fresh
        row._fresh = nil
        local parts, why = AP.Lists(fresh)
        local noteText = AP.Note(parts, why)
        local cols = math.max(1, math.floor((owner:GetWidth() - 64 + AP.GAP) / AP.PITCH))
        local full = AP.Height(parts, cols, noteText)
        local want = AP.TOP + math.min(full, AP.ROWS * AP.PITCH - AP.GAP) + AP.GAP
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
            -- the rows below move with it; that pass syncs back here
            if not inLayout then AT.LayoutPage(pg) return end
        end
        local query, pickID = AP.Query(getText())
        local y, n = 0, 0
        local noteShown = false
        for pi, p in ipairs(parts) do
            local hits = {}
            for _, e in ipairs(p.list) do
                if AP.Matches(e, query) then hits[#hits + 1] = e end
            end
            local withNote = query == nil and p.key == "cdm" and noteText ~= nil
            local head = heads[pi]
            if #hits > 0 or withNote then
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", 2, -y - 2)
                head:Show()
                y = y + AP.HEAD
                if withNote then
                    note:ClearAllPoints()
                    note:SetPoint("LEFT", grid, "TOPLEFT", 2, -y - AP.CELL / 2)
                    note:SetText(noteText)
                    noteShown = true
                    y = y + AP.PITCH
                end
                for i, e in ipairs(hits) do
                    n = n + 1
                    local b = Cell(n)
                    b._e = e
                    b._picked = pickID ~= nil and e.ids[1] == pickID -- raw-id: a picker pick, not a match
                    b.tex:SetTexture(e.texture or 134400)
                    local dim = not (e.known and e.shown)
                    b.tex:SetDesaturated(dim)
                    b.tex:SetAlpha(dim and AP.DIM or 1)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", ((i - 1) % cols) * AP.PITCH,
                        -(y + math.floor((i - 1) / cols) * AP.PITCH))
                    b.Edge(b:IsMouseOver())
                    b:Show()
                end
                y = y + math.ceil(#hits / cols) * AP.PITCH
            else
                head:Hide()
            end
        end
        note:SetShown(noteShown)
        for i = n + 1, #cells do
            cells[i]._e = nil
            cells[i]:Hide()
        end
        grid:SetSize(cols * AP.PITCH - AP.GAP, math.max(1, y - AP.GAP))
        row._scroll:UpdateScroll()
        row._empty:SetShown(n == 0 and not noteShown)
    end
    row._sync = function() Update(true) end
    return function() Update(false) end
end
