-- AD_DriverCustom: the rule engine behind Custom Icons and Custom Bars (the timer kind): each rule is a trigger the game keeps plain, optional guards, and an action on the item's own timer and stacks.
-- The cooldown driver attaches icons here (Attach / Detach / Refeed); the bars runtime registers CU.BarKind for timer bars; the display goes through Factory.SetState, the icon's Cooldown and the bars kit's GetTime fill.
-- Every trigger stays plain in combat on WoW Forever: UNIT_COMBAT on you and your pet, COMBAT_TEXT_UPDATE's type, your own casts, shadow-Cooldown edges (NS.Reminders' watches), proc overlays, combat, target and totem events. A secret amount or spell ID means unknown and fires nothing.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Schema = NS.Schema

local CU = {}
NS.DriverCustom = CU

-- UNIT_COMBAT on "target" (your attacks dodged, parried, blocked, landing) is
-- not registered by the game's own frames on Forever, so it stays off until a
-- fight with /adcustom diag proves it fires.
CU.CUSTOM_TARGET_FEEDBACK = false
-- A saved state older than this is dropped at login: a timer or a count from
-- yesterday's session is stale.
CU.RUNTIME_MAX_AGE = 3600
-- "Your cast was interrupted" arrives from two events: one fire per moment.
CU.DEDUPE = 0.3
-- A loading screen sends a burst of spell updates for spells nobody used:
-- none of them fires a rule for this long after it.
CU.UPDATE_QUIET = 2
CU.WATCH_PREFIX = "adcustom:"
CU.EVENT_KEY = "adcustom"

