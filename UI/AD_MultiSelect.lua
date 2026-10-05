-- AD_MultiSelect: several sidebar rows selected at once: the "N selected" pane (Move or copy to, Edit together, Duplicate, Export selection, Delete selection) and the multi proxy the icon and bar editors read and write through.
-- AD_Options wires the rail clicks, the pane and the editors' gates behind nil checks; the proxy is Store.MultiProxy, and a write through it fans out in Store.SetOverride.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL = AT.COL
local ui = Options.ui

-- ids: the selection in click order; set: the same by id; items / n: the
-- sidebar's visible rows of the last refresh (Shift ranges read them); rev:
-- bumped on every change (the tab cache and the Move pick key on it);
-- anchor: the row a Shift click ranges from; editing / fam: Edit together
-- open on "icon" or "bar".
local M = { ids = {}, set = {}, items = {}, n = 0, rev = 0 }
Options.MultiSelect = M

-- the sidebar rows a selection can hold (a layout row never)
M.SELECTABLE = { group = true, groupicon = true, reminder = true, bar = true, freeicon = true }
-- what a record keeps to itself: never edited over several at once
M.PER_ITEM_TABS = { Tracking = true, Triggers = true, Position = true, ["Load Conditions"] = true }

local ICON_WORD = { spell = "cooldown", aura = "aura", item = "item", trinket = "trinket", timer = "custom",
    totem = "totem", ammo = "ammo", enchant = "enchant" }
local BAR_WORD = { cooldown = "cooldown", aura = "aura", timer = "custom", stack = "stack", swing = "swing",
    resource = "resource", health = "health", cast = "cast", enchant = "enchant", range = "range" }
local TYPE_ORDER = { "group", "bar", "icon", "reminder" }
local TYPE_WORD = { group = { "group", "groups" }, bar = { "bar", "bars" }, icon = { "icon", "icons" },
    reminder = { "reminder", "reminders" } }

-- The selection

function M.Count() return #M.ids end

function M.Has(id) return id ~= nil and M.set[id] == true end

