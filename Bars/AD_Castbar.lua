-- Castbars (barKind "cast") for the player, target and focus, plugged into the
-- bars runtime through Bars.RegisterKind and Bars.Kit. A target's or focus's
-- cast is secret in combat: its duration object only feeds SetTimerDuration and
-- SetFormattedText, and "cannot be interrupted" only the *FromBoolean setters.
-- A cast of yours the game starts with no START event (Forever's Multi-Shot)
-- is drawn from its press, UNIT_SPELLCAST_SENT, for the spell's cast time.

local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R

local CB = {}
NS.Castbars = CB
CB.KEY = "adbarscast"
CB.UNITS = { player = true, target = true, focus = true }
CB.SHIELD_ATLAS = "ui-castingbar-shield"
CB.SHIELD_FILE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
-- The edit-mode sample: a name per unit and a spell for its icon.
CB.SAMPLE_NAMES = { player = "Your casts", target = "Target's casts", focus = "Focus's casts" }
CB.SAMPLE_SPELL = 133            -- Fireball
CB.PV_SPELLS = { 133, 116, 5143 } -- Fireball, Frostbolt, Arcane Missiles
CB.PV_LATENCY = 0.08             -- latency zone as a fraction of the bar
-- Seconds between ticks for the channels slower than one tick a second.
-- Rank 1 IDs; other ranks match by spell name.
CB.TICK_SLOW = {
    [1120] = 3,    -- Drain Soul
    [5740] = 2,    -- Rain of Fire
    [740] = 2,     -- Tranquility
    [12051] = 2,   -- Evocation
    [20577] = 2,   -- Cannibalize
}
-- Longer channels (Mind Control, Eagle Eye, fishing) have no ticks to mark.
CB.TICK_MAX_LEN = 15
CB.SAMPLE_TICKS = { 0.2, 0.4, 0.6, 0.8 }   -- the edit-mode sample: a five-tick channel
CB.EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
-- Your castbars also hear the press and how it went, for casts drawn from it.
CB.PLAYER_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_EMPOWER_START" }
-- A START answers a press after the round trip, so a press waits that long
-- (the connection's delay) before it is drawn; the bounds in seconds.
CB.SENT_SETTLE = 0.05
CB.SENT_SETTLE_MAX = 0.25
-- a press queued behind a cast of yours still counts this long after it
CB.SENT_QUEUED = 1
-- a cast drawn from its press ends this long past its time if nothing ends it
CB.SENT_GRACE = 1
-- the edit-mode sample's cast length: 1.2 s left at 60%
CB.SAMPLE_LEN = 3
CB.QUEUE_COLOR = { 0.35, 0.85, 1, 1 }
-- The events CastingBarMixin:SetUnit registers on the player castbar;
-- registered again to undo hiding it.
CB.BLIZZ_EVENTS = { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED" }

function CB.Unit(e)
    local d = e.rec.driver
    local u = d and d.unit
    return CB.UNITS[u] and u or "player"
end

-- A name typed in the Text block replaces the spell's name.
function CB.CustomName(rec)
    local v = R(rec, "text", "nameText")
    return type(v) == "string" and v ~= ""
end

-- A plain value, or nil when it is secret.
function CB.Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

function CB.Vertical(rec)
    return (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
end

-- The unit's cast or channel duration object, or nil. Only nil-check it:
-- it may be secret.
function CB.StillCasting(e)
    local u = e.castUnit or CB.Unit(e)
    return (UnitCastingDuration and UnitCastingDuration(u))
        or (UnitChannelDuration and UnitChannelDuration(u))
end

-- Widgets, built once per entry
function CB.Build(e)
    local shell = e.shell
    if not e.castTick then
        -- Drives the time text; its OnUpdate is set only while a cast shows.
        e.castTick = CreateFrame("Frame", nil, shell)
    end
    if not e.castSpark then
        local sp = shell.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        sp:SetTexture(K.WHITE)
        sp:SetBlendMode("ADD")
        sp:Hide()
        e.castSpark = sp
    end
    if not e.castLat then
        -- Over the fill's far end, under the texts.
        local lt = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 3)
        lt:SetTexture(K.WHITE)
        lt:Hide()
        e.castLat = lt
    end
    if not e.castQueue then
        -- the spell queue tick, over the latency zone, under the texts
        local qt = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 4)
        qt:Hide()
        e.castQueue = qt
    end
    if not e.castShield then
        local sh = shell.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CB.SHIELD_ATLAS) then
            sh:SetAtlas(CB.SHIELD_ATLAS)
        else
            sh:SetTexture(CB.SHIELD_FILE)
        end
        sh:Hide()
        e.castShield = sh
    end
    if not e.castFade then
        local ag = shell:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0)
        a:SetDuration(0.3)
        ag.alpha = a
        ag:SetScript("OnFinished", function(self)
            if e.castGen == self.gen and not e.castOn then CB.Rest(e) end
        end)
        e.castFade = ag
    end
end

