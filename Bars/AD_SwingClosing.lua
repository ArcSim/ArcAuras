-- AD_SwingClosing: a swing bar's fill as two halves that close in from the ends, plus up to three ticks set times before the swing lands.
-- Owns the mirror half and the ticks; the bars runtime calls in through Bars.SwingClose when it styles or releases a swing bar.
-- PLAYER_SWING's duration is plain, so the ticks are placed from it with no secret math.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.ApplySheen) then return end
local Events = NS.Events

local SC = {}
Bars.SwingClose = SC
local armed = false
SC.MAX_TICKS = 3
-- each tick's time and colour when a record carries none (the schema's defaults)
SC.TICK_DEFAULTS = {
    { 0.5, { 1, 1, 1, 0.9 } }, { 1.5, { 0.4, 1, 0.4, 0.9 } }, { 0.4, { 1, 0.45, 0.9, 0.9 } },
}

-- The off-hand track splits the fill its own way, so a bar with its switch on
-- never closes in; the editor hides this switch by the same rule.
local function Closing(rec)
    return K.R(rec, "fill", "swingClosing") == true and K.R(rec, "fill", "swingOffhand") ~= true
end

-- A tick rides the moving edge of a helper bar that spans one half and draws
-- nothing, so the game places it at any size with no reads.
local function NewEdge(shell)
    local bar = CreateFrame("StatusBar", nil, shell)
    bar:EnableMouse(false)
    bar:SetStatusBarTexture(K.WHITE)
    bar:SetStatusBarColor(1, 1, 1, 0)
    bar:SetMinMaxValues(0, 1)
    bar:Hide()
    -- on the text host like the bar's own tick marks: above both halves, under the texts
    local tick = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 2)
    tick:Hide()
    return { bar = bar, tex = bar:GetStatusBarTexture(), tick = tick }
end

-- The widgets live on the shell, which can outlive the entry that built them.
local function Ensure(shell)
    local c = shell._adSWC
    if c then return c end
    c = { edges = { NewEdge(shell), NewEdge(shell) } }
    c.bar = CreateFrame("StatusBar", nil, shell)
    c.bar:EnableMouse(false)
    c.bar:Hide()
    c.sheen = shell.overlay:CreateTexture(nil, "BACKGROUND")
    c.sheen:SetTexture(K.WHITE)
    c.sheen:Hide()
    shell._adSWC = c
    return c
end

-- The mirror copies every write to the main fill. A hook cannot be removed, so
-- these stay for the shell's life and do nothing while the halves are off.
local function Hook(shell, c)
    if c.hooked then return end
    c.hooked = true
    local fill = shell.fill
    hooksecurefunc(fill, "SetMinMaxValues", function(_, ...)
        if c.active then c.bar:SetMinMaxValues(...) end
    end)
    hooksecurefunc(fill, "SetValue", function(_, ...)
        if c.active then c.bar:SetValue(...) end
    end)
    hooksecurefunc(fill, "SetStatusBarColor", function(_, ...)
        if c.active then c.bar:SetStatusBarColor(...) end
    end)
    -- The bar's own tick marks measure the main fill, whose width moves only
    -- on the layout after a split: lay them out again then.
    fill:HookScript("OnSizeChanged", function()
        if shell._adResize then shell._adResize() end
    end)
end

local function Unsplit(shell, c)
    if not c.split then return end
    c.split = false
    shell.overlay:ClearAllPoints()
    shell.overlay:SetAllPoints(shell.fill)
end

local function HideEdge(ed)
    if not ed then return end
    ed.tick:Hide()
    ed.bar:Hide()
end

-- Tick k's pair: edges[2k - 1] on the main half (or the whole fill), edges[2k]
-- on the mirror. Tick 1's pair exists from Ensure; the others come when used.
local function EdgePair(shell, c, k)
    local i = 2 * k - 1
    if not c.edges[i] then c.edges[i] = NewEdge(shell) end
    if not c.edges[i + 1] then c.edges[i + 1] = NewEdge(shell) end
    return c.edges[i], c.edges[i + 1]
end

local function HideTicks(c, from)
    for i = 2 * from - 1, #c.edges do HideEdge(c.edges[i]) end
