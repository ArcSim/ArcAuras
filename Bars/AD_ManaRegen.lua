-- AD_ManaRegen: the five-second rule and the regen ticks on mana resource bars.
-- Owns the rule's clock, the tick grid and each bar's sparks, countdown, incoming mana and sound; the bars runtime calls in through Bars.ManaRegen when it styles or releases a resource bar.
-- Mana reads secret, so nothing reads it: a spend is your own costly cast confirmed by a mana event beside it, a tick is a mana event on the 2 s grid away from your casts, and the next tick's mana is GetManaRegen fed unread into a bar.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.WHITE and K.R and Bars.StripPx) then return end

local MR = {}
Bars.ManaRegen = MR

MR.RULE = 5           -- seconds spirit regen waits after mana is spent
MR.CONFIRM = 0.5      -- a mana event this close to a costly cast is its spend
MR.SPEND = 0.5        -- a mana event this soon after any cast of yours is its cost or its gain
MR.TICK = 2           -- the server's regen period
MR.GRID_SLOP = 0.3    -- how far off the 2 s grid a regen event may land and still count
MR.PHASE_KEEP = 10    -- a tick this recent still dates the grid
MR.LIVE_SLOP = 0.5    -- the tick visuals wait this long past a due tick, then stop
MR.FLASH = 0.35       -- the landing flash's fade
MR.DEMO_EVERY = 6.5   -- the rule's editing sample restarts this often
MR.STEP = 0.05        -- the countdown's step while a sweep runs
MR.MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
MR.COLOR = { 1, 0.82, 0.25, 0.95 }
MR.TICK_COLOR = { 0.9, 0.95, 1, 0.9 }
MR.IN_COLOR = { 0.52, 0.72, 0.92, 0.85 }

MR.entries = {}       -- [entry] = true while a mana bar wants the rule or the ticks
MR.gen = 0            -- bumped by every new spend, so a stale end does nothing
MR.tickGen = 0        -- bumped by every tick window, so a stale check does nothing

-- A plain number, or nil for a secret or missing one.
function MR.Num(v)
    if v == nil or (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then return nil end
    return v
end

-- Set up for the rule or the ticks: a resource bar on mana, or on the display
-- power, which is mana in caster form.
function MR.Configured(e)
    if not (e and e.kind == "resource" and e.rec) then return false end
    if not ((K.R(e.rec, "regen", "fsrOn") == true) or (K.R(e.rec, "regen", "tickSpark") == true) or (K.R(e.rec, "regen", "incoming") == true)) then return false end
    local d = e.rec.driver
    local pt = d and tonumber(d.powerType)
    return pt == nil or pt < 0 or pt == MR.MANA
end

-- Showing mana right now; a form swap moves a display-power bar off it.
function MR.Wanted(e)
    return MR.Configured(e) and e.powerType == MR.MANA
end

-- Does this spell spend mana? Spell costs are plain; a cost that needs an aura
-- the player lacks does not apply.
function MR.CostsMana(spellID)
    if not (MR.Num(spellID) and C_Spell and C_Spell.GetSpellPowerCost) then return false end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return false end
    for _, c in ipairs(costs) do
        local needs = MR.Num(c.requiredAuraID)
        local skip = needs ~= nil and needs ~= 0 and c.hasRequiredAura == false
        if not skip and MR.Num(c.type) == MR.MANA then
            if (MR.Num(c.cost) or 0) > 0 or (MR.Num(c.costPercent) or 0) > 0
                or (MR.Num(c.costPerSec) or 0) > 0 then
                return true
            end
        end
    end
    return false
end

-- Events

-- Listens only while a mana bar wants the rule or the ticks, and only to the
-- player; the frame is made the first time one does.
function MR.Arm()
    local f = MR.frame
    if next(MR.entries) then
        if MR.armed then return end
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(_, event, ...) MR.OnEvent(event, ...) end)
            MR.frame = f
        end
        MR.armed = true
        MR.inCombat = InCombatLockdown() and true or false
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif MR.armed then
        MR.armed = false
        f:UnregisterAllEvents()
        MR.pending, MR.lastPower, MR.lastCast = nil, nil, nil
    end
end

