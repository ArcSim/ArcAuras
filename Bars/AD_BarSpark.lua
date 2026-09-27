-- AD_BarSpark: a bright line on the moving edge of a swing or timer bar's fill while it runs.
-- Owns the spark textures; the bars runtime calls in through Bars.Spark when it styles, starts, idles or releases one of those bars.
-- Each spark is anchored to a fill texture's edge, so the game carries it with the fill: no reads and no per-frame Lua.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.WHITE and Bars.StripPx) then return end

local SP = {}
Bars.Spark = SP

-- The castbar spark's look when a record carries none.
SP.WIDTH = 3
SP.COLOR = { 1, 1, 1, 0.9 }

function SP.Wanted(e)
    return (e.kind == "swing" or e.kind == "timer") and K.R(e.rec, "fill", "edgeSpark") == true
end

local function NewSpark(shell)
    -- on the text host: over the fill and the swing ticks, under the texts
    local t = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 3)
    t:SetTexture(K.WHITE)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

-- The textures live on the shell, which can outlive the entry that built them.
local function Ensure(shell)
    local s = shell._adSpark
    if s then return s end
    s = { main = NewSpark(shell), mirror = NewSpark(shell) }
    shell._adSpark = s
    return s
end

-- Across the whole fill, n pixels thick and split in whole pixels either side
-- of the edge; a fill texture's moving edge is its far end, or its start when
-- the bar fills in reverse.
local function Place(sp, shell, ft, vertical, reverse, n, c)
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

-- Shown only while the bar runs: RunTimedFill starts a swing or timer, and the
-- idle look (SwingIdle, TimerStop) ends it.
function SP.Sync(e)
    local s = e.spark
    if not s then return end
    local on = e.running == true
    s.main:SetShown(on)
    s.mirror:SetShown(on and s.mirrorOn == true)
end

local function Hide(s)
    s.main:Hide()
    s.mirror:Hide()
end

-- Called at the end of every style pass, after the closing fill's pass, whose
-- mirror half gets a spark of its own.
function SP.Styled(e)
    local shell = e.shell
    if not SP.Wanted(e) then
        if shell._adSpark then Hide(shell._adSpark) end
        e.spark = nil
        return
    end
    local s = Ensure(shell)
    e.spark = s
    local rec = e.rec
    local vertical = (K.R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local reverse = K.R(rec, "fill", "reverseFill") == true
    -- two pixels at least, the hairline floor
    local w = K.R(rec, "fill", "edgeSparkWidth")
    local n = math.max(2, math.floor(tonumber(w) or SP.WIDTH))
    local c = K.R(rec, "fill", "edgeSparkColor")
    if type(c) ~= "table" then c = SP.COLOR end
    Place(s.main, shell, shell.fillTex or shell.fill:GetStatusBarTexture(), vertical, reverse, n, c)
    -- the mirror half fills the other way (Bars\AD_SwingClosing.lua)
    local sc = e.swc
    s.mirrorOn = (sc and sc.active and sc.bar) and true or false
    if s.mirrorOn then
        Place(s.mirror, shell, sc.bar:GetStatusBarTexture(), vertical, not reverse, n, c)
    end
    SP.Sync(e)
end

function SP.Release(e)
    if e.spark then Hide(e.spark) end
    e.spark = nil
end
