-- AD_SwingWindup: a ranged swing bar's last half second as Auto Shot's windup, which fills only while the player stands still.
-- Owns the windup zone (its outline and overlay) and the hold while moving; the bars runtime calls in through Bars.SwingWindup when it styles or releases a swing bar.
-- PLAYER_SWING's duration, the moving events and the auto-repeat events are plain on Forever, so the windup is GetTime math with no secret reads.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.RunTimedFill and K.SwingIdle and Bars.StripPx) then return end
local Events = NS.Events

local SWU = {}
Bars.SwingWindup = SWU

local KEY = "adswingwindup"
local EVENTS = {
    "PLAYER_SWING", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
}
local RANGED = 2
-- The game's windup; the player feels about 0.6 s with latency.
SWU.WINDUP = 0.5
SWU.AUTO_SHOT = 75
-- the zone outline's alpha while the reload runs, and while the windup fills or waits
SWU.EDGE_DIM, SWU.EDGE_LIT = 0.35, 0.6
SWU.WINDUP_COLOR = { 0.95, 0.79, 0.3, 1 }
SWU.WAIT_COLOR = { 0.91, 0.34, 0.35, 1 }
local armed = false
local moving, auto = false, false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function SWU.On(rec)
    return rec.barKind == "swing" and ((rec.driver and rec.driver.swingType) or 0) == RANGED
        and K.R(rec, "fill", "swingWindup") == true
end

local function Color(rec, field, d)
    local c = K.R(rec, "fill", field)
    return (type(c) == "table") and c or d
end

-- The weapon's plain speed, for a timer restarted before a shot was seen.
-- Secret in combat on Forever: then there is none.
local function RangedSpeed()
    local s = UnitRangedDamage and UnitRangedDamage("player")
    if s == nil or IsSecret(s) or type(s) ~= "number" or s <= 0 then return nil end
    return s
end

local function NewLane(shell)
    -- spans the zone with its own texture and draws nothing
    local zh = CreateFrame("StatusBar", nil, shell)
    zh:EnableMouse(false)
    zh:SetStatusBarTexture(K.WHITE)
    zh:SetStatusBarColor(1, 1, 1, 0)
    zh:Hide()
    local zb = CreateFrame("StatusBar", nil, shell)
    zb:EnableMouse(false)
    zb:Hide()
    -- on the text host like the swing ticks, a sublevel under them
    local edges = {}
    for i = 1, 4 do
        local t = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture(K.WHITE)
        t:Hide()
        edges[i] = t
    end
    return { zh = zh, zb = zb, edges = edges }
end

-- The widgets live on the shell, which can outlive the entry that built them.
local function Ensure(shell)
    local w = shell._adSWU
    if w then return w end
    w = { lanes = { NewLane(shell), NewLane(shell) }, gen = 0 }
    shell._adSWU = w
    return w
end

local function HideLane(lane)
    lane.zh:Hide()
    lane.zb:Hide()
    for i = 1, 4 do lane.edges[i]:Hide() end
    lane.on = false
end

local SIDES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

-- A one-pixel outline inside the zone. Where two halves' zones meet in the
-- middle, the side on the centre line is left out so they read as one box.
local function PlaceEdges(lane, zt, px, skip)
    local topIn = (skip == "TOP") and 0 or px
    local botIn = (skip == "BOTTOM") and 0 or px
    for i, side in ipairs(SIDES) do
        local t = lane.edges[i]
        t:ClearAllPoints()
        if side == skip then
            t:Hide()
        else
            if side == "TOP" then
                t:SetPoint("TOPLEFT", zt, "TOPLEFT", 0, 0)
                t:SetPoint("BOTTOMRIGHT", zt, "TOPRIGHT", 0, -px)
            elseif side == "BOTTOM" then
                t:SetPoint("TOPLEFT", zt, "BOTTOMLEFT", 0, px)
                t:SetPoint("BOTTOMRIGHT", zt, "BOTTOMRIGHT", 0, 0)
            elseif side == "LEFT" then
                t:SetPoint("TOPLEFT", zt, "TOPLEFT", 0, -topIn)
                t:SetPoint("BOTTOMRIGHT", zt, "BOTTOMLEFT", px, botIn)
            else
                t:SetPoint("TOPLEFT", zt, "TOPRIGHT", -px, -topIn)
                t:SetPoint("BOTTOMRIGHT", zt, "BOTTOMRIGHT", 0, botIn)
            end
            t:Show()
        end
    end