function M.Add(id)
    if not id or M.set[id] then return false end
    M.set[id] = true
    M.ids[#M.ids + 1] = id
    M.rev = M.rev + 1
    return true
end

function M.Remove(id)
    if not M.set[id] then return false end
    M.set[id] = nil
    for i = #M.ids, 1, -1 do
        if M.ids[i] == id then table.remove(M.ids, i) end
    end
    M.rev = M.rev + 1
    return true
end

function M.Toggle(id)
    if M.set[id] then M.Remove(id) else M.Add(id) end
end

-- Forgets the selection and closes Edit together. The pane is whoever
-- selects next.
function M.Clear()
    if #M.ids == 0 and not M.editing then return end
    M.ids, M.set = {}, {}
    M.editing, M.fam = nil, nil
    M.rev = M.rev + 1
end

-- Drops what no longer exists (deleted since). True when something went.
function M.Prune()
    local changed = false
    for i = #M.ids, 1, -1 do
        local id = M.ids[i]
        if not Store.Get(id) then
            M.set[id] = nil
            table.remove(M.ids, i)
            changed = true
        end
    end
    if changed then M.rev = M.rev + 1 end
    return changed
end

-- the selected records, in click order
function M.Records()
    local out = {}
    for _, id in ipairs(M.ids) do
        local r = Store.Get(id)
        if r then out[#out + 1] = r end
    end
    return out
end

-- "3 groups, 2 bars, 4 icons": the selection by record type
function M.Summary()
    local counts = {}
    for _, r in ipairs(M.Records()) do counts[r.type] = (counts[r.type] or 0) + 1 end
    local parts = {}
    for _, t in ipairs(TYPE_ORDER) do
        local n = counts[t]
        if n then parts[#parts + 1] = n .. " " .. TYPE_WORD[t][n == 1 and 1 or 2] end
    end
    return table.concat(parts, ", ")
end

-- "3 icons (2 cooldown, 1 aura)": the band's words, kinds in first-seen order
function M.Words(fam)
    local counts, order, n = {}, {}, 0
    for _, r in ipairs(M.Records()) do
        local k
        if fam == "bar" then k = BAR_WORD[r.barKind] or r.barKind or "bar"
        else k = ICON_WORD[r.kind] or r.kind or "icon" end
        if not counts[k] then
            order[#order + 1] = k
            counts[k] = 0
        end
        counts[k] = counts[k] + 1
        n = n + 1
    end
    local parts = {}
    for _, k in ipairs(order) do parts[#parts + 1] = counts[k] .. " " .. k end
    return n .. (fam == "bar" and " bars" or " icons") .. " (" .. table.concat(parts, ", ") .. ")"
end

-- "icon" when every record is an icon, "bar" when every one is a bar, else
-- nil: Edit together needs one family.
function M.SameFamily()
    local fam
    for _, r in ipairs(M.Records()) do
        local t = r.type
        if t ~= "icon" and t ~= "bar" then return nil end
        if fam and fam ~= t then return nil end
        fam = t
    end
    return fam
end

-- The sidebar

-- The record whose editor is open, when a sidebar row could hold it: the
-- first member of a selection started with Ctrl.
function M.CurrentId()
    local t = ui.selType
    if t == "bar" then return ui.selId end
    if t == "group" then
        if ui.grpMode == "ico" then
            local ic = Store.Get(ui.selIconId)
            if ic and ic.groupId == ui.selId then return ic.id end
        elseif ui.grpMode == "rem" then
            local rm = Store.Get(ui.selRemId)
            if rm and rm.groupId == ui.selId then return rm.id end
        end
        return ui.selId
    end
    if t == "free" then
        local ic = Store.Get(ui.selIconId)
        if ic and not ic.groupId and ic.layoutId == ui.selId then return ic.id end
    end
end

-- An empty selection starts from the record being edited.
function M.Seed()
    if #M.ids > 0 then return end
    local id = M.CurrentId()
    if id and Store.Get(id) then
        M.Add(id)
        M.anchor = id
    end
end

-- Called by the sidebar refresh for every row, in order: keeps the visible
-- list for Shift ranges and takes a Ctrl or Shift click before the row's own.
function M.RailRow(row, item, index)
    M.items[index] = item
    M.n = index
    local orig = row:GetScript("OnClick")
    row:SetScript("OnClick", function(s, ...)
        if M.Click(item, index) then return end
        if item.rec and M.SELECTABLE[item.kind] then M.anchor = item.rec.id end
        if orig then orig(s, ...) end
    end)
end

-- Every selectable row between the anchor's row and `index` on the visible
-- list joins the selection. False when the anchor's row is not on the list.
function M.Range(anchorId, index)
    local from
    for i = 1, M.n do
        local it = M.items[i]
        if it and it.rec and it.rec.id == anchorId and M.SELECTABLE[it.kind] then
            from = i
            break
        end
    end
    if not from then return false end
    local a, b = math.min(from, index), math.max(from, index)
    for i = a, b do
        local it = M.items[i]
        if it and it.rec and M.SELECTABLE[it.kind] then M.Add(it.rec.id) end
    end
    return true
end

-- A click with Ctrl or Shift held: Ctrl toggles the row, Shift ranges from
-- the last row clicked. A layout row opens or shuts instead, keeping the
-- selection; other rows do nothing. True when the click was taken.
function M.Click(item, index)
    local ctrl, shift = IsControlKeyDown() == true, IsShiftKeyDown() == true
    if not (ctrl or shift) then return false end
    local rec = item.rec
    if not (rec and M.SELECTABLE[item.kind]) then
        if item.kind == "layout" and rec then
            local u = Store.UI()
            u.expanded = u.expanded or {}
            u.expanded[rec.id] = (not u.expanded[rec.id]) or nil
            Options.RefreshAll()
        end
        return true
    end
    M.Seed()
    if not (shift and M.anchor and M.Range(M.anchor, index)) then
        M.Toggle(rec.id)
        M.anchor = rec.id
    end
    M.Settle(rec)
    return true
end

-- After a change: two or more open the selection pane, one lands on that
-- record's editor, none on the row just clicked.
function M.Settle(clicked)
    M.Prune()
    local n = #M.ids
    if n >= 2 then
        Options.Select("multi")
    elseif n == 1 then
        M.Open(Store.Get(M.ids[1]))
    else
        M.Open(clicked)
    end
end

-- The single editor for a record.
function M.Open(rec)
    if not rec then return end
    if rec.type == "layout" then
        Options.Select("layout", rec.id)
    elseif rec.type == "group" then
        ui.grpMode = "grp"
        Options.Select("group", rec.id)
    elseif rec.type == "bar" then
        Options.Select("bar", rec.id)
    elseif rec.type == "icon" or rec.type == "reminder" then
        Options.SelectIconHome(rec)
    end
end

-- The layout the sidebar last had open, else the first, else nothing.
function M.OpenLast()
    local lay = Store.Get(ui.lastLayoutId)
    if not (lay and lay.type == "layout") then lay = Store.Layouts()[1] end
    if lay then
        Options.Select("layout", lay.id)
    else
        Options.Select("empty")
    end
end

-- A single pick (a row, a search jump, a new record) ends the selection.
function M.OnSelect(selType)
    if selType == "layout" or selType == "group" or selType == "free" or selType == "bar"
        or selType == "newlayout" then
        M.Clear()
    end
end

-- The proxy and the editors' gates

-- The multi proxy the editors read and write through while Edit together is
-- open on that family; nil otherwise, so the single editors are untouched.
function M.Proxy(fam)
    if ui.selType ~= "multi" or not M.editing or M.fam ~= fam or #M.ids < 2 then return nil end
    return Store.MultiProxy(M.ids, M.Applies)
end

-- The editor's own row test, per record: the schema's kind and mode gates,
-- the class, the group-only and showIf gates. A write lands where this holds.
function M.Applies(r, section, field, def)
    return Options.FieldShows(r, Store.FamilyOf(r), section, def) == true
end

-- True when every record of the proxy passes fn(rec).
function M.All(px, fn)
    for _, id in ipairs(px._adIds) do
        local r = Store.Get(id)
        if r and not fn(r) then return false end
    end
    return true
end

-- A row shows only when it shows for every record.
function M.FieldShows(px, family, section, def, tier)
    return M.All(px, function(r) return Options.FieldShows(r, family, section, def, tier) == true end)
end

-- A block the editors show over several records: never a per-item pane
-- (Fade When, Position, Anchor) or a block marked perItem; else one every
-- record has. test(rec, def): the editor's own BlockApplies.
function M.BlockApplies(px, def, test)
    if def.pane or def.perItem then return false end
    return M.All(px, function(r) return test(r, def) == true end)
end

-- the tabs every record has, in the first record's order, less the per-item
-- ones; cached per selection (the lists cost a block walk per record)
local function Intersect(lists)
    local out = {}
    for _, t in ipairs(lists[1] or {}) do
        local every = not M.PER_ITEM_TABS[t]
        for i = 2, #lists do
            local has = false
            for _, x in ipairs(lists[i]) do
                if x == t then
                    has = true
                    break
                end
            end
            if not has then
                every = false
                break
            end
        end
        if every then out[#out + 1] = t end
    end
    return out
end

-- keep(px, tab): false for a tab none of whose blocks survive the
-- intersection (an empty page otherwise)
local function TabsOf(px, fam, listFn, keep)
    local c = M.tabCache
    if not (c and c.rev == M.rev) then
        c = { rev = M.rev }
        M.tabCache = c
    end
    if c[fam] then return c[fam] end
    local lists = {}
    for _, id in ipairs(px._adIds) do
        local r = Store.Get(id)
        if r then lists[#lists + 1] = listFn(r) end
    end
    local out = {}
    for _, t in ipairs(Intersect(lists)) do
        if keep(px, t) then out[#out + 1] = t end
    end
    c[fam] = out
    return out
end

-- an icon tab with chips keeps one applicable sub-tab at least; Glows and
-- Sounds answer through the editor's own emptiness test, over the proxy
local STACKED_ICON = { Glows = true, Sounds = true }
local function KeepIconTab(px, t)
    if STACKED_ICON[t] then
        local empty = Options.iconTabEmpty
        return not (empty and empty(px, t))
    end
    local src = Options.SEARCH_SRC and Options.SEARCH_SRC.icon
    return not (src and src.subs and #src.subs(t, px) == 0)
end

-- a bar tab with chips the same; the two one-page tabs are kind-gated already.
-- The sub-tab list reads the editor's own bar, so only while that is the proxy.
local STACKED_BAR = { ["Heals & Shields"] = true, Castbar = true }
local function KeepBarTab(px, t)
    if STACKED_BAR[t] or M.Proxy("bar") ~= px then return true end
    local src = Options.SEARCH_SRC and Options.SEARCH_SRC.bar
    return not (src and src.subs and #src.subs(t) == 0)
end

function M.IconTabs(px) return TabsOf(px, "icon", Options._iconTabsFor, KeepIconTab) end

function M.BarTabs(px) return TabsOf(px, "bar", Options._barTabsFor, KeepBarTab) end

-- Mixed values

-- Two values read the same: colours by their numbers (a missing alpha is 1),
-- other tables key by key.
function M.Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    if type(a[1]) == "number" then
        for i = 1, 3 do
            if a[i] ~= b[i] then return false end
        end
        return (a[4] or 1) == (b[4] or 1)
    end
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- True while the records that have `field` do not all read the same value.
function M.Mixed(px, section, field)
    local seen, first = false, nil
    for _, id in ipairs(px._adIds) do
        local r = Store.Get(id)
        if r and Store.MultiTakes(px, r, section, field) then
            local v = Store.Resolve(r, section, field)
            if not seen then
                seen, first = true, v
            elseif not M.Same(v, first) then
                return true
            end
        end
    end
    return false
end

-- the mark, in the theme's faint ink
local function MarkText()
    if not M.mark then
        local c = COL.faint
        M.mark = string.format(" |cff%02x%02x%02x(mixed)|r",
            math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    end
    return M.mark
end

-- Shows or clears "(mixed)" after a label. The plain words are kept on the
-- row the first time, so the mark never stacks.
function M.SetMark(row, fs, on)
    if not fs then return end
    if row._adPlainLabel == nil then row._adPlainLabel = fs:GetText() or "" end
    local want = on and (row._adPlainLabel .. MarkText()) or row._adPlainLabel
    if fs:GetText() ~= want then fs:SetText(want) end
end

-- Wraps a schema row's sync (SectionRows): the mark while Edit together is
-- open and the records disagree on the field (or on `also`, the second
-- field a showPick dropdown writes). Costs one boolean otherwise.
function M.MarkRow(row, ctx, section, field, also)
    local sync = row._sync
    row._sync = function()
        if sync then sync() end
        if not M.editing then
            if row._adPlainLabel then M.SetMark(row, row._colLabel, false) end
            return
        end
        local r = ctx()
        M.SetMark(row, row._colLabel, r ~= nil and r._adMulti == true
            and (M.Mixed(r, section, field) or (also ~= nil and M.Mixed(r, section, also))))
    end
end

-- The state table's rows and the cards

-- Every record's kind has this state row, with the same field in each
-- column, so a cell edit lands on all of them.
function M.StateShared(px, st)
    local ET = Options.EditorTabs
    if not ET then return false end
    local COLS = { "alpha", "grey", "tint" }
    for i = 2, #px._adIds do
        local r = Store.Get(px._adIds[i])
        local list = r and ET.STATES[r.kind]
        local match
        for _, st2 in ipairs(list or {}) do
            if st2.label == st.label then
                match = st2
                break
            end
        end
        if not match then return false end
        for _, c in ipairs(COLS) do
            local a, b = st[c], match[c]
            if (a == nil) ~= (b == nil) then return false end
            if a and not (a[1] == b[1] and a[2] == b[2] and a.on == b.on) then
                return false
            end
        end
    end
    return true
end

-- any cell of the state row, or the look it copies, reads differently across
-- the records
function M.StateMixed(px, st)
    for _, c in ipairs({ "alpha", "grey", "tint" }) do
        local spec = st[c]
        if spec then
            for _, f in ipairs({ spec[2], spec.on }) do
                if f and M.Mixed(px, spec[1], f) then return true end
            end
        end
    end
    return st.base ~= nil and M.Mixed(px, st.base[1], st.base[2]) == true
end

local function WrapStateRow(row)
    local st, vis, sync = row._adStateRow, row._visibleFn, row._sync
    row._visibleFn = function()
        if vis and not vis() then return false end
        local px = M.Proxy("icon")
        return px == nil or M.StateShared(px, st)
    end
    row._sync = function()
        if sync then sync() end
        if not M.editing then
            if row._adPlainLabel then M.SetMark(row, row._adLabel, false) end
            return
        end
        local px = M.Proxy("icon")
        M.SetMark(row, row._adLabel, px ~= nil and M.StateMixed(px, st))
    end
end

-- the header shows only over rows every record shares
local function WrapStateHead(row)
    local T, vis = row._adStateHead, row._visibleFn
    row._visibleFn = function()
        if vis and not vis() then return false end
        if not M.Proxy("icon") then return true end
        for _, r in ipairs(T.rows) do
            if r._visibleFn() then return true end
        end
        return false
    end
end

-- a card's switch: the mark after the card's title
local function WrapCardHead(row)
    local c, m, sync = row._adCardHead, row._adMeta, row._sync
    row._sync = function()
        if sync then sync() end
        if not M.editing then
            if row._adPlainLabel then M.SetMark(row, c.title, false) end
            return
        end
        local px = M.Proxy(m.family == "bar" and "bar" or "icon")
        M.SetMark(row, c.title, px ~= nil and M.Mixed(px, m.section, m.field))
    end
end

-- The rows the editors build outside SectionRows, wrapped once per page on
-- its first multi use: the state table's rows and head, the cards' heads.
function M.WrapPage(pg)
    if pg._adMultiWrapped then return end
    pg._adMultiWrapped = true
    for _, sec in ipairs(pg._sections or {}) do
        for _, row in ipairs(sec.rows) do
            if row._adStateRow then WrapStateRow(row) end
            if row._adStateHead then WrapStateHead(row) end
            if row._adCardHead and row._adMeta then WrapCardHead(row) end
        end
    end
end

-- The editing band over several records: "Editing:  3 icons (2 cooldown, 1
-- aura)" with the actions and pills hidden, the first record's art kept; put
-- back on the next single record. host: the band's frame (host._adBand).
-- True when it drew the multi words.
function M.Band(host, rec, fam)
    local band = host._adBand
    if not band then return false end
    if not (rec and rec._adMulti) then
        if band._adMultiHid then
            band._adMultiHid = nil
            for _, b in ipairs(band.btns) do b:Show() end
            for _, r in ipairs(band.extra) do r:Show() end
        end
        return false
    end
    if not band._adMultiHid then
        band._adMultiHid = true
        for _, b in ipairs(band.btns) do b:Hide() end
        for _, r in ipairs(band.extra) do r:Hide() end
    end
    if host._icon then
        local first = Store.Get(rec._adIds[1])
        host._icon.tex:SetTexture(first and NS.Factory.GetTexture(first) or nil)
    end
    band.name:SetText("Editing:  " .. M.Words(fam))
    band.name:SetWidth(0)
    local row = band.row
    if row._h ~= band.h then
        row._h = band.h
        row:SetHeight(band.h)
    end
    return true
end

-- The actions

-- The Move or copy to targets: every layout (free there), and for icons alone
-- every group that takes each of them; a place the whole selection already
-- holds is left out. Values "L<id>" / "G<id>", as the band's Move to.
function M.MoveItems()
    local items = { { value = 0, text = "Pick a place..." } }
    local recs = M.Records()
    if #recs == 0 then return items end
    local iconsOnly = true
    for _, r in ipairs(recs) do
        if r.type ~= "icon" then
            iconsOnly = false
            break
        end
    end
    for _, lay in ipairs(Store.Layouts()) do
        local allHere = true
        for _, r in ipairs(recs) do
            if r.groupId or r.layoutId ~= lay.id then
                allHere = false
                break
            end
        end
        if not allHere then
            items[#items + 1] = { value = "L" .. lay.id, text = (iconsOnly and "Free in " or "") .. lay.name }
        end
        if iconsOnly then
            local groups = Store.ChildrenOf(lay)
            for _, g in ipairs(groups) do
                local takes, inside = true, true
                for _, r in ipairs(recs) do
                    if not Store.GroupTakes(g, r.kind) then
                        takes = false
                        break
                    end
                    if r.groupId ~= g.id then inside = false end
                end
                if takes and not inside then
                    items[#items + 1] = { value = "G" .. g.id, text = lay.name .. " / " .. g.name }
                end
            end
        end
    end
    return items
end

-- a picked place: its kind ("G" / "L"), its id and the store's target, or nil
local function PickTarget(value)
    if type(value) ~= "string" then return nil end
    local kind, id = value:sub(1, 1), tonumber(value:sub(2))
    if not id then return nil end
    if kind == "G" then return kind, id, { groupId = id } end
    if kind == "L" then return kind, id, { layoutId = id } end
end

-- lands on a picked place, unfolded (the single pick forgets the selection)
local function Land(kind, id)
    local u = Store.UI()
    u.expanded = u.expanded or {}
    if kind == "G" then
        local g = Store.Get(id)
        if g and g.layoutId then u.expanded[g.layoutId] = true end
        u.expanded[id] = true
        ui.grpMode = "grp"
        Options.Select("group", id)
    else
        u.expanded[id] = true
        Options.Select("layout", id)
    end
end

-- Moves the selection to a picked place and lands on that place. Returns how
-- many moved, or nil for a bad pick.
function M.Move(value)
    local kind, id, target = PickTarget(value)
    if not target then return nil end
    local moved = Store.MoveMany(M.ids, target)
    Land(kind, id)
    return #moved
end

-- Copies the selection into a picked place, the originals left where they
-- are, and lands on that place. Returns how many copies, or nil for a bad pick.
function M.Copy(value)
    local kind, id, target = PickTarget(value)
    if not target then return nil end
    local copies = Store.CopyMany(M.ids, target)
    Land(kind, id)
    return #copies
end

-- Copies every selected record beside its original (the band's Duplicate, for
-- several at once) and selects the copies, their rows unfolded. Returns how
-- many copies were made.
function M.Duplicate()
    local copies = Store.CopyMany(M.ids, nil)
    if #copies == 0 then return 0 end
    M.ids, M.set = {}, {}
    local u = Store.UI()
    u.expanded = u.expanded or {}
    for _, c in ipairs(copies) do
        M.Add(c.id)
        local g = Store.Get(c.groupId)
        if g then u.expanded[g.id] = true end
        local lid = c.layoutId or (g and g.layoutId)
        if lid then u.expanded[lid] = true end
    end
    M.anchor = copies[#copies].id
    M.Settle(copies[1])
    return #copies
end

-- Deletes every selected record, or the ids given (a group takes what is
-- inside it), and lands on the layout the sidebar last had open. Returns how
-- many went.
function M.Delete(ids)
    local n = 0
    for _, id in ipairs(ids or M.ids) do
        if Store.Get(id) then
            Store.Delete(id)
            n = n + 1
        end
    end
    if ui.selIconId and not Store.Get(ui.selIconId) then
        ui.selIconId = nil
        ui.grpMode = "grp"
    end
    M.Clear()
    M.OpenLast()
    return n
end

-- The question before Delete: the selection's summary, and what its groups
-- take with them that is not selected itself.
function M.DeleteText()
    local inside, groups = { icon = 0, reminder = 0 }, 0
    for _, r in ipairs(M.Records()) do
        if r.type == "group" then
            groups = groups + 1
            for _, mid in ipairs(r.members or {}) do
                local m = Store.Get(mid)
                if m and not M.set[mid] and inside[m.type] then inside[m.type] = inside[m.type] + 1 end
            end
        end
    end
    local parts = {}
    for _, t in ipairs({ "icon", "reminder" }) do
        local k = inside[t]
        if k > 0 then parts[#parts + 1] = k .. " " .. TYPE_WORD[t][k == 1 and 1 or 2] end
    end
    local text = "Delete " .. M.Summary() .. "?"
    if #parts > 0 then
        text = text .. "\n" .. (groups == 1 and "The group takes its " or "The groups take their ")
            .. table.concat(parts, " and ") .. " with " .. (groups == 1 and "it." or "them.")
    end
    return text
end

-- Asks first; a Yes deletes the selection as it stood when asked.
function M.ConfirmDelete()
    if #M.ids == 0 then return end
    StaticPopupDialogs["ARCUIV2_DELETE_MANY"] = StaticPopupDialogs["ARCUIV2_DELETE_MANY"] or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        preferredIndex = 3,
    }
    local d = StaticPopupDialogs["ARCUIV2_DELETE_MANY"]
    d.text = M.DeleteText()
    local ids = {}
    for i, id in ipairs(M.ids) do ids[i] = id end
    d.OnAccept = function() M.Delete(ids) end
    StaticPopup_Show("ARCUIV2_DELETE_MANY")
end

-- The Import / Export page with exactly this selection ticked and its share
-- string ready (a selected group takes its icons with it there).
function M.Export()
    local sel, open = {}, ui.ieOpen
    for _, r in ipairs(M.Records()) do
        sel[r.id] = true
        local lid = r.layoutId
        if not lid and r.groupId then
            local g = Store.Get(r.groupId)
            lid = g and g.layoutId
        end
        if lid then open[lid] = true end
    end
    ui.ieSel = sel
    Options.Select("ie")
    Options.ExportSelected()
end

-- Opens the family's editor under the actions, over every selected record.
function M.EditTogether()
    local fam = M.SameFamily()
    if not fam then return false end
    M.editing, M.fam = true, fam
    -- the tab lists are filtered over the proxy: a fresh cache
    M.rev = M.rev + 1
    Options.RefreshAll()
    return true
end

-- The pane

-- a one-line note row (no wrap, so the page's height never waits on a width)
local function Line(pg, h, size, color, visibleFn)
    local row = AT.AddRow(pg, h, visibleFn)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(color[1], color[2], color[3])
    row._adFS = fs
    return row
end

-- The pane: its header, the actions on a short page, and under them the icon
-- or bar editor's own page while Edit together is open. kit: those two pages.
function M.Fill(pane, header, win, kit)
    M.pane, M.header, M.win, M.kit = pane, header, win, kit
    local top = CreateFrame("Frame", nil, pane)
    top:SetPoint("TOPLEFT", 0, -36)
    top:SetPoint("TOPRIGHT", -4, -36)
    top:SetHeight(140)
    M.top = top
    local pg = AT.NewPage(top)
    pg:SetAllPoints()
    pg:Show()
    M.page = pg
    AT.Section(pg, "Selection")
    local sum = Line(pg, 22, 12, COL.dim)
    sum._sync = function() sum._adFS:SetText(M.Summary()) end
    M.summaryRow = sum

    -- Move or copy to: the pick, then Move or Copy
    local mv = AT.AddRow(pg, 24)
    local lbl = AT.RowLabel(mv, "Move or copy to")
    local pick, pickRev = 0, nil
    local function Pick()
        if pickRev ~= M.rev then pick, pickRev = 0, M.rev end
        return pick
    end
    local dd = AT.MakeDropdown(win, mv, nil, M.MoveItems, Pick, function(v)
        Pick()
        pick = v
    end)
    local go = AT.MakeSmallButton(mv, "Move", 60)
    go:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    local cp = AT.MakeSmallButton(mv, "Copy", 60)
    cp:SetPoint("LEFT", go, "RIGHT", 6, 0)
    -- a press with no place picked asks for one on the button itself
    local function Act(btn, word, fn)
        btn:SetScript("OnClick", function()
            AT.CloseDropdown()
            local v = Pick()
            if v == 0 then
                btn.fs:SetText("Pick one")
                C_Timer.After(1.2, function() btn.fs:SetText(word) end)
                return
            end
            fn(v)
        end)
    end
    Act(go, "Move", function(v) M.Move(v) end)
    Act(cp, "Copy", function(v) M.Copy(v) end)
    AT.Tooltip(dd, "Move or copy to", "Where the selection goes: free in a layout, or, for icons, into a group that takes them. A selected group takes its icons along. Nothing happens until you press Move or Copy.")
    AT.Tooltip(go, "Move", "Moves the selection to the picked place. Positions and settings travel with each item.")
    AT.Tooltip(cp, "Copy", "Puts a copy of the selection in the picked place and leaves the originals where they are. Each copy keeps its settings, name and position.")
    mv._colLabel, mv._colCtrl = lbl, dd
    mv._sync = dd.Refresh
    M.moveDD, M.moveBtn, M.copyBtn = dd, go, cp

    -- the actions on the control column: Edit together, Duplicate and Export
    -- on one line, Delete and Clear on the next
    local act = AT.AddRow(pg, 28)
    local alb = AT.RowLabel(act, "Actions")
    local edit = AT.MakeSmallButton(act, "Edit together", 100)
    local dup = AT.MakeSmallButton(act, "Duplicate", 74)
    local exp = AT.MakeSmallButton(act, "Export selection", 112)
    local act2 = AT.AddRow(pg, 28)
    local del = AT.MakeSmallButton(act2, "Delete selection", 112)
    local clr = AT.MakeQuietButton(act2, "Clear selection", 108)
    clr:SetPoint("LEFT", del, "RIGHT", 8, 0)
    act2._colCtrl = del
    edit:SetScript("OnClick", function()
        AT.CloseDropdown()
        M.EditTogether()
    end)
    dup:SetScript("OnClick", function()
        AT.CloseDropdown()
        M.Duplicate()
    end)
    exp:SetScript("OnClick", function()
        AT.CloseDropdown()
        M.Export()
    end)
    del:SetScript("OnClick", function()
        AT.CloseDropdown()
        M.ConfirmDelete()
    end)
    clr:SetScript("OnClick", function()
        AT.CloseDropdown()
        M.Clear()
        M.OpenLast()
    end)
    AT.Tooltip(edit, "Edit together", "One editor for every selected icon (or bar): the rows they all share, read from the first one; a change lands on all of them.")
    AT.Tooltip(dup, "Duplicate", "Makes a copy of each selected item right beside it (a group with its icons) and selects the copies.")
    AT.Tooltip(exp, "Export selection", "Opens Import / Export with exactly this selection ticked and its share string ready to copy.")
    AT.Tooltip(del, "Delete selection", "Deletes everything selected, a group with its icons. Asks first.")
    AT.Tooltip(clr, "Clear selection", "Forgets the selection and goes back to the layout.")
    act._colLabel = alb
    -- Edit together goes while the editor is open or the kinds mix; the rest
    -- packs left from the column
    act._sync = function()
        edit:SetShown(not M.editing and M.SameFamily() ~= nil)
        local prev
        for _, b in ipairs({ edit, dup, exp }) do
            if b:IsShown() then
                if prev then
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
                else
                    act._colCtrl = b
                end
                prev = b
            end
        end
    end
    M.editBtn, M.dupBtn, M.exportBtn, M.deleteBtn, M.clearBtn = edit, dup, exp, del, clr
    local note = Line(pg, 20, 11, COL.dim, function() return M.SameFamily() == nil end)
    note._adFS:SetText("Edit together needs icons only, or bars only.")
    M.noteRow = note
    win:HookScript("OnHide", function() M.Clear() end)
end

-- The pane refresh: fewer than two left (deleted since) leaves the pane;
-- else the header, the actions and, with Edit together open, the family's
-- editor page hosted under them over the proxy.
function M.Refresh()
    if not (M.pane and ui.selType == "multi") then return end
    M.Prune()
    if #M.ids < 2 then
        local rec = Store.Get(M.ids[1])
        M.Clear()
        if rec then M.Open(rec) else M.OpenLast() end
        return
    end
    if M.editing and M.SameFamily() ~= M.fam then
        M.editing, M.fam = nil, nil
        M.rev = M.rev + 1
    end
    local h = M.header
    h.name:SetText(#M.ids .. " selected")
    h.chip1:Hide()
    h.chip2:Hide()
    h.sub:SetText(M.Summary())
    Options.FitHeader(h)
    AT.LayoutPage(M.page)
    M.top:SetHeight(M.page._contentH or 140)
    for fam, page in pairs(M.kit or {}) do
        if M.editing and M.fam == fam then
            M.WrapPage(page)
            page:SetParent(M.pane)
            page:ClearAllPoints()
            page:SetPoint("TOPLEFT", M.top, "BOTTOMLEFT", 0, 0)
            page:SetPoint("BOTTOMRIGHT", M.pane, "BOTTOMRIGHT", 0, 0)
            page:Show()
            AT.LayoutPage(page)
        elseif page:GetParent() == M.pane then
            page:Hide()
        end
    end
end