-- Styling from settings
function CB.PlaceSpark(e)
    local rec, shell, sp = e.rec, e.shell, e.castSpark
    if not sp then return end
    local c = R(rec, "cast", "sparkColor") or { 1, 1, 1, 0.9 }
    sp:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    local w = K.Px(shell) * (R(rec, "cast", "sparkWidth") or 3)
    local rev = R(rec, "fill", "reverseFill") == true
    -- The fill texture's leading edge moves with the timer, so the spark follows
    -- it without per-frame Lua.
    local ft = shell.fillTex or shell.fill:GetStatusBarTexture()
    sp:ClearAllPoints()
    if CB.Vertical(rec) then
        local edge = rev and "BOTTOM" or "TOP"
        sp:SetPoint("LEFT", ft, edge .. "LEFT", 0, 0)
        sp:SetPoint("RIGHT", ft, edge .. "RIGHT", 0, 0)
        sp:SetHeight(w)
    else
        local edge = rev and "LEFT" or "RIGHT"
        sp:SetPoint("TOP", ft, "TOP" .. edge, 0, 0)
        sp:SetPoint("BOTTOM", ft, "BOTTOM" .. edge, 0, 0)
        sp:SetWidth(w)
    end
end

-- On the icon when it shows, else at the bar's start. Size 0 = from the bar's
-- thickness.
function CB.PlaceShield(e)
    local sh, shell = e.castShield, e.shell
    if not sh then return end
    local H = K.R(e.rec, "size", "height") or 20
    local W = K.R(e.rec, "size", "width") or 220
    local s = K.R(e.rec, "icon", "iconShieldSize") or 0
    if s <= 0 then s = math.max(12, math.min(H, W) * 1.6) end
    sh:ClearAllPoints()
    sh:SetSize(s, s)
    local icon = e.iconF
    if icon and icon:IsShown() then
        sh:SetPoint("CENTER", icon, "CENTER", 0, 0)
    elseif CB.Vertical(e.rec) then
        sh:SetPoint("CENTER", shell, "BOTTOM", 0, 0)
    else
        sh:SetPoint("CENTER", shell, "LEFT", 0, 0)
    end
end

function CB.Style(e)
    e.castUnit = CB.Unit(e)
    CB.PlaceSpark(e)
    CB.PlaceShield(e)
    local c = R(e.rec, "cast", "latencyColor") or { 1, 0.25, 0.2, 0.55 }
    if e.castLat then e.castLat:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

-- Painting a cast

-- The not-interruptible flag can be secret, so its colour is picked C-side
-- by SetVertexColorFromBoolean.
function CB.Paint(e)
    local rec, shell = e.rec, e.shell
    local r, g, b, a = K.BarColorOf(rec)
    if e.castChannel and R(rec, "fill", "castChannelOn") == true then
        local c = R(rec, "fill", "castChannelColor") or { 0.36, 0.85, 0.46, 1 }
        r, g, b, a = c[1], c[2], c[3], c[4] or 1
    end
    local ni, tex = e.castNotInt, shell.fillTex
    if ni ~= nil and R(rec, "fill", "castLockOn") == true
        and tex and tex.SetVertexColorFromBoolean and CreateColor then
        local lc = R(rec, "fill", "castLockColor") or { 0.62, 0.64, 0.68, 1 }
        tex:SetVertexColorFromBoolean(ni, CreateColor(lc[1], lc[2], lc[3], lc[4] or 1),
            CreateColor(r, g, b, a))
    else
        shell.fill:SetStatusBarColor(r, g, b, a)
    end
end

-- The shield and lockHide read the same, possibly secret, flag.
function CB.LockLook(e)
    local rec, shell, ni, sh = e.rec, e.shell, e.castNotInt, e.castShield
    if sh then
        if e.castOn and ni ~= nil and R(rec, "icon", "iconShield") == true then
            CB.PlaceShield(e)
            sh:Show()
            if sh.SetAlphaFromBoolean then sh:SetAlphaFromBoolean(ni, 1, 0) end
        else
            sh:Hide()
        end
    end
    -- Skipped in edit mode so a bar being placed stays visible.
    if e.castOn and ni ~= nil and R(rec, "cast", "lockHide") == true
        and not (K.IsEditMode() and not e.isPreview) and shell.SetAlphaFromBoolean then
        shell:SetAlphaFromBoolean(ni, 0, 1)
    else
        shell:SetAlpha(1)
    end
end

-- LayoutTicks honours e.ticksOff when it lays the marks out again.
function CB.TicksFor(e)
    e.ticksOff = (not CB.PerTick(e) and R(e.rec, "ticks", "tickChannelOnly") == true
        and not e.castChannel) or nil
    local ticks = e.shell.ticks
    for i = 1, e.tickCount or 0 do
        if ticks[i] then ticks[i]:SetShown(not e.ticksOff) end
    end
end

-- One mark per channel tick

-- Player castbars only: a target's or focus's channel spell and length are
-- secret in combat.
function CB.PerTick(e)
    return R(e.rec, "ticks", "ticksShow") == true and R(e.rec, "ticks", "tickMode") == "pertick"
        and (e.castUnit or CB.Unit(e)) == "player"
end

-- The name table is kept only once every rank 1 name resolves.
function CB.TickEvery(spellID)
    local byName = CB.tickByName
    if not byName then
        byName = {}
        local all = true
        for id, every in pairs(CB.TICK_SLOW) do
            local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if n then byName[n] = every else all = false end
        end
        if all then CB.tickByName = byName end
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return (name and byName[name]) or CB.TICK_SLOW[spellID] or 1
end

