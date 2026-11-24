-- AD_LoadRules: the Level and Zone load rules every item's Load Conditions offer (rec.c.levelMin / levelMax, zoneMode / zones).
-- NS.Conditions asks it in the WHEN layer (Holds), so a record that fails goes inert and comes back at once, in combat too; its events arm only while a live record uses a rule.
-- UnitLevel, the zone texts and C_Map.GetBestMapForUnit are plain reads; a secret answer keeps the last plain one.
local ADDON, NS = ...
local CreateFrame = NS.Perf and NS.Perf.Frames("LoadRules") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames

local LR = {}
NS.LoadRules = LR

LR.LEVEL_MAX = 999
LR.ZONES_MAX = 12
LR.NAME_MAX = 60

-- the reads of this pass: level, best map, lower-cased zone texts
LR.now = { level = nil, map = nil, names = {} }
LR.last = {}
LR.used = false

local function Plain(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function Trim(s)
    return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function LR.Level()
    local v = UnitLevel and UnitLevel("player")
    if Plain(v) and type(v) == "number" and v > 0 then LR.last.level = v end
    local lv = LR.last.level
    -- PLAYER_LEVEL_UP arrives before UnitLevel says the new level
    if LR.lvlEv and (not lv or LR.lvlEv > lv) then lv = LR.lvlEv end
    return lv
end

-- No map (some instances, a loading screen) is no map, never the last one:
-- only a secret answer keeps the last plain map.
function LR.Map()
    local f = C_Map and C_Map.GetBestMapForUnit
    local v = f and f("player")
    if v == nil then
        LR.last.map = nil
    elseif Plain(v) and type(v) == "number" then
        LR.last.map = v
    end
    return LR.last.map
end

-- The floors of one dungeon, raid or city share a map group, so a map ID
-- picked on one floor holds on every floor. Map data never changes: kept.
LR.groups = {}
function LR.GroupOf(id)
    if type(id) ~= "number" then return nil end
    local g = LR.groups[id]
    if g == nil then
        local f = C_Map and C_Map.GetMapGroupID
        local v = f and f(id)
        g = (Plain(v) and type(v) == "number" and v > 0) and v or false
        if Plain(v) or v == nil then LR.groups[id] = g end
    end
    return g or nil
end

-- the zone, the real zone, the subzone and the minimap's place name
function LR.Names()
    local out = {}
    for i, fn in ipairs({ GetZoneText, GetRealZoneText, GetSubZoneText, GetMinimapZoneText }) do
        local v = fn and fn()
        if Plain(v) and type(v) == "string" then LR.last[i] = v end
        local s = LR.last[i]
        if s and s ~= "" then out[s:lower()] = true end
    end
    return out
end

-- A zone entry's name for the panel: a map ID by the map's own name.
function LR.EntryName(e)
    if type(e) == "number" then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(e)
        local nm = info and info.name
        if Plain(nm) and type(nm) == "string" and nm ~= "" then return nm end
        return NS.AT.Tr("Map %d"):format(e)
    end
    return tostring(e)
end

function LR.BeginPass()
    LR.used = false
    local n = LR.now
    n.level, n.map, n.names = LR.Level(), LR.Map(), LR.Names()
    n.group = LR.GroupOf(n.map)
end

local function LevelOf(c)
    local lo, hi = tonumber(c.levelMin), tonumber(c.levelMax)
    return lo, hi
end

local function ZonesOf(c)
    if (c.zoneMode ~= "in" and c.zoneMode ~= "out") or type(c.zones) ~= "table" or c.zones[1] == nil then
        return nil
    end
    return c.zoneMode, c.zones
end

function LR.Has(rec)
    local c = rec and rec.c
    if not c then return false end
    local lo, hi = LevelOf(c)
    return lo ~= nil or hi ~= nil or ZonesOf(c) ~= nil
end

function LR.Collect(c)
    if not LR.used and c and (c.levelMin or c.levelMax or ZonesOf(c)) then LR.used = true end
end

function LR.InZone(zones)
    local n = LR.now
    for _, e in ipairs(zones) do
        if type(e) == "number" then
            if n.map == e or (n.group and LR.GroupOf(e) == n.group) then return true end
        elseif n.names[tostring(e):lower()] then
            return true
        end
    end
    return false
end

-- The rule holds: level inside its range, the zone list as its mode says.
-- An unknown level never gates.
function LR.Holds(rec)
    local c = rec and rec.c
    if not c then return true end
    local lo, hi = LevelOf(c)
    local lv = LR.now.level
    if lv then
        if lo and lv < lo then return false end
        if hi and lv > hi then return false end
    end
    local mode, zones = ZonesOf(c)
    if mode then
        local inside = LR.InZone(zones)
        if mode == "in" and not inside then return false end
        if mode == "out" and inside then return false end
    end
    return true
end

-- Setters: whole levels 1 to LEVEL_MAX, nil = no limit; the other end moves
-- along so the range is never empty.
local function Lvl(v)
    v = tonumber(v)
    if not v then return nil end
    v = math.floor(v)
    if v < 1 then v = 1 elseif v > LR.LEVEL_MAX then v = LR.LEVEL_MAX end
    return v
end

local function Dirty(rec) NS.Store.Dirty("load", rec.id) end

function LR.SetLevelMin(rec, v)
    if not rec then return end
    v = Lvl(v)
    local c = rec.c
    if c.levelMin == v then return end
    c.levelMin = v
    if v and c.levelMax and c.levelMax < v then c.levelMax = v end
    Dirty(rec)
end

function LR.SetLevelMax(rec, v)
    if not rec then return end
    v = Lvl(v)
    local c = rec.c
    if c.levelMax == v then return end
    c.levelMax = v
    if v and c.levelMin and c.levelMin > v then c.levelMin = v end
    Dirty(rec)
end

function LR.SetZoneMode(rec, mode)
    if not rec then return end
    if mode ~= "in" and mode ~= "out" then mode = nil end
    if rec.c.zoneMode == mode then return end
    rec.c.zoneMode = mode
    Dirty(rec)
end

-- A zone entry from typed text: digits are a map ID, anything else a name.
function LR.Parse(s)
    if type(s) == "number" then
        return (s > 0) and math.floor(s) or nil
    end
    if type(s) ~= "string" then return nil end
    s = Trim(s)
    if s == "" then return nil end
    local id = s:match("^%d+$") and tonumber(s)
    if id then return (id > 0) and id or nil end
    return s:sub(1, LR.NAME_MAX)
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "string" then return a:lower() == b:lower() end
    return a == b
end

-- Adds an entry; false when it is empty, already listed or the list is full.
function LR.AddZone(rec, s)
    if not rec then return false end
    local e = LR.Parse(s)
    if not e then return false end
    local list = rec.c.zones or {}
    if #list >= LR.ZONES_MAX then return false end
    for _, have in ipairs(list) do
        if Same(have, e) then return false end
    end
    list[#list + 1] = e
    rec.c.zones = list
    Dirty(rec)
    return true
end

function LR.RemoveZone(rec, i)
    local list = rec and rec.c.zones
    if type(list) ~= "table" or not list[i] then return end
    table.remove(list, i)
    if list[1] == nil then rec.c.zones = nil end
    Dirty(rec)
end

-- Where you are, for the panel's add button: the best map, else the zone name.
function LR.Here()
    local id = LR.Map()
    if id then return id end
    local z = GetRealZoneText and GetRealZoneText()
    if Plain(z) and type(z) == "string" and z ~= "" then return z end
    return nil
end

-- Shape checks, called from Conditions.Normalize.
function LR.Normalize(c)
    if c.levelMin ~= nil then c.levelMin = Lvl(c.levelMin) end
    if c.levelMax ~= nil then c.levelMax = Lvl(c.levelMax) end
    if c.levelMin and c.levelMax and c.levelMin > c.levelMax then c.levelMax = c.levelMin end
    if c.zoneMode ~= nil and c.zoneMode ~= "in" and c.zoneMode ~= "out" then c.zoneMode = nil end
    if c.zones ~= nil then
        local out = {}
        if type(c.zones) == "table" then
            for _, e in ipairs(c.zones) do
                local v = LR.Parse(e)
                local dup = false
                for _, have in ipairs(out) do
                    if v ~= nil and Same(have, v) then dup = true end
                end
                if v ~= nil and not dup and #out < LR.ZONES_MAX then out[#out + 1] = v end
            end
        end
        c.zones = (out[1] ~= nil) and out or nil
    end
end

-- Events, armed only while a live record reads a rule.
LR.EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA" }
LR.frame = CreateFrame("Frame")
LR.armed = false
LR.frame:SetScript("OnEvent", function(_, e, a1, a2)
    -- the new level rides the event: PLAYER_LEVEL_UP (level), PLAYER_LEVEL_CHANGED (old, new)
    local nv = (e == "PLAYER_LEVEL_UP" and a1) or (e == "PLAYER_LEVEL_CHANGED" and a2) or nil
    if Plain(nv) and type(nv) == "number" and nv > 0 then LR.lvlEv = nv end
    if NS.Conditions then NS.Conditions.Queue() end
end)

function LR.Arm()
    if LR.used == LR.armed then return end
    LR.armed = LR.used
    for _, e in ipairs(LR.EVENTS) do
        if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
            if LR.used then LR.frame:RegisterEvent(e) else LR.frame:UnregisterEvent(e) end
        end
    end
end
