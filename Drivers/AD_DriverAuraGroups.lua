-- Engine rows for Dynamic aura groups. With the options panel closed and the
-- group's Dynamic toggle on, AuraContainer rows (player buffs, target debuffs,
-- pet buffs) replace the holders: a button exists only while its aura is up,
-- and the flow layout compacts the row. Otherwise the static grid stays.

local ADDON, NS = ...
local Store = NS.Store
local Factory = NS.Factory
local Events = NS.Events

local Groups = {}
NS.DriverAuraGroups = Groups

-- Capability probe as well as a version gate: Forever (1.60.x, branched from
-- retail 12.1.5) has the engine under a lower build number.
local IS_121 = ((select(4, GetBuildInfo()) or 0) >= 120100)
    or (C_Secrets and C_Secrets.ShouldAurasBeSecret ~= nil)
local MEMBER_SLOTS = 10
local SLOT_KEYS = {}
for k = 1, MEMBER_SLOTS do SLOT_KEYS[k] = "adSlot" .. k end
local SLOT_CAP = { player = 1, target = 2, pet = 1 }  -- two casters can apply one debuff
local BASE_FILTER = { player = "HELPFUL", target = "HARMFUL", pet = "HELPFUL" }
-- the engine rows, chained in this order (a missing one is skipped)
local ENGINE_ORDER = { "player", "target", "pet" }

local runtimes = {}        -- [groupId] = { engines={player=,target=,pet=}, buttons={}, slotRecs={}, slotDims={}, cfg={} }
-- [engine] = { [groupKey] = the id map last sent, as DriverAura.FilterSig }
local sentFilters = {}
local loadWindowOver = false
local pendingBuild = false
local pendingSync = false
local targetSwapArmed = false

local function AurasSecretNow()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    -- On Forever the probe can return a secret boolean, which throws on a test.
    -- A secret answer means restrictions are on.
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end
Groups.AurasSecretNow = AurasSecretNow

function Groups.IsAvailable() return IS_121 end

-- Engine mode: the options panel is closed.
local function EngineModeActive()
    local Engine = NS.LayoutEngine
    return not (Engine and Engine.IsEditMode and Engine.IsEditMode())
end

-- The Dynamic toggle is the live-view switch: off, the group stays a static
-- grid in play, its rows hidden. The layout engine's flowMode reads it too.
local function IsDynamic(grec)
    return grec ~= nil and Store.Resolve(grec, "arrangement", "dynamicLayout") == true
end
Groups.IsDynamic = IsDynamic

-- A group showing every aura on a unit has no member rows: its own engine
-- draws it (Drivers\AD_DriverUnitAuras.lua).
local function ShowsAll(grec)
    return Store.ShowsAll ~= nil and Store.ShowsAll(grec)
end

-- Membership

-- Loaded aura members in a fixed grid order (gpos row-major, id tiebreak)
local function MembersOf(grec)
    local rows = {}
    for _, rec in ipairs(Store.IconsOf(grec)) do
        if rec.kind == "aura" and Store.IsLoaded(rec) then
            local gp = rec.gpos or {}
            rows[#rows + 1] = {
                rec = rec,
                key = (gp.row or 0) * 1000 + (gp.col or 0),
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        return a.rec.id < b.rec.id
    end)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.rec end
    return out
end

local function ParkMap() return { [0] = true } end

-- Hostility gate: true when the engine honors identity filters on the
-- target's harmful auras (it cannot be assisted), false if not, nil if
-- unknown: UnitCanAssist can be secret on Forever, and `not` on a secret
-- boolean throws. Callers keep the current caps on unknown.
local function TargetFiltersHonored()
    local assist = UnitCanAssist("player", "target", true, true)
    if issecretvalue and issecretvalue(assist) then return nil end
    return assist ~= true
end

