-- AD_ResourceCells: what a resource bar's points can wear beyond lit and dark.
-- Owns the bar-style recharge slots (runes, essence), the recharge countdown on
-- every recharging point, rogue charged points, the fold in half, and fading
-- Blizzard's own class bar; Bars\AD_Bars.lua and Bars\AD_ResourcePowers.lua
-- call it through Bars.ResCells at fixed points.
-- Power values only reach SetValue and the client's own countdown; what is
-- compared here (maxima, the charged list) is plain or skipped.
local ADDON, NS = ...
local Bars = NS.Bars
if not Bars then return end
local K = Bars.Kit

local RC = {}
Bars.ResCells = RC

RC.COMBO, RC.RUNES, RC.ESSENCE = 4, 5, 19
RC.DIM = 0.5
RC.INTERP_SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
RC.KEY = "adrescells"

local function Plain(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "number"
end

-- Which way a recharging point fills: the bar's own way, or a fixed one.
RC.DIRS = {
    right = { "HORIZONTAL", false }, left = { "HORIZONTAL", true },
    up = { "VERTICAL", false }, down = { "VERTICAL", true },
}

-- Gates

function RC.Recharges(entry)
    local pt = entry.powerType
    return (pt == RC.RUNES or pt == RC.ESSENCE) and NS.IsForever ~= true
end

function RC.Folded(entry)
    if entry.kind ~= "resource" or K.R(entry.rec, "resource", "foldOn") ~= true then return false end
    return NS.Schema.Foldable(entry.rec) == true
end

function RC.ChargedOn(entry)
    return entry.powerType == RC.COMBO and NS.IsForever ~= true
        and K.R(entry.rec, "resource", "chargedShow") == true
end

function RC.Half(n) return math.max(1, math.ceil(n / 2)) end

-- the cells a pips bar lays (half when folded)
function RC.CellCount(entry, n)
    if RC.Folded(entry) then return RC.Half(n) end
    return n
end

-- the continuous fill's range and the tick unit: half when folded
function RC.FillRange(entry, range)
    if range and RC.Folded(entry) then return RC.Half(range) end
    return range
end

-- A bar-style rune or essence bar draws its points in slots; the count's own
-- fill would glide behind them, so it steps.
function RC.NoSmooth(entry)
    return not entry.pipsOn and entry.rsOn == true
end

function RC.Drain(entry)
    return K.R(entry.rec, "resource", "rechargeFill") == "down"
end

-- the orientation a recharging layer fills in
function RC.ApplyDir(entry, bar)
    local rec = entry.rec
    local d = RC.DIRS[K.R(rec, "resource", "rechargeDir") or "bar"]
    if d then
        bar:SetOrientation(d[1])
        bar:SetReverseFill(d[2])
    else
        bar:SetOrientation((K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
        bar:SetReverseFill(K.R(rec, "fill", "reverseFill") == true)
    end
end

-- A recharging point draws dimmer than a full one: the bar's own recharge
-- colour, else the cell's lit colour (c.pr..c.pa) at half brightness.
function RC.RechargeColor(entry, c)
    local rec = entry.rec
    if K.R(rec, "resource", "rechargeColorEnabled") == true then
        local col = K.R(rec, "resource", "rechargeColor") or { 0.4, 0.4, 0.4, 1 }
        return col[1], col[2], col[3], col[4] or 1
    end
    if c.pr == nil then return nil end
    return c.pr * RC.DIM, c.pg * RC.DIM, c.pb * RC.DIM, c.pa or 1
end

-- Recharge text: a Cooldown widget with no swipe on every point, fed the same
-- duration object that fills it, so the client counts down C-side.

function RC.StyleText(entry, cd)
    local rec = entry.rec
    local show = K.R(rec, "text", "rcShow") == true
    cd:SetHideCountdownNumbers(not show)
    if not show then return end
    if cd.SetCountdownFormatter and NS.Factory and NS.Factory.TimerFormatter then
        local decTo = (K.R(rec, "text", "rcDecimalsEnabled") == true) and (K.R(rec, "text", "rcDecimalThreshold") or 3) or 0
        local fmt = NS.Factory.TimerFormatter(decTo, nil, 0, nil, K.BarRounding(rec))
        local sig = fmt or "stock"
        if cd._adFmtSig ~= sig then
            cd._adFmtSig = sig
            cd:SetCountdownFormatter(fmt)
        end
    end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not fs then return end
    local fo = K.StyleFont(fs, entry, "rccd", K.R(rec, "text", "rcSize") or 12,
        K.R(rec, "text", "rcOutline") or "OUTLINE", K.R(rec, "text", "rcShadow") == true)
    -- the widget re-applies its countdown font on every start: hand it ours by name
    if fo and cd.SetCountdownFont and cd._adFontName ~= fo:GetName() then
        cd._adFontName = fo:GetName()
        cd:SetCountdownFont(fo:GetName())
    end
    local col = K.R(rec, "text", "rcColor") or { 1, 1, 1, 1 }
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    K.PlaceText(fs, cd, K.R(rec, "text", "rcAnchor") or "CENTER",
        K.R(rec, "text", "rcOffsetX"), K.R(rec, "text", "rcOffsetY"))
end

-- A recharge countdown sits on the marks rung: over the bar glows, under the
-- bar's ticks and texts, still the top of its point.
function RC.TextLevel(entry)
    return entry.shell.fill:GetFrameLevel() + Bars.LADDER.marks
end

function RC.EnsureText(entry, c, parent, region, level)
    local cd = c.rc
    if not cd then
        cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
        cd:SetDrawSwipe(false)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        -- the widget hides numbers under its minimum duration by default
        if cd.SetMinimumCountdownDuration then cd:SetMinimumCountdownDuration(0) end
        cd:EnableMouse(false)
        c.rc = cd
    end
    cd:ClearAllPoints()
    cd:SetAllPoints(region)
    cd:SetFrameLevel(level)
    RC.StyleText(entry, cd)
    cd:Show()
    return cd
end

-- d: the point's duration object while it recharges, nil otherwise
function RC.Text(entry, c, d)
    local cd = c and c.rc
    if not cd then return end
    if d and K.R(entry.rec, "text", "rcShow") == true and cd.SetCooldownFromDurationObject then
        cd:SetCooldownFromDurationObject(d, true)
    else
        cd:Clear()
    end
end

local function DropText(c)
    if c and c.rc then
        c.rc:Clear()
        c.rc:Hide()
    end
end

-- A shared duration object per point, kept on the entry under its own key.
function RC.Dur(entry, key, i)
    entry[key] = entry[key] or {}
    local d = entry[key][i]
    if not d and C_DurationUtil and C_DurationUtil.CreateDuration then
        d = C_DurationUtil.CreateDuration()
        entry[key][i] = d
    end
    return d
end

-- A layer's texture, direction and shape: the cell's own (its mask and
-- rotation), re-run after every layout. maskKey names the layer's own mask.
function RC.StyleLayer(entry, p, layer, maskKey, recharge)
    local rec = entry.rec
    if recharge then
        RC.ApplyDir(entry, layer)
    else
        layer:SetOrientation((K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
        layer:SetReverseFill(K.R(rec, "fill", "reverseFill") == true)
    end
    local path = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    local pk = maskKey .. "Path"
    if p[pk] ~= path then
        p[pk] = path
        layer:SetStatusBarTexture(path)
    end
    p[maskKey] = p[maskKey] or layer:CreateMaskTexture()
    local m = p[maskKey]
    local shape = K.R(rec, "resource", "pipShape") or "square"
    local rot = (shape == "diamond") and (math.pi / 4) or 0
    -- a texture swap makes a new object: the mask goes on whatever is current
    local tex = layer:GetStatusBarTexture()
    local tk = maskKey .. "Tex"
    if p[tk] ~= tex then
        p[tk] = tex
        tex:AddMaskTexture(m)
    end
    tex:SetRotation(rot)
    m:SetTexture((shape == "circle") and Bars.PIP_CIRCLE_MASK or K.WHITE,
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", (shape == "square") and "NEAREST" or "LINEAR")
    m:ClearAllPoints()
    m:SetRotation(rot)
    m:SetAllPoints(p.maskLit)
end

-- Pips

-- A pips cell's second lap when folded: its own lit bar over the first, the
-- window (half + i - 0.5, half + i), so the count past the middle lights it.
function RC.EnsureLap(entry, p, i, half)
    local lap = p.lap2
    if not lap then
        lap = CreateFrame("StatusBar", nil, p.f)
        lap:SetStatusBarTexture(K.WHITE)
        p.lap2 = lap
    end
    lap:SetFrameLevel(p.f:GetFrameLevel() + 3)
    lap:ClearAllPoints()
    lap:SetAllPoints(p.litBar)
    RC.StyleLayer(entry, p, lap, "lapMask", false)
    lap:SetMinMaxValues(half + i - 0.5, half + i)
    lap:Show()
end

-- after LayoutPips: the recharge layer, its text and the second lap on every cell
function RC.PipsLaid(entry)
    local n = entry.pipCount or 0
    local rech = RC.Recharges(entry)
    local folded = RC.Folded(entry)
    for i = 1, n do
        local p = entry.pips[i]
        if p then
            p.rbar = p.litBar
            if rech and entry.powerType == RC.RUNES then RC.ApplyDir(entry, p.litBar) end
            if rech then
                RC.EnsureText(entry, p, p.f, p.f, RC.TextLevel(entry))
            else
                DropText(p)
            end
            if folded then
                RC.EnsureLap(entry, p, i, n)
            elseif p.lap2 then
                p.lap2:Hide()
            end
            if rech and entry.isPreview then
                RC.PvLayer(entry, p)
            elseif p.pv then
                p.pv:Hide()
            end
        end
    end
    if entry.isPreview then
        -- a preview marks two points charged, so the colours can be set
        entry.chargedSet = RC.ChargedOn(entry) and { [2] = true, [4] = true } or nil
        entry.pvK = nil
    else
        RC.ReadCharged(entry)
    end
end

-- Bar style

local function PlaceAlong(region, host, vertical, rev, a, len, cross)
    region:ClearAllPoints()
    if vertical then
        region:SetSize(cross, len)
        if rev then
            region:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -a)
        else
            region:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, a)
        end
    else
        region:SetSize(len, cross)
        if rev then
            region:SetPoint("TOPRIGHT", host, "TOPRIGHT", -a, 0)
        else
            region:SetPoint("TOPLEFT", host, "TOPLEFT", a, 0)
        end
    end
end

function RC.EnsureSlot(entry, i)
    entry.rslots = entry.rslots or {}
    local s = entry.rslots[i]
    if s then return s end
    local host = entry.rsHost
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetStatusBarTexture(K.WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local chg = CreateFrame("StatusBar", nil, host)
    chg:SetStatusBarTexture(K.WHITE)
    chg:SetMinMaxValues(i - 0.5, i)
    chg:SetValue(0)
    local chgDim = host:CreateTexture(nil, "ARTWORK")
    chgDim:SetTexture(K.WHITE)
    s = { bar = bar, chg = chg, chgDim = chgDim }
    entry.rslots[i] = s
    return s
end

local function HideSlot(s)
    s.bar:Hide()
    s.chg:Hide()
    s.chgDim:Hide()
    DropText(s)
end

-- the fold's second lap on a bar: one bar over the fill, range (half, 2 x half)
function RC.LayoutFold(entry)
    local fb = entry.foldBar
    if entry.pipsOn or not RC.Folded(entry) then
        if fb then fb:Hide() end
        entry.foldOn = false
        return
    end
    local shell, rec = entry.shell, entry.rec
    if not fb then
        fb = CreateFrame("StatusBar", nil, shell)
        fb:SetStatusBarTexture(K.WHITE)
        entry.foldBar = fb
    end
    fb:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
    fb:ClearAllPoints()
    fb:SetAllPoints(shell.fill)
    fb:SetOrientation((K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL" and "VERTICAL" or "HORIZONTAL")
    fb:SetReverseFill(K.R(rec, "fill", "reverseFill") == true)
    local path = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    if entry.foldPath ~= path then
        entry.foldPath = path
        fb:SetStatusBarTexture(path)
    end
    local half = RC.Half(Bars.PlainMax(entry) or 2)
    fb:SetMinMaxValues(half, half * 2)
    fb:Show()
    entry.foldOn = true
end

-- After the bar laid out (bar style): runes and essence draw each point in
-- its stretch of the fill, charged points mark theirs. The stretches come
-- from the fill's size, whole pixels, the first at the fill's start.
function RC.BarLaid(entry)
    RC.LayoutFold(entry)
    local rech = RC.Recharges(entry)
    local chg = RC.ChargedOn(entry)
    if not (rech or chg) then
        for _, s in ipairs(entry.rslots or {}) do HideSlot(s) end
        entry.rsOn, entry.chgOn, entry.rsCount = false, false, 0
        return
    end
    local shell, rec = entry.shell, entry.rec
    if Bars.RectHidden(shell.fill) then return end   -- pinned to a nameplate
    local W, H = shell.fill:GetWidth() or 0, shell.fill:GetHeight() or 0
    if W <= 0 or H <= 0 then return end              -- OnSizeChanged lays it again
    local range = Bars.PlainMax(entry)
    local n = (range and range >= 1 and range <= 20) and math.floor(range) or 0
    n = RC.CellCount(entry, n)
    if not entry.rsHost then
        local host = CreateFrame("Frame", nil, shell)
        host:SetAllPoints(shell.fill)
        entry.rsHost = host
    end
    local host = entry.rsHost
    host:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
    local vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = K.R(rec, "fill", "reverseFill") == true
    local px = K.Px(shell)
    local L, cross = vertical and H or W, vertical and W or H
    local path = K.ResolveBarTexture(K.R(rec, "fill", "texture"))
    for i = 1, n do
        local s = RC.EnsureSlot(entry, i)
        local a = math.floor(L * (i - 1) / n / px + 0.5) * px
        local b = math.floor(L * i / n / px + 0.5) * px
        local len = math.max(px, b - a)
        if rech then
            PlaceAlong(s.bar, host, vertical, rev, a, len, cross)
            s.bar:SetFrameLevel(host:GetFrameLevel() + 1)
            if s.barPath ~= path then
                s.barPath = path
                s.bar:SetStatusBarTexture(path)
            end
            RC.ApplyDir(entry, s.bar)
            s.bar:Show()
            s.rbar = s.bar
            RC.EnsureText(entry, s, host, s.bar, RC.TextLevel(entry))
        else
            s.bar:Hide()
            DropText(s)
        end
        if chg then
            PlaceAlong(s.chg, host, vertical, rev, a, len, cross)
            PlaceAlong(s.chgDim, host, vertical, rev, a, len, cross)
            s.chg:SetFrameLevel(host:GetFrameLevel() + 2)
            s.chg:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
            s.chg:SetReverseFill(rev)
            if s.chgPath ~= path then
                s.chgPath = path
                s.chg:SetStatusBarTexture(path)
            end
            s.chg:SetMinMaxValues(i - 0.5, i)
        else
            s.chg:Hide()
            s.chgDim:Hide()
        end
    end
    for i = n + 1, #(entry.rslots or {}) do HideSlot(entry.rslots[i]) end
    entry.rsOn, entry.chgOn, entry.rsCount = rech, chg, n
    if entry.isPreview then
        entry.chargedSet = chg and { [2] = true, [4] = true } or nil
        entry.pvK = nil
    else
        RC.ReadCharged(entry)
    end
    RC.Painted(entry)
    -- a re-laid slot is fed afresh
    if rech and Bars.ResPowers then Bars.ResPowers.SlotsLaid(entry) end
end

-- Colours, after the pips painted or the bar's colour changed

function RC.Painted(entry)
    local rec = entry.rec
    local set = RC.ChargedOn(entry) and entry.chargedSet or nil
    local cc = set and (K.R(rec, "resource", "chargedColor") or { 0.169, 0.733, 0.992, 1 })
    if entry.pipsOn then
        local n = entry.pipCount or 0
        if RC.Folded(entry) then
            local fc = K.R(rec, "resource", "foldColor") or { 1, 0.5, 0, 1 }
            for i = 1, n do
                local p = entry.pips[i]
                if p and p.lap2 then p.lap2:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1) end
            end
        end
        -- charged cells of the first lap: lit in the charged colour, half bright before
        if set then
            for i = 1, n do
                local p = entry.pips[i]
                if p and set[i] then
                    p.litBar:SetStatusBarColor(cc[1], cc[2], cc[3], cc[4] or 1)
                    p.dim:SetVertexColor(cc[1] * RC.DIM, cc[2] * RC.DIM, cc[3] * RC.DIM, cc[4] or 1)
                end
            end
        end
        return
    end
    local r, g, b, a = entry.cr, entry.cg, entry.cb, entry.ca
    if r == nil then r, g, b, a = K.BarColorOf(rec) end
    for i = 1, entry.rsCount or 0 do
        local s = entry.rslots[i]
        s.pr, s.pg, s.pb, s.pa, s.tinted = r, g, b, a or 1, nil
        if entry.chgOn and set and set[i] then
            s.chg:SetStatusBarColor(cc[1], cc[2], cc[3], cc[4] or 1)
            s.chgDim:SetVertexColor(cc[1] * RC.DIM, cc[2] * RC.DIM, cc[3] * RC.DIM, cc[4] or 1)
            s.chg:Show()
            s.chgDim:Show()
        else
            s.chg:Hide()
            s.chgDim:Hide()
        end
    end
    if entry.foldOn and entry.foldBar then
        local fc = K.R(rec, "resource", "foldColor") or { 1, 0.5, 0, 1 }
        entry.foldBar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
    end
end

-- The value into the extra lit layers (second laps, charged slots): sinks only.
function RC.Feed(entry, cur)
    if entry.pipsOn then
        if not RC.Folded(entry) then return end
        for i = 1, entry.pipCount or 0 do
            local p = entry.pips[i]
            if p and p.lap2 then p.lap2:SetValue(cur) end
        end
        return
    end
    if entry.foldOn and entry.foldBar then
        local interp = (K.R(entry.rec, "fill", "smoothing") ~= false) and RC.INTERP_SMOOTH or nil
        if interp then entry.foldBar:SetValue(cur, interp) else entry.foldBar:SetValue(cur) end
    end
    if entry.chgOn then
        for i = 1, entry.rsCount or 0 do entry.rslots[i].chg:SetValue(cur) end
    end
end

-- Charged combo points: GetUnitChargedPowerPoints lists them. A secret or
-- restricted answer is unknown and keeps the last list.
function RC.ReadCharged(entry)
    if not RC.ChargedOn(entry) or entry.isPreview then return end
    local f = GetUnitChargedPowerPoints
    if not f then
        entry.chargedSet = nil
        return
    end
    local CS = C_Secrets
    if CS and CS.ShouldUnitPowerBeSecret then
        local s = CS.ShouldUnitPowerBeSecret("player", RC.COMBO)
        if (issecretvalue and issecretvalue(s)) or s == true then return end
    end
    local t = f("player")
    if t == nil then
        entry.chargedSet = {}
        return
    end
    if (issecretvalue and issecretvalue(t)) or type(t) ~= "table" then return end
    local set = {}
    for _, i in ipairs(t) do
        if Plain(i) then set[i] = true end
    end
    entry.chargedSet = set
end

local function ChargedEvent(_, unit)
    if unit ~= nil and not (issecretvalue and issecretvalue(unit)) and unit ~= "player" then return end
    K.ForEach("resource", function(e)
        if RC.ChargedOn(e) then
            RC.ReadCharged(e)
            -- the colour memo busted: the refresh repaints every cell, then these
            e.cr = nil
            K.ResourceRefresh(e)
        end
    end)
end

-- Blizzard's own class bar: faded to nothing (alpha is a sink, so its layout
-- never runs from here) and its mouse off, so no tooltip hides under it.
-- Mouse changes wait for the end of combat.
RC.BLIZZ = { [5] = "RuneFrame", [7] = "WarlockPowerFrame", [9] = "PaladinPowerBarFrame",
    [12] = "MonkHarmonyBarFrame", [16] = "MageArcaneChargesFrame", [19] = "EssencePlayerFrame",
    [100] = "MonkStaggerBar", [103] = "DemonHunterSoulFragmentsBar" }
RC.faded = {}
RC.hooked = {}

function RC.HasBlizzardBar(pt)
    if NS.IsForever == true then return false end
    return pt == RC.COMBO or RC.BLIZZ[pt] ~= nil
end

function RC.BlizzFrame(pt)
    if NS.IsForever == true then return nil end
    if pt == RC.COMBO then
        local _, tag = UnitClass("player")
        return _G[(tag == "DRUID") and "DruidComboPointBarFrame" or "RogueComboPointBarFrame"]
    end
    local name = RC.BLIZZ[pt]
    return name and _G[name] or nil
end

function RC.MouseSync()
    if InCombatLockdown and InCombatLockdown() then
        RC.mousePending = true
        return
    end
    RC.mousePending = false
    for f, st in pairs(RC.faded) do
        if not st.mouseOff then
            st.mouseOff, st.mouse = true, {}
            for _, r in ipairs({ f, f:GetChildren() }) do
                if r.IsMouseEnabled and r:IsMouseEnabled() then
                    st.mouse[#st.mouse + 1] = r
                    r:EnableMouse(false)
                end
            end
        end
    end
    for f, st in pairs(RC.restore or {}) do
        for _, r in ipairs(st.mouse or {}) do r:EnableMouse(true) end
        RC.restore[f] = nil
    end
end

function RC.Fade(f)
    local st = { alpha = f:GetAlpha() }
    if not Plain(st.alpha) then st.alpha = 1 end
    RC.faded[f] = st
    f:SetAlpha(0)
    -- the game can set the alpha again (a fade, a vehicle): it goes back to 0
    if not RC.hooked[f] and hooksecurefunc then
        RC.hooked[f] = true
        hooksecurefunc(f, "SetAlpha", function(self)
            if RC.faded[self] and not RC.busy then
                RC.busy = true
                self:SetAlpha(0)
                RC.busy = false
            end
        end)
    end
end

function RC.Unfade(f)
    local st = RC.faded[f]
    RC.faded[f] = nil
    if not st then return end
    RC.busy = true
    f:SetAlpha(st.alpha or 1)
    RC.busy = false
    if st.mouseOff then
        RC.restore = RC.restore or {}
        RC.restore[f] = st
    end
end

function RC.SyncBlizzard()
    if NS.IsForever == true then return end
    local want = {}
    K.ForEach("resource", function(e)
        if not e.isPreview and K.R(e.rec, "resource", "hideBlizzard") == true then
            local f = RC.BlizzFrame(e.powerType)
            if f then want[f] = true end
        end
    end)
    for f in pairs(RC.faded) do
        if not want[f] then RC.Unfade(f) end
    end
    for f in pairs(want) do
        if not RC.faded[f] then RC.Fade(f) end
    end
    RC.MouseSync()
end

-- Events (own key): charged points move on UNIT_POWER_POINT_CHARGE; a mouse
-- change held back by combat lands when it ends.
function RC.Sync()
    local charged = false
    K.ForEach("resource", function(e) if RC.ChargedOn(e) then charged = true end end)
    if charged and not RC.armedCharged then
        RC.armedCharged = true
        K.SafeOn("UNIT_POWER_POINT_CHARGE", RC.KEY, ChargedEvent)
    elseif not charged and RC.armedCharged then
        RC.armedCharged = false
        NS.Events.Off("UNIT_POWER_POINT_CHARGE", RC.KEY)
    end
    RC.SyncBlizzard()
    local regen = RC.mousePending == true
    if regen and not RC.armedRegen then
        RC.armedRegen = true
        K.SafeOn("PLAYER_REGEN_ENABLED", RC.KEY, function()
            RC.MouseSync()
            if not RC.mousePending then
                RC.armedRegen = false
                NS.Events.Off("PLAYER_REGEN_ENABLED", RC.KEY)
            end
        end)
    end
end

-- after Bars.Release took the entry out of `live`
function RC.Release(entry)
    for _, p in ipairs(entry.pips or {}) do DropText(p) end
    for _, s in ipairs(entry.rslots or {}) do HideSlot(s) end
    entry.rsOn, entry.chgOn, entry.rsCount, entry.chargedSet = false, false, 0, nil
end

-- Editor preview: the live layers magnified. The point after the lit ones
-- recharges on a sample 8 s timer (restarted when it ends) with its colour,
-- direction and text; charged and folded points paint as live.
RC.SAMPLE = 8

function RC.PvLayer(entry, p)
    local pv = p.pv
    if not pv then
        pv = CreateFrame("StatusBar", nil, p.f)
        pv:SetStatusBarTexture(K.WHITE)
        p.pv = pv
    end
    pv:SetFrameLevel(p.f:GetFrameLevel() + 1)
    p.litBar:SetFrameLevel(p.f:GetFrameLevel() + 2)
    pv:ClearAllPoints()
    pv:SetAllPoints(p.litBar)
    RC.StyleLayer(entry, p, pv, "pvMask", true)
    pv:Show()
    return pv
end

function RC.PreviewPaint(entry, cur)
    if not entry.pipsOn then RC.Painted(entry) end
    RC.Feed(entry, cur)
    if not RC.Recharges(entry) then return end
    local cells, n
    if entry.pipsOn then
        cells, n = entry.pips, entry.pipCount or 0
    else
        cells, n = entry.rslots, entry.rsCount or 0
    end
    if not cells or n == 0 then return end
    local k = math.floor(cur) + 1
    local now = GetTime()
    local restart = entry.pvK ~= k or now >= (entry.pvEnd or 0)
    for i = 1, n do
        local c = cells[i]
        -- the layer is laid by PipsLaid / BarLaid: nothing to paint before that
        local layer = c and (entry.pipsOn and c.pv or c.bar)
        if layer then
            if i == k and restart then
                local d = RC.Dur(entry, "pvDur", 1)
                if d and d.SetTimeFromStart then d:SetTimeFromStart(now - RC.SAMPLE * 0.4, RC.SAMPLE) end
                local r, g, b, a = RC.RechargeColor(entry, c)
                if r then layer:SetStatusBarColor(r, g, b, a) end
                if not (d and K.FeedStatusBarTimer(layer, d, true, RC.Drain(entry))) then
                    layer:SetMinMaxValues(0, 1)
                    layer:SetValue(0.4)
                end
                layer:SetAlpha(1)
                RC.Text(entry, c, d)
            elseif i ~= k and (restart or c.pvLit) then
                layer:SetMinMaxValues(0, 1)
                layer:SetValue(0)
                RC.Text(entry, c, nil)
            end
            c.pvLit = (i == k)
        end
    end
    if restart then
        entry.pvK, entry.pvEnd = k, now + RC.SAMPLE * 0.6
    end
end
