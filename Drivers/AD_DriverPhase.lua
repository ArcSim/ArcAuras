-- A spell icon's overlay from its totem or a set duration on cast (Tracking >
-- "On this icon"): the time goes into the icon's own cooldown, in the look the
-- aura phase wears (Factory.SetPhase), while the totem is down or the time
-- runs; at its end the cooldown driver re-feeds the spell's own. The casts are
-- the player's own, plain in combat; a totem's time goes to the cooldown as
-- the game hands it over, never read. The aura source stays the engine's
-- (Drivers\AD_DriverAura.lua). A Dynamic aura group's totem row has no icon of
-- its own, so its slots carry a button of ours instead.

local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("DriverPhase") or C_Timer   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("DriverPhase") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames and its sweep skips those on the game's aura buttons
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local PH = {}
NS.DriverPhase = PH

PH.KEY = "adphase"
PH.entries = {}   -- [iconId] = { rec, holder, src, pseudo }
PH.timers = {}    -- [iconId] = { at, dur, token }: a running set duration, kept across a re-attach
PH.buttons = {}   -- [iconId] = a totem row slot's button, kept across a re-attach
PH.armed = false

-- the overlay table and its source when it is not the aura's, else nil
-- (spell, item and trinket icons); an aura with its totem over it
-- (overlay.totem: the aura driver runs the aura) runs the totem here, and an
-- aura icon that shows its totem first (driver.totem) does too. A totem
-- before any aura is the Cooldown Manager's order.
function PH.Source(rec)
    if rec and rec.kind == "aura" then
        if type(rec.driver) == "table" and rec.driver.totem == true then return "totem", rec.driver end
        return nil
    end
    local ok = rec and (rec.kind == "spell" or rec.kind == "item" or rec.kind == "trinket")
    local ov = ok and rec.driver and rec.driver.overlay
    if not (type(ov) == "table" and ov.on == true) then return nil end
    if ov.source == "totem" or ov.source == "cast" then return ov.source, ov end
    if ov.totem == true then return "totem", ov end
    return nil
end

local function Num(v)
    v = tonumber(v)
    if v and v > 0 then return v end
    return nil
end

-- The spell an icon stands for: a spell icon's own, an item's or a trinket's
-- use spell (the item it shows, the trinket worn now). Item reads are plain.
function PH.OwnSpell(rec)
    local d = rec and rec.driver
    if not d then return nil end
    if rec.kind == "spell" then return Num(d.spellID) end
    if rec.kind == "aura" then return Num(d.spellID) end
    local iid
    if rec.kind == "item" then
        local DC = NS.DriverCooldown
        iid = (DC and DC.LiveItem and DC.LiveItem(rec)) or Num(d.itemID)
    elseif rec.kind == "trinket" and GetInventoryItemID then
        iid = GetInventoryItemID("player", d.slotID or 13)
    end
    if not (iid and C_Item and C_Item.GetItemSpell) or (issecretvalue and issecretvalue(iid)) then return nil end
    local _, sid = C_Item.GetItemSpell(iid)
    if issecretvalue and issecretvalue(sid) then return nil end
    return Num(sid)
end

-- The spell whose cast or totem drives the phase: its own pick, else the icon's.
function PH.SpellOf(rec, ov)
    local list = type(ov.spells) == "table" and ov.spells or nil
    return Num(list and list[1]) or PH.OwnSpell(rec)
end

-- The spells that start the set duration: its own list, else the icon's.
function PH.StartSpells(rec, ov)
    if type(ov.spells) == "table" and #ov.spells > 0 then return ov.spells end
    return { PH.OwnSpell(rec) }
end

function PH.EndSpells(ov)
    return type(ov.endSpells) == "table" and ov.endSpells or {}
end

-- A cast is one of a list's spells by the one matcher: its forms, and any
-- rank by name on either client, as the lists have always matched.
function PH.InList(list, spellID)
    for _, id in ipairs(list) do
        id = Num(id)
        if id and Store.SpellMatch(id, spellID, nil, true) then return true end
    end
    return false
end