local function AllNeverSecret(ids)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum.SecrecyLevel) then
        return false
    end
    for id in pairs(ids) do
        if C_Secrets.GetSpellAuraSecrecy(id) ~= Enum.SecrecyLevel.NeverSecret then
            return false
        end
    end
    return true
end

-- Park and unpark. Park is the never-matching id map plus a zero frame cap:
-- identity filters are skipped for harmful auras on assistable units, so an
-- uncapped parked target row shows an arbitrary debuff in every slot. Park
-- caps first, unpark caps last. The setters are data-only and combat-legal.
local function ApplySlotFilter(c, unit, k, ids, fstr, exempt)
    local key = "adSlot" .. k
    local parked = ids[0] ~= nil
    local canCap = c.SetAuraGroupMaxFrameCount ~= nil
    if parked and canCap then c:SetAuraGroupMaxFrameCount(key, 0) end
    if c.SetAuraGroupFilterString then
        c:SetAuraGroupFilterString(key, fstr or BASE_FILTER[unit] or "HELPFUL")
    end
    -- an unchanged set is not sent again: every send rebuilds the whole engine
    local sent = sentFilters[c] or {}
    sentFilters[c] = sent
    local sig = NS.DriverAura.FilterSig(ids)
    if sent[key] ~= sig then
        sent[key] = sig
        c:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
    end
    if not parked and canCap then
        local cap = SLOT_CAP[unit] or 1
        -- Only a plain true opens a gated target slot; never-secret members
        -- are exempt. This runs out of combat (from AssignSlots), where the
        -- answer is plain in practice.
        if unit == "target" and not exempt and TargetFiltersHonored() ~= true then
            cap = 0
        end
        c:SetAuraGroupMaxFrameCount(key, cap)
    end
end

-- One member's include map for one row, parked when its lane is not the
-- row's. A lane no row carries (focus, party, target buffs, your debuffs)
-- shows only in the panel. Lane, ids and Cast by string come from DriverAura.
local function MemberMapFor(rec, unit)
    local DA = NS.DriverAura
    local d = rec.driver or {}
    local lane, harmful = DA.LaneOf(d)
    if lane ~= unit or harmful ~= (unit == "target") then return ParkMap() end
    local ids = DA.IncludeMap(d)
    if ids[0] then return ParkMap() end
    local fstr = DA.FilterForLane(d, { harmful = harmful })
    local exempt = (unit == "target") and AllNeverSecret(ids) or false
    return ids, fstr, exempt
end

-- Target and pet swaps: re-cap the hostility gate and rescan

local function ArmTargetSwapRefresh()
    if targetSwapArmed then return end
    targetSwapArmed = true
    -- Re-cap every target row; `rescan` then rebuilds them for a new unit. An
    -- unknown (secret) answer skips only the re-cap, keeping the last plain
    -- caps. True once it decided.
    local function Recap(rescan)
        local honored = TargetFiltersHonored()
        for _, rt in pairs(runtimes) do
            local c = rt.engines.target
            if c then
                local tm = rt.slotTargetMode
                if honored ~= nil and tm and c.SetAuraGroupMaxFrameCount then
                    for k = 1, MEMBER_SLOTS do
                        local mode = tm[k]
                        if mode then
                            c:SetAuraGroupMaxFrameCount("adSlot" .. k,
                                (mode == "exempt" or honored) and SLOT_CAP.target or 0)
                        end
                    end
                end
                if rescan and c:IsShown() and c.UpdateAllAuras then c:UpdateAllAuras() end
            end
        end
        return honored ~= nil
    end
    Events.On("PLAYER_TARGET_CHANGED", "adaurag_swap", function() Recap(true) end)
    -- Combat end settles a re-cap the fight skipped. A cap change re-deals
    -- the row's frames by itself, so no rebuild: one would restart everything
    -- on the rows. Secrecy can lift a beat late, so an unknown gets two more
    -- tries, then waits for a target change.
    Events.On("PLAYER_REGEN_ENABLED", "adaurag_swap", function()
        if Recap(false) then return end
        C_Timer.After(0.3, function()
            if not Recap(false) then
                C_Timer.After(1, function() Recap(false) end)
            end
        end)
    end)
    -- the pet row goes stale the same way when the pet is swapped or dies
    Events.On("UNIT_PET", "adaurag_swap", function(_, unit)
        if unit ~= nil and unit ~= "player" then return end
        for _, rt in pairs(runtimes) do
            local c = rt.engines.pet
            if c and c:IsShown() and c.UpdateAllAuras then c:UpdateAllAuras() end
        end
    end)