end

-- The zone is where the host's fill stands during the windup: the far end of
-- a filling bar, the start of a draining one. The helper's texture spans it
-- at any size, so nothing is measured; the overlay fills it the fill's way.
local function PlaceLane(w, lane, host, vertical, hostReverse, skip, D, level, tex, px)
    local W = SWU.WINDUP
    local orient = vertical and "VERTICAL" or "HORIZONTAL"
    local zh, zb = lane.zh, lane.zb
    zh:ClearAllPoints()
    zh:SetAllPoints(host)
    zh:SetOrientation(orient)
    zh:SetReverseFill(hostReverse ~= (not w.drain))
    zh:SetMinMaxValues(0, D)
    zh:SetValue(W)
    zh:Show()
    local zt = zh:GetStatusBarTexture()
    zb:ClearAllPoints()
    zb:SetAllPoints(zt)
    zb:SetFrameLevel(level)
    zb:SetOrientation(orient)
    zb:SetReverseFill(hostReverse)
    if lane.tex ~= tex then
        -- a texture swap makes a new texture object
        lane.tex = tex
        zb:SetStatusBarTexture(tex)
        local t = zb:GetStatusBarTexture()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    end
    zb:SetRotatesTexture(w.rotate)
    zb:SetMinMaxValues(0, W)
    local c = w.windColor
    zb:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    PlaceEdges(lane, zt, px, skip)
    lane.on = true
end

local function PaintEdges(w, lit)
    local c = w.windColor
    local a = (c[4] or 1) * (lit and SWU.EDGE_LIT or SWU.EDGE_DIM)
    for _, lane in ipairs(w.lanes) do
        if lane.on then
            for i = 1, 4 do lane.edges[i]:SetVertexColor(c[1], c[2], c[3], a) end
        end
    end
end

local Lay

-- Every write to the main fill's value lands here. Inside the zone the
-- overlay copies the fill's part of it in the windup colour; a hold lasts
-- while the fill keeps the held value, so any restart or idle ends it.
function SWU.Track(w, v)
    local e = w.e
    if not e or type(v) ~= "number" then return end
    if w.holding and (not e.running or v ~= w.holdV) then w.holding = false end
    local D = e.duration or e.swingLen
    if D ~= w.D then
        Lay(e, w)
        return
    end
    local W = SWU.WINDUP
    local zv
    if e.running and not w.holding and D and D > W then
        if w.drain then
            if v <= W then zv = v end
        elseif v >= D - W then
            zv = v - (D - W)
        end
    end
    for _, lane in ipairs(w.lanes) do
        if lane.on then
            if zv then
                lane.zb:SetValue(zv)
                lane.zb:Show()
            else
                lane.zb:Hide()
            end
        end
    end
    local lit = w.holding or zv ~= nil
    if lit ~= w.lit then
        w.lit = lit
        PaintEdges(w, lit)
    end
end

function Lay(e, w)
    local rec, shell = e.rec, e.shell
    local D = e.duration or e.swingLen
    w.D = D
    local W = SWU.WINDUP
    local c = e.swc
    local mirror = c and c.active and c.bar
    local vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local r = K.R(rec, "fill", "reverseFill") == true
    -- the two zones meet on the centre line when each sits at its half's inner end
    local meet = mirror and ((not w.drain) ~= r)
    local level = shell.fill:GetFrameLevel() + (Bars.LADDER.windup or 2)
    local tex = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    local px = Bars.StripPx(shell, 1)
    for i, lane in ipairs(w.lanes) do
        local host = (i == 1) and shell.fill or mirror
        if D and D > W and host then
            local skip
            if meet then
                if vertical then skip = (i == 1) and "TOP" or "BOTTOM"
                else skip = (i == 1) and "RIGHT" or "LEFT" end
            end
            -- the mirror half fills the other way (Bars\AD_SwingClosing.lua)
            local hr = r
            if i == 2 then hr = not r end
            PlaceLane(w, lane, host, vertical, hr, skip, D, level, tex, px)
        else
            HideLane(lane)
        end
    end
    w.lit = nil
    SWU.Track(w, shell.fill:GetValue())
