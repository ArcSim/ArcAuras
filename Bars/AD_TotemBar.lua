-- AD_TotemBar: the totem bar (barKind "totembar"), the time left on one of your totems or guardians as a fill.
-- The totem driver (Drivers\AD_DriverTotem.lua) names the slot it sits in by your own cast, plain in combat;
-- the slot's duration object feeds the fill and the countdown C-side, so nothing is read or polled.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R

local TB = {}
NS.TotemBars = TB
TB.KEY = "adtotembar"
-- The editor sample: 14 of a totem's 24 seconds left.
TB.SAMPLE_LEFT, TB.SAMPLE_FULL = 14, 24

function TB.SpellID(rec)
    local d = rec and rec.driver
    local id = d and tonumber(d.spellID)
    if id and id > 0 then return math.floor(id) end
    return nil
end

function TB.Slot(rec)
    local d = rec and rec.driver
    local s = d and tonumber(d.slot)
    if s and s >= 1 and s <= 4 then return math.floor(s) end
    return 1
end

-- Text only: the client draws the countdown from the duration object.
function TB.Build(e)
    if e.durCD then return end
    local dcd = CreateFrame("Cooldown", nil, e.shell.overlay, "CooldownFrameTemplate")
    dcd:SetAllPoints(e.shell.overlay)
    dcd:SetDrawSwipe(false)
    dcd:SetDrawEdge(false)
    dcd:SetDrawBling(false)
    dcd:SetHideCountdownNumbers(false)
    if dcd.SetMinimumCountdownDuration then dcd:SetMinimumCountdownDuration(0) end
    dcd:EnableMouse(false)
    dcd:Show()
    e.durCD = dcd
end

-- The driver follows the bar's totem under a key of its own: by the spell that
-- puts it down, into whatever slot it lands, else the bar's slot.
function TB.Track(e)
    local DT = NS.DriverTotem
    if not DT then return end
    local d = e.rec.driver or {}
    local sid = TB.SpellID(e.rec)
    local list = (sid and type(d.spellIDs) == "table") and d.spellIDs or nil
    local p = e.tbPseudo
    if p and p.driver.spellID == sid and p.driver.slot == TB.Slot(e.rec) then -- raw-id: the same pick, not a match
        p.driver.spellIDs = list
        return
    end
    -- re-pointed under the same key: no detach, so the slots are not re-read
    e.tbPseudo = { id = TB.KEY .. tostring(e.rec.id), driver = { spellID = sid, spellIDs = list, slot = TB.Slot(e.rec) } }
    DT.Attach(e.tbPseudo)
end

function TB.Untrack(e)
    if e.tbPseudo and NS.DriverTotem then NS.DriverTotem.Detach(e.tbPseudo.id) end
    e.tbPseudo = nil
end

function TB.Refresh(e)
    if e.isPreview then return end
    local DT = NS.DriverTotem
    local slot = e.tbPseudo and DT and DT.SlotFor(e.tbPseudo)
    local dur = slot and GetTotemDuration and GetTotemDuration(slot)
    local shell = e.shell
    if dur then
        local drain = (R(e.rec, "fill", "fillMode") or "drain") == "drain"
        K.FeedStatusBarTimer(shell.fill, dur, false, drain)
        if e.durCD then e.durCD:SetCooldownFromDurationObject(dur, true) end
        e.tbRunning = true
    else
        shell.fill:SetMinMaxValues(0, 1)
        shell.fill:SetValue(0)
        if e.durCD then e.durCD:Clear() end
        e.tbRunning = false
    end
    shell.fill:SetStatusBarColor(K.BarColorOf(e.rec))
    e.stateHidden = (not e.tbRunning) and R(e.rec, "behavior", "hideWhenInactive") == true
    K.ApplyVisibility(e)
end

-- Every totem bar on a slot change (DT.Changed).
function TB.OnTotems()
    K.ForEach("totembar", TB.Refresh)
end

-- Kind registry hooks
function TB.Ensure(e)
    if e.isPreview then return end
    TB.Track(e)
    TB.Refresh(e)
end

function TB.Release(e)
    TB.Untrack(e)
    e.tbRunning = nil
end

function TB.Diag(e)
    local DT = NS.DriverTotem
    local slot = e.tbPseudo and DT and DT.SlotFor(e.tbPseudo)
    return ("%s [totembar spell=%s slot=%s] down=%s running=%s"):format(tostring(e.rec.name),
        tostring(TB.SpellID(e.rec)), tostring(TB.Slot(e.rec)), tostring(slot), tostring(e.tbRunning == true))
end

-- Editor preview: the sample totem, standing or counting down.
function TB.PreviewModes()
    return {
        { key = "static", text = "Preview", tip = "A totem with 14 of its 24 seconds left, standing still." },
        { key = "loop", text = "Running", tip = "The same totem counting down, as it looks in play." },
    }
end

function TB.PreviewBuild(e)
    TB.Build(e)
end

function TB.PreviewApply(e, loop, t, fresh)
    if not (fresh or loop ~= e.pvTotemLoop) then return end
    e.pvTotemLoop = loop
    local shell = e.shell
    local drain = (R(e.rec, "fill", "fillMode") or "drain") == "drain"
    shell.fill:SetStatusBarColor(K.BarColorOf(e.rec))
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then
        shell.fill:SetMinMaxValues(0, TB.SAMPLE_FULL)
        shell.fill:SetValue(drain and TB.SAMPLE_LEFT or (TB.SAMPLE_FULL - TB.SAMPLE_LEFT))
        return
    end
    e.tbDur = e.tbDur or C_DurationUtil.CreateDuration()
    e.tbDur:SetTimeFromEnd(GetTime() + TB.SAMPLE_LEFT, TB.SAMPLE_FULL)
    if loop then
        K.FeedStatusBarTimer(shell.fill, e.tbDur, false, drain)
    else
        shell.fill:SetMinMaxValues(0, TB.SAMPLE_FULL)
        shell.fill:SetValue(drain and TB.SAMPLE_LEFT or (TB.SAMPLE_FULL - TB.SAMPLE_LEFT))
    end
    if e.durCD then
        e.durCD:SetCooldownFromDurationObject(e.tbDur, true)
        -- a still countdown: paused at the sample's time left
        if loop then
            if e.durCD.Resume then e.durCD:Resume() end
        elseif e.durCD.Pause then
            e.durCD:Pause()
        end
    end
end

Bars.RegisterKind("totembar", {
    Build = TB.Build,
    Ensure = TB.Ensure,
    Refresh = TB.Refresh,
    Release = TB.Release,
    Diag = TB.Diag,
    PreviewModes = TB.PreviewModes,
    PreviewBuild = TB.PreviewBuild,
    PreviewApply = TB.PreviewApply,
})
