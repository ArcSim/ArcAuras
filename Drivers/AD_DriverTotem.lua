-- Totem tracking: which of your totems sits in which slot, and the pulse bar.
-- The totem icon feed in AD_DriverCooldown asks SlotFor which slot to show and
-- hands every fed icon to Pulse; this file owns the pairing and the bars.
-- In combat a slot's totem info is secret, so a slot is named by your own cast
-- (its spell ID stays plain) landing with the slot's update, and every time is
-- our own GetTime stamp, never a totem number.

local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("DriverTotem") or C_Timer   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("DriverTotem") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames and its sweep skips those on the game's aura buttons
local hooksecurefunc = NS.Perf and NS.Perf.Hooks("DriverTotem") or hooksecurefunc
local Store = NS.Store
local Events = NS.Events

local DT = {}
NS.DriverTotem = DT

-- retail has 8 slots (a Demonology warlock fills more than 4); Forever's shaman 4
DT.SLOTS = (not NS.IsForever and GetNumTotemSlots and math.max(4, tonumber(GetNumTotemSlots()) or 4)) or 4
-- A cast and the slot update it causes land within this many seconds, unless
-- an icon following the spell waits longer (driver.slotWait, DT.Window): a
-- guardian that flies in first (Summon Hawk) lights its slot later.
DT.PAIR_WINDOW = 0.5
-- Out of combat a slot is plain, so a cast this many seconds old still pairs
-- it: one of its own spell, or the one totem spell cast in that time (a
-- guardian's slot names the guardian, not the spell).
DT.PLAIN_MAX = 5
DT.WAIT_MAX = 5
-- A slot's plain start within this many seconds of when its update came is
-- the same totem: every new one lighting the slot moves litAt again.
DT.SAME_LIT = 1
-- Updates of one cast's slots land together: a fresh slot this close after a
-- lit one took a cast takes it back (DT.Reclaim). Frame times, so a slow
-- frame splits one burst; two casts are a global cooldown apart.
DT.SAME_BURST = 0.25
-- the longer waits a player may pick (driver.slotWait), in seconds
DT.WAITS = { 1, 1.5, 2, 3, 4, 5 }
DT.QUEUE_MAX = 8
-- An icon can follow a spell that summons nothing (a buff's cast with its
-- totem ticked). While another cast waits too, one that has lit nothing gives
-- way. A cast waiting alone always pairs. Per session.
DT.missed = {}     -- [spell name] = casts in a row that lit no slot
-- how many of one spell an icon can tell apart (driver.which: First to Fourth)
DT.WHICH_MAX = 4
-- Seconds between pulses, keyed by the rank 1 spell ID; other ranks match by
-- name, and a pulse setting on the icon wins. Forever's classic totems only:
-- the retail totems' periods are not in the spell data at hand, so retail
-- starts empty and only a typed interval draws the bar there.
DT.PULSE_EVERY = NS.IsForever == true and {
    [8143] = 3,    -- Tremor Totem
    [2484] = 3,    -- Earthbind Totem
    [16190] = 3,   -- Mana Tide Totem
    [8190] = 2,    -- Magma Totem
    [5675] = 2,    -- Mana Spring Totem
    [5394] = 2,    -- Healing Stream Totem
    [8166] = 5,    -- Poison Cleansing Totem
    [8170] = 5,    -- Disease Cleansing Totem
} or {}
-- What a shaman's totem slots hold on Forever (FIRE_TOTEM_SLOT .. AIR_TOTEM_SLOT),
-- for hints only: a slot is a slot, whatever the game puts in it.
DT.ELEMENTS = { "Fire", "Earth", "Water", "Air" }

DT.slot = {}       -- [slot] = { name = totem name or nil, id = its spell ID or nil,
                   --   castId = the cast that put it down or nil, litAt = GetTime(),
                   --   prev = what it held before a cast renamed it while lit (DT.Reclaim) }
DT.cdmSpells = {}  -- [cooldownID] = the spells of that Cooldown Manager entry, read while plain
DT.pending = {}    -- [slot] = when it lit with no cast to name it yet
DT.waiting = {}    -- [slot] = when it lit, named, with no cast paired yet
DT.queue = {}      -- { name, id, at }: totem casts still waiting for their slot, oldest first
DT.shadow = {}     -- [slot] = hidden Cooldown whose IsShown() says a totem is down
DT.recs = {}       -- [iconId] = rec, the attached totem icons
DT.tracked = {}    -- [spell name] = true, the totems icons follow by spell

function DT.SlotName(slot) return "Slot " .. tostring(slot) end

-- "1 Fire, 2 Earth, 3 Water, 4 Air" on Forever, for a tooltip; nil elsewhere.
function DT.ElementHint()
    if not NS.IsForever then return nil end
    local parts = {}
    for i, el in ipairs(DT.ELEMENTS) do parts[i] = i .. " " .. el end
    return table.concat(parts, ", ")
end

function DT.SpellName(id)
    if not id or (issecretvalue and issecretvalue(id)) then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
end

-- Totem names seen in a plain read: they let a cast in combat count as a totem.
function DT.Known()
    local u = Store.UI()
    u.totemNames = u.totemNames or {}
    return u.totemNames
end

function DT.PulseByName()
    local map = DT.pulseNames
    if map and next(map) then return map end
    map = {}
    for id, every in pairs(DT.PULSE_EVERY) do
        local nm = DT.SpellName(id)
        if nm then map[nm] = every end
    end
    DT.pulseNames = map
    return map
end

function DT.IsTotemName(name)
    if not name then return false end
    if DT.Known()[name] == true or DT.tracked[name] == true or DT.PulseByName()[name] ~= nil then return true end
    local bar = DT.BarSpellNames()
    return bar ~= nil and bar[name] == true
end

-- The totem spells the client lists for its elements (Forever's totem bar
-- flyouts), by name so every rank counts; nil where it has no such list.
function DT.BarSpellNames()
    if type(GetMultiCastTotemSpells) ~= "function" then return nil end
    local out = {}
    for slot = 1, DT.SLOTS do
        local list = { GetMultiCastTotemSpells(slot) }
        for i = 1, #list do
            local nm = DT.SpellName(list[i]) -- raw-id: the client's own totem list
            if nm then out[nm] = true end
        end
    end
    return out
end



function DT.Shadow(slot)
    local w = DT.shadow[slot]
    local D = NS.DriverCooldown
    if not w and D and D.MakeShadow then
        w = D.MakeShadow()
        DT.shadow[slot] = w
    end
    return w
end

-- The duration object is the one totem read that stays usable in combat.
function DT.Active(slot)
    local w = DT.Shadow(slot)
    if not w then return false end
    local dur = GetTotemDuration and GetTotemDuration(slot)
    if dur and w.SetCooldownFromDurationObject then
        w:SetCooldownFromDurationObject(dur, true)
    else
        w:Clear()
    end
    return w:IsShown() == true
end

-- The slot's totem name and spell ID when the game lets them be read, false
-- for a plain empty slot, nil when the answer is secret. A guardian's name is
-- not its spell's, so its spell ID is what a spell is matched by.
function DT.ReadSlot(slot)
    if not GetTotemInfo then return nil end
    local have, name, _, _, _, _, sid = GetTotemInfo(slot)
    if issecretvalue and (issecretvalue(have) or issecretvalue(name)) then return nil end
    if have ~= true or type(name) ~= "string" or name == "" then return false end
    if issecretvalue and issecretvalue(sid) then sid = nil end
    return name, (type(sid) == "number" and sid > 0) and sid or nil
end

-- A totem's time, per spell name, learned from a plain read out of combat:
-- Show from the cast times the icon with it before the slot lights.
function DT.Durations()
    local u = Store.UI()
    u.totemDurs = u.totemDurs or {}
    return u.totemDurs
end

function DT.Duration(name)
    local d = name and DT.Durations()[name]
    return (type(d) == "number" and d > 0) and d or nil
end

function DT.Learn(name, slot)
    if not (name and GetTotemInfo) then return end
    local _, _, _, len = GetTotemInfo(slot)
    if type(len) == "number" and not (issecretvalue and issecretvalue(len)) and len > 0 then
        DT.Durations()[name] = len
    end
end

-- How long a cast of this spell waits for its slot: the longest wait an icon
-- or bar following it picks, else the short default. rec: one more record
-- counted (the one being edited, loaded or not).
function DT.Window(name, rec)
    local hand
    local function Hand(r)
        local d = r and r.driver
        local w = d and tonumber(d.slotWait)
        if w and w > 0 and d.spellID and DT.SpellName(Store.RecordSpellID(d)) == name then
            hand = math.max(hand or 0, math.min(DT.WAIT_MAX, w))
        end
    end
    for _, r in pairs(DT.recs) do Hand(r) end
    Hand(rec)
    return math.max(DT.PAIR_WINDOW, hand or 0)
end

-- A spell the player set to wait for its slot, or to show from the cast, is a
-- summon by their word: it never counts as lighting nothing.
function DT.NoteMiss(name)
    if DT.Window(name) > DT.PAIR_WINDOW or DT.Predicting(name) then return end
    DT.missed[name] = (DT.missed[name] or 0) + 1
end

-- casts too old to pair any slot drop out
function DT.Prune(now)
    local q, i = DT.queue, 1
    while q[i] do
        if now - q[i].at > math.max(DT.Window(q[i].name), DT.PLAIN_MAX) then
            DT.NoteMiss(q[i].name)
            table.remove(q, i)
        else
            i = i + 1
        end
    end
end

-- The cast that put a lit slot down: the oldest one waiting within its
-- spell's wait (several quick casts each pair their own slot). A plain slot
-- out of combat also takes a cast up to PLAIN_MAX old: one of the spell it
-- names, else the oldest when every cast waiting is of one spell.
function DT.TakeCast(now, name, sid, slot)
    DT.Prune(now)
    local q = DT.queue
    -- a cast that gives way goes, or it would take the burst's next slot
    local function Take(i)
        local c = table.remove(q, i)
        if DT.missed[c.name] then
            DT.missed[c.name] = nil
        else
            for j = #q, 1, -1 do
                if DT.missed[q[j].name] and now - q[j].at <= DT.Window(q[j].name) then table.remove(q, j) end
            end
        end
        return c
    end
    -- a plain slot takes its own spell's cast first: one cast dropping several
    -- totems reports their casts in another order than their slots light
    if name ~= nil then
        for i, c in ipairs(q) do
            if ((sid ~= nil and Store.SpellMatch(c.id, sid)) or c.name == name) and now - c.at <= DT.PLAIN_MAX then
                return Take(i)
            end
        end
    end
    -- Forever: a slot is one element, readable while the slot is secret, so a
    -- cast of another element's totem never pairs it
    local function Away(c)
        local h = slot and DT.HomeSlot(c.name)
        return h ~= nil and h ~= slot
    end
    local function Waiting(evenMissed)
        for i, c in ipairs(q) do
            local age = now - c.at
            local same = name ~= nil and ((sid ~= nil and Store.SpellMatch(c.id, sid)) or c.name == name)
            if (evenMissed or not DT.missed[c.name]) and not Away(c)
                and (age <= DT.Window(c.name) or (same and age <= DT.PLAIN_MAX)) then
                return i
            end
        end
    end
    local i = Waiting(false) or Waiting(true)
    if i then return Take(i) end
    if name == nil or not q[1] or now - q[1].at > DT.PLAIN_MAX or Away(q[1]) then return nil end
    for _, c in ipairs(q) do
        if c.name ~= q[1].name then return nil end
    end
    return Take(1)
end

-- Forever: the slot an element totem drops into, by spell name, from the
-- client's own totem bar lists (only element totems are listed, so a hawk or
-- any other summon has none). nil elsewhere.
DT.homes = {}
function DT.HomeSlot(name)
    if not (NS.IsForever and name) then return nil end
    local h = DT.homes[name]
    if h then return h end
    -- only a hit is kept: the lists can be empty before the bar loads
    if type(GetMultiCastTotemSpells) ~= "function" then return nil end
    for slot = 1, DT.SLOTS do
        local list = { GetMultiCastTotemSpells(slot) }
        for i = 1, #list do
            if DT.SpellName(list[i]) == name then -- raw-id: the client's own totem list
                DT.homes[name] = slot
                return slot
            end
        end
    end
    return nil