end

-- The hold keeps the colour through every other write (a restyle, the idle
-- rules of the ability colours); a rule's own colour still wins.
local function Hook(shell, w)
    if w.hooked then return end
    w.hooked = true
    local fill = shell.fill
    hooksecurefunc(fill, "SetValue", function(_, v)
        if w.on then SWU.Track(w, v) end
    end)
    hooksecurefunc(fill, "SetStatusBarColor", function(self)
        if not (w.on and w.holding) or w.busy then return end
        local ac = w.e and w.e.acol
        if ac and ac.color then return end
        w.busy = true
        local col = w.waitColor
        self:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
        w.busy = false
    end)
end

-- The reload is done and the shot waits for the player to stop: the fill
-- holds at the zone's edge in the waiting colour, with the windup's length.
local function Hold(e, w, D)
    local W = SWU.WINDUP
    if not D or D <= W then return end
    local rec, shell = e.rec, e.shell
    local fill = shell.fill
    fill:SetScript("OnUpdate", nil)
    e.duration = D
    e.running = true
    e.stateHidden = false
    K.ApplyVisibility(e)
    w.holdV = w.drain and W or (D - W)
    w.holding = true
    fill:SetMinMaxValues(0, D)
    fill:SetValue(w.holdV)
    local col = w.waitColor
    fill:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
    if Bars.Spark then Bars.Spark.Sync(e) end
    local decOn = K.R(rec, "text", "durDecimalsEnabled") == true
    local decTo = K.R(rec, "text", "durDecimalThreshold") or 10
    K.SetRunText(shell, "dur", NS.Factory.FormatCountdown(W, decOn and decTo or 0,
        K.R(rec, "text", "durAbbrev") or 0, K.BarRounding(rec) == "down"))
end

-- The windup runs from the zone's edge to the shot, on the shared fill loop.
local function StartWindup(e, w, D)
    local W = SWU.WINDUP
    if not D or D <= W then return end
    w.holding = false
    K.RunTimedFill(e, D, K.SwingIdle)
    e.endTime = GetTime() + W
    -- the loop's first frame would paint the start for one frame
    e.shell.fill:SetValue(w.drain and W or (D - W))
    w.R = GetTime()
end

local function AtReloadEnd(e, w)
    if not e.running or w.holding then return end
    -- Auto Shot off: nothing is coming, the bar rests
    if not auto then
        K.SwingIdle(e)
    elseif moving then
        Hold(e, w, e.duration)
    end
end

-- One timer per timer start, at the reload's plain end; a newer start moves
-- the generation on.
local function ArmReload(e, w, delay)
    w.gen = w.gen + 1
    local gen = w.gen
    w.R = GetTime() + math.max(0, delay)
    C_Timer.After(math.max(0, delay), function()
        if w.gen ~= gen or not w.on or w.e ~= e then return end
        AtReloadEnd(e, w)
    end)
end

local function InWindup(e, w)
    return e.running and w.R ~= nil and GetTime() >= w.R
end

local function Each(fn)
    K.ForEach("swing", function(e)
        local w = e.swu
        if w and w.on and not e.isPreview then fn(e, w) end
    end)
end

local function OnSwing(duration, swingType)
    if IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then return end
    local W = SWU.WINDUP
    if swingType == RANGED then
        -- a shot went off, so Auto Shot is on
        auto = true
        Each(function(e, w)
            if w.holding then
                w.holding = false
                e.shell.fill:SetStatusBarColor(K.BarColorOf(e.rec))
            end
            ArmReload(e, w, duration - W)
        end)
    else
        -- any melee swing starts the whole Auto Shot timer over
        Each(function(e, w)
            local D = e.swingLen or RangedSpeed()
            if not D or D <= W then return end
            w.holding = false
            K.RunTimedFill(e, D, K.SwingIdle)
            ArmReload(e, w, D - W)
        end)
    end
