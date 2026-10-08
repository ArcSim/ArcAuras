-- AD_SwingColors: a swing bar's fill wears an ability's colour while it is queued on the next swing, or from its cast until that swing lands.
-- Owns the rules' state and a colour hook on the main fill; the bars runtime calls in through Bars.SwingColor when it styles or releases a swing bar.
-- IsCurrentSpell and PLAYER_SWING's duration are plain on Forever; a secret answer keeps the last state and never reaches a compare.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.BarColorOf and K.SwingClock) then return end
local Events = NS.Events

local SW = {}
Bars.SwingColor = SW

local KEY = "adswingcolors"
local EVENTS = { "PLAYER_SWING", "CURRENT_SPELL_CAST_CHANGED", "SPELLS_CHANGED" }
local CAST_EVENT = "UNIT_SPELLCAST_SUCCEEDED"
-- An ability that goes off with a swing reports in the same moment as that
-- swing, in either order: a swing this soon after a cast is the cast's own.
SW.GRACE = 0.1
-- How long a cast with no swing running waits for one, when the bar has not
-- seen a swing of its own yet.
SW.IDLE_WAIT = 3
-- a timer lands just after the plain end it waits for
local LATE = 0.05
local armed, castArmed = false, false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Hand(rec)
    return (rec.driver and rec.driver.swingType) or 0
end

local function Default()
    return (NS.Schema and NS.Schema.SWING_COLOR_DEFAULT) or { 1, 0.55, 0.15, 1 }
end

-- The rules of a swing bar whose switch is on, else nil.
function SW.RulesOf(rec)
    if rec.barKind ~= "swing" or K.R(rec, "abilcolors", "abilColorsOn") ~= true then return nil end
    local list = rec.driver and rec.driver.swingColors
    if type(list) ~= "table" or #list == 0 then return nil end
    return list
end

-- The rank the player knows, found by the spell's name, then its override:
-- the one resolve, as the next-swing markers read it.
local function Resolve(id)
    return NS.Store.TrackedSpellID(id, true, false) or id
end

local function ColorOf(c)
    local d = Default()
    if type(c) ~= "table" then c = d end
    return { tonumber(c[1]) or d[1], tonumber(c[2]) or d[2], tonumber(c[3]) or d[3], tonumber(c[4]) or 1 }
end