end


-- The spell a slot belongs to: the cast that put it down, else its own name.
local function SlotMatches(d, sid, want, s)
    return s ~= nil and (DT.IdMatch(d, sid, s.id) or DT.IdMatch(d, sid, s.castId) or s.name == want)
end

-- Several of one spell out at once, in the slots they fill now, lowest first:
-- [1] = the First's slot, [2] = the Second's... When a lower one ends, the one
-- above it becomes the First.
function DT.InUse(d, sid, want)
    local out = {}
    for slot = 1, DT.SLOTS do
        if SlotMatches(d, sid, want, DT.slot[slot]) then out[#out + 1] = slot end
    end
    return out
end

-- The same counted by the order they came out (driver.whichBy "order"): a
-- newly lit one takes the lowest free place, in the order they lit, and keeps
-- it until its slot empties (s.pos), so its timer never moves to another icon.
-- [place] = slot; a place may be free with a higher one held.
function DT.Places(d, sid, want)
    local held, fresh = {}, {}
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot]
        if SlotMatches(d, sid, want, s) then
            if s.pos and not held[s.pos] then
                held[s.pos] = slot
            else
                fresh[#fresh + 1] = slot
            end
        end
    end
    table.sort(fresh, function(a, b) return (DT.slot[a].litAt or 0) < (DT.slot[b].litAt or 0) end)
    for _, slot in ipairs(fresh) do
        local p = 1
        while held[p] do p = p + 1 end
        held[p] = slot
        DT.slot[slot].pos = p
    end
    return held
end

function DT.ByOrder(d) return d ~= nil and d.whichBy == "order" end

function DT.Changed()
    local D = NS.DriverCooldown
    if D and D.FeedTotems then Events.Coalesce("adcd_feedtotems", D.FeedTotems) end
    -- a spell icon showing its totem (Drivers\AD_DriverPhase.lua)
    local P = NS.DriverPhase
    if P and P.OnTotems then Events.Coalesce("adphase_totems", P.OnTotems) end
    -- a totem bar's time (Bars\AD_TotemBar.lua)
    local TB = NS.TotemBars
    if TB and TB.OnTotems then Events.Coalesce("adtotembar_all", TB.OnTotems) end
end

-- A lit slot a cast renamed in the same burst gives that cast back to a slot
-- lighting fresh, and is what it was again: Summon Demonic Tyrant extends the
-- demons out (their slots update) and lights its own slot, in either order.
function DT.Reclaim(now)
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot]
        local p = s and s.prev
        if p and now - p.at <= DT.SAME_BURST then
            s.name, s.id, s.castId, s.litAt, s.pos, s.prev = p.name, p.id, p.castId, p.litAt, p.pos, nil
            return p.cast
        end
    end
    return nil
