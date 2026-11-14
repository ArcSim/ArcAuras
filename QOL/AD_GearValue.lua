-- AD_GearValue: stat weight scales on gear tooltips. A scale is a name and one
-- weight per stat; each scale the player shows adds a line with the item's worth
-- and its change from what is worn in its slot. Read-only defaults ship per class,
-- the player's own scales are account-wide, and which scales show is kept per
-- character and talent group (Forever) or spec (retail). Item stats and tooltip
-- text are item data, plain in combat; a secret read prints no line.
local ADDON, NS = ...

local GV = {}
NS.GearValue = GV

GV.SETTING = "tooltipGearValue"
GV.LINE_COLOR = "|cff3fc9f2"
GV.UP_COLOR = "|cff40ff40"
GV.DOWN_COLOR = "|cffff5050"
GV.SAME_COLOR = "|cffa0a0a0"
GV.MAIN_HAND, GV.OFF_HAND = 16, 17
-- an off-hand weapon hits for half damage
GV.OFF_HAND_DPS = 0.5
GV.CACHE_CAP = 32

-- The stats a scale can weigh, per game, in the order the page lists them.
-- pct = weighed per 1%: Forever items give hit, crit and haste as rating the
-- client turns into a percent at the player's level (rating index, rating a 1%
-- when the client cannot say).
GV.STATS = {
    forever = {
        { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" },
        { "spi", "Spirit" }, { "ap", "Attack Power" }, { "sp", "Spell Power" },
        { "nature", "Nature spell power" }, { "fire", "Fire spell power" }, { "mp5", "MP5" },
        { "hit", "1% hit", pct = { 6, 10 } }, { "crit", "1% crit", pct = { 9, 14 } },
        { "haste", "1% haste", pct = { 18, 10 } }, { "dps", "Weapon DPS" }, { "pen", "Spell penetration" },
    },
    retail = {
        { "str", "Strength" }, { "agi", "Agility" }, { "int", "Intellect" }, { "sta", "Stamina" },
        { "crit", "Critical Strike" }, { "haste", "Haste" }, { "mastery", "Mastery" },
        { "vers", "Versatility" }, { "dps", "Weapon DPS" },
    },
}

-- The stat call's keys, folded into the names the weights use. Forever's melee
-- and spell variants of hit and crit count as the one stat.
GV.STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "nature", ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "fire",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
    ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
    ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
    ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
    ITEM_MOD_VERSATILITY = "vers",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "pen",
}

-- Equip lines in the client's words, lower case. Random suffixes and older
-- items give spell power, school damage and mana regen as equip spells, which
-- the stat call does not list. Patterns start at the line's start, so set
-- bonuses and Use lines never count.
GV.EQUIP = {
    prefix = "^equip:%s*",
    lines = {
        { "sp", "^increases damage and healing done by magical spells and effects by up to (%d+)" },
        { "sp", "^increases damage done by magical spells and effects by up to (%d+)" },
        { "sp", "^increases spell power by (%d+)" },
        -- healing and damage apart: only the damage part is spell power
        { "sp", "^increases healing done by up to %d+ and damage done by up to (%d+)" },
        { "nature", "^increases damage done by nature spells and effects by up to (%d+)" },
        { "nature", "^increases nature damage done by up to (%d+)" },
        { "fire", "^increases damage done by fire spells and effects by up to (%d+)" },
        { "fire", "^increases fire damage done by up to (%d+)" },
        { "mp5", "^restores (%d+) mana per 5 sec" },
        { "mp5", "^restores (%d+) mana every 5 sec" },
        { "ap", "^increases attack power by (%d+)" },
        { "ap", "^%+(%d+) attack power" },
        { "hit", "^increases your hit by (%d+)" },
        { "crit", "^increases your critical strike by (%d+)" },
        { "haste", "^increases your haste by (%d+)" },
        { "hit", "^improves spell hit by (%d+)" },
        { "crit", "^improves spell critical strike by (%d+)" },
        { "dps", "^%((%d+%.?%d*) damage per second%)" },
        { "pen", "^your spells pierce (%d+)" },
        { "pen", "^increases spell piercing by (%d+)" },
    },
}
-- a client language missing here values gear by the stat call alone
GV.EQUIP_BY_LOCALE = { enUS = GV.EQUIP, enGB = GV.EQUIP }