end

local function OnMoving(now)
    moving = now
    Each(function(e, w)
        if now then
            if auto and not w.holding and InWindup(e, w) then Hold(e, w, e.duration) end
        elseif w.holding then
            StartWindup(e, w, e.duration)
        end
    end)
end

local function OnAuto(on)
    auto = on
    Each(function(e, w)
        if not on then
            if w.holding or InWindup(e, w) then
                w.holding = false
                K.SwingIdle(e)
            end
            return
        end
        -- on during the reload: the windup comes at its end as usual
        if e.running and not w.holding and not InWindup(e, w) then return end
        -- ready, or mid-windup: a fresh windup starts now
        local D = (e.running and e.duration) or e.swingLen or RangedSpeed()
        if moving then
            if not w.holding then Hold(e, w, D) end
        else
            StartWindup(e, w, D)
        end
    end)
end

local function ReadMoving()
    local v = IsPlayerMoving and IsPlayerMoving()
    return not IsSecret(v) and v == true
end

local function ReadAuto()
    local f = C_Spell and C_Spell.IsAutoRepeatSpell
    if not f then return false end
    local v = f(SWU.AUTO_SHOT) -- raw-id: Auto Shot has one rank
    return not IsSecret(v) and v == true
end

-- The events only while a live bar shows the windup.
function SWU.SyncEvents()
    local want = false
    if C_SwingTimer and Events then
        K.ForEach("swing", function(e)
            if e.swu and e.swu.on then want = true end
        end)
    end
    if want == armed then return end
    armed = want
    if want then
        moving, auto = ReadMoving(), ReadAuto()
        Events.On("PLAYER_SWING", KEY, function(_, duration, swingType) OnSwing(duration, swingType) end)
        Events.On("PLAYER_STARTED_MOVING", KEY, function() OnMoving(true) end)
        Events.On("PLAYER_STOPPED_MOVING", KEY, function() OnMoving(false) end)
        Events.On("START_AUTOREPEAT_SPELL", KEY, function() OnAuto(true) end)
        Events.On("STOP_AUTOREPEAT_SPELL", KEY, function() OnAuto(false) end)
    else
        for _, ev in ipairs(EVENTS) do Events.Off(ev, KEY) end
    end
end

local function Stop(e, w)
    local held = w.holding and w.e == e
    w.on = false
    w.holding = false
    w.gen = w.gen + 1
    w.R, w.D, w.lit = nil, nil, nil
    for _, lane in ipairs(w.lanes) do HideLane(lane) end
    w.e = nil
    if held then K.SwingIdle(e) end
end

-- Called in every style pass, after the closing fill's, whose mirror half
-- gets a zone of its own.
function SWU.Styled(e)
    local shell, rec = e.shell, e.rec
    if not SWU.On(rec) then
        if shell._adSWU then Stop(e, shell._adSWU) end
        e.swu = nil
        SWU.SyncEvents()
        return
    end
    local w = Ensure(shell)
    w.on, w.e = true, e
    e.swu = w
    w.drain = (K.R(rec, "fill", "fillMode") or "drain") == "drain"
    w.rotate = K.R(rec, "fill", "rotateTexture") == true
    w.windColor = Color(rec, "swingWindupColor", SWU.WINDUP_COLOR)
    w.waitColor = Color(rec, "swingWaitColor", SWU.WAIT_COLOR)
    Hook(shell, w)
    Lay(e, w)
    SWU.SyncEvents()
end

function SWU.Release(e)
    if e.swu then Stop(e, e.swu) end
    e.swu = nil
    SWU.SyncEvents()
end

-- The editor's "Waiting on you": the hold, still, at the preview's own length.
function SWU.PreviewWait(e)
    local w = e.swu
    if not (w and w.on) then return end
    Hold(e, w, e.swingLen)
end
