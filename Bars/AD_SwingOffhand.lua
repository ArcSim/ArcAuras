-- AD_SwingOffhand: the off-hand's swing as a second track on a main-hand swing bar.
-- Owns that track; the bars runtime calls in through Bars.SwingOH when it styles, refreshes, releases or previews a swing bar.
-- PLAYER_SWING's duration is plain, so the track is GetTime math like the main fill and holds in combat.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.SwingHandExists) then return end
local Events = NS.Events

local OH = {}
Bars.SwingOH = OH

local OFF_HAND = 1
-- Line thickness in physical pixels; two is the least that never vanishes.
local LINE_PX = { thin = 2, thick = 4 }
local armed = false

local function Merged(e)
    local rec = e.rec
    return rec.barKind == "swing" and ((rec.driver and rec.driver.swingType) or 0) == 0
        and K.R(rec, "fill", "swingOffhand") == true
end

-- An editor preview shows the track even on a character without an off-hand.
local function HandPresent(e)
    if e.isPreview then return true end
    return C_SwingTimer ~= nil and K.SwingHandExists(OFF_HAND) == true
end

-- The widgets live on the shell, which can outlive the entry that built them.
local function Ensure(shell)
    local o = shell._adOH
    if o then return o end
    o = {}
    o.track = CreateFrame("Frame", nil, shell)
    o.track:EnableMouse(false)
    o.bar = CreateFrame("StatusBar", nil, o.track)
    o.bar:EnableMouse(false)
    o.bar:SetAllPoints(o.track)
    o.bar:SetMinMaxValues(0, 1)
    -- An invisible copy of the off-hand fill across the whole bar: the label
    -- rides its moving edge at the bar's own height, whatever the style.
    o.follow = CreateFrame("StatusBar", nil, o.track)
    o.follow:EnableMouse(false)
    o.follow:SetMinMaxValues(0, 1)
    o.follow:SetStatusBarTexture(K.WHITE)
    o.follow:SetStatusBarColor(1, 1, 1, 0)
    -- the mark and the label ride the follower, on the marks rung: over the
    -- bar glows, under the bar's ticks and texts; the mark still sits on the
    -- off-hand fill's edge (PlaceMark), under the label and the follower's
    -- clear fill as before
    o.mark = o.follow:CreateTexture(nil, "BACKGROUND")
    o.label = o.follow:CreateFontString(nil, "OVERLAY")
    o.label:Hide()
    shell._adOH = o
    return o
end

local function Stop(o)
    o.running = false
    o.active = false
    o.bar:SetScript("OnUpdate", nil)
    o.mark:Hide()
    o.label:Hide()
    o.track:Hide()
end

-- Between swings the track rests like the main fill: empty when it drains or
-- when "Empty fill when idle" is on, else full.
local function Idle(e)
    local o = e.oh
    if not o then return end
    o.running = false
    o.bar:SetScript("OnUpdate", nil)
    local drain = (K.R(e.rec, "fill", "fillMode") or "drain") == "drain"
    local empty = drain or K.R(e.rec, "fill", "idleEmpty") == true
    o.bar:SetMinMaxValues(0, 1)
    o.bar:SetValue(empty and 0 or 1)
    o.follow:SetMinMaxValues(0, 1)
    o.follow:SetValue(empty and 0 or 1)
    o.mark:Hide()
    o.label:Hide()
    if e.isPreview then o.pvAt = GetTime() + 0.35 end
end

local function Run(e, duration)
    local o = e.oh
    if not (o and o.active) then return end
    if issecretvalue and issecretvalue(duration) then return end
    duration = tonumber(duration) or 0
    if duration <= 0 then return end
    local drain = (K.R(e.rec, "fill", "fillMode") or "drain") == "drain"
    o.running = true
    o.duration = duration
    o.endTime = GetTime() + duration
    o.bar:SetMinMaxValues(0, duration)
    o.bar:SetValue(drain and duration or 0)
    o.follow:SetMinMaxValues(0, duration)
    o.follow:SetValue(drain and duration or 0)
    o.mark:SetShown(o.style == "mark")
    o.label:SetShown(o.labelOn == true)
    o.bar:SetScript("OnUpdate", function(bar)
        local remaining = o.endTime - GetTime()
        if remaining <= 0 then
            Idle(e)
            return
        end
        local v = drain and remaining or (o.duration - remaining)
        bar:SetValue(v)
        o.follow:SetValue(v)
    end)
end

