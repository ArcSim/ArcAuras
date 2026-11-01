local _, ns = ...

-- Data\Items.lua (generated) sets ns.Data; this file adds the lookups
local D = ns.Data or {}
ns.Data = D

local floor = math.floor
local concat = table.concat
local seed = D.seed or ""

-- numbers as fixed-width base-64, so the lookups are compact strings searched in place
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local REV = {}
for i = 1, #B64 do REV[B64:byte(i)] = i - 1 end
local function Enc(n, width)
    local out = {}
    for i = width, 1, -1 do
        local d = n % 64
        out[i] = B64:sub(d + 1, d + 1)
        n = floor(n / 64)
    end
    return concat(out)
end
local function Dec(s, pos, width)
    local n = 0
    for i = pos, pos + width - 1 do n = n * 64 + REV[s:byte(i)] end
    return n
end

local LINE = "^(%d+):(%a):(%d+):(%d+):(%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%d+):([^\n]*)"

-- the seed index: 19 characters per row, shipped ready in the data so nothing is parsed at load. Per row: id 4,
-- where its line starts 4, kind 1, quality 1, required level 2, class 1, subclass + 1 1, slot + 1 1, allowed
-- classes 2 (4095 = all), where the name starts in the line 2. A data file without one (a test's) gets it built.
local STRIDE = 19
local index, rows = D.seedIndex, nil
D.seedIndex = nil
local function IndexSeed()
    if rows then return end
    if not index then
        local parts = {}
        local pos, len = 1, #seed
        while pos <= len do
            local nl = seed:find("\n", pos, true) or (len + 1)
            local id, kind, q, _, req, cls, sub, inv, ac, _, name = seed:match(LINE, pos)
            if id then
                ac = tonumber(ac)
                parts[#parts + 1] = Enc(tonumber(id), 4) .. Enc(pos, 4) .. kind .. Enc(tonumber(q), 1) .. Enc(tonumber(req), 2) ..
                    Enc(tonumber(cls), 1) .. Enc(tonumber(sub) + 1, 1) .. Enc(tonumber(inv) + 1, 1) ..
                    Enc(ac == -1 and 4095 or ac % 4096, 2) .. Enc(nl - pos - #name, 2)
            end
            pos = nl + 1
        end
        index = concat(parts)
    end
    rows = floor(#index / STRIDE)
end

local function RowId(i) return Dec(index, (i - 1) * STRIDE + 1, 4) end
local function RowPos(i) return Dec(index, (i - 1) * STRIDE + 5, 4) end

local function ParseAt(pos)
    local id, kind, q, ilvl, req, cls, sub, inv, ac, flags, name = seed:match(LINE, pos)
    if not id then return end
    return tonumber(id), kind, tonumber(q), tonumber(ilvl), tonumber(req), tonumber(cls), tonumber(sub),
        tonumber(inv), tonumber(ac), tonumber(flags), name
end

local function FindSeed(id)
    IndexSeed()
    local lo, hi = 1, rows
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local v = RowId(mid)
        if v == id then return mid end
        if v < id then lo = mid + 1 else hi = mid - 1 end
    end
end

local function RowTable(pos)
    local id, kind, q, ilvl, req, cls, sub, inv, ac, flags, name = ParseAt(pos)
    if not id then return end
    return { id = id, kind = kind, q = q, ilvl = ilvl, req = req, cls = cls, sub = sub, inv = inv,
        ac = ac, beta = flags % 2 == 1, name = name }
end

-- a seed row as a table: id, kind (n new / c changed from Classic / h hotfix), quality, item level, ...
function D.Seed(id)
    local i = FindSeed(id)
    if i then return RowTable(RowPos(i)) end
end

-- every seed row, as plain values (no table per row): fn(id, kind, q, ilvl, req, cls, sub, inv, ac, flags, name)
function D.ForEachSeed(fn)
    IndexSeed()
    for i = 1, rows do fn(ParseAt(RowPos(i))) end
end

-- newest ids first, with each row's position so a list can hold numbers instead of tables
function D.ForEachSeedAt(fn)
    IndexSeed()
    for i = rows, 1, -1 do
        local p = RowPos(i)
        fn(p, ParseAt(p))
    end
end

function D.SeedAt(pos)
    return RowTable(pos)
end

function D.SeedCount()
    IndexSeed()
    return rows
end

-- rows nobody has found (hidden, or new with no known place and not seen in the beta), 6 rows per character in seed
-- order, worked out by the data build so the tag, the status and the chip share one answer
local notFoundBits = D.notFound
D.notFound = nil
local function RowBit(bits, i)
    local c = bits and bits:byte(floor((i - 1) / 6) + 1)
    return c ~= nil and floor(REV[c] / 2 ^ ((i - 1) % 6)) % 2 == 1
end
function D.RowNotFound(i)
    return RowBit(notFoundBits, i)
end
-- rows whose icon file only Forever's client holds, in the same shape: another client (a test run) draws that file as
-- a green square
local newArtBits = D.newArt
D.newArt = nil

function D.IsNotFound(id)
    local i = FindSeed(id)
    return i ~= nil and D.RowNotFound(i)
end

-- every row, newest first, read from the index alone (no line is parsed, nothing is made per row):
-- fn(pos, id, kind, quality, requiredLevel, class, subclass, slot, allowedClasses, nameStart, sourceMask, notFound)
function D.ForEachRow(fn)
    IndexSeed()
    for i = rows, 1, -1 do
        local o = (i - 1) * STRIDE
        local ac = Dec(index, o + 16, 2)
        local pos = Dec(index, o + 5, 4)
        fn(pos, Dec(index, o + 1, 4), index:sub(o + 9, o + 9), Dec(index, o + 10, 1), Dec(index, o + 11, 2),
            Dec(index, o + 13, 1), Dec(index, o + 14, 1) - 1, Dec(index, o + 15, 1) - 1, ac == 4095 and -1 or ac,
            pos + Dec(index, o + 18, 2), D.RowMask(i), D.RowNotFound(i), i)
    end
end

-- a row's name, from where ForEachRow says it starts
function D.NameAt(nameStart)
    return seed:match("^[^\n]*", nameStart)
end

-- flags carry the data version that first listed a row, so an update counts what it adds even when it drops others
D.version = D.version or 1
local addedIn
function D.AddedSince(version)
    if not addedIn then
        addedIn = D.addedCounts
    end
    if not addedIn then
        addedIn = {}
        -- old items listed for their places, and items Blizzard has not released, are not datamining news
        D.ForEachSeed(function(_, kind, _, _, _, _, _, _, _, flags)
            if kind == "o" or kind == "x" then return end
            local v = floor(flags / 2)
            addedIn[v] = (addedIn[v] or 0) + 1
        end)
    end
    local n = 0
    for v, count in pairs(addedIn) do
        if v > version then n = n + count end
    end
    return n
end

-- where items come from: one text block per kind, each line "id|..." (sources "id:..."), sorted by id and
-- searched in place through an 8-character-per-line index built on first use
local blocks = { sources = D.sources or "", npcs = D.npcs or "", objects = D.objects or "", quests = D.quests or "", dungeons = D.dungeons or "",
    tips = D.tips or "", effects = D.effects or "", hidden = D.hidden or "", dungeonItems = D.dungeonItems or "", sets = D.sets or "",
    boxes = D.boxes or "" }
D.sources, D.npcs, D.objects, D.quests, D.dungeons, D.tips, D.effects, D.hidden, D.dungeonItems, D.sets = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
D.boxes = nil
local blockIndex = {}

local function BlockLine(name, id)
    local text = blocks[name]
    local ix = blockIndex[name]
    local shipped = D.placeIndex and D.placeIndex[name]
    if not ix and shipped then
        ix = { shipped, floor(#shipped / 8) }
        blockIndex[name] = ix
    end
    if not ix then
        local parts = {}
        local pos, len = 1, #text
        while pos <= len do
            local nl = text:find("\n", pos, true) or (len + 1)
            local key = nl > pos and tonumber(text:match("^(%d+)", pos))
            if key then parts[#parts + 1] = Enc(key, 4) .. Enc(pos, 4) end
            pos = nl + 1
        end
        ix = { concat(parts), #parts }
        blockIndex[name] = ix
    end
    local lo, hi = 1, ix[2]
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local v = Dec(ix[1], (mid - 1) * 8 + 1, 4)
        if v == id then
            local pos = Dec(ix[1], (mid - 1) * 8 + 5, 4)
            local nl = text:find("\n", pos, true)
            return text:sub(pos, (nl or (#text + 1)) - 1)
        end
        if v < id then lo = mid + 1 else hi = mid - 1 end
    end
end

-- "m.x.y;m.x.y" (map, per-mille) and "@area" (inside that dungeon)
-- a place's zones split by ";": "@area" inside a dungeon, else "map:" and every spot as x and y in per-mille, two
-- base-64 characters each
local function Spots(text)
    local pins, inside = {}, nil
    for part in (text or ""):gmatch("[^;]+") do
        local area = part:match("^@(%d+)$")
        if area then
            inside = inside or tonumber(area)
        else
            local m, xy = part:match("^(%d+):([%w+/]*)$")
            m = tonumber(m)
            if m then
                for i = 1, #xy - 3, 4 do
                    pins[#pins + 1] = { m = m, x = Dec(xy, i, 2), y = Dec(xy, i + 2, 2) }
                end
            end
        end
    end
    return pins, inside
end

function D.Dungeon(area)
    local line = area and BlockLine("dungeons", area)
    if not line then return end
    local name, at, flag = line:match("^%d+|([^|]*)|([^|]*)|?(%a*)")
    if not name then return end
    -- an announced dungeon has no entrance until the data has one
    local m, x, y = at:match("^(%d+)%.(%d+)%.(%d+)$")
    return { name = name, m = tonumber(m), x = tonumber(x), y = tonumber(y), raid = flag:find("r", 1, true) ~= nil,
        own = flag:find("f", 1, true) ~= nil }
end

-- names compared without a leading "The", case or punctuation, so an announced name still matches the game's
local function NameKey(s)
    return (s:lower():gsub("^the ", ""):gsub("[^%w]", ""))
end

-- a dungeon by the zone name the game shows inside it
local dungeonByName
function D.DungeonNamed(zone)
    if not zone then return end
    if not dungeonByName then
        dungeonByName = {}
        for area in blocks.dungeons:gmatch("(%d+)|[^\n]*") do
            local d = D.Dungeon(tonumber(area))
            if d and not dungeonByName[NameKey(d.name)] then dungeonByName[NameKey(d.name)] = d end
        end
    end
    return dungeonByName[NameKey(zone)]
end

-- the dungeons and raids that drop listed items, plus Forever's own before their loot is known, by name (Dire Maul's
-- wings share one name, so one entry), each with the ids it drops; built the first time the dungeon filter is used
local instances
local function IndexInstances()
    if instances then return end
    instances = { names = { raid = {}, dungeon = {} }, items = {} }
    local function SetOf(d)
        local set = instances.items[d.name]
        if not set then
            set = {}
            instances.items[d.name] = set
            local list = instances.names[d.raid and "raid" or "dungeon"]
            list[#list + 1] = d.name
        end
        return set
    end
    for area, ids in blocks.dungeonItems:gmatch("(%d+)|([^\n]*)") do
        local d = D.Dungeon(tonumber(area))
        if d then
            local set = SetOf(d)
            for id in ids:gmatch("%d+") do set[tonumber(id)] = true end
        end
    end
    for area in blocks.dungeons:gmatch("(%d+)|[^\n]*") do
        local d = D.Dungeon(tonumber(area))
        if d and d.own then SetOf(d) end
    end
    table.sort(instances.names.raid)
    table.sort(instances.names.dungeon)
end

-- the raids (raid true) or the dungeons that drop listed items, plus Forever's own, sorted by name
function D.DungeonNames(raid)
    IndexInstances()
    return instances.names[raid and "raid" or "dungeon"]
end

-- whether a dungeon or raid, by name, drops the item
function D.InDungeon(name, id)
    IndexInstances()
    local set = instances.items[name]
    return set ~= nil and set[id] == true
end

-- the short names players use, for a row's tag; a place without one shows its name
local SHORT = { ["Ragefire Chasm"] = "RFC", ["Wailing Caverns"] = "WC", ["The Deadmines"] = "DM", ["Shadowfang Keep"] = "SFK",
    ["Blackfathom Deeps"] = "BFD", ["The Stockade"] = "STOCKS", ["Gnomeregan"] = "GNOMER", ["Razorfen Kraul"] = "RFK",
    ["Scarlet Monastery"] = "SM", ["Razorfen Downs"] = "RFD", ["Uldaman"] = "ULDA", ["Zul'Farrak"] = "ZF", ["Maraudon"] = "MARA",
    ["The Temple of Atal'Hakkar"] = "ST", ["Blackrock Depths"] = "BRD", ["Blackrock Spire"] = "BRS", ["Dire Maul"] = "DIRE MAUL",
    ["Scholomance"] = "SCHOLO", ["Stratholme"] = "STRAT", ["Onyxia's Lair"] = "ONY", ["Molten Core"] = "MC",
    ["Blackwing Lair"] = "BWL", ["Zul'Gurub"] = "ZG", ["Ruins of Ahn'Qiraj"] = "AQ20", ["Temple of Ahn'Qiraj"] = "AQ40",
    ["Naxxramas"] = "NAXX" }
function D.DungeonShort(name)
    return SHORT[name] or (name and name:upper())
end

-- a find's source mask: what the data knows of the item, plus how players got it (inside a dungeon the zone the game
-- shows is the dungeon's name)
local findMasks = {}
function D.FindMask(e)
    local m = findMasks[e.id]
    if not m then
        m = D.MaskOf(e.id)
        findMasks[e.id] = m
    end
    for _, s in ipairs(e.s or {}) do
        if s.t == "l" or s.t == "r" or s.t == "c" then
            local dg = D.DungeonNamed(s.z)
            m = D.AddBit(m, dg and (dg.raid and 1 or 2) or 32)
        elseif s.t == "v" then m = D.AddBit(m, 16)
        elseif s.t == "q" then m = D.AddBit(m, 4)
        elseif s.t == "o" or s.t == "x" then m = D.AddBit(m, 64) end
    end
    return m
end

-- what a find teaches the database: an item it has no row for, a hidden one, a new one with no known drop place, an
-- old Classic item Forever changed (a find only when its numbers differ), or a changed one whose drop place was not
-- known. A test run outside Forever counts every find.
local Discovery
-- kept per item: the answer holds while the data is loaded, and the feed asks it for every find on each redraw
local discovery = {}
function D.IsDiscovery(id)
    local v = discovery[id]
    if v == nil then
        v = Discovery(id)
        discovery[id] = v
    end
    return v
end
function Discovery(id)
    if not ns.isForever then return true end
    local what, row = D.Classify(id)
    if what == "unknown" or what == "withheld" then return true end
    if what ~= "seed" then return false end
    if row.kind == "o" then return true end
    if row.kind == "n" or row.kind == "x" then return D.IsNotFound(id) end
    return not D.HasSources(id)
end

-- whether a find passes a find filter (the Live Feed's, which pop-ups follow, or the pop-ups' own copy): discoveries
-- only (D.IsDiscovery), kinds ticked, a quality floor, a level choice against the player's level, the slots ticked
-- (none = any), usable gear only. anyKind: leave the kinds out (for the counts on the New / Changed chips). A demo find
-- stands in for a discovery, so the demo shows on Forever too, where its items' drop places are known
local QUALITY_FLOOR = { any = 0, uncommon = 2, rare = 3, epic = 4 }
function D.FindPasses(f, e, level, classFile, anyKind)
    if f.discoveries and not e.demo and not D.IsDiscovery(e.id) then return false end
    if not anyKind and not f.kinds[e.k == "c" and "c" or "n"] then return false end
    if (e.q or 0) < (QUALITY_FLOOR[f.quality] or 0) then return false end
    local rq = e.rq or 0
    if f.level == "mine" and rq > level then return false end
    if f.level == "near" and math.abs(rq - level) > 10 then return false end
    if f.level == "custom" and ((f.levelMin and rq < f.levelMin) or (f.levelMax and rq > f.levelMax)) then return false end
    if next(f.slots) ~= nil and not f.slots[D.SlotGroup(e.iv)] then return false end
    if f.usable and not D.CanUse(classFile, level, e.cl, e.sc, e.ac) then return false end
    return true
end

-- whether a row passes the Item Database's filter state (st: minL, maxL, fq, slot, cls, src, dg); the caller handles
-- search and the kind chips. mask: the row's source mask; e: the find, when the row is one
function D.FilterPasses(st, id, q, req, cls, sub, inv, ac, mask, e)
    if st.minL and (req or 0) < st.minL then return false end
    if st.maxL and (req or 0) > st.maxL then return false end
    -- qualities, slots and classes are sets of picks (empty = any); src is the picked source bits added up
    if next(st.qs) and not st.qs[q] then return false end
    if next(st.slots) and not st.slots[D.SlotGroup(inv) or 0] then return false end
    if next(st.clss) then
        local usable = false
        for file in pairs(st.clss) do
            if D.CanUse(file, 60, cls, sub, ac) then usable = true break end
        end
        if not usable then return false end
    end
    if st.src > 0 and not D.HasAnyBit(mask, st.src) then return false end
    if st.dg ~= "" and not D.InDungeon(st.dg, id) then
        local inside = false
        for _, s in ipairs(e and e.s or {}) do
            local dg = D.DungeonNamed(s.z)
            if dg and dg.name == st.dg then inside = true end
        end
        if not inside then return false end
    end
    return true
end

-- an NPC or object: its name, level text, rank (1 elite, 2 rare elite, 3 boss, 4 rare), spots, and the dungeon it
-- stands in (if any); an object's level field holds the gathering skill a vein or herb needs (gather: its name)
local function Place(kind, id)
    local line = BlockLine(kind, id)
    if not line then return end
    local name, level, rank, spots = line:match("^%d+|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if not name then return end
    local pins, inside = Spots(spots)
    local gather = kind == "objects" and level ~= "" and D.PROFESSIONS[tonumber(level)] or nil
    return { id = id, name = name, lv = level ~= "" and not gather and level or nil, rank = tonumber(rank), pins = pins,
        dungeon = D.Dungeon(inside), gather = gather }
end
D.Place = Place

-- where an item comes from, as bits (the same in build_places.js); this order picks the one tag a row shows
D.SOURCE_KINDS = {
    { bit = 1, key = "raid", text = "Raid" },
    { bit = 2, key = "dungeon", text = "Dungeon" },
    -- a vein, herb or beast to skin leads an item that also drops or sells: gathering is how players get it
    { bit = 256, key = "gathered", text = "Gathered" },
    { bit = 4, key = "quest", text = "Quest" },
    { bit = 8, key = "world", text = "World Drop" },
    { bit = 16, key = "vendor", text = "Vendor" },
    { bit = 32, key = "mob", text = "Mob Drop" },
    { bit = 64, key = "container", text = "Container" },
    { bit = 128, key = "crafted", text = "Crafted" },
}

-- skill lines a k ref names (build_places.js PROFESSIONS)
local PROFESSIONS = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [185] = "Cooking", [129] = "First Aid", [186] = "Mining", [356] = "Fishing",
    [182] = "Herbalism", [393] = "Skinning", [40] = "Poisons" }
D.PROFESSIONS = PROFESSIONS

function D.HasBit(mask, bit)
    return floor((mask or 0) / bit) % 2 == 1
end

-- whether mask holds any of the bits added up in bits
function D.HasAnyBit(mask, bits)
    local bit = 1
    while bit <= bits do
        if D.HasBit(bits, bit) and D.HasBit(mask, bit) then return true end
        bit = bit * 2
    end
    return false
end

local function AddBit(mask, bit)
    if D.HasBit(mask, bit) then return mask end
    return mask + bit
end
D.AddBit = AddBit

-- the first kind in D.SOURCE_KINDS order that the mask holds
function D.SourceKind(mask)
    if not mask or mask == 0 then return end
    for _, k in ipairs(D.SOURCE_KINDS) do
        if D.HasBit(mask, k.bit) then return k end
    end
end

-- every known source of an item, surest first: { t = l mob drop / v vendor / o object / q quest / c container /
-- w world drop / s skinning / k crafted, name, lv, rank, npc (l, v), chance (l, o, c: Classic's, in percent),
-- gather (o: Mining or Herbalism for a vein or herb), pins = { {m, x, y}, ... }, dungeon = { name, m, x, y, raid },
-- count (w, s), giver = { name, lv, rank, npc } (q), skill (k, 0 when unknown) }; a world drop's or skinning's pins
-- each carry their own mob (npc, name, lv, rank)
function D.HasSources(id)
    return BlockLine("sources", id) ~= nil
end

function D.Sources(id)
    local line = BlockLine("sources", id)
    if not line then return {} end
    local out = {}
    for ref in (line:match("^%d+:(.*)$") or ""):gmatch("[^,]+") do
        local t, rest = ref:sub(1, 1), ref:sub(2)
        local src
        if t == "l" or t == "v" then
            -- a chance ending in b is Forever beta's, any other Classic's
            local npc, chance, mark = rest:match("^(%d+)~?(%d*)(b?)$")
            src = npc and Place("npcs", tonumber(npc))
            if src then
                src.npc = src.id
                if chance and chance ~= "" then
                    src.chance, src.beta = tonumber(chance) / 100, mark == "b"
                end
            end
        elseif t == "k" then
            local skill, rank = rest:match("^(%d+)%.(%d+)$")
            local prof = PROFESSIONS[tonumber(skill)]
            if prof then src = { name = prof, skill = tonumber(rank), pins = {} } end
        elseif t == "o" then
            local obj, chance = rest:match("^(%d+)~?(%d*)$")
            src = obj and Place("objects", tonumber(obj))
            if src and chance ~= "" then src.chance = tonumber(chance) / 100 end
        elseif t == "q" then
            local qline = BlockLine("quests", tonumber(rest))
            -- "qline and qline:match(...)" would keep only the first capture
            local name, level, gk, gid
            if qline then name, level, gk, gid = qline:match("^%d+|([^|]*)|([^|]*)|(%a?)(%d*)$") end
            if name then
                local giver = gid ~= "" and Place(gk == "o" and "objects" or "npcs", tonumber(gid))
                if giver and gk ~= "o" then giver.npc = giver.id end
                src = { name = name, lv = level ~= "" and level or nil, pins = giver and giver.pins or {},
                    dungeon = giver and giver.dungeon, giver = giver or nil }
            end
        elseif t == "c" then
            local box, chance = rest:match("^(%d+)~?(%d*)$")
            box = tonumber(box)
            local row = box and D.Seed(box)
            local named = box and BlockLine("boxes", box)
            src = box and { name = (row and row.name) or (named and named:match("^%d+|(.*)$")) or ("Item " .. box), pins = {}, item = box,
                chance = chance ~= "" and tonumber(chance) / 100 or nil }
        elseif t == "w" or t == "s" then
            local count = tonumber(rest:match("^(%d+)"))
            local pins = {}
            for npc, m in rest:gmatch("/(%d+)%.(%d+)") do
                local p = Place("npcs", tonumber(npc))
                for _, pin in ipairs(p and p.pins or {}) do
                    if pin.m == tonumber(m) then
                        pin.npc, pin.name, pin.lv, pin.rank = p.id, p.name, p.lv, p.rank
                        pins[#pins + 1] = pin
                        break
                    end
                end
            end
            src = { name = (count or 0) .. (t == "s" and " kinds of beasts" or " kinds of mobs"), pins = pins, count = count }
        end
        if src then
            src.t = t
            out[#out + 1] = src
        end
    end
    return out
end

-- an item's source mask read from its sources: a mob or object inside a dungeon makes it a dungeon (or raid) item,
-- one outdoors a mob drop (or container). D.sourceMask ships the same per seed row.
function D.SourceMask(id)
    local line = BlockLine("sources", id)
    if not line then return 0 end
    local m = 0
    for ref in (line:match("^%d+:(.*)$") or ""):gmatch("[^,]+") do
        local t = ref:sub(1, 1)
        if t == "q" then m = AddBit(m, 4)
        elseif t == "v" then m = AddBit(m, 16)
        elseif t == "w" then m = AddBit(m, 8)
        elseif t == "c" then m = AddBit(m, 64)
        elseif t == "k" then m = AddBit(m, 128)
        elseif t == "s" then m = AddBit(m, 256)
        elseif t == "l" or t == "o" then
            local p = Place(t == "l" and "npcs" or "objects", tonumber(ref:match("^%a(%d+)")))
            if p and p.dungeon then m = AddBit(m, p.dungeon.raid and 1 or 2) end
            if p and #p.pins > 0 then m = AddBit(m, t == "l" and 32 or (p.gather and 256) or 64) end
        end
    end
    return m
end

-- 2 characters per seed row, in the seed index's order; a data file without it (a test's) gets it built
local maskIndex = D.sourceMask
D.sourceMask = nil
function D.RowMask(i)
    if not maskIndex then
        IndexSeed()
        local parts = {}
        for r = 1, rows do parts[r] = Enc(D.SourceMask(RowId(r)), 2) end
        maskIndex = concat(parts)
    end
    return Dec(maskIndex, (i - 1) * 2 + 1, 2)
end

-- an item's mask by id: its seed row's, else read from its sources
function D.MaskOf(id)
    local i = FindSeed(id)
    if i then return D.RowMask(i) end
    return D.SourceMask(id)
end

-- a new item's tooltip, worked out from Forever's tables for when the game cannot draw it:
-- { bind, unique = "u" / "e" (equipped), armor, dmg = { min, max, delay, school }, stats = { { type, value }, ... },
--   more = { [tag] = text } } with the tags of item_tooltip.js details() (k skill, f reputation, s set, T a recipe's
-- "Use:" line, C the item it makes, R its reagents, d flavor, ...); a tag with no text holds true
function D.Tip(id)
    local line = BlockLine("tips", id)
    if not line then return end
    local bind, unique, armor, dmg, stats, more = line:match("^%d+|(%d*)|(%a*)|(%d*)|([%d%-]*)|([^|]*)|?(.*)$")
    if not bind then return end
    local tip = { bind = tonumber(bind), unique = unique ~= "" and unique or nil, armor = tonumber(armor), stats = {}, more = {} }
    local lo, hi, delay, school = dmg:match("^(%d+)%-(%d+)%-(%d+)%-?(%d*)$")
    if lo then tip.dmg = { tonumber(lo), tonumber(hi), tonumber(delay), tonumber(school) } end
    for t, v in stats:gmatch("(%d+)%.(%-?%d+)") do tip.stats[#tip.stats + 1] = { tonumber(t), tonumber(v) } end
    for entry in more:gmatch("[^\t]+") do
        local tag, text = entry:sub(1, 1), entry:sub(2)
        tip.more[tag] = text ~= "" and text or true
    end
    return tip
end

-- an item set as the tooltip lists it: { name, pieces, items = { name, ... }, bonuses = { { threshold, text }, ... } }
function D.Set(setID)
    local line = setID and BlockLine("sets", setID)
    if not line then return end
    local name, pieces, items, bonuses = line:match("^%d+|([^|]*)|(%d+)|([^|]*)|(.*)$")
    if not name then return end
    local set = { name = name, pieces = tonumber(pieces), items = {}, bonuses = {} }
    for item in items:gmatch("[^\t]+") do set.items[#set.items + 1] = item end
    for thr, text in bonuses:gmatch("(%d+)~([^\t]+)") do set.bonuses[#set.bonuses + 1] = { tonumber(thr), text } end
    return set
end

-- a new or hidden item's Use / Equip / Chance on hit lines (item_effects.js): { { trig = 0 use / 1 equip / 2 chance
-- on hit, text }, ... }; a line whose numbers could not be filled holds only the spell's name
function D.Effects(id)
    local line = BlockLine("effects", id)
    if not line then return end
    local out = {}
    for trig, text in (line:match("^%d+|(.*)$") or ""):gmatch("(%d)([^\t]+)") do
        out[#out + 1] = { trig = tonumber(trig), text = text }
    end
    return #out > 0 and out or nil
end

-- what is known of an item Blizzard has not released (seed kind x): its set's name and the name of an item wearing
-- the same model, either may be missing
function D.Hidden(id)
    local line = BlockLine("hidden", id)
    if not line then return end
    local set, look = line:match("^%d+|([^|]*)|(.*)$")
    if not set then return end
    return { set = set ~= "" and set or nil, look = look ~= "" and look or nil }
end

-- the quality a hidden row carries: none is known
D.UNKNOWN_QUALITY = 9

-- a hidden row's name: the worked-out one, else what it is ("Unknown One-Hand Sword")
function D.HiddenName(row)
    if row.name ~= "" then return row.name end
    local kind = D.ItemKind(row.cls, row.sub, row.inv)
    return "Unknown " .. (kind ~= "" and kind or "item")
end

-- 4 characters per seed row, in the seed index's order: a new or changed item's icon file, for when the game cannot
-- show the item yet (0 for old items, whose icons every client has)
local iconIndex = D.iconIndex
D.iconIndex = nil
function D.IconOf(id)
    local i = iconIndex and FindSeed(id)
    return i and D.IconAt(i)
end

-- the same by seed row index (what ForEachRow passes last), without the search
function D.IconAt(i)
    if not iconIndex or (not ns.isForever and RowBit(newArtBits, i)) then return end
    local icon = Dec(iconIndex, (i - 1) * 4 + 1, 4)
    return icon > 0 and icon or nil
end

-- the "boring" set: 6 ids per character of a base-64 string
local boring = D.boring or ""

function D.IsBoring(id)
    local c = boring:byte(floor(id / 6) + 1)
    if not c then return false end
    local v = REV[c] or 0
    return floor(v / 2 ^ (id % 6)) % 2 == 1
end

-- old Classic items the client withholds: 9 characters each (id, quality, item level, required level)
local withheld, withheldRows
function D.Withheld(id)
    if not withheld then
        local parts = {}
        for line in (D.classicWithheld or ""):gmatch("[^\n]+") do
            local wid, q, ilvl, req = line:match("^(%d+):(%d+):(%d+):(%d+)")
            if wid then parts[#parts + 1] = Enc(tonumber(wid), 4) .. Enc(tonumber(q), 1) .. Enc(tonumber(ilvl), 2) .. Enc(tonumber(req), 2) end
        end
        withheld, withheldRows = concat(parts), #parts
        -- the text it came from is no longer needed
        D.classicWithheld = nil
    end
    local lo, hi = 1, withheldRows
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local at = (mid - 1) * 9 + 1
        local v = Dec(withheld, at, 4)
        if v == id then return Dec(withheld, at + 4, 1), Dec(withheld, at + 5, 2), Dec(withheld, at + 7, 2) end
        if v < id then lo = mid + 1 else hi = mid - 1 end
    end
end

-- what the shipped data says about an item the player just saw
function D.Classify(id)
    local row = D.Seed(id)
    if row then return "seed", row end
    local q, ilvl, req = D.Withheld(id)
    if q then return "withheld", q, ilvl, req end
    if D.IsBoring(id) then return "boring" end
    return "unknown"
end

-- item classes the way the auction house lists them
local function ClassName(classID, fallback)
    local f = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
    local name = f and f(classID)
    return (type(name) == "string" and name ~= "") and name or fallback
end
local function SubName(classID, subID, fallback)
    local f = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local name = f and f(classID, subID)
    return (type(name) == "string" and name ~= "") and name or fallback
end

-- the tree files every crafting material (the game's trade goods, class 7) under Reagent beside the spell reagents,
-- as subcategory 100 + its subclass; a subcategory with a game class and subclass takes the client's name for them
local TRADE_GOODS, REAGENT, TRADE_SUB = 7, 5, 100
function D.CatOf(cls, sub)
    if cls == TRADE_GOODS then return REAGENT, TRADE_SUB + (sub or 0) end
    return cls, sub
end

D.CATEGORIES = {
    { cls = 2, name = "Weapon", subs = { { 0, "One-Handed Axes" }, { 1, "Two-Handed Axes" }, { 2, "Bows" }, { 3, "Guns" },
        { 4, "One-Handed Maces" }, { 5, "Two-Handed Maces" }, { 6, "Polearms" }, { 7, "One-Handed Swords" },
        { 8, "Two-Handed Swords" }, { 10, "Staves" }, { 13, "Fist Weapons" }, { 14, "Miscellaneous" }, { 15, "Daggers" },
        { 16, "Thrown" }, { 18, "Crossbows" }, { 19, "Wands" }, { 20, "Fishing Poles" } } },
    { cls = 4, name = "Armor", subs = { { 0, "Miscellaneous" }, { 1, "Cloth" }, { 2, "Leather" }, { 3, "Mail" }, { 4, "Plate" },
        { 6, "Shields" }, { 7, "Librams" }, { 8, "Idols" }, { 9, "Totems" } } },
    { cls = 1, name = "Container", subs = {} },
    { cls = 0, name = "Consumable", subs = {} },
    { cls = 5, name = "Reagent", subs = { { 107, "Metal & Stone", 7, 7 }, { 109, "Herb", 7, 9 }, { 106, "Leather", 7, 6 },
        { 105, "Cloth", 7, 5 }, { 108, "Cooking", 7, 8 }, { 110, "Elemental", 7, 10 }, { 112, "Enchanting", 7, 12 },
        { 101, "Parts", 7, 1 }, { 102, "Explosives", 7, 2 }, { 111, "Other", 7, 11 }, { 0, "Spell Reagents", false } } },
    { cls = 6, name = "Projectile", subs = {} },
    { cls = 11, name = "Quiver", subs = {} },
    { cls = 9, name = "Recipe", subs = { { 0, "Book" }, { 1, "Leatherworking" }, { 2, "Tailoring" }, { 3, "Engineering" },
        { 4, "Blacksmithing" }, { 5, "Cooking" }, { 6, "Alchemy" }, { 7, "First Aid" }, { 8, "Enchanting" }, { 9, "Fishing" } } },
    { cls = 15, name = "Miscellaneous", subs = {} },
}

function D.LocalizeCategories()
    for _, c in ipairs(D.CATEGORIES) do
        c.name = ClassName(c.cls, c.name)
        for _, s in ipairs(c.subs) do
            if s[3] ~= false then s[2] = SubName(s[3] or c.cls, s[4] or s[1], s[2]) end
        end
    end
end

function D.SubclassName(cls, sub)
    cls, sub = D.CatOf(cls, sub)
    for _, c in ipairs(D.CATEGORIES) do
        if c.cls == cls then
            for _, s in ipairs(c.subs) do
                if s[1] == sub then return s[2] end
            end
            return c.name
        end
    end
    return ""
end

-- inventory types the slot filter offers, in paper-doll order
D.SLOTS = { 1, 2, 3, 16, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 17, 21, 22, 14, 23, 15, 25, 26, 28 }
local SLOT_KEYS = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
    [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
    [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD",
    [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [19] = "INVTYPE_TABARD",
    [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE",
    [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}
local SLOT_FALLBACK = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "One-Hand", [14] = "Off Hand", [15] = "Ranged",
    [16] = "Back", [17] = "Two-Hand", [19] = "Tabard", [20] = "Chest", [21] = "Main Hand", [22] = "Off Hand",
    [23] = "Held In Off-hand", [25] = "Thrown", [26] = "Ranged", [28] = "Relic",
}
function D.SlotName(inv)
    local key = SLOT_KEYS[inv]
    local text = key and _G[key]
    if type(text) == "string" and text ~= "" then return text end
    return SLOT_FALLBACK[inv] or ""
end

-- weapons read as the tooltip does ("Main Hand Axe"), not as the auction house's plural group names
local WEAPON_ONE = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm",
    [7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow",
    [19] = "Wand", [20] = "Fishing Pole" }
local RANGED_SLOT = { [15] = true, [25] = true, [26] = true }

-- "Leather Chest"; armor with no armor type (rings, trinkets, necks) is just its slot
function D.ItemKind(cls, sub, inv)
    if cls == 2 and WEAPON_ONE[sub] then
        local slot = D.SlotName(inv)
        if RANGED_SLOT[inv] or slot == "" then return WEAPON_ONE[sub] end
        return slot .. " " .. WEAPON_ONE[sub]
    end
    local slot = D.SlotName(inv)
    local kind = D.SubclassName(cls, sub)
    if (cls == 4 and sub == 0 and slot ~= "") or kind == slot then kind = "" end
    if kind ~= "" and slot ~= "" then return kind .. " " .. slot end
    return kind ~= "" and kind or slot
end

-- "Leather Chest, item level 219, level 60", leaving out what is unknown (item level 0: a hidden item's)
function D.ItemLine(cls, sub, inv, ilvl, req)
    local parts = {}
    local kind = D.ItemKind(cls, sub, inv)
    if kind ~= "" then parts[#parts + 1] = kind end
    if ilvl ~= 0 or #parts == 0 then parts[#parts + 1] = (#parts == 0 and "Item level " or "item level ") .. ((ilvl ~= 0 and ilvl) or "?") end
    if (req or 0) > 0 then parts[#parts + 1] = "level " .. req end
    return table.concat(parts, ", ")
end
-- a robe is a chest piece for the slot filter
function D.SlotGroup(inv)
    if inv == 20 then return 5 end
    return inv
end

-- who can use what (Classic rules; Forever may differ, a filter not a promise)
D.CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
D.CLASS_ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local ARMOR = {
    WARRIOR = { 0, 1, 2, 3, 4, 6 }, PALADIN = { 0, 1, 2, 3, 4, 6, 7 }, HUNTER = { 0, 1, 2, 3 }, ROGUE = { 0, 1, 2 },
    PRIEST = { 0, 1 }, SHAMAN = { 0, 1, 2, 3, 6, 9 }, MAGE = { 0, 1 }, WARLOCK = { 0, 1 }, DRUID = { 0, 1, 2, 8 },
}
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local function Has(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

-- mail and plate open at level 40 for the classes that train them
function D.CanUse(classFile, level, cls, sub, ac)
    local bit = D.CLASS_BITS[classFile]
    if bit and ac and ac > 0 and ac ~= 32767 and floor(ac / bit) % 2 == 0 then return false end
    if cls == 4 then
        if sub == 3 and (classFile == "HUNTER" or classFile == "SHAMAN") and level < 40 then return false end
        if sub == 4 and level < 40 then return false end
        return Has(ARMOR[classFile] or {}, sub)
    elseif cls == 2 then
        if sub == 14 or sub == 20 then return true end
        return Has(WEAPONS[classFile] or {}, sub)
    end
    return true
end

function D.ClassAllows(classFile, ac)
    local bit = D.CLASS_BITS[classFile]
    if not bit or not ac or ac <= 0 or ac == 32767 then return true end
    return floor(ac / bit) % 2 == 1
end

-- the single class an item is limited to, for the type line ("Shaman"), or nil
function D.OnlyClass(ac)
    if not ac or ac <= 0 or ac == 32767 then return end
    for file, bit in pairs(D.CLASS_BITS) do
        if ac == bit then
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or (file:sub(1, 1) .. file:sub(2):lower())
            return name
        end
    end
end
