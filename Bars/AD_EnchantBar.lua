-- Weapon enchant bars (barKind "enchant"): the time left on a weapon's enchant
-- as a fill, with its charges, plugged into the bars runtime through
-- Bars.RegisterKind and Bars.Kit; the reads are NS.DriverEnchant's.
-- The enchant info is plain on Forever; the fill and the countdown still run
-- from a duration object, so nothing polls.

local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R

local EB = {}
NS.EnchantBars = EB
EB.KEY = "adbarsench"
EB.EVENTS = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED" }
-- The editor sample: 25 of 30 minutes left, no charges.
EB.SAMPLE_LEFT, EB.SAMPLE_FULL = 1500, 1800

-- Text only: the client draws the countdown from the duration object.
function EB.Build(e)
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

function EB.Art(e, en)
    if not (e.iconF and e.iconF.tex) then return end
    local E = NS.DriverEnchant
    local tex = en and en.icon
    if not tex then
        tex = GetInventoryItemTexture("player", E and E.InvSlot(e.rec) or 16)
    end
    e.enchArt = tex
    e.iconF.tex:SetTexture(tex or 134400)
end

-- One re-read when the enchant should run out, in case no event says so.
function EB.Expiry(e, left)
    e.enchToken = (e.enchToken or 0) + 1
    local token, id = e.enchToken, e.rec.id
    C_Timer.After(math.max(0.1, left + 0.2), function()
        local live = K.live[id]
        if live and live.enchToken == token then EB.Refresh(live) end
    end)
end

function EB.Show(e, left, full, charges)
    local shell = e.shell
    if C_DurationUtil and C_DurationUtil.CreateDuration then
        e.enchDur = e.enchDur or C_DurationUtil.CreateDuration()
        e.enchDur:SetTimeFromEnd(GetTime() + left, full)
        local drain = (R(e.rec, "fill", "fillMode") or "drain") == "drain"
        K.FeedStatusBarTimer(shell.fill, e.enchDur, false, drain)
        if e.durCD then e.durCD:SetCooldownFromDurationObject(e.enchDur, true) end
    end
    shell.fill:SetStatusBarColor(K.BarColorOf(e.rec))
    K.SetRunText(shell, "stk", (charges or 0) > 0 and charges or "")
end

function EB.Refresh(e)
    if e.isPreview then return end
    local E = NS.DriverEnchant
    if not E then return end
    local en = E.Read(e.rec)
    if en == nil then return end
    if en then
        EB.Show(e, en.left, E.Full(en), en.charges)
        e.running = true
        e.stateHidden = false
        EB.Expiry(e, en.left)
    else
        e.enchToken = (e.enchToken or 0) + 1
        e.shell.fill:SetMinMaxValues(0, 1)
        e.shell.fill:SetValue(0)
        if e.durCD then e.durCD:Clear() end
        K.SetRunText(e.shell, "stk", "")
        e.running = false
        e.stateHidden = R(e.rec, "behavior", "hideWhenInactive") == true
    end
    EB.Art(e, en or nil)
    K.ApplyVisibility(e)
end

function EB.RefreshAll()
    K.ForEach("enchant", EB.Refresh)
end

function EB.Arm()
    if EB.armed then return end
    EB.armed = true
    for _, ev in ipairs(EB.EVENTS) do
        K.SafeOn(ev, EB.KEY, function(_, unit)
            if ev == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
            NS.Events.Coalesce("adbarsench_all", EB.RefreshAll)
        end)
    end
end

function EB.Disarm()
    if not EB.armed then return end
    for _, e in pairs(K.live) do
        if e.kind == "enchant" then return end
    end
    EB.armed = false
    for _, ev in ipairs(EB.EVENTS) do NS.Events.Off(ev, EB.KEY) end
end

-- Kind registry hooks
function EB.Ensure(e)
    EB.Arm()
    EB.Refresh(e)
end

function EB.Release(e)
    e.enchToken = (e.enchToken or 0) + 1
    EB.Disarm()
end

-- ApplyStyle resets the bar icon: put back the art this bar last showed.
function EB.Styled(e)
    if e.iconF and e.iconF.tex and e.enchArt then e.iconF.tex:SetTexture(e.enchArt) end
end

function EB.Diag(e)
    local E = NS.DriverEnchant
    local en = E and E.Read(e.rec)
    return ("%s [enchant %s] on=%s left=%s charges=%s"):format(tostring(e.rec.name),
        tostring(e.rec.driver and e.rec.driver.hand or "main"), tostring(en and true or false),
        tostring(en and en.left), tostring(en and en.charges))
end

-- Editor preview: the sample enchant, standing or counting down.
function EB.PreviewModes()
    return {
        { key = "static", text = "Preview", tip = "An enchant with 25 of its 30 minutes left, standing still." },
        { key = "loop", text = "Running", tip = "The same enchant counting down, as it looks in play." },
    }
end

function EB.PreviewBuild(e)
    EB.Build(e)
end

function EB.PreviewApply(e, loop, t, fresh)
    if not (fresh or loop ~= e.pvEnchLoop) then return end
    e.pvEnchLoop = loop
    local shell = e.shell
    if loop then
        EB.Show(e, EB.SAMPLE_LEFT, EB.SAMPLE_FULL, 0)
    else
        local drain = (R(e.rec, "fill", "fillMode") or "drain") == "drain"
        shell.fill:SetMinMaxValues(0, EB.SAMPLE_FULL)
        shell.fill:SetValue(drain and EB.SAMPLE_LEFT or (EB.SAMPLE_FULL - EB.SAMPLE_LEFT))
        shell.fill:SetStatusBarColor(K.BarColorOf(e.rec))
        if e.durCD and C_DurationUtil and C_DurationUtil.CreateDuration then
            -- a still countdown: paused at the sample's time left
            e.enchDur = e.enchDur or C_DurationUtil.CreateDuration()
            e.enchDur:SetTimeFromEnd(GetTime() + EB.SAMPLE_LEFT, EB.SAMPLE_FULL)
            e.durCD:SetCooldownFromDurationObject(e.enchDur, true)
            if e.durCD.Pause then e.durCD:Pause() end
        end
        K.SetRunText(shell, "stk", "")
    end
    if loop and e.durCD and e.durCD.Resume then e.durCD:Resume() end
    EB.Art(e, nil)
end

Bars.RegisterKind("enchant", {
    Build = EB.Build,
    Ensure = EB.Ensure,
    Refresh = EB.Refresh,
    Release = EB.Release,
    Styled = EB.Styled,
    Diag = EB.Diag,
    PreviewModes = EB.PreviewModes,
    PreviewBuild = EB.PreviewBuild,
    PreviewApply = EB.PreviewApply,
})