end

-- Per-slot styling

-- A slot button exists only while its member's aura is up, so the active
-- look is drawn on it; no presence read, which fails closed while auras are
-- secret. No ghost under a play-mode row, so no plate. Size comes from the
-- slot's plain dims; re-run each pass, as slots re-map to other members.
local function StyleSlotButton(b, rt)
    local rec = rt.slotRecs and rt.slotRecs[b._adSlotIndex or 0]
    if not rec then return end
    -- The border is drawn on the text overlay, so any border host is hidden.
    if b._adBorderHost then b._adBorderHost:Hide() end
    local dims = rt.slotDims and rt.slotDims[b._adSlotIndex or 0]
    local w = (dims and dims.w) or rt.cfg.iconW or 36
    local h = (dims and dims.h) or rt.cfg.iconH or 36
    Factory.StyleAuraButton(b, rec, h, { w = w, h = h, ghost = false })
end
-- Shared with the show-all engine (Drivers\AD_DriverUnitAuras.lua), which
-- styles every button from one record.
Groups.StyleSlotButton = StyleSlotButton

-- Restyles a runtime's buttons where the game allows it (resized first, when
-- their size changed). True when one was locked, so the caller retries at its
-- settle edge. Shared with the show-all engine.
local function StyleButtons(rt)
    local resized, locked = false, false
    for _, b in ipairs(rt.buttons or {}) do
        local ok
        if b.CanBeAccessedInContext then
            ok = b:CanBeAccessedInContext()
        else
            ok = not (b.IsForbidden and b:IsForbidden())
        end
        if ok then
            -- Never GetSize() an engine button (its rect can be secret):
            -- track the size last applied and resize only on change.
            local dims = rt.slotDims and rt.slotDims[b._adSlotIndex]
            local w = (dims and dims.w) or rt.cfg.iconW or 36
            local h = (dims and dims.h) or rt.cfg.iconH or 36
            if b._adAppliedW ~= w or b._adAppliedH ~= h then
                b:SetSize(w, h)
                b._adAppliedW, b._adAppliedH = w, h
                resized = true
            end
            StyleSlotButton(b, rt)
        else
            locked = true
        end
    end
    if resized and not InCombatLockdown() then
        for _, c in pairs(rt.engines) do
            if c.UpdateAllAuras then c:UpdateAllAuras() end
        end
    end
    return locked
end
Groups.StyleButtons = StyleButtons

local function StyleRuntimeButtons(rt)
    if StyleButtons(rt) then pendingSync = true end
end

-- Runtime build
-- Each member gets its own engine group ("adSlot<k>") in the shared rows, so
-- every button has a known member and the row still compacts as one. Groups
-- are added once, at build: creation is illegal while auras are secret.