-- Takes a plain spell ID and length in seconds. A channel's fill drains, so
-- tick k lands where the fill's edge is at 1 - k * every / len.
function CB.ChannelTicks(spellID, len)
    if not (spellID and len and len > 0 and len <= CB.TICK_MAX_LEN) then return nil end
    local every = CB.TickEvery(spellID)
    local out, k = {}, 1
    while k * every < len - 0.05 and #out < 30 do
        out[#out + 1] = 1 - k * every / len
        k = k + 1
    end
    return #out > 0 and out or nil
end

-- Returned as the extra fractions TickFractions adds; the mode itself adds none.
function CB.TickUnit(e)
    if not CB.PerTick(e) then return nil, false end
    return nil, false, e.castTickFracs
end

-- Player casts only, never channels. frac = the share of the cast the
-- connection delay covers.
function CB.Latency(e, frac)
    local lt, rec, shell = e.castLat, e.rec, e.shell
    if not lt then return end
    if not (frac and frac > 0 and e.castOn and not e.castChannel and e.castUnit == "player"
        and R(rec, "cast", "latencyOn") == true) or Bars.RectHidden(shell.fill) then
        lt:Hide()
        return
    end
    local fill, vertical = shell.fill, CB.Vertical(rec)
    local len = (vertical and fill:GetHeight() or fill:GetWidth()) or 0
    if len <= 1 then lt:Hide() return end
    local px = K.Px(shell)
    local size = math.max(px, math.floor(len * math.min(1, frac) / px + 0.5) * px)
    local rev = R(rec, "fill", "reverseFill") == true
    lt:ClearAllPoints()
    if vertical then
        local edge = rev and "BOTTOM" or "TOP"
        lt:SetPoint(edge .. "LEFT", fill, edge .. "LEFT", 0, 0)
        lt:SetPoint(edge .. "RIGHT", fill, edge .. "RIGHT", 0, 0)
        lt:SetHeight(size)
    else
        local edge = rev and "LEFT" or "RIGHT"
        lt:SetPoint("TOP" .. edge, fill, "TOP" .. edge, 0, 0)
        lt:SetPoint("BOTTOM" .. edge, fill, "BOTTOM" .. edge, 0, 0)
        lt:SetWidth(size)
    end
    lt:Show()
end

-- The player's own cast times read plain; nil when they do not.
function CB.LiveLatency()
    if not (UnitCastingInfo and GetNetStats) then return nil end
    local _, _, _, sMs, eMs = UnitCastingInfo("player")
    sMs, eMs = CB.Plain(sMs), CB.Plain(eMs)
    local _, _, _, world = GetNetStats()
    world = CB.Plain(world)
    if not (sMs and eMs and world) or eMs <= sMs then return nil end
    return world / (eMs - sMs)
end

-- The game's spell queue window in seconds (the SpellQueueWindow setting, a
-- plain string), or nil when it is off.
function CB.QueueWindow()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local v = get and tonumber(get("SpellQueueWindow"))
    if not v or v <= 0 then return nil end
    return v / 1000
end

-- Your casts, never channels: a tick where the queue window opens, so a
-- spell pressed past it goes off as this cast ends. len = the cast's plain
-- length in seconds. A whole number of pixels with whole-pixel edges, the
-- way LayoutTicks places a mark.
function CB.QueueTick(e, len)
    local qt, rec, shell = e.castQueue, e.rec, e.shell
    if not qt then return end
    local win = CB.QueueWindow()
    if not (len and win and win < len and not e.castChannel and e.castUnit == "player"
        and R(rec, "cast", "queueTickOn") == true) or Bars.RectHidden(shell.fill) then
        qt:Hide()
        return
    end
    local fill, vertical = shell.fill, CB.Vertical(rec)
    local size = (vertical and fill:GetHeight() or fill:GetWidth()) or 0
    if size <= 1 then qt:Hide() return end
    local px = K.Px(shell)
    local n = math.max(1, math.floor((R(rec, "cast", "queueTickWidth") or 2) + 0.5))
    local thick = Bars.StripPx(shell, n)
    -- pixels before the spot, from the fill origin: an odd width's spare
    -- pixel goes right of it (below on a standing bar), either direction
    local rev = R(rec, "fill", "reverseFill") == true
    local lead = (vertical == rev) and math.floor(n / 2) or (n - math.floor(n / 2))
    local pos = (math.floor(size * (1 - win / len) / px + 0.5) - lead) * px
    local c = R(rec, "cast", "queueTickColor") or CB.QUEUE_COLOR
    qt:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    qt:ClearAllPoints()
    if vertical then
        local edge = rev and "TOP" or "BOTTOM"
        local y = rev and -pos or pos
        qt:SetPoint(edge .. "LEFT", fill, edge .. "LEFT", 0, y)
        qt:SetPoint(edge .. "RIGHT", fill, edge .. "RIGHT", 0, y)
        qt:SetHeight(thick)
    else
        local edge = rev and "RIGHT" or "LEFT"
        local x = rev and -pos or pos
        qt:SetPoint("TOP" .. edge, fill, "TOP" .. edge, x, 0)
        qt:SetPoint("BOTTOM" .. edge, fill, "BOTTOM" .. edge, x, 0)
        qt:SetWidth(thick)
    end
    qt:Show()
end

function CB.SparkShown(e, on)
    if e.castSpark then e.castSpark:SetShown(on and R(e.rec, "cast", "sparkOn") == true) end
end

function CB.TimeFmt(rec)
    return (R(rec, "text", "durDecimalsEnabled") == true) and "%.1f" or "%.0f"
end

