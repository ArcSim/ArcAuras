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

-- Read-only scales that ship, per game and class: { id, game, class, name, spec, w }.
-- None yet: measured numbers stay the measuring player's own scales.
GV.DEFAULTS = {}

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

-- A new scale of the player's own: a copy of `from`'s weights and goals, or
-- empty. Returns its id; nil before the saves load.
function GV.NewScale(name, from)
    local data = GV.Data()
    if not data then return nil end
    data.gearNext = (tonumber(data.gearNext) or 0) + 1
    local n = data.gearNext
    local w = {}
    for k, v in pairs(from and from.w or {}) do w[k] = v end
    local id = "u" .. n
    data.gearScales[id] = { n = n, name = name, game = GV.Game(), class = (from and from.class) or GV.ClassToken(),
        spec = from and from.spec or nil, w = w, goals = GV.CopyGoals(from and from.goals),
        extras = GV.CopyExtras(from and from.extras), dps = GV.CopyDps(from and from.dps) }
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


-- Goals: part of a scale, like its weights. Each is an amount of a stat to
-- reach; the scale counts that stat only up to it. Regen (Forever) is the worn
-- gear's MP5 with Spirit and Intellect at their rates; hit is the character's
-- whole hit chance, talents and auras too (cr = the rating, total = which
-- modifier); every other goal is the worn gear's stat in the unit its weight is
-- per. Goal 0 is off. Kept as scale.goals[kind].
GV.GOAL_RATES = { spi = 0.5, int = 0.075 }
GV.GOAL_SLOTS = 18
GV.GOAL_KINDS = {
    forever = {
        { key = "regen", step = 1 },
        { key = "spellhit", stat = "hit", cr = 8, total = "spell", step = 1 },
        { key = "meleehit", stat = "hit", cr = 6, total = "melee", step = 1 },
        { key = "crit", stat = "crit", step = 1 }, { key = "haste", stat = "haste", step = 1 },
        { key = "pen", stat = "pen", step = 5 },
    },
    retail = {
        { key = "crit", stat = "crit", step = 50 }, { key = "haste", stat = "haste", step = 50 },
        { key = "mastery", stat = "mastery", step = 50 }, { key = "vers", stat = "vers", step = 50 },
    },
}

function GV.GoalKinds()
    return GV.GOAL_KINDS[GV.Game()]
end

function GV.GoalKind(key)
    for _, k in ipairs(GV.GoalKinds()) do
        if k.key == key then return k end
    end
    return nil
end

function GV.GoalName(key)
    if key == "regen" then return Tr("Regen") end
    if GV.Game() == "retail" then
        local names = { crit = Tr("Critical Strike"), haste = Tr("Haste"), mastery = Tr("Mastery"),
            vers = Tr("Versatility") }
        return names[key] or key
    end
    local names = { spellhit = Tr("Spell hit"), meleehit = Tr("Melee hit"), crit = Tr("Crit"), haste = Tr("Haste"),
        pen = Tr("Spell penetration") }
    return names[key] or key
end

-- The character's whole hit chance for a hit goal, as the character sheet adds
-- it: the rating's percent and the talent / aura modifier. nil while either
-- reads secret (unit stats can be restricted).
function GV.TotalOf(kind)
    local bonus = GetCombatRatingBonus and GetCombatRatingBonus(kind.cr)
    local get = (kind.total == "spell") and GetSpellHitModifier or GetHitModifier
    local mod = get and get()
    if Secret(bonus) or Secret(mod) or type(bonus) ~= "number" or type(mod) ~= "number" then return nil end
    return bonus + mod
end

-- What follows a goal's number: MP5, a percent sign, or nothing (rating, points).
function GV.GoalUnit(key)
    if key == "regen" then return " " .. Tr("MP5") end
    local k = GV.GoalKind(key)
    local info = k and k.stat and GV.StatInfo(k.stat)
    if info and info.pct then return "%" end
    return ""
end

-- A goal's number: one decimal for a percent (hit lands on fractions), whole otherwise.
function GV.GoalNum(v, key)
    if GV.GoalUnit(key) == "%" and math.abs(v) >= 0.5 then
        local s = string.format("%.1f", v):gsub("%.0$", "")
        return s
    end
    return GV.Num(v)
end

-- A scale's goal and rates, kept or not (the page shows them while off).
function GV.GoalSettings(scale, key)
    local all = scale and scale.goals
    local r = type(all) == "table" and type(all[key]) == "table" and all[key] or {}
    return { kind = key, goal = tonumber(r.goal) or 0, spi = tonumber(r.spi) or GV.GOAL_RATES.spi,
        int = tonumber(r.int) or GV.GOAL_RATES.int }
end

-- A scale's goal in force; nil while off or when this game has no such goal.
function GV.Goal(scale, key)
    if not (scale and GV.GoalKind(key)) then return nil end
    local s = GV.GoalSettings(scale, key)
    if s.goal <= 0 then return nil end
    return s
end

