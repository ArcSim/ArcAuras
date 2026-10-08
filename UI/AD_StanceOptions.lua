-- AD_StanceOptions: a Stance icon's rows. Tracking, under the Shows row that
-- AD_Options draws from the schema: One stance's pick from your stance bar,
-- by name and stored by spell ID, and a spell ID box for a stance this
-- character does not have. The Add window's rows, Create, and the card words.
-- AD_Options calls in behind nil checks: Options.StanceTrackRows,
-- StanceAddRows, StanceCanCreate, StanceCreate and StanceWhat.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- the stance driver at call time: the options may build before it answers
local function Driver() return NS.DriverStance end

-- a stance's name, else its spell ID in words
function Options.StanceName(sid)
    local D = Driver()
    return (D and D.Name(sid)) or ("Spell " .. tostring(sid))
end

-- The pick's list: "Pick a stance" until one is, your stance bar's entries by
-- name (each by its spell ID), and the pick when it is not on your bar.
function Options.StanceItems(pick)
    local D = Driver()
    local out = {}
    if not pick then out[1] = { value = 0, text = "Pick a stance" } end
    for _, e in ipairs(D and D.BarList() or {}) do
        out[#out + 1] = { value = e.sid, text = e.name or ("Spell " .. e.sid) }
    end
    if pick and not (D and D.OnBar(pick)) then
        out[#out + 1] = { value = pick, text = Options.StanceName(pick) .. " (not on your bar)" }
    end
    return out
end

-- What the pick's dropdown shows: your bar's entry for it (another rank of it
-- reads as the one you have), else the pick, else nothing picked.
function Options.StanceValue(pick)
    local D = Driver()
    local e = pick and D and D.OnBar(pick)
    return (e and e.sid) or pick or 0
end

-- The layout view's card line.
function Options.StanceWhat(rec)
    if NS.Store.Resolve(rec, "stance", "shows") ~= "one" then return "your current stance" end
    local D = Driver()
    local pick = D and D.Pick(rec)
    if not pick then return "one stance, none picked yet" end
    return "one stance: " .. Options.StanceName(pick)
end

-- A new pick names the icon after it, as a totem's spell ID does; an empty
-- box clears it, a typo changes nothing.
local function SetPick(r, v, refresh)
    local d = r.driver
    if type(d) ~= "table" then
        d = {}
        r.driver = d
    end
    local sid = tonumber(v)
    if sid and sid > 0 then
        sid = math.floor(sid)
        if d.spellID == sid then return end -- raw-id: an unchanged pick, not a match
        d.spellID = sid
        local D = Driver()
        local nm = D and D.Name(sid)
        if nm then r.name = nm end
    elseif tostring(v or "") == "" then
        if d.spellID == nil then return end
        d.spellID = nil
    else
        return
    end
    NS.Store.Dirty("tree")
    refresh()
end

-- ctx: the selected icon. vis: the Tracking tab shows. owner: the window the
-- dropdown lists open on. refresh: the panel's full refresh.
function Options.StanceTrackRows(pg, ctx, vis, owner, refresh)
    local AT, Store = NS.AT, NS.Store
    -- one stance icon: several at once share no driver to write
    local function Rec()
        local r = ctx()
        if not (r and r.kind == "stance" and not r._adMulti) then return nil end
        return r
    end
    local function Pick()
        local r, D = Rec(), Driver()
        return r and D and D.Pick(r) or nil
    end
    local function baseVis() return vis() and Rec() ~= nil end
    local function oneVis()
        local r = Rec()
        return vis() and r ~= nil and Store.Resolve(r, "stance", "shows") == "one"
    end

    local pickRow = AT.RowDropdown(pg, owner, "Stance",
        function() return Options.StanceValue(Pick()) end,
        function(v)
            local r = Rec()
            if r and (tonumber(v) or 0) > 0 then SetPick(r, v, refresh) end
        end,
        function() return Options.StanceItems(Pick()) end,
        oneVis)
    AT.Tooltip(pickRow, "Stance", "A stance, form or aura from your stance bar. The icon lights up while you are in it.")
    -- found by the search under Your current stance too; the jump flashes Shows
    pickRow._adMeta = { family = "icon", section = "stance", field = "stancePick",
        def = { label = "Stance", dep = { field = "shows", value = "one" } }, baseVis = baseVis }

    local idRow = AT.RowInput(pg, "Stance spell ID",
        function()
            local p = Pick()
            return p and tostring(p) or ""
        end,
        function(v)
            local r = Rec()
            if r then SetPick(r, v, refresh) end
        end,
        oneVis,
        "The stance's spell ID: one this character does not have, such as another class's.",
        "Type a spell ID")
    idRow._adMeta = { family = "icon", section = "stance", field = "stanceSpellID",
        def = { label = "Stance spell ID", dep = { field = "shows", value = "one" } }, baseVis = baseVis }

    AT.RowDesc(pg, "Not on this character's stance bar: it lights up on one that has it.", 20, function()
        local p, D = Pick(), Driver()
        return oneVis() and p ~= nil and D ~= nil and D.OnBar(p) == nil
    end)
end

-- The Add window's rows: what it shows, then One stance's pick.
function Options.StanceAddRows(pg, owner, addState, vis, changed)
    local AT = NS.AT
    local def = NS.Schema.icon.stance.fields.shows
    local function oneVis() return vis() and addState.stanceShows == "one" end
    AT.RowDesc(pg, "The stance or form you are in, or one lit while you are in it.", 20, vis)
    local shows = AT.RowDropdown(pg, owner, "Shows",
        function() return addState.stanceShows == "one" and "one" or "current" end,
        function(v)
            addState.stanceShows = v
            AT.LayoutPage(pg)
            changed()
        end,
        function()
            local out = {}
            for _, v in ipairs(def.values) do out[#out + 1] = { value = v, text = def.labels[v] } end
            return out
        end,
        vis)
    AT.Tooltip(shows, "Shows", def.desc)
    AT.RowDropdown(pg, owner, "Stance",
        function() return Options.StanceValue(tonumber(addState.stanceSpell)) end,
        function(v)
            if (tonumber(v) or 0) <= 0 then return end
            addState.stanceSpell = tostring(v)
            AT.LayoutPage(pg)
            changed()
        end,
        function() return Options.StanceItems(tonumber(addState.stanceSpell)) end,
        oneVis)
    AT.RowInput(pg, "Stance spell ID",
        function() return addState.stanceSpell or "" end,
        function(v)
            addState.stanceSpell = v
            changed()
        end,
        oneVis, "The stance's spell ID: one this character does not have, such as another class's.",
        "Or type a spell ID", true)
end

-- Create lights for your current stance at once, for One stance with a pick.
function Options.StanceCanCreate(addState)
    if addState.stanceShows ~= "one" then return true end
    local sid = tonumber(addState.stanceSpell)
    return sid ~= nil and sid > 0
end

-- The new icon, named for its stance (Stance for your current one).
function Options.StanceCreate(addState, dest, layoutId)
    local Store = NS.Store
    local one = addState.stanceShows == "one"
    local sid = one and tonumber(addState.stanceSpell) or nil
    if one and not (sid and sid > 0) then return nil end
    if sid then sid = math.floor(sid) end
    local rec = Store.NewIcon("stance", { spellID = sid }, dest, layoutId, one and Options.StanceName(sid) or "Stance")
    if rec and one then Store.SetOverride(rec, "stance", "shows", "one") end
    return rec
end
