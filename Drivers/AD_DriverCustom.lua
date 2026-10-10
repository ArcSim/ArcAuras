-- AD_DriverCustom: the rule engine behind Custom Icons and Custom Bars (the timer kind): each rule is a trigger the game keeps plain, optional guards, and an action on the item's own timer and stacks.
-- The cooldown driver attaches icons here (Attach / Detach / Refeed); the bars runtime registers CU.BarKind for timer bars; the display goes through Factory.SetState, the icon's Cooldown and the bars kit's GetTime fill. A Sound item (Bars\AD_SoundItem.lua) attaches with nothing to draw: its rules only cue sounds and speech.
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
-- Saved stacks older than this are dropped at login: a count from yesterday's
-- session is stale. A timer or a stack still running is picked up at any age.
CU.RUNTIME_MAX_AGE = 3600
-- "Your cast was interrupted" arrives from two events: one fire per moment.
CU.DEDUPE = 0.3
-- A loading screen sends a burst of spell updates for spells nobody used:
-- none of them fires a rule for this long after it.
CU.UPDATE_QUIET = 2
-- A login or reload settles a few reads late (the roster, the pet): a
-- condition's edge only sets its state for this long after one.
CU.COND_QUIET = 3
CU.WATCH_PREFIX = "adcustom:"
CU.EVENT_KEY = "adcustom"

