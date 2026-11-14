-- AD_BarRestore: keeps a copy of what sits on each action button, per character and per talent spec, and puts a copy
-- back, for when the game loads a spec's bars empty after a login; after a login, reload or spec swap it asks in a box.
-- WoW Forever only. Setting: "barRestore", off until switched on. Owns Store.UI().barSaves; the Modules page
-- (UI\AD_BarRestoreOptions.lua) calls Save, Load and the reads.
-- The game fills buttons only out of combat with an empty cursor, so a load asked for in combat runs when combat ends.
local ADDON, NS = ...
if NS.IsForever ~= true then return end
local C_Timer = NS.Perf and NS.Perf.Timers("BarRestore") or C_Timer   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("BarRestore") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames
local Store, Events, AT = NS.Store, NS.Events, NS.AT
local BR = {}
NS.BarRestore = BR

local KEY = "adbarrestore"
local KEY_CHECK = "adbarrestorecheck"
-- The bars arrive a moment after the loading screen, and a spec swap fills them over a moment too.
BR.CHECK_AFTER = 5
local ASK_NAME = "ArcAurasBarRestoreAsk"
local ASK_PAD, ASK_GAP, ASK_TOP, ASK_BTN_W, ASK_MAX_W = 12, 6, 160, 92, 460
-- Names in the box before the rest is a count.
local ASK_NAMES = 6
-- Pages 1 to 10 (the main bar, the side bars, each stance's bar) and 13 to 15 (bars 6 to 8). Page 11 belongs to
-- vehicles and page 12 to the totem bar, which the game fills itself.
BR.SLOTS = {}
for s = 1, 120 do BR.SLOTS[#BR.SLOTS + 1] = s end
for s = 145, 180 do BR.SLOTS[#BR.SLOTS + 1] = s end
-- Kinds a load can put back; any other kind stays in the save and is reported as not placed.
BR.PLACEABLE = { spell = true, macro = true, item = true, equipmentset = true, summonmount = true, summonpet = true,
    flyout = true }
BR.RANDOM_MOUNT = 0x0FFFFFFF   -- the action id the game gives its random favorite mount
local RANDOM_MOUNT_SPELL = 150544 -- raw-id: the random favorite mount's spell, for its name
-- Many buttons change at once while the bars load or a spec swaps: the page redraws once after them.
local NOTIFY_AFTER = 0.2

local pending   -- the save a load asked for in combat will use
local busy      -- our own placing is running
local queued, pick
local listening = {}   -- [event] = true while subscribed
local checkGen = 0
local ask, askG, askQueued
local declined = {}    -- [spec] = true after Not now, until the next login or reload
BR.last = nil   -- the last load for the page: { placed, same, missed = { names }, value } or { why, value }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function InCombat() return InCombatLockdown ~= nil and InCombatLockdown() == true end
local function CursorBusy() return GetCursorInfo() ~= nil end

local function EventValid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
end

local function Tell()
    if busy or queued or not BR.notify then return end
    queued = true
    C_Timer.After(NOTIFY_AFTER, function()
        queued = false
        if BR.notify then BR.notify() end
    end)
end

local function Text(v)
    if Secret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

local function ActionText(slot)
    local f = (C_ActionBar and C_ActionBar.GetActionText) or GetActionText
    return f and Text(f(slot))
end

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    return Text(C_Spell.GetSpellName(id)) -- raw-id: a bar slot's spell
end

local function ItemName(id)
    if not (C_Item and C_Item.GetItemNameByID) then return nil end
    return Text(C_Item.GetItemNameByID(id))
end

-- Mounts, pets and flyouts are kept by number or GUID; their names say which one a load could not place.
local function OtherName(k, id)
    if Secret(id) then return nil end
    if k == "summonmount" and type(id) == "number" then
        if id == BR.RANDOM_MOUNT then return SpellName(RANDOM_MOUNT_SPELL) end
        local MJ = C_MountJournal
        return MJ and MJ.GetMountInfoByID and Text((MJ.GetMountInfoByID(id))) or nil
    elseif k == "summonpet" and type(id) == "string" then
        local PJ = C_PetJournal
        if not (PJ and PJ.GetPetInfoByPetID) then return nil end
        local _, custom, _, _, _, _, _, name = PJ.GetPetInfoByPetID(id)
        return Text(custom) or Text(name)
    elseif k == "flyout" and type(id) == "number" then
        return GetFlyoutInfo and Text((GetFlyoutInfo(id))) or nil
    end
    return nil
end

local function NameOf(e) return e.n or OtherName(e.k, e.id) or e.k end

-- 1 or 2; nil when the game answers something else. Single-spec clients have only the first.
function BR.Group()
    local g
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        g = C_SpecializationInfo.GetActiveSpecGroup()
    elseif GetActiveTalentGroup then
        g = GetActiveTalentGroup()
    else
        return 1
    end
    if Secret(g) then return nil end
    if g == 1 or g == 2 then return g end
    return nil
end

-- The talent frame's own tab name for spec g, in the client's language.
function BR.SpecWord(g)
    local game
    if g == 2 then game = DUAL_SPEC_SECONDARY else game = DUAL_SPEC_PRIMARY end
    if type(game) == "string" and game ~= "" then return game end
    if g == 2 then return AT.Tr("Secondary") end
    return AT.Tr("Primary")
end

local function MyKey()
    local g = UnitGUID("player")
    if Secret(g) or type(g) ~= "string" or g == "" then return nil end
    return g
end

local function MyClass()
    local _, class = UnitClass("player")
    return Text(class)
end

local function Saves(create)
    local ui = Store.UI()
    if create and type(ui.barSaves) ~= "table" then ui.barSaves = {} end
    return type(ui.barSaves) == "table" and ui.barSaves or nil
end

-- One button as a save keeps it: nil when empty, false when it cannot be read (a secret).
local function Read(slot)
    local kind, id = GetActionInfo(slot)
    if kind == nil then return nil end
    if Secret(kind) or Secret(id) then return false end
    if kind == "spell" then
        if type(id) ~= "number" or id <= 0 then return false end
        return { k = "spell", id = id, n = SpellName(id) }
    elseif kind == "macro" then
        -- the action's id can be the spell the macro shows; the name finds the macro again
        return { k = "macro", n = ActionText(slot) }
    elseif kind == "item" then
        return { k = "item", id = id, n = type(id) == "number" and ItemName(id) or nil }
    elseif kind == "equipmentset" then
        return { k = "equipmentset", id = id, n = Text(id) or ActionText(slot) }
    end
    return { k = kind, id = id, n = OtherName(kind, id) }
end
BR.Read = Read

-- A different rank of the same spell counts as the same, so a rank-up on the bars is never undone.
local function Same(now, want)
    if not now or not want or now.k ~= want.k then return false end
    if want.k == "spell" then return now.id == want.id or (want.n ~= nil and now.n == want.n) end
    if want.k == "macro" then return want.n ~= nil and now.n == want.n end
    return now.id == want.id
end
BR.Same = Same

local function Snapshot()
    local slots, n = {}, 0
    for _, s in ipairs(BR.SLOTS) do
        local e = Read(s)
        if e == false then return nil end
        if e then
            slots[s] = e
            n = n + 1
        end
    end
    return slots, n
end

-- A spec save's value is "<character>:<1|2>"; a named profile's is "profile:<id>".
local function Value(key, g) return key .. ":" .. g end
local function ProfileValue(id) return "profile:" .. id end

local function Split(value)
    if type(value) ~= "string" then return nil end
    local id = value:match("^profile:(%d+)$")
    if id then return nil, nil, tonumber(id) end
    local key, g = value:match("^(.+):([12])$")
    return key, tonumber(g)
end

local function Valid(save) return type(save) == "table" and type(save.slots) == "table" end

local function Profiles(create)
    local ui = Store.UI()
    if create and type(ui.barProfiles) ~= "table" then ui.barProfiles = {} end
    return type(ui.barProfiles) == "table" and ui.barProfiles or nil
end

function BR.SaveOf(value)
    local key, g, id = Split(value)
    if id then
        local all = Profiles(false)
        local p = all and all[id]
        return Valid(p) and p or nil
    end
    local all = Saves(false)
    local who = key and all and all[key]
    local save = type(who) == "table" and who[g] or nil
    return Valid(save) and save or nil
end

-- This character's save for spec g, or nil.
function BR.MySave(g)
    local key = MyKey()
    return key and g and BR.SaveOf(Value(key, g)) or nil
end

-- Action Bars 2 to 8 on or off, read as the game's own options read them: every value GetActionBarToggles gives. The
-- first seven become true or false; any value after them goes back to the game exactly as it came.
local function ReadBars()
    if not GetActionBarToggles then return nil end
    local n = select("#", GetActionBarToggles())
    if n < 7 then return nil end
    local t = { GetActionBarToggles() }
    for i = 1, n do
        if Secret(t[i]) then return nil end
        if i <= 7 then t[i] = t[i] and true or false end
    end
    t.n = n
    return t
end
BR.ReadBars = ReadBars

local function SevenOf(t)
    if type(t) ~= "table" then return nil end
    local c = {}
    for i = 1, 7 do c[i] = t[i] == true end
    return c
end

local needReload   -- bars 2 to 8 were set this session; the game draws them at the next reload

-- Sets bars 2 to 8 the way the game's options do: the whole set back with only the first seven changed. The game
-- keeps it on its servers and draws it at the next reload; drawing it now from addon code would taint the bars' paging.
local function SetBars(want)
    if type(want) ~= "table" or not SetActionBarToggles then return false end
    local now = ReadBars()
    if not now then return false end
    local changed = false
    for i = 1, 7 do
        local v = want[i] == true
        if now[i] ~= v then
            now[i] = v
            changed = true
        end
    end
    if changed then
        SetActionBarToggles(unpack(now, 1, now.n))
        needReload = true
    end
    return changed
end

local function PresetLayouts()
    local m = EditModePresetLayoutManager
    return (type(m) == "table" and type(m.presetLayoutInfo) == "table") and m.presetLayoutInfo or {}
end

-- The active Edit Mode layout by name; preset = true for a built-in one. Built-in layouts count first in the index.
local function ReadLayout()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local info = C_EditMode.GetLayouts()
    local i = type(info) == "table" and info.activeLayout or nil
    if type(i) ~= "number" or Secret(i) then return nil end
    local presets = PresetLayouts()
    if i <= #presets then
        local name = type(presets[i]) == "table" and Text(presets[i].layoutName) or nil
        return name and { name = name, preset = true } or nil
    end
    local l = type(info.layouts) == "table" and info.layouts[i - #presets] or nil
    local name = type(l) == "table" and Text(l.layoutName) or nil
    return name and { name = name } or nil
end
BR.ReadLayout = ReadLayout

-- Switches to a layout by name as Edit Mode's own picker does; the game's layout event then applies it.
-- "same", "switched", "gone", or "editmode" while the editor is open.
local function SetLayout(want)
    if type(want) ~= "table" or not want.name then return nil end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout) then return nil end
    local info = C_EditMode.GetLayouts()
    if type(info) ~= "table" then return nil end
    local presets, index = PresetLayouts(), nil
    if want.preset then
        for j, p in ipairs(presets) do
            if type(p) == "table" and p.layoutName == want.name then index = j break end
        end
    else
        for j, l in ipairs(type(info.layouts) == "table" and info.layouts or {}) do
            if type(l) == "table" and l.layoutName == want.name then index = #presets + j break end
        end
    end
    if not index then return "gone" end
    if index == info.activeLayout then return "same" end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return "editmode" end
    C_EditMode.SetActiveLayout(index)
    return "switched"
end

function BR.NeedsReload() return needReload == true end

-- What a save keeps: the buttons, bars 2 to 8 and the Edit Mode layout. Nil and why when the bars cannot be read.
local function Record()
    if InCombat() then return nil, "combat" end
    local slots, n = Snapshot()
    if not slots then return nil, "combat" end
    if n == 0 then return nil, "empty" end
    return { t = time(), n = n, slots = slots, bars = SevenOf(ReadBars()), layout = ReadLayout() }
end

-- Saves the bars into a spec save or a named profile; value nil is the active spec's own save. A spec save takes only
-- its own character in its own spec, since the login check compares with it. A save with fewer buttons than the one it
-- replaces needs force: the bars it reads may be the ones the game left empty. Returns the count, or nil and why.
function BR.Save(value, force)
    if not BR.IsOn() then return nil, "off" end
    local me, active = MyKey(), BR.Group()
    if not (me and active) then return nil, "spec" end
    value = value or Value(me, active)
    local key, g, id = Split(value)
    if id then
        if not BR.SaveOf(value) then return nil, "none" end
    elseif key ~= me then
        return nil, "notyours"
    elseif g ~= active then
        return nil, "otherspec"
    end
    local rec, why = Record()
    if not rec then return nil, why end
    local old = BR.SaveOf(value)
    if old and not force and rec.n < (old.n or 0) then return nil, "fewer", (old.n or 0) - rec.n end
    if id then
        old.t, old.n, old.slots, old.bars, old.layout = rec.t, rec.n, rec.slots, rec.bars, rec.layout
        old.owner, old.class = Text(UnitName("player")), MyClass()
    else
        local all = Saves(true)
        local who = type(all[me]) == "table" and all[me] or {}
        all[me] = who
        who.name, who.class = Text(UnitName("player")), MyClass()
        who[g] = rec
    end
    Tell()
    return rec.n
end

local NAME_MAX = 40

local function FreeName()
    local used, all = {}, Profiles(false) or {}
    for _, p in pairs(all) do
        if type(p) == "table" and p.name then used[p.name] = true end
    end
    local k = 1
    while used[AT.Tr("Profile %d"):format(k)] do k = k + 1 end
    return AT.Tr("Profile %d"):format(k)
end

-- A named profile from the bars as they are now; it becomes the pick. Returns its value, or nil and why.
function BR.NewProfile()
    if not BR.IsOn() then return nil, "off" end
    local rec, why = Record()
    if not rec then return nil, why end
    local ui, all = Store.UI(), Profiles(true)
    local id = (tonumber(ui.barProfileNext) or 0) + 1
    while all[id] ~= nil do id = id + 1 end
    ui.barProfileNext = id
    rec.name, rec.owner, rec.class = FreeName(), Text(UnitName("player")), MyClass()
    all[id] = rec
    pick = ProfileValue(id)
    Tell()
    return pick
end

-- Names are trimmed and kept to 40 bytes, a cut character dropped. False when nothing changed.
function BR.Rename(value, name)
    local _, _, id = Split(value)
    local p = id and BR.SaveOf(value)
    if not p or type(name) ~= "string" then return false end
    name = (name:gsub("^%s+", ""):gsub("%s+$", ""))
    if #name > NAME_MAX then name = (name:sub(1, NAME_MAX):gsub("[\192-\255][\128-\191]*$", "")) end
    if name == "" or name == p.name then return false end
    p.name = name
    Tell()
    return true
end

function BR.Delete(value)
    local _, _, id = Split(value)
    local all = Profiles(false)
    if not (id and all and all[id] ~= nil) then return false end
    all[id] = nil
    if pick == value then pick = nil end
    Tell()
    return true
end

-- Everything the dropdown offers: this character's Primary and Secondary (saved or not), the named profiles by name,
-- then other characters' spec saves by name. Any character may load any of them.
-- { value, kind = "spec" / "profile", g, mine, name, saved }
function BR.Sources()
    local list, me = {}, MyKey()
    if not me then return list end
    local saves = Saves(false) or {}
    local mine = type(saves[me]) == "table" and saves[me] or {}
    for g = 1, 2 do
        list[#list + 1] = { value = Value(me, g), kind = "spec", g = g, mine = true, saved = Valid(mine[g]) }
    end
    local profiles, ids = Profiles(false) or {}, {}
    for id, p in pairs(profiles) do
        if type(id) == "number" and Valid(p) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local x, y = tostring(profiles[a].name), tostring(profiles[b].name)
        if x ~= y then return x < y end
        return a < b
    end)
    for _, id in ipairs(ids) do
        list[#list + 1] = { value = ProfileValue(id), kind = "profile", name = profiles[id].name, saved = true }
    end
    local others = {}
    for key, who in pairs(saves) do
        if key ~= me and type(who) == "table" then others[#others + 1] = key end
    end
    table.sort(others, function(a, b) return tostring(saves[a].name) < tostring(saves[b].name) end)
    for _, key in ipairs(others) do
        for g = 1, 2 do
            if Valid(saves[key][g]) then
                list[#list + 1] = { value = Value(key, g), kind = "spec", g = g, name = saves[key].name, saved = true }
            end
        end
    end
    return list
end

-- The Sources entry for a value, or nil.
function BR.Info(value)
    for _, s in ipairs(BR.Sources()) do
        if s.value == value then return s end
    end
    return nil
end

-- The dropdown's choice: what was picked while it still exists, else the active spec's own save.
function BR.Pick()
    local list = BR.Sources()
    for _, s in ipairs(list) do
        if s.value == pick then return pick end
    end
    local me, g = MyKey(), BR.Group()
    if me and g then return Value(me, g) end
    return list[1] and list[1].value or nil
end

function BR.SetPick(value)
    pick = value
    Tell()
end

-- How many saved buttons differ from the bars now; nil in combat or without that save.
function BR.Differs(value)
    if InCombat() then return nil end
    local save = BR.SaveOf(value)
    if not save then return nil end
    local n = 0
    for _, s in ipairs(BR.SLOTS) do
        local want = save.slots[s]
        if want and not Same(Read(s), want) then n = n + 1 end
    end
    return n
end

local function Known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end -- raw-id: a saved bar slot's spell
    if IsSpellKnown and IsSpellKnown(id) then return true end -- raw-id: a saved bar slot's spell
    return false
end

-- The saved rank while it is known, else the top rank known by the spell's name (a save from another character).
local function SpellToPlace(e)
    if type(e.id) == "number" and Known(e.id) then return e.id end
    if e.n and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local best = C_Spell.GetSpellIDForSpellIdentifier(e.n) -- raw-id: a saved bar slot's spell
        if type(best) == "number" and not Secret(best) and best > 0 and Known(best) then return best end
    end
    return nil
end

local function MountOwned(id)
    if type(id) ~= "number" then return false end
    if id == BR.RANDOM_MOUNT then return true end
    local MJ = C_MountJournal
    if not (MJ and MJ.GetMountInfoByID) then return false end
    local collected = select(11, MJ.GetMountInfoByID(id))
    return collected == true
end

-- The journal picks up a mount by its place in the list it shows.
local function MountIndex(id)
    local MJ = C_MountJournal
    if not (MJ and MJ.GetNumDisplayedMounts and MJ.GetDisplayedMountID) then return nil end
    for i = 1, MJ.GetNumDisplayedMounts() do
        if MJ.GetDisplayedMountID(i) == id then return i end
    end
    return nil
end

local function PetOwned(id)
    local PJ = C_PetJournal
    if type(id) ~= "string" or not (PJ and PJ.GetPetInfoByPetID) then return false end
    return PJ.GetPetInfoByPetID(id) ~= nil
end

-- A flyout is picked up from its spellbook slot.
local function FlyoutSlot(id)
    local SB, E = C_SpellBook, Enum
    local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Player
    local flyout = E and E.SpellBookItemType and E.SpellBookItemType.Flyout
    if type(id) ~= "number" or bank == nil or flyout == nil then return nil end
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
        return nil
    end
    for line = 1, SB.GetNumSpellBookSkillLines() do
        local li = SB.GetSpellBookSkillLineInfo(line)
        if li and type(li.itemIndexOffset) == "number" and type(li.numSpellBookItems) == "number" then
            for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                local info = SB.GetSpellBookItemInfo(slot, bank)
                if info and info.itemType == flyout and info.actionID == id then return slot, bank end
            end
        end
    end
    return nil
end

-- Puts the saved thing on the cursor; true when the cursor holds that kind.
local function Pickup(e)
    if e.k == "spell" then
        local id = SpellToPlace(e)
        if not id then return false end
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(id) -- raw-id: a saved bar slot's spell
        elseif PickupSpell then PickupSpell(id) end -- raw-id: a saved bar slot's spell
        local kind, _, _, cid = GetCursorInfo()
        return kind == "spell" and (cid == nil or cid == id)
    elseif e.k == "macro" then
        local i = e.n and GetMacroIndexByName and GetMacroIndexByName(e.n)
        if type(i) ~= "number" or i <= 0 or not PickupMacro then return false end
        PickupMacro(i)
        return GetCursorInfo() == "macro"
    elseif e.k == "item" then
        local f = (C_Item and C_Item.PickupItem) or PickupItem
        if type(e.id) ~= "number" or not f then return false end
        f(e.id)
        return GetCursorInfo() == "item"
    elseif e.k == "equipmentset" then
        local ES = C_EquipmentSet
        if not (ES and ES.PickupEquipmentSet) then return false end
        local id = e.id
        if type(id) ~= "number" and e.n and ES.GetEquipmentSetID then id = ES.GetEquipmentSetID(e.n) end
        if type(id) ~= "number" then return false end
        ES.PickupEquipmentSet(id)
        return GetCursorInfo() == "equipmentset"
    elseif e.k == "summonmount" then
        local MJ = C_MountJournal
        if not (MJ and MJ.Pickup and MountOwned(e.id)) then return false end
        if e.id == BR.RANDOM_MOUNT then
            MJ.Pickup(0)
            return CursorBusy()
        end
        local i = MountIndex(e.id)
        if i then MJ.Pickup(i) end
        if not CursorBusy() then
            -- the journal's filters or search can hide it from the list; its spell places the same mount
            local _, spell = MJ.GetMountInfoByID(e.id)
            local f = (C_Spell and C_Spell.PickupSpell) or PickupSpell
            if type(spell) == "number" and not Secret(spell) and f then f(spell) end -- raw-id: a saved mount's spell
        end
        return CursorBusy()
    elseif e.k == "summonpet" then
        local PJ = C_PetJournal
        if not (PJ and PJ.PickupPet and PetOwned(e.id)) then return false end
        PJ.PickupPet(e.id)
        return CursorBusy()
    elseif e.k == "flyout" then
        local slot, bank = FlyoutSlot(e.id)
        if not (slot and C_SpellBook.PickupSpellBookItem) then return false end
        C_SpellBook.PickupSpellBookItem(slot, bank)
        return CursorBusy()
    end
    return false
end

-- Whatever the button held lands on the cursor and is dropped.
local function Place(slot, e)
    if not (BR.PLACEABLE[e.k] and Pickup(e)) then
        ClearCursor()
        return false
    end
    PlaceAction(slot)
    ClearCursor()
    return true
end

-- Only buttons the save fills are touched; a button the save has empty keeps what it holds now.
local function Apply(save, value)
    local placed, same, missed, seen = 0, 0, {}, {}
    busy = true
    for _, s in ipairs(BR.SLOTS) do
        local want = save.slots[s]
        if type(want) == "table" then
            if Same(Read(s), want) then
                same = same + 1
            elseif Place(s, want) then
                placed = placed + 1
            else
                local name = NameOf(want) or "?"
                if not seen[name] then
                    seen[name] = true
                    missed[#missed + 1] = name
                end
            end
        end
    end
    busy = false
    BR.last = { placed = placed, same = same, missed = missed, value = value }
    Tell()
    return placed, missed
end

local pendingButtonsOnly

local function AfterCombat()
    Events.Off("PLAYER_REGEN_ENABLED", KEY)
    local v, only = pending, pendingButtonsOnly
    pending, pendingButtonsOnly = nil, nil
    if v == nil then return end
    local n, why = BR.Load(v, only)
    if n == nil and why ~= "combat" then
        BR.last = { why = why, value = v }
        Tell()
    end
end

-- Fills the bars from a save, then (unless buttonsOnly) sets bars 2 to 8 and switches to its Edit Mode layout.
-- Returns how many buttons were filled and the names that could not be, or nil and why; in combat it waits for combat
-- to end. BR.last also says whether bars 2 to 8 changed (they draw at the next reload) and what the layout did.
function BR.Load(value, buttonsOnly)
    if not BR.IsOn() then return nil, "off" end
    local save = BR.SaveOf(value)
    if not save then return nil, "none" end
    if InCombat() then
        pending, pendingButtonsOnly = value, buttonsOnly
        Events.On("PLAYER_REGEN_ENABLED", KEY, AfterCombat)
        Tell()
        return nil, "combat"
    end
    if CursorBusy() then return nil, "cursor" end
    local placed, missed = Apply(save, value)
    if not buttonsOnly then
        local last = BR.last
        last.bars = SetBars(save.bars)
        last.layout = SetLayout(save.layout)
        last.layoutName = type(save.layout) == "table" and save.layout.name or nil
    end
    return placed, missed
end

function BR.Pending() return pending ~= nil end

-- Whether a load could fill this saved button now: a spell this spec lacks or a deleted macro is no reason to ask.
local function CanPlace(e)
    if type(e) ~= "table" or not BR.PLACEABLE[e.k] then return false end
    if e.k == "spell" then return SpellToPlace(e) ~= nil end
    if e.k == "macro" then
        local i = e.n and GetMacroIndexByName and GetMacroIndexByName(e.n)
        return type(i) == "number" and i > 0
    end
    if e.k == "item" then return type(e.id) == "number" end
    if e.k == "summonmount" then return MountOwned(e.id) end
    if e.k == "summonpet" then return PetOwned(e.id) end
    if e.k == "flyout" then return FlyoutSlot(e.id) ~= nil end
    return true
end

-- Saved buttons that are empty now and that a load could fill: the count and their names. Nil in combat.
function BR.Empties(save)
    if InCombat() or not Valid(save) then return nil end
    local n, names, seen = 0, {}, {}
    for _, s in ipairs(BR.SLOTS) do
        local want = save.slots[s]
        if want and Read(s) == nil and CanPlace(want) then
            n = n + 1
            local name = NameOf(want)
            if name and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    return n, names
end

-- The question box

local Listen, Check

function BR.AskShown() return ask ~= nil and ask:IsShown() end

local function CloseAsk()
    askG = nil
    if ask then ask:Hide() end
end

local function NameList(list)
    local shown = {}
    for i = 1, math.min(#list, ASK_NAMES) do shown[i] = list[i] end
    local s = table.concat(shown, ", ")
    if #list > ASK_NAMES then return AT.Tr("%s and %d more"):format(s, #list - ASK_NAMES) end
    return s
end

-- Both buttons one width, the row and the box centred, every edge on a whole pixel.
local function LayAsk()
    local widest = 0
    for _, b in ipairs(ask.btns) do widest = math.max(widest, b:GetWidth()) end
    local w, h = AT.PixelSize(ask, widest), AT.PixelSize(ask, 22)
    local pad, gap = AT.PixelSize(ask, ASK_PAD), AT.PixelSize(ask, ASK_GAP)
    local rowW = #ask.btns * w + (#ask.btns - 1) * gap
    local textW = math.max(ask.q:GetStringWidth() or 0, ask.nameFS:GetStringWidth() or 0)
    local boxW = AT.PixelSize(ask, math.min(ASK_MAX_W, math.max(rowW, textW) + pad * 2))
    ask.nameFS:SetWidth(boxW - pad * 2)
    local x0 = AT.PixelSize(ask, (boxW - rowW) / 2)
    for i, b in ipairs(ask.btns) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", ask, "BOTTOMLEFT", x0 + (i - 1) * (w + gap), pad)
    end
    ask:SetSize(boxW, AT.PixelSize(ask, 84))
    local px = AT.Px(ask)
    local x = (UIParent:GetWidth() - boxW) / 2
    if px > 0 then x = math.floor(x / px + 0.5) * px end
    ask:ClearAllPoints()
    ask:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -AT.PixelSize(ask, ASK_TOP))
end

local function AskLoad()
    local g, key = askG, MyKey()
    if not (g and key) then CloseAsk() return end
    local _, why = BR.Load(Value(key, g), true)
    if why == "cursor" then
        local b = ask.btns[1]
        b:SetLabel("Empty your cursor first")
        LayAsk()
        C_Timer.After(1.6, function()
            if ask and ask.btns[1] == b then
                b:SetLabel("Load")
                LayAsk()
            end
        end)
        return
    end
    CloseAsk()
end

local function AskNotNow()
    if askG then declined[askG] = true end
    CloseAsk()
end

local function BuildAsk()
    if ask then return end
    local COL = AT.COL
    ask = CreateFrame("Frame", ASK_NAME, UIParent)
    ask:Hide()
    ask:SetFrameStrata("DIALOG")
    ask:SetClampedToScreen(true)
    ask:EnableMouse(true)
    AT.Skin(ask, COL.bg, COL.line2)
    tinsert(UISpecialFrames, ASK_NAME)
    -- Esc shuts it without an answer; the bars stop being watched for it.
    ask:SetScript("OnHide", function()
        askG = nil
        Listen()
    end)
    ask.q = ask:CreateFontString(nil, "OVERLAY")
    ask.q:SetFont(AT.FONT, 13, "")
    ask.q:SetPoint("TOP", 0, -ASK_PAD)
    ask.q:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    ask.nameFS = ask:CreateFontString(nil, "OVERLAY")
    ask.nameFS:SetFont(AT.FONT, 12, "")
    ask.nameFS:SetPoint("TOP", ask.q, "BOTTOM", 0, -4)
    ask.nameFS:SetWordWrap(false)
    ask.nameFS:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    ask.btns = { AT.MakeSmallButton(ask, "Load", ASK_BTN_W), AT.MakeSmallButton(ask, "Not now", ASK_BTN_W) }
    ask.btns[1]:SetScript("OnClick", AskLoad)
    ask.btns[2]:SetScript("OnClick", AskNotNow)
end

local function ShowAsk(g, n, names)
    BuildAsk()
    askG = g
    local word = BR.SpecWord(g)
    ask.q:SetText(n == 1 and AT.Tr("%s: 1 saved button came in empty."):format(word)
        or AT.Tr("%s: %d saved buttons came in empty."):format(word, n))
    ask.nameFS:SetText(NameList(names))
    LayAsk()
    ask:Show()
    Listen()
end

local function AfterCombatCheck()
    Events.Off("PLAYER_REGEN_ENABLED", KEY_CHECK)
    Check()
end

-- Asks when the active spec's save has buttons that are empty now and a load could fill; closes when none are left.
function Check()
    if not BR.IsOn() then CloseAsk() return end
    if InCombat() then
        Events.On("PLAYER_REGEN_ENABLED", KEY_CHECK, AfterCombatCheck)
        return
    end
    local g = BR.Group()
    local save = g and BR.MySave(g)
    if not save or declined[g] then CloseAsk() return end
    local n, names = BR.Empties(save)
    if not n or n == 0 then CloseAsk() return end
    ShowAsk(g, n, names)
end
BR.Check = Check

local function CheckSoon()
    checkGen = checkGen + 1
    local gen = checkGen
    C_Timer.After(BR.CHECK_AFTER, function()
        if gen == checkGen then Check() end
    end)
end

-- While the box is up, buttons the game fills late (or the player fills) change its count or close it.
local function OnSlot()
    Tell()
    if askQueued or not BR.AskShown() then return end
    askQueued = true
    C_Timer.After(NOTIFY_AFTER, function()
        askQueued = false
        if BR.AskShown() then Check() end
    end)
end

local function OnSpec()
    Tell()
    CloseAsk()
    CheckSoon()
end

local function Want(e, on, fn)
    if on and not listening[e] then
        if EventValid(e) then
            Events.On(e, KEY, fn)
            listening[e] = true
        end
    elseif not on and listening[e] then
        Events.Off(e, KEY)
        listening[e] = nil
    end
end

-- On: the spec swap. The bars only while the page watches or the box is up.
function Listen()
    local on = BR.IsOn()
    Want("ACTIVE_TALENT_GROUP_CHANGED", on, OnSpec)
    Want("ACTIONBAR_SLOT_CHANGED", on and (BR.notify ~= nil or BR.AskShown()), OnSlot)
end

-- The page's redraw.
function BR.Watch(fn)
    BR.notify = fn
    Listen()
end

function BR.IsOn() return Store.GetSetting("barRestore") == true end

-- Switching off keeps the saves; it drops a waiting load, a waiting check and the box.
function BR.SetOn(v)
    Store.SetSetting("barRestore", v and true or nil)
    if not v then
        Events.Off("PLAYER_REGEN_ENABLED", KEY)
        Events.Off("PLAYER_REGEN_ENABLED", KEY_CHECK)
        pending = nil
        checkGen = checkGen + 1
        CloseAsk()
    end
    Listen()
    Tell()
end

-- Off, this reads one setting. A login or reload starts over: Not now lasts until then.
Events.On("PLAYER_ENTERING_WORLD", KEY, function(_, isLogin, isReload)
    if not BR.IsOn() then return end
    Listen()
    if isLogin or isReload then
        wipe(declined)
        CheckSoon()
    end
end)
