local _, ns = ...

local D = ns.Data
local Secret = ns.Secret

local Detect = {}
ns.Detect = Detect

local seen = {}         -- item ids judged this session
local pending = {}      -- item id -> callbacks waiting for the game to load it
local mobs, mobCount = {}, 0
local encounterName

local function ItemID(link)
    if type(link) ~= "string" or Secret(link) then return end
    return tonumber(link:match("item:(%d+)"))
end

local function NpcID(guid)
    if type(guid) ~= "string" or Secret(guid) then return end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

local function NoteUnit(unit)
    local guid = UnitGUID(unit)
    if not guid or Secret(guid) or not NpcID(guid) then return end
    local name, level = UnitName(unit), UnitLevel(unit)
    if not name or Secret(name) then return end
    if level and Secret(level) then level = nil end
    if not mobs[guid] then
        mobCount = mobCount + 1
        -- a long session only needs the recent mobs
        if mobCount > 300 then mobs, mobCount = {}, 1 end
    end
    mobs[guid] = { n = name, npc = NpcID(guid), lv = level }
end

local function Place()
    local zone, sub = GetRealZoneText and GetRealZoneText(), GetSubZoneText and GetSubZoneText()
    if Secret(zone) then zone = nil end
    if Secret(sub) then sub = nil end
    local x, y
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and not Secret(map) and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
        local px, py = pos:GetXY()
        if px and not Secret(px) and px > 0 then x, y = math.floor(px * 1000 + 0.5), math.floor(py * 1000 + 0.5) end
    end
    if sub == "" or sub == zone then sub = nil end
    if map and Secret(map) then map = nil end
    return zone, sub, x, y, map
end

-- noPlace: the item came from somewhere other than where the player stands (a container opened from the bags)
local function Source(t, name, npc, level, noPlace)
    if noPlace then return { t = t, n = name, npc = npc, lv = level } end
    local zone, sub, x, y, map = Place()
    return { t = t, n = name, npc = npc, lv = level, z = zone, sz = sub, x = x, y = y, m = map }
end

-- a capital city or an inn: what shows up there without a known source (bought, crafted, mailed) says nothing
-- about where it drops
local function InTown()
    return IsResting and IsResting() == true
end

-- item data: the game is the only source of truth for an item's details
function Detect.WhenLoaded(id, fn)
    if C_Item.GetItemInfo(id) then return fn(true) end
    if pending[id] then table.insert(pending[id], fn) return end
    pending[id] = { fn }
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    C_Timer.After(30, function()
        local list = pending[id]
        if not list then return end
        pending[id] = nil
        for i = 1, #list do list[i](false) end
    end)
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
    local list = pending[id]
    if not list then return end
    pending[id] = nil
    for i = 1, #list do list[i](ok ~= false) end
end)

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
    return ("%06x"):format(h)
end

