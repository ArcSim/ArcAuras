-- AD_ImbueTooltip: a "With your weapon" line on weapon imbue and weapon stone
-- tooltips (Rockbiter, Flametongue, Frostbrand and Windfury Weapon; sharpening
-- stones and weightstones): what each adds per hit and per second with the
-- main-hand weapon, worked from the numbers the tooltip prints (the realm's own
-- values), read through its language's words: no patterns for it, no line.
-- Opt-in on Modules > Tooltip IDs. Secret weapon reads (stats restricted): no line.
local ADDON, NS = ...

local IT = {}
NS.ImbueTooltip = IT

-- the client's words; English while the theme is not loaded
local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

IT.SETTING = "tooltipImbueDamage"
IT.MAIN_HAND = 16
-- attack power per point of damage per second of swing
IT.AP_PER_DPS = 14
-- Frostbrand's procs per minute, measured in combat logs: the game's data has no rate.
IT.FROSTBRAND_PPM = 8
-- seconds between Windfury procs, from its proc spell
IT.WINDFURY_LOCKOUT = 1.5
IT.STORMSTRIKE = 17364
-- Rockbiter's enchant IDs and the rank spell whose text holds that enchant's attack power
IT.ROCKBITER_ENCHANTS = {
    [29] = 8017, [6] = 8018, [1] = 8019, [503] = 10399,
    [1663] = 16314, [683] = 16315, [1664] = 16316, [7568] = 461635,
}

-- The imbues by name: every rank shares its rank 1 spell's name, which the
-- game gives in the client's language; the English names stand in until it
-- answers. The stones are found by their text on any item.
IT.IMBUE_IDS = { rockbiter = 8017, flametongue = 8024, frostbrand = 8033, windfury = 8232 }
IT.IMBUES = {
    ["Rockbiter Weapon"] = "rockbiter",
    ["Flametongue Weapon"] = "flametongue",
    ["Frostbrand Weapon"] = "frostbrand",
    ["Windfury Weapon"] = "windfury",
}
IT.PATTERNS = {
    rockbiter = "attack power by (%d+)",
    flametongue = "causes (%d+) to (%d+) additional Fire damage",
    frostbrand = "chance of causing (%d+) additional Frost damage",
    windfury = "(%d+)%% chance of granting you (%d+) extra %a+ with (%d+) extra melee attack power",
    strike = "strike for (%d+)%% weapon damage",
    stones = { "sharp weapon damage by (%d+)", "damage of a blunt weapon by (%d+)" },
}
-- the patterns per client language; one missing here means no line there
IT.PATTERNS_BY_LOCALE = { enUS = IT.PATTERNS, enGB = IT.PATTERNS }

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- The patterns for this client's words, or nil when there are none.
function IT.Patterns()
    local loc = GetLocale and GetLocale()
    if loc == nil then return IT.PATTERNS end
    return IT.PATTERNS_BY_LOCALE[loc]
end

-- An imbue's kind from its spell's name: this client's names (read from the
-- rank 1 spells, kept once every one answered), else the English ones.
function IT.KindOf(name)
    if type(name) ~= "string" or Secret(name) then return nil end
    if not IT.names then
        local t, all = {}, true
        local get = C_Spell and C_Spell.GetSpellName
        for kind, id in pairs(IT.IMBUE_IDS) do
            local n = get and get(id) -- raw-id: an imbue's rank 1, for its name
            if type(n) == "string" and n ~= "" and not Secret(n) then t[n] = kind else all = false end
        end
        if all then IT.names = t end
        if t[name] then return t[name] end
    elseif IT.names[name] then
        return IT.names[name]
    end
    return IT.IMBUES[name]
end

-- On only when switched on, and with the Tooltip IDs module it lives under.
function IT.Enabled()
    local S = NS.Store
    return S ~= nil and S.GetSetting ~= nil and S.GetSetting(IT.SETTING) == true
        and S.GetSetting("tooltipIDs") ~= false
end

-- The main hand's swing time and average hit (UnitDamage's min and max carry
-- attack power and damage modifiers already), or nil with no weapon or while
-- they read secret.
function IT.Weapon()
    local item = GetInventoryItemID and GetInventoryItemID("player", IT.MAIN_HAND)
    if item == nil or Secret(item) then return nil end
    local speed = UnitAttackSpeed and UnitAttackSpeed("player")
    if Secret(speed) or type(speed) ~= "number" or speed <= 0 then return nil end
    local lo, hi = UnitDamage("player")
    if Secret(lo) or Secret(hi) or type(lo) ~= "number" or type(hi) ~= "number" then return nil end
    return speed, (lo + hi) / 2
end

local function Description(spellID)
    local get = C_Spell and C_Spell.GetSpellDescription
    local text = get and get(spellID) -- raw-id: a fixed imbue rank or strike
    if type(text) ~= "string" or Secret(text) then return nil end
    return text
end

-- Stormstrike while the player knows it: its cooldown in seconds and its share
-- of a weapon hit; nil otherwise, so a line counts swings alone.
function IT.Strike()
    local P = IT.Patterns()
    local catalog = NS.SpellCatalog
    if not (P and catalog and catalog.Known and catalog.Known(IT.STORMSTRIKE)) then return nil end
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(IT.STORMSTRIKE) -- raw-id: a fixed strike
    if Secret(ms) or type(ms) ~= "number" or ms <= 0 then return nil end
    local text = Description(IT.STORMSTRIKE)
    local pct = text and tonumber(text:match(P.strike))
    if not pct then return nil end
    return { cooldown = ms / 1000, weapon = pct / 100 }
end

