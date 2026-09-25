-- Castbars (barKind "cast") for the player, target and focus, plugged into the
-- bars runtime through Bars.RegisterKind and Bars.Kit. A target's or focus's
-- cast is secret in combat: its duration object only feeds SetTimerDuration and
-- SetFormattedText, and "cannot be interrupted" only the *FromBoolean setters.

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

function CB.SparkShown(e, on)
    if e.castSpark then e.castSpark:SetShown(on and R(e.rec, "cast", "sparkOn") == true) end
end

function CB.TimeFmt(rec)
    return (R(rec, "text", "durDecimalsEnabled") == true) and "%.1f" or "%.0f"
end

-- Runs 20 times a second while a cast shows. The remaining time only reaches
-- SetFormattedText, since it may be secret. If the unit stops casting and no
-- ending event has matched within 0.15 s, the cast ends as finished.
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
            if CB.StillCasting(e) then
                e.castGoneAt = nil
            else
                local now = GetTime()
                e.castGoneAt = e.castGoneAt or now
                if now - e.castGoneAt >= 0.15 then
                    e.castLastEv = "watchdog"
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

-- info = { dur, channel, name, tex, notInt, barID, latency, spellID, len },
-- from CB.Begin or the editor preview. spellID and len are plain and only set
-- for a player channel.
function CB.Show(e, info)
    local rec, shell = e.rec, e.shell
    CB.StopFade(e)
    e.castGen = (e.castGen or 0) + 1
    e.castOn, e.castHold, e.castHow = true, nil, nil
    e.castChannel, e.castBarID, e.castDur = info.channel and true or false, info.barID, info.dur
    e.castNotInt, e.castTex = info.notInt, info.tex
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
    CB.SparkShown(e, true)
    CB.StartTicker(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

function CB.Sync(e)
    if e.isPreview then return end
    local unit = e.castUnit or CB.Unit(e)
    e.castUnit = unit
    local dur = UnitChannelDuration and UnitChannelDuration(unit)
    if dur then return CB.Begin(e, true, dur) end
    dur = UnitCastingDuration and UnitCastingDuration(unit)
    if dur then return CB.Begin(e, false, dur) end
    if not e.castHold then CB.Rest(e) end
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
        local n, _, t, _, _, _, _, x, _, b = UnitCastingInfo(unit)
        name, tex, ni, bid = n, t, x, b
    end
    CB.Show(e, { dur = dur, channel = channel, name = name, tex = tex, notInt = ni,
        barID = CB.Plain(bid), spellID = sid, len = len,
        latency = (not channel and unit == "player") and CB.LiveLatency() or nil })
end

-- how = "done", "failed" or "interrupted". A mismatched cast bar id belongs to
-- an older cast only while the unit still casts; with nothing cast, the bar ends.
function CB.End(e, how, barID)
    if not e.castOn then return end
    if barID ~= nil and e.castBarID ~= nil and barID ~= e.castBarID and CB.StillCasting(e) then
        return
    end
    e.castOn = false
    e.castDur = nil
    CB.StopTicker(e)
    CB.SparkShown(e, false)
    if e.castLat then e.castLat:Hide() end
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
    e.castTickFracs = nil
    CB.StopFade(e)
    CB.StopTicker(e)
    if e.castLat then e.castLat:Hide() end
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
    -- so "One per tick" marks can be styled while editing
    e.castTickFracs = CB.SAMPLE_TICKS
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

function CB.ForUnit(unit, fn)
    if not CB.UNITS[unit] then return end
    for _, e in pairs(K.live) do
        if e.kind == "cast" and e.castUnit == unit then fn(e) end
    end
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

function CB.OnCast(event, unit, ...)
    if not CB.UNITS[unit] then return end
    -- For /adbars diag; plain parts only.
    local id = CB.BarIDOf(event, unit, ...)
    local short = event:gsub("^UNIT_SPELLCAST_", "")
    CB.ForUnit(unit, function(e) e.castLastEv = short .. "#" .. tostring(id) end)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        CB.ForUnit(unit, CB.Sync)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        CB.ForUnit(unit, function(e) if e.castOn then CB.Sync(e) end end)
    else
        local how = (event == "UNIT_SPELLCAST_INTERRUPTED" and "interrupted")
            or (event == "UNIT_SPELLCAST_FAILED" and "failed") or "done"
        CB.ForUnit(unit, function(e) CB.End(e, how, id) end)
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

function CB.Arm()
    if CB.armed then return end
    CB.armed = true
    for _, ev in ipairs(CB.EVENTS) do
        K.SafeOn(ev, CB.KEY, function(event, unit, ...) CB.OnCast(event, unit, ...) end)
    end
    K.SafeOn("PLAYER_TARGET_CHANGED", CB.KEY, function() CB.Swap("target") end)
    K.SafeOn("PLAYER_FOCUS_CHANGED", CB.KEY, function() CB.Swap("focus") end)
end

function CB.Disarm()
    if not CB.armed then return end
    for _, e in pairs(K.live) do
        if e.kind == "cast" then return end
    end
    CB.armed = false
    for _, ev in ipairs(CB.EVENTS) do NS.Events.Off(ev, CB.KEY) end
    NS.Events.Off("PLAYER_TARGET_CHANGED", CB.KEY)
    NS.Events.Off("PLAYER_FOCUS_CHANGED", CB.KEY)
end

-- Kind registry hooks

function CB.Ensure(e)
    CB.Style(e)
    CB.Arm()
    CB.SyncBlizzard()
    if not e.castHold then CB.Sync(e) end
end

function CB.Refresh(e)
    if not e.castHold then CB.Sync(e) end
end

function CB.Relayout(e)
    CB.Style(e)
    if e.castOn then CB.LockLook(e) end
end

function CB.Release(e)
    e.castOn, e.castHold = false, nil
    CB.StopTicker(e)
    CB.StopFade(e)
    CB.Disarm()
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

-- One /adbars diag line; plain values only (casting now is a nil test).
function CB.Diag(e)
    return ("%s [cast %s] on=%s channel=%s hold=%s barID=%s last=%s castingNow=%s blizzardHidden=%s"):format(
        tostring(e.rec.name), tostring(e.castUnit), tostring(e.castOn == true),
        tostring(e.castChannel == true), tostring(e.castHold == true), tostring(e.castBarID),
        tostring(e.castLastEv), tostring(CB.StillCasting(e) ~= nil), tostring(CB.blizzOff == true))
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

-- A plain duration object for the preview.
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
        local mine = channel and e.castUnit == "player"
        CB.Show(e, { dur = CB.FakeDuration(started, p.len), channel = channel, name = name, tex = tex,
            notInt = p.lock and true or false,
            spellID = mine and CB.PV_SPELLS[p.spell] or nil, len = mine and p.len or nil,
            latency = (not channel and e.castUnit == "player") and CB.PV_LATENCY or nil })
    elseif p.kind == "hold" then
        -- The previous cast ended: hold its colour, or rest.
        e.castOn, e.castBarID = false, nil
        CB.StopTicker(e)
        CB.SparkShown(e, false)
        if e.castLat then e.castLat:Hide() end
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
        e.castOn, e.castHold, e.castTickFracs = false, nil, nil
        CB.StopTicker(e)
        CB.SparkShown(e, false)
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
