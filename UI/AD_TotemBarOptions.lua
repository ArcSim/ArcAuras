-- AD_TotemBarOptions: a totem bar's rows (Bars\AD_TotemBar.lua): the Add window's pick, the Tracking pick and the card line.
-- AD_Options calls in behind nil checks (Options.TotemBarAddRows / TotemBarCanCreate / TotemBarDriver / TotemBarWhat / TotemBarTrackRows).
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local TO = {}
Options.TotemBar = TO

TO.SPELL_TIP = "The spell that puts it down. The bar follows that totem or guardian, any rank, in any slot. Empty: whatever is in the slot."

function TO.On()
    return NS.TotemBars ~= nil and NS.DriverTotem ~= nil
end

local function SpellOf(v)
    local sid = tonumber(v)
    if sid and sid > 0 then return math.floor(sid) end
    return nil
end

-- the spell's name as the game names it, else the slot's
function TO.NameFor(sid, slot)
    local nm = sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: the typed totem spell
    if nm then return nm end
    return Tr("Totem slot") .. " " .. tostring(slot or 1)
end

function Options.TotemBarAddRows(pg, owner, addState)
    if not TO.On() then return end
    local AT = NS.AT
    local function Vis() return addState.cat == "Bar" and addState.barKind == "totembar" end
    AT.RowDesc(pg, "The time left on one of your totems or guardians, by the spell that puts it down or by its slot.", 20, Vis)
    AT.RowInput(pg, "Spell ID",
        function() return addState.totemBarSpell or "" end,
        function(v) addState.totemBarSpell = v end,
        Vis, TO.SPELL_TIP, "Optional", true)
    local slotRow = AT.RowDropdown(pg, owner, "Totem slot",
        function() return addState.totemBarSlot or 1 end,
        function(v) addState.totemBarSlot = v end,
        function() return Options.TotemSlotItems() end,
        function() return Vis() and not SpellOf(addState.totemBarSpell) end)
    AT.Tooltip(slotRow, "Totem slot", Options.TotemSlotTip)
    local inSlot = AT.RowDropdown(pg, owner, "Which one",
        function() return addState.totemBarWhich or 0 end,
        function(v) addState.totemBarWhich = tonumber(v) or 0 end,
        function() return Options.TotemWhichItems() end,
        function() return Vis() and SpellOf(addState.totemBarSpell) ~= nil end)
    AT.Tooltip(inSlot, "Which one", Options.TOTEM_WHICH_TIP)
end

function Options.TotemBarCanCreate(addState)
    return TO.On()
end

-- The new bar's driver and name; its side icon wears the spell's picture.
function Options.TotemBarDriver(addState)
    local sid = SpellOf(addState.totemBarSpell)
    local slot = (not sid) and (tonumber(addState.totemBarSlot) or 1) or nil
    local only = sid and tonumber(addState.totemBarWhich)
    return { spellID = sid, slot = slot, which = (only and only >= 1) and only or nil }, TO.NameFor(sid, slot)
end

-- A card line: the totem's spell, else its slot.
function Options.TotemBarWhat(rec)
    local d = rec and rec.driver or {}
    local sid = SpellOf(d.spellID)
    if sid then return TO.NameFor(sid) end
    return Tr("totem slot %s"):format(tonumber(d.slot) or 1)
end

function Options.TotemBarTrackRows(pg, ctx, trackVis, owner)
    if not TO.On() then return end
    local AT, Store = NS.AT, NS.Store
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "totembar") and r or nil
    end
    local function Vis() return trackVis() and Rec() ~= nil end
    AT.Section(pg, "Totem", { visibleFn = Vis })
    AT.RowInput(pg, "Spell ID",
        function()
            local r = Rec()
            local sid = r and SpellOf(r.driver.spellID)
            return sid and tostring(sid) or ""
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local sid = SpellOf(v)
            if sid == SpellOf(r.driver.spellID) then return end
            r.driver.spellID = sid
            r.driver.slot = (not sid) and (tonumber(r.driver.slot) or 1) or nil
            if not sid then r.driver.which, r.driver.whichBy, r.driver.slotWait, r.driver.fromCast = nil, nil, nil, nil end
            r.name = TO.NameFor(sid, r.driver.slot)
            Store.Dirty("tree")
            Options.RefreshAll()
        end,
        Vis, TO.SPELL_TIP, "Optional")
    local slotRow = AT.RowDropdown(pg, owner, "Totem slot",
        function()
            local r = Rec()
            return r and (tonumber(r.driver.slot) or 1) or 1
        end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.slot = tonumber(v) or 1
            r.name = TO.NameFor(nil, r.driver.slot)
            Store.Dirty("tree")
            Options.RefreshAll()
        end,
        function() return Options.TotemSlotItems() end,
        function()
            local r = Rec()
            return Vis() and r ~= nil and not SpellOf(r.driver.spellID)
        end)
    AT.Tooltip(slotRow, "Totem slot", Options.TotemSlotTip)
    local inSlot = AT.RowDropdown(pg, owner, "Which one",
        function()
            local r = Rec()
            local DT = NS.DriverTotem
            return (r and DT and DT.Which(r.driver)) or 0
        end,
        function(v)
            local r = Rec()
            if not r then return end
            v = tonumber(v) or 0
            r.driver.which = (v >= 1) and v or nil
            Store.Dirty("style", r.id)
        end,
        function() return Options.TotemWhichItems() end,
        function()
            local r = Rec()
            return Vis() and r ~= nil and SpellOf(r.driver.spellID) ~= nil
        end)
    AT.Tooltip(inSlot, "Which one", Options.TOTEM_WHICH_TIP)
    -- how it counts, and when it lands after the cast (UI\AD_TotemOptions.lua)
    if Options.TotemWhichByRow then
        Options.TotemWhichByRow(pg, Rec, function()
            local r = Rec()
            return Vis() and r ~= nil and SpellOf(r.driver.spellID) ~= nil
        end, owner)
    end
    if Options.TotemTimingRows then
        Options.TotemTimingRows(pg, Rec, function()
            local r = Rec()
            return Vis() and r ~= nil and SpellOf(r.driver.spellID) ~= nil
        end, owner)
    end
    AT.Section(pg, nil)
end
