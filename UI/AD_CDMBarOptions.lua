-- AD_CDMBarOptions: a Cooldown Manager bar's rows (Bars\AD_CDMBar.lua): the Add window's pick, the Tracking pick and the card line (retail only).
-- AD_Options calls in behind nil checks (Options.CDMBarAddRows / CDMBarCanCreate / CDMBarDriver / CDMBarWhat / CDMBarTrackRows); the list is NS.CDMMirror's read.
local ADDON, NS = ...
local Options = NS.Options
if not Options or NS.IsForever == true then return end
local Tr = NS.AT.Tr

local CO = {}
Options.CDMBar = CO

-- the list is read again at most this often while a page lays out
CO.READ_GAP = 1

function CO.On()
    return NS.CDMBars ~= nil and NS.CDMMirror ~= nil
end

-- One entry as the Cooldown Manager shows it: its name and its picture's spell.
function CO.Entry(id, info)
    local M = NS.CDMMirror
    local name = type(info) == "table" and M.NameOf(M.NameSpell(info)) or nil
    return { id = id, name = name or Tr("Cooldown Manager entry %s"):format(id),
        art = type(info) == "table" and M.ArtSpell(info) or nil }
end

-- The entries in the player's Tracked Bars, in their order. Read out of
-- combat; combat and a failed read answer the last list.
function CO.Entries()
    local M = NS.CDMMirror
    if not M then return {} end
    local now = GetTime()
    if CO.list and ((InCombatLockdown and InCombatLockdown()) or now - (CO.readAt or 0) < CO.READ_GAP) then
        return CO.list
    end
    local snap = M.Read()
    if not snap.complete then return CO.list or {} end
    local merged = M.Merge(snap)
    local out = {}
    for _, id in ipairs(M.Shown(snap, merged, M.Cat("TrackedBar"))) do
        out[#out + 1] = CO.Entry(id, snap.infos[id])
    end
    CO.list, CO.readAt = out, now
    return out
end

-- Any entry by its ID, in the Tracked Bars or not.
function CO.Find(id)
    id = tonumber(id)
    if not id then return nil end
    for _, e in ipairs(CO.list or {}) do
        if e.id == id then return e end
    end
    local CV, M = C_CooldownViewer, NS.CDMMirror
    local raw = CV and CV.GetCooldownViewerCooldownInfo and CV.GetCooldownViewerCooldownInfo(id)
    local info = raw and M and M.CopyInfo(raw)
    return CO.Entry(id, info)
end

-- Whether the Tracked Bars draw this entry now: only then is there a bar to copy.
function CO.InTracked(id)
    if not id then return false end
    local v = _G[NS.CDMBars and NS.CDMBars.VIEWER or ""]
    if type(v) ~= "table" or type(v.GetChildren) ~= "function" then return false end
    local kids = { v:GetChildren() }
    for i = 1, #kids do
        local k = kids[i]
        if type(k) == "table" and k.Bar and k.cooldownID == id then return true end
    end
    return false
end

-- The pick list: the Tracked Bars, and the bar's own entry when it left them.
function CO.Items(cur)
    local items, seen = {}, {}
    for _, e in ipairs(CO.Entries()) do
        items[#items + 1] = { value = e.id, text = e.name, raw = true }
        seen[e.id] = true
    end
    cur = tonumber(cur)
    if cur and not seen[cur] then
        local e = CO.Find(cur)
        items[#items + 1] = { value = cur, text = e.name, raw = true }
    end
    return items
end

CO.PICK_TIP = "The Tracked Bars entry this bar copies. Keep the Cooldown Manager's own bar on, and hide it with opacity 0 in Edit Mode."

function Options.CDMBarAddRows(pg, owner, addState)
    if not CO.On() then return end
    local AT = NS.AT
    local function Vis() return addState.cat == "Bar" and addState.barKind == "cdmbar" end
    AT.RowDesc(pg, "Copies one of the Cooldown Manager's Tracked Bars, its timer and all.", 20, Vis)
    local row = AT.RowDropdown(pg, owner, "Tracked bar",
        function() return addState.cdmID end,
        function(v)
            addState.cdmID = v
            AT.LayoutPage(pg)
        end,
        function() return CO.Items(nil) end,
        function() return Vis() and #CO.Entries() > 0 end)
    AT.Tooltip(row, "Tracked bar", CO.PICK_TIP)
    AT.RowDesc(pg, "Your Tracked Bars are empty: add the entry to them in the Cooldown Manager first.", 20,
        function() return Vis() and #CO.Entries() == 0 end)
end

function Options.CDMBarCanCreate(addState)
    return CO.On() and tonumber(addState.cdmID) ~= nil
end

-- The new bar's driver and name; its side icon wears the entry's picture.
function Options.CDMBarDriver(addState)
    local id = tonumber(addState.cdmID)
    if not id then return nil end
    local e = CO.Find(id)
    return { cooldownID = id, spellID = e.art }, e.name
end

-- A card line: the entry's name.
function Options.CDMBarWhat(rec)
    local id = NS.CDMBars and NS.CDMBars.CooldownID(rec)
    if not id then return Tr("no entry picked") end
    return CO.Find(id).name
end

function Options.CDMBarTrackRows(pg, ctx, trackVis, owner)
    if not CO.On() then return end
    local AT, Store = NS.AT, NS.Store
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "cdmbar") and r or nil
    end
    local function Vis() return trackVis() and Rec() ~= nil end
    AT.Section(pg, "Cooldown Manager bar", { visibleFn = Vis })
    local row = AT.RowDropdown(pg, owner, "Tracked bar",
        function()
            local r = Rec()
            return r and NS.CDMBars.CooldownID(r)
        end,
        function(v)
            local r = Rec()
            local id = tonumber(v)
            if not (r and id) then return end
            local e = CO.Find(id)
            r.driver.cooldownID = id
            r.driver.spellID = e.art
            r.name = e.name
            Store.Dirty("tree")
            Options.RefreshAll()
        end,
        function()
            local r = Rec()
            return CO.Items(r and NS.CDMBars.CooldownID(r))
        end,
        Vis)
    AT.Tooltip(row, "Tracked bar", CO.PICK_TIP)
    AT.RowDesc(pg, "Not in your Tracked Bars now: move it there in the Cooldown Manager.", 20, function()
        local r = Rec()
        return Vis() and not CO.InTracked(NS.CDMBars.CooldownID(r))
    end)
    AT.Section(pg, nil)
end
