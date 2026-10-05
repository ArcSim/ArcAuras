-- AD_DriverAuraGroups: what the aura-group engines share. A Dynamic aura group
-- is drawn in play by Drivers\AD_DriverAuraRows.lua (one piece per icon) and a
-- group showing every aura on a unit by Drivers\AD_DriverUnitAuras.lua; both
-- read the member maps, the hostility gate, the button styling and the flow
-- setters from here. A unit answer that can be secret is never tested unguarded.

local ADDON, NS = ...
local Store = NS.Store
local Factory = NS.Factory

local Groups = {}
NS.DriverAuraGroups = Groups

-- Capability probe as well as a version gate: Forever (1.60.x, branched from
-- retail 12.1.5) has the engine under a lower build number.
local IS_121 = ((select(4, GetBuildInfo()) or 0) >= 120100)
    or (C_Secrets and C_Secrets.ShouldAurasBeSecret ~= nil)
local SLOT_CAP = { player = 1, target = 2, pet = 1 }  -- two casters can apply one debuff
-- the units a Dynamic aura group draws in play, in this order
local ENGINE_ORDER = { "player", "target", "pet" }

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

-- The Dynamic toggle is the live-view switch: off, the group stays a static
-- grid in play.
local function IsDynamic(grec)
    return grec ~= nil and Store.Resolve(grec, "arrangement", "dynamicLayout") == true
end
Groups.IsDynamic = IsDynamic

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

-- One member's include map for one unit, parked when its lane is not that
-- unit's. A lane no unit carries (focus, party, target buffs, your debuffs)
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

Groups.SLOT_CAP = SLOT_CAP
Groups.ENGINE_ORDER = ENGINE_ORDER
Groups.ParkMap = ParkMap
Groups.TargetFiltersHonored = TargetFiltersHonored
Groups.MemberMapFor = MemberMapFor

-- Button styling

-- A button exists only while its member's aura is up, so the active look is
-- drawn on it; no presence read, which fails closed while auras are secret.
-- No ghost under a play-mode button, so no plate. Size comes from the slot's
-- plain dims. rt is anything with slotRecs, slotDims, cfg (and buttons and
-- engines for StyleButtons): a piece, or a show-all runtime.
local function StyleSlotButton(b, rt)
    local rec = rt.slotRecs and rt.slotRecs[b._adSlotIndex or 0]
    if not rec then return end
    -- The border is drawn on the text overlay, so any border host is hidden.
    if b._adBorderHost then b._adBorderHost:Hide() end
    local dims = rt.slotDims and rt.slotDims[b._adSlotIndex or 0]
    local w = (dims and dims.w) or rt.cfg.iconW or 36
    local h = (dims and dims.h) or rt.cfg.iconH or 36
    -- rt.erase: a piece born in its Missing look's stage
    Factory.StyleAuraButton(b, rec, h, { w = w, h = h, ghost = false, erase = rt.erase == true,
        rowGlows = rt.rowGlows == true, rowLanes = rt.rowLanes })
    -- a runtime's own parts after the look (a show-all group's type looks)
    if rt.afterStyle then rt.afterStyle(b, rt, rec, w, h) end
end
Groups.StyleSlotButton = StyleSlotButton

-- Restyles rt's buttons where the game allows it (resized first, when their
-- size changed). True when one was locked, so the caller retries at its
-- settle edge.
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

-- Layout helpers

-- A group's cell size, spacing, columns and growth, from its arrangement. Each
-- size and spacing is whole pixels, rounded as the engine's grid rounds them,
-- so aura rows step exactly like the static grid at any UI scale.
local function GroupDims(grec)
    local R = function(field) return Store.Resolve(grec, "arrangement", field) end
    local E = NS.LayoutEngine
    local Snap = E and E.Snap or function(v) return v end
    local scale = math.floor((R("iconSize") or 36) + 0.5) / 36
    local w = Snap(math.floor((R("iconWidth") or 36) * scale + 0.5))
    local h = Snap(math.floor((R("iconHeight") or 36) * scale + 0.5))
    local spBase = R("spacing") or 2
    local sep = R("separateSpacing") == true
    local sx = Snap(sep and (R("spacingX") or spBase) or spBase)
    local sy = Snap(sep and (R("spacingY") or spBase) or spBase)
    return w, h, sx, sy, math.max(1, R("cols") or 6),
        R("growthH") or "RIGHT", R("growthV") or "DOWN"
end
Groups.GroupDims = GroupDims

-- One container's flow: the spacing of each of its groups (keys), the line
-- size, the padding, the reading direction and the corner the buttons start
-- from, through whichever setter names this client has. Returns the corner.
local function ApplyFlow(c, keys, sx, sy, lineSize, pad, flowRight, flowDown)
    if c.SetAuraGroupLayout then
        for _, key in ipairs(keys) do
            -- Every button already leaves elementSpacing after itself, so a
            -- group gap would put two spacings between groups' buttons.
            c:SetAuraGroupLayout(key, {
                elementSpacingX = sx, elementSpacingY = sy,
                elementSpacing = sx, lineSpacing = sy,
                groupSpacing = 0, groupLineSpacing = sy,
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

-- Mirror the group frame's shown state, effective alpha and strata onto a
-- container, which is not its child: conditions and the flip must carry over.
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