CU.items = {}      -- [recId] = { id, rec, f, bar, text, start, dur, endAt, stacks, gen, last, exp, sgen }
CU.watchers = {}   -- [key] = fn(st), told after every paint (a text element's readout)
CU.live = {}       -- [recId] = its state, while attached and loaded
CU.watched = {}    -- [spellID] = true, an external watch on the reminder runtime
CU.totemUp = {}    -- [slot] = true while the slot holds a totem
CU.lastFire = {}   -- [trigger] = GetTime of its last fire (the dedupe)
CU.armed = {}      -- which event sets are registered
CU.updQuiet = 0    -- GetTime until which spell updates fire nothing
CU.conds = {}      -- [key] = true, the condition keys the live rules watch
CU.condWas = {}    -- [key] = the key's last known answer
CU.condQuiet = 0   -- GetTime until which a condition's edge fires nothing
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
for _, list in ipairs({ Schema.CUSTOM_TRIGGER_GROUPS, Schema.SOUND_TRIGGER_GROUPS or {} }) do
    for _, g in ipairs(list) do
        for _, k in ipairs(g.list) do CU.GROUP_OF[k] = g.key end
    end
end
for _, k in ipairs(Schema.CUSTOM_TARGET_TRIGGERS) do CU.GROUP_OF[k] = "target" end

CU.SPELL_TRIGGERS = { cast = true, cast_except = true, cd_start = true, cd_end = true, usable_on = true,
    usable_off = true, proc_on = true, proc_off = true, spell_update = true }
CU.WATCH_TRIGGERS = { cd_start = true, cd_end = true, usable_on = true, usable_off = true }
CU.USABLE_TRIGGERS = { usable_on = true, usable_off = true }
CU.PROC_TRIGGERS = { proc_on = true, proc_off = true }
CU.TOTEM_TRIGGERS = { totem_placed = true, totem_gone = true }
CU.TEXT_TRIGGERS = { extra_attacks = true, reactive = true, health_low = true, mana_low = true,
    combo_points = true, interrupted = true }
CU.COND_TRIGGERS = { cond_on = true, cond_off = true }
-- the game plays these itself (Drivers\AD_AuraSounds.lua): no event reaches a rule
CU.AURA_TRIGGERS = { aura_gain = true, aura_stack = true, aura_lost = true }
-- Conditions that read another unit's identity, secret in instances: never a trigger.
CU.COND_SKIP = { pvp = true, shamanInGroup = true, roleTank = true, roleHealer = true, roleDamage = true,
    groupLeader = true }

-- A condition can be a trigger when the client reads it, an event reports it
-- (the polled rows would need a ticker) and it is a state that can turn on.
function CU.CondOK(key)
    local C = NS.Conditions
    local d = type(key) == "string" and C and C.ByKey and C.ByKey(key)
    if not d or d.poll or d.negOnly or CU.COND_SKIP[key] then return false end
    return not (d.avail and not d.avail())
end

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

-- The count it shows: its stacks, or while the timer is idle at no stacks
-- the full pool it is set to show (driver.idleCount).
function CU.ShownCount(st)
    if st.stacks > 0 then return st.stacks end
    local n = tonumber(st.rec.driver.idleCount)
    if n and n > 0 and not CU.Running(st) then return n end
    return 0
end

function CU.Save(st)
    if not CU.Running(st) and st.stacks == 0 then
        Store.SetRuntime(st.id, nil)
        return
    end
    local now, wall = GetTime(), Clock()
    local s = { s = st.stacks, w = wall }
    if CU.Running(st) then
        s.d = st.dur
        s.g = st.endAt
        s.e = wall + (st.endAt - now)
    end
    if st.exp and #st.exp > 0 then
        s.x = {}
        for i, t in ipairs(st.exp) do s.x[i] = wall + (t - now) end
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
    local ahead = type(s.e) == "number" and s.e > wall
    if type(s.x) == "table" then
        for _, x in ipairs(s.x) do
            if type(x) == "number" and x > wall then ahead = true end
        end
    end
    if type(s.w) ~= "number" or (wall - s.w > CU.RUNTIME_MAX_AGE and not ahead) then
        Store.SetRuntime(st.id, nil)
        return
    end
    st.stacks = math.max(0, math.floor(tonumber(s.s) or 0))
    -- the stacks' own ends: the ones passed while away are gone
    if type(s.x) == "table" and CU.StackTimed(st) then
        local exp, gone = {}, 0
        for _, x in ipairs(s.x) do
            if type(x) == "number" then
                if x > wall then exp[#exp + 1] = GetTime() + (x - wall) else gone = gone + 1 end
            end
        end
        st.stacks = math.max(0, st.stacks - gone)
        while #exp > st.stacks do table.remove(exp) end
        st.exp = exp
        CU.ScheduleStacks(st)
    end
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
            CU.SetStacks(st, 0)
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
    if st.rec.driver.clearOnEnd then CU.SetStacks(st, 0) end
    CU.Paint(st)
    CU.Save(st)
    -- one pass hears both: this item's "this timer ended" and the items chained to it
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

-- A rule's seconds, else the item's Default seconds; 0 = no length.
function CU.Len(st, secs)
    secs = tonumber(secs) or 0
    if secs <= 0 then secs = tonumber(st.rec.driver.duration) or 0 end
    if secs < 0 then secs = 0 end
    return secs
end

function CU.StartTimer(st, secs, mode)
    secs = CU.Len(st, secs)
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

-- The one writer of the count. secs: a new stack's seconds when each stack
-- runs out on its own.
function CU.SetStacks(st, n, secs)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    local cap = tonumber(st.rec.driver.maxStacks)
    if cap and cap > 0 and n > cap then n = cap end
    if n == st.stacks then return false end
    local was = st.stacks
    st.stacks = n
    CU.SyncExp(st, was, secs)
    return true
end

-- k more stacks. Past the cap, with stack timers, an add renews the end of
-- the stack nearest its end instead.
function CU.AddStacks(st, k, secs)
    local want = st.stacks + k
    local changed = CU.SetStacks(st, want, secs)
    local over = want - st.stacks
    if over > 0 and k > 0 and CU.StackTimed(st) and st.exp and #st.exp > 0 then
        local len = CU.Len(st, secs)
        if len > 0 then
            for _ = 1, math.min(over, #st.exp) do
                local i = CU.Soonest(st.exp)
                st.exp[i] = GetTime() + len
            end
            CU.ScheduleStacks(st)
            changed = true
        end
    end
    return changed
end

-- Stacks that each run out on their own (driver.stackTimers): every stack
-- added carries its own end (st.exp, GetTime seconds) from the rule's seconds,
-- else the item's Default seconds; with neither it never runs out. One
-- scheduled call waits for the soonest end.
function CU.StackTimed(st)
    return st.rec.driver.stackTimers == true
end

function CU.Soonest(exp)
    local bi
    for i, t in ipairs(exp) do
        if not bi or t < exp[bi] then bi = i end
    end
    return bi
end

-- The ends follow the count: fewer stacks drop the soonest ends (stacks with
-- no end go last), more give each new stack its own.
function CU.SyncExp(st, was, secs)
    if not CU.StackTimed(st) then
        if st.exp then
            st.exp = nil
            st.sgen = (st.sgen or 0) + 1
        end
        return
    end
    local exp = st.exp or {}
    st.exp = exp
    local n = st.stacks
    if n < was then
        for _ = 1, was - n do
            local i = CU.Soonest(exp)
            if not i then break end
            table.remove(exp, i)
        end
    elseif n > was then
        local len = CU.Len(st, secs)
        if len > 0 then
            local at = GetTime() + len
            for _ = 1, n - was do exp[#exp + 1] = at end
        end
    end
    while #exp > n do table.remove(exp, CU.Soonest(exp)) end
    CU.ScheduleStacks(st)
end

function CU.ScheduleStacks(st)
    st.sgen = (st.sgen or 0) + 1
    local i = st.exp and CU.Soonest(st.exp)
    if not i then return end
    local gen, id = st.sgen, st.id
    C_Timer.After(math.max(st.exp[i] - GetTime(), 0) + 0.01, function()
        local live = CU.items[id]
        if live and live.sgen == gen then CU.StacksRanOut(live) end
    end)
end

-- The soonest stacks reached their ends: they drop, the item repaints.
function CU.StacksRanOut(st)
    if not (CU.StackTimed(st) and st.exp) then
        st.exp = nil
        return
    end
    local now, gone = GetTime(), 0
    for i = #st.exp, 1, -1 do
        if st.exp[i] <= now + 0.005 then
            table.remove(st.exp, i)
            gone = gone + 1
        end
    end
    if gone > 0 then
        st.stacks = math.max(0, st.stacks - gone)
        CU.Paint(st)
        CU.Save(st)
    end
    CU.ScheduleStacks(st)
end

-- Matching, guards and actions

local nameCache = {}
local function SpellName(sid)
    local nm = nameCache[sid]
    if nm ~= nil then return nm or nil end
    nm = sid and C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(sid)) -- raw-id: a rule's typed spell, for its words
    if type(nm) ~= "string" or nm == "" then nm = false end
    nameCache[sid] = nm
    return nm or nil
end

-- A rule's spell against an event's: the one matcher (its override or base
-- form, and on ranked realms any rank by name).
function CU.SpellMatch(want, got)
    if type(want) ~= "number" or type(got) ~= "number" then return false end
    return Store.SpellMatch(want, got)
end

-- A rule's spells: its one, or every one of its list.
function CU.RuleSpells(r)
    if type(r.spellIDs) == "table" and #r.spellIDs > 0 then return r.spellIDs end
    return { r.spellID }
end

function CU.RuleHears(r, sid)
    if type(sid) ~= "number" then return false end
    if CU.SpellMatch(r.spellID, sid) then return true end
    local list = r.spellIDs
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if CU.SpellMatch(list[i], sid) then return true end
    end
    return false
end

-- st: the item whose rule this is (its own end names it).
function CU.Matches(r, ctx, st)
    -- your own casts but the listed spells (any rank of them); none listed: every cast
    if r.when == "cast_except" then
        if not (ctx and ctx.unit == "player" and type(ctx.spellID) == "number") then return false end
        return not (CU.RuleHears(r, ctx.spellID) or (ctx.baseID ~= nil and CU.RuleHears(r, ctx.baseID)))
    end
    if CU.SPELL_TRIGGERS[r.when] then
        if not (ctx and (CU.RuleHears(r, ctx.spellID)
            or (ctx.baseID ~= nil and CU.RuleHears(r, ctx.baseID)))) then return false end
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
    if r.when == "ended" then
        return ctx ~= nil and st ~= nil and ctx.srcId == st.id
    end
    if CU.COND_TRIGGERS[r.when] then
        return ctx ~= nil and r.cond ~= nil and r.cond == ctx.cond
    end
    if CU.AURA_TRIGGERS[r.when] then return false end
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

-- Every spoken line of Arc Auras: the shared voice and rate picked under a
-- Sound item's Speech (settings ttsVoice, ttsRate: 0 or none = WoW's own rate),
-- at WoW's own text to speech volume.
function CU.Speak(text)
    if type(text) ~= "string" or text == "" then return false end
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local RM = NS.Reminders
    local pick = Store.GetSetting and Store.GetSetting("ttsVoice") or nil
    local voice = (RM and RM.Voice and RM.Voice(pick or "default")) or 0
    local rate = Store.GetSetting and Store.GetSetting("ttsRate") or nil
    if type(rate) ~= "number" or rate == 0 then
        rate = C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()
    end
    local vol = C_TTSSettings and C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()
    if type(voice) ~= "number" then voice = 0 end
    C_VoiceChat.SpeakText(voice, text, tonumber(rate) or 0, tonumber(vol) or 100, false)
    return true
end

function CU.Channel(rec)
    if rec.type == "icon" then return Store.Resolve(rec, "alerts", "soundChannel") or "Master" end
    local SN = NS.SoundItems
    if SN and SN.Is(rec) then return SN.Channel(rec) end
    return "Master"
end

-- A sound or a spoken line: silent while inert, nothing to play is no cue, and
-- a Sound item's spam guards have the last word (NS.SoundItems.MayCue).
function CU.Cue(st, r, i)
    if CU.Quiet(st.rec) then return false end
    local speak = r.act == "speak"
    if speak then
        if type(r.text) ~= "string" or r.text == "" or not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    elseif not (r.sound and NS.Sounds) then
        return false
    end
    local SN = NS.SoundItems
    if SN and SN.Is(st.rec) and not SN.MayCue(st, r, i) then return false end
    if speak then return CU.Speak(r.text) end
    NS.Sounds.Play(r.sound, CU.Channel(st.rec))
    return true
end

function CU.Act(st, r, i)
    local act = r.act or "start"
    local changed = false
    if act == "start" then
        changed = CU.StartTimer(st, r.secs, r.mode or "restart")
    elseif act == "stop" then
        changed = CU.StopTimer(st)
    elseif act == "add" then
        changed = CU.AddStacks(st, r.n or 1, r.secs)
        if r.restartToo and CU.StartTimer(st, r.secs, "restart") then changed = true end
    elseif act == "remove" then
        changed = CU.SetStacks(st, st.stacks - (r.n or 1))
    elseif act == "set" then
        changed = CU.SetStacks(st, r.n or 0, r.secs)
    elseif act == "reset" then
        local a = CU.StopTimer(st)
        local b = CU.SetStacks(st, 0)
        changed = a or b
    elseif act == "sound" or act == "speak" then
        CU.Cue(st, r, i)
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
                if (r.when == when or (when == "chain" and r.when == "ended"))
                    and not (ctx and ctx.once and st.last[i] == ctx.once)
                    and CU.Matches(r, ctx, st) and CU.Guard(st, r) then
                    st.last[i] = GetTime()
                    CU.Act(st, r, i)
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
        local n = CU.ShownCount(st)
        if n == 0 and Store.Resolve(rec, "text", "stackShowZero") ~= true then n = "" end
        f.stackText:SetText(n)
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

-- A stack bar's length in stacks: Max stacks, else the count it holds.
function CU.BarCap(st)
    local cap = tonumber(st.rec.driver and st.rec.driver.maxStacks)
    if cap and cap > 0 then return math.floor(cap) end
    return math.max(CU.ShownCount(st), 1)
end

function CU.PaintBar(st)
    local e, rec = st.bar, st.rec
    local K = NS.Bars and NS.Bars.Kit
    if not (e and K) then return end
    local d = rec.driver or {}
    local shown = CU.ShownCount(st)
    if e.mode == "stack" then
        if e.running then K.TimerStop(e) end
        local cap = CU.BarCap(st)
        e.shell.fill:SetMinMaxValues(0, cap)
        -- cells (pips, icons, segments) light one by one over an empty fill;
        -- with no Max stacks a new count past the row adds a cell
        if e.pipsOn then
            if e.cellCount ~= cap then
                e.cellCount = cap
                K.LayoutPips(e)
            end
            e.shell.fill:SetValue(0)
            K.FeedCells(e, shown)
        else
            e.shell.fill:SetValue(shown)
        end
        e.shell.fill:SetStatusBarColor(K.BarColorOf(rec))
        K.SetRunText(e.shell, "dur", "")
        -- the timer's time left as the duration text (plain GetTime numbers on
        -- a text-only Cooldown); pushed only when the timer changes
        local running = CU.Running(st)
        local s0, d0 = running and st.start or nil, running and st.dur or nil
        if e.durCD and (e.cuStart ~= s0 or e.cuDur ~= d0) then
            if running then e.durCD:SetCooldown(s0, d0) else e.durCD:Clear() end
        end
        e.cuStart, e.cuDur = s0, d0
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
    K.SetRunText(e.shell, "stk", K.StackCount(rec, shown))
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

-- A Sound item (Bars\AD_SoundItem.lua): the fourth sink, which draws nothing;
-- its rules only ever cue a sound or a spoken line.
function CU.AttachSound(rec, e)
    local st = Ensure(rec)
    st.sound = e
    CU.QueueSync()
end

function CU.DetachSound(id)
    local st = CU.items[id]
    if not st then return end
    st.sound = nil
    CU.QueueSync()
end

function CU.Watch(key, fn) CU.watchers[key] = fn end

function CU.Unwatch(key) CU.watchers[key] = nil end

-- The bar kind the bars runtime registers (Bars.RegisterKind("timer")).
CU.BarKind = {
    -- stack mode shows its timer as text only (a mode change rebuilds the bar)
    Build = function(e)
        local K = NS.Bars and NS.Bars.Kit
        if e.mode == "stack" and not e.durCD and K and K.TextCooldown then e.durCD = K.TextCooldown(e.shell) end
    end,
    Ensure = function(e)
        local st = Ensure(e.rec)
        st.bar = e
        local K = NS.Bars.Kit
        K.LayoutDividers(e.shell, e.rec, 1)
        -- the cells of a stack bar drawn as pips, icons or segments, or none
        if e.mode == "stack" then
            e.cellCount = CU.BarCap(st)
            K.LayoutPips(e)
        end
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
    -- a new size: the segments split it again
    Relayout = function(e)
        local K = NS.Bars.Kit
        K.LayoutDividers(e.shell, e.rec, 1)
        if e.mode == "stack" then
            K.LayoutPips(e)
            local st = CU.items[e.rec.id]
            if st and st.bar == e then K.FeedCells(e, CU.ShownCount(st)) end
        end
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
    local ctx = { spellID = spellID, unit = unit }
    CU.Fire("cast", ctx)
    CU.Fire("cast_except", ctx)
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

-- The condition triggers: the conditions module arms the events of the keys
-- the live rules name and calls CU.OnConds after each of its passes. A key's
-- first read only sets its state, so a state already true never fires.
function CU.SyncConds(want)
    local C = NS.Conditions
    if not (C and C.Watch) then return end
    for key in pairs(CU.condWas) do
        if not want[key] then CU.condWas[key] = nil end
    end
    local any = next(want) ~= nil
    -- armed at login or /reload, while the roster and the pet still settle
    if any and not CU.armed.cond then CU.condQuiet = GetTime() + CU.COND_QUIET end
    CU.armed.cond = any
    CU.conds = want
    C.Watch(CU.EVENT_KEY, want, CU.OnConds)
end

-- An edge is a known answer that differs from the last known one. An unknown
-- answer fires nothing and forgets the state, so the next known one only sets it.
function CU.OnConds()
    local C = NS.Conditions
    if not (C and C.Read) then return end
    local quiet = GetTime() < CU.condQuiet
    for key in pairs(CU.conds) do
        local v = C.Read(key)
        local was = CU.condWas[key]
        CU.condWas[key] = v
        if v ~= nil and was ~= nil and v ~= was and not quiet then
            CU.Fire(v and "cond_on" or "cond_off", { cond = key })
        end
    end
end

function CU.Sync()
    local live = {}
    local feedback, casts, petCasts, text, proc, target, totem = {}, false, false, false, false, false, false
    local upd = false
    local watch, usable, conds = {}, {}, {}
    for id, st in pairs(CU.items) do
        local rec = Store.Get(id)
        if not rec then
            CU.items[id] = nil
        else
            st.rec = rec
            if (st.f or st.bar or st.text or st.sound) and Store.IsLoaded(rec) then
                live[id] = st
                for _, r in ipairs(CU.Rules(rec) or {}) do
                    local g = CU.GROUP_OF[r.when]
                    if r.when == "cast" or r.when == "cast_except" then
                        casts = true
                        if r.pet then petCasts = true end
                    elseif CU.WATCH_TRIGGERS[r.when] and r.spellID then
                        for _, sid in ipairs(CU.RuleSpells(r)) do
                            watch[sid] = true
                            if CU.USABLE_TRIGGERS[r.when] then usable[sid] = true end
                        end
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
                    elseif CU.COND_TRIGGERS[r.when] and CU.CondOK(r.cond) then
                        conds[r.cond] = true
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
    CU.ArmSet("world", any, { "PLAYER_ENTERING_WORLD" }, function(_, login, reload)
        CU.updQuiet = GetTime() + CU.UPDATE_QUIET
        -- a zone change keeps its edges (entering a dungeon is one)
        if login or reload then CU.condQuiet = GetTime() + CU.COND_QUIET end
        if CU.armed.totem then CU.ReadTotems() end
    end)
    CU.SyncWatches(watch, usable)
    CU.SyncConds(conds)
end

function CU.QueueSync() Events.Coalesce("adcustom_sync", CU.Sync) end

-- The editor's writes: each changes the record in place and marks it dirty.

function CU.AddRule(rec)
    local d = rec.driver
    d.rules = d.rules or {}
    if #d.rules >= Schema.CUSTOM_MAX_RULES then return false end
    -- a Sound item's rule only ever plays something
    if rec.type == "bar" and rec.barKind == "sound" then
        d.rules[#d.rules + 1] = { when = "cast", act = "sound" }
    else
        d.rules[#d.rules + 1] = { when = "cast", act = "start", mode = "restart" }
    end
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
    if st then st.last, st.cue = {}, nil end
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
    if st then st.last, st.cue = {}, nil end
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
        if not CU.SPELL_TRIGGERS[value] then r.spellID, r.spellIDs, r.pet = nil, nil, nil end
        if value ~= "cast" then r.pet = nil end
        if not CU.USABLE_TRIGGERS[value] then r.ignoreCooldown = nil end
        if not CU.TOTEM_TRIGGERS[value] then r.slot = nil end
        if value ~= "chain" then r.srcId = nil end
        if not CU.COND_TRIGGERS[value] then r.cond = nil end
        if not CU.AURA_TRIGGERS[value] then r.unit, r.auraIDs = nil, nil end
        -- the game plays an aura's moment from a sound file: never speech or a
        -- kit, and no guard of ours can hold it back
        if CU.AURA_TRIGGERS[value] then
            if r.act == "speak" then r.act = "sound" end
            if type(r.sound) == "string" and r.sound:sub(1, 4) == "kit:" then r.sound = nil end
            r.combat, r.talent, r.talentEntry, r.talentNot, r.spec, r.spellReady = nil, nil, nil, nil, nil, nil
            r.stacksMin, r.stacksMax, r.withinRule, r.withinSecs, r.timer = nil, nil, nil, nil, nil
        end
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
    -- the count it shows and its stacks' ends follow the edit at once
    local st = CU.items[rec.id]
    if st then
        if field == "stackTimers" then CU.SyncExp(st, st.stacks) end
        CU.Paint(st)
    end
    return true
end

-- A rule in a few words, for summaries.
function CU.Words(r)
    local L = Schema.CUSTOM_TRIGGER_LABELS[r.when] or tostring(r.when)
    if CU.SPELL_TRIGGERS[r.when] and r.spellID then
        local more = (type(r.spellIDs) == "table" and #r.spellIDs > 1) and (" + " .. (#r.spellIDs - 1)) or ""
        L = L .. " (" .. (SpellName(r.spellID) or tostring(r.spellID)) .. more .. ")"
    end
    if CU.COND_TRIGGERS[r.when] and r.cond then
        local C = NS.Conditions
        local d = C and C.ByKey and C.ByKey(r.cond)
        L = L .. " (" .. ((d and d.text) or r.cond) .. ")"
    end
    local first = CU.AURA_TRIGGERS[r.when] and type(r.auraIDs) == "table" and r.auraIDs[1]
    if first then
        L = L .. " (" .. (SpellName(first) or tostring(first)) .. ((#r.auraIDs > 1) and ", ..." or "") .. ")"
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