function MR.OnEvent(event, unit, a2, a3)
    local now = GetTime()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        MR.lastCast = now
        if not MR.CostsMana(a3) then return end
        if MR.lastPower and now - MR.lastPower <= MR.CONFIRM then
            MR.pending = nil
            MR.Begin(now)
        else
            MR.pending = now
        end
    elseif event == "UNIT_POWER_UPDATE" then
        if unit ~= "player" then return end
        -- a secret token could still be mana: only a plain other one is skipped
        local token = a2
        if not (issecretvalue and issecretvalue(token)) and token ~= "MANA" then return end
        MR.lastPower = now
        if MR.pending and now - MR.pending <= MR.CONFIRM then
            local at = MR.pending
            MR.pending = nil
            MR.Begin(at)
        end
        if not (MR.lastCast and now - MR.lastCast <= MR.SPEND) then MR.OnTick(now) end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        MR.inCombat = event == "PLAYER_REGEN_DISABLED"
        MR.ShowAll()
    elseif event == "UNIT_DISPLAYPOWER" then
        -- a druid's form swap can move a bar that follows the display power off mana
        C_Timer.After(0, MR.ShowAll)
    end
end

-- The rule's clock

function MR.Begin(at)
    MR.start, MR.stop = at, at + MR.RULE
    MR.gen = MR.gen + 1
    local gen = MR.gen
    C_Timer.After(math.max(0, MR.stop - GetTime()) + 0.01, function() MR.End(gen) end)
    MR.ShowAll()
end

-- The bars whose rule a finished window ends: shown and set to sound.
function MR.EndSounds()
    local out = {}
    for e in pairs(MR.entries) do
        if MR.RuleMode(e, true) == "rule" then
            local s = K.R(e.rec, "regen", "fsrSound")
            if type(s) == "string" and s ~= "" then out[s] = true end
        end
    end
    return out
end

function MR.End(gen)
    if gen ~= MR.gen or not MR.stop then return end
    local sounds = MR.EndSounds()
    MR.start, MR.stop = nil, nil
    -- regen is back: the incoming mana grows toward the next tick on the grid
    local nextAt = MR.NextTick(GetTime())
    if nextAt and MR.AnyTicks() then MR.TickWindow(nextAt - MR.TICK, nextAt) end
    MR.ShowAll()
    local S = NS.Sounds
    if S and S.Play then
        for s in pairs(sounds) do S.Play(s) end
    end
end

-- What a bar's rule shows now: "demo" while editing, "rule" while the window
-- runs, else nil. atEnd asks about the window that is just closing.
function MR.RuleMode(e, atEnd)
    if not (MR.Wanted(e) and (K.R(e.rec, "regen", "fsrOn") == true)) then return nil end
    -- the preview pane lives only while the options are open
    if K.IsEditMode() then return "demo" end
    if e.isPreview then return nil end
    if not MR.stop or (not atEnd and GetTime() >= MR.stop) then return nil end
    if K.R(e.rec, "regen", "fsrShow") == "ooc" and MR.inCombat then return nil end
    return "rule"
end

-- Is the rule's spark crossing this bar right now?
function MR.RuleShowing(e)
    local mode = MR.RuleMode(e)
    if mode == "demo" then return MR.demoFrom ~= nil and GetTime() < MR.demoFrom + MR.RULE end
    return mode == "rule"
end

-- The tick grid

-- The next tick on the grid after now, while a recent tick dates it.
function MR.NextTick(now)
    local last = MR.lastTick
    if not (last and now - last < MR.PHASE_KEEP) then return nil end
    local n = last + MR.TICK * math.ceil((now - last) / MR.TICK)
    if n <= now then n = n + MR.TICK end
    return n
end