-- Read-only scales that ship, per game and class, from measured Forever play.
GV.DEFAULTS = {
    { id = "d-shaman-ele", game = "forever", class = "SHAMAN", name = "Elemental", spec = "Elemental",
        w = { sp = 1, nature = 0.95, fire = 0.1, int = 0.13, hit = 6.6, crit = 6.6, pen = 0.8 } },
    { id = "d-shaman-enh", game = "forever", class = "SHAMAN", name = "Enhancement", spec = "Enhancement",
        w = { ap = 1, str = 2, agi = 1.1, sp = 1.75, int = 1.53, hit = 18, crit = 21, haste = 14, dps = 14, pen = 1.39 } },
}

-- What a piece of gear replaces: its slots, and how they combine.
GV.SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12, weaker = true }, INVTYPE_TRINKET = { 13, 14, weaker = true },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON = { 16, 17, both = true },
    INVTYPE_SHIELD = { 17, offHand = true }, INVTYPE_WEAPONOFFHAND = { 17, offHand = true },
    INVTYPE_HOLDABLE = { 17, offHand = true },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- the client's words; English while the theme is not loaded
local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

function GV.Game()
    return NS.IsForever == true and "forever" or "retail"
end

function GV.Stats()
    return GV.STATS[GV.Game()]
end

-- The stat's row in this game's list, or nil.
function GV.StatInfo(key)
    for _, s in ipairs(GV.Stats()) do
        if s[1] == key then return s end
    end
    return nil
end

-- The player's class token, or nil.
function GV.ClassToken()
    local _, token = UnitClass("player")
    if Secret(token) or type(token) ~= "string" then return nil end
    return token
end

-- On only when switched on.
function GV.Enabled()
    local S = NS.Store
    return S ~= nil and S.GetSetting ~= nil and S.GetSetting(GV.SETTING) == true
end


-- The account-wide store: own scales by id and which scales show, per character
-- (GUID) and talent group. Nil before the saves load.
function GV.Data()
    local S = NS.Store
    local ui = S and S.UI and S.UI()
    if type(ui) ~= "table" then return nil end
    if type(ui.gearScales) ~= "table" then ui.gearScales = {} end
    if type(ui.gearShow) ~= "table" then ui.gearShow = {} end
    return ui
end