-- Runs 20 times a second while a cast shows. The remaining time only reaches
-- SetFormattedText, since it may be secret. If the unit stops casting and no
-- ending event has matched within 0.15 s, the cast ends as finished. A cast
-- drawn from its press is not one the game reports: it ends on its own
-- events, else SENT_GRACE past its time.
function CB.StartTicker(e)
    local tk = e.castTick
    if not tk then return end
    tk.acc = 1
    e.castGoneAt = nil
    tk:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        if not e.castOn then
            self:SetScript("OnUpdate", nil)
            return
        end
        if not e.isPreview then
            if e.castSent then
                if GetTime() >= e.castSentEnd + CB.SENT_GRACE then
                    e.castLastEv, e.castLastID = "watchdog", nil
                    CB.Finish(e, "done")
                    return
                end
            elseif CB.StillCasting(e) then
                e.castGoneAt = nil
            else
                local now = GetTime()
                e.castGoneAt = e.castGoneAt or now
                if now - e.castGoneAt >= 0.15 then
                    e.castLastEv, e.castLastID = "watchdog", nil
                    CB.End(e, "done")
                    return
                end
            end
        end
        local fs = e.shell.texts.dur
        if not (fs and fs:IsShown()) then return end
        local fill = e.shell.fill
        local d = (fill.GetTimerDuration and fill:GetTimerDuration()) or e.castDur
        local rem = d and d.GetRemainingDuration and d:GetRemainingDuration()
        if rem then fs:SetFormattedText(CB.TimeFmt(e.rec), rem) end
    end)
end

function CB.StopTicker(e)
    if e.castTick then e.castTick:SetScript("OnUpdate", nil) end
end

function CB.StopFade(e)
    if e.castFade and e.castFade:IsPlaying() then e.castFade:Stop() end
end