-- What Rockbiter adds to UnitDamage's average while it is on the main hand: an
-- imbue put in its place would lose it. 0 with none on, nil when it cannot be read.
function IT.WornHit(speed)
    local P = IT.Patterns()
    local DE = NS.DriverEnchant
    if not (P and DE and DE.ReadHand) then return 0 end
    local list = DE.ReadHand("main")
    if list == nil then return nil end
    for _, e in ipairs(list) do
        local spell = IT.ROCKBITER_ENCHANTS[e.id]
        if spell then
            local text = Description(spell)
            local ap = text and tonumber(text:match(P.rockbiter))
            return ap and ap / IT.AP_PER_DPS * speed or nil
        end
    end
    return 0
end

-- The tooltip's lines as one string, or nil when any of them reads secret.
function IT.Text(data)
    local parts = {}
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if Secret(t) then return nil end
        if type(t) == "string" then parts[#parts + 1] = t end
    end
    return table.concat(parts, " ")
end

-- Damage per hit and per second, worked from the tooltip's numbers:
-- attack power adds AP / 14 per second of swing; Flametongue's high end is its
-- per-hit damage on a 4.0 speed weapon (the tooltip's own formula), so a hit
-- is high / 4 per second of swing; Frostbrand is an average (its damage at its
-- procs per minute); Windfury is an average (its chance x its extra attacks,
-- each a main-hand hit with the extra attack power, less its lockout); a stone
-- adds its number to every hit. strike (IT.Strike, optional) adds Stormstrike's
-- hits: weapon damage counts at its share of a weapon hit, a flat or proc effect
-- once per hit. Returns perHit, dps, avg (true = an average) or nil when the
-- text does not match or this client has no patterns.
function IT.Gain(kind, text, speed, avgHit, strike)
    local P = IT.Patterns()
    if not P then return nil end
    local strikeHits = strike and 1 / strike.cooldown or 0
    local strikeShare = strike and strike.weapon / strike.cooldown or 0
    if kind == "rockbiter" then
        local ap = tonumber(text:match(P.rockbiter))
        if not ap then return nil end
        local hit = ap / IT.AP_PER_DPS * speed
        return hit, hit / speed + hit * strikeShare
    elseif kind == "flametongue" then
        local lo, hi = text:match(P.flametongue)
        lo, hi = tonumber(lo), tonumber(hi)
        if not (lo and hi) then return nil end
        local hit = math.max(lo, math.min(hi, hi / 4 * speed))
        return hit, hit / speed + hit * strikeHits
    elseif kind == "frostbrand" then
        local hit = tonumber(text:match(P.frostbrand))
        if not hit then return nil end
        local chance = math.min(1, IT.FROSTBRAND_PPM * speed / 60)
        return hit, hit * chance * (1 / speed + strikeHits), true
    elseif kind == "windfury" then
        local chance, n, ap = text:match(P.windfury)
        chance, n, ap = tonumber(chance), tonumber(n), tonumber(ap)
        if not (chance and n and ap) then return nil end
        local perProc = n * (avgHit + ap / IT.AP_PER_DPS * speed)
        local rolls = (1 / speed + strikeHits) * chance / 100
        return perProc, perProc * rolls / (1 + rolls * IT.WINDFURY_LOCKOUT), true
    elseif kind == "stone" then
        for _, pat in ipairs(P.stones) do
            local n = tonumber(text:match(pat))
            if n then return n, n / speed + n * strikeShare end
        end
    end
    return nil
end

-- the two lines for a gain: which weapon, then the numbers
function IT.Lines(speed, perHit, dps, avg)
    local head = Tr("With your weapon (%.2f speed)"):format(speed)
    local body
    if avg then
        body = Tr("+%.1f per proc, +%.1f DPS on average"):format(perHit, dps)
    else
        body = Tr("+%.1f per hit, +%.1f DPS"):format(perHit, dps)
    end
    return head, body
end

-- One block per tooltip build: OnTooltipCleared resets it.
local function Clear(tooltip)
    tooltip._adImbueDone = nil
end

function IT.Append(tooltip, data)
    if not IT.Enabled() or not IT.Patterns() then return end
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if type(data) ~= "table" or Secret(data.id) or data.id == nil then return end
    local kind
    local D = Enum and Enum.TooltipDataType
    if D and data.type == D.Spell then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(data.id) -- raw-id: a tooltip's own data ID
        if Secret(name) then return end
        kind = name and IT.KindOf(name)
    elseif D and data.type == D.Item then
        kind = "stone"
    end
    if not kind then return end
    if tooltip._adImbueDone == data.id then return end
    local speed, avgHit = IT.Weapon()
    if not speed then return end
    if kind == "windfury" then
        local worn = IT.WornHit(speed)
        if not worn then return end
        avgHit = avgHit - worn
    end
    local text = IT.Text(data)
    if not text then return end
    local perHit, dps, avg = IT.Gain(kind, text, speed, avgHit, IT.Strike())
    if not perHit then return end
    tooltip._adImbueDone = data.id
    if not tooltip._adImbueHooked and tooltip.HookScript then
        tooltip._adImbueHooked = true
        if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") then
            tooltip:HookScript("OnTooltipCleared", Clear)
        end
        tooltip:HookScript("OnHide", Clear)
    end
    local head, body = IT.Lines(speed, perHit, dps, avg)
    tooltip:AddLine(" ")
    tooltip:AddLine(head, 0.25, 0.79, 0.95)
    tooltip:AddLine(body, 1, 1, 1)
    tooltip:Show()
end

-- Registered at load, before the ID block (installed at PLAYER_ENTERING_WORLD),
-- so the line sits above it; each call asks the switch first.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    for _, key in ipairs({ "Spell", "Item" }) do
        local dt = Enum.TooltipDataType[key]
        if dt then TooltipDataProcessor.AddTooltipPostCall(dt, IT.Append) end
    end
end
