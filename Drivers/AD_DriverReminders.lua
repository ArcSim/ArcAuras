-- AD_DriverReminders: the Reminder group's runtime, ArcUI v1's Cooldown Reminder: what fires each reminder, and how its pulse shows and sounds.
-- The engine hands it every Reminder group to place (Engine.RegisterGroupKind); reminders are their own records (Store.NewReminder).
-- Every trigger reads a value that stays plain in combat: a cooldown shadow's IsShown, your own cast's spell ID, a proc overlay's spell ID, a weapon enchant's time left and charges (NS.DriverEnchant), C_Spell.IsSpellUsable.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local RM = {}
NS.Reminders = RM

-- A ready edge holds this long before it fires: the GCD filter can report a
-- transient one, and a pulse cannot be taken back (the ready sound's rule).
RM.VERIFY_SPELL = 0.15
-- An item's windup can read ready for a moment before its real cooldown
-- lands, so an item waits longer and reads again (v1's rule).
RM.VERIFY_ITEM = 0.5
-- An item cooldown this short or shorter is the GCD or a windup.
RM.ITEM_GCD = 1.5
-- A weapon enchant that is gone waits this long before "when it's missing"
-- fires: a re-apply or a weapon swap can read bare for a moment.
RM.VERIFY_ENCHANT = 1
-- Stack mode shows at most this many pulses side by side (v1's cap).
RM.STACK_MAX = 5
-- Preview Multiple: this many reminders, this far apart (v1's).
RM.PREVIEW_COUNT, RM.PREVIEW_GAP = 3, 0.25
RM.GLOW_KEY = "adrem"
RM.PLACEHOLDER = 134400
-- "Stay until cast": the held step's length, a backstop for a pulse nothing
-- ever clears; a cast or the trigger's clear ends it long before.
RM.HOLD_MAX = 600
-- a glow's pace per style, the library's own defaults
RM.GLOW_SPEED = { pixel = 0.25, autocast = 0.125, button = 0.125 }

RM.watch = {}     -- [reminderId] = { main shadow, avail, ready, vtok, ttok, eff, use, slot, dur, lastEnd,
                  -- usable, castable }, or for an enchant { ench, state, exp, charges, app, fired, planned,
                  -- sig, vtok, etok, xtok }
RM.shadows = {}   -- [reminderId] = its shadow, kept across a drop
RM.pulse = {}     -- [groupId] = { gf, primary, stack, pool, queue, hold, holdTok, sound, ph, mode }
RM.placed = {}    -- [groupId] = its frame while the engine draws the group
RM.procs = {}     -- [spellID] = true while its proc overlay is up
RM.live = {}      -- ids of the loaded reminders of drawn groups
RM.armed = { cd = false, cast = false, proc = false, ench = false, usab = false }

local function R(g, section, field) return Store.Resolve(g, section, field) end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Valid(e)
    return (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(e)
end

-- Who loads and fires

function RM.GroupOf(rec)
    local g = rec and rec.type == "reminder" and Store.Get(rec.groupId)
    if g and g.type == "group" and g.groupKind == "reminder" then return g end
end

-- Loaded here: the reminder, its group and its layout.
function RM.Loaded(rec)
    local g = RM.GroupOf(rec)
    if not (g and Store.IsLoaded(rec) and Store.IsLoaded(g)) then return false end
    local lay = Store.Get(g.layoutId)
    return not (lay and not Store.IsLoaded(lay))
end

-- Loaded and not inert: an inert reminder neither shows nor sounds.
function RM.Live(rec)
    return RM.Loaded(rec) and not (NS.Conditions and NS.Conditions.IsInert(rec))
end

local function SpellName(sid)
    local nm = sid and C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(sid))
    if type(nm) ~= "string" or nm == "" then return nil end
    return nm
end

-- The spell a reminder's cooldown is read from, as the cooldown driver reads
-- an icon's: on ranked realms the rank you know by name, then its override.
function RM.EffSpell(rec)
    local sid = rec.driver and rec.driver.spellID
    if not sid then return nil end
    if NS.IsForever == true and C_Spell.GetSpellIDForSpellIdentifier then
        local nm = SpellName(sid)
        local known = nm and Plain(C_Spell.GetSpellIDForSpellIdentifier(nm))
        if type(known) == "number" and known > 0 then sid = known end
    end
    if C_Spell.GetOverrideSpell then
        local ov = Plain(C_Spell.GetOverrideSpell(sid))
        if type(ov) == "number" and ov ~= 0 and ov ~= sid then sid = ov end
    end
    return sid
end

function RM.UseSpell(itemID)
    if not (itemID and C_Item and C_Item.GetItemSpell) then return nil end
    local _, sid = C_Item.GetItemSpell(itemID)
    sid = Plain(sid)
    return type(sid) == "number" and sid or nil
end

-- A cast or proc overlay names this reminder: its spell, the one its cooldown
-- is read from, and on ranked realms any rank by name; an item its use spell.
function RM.Matches(rec, w, sid)
    -- a weapon enchant is read from the weapon, never from a cast
    if rec.kind == "enchant" then return false end
    local d = rec.driver or {}
    if rec.kind == "item" then
        local use = (w and w.use) or RM.UseSpell(d.itemID)
        return use ~= nil and use == sid
    end
    if sid == d.spellID or (w and w.eff ~= nil and sid == w.eff) then return true end
    if NS.IsForever == true and d.spellID then
        local a = SpellName(sid)
        return a ~= nil and a == SpellName(d.spellID)
    end
    return false
end

function RM.ProcActive(rec, w)
    for sid in pairs(RM.procs) do
        if RM.Matches(rec, w, sid) then return true end
    end
    return false
end

-- v1's rule: a trinket or other equippable item reminds only while worn.
function RM.Unequipped(rec)
    local iid = rec.driver and rec.driver.itemID
    if not (iid and C_Item and C_Item.IsEquippableItem and C_Item.IsEquippedItem) then return false end
    return C_Item.IsEquippableItem(iid) == true and C_Item.IsEquippedItem(iid) ~= true
end

-- Watches: one hidden shadow per reminder, shown while its cooldown runs (a
-- charge spell: while every charge is spent). Ready = the shadow going off.

function RM.Resolve(w, rec)
    if rec.kind == "item" then
        local iid = rec.driver and rec.driver.itemID
        w.use = RM.UseSpell(iid)
        w.slot = nil
        for s = 13, 14 do
            if iid and Plain(GetInventoryItemID("player", s)) == iid then w.slot = s end
        end
    else
        w.eff = RM.EffSpell(rec)
    end
end

-- The GCD never counts, a toggle that is on (isEnabled false) is ready, and a
-- wand shot's lock is the GCD too, all as the cooldown driver feeds an icon.
function RM.Feed(w, rec)
    if rec.kind == "item" then
        RM.FeedItem(w, rec)
        return
    end
    local sid = w.eff
    if not (sid and C_Spell.GetSpellCooldownDuration) then
        w.main:Clear()
        return
    end
    local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = info ~= nil and Plain(info.isOnGCD) == true
    local disabled = info ~= nil and Plain(info.isEnabled) == false
    local D = NS.DriverCooldown
    local wand = D ~= nil and D.WandLocked ~= nil and D.WandLocked() and not D.IsWandShot(sid)
    -- a cooldown already running keeps its snapshot through the wand's lock
    if wand and w.avail == false and w.main:IsShown() == true then return end
    local dur = C_Spell.GetSpellCooldownDuration(sid, true)
    if dur and not onGcd and not disabled and not wand then
        w.main:SetCooldownFromDurationObject(dur, true)
    else
        w.main:Clear()
    end
end

-- Plain item numbers skip the GCD blip and hold through a false zero (a
-- loading screen reads 0 mid-cooldown); secret ones go to the shadow as they
-- are, through a duration object.
function RM.FeedItem(w, rec)
    local iid = rec.driver and rec.driver.itemID
    local start, duration
    if w.slot then
        start, duration = GetInventoryItemCooldown("player", w.slot)
    elseif iid and C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(iid)
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then
        w.main:Clear()
        return
    end
    w.dur = w.dur or C_DurationUtil.CreateDuration()
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        w.dur:SetTimeFromStart(start, duration)
        w.main:SetCooldownFromDurationObject(w.dur, true)
        return
    end
    start, duration = tonumber(start) or 0, tonumber(duration) or 0
    if duration > RM.ITEM_GCD then
        w.dur:SetTimeFromStart(start, duration)
        w.main:SetCooldownFromDurationObject(w.dur, true)
        w.lastEnd = start + duration
        return
    end
    if duration <= 0 and w.lastEnd and GetTime() < w.lastEnd then return end
    w.main:Clear()
    w.lastEnd = nil
end

function RM.Ensure(rec)
    local w = RM.watch[rec.id]
    if w then return w end
    if rec.kind == "enchant" then
        w = { id = rec.id, ench = true, vtok = 0, ttok = 0, etok = 0, xtok = 0, app = 0,
            fired = {}, planned = {}, sig = RM.EnchantSig(rec) }
        RM.watch[rec.id] = w
        RM.ReadEnchant(w, rec)
        return w
    end
    local id = rec.id
    local sh = RM.shadows[id]
    if not sh then
        sh = NS.DriverCooldown.MakeShadow()
        sh:SetScript("OnCooldownDone", function() RM.Update(id) end)
        RM.shadows[id] = sh
    end
    w = { id = id, main = sh, vtok = 0, ttok = 0 }
    RM.watch[id] = w
    RM.Resolve(w, rec)
    RM.Feed(w, rec)
    -- the first read never fires
    w.avail = sh:IsShown() ~= true
    w.ready = w.avail
    return w
end

function RM.Drop(id)
    local w = RM.watch[id]
    if not w then return end
    RM.watch[id] = nil
    w.vtok, w.ttok = w.vtok + 1, w.ttok + 1
    if w.ench then
        w.etok, w.xtok = w.etok + 1, w.xtok + 1
        return
    end
    w.main:Clear()
end

-- Unavailable to available fires once the edge has held (an item reads
-- again first); available to unavailable cancels an edge still waiting.
function RM.Evaluate(w, rec)
    local avail = w.main:IsShown() ~= true
    local last = w.avail
    w.avail = avail
    if not avail then
        w.vtok = w.vtok + 1
        -- on cooldown: not castable, so "when usable" is armed again
        w.ready = false
        if w.castable then RM.UsableEdges(w, rec) end
        -- an external watch hears the cooldown start (never on its first read)
        if w.ext and last == true and w.cb and w.cb.started then w.cb.started() end
        return
    end
    if last ~= false then return end
    w.vtok = w.vtok + 1
    local tok, id, item = w.vtok, w.id, rec.kind == "item"
    C_Timer.After(item and RM.VERIFY_ITEM or RM.VERIFY_SPELL, function()
        local live = RM.watch[id]
        local r = live and (live.rec or Store.Get(id))
        if not (live and r) or live.vtok ~= tok then return end
        if item then RM.Feed(live, r) end
        if live.main:IsShown() == true then
            live.avail = false
            return
        end
        live.ready = true
        if live.ext then
            if live.cb and live.cb.ready then live.cb.ready() end
        else
            RM.Ready(r, live)
        end
        RM.Usable(live, r)
    end)
end

function RM.Update(id)
    local w = RM.watch[id]
    local rec = w and (w.rec or Store.Get(id))
    if not (w and rec) then return end
    RM.Feed(w, rec)
    RM.Evaluate(w, rec)
end

-- Every watch, next frame after any cooldown news; spell and gear changes
-- first re-resolve what each one reads.
function RM.UpdateAll()
    local again = RM.reresolve
    RM.reresolve = nil
    for id, w in pairs(RM.watch) do
        local rec = w.rec or Store.Get(id)
        if rec and not w.ench then
            if again then
                local was = w.eff
                RM.Resolve(w, rec)
                -- another spell read: its usable state starts afresh
                if w.eff ~= was then w.castable, w.canUse = nil, nil end
            end
            RM.Feed(w, rec)
            RM.Evaluate(w, rec)
            if w.castable == nil then RM.Usable(w, rec) end
        end
    end
end

-- Triggers

-- The cooldown is back: "when ready" fires, "N seconds after ready" waits.
function RM.Ready(rec, w)
    if not RM.Live(rec) then return end
    if rec.kind == "item" and RM.Unequipped(rec) then return end
    for _, t in ipairs(rec.triggers or {}) do
        if t.type == "when_ready" then
            RM.Fire(rec, t)
        elseif t.type == "after_ready" then
            RM.Later(rec, w, t)
        end
    end
end

-- A timed trigger; your next cast of the spell outdates it (v1's token).
function RM.Later(rec, w, t)
    local tok, id = w.ttok, rec.id
    C_Timer.After(t.seconds or 3, function()
        local live, r = RM.watch[id], Store.Get(id)
        if not (live and r) or live.ttok ~= tok then return end
        RM.Fire(r, t)
    end)
end

-- Your own cast: its spell ID is plain in combat, and every one is noted so a
-- wand shot's lock is never read as a cooldown. A secret one is skipped.
function RM.OnCast(sid)
    local D = NS.DriverCooldown
    if D and D.NoteCast then D.NoteCast(sid) end
    if sid == nil or (issecretvalue and issecretvalue(sid)) then return end
    for _, id in ipairs(RM.live) do
        local rec, w = Store.Get(id), RM.watch[id]
        if rec and w and RM.Matches(rec, w, sid) and RM.Live(rec) then
            w.ttok = w.ttok + 1
            local onUse = false
            for _, t in ipairs(rec.triggers or {}) do
                if t.type == "on_use" then
                    RM.Fire(rec, t)
                    onUse = true
                elseif t.type == "into_cooldown" then
                    RM.Later(rec, w, t)
                end
            end
            -- the reminder's job is done once you cast it, unless the cast
            -- is what it reminds of (its own switch, else the group's)
            local g = RM.GroupOf(rec)
            if not onUse and g and RM.EndsOnCast(rec) then RM.Cancel(g, id) end
        end
    end
end

-- A cast ends the reminder's pulse: Cancel pulse on cast, or Stay until cast,
-- which would otherwise hold until its backstop.
function RM.EndsOnCast(rec)
    return R(rec, "pulse", "cancelOnCast") == true or R(rec, "pulse", "holdUntilCast") == true
end

-- The first overlay SHOW fires "on proc" once per proc; HIDE forgets it and
-- ends the pulses set to clear with it, once no proc of the spell is up.
function RM.OnProc(sid, on)
    if sid == nil or (issecretvalue and issecretvalue(sid)) then return end
    if not on then
        RM.procs[sid] = nil
        for _, id in ipairs(RM.live) do
            local rec, w = Store.Get(id), RM.watch[id]
            if rec and w and RM.Matches(rec, w, sid) and not RM.ProcActive(rec, w) then
                for _, t in ipairs(rec.triggers or {}) do
                    if t.type == "on_proc" and t.clearOnEnd then RM.ClearTrigger(rec, t) end
                end
            end
        end
        return
    end
    local was = RM.procs[sid]
    RM.procs[sid] = true
    if was then return end
    for _, id in ipairs(RM.live) do
        local rec, w = Store.Get(id), RM.watch[id]
        if rec and w and RM.Matches(rec, w, sid) then
            for _, t in ipairs(rec.triggers or {}) do
                if t.type == "on_proc" then RM.Fire(rec, t) end
            end
        end
    end
end

-- "When usable": usable = C_Spell.IsSpellUsable (plain in combat); castable =
-- usable with the cooldown back (the verified ready state, the GCD never
-- counting). A trigger fires on its rising edge: castable, or usable alone
-- with "Fire even while on cooldown". The falling edge arms it again. The
-- first read only sets the state, and a secret read keeps the last one.
function RM.Usable(w, rec)
    if not w.usable then return end
    local sid = w.eff
    if not (sid and C_Spell.IsSpellUsable) then return end
    local ok, noPower = C_Spell.IsSpellUsable(sid)
    if issecretvalue and (issecretvalue(ok) or issecretvalue(noPower)) then return end
    RM.UsableEdges(w, rec, ok == true)
end

-- A new usable read, or nil when only the cooldown moved. A falling edge
-- also ends the pulses of a trigger set to clear when its moment ends.
function RM.UsableEdges(w, rec, use)
    if use == nil then use = w.canUse end
    if use == nil then return end
    local now = use and w.ready == true
    local lastUse, lastNow = w.canUse, w.castable
    w.canUse, w.castable = use, now
    -- an external watch hears the castable edges (usable and off cooldown)
    -- and, apart, the plain usable ones (a reactive spell mid-cooldown)
    if w.ext then
        local cb = w.cb
        if cb then
            if cb.usable and lastNow ~= nil and lastNow ~= now then cb.usable(now) end
            if cb.usableRaw and lastUse ~= nil and lastUse ~= use then cb.usableRaw(use) end
        end
        return
    end
    for _, t in ipairs(rec.triggers or {}) do
        if t.type == "when_usable" then
            local was, cur = lastNow, now
            if t.ignoreCooldown then was, cur = lastUse, use end
            if was == false and cur then
                RM.Fire(rec, t)
            elseif was and not cur and t.clearOnEnd then
                RM.ClearTrigger(rec, t)
            end
        end
    end
end

-- A spell watch reads its usable state only while its reminder has the
-- trigger; one that gains it starts from a fresh first read.
function RM.WantUsable(w, rec, on)
    if (w.usable == true) == on then return end
    w.usable = on or nil
    w.castable, w.canUse = nil, nil
    RM.Usable(w, rec)
end

function RM.UsableAll()
    for id, w in pairs(RM.watch) do
        local rec = w.usable and (w.rec or Store.Get(id))
        if rec then RM.Usable(w, rec) end
    end
end

-- External watches: another module (the custom rule engine) watches a spell
-- through the same shadow and edges, keyed by its own string, and hears the
-- edges through callbacks (started, ready, usable(castable), usableRaw(usable))
-- instead of triggers. w.rec is a stand-in record, so every read above
-- serves both.
function RM.WatchSpell(key, spellID, cb)
    local w = RM.watch[key]
    if w and w.ext then
        w.cb = cb or w.cb
        if w.rec.driver.spellID ~= spellID then
            w.rec.driver.spellID = spellID
            RM.Resolve(w, w.rec)
            RM.Feed(w, w.rec)
            w.avail = w.main:IsShown() ~= true
            w.ready = w.avail
            w.castable, w.canUse = nil, nil
        end
        RM.WantUsable(w, w.rec, cb ~= nil and (cb.usable ~= nil or cb.usableRaw ~= nil))
        return w
    end
    local sh = RM.shadows[key]
    if not sh then
        sh = NS.DriverCooldown.MakeShadow()
        sh:SetScript("OnCooldownDone", function() RM.Update(key) end)
        RM.shadows[key] = sh
    end
    w = { id = key, main = sh, vtok = 0, ttok = 0, ext = true, cb = cb,
        rec = { kind = "spell", driver = { spellID = spellID } } }
    RM.watch[key] = w
    RM.Resolve(w, w.rec)
    RM.Feed(w, w.rec)
    w.avail = sh:IsShown() ~= true
    w.ready = w.avail
    if cb and (cb.usable or cb.usableRaw) then RM.WantUsable(w, w.rec, true) end
    RM.QueueSync()
    return w
end

function RM.Unwatch(key)
    local w = RM.watch[key]
    if not (w and w.ext) then return end
    RM.Drop(key)
    RM.QueueSync()
end

-- An external watch's spell is off its real cooldown (the GCD never counts).
function RM.WatchReady(key)
    local w = RM.watch[key]
    return w ~= nil and w.avail == true
end

-- One trigger fires. preview: a panel test, which skips the conditions and
-- "Only fire when proc is active".
function RM.Fire(rec, t, preview)
    local g = RM.GroupOf(rec)
    if not g then return end
    if not preview then
        if not RM.Live(rec) then return end
        -- a weapon enchant has no proc glow: a stray flag never mutes it
        if t.requireProc and rec.kind ~= "enchant" and not RM.ProcActive(rec, RM.watch[rec.id]) then return end
    end
    -- a preview reads the trigger through a marked view, never writes it
    if preview then t = setmetatable({ preview = true }, { __index = t }) end
    RM.DoPulse(g, rec, t)
end

-- Weapon enchants: read through the enchant driver on its own events, plus
-- one re-read timed from the plain time left; nothing polls.

function RM.EnchantFire(rec, ty)
    for _, t in ipairs(rec.triggers or {}) do
        if t.type == ty then RM.Fire(rec, t) end
    end
end

-- What the plans depend on, so an edit plans again and nothing else does.
function RM.EnchantSig(rec)
    local parts = {}
    for _, t in ipairs(rec.triggers or {}) do
        parts[#parts + 1] = tostring(t.type) .. ":" .. tostring(t.seconds) .. ":" .. tostring(t.count)
    end
    return table.concat(parts, ",")
end

-- The hand now: on (an enchant), off (a weapon, no enchant) or none (no
-- weapon there, so nothing to remind of). A secret answer keeps the last state.
function RM.ReadEnchant(w, rec)
    local DE = NS.DriverEnchant
    if not DE then return end
    local state, e = "none", nil
    if DE.WeaponIn(rec.driver and rec.driver.hand) then
        e = DE.Read(rec)
        if e == nil then return end
        state = e and "on" or "off"
    end
    local last = w.state
    w.state = state
    if state == "on" then
        RM.EnchantOn(w, rec, e, last)
        return
    end
    if state == last then return end
    -- whatever waited on the last enchant is void
    w.vtok, w.etok, w.xtok = w.vtok + 1, w.etok + 1, w.xtok + 1
    w.exp, w.charges = nil, nil
    if state == "off" then RM.EnchantMissing(w, rec) end
end

-- Gone, or none on when the watch starts: if the hand still reads bare a
-- moment later, "when it's missing" fires.
function RM.EnchantMissing(w, rec)
    local tok, id = w.vtok, w.id
    C_Timer.After(RM.VERIFY_ENCHANT, function()
        local live, r = RM.watch[id], Store.Get(id)
        if not (live and r) or live.vtok ~= tok then return end
        RM.ReadEnchant(live, r)
        if live.vtok ~= tok or live.state ~= "off" then return end
        RM.EnchantFire(r, "enchant_missing")
    end)
end

-- On. A new application (it was not on, its end moved, or its charges went
-- up) arms its warnings again and one re-read for when it should run out, in
-- case no event says so (the enchant driver's rule).
function RM.EnchantOn(w, rec, e, last)
    local exp = (e.left > 0) and (GetTime() + e.left) or nil
    local fresh = last ~= "on" or (exp == nil) ~= (w.exp == nil)
        or (exp ~= nil and math.abs(exp - w.exp) > 1) or e.charges > (w.charges or 0)
    w.exp, w.charges = exp, e.charges
    if fresh then
        w.app = w.app + 1
        w.vtok, w.etok, w.xtok = w.vtok + 1, w.etok + 1, w.xtok + 1
        wipe(w.fired)
        wipe(w.planned)
        -- back on: with Cancel pulse on cast (or Stay until cast), its missing
        -- pulse has done its job
        local g = RM.GroupOf(rec)
        if last == "off" and g and RM.EndsOnCast(rec) then RM.Cancel(g, rec.id) end
        if exp then
            local tok, id = w.xtok, w.id
            C_Timer.After(e.left + 0.2, function()
                local live, r = RM.watch[id], Store.Get(id)
                if live and r and live.xtok == tok then RM.ReadEnchant(live, r) end
            end)
        end
    end
    RM.EnchantPlan(w, rec)
end

-- This application's warnings: "N seconds before it runs out" at its time (at
-- once when that has passed), "when N charges are left" as soon as they are.
-- Each fires once per application.
function RM.EnchantPlan(w, rec)
    for _, t in ipairs(rec.triggers or {}) do
        if not w.fired[t] then
            if t.type == "enchant_charges" then
                if w.charges and w.charges > 0 and w.charges <= (t.count or 5) then
                    w.fired[t] = true
                    RM.Fire(rec, t)
                end
            elseif t.type == "enchant_expiring" and w.exp and not w.planned[t] then
                w.planned[t] = true
                local due = w.exp - (t.seconds or 60) - GetTime()
                if due <= 0 then
                    w.fired[t] = true
                    RM.Fire(rec, t)
                else
                    local tok, app, id = w.etok, w.app, w.id
                    C_Timer.After(due, function()
                        local live, r = RM.watch[id], Store.Get(id)
                        if not (live and r) or live.etok ~= tok or live.app ~= app or live.fired[t] then return end
                        live.fired[t] = true
                        RM.Fire(r, t)
                    end)
                end
            end
        end
    end
end

-- An edited warning plans again; what already fired this application stays fired.
function RM.EnchantReplan(w, rec)
    local sig = RM.EnchantSig(rec)
    if sig == w.sig then return end
    w.sig = sig
    if w.state ~= "on" then return end
    w.etok = w.etok + 1
    wipe(w.planned)
    RM.EnchantPlan(w, rec)
end

function RM.EnchantAll()
    for id, w in pairs(RM.watch) do
        local rec = Store.Get(id)
        if rec and w.ench then RM.ReadEnchant(w, rec) end
    end
end

-- The pulse window (v1's replace, queue and stack), one per group

function RM.State(g)
    local P = RM.pulse[g.id]
    if not P then
        P = { stack = {}, pool = {}, queue = {}, holdTok = 0, pending = 0, ftok = 0 }
        RM.pulse[g.id] = P
    end
    return P
end

-- v1's pulse frame: a black edge under the art and one animation group per
-- style; playing one shows the frame and its end hands it to f._onDone.
function RM.NewFrame(P)
    local f = CreateFrame("Frame", nil, P.gf or UIParent)
    f:SetSize(64, 64)
    f:Hide()
    f:EnableMouse(false)
    f._border = f:CreateTexture(nil, "BACKGROUND")
    f._border:SetColorTexture(0, 0, 0, 1)
    f._tex = f:CreateTexture(nil, "ARTWORK")
    f._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._anims = {}
    local function Wire(ag)
        ag:SetScript("OnPlay", function() f:Show() end)
        ag:SetScript("OnFinished", function() if f._onDone then f._onDone(f) end end)
        return ag
    end
    local function Alpha(ag, from, to, order)
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(from)
        a:SetToAlpha(to)
        if order then a:SetOrder(order) end
        return a
    end
    -- fade: full to nothing over the whole time
    local ag = Wire(f:CreateAnimationGroup())
    f._anims.fade = { group = ag, fade = Alpha(ag, 1, 0) }
    -- no fade: full for the whole time, then gone
    ag = Wire(f:CreateAnimationGroup())
    f._anims.no_fade = { group = ag, fade = Alpha(ag, 1, 1) }
    -- flash: four bounces, then the fade
    ag = Wire(f:CreateAnimationGroup())
    local steps = {}
    for i, s in ipairs({ { 1, 0.3 }, { 0.3, 1 }, { 1, 0.3 }, { 0.3, 1 } }) do
        steps[i] = Alpha(ag, s[1], s[2], i)
    end
    local last = Alpha(ag, 1, 0, 5)
    last:SetSmoothing("OUT")
    f._anims.flash = { group = ag, fade = last, steps = steps }
    -- zoom: pop in past full size, settle, then the fade
    ag = Wire(f:CreateAnimationGroup())
    local s1 = ag:CreateAnimation("Scale")
    s1:SetOrder(1)
    s1:SetSmoothing("OUT")
    local s2 = ag:CreateAnimation("Scale")
    s2:SetOrder(2)
    s2:SetSmoothing("IN")
    local zf = Alpha(ag, 1, 0, 3)
    zf:SetSmoothing("OUT")
    f._anims.zoom = { group = ag, fade = zf, s1 = s1, s2 = s2 }
    f._ag = f._anims.fade.group
    return f
end

-- The pulse's timing: the trigger's own while it overrides, else its look
-- record's (a reminder: its own values, the group's for the rest).
function RM.Tune(lr, t)
    local o = t and t.overrideAnim == true and t or nil
    local function P(k) return (o and o[k]) or R(lr, "pulse", k) end
    return { pulseDuration = P("pulseDuration"), animFadeSmoothing = P("animFadeSmoothing"),
        animFlashSpeed = P("animFlashSpeed"), animZoomStart = P("animZoomStart"),
        animZoomPeak = P("animZoomPeak"), animZoomPopTime = P("animZoomPopTime"),
        animZoomSettleTime = P("animZoomSettleTime") }
end

-- v1's timing: the whole style fits the pulse duration, its entrance capped so
-- the fade keeps a share (zoom 80 %, flash 70 %). hold: "Stay until cast", the
-- closing step stays at full for RM.HOLD_MAX; RM.Cancel ends it.
function RM.SetAnim(f, style, tune, hold)
    local e = f._anims[style] or f._anims.fade
    -- the closing step is shared by every pulse on this frame: set both ends
    e.fade:SetFromAlpha(1)
    e.fade:SetToAlpha((hold or e == f._anims.no_fade) and 1 or 0)
    if f._ag ~= e.group and f._ag:IsPlaying() then f._ag:Stop() end
    f._ag = e.group
    local D = math.max(0.05, tonumber(tune.pulseDuration) or 2)
    if e.s1 then
        local pop = math.max(0.02, tonumber(tune.animZoomPopTime) or 0.12)
        local settle = math.max(0.02, tonumber(tune.animZoomSettleTime) or 0.08)
        local cap = D * 0.80
        if pop + settle > cap then
            local k = cap / (pop + settle)
            pop, settle = pop * k, settle * k
        end
        local from, peak = tonumber(tune.animZoomStart) or 0.70, tonumber(tune.animZoomPeak) or 1.15
        e.s1:SetScaleFrom(from, from)
        e.s1:SetScaleTo(peak, peak)
        e.s1:SetDuration(pop)
        e.s2:SetScaleFrom(peak, peak)
        e.s2:SetScaleTo(1, 1)
        e.s2:SetDuration(settle)
        e.fade:SetDuration(math.max(0.05, D - pop - settle))
    elseif e.steps then
        local step = math.max(0.03, tonumber(tune.animFlashSpeed) or 0.10)
        if step * #e.steps > D * 0.70 then step = D * 0.70 / #e.steps end
        for _, a in ipairs(e.steps) do a:SetDuration(step) end
        e.fade:SetDuration(math.max(0.05, D - step * #e.steps))
    else
        e.fade:SetDuration(D)
        if e == f._anims.fade then e.fade:SetSmoothing(tune.animFadeSmoothing or "OUT") end
    end
    if hold then e.fade:SetDuration(RM.HOLD_MAX) end
end

-- Size, the black edge (4 % of the size) and the art's opacity, from a look
-- record: a reminder, or its group for the group's own previews. The size is
-- kept on the frame, so the stack lines up frames of different sizes.
function RM.Look(f, lr)
    local size = R(lr, "pulse", "size") or 80
    f:SetSize(size, size)
    f._size = size
    local inset = math.max(1, math.floor(size * 0.04 + 0.5))
    f._border:ClearAllPoints()
    f._border:SetAllPoints(f)
    f._tex:ClearAllPoints()
    f._tex:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    f._tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    f._tex:SetAlpha(R(lr, "pulse", "iconOpacity") or 1)
end

function RM.StartGlow(f, t)
    local F = NS.Factory
    if not (F and F.StartGlowLane) then return end
    local c = t.glowColor or NS.Schema.REMINDER_GLOW_COLOR
    F.StartGlowLane(f, RM.GLOW_KEY, t.glowType, { color = { c[1], c[2], c[3], c[4] or 1 },
        speed = RM.GLOW_SPEED[t.glowType], lines = 8, thickness = 2, particles = 4, scale = 1,
        xo = 0, yo = 0, level = 3 })
    f._glowOn = true
end

function RM.StopGlow(f)
    if not f._glowOn then return end
    f._glowOn = nil
    local F = NS.Factory
    if F and F.StopGlowLane then F.StopGlowLane(f, RM.GLOW_KEY) end
end

-- One pulse on one frame; its sound starts with it (v1's lock-step), so a
-- pulse that waits or is dropped never sounds. It wears its reminder's look
-- (the group's for a group preview, t.groupLook) and is tagged with its
-- trigger, so a trigger's moment ending can take back what it started.
function RM.PlayOn(f, g, rec, t)
    local lr = t.groupLook and g or rec
    RM.Look(f, lr)
    f._lookId = lr.id
    f._tex:SetTexture(NS.Factory.GetTexture(rec))
    f._recId = rec.id
    f._trig = t
    f._playedAt = GetTime()
    f._priority = t.priority or 0
    -- Stay until cast: never for an "On use" pulse (its cast is the reminder,
    -- so no cast would end it) or a panel preview
    local hold = R(lr, "pulse", "holdUntilCast") == true and t.type ~= "on_use" and not t.preview
    f._hold = hold or nil
    RM.SetAnim(f, t.animStyle or R(lr, "pulse", "animStyle") or "fade", RM.Tune(lr, t), hold)
    RM.StopGlow(f)
    if t.glowType then RM.StartGlow(f, t) end
    RM.PlaySound(g, t)
    f._fin = nil
    f._ag:Stop()
    f._ag:Play()
    RM.PaintMarker(g.id)
end

-- On screen: playing, and not the one finishing now. Inside its own
-- OnFinished the client still reports the group as playing.
local function Up(f)
    return f ~= nil and f._fin ~= true and f._ag:IsPlaying() == true
end

-- A pulse up, one waiting in the queue or the replace hold, or the queue's
-- next one on its way.
function RM.Busy(P)
    if (P.pending or 0) > 0 or P.hold or #P.queue > 0 then return true end
    if Up(P.primary) then return true end
    for _, f in ipairs(P.stack) do
        if Up(f) then return true end
    end
    return false
end

-- With this window open a dim copy of the art marks the spot; it steps aside
-- while the group pulses, so a test shows the pulse alone. "Hide preview icon
-- while editing" leaves the outline alone.
function RM.PaintMarker(gid)
    local P = RM.pulse[gid]
    if not (P and P.ph) then return end
    local g = Store.Get(gid)
    P.ph:SetShown(P.edit == true and RM.placed[gid] ~= nil and not RM.Busy(P)
        and not (g and R(g, "pulse", "hideMarker") == true))
end

-- Stack mode: slot 1 at the pulse area's start edge, each next one beside it.
-- Each keeps its own reminder's size; they line up on the area's middle.
function RM.Relayout(P, g)
    local gf = P.gf
    if not gf then return end
    local size = R(g, "pulse", "size") or 80
    local sp = R(g, "pulse", "stackSpacing") or 4
    local right = R(g, "pulse", "stackDirection") ~= "left"
    for i, f in ipairs(P.stack) do
        f:ClearAllPoints()
        if i == 1 then
            local edge = right and "LEFT" or "RIGHT"
            f:SetPoint(edge, gf, edge, 0, 0)
        elseif right then
            f:SetPoint("LEFT", P.stack[i - 1], "RIGHT", sp, 0)
        else
            f:SetPoint("RIGHT", P.stack[i - 1], "LEFT", -sp, 0)
        end
        local s = f._size or size
        f:SetSize(s, s)
    end
end

local function Unstack(P, f)
    for i, x in ipairs(P.stack) do
        if x == f then
            table.remove(P.stack, i)
            return
        end
    end
end

-- The rest spot of the replace and queue modes: the pulse area's centre.
local function Centre(P, f)
    f:ClearAllPoints()
    f:SetPoint("CENTER", P.gf, "CENTER", 0, 0)
end

function RM.Primary(P, g)
    local f = P.primary
    if not f then
        f = RM.NewFrame(P)
        local gid = g.id
        f._onDone = function(self) RM.PrimaryDone(gid, self) end
        P.primary = f
    end
    return f
end

function RM.Extra(P, g)
    local f = table.remove(P.pool)
    if not f then
        f = RM.NewFrame(P)
        local gid = g.id
        f._onDone = function(self) RM.ExtraDone(gid, self) end
    end
    f:SetParent(P.gf)
    return f
end

function RM.ReleaseFrame(P, f, g)
    Unstack(P, f)
    if f._ag:IsPlaying() then f._ag:Stop() end
    RM.StopGlow(f)
    f:Hide()
    if f ~= P.primary then P.pool[#P.pool + 1] = f end
    if g then RM.Relayout(P, g) end
end

-- The primary's end: the next queued pulse after the gap, a held replace
-- pulse, or the stack closing up. Each waits a frame at least: a Play from
-- inside OnFinished can leave the next pulse unable to finish (v1's finding).
function RM.PrimaryDone(gid, f)
    f._fin = true
    RM.StopGlow(f)
    f:Hide()
    local P, g = RM.pulse[gid], Store.Get(gid)
    if not (P and g) then return end
    Unstack(P, f)
    local mode = R(g, "pulse", "queueMode")
    if mode == "queue" and #P.queue > 0 then
        local nxt = table.remove(P.queue, 1)
        -- on its way: the marker stays aside through the gap
        P.pending = (P.pending or 0) + 1
        local ftok = P.ftok
        C_Timer.After(math.max(R(g, "pulse", "queueInterDelay") or 0, 0), function()
            local P2 = RM.pulse[gid]
            if not P2 or P2.ftok ~= ftok then return end
            P2.pending = math.max(0, (P2.pending or 1) - 1)
            local g2, r2 = Store.Get(gid), Store.Get(nxt.id)
            if g2 and r2 and RM.placed[gid] then RM.Route(g2, r2, nxt.t) end
            RM.PaintMarker(gid)
        end)
    elseif mode == "replace" then
        C_Timer.After(0, function() RM.DrainHold(gid) end)
    elseif mode == "stack" then
        RM.Relayout(P, g)
    end
    RM.RepaintMarker(gid)
end

function RM.ExtraDone(gid, f)
    local P, g = RM.pulse[gid], Store.Get(gid)
    if not P then
        RM.StopGlow(f)
        f:Hide()
        return
    end
    RM.ReleaseFrame(P, f, g)
    RM.RepaintMarker(gid)
end

-- A pulse's end paints the marker now and once more next frame, past the
-- client's own finish.
function RM.RepaintMarker(gid)
    RM.PaintMarker(gid)
    C_Timer.After(0, function() RM.PaintMarker(gid) end)
end

-- Replace mode's guard: a pulse arriving while the one on screen is younger
-- than the guard waits (the newest one only) until the guard runs out or the
-- pulse ends, whichever is first.
function RM.DrainHold(gid)
    local P, g = RM.pulse[gid], Store.Get(gid)
    local hold = P and P.hold
    if not (hold and g) then return end
    P.hold = nil
    local rec = Store.Get(hold.id)
    if not (rec and RM.placed[gid]) then
        RM.PaintMarker(gid)
        return
    end
    local f = RM.Primary(P, g)
    if f._ag:IsPlaying() then
        f._ag:Stop()
        RM.StopGlow(f)
    end
    Centre(P, f)
    RM.PlayOn(f, g, rec, hold.t)
end

-- v1's router: the same reminder restarts in place; a higher priority takes
-- the pulse over and a lower one is dropped (not in stack mode, which is
-- additive); then replace (with its guard), queue (deduplicated, capped,
-- lowest priority out first) or stack (capped, lowest priority out first).
function RM.Route(g, rec, t)
    local P = RM.State(g)
    if not P.gf then return end
    local primary = RM.Primary(P, g)
    local prio = t.priority or 0
    local mode = R(g, "pulse", "queueMode") or "queue"
    local busy = primary._ag:IsPlaying()
    if busy and primary._recId == rec.id then
        RM.PlayOn(primary, g, rec, t)
        return
    end
    for _, f in ipairs(P.stack) do
        if f ~= primary and f._recId == rec.id then
            RM.PlayOn(f, g, rec, t)
            return
        end
    end
    if busy and mode ~= "stack" then
        local active = primary._priority or 0
        if prio > active then
            primary._ag:Stop()
            RM.StopGlow(primary)
            P.hold = nil
            Unstack(P, primary)
            Centre(P, primary)
            RM.PlayOn(primary, g, rec, t)
            return
        elseif prio < active then
            return
        end
    end
    if mode == "queue" then
        for _, q in ipairs(P.queue) do
            if q.id == rec.id then return end
        end
    end
    if mode == "replace" and busy then
        local guard = R(g, "pulse", "replaceGuard") or 0
        local elapsed = GetTime() - (primary._playedAt or 0)
        if guard > 0 and elapsed < guard then
            P.holdTok = P.holdTok + 1
            local tok, gid = P.holdTok, g.id
            P.hold = { id = rec.id, t = t, tok = tok }
            C_Timer.After(guard - elapsed, function()
                local P2 = RM.pulse[gid]
                if P2 and P2.hold and P2.hold.tok == tok then RM.DrainHold(gid) end
            end)
            return
        end
    end
    -- a free primary takes it; in stack mode it becomes slot 1
    if mode == "replace" or not busy then
        Unstack(P, primary)
        if mode ~= "stack" then Centre(P, primary) end
        RM.PlayOn(primary, g, rec, t)
        if mode == "stack" then
            table.insert(P.stack, 1, primary)
            RM.Relayout(P, g)
        end
        return
    end
    if mode == "queue" then
        if #P.queue >= (R(g, "pulse", "queueMaxLen") or 3) then
            local vi, vp
            for i, q in ipairs(P.queue) do
                local p = q.t.priority or 0
                if vp == nil or p < vp then vi, vp = i, p end
            end
            if vp ~= nil and prio < vp then return end
            if vi then table.remove(P.queue, vi) end
        end
        P.queue[#P.queue + 1] = { id = rec.id, t = t }
        return
    end
    -- stack, the primary busy: a new pulse beside the others
    if #P.stack >= RM.STACK_MAX then
        local victim, vp
        for _, f in ipairs(P.stack) do
            local p = f._priority or 0
            if vp == nil or p < vp then victim, vp = f, p end
        end
        if vp ~= nil and prio < vp then return end
        if victim == primary then
            primary._ag:Stop()
            RM.StopGlow(primary)
            Unstack(P, primary)
            table.insert(P.stack, 1, primary)
            RM.Relayout(P, g)
            RM.PlayOn(primary, g, rec, t)
            return
        elseif victim then
            RM.ReleaseFrame(P, victim, g)
        end
    end
    local inStack = false
    for _, f in ipairs(P.stack) do
        if f == primary then inStack = true end
    end
    if not inStack then table.insert(P.stack, 1, primary) end
    local extra = RM.Extra(P, g)
    extra:SetFrameLevel(primary:GetFrameLevel())
    P.stack[#P.stack + 1] = extra
    RM.Relayout(P, g)
    RM.PlayOn(extra, g, rec, t)
end

-- Faded to nothing by its own Visibility or its layout's (never with this
-- window open): nothing of a pulse would show.
function RM.Hidden(g)
    local C = NS.Conditions
    if not (C and C.AlphaFor) then return false end
    if C.AlphaFor(g) <= 0 then return true end
    local lay = Store.Get(g.layoutId)
    return lay ~= nil and C.AlphaFor(lay) <= 0
end

-- v1's entry point for one trigger: sound alone when the icon is off (the
-- group's switch or the trigger's) or the group is faded to nothing, else the
-- router. Visibility fades what you see; Load Conditions also silence.
function RM.DoPulse(g, rec, t)
    local show = R(g, "pulse", "iconEnabled") ~= false and t.showIcon ~= false
    if not show or not RM.placed[g.id] or RM.Hidden(g) then
        RM.PlaySound(g, t)
        return
    end
    RM.Route(g, rec, t)
end

-- Casting a reminded spell: its pulse goes, shown, held or queued. The one on
-- screen ends as if it had run out, so a pulse waiting behind it shows. With
-- `t`, only what that trigger started goes (its moment ended).
function RM.Cancel(g, recId, t)
    local P = RM.pulse[g.id]
    if not P then return end
    local function Hit(id, tt) return id == recId and (t == nil or tt == t) end
    local f = P.primary
    if P.hold and Hit(P.hold.id, P.hold.t) then P.hold = nil end
    for j = #P.queue, 1, -1 do
        if Hit(P.queue[j].id, P.queue[j].t) then table.remove(P.queue, j) end
    end
    local i = 1
    while i <= #P.stack do
        local x = P.stack[i]
        if x ~= f and Hit(x._recId, x._trig) then
            RM.ReleaseFrame(P, x, g)
        else
            i = i + 1
        end
    end
    if f and f._ag:IsPlaying() and Hit(f._recId, f._trig) then
        f._ag:Stop()
        RM.PrimaryDone(g.id, f)
    end
    RM.PaintMarker(g.id)
end

-- "Clear when it ends": a trigger's moment is over (the proc glow went, the
-- spell stopped being usable), so the pulses it started go, as on a cancel.
function RM.ClearTrigger(rec, t)
    local g = RM.GroupOf(rec)
    if g then RM.Cancel(g, rec.id, t) end
end

-- Everything off the screen and out of the queue (a mode change, the group
-- no longer drawn).
function RM.Flush(gid)
    local P = RM.pulse[gid]
    if not P then return end
    for _, f in ipairs(P.stack) do
        if f._ag:IsPlaying() then f._ag:Stop() end
        RM.StopGlow(f)
        f:Hide()
        if f ~= P.primary then P.pool[#P.pool + 1] = f end
    end
    wipe(P.stack)
    local f = P.primary
    if f then
        if f._ag:IsPlaying() then f._ag:Stop() end
        RM.StopGlow(f)
        f:Hide()
    end
    wipe(P.queue)
    P.hold = nil
    -- the queue's next one already on its way is void too
    P.pending = 0
    P.ftok = (P.ftok or 0) + 1
    RM.PaintMarker(gid)
end

-- Sound and speech

-- Forever's call is SpeakText(voiceID, text, rate, volume, overlap).
function RM.Speak(g, text)
    if type(text) ~= "string" or text == "" then return false end
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local rate
    if R(g, "audio", "ttsRateOverride") == true then
        rate = R(g, "audio", "ttsRate") or 0
    elseif C_TTSSettings and C_TTSSettings.GetSpeechRate then
        rate = C_TTSSettings.GetSpeechRate()
    end
    local vol = C_TTSSettings and C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()
    C_VoiceChat.SpeakText(RM.Voice(R(g, "audio", "ttsVoiceOverride")), text, rate or 0, vol or 100, false)
    return true
end

-- "default" is the voice picked in the game's text-to-speech options; male
-- and female pick a matching voice by name, else by position (v1's rule).
function RM.Voice(which)
    if which ~= "male" and which ~= "female" then
        if TextToSpeech_GetSelectedVoice and Enum and Enum.TtsVoiceType then
            local v = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
            if v and v.voiceID then return v.voiceID end
        end
        return 0
    end
    local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
    if type(voices) ~= "table" or #voices == 0 then return 0 end
    local male = which == "male"
    for _, v in ipairs(voices) do
        local n = type(v.name) == "string" and v.name:lower() or ""
        local fem = n:find("feminine", 1, true) or n:find("female", 1, true)
        local mas = not fem and (n:find("masculine", 1, true) or n:find("male", 1, true))
        if (male and mas) or (not male and fem) then return v.voiceID end
    end
    if male then return voices[1].voiceID or 0 end
    return (voices[2] or voices[1]).voiceID or 0
end

-- The previous sound (and any speech) stops first when the group cuts off,
-- faded out over the cutoff time.
function RM.Cutoff(P, g)
    if R(g, "audio", "cutoffPreviousSound") ~= true then return end
    if P.sound and StopSound then
        StopSound(P.sound, math.floor((R(g, "audio", "cutoffFadeTime") or 0.1) * 1000))
    end
    P.sound = nil
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then C_VoiceChat.StopSpeakingText() end
end

-- A trigger's text, spoken, wins over its sound; its sound is its own or the
-- group's default. The group's switch and the trigger's both allow it.
function RM.PlaySound(g, t)
    if R(g, "audio", "soundEnabled") == false or t.soundDisabled then return end
    local P = RM.State(g)
    RM.Cutoff(P, g)
    if t.tts and RM.Speak(g, t.tts) then return end
    local name = t.sound or R(g, "audio", "soundName")
    if type(name) ~= "string" or name == "" or not NS.Sounds then return end
    local _, handle = NS.Sounds.Play(name, R(g, "audio", "soundChannel"))
    if R(g, "audio", "cutoffPreviousSound") == true then P.sound = handle end
end

-- The engine's hooks

-- The pulse area: one icon, or the stack's whole reach in stack mode. Panel
-- open: a dim copy of the first reminder's art shows where the pulse lands.
function RM.Place(g, gf, editMode)
    local P = RM.State(g)
    P.gf = gf
    P.edit = editMode == true
    RM.placed[g.id] = gf
    local size = math.max(4, R(g, "pulse", "size") or 80)
    local mode = R(g, "pulse", "queueMode") or "queue"
    -- a new overlap mode starts from a clean slate (v1)
    if P.mode and P.mode ~= mode then RM.Flush(g.id) end
    P.mode = mode
    local w = size
    if mode == "stack" then
        w = size + (size + (R(g, "pulse", "stackSpacing") or 4)) * (RM.STACK_MAX - 1)
    end
    gf:SetSize(math.max(w, size), size)
    local lvl = gf:GetFrameLevel() + 5
    local primary = RM.Primary(P, g)
    local frames = { primary }
    for _, f in ipairs(P.stack) do
        if f ~= primary then frames[#frames + 1] = f end
    end
    for _, f in ipairs(P.pool) do frames[#frames + 1] = f end
    -- each keeps the look it plays with, so an edit shows on a pulse at once
    for _, f in ipairs(frames) do
        f:SetParent(gf)
        f:SetFrameLevel(lvl)
        RM.Look(f, (f._lookId and Store.Get(f._lookId)) or g)
    end
    if mode == "stack" then
        RM.Relayout(P, g)
    else
        Centre(P, primary)
    end
    local ph = P.ph
    if not ph then
        ph = CreateFrame("Frame", nil, gf)
        ph:EnableMouse(false)
        ph.tex = ph:CreateTexture(nil, "ARTWORK")
        ph.tex:SetAllPoints()
        ph.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        P.ph = ph
    end
    ph:SetParent(gf)
    ph:SetFrameLevel(lvl - 1)
    ph:SetSize(size, size)
    ph:ClearAllPoints()
    if mode == "stack" then
        local edge = R(g, "pulse", "stackDirection") == "left" and "RIGHT" or "LEFT"
        ph:SetPoint(edge, gf, edge, 0, 0)
    else
        ph:SetPoint("CENTER", gf, "CENTER", 0, 0)
    end
    local first = Store.RemindersOf(g)[1]
    ph.tex:SetTexture(first and NS.Factory.GetTexture(first) or RM.PLACEHOLDER)
    ph:SetAlpha(0.5)
    RM.PaintMarker(g.id)
    RM.QueueSync()
end

-- Not drawn (unloaded, hidden, its layout off): nothing pulses or watches.
function RM.Release(g)
    if not RM.placed[g.id] then return end
    RM.placed[g.id] = nil
    RM.Flush(g.id)
    local P = RM.pulse[g.id]
    if P and P.ph then P.ph:Hide() end
    RM.QueueSync()
end

-- Events, each only while a loaded reminder of a drawn group needs it

local CD_EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES",
    "BAG_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }
local RERESOLVE = { SPELLS_CHANGED = true, PLAYER_EQUIPMENT_CHANGED = true, PLAYER_ENTERING_WORLD = true }
local PROC_EVENTS = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }
local USABLE_EVENTS = { "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED" }

function RM.OnWorld(e)
    if RERESOLVE[e] then RM.reresolve = true end
    Events.Coalesce("adrem_feed", RM.UpdateAll)
end

function RM.ArmCooldown(on)
    if on == RM.armed.cd then return end
    RM.armed.cd = on
    for _, e in ipairs(CD_EVENTS) do
        if not on then
            Events.Off(e, "adrem")
        elseif Valid(e) then
            Events.On(e, "adrem", RM.OnWorld)
        end
    end
end

-- Its own frame, player casts only, so nobody else's casts reach Lua.
function RM.ArmCast(on)
    if on == RM.armed.cast then return end
    RM.armed.cast = on
    local f = RM.castFrame
    if on then
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(_, _, _, _, spellID) RM.OnCast(spellID) end)
            RM.castFrame = f
        end
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    elseif f then
        f:UnregisterAllEvents()
    end
end

function RM.ArmProc(on)
    if on == RM.armed.proc then return end
    RM.armed.proc = on
    for _, e in ipairs(PROC_EVENTS) do
        if not on then
            Events.Off(e, "adrem")
        elseif Valid(e) then
            Events.On(e, "adrem", function(ev, sid)
                RM.OnProc(sid, ev == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            end)
        end
    end
    if not on then wipe(RM.procs) end
end

-- The enchant driver's own events, under a key of their own: the cooldown
-- events share PLAYER_EQUIPMENT_CHANGED.
function RM.ArmEnchant(on)
    if on == RM.armed.ench then return end
    RM.armed.ench = on
    local DE = NS.DriverEnchant
    for _, e in ipairs((DE and DE.EVENTS) or {}) do
        if not on then
            Events.Off(e, "adrem_ench")
        elseif Valid(e) then
            Events.On(e, "adrem_ench", function(ev, unit)
                if ev == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
                Events.Coalesce("adrem_ench", RM.EnchantAll)
            end)
        end
    end
end

-- "When usable" re-reads on usability news and on a new target, a frame at a
-- time: SPELL_UPDATE_USABLE comes in bursts.
function RM.ArmUsable(on)
    if on == RM.armed.usab then return end
    RM.armed.usab = on
    for _, e in ipairs(USABLE_EVENTS) do
        if not on then
            Events.Off(e, "adrem_usab")
        elseif Valid(e) then
            Events.On(e, "adrem_usab", function() Events.Coalesce("adrem_usab", RM.UsableAll) end)
        end
    end
end

-- Which reminders load in drawn groups, their watches, and which events they
-- need. Every cast is noted while any cooldown watch runs, for the wand's lock.
function RM.Sync()
    for gid in pairs(RM.placed) do
        local g = Store.Get(gid)
        if not (g and g.type == "group" and g.groupKind == "reminder") then
            RM.placed[gid] = nil
            RM.Flush(gid)
        end
    end
    local list, keep, proc, shadows, ench, usab = {}, {}, false, false, false, false
    for gid in pairs(RM.placed) do
        for _, rec in ipairs(Store.RemindersOf(Store.Get(gid))) do
            if RM.Loaded(rec) then
                list[#list + 1] = rec.id
                keep[rec.id] = true
                local w = RM.Ensure(rec)
                if w.ench then
                    ench = true
                    RM.EnchantReplan(w, rec)
                else
                    shadows = true
                    local wants = false
                    for _, t in ipairs(rec.triggers or {}) do
                        if t.type == "on_proc" or t.requireProc then proc = true end
                        if t.type == "when_usable" and rec.kind == "spell" then wants = true end
                    end
                    if wants then usab = true end
                    RM.WantUsable(w, rec, wants)
                end
            end
        end
    end
    for id, w in pairs(RM.watch) do
        if w.ext then
            -- an external watch stays until its owner drops it, and keeps the
            -- cooldown (and usable) events it needs armed
            shadows = true
            if w.usable then usab = true end
        elseif not keep[id] then
            RM.Drop(id)
        end
    end
    table.sort(list)
    RM.live = list
    RM.ArmCooldown(shadows)
    RM.ArmCast(shadows)
    RM.ArmProc(proc)
    RM.ArmEnchant(ench)
    RM.ArmUsable(usab)
end

function RM.QueueSync() Events.Coalesce("adrem_sync", RM.Sync) end

-- The editor's writes: each changes the record in place and marks it dirty.

function RM.AddTrigger(rec)
    rec.triggers = rec.triggers or {}
    if #rec.triggers >= NS.Schema.REMINDER_MAX_TRIGGERS then return false end
    rec.triggers[#rec.triggers + 1] = Store.NewTrigger(rec.kind)
    Store.Dirty("style", rec.id)
    return true
end

-- A reminder keeps one trigger at least: the last one cannot go.
function RM.RemoveTrigger(rec, i)
    if not (rec.triggers and rec.triggers[i] and #rec.triggers > 1) then return false end
    table.remove(rec.triggers, i)
    Store.Dirty("style", rec.id)
    return true
end

local OVERRIDE_KEYS = { "pulseDuration", "animFadeSmoothing", "animFlashSpeed", "animZoomStart",
    "animZoomPeak", "animZoomPopTime", "animZoomSettleTime" }

function RM.SetTrigger(rec, i, field, value)
    local t = rec.triggers and rec.triggers[i]
    if not t or t[field] == value then return false end
    t[field] = value
    -- a timed type needs its seconds (v1's own fix); a count needs its number
    if field == "type" and (value == "after_ready" or value == "into_cooldown") and not t.seconds then
        t.seconds = 3
    end
    if field == "type" and value == "enchant_expiring" and not t.seconds then t.seconds = 60 end
    if field == "type" and value == "enchant_charges" and not t.count then t.count = 5 end
    -- off: the override values go, so on starts from the group's again (v1)
    if field == "overrideAnim" and not value then
        for _, k in ipairs(OVERRIDE_KEYS) do t[k] = nil end
    end
    Store.Dirty("style", rec.id)
    return true
end

-- The panel's tests, which play even where the conditions keep a reminder
-- quiet: you asked to see them.

-- Test Alert: the first reminder with the group's own look and sound.
function RM.Test(g)
    local first = Store.RemindersOf(g)[1]
    if not first then return false end
    RM.DoPulse(g, first, { type = "when_ready", groupLook = true, preview = true })
    return true
end

-- The Preview Alert of a reminder's Appearance tab: its own look, no trigger's
-- override, with the group's sound.
function RM.PreviewLook(rec)
    local g = RM.GroupOf(rec)
    if not g then return false end
    RM.DoPulse(g, rec, { type = "when_ready", preview = true })
    return true
end

-- Preview Multiple: up to three reminders a moment apart, to see the overlap,
-- each with its own look.
function RM.PreviewMultiple(g)
    local list = Store.RemindersOf(g)
    if #list == 0 then return false end
    local gid = g.id
    for i = 1, math.min(RM.PREVIEW_COUNT, #list) do
        local id = list[i].id
        local function Go()
            local g2, r = Store.Get(gid), Store.Get(id)
            if g2 and r then RM.DoPulse(g2, r, { type = "when_ready", preview = true }) end
        end
        if i == 1 then Go() else C_Timer.After((i - 1) * RM.PREVIEW_GAP, Go) end
    end
    return true
end

-- Preview Alert: the reminder's first trigger, as it will fire.
function RM.Preview(rec)
    local t = rec and rec.triggers and rec.triggers[1]
    if not (t and RM.GroupOf(rec)) then return false end
    RM.Fire(rec, t, true)
    return true
end

if NS.LayoutEngine and NS.LayoutEngine.RegisterGroupKind then
    NS.LayoutEngine.RegisterGroupKind("reminder", { place = RM.Place, release = RM.Release })
end
Events.OnMessage("AD_DIRTY", "adrem", RM.QueueSync)
-- A group faded to nothing drops what it shows, so no pulse is left to pop
-- back in when it fades in again.
Events.OnMessage("AD_VISIBILITY", "adrem", function()
    for gid in pairs(RM.placed) do
        local P, g = RM.pulse[gid], Store.Get(gid)
        if P and g and RM.Busy(P) and RM.Hidden(g) then RM.Flush(gid) end
    end
end)
-- the conditions pass reads the reminders too, so the events their own
-- conditions need are armed
if NS.Conditions then
    NS.Conditions.RegisterSubject("reminder", {
        each = function(fn)
            for _, id in ipairs(RM.live) do fn(id) end
        end,
        apply = function() end,
    })
end

-- /adremind: every Reminder group, what it listens to, and each reminder's state.
SLASH_ADREMIND1 = "/adremind"
SlashCmdList.ADREMIND = function()
    local TL = NS.Schema.REMINDER_TRIGGER_LABELS
    print(("|cff3fc9f2Arc Auras reminders:|r cooldowns %s, casts %s, procs %s, enchants %s, usable %s"):format(
        RM.armed.cd and "on" or "off", RM.armed.cast and "on" or "off", RM.armed.proc and "on" or "off",
        RM.armed.ench and "on" or "off", RM.armed.usab and "on" or "off"))
    local any = false
    for _, lay in ipairs(Store.Layouts()) do
        for _, g in ipairs((Store.ChildrenOf(lay))) do
            if g.groupKind == "reminder" then
                any = true
                local P = RM.pulse[g.id]
                print(("  %s: %s, %s, %d queued"):format(g.name or "?",
                    RM.placed[g.id] and "drawn" or "not drawn", R(g, "pulse", "queueMode") or "?",
                    P and #P.queue or 0))
                for _, rec in ipairs(Store.RemindersOf(g)) do
                    local w = RM.watch[rec.id]
                    local ENCH = { on = "enchant on", off = "enchant missing", none = "no weapon in that hand" }
                    local st = (not RM.Loaded(rec) and "not loaded here")
                        or (not RM.Live(rec) and "its conditions keep it quiet now")
                        or (w and w.ench and (ENCH[w.state] or "not read yet"))
                        or (w and (w.avail and "ready" or "on cooldown")) or "not watched"
                    if w and w.usable and RM.Live(rec) then
                        st = st .. ((w.castable == nil and ", usable not read yet")
                            or (w.castable and ", castable now")
                            or (w.canUse and ", usable, on cooldown") or ", not castable now")
                    end
                    local ts = {}
                    for _, t in ipairs(rec.triggers or {}) do ts[#ts + 1] = TL[t.type] or t.type end
                    print(("    %s: %s; %s"):format(rec.name or "?", st, table.concat(ts, ", ")))
                end
            end
        end
    end
    if not any then print("  no reminder groups") end
end
