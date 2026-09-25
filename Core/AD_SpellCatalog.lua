-- The player's cooldown-worthy spells, for the Add window's search, and the
-- talent nodes that load conditions test. Both scan on first use and again
-- after a relevant change; the spell scan is skipped in combat.

local ADDON, NS = ...
local Events = NS.Events

local Catalog = {}
NS.SpellCatalog = Catalog

local entries = {}       -- sorted { {spellID, name, nameLower, texture, hasCharges, maxCharges, hasCooldown, isTalent, source} }
local dirty = true
local subscribed = false

local EXCLUDED_SPELLS = {
    -- Dragonriding / Skyriding
    [372608] = true, [361584] = true, [372610] = true, [358267] = true,
    [361469] = true, [404468] = true,
    -- Generic / Utility
    [125439] = true, [6603] = true,
    -- DH passive talents
    [339924] = true, [320415] = true, [258881] = true, [206416] = true,
    [258876] = true, [258860] = true, [343311] = true, [347461] = true,
    [388114] = true, [389694] = true, [390163] = true, [442688] = true,
    [388116] = true, [382197] = true,
}
local RACIAL_SPELLS = {
    [58984] = true, [20594] = true, [20589] = true, [59752] = true,
    [7744] = true, [255654] = true, [312411] = true,
}

local function ShouldExclude(spellID, name)
    if EXCLUDED_SPELLS[spellID] or RACIAL_SPELLS[spellID] then return true end
    if not name then return true end
    local n = name:lower()
    if n:find("passive") then return true end
    if n:find("dragonriding") or n:find("skyriding") then return true end
    if n:find("skyward") or n:find("surge forward") then return true end
    if n:find("whirling") or n:find("bronze timelock") then return true end
    if n:find("aerial halt") then return true end
    if n:find("battle pet") or n:find("revive pet") then return true end
    return false
end

local function AddSpell(seen, spellID, source)
    if not spellID or spellID == 0 or seen[spellID] then return end
    local name = C_Spell.GetSpellName(spellID)
    if not name then return end
    if C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID) then return end
    local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
    if subtext and subtext:lower():find("passive") then return end
    if ShouldExclude(spellID, name) then return end
    if C_Spell.GetSpellInfo and not C_Spell.GetSpellInfo(spellID) then return end

    seen[spellID] = true
    -- Single-charge spells return chargeInfo too but are plain cooldowns, so
    -- only maxCharges > 1 counts as a charge spell.
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
    local maxCharges = (chargeInfo and chargeInfo.maxCharges) or 0
    local hasCharges = maxCharges > 1
    local hasCooldown = true
    if not hasCharges and C_Spell.GetSpellCooldown then
        hasCooldown = C_Spell.GetSpellCooldown(spellID) ~= nil
    end
    local isTalent = (C_Spell.IsClassTalentSpell and C_Spell.IsClassTalentSpell(spellID))
        or (C_Spell.IsPvPTalentSpell and C_Spell.IsPvPTalentSpell(spellID)) or false

    entries[#entries + 1] = {
        spellID = spellID,
        name = name,
        nameLower = name:lower(),
        texture = C_Spell.GetSpellTexture(spellID) or 134400,
        hasCharges = hasCharges,
        maxCharges = hasCharges and maxCharges or 0,
        hasCooldown = hasCooldown,
        isTalent = isTalent,
        source = source,
    }
end

