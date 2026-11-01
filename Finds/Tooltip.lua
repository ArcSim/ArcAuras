local _, ns = ...
if ns.shareOnly then return end

-- The tooltip of a new or hidden item the game cannot draw yet, from the datamined numbers and effect lines (Data.lua
-- D.Tip, D.Effects, D.Hidden, D.Set), in the game's wording and order; T.ItemTip shows the game's own once the server
-- sends the item.
local T, D = ns.Theme, ns.Data

local SLOT = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
    [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
    [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED",
    [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG", [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE",
    [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE", [24] = "INVTYPE_AMMO",
    [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [27] = "INVTYPE_QUIVER", [28] = "INVTYPE_RELIC" }
local SLOT_TEXT = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Finger", "Trinket",
    "One-Hand", "Off Hand", "Ranged", "Back", "Two-Hand", "Bag", "Tabard", "Chest", "Main Hand", "Off Hand", "Held In Off-hand",
    "Ammo", "Thrown", "Ranged", "Quiver", "Relic" }
-- the type on the right of the slot line, as the game's tooltip names it
local WEAPON = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm", [7] = "Sword",
    [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand",
    [20] = "Fishing Pole" }
local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem" }

-- stats the game shows as a white "+N Name" line: the game's short name (global) and a fallback
local WHITE = {
    [0] = { "ITEM_MOD_MANA_SHORT", "Mana" }, [1] = { "ITEM_MOD_HEALTH_SHORT", "Health" },
    [3] = { "ITEM_MOD_AGILITY_SHORT", "Agility" }, [4] = { "ITEM_MOD_STRENGTH_SHORT", "Strength" },
    [5] = { "ITEM_MOD_INTELLECT_SHORT", "Intellect" }, [6] = { "ITEM_MOD_SPIRIT_SHORT", "Spirit" },
    [7] = { "ITEM_MOD_STAMINA_SHORT", "Stamina" },
    [51] = { "RESISTANCE2_NAME", "Fire Resistance" }, [52] = { "RESISTANCE4_NAME", "Frost Resistance" },
    [53] = { "RESISTANCE1_NAME", "Holy Resistance" }, [54] = { "RESISTANCE5_NAME", "Shadow Resistance" },
    [55] = { "RESISTANCE3_NAME", "Nature Resistance" }, [56] = { "RESISTANCE6_NAME", "Arcane Resistance" },
}
-- every other stat: the game's TOOLTIP_ITEM_STAT_<key>_INCREASE / _DECREASE line, its English text as the fallback;
-- a third value makes it a percent line, the stat's points per 1%
local LINE = {
    [12] = { "DEFENSE", "Equip: Increased Defense +%1$d.", "Equip: Decreased Defense -%1$d." },
    [13] = { "DODGE_PCT", "Equip: Increases your chance to Dodge an attack by %1$.1f%%.", "Equip: Decreases your chance to Dodge an attack by %1$.1f%%.", 12 },
    [14] = { "PARRY_PCT", "Equip: Increases your chance to Parry an attack by %1$.1f%%.", "Equip: Decreases your chance to Parry an attack by %1$.1f%%.", 15 },
    [15] = { "BLOCK_CHANCE", "Equip: Increases your chance to Block attacks with a shield by %1$.1f%%.", "Equip: Decreases your chance to Block attacks with a shield by %1$.1f%%.", 5 },
    [31] = { "HIT_PERCENT", "Equip: Improves your chance to hit by %1$.1f%%.", "Equip: Decreases your chance to hit by %1$.1f%%.", 10 },
    [32] = { "CRIT_PERCENT", "Equip: Improves your chance to get a critical strike by %1$.1f%%.", "Equip: Decreases your chance to get a critical strike by %1$.1f%%.", 14 },
    [36] = { "HASTE_PCT", "Equip: Increases your attack speed and casting speed by %1$.1f%%.", "Equip: Decreases your attack speed and casting speed by %1$.1f%%.", 10 },
    [37] = { "EXPERTISE_PCT", "Equip: Reduces chance to be Dodged or Parried by %1$.1f%%.", "Equip: Increases chance to be Dodged or Parried by %1$.1f%%.", 10 },
    [38] = { "ATTACK_POWER", "Equip: +%1$d Attack Power.", "Equip: -%1$d Attack Power." },
    [39] = { "RANGED_ATTACK_POWER", "Equip: +%1$d Ranged Attack Power.", "Equip: -%1$d Ranged Attack Power." },
    [41] = { "SPELL_HEALING", "Equip: Increases healing done by magical spells and effects by up to %1$d.", "Equip: Decreases healing done by magical spells and effects by up to %1$d." },
    [42] = { "SPELL_DAMAGE", "Equip: Increases damage done by magical spells and effects by up to %1$d.", "Equip: Decreases damage done by magical spells and effects by up to %1$d." },
    [43] = { "MANA_REGEN", "Equip: Restores %1$d Mana per 5 sec.", "Equip: Reduces Mana Regen by %1$d Mana per 5 sec." },
    [44] = { "ARMOR_PENETRATION", "Equip: Your attacks pierce up to %1$d Armor.", "Equip: Your attacks pierce up to %1$d less Armor." },
    [45] = { "SPELL_POWER", "Equip: Increases damage and healing done by magical spells and effects by up to %1$d.", "Equip: Decreases damage and healing done by magical spells and effects by up to %1$d." },
    [46] = { "HEALTH_REGEN", "Equip: Restores %1$d Health per 5 sec.", "Equip: Reduces Health Regen by %1$d Health per 5 sec." },
    [47] = { "SPELL_PENETRATION", "Equip: Your spells pierce %1$d Magical Resistance.", "Equip: Your spells pierce %1$d less Magical Resistance." },
    [48] = { "BLOCK_VALUE", "Equip: Increases the Block Value of your shield by %1$d.", "Equip: Decreases the Block Value of your shield by %1$d." },
    [50] = { "ARMOR", "+%1$d Armor", "-%1$d Armor", nil, true },
    [83] = { "WEAPON_DAMAGE", "Equip: +%1$d Weapon Damage.", "Equip: -%1$d Weapon Damage." },
    [124] = { "SPELL_RESISTANCE_ALL_SCHOOLS", "+%1$d to All Resistances", "-%1$d to All Resistances", nil, true },
}
do
    -- the families: spell damage by school, weapon and profession skills, penetration, attack power and spell damage
    -- against a creature type
    local schools = { { 84, "HOLY", "Holy" }, { 85, "FIRE", "Fire" }, { 86, "NATURE", "Nature" }, { 87, "FROST", "Frost" },
        { 88, "SHADOW", "Shadow" }, { 89, "ARCANE", "Arcane" } }
    for _, s in ipairs(schools) do
        LINE[s[1]] = { s[2] .. "_DAMAGE", "Equip: Increases damage done by " .. s[3] .. " spells and effects by up to %1$d.",
            "Equip: Decreases damage done by " .. s[3] .. " spells and effects by up to %1$d." }
    end
    local skills = { "Two-Handed Axes", "Two-Handed Maces", "Two-Handed Swords", "Axes", "Bows", "Crossbows", "Daggers",
        "Dual Wielding", "Fist Weapons", "Guns", "Maces", "Polearms", "Staves", "Swords", "Thrown Weapons", "Wands", "Alchemy",
        "Blacksmithing", "Enchanting", "Engineering", "Jewelcrafting", "Leatherworking", "Herbalism", "Mining", "Skinning",
        "Cooking", "First Aid", "Fishing", "Tailoring" }
    for i, name in ipairs(skills) do
        LINE[89 + i] = { "SKILL_" .. name:upper():gsub(" ", "_"), "Equip: Increased " .. name .. " +%1$d.", "Equip: Decreased " .. name .. " -%1$d." }
    end
    local pierce = { "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }
    for i, key in ipairs(pierce) do
        local name = key:sub(1, 1) .. key:sub(2):lower()
        LINE[118 + i] = { key .. "_PENETRATION", "Equip: Your spells pierce %1$d " .. name .. " Resistance.",
            "Equip: Your spells pierce %1$d less " .. name .. " Resistance." }
    end
    local kinds = { { "HUMANOID", "Humanoids" }, { "ELEMENTAL", "Elementals" }, { "DEMON", "Demons" }, { "UNDEAD", "Undead" },
        { "DRAGONKIN", "Dragonkin" }, { "GIANT", "Giants" }, { "BEAST", "Beasts" }, { "MECHANICAL", "Mechanical units" } }
    for i, k in ipairs(kinds) do
        LINE[124 + i] = { "AP_VS_" .. k[1], "Equip: +%1$d Attack Power against " .. k[2] .. ".", "Equip: -%1$d Attack Power against " .. k[2] .. "." }
        LINE[132 + i] = { "SD_VS_" .. k[1], "Equip: Increases damage done to " .. k[2] .. " by magical spells and effects by up to %1$d.",
            "Equip: Decreases damage done to " .. k[2] .. " by magical spells and effects by up to %1$d." }
    end
end
-- the game lists the white stats in this order whatever the item's data order, then the Equip lines by stat type
local WHITE_ORDER = { 4, 3, 7, 5, 6, 0, 1, 50, 124, 53, 51, 55, 52, 54, 56 }
local STAT_RANK = {}
for i, t in ipairs(WHITE_ORDER) do STAT_RANK[t] = i end
local CLASS_BITS = { { 1, "WARRIOR" }, { 2, "PALADIN" }, { 4, "HUNTER" }, { 8, "ROGUE" }, { 16, "PRIEST" }, { 64, "SHAMAN" },
    { 128, "MAGE" }, { 256, "WARLOCK" }, { 1024, "DRUID" } }
local SCHOOL = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local GREEN, GOLD, GREY = { 0.12, 1, 0 }, { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 }

local function G(key, fallback)
    local v = rawget(_G, key)
    return type(v) == "string" and v or fallback
end

local function RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- the game's formats number their value ("%1$d"); plain Lua formats take it unnumbered
local function Fill(fmt, v)
    return (fmt:gsub("%%1%$", "%%")):format(v)
end

-- "%d hours" style counts: the game's text carries grammar codes only its own text renderer reads, so the fallbacks
-- pick the word here
local function Count(key, n, one, many)
    local g = rawget(_G, key)
    if type(g) == "string" then return g:format(n) end
    return (n == 1 and one or many):format(n)
end

-- the pieces of a tagged entry; nothing when the entry is missing or only a flag
local function Parts(v, pattern)
    if type(v) == "string" then return v:match(pattern) end
end

local TRIGGERS = { [0] = { "ITEM_SPELL_TRIGGER_ONUSE", "Use:" }, [1] = { "ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:" },
    [2] = { "ITEM_SPELL_TRIGGER_ONPROC", "Chance on hit:" } }

local function Requirements(tip, row, more)
    local classes = {}
    if row.ac and row.ac ~= 4095 and row.ac > 0 then
        for _, c in ipairs(CLASS_BITS) do
            if D.HasBit(row.ac, c[1]) then classes[#classes + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c[2]]) or c[2] end
        end
    end
    if #classes > 0 and #classes < #CLASS_BITS then tip:AddLine((G("ITEM_CLASSES_ALLOWED", "Classes: %s")):format(table.concat(classes, ", ")), 1, 1, 1) end
    if type(more.r) == "string" then tip:AddLine((G("ITEM_RACES_ALLOWED", "Races: %s")):format(more.r), 1, 1, 1) end
    if (row.req or 0) > 0 then tip:AddLine((G("ITEM_MIN_LEVEL", "Requires Level %d")):format(row.req), 1, 1, 1) end
    local skill, rank = Parts(more.k, "^(.*)~(%d+)$")
    if skill then tip:AddLine((G("ITEM_MIN_SKILL", "Requires %s (%d)")):format(skill, tonumber(rank)), 1, 1, 1) end
    local faction, standing = Parts(more.f, "^(.*)~(%d+)$")
    if faction then
        local n = tonumber(standing) + 1
        tip:AddLine((G("ITEM_REQ_REPUTATION", "Requires %s - %s")):format(faction, G("FACTION_STANDING_LABEL" .. n, STANDING[n] or "")), 1, 1, 1)
    end
    if type(more.a) == "string" then tip:AddLine((G("ITEM_REQ_SKILL", "Requires %s")):format(more.a), 1, 1, 1) end
end

local function SetLines(tip, set)
    tip:AddLine(" ")
    tip:AddLine((G("ITEM_SET_NAME", "%s (%d/%d)")):format(set.name, 0, set.pieces), GOLD[1], GOLD[2], GOLD[3])
    for _, name in ipairs(set.items) do tip:AddLine("  " .. name, GREY[1], GREY[2], GREY[3]) end
    if #set.bonuses > 0 then
        tip:AddLine(" ")
        for _, b in ipairs(set.bonuses) do
            tip:AddLine((G("ITEM_SET_BONUS_GRAY", "(%d) Set: %s")):format(b[1], b[2]), GREY[1], GREY[2], GREY[3], true)
        end
    end
    tip:AddLine(" ")
end

local Body
-- the item a recipe makes: its datamined tooltip, else the game's own, else its name
local function MadeItem(tip, entry)
    local id, name, q = entry:match("^(%d+)~(.*)~(%d+)$")
    id = tonumber(id)
    if not id then return end
    local row, data = D.Seed(id), D.Tip(id)
    if row and data and row.kind == "n" then
        tip:AddLine(row.name, RGB(T.QualityHex(row.q)))
        Body(tip, id, row, data, true)
        return
    end
    local game = C_Item.GetItemInfo(id) and C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
    if game and game.lines and #game.lines > 0 then
        for _, l in ipairs(game.lines) do
            local lc, rc = l.leftColor, l.rightColor
            local sellWord = type(SELL_PRICE) == "string" and SELL_PRICE or "Sell Price"
            local left = l.leftText or ""
            if l.price == nil and left:find(sellWord, 1, true) ~= 1 then
                if l.rightText and l.rightText ~= "" then
                    tip:AddDoubleLine(left, l.rightText, lc and lc.r or 1, lc and lc.g or 1, lc and lc.b or 1, rc and rc.r or 1, rc and rc.g or 1, rc and rc.b or 1)
                else
                    tip:AddLine(left, lc and lc.r or 1, lc and lc.g or 1, lc and lc.b or 1, true)
                end
            end
        end
        return
    end
    tip:AddLine(name, RGB(T.QualityHex(tonumber(q) or 1)))
end

-- everything under the name, in the game's order; nested: the item a recipe makes, drawn inside the recipe's tooltip
function Body(tip, id, row, data, nested)
    local more = data.more or {}
    local white = function(text) tip:AddLine(text, 1, 1, 1) end
    -- the game's own tooltip has no item level line; every equippable item, bags included, shows one right under the name
    if row.ilvl and row.ilvl > 0 and row.inv and row.inv > 0 then
        tip:AddLine((G("ITEM_LEVEL", "Item Level %d")):format(row.ilvl), GOLD[1], GOLD[2], GOLD[3])
    end
    if type(more.N) == "string" then
        local text, hex = more.N:match("^(.*)~(%x%x%x%x%x%x)$")
        if text then tip:AddLine(text, RGB(hex)) end
    end
    local bind = ({ G("ITEM_BIND_ON_PICKUP", "Binds when picked up"), G("ITEM_BIND_ON_EQUIP", "Binds when equipped"),
        G("ITEM_BIND_ON_USE", "Binds when used"), G("ITEM_BIND_QUEST", "Quest Item") })[data.bind or 0]
    if bind then white(bind) end
    if data.unique == "u" then white(G("ITEM_UNIQUE", "Unique")) end
    if data.unique == "e" then white(G("ITEM_UNIQUE_EQUIPPABLE", "Unique-Equipped")) end
    local lname, lqty, leq = Parts(more.L, "^(.*)~(%d+)~(%d)$")
    if lname then
        local fmt = leq == "1" and G("ITEM_LIMIT_CATEGORY_MULTIPLE", "Unique-Equipped: %s (%d)") or G("ITEM_LIMIT_CATEGORY", "Unique: %s (%d)")
        white(fmt:format(lname, tonumber(lqty)))
    end
    if more.u then white((G("ITEM_UNIQUE_MULTIPLE", "Unique (%d)")):format(tonumber(more.u))) end
    if more.q then white(G("ITEM_STARTS_QUEST", "This Item Begins a Quest")) end
    if more.c then white(G("ITEM_CONJURED", "Conjured Item")) end
    local slots, bagKind = Parts(more.b, "^(%d+)~(.*)$")
    local slot = row.inv and row.inv > 0 and row.inv ~= 18 and G(SLOT[row.inv] or "", SLOT_TEXT[row.inv])
    local kind = (row.cls == 2 and WEAPON[row.sub]) or (row.cls == 4 and row.inv ~= 16 and ARMOR[row.sub]) or nil
    if slots then
        white((G("CONTAINER_SLOTS", "%d Slot %s")):format(tonumber(slots), bagKind))
    elseif slot then
        if kind then tip:AddDoubleLine(slot, kind, 1, 1, 1, 1, 1, 1) else white(slot) end
    end
    if data.dmg then
        local lo, hi, delay = data.dmg[1], data.dmg[2], data.dmg[3] / 1000
        local school = data.dmg[4] and SCHOOL[data.dmg[4]]
        local dmgText = school and (G("DAMAGE_TEMPLATE_WITH_SCHOOL", "%s - %s %s Damage")):format(lo, hi, G("SPELL_SCHOOL" .. data.dmg[4] .. "_CAP", school))
            or (G("DAMAGE_TEMPLATE", "%s - %s Damage")):format(lo, hi)
        tip:AddDoubleLine(dmgText, ("%s %.2f"):format(G("SPEED", "Speed"), delay), 1, 1, 1, 1, 1, 1)
        -- the game rounds a half down: 22.75 shows as 22.7
        local dps = math.ceil((lo + hi) / 2 / delay * 10 - 0.5) / 10
        white((G("DPS_TEMPLATE", "(%s damage per second)")):format(("%.1f"):format(dps)))
    end
    if data.armor then white((G("ARMOR_TEMPLATE", "%s Armor")):format(data.armor)) end
    local equip, stats = {}, {}
    for i, s in ipairs(data.stats) do stats[i] = s end
    table.sort(stats, function(a, b) return (STAT_RANK[a[1]] or 100 + a[1]) < (STAT_RANK[b[1]] or 100 + b[1]) end)
    for _, s in ipairs(stats) do
        local w, line = WHITE[s[1]], LINE[s[1]]
        if w then
            white(("%s%d %s"):format(s[2] < 0 and "" or "+", s[2], G(w[1], w[2])))
        elseif line then
            local up = s[2] >= 0
            local fmt = G("TOOLTIP_ITEM_STAT_" .. line[1] .. (up and "_INCREASE" or "_DECREASE"), up and line[2] or line[3])
            local v = math.abs(s[2])
            local text = Fill(fmt, line[4] and v / line[4] or v)
            if line[5] then white(text) else equip[#equip + 1] = text end
        end
    end
    for _, text in ipairs(equip) do tip:AddLine(text, GREEN[1], GREEN[2], GREEN[3], true) end
    -- a recipe lists what it needs before what it teaches; every other item after its effects
    local recipe = type(more.T) == "string"
    if recipe then Requirements(tip, row, more) end
    for _, fx in ipairs(D.Effects(id) or {}) do
        local word = TRIGGERS[fx.trig]
        if word then tip:AddLine(G(word[1], word[2]) .. " " .. fx.text, GREEN[1], GREEN[2], GREEN[3], true) end
    end
    if recipe then
        tip:AddLine(G("ITEM_SPELL_TRIGGER_ONUSE", "Use:") .. " " .. more.T, GREEN[1], GREEN[2], GREEN[3], true)
        if type(more.C) == "string" and not nested then
            tip:AddLine(" ")
            MadeItem(tip, more.C)
            if type(more.R) == "string" then
                tip:AddLine(" ")
                tip:AddLine((G("ITEM_REQ_SKILL", "Requires %s")):format(more.R), 1, 1, 1, true)
            end
        end
    end
    if more.x then white(Count("ITEM_SPELL_CHARGES", tonumber(more.x), "%d Charge", "%d Charges")) end
    local sec = tonumber(more.t)
    if sec then
        local floor = math.floor
        if sec >= 86400 then white(Count("ITEM_DURATION_DAYS", floor(sec / 86400), "Duration: %d day", "Duration: %d days"))
        elseif sec >= 3600 then white(Count("ITEM_DURATION_HOURS", floor(sec / 3600), "Duration: %d hour", "Duration: %d hrs"))
        elseif sec >= 60 then white((G("ITEM_DURATION_MIN", "Duration: %d min")):format(floor(sec / 60)))
        else white((G("ITEM_DURATION_SEC", "Duration: %d sec")):format(sec)) end
    end
    local set = more.s and D.Set(tonumber(more.s))
    if set then SetLines(tip, set) end
    if not recipe then Requirements(tip, row, more) end
    if more.p then tip:AddLine(G("ITEM_READABLE", "<Right Click to Read>"), GREEN[1], GREEN[2], GREEN[3]) end
    if more.o then tip:AddLine(G("ITEM_OPENABLE", "<Right Click to Open>"), GREEN[1], GREEN[2], GREEN[3]) end
    if type(more.d) == "string" then tip:AddLine('"' .. more.d .. '"', GOLD[1], GOLD[2], GOLD[3], true) end
end

-- draws the datamined tooltip into tip; false when nothing is known of the item beyond the game's own
function T.DataTip(tip, id)
    local row = D.Seed(id)
    if not row then return false end
    local hidden = row.kind == "x"
    local data = D.Tip(id)
    if not data and not hidden then return false end
    data = data or { stats = {}, more = {} }
    tip:ClearLines()
    tip:AddLine(hidden and D.HiddenName(row) or row.name, RGB(T.QualityHex(row.q)))
    if hidden then tip:AddLine("Hidden by Blizzard", GREY[1], GREY[2], GREY[3]) end
    Body(tip, id, row, data)
    local known = hidden and D.Hidden(id)
    if known and known.set then tip:AddLine(known.set, GOLD[1], GOLD[2], GOLD[3]) end
    if known and known.look then tip:AddLine("Looks like " .. known.look, GREY[1], GREY[2], GREY[3], true) end
    tip:AddLine("Datamined, may change", GREY[1], GREY[2], GREY[3])
    tip.dataTipFor = id
    return true
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id) T.ItemArrived(id) end)