end

local function Stop(shell, c)
    c.active = false
    c.ticksOn = false
    c.dur = nil
    c.bar:Hide()
    c.sheen:Hide()
    HideTicks(c, 1)
    Unsplit(shell, c)
end

local function PaintMirror(e, c)
    local rec, fill = e.rec, e.shell.fill
    c.bar:SetFrameLevel(fill:GetFrameLevel())
    c.bar:SetOrientation(c.vertical and "VERTICAL" or "HORIZONTAL")
    -- the main half's mirror image: both grow toward the same centre
    c.bar:SetReverseFill(not c.reverse)
    local tex = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    if c.tex ~= tex then
        -- a texture swap makes a new texture object
        c.tex = tex
        c.bar:SetStatusBarTexture(tex)
        local t = c.bar:GetStatusBarTexture()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        c.sheen:ClearAllPoints()
        c.sheen:SetAllPoints(t)
    end
    c.bar:SetRotatesTexture(K.R(rec, "fill", "rotateTexture") == true)
    K.ApplySheen(c.sheen, rec)
    c.sheen:SetShown(K.R(rec, "fill", "useGradient") ~= false)
    -- the main fill's state now; the hooks carry every later write
    c.bar:SetMinMaxValues(fill:GetMinMaxValues())
    c.bar:SetValue(fill:GetValue())
    c.bar:SetStatusBarColor(fill:GetStatusBarColor())
    c.bar:Show()
end

-- The halves meet on the shell's own centre line, so the split holds at any
-- size the engine, an anchor or the preview gives the bar.
local function Split(e, c)
    local shell = e.shell
    local fill, mirror, i = shell.fill, c.bar, e.fillInset or 0
    fill:ClearAllPoints()
    mirror:ClearAllPoints()
    if c.vertical then
        -- a vertical fill starts at the bottom as a flat one starts at the left
        fill:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", i, i)
        fill:SetPoint("TOPRIGHT", shell, "RIGHT", -i, 0)
        mirror:SetPoint("TOPLEFT", shell, "TOPLEFT", i, -i)
        mirror:SetPoint("BOTTOMRIGHT", shell, "RIGHT", -i, 0)
    else
        fill:SetPoint("TOPLEFT", shell, "TOPLEFT", i, -i)
        fill:SetPoint("BOTTOMRIGHT", shell, "BOTTOM", 0, i)
        mirror:SetPoint("TOPLEFT", shell, "TOP", 0, -i)
        mirror:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -i, i)
    end
    -- the texts keep the whole bar, not the main half
    local ov = shell.overlay
    ov:ClearAllPoints()
    ov:SetPoint("TOPLEFT", shell, "TOPLEFT", i, -i)
    ov:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -i, i)
    c.split = true
end

local function PlaceEdge(ed, host, vertical, reverse, dur, value, color, half, level)
    local bar, t, ft = ed.bar, ed.tick, ed.tex
    bar:SetFrameLevel(level)
    bar:ClearAllPoints()
    bar:SetAllPoints(host)
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(reverse)
    bar:SetMinMaxValues(0, dur)
    bar:SetValue(value)
    bar:Show()
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    t:ClearAllPoints()
    if vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        t:SetPoint("TOPLEFT", ft, edge .. "LEFT", 0, half)
        t:SetPoint("BOTTOMRIGHT", ft, edge .. "RIGHT", 0, -half)
    else
        local edge = reverse and "LEFT" or "RIGHT"
        t:SetPoint("TOPLEFT", ft, "TOP" .. edge, -half, 0)
        t:SetPoint("BOTTOMRIGHT", ft, "BOTTOM" .. edge, half, 0)
    end
    t:Show()
end

-- How many ticks the bar asks for, 1 to 3.
function SC.TickCount(rec)
    local v = K.R(rec, "fill", "swingTickCount")
    local n = math.floor(tonumber(v) or 1)
    if n < 1 then return 1 end
    return math.min(n, SC.MAX_TICKS)
end

