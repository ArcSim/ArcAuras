-- AD_GearValueAH: Find upgrades on the auction house: one button searches every slot and lists only the listings
-- that beat what is worn, for the Gear Value scales picked; a row opens the game's own buy view.
-- Reads NS.GearValue for scales and values. Auction results and item data are plain; nothing here is protected.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("AD_GearValueAH") or C_Timer
local hooksecurefunc = NS.Perf and NS.Perf.Hooks("AD_GearValueAH") or hooksecurefunc
local CreateFrame = NS.Perf and NS.Perf.Frames("GearValueAH") or function(...) return CreateFrame(...) end

local AH = { seen = {}, byKey = {}, tasks = {}, loads = {}, rows = {}, pending = {}, head = 1, slotsDone = 0, token = 0,
    drawGen = 0 }
NS.GearValueAH = AH

-- browse pages read at most (all of them, short of a runaway); a step with no answer is dropped after this long
AH.MAX_PAGES, AH.WAIT_FOR = 400, 6
-- listings read in full a frame at most, the time budget a frame (ms), how often the list redraws while searching
-- (s), and listings looked at a frame at most (most are other slots, dropped at once)
AH.PER_FRAME, AH.FRAME_MS, AH.DRAW_EVERY, AH.SCAN_PER_FRAME = 25, 3, 0.25, 400
AH.ROW_H, AH.HEAD_H, AH.STATUS_H, AH.ICON = 32, 24, 22, 22
-- the bottom bar's controls: the game's own Cancel Auction button sits 3 in from the right, 7 up from the bottom
AH.BAR_H, AH.BTN_W, AH.SCALES_W, AH.SLOT_W, AH.GAP, AH.BAR_X, AH.BAR_Y = 22, 140, 170, 110, 8, -12, -33
-- the page's body (the list) inside the frame, left / top / right / bottom, and the gap before our tab
AH.VIEW_L, AH.VIEW_T, AH.VIEW_R, AH.VIEW_B, AH.TAB_GAP = 8, -62, -8, 29, 3
AH.UNIT_W = 140
AH.LVL_W, AH.AVAIL_W, AH.PRICE_W, AH.GAP_W, AH.GAIN_W = 40, 84, 120, 20, 210
-- the header's columns, left to right as built: what each sorts by
AH.HEAD_KEYS = { "name", "lvl", "price", "gain", "avail" }
-- the auction house list's own colours, so the finder's list reads as part of it
AH.GOLD = { 1, 0.82, 0 }
AH.LIST_BG, AH.LIST_EDGE, AH.HEAD_BG = { 0.063, 0.051, 0.039 }, { 0.227, 0.180, 0.122 }, { 0.122, 0.098, 0.071 }
AH.ROW_A, AH.ROW_B, AH.ROW_HOVER = { 0.094, 0.075, 0.055 }, { 0.110, 0.086, 0.063 }, { 0.227, 0.184, 0.110 }
AH.INK, AH.MUTED = { 0.910, 0.878, 0.800 }, { 0.541, 0.478, 0.369 }
AH.UP, AH.DOWN, AH.SAME, AH.DONE = { 0.25, 1, 0.25 }, { 1, 0.31, 0.31 }, { 0.63, 0.63, 0.63 }, { 0.349, 0.851, 0.451 }

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

-- The slots in search order; a relic only where the game has relics.
AH.SLOTS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger",
    "trinket", "onehand", "twohand", "offhand", "relic" }