-- The icon's own cooldown takes the time; a totem row's slot has none.
local function OwnFrame(e)
    return e.holder ~= nil and e.holder.cooldown ~= nil and e.holder.icon ~= nil
end

-- The art while it runs, for a spell icon set to the aura's icon: the spell
-- picked to follow (its own spell keeps the icon's art); an item or trinket
-- keeps its own.
function PH.Art(e)
    local _, ov = PH.Source(e.rec)
    if not ov then return nil end
    if e.rec.kind == "spell" then
        local list = type(ov.spells) == "table" and ov.spells or nil
        local sid = Num(list and list[1])
        if not sid or sid == PH.OwnSpell(e.rec) then return nil end
        local id = Store.RecordSpellID(e.rec.driver, sid)
        return id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
    end
    return nil
end

-- A totem row slot's button: built and styled like the editor's stand-in,
-- the live recipe with the two engine setters as no-ops. It rides the slot,
-- so the group's fades and hides reach it.
function PH.Button(e)
    local id = e.rec.id
    local b = PH.buttons[id]
    if not b then
        b = CreateFrame("Frame", nil, e.holder)
        b.SetIcon = function() end
        b.SetDurationCooldown = function() end
        NS.DriverAura.WireButton(b)
        b:Hide()
        PH.buttons[id] = b
    end
    if b:GetParent() ~= e.holder then b:SetParent(e.holder) end
    return b
end

function PH.Style(e)
    local b = PH.buttons[e.rec.id]
    if not (b and e.holder) then return end
    local _, ov = PH.Source(e.rec)
    if not ov then return end
    -- one rung over the aura's buttons when they share the icon (a spell's ride
    -- one up, a two-unit icon lifts its top one), still under the texts
    local DA = NS.DriverAura
    local lift = 1
    if DA.ShapeFor and DA.ShapeFor(e.rec) then
        lift = ((e.rec.kind ~= "aura") and 2 or 1) + ((DA.Rise and DA.Rise(e.rec)) or 0)
    end
    DA.AnchorButton(b, e.holder, lift)
    -- a spell's art from the spell it follows; an item or trinket keeps its own
    local tex
    if e.rec.kind == "spell" then
        local id = Store.RecordSpellID(e.rec.driver, PH.SpellOf(e.rec, ov))
        tex = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    else
        tex = Factory.GetTexture(e.rec)
    end
    if tex then b._adIcon:SetTexture(tex) end
    local w, h = e.holder:GetSize()
    if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) or w <= 0 then w = 36 end
    if type(h) ~= "number" or (issecretvalue and issecretvalue(h)) or h <= 0 then h = w end
    -- the cooldown always sits under it: the plate keeps a dimmed look from showing it
    Factory.StyleAuraButton(b, e.rec, h, { w = w, h = h, ghost = true })
end

-- An aura on the same icon steps aside while its totem shows (Drivers\AD_DriverAura.lua).
local function SyncAura(e)
    local DA = NS.DriverAura
    if DA and DA.SyncAlpha and e.rec then DA.SyncAlpha(e.rec.id) end
end

-- The icon's own cooldown handed back: the state's look, then the cooldown
-- driver's re-feed of the real one (none for an icon being released).
function PH.Release(f, rec, released)
    f.cooldown:Clear()
    Factory.SetPhase(f, rec, false)
    local DC = NS.DriverCooldown
    if rec and not released and DC and DC.Refeed then DC.Refeed(rec.id) end
end

function PH.Hide(e, released)
    local b = e.rec and PH.buttons[e.rec.id]
    if b then
        b._adSwipe:Clear()
        b:Hide()
    end
    local f = e.holder
    if f and f._adPhaseUp and f.cooldown then
        PH.Release(f, e.rec, released)
        SyncAura(e)
    end
end