local function Scan()
    if InCombatLockdown() then return end
    wipe(entries)
    local seen = {}

    -- Source 1: Cooldown Manager Essential (0) and Utility (1) categories. A
    -- client without C_CooldownViewer skips it, so sources 2-4 must stand alone.
    -- Data API only; a viewer frame method call can taint the Cooldown Manager.
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        for category = 0, 1 do
            local ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, false)
            for _, cdID in ipairs(ids or {}) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo
                    and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info and info.spellID then
                    AddSpell(seen, info.spellID, category == 0 and "Essential" or "Utility")
                end
            end
        end
    end

    -- Source 2: action bars, with macros resolved to their spell
    for slot = 1, 180 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id then
            AddSpell(seen, id, "ActionBar")
        elseif actionType == "macro" and id then
            local spellID = GetMacroSpell(id)
            if spellID then AddSpell(seen, spellID, "Macro") end
        end
    end

    -- Source 3: the active talent tree
    if C_ClassTalents and C_Traits then
        local configID = C_ClassTalents.GetActiveConfigID()
        local specIdx = GetSpecialization and GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx)
        local treeID = configID and specID and C_ClassTalents.GetTraitTreeForSpec(specID)
        if configID and treeID then
            local nodeIDs = C_Traits.GetTreeNodes(treeID)
            for _, nodeID in ipairs(nodeIDs or {}) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.activeRank and nodeInfo.activeRank > 0 then
                    local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
                    local entryInfo = entryID and C_Traits.GetEntryInfo(configID, entryID)
                    local defInfo = entryInfo and entryInfo.definitionID
                        and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    if defInfo and defInfo.spellID then
                        AddSpell(seen, defInfo.spellID, "Talent")
                    end
                end
            end
        end
    end

    -- Source 4: the spellbook, minus General, guild, hidden and off-spec lines
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for skillIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(skillIndex)
            if line and not line.isGuild and not line.shouldHide and line.name ~= "General"
                and (line.specID ~= nil or line.offSpecID == nil) then
                local first = line.itemIndexOffset + 1
                local last = first + line.numSpellBookItems - 1
                for i = first, last do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                    if item and not item.isPassive and not item.isOffSpec then
                        AddSpell(seen, item.actionID or item.spellID, "Spellbook")
                    end
                end
            end
        end
    end

    -- Forever's spellbook lists every rank; keep one per name: the known rank,
    -- or the highest spell ID when the resolver has no answer.
    if C_Spell.GetSpellIDForSpellIdentifier then
        local byName, deduped = {}, {}
        for _, e in ipairs(entries) do
            local prev = byName[e.nameLower]
            if not prev then
                byName[e.nameLower] = #deduped + 1
                deduped[#deduped + 1] = e
            else
                local slot = byName[e.nameLower]
                local want = C_Spell.GetSpellIDForSpellIdentifier(e.name)
                if (want and e.spellID == want)
                    or (not want and e.spellID > deduped[slot].spellID) then
                    deduped[slot] = e
                end
            end
        end
        entries = deduped   -- every reader goes through this upvalue
    end

    -- Charge spells, then talents, then A-Z; an empty search shows the top few.
    table.sort(entries, function(a, b)
        if a.hasCharges ~= b.hasCharges then return a.hasCharges end
        if a.isTalent ~= b.isTalent then return a.isTalent end
        return a.name < b.name
    end)
    dirty = false
end

function Catalog.Ensure()
    if not subscribed then
        subscribed = true
        local mark = function() dirty = true end
        Events.On("SPELLS_CHANGED", "adcat", mark)
        Events.On("ACTIONBAR_SLOT_CHANGED", "adcat", mark)
        Events.On("TRAIT_CONFIG_UPDATED", "adcat", mark)
        Events.On("PLAYER_SPECIALIZATION_CHANGED", "adcat", mark)
    end
    if dirty then Scan() end
end

function Catalog.Rescan()
    dirty = true
    Catalog.Ensure()
    return #entries
end

-- The live sorted list, not a copy: treat it as read-only.
function Catalog.All()
    Catalog.Ensure()
    return entries
end

-- query by name substring (case-insensitive) or by spell ID prefix;
-- empty query returns the head of the catalog (charges/talents first)
function Catalog.Search(query, max)
    Catalog.Ensure()
    max = max or 6
    local out = {}
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then
        for i = 1, math.min(max, #entries) do out[i] = entries[i] end
        return out
    end
    local isNumeric = query:match("^%d+$") ~= nil
    for _, e in ipairs(entries) do
        local hit
        if isNumeric then
            hit = tostring(e.spellID):find(query, 1, true) == 1
        else
            hit = e.nameLower:find(query, 1, true) ~= nil
        end
        if hit then
            out[#out + 1] = e
            if #out >= max then break end
        end
    end
    return out
end

-- Talent catalog: Forever has no specs, so load conditions test talent nodes.
-- Trees come from the active config's treeIDs, since GetTraitTreeForSpec needs
-- a specID and spec enumeration is dead on Forever.

local Talents = {}
NS.TalentCatalog = Talents

local tEntries = {}      -- sorted { {nodeID, name, nameLower, icon, rank, maxRanks, treeID, groupID, posX, posY, edges} }
local tDirty = true
local taken = {}         -- [nodeID] = true, rebuilt with tEntries
local tSubscribed = false
local tGroups = {}       -- the classic trees, in Blizzard's display order
local tBounds = {}       -- { minX, maxX, minY, maxY } over the kept nodes, for the picker

-- configID + every tree it carries, spec-free where possible
local function ActiveTrees()
    if not (C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID) then return end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end
    local info = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
    if info and info.treeIDs and #info.treeIDs > 0 then
        return configID, info.treeIDs
    end
    -- retail fallback: the active spec's tree
    local specIdx = GetSpecialization and GetSpecialization()
    local specID = specIdx and GetSpecializationInfo(specIdx)
    local treeID = specID and C_ClassTalents.GetTraitTreeForSpec
        and C_ClassTalents.GetTraitTreeForSpec(specID)
    if treeID then return configID, { treeID } end
    return configID, nil
end

-- Name and icon come from the node's active entry (a choice node shows your
-- pick), else its first entry, so untaken talents still list.
local function NodeDisplay(configID, nodeInfo)
    local entryID = (nodeInfo.activeEntry and nodeInfo.activeEntry.entryID)
        or (nodeInfo.entryIDs and nodeInfo.entryIDs[1])
    if not entryID then return end
    local entryInfo = C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
    local defID = entryInfo and entryInfo.definitionID
    local defInfo = defID and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(defID)
    if not defInfo then return end
    local name = defInfo.overrideName
    local icon = defInfo.overrideIcon
    if (not name or not icon) and defInfo.spellID then
        name = name or C_Spell.GetSpellName(defInfo.spellID)
        icon = icon or C_Spell.GetSpellTexture(defInfo.spellID)
    end
    return name, icon
end

-- Some nodes sit an order of magnitude off the tree (Hunter tree 1091, node
-- 104982: posX 102800, real max 10880). Blizzard's TalentButtonUtil divides
-- positions by 10 and the canvas clips, so these never draw: it is how a tree
-- hides a node. Scaled down, one would duplicate a real talent, so drop them.
-- The grid is uniform, so a node past 3x an axis's 95th percentile is parked.
local function SaneMax(list, key)
    local vals = {}
    for _, e in ipairs(list) do vals[#vals + 1] = e[key] or 0 end
    if #vals < 4 then return nil end
    table.sort(vals)
    local sane = vals[math.max(1, math.floor(#vals * 0.95))]
    if not sane or sane <= 0 then return nil end
    return sane * 3
end

local function DropOffCanvas(list)
    local maxX, maxY = SaneMax(list, "posX"), SaneMax(list, "posY")
    if not (maxX and maxY) then return list end
    local out = {}
    for _, e in ipairs(list) do
        if (e.posX or 0) <= maxX and (e.posY or 0) <= maxY then
            out[#out + 1] = e
        end
    end
    return out
end

-- Classic tree art: four quadrant textures at
-- Interface\TalentFrame\<background>-TopLeft (and TopRight, BottomLeft,
-- BottomRight), still shipped where the old talent frame does not load.
-- <background> is GetSpecializationInfo's 8th return where that works, else
-- <Class><TreeName> such as "HunterSurvival". A missing file draws nothing.
local function TreeBackground(orderIndex, displayName)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local _, _, _, _, _, _, _, bg =
            C_SpecializationInfo.GetSpecializationInfo((orderIndex or 0) + 1)
        if type(bg) == "string" and bg ~= "" then return bg end
    end
    local token = select(2, UnitClass("player"))
    if not token or token == "" or not displayName or displayName == "" then return nil end
    local cls = token:sub(1, 1):upper() .. token:sub(2):lower()
    if token == "DEATHKNIGHT" then cls = "DeathKnight"
    elseif token == "DEMONHUNTER" then cls = "DemonHunter" end
    return cls .. (displayName:gsub("[%s'%-]", ""))
end

local function ScanTalents()
    wipe(tEntries)
    wipe(taken)
    wipe(tGroups)
    wipe(tBounds)
    local configID, trees = ActiveTrees()
    if not (configID and trees) then
        tDirty = false
        return
    end
    -- The classic trees. A node's tree is the one of its groupIDs that is a
    -- top-level display group, as in ClassTalentsFrameMixin:GetTraitTreeName.
    local topGroup = {}
    for _, treeID in ipairs(trees) do
        local infos = C_Traits.GetGroupDisplayInfoByTreeID
            and C_Traits.GetGroupDisplayInfoByTreeID(treeID)
        for _, gi in ipairs(infos or {}) do
            if gi.groupID and not topGroup[gi.groupID] then
                topGroup[gi.groupID] = true
                tGroups[#tGroups + 1] = {
                    groupID = gi.groupID,
                    name = gi.displayName or "",
                    icon = gi.icon,
                    order = gi.orderIndex or #tGroups,
                    background = TreeBackground(gi.orderIndex, gi.displayName),
                }
            end
        end
    end
    table.sort(tGroups, function(a, b) return a.order < b.order end)

    local seenNode = {}
    for _, treeID in ipairs(trees) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            if not seenNode[nodeID] then
                seenNode[nodeID] = true
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo then
                    local rank = nodeInfo.activeRank or 0
                    if rank > 0 then taken[nodeID] = true end
                    local name, icon = NodeDisplay(configID, nodeInfo)
                    if name then
                        local groupID
                        for _, g in ipairs(nodeInfo.groupIDs or {}) do
                            if topGroup[g] then groupID = g break end
                        end
                        local edges
                        for _, ev in ipairs(nodeInfo.visibleEdges or {}) do
                            if ev.targetNode then
                                edges = edges or {}
                                edges[#edges + 1] = ev.targetNode
                            end
                        end
                        tEntries[#tEntries + 1] = {
                            nodeID = nodeID,
                            name = name,
                            nameLower = name:lower(),
                            icon = icon or 134400,
                            rank = rank,
                            maxRanks = nodeInfo.maxRanks,
                            treeID = treeID,
                            groupID = groupID,
                            posX = nodeInfo.posX or 0,
                            posY = nodeInfo.posY or 0,
                            edges = edges,
                        }
                    end
                end
            end
        end
    end

    -- taken[] keeps every node, so a condition saved against a node dropped
    -- here still evaluates correctly.
    tEntries = DropOffCanvas(tEntries)

    -- Whole-tree extents, plus each tree's band (the picker heads its column)
    -- and the points spent in it.
    local byGroup = {}
    for _, e in ipairs(tEntries) do
        tBounds.minX = math.min(tBounds.minX or e.posX, e.posX)
        tBounds.maxX = math.max(tBounds.maxX or e.posX, e.posX)
        tBounds.minY = math.min(tBounds.minY or e.posY, e.posY)
        tBounds.maxY = math.max(tBounds.maxY or e.posY, e.posY)
        if e.groupID then
            local b = byGroup[e.groupID]
            if not b then
                byGroup[e.groupID] = { minX = e.posX, maxX = e.posX,
                    minY = e.posY, maxY = e.posY, spent = e.rank or 0 }
            else
                b.minX = math.min(b.minX, e.posX); b.maxX = math.max(b.maxX, e.posX)
                b.minY = math.min(b.minY, e.posY); b.maxY = math.max(b.maxY, e.posY)
                b.spent = b.spent + (e.rank or 0)
            end
        end
    end
    for _, g in ipairs(tGroups) do
        local b = byGroup[g.groupID]
        g.minX, g.maxX = b and b.minX, b and b.maxX
        g.minY, g.maxY = b and b.minY, b and b.maxY
        g.spent = (b and b.spent) or 0
    end

    table.sort(tEntries, function(a, b)
        local at, bt = a.rank > 0, b.rank > 0
        if at ~= bt then return at end
        return a.name < b.name
    end)
    tDirty = false
end

-- Every event that can change a talent. Not every client has them all and
-- RegisterEvent throws on an unknown name, so use ValidEvents.
Talents.EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }

function Talents.ValidEvents()
    local out = {}
    for _, e in ipairs(Talents.EVENTS) do
        if not (C_EventUtils and C_EventUtils.IsEventValid)
            or C_EventUtils.IsEventValid(e) then
            out[#out + 1] = e
        end
    end
    return out
end

function Talents.Ensure()
    if not tSubscribed then
        tSubscribed = true
        local mark = function() tDirty = true end
        for _, e in ipairs(Talents.ValidEvents()) do
            Events.On(e, "adtal", mark)
        end
    end
    if tDirty then ScanTalents() end
end

function Talents.Rescan()
    tDirty = true
    Talents.Ensure()
    return #tEntries
end

function Talents.IsTaken(nodeID)
    Talents.Ensure()
    return taken[nodeID] == true
end

-- A stored node may be missing from the current tree (imported from another
-- class, or the tree changed); the UI greys those out.
function Talents.Known(nodeID)
    Talents.Ensure()
    for _, e in ipairs(tEntries) do
        if e.nodeID == nodeID then return e end
    end
    return nil
end

function Talents.All()
    Talents.Ensure()
    return tEntries
end

-- What the tree picker draws: the nodes (position, tree, edges), the classic
-- trees in display order and the whole-tree extents. Coordinates are raw
-- trait units; divide by 10 for display units, as Blizzard's frame does.
function Talents.Layout()
    Talents.Ensure()
    return tEntries, tGroups, tBounds
end

-- name substring, or a node ID prefix; empty query returns the head
-- (talents you have, then the rest alphabetically)
function Talents.Search(query, max)
    Talents.Ensure()
    max = max or 8
    local out = {}
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then
        for i = 1, math.min(max, #tEntries) do out[i] = tEntries[i] end
        return out
    end
    local isNumeric = query:match("^%d+$") ~= nil
    for _, e in ipairs(tEntries) do
        local hit
        if isNumeric then
            hit = tostring(e.nodeID):find(query, 1, true) == 1
        else
            hit = e.nameLower:find(query, 1, true) ~= nil
        end
        if hit then
            out[#out + 1] = e
            if #out >= max then break end
        end
    end
    return out
end