local function BuildRuntime(groupId, seed)
    local rt = runtimes[groupId]
    if rt then return rt end
    if not IS_121 then return nil end
    if loadWindowOver and AurasSecretNow() then
        pendingBuild = true
        return nil
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end

    local WireButton = NS.DriverAura and NS.DriverAura.WireButton

    rt = {
        engines = {},
        buttons = {},
        slotRecs = (seed and seed.slotRecs) or {},
        slotDims = (seed and seed.slotDims) or {},
        cfg = { iconW = (seed and seed.iconW) or 36, iconH = (seed and seed.iconH) or 36 },
    }

    local function makeEngine(unit, filter)
        local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not c or type(c.AddAuraGroup) ~= "function" then
            if c then c:Hide() end
            return nil
        end
        c:SetSize(1, 1)
        c:SetUnit(unit)
        c:SetEnabled(true)
        c:EnableMouse(false)
        c:Hide()   -- shown only in engine mode, mirrored from the group frame
        for k = 1, MEMBER_SLOTS do
            c:AddAuraGroup("adSlot" .. k, filter, {
                -- Born parked (cap 0; see ApplySlotFilter). The frame batch
                -- is still pre-created here, on our stack.
                maxFrameCount = 0,
                initializeFrame = function(b)
                    if WireButton then WireButton(b) end
                    local dims = rt.slotDims and rt.slotDims[k]
                    local w = (dims and dims.w) or rt.cfg.iconW
                    local h = (dims and dims.h) or rt.cfg.iconH
                    b:SetSize(w, h)
                    b._adAppliedW, b._adAppliedH = w, h
                    b._adSlotIndex = k
                    b:EnableMouse(false)
                    if not b._adCollected then
                        b._adCollected = true
                        rt.buttons[#rt.buttons + 1] = b
                    end
                    StyleSlotButton(b, rt)
                end,
                candidateFilters = { includeSpellIDs = ParkMap() },
                layout = {
                    elementSpacingX = 2, elementSpacingY = 2,  -- pre-PTR7 keys
                    elementSpacing = 2, lineSpacing = 2,       -- PTR7 keys
                    groupSpacing = 2, groupLineSpacing = 2,    -- between slots
                },
            })
        end
        local sent, parkSig = {}, NS.DriverAura.FilterSig(ParkMap())
        for k = 1, MEMBER_SLOTS do sent["adSlot" .. k] = parkSig end
        sentFilters[c] = sent
        rt.engines[unit] = c
        return c
    end

    makeEngine("player", "HELPFUL")
    makeEngine("target", "HARMFUL")
    makeEngine("pet", "HELPFUL")   -- pet buffs, parked until a member wants them
    ArmTargetSwapRefresh()
    runtimes[groupId] = rt
    return rt
end

-- Layout and pin, from the group's arrangement

local function GroupDims(grec)
    local R = function(field) return Store.Resolve(grec, "arrangement", field) end
    local scale = math.floor((R("iconSize") or 36) + 0.5) / 36
    local w = math.floor((R("iconWidth") or 36) * scale + 0.5)
    local h = math.floor((R("iconHeight") or 36) * scale + 0.5)
    local spBase = R("spacing") or 2
    local sep = R("separateSpacing") == true
    local sx = sep and (R("spacingX") or spBase) or spBase
    local sy = sep and (R("spacingY") or spBase) or spBase
    return w, h, sx, sy, math.max(1, R("cols") or 6),
        R("growthH") or "RIGHT", R("growthV") or "DOWN"
end
Groups.GroupDims = GroupDims

-- One container's flow: the spacing of each of its groups (keys), the line
-- size, the padding, the reading direction and the corner the buttons start
-- from, through whichever setter names this client has. Returns the corner.
-- Shared with the show-all engine.
local function ApplyFlow(c, keys, sx, sy, lineSize, pad, flowRight, flowDown)
    if c.SetAuraGroupLayout then
        for _, key in ipairs(keys) do
            c:SetAuraGroupLayout(key, {
                elementSpacingX = sx, elementSpacingY = sy,
                elementSpacing = sx, lineSpacing = sy,
                groupSpacing = sx, groupLineSpacing = sy,
            })
        end
    end
    if c.SetFlowLayoutMaximumLineSize then
        c:SetFlowLayoutMaximumLineSize(lineSize)
    elseif c.SetAuraLayoutRowWidth then
        c:SetAuraLayoutRowWidth(lineSize)
    end
    if c.SetFlowLayoutPadding then
        c:SetFlowLayoutPadding(pad, pad, pad, pad)
    elseif c.SetAuraLayoutPadding then
        c:SetAuraLayoutPadding(pad, pad, pad, pad)
    end
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if FD then
        local dirH = flowRight and FD.Right or FD.Left
        local dirV = flowDown and FD.Down or FD.Up
        if c.SetFlowLayoutGrowthDirection then
            c:SetFlowLayoutGrowthDirection(dirH, dirV)
        elseif c.SetAuraLayoutGrowthDirection then
            c:SetAuraLayoutGrowthDirection(dirH, dirV)
        end
    end
    local corner = (flowDown and "TOP" or "BOTTOM") .. (flowRight and "LEFT" or "RIGHT")
    if c.SetFlowLayoutAnchorPoint then
        c:SetFlowLayoutAnchorPoint(corner)
    elseif c.SetAuraLayoutAnchorPoint then
        c:SetAuraLayoutAnchorPoint(corner)
    end
    return corner
end
Groups.ApplyFlow = ApplyFlow

local function ApplyEngineLayout(groupId, grec)
    local rt = runtimes[groupId]
    if not rt then return end
    local iconW, iconH, sx, sy, perRow, growthH, growthV = GroupDims(grec)
    rt.cfg.iconW, rt.cfg.iconH = iconW, iconH

    -- Alignment picks the pin the auto-sizing box grows away from: Left grows
    -- right, Right left, Center both ways; row growth sets the vertical pin.
    local Engine = NS.LayoutEngine
    local align, shape = "center", "horizontal"
    if Engine and Engine.EffectiveAlignment then
        align, shape = Engine.EffectiveAlignment(grec)
    end
    local hMode
    if align == "left" or align == "right" then
        hMode = align:upper()
    elseif align == "center_h" or (align == "center" and shape ~= "vertical") then
        hMode = "CENTER"
    else
        hMode = (growthH == "LEFT") and "RIGHT" or "LEFT"
    end
    local vMode = (growthV == "UP") and "BOTTOM" or "TOP"
    if align == "top" then
        vMode = "TOP"
    elseif align == "bottom" then
        vMode = "BOTTOM"
    elseif align == "center_v" or (align == "center" and shape == "vertical") then
        vMode = "CENTER"
    end
    -- Reading direction: away from an edge pin, so the first aura up stays put.
    -- The flow always anchors on a corner (an edge-midpoint flow shifts each
    -- element half out); centering comes from the pin.
    local flowRight
    if hMode == "LEFT" then flowRight = true
    elseif hMode == "RIGHT" then flowRight = false
    else flowRight = (growthH ~= "LEFT") end
    local flowDown
    if vMode == "TOP" then flowDown = true
    elseif vMode == "BOTTOM" then flowDown = false
    else flowDown = (growthV ~= "UP") end

    local pad = Store.Resolve(grec, "arrangement", "containerPadding") or 0
    if pad < 0 then pad = 0 end
    for _, c in pairs(rt.engines) do
        ApplyFlow(c, SLOT_KEYS, sx, sy, perRow * (iconW + sx), pad, flowRight, flowDown)
    end

    -- Pin the rows to the group frame, which keeps its grid-sized rect in flow
    -- mode. Anchoring an engine container to our frame is legal.
    local gf = Engine and Engine.GetGroupFrame and Engine.GetGroupFrame(groupId)
    if not gf then return end
    rt.pinFrame = gf
    -- Center on an axis pins its midpoint, so the box grows evenly both ways.
    local vPart = (vMode == "TOP") and "TOP" or (vMode == "BOTTOM") and "BOTTOM" or ""
    local hPart = (hMode == "LEFT") and "LEFT" or (hMode == "RIGHT") and "RIGHT" or ""
    local pin = vPart .. hPart
    if pin == "" then pin = "CENTER" end
    -- Chain the rows on TOP/BOTTOM edges only: an empty container has near-zero
    -- height, so side midpoints drift. A centered column or grid puts each row
    -- on its own line; otherwise rows continue in the reading direction.
    local newline = hMode == "CENTER" and shape ~= "horizontal"
    local chainV = flowDown and "TOP" or "BOTTOM"
    local hSelf = flowRight and "LEFT" or "RIGHT"
    local hFar = flowRight and "RIGHT" or "LEFT"
    local prev
    for _, unit in ipairs(ENGINE_ORDER) do
        local c = rt.engines[unit]
        if c then
            c:ClearAllPoints()
            if not prev then
                c:SetPoint(pin, gf, pin, 0, 0)
            elseif newline then
                if flowDown then
                    c:SetPoint("TOP" .. hPart, prev, "BOTTOM" .. hPart, 0, -sy)
                else
                    c:SetPoint("BOTTOM" .. hPart, prev, "TOP" .. hPart, 0, sy)
                end
            else
                c:SetPoint(chainV .. hSelf, prev, chainV .. hFar,
                    flowRight and sx or -sx, 0)
            end
            prev = c
        end
    end
end

-- Mirror the group frame's shown state, effective alpha and strata onto a
-- container, which is not its child: conditions and the flip must carry over.
-- Shared with the show-all engine.
local function MirrorOnto(c, gf, on)
    local alpha = 1
    if gf then
        alpha = gf.GetEffectiveAlpha and gf:GetEffectiveAlpha() or gf:GetAlpha() or 1
        if issecretvalue and issecretvalue(alpha) then alpha = 1 end
    end
    c:SetShown(on)
    c:SetAlpha(alpha)
    if gf then
        c:SetFrameStrata(gf:GetFrameStrata())
        c:SetFrameLevel(gf:GetFrameLevel() + 2)
    end
end
Groups.MirrorOnto = MirrorOnto

local function UpdateEngineShown(groupId, grec)
    local rt = runtimes[groupId]
    if not rt then return end
    local Engine = NS.LayoutEngine
    local gf = Engine and Engine.GetGroupFrame and Engine.GetGroupFrame(groupId)
    local on = EngineModeActive() and IsDynamic(grec) and not ShowsAll(grec)
        and Store.IsLoaded(grec) and gf ~= nil and gf:IsShown()
    for _, c in pairs(rt.engines) do MirrorOnto(c, gf, on) end
end

-- Sync (SyncAll is the one reconciler)

local function AssignSlots(groupId, grec)
    local rt = runtimes[groupId]
    if not rt then return end
    local members = MembersOf(grec)
    for k = 1, MEMBER_SLOTS do
        rt.slotRecs[k] = members[k]
        local rec = members[k]
        local dims = nil
        if rec then
            -- The member's own size (Position tab) once Use group scale is
            -- off; nil dims mean the group's slot size. It is the one Position
            -- option that reaches a play-mode row (buttons take SetSize).
            local Rp = function(f) return Store.Resolve(rec, "position", f) end
            if Rp("useGroupScale") == false then
                local w, h = rt.cfg.iconW, rt.cfg.iconH
                local iw, ih = Rp("iconWidth") or 0, Rp("iconHeight") or 0
                if iw > 0 then w = iw end
                if ih > 0 then h = ih end
                local sc = Rp("iconScale") or 1
                dims = { w = math.max(1, math.floor(w * sc + 0.5)), h = math.max(1, math.floor(h * sc + 0.5)) }
            end
        end
        rt.slotDims[k] = dims
    end
    if InCombatLockdown() then
        pendingSync = true
        return
    end
    for unit, c in pairs(rt.engines) do
        if c.SetAuraGroupCandidateFilters then
            local tm = (unit == "target") and {} or nil
            for k = 1, MEMBER_SLOTS do
                local rec = members[k]
                local ids, fstr, exempt
                if rec then ids, fstr, exempt = MemberMapFor(rec, unit) end
                ids = ids or ParkMap()
                ApplySlotFilter(c, unit, k, ids, fstr, exempt)
                if tm and ids[0] == nil then
                    tm[k] = exempt and "exempt" or "gated"
                end
            end
            if tm then rt.slotTargetMode = tm end
        end
    end
end

function Groups.SyncAll()
    if not IS_121 then return end
    local live = {}
    for _, layout in ipairs(Store.Layouts()) do
        local groupsOf = Store.ChildrenOf(layout)
        for _, grec in ipairs(groupsOf) do
            if grec.groupKind == "aura" and not ShowsAll(grec) then
                live[grec.id] = true
                local rt = runtimes[grec.id] or BuildRuntime(grec.id)
                if rt then
                    ApplyEngineLayout(grec.id, grec)
                    AssignSlots(grec.id, grec)
                    StyleRuntimeButtons(rt)
                    UpdateEngineShown(grec.id, grec)
                end
            end
        end
    end
    -- runtimes whose group is gone or shows every aura on a unit: park
    -- (frames reused if it returns)
    for groupId, rt in pairs(runtimes) do
        if not live[groupId] then
            rt.slotTargetMode = nil
            for unit, c in pairs(rt.engines) do
                if not InCombatLockdown() and c.SetAuraGroupCandidateFilters then
                    for k = 1, MEMBER_SLOTS do
                        ApplySlotFilter(c, unit, k, ParkMap())
                    end
                end
                c:Hide()
            end
        end
    end
end

local syncQueued = false
function Groups.QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0.2, function()
        syncQueued = false
        Groups.SyncAll()
    end)