-- A mana event away from your casts: a regen tick when it lands on the grid,
-- or starts one when no recent tick dates it. Off the grid (a sync as combat
-- ends, a drink's gain) it is ignored.
function MR.OnTick(now)
    local last = MR.lastTick
    if last and now - last < MR.PHASE_KEEP then
        local k = math.floor((now - last) / MR.TICK + 0.5)
        if k < 1 or math.abs(now - (last + k * MR.TICK)) > MR.GRID_SLOP then return end
    end
    MR.lastTick = now
    if not MR.AnyTicks() then return end
    MR.TickWindow(now, now + MR.TICK)
    for e in pairs(MR.entries) do
        if MR.TickMode(e) == "live" then MR.Flash(e) end
    end
end

-- Does any bar show the ticks? The grid is kept either way: the rule's end
-- reads it.
function MR.AnyTicks()
    for e in pairs(MR.entries) do
        if (K.R(e.rec, "regen", "tickSpark") == true) or (K.R(e.rec, "regen", "incoming") == true) then return true end
    end
    return false
end

-- The window the tick visuals run over, up to the tick due at `to`; a check
-- after it hides them when no tick came (full mana, the rule).
function MR.TickWindow(from, to)
    MR.tickFrom, MR.tickTo = from, to
    MR.tickGen = MR.tickGen + 1
    local gen = MR.tickGen
    C_Timer.After(math.max(0, to + MR.LIVE_SLOP - GetTime()) + 0.01, function()
        if gen == MR.tickGen then MR.ShowAll() end
    end)
    MR.ShowAll()
end

-- What a bar's ticks show now: "demo" while editing, "live" while a window
-- runs, else nil.
function MR.TickMode(e)
    if not (MR.Wanted(e) and ((K.R(e.rec, "regen", "tickSpark") == true) or (K.R(e.rec, "regen", "incoming") == true))) then return nil end
    if K.IsEditMode() then return "demo" end
    if e.isPreview then return nil end
    if MR.tickTo and GetTime() <= MR.tickTo + MR.LIVE_SLOP then return "live" end
    return nil
end

-- One bar's widgets

-- Across the whole track, n pixels thick on its moving edge, as the timer
-- bars' spark sits.
function MR.PlaceSpark(sp, shell, ft, vertical, reverse, n, c)
    local a = Bars.StripPx(shell, math.floor(n / 2))
    local b = Bars.StripPx(shell, n - math.floor(n / 2))
    sp:ClearAllPoints()
    if vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        sp:SetPoint("TOPLEFT", ft, edge .. "LEFT", 0, a)
        sp:SetPoint("BOTTOMRIGHT", ft, edge .. "RIGHT", 0, -b)
    else
        local edge = reverse and "LEFT" or "RIGHT"
        sp:SetPoint("TOPLEFT", ft, "TOP" .. edge, -a, 0)
        sp:SetPoint("BOTTOMRIGHT", ft, "BOTTOM" .. edge, b, 0)
    end
    sp:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- A clear track laid over the fill, which the game moves from a plain duration.
function MR.NewTrack(shell)
    local track = CreateFrame("StatusBar", nil, shell)
    track:SetAllPoints(shell.fill)
    track:SetStatusBarTexture(K.WHITE)
    track:GetStatusBarTexture():SetAlpha(0)
    track:SetMinMaxValues(0, 1)
    track:SetValue(0)
    return track
end

function MR.NewSpark(shell)
    -- on the text host: over the fill and the incoming mana, under the texts
    local sp = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 4)
    sp:SetTexture(K.WHITE)
    sp:SetBlendMode("ADD")
    sp:Hide()
    return sp
end

function MR.Ensure(e)
    local shell = e.shell
    local v = shell._adFsr
    if v then return v end
    v = { track = MR.NewTrack(shell), spark = MR.NewSpark(shell), text = shell.overlay:CreateFontString(nil, "OVERLAY"),
        ttrack = MR.NewTrack(shell), tspark = MR.NewSpark(shell) }
    v.text:Hide()
    -- the incoming mana and its landing flash, clipped to the bar so a full
    -- bar pushes them out of sight
    local clip = CreateFrame("Frame", nil, shell)
    clip:SetAllPoints(shell.fill)
    -- over a colour rule's layers (Bars\AD_ResColors.lua)
    clip:SetFrameLevel(shell.fill:GetFrameLevel() + Bars.LADDER.fillMarks)
    clip:SetClipsChildren(true)
    v.clip = clip
    v.ghost = CreateFrame("StatusBar", nil, clip)
    v.ghost:SetStatusBarTexture(K.WHITE)
    v.ghost:Hide()
    v.ramp = v.ghost:CreateAnimationGroup()
    v.rampA = v.ramp:CreateAnimation("Alpha")
    v.ramp:SetToFinalAlpha(true)
    v.flash = CreateFrame("StatusBar", nil, clip)
    v.flash:SetStatusBarTexture(K.WHITE)
    v.flash:SetAlpha(0)
    v.flashAG = v.flash:CreateAnimationGroup()
    local fa = v.flashAG:CreateAnimation("Alpha")
    fa:SetFromAlpha(0.9)
    fa:SetToAlpha(0)
    fa:SetDuration(MR.FLASH)
    v.flashAG:SetToFinalAlpha(true)
    shell._adFsr = v
    return v