function AH.Slots()
    local G = NS.GearValue
    local out = {}
    for _, s in ipairs(AH.SLOTS) do
        if s ~= "relic" or (G and G.Game() == "forever") then out[#out + 1] = s end
    end
    return out
end

function AH.SlotWord(key)
    local w = { all = Tr("All slots"), head = Tr("Head"), neck = Tr("Neck"), shoulder = Tr("Shoulder"), back = Tr("Back"),
        chest = Tr("Chest"), wrist = Tr("Wrist"), hands = Tr("Hands"), waist = Tr("Waist"), legs = Tr("Legs"),
        feet = Tr("Feet"), finger = Tr("Finger"), trinket = Tr("Trinket"), onehand = Tr("One-Hand"),
        twohand = Tr("Two-Hand"), offhand = Tr("Off Hand"), relic = Tr("Relic") }
    return w[key] or key
end

-- What the auction house is asked for a slot: the categories the game's own list uses for it.
function AH.ClassFilters(key)
    local IC, IT, AS, WS = Enum and Enum.ItemClass, Enum and Enum.InventoryType, Enum and Enum.ItemArmorSubclass,
        Enum and Enum.ItemWeaponSubclass
    if not (IC and IT and AS and WS) then return nil end
    local A, W = IC.Armor, IC.Weapon
    local function f(classID, subClassID, inv) return { classID = classID, subClassID = subClassID, inventoryType = inv } end
    local all = {
        head = { f(A, nil, IT.IndexHeadType) }, shoulder = { f(A, nil, IT.IndexShoulderType) },
        chest = { f(A, nil, IT.IndexChestType), f(A, nil, IT.IndexRobeType) }, waist = { f(A, nil, IT.IndexWaistType) },
        legs = { f(A, nil, IT.IndexLegsType) }, feet = { f(A, nil, IT.IndexFeetType) },
        wrist = { f(A, nil, IT.IndexWristType) }, hands = { f(A, nil, IT.IndexHandType) },
        neck = { f(A, AS.Generic, IT.IndexNeckType) }, back = { f(A, AS.Cloth, IT.IndexCloakType) },
        finger = { f(A, AS.Generic, IT.IndexFingerType) }, trinket = { f(A, AS.Generic, IT.IndexTrinketType) },
        offhand = { f(A, AS.Generic, IT.IndexHoldableType), f(A, AS.Shield) },
        relic = { f(A, AS.Idol), f(A, AS.Libram), f(A, AS.Totem) },
        onehand = { f(W, WS.Axe1H), f(W, WS.Mace1H), f(W, WS.Sword1H), f(W, WS.Dagger), f(W, WS.Unarmed) },
        twohand = { f(W, WS.Axe2H), f(W, WS.Mace2H), f(W, WS.Sword2H), f(W, WS.Polearm), f(W, WS.Staff) },
    }
    local out = {}
    for _, x in ipairs(all[key] or {}) do
        -- a category this game lacks reads nil: leave it out rather than ask for everything
        if x.classID ~= nil and (x.inventoryType ~= nil or x.subClassID ~= nil) then out[#out + 1] = x end
    end
    return out
end

-- Usable items of every quality but poor, as the game's filter names them.
function AH.Filters()
    local F = Enum and Enum.AuctionHouseFilter
    local out = {}
    if not F then return out end
    for _, k in ipairs({ "UsableOnly", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality" }) do
        if F[k] ~= nil then out[#out + 1] = F[k] end
    end
    return out
end

function AH.Sorts()
    local S = Enum and Enum.AuctionHouseSortOrder
    return { { sortOrder = S and S.Price or 0, reverseSort = false } }
end

-- The picks: which scales count and which slot, per character (scales per talent group or spec).

function AH.Store(create)
    local G = NS.GearValue
    local data = G and G.Data()
    local me = UnitGUID and UnitGUID("player")
    if not data or Secret(me) or type(me) ~= "string" then return nil end
    if type(data.gearFinder) ~= "table" then
        if not create then return nil end
        data.gearFinder = {}
    end
    local t = data.gearFinder[me]
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        data.gearFinder[me] = t
    end
    return t
end

-- To start: the scales the group shows, of the spec most of them name.
function AH.DefaultPicks()
    local G = NS.GearValue
    local g = G and G.Group()
    local shown = g and G.ShownScales(g) or {}
    local count, best, bestN = {}, nil, 0
    for _, s in ipairs(shown) do
        local k = s.spec or ""
        count[k] = (count[k] or 0) + 1
        if count[k] > bestN then best, bestN = k, count[k] end
    end
    local out = {}
    for _, s in ipairs(shown) do
        if (s.spec or "") == best then out[s.id] = true end
    end
    return out
end

function AH.Picks()
    local G = NS.GearValue
    local g = G and G.Group()
    local t = AH.Store(false)
    local kept = t and g and t[g]
    if type(kept) == "table" and type(kept.picks) == "table" then return kept.picks end
    return AH.DefaultPicks()
end

function AH.SetPick(id, on)
    local G = NS.GearValue
    local g = G and G.Group()
    local t = AH.Store(true)
    if not (t and g) then return false end
    if type(t[g]) ~= "table" then t[g] = {} end
    if type(t[g].picks) ~= "table" then
        t[g].picks = {}
        for k, v in pairs(AH.DefaultPicks()) do t[g].picks[k] = v end
    end
    t[g].picks[id] = on and true or nil
    return true
end

-- The picked scales in page order.
function AH.PickedScales()
    local G = NS.GearValue
    local picks, out = AH.Picks(), {}
    for _, s in ipairs(G and G.Scales() or {}) do
        if picks[s.id] then out[#out + 1] = s end
    end
    return out
end

-- The slots picked, one or several, per character: `gearFinder[GUID].slots` = { [slot] = true }; none means all. An
-- older single `slot` still reads.
function AH.SlotPicks()
    local t = AH.Store(false)
    local out = {}
    if not t then return out end
    if type(t.slots) == "table" then
        for k, on in pairs(t.slots) do out[k] = on == true or nil end
    elseif type(t.slot) == "string" and t.slot ~= "all" then
        out[t.slot] = true
    end
    return out
end

-- The slots a search asks for, in search order: the picked ones, else every slot.
function AH.PickedSlots()
    local picks, out = AH.SlotPicks(), {}
    for _, k in ipairs(AH.Slots()) do
        if picks[k] then out[#out + 1] = k end
    end
    if #out == 0 then return AH.Slots() end
    return out
end

-- "all", the one slot picked, or "multi".
function AH.Slot()
    local picks, n, one = AH.SlotPicks(), 0, nil
    for _, k in ipairs(AH.Slots()) do
        if picks[k] then n, one = n + 1, k end
    end
    if n == 0 then return "all" end
    return (n == 1) and one or "multi"
end

-- One slot alone ("all" for every slot).
function AH.SetSlot(v)
    local t = AH.Store(true)
    if not t then return end
    t.slot = nil
    t.slots = (v ~= "all") and { [v] = true } or nil
end

-- A slot ticked or unticked; "all" unticks them all.
function AH.ToggleSlot(v)
    local t = AH.Store(true)
    if not t then return end
    local picks = AH.SlotPicks()
    if v == "all" then
        picks = {}
    else
        picks[v] = not picks[v] or nil
    end
    t.slot = nil
    t.slots = next(picks) and picks or nil
end

function AH.SlotsText()
    local list = AH.PickedSlots()
    if AH.Slot() == "all" then return AH.SlotWord("all") end
    if #list == 1 then return AH.SlotWord(list[1]) end
    return AH.SlotWord(list[1]) .. " +" .. (#list - 1)
end

-- What a slot takes, by the item's equip location: the server may answer a slot's query with other slots' items.
AH.SLOT_LOCS = {
    head = { INVTYPE_HEAD = true }, neck = { INVTYPE_NECK = true }, shoulder = { INVTYPE_SHOULDER = true },
    back = { INVTYPE_CLOAK = true }, chest = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    wrist = { INVTYPE_WRIST = true }, hands = { INVTYPE_HAND = true }, waist = { INVTYPE_WAIST = true },
    legs = { INVTYPE_LEGS = true }, feet = { INVTYPE_FEET = true }, finger = { INVTYPE_FINGER = true },
    trinket = { INVTYPE_TRINKET = true },
    onehand = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true },
    twohand = { INVTYPE_2HWEAPON = true }, offhand = { INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true },
    relic = { INVTYPE_RELIC = true },
}
function AH.SlotTakes(slot, loc)
    local set = AH.SLOT_LOCS[slot]
    return set ~= nil and loc ~= nil and set[loc] == true
end

-- The list's order: a column and its direction, per character. A first click on a column takes its own way
-- (gains and counts high first, words and prices low first, levels high first); a second click turns it.
AH.SORT_FIRST = { name = false, lvl = true, avail = true, price = false, gain = true }
function AH.Sort()
    local t = AH.Store(false)
    local s = t and t.sort
    if type(s) == "table" and AH.SORT_FIRST[s.key] ~= nil then return s.key, s.desc == true end
    return "gain", true
end

function AH.SetSort(key)
    if AH.SORT_FIRST[key] == nil then return end
    local now, desc = AH.Sort()
    local t = AH.Store(true)
    if not t then return end
    if now == key then desc = not desc else desc = AH.SORT_FIRST[key] end
    t.sort = { key = key, desc = desc }
    AH.Dirty()
end

-- The gain's unit: the scale's own points, DPS, or a share of the scale's DPS (each scale's numbers from a
-- simulator; a scale without them stays in points).
AH.UNITS = { "points", "dps", "pct" }
function AH.Unit()
    local t = AH.Store(false)
    local u = t and t.unit
    if u == "dps" or u == "pct" then return u end
    return "points"
end

function AH.SetUnit(v)
    local t = AH.Store(true)
    if t then t.unit = (v ~= "points") and v or nil end
    AH.SyncBar()
    AH.Dirty()
end

function AH.UnitWord(u)
    if u == "dps" then return Tr("Gain in DPS") end
    if u == "pct" then return Tr("Gain in DPS %") end
    return Tr("Gain in points")
end

-- The search: one task at a time, a slot's browse query first, then an item search for each listing whose
-- stats need its own link (a random suffix, or retail's item levels). Items without one load by ID.

local function SameKey(a, b)
    return a and b and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
        and (a.itemSuffix or 0) == (b.itemSuffix or 0) and (a.battlePetSpeciesID or 0) == (b.battlePetSpeciesID or 0)
end
AH.SameKey = SameKey

-- One query for every picked slot. The server may ignore a filter's slot and answer with every item of the class in
-- name order (four pages a slot only ever reached names from A to D): so every page is read, and each
-- item goes to the picked slot its equip location fits. slots: a list of slot keys, a single key, or "all".
function AH.Start(slots)
    AH.Stop()
    AH.seen, AH.byKey, AH.tasks, AH.loads, AH.loading = {}, {}, {}, {}, 0
    AH.pending, AH.head, AH.listed = {}, 1, 0
    if type(slots) == "table" then AH.order = slots
    elseif slots == "all" or slots == nil then AH.order = AH.Slots()
    else AH.order = { slots } end
    -- one query for every picked slot: the server sends all armor for any armor query, so one read serves them all
    local filters = {}
    for _, s in ipairs(AH.order) do
        for _, f in ipairs(AH.ClassFilters(s) or {}) do filters[#filters + 1] = f end
    end
    AH.tasks[1] = { kind = "browse", filters = filters }
    AH.slotsDone, AH.running, AH.deadline = 0, true, nil
    AH.Listen(true)
    AH.Pump()
    -- the press shows once the query is out: the button, the first status
    AH.ShowList()
end

function AH.Stop()
    AH.token = AH.token + 1
    AH.tasks, AH.wait, AH.running = {}, nil, false
    AH.Listen(false)
end

-- What the search is waiting on; a step the server never answers is let go. Each further page asked for arms the
-- wait again.
function AH.Wait(w)
    AH.wait = w
    AH.Arm(w)
end

function AH.Arm(w)
    w.armed = (w.armed or 0) + 1
    local token, armed = AH.token, w.armed
    C_Timer.After(AH.WAIT_FOR, function()
        if AH.token == token and AH.wait == w and w.armed == armed then
            AH.wait = nil
            if w.kind == "browse" then AH.slotsDone = #AH.order end
            AH.Pump()
        end
    end)
end

-- The picked slot an equip location fits, or nil.
function AH.SlotFor(loc)
    for _, s in ipairs(AH.order or {}) do
        if AH.SlotTakes(s, loc) then return s end
    end
    return nil
end

function AH.Pump()
    if not AH.running or AH.wait then return end
    local CA = C_AuctionHouse
    local task = AH.tasks[1]
    if not task then
        if AH.Left() > 0 then
            -- listings still being read a few a frame: the last slice pumps again
            AH.Dirty()
            return
        elseif (AH.loading or 0) <= 0 then
            AH.Finish()
        elseif not AH.deadline then
            -- an item that never loads must not hold the search open
            AH.deadline = true
            local token = AH.token
            C_Timer.After(AH.WAIT_FOR, function()
                if AH.token == token and AH.running and not AH.tasks[1] and not AH.wait then
                    AH.loads, AH.loading = {}, 0
                    AH.Finish()
                end
            end)
        end
        AH.Dirty()
        return
    end
    if CA.IsThrottledMessageSystemReady and not CA.IsThrottledMessageSystemReady() then
        AH.Wait({ kind = "throttle" })
        return
    end
    table.remove(AH.tasks, 1)
    if task.kind == "browse" then
        local query = { searchString = "", sorts = AH.Sorts(), filters = AH.Filters(), itemClassFilters = task.filters }
        AH.sending = true
        CA.SendBrowseQuery(query)
        AH.sending = false
        AH.Wait({ kind = "browse", pages = 1, taken = 0 })
    else
        CA.SendSearchQuery(task.key, AH.Sorts(), true)
        AH.Wait({ kind = "item", key = task.key, entry = task.entry })
    end
    AH.Dirty()
end

function AH.Next()
    local token = AH.token
    C_Timer.After(0, function()
        if AH.token == token then AH.Pump() end
    end)
end

-- Each page as it comes: a first answer brings the list so far (only what is new is read), a further page brings its
-- own batch; then the next page is asked for until the server has sent them all.
function AH.OnBrowse(event, added)
    local w, CA = AH.wait, C_AuctionHouse
    if not (w and w.kind == "browse") then return end
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and type(added) == "table" then
        AH.Queue(added)
        w.taken = w.taken + #added
    else
        local list = CA.GetBrowseResults() or {}
        local new = {}
        for i = w.taken + 1, #list do new[#new + 1] = list[i] end
        AH.Queue(new)
        w.taken = math.max(w.taken, #list)
    end
    AH.listed = w.taken
    local full = not CA.HasFullBrowseResults or CA.HasFullBrowseResults()
    if not full and w.pages < AH.MAX_PAGES and CA.RequestMoreBrowseResults then
        AH.More(w)
        AH.Dirty()
        return
    end
    AH.slotsDone = #AH.order
    AH.wait = nil
    AH.Next()
end

-- The next page, when the auction house takes requests again (the throttle event asks again).
function AH.More(w)
    local CA = C_AuctionHouse
    if CA.IsThrottledMessageSystemReady and not CA.IsThrottledMessageSystemReady() then
        w.needMore = true
        AH.Arm(w)
        return
    end
    w.needMore = nil
    w.pages = w.pages + 1
    CA.RequestMoreBrowseResults()
    AH.Arm(w)
end

function AH.OnItem(itemKey)
    local w, CA = AH.wait, C_AuctionHouse
    if not (w and w.kind == "item" and SameKey(itemKey, w.key)) then return end
    local info = CA.GetItemSearchResultInfo and CA.GetItemSearchResultInfo(w.key, 1)
    local link = info and info.itemLink
    if type(link) == "string" and not Secret(link) then AH.Value(w.entry, link) end
    AH.wait = nil
    AH.Next()
end

local function LinkOf(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = get(id)
    if type(link) == "string" and not Secret(link) then return link end
    return nil
end

-- Browse results wait here and are read a few a frame, within a time budget, so a big search never stalls the
-- game: reading a listing takes the item's tooltip data and its worth on each picked scale.
function AH.Left()
    return #AH.pending - AH.head + 1
end

function AH.Queue(list)
    for _, r in ipairs(list) do AH.pending[#AH.pending + 1] = r end
    AH.Work()
end

function AH.Work()
    if AH.working or AH.Left() <= 0 then return end
    AH.working = true
    local token = AH.token
    C_Timer.After(0, function() AH.Slice(token) end)
end

function AH.Slice(token)
    AH.working = false
    if token ~= AH.token then return end
    local G = NS.GearValue
    local clock = debugprofilestop
    local t0 = clock and clock()
    -- the worn gear's goal amounts once a slice, not once a listing and scale
    if G then G.wornMemo = {} end
    AH.slicePicks = AH.PickedScales()
    -- n: listings read in full (tooltip data, worth); scanned: every listing looked at, most dropped at once as
    -- another slot or a repeat
    local n, scanned = 0, 0
    while AH.Left() > 0 and n < AH.PER_FRAME and scanned < AH.SCAN_PER_FRAME do
        local r = AH.pending[AH.head]
        AH.pending[AH.head] = nil
        AH.head = AH.head + 1
        if AH.Take(r) then n = n + 1 end
        scanned = scanned + 1
        if t0 and clock() - t0 > AH.FRAME_MS then break end
    end
    AH.slicePicks = nil
    if G then G.wornMemo = nil end
    if AH.Left() > 0 then
        AH.Work()
    else
        AH.pending, AH.head = {}, 1
        AH.Next()
    end
    AH.Dirty()
end

function AH.KeyText(key)
    return key.itemID .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0)
end

-- A listing. One row per item: another listing of it only lowers the price and adds to the count. Its link comes
-- straight from the item when it has no variants, from its key (suffix, level) when the client reads that, else
-- from an item search.
function AH.Take(r)
    local key = r and r.itemKey
    if type(key) ~= "table" or Secret(key.itemID) or type(key.itemID) ~= "number" then return false end
    -- only the picked slots: the item's equip location reads at once from its ID, before anything costly
    local inst = C_Item and C_Item.GetItemInfoInstant
    local loc = inst and select(4, inst(key.itemID))
    local slot = (not Secret(loc)) and AH.SlotFor(loc) or nil
    if not slot then return false end
    local price, count = r.minPrice, tonumber(r.totalQuantity) or 0
    if Secret(price) or type(price) ~= "number" then price = nil end
    local kt = AH.KeyText(key)
    local had = AH.byKey[kt]
    if had then
        if price and (not had.price or price < had.price) then had.price = price end
        had.count, had.listings = had.count + count, had.listings + 1
        AH.Dirty()
        return false
    end
    local entry = { key = key, price = price, count = count, listings = 1, slot = slot }
    AH.byKey[kt] = entry
    local G = NS.GearValue
    if (key.itemSuffix or 0) ~= 0 or (G and G.Game() == "retail") then
        local TI = C_TooltipInfo
        local data = TI and TI.GetItemKey and TI.GetItemKey(key.itemID, key.itemLevel or 0, key.itemSuffix or 0)
        local link = (type(data) == "table" and not Secret(data)) and data.hyperlink or nil
        if type(link) == "string" and not Secret(link) then
            AH.Value(entry, link, data.lines)
            return true
        end
        AH.tasks[#AH.tasks + 1] = { kind = "item", key = key, entry = entry }
        return true
    end
    local link = LinkOf(key.itemID)
    if link then
        AH.Value(entry, link)
        return true
    end
    local waiting = AH.loads[key.itemID]
    if not waiting then
        waiting = {}
        AH.loads[key.itemID] = waiting
        AH.loading = (AH.loading or 0) + 1
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(key.itemID) end
    end
    waiting[#waiting + 1] = entry
    return true
end

function AH.OnItemInfo(id)
    local waiting = AH.loads[id]
    if not waiting then return end
    local link = LinkOf(id)
    if not link then return end
    AH.loads[id] = nil
    AH.loading = math.max(0, (AH.loading or 0) - 1)
    for _, e in ipairs(waiting) do AH.Value(e, link) end
    AH.Next()
end

function AH.Value(entry, link, lines)
    local tip = (not lines) and C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality, _, minLevel, _, _, _, _, icon = get(link)
    entry.link, entry.lines = link, lines or (tip and tip.lines)
    entry.name = link:match("%[(.-)%]") or "?"
    entry.quality, entry.req, entry.icon, entry.gains = quality, minLevel, icon, {}
    AH.seen[#AH.seen + 1] = entry
    -- its worth on the picked scales now, inside the reading budget, so a redraw only reads what is kept
    for _, s in ipairs(AH.slicePicks or {}) do AH.Gain(entry, s) end
    AH.Dirty()
end

function AH.Finish()
    AH.running = false
    AH.Listen(false)
    -- the last state at once, not after the search's redraw pace
    AH.Draw()
end

-- The listings that beat what is worn for a picked scale, best gain first. Each listing's gain per scale is read
-- once a search, so picking scales re-ranks at once.
function AH.Gain(entry, scale)
    local g = entry.gains[scale.id]
    if g == nil then
        local G = NS.GearValue
        local out = G and entry.link and G.Gains(entry.link, entry.lines, { scale })
        local d = out and out[1] and out[1].delta
        g = (type(d) == "number") and d or false
        entry.gains[scale.id] = g
    end
    return g or nil
end

-- Each row: the gain in points on its best picked scale, that gain in the unit asked (value, unit), the scale; in
-- the order the clicked column asks, ties by the larger gain, then the lower price. In DPS or DPS % only the scales
-- that can say it count, so every row is in the one unit (the status names the others).
function AH.Ranked()
    local G = NS.GearValue
    local scales, out, mode = AH.PickedScales(), {}, AH.Unit()
    for _, e in ipairs(AH.seen) do
        local best, by, bestV, bestU
        for _, s in ipairs(scales) do
            local d = AH.Gain(e, s)
            if d and d > 0.05 then
                local v, u = d, "points"
                if G then v, u = G.InUnit(s, d, mode) end
                if (u == mode or mode == "points") and (not bestV or v > bestV) then
                    best, by, bestV, bestU = d, s, v, u
                end
            end
        end
        if best then out[#out + 1] = { entry = e, gain = best, scale = by, value = bestV, unit = bestU } end
    end
    local key, desc = AH.Sort()
    local function field(it)
        local e = it.entry
        if key == "name" then return (e.name or ""):lower() end
        if key == "lvl" then return e.req or 0 end
        if key == "avail" then return e.count or 0 end
        if key == "price" then return e.price or math.huge end
        return it.value
    end
    table.sort(out, function(a, b)
        local x, y = field(a), field(b)
        if x ~= y then
            if desc then return x > y end
            return x < y
        end
        if a.value ~= b.value then return a.value > b.value end
        return (a.entry.price or 0) < (b.entry.price or 0)
    end)
    return out
end

-- A row's gain in its unit: "+8 SP", "+3.5 DPS", "+0.55%".
function AH.GainText(it)
    local G = NS.GearValue
    if it.unit == "dps" then return ("+%.1f %s"):format(it.value, Tr("DPS")) end
    if it.unit == "pct" then return ((it.value < 1) and "+%.2f%%" or "+%.1f%%"):format(it.value) end
    local unit = G and G.Unit(it.scale)
    return "+" .. (G and G.Num(it.gain) or it.gain) .. (unit and (" " .. Tr(unit)) or "")
end

-- DPS asked for while a picked scale lacks its numbers: say which scales the DPS rows leave out.
function AH.UnitHint()
    local mode = AH.Unit()
    local G = NS.GearValue
    if mode == "points" or not G then return nil end
    local missing = {}
    for _, s in ipairs(AH.PickedScales()) do
        local per, base = G.Dps(s)
        if not per or (mode == "pct" and not base) then missing[#missing + 1] = s.name end
    end
    if #missing == 0 then return nil end
    return Tr("Left out of DPS: %s. Set DPS per point and Your DPS on its Weights tab."):format(table.concat(missing, ", "))
end

function AH.StatusText()
    if not (AH.running or AH.slotsDone > 0) then return nil end
    local n = AH.order and #AH.order or 0
    if AH.running then
        if AH.wait and AH.wait.kind == "browse" then
            return Tr("Searching the auction house: %d listings so far"):format(AH.listed or 0), false
        end
        return Tr("Reading the listings: %d left"):format(#AH.tasks + (AH.loading or 0) + (AH.wait and 1 or 0) + AH.Left()), false
    end
    local found = #AH.Ranked()
    if n == 1 then
        local f = found == 1 and Tr("%s searched: %d upgrade") or Tr("%s searched: %d upgrades")
        return f:format(AH.SlotWord(AH.order[1]), found), true
    end
    local f = found == 1 and Tr("%d slots searched: %d upgrade") or Tr("%d slots searched: %d upgrades")
    return f:format(n, found), true
end

-- Events: the auction house's own, listened to only while a search runs (item info only while one loads).

local EV = CreateFrame("Frame")
AH.events = EV
function AH.Listen(on)
    local list = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
        "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "GET_ITEM_INFO_RECEIVED" }
    for _, e in ipairs(list) do
        if on then EV:RegisterEvent(e) else EV:UnregisterEvent(e) end
    end
end
EV:RegisterEvent("ADDON_LOADED")
EV:RegisterEvent("AUCTION_HOUSE_SHOW")
EV:RegisterEvent("AUCTION_HOUSE_CLOSED")
EV:SetScript("OnEvent", function(_, event, a)
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        AH.OnBrowse(event, a)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        AH.OnItem(a)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        local w = AH.wait
        if w and w.kind == "throttle" then
            AH.wait = nil
            AH.Pump()
        elseif w and w.needMore then
            AH.More(w)
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        AH.OnItemInfo(a)
    elseif event == "ADDON_LOADED" then
        if a == "Blizzard_AuctionHouseUI" then AH.Build() end
    elseif event == "AUCTION_HOUSE_SHOW" then
        AH.Build()
        AH.SyncBar()
        -- other addons place their tabs as the frame opens: ours goes after them a frame later
        C_Timer.After(0, AH.PlaceTab)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        AH.Stop()
        AH.slotsDone, AH.seen, AH.byKey = 0, {}, {}
        AH.HideList()
        if AH.view then AH.view:Hide() end
    end
end)

-- The game's own search (in its Buy tab) stops ours: the results it would bring are the game's; what was found stays.
function AH.OnGameSearch()
    if AH.sending then return end
    if AH.running then
        AH.Stop()
        AH.Finish()
    end
end

-- Any other page (a game tab, another addon's tab, a row's buy view) takes ours away and unpicks our tab.
function AH.OnMode()
    if AH.view then AH.view:Hide() end
    if AH.tab and PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(AH.tab) end
end

-- Our page: the game's pages and any other tab's page go (a switch to Buy first, so other tabs close as they do for a
-- game tab; then no page), every other tab unpicked, ours picked, the frame's title ours.
function AH.SelectTab()
    local F = AuctionHouseFrame
    local M = AuctionHouseFrameDisplayMode
    if not (F and AH.view) then return end
    -- these switches pass through OnMode, which hides ours: it shows again below
    if M and M.Buy then F:SetDisplayMode(M.Buy) end
    F:SetDisplayMode({})
    F.displayMode = nil
    if PanelTemplates_DeselectTab then
        for _, t in ipairs(F.Tabs or {}) do PanelTemplates_DeselectTab(t) end
    end
    if PanelTemplates_SelectTab then PanelTemplates_SelectTab(AH.tab) end
    if F.SetTitle then F:SetTitle(Tr("Find Upgrades")) end
    AH.view:Show()
    AH.SyncBar()
    AH.Draw()
end

-- Our tab after the rightmost tab under the frame, the game's own or one another addon added, so none overlaps;
-- again on every open, after the others have placed theirs.
function AH.PlaceTab()
    local F, tab = AuctionHouseFrame, AH.tab
    local tabs = F and F.Tabs
    -- the game's last tab, never ours (ours sits on a holder of its own, out of the game's list)
    local last
    if type(tabs) == "table" then
        for i = #tabs, 1, -1 do
            if tabs[i] ~= tab then
                last = tabs[i]
                break
            end
        end
    end
    if not (tab and last) then return end
    local top, best, bestR = last:GetTop(), last, last:GetRight()
    local function consider(f)
        if f == tab or not (f:IsObjectType("Button") and f:IsShown()) then return end
        local t, r = f:GetTop(), f:GetRight()
        if t and top and r and bestR and math.abs(t - top) < 2 and r > bestR then best, bestR = f, r end
    end
    for _, c in ipairs({ F:GetChildren() }) do
        consider(c)
        for _, g in ipairs({ c:GetChildren() }) do consider(g) end
    end
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", best, "TOPRIGHT", AH.TAB_GAP, 0)
end

-- The finder's own tab and page. The controls (the gain unit, the scales, the slots, Find upgrades) in the game's
-- own look where its search bar sits; the list fills the page below.
function AH.Build()
    local F = AuctionHouseFrame
    local AT = NS.AT
    if AH.bar or not (F and type(F.Tabs) == "table" and F.SetDisplayMode and AT) then return end
    local view = CreateFrame("Frame", nil, F)
    view:SetPoint("TOPLEFT", F, "TOPLEFT", AH.VIEW_L, AH.VIEW_T)
    view:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", AH.VIEW_R, AH.VIEW_B)
    view:SetFrameLevel(F:GetFrameLevel() + 5)
    view:Hide()
    AH.view = view

    -- the tab template files each tab into its parent's Tabs: a holder of our own keeps ours out of the game's list
    -- (its tab code walks that list), as other auction addons do
    local holder = CreateFrame("Frame", nil, F)
    holder:SetSize(1, 1)
    holder:SetPoint("TOPLEFT", F, "BOTTOMLEFT", 0, 0)
    AH.tabHolder = holder
    local tab = CreateFrame("Button", nil, holder, "AuctionHouseFrameDisplayModeTabTemplate")
    tab:SetText(Tr("Find Upgrades"))
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 20, nil, 70) end
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
    tab:SetScript("OnClick", function()
        AT.CloseDropdown()
        AH.SelectTab()
    end)
    AH.tab = tab
    AH.PlaceTab()

    local bar = CreateFrame("Frame", nil, view)
    bar:SetSize(AH.UNIT_W + AH.SCALES_W + AH.SLOT_W + AH.BTN_W + 3 * AH.GAP, AH.BAR_H)
    bar:SetPoint("TOPRIGHT", F, "TOPRIGHT", AH.BAR_X, AH.BAR_Y)
    AH.bar = bar

    local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    btn:SetSize(AH.BTN_W, AH.BAR_H)
    btn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    btn:SetText(Tr("Find upgrades"))
    btn:SetScript("OnClick", function()
        AT.CloseDropdown()
        if not AH.running then AH.Start(AH.PickedSlots()) end
    end)
    AH.btn = btn

    local dd = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
    dd:SetWidth(AH.SLOT_W)
    dd:SetPoint("RIGHT", btn, "LEFT", -AH.GAP, 0)
    dd:SetupMenu(function(_, root)
        for _, it in ipairs(AH.SlotItems()) do
            -- ticks, open while ticking: one slot or several; All slots unticks the rest
            root:CreateCheckbox(it.text, function(v)
                if v == "all" then return AH.Slot() == "all" end
                return AH.SlotPicks()[v] == true
            end, AH.PickSlot, it.value)
        end
    end)
    AH.slotDD = dd

    local field = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
    field:SetWidth(AH.SCALES_W)
    field:SetPoint("RIGHT", dd, "LEFT", -AH.GAP, 0)
    -- a tick per scale; the list stays open while ticking
    field:SetupMenu(function(_, root)
        local G = NS.GearValue
        for _, s in ipairs(G and G.Scales() or {}) do
            root:CreateCheckbox(s.name, function(id) return AH.Picks()[id] == true end, function(id)
                AH.SetPick(id, not AH.Picks()[id])
                AH.SyncBar()
                AH.Dirty()
            end, s.id)
        end
    end)
    AT.Tooltip(field, "Scales", "The Gear Value scales that count. A listing shows when it beats what you wear on one of them.")
    AH.field = field

    local unit = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
    unit:SetWidth(AH.UNIT_W)
    unit:SetPoint("RIGHT", field, "LEFT", -AH.GAP, 0)
    unit:SetupMenu(function(_, root)
        for _, u in ipairs(AH.UNITS) do
            root:CreateRadio(AH.UnitWord(u), function(v) return AH.Unit() == v end, AH.SetUnit, u)
        end
    end)
    AT.Tooltip(unit, "Gain", "Gains in the scale's points, in DPS or as a share of your DPS. DPS takes each scale's DPS per point and your DPS, set on its Weights tab.")
    AH.unitDD = unit

    AH.BuildList(F)
    hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", AH.OnGameSearch)
    hooksecurefunc(F, "SetDisplayMode", function(_, mode) AH.OnMode(mode) end)
    AH.SyncBar()
end

function AH.SlotItems()
    local out = { { value = "all", text = AH.SlotWord("all"), raw = true } }
    for _, s in ipairs(AH.Slots()) do out[#out + 1] = { value = s, text = AH.SlotWord(s), raw = true } end
    return out
end

-- A new slot takes a new search: the results go until the next press.
function AH.PickSlot(v)
    AH.ToggleSlot(v)
    AH.Stop()
    AH.slotsDone, AH.seen, AH.byKey = 0, {}, {}
    AH.HideList()
    AH.SyncBar()
end

function AH.ScalesText()
    local picked = AH.PickedScales()
    if #picked == 0 then return Tr("No scale") end
    if #picked == 1 then return picked[1].name end
    return picked[1].name .. " +" .. (#picked - 1)
end

-- The finder shows only with Gear Value on.
function AH.SyncBar()
    if not AH.bar then return end
    local G = NS.GearValue
    local on = G ~= nil and G.Enabled()
    AH.bar:SetShown(on)
    if AH.tab then AH.tab:SetShown(on) end
    if not on then
        AH.Stop()
        if AH.list then AH.list:Hide() end
        if AH.view and AH.view:IsShown() then AH.OnMode() end
        return
    end
    AH.btn:SetText(AH.running and Tr("Searching...") or Tr("Find upgrades"))
    -- a longer language widens the button; the bar follows so nothing runs past the frame's edge
    local bw = math.max(AH.BTN_W, math.ceil((AH.btn:GetTextWidth() or 0) + 28))
    if AH.btn:GetWidth() ~= bw then AH.btn:SetWidth(bw) end
    local w = AH.UNIT_W + AH.SCALES_W + AH.SLOT_W + bw + 3 * AH.GAP
    if AH.bar:GetWidth() ~= w then AH.bar:SetWidth(w) end
    AH.field:OverrideText(AH.ScalesText())
    AH.slotDD:OverrideText(AH.SlotsText())
    AH.unitDD:GenerateMenu()
end

-- The list: laid over the game's browse list in its look, with a Gain column. Rows are pooled.

local function Fill(tex, c, a)
    tex:SetColorTexture(c[1], c[2], c[3], a or 1)
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT or (NS.AT and NS.AT.FONT), size, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function AH.BuildList(F)
    local AT = NS.AT
    local list = CreateFrame("Frame", nil, AH.view)
    list:SetAllPoints(AH.view)
    list:EnableMouse(true)
    list:Hide()
    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, AH.LIST_BG)
    -- a 1-pixel edge on every side, whole pixels at any scale
    list.edges = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
        { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = list:CreateTexture(nil, "BORDER")
        Fill(e, AH.LIST_EDGE)
        e:SetPoint(pts[1])
        e:SetPoint(pts[2])
        list.edges[i] = e
    end

    local head = CreateFrame("Frame", nil, list)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(AH.HEAD_H)
    local hb = head:CreateTexture(nil, "BACKGROUND")
    hb:SetAllPoints()
    Fill(hb, AH.HEAD_BG)
    head.cols, head.btns = {}, {}
    -- one-word titles: through Tr here so the key list reads them. Each a button that sorts by its column, as the
    -- game's own headers do; the sorted one wears the game's arrow.
    for i, word in ipairs({ Tr("Name"), Tr("Lvl"), Tr("Price"), Tr("Gain"), Tr("Available") }) do
        local key = AH.HEAD_KEYS[i]
        local b = CreateFrame("Button", nil, head)
        b:SetHeight(AH.HEAD_H)
        local just = (i == 2 or i == 5) and "CENTER" or ((i == 3) and "RIGHT" or "LEFT")
        local fs = Text(b, 11, just)
        fs:SetPoint(just, b, just, 0, 0)
        fs:SetText(word:upper())
        local c = (i == 4) and AT.COL.arc or AH.GOLD
        fs:SetTextColor(c[1], c[2], c[3])
        b:SetScript("OnClick", function() AH.SetSort(key) end)
        b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function() fs:SetTextColor(c[1], c[2], c[3]) end)
        b.fs, b.key = fs, key
        head.cols[i], head.btns[i] = fs, b
    end
    head.arrow = head:CreateTexture(nil, "OVERLAY")
    if not (head.arrow.SetAtlas and head.arrow:SetAtlas("auctionhouse-ui-sortarrow", true)) then
        head.arrow:SetSize(9, 6)
        Fill(head.arrow, AH.GOLD)
    end
    list.head = head

    local status = CreateFrame("Frame", nil, list)
    status:SetPoint("BOTTOMLEFT", 1, 1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetHeight(AH.STATUS_H)
    status.dot = status:CreateTexture(nil, "ARTWORK")
    status.dot:SetSize(8, 8)
    status.dot:SetPoint("LEFT", 8, 0)
    status.fs = status:CreateFontString(nil, "OVERLAY")
    status.fs:SetFont(AT.FONT, 12, "")
    status.fs:SetPoint("LEFT", status.dot, "RIGHT", 8, 0)
    status.fs:SetPoint("RIGHT", -8, 0)
    status.fs:SetJustifyH("LEFT")
    status.fs:SetWordWrap(false)
    list.status = status

    local host, content = AT.MakeScroll(list)
    host:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", -AT.ScrollW - 4, 0)
    -- a scroll refills the rows on screen
    host:HookScript("OnVerticalScroll", function() AH.DrawRows() end)
    list.host, list.content = host, content
    list.empty = Text(content, 13)
    list.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -14)
    list.empty:SetTextColor(AH.MUTED[1], AH.MUTED[2], AH.MUTED[3])

    list:SetScript("OnSizeChanged", function() AH.Dirty() end)
    list:SetScript("OnHide", function() if GameTooltip:GetOwner() and GameTooltip:GetOwner()._adFinder then GameTooltip:Hide() end end)
    AH.list = list
end

-- The columns' x on the list's width: name takes what the others leave.
function AH.Columns(w)
    local px = NS.AT.Px(AH.list)
    local function snap(v) return math.floor(v / px + 0.5) * px end
    local pad = 8
    local nameW = snap(math.max(80, w - 2 * pad - AH.LVL_W - AH.AVAIL_W - AH.PRICE_W - AH.GAP_W - AH.GAIN_W
        - NS.AT.ScrollW - 4))
    local x = { name = pad, lvl = pad + nameW, avail = pad + nameW + AH.LVL_W }
    x.price = x.avail + AH.AVAIL_W
    x.gain = x.price + AH.PRICE_W + AH.GAP_W
    return x, nameW
end

function AH.Row(i)
    local row = AH.rows[i]
    if row then return row end
    local content = AH.list.content
    row = CreateFrame("Button", nil, content)
    row._adFinder = true
    row:SetHeight(AH.ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    -- hover: the game's own row highlight, added onto the row under its words (a solid fill on the highlight
    -- layer draws over the text and blanks the row)
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetAllPoints()
    if not (row.hl.SetAtlas and row.hl:SetAtlas("auctionhouse-ui-row-highlight")) then Fill(row.hl, AH.ROW_HOVER, 0.5) end
    row.hl:SetBlendMode("ADD")
    row.hl:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(AH.ICON - 2, AH.ICON - 2)
    row.edge = row:CreateTexture(nil, "BORDER")
    row.edge:SetSize(AH.ICON, AH.ICON)
    row.edge:SetPoint("CENTER", row.icon, "CENTER")
    row.name = Text(row, 13)
    row.lvl = Text(row, 13, "CENTER")
    row.avail = Text(row, 13, "CENTER")
    row.price = Text(row, 13, "RIGHT")
    row.gain = Text(row, 13)
    row.by = Text(row, 11)
    local faint = NS.AT.COL.faint
    row.by:SetTextColor(faint[1], faint[2], faint[3])
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.entry.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    -- the game's own buy view for the listing
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult then
            AuctionHouseFrame:SelectBrowseResult({ itemKey = e.key, minPrice = e.price, totalQuantity = e.count })
        end
    end)
    AH.rows[i] = row
    return row
end

local function Money(copper)
    if type(copper) ~= "number" then return "" end
    if GetMoneyString then return GetMoneyString(copper, true) end
    return math.floor(copper / 10000) .. "g"
end

function AH.Draw()
    -- any redraw still waiting is now done
    AH.dirty, AH.drawGen = nil, AH.drawGen + 1
    local list = AH.list
    if not (list and list:IsShown()) then return end
    local COL, AT = NS.AT.COL, NS.AT
    local w = list:GetWidth() or 0
    local x, nameW = AH.Columns(w)
    -- the header buttons over their columns; the arrow beside the sorted one's words, up for low first
    local head = list.head
    local spans = { { x.name, nameW }, { x.lvl, AH.LVL_W }, { x.price, AH.PRICE_W }, { x.gain, AH.GAIN_W },
        { x.avail, AH.AVAIL_W } }
    local sortKey, desc = AH.Sort()
    head.arrow:Hide()
    for i, b in ipairs(head.btns) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", head, "LEFT", spans[i][1], 0)
        b:SetWidth(spans[i][2])
        if b.key == sortKey then
            head.arrow:ClearAllPoints()
            head.arrow:SetPoint("LEFT", b.fs, "RIGHT", 3, 0)
            if desc then head.arrow:SetTexCoord(0, 1, 0, 1) else head.arrow:SetTexCoord(0, 1, 1, 0) end
            head.arrow:Show()
        end
    end
    local ranked = AH.Ranked()
    AH.ranked, AH.cols, AH.nameW = ranked, x, nameW
    list.content:SetSize(math.max(1, list.host:GetWidth() or 1), math.max(1, #ranked * AH.ROW_H))
    list.host:UpdateScroll()
    AH.DrawRows()
    local empty = #ranked == 0
    list.empty:SetShown(empty)
    if empty then
        list.empty:SetText(AH.running and Tr("Searching...") or Tr("Nothing here beats what you wear."))
    end
    local text, done = AH.StatusText()
    -- the search's own line stays; the DPS word follows it
    local hint = (not AH.running) and AH.UnitHint() or nil
    if hint then text, done = text and (text .. "   " .. hint) or hint, false end
    list.status:SetShown(text ~= nil)
    if text then
        list.status.fs:SetText(text)
        local c = done and AH.DONE or COL.arc
        list.status.dot:SetColorTexture(c[1], c[2], c[3], 1)
        local ink = done and COL.ink or COL.dim
        list.status.fs:SetTextColor(ink[1], ink[2], ink[3])
    end
    AH.SyncBar()
end

-- Only the rows on screen exist (a long search can bring hundreds of upgrades): they are filled from the kept
-- order at the scroll's offset, again on every scroll.
function AH.DrawRows()
    local list, ranked, x, nameW = AH.list, AH.ranked or {}, AH.cols, AH.nameW
    if not (list and x) then return end
    local top = (list.host.GetVerticalScroll and list.host:GetVerticalScroll()) or 0
    local first = math.max(1, math.floor(top / AH.ROW_H) + 1)
    local count = math.ceil((list.host:GetHeight() or 0) / AH.ROW_H) + 1
    local QC = ITEM_QUALITY_COLORS or {}
    local used = 0
    for k = 1, count do
        local i = first + k - 1
        local it = ranked[i]
        if not it then break end
        used = k
        local row, e = AH.Row(k), it.entry
        row.entry = e
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * AH.ROW_H)
        row:SetPoint("RIGHT", list.host, "RIGHT", 0, 0)
        local a = (i % 2 == 0) and AH.ROW_B or AH.ROW_A
        Fill(row.bg, a)
        local q = QC[e.quality or 1] or { r = 1, g = 1, b = 1 }
        row.icon:SetTexture(e.icon)
        row.icon:SetPoint("LEFT", row, "LEFT", x.name, 0)
        row.edge:SetColorTexture(q.r, q.g, q.b, 1)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(math.max(20, nameW - AH.ICON - 12))
        row.name:SetText(e.name)
        row.name:SetTextColor(q.r, q.g, q.b)
        row.lvl:SetPoint("LEFT", row, "LEFT", x.lvl, 0)
        row.lvl:SetWidth(AH.LVL_W)
        row.lvl:SetText(e.req and e.req > 0 and tostring(e.req) or "")
        row.lvl:SetTextColor(AH.INK[1], AH.INK[2], AH.INK[3])
        -- every listing of the item, its price the lowest
        row.avail:SetPoint("LEFT", row, "LEFT", x.avail, 0)
        row.avail:SetWidth(AH.AVAIL_W)
        row.avail:SetText((e.count and e.count > 0) and tostring(e.count) or "")
        row.avail:SetTextColor(AH.INK[1], AH.INK[2], AH.INK[3])
        row.price:SetPoint("LEFT", row, "LEFT", x.price, 0)
        row.price:SetWidth(AH.PRICE_W)
        row.price:SetText(Money(e.price))
        row.price:SetTextColor(AH.INK[1], AH.INK[2], AH.INK[3])
        row.gain:SetPoint("LEFT", row, "LEFT", x.gain, 0)
        row.gain:SetText(AH.GainText(it))
        row.gain:SetTextColor(AH.UP[1], AH.UP[2], AH.UP[3])
        row.by:SetPoint("LEFT", row.gain, "RIGHT", 6, 0)
        row.by:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.by:SetText(it.scale.name)
        row:Show()
    end
    for k = used + 1, #AH.rows do
        AH.rows[k].entry = nil
        AH.rows[k]:Hide()
    end
end

-- Redraws come together: many listings arrive in one frame, and while a search runs the list is drawn a few times a
-- second, not every frame.
function AH.Dirty()
    if AH.dirty then return end
    AH.dirty = true
    local gen = AH.drawGen
    C_Timer.After(AH.running and AH.DRAW_EVERY or 0, function()
        -- drawn since it was asked for: nothing left to do
        if AH.drawGen ~= gen then return end
        AH.Draw()
        if AH.bar then AH.SyncBar() end
    end)
end

function AH.ShowList()
    if not AH.list then return end
    AH.list:Show()
    -- the press shows at once: the button's words, the first status
    AH.Draw()
end

function AH.HideList()
    if AH.list then AH.list:Hide() end
    if AH.bar then AH.SyncBar() end
end

-- The auction house may already be loaded when this file loads (another addon opened it).
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    C_Timer.After(0, AH.Build)
end