-- The time on show: a totem's duration object, else a set duration from `at`
-- for `len`, on the icon's own cooldown in the Active look, or on the slot's button.
local function ShowTime(e, dur, at, len)
    if OwnFrame(e) then
        local f = e.holder
        -- first, so the cooldown driver stands off the frame
        Factory.SetPhase(f, e.rec, true, PH.Art(e))
        local cd = f.cooldown
        if cd.Resume then cd:Resume() end
        if dur then cd:SetCooldownFromDurationObject(dur, true) else cd:SetCooldown(at, len) end
        SyncAura(e)
        return
    end
    local b = PH.Button(e)
    PH.Style(e)
    if dur then b._adSwipe:SetCooldownFromDurationObject(dur, true) else b._adSwipe:SetCooldown(at, len) end
    b:Show()
end

-- The cooldown showing an icon's totem or set duration now (its own, or its
-- slot's button's), else nil.
function PH.Showing(id)
    local e = PH.entries[id]
    if e and OwnFrame(e) and e.holder._adPhaseUp then return e.holder.cooldown end
    local b = PH.buttons[id]
    if b and b:IsShown() then return b._adSwipe end
    return nil
end

-- Set duration

function PH.Stop(id)
    local t = PH.timers[id]
    if t then
        PH.timers[id] = nil
        t.token = nil
    end
    local e = PH.entries[id]
    if e then PH.Hide(e) end
end

-- Shows what is left of a running duration, and ends it on time.
function PH.ShowTimer(id)
    local e, t = PH.entries[id], PH.timers[id]
    if not (e and t) then return end
    local left = t.at + t.dur - GetTime()
    if left <= 0 then
        PH.Stop(id)
        return
    end
    ShowTime(e, nil, t.at, t.dur)
    local token = {}
    t.token = token
    C_Timer.After(left, function()
        if PH.timers[id] and PH.timers[id].token == token then PH.Stop(id) end
    end)
end

-- A cast while it runs: restart it (the default), extend it by the seconds,
-- leave it ("idle": only a cast with none running starts one), as a Custom
-- item's Start mode, or end it ("end": the cast works as a toggle).
function PH.Start(id)
    local e = PH.entries[id]
    if not e then return end
    local _, ov = PH.Source(e.rec)
    local dur = ov and Num(ov.seconds)
    if not dur then return end
    local t = PH.timers[id]
    local running = t ~= nil and t.at + t.dur > GetTime()
    if running and ov.recast == "idle" then return end
    if running and ov.recast == "end" then
        PH.Stop(id)
        return
    end
    if running and ov.recast == "extend" then
        t.dur = t.dur + dur
    else
        PH.timers[id] = { at = GetTime(), dur = dur }
    end
    PH.ShowTimer(id)
end

-- Your death ends the durations set to end with it.
function PH.OnDeath()
    for id, e in pairs(PH.entries) do
        local _, ov = PH.Source(e.rec)
        if e.src == "cast" and ov and ov.endOnDeath == true and PH.timers[id] then PH.Stop(id) end
    end
end

-- A cast ends the durations it is set to end, then starts the ones it starts,
-- so a spell in both lists restarts its own.
function PH.OnCast(spellID)
    if issecretvalue and issecretvalue(spellID) then return end
    for id, e in pairs(PH.entries) do
        if e.src == "cast" then
            local _, ov = PH.Source(e.rec)
            if ov then
                if PH.timers[id] and PH.InList(PH.EndSpells(ov), spellID) then PH.Stop(id) end
                if PH.InList(PH.StartSpells(e.rec, ov), spellID) then PH.Start(id) end
            end
        end
    end
end

-- Totem