end

-- The incoming mana past the fill's moving edge, a whole bar long and filling
-- away from it; the flash from the same edge back into the fill. Their range
-- is half the pool, so GetManaRegen's per-second figure draws one 2 s tick.
function MR.LayoutGhost(e, v, vertical, reverse)
    local shell = e.shell
    local ft = shell.fillTex or shell.fill:GetStatusBarTexture()
    local w = MR.Num(shell.fill:GetWidth()) or 0
    local h = MR.Num(shell.fill:GetHeight()) or 0
    -- a bar not laid out yet has no size: once more a frame later
    if (w <= 1 or h <= 1) and (v.layoutTries or 0) < 3 then
        v.layoutTries = (v.layoutTries or 0) + 1
        C_Timer.After(0, function()
            if shell._adFsr == v then MR.LayoutGhost(e, v, vertical, reverse) end
        end)
    elseif w > 1 and h > 1 then
        v.layoutTries = 0
    end
    local g, f = v.ghost, v.flash
    g:ClearAllPoints()
    f:ClearAllPoints()
    g:SetSize(math.max(1, w), math.max(1, h))
    f:SetSize(math.max(1, w), math.max(1, h))
    g:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    f:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    if vertical then
        if reverse then
            g:SetPoint("TOP", ft, "BOTTOM")
            f:SetPoint("BOTTOM", ft, "BOTTOM")
        else
            g:SetPoint("BOTTOM", ft, "TOP")
            f:SetPoint("TOP", ft, "TOP")
        end
    else
        if reverse then
            g:SetPoint("RIGHT", ft, "LEFT")
            f:SetPoint("LEFT", ft, "LEFT")
        else
            g:SetPoint("LEFT", ft, "RIGHT")
            f:SetPoint("RIGHT", ft, "RIGHT")
        end
    end
    g:SetReverseFill(reverse)
    f:SetReverseFill(not reverse)
end

-- Orientation, sparks, countdown and incoming mana from the record; restarts
-- nothing but the feeds.
function MR.Look(e, v)
    local rec, shell = e.rec, e.shell
    local vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local reverse = K.R(rec, "fill", "reverseFill") == true
    for _, tr in ipairs({ v.track, v.ttrack }) do
        tr:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        tr:SetReverseFill(reverse)
    end
    v.drain = (K.R(rec, "regen", "fsrDir") or "down") == "down"
    local c = K.R(rec, "regen", "fsrColor")
    if type(c) ~= "table" then c = MR.COLOR end
    local n = math.max(1, math.floor(tonumber(K.R(rec, "regen", "fsrWidth")) or 2))
    MR.PlaceSpark(v.spark, shell, v.track:GetStatusBarTexture(), vertical, reverse, n, c)
    local tc = K.R(rec, "regen", "tickSparkColor")
    if type(tc) ~= "table" then tc = MR.TICK_COLOR end
    local tn = math.max(1, math.floor(tonumber(K.R(rec, "regen", "tickSparkWidth")) or 2))
    MR.PlaceSpark(v.tspark, shell, v.ttrack:GetStatusBarTexture(), vertical, reverse, tn, tc)
    v.textOn = (K.R(e.rec, "regen", "fsrText") == true)
    local t = v.text
    local pos = K.R(rec, "regen", "fsrTextPos") or "right"
    local size = math.floor(tonumber(K.R(rec, "regen", "fsrTextSize")) or 11)
    if K.StyleFont then K.StyleFont(t, e, "fsr", size, "OUTLINE", false) end
    t:ClearAllPoints()
    if pos == "left" then
        t:SetPoint("LEFT", shell.fill, "LEFT", 4, 0)
    elseif pos == "center" then
        t:SetPoint("CENTER", shell.fill, "CENTER", 0, 0)
    else
        t:SetPoint("RIGHT", shell.fill, "RIGHT", -4, 0)
    end
    t:SetTextColor(c[1], c[2], c[3], 1)
    MR.LayoutGhost(e, v, vertical, reverse)
    local ic = K.R(rec, "regen", "incomingColor")
    if type(ic) ~= "table" then ic = MR.IN_COLOR end
    v.ghost:SetStatusBarColor(ic[1], ic[2], ic[3], ic[4] or 1)
    v.flash:SetStatusBarColor(ic[1], ic[2], ic[3], 1)
    -- a new look restarts the feeds, as a track's direction may differ
    v.fedFrom, v.tFed, v.rampTo = nil, nil, nil