-- The player's scales in page order: this game's defaults for the class, then
-- the player's own for the class. Each entry is the scale itself; kind tells
-- which ("default" never changes, "own" does).
function GV.Scales()
    local out, cls, game = {}, GV.ClassToken(), GV.Game()
    for _, d in ipairs(GV.DEFAULTS) do
        if d.game == game and d.class == cls then
            d.kind = "default"
            out[#out + 1] = d
        end
    end
    local data = GV.Data()
    local own = {}
    for id, s in pairs(data and data.gearScales or {}) do
        if type(s) == "table" and s.class == cls and s.game == game then
            s.id, s.kind = id, "own"
            own[#own + 1] = s
        end
    end
    table.sort(own, function(a, b) return (a.n or 0) < (b.n or 0) end)
    for _, s in ipairs(own) do out[#out + 1] = s end
    return out
end

function GV.Get(id)
    for _, s in ipairs(GV.Scales()) do
        if s.id == id then return s end
    end
    return nil
end

-- A new scale of the player's own: a copy of `from`'s weights, or empty.
-- Returns its id; nil before the saves load.
function GV.NewScale(name, from)
    local data = GV.Data()
    if not data then return nil end
    data.gearNext = (tonumber(data.gearNext) or 0) + 1
    local n = data.gearNext
    local w = {}
    for k, v in pairs(from and from.w or {}) do w[k] = v end
    local id = "u" .. n
    data.gearScales[id] = { n = n, name = name, game = GV.Game(), class = (from and from.class) or GV.ClassToken(),
        spec = from and from.spec or nil, w = w }
    return id
end

local function Own(id)
    local data = GV.Data()
    local s = data and data.gearScales[id]
    if type(s) ~= "table" then return nil end
    return s
end

-- A weight of an own scale; 0 or less takes the stat off the scale.
function GV.SetWeight(id, key, v)
    local s = Own(id)
    if not (s and GV.StatInfo(key)) then return false end
    v = tonumber(v)
    if v == nil then return false end
    if type(s.w) ~= "table" then s.w = {} end
    s.w[key] = (v > 0) and v or nil
    return true
end

function GV.SetName(id, name)
    local s = Own(id)
    if not s or type(name) ~= "string" or name:match("^%s*$") then return false end
    s.name = name:match("^%s*(.-)%s*$")
    return true
end

function GV.SetSpec(id, spec)
    local s = Own(id)
    if not s then return false end
    s.spec = spec
    return true
end

function GV.Delete(id)
    local data = GV.Data()
    if not (data and data.gearScales[id]) then return false end
    data.gearScales[id] = nil
    for _, groups in pairs(data.gearShow) do
        if type(groups) == "table" then
            for _, set in pairs(groups) do
                if type(set) == "table" then set[id] = nil end
            end
        end
    end
    return true
end


-- The active talent group (Forever, 1 or 2) or spec (retail); nil when unread.
function GV.Group()
    local g
    if GV.Game() == "retail" then
        g = GetSpecialization and GetSpecialization()
    elseif C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        g = C_SpecializationInfo.GetActiveSpecGroup()
    elseif GetActiveTalentGroup then
        g = GetActiveTalentGroup()
    else
        g = 1
    end
    if Secret(g) or type(g) ~= "number" then return nil end
    return g
end

local function Me()
    local g = UnitGUID and UnitGUID("player")
    if Secret(g) or type(g) ~= "string" or g == "" then return nil end
    return g
end

-- The group's show set, or nil while none is kept (then the defaults show).
local function ShowSet(g, create)
    local data, me = GV.Data(), Me()
    if not (data and me and g) then return nil end
    local mine = data.gearShow[me]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        data.gearShow[me] = mine
    end
    local set = mine[g]
    if type(set) ~= "table" then
        if not create then return nil end
        set = {}
        for _, s in ipairs(GV.Scales()) do
            if s.kind == "default" then set[s.id] = true end
        end
        mine[g] = set
    end
    return set
end

function GV.Shown(g, id)
    local set = ShowSet(g, false)
    if set then return set[id] == true end
    local s = GV.Get(id)
    return s ~= nil and s.kind == "default"
end

function GV.SetShown(g, id, on)
    local set = ShowSet(g, true)
    if not set then return false end
    set[id] = on and true or nil
    return true
end

-- The scales shown for a group, in page order.
function GV.ShownScales(g)
    local out = {}
    for _, s in ipairs(GV.Scales()) do
        if GV.Shown(g, s.id) then out[#out + 1] = s end
    end
    return out
end


function GV.EquipWords()
    local loc = GetLocale and GetLocale()
    if loc == nil then return GV.EQUIP end
    return GV.EQUIP_BY_LOCALE[loc]
end

local function Plain(t)
    local s = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    return s
end

-- The stats an item's lines give; nil when the lines cannot be read (one reads
-- secret, or this client has no patterns).
function GV.FromLines(lines)
    local E = GV.EquipWords()
    if not E or type(lines) ~= "table" or Secret(lines) then return nil end
    local out = {}
    for _, line in ipairs(lines) do
        local t = type(line) == "table" and line.leftText or nil
        if Secret(t) then return nil end
        if type(t) == "string" then
            local s = Plain(t):gsub(E.prefix, "")
            for _, p in ipairs(E.lines) do
                local n = tonumber(s:match(p[2]))
                if n then
                    out[p[1]] = (out[p[1]] or 0) + n
                    break
                end
            end
        end
    end
    return out
end

-- An item's stats: the stat call, then the equip lines, the larger of the two
-- for each stat, so a bonus both report counts once. Returns the stats and
-- whether anything was read at all.
function GV.ItemStats(link, lines)
    local out, any = {}, false
    if Secret(link) or type(link) ~= "string" then return out, false end
    local get = C_Item and C_Item.GetItemStats
    local raw = get and get(link)
    if raw ~= nil and not Secret(raw) and type(raw) == "table" then
        for k, v in pairs(raw) do
            if not Secret(v) and type(v) == "number" then
                any = true
                local s = GV.STAT_KEYS[k]
                if s then out[s] = (out[s] or 0) + v end
            end
        end
    end
    local text = GV.FromLines(lines)
    if text then
        for s, v in pairs(text) do
            any = true
            if v > (out[s] or 0) then out[s] = v end
        end
    end
    return out, any
end


-- An amount of a stat in the unit its weight is per: rating turned into a percent
-- for a stat weighed per 1%.
function GV.Amount(key, n)
    local info = GV.StatInfo(key)
    if not (info and info.pct) then return n end
    local get = GetCombatRatingBonusForCombatRatingValue
    local pct = get and get(info.pct[1], n)
    if Secret(pct) or type(pct) ~= "number" then return n / info.pct[2] end
    return pct
end

-- An item's worth to a scale: each stat x its weight; dpsShare scales weapon
-- damage (an off hand hits for half).
function GV.Worth(stats, scale, dpsShare)
    local v, w = 0, scale.w or {}
    for k, n in pairs(stats) do
        local each = w[k]
        if each and type(n) == "number" then
            if k == "dps" then n = n * (dpsShare or 1) end
            v = v + GV.Amount(k, n) * each
        end
    end
    return v
end

-- The unit a scale's numbers read in: the stat it weighs at 1, else none.
GV.UNITS = { { "sp", "SP" }, { "ap", "AP" }, { "str", "Str" }, { "agi", "Agi" }, { "int", "Int" } }
function GV.Unit(scale)
    local w = scale.w or {}
    for _, u in ipairs(GV.UNITS) do
        if w[u[1]] == 1 then return u[2] end
    end
    return nil
end


function GV.EquipLoc(link)
    local get = C_Item and C_Item.GetItemInfoInstant
    if not get then return nil end
    local _, _, _, loc = get(link)
    if Secret(loc) or type(loc) ~= "string" then return nil end
    return loc
end

local wornCache, wornCount = {}, 0

-- A worn item's link and stats. Stats are kept by link, which changes with
-- the item. Returns nil for an empty slot, false when the slot reads secret.
function GV.Worn(slot)
    local link = GetInventoryItemLink("player", slot)
    if Secret(link) then return false end
    if type(link) ~= "string" then return nil end
    local stats = wornCache[link]
    if stats then return link, stats end
    local get = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    local data = get and get("player", slot)
    local lines = (not Secret(data) and type(data) == "table") and data.lines or nil
    local any
    stats, any = GV.ItemStats(link, lines)
    if any then
        if wornCount >= GV.CACHE_CAP then wornCache, wornCount = {}, 0 end
        wornCache[link] = stats
        wornCount = wornCount + 1
    end
    return link, stats
end

-- Two links name the same item when their item ID and random suffix match: a
-- comparison tooltip's link can differ from the worn one in its other fields,
-- or name the item by its ID alone.
function GV.SameItem(a, b)
    if a == b then return true end
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local ia, ib = a:match("item:(%-?%d+)"), b:match("item:(%-?%d+)")
    if ia == nil or ia ~= ib then return false end
    local SUFFIX = "item:%-?%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]*)"
    local sa, sb = a:match(SUFFIX), b:match(SUFFIX)
    if sa == nil or sb == nil then return true end
    return sa == sb
end

function GV.DualWielding()
    local link = GV.Worn(GV.OFF_HAND)
    if not link then return false end
    local loc = GV.EquipLoc(link)
    return loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND"
end

-- Spells that let the player hold a weapon in each hand.
GV.DUAL_WIELD = { 674, 30798 }
function GV.CanDualWield()
    if GV.DualWielding() then return true end
    local catalog = NS.SpellCatalog
    if not (catalog and catalog.Known) then return false end
    for _, id in ipairs(GV.DUAL_WIELD) do
        if catalog.Known(id) then return true end
    end
    return false
end

-- The ways an item can go on: each takes the items in `take` off and lands in
-- `hand` (an off hand hits for half). Rings, trinkets and, for a player who
-- can dual wield, one-hand weapons have two.
function GV.Options(slots, loc)
    if slots.weaker then return { { take = { slots[1] } }, { take = { slots[2] } } } end
    if slots.both then return { { take = { GV.MAIN_HAND, GV.OFF_HAND } } } end
    if slots.offHand then
        local main = GV.Worn(GV.MAIN_HAND)
        if main and GV.EquipLoc(main) == "INVTYPE_2HWEAPON" then
            return { { take = { GV.MAIN_HAND }, hand = GV.OFF_HAND } }
        end
        return { { take = { GV.OFF_HAND }, hand = GV.OFF_HAND } }
    end
    if loc == "INVTYPE_WEAPON" and GV.CanDualWield() then
        return { { take = { GV.MAIN_HAND } }, { take = { GV.OFF_HAND }, hand = GV.OFF_HAND } }
    end
    return { { take = { slots[1] } } }
end

local function Share(slot)
    return (slot == GV.OFF_HAND) and GV.OFF_HAND_DPS or 1
end

-- The best swap for one scale: each place values what it takes off (each worn
-- piece where it sits), and the largest change wins. Returns the worth, the
-- change (nil when there is nothing to compare: the item is the one worn, or a
-- slot reads secret), whether the place is empty, and the replaced item's name
-- when there was a choice.
function GV.BestSwap(stats, link, slots, loc, scale)
    local options = GV.Options(slots, loc)
    for _, opt in ipairs(options) do
        for _, slot in ipairs(opt.take) do
            local wl = GV.Worn(slot)
            if wl == false then return GV.Worth(stats, scale, Share(opt.hand)) end
            if wl and GV.SameItem(wl, link) then return GV.Worth(stats, scale, Share(slot)) end
        end
    end
    local best
    for _, opt in ipairs(options) do
        local was, empty, name = 0, true, nil
        for _, slot in ipairs(opt.take) do
            local wl, ws = GV.Worn(slot)
            if wl then
                empty = false
                name = wl:match("%[(.-)%]")
                was = was + GV.Worth(ws, scale, Share(slot))
            end
        end
        local v = GV.Worth(stats, scale, Share(opt.hand))
        if not best or v - was > best.v - best.was then
            best = { v = v, was = was, empty = empty, name = name }
        end
    end
    return best.v, best.v - best.was, best.empty, (#options > 1 and not best.empty) and best.name or nil
end


-- A whole number, or one decimal for a small value that would round to 0.
function GV.Num(v)
    local a = math.abs(v)
    if a > 0 and a < 0.5 then return string.format("%.1f", v) end
    local n = math.floor(a + 0.5)
    return string.format("%d", v < 0 and -n or n)
end

-- One scale's line: "Elemental: 22 SP (-3 vs worn)"; the change and its words
-- are each one sentence to translate; name = the item it replaces, when it
-- could go in two places.
function GV.Line(scale, v, delta, empty, name)
    local unit = GV.Unit(scale)
    local s = GV.LINE_COLOR .. scale.name .. ": " .. GV.Num(v) .. (unit and (" " .. Tr(unit)) or "") .. "|r"
    if delta == nil then return s end
    local col, sign = GV.SAME_COLOR, ""
    if math.abs(delta) < 0.05 then
        delta = 0
    elseif delta > 0 then
        col, sign = GV.UP_COLOR, "+"
    else
        col = GV.DOWN_COLOR
    end
    local n = sign .. GV.Num(delta)
    local vs
    if empty then
        vs = Tr("(%s vs empty)"):format(n)
    elseif name then
        vs = Tr("(%s vs %s)"):format(n, name)
    else
        vs = Tr("(%s vs worn)"):format(n)
    end
    return s .. " " .. col .. vs .. "|r"
end

-- The lines for one item and a list of scales, or nil when it has nothing to
-- value (not gear, no stats read, no scale).
function GV.LinesFor(link, lines, scales)
    if #scales == 0 then return nil end
    local loc = GV.EquipLoc(link)
    local slots = loc and GV.SLOTS[loc]
    if not slots then return nil end
    local stats, any = GV.ItemStats(link, lines)
    if not any then return nil end
    local out = {}
    for _, scale in ipairs(scales) do
        local v, delta, empty, name = GV.BestSwap(stats, link, slots, loc, scale)
        out[#out + 1] = GV.Line(scale, v, delta, empty, name)
    end
    return out
end

-- The lines the active group shows.
function GV.Lines(link, lines)
    local g = GV.Group()
    if not g then return nil end
    return GV.LinesFor(link, lines, GV.ShownScales(g))
end


-- The weights string: ( Tool: v1: "Name": Class=Shaman, Key=Value, ... ), the
-- one simulators write. Ratings are per point in it; a stat weighed per 1% here
-- is turned at the player's level.
GV.SHARE_NAMES = {
    forever = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "Ap",
        sp = "SpellDamage", nature = "NatureDamage", fire = "FireDamage", mp5 = "Mp5", hit = "HitRating",
        crit = "CritRating", haste = "HasteRating", dps = "MeleeDps", pen = "SpellPenetration" },
    retail = { str = "Strength", agi = "Agility", int = "Intellect", sta = "Stamina", crit = "CritRating",
        haste = "HasteRating", mastery = "MasteryRating", vers = "Versatility", dps = "MeleeDps" },
}
GV.CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    DEATHKNIGHT = "DeathKnight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", MONK = "Monk",
    DRUID = "Druid", DEMONHUNTER = "DemonHunter", EVOKER = "Evoker" }

-- A percent a rating point gives for a stat weighed per 1% (1 for others).
local function PerPoint(key)
    local info = GV.StatInfo(key)
    if not (info and info.pct) then return 1 end
    return GV.Amount(key, 1)
end

local function Short(v)
    local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

function GV.Export(scale)
    local names = GV.SHARE_NAMES[GV.Game()]
    local parts = { "Class=" .. (GV.CLASS_NAMES[scale.class] or tostring(scale.class)) }
    if scale.spec then parts[#parts + 1] = "Spec=" .. scale.spec end
    for _, s in ipairs(GV.Stats()) do
        local w = scale.w and scale.w[s[1]]
        if w and names[s[1]] then parts[#parts + 1] = names[s[1]] .. "=" .. Short(w * PerPoint(s[1])) end
    end
    -- the word goes in as an argument: the format itself holds no words to translate
    return string.format('( %s: v1: "%s": %s )', "ArcAuras", (scale.name or ""):gsub('"', "'"), table.concat(parts, ", "))
end

-- A weights string read into a new scale of the player's own. Returns its id,
-- or nil and why.
function GV.Import(text)
    if type(text) ~= "string" then return nil, "empty" end
    local name, body = text:match('^%s*%(%s*[%w_]+%s*:%s*v%d+%s*:%s*"([^"]+)"%s*:(.-)%)%s*$')
    if not name then return nil, "format" end
    local byName = {}
    for k, n in pairs(GV.SHARE_NAMES[GV.Game()]) do byName[n:lower()] = k end
    byName.dps = "dps"
    local cls, spec, w, n = nil, nil, {}, 0
    for pair in (body .. ","):gmatch("([^,]*),") do
        local k, v = pair:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "Class" then
            for token, word in pairs(GV.CLASS_NAMES) do
                if word:lower() == v:lower() then cls = token end
            end
        elseif k == "Spec" then
            spec = v
        elseif k then
            local key, num = byName[k:lower()], tonumber(v)
            if key and num and num > 0 then
                w[key] = num / PerPoint(key)
                n = n + 1
            end
        end
    end
    if n == 0 then return nil, "weights" end
    local id = GV.NewScale(name, { w = w, class = cls or GV.ClassToken(), spec = spec })
    if not id then return nil, "saves" end
    return id
end


-- One block per tooltip build: OnTooltipCleared resets it.
local function Clear(tooltip)
    tooltip._adGearDone = nil
end

-- The hovered item's full link. A bag item's tooltip names it by its GUID, not
-- a link, and its ID alone loses the random suffix and all the stats it gives.
-- nil when the link reads secret.
function GV.ItemLink(data)
    local guid = data.guid
    local byGuid = C_Item and C_Item.GetItemLinkByGUID
    if byGuid and guid ~= nil and not Secret(guid) then
        local link = byGuid(guid)
        if type(link) == "string" and not Secret(link) and link ~= "" then return link end
    end
    local link = data.hyperlink
    if Secret(link) then return nil end
    if type(link) == "string" and link ~= "" then return link end
    return "item:" .. tostring(data.id)
end

-- The lines a tooltip shows: the active group's, unless the page's preview asks
-- for another group's (tooltip._adGearGroup).
function GV.Append(tooltip, data)
    if not GV.Enabled() or not tooltip or not data then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local id = data.id
    if id == nil or Secret(id) then return end
    if tooltip._adGearDone == id then return end
    local link = GV.ItemLink(data)
    if link == nil then return end
    local g = tooltip._adGearGroup or GV.Group()
    if not g then return end
    local out = GV.LinesFor(link, data.lines, GV.ShownScales(g))
    if not out then return end
    tooltip._adGearDone = id
    if not tooltip._adGearHooked and tooltip.HookScript then
        tooltip._adGearHooked = true
        if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") then
            tooltip:HookScript("OnTooltipCleared", Clear)
        end
        tooltip:HookScript("OnHide", Clear)
    end
    tooltip:AddLine(" ")
    for _, line in ipairs(out) do tooltip:AddLine(line, 1, 1, 1) end
    tooltip:Show()
end

-- Registered at load, before the ID block (installed at PLAYER_ENTERING_WORLD),
-- so the lines sit above it; each call asks the switch first.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, GV.Append)
end