local function Paint(e, o)
    local rec, shell = e.rec, e.shell
    o.vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    o.reverse = K.R(rec, "fill", "reverseFill") == true
    -- above the main fill, under the bar's text overlay
    local lvl = shell.fill:GetFrameLevel()
    o.track:SetFrameLevel(lvl + 1)
    o.bar:SetFrameLevel(lvl + 2)
    o.bar:SetOrientation(o.vertical and "VERTICAL" or "HORIZONTAL")
    o.bar:SetReverseFill(o.reverse)
    local tex = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    if o.tex ~= tex then
        -- a texture swap makes a new texture object
        o.tex = tex
        o.bar:SetStatusBarTexture(tex)
        local t = o.bar:GetStatusBarTexture()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        o.fillTex = t
    end
    o.bar:SetRotatesTexture(K.R(rec, "fill", "rotateTexture") == true)
    o.follow:SetFrameLevel(lvl + Bars.LADDER.marks)
    o.follow:SetOrientation(o.vertical and "VERTICAL" or "HORIZONTAL")
    o.follow:SetReverseFill(o.reverse)
    o.labelOn = K.R(rec, "fill", "swingOffhandLabel") == true
    if o.labelOn then
        K.StyleFont(o.label, e, "ohlabel", K.R(rec, "fill", "swingOffhandLabelSize") or 10, "OUTLINE", false)
        local lc = K.R(rec, "fill", "swingOffhandLabelColor") or { 1, 1, 1, 1 }
        o.label:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1)
        o.label:SetText(K.R(rec, "fill", "swingOffhandLabelText") or "OH")
    end
    local c = K.R(rec, "fill", "swingOffhandColor") or { 1, 0.75, 0.3, 1 }
    if o.style == "mark" then
        -- the bar only supplies a moving edge for the mark to ride
        o.bar:SetStatusBarColor(1, 1, 1, 0)
        o.mark:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    else
        o.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
end

-- The mark sits on the off-hand fill's moving edge, two pixels across.
local function PlaceMark(o, px)
    local ft, mk = o.fillTex, o.mark
    if not ft then return end
    mk:ClearAllPoints()
    if o.vertical then
        local edge = o.reverse and "BOTTOM" or "TOP"
        mk:SetPoint("TOPLEFT", ft, edge .. "LEFT", 0, px)
        mk:SetPoint("BOTTOMRIGHT", ft, edge .. "RIGHT", 0, -px)
    else
        local edge = o.reverse and "LEFT" or "RIGHT"
        mk:SetPoint("TOPLEFT", ft, "TOP" .. edge, -px, 0)
        mk:SetPoint("BOTTOMRIGHT", ft, "BOTTOM" .. edge, px, 0)
    end
end

-- The label rides the follower's moving edge: centred on it, or just outside
-- the bar (a standing bar: its left or right side). Anchors only, so the edge
-- carries it with no work per frame.
local function PlaceLabel(e, o, px)
    local shell, inset = e.shell, e.fillInset or 0
    o.follow:ClearAllPoints()
    o.follow:SetPoint("TOPLEFT", shell, "TOPLEFT", inset, -inset)
    o.follow:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset, inset)
    local ft, lb = o.follow:GetStatusBarTexture(), o.label
    local pos = K.R(e.rec, "fill", "swingOffhandLabelPos") or "on"
    local gap = 2 * px
    lb:ClearAllPoints()
    if o.vertical then
        local edge = o.reverse and "BOTTOM" or "TOP"
        if pos == "above" then
            lb:SetPoint("RIGHT", ft, edge .. "LEFT", -gap, 0)
        elseif pos == "below" then
            lb:SetPoint("LEFT", ft, edge .. "RIGHT", gap, 0)
        else
            lb:SetPoint("CENTER", ft, edge, 0, 0)
        end
    else
        local edge = o.reverse and "LEFT" or "RIGHT"
        if pos == "above" then
            lb:SetPoint("BOTTOM", ft, "TOP" .. edge, 0, gap)
        elseif pos == "below" then
            lb:SetPoint("TOP", ft, "BOTTOM" .. edge, 0, -gap)
        else
            lb:SetPoint("CENTER", ft, edge, 0, 0)
        end
    end
end