end

-- Feeds a track one sweep from a plain start: engine driven where the client
-- has the timer feed, else the countdown ticker steps it (stepped = true).
function MR.FeedTrack(track, from, len, drain)
    local d = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()
    if d and d.SetTimeFromStart then d:SetTimeFromStart(from, len) end
    if d and K.FeedStatusBarTimer and K.FeedStatusBarTimer(track, d, false, drain) then return false end
    track:SetMinMaxValues(0, len)
    return true
end

function MR.Feed(v, from)
    if v.fedFrom == from then return end
    v.fedFrom = from
    v.stepped = MR.FeedTrack(v.track, from, MR.RULE, v.drain)
    if v.stepped then MR.Step(v, GetTime()) end
end

function MR.Step(v, now)
    local left = math.max(0, math.min(MR.RULE, (v.fedFrom or now) + MR.RULE - now))
    v.track:SetValue(v.drain and left or (MR.RULE - left))
end

function MR.FeedTick(v, start)
    if v.tFed == start then return end
    v.tFed = start
    v.tStepped = MR.FeedTrack(v.ttrack, start, MR.TICK, false)
    if v.tStepped then MR.StepTick(v, GetTime()) end
end

function MR.StepTick(v, now)
    v.ttrack:SetValue(math.max(0, math.min(MR.TICK, now - (v.tFed or now))))
end

function MR.Hide(v)
    v.spark:Hide()
    v.text:Hide()
    v.fedFrom = nil
    v.from = nil
end

function MR.HideTicks(v)
    v.tspark:Hide()
    v.ghost:Hide()
    v.tFed, v.rampTo, v.tStepped = nil, nil, nil
end

-- Paints one bar's rule for what it shows now.
function MR.Show(e)
    local v = e.shell and e.shell._adFsr
    if not v then return end
    local mode = MR.RuleMode(e)
    if not mode then
        MR.Hide(v)
        return
    end
    local from = (mode == "demo") and MR.demoFrom or MR.start
    if not from or GetTime() >= from + MR.RULE then
        MR.Hide(v)
        return
    end
    v.from = from
    MR.Feed(v, from)
    v.spark:Show()
    MR.Text(v, GetTime())
end

-- The incoming mana's amount: regen while casting inside the rule, else the
-- full regen; both can read secret and go straight into the bars.
function MR.GhostFeed(e, v, mode)
    if not GetManaRegen then return false end
    local max = MR.Num(e.lastMax) or MR.Num(UnitPowerMax("player", MR.MANA))
    if not max or max <= 0 then return false end
    local base, casting = GetManaRegen()
    local val
    if mode == "live" and MR.stop and GetTime() < MR.stop then val = casting else val = base end
    if val == nil then return false end
    v.ghost:SetMinMaxValues(0, max / MR.TICK)
    v.flash:SetMinMaxValues(0, max / MR.TICK)
    v.ghost:SetValue(val)
    v.flash:SetValue(val)
    return true
end

-- The incoming mana brightens toward the tick due at `to`, from where the
-- window stands now; restarted only for a new window.
function MR.Ramp(v, now, to)
    if v.rampTo == to then return end
    v.rampTo = to
    local left = math.max(0.05, to - now)
    local p = 1 - math.min(1, left / MR.TICK)
    v.ramp:Stop()
    v.rampA:SetFromAlpha(0.15 + 0.85 * p)
    v.rampA:SetToAlpha(1)
    v.rampA:SetDuration(left)
    v.ramp:Play()
end

function MR.Flash(e)
    local v = e.shell and e.shell._adFsr
    if not (v and (K.R(e.rec, "regen", "incoming") == true) and (K.R(e.rec, "regen", "incomingFlash") == true) and v.ghost:IsShown()) then return end
    v.flashAG:Stop()
    v.flashAG:Play()
end

-- Paints one bar's ticks for what they show now.
function MR.ShowTicks(e)
    local v = e.shell and e.shell._adFsr
    if not v then return end
    local mode = MR.TickMode(e)
    local now = GetTime()
    local to = (mode == "demo") and MR.dtTo or MR.tickTo
    if not mode or not to or now > to + MR.LIVE_SLOP then
        MR.HideTicks(v)
        return
    end
    if (K.R(e.rec, "regen", "tickSpark") == true) and not MR.RuleShowing(e) then
        MR.FeedTick(v, to - MR.TICK)
        v.tspark:Show()
    else
        v.tspark:Hide()
        v.tFed = nil
    end
    if (K.R(e.rec, "regen", "incoming") == true) and MR.GhostFeed(e, v, mode) then
        v.ghost:Show()
        MR.Ramp(v, now, to)
    else
        v.ghost:Hide()
        v.rampTo = nil
    end