-- what the item is right now, compact: item level, quality, required level, then its stats
function Detect.Fingerprint(id)
    local _, link, q, ilvl, req = C_Item.GetItemInfo(id)
    if not link then return end
    local stats = C_Item.GetItemStats and C_Item.GetItemStats(link)
    local parts = {}
    if type(stats) == "table" then
        for k, v in pairs(stats) do parts[#parts + 1] = k .. "=" .. tostring(v) end
        table.sort(parts)
    end
    return ("%d.%d.%d.%s"):format(ilvl or 0, q or 0, req or 0, Hash(table.concat(parts, ",")))
end

local function GameFields(id)
    local name, _, q, ilvl, req, _, _, _, equipLoc, _, _, cls, sub = C_Item.GetItemInfo(id)
    if not name then return end
    local inv = C_Item.GetItemInventoryTypeByID and C_Item.GetItemInventoryTypeByID(id)
    return { name = name, q = q, ilvl = ilvl, req = req, cls = cls, sub = sub, inv = inv, equipLoc = equipLoc }
end

-- kind of find this item is for this copy's data: "n", "c", "pend" (needs a second player), or nil (not a find)
function Detect.Kind(id, game)
    if not ns.isForever then
        -- a test run on another client: anything uncommon or better counts, except while the demo shows Forever's finds
        if ns.db.demoOn then return nil end
        return (game and (game.q or 0) >= 2) and "n" or nil
    end
    local what, a, b, c = D.Classify(id)
    if what == "seed" and a.kind == "o" then
        -- an old item listed for its places: a find only when the game shows other numbers than its row
        if not game then return end
        if game.q == a.q and game.ilvl == a.ilvl and game.req == a.req then return end
        return "c", a
    elseif what == "seed" then
        return (a.kind == "n" or a.kind == "x") and "n" or "c", a
    elseif what == "withheld" then
        if not game then return end
        if game.q == a and game.ilvl == b and game.req == c then return end
        return "c"
    elseif what == "boring" then
        return
    end
    return "n"
end

-- a network find: false when this copy's own data says it is an old item
function Detect.Judge(id, info)
    if not ns.isForever then return true end
    local what, row = D.Classify(id)
    if what == "boring" or (what == "seed" and row.kind == "o") then
        -- an old item said to be changed shows only once two players report it
        if info.kind == "c" then info.pend = true return true end
        return false
    end
    if what == "withheld" then
        local q, ilvl, req = D.Withheld(id)
        if info.q == q and info.ilvl == ilvl and info.req == req then return false end
    end
    return true
end

local function Me()
    return UnitName("player")
end

-- one sighting by this player; the item is judged once per session, new sources still count
function Detect.Saw(id, src)
    if not id or not ns.db then return end
    local rec = ns.Finds.Get(id)
    if seen[id] then
        if rec and src and src.t ~= "t" then
            local status = ns.Finds.Record({ id = id, src = src, mine = true })
            if status then ns.Sync.Announce(rec) end
        end
        return
    end
    seen[id] = true
    Detect.WhenLoaded(id, function(ok)
        if not ok then return end
        local game = GameFields(id)
        if not game then return end
        local kind, row = Detect.Kind(id, game)
        local fp = Detect.Fingerprint(id)
        -- an old item someone called changed: this player backs it only on seeing the same item
        if not kind and not (rec and rec.pend and fp == rec.fp) then return end
        local info = {
            id = id, kind = kind or (rec and rec.k) or "n", q = game.q, ilvl = game.ilvl, req = game.req,
            cls = game.cls, sub = game.sub, inv = game.inv, ac = row and row.ac, name = game.name, fp = fp,
            src = src, mine = true, reporter = Me(),
            by = (ns.settings.credit ~= "anon") and Me() or nil,
        }
        local status, e = ns.Finds.Record(info)
        -- tell the others when the find is new, changed, or still waits for a second player
        if e and (status == "new" or status == "changed" or (status == "updated" and not ns.Finds.Confirmed(e))) then
            ns.Sync.Announce(e)
        end
    end)
end

local function SawLink(link, src)
    local id = ItemID(link)
    if id then Detect.Saw(id, src) end
end

-- where items show up
local function LootSource(slot)
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid and not Secret(guid) then
        local m = mobs[guid]
        if m then return Source("l", m.n, m.npc, m.lv) end
        local npc = NpcID(guid)
        if npc then return Source("l", nil, npc, nil) end
        -- a chest, a node, a fishing pool: where it stands is where it drops
        if guid:find("^GameObject%-") then return Source("o") end
        -- a container opened from the bags: the container is the source, not the place it was opened in
        if guid:find("^Item%-") then
            local cid = C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(guid)
            local cname = cid and not Secret(cid) and C_Item.GetItemInfo(cid)
            if Secret(cname) then cname = nil end
            return Source("x", cname or nil, nil, nil, true)
        end
    end
    -- nothing names the source: in a town that is no place to record (an old dead target proves nothing there)
    if InTown() then return nil end
    if UnitExists("target") and UnitIsDead("target") then
        NoteUnit("target")
        local tg = UnitGUID("target")
        local m = tg and not Secret(tg) and mobs[tg]
        if m then return Source("l", m.n, m.npc, m.lv) end
    end
    return Source("l")
end

ns.On("LOOT_READY", function()
    for slot = 1, GetNumLootItems() or 0 do
        local link = GetLootSlotLink(slot)
        if link and not Secret(link) then SawLink(link, LootSource(slot)) end
    end
end)

ns.On("START_LOOT_ROLL", function(rollID)
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    if link and not Secret(link) then SawLink(link, Source("r", encounterName)) end
end)

-- the game's "<name> receives loot: <item>" lines as patterns (from its own strings, so any language works)
local othersLoot
local function OthersLoot()
    if othersLoot then return othersLoot end
    othersLoot = {}
    for _, key in ipairs({ "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_BONUS_ROLL", "LOOT_ITEM_BONUS_ROLL_MULTIPLE" }) do
        local fmt = _G[key]
        if type(fmt) == "string" and fmt ~= "" then
            local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
            p = p:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
            p = p:gsub("\1", ".+"):gsub("\2", "%%d+")
            othersLoot[#othersLoot + 1] = "^" .. p .. "$"
        end
    end
    return othersLoot
end

-- only another player's loot says where something drops: "You receive item" (vendors, quests, mail) and "You
-- create" do not, and this player's own loot comes through the loot window
ns.On("CHAT_MSG_LOOT", function(msg)
    if type(msg) ~= "string" or Secret(msg) then return end
    local others = false
    for _, p in ipairs(OthersLoot()) do
        if msg:find(p) then others = true break end
    end
    local src = (others and not InTown()) and Source("c") or nil
    for link in msg:gmatch("|Hitem:[%-%d:]+|h") do SawLink(link, src) end
end)

ns.On("MERCHANT_SHOW", function()
    local name = UnitName("npc")
    if Secret(name) then name = nil end
    local npc = NpcID(UnitGUID("npc"))
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
        local link = GetMerchantItemLink(i)
        if link and not Secret(link) then SawLink(link, Source("v", name, npc)) end
    end
end)

local function QuestRewards()
    local title = GetTitleText and GetTitleText()
    if Secret(title) then title = nil end
    for i = 1, (GetNumQuestRewards and GetNumQuestRewards()) or 0 do SawLink(GetQuestItemLink("reward", i), Source("q", title)) end
    for i = 1, (GetNumQuestChoices and GetNumQuestChoices()) or 0 do SawLink(GetQuestItemLink("choice", i), Source("q", title)) end
end
ns.On("QUEST_DETAIL", QuestRewards)
ns.On("QUEST_COMPLETE", QuestRewards)

ns.On("ENCOUNTER_START", function(_, name) if not Secret(name) then encounterName = name end end)
ns.On("ENCOUNTER_END", function(_, name) if not Secret(name) then encounterName = name end end)
ns.On("PLAYER_TARGET_CHANGED", function() NoteUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() NoteUnit("mouseover") end)

-- bags: once after login, then at most every 10 seconds after a change
local bagsQueued = false
local function ScanBags()
    bagsQueued = false
    if not C_Container then return end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not Secret(id) and not seen[id] then Detect.Saw(id, nil) end
        end
    end
end
ns.On("BAG_UPDATE_DELAYED", function()
    if bagsQueued then return end
    bagsQueued = true
    C_Timer.After(10, ScanBags)
end)
ns.Listen("Login", function()
    bagsQueued = true
    C_Timer.After(20, ScanBags)
end)

-- any item tooltip but our own (the database and pop-up show items nobody has seen yet): the item exists,
-- nothing is known about where it drops
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        if ns.Theme.IsOwnTip(tip) then return end
        local id = data and data.id
        if id and not Secret(id) and not seen[id] then Detect.Saw(id, nil) end
    end)
end

function Detect.Forget()
    wipe(seen)
end

-- /fif demo: a few Forever items as test finds where they really drop, so the window, the pop-up and the badge can
-- be shown on any client (one without these items takes their details from the shipped database); a second run
-- replays the pop-ups
-- gear only, newest first: an epic, greens from world rares, blues from dungeons, a changed green. The pop-up ends on
-- the newest whatever the Next find choice: when a find waits in the feed the newest arrives first and keeps the card,
-- otherwise the oldest arrives first and the epic, last, takes over (pushing out the blue on screen when rarer wins)
local DEMO = { { 272958, "The Barrens" }, { 284193, "Darkshore" }, { 273809, "The Stockade" },
    { 282711, "Hillsbrad Foothills" }, { 271215, "Ruins of Lordaeron" }, { 1913, "Elwynn Forest" } }
ns.Listen("Demo", function(clear)
    -- a test run's own finds (that client's items) go too, so the demo shows Forever's alone; Forever keeps its finds
    for id, e in pairs(ns.db.finds) do
        if e.demo or (not clear and not ns.isForever) then
            ns.db.finds[id] = nil
            if ns.db.popped then ns.db.popped[id] = nil end
        end
    end
    ns.Finds.Invalidate()
    ns.db.demoOn = not clear or nil
    if clear then
        ns.db.demoMined = nil
        ns.Signal("FindsChanged", nil, "cleared")
        ns.Signal("DatabaseSeen")
        return
    end
    if not ns.db.demoMined then
        ns.db.demoMined = 6
        ns.db.minedAt = ns.Now()
        ns.Signal("DatabaseSeen")
    end
    local newestFirst = ns.settings.popNext == "wait"
    for i, d in ipairs(DEMO) do
        C_Timer.After((newestFirst and (i - 1) or (#DEMO - i)) * 0.5, function()
            local id, zone = d[1], d[2]
            local row = D.Seed(id)
            if not row then return end
            local src
            for _, s in ipairs(D.Sources(id)) do
                if s.npc then
                    -- a find's level is a number, as a seen mob's is; the database's is text ("17", "8-9")
                    src = { t = s.t == "v" and "v" or "l", n = s.name, npc = s.npc, lv = tonumber(s.lv), z = zone }
                    break
                end
            end
            ns.Finds.Record({ id = id, kind = row.kind == "c" and "c" or "n", q = row.q, ilvl = row.ilvl, req = row.req,
                cls = row.cls, sub = row.sub, inv = row.inv, ac = row.ac, name = row.name, src = src, mine = true,
                reporter = Me(), by = Me(), at = ns.Now() - i * 600, demo = true })
        end)
    end
end)