-- Tick k's lead time and colour. Tick 1 keeps its first two fields, so a bar
-- saved before ticks 2 and 3 existed reads the same.
function SC.TickSpec(rec, k)
    local lead, color
    if k == 1 then
        lead, color = K.R(rec, "fill", "swingTickTime"), K.R(rec, "fill", "swingTickColor")
    elseif k == 2 then
        lead, color = K.R(rec, "fill", "swingTick2Time"), K.R(rec, "fill", "swingTick2Color")
    else
        lead, color = K.R(rec, "fill", "swingTick3Time"), K.R(rec, "fill", "swingTick3Color")
    end
    local d = SC.TICK_DEFAULTS[k]
    return tonumber(lead) or d[1], (type(color) == "table") and color or d[2]
end

-- Each tick marks where its half's fill edge stands when its lead time is
-- left: the live bar's last plain swing length, or the preview's own; no
-- ticks until one is known, and none that lead the whole swing.
local function PlaceTicks(e, c)
    local rec = e.rec
    local dur = c.dur or e.swingLen
    local n = (c.ticksOn and dur) and SC.TickCount(rec) or 0
    -- the fill's value at that moment: time left on a drain bar, else time gone
    local drain = (K.R(rec, "fill", "fillMode") or "drain") == "drain"
    -- two pixels across, each at least one of this frame's own, so a
    -- zoomed-out preview keeps it
    local half = Bars.StripPx(e.shell, 1)
    local fill = e.shell.fill
    local level = fill:GetFrameLevel()
    for k = 1, n do
        local main, other = EdgePair(e.shell, c, k)
        local lead, color = SC.TickSpec(rec, k)
        if lead > 0 and lead < dur then
            local value = drain and lead or (dur - lead)
            PlaceEdge(main, fill, c.vertical, c.reverse, dur, value, color, half, level)
            if c.active then
                PlaceEdge(other, c.bar, c.vertical, not c.reverse, dur, value, color, half, level)
            else
                HideEdge(other)
            end
        else
            HideEdge(main)
            HideEdge(other)
        end
    end
    HideTicks(c, n + 1)
end

-- PLAYER_SWING only while a live bar shows ticks; each swing's own length
-- moves them (haste changes it).
function SC.SyncEvents()
    local want = false
    if C_SwingTimer and Events then
        K.ForEach("swing", function(e)
            if e.swc and e.swc.ticksOn then want = true end
        end)
    end
    if want == armed then return end
    armed = want
    if want then
        Events.On("PLAYER_SWING", "adswingclose", function(_, duration, swingType)
            if issecretvalue and issecretvalue(duration) then return end
            if type(duration) ~= "number" or duration <= 0 then return end
            K.ForEach("swing", function(e)
                local c = e.swc
                if c and c.ticksOn and ((e.rec.driver and e.rec.driver.swingType) or 0) == swingType then
                    c.dur = duration
                    PlaceTicks(e, c)
                end
            end)
        end)
    else
        Events.Off("PLAYER_SWING", "adswingclose")
    end
end

-- Called at the end of every style pass, after the fill rect is laid (and
-- after the off-hand track's pass, which may have split it).
function SC.Styled(e)
    local shell, rec = e.shell, e.rec
    local closing = Closing(rec)
    local ticking = K.R(rec, "fill", "swingTicks") == true
    if not (closing or ticking) then
        if shell._adSWC then Stop(shell, shell._adSWC) end
        e.swc = nil
        SC.SyncEvents()
        return
    end
    local c = Ensure(shell)
    e.swc = c
    -- a length from another hand, or from before the ticks went off, is stale
    local st = (rec.driver and rec.driver.swingType) or 0
    if c.st ~= st or not ticking then c.dur = nil end
    c.st = st
    c.vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    c.reverse = K.R(rec, "fill", "reverseFill") == true
    if closing then
        Hook(shell, c)
        c.active = true
        PaintMirror(e, c)
        Split(e, c)
    else
        c.active = false
        c.bar:Hide()
        c.sheen:Hide()
        Unsplit(shell, c)
    end
    c.ticksOn = ticking
    PlaceTicks(e, c)
    SC.SyncEvents()
end

function SC.Release(e)
    if e.swc then Stop(e.shell, e.swc) end
    e.swc = nil
    SC.SyncEvents()
end