end

function MR.Text(v, now)
    local left = (v.from or now) + MR.RULE - now
    if not v.textOn or left <= 0 then
        v.text:Hide()
        return
    end
    v.text:SetText(("%.1f"):format(left))
    v.text:Show()
end

-- Every bar, then the ticker and the editing samples as they are needed.
function MR.ShowAll()
    local demo, tdemo = false, false
    for e in pairs(MR.entries) do
        if MR.RuleMode(e) == "demo" then demo = true end
        if MR.TickMode(e) == "demo" then tdemo = true end
    end
    if demo and not MR.demoTicker then
        MR.DemoStart()
    elseif not demo and MR.demoTicker then
        MR.demoTicker:Cancel()
        MR.demoTicker, MR.demoFrom = nil, nil
    end
    if tdemo and not MR.tickDemo then
        MR.TickDemoStart()
    elseif not tdemo and MR.tickDemo then
        MR.tickDemo:Cancel()
        MR.tickDemo, MR.dtTo = nil, nil
    end
    for e in pairs(MR.entries) do
        MR.Show(e)
        MR.ShowTicks(e)
    end
    MR.SyncTicker()
end

-- The countdown ticker: only while a shown bar counts down in text or steps
-- a track by hand.
function MR.SyncTicker()
    local need = false
    local now = GetTime()
    for e in pairs(MR.entries) do
        local v = e.shell and e.shell._adFsr
        if v then
            if v.from and now < v.from + MR.RULE and (v.textOn or v.stepped) then need = true end
            if v.tStepped and v.tFed and now < v.tFed + MR.TICK then need = true end
        end
    end
    if need and not MR.ticker then
        MR.ticker = C_Timer.NewTicker(MR.STEP, MR.Tick)
    elseif not need and MR.ticker then
        MR.ticker:Cancel()
        MR.ticker = nil
    end
end

function MR.Tick()
    local now = GetTime()
    for e in pairs(MR.entries) do
        local v = e.shell and e.shell._adFsr
        if v and v.from then
            if v.stepped then MR.Step(v, now) end
            MR.Text(v, now)
            if now >= v.from + MR.RULE then v.spark:Hide() end
        end
        if v and v.tStepped and v.tFed then MR.StepTick(v, now) end
    end
    MR.SyncTicker()
end

-- The editing samples: while the options are open every wanted bar runs the
-- rule on a loop and ticks every 2 s, so nothing is invisible while set up.
function MR.DemoStart()
    MR.demoFrom = GetTime()
    MR.demoTicker = C_Timer.NewTicker(MR.DEMO_EVERY, MR.DemoTick)
    C_Timer.After(MR.RULE + 0.01, MR.ShowAll)
end

-- A fresh sample sweep; ShowAll ends the loop once no bar wants it.
function MR.DemoTick()
    MR.demoFrom = GetTime()
    C_Timer.After(MR.RULE + 0.01, MR.ShowAll)
    MR.ShowAll()
end

function MR.TickDemoStart()
    MR.dtTo = GetTime() + MR.TICK
    MR.tickDemo = C_Timer.NewTicker(MR.TICK, MR.TickDemoTick)
end

function MR.TickDemoTick()
    MR.dtTo = GetTime() + MR.TICK
    MR.ShowAll()
    for e in pairs(MR.entries) do
        if MR.TickMode(e) == "demo" then MR.Flash(e) end
    end
end

-- Host calls

-- At the end of every style pass of a resource bar.
function MR.Styled(e)
    if not MR.Configured(e) then
        MR.Release(e)
        return
    end
    MR.entries[e] = true
    local v = MR.Ensure(e)
    MR.Look(e, v)
    MR.Arm()
    MR.ShowAll()
end

function MR.Release(e)
    local v = e.shell and e.shell._adFsr
    if v then
        MR.Hide(v)
        MR.HideTicks(v)
    end
    if MR.entries[e] then
        MR.entries[e] = nil
        MR.Arm()
        MR.ShowAll()
    end
end