end

-- One cast lighting several fresh slots in one burst: the cast is the lowest
-- slot's, the one the game filled first (Call Dreadstalkers in slot 1, the
-- Charhound with them in slot 2, whose update can land first). A higher slot
-- that took the cast in the same burst gives it back and keeps only its own name.
-- Either way the other slots of the burst keep the cast as s.burstId, for an
-- icon set to Last summoned.
function DT.TakeBurst(slot, now)
    for h = slot + 1, DT.SLOTS do
        local s = DT.slot[h]
        local b = s and s.paired
        local home = b and DT.HomeSlot(b.cast.name)
        -- Forever: another element's totem keeps its own cast
        if b and now - b.at <= DT.SAME_BURST and (home == nil or home == slot) then
            s.castId, s.pos, s.paired, s.burstId = nil, nil, nil, b.cast.id
            if b.secret then s.name, s.id = nil, nil end
            DT.pending[h], DT.waiting[h] = nil, nil
            return b.cast
        end
    end
    return nil
end

-- a lower slot that took a cast in this burst: that cast
function DT.BurstSibling(slot, now)
    for l = 1, slot - 1 do
        local b = DT.slot[l] and DT.slot[l].paired
        if b and now - b.at <= DT.SAME_BURST then return b.cast end
    end
    return nil