-- Every goal in force on a scale, in the page's order.
function GV.Goals(scale)
    local out = {}
    for _, k in ipairs(GV.GoalKinds()) do
        local s = GV.Goal(scale, k.key)
        if s then out[#out + 1] = s end
    end
    return out
end

-- A goal of an own scale (rates on regen only).
function GV.SetGoal(id, key, field, v)
    v = tonumber(v)
    local s = Own(id)
    if not (s and v and GV.GoalKind(key)) then return false end
    if not (field == "goal" or (key == "regen" and (field == "spi" or field == "int"))) then return false end
    if type(s.goals) ~= "table" then s.goals = {} end
    if type(s.goals[key]) ~= "table" then s.goals[key] = {} end
    s.goals[key][field] = math.max(0, v)
    return true
end

-- A copy of a goals table: plain numbers per kind, nothing shared.
function GV.CopyGoals(goals)
    if type(goals) ~= "table" then return nil end
    local out
    for kind, t in pairs(goals) do
        if type(t) == "table" then
            out = out or {}
            out[kind] = { goal = tonumber(t.goal), spi = tonumber(t.spi), int = tonumber(t.int) }
        end
    end
    return out
end

-- Which goals get a line under a tooltip's block, account-wide: none until the player ticks one. The goals count
-- toward the worth either way; this only shows or hides their lines.
function GV.GoalLineOn(kind)
    local data = GV.Data()
    local t = data and data.gearGoalLines
    return type(t) == "table" and t[kind] == true
end

function GV.SetGoalLine(kind, on)
    local data = GV.Data()
    if not (data and GV.GoalKind(kind)) then return false end
    if type(data.gearGoalLines) ~= "table" then data.gearGoalLines = {} end
    data.gearGoalLines[kind] = on and true or nil
    return true
end

-- What an item's stats give toward a goal.
function GV.AmountOf(stats, goal)
    if goal.kind == "regen" then
        return (stats.mp5 or 0) + goal.spi * (stats.spi or 0) + goal.int * (stats.int or 0)
    end
    local k = GV.GoalKind(goal.kind)
    local n = k and stats[k.stat]
    if type(n) ~= "number" then return 0 end
    return GV.Amount(k.stat, n, k.cr)
end

-- Where a goal stands now: the character's whole hit for a hit goal, else what
-- the worn gear gives. nil when something reads secret.
-- GV.wornMemo: a caller valuing many items in one go (the auction finder, a frame at a time) sets a table here, so
-- each goal's worn amount is added up once for the lot; it clears it after.
function GV.WornAmount(goal)
    local memo, key = GV.wornMemo, nil
    if type(memo) == "table" then
        key = tostring(goal.kind) .. ":" .. tostring(goal.spi) .. ":" .. tostring(goal.int)
        local m = memo[key]
        if m ~= nil then return m or nil end
    end
    local k = GV.GoalKind(goal.kind)
    local sum
    if k and k.total then
        sum = GV.TotalOf(k)
    else
        sum = 0
        for slot = 1, GV.GOAL_SLOTS do
            local link, stats = GV.Worn(slot)
            if link == false then
                sum = nil
                break
            end
            if link and stats then sum = sum + GV.AmountOf(stats, goal) end
        end
    end
    if key then memo[key] = sum or false end
    return sum
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
-- for a stat weighed per 1%; cr = another rating to turn it by (spell hit).
function GV.Amount(key, n, cr)
    local info = GV.StatInfo(key)
    if not (info and info.pct) then return n end
    local get = GetCombatRatingBonusForCombatRatingValue
    local pct = get and get(cr or info.pct[1], n)
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

-- The part of a scale's worth a goal's stats make. Regen: Spirit and MP5 at
-- their weights, and of Intellect its rate times what one MP5 is worth to the
-- scale (the rest of its weight, its crit, is not regen).
local function GoalPart(stats, scale, goal)
    local w = scale.w or {}
    if goal.kind ~= "regen" then
        local k = GV.GoalKind(goal.kind)
        local n = k and stats[k.stat]
        if type(n) ~= "number" then return 0 end
        return GV.Amount(k.stat, n) * (w[k.stat] or 0)
    end
    local perMp5 = w.mp5 or 0
    if perMp5 <= 0 and goal.spi > 0 then perMp5 = (w.spi or 0) / goal.spi end
    local intPart = math.min(w.int or 0, goal.int * perMp5)
    return (stats.spi or 0) * (w.spi or 0) + (stats.mp5 or 0) * (w.mp5 or 0) + (stats.int or 0) * intPart
end

-- Pieces' worth with goals: list = { { stats, dpsShare }, ... }, bases[i] = what
-- the worn gear gives toward goals[i] without them. Each goal's stats count only
-- the part below it, so past it they count nothing and a piece that drops the
-- worn amount under it loses that part.
local function GoalWorth(list, scale, goals, bases)
    local v = 0
    for _, it in ipairs(list) do v = v + GV.Worth(it[1], scale, it[2]) end
    for i, goal in ipairs(goals) do
        local part, e = 0, 0
        for _, it in ipairs(list) do
            part = part + GoalPart(it[1], scale, goal)
            e = e + GV.AmountOf(it[1], goal)
        end
        if part ~= 0 and e ~= 0 then
            local base = bases[i]
            local counted = math.min(base + e, goal.goal) - math.min(base, goal.goal)
            v = v - part + part * counted / e
        end
    end
    return v
end

-- Extras: what the player puts on things stats cannot say, per scale and in its
-- unit: an item's effect (a Use, a chance on hit, an Equip line no stat pattern
-- reads) and a set's bonuses by pieces worn. Only what the player adds.
-- scale.extras = { items = { [itemID] = value or true },
--   sets = { [setID] = { item = a piece's itemID, [pieces] = value } } };
-- true or no value: the number reads from the words where it can, else 0.

function GV.ItemID(link)
    if type(link) ~= "string" or Secret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function Clean(t)
    local s = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end

-- An item's effect lines in its own words: Use, Chance on, and Equip lines no
-- stat pattern reads.
function GV.EffectLines(lines)
    local E = GV.EquipWords()
    local out = {}
    if type(lines) ~= "table" or Secret(lines) then return out end
    for _, line in ipairs(lines) do
        local t = type(line) == "table" and line.leftText or nil
        if type(t) == "string" and not Secret(t) then
            local p = Plain(t)
            local fx = p:find("^use:") ~= nil or p:find("^chance on") ~= nil
            if not fx and p:find("^equip:") then
                fx = true
                local s = E and p:gsub(E.prefix, "") or p
                for _, pat in ipairs(E and E.lines or {}) do
                    if s:find(pat[2]) then
                        fx = false
                        break
                    end
                end
            end
            if fx then out[#out + 1] = Clean(t) end
        end
    end
    return out
end

-- A set's bonuses from a piece's lines: "(3) Set: ..." -> { { at = 3, text }, ... }.
function GV.SetBonuses(lines)
    local out = {}
    if type(lines) ~= "table" or Secret(lines) then return out end
    for _, line in ipairs(lines) do
        local t = type(line) == "table" and line.leftText or nil
        if type(t) == "string" and not Secret(t) then
            local at, text = Clean(t):match("^%((%d+)%)%s*[^:]+:%s*(.+)$")
            if at then out[#out + 1] = { at = tonumber(at), text = text } end
        end
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

-- How many pieces a set has, from a piece's "Name (n/N)" line; nil when unread.
function GV.SetSize(lines)
    if type(lines) ~= "table" or Secret(lines) then return nil end
    for _, line in ipairs(lines) do
        local t = type(line) == "table" and line.leftText or nil
        if type(t) == "string" and not Secret(t) then
            local n = Clean(t):match("^[^%(]+%(%d+/(%d+)%)%s*$")
            if n then return tonumber(n) end
        end
    end
    return nil
end

-- The set an item belongs to; nil for none or unread. Kept by item once read: the game forgets items after a big
-- auction search, and a piece listed then is valued later.
GV.setOf = {}
function GV.SetOf(link)
    if type(link) ~= "string" or Secret(link) then return nil end
    local key = GV.ItemID(link)
    local had = key and GV.setOf[key]
    if had ~= nil then return had or nil end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get or get(link) == nil then return nil end
    local id = select(16, get(link))
    if Secret(id) then return nil end
    local v = (type(id) == "number" and id ~= 0) and id or false
    if key then GV.setOf[key] = v end
    return v or nil
end

-- The stat words name, as the equip patterns read it: key and amount, or nil.
function GV.StatOfText(text)
    local E = GV.EquipWords()
    if not (E and type(text) == "string") then return nil end
    local s = Plain(text):gsub(E.prefix, "")
    for _, pat in ipairs(E.lines) do
        local v = tonumber(s:match(pat[2]))
        if v then return pat[1], v end
    end
    return nil
end

-- What words give by themselves on a scale: a stat line the equip patterns
-- read, or a Use that raises spell power averaged over its cooldown; nil when
-- nothing reads.
GV.USE_SP = {
    "^use: increases damage and healing done by magical spells and effects by up to (%d+) for (%d+) sec",
    "^use: increases spell power by (%d+) for (%d+) sec",
}
function GV.AutoOf(scale, text)
    if type(text) ~= "string" then return nil end
    local p = Plain(text)
    for _, pat in ipairs(GV.USE_SP) do
        local n, d = p:match(pat)
        -- the cooldown in its own brackets: "(1 min, 30 sec cooldown)"
        local cd = n and p:match("%(([^%)]-cooldown)%)")
        if cd then
            local every = (tonumber(cd:match("(%d+) min")) or 0) * 60 + (tonumber(cd:match("(%d+) sec")) or 0)
            if every > 0 then
                return tonumber(n) * math.min(tonumber(d), every) / every * ((scale.w or {}).sp or 0)
            end
        end
    end
    local key, v = GV.StatOfText(text)
    if key then return GV.Worth({ [key] = v }, scale) end
    return nil
end

local function ExtrasOf(s, create)
    if type(s.extras) ~= "table" then
        if not create then return nil end
        s.extras = {}
    end
    local x = s.extras
    if type(x.items) ~= "table" then x.items = {} end
    if type(x.sets) ~= "table" then x.sets = {} end
    return x
end

-- A scale's extras to read: { items, sets }, empty when it has none.
function GV.Extras(scale)
    local x = scale and scale.extras
    if type(x) ~= "table" then return { items = {}, sets = {} } end
    return { items = type(x.items) == "table" and x.items or {}, sets = type(x.sets) == "table" and x.sets or {} }
end

-- An item on an own scale's list: v a number types its value, true reads it from
-- its words, nil takes it off.
function GV.SetItemExtra(id, itemID, v)
    local s = Own(id)
    if not (s and type(itemID) == "number") then return false end
    if v ~= nil and v ~= true then
        v = tonumber(v)
        if not v then return false end
        v = math.max(0, v)
    end
    ExtrasOf(s, true).items[itemID] = v
    return true
end

-- A set on an own scale's list, known by one of its pieces; nil itemID takes it off.
function GV.SetSetExtra(id, setID, itemID)
    local s = Own(id)
    if not (s and type(setID) == "number") then return false end
    local sets = ExtrasOf(s, true).sets
    if itemID == nil then
        sets[setID] = nil
    else
        sets[setID] = sets[setID] or {}
        sets[setID].item = itemID
    end
    return true
end

-- A set bonus's typed value; nil reads it from its words again.
function GV.SetBonusValue(id, setID, at, v)
    local s = Own(id)
    local x = s and ExtrasOf(s, false)
    local set = x and x.sets[setID]
    if not (set and type(at) == "number") then return false end
    if v ~= nil then
        v = tonumber(v)
        if not v then return false end
        v = math.max(0, v)
    end
    set[at] = v
    return true
end

local function LinesOfLink(link)
    local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    local data = get and type(link) == "string" and get(link)
    return (not Secret(data) and type(data) == "table") and data.lines or nil
end

-- An item's extra on a scale: its typed value, else what its effect lines read,
-- else 0. Returns the value, whether it was typed, and whether its words read.
function GV.ItemExtra(scale, link, lines)
    local id = GV.ItemID(link)
    local e = id and GV.Extras(scale).items[id]
    if e == nil then return 0, false, false end
    if type(e) == "number" then return e, true, false end
    local auto
    for _, t in ipairs(GV.EffectLines(lines or LinesOfLink(link))) do
        local a = GV.AutoOf(scale, t)
        if a then auto = (auto or 0) + a end
    end
    return auto or 0, false, auto ~= nil
end

-- A listed set's bonuses on a scale, from its piece's lines: { { at, text, value,
-- typed, read } }; empty while the piece is not loaded.
function GV.SetBonusList(scale, setID)
    local set = GV.Extras(scale).sets[setID]
    if type(set) ~= "table" or not set.item then return {} end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link = get and select(2, get(set.item))
    local out = {}
    for _, b in ipairs(GV.SetBonuses(LinesOfLink(link))) do
        local typed = type(set[b.at]) == "number"
        local auto = GV.AutoOf(scale, b.text)
        out[#out + 1] = { at = b.at, text = b.text, value = typed and set[b.at] or (auto or 0), typed = typed, read = auto ~= nil }
    end
    return out
end

-- How many pieces of each set are worn.
function GV.WornSetCounts()
    local out = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        local s = GV.SetOf(link)
        if s then out[s] = (out[s] or 0) + 1 end
    end
    return out
end

-- The set bonuses' change from a swap: for each listed set it touches, the pieces
-- worn before and after (the new piece in, the taken ones out), and the values of
-- the bonuses crossed.
function GV.SetDelta(scale, link, takenLinks)
    local sets = GV.Extras(scale).sets
    if not next(sets) then return 0 end
    local touched = {}
    local mine = GV.SetOf(link)
    if mine and sets[mine] then touched[mine] = 1 end
    for _, l in ipairs(takenLinks) do
        local s = GV.SetOf(l)
        if s and sets[s] then touched[s] = (touched[s] or 0) - 1 end
    end
    if not next(touched) then return 0 end
    local worn, d = GV.WornSetCounts(), 0
    for setID, change in pairs(touched) do
        if change ~= 0 then
            local before = worn[setID] or 0
            local after = before + change
            for _, b in ipairs(GV.SetBonusList(scale, setID)) do
                if after >= b.at and before < b.at then
                    d = d + b.value
                elseif before >= b.at and after < b.at then
                    d = d - b.value
                end
            end
        end
    end
    return d
end

function GV.CopyExtras(x)
    if type(x) ~= "table" then return nil end
    local out = { items = {}, sets = {} }
    for k, v in pairs(type(x.items) == "table" and x.items or {}) do out.items[k] = v end
    for k, set in pairs(type(x.sets) == "table" and x.sets or {}) do
        if type(set) == "table" then
            out.sets[k] = {}
            for a, v in pairs(set) do out.sets[k][a] = v end
        end
    end
    return out
end

-- What one point of a scale is worth in DPS, from a simulator (the DPS weight of the stat weighed at 1).
-- scale.dps = { per }.
function GV.Dps(scale)
    local d = scale and scale.dps
    if type(d) ~= "table" then return nil end
    return (type(d.per) == "number" and not Secret(d.per) and d.per > 0) and d.per or nil
end

-- On an own scale; 0 or less unsets it.
function GV.SetDps(id, field, v)
    local s = Own(id)
    v = tonumber(v)
    if not (s and field == "per" and v) then return false end
    s.dps = (v > 0) and { per = v } or nil
    return true
end

function GV.CopyDps(d)
    if type(d) ~= "table" or type(d.per) ~= "number" then return nil end
    return { per = d.per }
end

-- A gain in the unit asked: "points" (the scale's own), "dps" (its DPS per point), or "pct" (a share of what the
-- replaced piece is worth, was). Returns the value and the unit it ends in: "points" when the one asked cannot be
-- said (no DPS per point; nothing worn worth comparing).
function GV.InUnit(scale, v, mode, was)
    if mode == "dps" then
        local per = GV.Dps(scale)
        if per then return v * per, "dps" end
    elseif mode == "pct" then
        local p = GV.Pct(v, was)
        if p then return p, "pct" end
    end
    return v, "points"
end

-- The best swap for one scale: each place values what it takes off (each worn
-- piece where it sits), and the largest change wins. Returns the worth, the
-- change (nil when there is nothing to compare: the item is the one worn, or a
-- slot reads secret), whether the place is empty, and the replaced item's name
-- when there was a choice. goals = the goals the scale stops at, each with
-- .worn (what the worn gear gives toward it); their stats count only up to them.
function GV.BestSwap(stats, link, slots, loc, scale, goals, lines)
    if goals and #goals == 0 then goals = nil end
    -- extras (the player's values on effects and sets) count beside the stats, never toward a goal
    local mineX = GV.ItemExtra(scale, link, lines)
    local function value(list, bases)
        if goals then return GoalWorth(list, scale, goals, bases) end
        local v = 0
        for _, it in ipairs(list) do v = v + GV.Worth(it[1], scale, it[2]) end
        return v
    end
    -- what the worn gear gives toward each goal without the given pieces' stats
    local function bases(pieces)
        local b = {}
        for i, goal in ipairs(goals or {}) do
            local took = 0
            for _, st in ipairs(pieces) do took = took + GV.AmountOf(st, goal) end
            b[i] = goal.worn - took
        end
        return b
    end
    local options = GV.Options(slots, loc)
    for _, opt in ipairs(options) do
        for _, slot in ipairs(opt.take) do
            local wl = GV.Worn(slot)
            if wl == false then return GV.Worth(stats, scale, Share(opt.hand)) + mineX end
            if wl and GV.SameItem(wl, link) then
                return value({ { stats, Share(slot) } }, bases({ stats })) + mineX, nil, nil, nil, mineX
            end
        end
    end
    local best
    for _, opt in ipairs(options) do
        local empty, name, taken, pieces, links, wasX = true, nil, {}, {}, {}, 0
        for _, slot in ipairs(opt.take) do
            local wl, ws = GV.Worn(slot)
            if wl then
                empty = false
                name = wl:match("%[(.-)%]")
                taken[#taken + 1] = { ws, Share(slot) }
                pieces[#pieces + 1] = ws
                links[#links + 1] = wl
                wasX = wasX + GV.ItemExtra(scale, wl)
            end
        end
        local base = bases(pieces)
        local setD = GV.SetDelta(scale, link, links)
        local was = value(taken, base) + wasX
        local v = value({ { stats, Share(opt.hand) } }, base) + mineX
        local d = v - was + setD
        if not best or d > best.d then
            best = { v = v, d = d, empty = empty, name = name, x = mineX - wasX + setD, was = was }
        end
    end
    -- the replaced pieces' worth last: a percent gain is a share of it
    return best.v, best.d, best.empty, (#options > 1 and not best.empty) and best.name or nil, best.x,
        (not best.empty) and best.was or nil
end

-- A gain as a percent of what the worn piece is worth; nil with nothing worth comparing (an empty slot, a piece
-- worth nothing to the scale).
function GV.Pct(delta, was)
    if type(delta) ~= "number" or type(was) ~= "number" or was < 0.05 then return nil end
    return delta / was * 100
end

-- "+20%", "+2.5%", "-12%".
function GV.PctText(p)
    local a = math.abs(p)
    local n = (a < 10) and (string.format("%.1f", a):gsub("%.0$", "")) or string.format("%d", math.floor(a + 0.5))
    return ((p > 0) and "+" or (p < 0 and n ~= "0") and "-" or "") .. n .. "%"
end

-- Whether item tooltips add the percent beside each change, account-wide; off until the player ticks it.
function GV.PctOn()
    local data = GV.Data()
    return data ~= nil and data.gearPct == true
end

function GV.SetPctOn(on)
    local data = GV.Data()
    if not data then return false end
    data.gearPct = on and true or nil
    return true
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
-- could go in two places; extra = how much of it the scale's extras make; was = what the replaced piece is worth
-- (the percent beside the change, when ticked).
function GV.Line(scale, v, delta, empty, name, extra, was)
    local unit = GV.Unit(scale)
    local s = GV.LINE_COLOR .. scale.name .. ": " .. GV.Num(v) .. (unit and (" " .. Tr(unit)) or "") .. "|r"
    local x = (type(extra) == "number" and math.abs(extra) >= 0.05) and GV.Num(extra) or nil
    if delta == nil then
        if x then return s .. " " .. GV.SAME_COLOR .. Tr("(%s from extras)"):format(x) .. "|r" end
        return s
    end
    local col, sign = GV.SAME_COLOR, ""
    if math.abs(delta) < 0.05 then
        delta = 0
    elseif delta > 0 then
        col, sign = GV.UP_COLOR, "+"
    else
        col = GV.DOWN_COLOR
    end
    local n = sign .. GV.Num(delta)
    local p = (delta ~= 0 and GV.PctOn()) and GV.Pct(delta, was) or nil
    if p then n = n .. ", " .. GV.PctText(p) end
    local vs
    if empty then
        vs = x and Tr("(%s vs empty, %s from extras)"):format(n, x) or Tr("(%s vs empty)"):format(n)
    elseif name then
        vs = x and Tr("(%s vs %s, %s from extras)"):format(n, name, x) or Tr("(%s vs %s)"):format(n, name)
    else
        vs = x and Tr("(%s vs worn, %s from extras)"):format(n, x) or Tr("(%s vs worn)"):format(n)
    end
    return s .. " " .. col .. vs .. "|r"
end

-- "Regen: 10 / 12 MP5": a goal's name, then the worn amount against the goal.
function GV.GoalText(goal, worn)
    local key = goal.kind
    return Tr("%s: %s"):format(GV.GoalName(key),
        GV.GoalNum(worn, key) .. " / " .. GV.GoalNum(goal.goal, key) .. GV.GoalUnit(key))
end

-- A goal's line: what the worn gear gives after the swap that keeps the most
-- of it, against the goal (goal.worn = before). nil when neither the item nor
-- what it replaces moves it.
function GV.GoalLine(stats, link, slots, loc, goal)
    local worn = goal.worn
    local mine = GV.AmountOf(stats, goal)
    local options = GV.Options(slots, loc)
    local after
    for _, opt in ipairs(options) do
        local took, isWorn = 0, false
        for _, slot in ipairs(opt.take) do
            local wl, ws = GV.Worn(slot)
            if wl and GV.SameItem(wl, link) then isWorn = true end
            if wl and ws then took = took + GV.AmountOf(ws, goal) end
        end
        if isWorn then
            if math.abs(mine) < 0.05 then return nil end
            return GV.LINE_COLOR .. GV.GoalText(goal, worn) .. "|r"
        end
        local a = worn - took + mine
        if not after or a > after then after = a end
    end
    if not after then return nil end
    local d = after - worn
    if math.abs(mine) < 0.05 and math.abs(d) < 0.05 then return nil end
    local s = GV.LINE_COLOR .. GV.GoalText(goal, after) .. "|r"
    local col, words
    if worn >= goal.goal and after >= goal.goal then
        col, words = GV.SAME_COLOR, Tr("(at the goal)")
    elseif after >= goal.goal then
        col, words = GV.UP_COLOR, Tr("(goal reached)")
    elseif math.abs(d) >= 0.05 then
        col = d > 0 and GV.UP_COLOR or GV.DOWN_COLOR
        words = Tr("(%s toward goal)"):format((d > 0 and "+" or "") .. GV.Num(d))
    end
    if not words then return s end
    return s .. " " .. col .. words .. "|r"
end

-- The lines for one item and a list of scales, or nil when it has nothing to
-- value (not gear, no stats read, no scale). Each scale counts its goals' stats
-- only up to them; a line per goal closes the block (one for scales that share
-- it), in the page's order of stats.
-- Whether a scale lists the item or its set: an item with no stats (a trinket
-- that only has a Use) still has a worth then.
function GV.Listed(link, scales)
    local id, set = GV.ItemID(link), GV.SetOf(link)
    for _, s in ipairs(scales) do
        local x = GV.Extras(s)
        if (id and x.items[id] ~= nil) or (set and x.sets[set]) then return true end
    end
    return false
end

function GV.LinesFor(link, lines, scales)
    if #scales == 0 then return nil end
    local loc = GV.EquipLoc(link)
    local slots = loc and GV.SLOTS[loc]
    if not slots then return nil end
    local stats, any = GV.ItemStats(link, lines)
    if not any and not GV.Listed(link, scales) then return nil end
    local out, seen, closing = {}, {}, {}
    for _, scale in ipairs(scales) do
        local mine = {}
        for _, goal in ipairs(GV.Goals(scale)) do
            goal.worn = GV.WornAmount(goal)
            if goal.worn ~= nil then
                mine[#mine + 1] = goal
                local id = goal.kind .. ":" .. goal.goal .. ":" .. goal.spi .. ":" .. goal.int
                -- a line only for the goals the player ticked
                if not seen[id] and GV.GoalLineOn(goal.kind) then
                    seen[id] = true
                    closing[#closing + 1] = goal
                end
            end
        end
        local v, delta, empty, name, extra, was = GV.BestSwap(stats, link, slots, loc, scale, mine, lines)
        out[#out + 1] = GV.Line(scale, v, delta, empty, name, extra, was)
    end
    local order = {}
    for i, k in ipairs(GV.GoalKinds()) do order[k.key] = i end
    table.sort(closing, function(a, b)
        if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
        return a.goal < b.goal
    end)
    for _, goal in ipairs(closing) do out[#out + 1] = GV.GoalLine(stats, link, slots, loc, goal) end
    return out
end

-- Each scale's worth of an item and its change from the best swap, its goals
-- counted: { { scale, v, delta, was, empty }, ... } (delta nil: nothing to compare; was: what the replaced piece
-- is worth), or nil when the item has nothing to value. stats, any: its stats as read before (GV.ItemStats), for an
-- item the game may no longer hold.
function GV.Gains(link, lines, scales, stats, any)
    local loc = GV.EquipLoc(link)
    local slots = loc and GV.SLOTS[loc]
    if not slots then return nil end
    if stats == nil then stats, any = GV.ItemStats(link, lines) end
    if not any and not GV.Listed(link, scales) then return nil end
    local out = {}
    for _, scale in ipairs(scales) do
        local mine = {}
        for _, goal in ipairs(GV.Goals(scale)) do
            goal.worn = GV.WornAmount(goal)
            if goal.worn ~= nil then mine[#mine + 1] = goal end
        end
        local v, delta, empty, _, _, was = GV.BestSwap(stats, link, slots, loc, scale, mine, lines)
        out[#out + 1] = { scale = scale, v = v, delta = delta, was = was, empty = empty == true }
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

-- Goals ride the string after the weights, each in its own unit (percent for
-- hit on Forever): RegenGoal=64, RegenSpirit=0.5, RegenIntellect=0.075, SpellHitGoal=17.
GV.GOAL_SHARE = { regen = "RegenGoal", spellhit = "SpellHitGoal", meleehit = "MeleeHitGoal", crit = "CritGoal",
    haste = "HasteGoal", pen = "SpellPenetrationGoal", mastery = "MasteryGoal", vers = "VersatilityGoal" }
GV.RATE_SHARE = { spi = "RegenSpirit", int = "RegenIntellect" }
-- The other words simulators write for the same stats (a spell and a melee word for one stat here: the larger
-- weight wins, the class's own).
GV.SHARE_ALIASES = {
    forever = { naturespelldamage = "nature", firespelldamage = "fire", spellhitrating = "hit",
        spellcritrating = "crit", spellhasterating = "haste", spellpen = "pen" },
}

-- A scale and its goals: one package.
function GV.Export(scale)
    local names = GV.SHARE_NAMES[GV.Game()]
    local parts = { "Class=" .. (GV.CLASS_NAMES[scale.class] or tostring(scale.class)) }
    if scale.spec then parts[#parts + 1] = "Spec=" .. scale.spec end
    for _, s in ipairs(GV.Stats()) do
        local w = scale.w and scale.w[s[1]]
        if w and names[s[1]] then parts[#parts + 1] = names[s[1]] .. "=" .. Short(w * PerPoint(s[1])) end
    end
    for _, goal in ipairs(GV.Goals(scale)) do
        local word = GV.GOAL_SHARE[goal.kind]
        if word then
            parts[#parts + 1] = word .. "=" .. Short(goal.goal)
            if goal.kind == "regen" then
                parts[#parts + 1] = GV.RATE_SHARE.spi .. "=" .. Short(goal.spi)
                parts[#parts + 1] = GV.RATE_SHARE.int .. "=" .. Short(goal.int)
            end
        end
    end
    -- what a point is worth in DPS
    local per = GV.Dps(scale)
    if per then parts[#parts + 1] = "DpsPerPoint=" .. Short(per) end
    -- extras by ID: Item_<id>=value (ItemAuto_<id>=1 reads from its words), SetItem_<set>=<piece>, Set_<set>_<n>=value
    local x = GV.Extras(scale)
    local ids = {}
    for id in pairs(x.items) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local e = x.items[id]
        parts[#parts + 1] = (type(e) == "number") and ("Item_" .. id .. "=" .. Short(e)) or ("ItemAuto_" .. id .. "=1")
    end
    local sids = {}
    for id in pairs(x.sets) do sids[#sids + 1] = id end
    table.sort(sids)
    for _, sid in ipairs(sids) do
        local set = x.sets[sid]
        parts[#parts + 1] = "SetItem_" .. sid .. "=" .. tostring(set.item or 0)
        local ats = {}
        for a, v in pairs(set) do if type(a) == "number" and type(v) == "number" then ats[#ats + 1] = a end end
        table.sort(ats)
        for _, a in ipairs(ats) do parts[#parts + 1] = "Set_" .. sid .. "_" .. a .. "=" .. Short(set[a]) end
    end
    -- the word goes in as an argument: the format itself holds no words to translate
    return string.format('( %s: v1: "%s": %s )', "ArcAuras", (scale.name or ""):gsub('"', "'"), table.concat(parts, ", "))
end

local function SameName(a, b)
    local function norm(s) return (tostring(s or ""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$")) end
    return norm(a) == norm(b)
end

-- The player's own scale of this game and class with that name (the oldest when
-- several share it), so an import can update it.
function GV.FindOwn(name, class)
    local data = GV.Data()
    local best
    for id, s in pairs(data and data.gearScales or {}) do
        if type(s) == "table" and s.game == GV.Game() and s.class == class and SameName(s.name, name)
            and (not best or (s.n or 0) < (best.n or 0)) then
            s.id = id
            best = s
        end
    end
    return best
end

-- The goals a string carried, as a scale keeps them: only the kinds this game
-- has, only goals above 0. Returns them (nil for none) and how many.
local function KeptGoals(goals)
    local out, count
    for kind, t in pairs(goals) do
        if GV.GoalKind(kind) and (t.goal or 0) > 0 then
            out = out or {}
            out[kind] = { goal = t.goal, spi = t.spi, int = t.int }
            count = (count or 0) + 1
        end
    end
    return out, count or 0
end

-- A weights string read into the player's own scales: a scale of the same class
-- and name takes its weights and goals (and its spec, when it names one), else a
-- new scale. Returns the id, true when it updated one, how many goals came in,
-- and the weighed words it does not know (said on the page, never dropped
-- silently); or nil and why.
function GV.Import(text)
    if type(text) ~= "string" then return nil, "empty" end
    local name, body = text:match('^%s*%(%s*[%w_]+%s*:%s*v%d+%s*:%s*"([^"]+)"%s*:(.-)%)%s*$')
    if not name then return nil, "format" end
    local byName, goalBy, rateBy = {}, {}, {}
    for k, n in pairs(GV.SHARE_NAMES[GV.Game()]) do byName[n:lower()] = k end
    for word, k in pairs(GV.SHARE_ALIASES[GV.Game()] or {}) do byName[word] = k end
    byName.dps = "dps"
    local skipped = {}
    for k, n in pairs(GV.GOAL_SHARE) do goalBy[n:lower()] = k end
    for k, n in pairs(GV.RATE_SHARE) do rateBy[n:lower()] = k end
    local cls, spec, w, n, goals = nil, nil, {}, 0, {}
    local extras, anyExtra = { items = {}, sets = {} }, false
    local dps
    for pair in (body .. ","):gmatch("([^,]*),") do
        local k, v = pair:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "Class" then
            for token, word in pairs(GV.CLASS_NAMES) do
                if word:lower() == v:lower() then cls = token end
            end
        elseif k == "Spec" then
            spec = v
        elseif k then
            local lk, num = k:lower(), tonumber(v)
            local key = byName[lk]
            local itemId, autoId = tonumber(lk:match("^item_(%d+)$")), tonumber(lk:match("^itemauto_(%d+)$"))
            local setPiece = tonumber(lk:match("^setitem_(%d+)$"))
            local setId, at = lk:match("^set_(%d+)_(%d+)$")
            if itemId and num and num >= 0 then
                extras.items[itemId], anyExtra = num, true
            elseif autoId then
                extras.items[autoId], anyExtra = true, true
            elseif setPiece and num and num > 0 then
                extras.sets[setPiece] = extras.sets[setPiece] or {}
                extras.sets[setPiece].item, anyExtra = num, true
            elseif setId and num and num >= 0 then
                setId, at = tonumber(setId), tonumber(at)
                extras.sets[setId] = extras.sets[setId] or {}
                extras.sets[setId][at] = num
            elseif lk == "dpsperpoint" and num and num > 0 then
                dps = { per = num }
            elseif lk == "basedps" then
                -- an older string's DPS, no longer used
            elseif goalBy[lk] and num and num >= 0 then
                goals[goalBy[lk]] = goals[goalBy[lk]] or {}
                goals[goalBy[lk]].goal = num
            elseif rateBy[lk] and num and num >= 0 then
                goals.regen = goals.regen or {}
                goals.regen[rateBy[lk]] = num
            elseif key and num and num > 0 then
                local each = num / PerPoint(key)
                if not w[key] then n = n + 1 end
                if not w[key] or each > w[key] then w[key] = each end
            elseif not key and num and num > 0 then
                skipped[#skipped + 1] = k
            end
        end
    end
    if n == 0 then return nil, "weights" end
    cls = cls or GV.ClassToken()
    local kept, count = KeptGoals(goals)
    -- a set value with no piece to read its bonuses from is dropped
    for sid, set in pairs(extras.sets) do
        if not set.item then extras.sets[sid] = nil end
    end
    local keptX = anyExtra and extras or nil
    local same = GV.FindOwn(name, cls)
    if same then
        -- the string is the whole package: a scale updated from one with no goals or extras has none
        same.w, same.goals, same.extras, same.dps = w, kept, keptX, dps
        if spec then same.spec = spec end
        return same.id, true, count, skipped
    end
    local id = GV.NewScale(name, { w = w, class = cls, spec = spec, goals = kept, extras = keptX, dps = dps })
    if not id then return nil, "saves" end
    return id, false, count, skipped
end

-- Every weights string in a paste, read in order. Returns a list of
-- { id, updated, goals, skipped } or { why }; a paste with none reads as one string.
function GV.ImportAll(text)
    local out = {}
    if type(text) ~= "string" then return { { why = "empty" } } end
    local function one(s)
        local id, r, goals, skipped = GV.Import(s)
        if id then return { id = id, updated = r == true, goals = goals or 0, skipped = skipped or {} } end
        return { why = r }
    end
    for block in text:gmatch("%b()") do out[#out + 1] = one(block) end
    if #out == 0 then out[1] = one(text) end
    return out
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
