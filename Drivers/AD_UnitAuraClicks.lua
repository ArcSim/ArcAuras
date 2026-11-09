-- AD_UnitAuraClicks: Click the icons on a party or raid aura group, one secure button over each member's line.
-- Whether an aura is up is secret in combat, so a line is clickable whenever its member exists. RegisterUnitWatch shows it for them.
-- Every button hangs from UIParent or a unit frame, never from the group frame: a protected frame would lock its anchor in combat.
-- Protected state changes out of combat only; UA.pending brings a rebuild at the settle edge.
local ADDON, NS = ...
local CreateFrame = NS.Perf and NS.Perf.Frames("UnitAuraClicks") or function(...) return CreateFrame(...) end
local Events = NS.Events

local UC = {
    strips = {},  -- [groupId] = { [i] = button }
    dropped = {}, -- [groupId] = true while its buttons wait for combat to end
}
NS.UnitAuraClicks = UC

UC.LEVEL = 20

-- What a saved pick does here: nil for Nothing and a spell this character
-- lacks; a spell's name reaches the top rank you know.
function UC.Action(pick)
    if pick == "target" then return "target" end
    local id = type(pick) == "string" and tonumber(pick:match("^s(%d+)$"))
    if not id or NS.Store.KnowsSpell(id) == false then return nil end
    local name = C_Spell.GetSpellName(id) -- raw-id: a fixed dispel from the schema list
    local top = name and C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(name) -- raw-id: the top rank of that dispel
    return "spell", top or id
end

function UC.Attr(b, name, v)
    if b._adAttrs[name] == v and b._adAttrs[name .. "?"] then return end
    b._adAttrs[name], b._adAttrs[name .. "?"] = v, true
    b:SetAttribute(name, v)
end

function UC.Ensure(gid, i)
    local list = UC.strips[gid]
    if not list then
        list = {}
        UC.strips[gid] = list
    end
    local b = list[i]
    if not b then
        b = CreateFrame("Button", "ArcAurasDebuffClick" .. gid .. "_" .. i, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp")
        b._adAttrs = {}
        UC.Attr(b, "useOnKeyDown", false)
        list[i] = b
    end
    return b
end

function UC.Button(b, n, pick, unit)
    local kind, spell = UC.Action(pick)
    UC.Attr(b, "type" .. n, kind)
    UC.Attr(b, "spell" .. n, spell)
    UC.Attr(b, "unit" .. n, unit)
end

function UC.Off(b)
    if b._adWatched then
        UnregisterUnitWatch(b)
        b._adWatched = false
    end
    b:Hide()
end

-- Member i's line in UIParent's units: its block's place in the group's box.
function UC.BlockRect(p, i, cfg)
    if not (cfg.members and p.memberStep) then return 0, 0, p.boxW, p.boxH end
    local a, c = NS.DriverUnitAuras.BlockDelta(p, i)
    local px, py = a, c
    if p.vertical then px, py = c, a end
    local left = p.right and (p.pad + px) or (p.boxW - p.pad - px - p.blockW)
    local top = p.down and (p.pad + py) or (p.boxH - p.pad - py - p.blockH)
    return left, top, p.blockW, p.blockH
end

function UC.Hang(b, gf, p, cfg, i, frame, k)
    local UA = NS.DriverUnitAuras
    local left, top, w, h = UC.BlockRect(p, i, cfg)
    b:ClearAllPoints()
    b:SetSize(w * k, h * k)
    if frame then
        local point, rel = UA.FramePoint(cfg)
        b:SetPoint(point, frame, rel, cfg.frameX * k, cfg.frameY * k)
    else
        b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (gf:GetLeft() + left) * k, (gf:GetTop() - top) * k)
    end
end

function UC.Wanted(g, cfg, editMode)
    return cfg.clicks == true and not editMode and NS.DriverUnitAuras.Drawn(g)
end

-- The engine placed the group. In combat nothing here may change, so a
-- rebuild comes back at the settle edge.
function UC.Place(g, rt, gf, cfg, p, editMode)
    local UA = NS.DriverUnitAuras
    if InCombatLockdown() then
        if cfg.clicks or UC.strips[g.id] then UA.pending = true end
        return
    end
    UC.dropped[g.id] = nil
    local n = 0
    if UC.Wanted(g, cfg, editMode) and gf:GetLeft() and gf:GetTop() then
        n = UA.Covered(rt)
        local gs, us = gf:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local k = 1
        if not (issecretvalue and issecretvalue(gs)) and us > 0 then k = gs / us end
        for i = 1, n do
            local b = UC.Ensure(g.id, i)
            local unit = UA.TokenFor(cfg, i)
            UC.Attr(b, "unit", unit)
            UC.Button(b, 1, cfg.clickLeft, unit)
            UC.Button(b, 2, cfg.clickRight, unit)
            b:SetFrameStrata(gf:GetFrameStrata())
            b:SetFrameLevel(gf:GetFrameLevel() + UC.LEVEL)
            UC.Hang(b, gf, p, cfg, i, rt.frames and rt.frames[i], k)
            if not b._adWatched then
                RegisterUnitWatch(b)
                b._adWatched = true
            end
        end
    end
    local list = UC.strips[g.id]
    if list then
        for i = n + 1, #list do UC.Off(list[i]) end
    end
end

-- The group is gone or not drawn.
function UC.Let(gid)
    if not UC.strips[gid] then return end
    if InCombatLockdown() then
        UC.dropped[gid] = true
        return
    end
    for _, b in ipairs(UC.strips[gid]) do UC.Off(b) end
end

Events.On("PLAYER_REGEN_ENABLED", "aduc", function()
    for gid in pairs(UC.dropped) do
        UC.dropped[gid] = nil
        -- it may have come back and been placed during the fight
        if not NS.DriverUnitAuras.placed[gid] then UC.Let(gid) end
    end
end)