CU.items = {}      -- [recId] = { id, rec, f, bar, text, start, dur, endAt, stacks, gen, last }
CU.watchers = {}   -- [key] = fn(st), told after every paint (a text element's readout)
CU.live = {}       -- [recId] = its state, while attached and loaded
CU.watched = {}    -- [spellID] = true, an external watch on the reminder runtime
CU.totemUp = {}    -- [slot] = true while the slot holds a totem
CU.lastFire = {}   -- [trigger] = GetTime of its last fire (the dedupe)
CU.armed = {}      -- which event sets are registered
CU.updQuiet = 0    -- GetTime until which spell updates fire nothing
CU.inCombat = false

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Valid(e)
    return (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(e)
end

-- wall-clock seconds for the saved state; the harness has no time()
local function Clock()
    if type(time) == "function" then
        local t = time()
        if type(t) == "number" then return t end
    end
    return GetTime()
end

-- The triggers a group offers, by key, and every trigger's group.
CU.GROUP_OF = {}
for _, g in ipairs(Schema.CUSTOM_TRIGGER_GROUPS) do
    for _, k in ipairs(g.list) do CU.GROUP_OF[k] = g.key end
end
for _, k in ipairs(Schema.CUSTOM_TARGET_TRIGGERS) do CU.GROUP_OF[k] = "target" end

CU.SPELL_TRIGGERS = { cast = true, cd_start = true, cd_end = true, usable_on = true, usable_off = true,
    proc_on = true, proc_off = true, spell_update = true }
CU.WATCH_TRIGGERS = { cd_start = true, cd_end = true, usable_on = true, usable_off = true }
CU.USABLE_TRIGGERS = { usable_on = true, usable_off = true }
CU.PROC_TRIGGERS = { proc_on = true, proc_off = true }
CU.TOTEM_TRIGGERS = { totem_placed = true, totem_gone = true }
CU.TEXT_TRIGGERS = { extra_attacks = true, reactive = true, health_low = true, mana_low = true,
    combo_points = true, interrupted = true }

-- The state

function CU.Get(id) return CU.items[id] end

function CU.Running(st)
    return st.endAt ~= nil and GetTime() < st.endAt
end

function CU.Rules(rec)
    local d = rec and rec.driver
    local rules = d and d.rules
    if type(rules) == "table" then return rules end
    return nil
end

-- The item shows as active (an icon's ready look, a bar not hidden) per its
-- Show while. An item with no rules yet shows active, so a fresh one can be
-- set up in view.
function CU.Active(st)
    local rules = CU.Rules(st.rec)
    if not (rules and #rules > 0) then return true end
    local w = st.rec.driver.showWhile or "timer"
    local running = CU.Running(st)
    if w == "always" then return true end
    if w == "stacks" then return st.stacks > 0 end
    if w == "either" then return running or st.stacks > 0 end
    return running
end

function CU.Save(st)
    if not CU.Running(st) and st.stacks == 0 then
        Store.SetRuntime(st.id, nil)
        return
    end
    local now = GetTime()
    local s = { s = st.stacks, w = Clock() }
    if CU.Running(st) then
        s.d = st.dur
        s.g = st.endAt
        s.e = Clock() + (st.endAt - now)
    end
    Store.SetRuntime(st.id, s)
end

-- A saved state comes back after a /reload: the stacks as they were, a timer
-- at the time it has left. GetTime runs on across a reload and time() across
-- a restart; the two agree within a few seconds, so the finer one is used.
function CU.Restore(st)
    local s = Store.Runtime(st.id)
    if type(s) ~= "table" then return end
    local wall = Clock()
    if type(s.w) ~= "number" or wall - s.w > CU.RUNTIME_MAX_AGE then
        Store.SetRuntime(st.id, nil)
        return
    end
    st.stacks = math.max(0, math.floor(tonumber(s.s) or 0))
    local d = tonumber(s.d)
    if d and d > 0 and type(s.e) == "number" then
        local left = s.e - wall
        if type(s.g) == "number" then
            local fine = s.g - GetTime()
            if math.abs(fine - left) < 5 then left = fine end
        end
        if left > 0 then
            if left > d then left = d end
            st.dur = d
            st.endAt = GetTime() + left
            st.start = st.endAt - d
            CU.ScheduleEnd(st)
        elseif st.rec.driver.clearOnEnd then
            st.stacks = 0
        end
    end
end

-- The timer and the stacks

function CU.ScheduleEnd(st)
    st.gen = (st.gen or 0) + 1
    local gen, id = st.gen, st.id
    local left = (st.endAt or GetTime()) - GetTime()
    C_Timer.After(math.max(left, 0) + 0.01, function()
        local live = CU.items[id]
        if live and live.gen == gen then CU.Ended(live) end
    end)
end

-- The timer ran out: the stacks clear when asked, the item repaints, and the
-- items chained to this one hear it. A stop never comes here.
function CU.Ended(st)
    st.gen = (st.gen or 0) + 1
    if not st.endAt then return end
    st.start, st.dur, st.endAt = nil, nil, nil
    if st.rec.driver.clearOnEnd then st.stacks = 0 end
    CU.Paint(st)
    CU.Save(st)
    CU.Fire("chain", { srcId = st.id })
end

-- The bar's fill reached zero: the end is processed once, here or from the
-- scheduled check, whichever comes first.
function CU.TimerCheck(st)
    if st.endAt and GetTime() >= st.endAt - 0.02 then
        CU.Ended(st)
    else
        CU.Paint(st)
    end
end

function CU.StartTimer(st, secs, mode)
    secs = tonumber(secs) or 0
    if secs <= 0 then secs = tonumber(st.rec.driver.duration) or 0 end
    if secs <= 0 then return false end
    local now = GetTime()
    local running = CU.Running(st)
    if mode == "idle" and running then return false end
    if mode == "extend" and running then
        st.dur = st.dur + secs
        st.endAt = st.start + st.dur
    else
        st.start, st.dur = now, secs
        st.endAt = now + secs
    end
    CU.ScheduleEnd(st)
    return true
end

function CU.StopTimer(st)
    if not st.endAt then return false end
    st.gen = (st.gen or 0) + 1
    st.start, st.dur, st.endAt = nil, nil, nil
    return true
end

function CU.SetStacks(st, n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    local cap = tonumber(st.rec.driver.maxStacks)
    if cap and cap > 0 and n > cap then n = cap end
    if n == st.stacks then return false end
    st.stacks = n
    return true
end

-- Matching, guards and actions

local nameCache = {}
local function SpellName(sid)
    local nm = nameCache[sid]
    if nm ~= nil then return nm or nil end
    nm = sid and C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(sid))
    if type(nm) ~= "string" or nm == "" then nm = false end
    nameCache[sid] = nm
    return nm or nil
end

-- A rule's spell against an event's: the id, its override or base form, and on
-- ranked realms any rank by name.
function CU.SpellMatch(want, got)
    if type(want) ~= "number" or type(got) ~= "number" then return false end
    if want == got then return true end
    if C_Spell then
        if C_Spell.GetOverrideSpell then
            local ov = Plain(C_Spell.GetOverrideSpell(want))
            if ov == got then return true end
        end
        if C_Spell.GetBaseSpell then
            local base = Plain(C_Spell.GetBaseSpell(got))
            if base == want then return true end
        end
    end
    if NS.IsForever == true then
        local a = SpellName(want)
        return a ~= nil and a == SpellName(got)
    end
    return false
end

function CU.Matches(r, ctx)
    if CU.SPELL_TRIGGERS[r.when] then
        if not (ctx and (CU.SpellMatch(r.spellID, ctx.spellID)
            or (ctx.baseID ~= nil and CU.SpellMatch(r.spellID, ctx.baseID)))) then return false end
        if r.when == "cast" and ctx.unit == "pet" and not r.pet then return false end
        -- a usable rule hears one edge: the plain usable one with "Fire even
        -- while on cooldown", the castable one (usable and ready) without
        if CU.USABLE_TRIGGERS[r.when] and (r.ignoreCooldown == true) ~= (ctx.raw == true) then return false end
        return true
    end
    if CU.TOTEM_TRIGGERS[r.when] then
        return r.slot == nil or (ctx ~= nil and r.slot == ctx.slot)
    end
    if r.when == "chain" then
        return ctx ~= nil and r.srcId ~= nil and r.srcId == ctx.srcId
    end
    return true
end

function CU.WatchKey(sid) return CU.WATCH_PREFIX .. tostring(sid) end

-- The spec you play, plain on retail. WoW Forever has none, so a rule kept to
-- a spec holds back there.
function CU.SpecID()
    if NS.IsForever == true or not Store.CurSpecID then return nil end
    return Store.CurSpecID()
end

-- Every guard reads a plain value of our own or of the talent catalog; a guard
-- that cannot be read holds the rule back.
function CU.Guard(st, r)
    if r.combat == "in" and not CU.inCombat then return false end
    if r.combat == "out" and CU.inCombat then return false end
    -- a talent taken, as Load Conditions read it: a choice node names its
    -- option (talentEntry), and talentNot asks the reverse
    if r.talent then
        local T = NS.TalentCatalog
        if not T then return false end
        local met = T.IsTaken(r.talent) == true
        if met and r.talentEntry then met = T.ActiveEntry ~= nil and T.ActiveEntry(r.talent) == r.talentEntry end
        if met == (r.talentNot == true) then return false end
    end
    if r.spec and CU.SpecID() ~= r.spec then return false end
    if r.spellReady then
        local RM = NS.Reminders
        if not (RM and RM.WatchReady and RM.WatchReady(CU.WatchKey(r.spellReady))) then return false end
    end
    if r.stacksMin and st.stacks < r.stacksMin then return false end
    if r.stacksMax and st.stacks > r.stacksMax then return false end
    if r.withinRule then
        local at = st.last[r.withinRule]
        if not at or GetTime() - at > (r.withinSecs or 1) then return false end
    end
    if r.timer == "running" and not CU.Running(st) then return false end
    if r.timer == "idle" and CU.Running(st) then return false end
    return true
end

function CU.Quiet(rec)
    local C = NS.Conditions
    return C ~= nil and C.IsInert(rec)
end

function CU.Speak(text)
    if type(text) ~= "string" or text == "" then return false end
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local RM = NS.Reminders
    local voice = (RM and RM.Voice and RM.Voice("default")) or 0
    local rate = C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()
    local vol = C_TTSSettings and C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()
    if type(voice) ~= "number" then voice = 0 end
    C_VoiceChat.SpeakText(voice, text, tonumber(rate) or 0, tonumber(vol) or 100, false)
    return true
end

function CU.Channel(rec)
    if rec.type == "icon" then return Store.Resolve(rec, "alerts", "soundChannel") or "Master" end
    return "Master"
end

function CU.Act(st, r)
    local act = r.act or "start"
    local changed = false
    if act == "start" then
        changed = CU.StartTimer(st, r.secs, r.mode or "restart")
    elseif act == "stop" then
        changed = CU.StopTimer(st)
    elseif act == "add" then
        changed = CU.SetStacks(st, st.stacks + (r.n or 1))
        if r.restartToo and CU.StartTimer(st, r.secs, "restart") then changed = true end
    elseif act == "remove" then
        changed = CU.SetStacks(st, st.stacks - (r.n or 1))
    elseif act == "set" then
        changed = CU.SetStacks(st, r.n or 0)
    elseif act == "reset" then
        local a = CU.StopTimer(st)
        local b = CU.SetStacks(st, 0)
        changed = a or b
    elseif act == "sound" then
        if r.sound and NS.Sounds and not CU.Quiet(st.rec) then NS.Sounds.Play(r.sound, CU.Channel(st.rec)) end
    elseif act == "speak" then
        if not CU.Quiet(st.rec) then CU.Speak(r.text) end
    end
    if changed then
        CU.Paint(st)
        CU.Save(st)
    end
end

-- One trigger fires: every live item's rules on it, in order. A rule's action
-- can move the stacks a later rule's guard reads; that order is the list's.
function CU.Fire(when, ctx)
    for _, st in pairs(CU.live) do
        local rules = CU.Rules(st.rec)
        if rules then
            for i, r in ipairs(rules) do
                if r.when == when and not (ctx and ctx.once and st.last[i] == ctx.once)
                    and CU.Matches(r, ctx) and CU.Guard(st, r) then
                    st.last[i] = GetTime()
                    CU.Act(st, r)
                end
            end
        end
    end
end

-- A trigger two events can report: only the first within the window fires.
function CU.FireOnce(when, ctx)
    local now = GetTime()
    local last = CU.lastFire[when]
    if last and now - last < CU.DEDUPE then return end
    CU.lastFire[when] = now
    CU.Fire(when, ctx)
end

-- Painting

function CU.PaintIcon(st)
    local f, rec = st.f, st.rec
    if not f then return end
    local F = NS.Factory
    if CU.Running(st) then
        f.cooldown:SetCooldown(st.start, st.dur)
    else
        f.cooldown:Clear()
    end
    if Store.Resolve(rec, "text", "stackText") ~= false then
        f.stackText:SetText(st.stacks > 0 and st.stacks or "")
    end
    local active = CU.Active(st)
    F.SetState(f, rec, not active, not active)
end

function CU.BarDone(e)
    local K = NS.Bars and NS.Bars.Kit
    if K then K.TimerStop(e) end
    local st = CU.items[e.rec.id]
    if st and st.bar == e then CU.TimerCheck(st) end
end

function CU.PaintBar(st)
    local e, rec = st.bar, st.rec
    local K = NS.Bars and NS.Bars.Kit
    if not (e and K) then return end
    local d = rec.driver or {}
    if e.mode == "stack" then
        if e.running then K.TimerStop(e) end
        e.cuStart, e.cuDur = nil, nil
        local cap = tonumber(d.maxStacks)
        if not (cap and cap > 0) then cap = math.max(st.stacks, 1) end
        e.shell.fill:SetMinMaxValues(0, cap)
        e.shell.fill:SetValue(st.stacks)
        e.shell.fill:SetStatusBarColor(K.BarColorOf(rec))
        K.SetRunText(e.shell, "dur", "")
    elseif CU.Running(st) then
        -- a start, restart or extension runs the fill afresh over the whole
        -- length, then moves its end to the timer's
        if not (e.running and e.cuStart == st.start and e.cuDur == st.dur) then
            e.plainThresh = K.BuildPlainBands(rec)
            K.RunTimedFill(e, st.dur, CU.BarDone)
            e.endTime = st.start + st.dur
            e.cuStart, e.cuDur = st.start, st.dur
        end
    else
        if e.running then K.TimerStop(e) end
        e.cuStart, e.cuDur = nil, nil
    end
    K.SetRunText(e.shell, "stk", K.StackCount(rec, st.stacks))
    e.stateHidden = (not CU.Active(st)) and Store.Resolve(rec, "behavior", "hideWhenInactive") == true
    K.ApplyVisibility(e)
end

function CU.Paint(st)
    st.lastActive = CU.Active(st)
    CU.PaintIcon(st)
    CU.PaintBar(st)
    for _, fn in pairs(CU.watchers) do fn(st) end
end

-- Attach points

local function Ensure(rec)
    local st = CU.items[rec.id]
    if not st then
        st = { id = rec.id, rec = rec, stacks = 0, gen = 0, last = {} }
        CU.items[rec.id] = st
        CU.Restore(st)
    end
    st.rec = rec
    return st
end

function CU.Attach(rec, f)
    local st = Ensure(rec)
    st.f = f
    CU.Paint(st)
    CU.QueueSync()
end

function CU.Detach(id)
    local st = CU.items[id]
    if not st then return end
    st.f = nil
    CU.QueueSync()
end

function CU.Refeed(id)
    local st = CU.items[id]
    if st then CU.Paint(st) end
end

-- A text element with rules of its own (Bars\AD_TextElement.lua): the third
-- sink beside the icon and the bar. Its readout is painted by the watcher it
-- registered, so the engine never learns how a text draws.
function CU.AttachText(rec, e)
    local st = Ensure(rec)
    st.text = e
    CU.Paint(st)
    CU.QueueSync()
end

function CU.DetachText(id)
    local st = CU.items[id]
    if not st then return end
    st.text = nil
    CU.QueueSync()
end

function CU.Watch(key, fn) CU.watchers[key] = fn end

function CU.Unwatch(key) CU.watchers[key] = nil end

-- The bar kind the bars runtime registers (Bars.RegisterKind("timer")).
CU.BarKind = {
    Ensure = function(e)
        local st = Ensure(e.rec)
        st.bar = e
        local K = NS.Bars.Kit
        K.LayoutDividers(e.shell, e.rec, 1)
        if not e.running then
            e.shell.fill:SetMinMaxValues(0, 1)
            e.shell.fill:SetValue(0)
        end
        CU.PaintBar(st)
        CU.QueueSync()
    end,
    Refresh = function(e)
        local st = CU.items[e.rec.id]
        if st and st.bar == e then CU.PaintBar(st) end
    end,
    Release = function(e)
        local st = CU.items[e.rec.id]
        if st and st.bar == e then
            st.bar = nil
            e.cuStart, e.cuDur = nil, nil
            CU.QueueSync()
        end
    end,
    Diag = function(e)
        local st = CU.items[e.rec.id]
        local rules = CU.Rules(e.rec)
        return ("%s [custom %s] rules=%d running=%s stacks=%d live=%s"):format(
            tostring(e.rec.name), tostring(e.mode), rules and #rules or 0,
            tostring(st ~= nil and CU.Running(st)), st and st.stacks or 0,
            tostring(st ~= nil and CU.live[e.rec.id] ~= nil))
    end,
}

-- The tick marks' unit: the bar's seconds while its timer runs (else its
-- default seconds), or its stack cap in stack mode.
function CU.BarTickUnit(e)
    local st = CU.items[e.rec.id]
    local d = e.rec.driver or {}
    if e.mode == "stack" then
        local cap = tonumber(d.maxStacks)
        if not (cap and cap > 0) then cap = math.max(st and st.stacks or 0, 1) end
        return cap, true
    end
    if st and CU.Running(st) then return st.dur, true end
    return tonumber(d.duration), true
end

-- Events, each only while a live item's rules need it

function CU.Feedback(event, flag, amount)
    if event == "DODGE" then return "dodge" end
    if event == "PARRY" then return "parry" end
    if event == "BLOCK" then return "block" end
    if event == "MISS" then return "miss" end
    if event == "ABSORB" then return "absorb" end
    if event == "RESIST" then return "resist" end
    if event == "IMMUNE" then return "immune" end
    if event == "EVADE" or event == "DEFLECT" or event == "REFLECT" then return "avoided" end
    if event == "INTERRUPT" then return "interrupted" end
    if event == "ENERGIZE" then return "energize" end
    if event == "HEAL" then
        if flag == "CRITICAL" then return "healed", "heal_crit" end
        return "healed"
    end
    if event ~= "WOUND" then return nil end
    -- a hit: the flag says so outright; a plain amount says so; a secret
    -- amount with no flag is unknown
    if flag == "CRITICAL" then return "hit", "crit" end
    if flag == "CRUSHING" or flag == "GLANCING" then return "hit" end
    if flag == "BLOCK_REDUCED" then return "hit", "block" end
    local plain = Plain(amount)
    local landed = type(plain) == "number" and plain ~= 0
    if flag == "ABSORB" then return "absorb", landed and "hit" or nil end
    if flag == "BLOCK" then return "block", landed and "hit" or nil end
    if flag == "RESIST" then return "resist", landed and "hit" or nil end
    if type(plain) ~= "number" then return nil end
    if plain ~= 0 then return "hit" end
    return "miss"
end

local UNIT_PREFIX = { player = "", pet = "pet_", target = "target_" }

function CU.OnUnitCombat(unit, event, flag, amount)
    local prefix = UNIT_PREFIX[Plain(unit)]
    if not prefix then return end
    local a, b = CU.Feedback(Plain(event), Plain(flag), amount)
    if a then
        if a == "interrupted" then CU.FireOnce(prefix .. a) else CU.Fire(prefix .. a) end
    end
    if b then CU.Fire(prefix .. b) end
end

local TEXT_TRIGGER = { EXTRA_ATTACKS = "extra_attacks", SPELL_ACTIVE = "reactive", HEALTH_LOW = "health_low",
    MANA_LOW = "mana_low", COMBO_POINTS = "combo_points", INTERRUPT = "interrupted" }

function CU.OnCombatText(kind)
    local key = TEXT_TRIGGER[Plain(kind)]
    if not key then return end
    if key == "interrupted" then CU.FireOnce(key) else CU.Fire(key) end
end

-- Your own casts, and your pet's, are plain in combat; a secret id is noted
-- for the wand lock and fires nothing.
function CU.OnCast(unit, spellID)
    unit = Plain(unit)
    if unit == "player" then
        local D = NS.DriverCooldown
        if D and D.NoteCast then D.NoteCast(spellID) end
    end
    spellID = Plain(spellID)
    if type(spellID) ~= "number" then return end
    CU.Fire("cast", { spellID = spellID, unit = unit })
end

function CU.OnProc(spellID, on)
    spellID = Plain(spellID)
    if type(spellID) ~= "number" then return end
    CU.Fire(on and "proc_on" or "proc_off", { spellID = spellID })
end

-- SPELL_UPDATE_COOLDOWN with its spell: a cooldown that started, changed or
-- reset, and for some buffs their gain or loss. A bulk update names no spell
-- and fires nothing. A frame can carry the same spell twice, so a rule fires
-- once per frame.
function CU.OnSpellUpdate(spellID, baseID)
    local now = GetTime()
    if now < CU.updQuiet then return end
    spellID, baseID = Plain(spellID), Plain(baseID)
    if type(spellID) ~= "number" then spellID = nil end
    if type(baseID) ~= "number" then baseID = nil end
    if not (spellID or baseID) then return end
    CU.Fire("spell_update", { spellID = spellID or baseID, baseID = baseID, once = now })
end

-- A slot's totem: GetTotemDuration answers a duration object while one is
-- down and nothing otherwise, a nil test with no secret in it.
function CU.TotemDown(slot)
    if not GetTotemDuration then return false end
    return GetTotemDuration(slot) ~= nil
end

function CU.OnTotem(slot)
    slot = Plain(slot)
    if type(slot) ~= "number" then return end
    local up = CU.TotemDown(slot)
    local was = CU.totemUp[slot] == true
    CU.totemUp[slot] = up
    if up and not was then
        CU.Fire("totem_placed", { slot = slot })
    elseif was and not up then
        CU.Fire("totem_gone", { slot = slot })
    end
end

function CU.ReadTotems()
    for slot = 1, 4 do CU.totemUp[slot] = CU.TotemDown(slot) end
end

function CU.OnRegen(on)
    CU.inCombat = on
    CU.Fire(on and "combat_start" or "combat_end")
end

-- The unit events ride a frame of their own, filtered to the units the rules
-- name, so nobody else's hits or casts reach Lua.
function CU.UnitFrame()
    local f = CU.frame
    if f then return f end
    f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, unit, a, b, c)
        if event == "UNIT_COMBAT" then
            CU.OnUnitCombat(unit, a, b, c)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            CU.OnCast(unit, b)
        end
    end)
    CU.frame = f
    return f
end

local function UnitList(set)
    local list = {}
    for _, u in ipairs({ "player", "pet", "target" }) do
        if set[u] then list[#list + 1] = u end
    end
    return list
end

-- RegisterUnitEvent takes two units; the target rides a second frame.
function CU.ArmUnit(event, units, tag)
    local key = tag .. ":" .. table.concat(units, ",")
    if CU.armed[tag] == key then return end
    CU.armed[tag] = key
    local f = CU.UnitFrame()
    f:UnregisterEvent(event)
    local f2 = CU.frame2
    if f2 then f2:UnregisterEvent(event) end
    if #units == 0 then return end
    f:RegisterUnitEvent(event, units[1], units[2])
    if units[3] then
        if not f2 then
            f2 = CreateFrame("Frame")
            f2:SetScript("OnEvent", f:GetScript("OnEvent"))
            CU.frame2 = f2
        end
        f2:RegisterUnitEvent(event, units[3])
    end
end

function CU.ArmSet(tag, on, events, handler)
    if (CU.armed[tag] == true) == on then return end
    CU.armed[tag] = on
    for _, e in ipairs(events) do
        if not on then
            Events.Off(e, CU.EVENT_KEY)
        elseif Valid(e) then
            Events.On(e, CU.EVENT_KEY, handler)
        end
    end
end

local PROC_EVENTS = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }
local REGEN_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- The reminder runtime's shadows watch the spells the rules read cooldown and
-- usable edges from, plus the "spell is ready" guards.
function CU.SyncWatches(want, usable)
    local RM = NS.Reminders
    if not (RM and RM.WatchSpell) then return end
    for sid in pairs(CU.watched) do
        if not want[sid] then
            RM.Unwatch(CU.WatchKey(sid))
            CU.watched[sid] = nil
        end
    end
    for sid in pairs(want) do
        local cb = {
            started = function() CU.Fire("cd_start", { spellID = sid }) end,
            ready = function() CU.Fire("cd_end", { spellID = sid }) end,
        }
        if usable[sid] then
            cb.usable = function(on) CU.Fire(on and "usable_on" or "usable_off", { spellID = sid }) end
            cb.usableRaw = function(on) CU.Fire(on and "usable_on" or "usable_off", { spellID = sid, raw = true }) end
        end
        RM.WatchSpell(CU.WatchKey(sid), sid, cb)
        CU.watched[sid] = true
    end
end

function CU.Sync()
    local live = {}
    local feedback, casts, petCasts, text, proc, target, totem = {}, false, false, false, false, false, false
    local upd = false
    local watch, usable = {}, {}
    for id, st in pairs(CU.items) do
        local rec = Store.Get(id)
        if not rec then
            CU.items[id] = nil
        else
            st.rec = rec
            if (st.f or st.bar or st.text) and Store.IsLoaded(rec) then
                live[id] = st
                for _, r in ipairs(CU.Rules(rec) or {}) do
                    local g = CU.GROUP_OF[r.when]
                    if r.when == "cast" then
                        casts = true
                        if r.pet then petCasts = true end
                    elseif CU.WATCH_TRIGGERS[r.when] and r.spellID then
                        watch[r.spellID] = true
                        if CU.USABLE_TRIGGERS[r.when] then usable[r.spellID] = true end
                    elseif CU.PROC_TRIGGERS[r.when] then
                        proc = true
                    elseif r.when == "spell_update" then
                        upd = true
                    elseif g == "you" then
                        feedback.player = true
                    elseif g == "pet" then
                        feedback.pet = true
                    elseif g == "target" then
                        feedback.target = true
                    elseif r.when == "interrupted" or r.when == "energize" or r.when == "healed"
                        or r.when == "heal_crit" then
                        feedback.player = true
                        if r.when == "interrupted" then text = true end
                    elseif CU.TEXT_TRIGGERS[r.when] then
                        text = true
                    elseif r.when == "target_changed" then
                        target = true
                    elseif CU.TOTEM_TRIGGERS[r.when] then
                        totem = true
                    end
                    if r.spellReady then watch[r.spellReady] = true end
                end
            end
        end
    end
    CU.live = live
    -- an edit that changes what counts as active (the rules, Show while)
    -- repaints without waiting for the next attach
    for _, st in pairs(live) do
        if st.lastActive ~= CU.Active(st) then CU.Paint(st) end
    end
    local any = next(live) ~= nil
    local fb = {}
    if feedback.player then fb.player = true end
    if feedback.pet then fb.pet = true end
    if feedback.target and CU.CUSTOM_TARGET_FEEDBACK then fb.target = true end
    CU.ArmUnit("UNIT_COMBAT", UnitList(fb), "feedback")
    local cu = {}
    if casts then
        cu.player = true
        if petCasts then cu.pet = true end
    end
    CU.ArmUnit("UNIT_SPELLCAST_SUCCEEDED", UnitList(cu), "cast")
    CU.ArmSet("text", text, { "COMBAT_TEXT_UPDATE" }, function(_, kind) CU.OnCombatText(kind) end)
    CU.ArmSet("proc", proc, PROC_EVENTS, function(ev, sid)
        CU.OnProc(sid, ev == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    end)
    -- armed at login or /reload, just before the loading burst
    if upd and not CU.armed.update then CU.updQuiet = GetTime() + CU.UPDATE_QUIET end
    CU.ArmSet("update", upd, { "SPELL_UPDATE_COOLDOWN" }, function(_, sid, base) CU.OnSpellUpdate(sid, base) end)
    CU.ArmSet("regen", any, REGEN_EVENTS, function(ev)
        CU.OnRegen(ev == "PLAYER_REGEN_DISABLED")
    end)
    if any then CU.inCombat = InCombatLockdown() == true or CU.inCombat end
    CU.ArmSet("target", target, { "PLAYER_TARGET_CHANGED" }, function() CU.Fire("target_changed") end)
    if totem and not CU.armed.totem then CU.ReadTotems() end
    CU.ArmSet("totem", totem, { "PLAYER_TOTEM_UPDATE" }, function(_, slot) CU.OnTotem(slot) end)
    CU.ArmSet("world", any, { "PLAYER_ENTERING_WORLD" }, function()
        CU.updQuiet = GetTime() + CU.UPDATE_QUIET
        if CU.armed.totem then CU.ReadTotems() end
    end)
    CU.SyncWatches(watch, usable)
end

function CU.QueueSync() Events.Coalesce("adcustom_sync", CU.Sync) end

-- The editor's writes: each changes the record in place and marks it dirty.

function CU.AddRule(rec)
    local d = rec.driver
    d.rules = d.rules or {}
    if #d.rules >= Schema.CUSTOM_MAX_RULES then return false end
    d.rules[#d.rules + 1] = { when = "cast", act = "start", mode = "restart" }
    Store.Dirty("style", rec.id)
    return true
end

function CU.RemoveRule(rec, i)
    local rules = CU.Rules(rec)
    if not (rules and rules[i]) then return false end
    table.remove(rules, i)
    -- a "within N seconds after rule Y" that named a later rule follows it
    for _, r in ipairs(rules) do
        if r.withinRule then
            if r.withinRule == i then r.withinRule, r.withinSecs = nil, nil
            elseif r.withinRule > i then r.withinRule = r.withinRule - 1 end
        end
    end
    local st = CU.items[rec.id]
    if st then st.last = {} end
    Store.Dirty("style", rec.id)
    return true
end

function CU.MoveRule(rec, i, dir)
    local rules = CU.Rules(rec)
    local j = i + dir
    if not (rules and rules[i] and rules[j]) then return false end
    rules[i], rules[j] = rules[j], rules[i]
    for _, r in ipairs(rules) do
        if r.withinRule == i then r.withinRule = j
        elseif r.withinRule == j then r.withinRule = i end
    end
    local st = CU.items[rec.id]
    if st then st.last = {} end
    Store.Dirty("style", rec.id)
    return true
end

function CU.SetRule(rec, i, field, value)
    local rules = CU.Rules(rec)
    local r = rules and rules[i]
    if not r or r[field] == value then return false end
    r[field] = value
    -- a new trigger drops the parameters the old one had
    if field == "when" then
        if not CU.SPELL_TRIGGERS[value] then r.spellID, r.pet = nil, nil end
        if value ~= "cast" then r.pet = nil end
        if not CU.USABLE_TRIGGERS[value] then r.ignoreCooldown = nil end
        if not CU.TOTEM_TRIGGERS[value] then r.slot = nil end
        if value ~= "chain" then r.srcId = nil end
    end
    if field == "withinRule" and value == nil then r.withinSecs = nil end
    -- a choice belongs to its talent; no talent, no reverse
    if field == "talent" then
        r.talentEntry = nil
        if value == nil then r.talentNot = nil end
    end
    Store.Dirty("style", rec.id)
    return true
end

function CU.SetDriver(rec, field, value)
    local d = rec.driver
    if d[field] == value then return false end
    d[field] = value
    Store.Dirty("style", rec.id)
    return true
end

-- A rule in a few words, for summaries.
function CU.Words(r)
    local L = Schema.CUSTOM_TRIGGER_LABELS[r.when] or tostring(r.when)
    if CU.SPELL_TRIGGERS[r.when] and r.spellID then
        L = L .. " (" .. (SpellName(r.spellID) or tostring(r.spellID)) .. ")"
    end
    local A = Schema.CUSTOM_ACTION_LABELS[r.act] or tostring(r.act)
    if r.act == "start" then
        A = A .. (" (%g s)"):format((r.secs and r.secs > 0) and r.secs or 0)
    elseif r.act == "add" or r.act == "remove" or r.act == "set" then
        A = A .. " (" .. tostring(r.n or 1) .. ")"
    end
    return L .. " > " .. A
end

Events.OnMessage("AD_DIRTY", CU.EVENT_KEY, CU.QueueSync)

-- /adcustom: every custom item's state. /adcustom diag: for 60 seconds, a
-- count of UNIT_COMBAT by unit and event and of COMBAT_TEXT_UPDATE by type,
-- then one summary, so the target source and the combat-text gating can be
-- read off one fight. Chat output only ever answers the typed command.
SLASH_ADCUSTOM1 = "/adcustom"
SlashCmdList.ADCUSTOM = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "diag" then
        if CU.diag then
            print("|cff3fc9f2Arc Auras custom:|r the diag is already counting")
            return
        end
        local counts, textCounts = {}, {}
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, a, b, c)
            if event == "UNIT_COMBAT" then
                local k = tostring(Plain(a) or "?") .. " " .. tostring(Plain(b) or "?")
                if Plain(c) ~= nil and Plain(c) ~= "" then k = k .. "/" .. tostring(Plain(c)) end
                counts[k] = (counts[k] or 0) + 1
            else
                local k = tostring(Plain(a) or "?")
                textCounts[k] = (textCounts[k] or 0) + 1
            end
        end)
        f:RegisterUnitEvent("UNIT_COMBAT", "player", "pet")
        local f2 = CreateFrame("Frame")
        f2:SetScript("OnEvent", f:GetScript("OnEvent"))
        f2:RegisterUnitEvent("UNIT_COMBAT", "target")
        if Valid("COMBAT_TEXT_UPDATE") then f:RegisterEvent("COMBAT_TEXT_UPDATE") end
        CU.diag = f
        local fct = GetCVar and GetCVar("enableFloatingCombatText")
        print(("|cff3fc9f2Arc Auras custom diag:|r counting for 60 s (floating combat text cvar: %s)"):format(
            tostring(fct)))
        C_Timer.After(60, function()
            f:UnregisterAllEvents()
            f2:UnregisterAllEvents()
            CU.diag = nil
            local keys = {}
            for k in pairs(counts) do keys[#keys + 1] = k end
            table.sort(keys)
            print("|cff3fc9f2Arc Auras custom diag:|r UNIT_COMBAT by unit and event")
            for _, k in ipairs(keys) do print(("  %s: %d"):format(k, counts[k])) end
            if #keys == 0 then print("  none") end
            keys = {}
            for k in pairs(textCounts) do keys[#keys + 1] = k end
            table.sort(keys)
            print("|cff3fc9f2Arc Auras custom diag:|r COMBAT_TEXT_UPDATE by type")
            for _, k in ipairs(keys) do print(("  %s: %d"):format(k, textCounts[k])) end
            if #keys == 0 then print("  none") end
            local tgt = 0
            for k, n in pairs(counts) do
                if k:sub(1, 6) == "target" then tgt = tgt + n end
            end
            local ct = 0
            for _, n in pairs(textCounts) do ct = ct + n end
            print(("|cff3fc9f2Arc Auras custom diag:|r target UNIT_COMBAT %s (%d), combat text %s (%d)"):format(
                tgt > 0 and "FIRES" or "silent", tgt, ct > 0 and "fires" or "silent", ct))
        end)
        return
    end
    print("|cff3fc9f2Arc Auras custom:|r /adcustom diag - count the combat feedback events for 60 s")
    local n = 0
    for id, st in pairs(CU.items) do
        n = n + 1
        local rules = CU.Rules(st.rec)
        print(("  %s: %s, %d rules, %s, %d stacks%s"):format(tostring(st.rec.name), CU.live[id] and "live" or "idle",
            rules and #rules or 0, CU.Running(st) and ("running, %.1f s left"):format(st.endAt - GetTime()) or "stopped",
            st.stacks, CU.Active(st) and "" or ", shown inactive"))
    end
    if n == 0 then print("  no custom icons or bars") end
    local ev = {}
    for tag, v in pairs(CU.armed) do
        if v then ev[#ev + 1] = tag end
    end
    table.sort(ev)
    print("  events: " .. (#ev > 0 and table.concat(ev, ", ") or "none"))
end
