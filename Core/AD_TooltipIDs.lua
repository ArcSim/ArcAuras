-- Adds an ID block to tooltips built from game data (spells, auras, items,
-- toys, mounts, currencies, achievements, quests; our own icons included),
-- with icon and Cooldown Manager IDs, and node IDs on talent buttons.
-- Taint: post-calls only, and the hovered frame is only ever read.
local ADDON, NS = ...

NS.TooltipIDs = {}
local T = NS.TooltipIDs

local HEADER = "|cff3fc9f2Arc Auras IDs|r"
local KEY_COLOR = "|cffffd100"

local function Enabled()
    return NS.Store and NS.Store.GetSetting
        and NS.Store.GetSetting("tooltipIDs") ~= false
end

-- Which parts of the block show (Modules > Tooltip IDs): each is on unless
-- switched off, so the block reads as it always did until someone picks.
-- Parts: "Data" (the spell / item / ... ID), "Icons", "CDM", "Talent".
local function Part(key)
    return NS.Store.GetSetting("tooltipIDs" .. key) ~= false
end

local function IsSecret(v)
    return (issecretvalue and issecretvalue(v)) and true or false
end

-- A secret is never compared, formatted or printed: its line is left out
-- until the combat-drop recheck can read it.
local function Val(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then return tostring(v) end
    return nil
end

local function AddLine(tooltip, key, value)
    if value == nil then return end
    tooltip:AddDoubleLine(KEY_COLOR .. key .. "|r", value, 1, 1, 1, 1, 1, 1)
end

-- The block's lines are gathered first, so an id with nothing left to show
-- (every part switched off) never leaves a bare header.
local function Push(out, key, value)
    if value == nil then return end
    out[#out + 1] = { key, value }
end

local LABELS
local function BuildLabels()
    if LABELS or not (Enum and Enum.TooltipDataType) then return end
    local D = Enum.TooltipDataType
    LABELS = {}
    local map = {
        { D.Spell,       "Spell ID" },
        { D.Item,        "Item ID" },
        { D.UnitAura,    "Aura Spell ID" },
        { D.Toy,         "Toy Item ID" },
        { D.Mount,       "Mount ID" },
        { D.Currency,    "Currency ID" },
        { D.Achievement, "Achievement ID" },
        { D.Quest,       "Quest ID" },
    }
    for _, e in ipairs(map) do
        if e[1] then LABELS[e[1]] = e[2] end
    end
end

-- Art file ID for a tooltip's data id; for a spell, the current icon plus the
-- base art an override replaced. Uncached items and unknown ids give nothing.
local function IconOf(dtype, id)
    local D = Enum.TooltipDataType
    if dtype == D.Spell or dtype == D.UnitAura then
        if C_Spell and C_Spell.GetSpellTexture then
            local icon, original = C_Spell.GetSpellTexture(id)
            return icon, original
        end
    elseif dtype == D.Item or dtype == D.Toy then
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    elseif dtype == D.Mount then
        if C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, _, icon = C_MountJournal.GetMountInfoByID(id)
            return icon
        end
    elseif dtype == D.Currency then
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(id)
        if type(info) == "table" then return info.iconFileID end
    elseif dtype == D.Achievement then
        if GetAchievementInfo then
            local _, _, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
            return icon
        end
    end
end

-- The art the hovered button shows, from its .icon or .Icon texture (action
-- buttons, buffs, bags and our icons). Forbidden frames and secrets give nil.
local function ShownIconOf(owner)
    if IsSecret(owner) or type(owner) ~= "table" then return nil end
    if owner.IsForbidden and owner:IsForbidden() then return nil end
    local tex = owner.icon
    if tex == nil then tex = owner.Icon end
    if IsSecret(tex) or type(tex) ~= "table" then return nil end
    if tex.IsForbidden and tex:IsForbidden() then return nil end
    if not (tex.GetObjectType and tex.GetTexture) then return nil end
    if tex:GetObjectType() ~= "Texture" then return nil end
    local v = tex:GetTexture()
    if IsSecret(v) then return nil end
    return v
end

-- Cooldown Manager IDs: spell -> cooldown IDs (base, override, tooltip
-- override and linked spells all point at the entry) and inventory slot ->
-- cooldown IDs. Plain C returns on Forever; no Blizzard Lua runs. These are
-- the categories Blizzard's settings data provider queries. The enum also has
-- UI-only values (HiddenActive -1, HiddenPassive -2) that raise a usage error
-- in GetCooldownViewerCategorySet, and GroupBuff has its own API.
local CD_CATS = {
    { "Essential", "Essential" }, { "Utility", "Utility" },
    { "TrackedBuff", "Buff" }, { "TrackedBar", "Bar" },
    { "EquipSlotEssential", "Equipped" }, { "EquipSlotTracked", "Equipped" },
    { "SpecAgnosticEssential", "Essential" }, { "SpecAgnosticTracked", "Tracked" },
}
local cdMap

local function CDMapAdd(bucket, key, cid, cat)
    if type(key) ~= "number" or IsSecret(key) then return end
    local list = bucket[key]
    if not list then
        list = {}
        bucket[key] = list
    end
    for _, e in ipairs(list) do
        if e.id == cid then return end
    end
    list[#list + 1] = { id = cid, cat = cat }
end

local function CDMap()
    if cdMap then return cdMap end
    local CV = C_CooldownViewer
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo
        and Enum and Enum.CooldownViewerCategory) then
        return nil
    end
    local map, any = { spell = {}, slot = {} }, false
    -- Fixed order, so a spell in two categories always lists them alike. Only
    -- a real category (>= 0) reaches the API; true = include unlearned spells.
    -- An empty read is not cached, since the tables load late.
    for _, c in ipairs(CD_CATS) do
        local cat = Enum.CooldownViewerCategory[c[1]]
        local ids = type(cat) == "number" and cat >= 0
            and CV.GetCooldownViewerCategorySet(cat, true)
        if type(ids) == "table" then
            local word = c[2]
            for _, cid in ipairs(ids) do
                local info = type(cid) == "number" and not IsSecret(cid)
                    and CV.GetCooldownViewerCooldownInfo(cid)
                if type(info) == "table" then
                    any = true
                    CDMapAdd(map.spell, info.spellID, cid, word)
                    CDMapAdd(map.spell, info.overrideSpellID, cid, word)
                    CDMapAdd(map.spell, info.overrideTooltipSpellID, cid, word)
                    if type(info.linkedSpellIDs) == "table" then
                        for _, l in ipairs(info.linkedSpellIDs) do
                            CDMapAdd(map.spell, l, cid, word)
                        end
                    end
                    CDMapAdd(map.slot, info.equipSlot, cid, word)
                end
            end
        end
    end
    if any then cdMap = map end
    return map
end

-- One line per category, "200028-200037 (Essential)": Forever gives a ranked
-- spell an entry per rank, so a joined list ran across the screen. IDs sort,
-- consecutive runs of three or more fold into a range, and past MAX_RUNS the
-- rest is counted. An item answers only while it is equipped in a slot the
-- Cooldown Manager tracks.
local MAX_RUNS = 4
local function CooldownLines(dtype, id)
    local D = Enum.TooltipDataType
    local map = CDMap()
    if not map then return nil end
    local list
    if dtype == D.Spell or dtype == D.UnitAura then
        list = map.spell[id]
    elseif dtype == D.Item and GetInventoryItemID then
        for slot, l in pairs(map.slot) do
            local iid = GetInventoryItemID("player", slot)
            if iid ~= nil and not IsSecret(iid) and iid == id then
                list = l
                break
            end
        end
    end
    if not list or #list == 0 then return nil end
    -- the map holds plain ids only (CDMapAdd), so sorting and adding is safe
    local order, byCat = {}, {}
    for _, e in ipairs(list) do
        local ids = byCat[e.cat]
        if not ids then
            ids = {}
            byCat[e.cat] = ids
            order[#order + 1] = e.cat
        end
        ids[#ids + 1] = e.id
    end
    local lines = {}
    for _, cat in ipairs(order) do
        local ids = byCat[cat]
        table.sort(ids)
        local runs, i = {}, 1
        while i <= #ids do
            local j = i
            while j < #ids and ids[j + 1] == ids[j] + 1 do j = j + 1 end
            if j - i >= 2 then
                runs[#runs + 1] = ids[i] .. "-" .. ids[j]
            else
                for k = i, j do runs[#runs + 1] = tostring(ids[k]) end
            end
            i = j + 1
        end
        if #runs > MAX_RUNS then
            local more = #runs - MAX_RUNS
            for k = #runs, MAX_RUNS + 1, -1 do runs[k] = nil end
            runs[#runs + 1] = "+" .. more .. " more"
        end
        lines[#lines + 1] = table.concat(runs, ", ") .. " (" .. cat .. ")"
    end
    return lines
end

-- The first category line carries the key; the rest read as its continuation.
local function PushCooldown(out, dtype, id)
    local lines = CooldownLines(dtype, id)
    if not lines then return end
    for i, l in ipairs(lines) do Push(out, i == 1 and "Cooldown ID" or "", l) end
end

-- Icon, base icon, shown icon and Cooldown Manager lines. `id` is plain or
-- nil: a secret must not index the map or reach a lookup. `held` means the id
-- exists but is secret, so the shown art prints as "Shown icon ID" and the
-- "Icon ID" line the combat-drop recheck adds later is not a duplicate.
local function AddExtras(out, dtype, id, owner, held)
    if Part("Icons") then
        local icon, original
        if id ~= nil then icon, original = IconOf(dtype, id) end
        Push(out, "Icon ID", Val(icon))
        if original ~= nil and icon ~= nil and not IsSecret(original)
            and not IsSecret(icon) and original ~= icon then
            Push(out, "Base icon ID", Val(original))
        end
        local shown = ShownIconOf(owner)
        if shown ~= nil then
            if held then
                Push(out, "Shown icon ID", Val(shown))
            elseif icon == nil then
                Push(out, "Icon ID", Val(shown))
            elseif not IsSecret(icon) and shown ~= icon then
                Push(out, "Shown icon ID", Val(shown))
            end
        end
    end
    if id ~= nil and Part("CDM") then PushCooldown(out, dtype, id) end
end

-- Temporary weapon enchants (imbues, poisons, oils, stones): the game's enchant
-- buffs, the character pane and our enchant icons all show the weapon's own
-- item tooltip, so the enchant IDs ride on it. Only a tooltip built from the
-- player's main or off hand slot answers (the game reports enchants on
-- equipped weapons only). A buff whose picture is one enchant's shows that
-- one; otherwise every enchant, each with its time left to tell them apart.
local ENCHANT_HAND = { [16] = "main", [17] = "off" }
local function PushEnchants(out, tooltip, owner)
    local DE = NS.DriverEnchant
    local info = tooltip.processingInfo
    if not (DE and DE.ReadHand and type(info) == "table") then return end
    local args = info.getterArgs
    if info.getterName ~= "GetInventoryItem" or type(args) ~= "table" then return end
    local unit, slot = args[1], args[2]
    if IsSecret(unit) or IsSecret(slot) or unit ~= "player" or type(slot) ~= "number" then return end
    local hand = ENCHANT_HAND[slot]
    local list = hand and DE.ReadHand(hand)
    if not list or #list == 0 then return end
    if #list > 1 then
        local shown = ShownIconOf(owner)
        for _, e in ipairs(list) do
            if shown ~= nil and e.icon == shown then
                list = { e }
                break
            end
        end
    end
    for i, e in ipairs(list) do
        Push(out, i == 1 and "Enchant ID" or "", #list > 1 and DE.Describe(e) or Val(e.id))
    end
end

-- Talent buttons carry their node IDs as plain fields, on the button or a
-- close ancestor, so walk up a few parents.
local function NodeIDsFromOwner(owner)
    local f, hops = owner, 0
    while f and hops < 4 do
        local nodeID = f.nodeID or (f.nodeInfo and f.nodeInfo.ID)
        if nodeID ~= nil then
            local entryID = f.entryID
                or (f.entryInfo and f.entryInfo.entryID)
                or (f.nodeInfo and f.nodeInfo.activeEntry
                    and f.nodeInfo.activeEntry.entryID)
            local defID = f.definitionID
                or (f.entryInfo and f.entryInfo.definitionID)
            return nodeID, entryID, defID
        end
        f = f.GetParent and f:GetParent() or nil
        hops = hops + 1
    end
end

function T.Append(tooltip, data)
    if not Enabled() then return end
    -- "Only while holding Shift": read as the tooltip builds
    if NS.Store.GetSetting("tooltipIDsShift") == true
        and not (IsShiftKeyDown and IsShiftKeyDown()) then
        return
    end
    if not tooltip or not tooltip.GetOwner then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    BuildLabels()
    local label = LABELS and data and LABELS[data.type]
    local id = data and data.id
    -- Secrecy first: a secret id is never compared, truth-tested or keyed.
    local idSecret = IsSecret(id)
    local hasID = idSecret or id ~= nil
    local owner = tooltip:GetOwner()
    local nodeID, entryID, defID = NodeIDsFromOwner(owner)
    if not (label and hasID) and nodeID == nil then return end
    -- One block per tooltip build; OnTooltipCleared and OnHide clear the flag.
    -- A line-count guard fails: another ID addon appending after us changes
    -- the count, which reads as a rebuild, and both keep adding blocks.
    local dedup
    if idSecret then dedup = "secret" elseif id ~= nil then dedup = id else dedup = nodeID end
    if tooltip._adIDDone and tooltip._adIDGeneric == dedup then return end
    tooltip._adIDGeneric = dedup
    tooltip._adIDDone = true
    local out, idIndex = {}, nil
    if label and hasID and Part("Data") and not idSecret then
        Push(out, label, Val(id))
        idIndex = #out
        if data.type == Enum.TooltipDataType.Item then PushEnchants(out, tooltip, owner) end
    end
    -- A secret id goes in as nil; the combat-drop recheck adds its lines.
    AddExtras(out, data and data.type, (label and hasID and not idSecret) and id or nil,
        owner, label ~= nil and idSecret)
    if Part("Talent") then
        Push(out, "Node ID", Val(nodeID))
        Push(out, "Entry ID", Val(entryID))
        Push(out, "Definition ID", Val(defID))
    end
    if #out == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(HEADER)
    local idLine
    for i, l in ipairs(out) do
        AddLine(tooltip, l[1], l[2])
        if i == idIndex then idLine = tooltip:NumLines() end
    end
    -- The combat-drop recheck rewrites the id line in place (0 = the id line
    -- is switched off) and adds the lines the secret held back.
    if label and idSecret and (idLine or Part("Icons") or Part("CDM")) then
        tooltip._adIDSecretLine = idLine or 0
        T._pending = T._pending or setmetatable({}, { __mode = "k" })
        T._pending[tooltip] = true
    end
    tooltip:Show()
end

local function ClearBuild(tooltip)
    tooltip._adIDDone = nil
    tooltip._adIDGeneric = nil
    tooltip._adIDSecretLine = nil
    if T._pending then T._pending[tooltip] = nil end
end

-- Re-reads the id through the tooltip's stored C_TooltipInfo getter: a value
-- captured in combat stays secret. true = settled, false = still secret.
local function RecheckOne(tooltip)
    local line = tooltip._adIDSecretLine
    if not line or not tooltip:IsShown()
        or (tooltip.IsForbidden and tooltip:IsForbidden()) then
        return true
    end
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
        or tooltip.primaryTooltipInfo or tooltip.processingInfo or tooltip.info
    local getter = info and info.getterName and C_TooltipInfo
        and C_TooltipInfo[info.getterName]
    if type(getter) ~= "function" then return true end
    local fresh
    if info.getterArgs then
        -- A secret stored arg would throw inside the getter; keep "<secret>".
        local n = table.maxn(info.getterArgs)
        for i = 1, n do
            local a = info.getterArgs[i]
            if issecretvalue and issecretvalue(a) then return true end
        end
        -- maxn: a nil hole in the stored args must not truncate the call
        fresh = getter(unpack(info.getterArgs, 1, n))
    else
        fresh = getter()
    end
    if issecretvalue and issecretvalue(fresh) then return false end
    if type(fresh) ~= "table" then return true end
    local id = fresh and fresh.id
    if IsSecret(id) then return false end
    local text = Val(id)
    local ok = text ~= nil
    if ok and line > 0 then
        local name = tooltip.GetName and tooltip:GetName()
        local fs = name and _G[name .. "TextRight" .. line]
        ok = fs ~= nil and fs.SetText ~= nil
        if ok then fs:SetText(text) end
    elseif ok and Part("Data") then
        -- the id line was left out while the id was secret
        BuildLabels()
        AddLine(tooltip, (LABELS and LABELS[fresh.type]) or "ID", text)
    end
    if ok then
        -- The lines the secret id held back; the shown art printed already.
        if Part("Icons") then
            local icon, original = IconOf(fresh.type, id)
            AddLine(tooltip, "Icon ID", Val(icon))
            if original ~= nil and icon ~= nil and not IsSecret(original)
                and not IsSecret(icon) and original ~= icon then
                AddLine(tooltip, "Base icon ID", Val(original))
            end
        end
        if Part("CDM") then
            local lines = CooldownLines(fresh.type, id)
            for i, l in ipairs(lines or {}) do AddLine(tooltip, i == 1 and "Cooldown ID" or "", l) end
        end
        tooltip:Show()   -- re-fit the width to the longer value
    end
    tooltip._adIDSecretLine = nil
    return true
end

local function RecheckSecrets()
    if not T._pending then return end
    local again = false
    for tooltip in pairs(T._pending) do
        if RecheckOne(tooltip) == false then
            again = true
        else
            T._pending[tooltip] = nil
        end
    end
    return again
end

function T.Install()
    if T._installed then return end
    T._installed = true
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType) then
        return
    end
    for _, key in ipairs({ "Spell", "Item", "UnitAura", "Toy", "Mount",
        "Currency", "Achievement", "Quest" }) do
        local dt = Enum.TooltipDataType[key]
        if dt then
            TooltipDataProcessor.AddTooltipPostCall(dt, function(tooltip, data)
                -- protected widget tooltips must never be touched
                if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then
                    return
                end
                T.Append(tooltip, data)
            end)
        end
    end
    if GameTooltip and GameTooltip.HookScript then
        -- reset the per-build guard so the next hover prints again
        GameTooltip:HookScript("OnHide", ClearBuild)
        if GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipCleared") then
            GameTooltip:HookScript("OnTooltipCleared", ClearBuild)
        end
    end
    -- A table reload or a spec change (new category sets) drops the Cooldown
    -- Manager map for the next tooltip to rebuild. Missing events are skipped.
    local cdEv = CreateFrame("Frame")
    for _, e in ipairs({ "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED",
        "PLAYER_SPECIALIZATION_CHANGED" }) do
        if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(e) then
            cdEv:RegisterEvent(e)
        end
    end
    cdEv:SetScript("OnEvent", function() cdMap = nil end)
    -- Leaving combat re-reads each "<secret>" id on a tooltip still shown.
    -- Secrecy can lift a moment after the event, so two more tries follow.
    local regen = CreateFrame("Frame")
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    regen:SetScript("OnEvent", function()
        if not RecheckSecrets() then return end
        C_Timer.After(0.3, function()
            if RecheckSecrets() then C_Timer.After(1, RecheckSecrets) end
        end)
    end)
end

-- No hooks while the setting is off (it is on unless explicitly false). By
-- PLAYER_ENTERING_WORLD, unlike PLAYER_LOGIN, Store.Init has always run.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if Enabled() then T.Install() end
end)