end

-- Load-window prebuild: engines and parked slots for every saved aura group.
-- Store.Init has already run, so no raw SavedVariables scan is needed.
function Groups.PreBuild()
    if not IS_121 then return end
    if not (Store and Store.Layouts) then return end
    for _, layout in ipairs(Store.Layouts()) do
        local groupsOf = Store.ChildrenOf(layout)
        for _, grec in ipairs(groupsOf) do
            if grec.groupKind == "aura" and not ShowsAll(grec) then
                local iconW, iconH = GroupDims(grec)
                local members = MembersOf(grec)
                local slotRecs = {}
                for k = 1, MEMBER_SLOTS do slotRecs[k] = members[k] end
                BuildRuntime(grec.id, {
                    iconW = iconW, iconH = iconH, slotRecs = slotRecs,
                })
            end
        end
    end
end

-- Events

-- QueueSync's 0.2s settle lets the layout engine's coalesced rebuild land
-- first, so the mirror reads the group frame's post-rebuild state
Events.OnMessage("AD_DIRTY", "adaurag", function()
    Groups.QueueSync()
end)

-- the engine's visibility pass (conditions -> alpha) fires this after every
-- paint: the rows follow their group frame's effective alpha at once
Events.OnMessage("AD_VISIBILITY", "adaurag", function()
    for gid in pairs(runtimes) do
        local g = Store.Get(gid)
        if g then UpdateEngineShown(gid, g) end
    end
end)

Events.On("PLAYER_LOGIN", "adaurag_lw", function()
    loadWindowOver = true
end)

Events.On("PLAYER_ENTERING_WORLD", "adaurag", function()
    -- staggered settle passes: layout rebuild + positions land just after PEW
    C_Timer.After(2, Groups.SyncAll)
    if (pendingBuild or pendingSync) and not AurasSecretNow() then
        pendingBuild = false
        pendingSync = false
        Groups.SyncAll()
    end
end)

Events.On("PLAYER_REGEN_ENABLED", "adaurag", function()
    if (pendingBuild or pendingSync) and not AurasSecretNow() then
        pendingBuild = false
        pendingSync = false
        Groups.SyncAll()
    end
end)
