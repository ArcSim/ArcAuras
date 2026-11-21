-- QOL\AD_GearList.lua: the gear list: every piece within reach that beats your gear, where it comes from, and the
-- dungeon run you are in (which bosses are down, which wanted piece dropped).
-- Reads the item finder's data through ArcAurasFinds (Forever) and values pieces with NS.GearValue; NS.GearListUI and
-- NS.GearTracker draw it. Owns the stat cache (ui.gearListStats) and the per-character state (ui.gearList[GUID]).
-- An item's stats are read while the game holds the item and kept: the game forgets items soon after many are read.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("GearList") or C_Timer

local GL = {}
NS.GearList = GL

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

-- the stat cache's shape: a new number reads every item again
GL.SHAPE = 1
-- items asked of the server at once, the time a frame may spend, how long an item may take to arrive
GL.LOADS, GL.FRAME_MS, GL.WAIT_FOR, GL.SOURCES_PER_FRAME = 30, 4, 10, 150

-- what each class wears: armor subclass = the level it starts at
GL.ARMOR = {
    WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 40 },
    ROGUE = { [0] = 1, [1] = 1, [2] = 1 },
    PRIEST = { [0] = 1, [1] = 1 },
    SHAMAN = { [0] = 1, [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    MAGE = { [0] = 1, [1] = 1 },
    WARLOCK = { [0] = 1, [1] = 1 },
    DRUID = { [0] = 1, [1] = 1, [2] = 1, [8] = 1 },
}
-- and the weapon subclasses each class can train
GL.WEAPON = {
    WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PALADIN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
    HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [18] = 1 },
    ROGUE = { [2] = 1, [3] = 1, [4] = 1, [7] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PRIEST = { [4] = 1, [10] = 1, [15] = 1, [19] = 1 },
    SHAMAN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
    MAGE = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
    WARLOCK = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
    DRUID = { [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
}
-- the finder's inventory type numbers, as the module's equip locations
GL.INV = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST",
    [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
    [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD",
    [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [20] = "INVTYPE_ROBE",
    [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN",
    [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC" }
GL.SLOT_WORD = { INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "One-Hand",
    INVTYPE_SHIELD = "Off Hand", INVTYPE_RANGED = "Ranged", INVTYPE_CLOAK = "Back", INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand", INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_HOLDABLE = "Off Hand",
    INVTYPE_THROWN = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_RELIC = "Relic" }

-- Only on Forever, with the module on and the item finder's data loaded (the Item Finds module).
function GL.Available()
    local G = NS.GearValue
    return NS.IsForever == true and G ~= nil and G.Enabled() and type(ArcAurasFinds) == "table"
        and ArcAurasFinds.ForEachSeed ~= nil
end

-- This character's state: ticks, tries per piece, folds, the picked scale.
function GL.Mine()
    local ui = NS.Store and NS.Store.UI and NS.Store.UI()
    local me = UnitGUID and UnitGUID("player")
    if type(ui) ~= "table" or Secret(me) or type(me) ~= "string" then return nil end
    if type(ui.gearList) ~= "table" then ui.gearList = {} end
    local t = ui.gearList[me]
    if type(t) ~= "table" then
        t = {}
        ui.gearList[me] = t
    end
    t.got, t.tries, t.open = t.got or {}, t.tries or {}, t.open or {}
    return t
end

-- The stat cache, account-wide: { [itemID] = { s = stats, a = read anything, f = effect lines, l = link } or false }.
function GL.Cache()
    local ui = NS.Store and NS.Store.UI and NS.Store.UI()
    if type(ui) ~= "table" then return nil end
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    local c = ui.gearListStats
    if type(c) ~= "table" or c.v ~= GL.SHAPE or c.build ~= build then
        c = { v = GL.SHAPE, build = build, items = {} }
        ui.gearListStats = c
    end
    return c.items
end

-- Whether a class can wear or wield the item at its level (the finder's class, subclass, inventory type).
function GL.Usable(class, level, cls, sub, inv)
    local loc = GL.INV[inv]
    local G = NS.GearValue
    if not (loc and G and G.SLOTS[loc]) then return false end
    if cls == 4 then
        local at = (GL.ARMOR[class] or {})[sub]
        return at ~= nil and level >= at
    end
    if cls == 2 then return (GL.WEAPON[class] or {})[sub] ~= nil end
    return false
end

-- An item's places, raids left out: { k = drop / chest / mob / quest / craft / vendor / box / world, place = the
-- dungeon, who, p = chance in percent }.
function GL.Places(id)
    local out = {}
    for _, s in ipairs(ArcAurasFinds.Sources(id) or {}) do
        local d = s.dungeon
        if not (d and d.raid) then
            local t = s.t
            if t == "l" then
                out[#out + 1] = { k = d and "drop" or "mob", place = d and d.name, who = s.name, p = s.chance }
            elseif t == "o" then
                out[#out + 1] = { k = d and "drop" or "chest", place = d and d.name, who = s.name, p = s.chance }
            elseif t == "d" and d then
                out[#out + 1] = { k = "drop", place = d.name, who = Tr("Dungeon loot") }
            elseif t == "q" then
                out[#out + 1] = { k = "quest", who = s.name, lv = s.lv }
            elseif t == "k" then
                out[#out + 1] = { k = "craft", who = s.name, skill = s.skill }
            elseif t == "v" then
                out[#out + 1] = { k = "vendor", who = s.name }
            elseif t == "c" then
                out[#out + 1] = { k = "box", who = s.name }
            elseif t == "w" or t == "s" then
                out[#out + 1] = { k = "world" }
            end
        end
    end
    return out
end

-- Building the list: every usable item row at once (a plain walk), then each one's places a share a frame.
function GL.Build()
    if GL.cands or GL.building or not GL.Available() then return end
    local _, class = UnitClass("player")
    local level = UnitLevel and UnitLevel("player") or 60
    if Secret(class) or Secret(level) then return end
    GL.building = true
    local rows = {}
    ArcAurasFinds.ForEachSeed(function(id, _, q, _, req, cls, sub, inv, _, _, name)
        if id and (q or 0) >= 2 and (req or 0) <= level and GL.Usable(class, level, cls, sub, inv) then
            rows[#rows + 1] = { id = id, q = q, req = req or 0, inv = inv, name = name }
        end
    end)
    local out, i = {}, 1
    local function Step()
        local t0 = debugprofilestop and debugprofilestop()
        local n = 0
        while i <= #rows and n < GL.SOURCES_PER_FRAME do
            local r = rows[i]
            r.places = GL.Places(r.id)
            if #r.places > 0 then out[#out + 1] = r end
            i, n = i + 1, n + 1
            if t0 and debugprofilestop() - t0 > GL.FRAME_MS then break end
        end
        if i <= #rows then
            C_Timer.After(0, Step)
            return
        end
        GL.cands, GL.building = out, nil
        GL.byId = {}
        for _, c in ipairs(out) do GL.byId[c.id] = c end
        GL.Read()
        GL.Changed()
    end
    Step()
end

-- Reading stats: an item the game holds is read at once; the others are asked for, a few at a time, and read the
-- moment they arrive. Never in combat.
function GL.ReadItem(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = get(id)
    if type(link) ~= "string" or Secret(link) then return false end
    local G = NS.GearValue
    local tip = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
    local lines = (type(tip) == "table" and not Secret(tip)) and tip.lines or nil
    local st, any = G.ItemStats(link, lines)
    local fx = G.EffectLines(lines)
    local cache = GL.Cache()
    if cache then cache[id] = { s = st, a = any or nil, f = (#fx > 0) and fx or nil, l = link } end
    return true
end

function GL.Read()
    local cache = GL.Cache()
    if not (GL.cands and cache) then return end
    GL.queue, GL.inflight, GL.head = {}, {}, 1
    for _, c in ipairs(GL.cands) do
        if cache[c.id] == nil then GL.queue[#GL.queue + 1] = c.id end
    end
    GL.Pump()
end

function GL.Left()
    if not GL.queue then return 0 end
    local n = #GL.queue - GL.head + 1
    for _ in pairs(GL.inflight or {}) do n = n + 1 end
    return n
end

function GL.Pump()
    if not GL.queue or GL.pumping then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local t0 = debugprofilestop and debugprofilestop()
    local busy = 0
    for _ in pairs(GL.inflight) do busy = busy + 1 end
    local load = C_Item and C_Item.RequestLoadItemDataByID
    while GL.head <= #GL.queue and busy < GL.LOADS do
        -- entries stay in place: a hole at the front would make # read short
        local id = GL.queue[GL.head]
        GL.head = GL.head + 1
        if not GL.ReadItem(id) then
            GL.inflight[id] = GetTime and GetTime() or 0
            busy = busy + 1
            if load then load(id) end
        end
        if t0 and debugprofilestop() - t0 > GL.FRAME_MS then break end
    end
    -- an item that never arrives is let go; it is asked for again next session
    local now = GetTime and GetTime() or 0
    for id, at in pairs(GL.inflight) do
        if now - at > GL.WAIT_FOR then GL.inflight[id] = nil end
    end
    if GL.Left() > 0 then
        GL.pumping = true
        C_Timer.After(0.1, function()
            GL.pumping = nil
            GL.Pump()
        end)
    end
    GL.Changed()
end

function GL.OnItemInfo(id, ok)
    if not (GL.inflight and GL.inflight[id]) then return end
    GL.inflight[id] = nil
    if ok == false then
        local cache = GL.Cache()
        if cache then cache[id] = false end
    else
        GL.ReadItem(id)
    end
    GL.Changed()
end

-- A piece's gain on a scale, from its kept stats; nil while unread. Gains are kept until the gear or a scale changes.
local function ScaleSig(scale)
    local p = {}
    for k, v in pairs(scale.w or {}) do p[#p + 1] = k .. "=" .. v end
    for kind, g in pairs(scale.goals or {}) do
        for k, v in pairs(type(g) == "table" and g or {}) do p[#p + 1] = kind .. "." .. k .. "=" .. tostring(v) end
    end
    table.sort(p)
    return table.concat(p, ",")
end

function GL.Gain(id, scale)
    local cache = GL.Cache()
    local c = cache and cache[id]
    if not c then return nil end
    GL.gains = GL.gains or {}
    local key = tostring(scale.id) .. "|" .. ScaleSig(scale)
    local per = GL.gains[key]
    if not per then
        per = {}
        GL.gains[key] = per
    end
    local g = per[id]
    if g == nil then
        local lines = {}
        for _, t in ipairs(c.f or {}) do lines[#lines + 1] = { leftText = t } end
        local G = NS.GearValue
        local out = G.Gains(c.l or ("item:" .. id), lines, { scale }, c.s or {}, c.a == true)
        local x = out and out[1]
        g = (x and type(x.delta) == "number") and { d = x.delta, was = x.was, empty = x.empty } or false
        per[id] = g
    end
    return g or nil
end

-- Whether he has it: ticked by hand, else in his bags, bank or worn.
function GL.Has(id)
    local m = GL.Mine()
    local t = m and m.got[id]
    if t ~= nil then return t end
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true)) or (GetItemCount and GetItemCount(id, true)) or 0
    if not Secret(count) and type(count) == "number" and count > 0 then return true end
    local worn = C_Item and C_Item.IsEquippedItem and C_Item.IsEquippedItem(id)
    return worn == true
end

function GL.SetHas(id, on)
    local m = GL.Mine()
    if m then m.got[id] = on end
    GL.Changed()
end

-- The scales the list can show (his shown scales), the picked one (kept per character), and picking another.
function GL.Scales()
    local G = NS.GearValue
    return G and G.ShownScales(G.Group()) or {}
end

function GL.Scale()
    local list, m = GL.Scales(), GL.Mine()
    for _, s in ipairs(list) do
        if m and s.id == m.scale then return s end
    end
    return list[1]
end

function GL.SetScale(id)
    local m = GL.Mine()
    if m then m.scale = id end
    GL.Changed()
end

-- The dungeon he is in: the finder's name for it and the instance's map ID (its bosses' order), or nil.
function GL.UpdateHere()
    local name, kind, _, _, _, _, _, map = GetInstanceInfo()
    local before = GL.here
    if (kind == "party" or kind == "raid") and type(name) == "string" and not Secret(name) then
        local d = ArcAurasFinds.DungeonNamed and ArcAurasFinds.DungeonNamed(name)
        GL.here = { name = d and d.name or name, map = map, raid = kind == "raid" }
    else
        GL.here = nil
    end
    -- a run starts on entering, from outside or from another dungeon
    if GL.here and not (before and before.map == GL.here.map) then
        GL.run = { map = GL.here.map, killed = {} }
    elseif not GL.here then
        GL.run = nil
    end
    GL.Changed()
end

-- Boss names: the encounter's name (Kirtonos) and the creature's (Kirtonos the Herald) are one boss.
function GL.Key(name)
    local s = tostring(name or ""):lower():gsub("^the ", ""):gsub("[^%a]", "")
    return s
end

function GL.SameBoss(a, b)
    local x, y = GL.Key(a), GL.Key(b)
    if x == "" or y == "" then return false end
    return x == y or x:find(y, 1, true) == 1 or y:find(x, 1, true) == 1
end

-- Its run order (the client's encounter order for the instance he is in), or nil.
function GL.OrderOf(who)
    local list = GL.here and NS.GearListOrder and NS.GearListOrder[GL.here.map]
    if not list then return nil end
    for i, name in ipairs(list) do
        if GL.SameBoss(name, who) then return i end
    end
    return nil
end

function GL.Killed(who)
    for name in pairs(GL.run and GL.run.killed or {}) do
        if GL.SameBoss(name, who) then return true end
    end
    return false
end

function GL.OnKill(name)
    if not (GL.run and type(name) == "string") or Secret(name) then return end
    GL.run.killed[name] = true
    -- one more try at each piece this boss drops that he still wants
    local m, scale = GL.Mine(), GL.Scale()
    for _, e in ipairs(GL.Wanted(scale)) do
        for _, p in ipairs(e.places) do
            if p.k == "drop" and GL.SameBoss(p.who, name) and m then
                m.tries[e.id] = (m.tries[e.id] or 0) + 1
                break
            end
        end
    end
    GL.Changed()
end

-- Every piece that beats his gear on the scale: { id, name, q, slot, gain, places } ; only read pieces count.
function GL.Ups(scale)
    local out = {}
    if not (GL.cands and scale) then return out end
    for _, c in ipairs(GL.cands) do
        local g = GL.Gain(c.id, scale)
        if g and g.d > 0.05 then
            local loc = GL.INV[c.inv]
            out[#out + 1] = { id = c.id, name = c.name, q = c.q, req = c.req, slot = Tr(GL.SLOT_WORD[loc] or ""),
                loc = loc, gain = g, places = c.places }
        end
    end
    return out
end

-- Where a piece is listed: the dungeon he is in, else the drop with the best chance, else a quest, crafting, a vendor
-- or box, the world.
function GL.Primary(e)
    local here = GL.here and GL.here.name
    local best, bestP
    for _, p in ipairs(e.places) do
        if p.k == "drop" then
            if here and p.place == here then return "d:" .. here end
            if not best or (p.p or 0) > bestP then best, bestP = p, p.p or 0 end
        end
    end
    if best then return "d:" .. best.place end
    for _, kind in ipairs({ "quest", "craft", "vendor", "box" }) do
        for _, p in ipairs(e.places) do
            if p.k == kind then return kind == "box" and "vendor" or kind end
        end
    end
    return "world"
end

-- written out so the key scan sees each word
function GL.GroupWord(k)
    if k == "quest" then return Tr("Quests") elseif k == "craft" then return Tr("Crafted") elseif k == "vendor" then return Tr("Vendors") end
    return Tr("World drops")
end

-- A dungeon's pieces boss by boss: run order where it is known, else the boss with most for him first; bosses with
-- the same pieces (one loot table) make one block. Each piece once, under its first block.
function GL.Blocks(place, list)
    local byBoss, names = {}, {}
    for _, e in ipairs(list) do
        for _, p in ipairs(e.places) do
            if p.k == "drop" and p.place == place then
                if not byBoss[p.who] then
                    byBoss[p.who] = {}
                    names[#names + 1] = p.who
                end
                table.insert(byBoss[p.who], { e = e, p = p })
            end
        end
    end
    local function sum(who)
        local s = 0
        for _, x in ipairs(byBoss[who]) do s = s + x.e.gain.d end
        return s
    end
    local here = GL.here and GL.here.name == place
    table.sort(names, function(a, b)
        local x, y = here and GL.OrderOf(a) or 1000, here and GL.OrderOf(b) or 1000
        if x ~= y then return x < y end
        local sa, sb = sum(a), sum(b)
        if sa ~= sb then return sa > sb end
        return a < b
    end)
    local blocks = {}
    for _, who in ipairs(names) do
        local ids = {}
        for _, x in ipairs(byBoss[who]) do ids[#ids + 1] = x.e.id end
        table.sort(ids)
        local key = table.concat(ids, ",")
        local last = blocks[#blocks]
        if last and last.key == key then
            last.bosses[#last.bosses + 1] = who
            for _, x in ipairs(byBoss[who]) do table.insert(last.chances[x.e.id], x.p.p) end
        else
            local b = { key = key, bosses = { who }, entries = {}, chances = {} }
            for _, x in ipairs(byBoss[who]) do
                b.entries[#b.entries + 1] = x.e
                b.chances[x.e.id] = { x.p.p }
            end
            blocks[#blocks + 1] = b
        end
    end
    local shown = {}
    for _, b in ipairs(blocks) do
        local keep = {}
        for _, e in ipairs(b.entries) do
            if not shown[e.id] then
                shown[e.id] = true
                keep[#keep + 1] = e
            end
        end
        table.sort(keep, function(x, y) return x.gain.d > y.gain.d end)
        b.entries = keep
        local all = true
        for _, who in ipairs(b.bosses) do if not GL.Killed(who) then all = false end end
        b.killed = here and all
    end
    local out = {}
    for _, b in ipairs(blocks) do if #b.entries > 0 then out[#out + 1] = b end end
    return out
end

-- A block's chance for a piece: "2%", or the range over the bosses sharing it ("1.1-3.7%"), or "".
function GL.ChanceText(block, id)
    local lo, hi
    for _, p in ipairs(block.chances[id] or {}) do
        if type(p) == "number" and p > 0 then
            lo, hi = math.min(lo or p, p), math.max(hi or p, p)
        end
    end
    if not lo then return "" end
    local function f(v)
        if v >= 10 then return string.format("%d", math.floor(v + 0.5)) end
        local s = string.format("%.1f", v):gsub("%.0$", "")
        return s
    end
    if lo == hi then return f(lo) .. "%" end
    return f(lo) .. "-" .. f(hi) .. "%"
end

-- The list: groups by place, the dungeon he is in first, then dungeons by how much they hold for him, then quests,
-- crafted, vendors, world drops.
function GL.Groups(scale)
    local buckets, order = {}, {}
    for _, e in ipairs(GL.Ups(scale)) do
        local k = GL.Primary(e)
        if not buckets[k] then
            buckets[k] = {}
            order[#order + 1] = k
        end
        table.insert(buckets[k], e)
    end
    local function sum(k)
        local s = 0
        for _, e in ipairs(buckets[k]) do s = s + e.gain.d end
        return s
    end
    local hereKey = GL.here and ("d:" .. GL.here.name)
    local dungeons = {}
    for _, k in ipairs(order) do if k:find("^d:") then dungeons[#dungeons + 1] = k end end
    table.sort(dungeons, function(a, b)
        if a == hereKey then return true end
        if b == hereKey then return false end
        return sum(a) > sum(b)
    end)
    for _, k in ipairs({ "quest", "craft", "vendor", "world" }) do
        if buckets[k] then dungeons[#dungeons + 1] = k end
    end
    local out = {}
    for _, k in ipairs(dungeons) do
        local list = buckets[k]
        table.sort(list, function(x, y) return x.gain.d > y.gain.d end)
        local best = 0
        for _, e in ipairs(list) do best = math.max(best, e.gain.d) end
        local place = k:match("^d:(.*)$")
        out[#out + 1] = { key = k, name = place or GL.GroupWord(k), place = place, here = k == hereKey, list = list,
            best = best, blocks = place and GL.Blocks(place, list) or nil }
    end
    return out
end

-- What he still wants in the dungeon he is in: the pieces listed under it that he has not got.
function GL.Wanted(scale)
    local out = {}
    if not (GL.here and scale) then return out end
    for _, g in ipairs(GL.Groups(scale)) do
        if g.here then
            for _, e in ipairs(g.list) do if not GL.Has(e.id) then out[#out + 1] = e end end
        end
    end
    return out
end

-- My List: one row per slot (rings and trinkets one row each), what he wears there, and the best piece he can get
-- outside raids on the scale. A slot with nothing better is at its best.
GL.MY_SLOTS = {
    { key = "head", inv = { 1 }, locs = { INVTYPE_HEAD = true } },
    { key = "neck", inv = { 2 }, locs = { INVTYPE_NECK = true } },
    { key = "shoulder", inv = { 3 }, locs = { INVTYPE_SHOULDER = true } },
    { key = "back", inv = { 15 }, locs = { INVTYPE_CLOAK = true } },
    { key = "chest", inv = { 5 }, locs = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { key = "wrist", inv = { 9 }, locs = { INVTYPE_WRIST = true } },
    { key = "hands", inv = { 10 }, locs = { INVTYPE_HAND = true } },
    { key = "waist", inv = { 6 }, locs = { INVTYPE_WAIST = true } },
    { key = "legs", inv = { 7 }, locs = { INVTYPE_LEGS = true } },
    { key = "feet", inv = { 8 }, locs = { INVTYPE_FEET = true } },
    { key = "finger", inv = { 11, 12 }, locs = { INVTYPE_FINGER = true } },
    { key = "trinket", inv = { 13, 14 }, locs = { INVTYPE_TRINKET = true } },
    { key = "main", inv = { 16 }, locs = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true } },
    { key = "off", inv = { 17 }, locs = { INVTYPE_SHIELD = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true } },
    { key = "ranged", inv = { 18 }, locs = { INVTYPE_RANGED = true, INVTYPE_THROWN = true, INVTYPE_RANGEDRIGHT = true,
        INVTYPE_RELIC = true } },
}
GL.RELIC_CLASSES = { SHAMAN = true, PALADIN = true, DRUID = true }

-- written out so the key scan sees each word
function GL.MySlotWord(key)
    if key == "head" then return Tr("Head") elseif key == "neck" then return Tr("Neck")
    elseif key == "shoulder" then return Tr("Shoulder") elseif key == "back" then return Tr("Back")
    elseif key == "chest" then return Tr("Chest") elseif key == "wrist" then return Tr("Wrist")
    elseif key == "hands" then return Tr("Hands") elseif key == "waist" then return Tr("Waist")
    elseif key == "legs" then return Tr("Legs") elseif key == "feet" then return Tr("Feet")
    elseif key == "finger" then return Tr("Finger") elseif key == "trinket" then return Tr("Trinket")
    elseif key == "main" then return Tr("Main Hand") elseif key == "off" then return Tr("Off Hand") end
    local _, class = UnitClass("player")
    return GL.RELIC_CLASSES[class] and Tr("Relic") or Tr("Ranged")
end

-- Where a piece comes from, in one line: the drop with the best chance, else a quest, crafting, a vendor, the world.
function GL.FromText(e)
    local best
    for _, p in ipairs(e.places or {}) do
        if p.k == "drop" and (not best or (p.p or 0) > (best.p or 0)) then best = p end
    end
    if best then
        local c = (type(best.p) == "number" and best.p > 0)
            and (best.p >= 10 and math.floor(best.p + 0.5) or (math.floor(best.p * 10 + 0.5) / 10)) or nil
        return (best.place or "") .. " - " .. (best.who or "") .. (c and (" - " .. c .. "%") or "")
    end
    for _, p in ipairs(e.places or {}) do if p.k == "quest" then return Tr("Quest") .. " - " .. (p.who or "") end end
    for _, p in ipairs(e.places or {}) do if p.k == "craft" then return Tr("Crafted") end end
    for _, p in ipairs(e.places or {}) do if p.k == "vendor" or p.k == "box" then return Tr("Vendor") end end
    return Tr("World drop")
end

local function WornName(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if type(link) ~= "string" or Secret(link) then return nil end
    return link:match("%[(.-)%]")
end

function GL.MyList(scale)
    local rows, best = {}, {}
    for _, e in ipairs(GL.Ups(scale)) do
        for i, s in ipairs(GL.MY_SLOTS) do
            if s.locs[e.loc] and (not best[i] or e.gain.d > best[i].gain.d) then best[i] = e end
        end
    end
    local up, got, done = 0, 0, 0
    for i, s in ipairs(GL.MY_SLOTS) do
        local worn = {}
        for _, slot in ipairs(s.inv) do worn[#worn + 1] = WornName(slot) end
        local e = best[i]
        rows[#rows + 1] = { key = s.key, word = GL.MySlotWord(s.key), worn = table.concat(worn, " / "), best = e,
            from = e and GL.FromText(e) or nil }
        if e then
            up = up + 1
            if GL.Has(e.id) then got = got + 1 end
        else
            done = done + 1
        end
    end
    return rows, { up = up, got = got, done = done, slots = #GL.MY_SLOTS }
end

-- A wanted piece in a loot roll or the loot window: kept until the roll or the window closes.
function GL.IdOf(link)
    if type(link) ~= "string" or Secret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function GL.IsWanted(id)
    for _, e in ipairs(GL.Wanted(GL.Scale())) do if e.id == id then return e end end
    return nil
end

function GL.OnRoll(rollID)
    local get = GetLootRollItemLink
    local e = GL.IsWanted(GL.IdOf(get and get(rollID)))
    if not e then return end
    GL.drop = { id = e.id, e = e, roll = rollID }
    GL.Changed()
end

function GL.OnLootOpened()
    local n = GetNumLootItems and GetNumLootItems() or 0
    for i = 1, (Secret(n) and 0 or n) do
        local e = GL.IsWanted(GL.IdOf(GetLootSlotLink and GetLootSlotLink(i)))
        if e then
            GL.drop = { id = e.id, e = e }
            GL.Changed()
            return
        end
    end
end

function GL.ClearDrop(rollID)
    if not GL.drop or (rollID and GL.drop.roll and GL.drop.roll ~= rollID) then return end
    GL.lastDrop = { id = GL.drop.id, e = GL.drop.e, at = GetTime and GetTime() or 0 }
    GL.drop = nil
    GL.Changed()
end

-- The piece reaches the bags soon after its roll or the loot window closes: it is won, and off the list.
GL.WON_WITHIN, GL.WON_SHOWN = 120, 6
function GL.OnBags()
    local last = GL.lastDrop
    local now = GetTime and GetTime() or 0
    if last and now - last.at <= GL.WON_WITHIN and GL.Has(last.id) then
        GL.lastDrop = nil
        GL.won = { id = last.id, e = last.e, at = now }
        C_Timer.After(GL.WON_SHOWN, function()
            if GL.won and GL.won.at == now then GL.won = nil GL.Changed() end
        end)
    end
    GL.Changed()
end

-- Every change reaches the window and the tracker once a frame.
function GL.Changed()
    if GL.dirty then return end
    GL.dirty = true
    C_Timer.After(0, function()
        GL.dirty = nil
        if NS.GearListUI and NS.GearListUI.Refresh then NS.GearListUI.Refresh() end
        if NS.GearTracker and NS.GearTracker.Refresh then NS.GearTracker.Refresh() end
    end)
end

-- Events: only while the list can work; item info and loot only while there is something to read or want.
local Events = NS.Events
function GL.Listen()
    if not Events then return end
    local on = GL.Available()
    local function Sub(event, fn) if on then Events.On(event, "GearList", fn) else Events.Off(event, "GearList") end end
    Sub("GET_ITEM_INFO_RECEIVED", function(_, id, ok) GL.OnItemInfo(id, ok) end)
    Sub("PLAYER_REGEN_ENABLED", function() GL.Pump() end)
    Sub("ZONE_CHANGED_NEW_AREA", function() GL.UpdateHere() end)
    Sub("PLAYER_EQUIPMENT_CHANGED", function() GL.gains = nil GL.Changed() end)
    Sub("BAG_UPDATE_DELAYED", function() GL.OnBags() end)
    Sub("BOSS_KILL", function(_, _, name) GL.OnKill(name) end)
    Sub("ENCOUNTER_END", function(_, _, name, _, _, success) if success == 1 then GL.OnKill(name) end end)
    Sub("START_LOOT_ROLL", function(_, rollID) GL.OnRoll(rollID) end)
    Sub("CANCEL_LOOT_ROLL", function(_, rollID) GL.ClearDrop(rollID) end)
    Sub("LOOT_OPENED", function() GL.OnLootOpened() end)
    Sub("LOOT_CLOSED", function() if GL.drop and not GL.drop.roll then GL.ClearDrop() end end)
    if on then
        GL.UpdateHere()
        GL.Build()
    end
end

if Events then
    Events.On("PLAYER_ENTERING_WORLD", "GearListBoot", function()
        -- the item finder loads on demand at login: a frame later its data is in
        C_Timer.After(1, GL.Listen)
    end)
end
