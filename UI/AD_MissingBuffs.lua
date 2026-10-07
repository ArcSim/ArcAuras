-- AD_MissingBuffs: the Missing Buffs template: a Dynamic aura group of icons, each shown only while its buff is missing.
-- AD_Options builds the Add window and calls Options.MissingBuffsAddRows, MissingBuffsCanCreate and MissingBuffsCreate.
-- The game draws each icon, so it shows and packs in combat; ranks and variants are read from the client by name.
local ADDON, NS = ...

local MB = {}
NS.MissingBuffs = MB

MB.SECTIONS = {
    { key = "raid", text = "RAID BUFFS" },
    { key = "class", text = "YOUR CLASS" },
    { key = "consumable", text = "CONSUMABLES" },
}

-- Each entry: its words, its section, the class it belongs to (none: every
-- class), the spells that stand for it on this client, and specs (retail)
-- when it is one spec's. expand: every spell named as one of these joins too,
-- with the same icon ("name": any icon), so other ranks and versions count.
MB.RETAIL = {
    { key = "shout", name = "Battle Shout", sect = "raid", ids = { 6673 } },
    { key = "intellect", name = "Arcane Intellect", sect = "raid", ids = { 1459 } },
    { key = "fortitude", name = "Power Word: Fortitude", sect = "raid", ids = { 21562 } },
    { key = "mark", name = "Mark of the Wild", sect = "raid", ids = { 1126 } },
    -- one buff ID per class, all one name
    { key = "bronze", name = "Blessing of the Bronze", sect = "raid", ids = { 381748, 381732, 381758 }, expand = true },
    { key = "skyfury", name = "Skyfury", sect = "raid", ids = { 462854 } },
    { key = "lethal", name = "Lethal Poison", sect = "class", class = "ROGUE", ids = { 315584, 2823, 8679, 381664 } },
    { key = "nonlethal", name = "Non-Lethal Poison", sect = "class", class = "ROGUE", ids = { 3408, 5761, 381637 } },
    { key = "shield", name = "Lightning or Water Shield", sect = "class", class = "SHAMAN", ids = { 192106, 52127 } },
    { key = "shadowform", name = "Shadowform", sect = "class", class = "PRIEST", specs = { 258 }, ids = { 232698 } },
    { key = "paladinaura", name = "Paladin Aura", sect = "class", class = "PALADIN", ids = { 465, 317920, 32223 } },
    { key = "flask", name = "Flask", sect = "consumable", ids = { 1235057, 1235108, 1235110, 1235111 }, expand = true },
    { key = "rune", name = "Augment Rune", sect = "consumable", ids = { 1264426, 1295329, 1234969, 1242347, 453250 } },
    { key = "food", name = "Food", sect = "consumable", ids = { 19705, 462181 }, expand = "name" },
}
MB.FOREVER = {
    { key = "fortitude", name = "Fortitude", sect = "raid", ids = { 1243, 21562 }, expand = true },
    { key = "intellect", name = "Arcane Intellect", sect = "raid", ids = { 1459, 23028 }, expand = true },
    { key = "mark", name = "Mark of the Wild", sect = "raid", ids = { 1126, 21849 }, expand = true },
    { key = "shout", name = "Battle Shout", sect = "raid", ids = { 6673 }, expand = true },
    { key = "spirit", name = "Divine Spirit", sect = "raid", ids = { 14752, 27681 }, expand = true },
    { key = "shadowprot", name = "Shadow Protection", sect = "raid", ids = { 976, 27683 }, expand = true },
    { key = "kings", name = "Blessing of Kings", sect = "raid", ids = { 20217, 25898 }, expand = true },
    { key = "might", name = "Blessing of Might", sect = "raid", ids = { 19740, 25782 }, expand = true },
    { key = "wisdom", name = "Blessing of Wisdom", sect = "raid", ids = { 19742, 25894 }, expand = true },
    { key = "salvation", name = "Blessing of Salvation", sect = "raid", ids = { 1038, 25895 }, expand = true },
    { key = "innerfire", name = "Inner Fire", sect = "class", class = "PRIEST", ids = { 588 }, expand = true },
    { key = "magearmor", name = "Mage Armor", sect = "class", class = "MAGE", ids = { 168, 7302, 6117 }, expand = true },
    { key = "demonarmor", name = "Demon Armor", sect = "class", class = "WARLOCK", ids = { 687, 706 }, expand = true },
    { key = "lshield", name = "Lightning Shield", sect = "class", class = "SHAMAN", ids = { 324 }, expand = true },
    { key = "aspect", name = "Aspect", sect = "class", class = "HUNTER",
        ids = { 13165, 13163, 5118, 13161, 13159, 20043 }, expand = true },
    { key = "trueshot", name = "Trueshot Aura", sect = "class", class = "HUNTER", ids = { 19506 }, expand = true },
    { key = "thorns", name = "Thorns", sect = "class", class = "DRUID", ids = { 467 }, expand = true },
    { key = "rfury", name = "Righteous Fury", sect = "class", class = "PALADIN", ids = { 25780 } },
    { key = "flask", name = "Flask", sect = "consumable", ids = { 17626, 17627, 17628, 17629 } },
    { key = "food", name = "Food", sect = "consumable", ids = { 19705 }, expand = "name" },
}

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- the spell's name when this client has it, plain
function MB.NameOf(id)
    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(nm) ~= "string" or Secret(nm) or nm == "" then return nil end
    return nm
