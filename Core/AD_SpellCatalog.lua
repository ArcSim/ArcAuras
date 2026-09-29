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
        local actionType, id, sub = GetActionInfo(slot)
        if actionType == "spell" and id then
            AddSpell(seen, id, "ActionBar")
        elseif actionType == "macro" and id then
            -- the id is the macro's spell when the third return says so;
            -- an older client gives the macro index instead
            local spellID = (sub == "spell") and id or GetMacroSpell(id)
            if spellID then AddSpell(seen, spellID, "Macro") end
        end
    end

    -- Source 3: the active talent tree
    if C_ClassTalents and C_Traits then
        local configID = C_ClassTalents.GetActiveConfigID()
        local SI = C_SpecializationInfo
        local specIdx = SI and SI.GetSpecialization and SI.GetSpecialization()
        local specID = specIdx and SI.GetSpecializationInfo(specIdx)
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

local tEntries = {}      -- sorted { {nodeID, name, nameLower, icon, rank, maxRanks, entryID, spellID, treeID, groupID, posX, posY, edges, and on retail home, subTreeID, subTreeActive, taken, entries, activeEntryID} }
local tDirty = true
local taken = {}         -- [nodeID] = true, rebuilt with tEntries
local activeEntryOf = {} -- [nodeID] = the active entry's ID, rebuilt with tEntries
local tSubscribed = false
local tGroups = {}       -- the classic trees, in Blizzard's display order
local tBounds = {}       -- { minX, maxX, minY, maxY } over the kept nodes, for the picker
local tHero = {}         -- retail: the class's hero trees { id, name, active, specs = { [specID] = true } }
local tPanels            -- retail: the picker's class / hero / spec panels (Talents.Panels)

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
    local SI = C_SpecializationInfo
    local specIdx = SI and SI.GetSpecialization and SI.GetSpecialization()
    local specID = specIdx and SI.GetSpecializationInfo(specIdx)
    local treeID = specID and C_ClassTalents.GetTraitTreeForSpec
        and C_ClassTalents.GetTraitTreeForSpec(specID)
    if treeID then return configID, { treeID } end
    return configID, nil
end

-- One entry's name, icon and spell, from its definition first (immune to a
-- runtime spell override), then the spell.
local function EntryDisplay(configID, entryID)
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
    return name, icon, defInfo.spellID
end

-- Name and icon come from the node's active entry (a choice node shows your
-- pick), else its first entry, so untaken talents still list. The entry and
-- its spell come back too: the picker's tooltip shows the game's talent text.
local function NodeDisplay(configID, nodeInfo)
    local entryID = (nodeInfo.activeEntry and nodeInfo.activeEntry.entryID)
        or (nodeInfo.entryIDs and nodeInfo.entryIDs[1])
    if not entryID then return end
    local name, icon, spellID = EntryDisplay(configID, entryID)
    return name, icon, entryID, spellID
end