-- info = { dur, channel, name, tex, notInt, barID, latency, spellID, len, sent },
-- from CB.Begin, CB.FromSent or the editor preview. spellID and len are plain:
-- spellID set for a player channel, len for any cast or channel of yours.
-- sent = the press a cast was drawn from (CB.sent), copied.
function CB.Show(e, info)
    local rec, shell = e.rec, e.shell
    CB.StopFade(e)
    e.castGen = (e.castGen or 0) + 1
    e.castOn, e.castHold, e.castHow = true, nil, nil
    e.castChannel, e.castBarID, e.castDur = info.channel and true or false, info.barID, info.dur
    e.castNotInt, e.castTex = info.notInt, info.tex
    local s = info.sent
    e.castSent, e.castLen = s ~= nil, info.len
    if s then e.castSentGUID, e.castSentSpell, e.castSentEnd = s.guid, s.sid, s.start + s.len end
    -- The fill runs from the cast's own timer; a channel drains.
    K.FeedStatusBarTimer(shell.fill, info.dur, false, e.castChannel)
    if not CB.CustomName(rec) then K.SetRunText(shell, "name", info.name) end
    -- castArt is what Styled puts back after a restyle; tex may be secret
    e.castArt = info.tex
    if e.iconF and e.iconF.tex then e.iconF.tex:SetTexture(info.tex) end
    K.SetRunText(shell, "dur", "")
    CB.Paint(e)
    CB.LockLook(e)
    e.castTickFracs = e.castChannel and CB.ChannelTicks(info.spellID, info.len) or nil
    if CB.PerTick(e) then K.LayoutTicks(e) end
    CB.TicksFor(e)
    CB.Latency(e, info.latency)
    CB.QueueTick(e, info.len)
    CB.SparkShown(e, true)
    CB.StartTicker(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

-- A cast drawn from its press is not one the game reports: a re-read leaves
-- it running.
function CB.Sync(e)
    if e.isPreview then return end
    local unit = e.castUnit or CB.Unit(e)
    e.castUnit = unit
    local dur = UnitChannelDuration and UnitChannelDuration(unit)
    if dur then return CB.Begin(e, true, dur) end
    dur = UnitCastingDuration and UnitCastingDuration(unit)
    if dur then return CB.Begin(e, false, dur) end
    if not (e.castHold or e.castSent) then CB.Rest(e) end
end

function CB.Begin(e, channel, dur)
    local rec, unit = e.rec, e.castUnit
    if channel and R(rec, "cast", "hideChannels") == true then
        e.castOn = false
        return CB.Rest(e)
    end
    local name, tex, ni, bid, sid, len
    if channel then
        local n, _, t, sMs, eMs, _, x, id, _, _, b = UnitChannelInfo(unit)
        name, tex, ni, bid = n, t, x, b
        -- the player's own channel reads plain; any other unit's may be secret
        if unit == "player" then
            sid, sMs, eMs = CB.Plain(id), CB.Plain(sMs), CB.Plain(eMs)
            if sMs and eMs and eMs > sMs then len = (eMs - sMs) / 1000 end
        end
    else
        local n, _, t, sMs, eMs, _, _, x, _, b = UnitCastingInfo(unit)
        name, tex, ni, bid = n, t, x, b
        if unit == "player" then
            sMs, eMs = CB.Plain(sMs), CB.Plain(eMs)
            if sMs and eMs and eMs > sMs then len = (eMs - sMs) / 1000 end
        end
    end
    CB.Show(e, { dur = dur, channel = channel, name = name, tex = tex, notInt = ni,
        barID = CB.Plain(bid), spellID = sid, len = len,
        latency = (not channel and unit == "player") and CB.LiveLatency() or nil })
end

-- how = "done", "failed" or "interrupted". An end event whose cast bar id is
-- missing, secret or not ours may belong to another cast, so it waits while
-- the unit still casts; with nothing cast, the bar ends (else the watchdog).
-- A cast drawn from its press has no cast bar id: only its press's own
-- events end it.
function CB.End(e, how, barID)
    if not e.castOn then return end
    if e.castSent then
        if not CB.EventIs(e.castSentGUID, e.castSentSpell) then return end
    elseif (barID == nil or barID ~= e.castBarID) and CB.StillCasting(e) then
        return
    end
    CB.Finish(e, how)
end

function CB.Finish(e, how)
    -- your cast finished: a press queued behind it gets its turn
    local queued = how == "done" and not e.castSent and e.castUnit == "player"
    e.castOn = false
    e.castDur, e.castSent, e.castLen = nil, nil, nil
    CB.StopTicker(e)
    CB.SparkShown(e, false)
    if e.castLat then e.castLat:Hide() end
    if e.castQueue then e.castQueue:Hide() end
    if e.castShield then e.castShield:Hide() end
    e.shell:SetAlpha(1)
    K.SetRunText(e.shell, "dur", "")
    -- a finished cast never holds: the hold is for casts cut short
    if how ~= "done" and R(e.rec, "cast", "holdOn") == true then
        CB.HoldLook(e, how)
        local gen = e.castGen
        C_Timer.After(R(e.rec, "cast", "holdTime") or 0.6, function()
            if e.castGen ~= gen or not e.castHold then return end
            e.castHold = nil
            CB.FadeOrRest(e)
        end)
    else
        CB.FadeOrRest(e)
    end
    if queued then CB.Unblock() end
end

-- how = "interrupted" or "failed": a full bar in that colour, named for it
function CB.HoldLook(e, how)
    local rec, shell = e.rec, e.shell
    e.castHold, e.castHow = true, how
    shell.fill:SetMinMaxValues(0, 1)
    shell.fill:SetValue(1)
    CB.HoldColor(e)
    if not CB.CustomName(rec) then
        K.SetRunText(shell, "name", how == "interrupted" and (INTERRUPTED or "Interrupted")
            or (FAILED or "Failed"))
    end
end

function CB.HoldColor(e)
    local c
    if e.castHow == "interrupted" then
        c = R(e.rec, "cast", "holdIntColor") or { 0.9, 0.2, 0.2, 1 }
    else
        c = R(e.rec, "cast", "holdFailColor") or { 1, 0.55, 0.1, 1 }
    end
    e.shell.fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

function CB.FadeOrRest(e)
    local f = R(e.rec, "cast", "fadeOut") or 0
    if f > 0 and e.castFade and not K.IsEditMode() then
        e.castFade.alpha:SetDuration(f)
        e.castFade.gen = e.castGen
        e.castFade:Play()
    else
        CB.Rest(e)
    end
end

-- Hidden while playing (Hidden opacity can show it faintly); the sample while
-- editing.
function CB.Rest(e)
    e.castOn, e.castHold, e.castDur, e.castNotInt, e.castBarID = false, nil, nil, nil, nil
    e.castChannel, e.castTex, e.castGoneAt, e.castHow = false, nil, nil, nil
    e.castTickFracs, e.castSent, e.castLen = nil, nil, nil
    CB.StopFade(e)
    CB.StopTicker(e)
    if e.castLat then e.castLat:Hide() end
    if e.castQueue then e.castQueue:Hide() end
    if e.castShield then e.castShield:Hide() end
    local shell = e.shell
    shell:SetAlpha(1)
    K.SetRunText(shell, "dur", "")
    if K.IsEditMode() and not e.isPreview then
        CB.Sample(e)
        e.stateHidden = false
    else
        shell.fill:SetMinMaxValues(0, 1)
        shell.fill:SetValue(0)
        CB.SparkShown(e, false)
        if not CB.CustomName(e.rec) then K.SetRunText(shell, "name", "") end
        -- An empty icon box, not the "?", if Hidden opacity shows the idle bar.
        e.castArt = nil
        if e.iconF and e.iconF.tex then e.iconF.tex:SetTexture(nil) end
        e.stateHidden = true
    end
    if CB.PerTick(e) then K.LayoutTicks(e) end
    e.ticksOff = nil
    CB.TicksFor(e)
    K.ApplyVisibility(e)
end

-- A still bar to style and place while editing.
function CB.Sample(e)
    local rec, shell = e.rec, e.shell
    shell.fill:SetMinMaxValues(0, 1)
    shell.fill:SetValue(0.6)
    e.castChannel, e.castNotInt = false, nil
    CB.Paint(e)
    if not CB.CustomName(rec) then
        K.SetRunText(shell, "name", CB.SAMPLE_NAMES[e.castUnit or CB.Unit(e)] or "Casts")
    end
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(CB.SAMPLE_SPELL)
    e.castArt = tex
    if e.iconF and e.iconF.tex and tex then e.iconF.tex:SetTexture(tex) end
    local fs = shell.texts.dur
    if fs and fs:IsShown() then fs:SetFormattedText(CB.TimeFmt(rec), 1.2) end
    CB.SparkShown(e, true)
    -- so "One per tick" marks and the spell queue tick can be styled while editing
    e.castTickFracs = CB.SAMPLE_TICKS
    e.castLen = CB.SAMPLE_LEN
    CB.QueueTick(e, CB.SAMPLE_LEN)
end

-- Blizzard's player castbar is a managed frame: calling its Hide from addon
-- code would run its layout tainted, so it is silenced with UnregisterAllEvents.
function CB.WantBlizzHidden()
    for _, e in pairs(K.live) do
        if e.kind == "cast" and CB.Unit(e) == "player" and R(e.rec, "cast", "hideBlizzard") == true then
            return true
        end
    end
    return false
end

function CB.SyncBlizzard()
    local f = PlayerCastingBarFrame
    if not (f and f.UnregisterAllEvents and f.RegisterUnitEvent) then return end
    local want = CB.WantBlizzHidden()
    if want == (CB.blizzOff == true) then return end
    if want then
        f:UnregisterAllEvents()
        CB.blizzOff = true
    else
        -- Registers back what CastingBarMixin:SetUnit registered; only after our hide.
        for _, ev in ipairs(CB.BLIZZ_EVENTS) do
            if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev) then
                f:RegisterUnitEvent(ev, "player")
            end
        end
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        CB.blizzOff = false
    end