end

-- an entry's spells this client has
function MB.IDs(e)
    local out = {}
    for _, id in ipairs(e.ids) do
        if MB.NameOf(id) then out[#out + 1] = id end
    end
    return out
end

-- the entries for this client and class, in order; one this client has no
-- spell of is left out
function MB.List()
    local list = (NS.IsForever == true) and MB.FOREVER or MB.RETAIL
    local cls = NS.Store.ClassTag and NS.Store.ClassTag()
    local out = {}
    for _, e in ipairs(list) do
        if (e.class == nil or e.class == cls) and #MB.IDs(e) > 0 then out[#out + 1] = e end
    end
    return out
end

function MB.Picked(addState)
    local picks, out = addState.mbPicks or {}, {}
    for _, e in ipairs(MB.List()) do
        if picks[e.key] then out[#out + 1] = e end
    end
    return out
end

-- An entry's IDs, then every spell sharing a name (and an icon) with one of
-- them: cb(state, idsByKey, pct), "loading" while the client's spells are
-- read, then "done".
function MB.Resolve(entries, cb)
    local base, wants, owner = {}, {}, {}
    for _, e in ipairs(entries) do
        local ids = MB.IDs(e)
        base[e.key] = ids
        if e.expand then
            local seen = {}
            for _, id in ipairs(ids) do
                local nm = MB.NameOf(id)
                local icons
                if e.expand ~= "name" then
                    local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                    if tex ~= nil and not Secret(tex) then icons = { [tex] = true } end
                end
                local sig = nm .. "\1" .. tostring(icons and next(icons) or "")
                if not seen[sig] then
                    seen[sig] = true
                    wants[#wants + 1] = { name = nm, icons = icons }
                    owner[#wants] = e.key
                end
            end
        end
    end
    local SN = NS.SpellNames
    if #wants == 0 or not (SN and SN.FindExact) then
        cb("done", base, 100)
        return
    end
    SN.FindExact(wants, function(state, out, pct)
        if state ~= "done" then
            cb(state, nil, pct)
            return
        end
        for i, list in ipairs(out) do
            local ids = base[owner[i]]
            local have = {}
            for _, v in ipairs(ids) do have[v] = true end
            for _, v in ipairs(list) do
                if not have[v] then
                    have[v] = true
                    ids[#ids + 1] = v
                end
            end
        end
        cb("done", base, 100)
    end)
end

-- The group and its icons: a Dynamic aura group one row wide, each icon on
-- you, any caster, at Active opacity 0 (shown only while missing), for the
-- whole class (an entry with specs: those specs).
function MB.Build(layoutId, name, entries, idsByKey)
    local Store = NS.Store
    local g = Store.NewGroup(layoutId, name, "aura")
    if not g then return nil end
    Store.SetOverride(g, "arrangement", "dynamicLayout", true)
    Store.SetOverride(g, "arrangement", "cols", math.max(1, math.min(20, #entries)))
    local tag = Store.ClassTag and Store.ClassTag()
    for _, e in ipairs(entries) do
        local ids = idsByKey[e.key]
        if ids and #ids > 0 then
            local d = { auraType = "buff", unit = "player" }
            NS.Options.SetAuraSpellIDs(d, ids)
            local r = Store.NewIcon("aura", d, g.id, layoutId, e.name)
            if r then
                Store.SetOverride(r, "auraActive", "activeAlpha", 0)
                r.c.specs = nil
                if e.specs and NS.IsForever ~= true then
                    r.c.specs = {}
                    for _, s in ipairs(e.specs) do r.c.specs[s] = true end
                end
                r.c.classes = tag and { [tag] = true } or nil
            end
        end
    end
    Store.Dirty("tree")
    return g
end

function MB.CanCreate(addState)
    return not MB.busy and #MB.Picked(addState) > 0
end

-- Create: the picks resolved, then built. onProgress(pct) while the client's
-- spells are read (once a session; a fight pauses it), onDone(group).
function MB.Create(addState, layoutId, onProgress, onDone)
    local entries = MB.Picked(addState)
    if #entries == 0 or MB.busy then return end
    local nm = (type(addState.groupName) == "string") and addState.groupName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if nm == "" then nm = "Missing Buffs" end
    MB.busy = true
    MB.Resolve(entries, function(state, ids, pct)
        if state ~= "done" then
            if MB.status then MB.status.fs:SetText(("Reading the game's spells, once a session: %d%%"):format(pct or 0)) end
            if onProgress then onProgress(pct or 0) end
            return
        end
        MB.busy = false
        local g = NS.Store.Get(layoutId) and MB.Build(layoutId, nm, entries, ids) or nil
        if g then addState.mbPicks = nil end
        if onDone then onDone(g) end
    end)
end

-- the hover words: what it watches
function MB.Tip(e)
    local names, seen = {}, {}
    for _, id in ipairs(MB.IDs(e)) do
        local nm = MB.NameOf(id)
        if nm and not seen[nm] then
            seen[nm] = true
            names[#names + 1] = nm
        end
    end
    local t = "Shows while you have none of: " .. table.concat(names, ", ") .. "."
    if e.expand == "name" then return t .. " Every food counts." end
    if e.expand then return t .. " Every rank counts, from anyone." end
    return t
end

MB.CELL, MB.PITCH, MB.TOP = 32, 36, 14

-- One row of squares per section: a click picks or drops an entry, picks
-- edged cyan.
function MB.SectionRow(pg, sect, addState, vis)
    local AT, COL = NS.AT, NS.AT.COL
    local function Entries()
        local out = {}
        for _, e in ipairs(MB.List()) do
            if e.sect == sect.key then out[#out + 1] = e end
        end
        return out
    end
    local row = AT.AddRow(pg, MB.TOP + MB.CELL + 4, function() return vis() and #Entries() > 0 end)
    local cap = row:CreateFontString(nil, "OVERLAY")
    cap:SetFont(STANDARD_TEXT_FONT, 9, "")
    cap:SetPoint("TOPLEFT", 10, -2)
    cap:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    cap:SetText(sect.text)
    row._cells = {}
    local function Cell(i)
        local b = row._cells[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(MB.CELL, MB.CELL)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        function b.Edge(hot)
            local on = addState.mbPicks and addState.mbPicks[b._key]
            local c = (on and COL.arc) or (hot and COL.arcDeep) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(b._entry.name, COL.ink[1], COL.ink[2], COL.ink[3])
            GameTooltip:AddLine(MB.Tip(b._entry), COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            addState.mbPicks = addState.mbPicks or {}
            addState.mbPicks[b._key] = (not addState.mbPicks[b._key]) or nil
            AT.LayoutPage(pg)
        end)
        row._cells[i] = b
        return b
    end
    row._sync = function()
        local list = Entries()
        for i, e in ipairs(list) do
            local b = Cell(i)
            b._key, b._entry = e.key, e
            local id = MB.IDs(e)[1]
            b.tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + (i - 1) * MB.PITCH, -MB.TOP)
            b.Edge(b:IsMouseOver())
            b:Show()
        end
        for i = #list + 1, #row._cells do row._cells[i]:Hide() end
    end
    return row
end

-- The Add window's rows under Group kind, for Missing Buffs
function MB.AddRows(pg, owner, addState)
    local AT, COL = NS.AT, NS.AT.COL
    local vis = function() return addState.cat == "Group" and addState.groupKind == "missing" end
    AT.RowDesc(pg, "Each icon shows only while its buff is missing, in combat too.", 20, vis)
    for _, sect in ipairs(MB.SECTIONS) do MB.SectionRow(pg, sect, addState, vis) end
    -- while Create reads the game's spells for the ranks
    local st = AT.AddRow(pg, 20, function() return vis() and MB.busy == true end)
    st.fs = st:CreateFontString(nil, "OVERLAY")
    st.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    st.fs:SetPoint("TOPLEFT", 10, -2)
    st.fs:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    st.fs:SetText("")
    MB.status = st
end

-- AD_Options loads first and calls these while building the Add window
if NS.Options then
    NS.Options.MissingBuffsAddRows = MB.AddRows
    NS.Options.MissingBuffsCanCreate = MB.CanCreate
    NS.Options.MissingBuffsCreate = MB.Create
end