-- Splits the fill rect ApplyStyle just laid (entry.fillInset): the main hand
-- keeps the top (a vertical bar: the left), the off-hand takes a strip along
-- the bottom (the right). Every length comes from settings, never a rect read,
-- so the split sits on whole pixels from the first frame. False = too thin.
local function Layout(e, o)
    local rec, shell = e.rec, e.shell
    local fill = shell.fill
    local inset = e.fillInset or 0
    local px = K.Px(shell)
    o.track:ClearAllPoints()
    if o.style == "mark" then
        o.track:SetAllPoints(fill)
        PlaceMark(o, px)
        return true
    end
    -- the bar's cross size, snapped the way the layout engine sizes its frame
    local hp = K.Px(e.holder)
    local sc = K.R(rec, "size", "scale") or 1
    local raw = o.vertical and math.max(1, (K.R(rec, "size", "width") or 220) * sc)
        or math.max(1, (K.R(rec, "size", "height") or 16) * sc)
    local inner = math.max(hp, math.floor(raw / hp + 0.5) * hp) - 2 * inset
    local th = (o.style == "half") and (math.floor(inner / 2 / px) * px)
        or ((LINE_PX[o.style] or 2) * px)
    if th < px or inner - th < px then return false end
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", shell, "TOPLEFT", inset, -inset)
    if o.vertical then
        fill:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset - th, inset)
        o.track:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -inset, -inset)
        o.track:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset, inset)
        o.track:SetWidth(th)
    else
        fill:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset, inset + th)
        o.track:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", inset, inset)
        o.track:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset, inset)
        o.track:SetHeight(th)
    end
    return true
end

-- A weapon swap can add or drop the off-hand: restyle only the bars whose
-- answer changed.
local function Presence()
    K.ForEach("swing", function(e)
        local o = e.oh
        if o and Merged(e) and HandPresent(e) ~= o.present then K.ApplyStyle(e) end
    end)
end

function OH.SyncEvents()
    local want = false
    if C_SwingTimer and Events then
        K.ForEach("swing", function(e) if Merged(e) then want = true end end)
    end
    if want == armed then return end
    armed = want
    if want then
        Events.On("PLAYER_SWING", "adswingoh", function(_, duration, swingType)
            if swingType ~= OFF_HAND then return end
            K.ForEach("swing", function(e)
                if e.oh and e.oh.active then Run(e, duration) end
            end)
        end)
        Events.On("WEAPON_SLOT_CHANGED", "adswingoh", Presence)
        Events.On("UNIT_ATTACK_SPEED", "adswingoh", function(_, unit)
            if unit == "player" then Presence() end
        end)
    else
        Events.Off("PLAYER_SWING", "adswingoh")
        Events.Off("WEAPON_SLOT_CHANGED", "adswingoh")
        Events.Off("UNIT_ATTACK_SPEED", "adswingoh")
    end
end

-- Called at the end of every style pass, after the fill rect is laid.
function OH.Styled(e)
    local shell = e.shell
    if not Merged(e) then
        if shell._adOH then Stop(shell._adOH) end
        e.oh = nil
        OH.SyncEvents()
        return
    end
    local o = Ensure(shell)
    e.oh = o
    o.style = K.R(e.rec, "fill", "swingOffhandStyle") or "thin"
    o.present = HandPresent(e)
    local ok = false
    if o.present then
        Paint(e, o)
        ok = Layout(e, o)
    end
    if not ok then
        Stop(o)
        OH.SyncEvents()
        return
    end
    o.active = true
    o.track:Show()
    PlaceLabel(e, o, K.Px(shell))
    if o.running then o.label:SetShown(o.labelOn == true) else Idle(e) end
    OH.SyncEvents()
    -- Tick marks size themselves from the fill's height, which moves only on
    -- the next layout: lay them out again then.
    if not e.isPreview and Events and Events.Coalesce then
        Events.Coalesce("adswingohticks", function()
            K.ForEach("swing", function(x)
                if x.oh and x.oh.active then K.LayoutTicks(x) end
            end)
        end)
    end
end

function OH.Refresh(e)
    local o = e.oh
    if o and o.active and not o.running then Idle(e) end
end

function OH.Release(e)
    if e.oh then Stop(e.oh) end
    e.oh = nil
    OH.SyncEvents()
end

-- The editor preview loops the track half a swing behind the main hand, so
-- both show moving.
function OH.Preview(e, loop, fresh)
    local o = e.oh
    if not (o and o.active) then return end
    local len = e.swingLen or 2.5
    if not loop then
        Idle(e)
        o.pvAt = nil
    elseif fresh then
        Idle(e)
        o.pvAt = GetTime() + len / 2
    elseif not o.running and o.pvAt and GetTime() >= o.pvAt then
        o.pvAt = nil
        Run(e, len)
    end
end