end

-- Events

-- fn(e, a, b) for every castbar of the unit: arguments, not a new closure,
-- so a cast event makes no garbage.
function CB.ForUnit(unit, fn, a, b)
    if not CB.UNITS[unit] then return end
    for _, e in pairs(K.live) do
        if e.kind == "cast" and e.castUnit == unit then fn(e, a, b) end
    end
end

-- For /adbars diag: the raw event and id, turned into words only by CB.Diag.
function CB.Note(e, event, id)
    e.castLastEv, e.castLastID = event, id
end

function CB.SyncIfOn(e)
    if e.castOn then CB.Sync(e) end
end

-- The cast bar id is NeverSecret. INTERRUPTED and CHANNEL_STOP carry one extra
-- argument before it.
function CB.BarIDOf(event, ...)
    local id
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        id = select(5, ...)
    else
        id = select(4, ...)
    end
    return CB.Plain(id)
end

-- Casts drawn from the press. CB.sent is your latest press of a spell with a
-- cast time that no START has answered yet, one table reused: live, guid,
-- sid, len, name, tex, at (pressed), start (drawn from), due (its wait ends),
-- blocked (queued behind a cast of yours).
CB.sent = { live = false }

-- How long a press waits for its START: the connection's delay, bounded.
function CB.SettleTime()
    local world
    if GetNetStats then world = CB.Plain(select(4, GetNetStats())) end
    local t = type(world) == "number" and world > 0 and world / 1000 or 0
    return math.min(CB.SENT_SETTLE_MAX, CB.SENT_SETTLE + t)
end

-- Whether the event being handled is about this cast: its cast GUID when both
-- read plain, else its spell. CB.OnCast keeps the event's own two.
function CB.EventIs(guid, sid)
    local g, s = CB.evGUID, CB.evSpell
    if g ~= nil and guid ~= nil then return g == guid end
    return s ~= nil and s == sid
end

-- UNIT_SPELLCAST_SENT (target, castGUID, spellID), your castbars only. Your
-- own casts read plain; an auto-repeat shot or an instant draws nothing.
function CB.Sent(_, guid, sid)
    sid = CB.Plain(sid)
    if type(sid) ~= "number" then return end
    local DT = NS.DriverToggle
    if DT and DT.REPEAT and DT.REPEAT[sid] then return end
    local info = CB.Plain(C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid))
    if type(info) ~= "table" then return end
    local ms = CB.Plain(info.castTime)
    if type(ms) ~= "number" or ms <= 0 then return end
    local s, now, wait = CB.sent, GetTime(), CB.SettleTime()
    s.live, s.blocked = true, false
    s.guid, s.sid, s.len = CB.Plain(guid), sid, ms / 1000
    s.name, s.tex = CB.Plain(info.name), CB.Plain(info.iconID)
    s.at, s.start, s.due = now, now, now + wait
    C_Timer.After(wait, CB.Settle)
end

