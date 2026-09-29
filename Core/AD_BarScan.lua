-- AD_BarScan: reads the player's action bars into spell/item icon candidates.
-- Read() alone owns the scan; UI\AD_BarImport.lua is its only caller.
-- Never runs in combat: GetActionInfo can hand back secrets there.
local ADDON, NS = ...

local BarScan = {}
NS.BarScan = BarScan

-- Slots 73-120 are the 4 shapeshift/stealth pages of Action Bar 1 swapping
-- in over slots 1-12 (see forever-stealth-page-swap), not bars of their own,
-- so they get one shared label instead of eating bar numbers 7-10; the
-- sequence picks back up at 7 for the real bars that follow.
local function BarLabel(slot)
    if slot >= 73 and slot <= 120 then
        return "Action Bar 1 (form or stealth page)"
    end
    local n = math.floor((slot - 1) / 12) + 1
    if slot > 120 then n = n - 4 end
    return "Action Bar " .. n
end

-- Passive-item filter, the way the cooldown driver already judges it, so an
-- item whose data has not loaded yet is never wrongly dropped here either.
local function ItemHasUse(itemID)
    local DC = NS.DriverCooldown
    if DC and DC.IsPassiveItem then return not DC.IsPassiveItem(itemID) end
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(itemID) ~= nil end
    return false
end

-- One slot's candidate, or nil. A macro resolves the way DriverCooldown's
-- keybind walk already reads one: GetActionInfo hands back the resolved
-- spell on the macro slot itself, sub telling you which, so no macro body
-- ever needs opening. GetMacroItem no longer exists on this client, so a
-- macro's item only counts when the slot's own sub says "item".
local function SlotEntry(slot)
    local atype, id, sub = GetActionInfo(slot)
    if issecretvalue and (issecretvalue(atype) or issecretvalue(id)) then return nil end
    local kind, rid
    if atype == "spell" and type(id) == "number" and id > 0 then
        kind, rid = "spell", id
    elseif atype == "item" and type(id) == "number" and id > 0 then
        kind, rid = "item", id
    elseif atype == "macro" and id then
        local plainSub = not (issecretvalue and issecretvalue(sub)) and sub or nil
        if plainSub == "spell" and type(id) == "number" and id > 0 then
            kind, rid = "spell", id
        elseif plainSub == "item" and type(id) == "number" and id > 0 then
            kind, rid = "item", id
        elseif GetMacroSpell then
            local sid = GetMacroSpell(id)
            if type(sid) == "number" and sid > 0 then kind, rid = "spell", sid end
        end
    end
    if not kind then return nil end
    if kind == "item" and not ItemHasUse(rid) then return nil end
    return { kind = kind, id = rid, bar = BarLabel(slot), slot = slot }
end

-- Every spell/item on the action bars, first slot wins, in bar order. This
-- feeds a create-icons picker, never live state, so it only ever runs out of
-- combat and returns nil plus a reason instead of guessing.
function BarScan.Read()
    if InCombatLockdown() then
        return nil, "Can't read your action bars in combat."
    end
    local seen, out = {}, {}
    for slot = 1, 180 do
        local e = SlotEntry(slot)
        if e then
            local key = e.kind .. ":" .. e.id
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = e
            end
        end
    end
    return out
end