end

-- What an icon picks when one cast puts down several (driver.multiSlot):
-- nil = First summoned, "last" = Last summoned, "cdm" = Cooldown Manager sync.
function DT.Multi(d)
    local m = d and d.multiSlot
    if m == "last" or m == "cdm" then return m end
    return "first"
end

-- The Cooldown Manager's own pairing: each of its icons keeps the slot whose
-- update matched its spell (preferredTotemUpdateSlot, plain in combat) and
-- holds that totem while its totemData is there (a secret table in combat:
-- only that it is there is read). One cast can light several slots at once
-- (Call Dreadstalkers and the Charhound with them), which no cast timing tells
-- apart, so an icon whose spell it lists follows its pick.
DT.CDM_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local function PlainNum(v)
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end
    return nil
end

-- an entry's spells (its own, override, tooltip override, linked), kept once
-- read; nil while the game hands them back secret (inside instances)
function DT.CdmSpells(cdID)
    local have = DT.cdmSpells[cdID]
    if have then return have end
    local CV = C_CooldownViewer
    local info = CV and CV.GetCooldownViewerCooldownInfo and CV.GetCooldownViewerCooldownInfo(cdID)
    if type(info) ~= "table" or (issecretvalue and issecretvalue(info)) then return nil end
    local ids = {}
    local function Add(v)
        v = PlainNum(v)
        if v and v > 0 then ids[#ids + 1] = v end
    end
    Add(info.spellID)
    Add(info.overrideSpellID)
    Add(info.overrideTooltipSpellID)
    local linked = info.linkedSpellIDs
    if type(linked) == "table" and not (issecretvalue and issecretvalue(linked)) then
        for _, v in ipairs(linked) do Add(v) end
    end
    if #ids == 0 then return nil end
    DT.cdmSpells[cdID] = ids
    return ids
end

-- Cooldown Manager sync hides the Cooldown Manager's icon it follows:
-- the item is hidden (its data keeps updating) and hooks hide it again
-- whenever the game shows it or hands it that cooldown. Our marks live here,
-- never on the game's frames.
DT.cdmHidden = setmetatable({}, { __mode = "k" }) -- [item frame] = the cooldownID hidden on it
DT.cdmHooked = setmetatable({}, { __mode = "k" })
DT.cdmWant = nil                                   -- [cooldownID] = true, nil = not worked out yet

-- whether an icon set to Cooldown Manager sync follows this entry
function DT.CdmWanted(id)
    local want = DT.cdmWant
    if not want then
        want = {}
        DT.cdmWant = want
    end
    if want[id] ~= nil then return want[id] end
    local hit = false
    local ids = DT.CdmSpells(id)
    for _, r in pairs(DT.recs) do
        local d = r.driver
        local sid = d and d.spellID and DT.Multi(d) == "cdm" and Store.RecordSpellID(d)
        if sid then
            for _, v in ipairs(ids or {}) do
                if DT.IdMatch(d, sid, v) then hit = true break end
            end
        end
        if hit then break end
    end
    -- unreadable spells (secret) are asked again next time
    if ids then want[id] = hit end
    return hit
end

local function CdmItemID(f)
    return PlainNum(f.cooldownID)
end

-- A Show while our own Hide runs is someone answering that Hide (an addon
-- that keeps the item shown): it stands, or the two would call each other
-- without end.
local cdmHiding = false
local function CdmHide(f)
    if cdmHiding then return end
    cdmHiding = true
    f:Hide()
    cdmHiding = false
end
DT.CdmHide = CdmHide

local function CdmHook(f)
    if DT.cdmHooked[f] then return end
    DT.cdmHooked[f] = true
    local function Keep(self)
        local id = DT.cdmHidden[self]
        if not id then return end
        local now = CdmItemID(self)
        if now and now ~= id then
            DT.cdmHidden[self] = nil
            return
        end
        CdmHide(self)
    end
    hooksecurefunc(f, "Show", Keep)
    -- the game shows its icons through SetShown(true), which skips Show
    hooksecurefunc(f, "SetShown", function(self, shown) if shown then Keep(self) end end)
    if f.SetCooldownID then
        -- a re-layout hands a cooldown to another item
        hooksecurefunc(f, "SetCooldownID", function(self, id)
            id = PlainNum(id)
            if id and DT.CdmWanted(id) then
                DT.cdmHidden[self] = id
                CdmHide(self)
            elseif DT.cdmHidden[self] then
                DT.cdmHidden[self] = nil
            end
        end)
    end
end

-- one Cooldown Manager item: hidden while a sync icon follows its entry
function DT.CdmSyncItem(f, id)
    if not (hooksecurefunc and f.Hide) then return end
    -- every item: a re-layout can hand it the cooldown later
    CdmHook(f)
    if DT.CdmWanted(id) then
        DT.cdmHidden[f] = id
        if f:IsShown() then CdmHide(f) end
    elseif DT.cdmHidden[f] then
        -- let go: the game shows it again on its next update
        DT.cdmHidden[f] = nil
    end
end

-- after a sync pick changes: the wanted entries are worked out again, the
-- items let go of or hidden on the next read, and released ones now
function DT.CdmRefresh()
    DT.cdmWant, DT.cdmAt = nil, nil
    for f in pairs(DT.cdmHidden) do
        local id = CdmItemID(f)
        if not (id and DT.CdmWanted(id)) then DT.cdmHidden[f] = nil end
    end
    for _, r in pairs(DT.recs) do
        if DT.Multi(r.driver) == "cdm" then DT.CdmPicks() break end
    end
end

local function CdmWalk(fr, depth, out)
    if depth > 2 then return end
    for _, c in ipairs({ fr:GetChildren() }) do
        if type(c) == "table" and not (c.IsForbidden and c:IsForbidden()) then
            local id = PlainNum(c.cooldownID)
            if id then
                DT.CdmSyncItem(c, id)
                local on = type(c.totemData) ~= "nil"
                local p = out[id]
                if not p or (on and not p.on) then out[id] = { slot = PlainNum(c.preferredTotemUpdateSlot), on = on } end
            elseif c.GetChildren then
                CdmWalk(c, depth + 1, out)
            end
        end
    end
end

-- [cooldownID] = { slot, on } per Cooldown Manager icon, read once a frame
-- (fields and widget getters only, never a mixin method)
function DT.CdmPicks()
    local t = GetTime()
    if DT.cdmAt == t and DT.cdmPicks then return DT.cdmPicks end
    local out = {}
    for _, name in ipairs(DT.CDM_VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and v.GetChildren then CdmWalk(v, 1, out) end
    end
    DT.cdmAt, DT.cdmPicks = t, out
    return out
end

-- The slot the Cooldown Manager shows this spell's totem in; false while its
-- icons for the spell hold none; nil when it has no say (no icon for the
-- spell, or a pick it does not let us read), and our own pairing decides.
function DT.CdmSlot(d, sid)
    local none = false
    for id, p in pairs(DT.CdmPicks()) do
        local ids = DT.CdmSpells(id)
        local mine = false
        for _, v in ipairs(ids or {}) do
            if DT.IdMatch(d, sid, v) then mine = true break end
        end
        if mine then
            if not p.on then
                none = true
            elseif p.slot and DT.Active(p.slot) then
                return p.slot
            else
                return nil
            end
        end
    end
    if none then return false end
    return nil
end

-- Every slot from scratch, from plain reads where the game allows them.
function DT.ReadAll()
    DT.cdmAt = nil
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot] or {}
        DT.slot[slot] = s
        if not DT.Active(slot) then
            s.name, s.id, s.castId, s.litAt, s.pos, s.prev, s.paired, s.burstId = nil, nil, nil, nil, nil, nil, nil, nil
            DT.pending[slot], DT.waiting[slot] = nil, nil
        else
            local name, sid = DT.ReadSlot(slot)
            if name then
                local _, _, start = GetTotemInfo(slot)
                local plain = not (issecretvalue and issecretvalue(start)) and type(start) == "number"
                -- the same totem (lit when the slot says) keeps the cast that put it
                -- down: named by that cast while secret, its own name can differ
                -- (a summon's: Feral Spirit's slot says Spirit Wolf)
                local same = plain and s.litAt ~= nil and math.abs(start - s.litAt) < DT.SAME_LIT
                if s.name ~= name and not same then s.castId, s.pos = nil, nil end
                s.name, s.id = name, sid
                DT.Known()[name] = true
                DT.pending[slot] = nil
                if plain then s.litAt = start end
            end
            s.litAt = s.litAt or GetTime()
        end
    end
    -- A slot paired while secret can hold another lit slot's cast (one cast
    -- dropping several, lit in another order): once both read plain, the cast
    -- of a spell another slot names goes back to that slot's own spell.
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot]
        if s and s.id and s.castId and not Store.SpellMatch(s.castId, s.id) then
            for o = 1, DT.SLOTS do
                local t = DT.slot[o]
                if o ~= slot and t and t.id and Store.SpellMatch(s.castId, t.id) then
                    s.castId = s.id
                    break
                end
            end
        end
    end
    DT.Changed()