-- The press's wait is over and no START came. Behind a cast of yours it is
-- queued (CB.Unblock); else every castbar of yours draws it. An older press's
-- timer finds the newer one not due yet (a millisecond's slack for the clock).
function CB.Settle()
    local s = CB.sent
    if not s.live or GetTime() < s.due - 0.001 then return end
    if (UnitCastingDuration and UnitCastingDuration("player"))
        or (UnitChannelDuration and UnitChannelDuration("player")) then
        s.blocked = true
        return
    end
    s.live = false
    CB.ForUnit("player", CB.FromSent, s)
end

function CB.FromSent(e, s)
    if e.isPreview then return end
    local dur = CB.FakeDuration(s.start, s.len)
    if not dur then return end
    CB.Show(e, { dur = dur, channel = false, name = s.name, tex = s.tex, len = s.len, sent = s })
end

-- Your cast finished: a press queued behind it waits once more for its own
-- START, then runs from now. One pressed long before is stale.
function CB.Unblock()
    local s = CB.sent
    if not (s.live and s.blocked) then return end
    s.blocked = false
    local now = GetTime()
    if now - s.at > CB.SENT_QUEUED then
        s.live = false
        return
    end
    local wait = CB.SettleTime()
    s.start, s.due = now, now + wait
    C_Timer.After(wait, CB.Settle)
end

-- An ending event of the pending press: it was answered with no bar.
function CB.Resolve()
    local s = CB.sent
    if s.live and CB.EventIs(s.guid, s.sid) then s.live = false end
end

-- SUCCEEDED or FAILED_QUIET end only a cast drawn from its press; a cast the
-- game reports ends on its STOP.
function CB.EndSent(e)
    if e.castOn and e.castSent and CB.EventIs(e.castSentGUID, e.castSentSpell) then
        CB.Finish(e, "done")
    end
end

-- An empowered cast is not drawn here; it ends a cast drawn from a press.
function CB.EndAnySent(e)
    if e.castOn and e.castSent then CB.Finish(e, "done") end
end

function CB.OnCast(event, unit, ...)
    if not CB.UNITS[unit] then return end
    if event == "UNIT_SPELLCAST_SENT" then
        CB.ForUnit(unit, CB.Note, event, nil)
        return CB.Sent(...)
    end
    local id = CB.BarIDOf(event, unit, ...)
    CB.ForUnit(unit, CB.Note, event, id)
    local guid, sid = ...
    CB.evGUID, CB.evSpell = CB.Plain(guid), CB.Plain(sid)
    local mine = unit == "player"
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        -- a START wins over a press still waiting or already drawn
        if mine and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") then
            CB.sent.live = false
        end
        CB.ForUnit(unit, CB.Sync)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        CB.ForUnit(unit, CB.SyncIfOn)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        CB.Resolve()
        CB.ForUnit(unit, CB.EndSent)
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        CB.sent.live = false
        CB.ForUnit(unit, CB.EndAnySent)
    else
        local how = (event == "UNIT_SPELLCAST_INTERRUPTED" and "interrupted")
            or (event == "UNIT_SPELLCAST_FAILED" and "failed") or "done"
        if mine then CB.Resolve() end
        CB.ForUnit(unit, CB.End, how, id)
    end
end

-- The token now points at another unit: show what it is casting.
function CB.Swap(unit)
    CB.ForUnit(unit, function(e)
        e.castHold = nil
        e.castOn = false
        CB.Sync(e)
    end)
end

function CB.SwapTarget() CB.Swap("target") end
function CB.SwapFocus() CB.Swap("focus") end

-- Each unit's cast events come to a frame of its own, registered only while a
-- castbar shows that unit, so the game drops every other unit's casts (raid
-- members, nameplates) before any Lua runs. Called on every Ensure and
-- Release; a released castbar has left K.live by then.
CB.frames = {}
function CB.Listen()
    local want = {}
    for _, e in pairs(K.live) do
        if e.kind == "cast" then want[CB.Unit(e)] = true end
    end
    for unit in pairs(CB.UNITS) do
        local f = CB.frames[unit]
        if want[unit] and not (f and f.adOn) then
            if not f then
                f = CreateFrame("Frame")
                -- through the table, so /arcperf times it
                f:SetScript("OnEvent", function(_, event, u, ...) CB.OnCast(event, u, ...) end)
                CB.frames[unit] = f
            end
            for _, ev in ipairs(CB.EVENTS) do
                if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev) then
                    f:RegisterUnitEvent(ev, unit)
                end
            end
            if unit == "player" then
                for _, ev in ipairs(CB.PLAYER_EVENTS) do
                    if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev) then
                        f:RegisterUnitEvent(ev, unit)
                    end
                end
            end
            f.adOn = true
        elseif not want[unit] and f and f.adOn then
            f:UnregisterAllEvents()
            f.adOn = false
        end
    end
    if want.target then K.SafeOn("PLAYER_TARGET_CHANGED", CB.KEY, CB.SwapTarget)
    else NS.Events.Off("PLAYER_TARGET_CHANGED", CB.KEY) end
    if want.focus then K.SafeOn("PLAYER_FOCUS_CHANGED", CB.KEY, CB.SwapFocus)
    else NS.Events.Off("PLAYER_FOCUS_CHANGED", CB.KEY) end
end

-- Kind registry hooks

function CB.Ensure(e)
    CB.Style(e)
    CB.Listen()
    CB.SyncBlizzard()
    if not e.castHold then CB.Sync(e) end
end

function CB.Refresh(e)
    if not e.castHold then CB.Sync(e) end
end

-- A new size moves the queue tick of the cast or sample on show; a fresh bar
-- has its first size only here.
function CB.Relayout(e)
    CB.Style(e)
    if e.castOn then CB.LockLook(e) end
    if e.castLen then CB.QueueTick(e, e.castLen) end
end

function CB.Release(e)
    e.castOn, e.castHold, e.castSent, e.castLen = false, nil, nil, nil
    CB.StopTicker(e)
    CB.StopFade(e)
    CB.Listen()
    CB.SyncBlizzard()
end

-- ApplyStyle resets the icon to the bar's "?" and the fill to its base colour;
-- put back the art this castbar last showed and the colour of what is on screen.
function CB.Styled(e)
    if e.iconF and e.iconF.tex then e.iconF.tex:SetTexture(e.castArt) end
    if e.castHold then
        CB.HoldColor(e)
    elseif e.castOn or (e.castFade and e.castFade:IsPlaying()) then
        CB.Paint(e)
    end
end

