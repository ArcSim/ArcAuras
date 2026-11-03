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

-- a stat's line as the game words it, and true when it is a white line (the rest are green Equip lines); nil for a stat
-- the game shows no line for
local function StatLine(t, v)
    local w, line = WHITE[t], LINE[t]
    if w then return ("%s%d %s"):format(v < 0 and "" or "+", v, G(w[1], w[2])), true end
    if not line then return end
    local up = v >= 0
    local fmt = G("TOOLTIP_ITEM_STAT_" .. line[1] .. (up and "_INCREASE" or "_DECREASE"), up and line[2] or line[3])
    local a = math.abs(v)
    return Fill(fmt, line[4] and a / line[4] or a), line[5] and true or false
end

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
        local text, isWhite = StatLine(s[1], s[2])
        if text and isWhite then white(text) elseif text then equip[#equip + 1] = text end
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

-- what changed from Classic, on the item box's lines (UI.lua TipLines), as board E4 draws it: the new value where the
-- game puts it, green when it got better, red when worse, the changed tag's orange when that cannot be told; Classic's
-- value right after it, smaller, struck through, in the panel's faint grey; a value Forever dropped struck whole.
-- A marked line carries segs (and rsegs for its right side): { text, kind } with kind nil (the line's own colour),
-- "up", "down", "flat", "old" or "gone"; T.LayChangeLine draws them. Quality and a missing item level are lines of our
-- own on top, removed values and changes whose line was not found at the bottom.
local QUALITY_NAME = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
local function QualityName(q)
    return G("ITEM_QUALITY" .. q .. "_DESC", QUALITY_NAME[q] or tostring(q))
end
local function BindText(b)
    return ({ G("ITEM_BIND_ON_PICKUP", "Binds when picked up"), G("ITEM_BIND_ON_EQUIP", "Binds when equipped"),
        G("ITEM_BIND_ON_USE", "Binds when used"), G("ITEM_BIND_QUEST", "Quest Item") })[b or 0]
end
local function UniqueText(u)
    if u == "u" then return G("ITEM_UNIQUE", "Unique") end
    if u == "e" then return G("ITEM_UNIQUE_EQUIPPABLE", "Unique-Equipped") end
end
-- lines compare without colour codes, case, doubled spaces or a closing full stop
local function Norm(s)
    s = (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():gsub("%s+", " ")
    return (s:gsub("^ ", ""):gsub("[ %.]+$", ""))
end
local function DpsText(d)
    return ("%.1f"):format(math.ceil((d[1] + d[2]) / 2 / (d[3] / 1000) * 10 - 0.5) / 10)
end
-- a stat line's number with its sign and percent ("+10", "1.5%"), never the full stop after it
local function FirstNumber(s)
    local n, at = s:match("([%+%-]?%d+)()")
    if not n then return end
    local frac = s:match("^%.%d+", at) or ""
    return n .. frac .. (s:match("^%%", at + #frac) or "")
end
-- the middle of every number in a value ("375 to 425" -> 400)
local function Amount(text)
    local sum, n = 0, 0
    for v in tostring(text):gmatch("%-?%d+%.?%d*") do sum, n = sum + tonumber(v), n + 1 end
    return n > 0 and sum / n or nil
end
local function Dir(new, old, lowerBetter)
    if not new or not old or new == old then return "flat" end
    if lowerBetter then return new < old and "up" or "down" end
    return new > old and "up" or "down"
end
-- an effect's number: a cooldown, cast time or "once every" gap is better lower; a duration, chance or range cannot be
-- judged; any other amount (damage, healing, restores, a stat) is better higher
local function EffectDir(text, at, len, newText, oldText)
    local after = text:sub(at + len, at + len + 24):lower()
    local before = text:sub(math.max(1, at - 12), at - 1):lower()
    if after:match("^%s*%a*%s*cooldown") or after:match("^%s*sec%s+cast") or before:match("every%s*$") then
        return Dir(Amount(newText), Amount(oldText), true)
    end
    if after:match("^%s*sec") or after:match("^%s*min") or after:match("^%s*hour") or after:match("^%s*day") or
        after:match("^%%%s*chance") or after:match("^%s*yard") then
        return "flat"
    end
    return Dir(Amount(newText), Amount(oldText))
end
-- segments with the empty ones left out
local function Segs(...)
    local out = {}
    for i = 1, select("#", ...) do
        local sg = select(i, ...)
        if sg and sg[1] ~= "" then out[#out + 1] = sg end
    end
    return out
end
-- before, the new value in its direction's look, Classic's value, after; the whole text is the value when it is not in it
local function Valued(text, value, dir, old)
    local s, e
    if value then s, e = text:find(value, 1, true) end
    if not s then return Segs({ text, dir }, old and { old, "old" }) end
    return Segs({ text:sub(1, s - 1) }, { value, dir }, old and { old, "old" }, { text:sub(e + 1) })
end

-- second value: how many changes found no line of their own and fell to the bottom (a removed value and the item level
-- Forever's tooltip lacks are meant to; t_item_changes sweeps every changed item for the rest)
function T.MarkChanges(lines, id, row)
    local ch = D.Changes(id)
    if not ch then return false, 0 end
    local used, head, tail, missed = {}, {}, {}, 0
    local WHITE_RGB = { 1, 1, 1 }
    -- prefix: the line starts with these words ("16 Slot" of "16 Slot Bag"), a whole word ("1 - 2" is not "1 - 25")
    local function Find(want, prefix)
        want = Norm(want)
        for i, l in ipairs(lines) do
            local have = Norm(l[1])
            if not used[i] and (have == want or (prefix and have:sub(1, #want) == want and have:sub(#want + 1, #want + 1) == " ")) then
                return i
            end
        end
    end
    -- a line of our own, in the colour its kind has in a tooltip (white, item level's gold, an effect's green)
    local function Own(list, text, segs, rgb)
        rgb = rgb or WHITE_RGB
        local l = { text, "", rgb[1], rgb[2], rgb[3], 1, 1, 1, segs = segs }
        list[#list + 1] = l
        return l
    end
    -- the game's line with its value marked, else a line of our own at the bottom
    local function Line(text, value, dir, old, prefix, rgb)
        local i = Find(text, prefix)
        if i then
            used[i] = true
            lines[i].segs = Valued(lines[i][1], value, dir, old)
        else
            missed = missed + 1
            Own(tail, text, Valued(text, value, dir, old), rgb)
        end
    end
    -- a value Forever dropped: struck whole, red for a loss, or the colour of what dropping it means
    local function Removed(text, dir, rgb) Own(tail, text, { { text, "gone", dir or "down" } }, rgb) end
    -- a value the item has on one side only; numeric: only the number is the value
    local function Pair(f, c, text, numeric, dir, onlyNew, onlyOld)
        local ft, ct = f and text(f), c and text(c)
        if ft and ct then Line(ft, numeric and tostring(f) or ft, dir, numeric and tostring(c) or ct)
        elseif ft then Line(ft, numeric and tostring(f) or ft, onlyNew)
        elseif ct then Removed(ct, onlyOld) end
    end

    if ch.q and row then
        local label = G("QUALITY", "Quality") .. ": "
        Own(head, label .. QualityName(row.q), Segs({ label }, { QualityName(row.q), Dir(row.q, ch.q) }, { QualityName(ch.q), "old" }))
    end
    if ch.ilvl and row then
        local text = (G("ITEM_LEVEL", "Item Level %d")):format(row.ilvl)
        local i = Find(text)
        local segs = Valued(text, tostring(row.ilvl), Dir(row.ilvl, ch.ilvl), tostring(ch.ilvl))
        if i then
            used[i] = true
            lines[i].segs = Valued(lines[i][1], tostring(row.ilvl), Dir(row.ilvl, ch.ilvl), tostring(ch.ilvl))
        else
            Own(head, text, segs, GOLD)
        end
    end
    local levelFmt = G("ITEM_MIN_LEVEL", "Requires Level %d")
    if ch.req and row then
        local f, c = row.req > 0 and row.req or nil, ch.req > 0 and ch.req or nil
        Pair(f, c, function(v) return levelFmt:format(v) end, true, Dir(f, c, true), "down", "up")
    end
    if ch.bind then Pair(BindText(ch.bind[1]) and ch.bind[1], BindText(ch.bind[2]) and ch.bind[2], BindText, false, "flat", "flat", "flat") end
    if ch.unique then
        Pair(UniqueText(ch.unique[1]) and ch.unique[1], UniqueText(ch.unique[2]) and ch.unique[2], UniqueText, false, "flat", "flat", "flat")
    end
    if ch.slots then
        local text = (G("CONTAINER_SLOTS", "%d Slot %s")):format(ch.slots[1], ""):gsub("%s+$", "")
        Line(text, tostring(ch.slots[1]), Dir(ch.slots[1], ch.slots[2]), tostring(ch.slots[2]), true)
    end
    if ch.armor then
        Line((G("ARMOR_TEMPLATE", "%s Armor")):format(ch.armor[1]), tostring(ch.armor[1]), Dir(ch.armor[1], ch.armor[2]), tostring(ch.armor[2]))
    end
    if ch.dmg then
        local f, c = ch.dmg[1], ch.dmg[2]
        local fr, cr = ("%d - %d"):format(f[1], f[2]), ("%d - %d"):format(c[1], c[2])
        local fs, cs = ("%.2f"):format(f[3] / 1000), ("%.2f"):format(c[3] / 1000)
        local i = Find(fr, true)
        local l = i and lines[i]
        if l then
            used[i] = true
        else
            missed = missed + 1
            l = Own(tail, (G("DAMAGE_TEMPLATE", "%s - %s Damage")):format(f[1], f[2]))
            l[2] = ("%s %s"):format(G("SPEED", "Speed"), fs)
        end
        if fr ~= cr then l.segs = Valued(l[1], fr, Dir(f[1] + f[2], c[1] + c[2]), cr) end
        -- speed: neither faster nor slower is better on its own
        if fs ~= cs then l.rsegs = Valued(l[2], fs, "flat", cs) end
        -- damage per second follows damage and speed: Classic's from Classic's numbers; one that did not move stays plain
        local fd, cd = DpsText(f), DpsText(c)
        if fd ~= cd then Line((G("DPS_TEMPLATE", "(%s damage per second)")):format(fd), fd, Dir(tonumber(fd), tonumber(cd)), cd) end
    end
    for _, s in ipairs(ch.stats or {}) do
        local ct = s[3] and StatLine(s[1], s[3])
        if s[2] then
            local ft, isWhite = StatLine(s[1], s[2])
            local rgb = not isWhite and GREEN or nil
            if ft and ct then
                Line(ft, FirstNumber(ft), Dir(s[2], s[3]), FirstNumber(ct) or tostring(s[3]), nil, rgb)
            elseif ft then
                Line(ft, FirstNumber(ft), "up", nil, nil, rgb)
            end
        elseif ct then
            local _, isWhite = StatLine(s[1], s[3])
            Removed(ct, "down", not isWhite and GREEN or nil)
        end
    end
    -- an effect: every changed number in its direction with Classic's right after it, when only numbers moved and our
    -- words are in the line; else the effect's words in orange, Classic's other words small and struck after them
    local function MarkEffect(l, e, word)
        local text = l[1]
        local at = e.spans and text:find(e.text, 1, true)
        if at then
            local segs, cursor = {}, 1
            for _, sp in ipairs(e.spans) do
                local a = at - 1 + sp[1]
                local new = text:sub(a, a + sp[2] - 1)
                segs[#segs + 1] = { text:sub(cursor, a - 1) }
                segs[#segs + 1] = { new, EffectDir(text, a, sp[2], new, sp[3]) }
                segs[#segs + 1] = { sp[3], "old" }
                cursor = a + sp[2]
            end
            segs[#segs + 1] = { text:sub(cursor) }
            local kept = {}
            for _, sg in ipairs(segs) do if sg[1] ~= "" then kept[#kept + 1] = sg end end
            l.segs = kept
            return
        end
        local old = e.how ~= "+" and e.was ~= "" and e.was or nil
        if not old and e.how ~= "+" and e.spans then
            local olds = {}
            for k, sp in ipairs(e.spans) do olds[k] = sp[3] end
            old = table.concat(olds, ", ")
        end
        local start = word .. " "
        if text:sub(1, #start) == start then
            l.segs = Segs({ start }, { text:sub(#start + 1), "flat" }, old and { old, "old" })
        else
            l.segs = Segs({ text, "flat" }, old and { old, "old" })
        end
    end
    -- the line with the same words first; a line known only by its spell's name, or worded otherwise, is the one Use or
    -- Chance on hit line of the tooltip (Equip lines also carry stats, so they are never guessed)
    local pending = {}
    for _, e in ipairs(ch.effects or {}) do
        local word = TRIGGERS[e.trig] and G(TRIGGERS[e.trig][1], TRIGGERS[e.trig][2])
        if word then
            local text = word .. " " .. e.text
            if e.how == "-" then
                Removed(text, "down", GREEN)
            else
                local i = not e.named and Find(text)
                if i then
                    used[i] = true
                    MarkEffect(lines[i], e, word)
                else
                    pending[#pending + 1] = { e, word, text }
                end
            end
        end
    end
    for _, p in ipairs(pending) do
        local e, word, text = p[1], p[2], p[3]
        local only
        if e.trig ~= 1 then
            local start = Norm(word) .. " "
            for i, l in ipairs(lines) do
                if not used[i] and Norm(l[1]):sub(1, #start) == start then
                    if only then only = false break end
                    only = i
                end
            end
        end
        if only then
            used[only] = true
            MarkEffect(lines[only], e, word)
        else
            missed = missed + 1
            MarkEffect(Own(tail, text, nil, GREEN), e, word)
        end
    end

    for i = #head, 1, -1 do table.insert(lines, 1, head[i]) end
    for _, l in ipairs(tail) do lines[#lines + 1] = l end
    return true, missed
end

-- the look of each kind: board E4's green and red, the changed tag's orange, and the faint grey of an old value
local LOOK = { up = "1EFF00", down = "FF5A36", flat = T.TAG.c.fg, old = T.C.faint }
-- the board's sizes: lines 13, an old value 11 with 4 before it; rows of 17
local BIG, SMALL, OLD_GAP, ROW, SIDE_GAP = 13, 11, 4, 17, 8
local U = T.U

-- a length on whole physical pixels of this frame (PixelUtil's own rounding); as given where the client has none
local function Snap(v, scale)
    if PixelUtil and PixelUtil.GetNearestPixelSize then return PixelUtil.GetNearestPixelSize(v, scale) end
    return v
end
local function OnePixel(scale)
    if PixelUtil and PixelUtil.GetNearestPixelSize then return PixelUtil.GetNearestPixelSize(0, scale, 1) end
    return 1
end

-- one measuring string per size, on the lines' own frame
local measure = {}
local function Width(parent, text, small)
    local key = small and SMALL or BIG
    local m = measure[key]
    if not m then
        m = T.Text(parent, key, "FFFFFF")
        m:Hide()
        measure[key] = m
    end
    m:SetText(text)
    return m.GetUnboundedStringWidth and m:GetUnboundedStringWidth() or m:GetStringWidth()
end

-- a piece of a marked line: a font string, and the 1-pixel strike across it when it is an old or dropped value
local function Piece(holder, parent, n)
    holder.pieces = holder.pieces or {}
    local p = holder.pieces[n]
    if not p then
        p = { fs = T.Text(parent, BIG, "FFFFFF"), strike = parent:CreateTexture(nil, "OVERLAY") }
        p.strike:SetTexture("Interface\\Buttons\\WHITE8X8")
        holder.pieces[n] = p
    end
    return p
end

function T.HideChangePieces(holder)
    for _, p in ipairs(holder.pieces or {}) do
        p.fs:Hide()
        p.strike:Hide()
    end
end

-- draws a marked line's segments into the box at height y, bodyW wide: pieces left to right on whole pixels, a row
-- ending at a space of plain or struck words, a new value kept on one row with Classic's value after it, so every strike
-- lies on its own row's words and never across a wrap. The right side (Speed) sits on the first row when it fits, else
-- on a row of its own under the left. Returns the height used and whether the right side took its own row.
function T.LayChangeLine(holder, l, bodyW, y, parent)
    local scale = parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
    local px = OnePixel(scale)
    local n, x, row = 0, 0, 0
    local function Put(text, kind, small, atX, atRow, rgb, strikeKind)
        n = n + 1
        local p = Piece(holder, parent, n)
        local fs = p.fs
        fs:SetFont(T.FONT, U(small and SMALL or BIG), "")
        fs:SetText(text)
        local hex = LOOK[kind == "gone" and strikeKind or kind]
        if hex then fs:SetTextColor(T.RGB(hex)) else fs:SetTextColor(rgb[1], rgb[2], rgb[3]) end
        local w = Snap(Width(parent, text, small), scale)
        -- an old value sits on the row's text bottom, as the board's smaller inline text does
        local top = Snap(y + atRow * U(ROW) + (small and (U(BIG) - U(SMALL)) or 0), scale)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", Snap(atX, scale), -top)
        fs:Show()
        if kind == "old" or kind == "gone" then
            p.strike:SetColorTexture(T.RGB(hex))
            p.strike:ClearAllPoints()
            p.strike:SetPoint("TOPLEFT", parent, "TOPLEFT", Snap(atX, scale), -(top + Snap(U(small and SMALL or BIG) / 2, scale)))
            p.strike:SetSize(w, px)
            p.strike:Show()
        else
            p.strike:Hide()
        end
        return w
    end
    local rgb = { l[3], l[4], l[5] }
    local segs = l.segs or { { l[1] } }
    for k, sg in ipairs(segs) do
        local text, kind = sg[1], sg[2]
        local small = kind == "old"
        local gap = small and Snap(U(OLD_GAP), scale) or 0
        if kind == "up" or kind == "down" or kind == "flat" then
            -- a value is one piece; it starts a row of its own when it and the old value after it do not fit here
            local w = Width(parent, text, false)
            local nextSeg = segs[k + 1]
            local tail = nextSeg and nextSeg[2] == "old" and (Snap(U(OLD_GAP), scale) + Width(parent, nextSeg[1]:match("^%S+") or nextSeg[1], true)) or 0
            if x > 0 and x + w + tail > bodyW then
                x, row = 0, row + 1
                text = text:gsub("^%s+", "")
            end
            if w <= bodyW or x > 0 then
                x = x + Put(text, kind, false, x, row, rgb)
            else
                -- longer than a row: its words flow like plain words, each row's run one piece in the value's colour
                local run = ""
                for tok in text:gmatch("%s*%S+%s*") do
                    local try = run .. tok
                    if run ~= "" and x + Width(parent, try, false) > bodyW then
                        x = x + Put(run, kind, false, x, row, rgb)
                        x, row, run = 0, row + 1, tok:gsub("^%s+", "")
                    else
                        run = try
                    end
                end
                if run ~= "" then x = x + Put(run, kind, false, x, row, rgb) end
            end
        else
            -- plain, old or dropped words: runs per row, broken at spaces; each run is one piece (an old or dropped
            -- run carries its own strike)
            local run = ""
            for tok in text:gmatch("%s*%S+%s*") do
                local try = run .. tok
                if x + gap + Width(parent, try, small) > bodyW and (run ~= "" or x > 0) then
                    if run ~= "" then x = x + gap + Put(run, kind, small, x + gap, row, rgb, sg[3]) end
                    x, row, gap, run = 0, row + 1, 0, tok:gsub("^%s+", "")
                else
                    run = try
                end
            end
            if run ~= "" then x = x + gap + Put(run, kind, small, x + gap, row, rgb, sg[3]) end
        end
    end
    local rows = row + 1
    local stacked = false
    holder.leftPieces = n
    local rsegs = l.rsegs or (l[2] ~= "" and { { l[2] } }) or nil
    if rsegs then
        local rrgb = { l[6], l[7], l[8] }
        -- the right side's width, its pieces laid from its left edge
        local widths, total = {}, 0
        for k, sg in ipairs(rsegs) do
            widths[k] = Snap(Width(parent, sg[1], sg[2] == "old"), scale) + (sg[2] == "old" and Snap(U(OLD_GAP), scale) or 0)
            total = total + widths[k]
        end
        local rx = bodyW - total
        local rrow = 0
        if rows > 1 or x + U(SIDE_GAP) > rx then
            stacked, rrow, rows = true, rows, rows + 1
        end
        for k, sg in ipairs(rsegs) do
            local small = sg[2] == "old"
            local gap = small and Snap(U(OLD_GAP), scale) or 0
            Put(sg[1], sg[2], small, rx + gap, rrow, rrgb, sg[3])
            rx = rx + widths[k]
        end
    end
    for i = n + 1, #(holder.pieces or {}) do
        holder.pieces[i].fs:Hide()
        holder.pieces[i].strike:Hide()
    end
    return rows * U(ROW), stacked
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id) T.ItemArrived(id) end)