end

function DT.OnSlotUpdate(slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > DT.SLOTS then return end
    local now = GetTime()
    DT.cdmAt = nil
    local s = DT.slot[slot] or {}
    DT.slot[slot] = s
    if not DT.Active(slot) then
        s.name, s.id, s.castId, s.litAt, s.pos, s.prev, s.paired, s.burstId = nil, nil, nil, nil, nil, nil, nil, nil
        DT.pending[slot], DT.waiting[slot] = nil, nil
        DT.Changed()
        return
    end
    local name, sid = DT.ReadSlot(slot)
    if name then
        -- the same totem lit when the slot says: refreshed (an extension), kept whole
        local _, _, start = GetTotemInfo(slot)
        if s.name == name and s.litAt and PlainNum(start) and math.abs(start - s.litAt) < DT.SAME_LIT then
            DT.Changed()
            return
        end
    elseif s.litAt then
        -- secret, already lit (named or not): refreshed in place unless a cast
        -- renames it, and a slot lighting fresh in the same burst takes that back
        local c = DT.TakeCast(now, nil, nil, slot)
        if c then
            s.prev = { name = s.name, id = s.id, castId = s.castId, litAt = s.litAt, pos = s.pos, at = now, cast = c }
            s.name, s.id, s.castId, s.litAt, s.pos = c.name, c.id, c.id, now, (c.name == s.name) and s.pos or nil
        end
        DT.Changed()
        return
    end
    s.litAt, s.paired, s.burstId = now, nil, nil
    local c = DT.TakeCast(now, name, sid, slot)
    if not name and not c then c = DT.Reclaim(now) end
    if not c then c = DT.TakeBurst(slot, now) end
    if c then
        s.paired = { cast = c, at = now, secret = not name }
    else
        local sib = DT.BurstSibling(slot, now)
        s.burstId = sib and sib.id or nil
    end
    if name then
        -- plain: its name and spell, and the cast that put it down (a
        -- guardian's slot need not carry the spell you cast), now or next;
        -- the gap and the totem's time are learned for combat
        if s.name ~= name then s.castId, s.pos = nil, nil end
        s.name, s.id = name, sid
        DT.Known()[name] = true
        DT.pending[slot] = nil
        if c then
            s.castId = c.id
            DT.waiting[slot] = nil
            DT.Learn(c.name, slot)
        else
            -- a burst's other slot waits for no cast of its own
            DT.waiting[slot] = not s.burstId and now or nil
        end
    else
        -- secret: the cast that landed within its wait names it, or the next one does
        DT.waiting[slot] = nil
        if c then
            if s.name ~= c.name then s.pos = nil end
            s.name, s.id, s.castId = c.name, c.id, c.id
            DT.pending[slot] = nil
        else
            s.name, s.id, s.castId, s.pos = nil, nil, nil, nil
            DT.pending[slot] = not s.burstId and now or nil
        end
    end
    DT.Changed()
end

-- A cast landing after its slots lit (list: DT.pending, secret, or DT.waiting,
-- plain): the lowest slot within the wait takes it, the others of its burst
-- keep it as s.burstId. Marked paired, so a lower slot lighting later in the
-- same burst still takes it over (DT.TakeBurst). Returns true when one took it.
function DT.LateCast(list, now, c, secret)
    local low, lit
    for slot, t in pairs(list) do
        if now - t > DT.PAIR_WINDOW then
            list[slot] = nil
        elseif not low or slot < low then
            low, lit = slot, t
        end
    end
    if not low then return false end
    -- Forever: the cast goes to its element's slot, or waits for it to light
    local home = DT.HomeSlot(c.name)
    if home then
        if not list[home] then return false end
        low, lit = home, list[home]
    end
    for slot, t in pairs(list) do
        if not home and slot ~= low and math.abs(t - lit) <= DT.SAME_BURST then
            list[slot] = nil
            local o = DT.slot[slot]
            if o then o.burstId = c.id end
        end
    end
    list[low] = nil
    local s = DT.slot[low]
    if s then
        if secret then s.name, s.id = c.name, c.id end
        s.castId = c.id
        s.paired, s.burstId = { cast = c, at = lit, secret = secret }, nil
    end
    return true
end

-- Only casts of known totems pair, so an unrelated spell landing in the same
-- half second can never name a slot.
function DT.OnCast(spellID)
    local name = DT.SpellName(spellID) -- raw-id: the cast the game reports
    local now = GetTime()
    DT.Prune(now)
    if not DT.IsTotemName(name) then return end
    local c = { name = name, id = spellID, at = now }
    if DT.LateCast(DT.pending, now, c, true) or DT.LateCast(DT.waiting, now, c, false) then
        DT.missed[name] = nil
        DT.Changed()
        return
    end
    local q = DT.queue
    q[#q + 1] = { name = name, id = spellID, at = now }
    while #q > DT.QUEUE_MAX do table.remove(q, 1) end
    -- an icon shown from the cast lights now, and goes dark if its wait ends
    -- with no slot (one timer per such cast)
    if DT.Predicting(name) then
        DT.Changed()
        C_Timer.After(DT.Window(name) + 0.05, DT.Changed)
    end
end

-- Whether an icon or bar following this spell shows from the cast.
function DT.Predicting(name)
    for _, r in pairs(DT.recs) do
        local d = r.driver
        if d and d.fromCast == true and d.spellID and DT.SpellName(Store.RecordSpellID(d)) == name then return true end
    end
    return false
end

-- Show from the cast (driver.fromCast): a cast of the record's spell still
-- waiting for its slot lights it, its time from the cast at the totem's
-- learned length. Returns that cast's time and the length, or nil. With a
-- Which pick, the casts on their way count after the ones already out (the
-- Second with one out: the first cast on its way); the real slot takes over
-- the moment it lights.
function DT.Predict(rec)
    local d = rec and rec.driver
    if not (d and d.fromCast == true and d.spellID) then return nil end
    local sid = Store.RecordSpellID(d)
    local want = sid and DT.SpellName(sid)
    local len = want and DT.Duration(want)
    if not len then return nil end
    local now = GetTime()
    local list = {}
    for _, c in ipairs(DT.queue) do
        if (DT.IdMatch(d, sid, c.id) or c.name == want) and now - c.at <= DT.Window(c.name) then
            list[#list + 1] = c
        end
    end
    if #list == 0 then return nil end
    local which = DT.Which(d)
    if not which then return list[1].at, len end
    if DT.ByOrder(d) then
        -- the casts on their way take the free places lowest first
        local held = DT.Places(d, sid, want)
        if held[which] then return nil end
        local i = 0
        for p = 1, which do
            if not held[p] then i = i + 1 end
        end
        local c = list[i]
        if c then return c.at, len end
        return nil
    end
    -- by the slots in use: that rank already out takes no cast (an index of 0
    -- or below finds none)
    local c = list[which - #DT.InUse(d, sid, want)]
    if c then return c.at, len end
    return nil
end

-- A duration object running from the cast, kept on holder (one per icon or bar).
function DT.CastDuration(holder, at, len)
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    holder._adCastDur = holder._adCastDur or C_DurationUtil.CreateDuration()
    holder._adCastDur:SetTimeFromStart(at, len)
    return holder._adCastDur
end

-- A slot's spell (its own, or the cast that put it down) against the icon's:
-- the icon's spell in any form, or one it lists (the Cooldown Manager's
-- linked spells, which it matches a slot by too).
function DT.IdMatch(d, sid, id)
    if not id then return false end
    if Store.SpellMatch(sid, id) then return true end
    if type(d.spellIDs) == "table" then
        for _, v in ipairs(d.spellIDs) do
            if v == id then return true end -- raw-id: the Cooldown Manager's own list, matched as it matches
        end
    end
    return false
end

-- Which one of its spell a spell-tracked icon shows (driver.which: 1 = the
-- First, 2 = the Second...), or nil for any: two hawks out at once take one
-- icon each. Counted by the slots in use (the lowest first), or with
-- driver.whichBy "order" by the order they came out (DT.Places).
function DT.Which(d)
    local w = tonumber(d and d.which)
    if w and w >= 1 and w <= DT.WHICH_MAX then return math.floor(w) end
    return nil
end

-- The slot an icon shows: a spell-tracked icon follows its totem into
-- whichever slot holds it (with a Which pick, the slot of that rank among the
-- ones in use; nil while it is not down), else its own slot.
function DT.SlotFor(rec)
    local d = (rec and rec.driver) or {}
    -- the totem the icon's spell drops now (an override drops its own)
    local sid = d.spellID and Store.RecordSpellID(d)
    local want = sid and DT.SpellName(sid)
    if not want then return d.slot or 1, false end
    local which = DT.Which(d)
    if which then
        if DT.ByOrder(d) then return DT.Places(d, sid, want)[which], true end
        return DT.InUse(d, sid, want)[which], true
    end
    local multi = DT.Multi(d)
    -- Cooldown Manager sync: its icon for the spell, when there is one
    if multi == "cdm" then
        local cdm = DT.CdmSlot(d, sid)
        if cdm then return cdm, true end
        if cdm == false then return nil, true end
    end
    for slot = 1, DT.SLOTS do
        -- its spell first, as the Cooldown Manager matches; else its name
        if SlotMatches(d, sid, want, DT.slot[slot]) then
            if multi ~= "last" then return slot, true end
            -- Last summoned: the highest slot the same cast lit
            local cast, last = DT.slot[slot].castId, slot
            for h = slot + 1, DT.SLOTS do
                local s = DT.slot[h]
                if cast and s and s.burstId == cast then last = h end
            end
            return last, true
        end
    end
    return nil, true
end

function DT.Track(rec)
    local d = rec.driver or {}
    local nm = d.spellID and DT.SpellName(Store.RecordSpellID(d))
    if nm then DT.tracked[nm] = true end
end

-- The totem bar (Forever's shaman bar): each element's slot holds the totem
-- picked in its flyout, the one the bar drops. An icon following it
-- (driver.bar, its element in driver.slot) shows that totem while the slot
-- is empty, and a click or a key can drop it (Drivers\AD_TotemButton.lua).

function DT.IsBar(rec)
    return rec ~= nil and rec.kind == "totem" and type(rec.driver) == "table" and rec.driver.bar == true
end

-- Only Forever's client has one.
function DT.HasBar()
    return C_ActionBar ~= nil and C_ActionBar.GetMultiCastBarIndex ~= nil and MultiCastActionBarFrame ~= nil
end

-- The action slot of an element on the bar's current page: Blizzard's
-- totem bar button math (SecureActionButtonMixin:CalculateAction).
function DT.BarAction(slot)
    if not (slot and DT.HasBar()) then return nil end
    local idx = C_ActionBar.GetMultiCastBarIndex()
    if type(idx) ~= "number" or (issecretvalue and issecretvalue(idx)) or idx < 1 then return nil end
    local page = MultiCastActionBarFrame.currentPage
    if type(page) ~= "number" or page < 1 then page = 1 end
    return (idx - 1) * (NUM_ACTIONBAR_BUTTONS or 12) + (page - 1) * (NUM_MULTI_CAST_BUTTONS_PER_PAGE or 4) + slot
end

-- The totem the bar drops for an element: its spell ID, art and action slot,
-- or nil while the slot holds none.
function DT.BarPick(slot)
    local action = DT.BarAction(slot)
    if not (action and GetActionInfo) then return nil end
    local kind, id = GetActionInfo(action)
    if issecretvalue and (issecretvalue(kind) or issecretvalue(id)) then return nil end
    if kind ~= "spell" or type(id) ~= "number" then return nil end
    local tex = GetActionTexture and GetActionTexture(action)
    if issecretvalue and issecretvalue(tex) then tex = nil end
    return id, tex, action
end

-- What an icon following the bar shows while its slot is empty: the bar's
-- pick (spell ID, art). nil for any other icon, or while a totem is down.
function DT.BarShows(rec)
    if not DT.IsBar(rec) then return nil end
    local slot = rec.driver.slot or 1
    if DT.Active(slot) then return nil end
    return DT.BarPick(slot)
end

-- A new pick, a page change or a new bar: the icons re-art, the buttons re-aim.
function DT.BarChanged()
    DT.Changed()
    if NS.TotemButton then NS.TotemButton.SyncAll() end
end

-- The bar's own events, only while an icon follows it; a page change reaches
-- no event, so its function is hooked once.
function DT.ArmBar()
    if DT.barLive then return end
    DT.barLive = true
    Events.On("UPDATE_MULTI_CAST_ACTIONBAR", "adtotembar", DT.BarChanged)
    Events.On("ACTIONBAR_SLOT_CHANGED", "adtotembar", function(_, action)
        local idx = C_ActionBar and C_ActionBar.GetMultiCastBarIndex and C_ActionBar.GetMultiCastBarIndex()
        if type(action) ~= "number" or type(idx) ~= "number" then return end
        if issecretvalue and (issecretvalue(action) or issecretvalue(idx)) then return end
        local first = (idx - 1) * (NUM_ACTIONBAR_BUTTONS or 12) + 1
        if action >= first and action < first + (NUM_ACTIONBAR_BUTTONS or 12) then DT.BarChanged() end
    end)
    if not DT.pageHooked and type(ChangeMultiCastActionPage) == "function" then
        DT.pageHooked = true
        hooksecurefunc("ChangeMultiCastActionPage", function()
            if DT.barLive then DT.BarChanged() end
        end)
    end
end

function DT.DisarmBar()
    for _, r in pairs(DT.recs) do
        if DT.IsBar(r) then return end
    end
    if not DT.barLive then return end
    DT.barLive = false
    Events.Off("UPDATE_MULTI_CAST_ACTIONBAR", "adtotembar")
    Events.Off("ACTIONBAR_SLOT_CHANGED", "adtotembar")
end

function DT.Attach(rec)
    DT.recs[rec.id] = rec
    DT.CdmRefresh()
    DT.Track(rec)
    if DT.IsBar(rec) and DT.HasBar() then DT.ArmBar() else DT.DisarmBar() end
    if DT.live then return end
    DT.live = true
    Events.On("PLAYER_TOTEM_UPDATE", "adtotem", function(_, slot) DT.OnSlotUpdate(slot) end)
    Events.On("UNIT_SPELLCAST_SUCCEEDED", "adtotem", function(_, unit, _, spellID)
        if unit == "player" then DT.OnCast(spellID) end
    end, { "player" })
    Events.On("PLAYER_REGEN_ENABLED", "adtotem", DT.ReadAll)
    Events.On("PLAYER_ENTERING_WORLD", "adtotem", DT.ReadAll)
    DT.ReadAll()
end

function DT.Detach(id, f)
    DT.recs[id] = nil
    DT.CdmRefresh()
    if f then DT.StopPulse(f) end
    DT.DisarmBar()
    if next(DT.recs) or not DT.live then return end
    DT.live = false
    Events.Off("PLAYER_TOTEM_UPDATE", "adtotem")
    Events.Off("UNIT_SPELLCAST_SUCCEEDED", "adtotem")
    Events.Off("PLAYER_REGEN_ENABLED", "adtotem")
    Events.Off("PLAYER_ENTERING_WORLD", "adtotem")
    wipe(DT.tracked)
    wipe(DT.queue)
end

-- Pulse bar

-- Seconds between pulses for this icon: its own setting, else the totem's.
function DT.PulseEvery(rec, slot)
    local manual = tonumber(Store.Resolve(rec, "pulse", "pulseInterval"))
    if manual and manual > 0 then return manual end
    local d = rec.driver or {}
    local name = (d.spellID and DT.SpellName(Store.RecordSpellID(d)))
        or (slot and DT.slot[slot] and DT.slot[slot].name)
    return name and DT.PulseByName()[name]
end

function DT.StopPulse(f)
    f._adPulseToken = (f._adPulseToken or 0) + 1
    if f._adPulse then f._adPulse:Hide() end
end

function DT.PulseBar(f)
    local b = f._adPulse
    if b then return b end
    b = CreateFrame("StatusBar", nil, f)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.55)
    b:Hide()
    f._adPulse = b
    return b
end

-- One timer per bar per pulse, alive only while the bar shows: the widget
-- draws the fill, so nothing runs per frame.
function DT.RunPulse(f, litAt, every)
    local b = f._adPulse
    if not (b and b:IsShown()) then return end
    local now = GetTime()
    local k = math.max(0, math.floor((now - litAt) / every))
    local last = litAt + k * every
    local K = NS.Bars and NS.Bars.Kit
    local fed = false
    if C_DurationUtil and C_DurationUtil.CreateDuration and K and K.FeedStatusBarTimer then
        b._adDur = b._adDur or C_DurationUtil.CreateDuration()
        b._adDur:SetTimeFromStart(last, every)
        fed = K.FeedStatusBarTimer(b, b._adDur, false, false)
    end
    if not fed then b:SetValue(math.min(1, (now - last) / every)) end
    local token = (f._adPulseToken or 0) + 1
    f._adPulseToken = token
    C_Timer.After(math.max(0.05, last + every - now + 0.01), function()
        if f._adPulseToken ~= token then return end
        DT.RunPulse(f, litAt, every)
    end)
end

function DT.Pulse(f, rec, slot, active)
    if not (f and rec) then return end
    local R = function(k) return Store.Resolve(rec, "pulse", k) end
    local s = slot and DT.slot[slot]
    local every = active and R("pulseShow") == true and DT.PulseEvery(rec, slot)
    if not (every and s and s.litAt) then
        DT.StopPulse(f)
        return
    end
    local b = DT.PulseBar(f)
    local px = (NS.AT and NS.AT.Px and NS.AT.Px(f)) or 1
    local h = math.max(2, math.floor((tonumber(R("pulseHeight")) or 3) + 0.5)) * px
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(h)
    local c = R("pulseColor") or { 1, 0.82, 0.2, 1 }
    b:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if f.cooldown then b:SetFrameLevel(f.cooldown:GetFrameLevel() + 1) end
    b:Show()
    DT.RunPulse(f, s.litAt, every)
end