-- Each rule with the rank to ask about while queued and the name a cast of
-- any rank reports. A rule with no spell yet takes part in nothing.
local function Build(h, list)
    local rules, names, typed, anyCast = {}, {}, false, false
    local CS = C_Spell
    for _, r in ipairs(list) do
        if type(r) == "table" then
            local rr = { when = (r.when == "cast") and "cast" or "queued", color = ColorOf(r.color) }
            local id = tonumber(r.id)
            if id and id > 0 then
                typed = true
                rr.id, rr.eff = id, Resolve(id)
                -- queued at any rank the player knows (a down-ranked cast too)
                local SA = Bars.SwingAbil
                rr.qids = (SA and SA.QueueIDs) and SA.QueueIDs(id, 0) or { rr.eff }
                local nm = CS and CS.GetSpellName and CS.GetSpellName(id) -- raw-id: the typed spell's name keys its rule
                if not IsSecret(nm) and type(nm) == "string" and nm ~= "" then rr.name = nm end
                if rr.when == "cast" then
                    anyCast = true
                    if rr.name then names[rr.name] = true end
                end
            end
            rules[#rules + 1] = rr
        end
    end
    h.rules, h.names, h.typed, h.anyCast = rules, names, typed, anyCast
end

-- The plain answer, or the last one when the game hands back a secret.
local function Queued(h, sid)
    local CS = C_Spell
    if not (sid and CS and CS.IsCurrentSpell) then return false end
    local v = CS.IsCurrentSpell(sid) -- raw-id: the spellbook's ranks of a typed ability
    if IsSecret(v) then return h.queued[sid] == true end
    v = (v == true)
    h.queued[sid] = v
    return v
end

-- Queued at any of a rule's ranks.
local function AnyQueued(h, r)
    for _, q in ipairs(r.qids or { r.eff }) do
        if Queued(h, q) then return true end
    end
    return false
end

-- The first rule that holds wins: the list order is the priority.
local function Pick(h)
    for _, r in ipairs(h.rules) do
        if r.when == "queued" then
            if AnyQueued(h, r) then return r.color end
        elseif r.name and h.cast[r.name] then
            return r.color
        end
    end
    return nil
end

-- One write when the colour changes; the hook holds it through every later
-- write. Back to the fill colour when no rule holds: the threshold loop
-- repaints its band on its next tick.
local function Paint(e, h, col)
    if col == h.color then return end
    h.color = col
    local fill = e.shell.fill
    h.busy = true
    if col then
        fill:SetStatusBarColor(col[1], col[2], col[3], col[4])
    else
        fill:SetStatusBarColor(K.BarColorOf(e.rec))
    end
    h.busy = false
end

local function Apply(e, h)
    Paint(e, h, Pick(h))
end

-- Every other write to the colour (a swing's start, the threshold loop, the
-- idle look, a restyle) is followed by the rule's in the same call, so no
-- other colour reaches the screen while a rule holds. busy stops the re-entry.
local function Guard(h, bar)
    hooksecurefunc(bar, "SetStatusBarColor", function(self)
        local col = h.color
        if not col or h.busy then return end
        h.busy = true
        self:SetStatusBarColor(col[1], col[2], col[3], col[4])
        h.busy = false
    end)
end

-- A hook cannot be removed, so each stays for its frame's life and does
-- nothing while no rule holds.
local function Hook(shell, h)
    if not h.hooked then
        h.hooked = true
        Guard(h, shell.fill)
    end
    -- The closing fill's mirror half copies the fill through its own hook,
    -- which can run after ours: it keeps the rule's colour the same way.
    local c = shell._adSWC
    if c and c.bar and h.mirror ~= c.bar then
        h.mirror = c.bar
        Guard(h, c.bar)
    end
end

local function Clear(h)
    h.phase = nil
    h.cast = {}
    h.gen = h.gen + 1
end

-- One timer per state, at a plain end time: it clears the cast colours
-- unless something newer moved the generation on, so none outlives its swing.
local function Arm(e, h, delay)
    h.gen = h.gen + 1
    local gen = h.gen
    C_Timer.After(math.max(0, delay) + LATE, function()
        if h.gen ~= gen then return end
        Clear(h)
        if h.on and e.acol == h then Apply(e, h) end
    end)
end

-- A cast colours the swing running now until it lands. With none running it
-- colours the next one, which gets one swing length to start.
local function Cast(e, h, name, now)
    local _, _, sEnd = K.SwingClock(e)
    -- the swing the earlier casts belonged to has landed
    if not sEnd and h.phase == "swing" then h.cast = {} end
    h.cast[name] = true
    h.castAt = now
    if sEnd then
        h.phase = "swing"
        Arm(e, h, sEnd - now)
    else
        h.phase = "next"
        Arm(e, h, (e.swingLen or SW.IDLE_WAIT) + SW.GRACE)
    end
end

local function OnSwing(_, duration, swingType)
    if IsSecret(duration) or IsSecret(swingType) then return end
    if type(duration) ~= "number" or duration <= 0 then return end
    local now = GetTime()
    K.ForEach("swing", function(e)
        local h = e.acol
        if not (h and h.on) or Hand(e.rec) ~= swingType then return end
        if h.phase == "next" or (h.phase == "swing" and now - (h.castAt or 0) <= SW.GRACE) then
            -- the cast's own swing: it holds until this one lands
            h.phase = "swing"
            Arm(e, h, duration)
        elseif h.phase == "swing" then
            Clear(h)
        end
        Apply(e, h)
    end)
end

-- A cast counts for every cast rule the one matcher pairs it with (any rank
-- by name, an override form too); a rule is keyed by its spell's name.
local function OnCast(_, _, unit, _, spellID)
    if IsSecret(unit) or IsSecret(spellID) or unit ~= "player" or type(spellID) ~= "number" then return end
    local St = NS.Store
    local now = GetTime()
    K.ForEach("swing", function(e)
        local h = e.acol
        if not (h and h.on) then return end
        local hit = false
        for _, r in ipairs(h.rules) do
            if r.when == "cast" and r.name and St.SpellMatch(r.id, spellID, r.eff, true) then
                if hit then h.cast[r.name] = true else Cast(e, h, r.name, now) end
                hit = true
            end
        end
        -- a queued ability that went off is no longer current
        Apply(e, h)
    end)
end

local function OnQueue()
    K.ForEach("swing", function(e)
        local h = e.acol
        if h and h.on then Apply(e, h) end
    end)
end

-- A learned rank is a new spell ID.
local function OnSpells()
    Events.Coalesce(KEY .. "_spells", function()
        local SA = Bars.SwingAbil
        if SA and SA.ForgetRanks then SA.ForgetRanks() end
        K.ForEach("swing", function(e)
            local h = e.acol
            local list = h and h.on and SW.RulesOf(e.rec)
            if list then
                Build(h, list)
                Apply(e, h)
            end
        end)
    end)
end

-- Its own frame: the client passes on the player's casts only, before any
-- Lua runs.
local function CastEvents(on)
    if on == castArmed then return end
    castArmed = on
    local f = SW.castFrame
    if on and not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", OnCast)
        SW.castFrame = f
    end
    if not f then return end
    if not on then
        f:UnregisterAllEvents()
    elseif not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(CAST_EVENT) then
        f:RegisterUnitEvent(CAST_EVENT, "player")
    end
end

-- Listening only while a live bar has the switch on and a rule with a spell;
-- the player's casts only while one of those rules waits for a cast.
function SW.SyncEvents()
    local want, wantCast = false, false
    if C_SwingTimer and Events then
        K.ForEach("swing", function(e)
            local h = e.acol
            if h and h.on then
                want = true
                if h.anyCast then wantCast = true end
            end
        end)
    end
    CastEvents(wantCast)
    if want == armed then return end
    armed = want
    if want then
        Events.On("PLAYER_SWING", KEY, OnSwing)
        K.SafeOn("CURRENT_SPELL_CAST_CHANGED", KEY, OnQueue)
        Events.On("SPELLS_CHANGED", KEY, OnSpells)
    else
        for _, ev in ipairs(EVENTS) do Events.Off(ev, KEY) end
    end
end

local function Stop(e, h)
    h.on = false
    h.gen = h.gen + 1
    h.phase, h.cast, h.queued = nil, {}, {}
    Paint(e, h, nil)
end

-- The state lives on the shell, whose fill carries the hook for its life.
local function Ensure(shell)
    local h = shell._adACol
    if h then return h end
    h = { gen = 0, cast = {}, queued = {}, rules = {}, names = {} }
    shell._adACol = h
    return h
end

-- Called at the end of every style pass, after the other swing passes, so the
-- closing fill's mirror exists by then.
function SW.Styled(e)
    local shell = e.shell
    local list = SW.RulesOf(e.rec)
    local h = shell._adACol
    if not list then
        if h then Stop(e, h) end
        e.acol = nil
        SW.SyncEvents()
        return
    end
    h = Ensure(shell)
    e.acol = h
    Hook(shell, h)
    Build(h, list)
    if e.isPreview then
        -- no events on a preview: the first rule's colour, to style the look
        h.on = false
        local first = h.rules[1]
        Paint(e, h, first and first.color)
    else
        h.on = h.typed
        if h.on then Apply(e, h) else Stop(e, h) end
    end
    SW.SyncEvents()
end

function SW.Release(e)
    if e.acol then Stop(e, e.acol) end
    e.acol = nil
    SW.SyncEvents()
end

-- Editing the bar's own list (rec.driver.swingColors): an edit that changes
-- nothing is skipped, any other marks the bar for one style refresh.
function SW.MaxRules()
    return (NS.Schema and NS.Schema.SWING_COLOR_MAX) or 8
end

function SW.List(rec)
    local l = rec and rec.driver and rec.driver.swingColors
    return type(l) == "table" and l or {}
end

local function Changed(rec)
    if NS.Store and NS.Store.Dirty then NS.Store.Dirty("style", rec.id) end
end

function SW.AddRule(rec)
    rec.driver = rec.driver or {}
    local l = rec.driver.swingColors
    if type(l) ~= "table" then l = {} end
    if #l >= SW.MaxRules() then return false end
    local d = Default()
    l[#l + 1] = { when = "queued", color = { d[1], d[2], d[3], d[4] or 1 } }
    rec.driver.swingColors = l
    Changed(rec)
    return true
end

function SW.RemoveRule(rec, i)
    local l = SW.List(rec)
    if not l[i] then return false end
    table.remove(l, i)
    if #l == 0 then rec.driver.swingColors = nil end
    Changed(rec)
    return true
end

-- delta -1 = one place up (higher priority), 1 = one down.
function SW.MoveRule(rec, i, delta)
    local l = SW.List(rec)
    local j = i + delta
    if not (l[i] and l[j]) then return false end
    l[i], l[j] = l[j], l[i]
    Changed(rec)
    return true
end

-- key "id": a spell ID (nil clears it); "when": "queued" or "cast"; "color":
-- { r, g, b, a } from the picker's opacity slider; one without an a keeps the
-- rule's own, and an opacity-only change is an edit.
function SW.SetRule(rec, i, key, v)
    local r = SW.List(rec)[i]
    if not r then return false end
    if key == "id" then
        v = tonumber(v)
        v = (v and v > 0) and math.floor(v) or nil
        if r.id == v then return false end
        r.id = v
    elseif key == "when" then
        if (v ~= "queued" and v ~= "cast") or r.when == v then return false end
        r.when = v
    elseif key == "color" then
        if type(v) ~= "table" then return false end
        local old = type(r.color) == "table" and r.color or {}
        local oa = tonumber(old[4]) or 1
        local c = { tonumber(v[1]) or 1, tonumber(v[2]) or 1, tonumber(v[3]) or 1, tonumber(v[4]) or oa }
        if old[1] == c[1] and old[2] == c[2] and old[3] == c[3] and oa == c[4] then return false end
        r.color = c
    else
        return false
    end
    Changed(rec)
    return true
end