-- One /adbars diag line; plain values only (casting now is a nil test). The
-- last event reads as its short name and cast bar id, or "watchdog".
function CB.Diag(e)
    local last = e.castLastEv
    if last and last ~= "watchdog" then
        last = last:gsub("^UNIT_SPELLCAST_", "") .. "#" .. tostring(e.castLastID)
    end
    return ("%s [cast %s] on=%s channel=%s hold=%s barID=%s last=%s castingNow=%s fromPress=%s blizzardHidden=%s"):format(
        tostring(e.rec.name), tostring(e.castUnit), tostring(e.castOn == true),
        tostring(e.castChannel == true), tostring(e.castHold == true), tostring(e.castBarID),
        tostring(last), tostring(CB.StillCasting(e) ~= nil), tostring(e.castSent == true),
        tostring(CB.blizzOff == true))
end

-- Editor preview

function CB.PreviewModes(rec)
    return {
        { key = "static", text = "Casting", tip = "The bar in the middle of a cast, standing still." },
        { key = "loop", text = "Cast loop",
          tip = "A cast that finishes, one that is interrupted, then a channel." },
    }
end

function CB.PreviewBuild(e)
    CB.Style(e)
end

-- A plain duration object: the preview's, a cast drawn from its press.
function CB.FakeDuration(start, len)
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
    local d = C_DurationUtil.CreateDuration()
    if d and d.SetTimeFromStart then d:SetTimeFromStart(start, len) end
    return d
end

function CB.PreviewSpell(i)
    local sid = CB.PV_SPELLS[i]
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
    return name or "Spell", tex
end

-- The loop, 8.6 s: a 2.5 s cast that finishes and goes; a 2.6 s cast
-- interrupted halfway, then its hold; a 3 s channel that can't be
-- interrupted; rest.
CB.PV_PHASES = {
    { at = 0,   kind = "cast", len = 2.5, spell = 1 },
    { at = 2.5, kind = "rest" },
    { at = 3.1, kind = "cast", len = 2.6, spell = 2 },
    { at = 4.4, kind = "hold", how = "interrupted" },
    { at = 5.0, kind = "chan", len = 3.0, spell = 3, lock = true },
    { at = 8.0, kind = "rest" },
}
CB.PV_CYCLE = 8.6

function CB.PreviewApply(e, loop, t, fresh)
    e.castUnit = CB.Unit(e)
    if not loop then
        if fresh or e.pvCastPhase ~= "static" then
            e.pvCastPhase = "static"
            CB.StopTicker(e)
            CB.StopFade(e)
            e.shell:SetAlpha(1)
            if e.castShield then e.castShield:Hide() end
            e.castOn = false
            CB.Sample(e)
            if CB.PerTick(e) then K.LayoutTicks(e) end
            if e.castLat then e.castLat:Hide() end
        end
        return
    end
    local x = t % CB.PV_CYCLE
    local idx = 1
    for i, p in ipairs(CB.PV_PHASES) do
        if x >= p.at then idx = i end
    end
    if not fresh and e.pvCastPhase == idx then return end
    e.pvCastPhase = idx
    local p = CB.PV_PHASES[idx]
    local rec = e.rec
    if p.kind == "cast" or p.kind == "chan" then
        local channel = p.kind == "chan"
        if channel and R(rec, "cast", "hideChannels") == true then
            e.castOn = false
            e.shell.fill:SetMinMaxValues(0, 1)
            e.shell.fill:SetValue(0)
            return
        end
        local name, tex = CB.PreviewSpell(p.spell)
        local started = GetTime() - (x - p.at)
        local yours = e.castUnit == "player"
        local mine = channel and yours
        CB.Show(e, { dur = CB.FakeDuration(started, p.len), channel = channel, name = name, tex = tex,
            notInt = p.lock and true or false,
            spellID = mine and CB.PV_SPELLS[p.spell] or nil, len = yours and p.len or nil,
            latency = (not channel and yours) and CB.PV_LATENCY or nil })
    elseif p.kind == "hold" then
        -- The previous cast ended: hold its colour, or rest.
        e.castOn, e.castBarID, e.castLen = false, nil, nil
        CB.StopTicker(e)
        CB.SparkShown(e, false)
        if e.castLat then e.castLat:Hide() end
        if e.castQueue then e.castQueue:Hide() end
        if e.castShield then e.castShield:Hide() end
        e.shell:SetAlpha(1)
        K.SetRunText(e.shell, "dur", "")
        if R(rec, "cast", "holdOn") == true then
            CB.HoldLook(e, p.how)
        else
            e.shell.fill:SetMinMaxValues(0, 1)
            e.shell.fill:SetValue(0)
        end
    else
        e.castOn, e.castHold, e.castTickFracs, e.castLen = false, nil, nil, nil
        CB.StopTicker(e)
        CB.SparkShown(e, false)
        if e.castQueue then e.castQueue:Hide() end
        if e.castShield then e.castShield:Hide() end
        e.shell:SetAlpha(1)
        e.shell.fill:SetMinMaxValues(0, 1)
        e.shell.fill:SetValue(0)
        K.SetRunText(e.shell, "dur", "")
        if CB.PerTick(e) then K.LayoutTicks(e) end
    end
end

Bars.RegisterKind("cast", {
    Build = CB.Build,
    Ensure = CB.Ensure,
    Refresh = CB.Refresh,
    Relayout = CB.Relayout,
    Release = CB.Release,
    Styled = CB.Styled,
    TickUnit = CB.TickUnit,
    Diag = CB.Diag,
    ownsName = true,
    PreviewModes = CB.PreviewModes,
    PreviewBuild = CB.PreviewBuild,
    PreviewApply = CB.PreviewApply,
})