-- A choice node's options (two or more entries), so a condition can name one.
local function NodeEntries(configID, nodeInfo)
    local ids = nodeInfo.entryIDs
    if type(ids) ~= "table" or #ids < 2 then return nil end
    local out = {}
    for _, entryID in ipairs(ids) do
        local name, icon, spellID = EntryDisplay(configID, entryID)
        if name then
            out[#out + 1] = { entryID = entryID, name = name, icon = icon or 134400, spellID = spellID }
        end
    end
    if #out < 2 then return nil end
    return out
end

-- Retail keeps every spec's nodes and every hero tree in one class tree. A
-- node's home: hero (it carries a subTreeID), else spec or class by the
-- currency its cost is paid in (the talent frame's treeCurrencyInfo[2] and
-- [1]); with no cost data, spec nodes sit at posX 10000 and beyond.
local function NodeHome(configID, nodeID, nodeInfo, classCur, specCur)
    if nodeInfo.subTreeID then return "hero" end
    if specCur and C_Traits.GetNodeCost then
        for _, cost in ipairs(C_Traits.GetNodeCost(configID, nodeID) or {}) do
            if cost.ID == specCur then return "spec" end
            if cost.ID == classCur then return "class" end
        end
    end
    return ((nodeInfo.posX or 0) >= 10000) and "spec" or "class"
end

-- Retail: the player's class's hero trees, each with the specs it serves. The
-- picker draws the current spec's, the Load Conditions rows list every one.
local function ScanHeroTrees(configID)
    wipe(tHero)
    local CT = C_ClassTalents
    if not (CT and CT.GetHeroTalentSpecsForClassSpec and C_Traits.GetSubTreeInfo) then return end
    local Store = NS.Store
    local tag = Store and Store.ClassTag and Store.ClassTag()
    local specs = {}
    for _, cls in ipairs((Store and Store.ClassSpecMatrix and Store.ClassSpecMatrix()) or {}) do
        if cls.tag == tag then
            for _, sp in ipairs(cls.specs) do specs[#specs + 1] = sp.id end
        end
    end
    local cur = Store and Store.CurSpecID and Store.CurSpecID()
    if #specs == 0 and cur then specs[1] = cur end
    local byID = {}
    for _, specID in ipairs(specs) do
        local ids = CT.GetHeroTalentSpecsForClassSpec(configID, specID)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            local t = byID[id]
            if not t then
                local info = C_Traits.GetSubTreeInfo(configID, id)
                t = { id = id, name = (info and info.name) or ("Hero tree " .. id),
                    active = info ~= nil and info.isActive == true, specs = {} }
                byID[id] = t
                tHero[#tHero + 1] = t
            end
            t.specs[specID] = true
        end
    end
    table.sort(tHero, function(a, b) return a.name < b.name end)
end

local function Extents(list)
    local b = {}
    for _, e in ipairs(list) do
        b.minX = math.min(b.minX or e.posX, e.posX)
        b.maxX = math.max(b.maxX or e.posX, e.posX)
        b.minY = math.min(b.minY or e.posY, e.posY)
        b.maxY = math.max(b.maxY or e.posY, e.posY)
    end
    return b
end

-- The retail picker's panels: the class tree, the spec's hero trees (each its
-- own band) and the spec tree, each with its own extents.
local function BuildPanels()
    local class, spec, heroLists = {}, {}, {}
    for _, e in ipairs(tEntries) do
        if e.home == "spec" then
            spec[#spec + 1] = e
        elseif e.home == "hero" then
            local l = heroLists[e.subTreeID]
            if not l then
                l = {}
                heroLists[e.subTreeID] = l
            end
            l[#l + 1] = e
        else
            class[#class + 1] = e
        end
    end
    local hero, seen = {}, {}
    for _, t in ipairs(tHero) do
        local l = heroLists[t.id]
        if l then
            seen[t.id] = true
            hero[#hero + 1] = { id = t.id, name = t.name, active = t.active, list = l, bounds = Extents(l) }
        end
    end
    -- a sub-tree the hero API did not name is still drawn, under its id
    for id, l in pairs(heroLists) do
        if not seen[id] then
            hero[#hero + 1] = { id = id, name = "Hero tree " .. id,
                active = l[1].subTreeActive == true, list = l, bounds = Extents(l) }
        end
    end
    table.sort(hero, function(a, b) return a.name < b.name end)
    local SI = C_SpecializationInfo
    local specName
    local idx = SI and SI.GetSpecialization and SI.GetSpecialization()
    if type(idx) == "number" and SI.GetSpecializationInfo then
        local _, nm = SI.GetSpecializationInfo(idx)
        specName = nm
    end
    return {
        class = { name = UnitClass("player") or "Class", list = class, bounds = Extents(class) },
        spec = { name = specName or "Spec", list = spec, bounds = Extents(spec) },
        hero = hero,
    }
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
    wipe(activeEntryOf)
    wipe(tGroups)
    wipe(tBounds)
    wipe(tHero)
    tPanels = nil
    local configID, trees = ActiveTrees()
    if not (configID and trees) then
        tDirty = false
        return
    end
    -- Retail: the currencies that tell class nodes from spec nodes, and the
    -- current spec's hero trees (the others' nodes stay out of the picker).
    local retail = NS.IsForever ~= true
    local classCur, specCur, heroAllowed
    if retail then
        if C_Traits.GetTreeCurrencyInfo then
            local ci = C_Traits.GetTreeCurrencyInfo(configID, trees[1], false)
            classCur = ci and ci[1] and ci[1].traitCurrencyID
            specCur = ci and ci[2] and ci[2].traitCurrencyID
        end
        ScanHeroTrees(configID)
        local cur = NS.Store and NS.Store.CurSpecID and NS.Store.CurSpecID()
        if cur then
            for _, t in ipairs(tHero) do
                if t.specs[cur] then
                    heroAllowed = heroAllowed or {}
                    heroAllowed[t.id] = true
                end
            end
        end
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
                    local visible = nodeInfo.isVisible ~= false
                    local sub = nodeInfo.subTreeID
                    -- retail: a hidden node (another spec's) or one of the hero
                    -- tree not chosen is never taken, whatever rank it reports
                    local counts = rank > 0
                    if retail and (not visible or (sub and nodeInfo.subTreeActive ~= true)) then
                        counts = false
                    end
                    if counts then taken[nodeID] = true end
                    local ae = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
                    if ae then activeEntryOf[nodeID] = ae end
                    local name, icon, entryID, spellID = NodeDisplay(configID, nodeInfo)
                    local keep = name ~= nil
                    -- retail draws only visible nodes, and only the spec's hero trees
                    if retail and (not visible or (sub and heroAllowed and not heroAllowed[sub])) then
                        keep = false
                    end
                    if keep then
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
                            entryID = entryID,
                            spellID = spellID,
                            treeID = treeID,
                            groupID = groupID,
                            posX = nodeInfo.posX or 0,
                            posY = nodeInfo.posY or 0,
                            edges = edges,
                            -- retail: the panel it draws in, its hero tree, whether
                            -- it counts, a choice node's options and the active one
                            home = retail and NodeHome(configID, nodeID, nodeInfo, classCur, specCur) or nil,
                            subTreeID = sub,
                            subTreeActive = nodeInfo.subTreeActive,
                            taken = counts,
                            entries = retail and NodeEntries(configID, nodeInfo) or nil,
                            activeEntryID = ae,
                        }
                    end
                end
            end
        end
    end

    -- taken[] keeps every node, so a condition saved against a node dropped
    -- here still evaluates correctly. Retail's panels are separate grids far
    -- apart, so the off-canvas rule runs per panel there.
    if retail then
        local byHome = { class = {}, spec = {}, hero = {} }
        for _, e in ipairs(tEntries) do
            local l = byHome[e.home]
            l[#l + 1] = e
        end
        local kept = {}
        for _, home in ipairs({ "class", "hero", "spec" }) do
            for _, e in ipairs(DropOffCanvas(byHome[home])) do kept[#kept + 1] = e end
        end
        tEntries = kept
    else
        tEntries = DropOffCanvas(tEntries)
    end

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
    if retail then tPanels = BuildPanels() end
    tDirty = false
end

-- Every event that can change a talent. Not every client has them all and
-- RegisterEvent throws on an unknown name, so use ValidEvents.
Talents.EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_SUB_TREE_CHANGED" }

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

-- The entry a node has active (a choice node's pick), or nil.
function Talents.ActiveEntry(nodeID)
    Talents.Ensure()
    return activeEntryOf[nodeID]
end

-- One option of a choice node: { entryID, name, icon, spellID }, or nil.
function Talents.EntryInfo(nodeID, entryID)
    local e = Talents.Known(nodeID)
    for _, opt in ipairs((e and e.entries) or {}) do
        if opt.entryID == entryID then return opt end
    end
    return nil
end

-- Retail: the class's hero trees ({ id, name, active, specs }); empty elsewhere.
function Talents.HeroTrees()
    Talents.Ensure()
    return tHero
end

function Talents.HeroName(id)
    for _, t in ipairs(Talents.HeroTrees()) do
        if t.id == id then return t.name end
    end
    return nil
end

-- Retail: what the retail picker draws ({ class, spec, hero = { ... } }, each
-- with name, list and bounds); nil on a spec-less client or with no tree.
function Talents.Panels()
    Talents.Ensure()
    return tPanels
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
