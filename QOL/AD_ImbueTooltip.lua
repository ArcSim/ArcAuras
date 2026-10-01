-- AD_ImbueTooltip: a "With your weapon" line on weapon imbue and weapon stone
-- tooltips (Rockbiter, Flametongue and Windfury Weapon; sharpening stones and
-- weightstones): what each adds per hit and per second with the main-hand
-- weapon, worked from the numbers the tooltip itself prints, so it follows
-- the realm's own values (English text). Opt-in on Modules > Tooltip IDs.
-- The weapon reads are secret while unit stats are restricted: no line then.
local ADDON, NS = ...

local IT = {}
NS.ImbueTooltip = IT

IT.SETTING = "tooltipImbueDamage"
IT.MAIN_HAND = 16
-- attack power per point of damage per second of swing
IT.AP_PER_DPS = 14

-- The imbues by spell name; the stones are found by their text on any item.
IT.IMBUES = {
    ["Rockbiter Weapon"] = "rockbiter",
    ["Flametongue Weapon"] = "flametongue",
    ["Windfury Weapon"] = "windfury",
}
IT.PATTERNS = {
    rockbiter = "attack power by (%d+)",
    flametongue = "causes (%d+) to (%d+) additional Fire damage",
    windfury = "(%d+)%% chance of granting you (%d+) extra %a+ with (%d+) extra melee attack power",
    stones = { "sharp weapon damage by (%d+)", "damage of a blunt weapon by (%d+)" },
}

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
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
-- is high / 4 per second of swing; Windfury is an average (its chance x its
-- extra attacks, each a main-hand hit with the extra attack power); a stone
-- adds its number to every hit. Returns perHit, dps, avg (true = an average)
-- or nil when the text does not match.
function IT.Gain(kind, text, speed, avgHit)
    local P = IT.PATTERNS
    if kind == "rockbiter" then
        local ap = tonumber(text:match(P.rockbiter))
        if not ap then return nil end
        local dps = ap / IT.AP_PER_DPS
        return dps * speed, dps
    elseif kind == "flametongue" then
        local lo, hi = text:match(P.flametongue)
        lo, hi = tonumber(lo), tonumber(hi)
        if not (lo and hi) then return nil end
        local hit = math.max(lo, math.min(hi, hi / 4 * speed))
        return hit, hit / speed
    elseif kind == "windfury" then
        local chance, n, ap = text:match(P.windfury)
        chance, n, ap = tonumber(chance), tonumber(n), tonumber(ap)
        if not (chance and n and ap) then return nil end
        local perProc = n * (avgHit + ap / IT.AP_PER_DPS * speed)
        local perSwing = chance / 100 * perProc
        return perProc, perSwing / speed, true
    elseif kind == "stone" then
        for _, pat in ipairs(P.stones) do
            local n = tonumber(text:match(pat))
            if n then return n, n / speed end
        end
    end
    return nil
end

-- the two lines for a gain: which weapon, then the numbers
function IT.Lines(speed, perHit, dps, avg)
    local head = ("With your weapon (%.2f speed)"):format(speed)
    local body
    if avg then
        body = ("+%.1f per proc, +%.1f DPS on average"):format(perHit, dps)
    else
        body = ("+%.1f per hit, +%.1f DPS"):format(perHit, dps)
    end
    return head, body
end

-- One block per tooltip build: OnTooltipCleared resets it.
local function Clear(tooltip)
    tooltip._adImbueDone = nil
end

function IT.Append(tooltip, data)
    if not IT.Enabled() then return end
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if type(data) ~= "table" or Secret(data.id) or data.id == nil then return end
    local kind
    local D = Enum and Enum.TooltipDataType
    if D and data.type == D.Spell then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(data.id)
        if Secret(name) then return end
        kind = name and IT.IMBUES[name]
    elseif D and data.type == D.Item then
        kind = "stone"
    end
    if not kind then return end
    if tooltip._adImbueDone == data.id then return end
    local speed, avgHit = IT.Weapon()
    if not speed then return end
    local text = IT.Text(data)
    if not text then return end
    local perHit, dps, avg = IT.Gain(kind, text, speed, avgHit)
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