-- The totem driver pairs a cast with the slot it lights; a stand-in record
-- names the spell to follow.
function PH.TrackTotem(e)
    local _, ov = PH.Source(e.rec)
    local sid = ov and PH.SpellOf(e.rec, ov)
    local DT = NS.DriverTotem
    if not (sid and DT) then return end
    local key = "adphase" .. tostring(e.rec.id)
    -- its own spell brings the icon's listed ones, as a slot may carry a linked spell
    local list = not (type(ov.spells) == "table" and #ov.spells > 0) and type(ov.spellIDs) == "table" and ov.spellIDs or nil
    if e.pseudo and e.pseudo.driver.spellID == sid then -- raw-id: the same pick, not a match
        e.pseudo.driver.spellIDs = list
        return
    end
    -- re-pointed under the same key: no detach, so the slots are not re-read
    e.pseudo = { id = key, driver = { spellID = sid, spellIDs = list } }
    DT.Attach(e.pseudo)
end

function PH.UntrackTotem(e)
    if e.pseudo and NS.DriverTotem then NS.DriverTotem.Detach(e.pseudo.id) end
    e.pseudo = nil
end

-- While its totem is up the time stays: the slot it came from is its own
-- until that slot empties or lights anew, so a lookup that fails meanwhile
-- (the slot re-read and named apart) never ends it.
function PH.FeedTotem(e)
    local DT = NS.DriverTotem
    local slot = e.pseudo and DT and DT.SlotFor(e.pseudo)
    local s = DT and slot and DT.slot[slot]
    if slot then
        e.slot, e.litAt = slot, s and s.litAt
    elseif DT and e.slot then
        s = DT.slot[e.slot]
        if s and s.litAt and e.litAt and math.abs(s.litAt - e.litAt) < DT.SAME_LIT then slot = e.slot end
    end
    local dur = slot and GetTotemDuration and GetTotemDuration(slot)
    if not dur then
        e.slot, e.litAt = nil, nil
        PH.Hide(e)
        return
    end
    ShowTime(e, dur)
end

-- Every totem icon on a slot change (Drivers\AD_DriverTotem.lua DT.Changed).
function PH.OnTotems()
    for _, e in pairs(PH.entries) do
        if e.src == "totem" then PH.FeedTotem(e) end
    end
    -- a Dynamic aura group's totem row lines up what is down (Drivers\AD_DriverAuraRows.lua)
    local AR = NS.DriverAuraRows
    if AR and AR.PackAllTotems then AR.PackAllTotems() end
end

-- Attach

function PH.Valid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e))
end

-- The cast and death events stay registered only while a set duration waits for them.
function PH.Arm()
    local want = false
    for _, e in pairs(PH.entries) do
        if e.src == "cast" then want = true break end
    end
    if want == PH.armed then return end
    PH.armed = want
    if want then
        if PH.Valid("UNIT_SPELLCAST_SUCCEEDED") then
            Events.On("UNIT_SPELLCAST_SUCCEEDED", PH.KEY, function(_, unit, _, spellID)
                if unit == "player" then PH.OnCast(spellID) end
            end, { "player" })
        end
        if PH.Valid("PLAYER_DEAD") then Events.On("PLAYER_DEAD", PH.KEY, PH.OnDeath) end
    else
        Events.Off("UNIT_SPELLCAST_SUCCEEDED", PH.KEY)
        Events.Off("PLAYER_DEAD", PH.KEY)
    end
end

-- Called from the cooldown driver's attach for every spell icon.
function PH.Attach(rec, f)
    local id = rec.id
    local src = PH.Source(rec)
    local e = PH.entries[id]
    if not src then
        -- switched off on a live icon: its own cooldown comes back at once
        if e then
            PH.Hide(e)
            PH.Detach(id)
        end
        PH.timers[id] = nil
        return
    end
    if not e then
        e = {}
        PH.entries[id] = e
    end
    -- a frame this icon left hands its cooldown back, a slot its button
    if e.holder and e.holder ~= f then PH.Hide(e) end
    e.rec, e.holder = rec, f
    if e.src ~= src then
        if e.src == "totem" then PH.UntrackTotem(e) end
        if e.src == "cast" then PH.timers[id] = nil end
        PH.Hide(e)
        e.src = src
    end
    PH.Arm()
    if src == "totem" then
        PH.TrackTotem(e)
        PH.FeedTotem(e)
    elseif PH.timers[id] then
        PH.ShowTimer(id)
    else
        PH.Hide(e)
    end
end

-- A released icon: its cooldown or button lets go; a running duration is kept for the next attach.
function PH.Detach(id)
    local e = PH.entries[id]
    if not e then return end
    PH.Hide(e, true)
    if e.src == "totem" then PH.UntrackTotem(e) end
    PH.entries[id] = nil
    PH.Arm()
end
