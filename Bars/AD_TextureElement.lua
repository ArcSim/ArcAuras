-- Textures (barKind "texture"): a picture on the bars runtime's shell, driven
-- by an aura, a spell's cooldown, rules of its own, your power or a unit's
-- health. It shows the whole picture while it is active, or fills and drains
-- like a bar, or runs round like a ring.
-- An aura's picture is drawn by the game's aura engine on the aura's own
-- button, so it follows the aura in combat with nothing read: its stack
-- windows and its time-left look are masks anchored to bars the engine fills,
-- its texts the engine's own. A cooldown's state is a hidden Cooldown's shown
-- flag, a rule's the custom engine's plain state; their fills are engine
-- timers fed with duration objects. A power or health picture takes the
-- percent, and its value gate is a razor bar the engine fills.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R
local Schema = NS.Schema

local TP = {}
NS.TextureElements = TP
TP.KEY = "adbarstexture"
-- a cooldown the global cooldown hid is read again this long after
TP.GCD_RETRY = 0.3
-- the question mark, for a picture with nothing set and no spell to show
TP.QUESTION = 134400
TP.WHITE = "Interface\\Buttons\\WHITE8X8"
-- a stack window with no top reaches this far past the last count
TP.OPEN_TOP = 1000
TP.armed = {}      -- [event] = true while registered under TP.KEY

local SOURCES = {}
for _, s in ipairs(Schema.TEXTURE_SOURCES or {}) do SOURCES[s] = true end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

function TP.Source(rec)
    local d = rec and rec.driver
    local s = d and d.source
    return SOURCES[s] and s or "aura"
end

function TP.Mode(rec)
    local m = R(rec, "texlook", "mode")
    return (m == "fill" or m == "ring") and m or "show"
end

-- a fill or a ring: the picture as a bar's fill
function TP.FillMode(rec)
    return TP.Mode(rec) ~= "show"
end

function TP.ByStacks(rec)
    return TP.FillMode(rec) and TP.Source(rec) == "aura" and R(rec, "texlook", "fillBy") == "stacks"
end

-- The spell a cooldown picture follows: the rank you know, then its override,
-- with the record's own Auto rank and Ignore override.
function TP.EffSpell(rec)
    return NS.Store.RecordSpellID(rec.driver)
end

-- What SetTexture takes: the picture's FileDataID, path or atlas name, else
-- the tracked spell's icon, else the question mark. k: a stack picture's
-- own, which falls back to the main one.
function TP.PictureOf(rec, k)
    local v = R(rec, "texlook", "image")
    if k then
        local own = R(rec, "texstate", "sb" .. k .. "Image")
        if own ~= nil and own ~= "" then v = own end
    end
    if type(v) == "number" and v > 0 then return math.floor(v) end
    if type(v) == "string" and v ~= "" then
        local n = tonumber(v)
        if n then return math.floor(n) end
        return v
    end
    -- a cooldown picture wears the spell it reads; an aura picture its aura
    local sid
    if TP.Source(rec) == "spellCd" then
        sid = TP.EffSpell(rec)
    else
        sid = NS.Store.TrackedAuraIDs(rec.driver)[1]
    end
    local icon = sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
    if icon ~= nil and not IsSecret(icon) then return icon end
    return TP.QUESTION
end

-- A picture value as art: a file (ID or path) over its whole span, or a
-- Blizzard atlas: its file and the part of it the atlas covers.
function TP.Art(v)
    if type(v) == "string" and C_Texture and C_Texture.GetAtlasInfo then
        local info = C_Texture.GetAtlasInfo(v)
        if type(info) == "table" and info.file then
            return { atlas = v, file = info.file, l = info.leftTexCoord or 0, r = info.rightTexCoord or 1,
                t = info.topTexCoord or 0, b = info.bottomTexCoord or 1 }
        end
    end
    return { file = v, l = 0, r = 1, t = 0, b = 1 }
end

function TP.Flip(rec)
    return TP.Mode(rec) == "show" and R(rec, "texlook", "flipOn") == true
end

-- The crop on each edge as a share of the picture: none in fill mode, which
-- keeps the picture whole, and each pair held under 98% so a sliver stays.
function TP.Crop(rec)
    if TP.FillMode(rec) or TP.Flip(rec) then return 0, 0, 0, 0 end
    local function F(v)
        return math.max(0, math.min(90, tonumber(v) or 0)) / 100
    end
    local l, r = F(R(rec, "texlook", "cropL")), F(R(rec, "texlook", "cropR"))
    local t, b = F(R(rec, "texlook", "cropT")), F(R(rec, "texlook", "cropB"))
    if l + r > 0.98 then
        local k = 0.98 / (l + r)
        l, r = l * k, r * k
    end
    if t + b > 0.98 then
        local k = 0.98 / (t + b)
        t, b = t * k, b * k
    end
    return l, r, t, b
end

-- The picture frame's size as plain numbers, nil while it is not laid out or
-- its rect is secret (pinned to a nameplate). Read on our own host only.
function TP.FrameSize(e)
    local host = e and e.tpHost
    if not host then return nil end
    local w, h = host:GetWidth(), host:GetHeight()
    if IsSecret(w) or IsSecret(h) or type(w) ~= "number" or type(h) ~= "number" then return nil end
    if w <= 0 or h <= 0 then return nil end
    return w, h
end

-- The picture's size from numbers the engine sizes it by (law 3: never a
-- rect read), else the laid-out host.
function TP.PlainSize(e)
    local LE = NS.LayoutEngine
    if LE and LE.BarSize and e.holder and not e.isPreview then
        local w, h = LE.BarSize(e.rec, e.holder)
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    end
    return TP.FrameSize(e)
end

-- Repeats across and down: a plain file only (an atlas is a part of one)
function TP.Tile(rec, art)
    if TP.Mode(rec) ~= "show" or TP.Flip(rec) or (art and art.atlas) then return nil end
    local x = math.max(1, math.floor(tonumber(R(rec, "texlook", "tileX")) or 1))
    local y = math.max(1, math.floor(tonumber(R(rec, "texlook", "tileY")) or 1))
    if x == 1 and y == 1 then return nil end
    return x, y
end

-- The whole picture's look on a plain texture: the art, colour, blend and grey,
-- then the turn, flips, zoom, crop and repeat (a fill keeps the picture
-- upright). dim: the dim copy behind, at its own opacity, tint and grey.
-- frame, w, h: where the texture sits and that frame's plain size; a crop cuts
-- the edges off in place, so the kept part is never stretched. With the size
-- unknown the crop waits (the whole picture shows) until the frame is laid
-- out. over: a stack picture or the time-left copy ({ pic, color }).
function TP.Dress(tex, rec, dim, frame, w, h, over)
    local art = TP.Art(over and over.pic or TP.PictureOf(rec))
    local tx, ty = TP.Tile(rec, art)
    -- an animated atlas sheet is set as the atlas, as the game's own are
    local sheetAtlas = art.atlas and TP.Flip(rec) and not dim and tex.SetAtlas
    if sheetAtlas then
        tex:SetAtlas(art.atlas, false)
    elseif tx then
        tex:SetTexture(art.file, "REPEAT", "REPEAT")
    else
        tex:SetTexture(art.file)
    end
    local c = (over and over.color) or R(rec, "texlook", "color") or { 1, 1, 1, 1 }
    local cr, cg, cb, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    local grey = (R(rec, "texlook", "desat") == true) and 1 or 0
    if dim then
        a = a * (R(rec, "texlook", "bgAlpha") or 0.3)
        if R(rec, "texlook", "bgTint") == true then
            local t = R(rec, "texlook", "bgColor") or { 1, 1, 1 }
            cr, cg, cb = t[1] or 1, t[2] or 1, t[3] or 1
        end
        -- never less grey than the picture it copies
        if R(rec, "texlook", "bgDesat") == true then
            grey = math.max(grey, (tonumber(R(rec, "texlook", "bgDesatAmount")) or 100) / 100)
        end
    end
    -- an animated sheet rests dark: its loop's alpha hold lights it (law 9)
    local flip = TP.Flip(rec) and not dim
    tex:SetVertexColor(cr, cg, cb, flip and 0 or a)
    tex._adFlipA = a
    tex:SetBlendMode(R(rec, "texlook", "blend") == "ADD" and "ADD" or "BLEND")
    if tex.SetDesaturation then tex:SetDesaturation(grey) else tex:SetDesaturated(grey > 0) end
    local l, r, t, b = 0, 0, 0, 0
    if frame and w and h then l, r, t, b = TP.Crop(rec) end
    if frame then
        tex:ClearAllPoints()
        if l + r + t + b > 0 then
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", w * l, -h * t)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -w * r, h * b)
        else
            tex:SetAllPoints(frame)
        end
    end
    local function Map(x0, x1, y0, y1)
        tex:SetTexCoord(art.l + (art.r - art.l) * x0, art.l + (art.r - art.l) * x1,
            art.t + (art.b - art.t) * y0, art.t + (art.b - art.t) * y1)
    end
    if TP.FillMode(rec) then
        Map(0, 1, 0, 1)
        if tex.SetRotation then tex:SetRotation(0) end
        return
    end
    if TP.Flip(rec) then
        -- the sheet's first frame on the dim copy; the loop sets the rest
        if dim then
            local cols = math.max(1, tonumber(R(rec, "texlook", "flipCols")) or 1)
            local rows = math.max(1, tonumber(R(rec, "texlook", "flipRows")) or 1)
            Map(0, 1 / cols, 0, 1 / rows)
        elseif not sheetAtlas then
            Map(0, 1, 0, 1)
        end
        if tex.SetRotation then tex:SetRotation(0) end
        return
    end
    -- zoom magnifies the middle evenly (45% keeps the middle 55%); the crop
    -- then cuts each edge off the zoomed picture
    local z = (R(rec, "texlook", "zoom") or 0) / 200
    local span = 1 - 2 * z
    local tl, tr, tt, tb = z + span * l, 1 - z - span * r, z + span * t, 1 - z - span * b
    if R(rec, "texlook", "flipH") == true then tl, tr = tr, tl end
    if R(rec, "texlook", "flipV") == true then tt, tb = tb, tt end
    if tx then
        tex:SetTexCoord(tl * tx, tr * tx, tt * ty, tb * ty)
    else
        Map(tl, tr, tt, tb)
    end
    if tex.SetRotation then tex:SetRotation(math.rad(R(rec, "texlook", "rotation") or 0)) end
end

-- The pulse: one repeating group, grow then shrink. Scale animations on one
-- region multiply, so the shrink runs 1 to 1/s over the held grow and each
-- loop ends at exactly the picture's own size; two legs of s back to 1 would
-- jump to s * s at the peak. The game plays it, so under an aura's button it
-- keeps going in combat with that button's shown state as the switch. A
-- hidden region's animation keeps running, so our own are stopped by hand.
function TP.Pulse(region, rec, on)
    local g = region._adPulse
    if not (on and R(rec, "texlook", "pulse") == true) then
        if g and g:IsPlaying() then g:Stop() end
        return
    end
    local s = 1 + (tonumber(R(rec, "texlook", "pulseSize")) or 15) / 100
    local half = math.max(0.1, (tonumber(R(rec, "texlook", "pulseTime")) or 1) / 2)
    if not g then
        g = region:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        g.up, g.down = g:CreateAnimation("Scale"), g:CreateAnimation("Scale")
        g.up:SetOrder(1)
        g.down:SetOrder(2)
        for _, an in ipairs({ g.up, g.down }) do
            an:SetOrigin("CENTER", 0, 0)
            an:SetSmoothing("IN_OUT")
        end
        region._adPulse = g
    end
    if g.size ~= s or g.half ~= half then
        if g:IsPlaying() then g:Stop() end
        g.size, g.half = s, half
        g.up:SetScaleFrom(1, 1)
        g.up:SetScaleTo(s, s)
        g.up:SetDuration(half)
        g.down:SetScaleFrom(1, 1)
        g.down:SetScaleTo(1 / s, 1 / s)
        g.down:SetDuration(half)
    end
    if not g:IsPlaying() then g:Play() end
end

-- Motion, beside the pulse. A turn (spin, wobble) runs on the picture
-- textures; a flash or a bounce on the frame that holds them, since a
-- texture's alpha is its tint's (law 7) and a frame carries a move. One
-- repeating group per region, rebuilt only when its recipe changes.
TP.TEX_MOTION = { spin = true, spinBack = true, wobble = true }
TP.FRAME_MOTION = { flash = true, bounce = true }

function TP.MotionOf(rec)
    local m = R(rec, "texlook", "motion")
    if TP.TEX_MOTION[m] and TP.Mode(rec) ~= "show" then return nil end
    if TP.TEX_MOTION[m] or TP.FRAME_MOTION[m] then return m end
    return nil
end

function TP.Motion(region, rec, on, frameLevel)
    local m = on and TP.MotionOf(rec) or nil
    if m and (TP.FRAME_MOTION[m] and true or false) ~= (frameLevel and true or false) then m = nil end
    local g = region._adMotion
    local t = math.max(0.2, tonumber(R(rec, "texlook", "motionTime")) or 2)
    local size = math.max(1, tonumber(R(rec, "texlook", "motionSize")) or 20)
    local sig = m and (m .. ":" .. t .. ":" .. size) or nil
    if g and g.sig ~= sig then
        g:Stop()
        g.sig = nil
    end
    if not sig then return end
    if not g then
        g = region:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        region._adMotion = g
    end
    if g.sig ~= sig then
        g.sig = sig
        -- each build gets its own steps: the old ones are finished with
        g.steps = g.steps or {}
        for _, an in ipairs(g.steps) do an:SetDuration(0) an:SetStartDelay(0) end
        local function Step(kind, order, dur)
            local an = g:CreateAnimation(kind)
            an:SetOrder(order)
            an:SetDuration(dur)
            g.steps[#g.steps + 1] = an
            return an
        end
        if m == "spin" or m == "spinBack" then
            local an = Step("Rotation", 1, t)
            an:SetOrigin("CENTER", 0, 0)
            an:SetDegrees(m == "spin" and -360 or 360)
        elseif m == "wobble" then
            for i, deg in ipairs({ size, -2 * size, size }) do
                local an = Step("Rotation", i, (i == 2) and t / 2 or t / 4)
                an:SetOrigin("CENTER", 0, 0)
                an:SetDegrees(deg)
                an:SetSmoothing("IN_OUT")
            end
        elseif m == "flash" then
            local low = math.max(0, math.min(1, size / 100))
            local down, up = Step("Alpha", 1, t / 2), Step("Alpha", 2, t / 2)
            down:SetFromAlpha(1)
            down:SetToAlpha(low)
            up:SetFromAlpha(low)
            up:SetToAlpha(1)
            down:SetSmoothing("IN_OUT")
            up:SetSmoothing("IN_OUT")
        else
            local upm, downm = Step("Translation", 1, t / 2), Step("Translation", 2, t / 2)
            upm:SetOffset(0, size)
            downm:SetOffset(0, -size)
            upm:SetSmoothing("OUT")
            downm:SetSmoothing("IN")
        end
    end
    if not g:IsPlaying() then g:Play() end
end

-- An animated picture: the sheet's frames in order, over and over. A
-- FlipBook target shows its whole sheet until it plays, so the picture rests
-- at alpha 0 (TP.Dress) and an Alpha hold in the same step lights it (law 9).
function TP.Flipbook(tex, rec, on)
    local g = tex._adFlip
    if not (on and TP.Flip(rec)) then
        if g and g:IsPlaying() then g:Stop() end
        return
    end
    local rows = math.max(1, math.floor(tonumber(R(rec, "texlook", "flipRows")) or 4))
    local cols = math.max(1, math.floor(tonumber(R(rec, "texlook", "flipCols")) or 4))
    local frames = math.max(1, math.min(rows * cols, math.floor(tonumber(R(rec, "texlook", "flipFrames")) or 16)))
    local dur = math.max(0.1, tonumber(R(rec, "texlook", "flipTime")) or 1)
    local a = tex._adFlipA or 1
    if not g then
        g = tex:CreateAnimationGroup()
        g:SetLooping("REPEAT")
        g.fb = g:CreateAnimation("FlipBook")
        g.lit = g:CreateAnimation("Alpha")
        g.fb:SetOrder(1)
        g.lit:SetOrder(1)
        tex._adFlip = g
    end
    local sig = rows .. ":" .. cols .. ":" .. frames .. ":" .. dur .. ":" .. a
    if g.sig ~= sig then
        if g:IsPlaying() then g:Stop() end
        g.sig = sig
        g.fb:SetFlipBookRows(rows)
        g.fb:SetFlipBookColumns(cols)
        g.fb:SetFlipBookFrames(frames)
        g.fb:SetFlipBookFrameWidth(0)
        g.fb:SetFlipBookFrameHeight(0)
        g.fb:SetDuration(dur)
        g.lit:SetFromAlpha(a)
        g.lit:SetToAlpha(a)
        g.lit:SetDuration(dur)
    end
    if not g:IsPlaying() then g:Play() end
end

-- Every loop a picture texture runs: pulse, turn, sheet.
function TP.Loops(tex, rec, on)
    TP.Pulse(tex, rec, on)
    TP.Motion(tex, rec, on, false)
    TP.Flipbook(tex, rec, on)
end

-- An aura's button and what we put on it may be touched only while the game
-- allows it (never in combat or while auras are secret).
function TP.Touchable(sub)
    local DA = NS.DriverAura
    return sub ~= nil and sub.button ~= nil and (not (DA and DA.IsAccessible) or DA.IsAccessible(sub.button))
end

-- The frame's size changed: a crop re-places its picture (an aura's while its
-- button can be touched, else at its next restyle).
function TP.Recrop(e)
    local rec = e.rec
    if not rec then return end
    local l, r, t, b = TP.Crop(rec)
    if l + r + t + b == 0 then return end
    local w, h = TP.FrameSize(e)
    TP.Dress(e.tpBg, rec, true, e.tpHost, w, h)
    TP.Dress(e.tpPic, rec, false, e.tpPicFrame, w, h)
    local sub = e.tpAura
    if sub and sub.layers and TP.Touchable(sub) then TP.StyleButton(e, sub) end
end

-- The ring's start: degrees clockwise from the top; the texture's offset
-- counts from the bottom.
function TP.RingOffset(rec)
    local deg = tonumber(R(rec, "texlook", "ringStart")) or 0
    return ((deg + 180) % 360) / 360
end

-- A fill's or a ring's bar: the picture as its fill texture (the bar reveals
-- it, never squeezes it), its direction or ring, colour, blend and grey. An
-- atlas fill: the bar's own fill turns invisible and a copy of the picture,
-- dressed like the whole picture, is cut to it by a mask (both on the bar,
-- so the mask may follow the engine's fill). over: the time-left copy.
function TP.DressBar(bar, rec, over)
    local ring = TP.Mode(rec) == "ring"
    local art = TP.Art(over and over.pic or TP.PictureOf(rec))
    local RM = Enum and Enum.StatusBarRenderMode
    if bar.SetRenderMode and RM then bar:SetRenderMode(ring and RM.Radial or RM.Linear) end
    if ring then
        bar:SetOrientation("HORIZONTAL")
        bar:SetReverseFill(false)
    else
        local dir = R(rec, "texlook", "fillDir") or "RIGHT"
        bar:SetOrientation((dir == "UP" or dir == "DOWN") and "VERTICAL" or "HORIZONTAL")
        bar:SetReverseFill(dir == "LEFT" or dir == "DOWN")
    end
    bar:SetRotatesTexture(false)
    local masked = art.atlas ~= nil and not ring
    local want = masked and TP.WHITE or art.file
    if bar._adPic ~= want then
        bar._adPic = want
        bar:SetStatusBarTexture(want)
    end
    local c = (over and over.color) or R(rec, "texlook", "color") or { 1, 1, 1, 1 }
    local t = bar:GetStatusBarTexture()
    if masked then
        bar:SetStatusBarColor(1, 1, 1, 0)
    else
        bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if t then
        t:SetBlendMode(R(rec, "texlook", "blend") == "ADD" and "ADD" or "BLEND")
        t:SetDesaturated(R(rec, "texlook", "desat") == true)
        if ring then
            t:SetTexCoord(art.l, art.r, art.t, art.b)
            if t.SetRadialProgressBarStartOffset then
                local off = TP.RingOffset(rec)
                t:SetRadialProgressBarStartOffset(off)
                t:SetRadialProgressBarEndOffset(off)
                t:SetRadialProgressBarReverse(R(rec, "texlook", "ringDir") == "ccw")
                t:SetRadialProgressBarFeather(0)
            end
        end
    end
    -- the atlas copy, cut to the fill
    local mp = bar._adMaskPic
    if masked then
        if not mp then
            mp = bar:CreateTexture(nil, "ARTWORK", nil, 1)
            mp:SetAllPoints(bar)
            bar._adMaskPic = mp
        end
        TP.Dress(mp, rec, false, nil, nil, nil, over)
        if t and bar._adRevealOf ~= t then
            local m = bar._adReveal
            if not m then
                m = bar:CreateMaskTexture()
                m:SetTexture(TP.WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
                bar._adReveal = m
                mp:AddMaskTexture(m)
            end
            m:ClearAllPoints()
            m:SetAllPoints(t)
            bar._adRevealOf = t
        end
        mp:Show()
    elseif mp then
        mp:Hide()
    end
    return t, mp
end

-- Stack windows. One hidden bar on the aura's button takes the stack count
-- (SetApplicationBar, 0 .. M); its fill's right edge sits one step (the
-- picture's width plus 2) further right for every stack. A picture shown for
-- lo .. hi stacks gets a mask WINDOW anchored to that edge that covers it
-- while lo <= stacks <= hi and clears it by a pixel at every other count, so
-- a size off by a pixel never shows a sliver; no count is read. One bar
-- serves every picture (one stack binding per button).

-- The count gate (Tracking, When it shows) as the whole counts it holds:
-- lo, hi (hi TP.OPEN_TOP = no top); nil = every count. charges: a cooldown
-- at a charge count, where no comparison set yet reads as "at least".
function TP.Gate(rec, charges)
    local show = R(rec, "texstate", "stackShow") or "any"
    if show == "any" then
        if not charges then return nil end
        show = "from"
    end
    local a = math.max(0, math.floor(tonumber(R(rec, "texstate", "stackLo")) or 2))
    local b = math.max(0, math.floor(tonumber(R(rec, "texstate", "stackHi")) or 5))
    if show == "from" then return a, TP.OPEN_TOP end
    if show == "more" then return a + 1, TP.OPEN_TOP end
    if show == "upto" then return 0, a end
    if show == "less" then return 0, a - 1 end
    if show == "exactly" then return a, a end
    return math.min(a, b), math.max(a, b)
end

-- The stack range each picture shows for: the main picture first, then each
-- stack picture from its count up to the next one's; nil = every count.
function TP.Windows(rec)
    if TP.Source(rec) ~= "aura" or TP.ByStacks(rec) then return nil end
    local glo, ghi = TP.Gate(rec)
    local lo, hi = glo or 0, ghi or TP.OPEN_TOP
    local bands = {}
    if TP.Mode(rec) == "show" then
        local n = math.max(0, math.min(4, math.floor(tonumber(R(rec, "texstate", "stackBands")) or 0)))
        for k = 1, n do
            local f = math.max(1, math.floor(tonumber(R(rec, "texstate", "sb" .. k .. "From")) or (k + 1)))
            bands[#bands + 1] = { k = k, from = f }
        end
        table.sort(bands, function(x, y) return x.from < y.from end)
    end
    if not glo and #bands == 0 then return nil end
    local out = {}
    local first = bands[1] and bands[1].from or (hi + 1)
    -- the main picture: below the first stack picture
    out[#out + 1] = { k = 0, lo = lo, hi = math.min(hi, first - 1) }
    for i, bd in ipairs(bands) do
        local nextFrom = bands[i + 1] and bands[i + 1].from or (TP.OPEN_TOP + 1)
        out[#out + 1] = { k = bd.k, lo = math.max(lo, bd.from), hi = math.min(hi, nextFrom - 1) }
    end
    -- a range left empty by the gate draws nothing
    for _, w in ipairs(out) do w.empty = w.lo > w.hi end
    return out
end

-- The bar's length in stacks: past every finite top, up to every open bottom.
function TP.WindowMax(wins)
    local m = 1
    for _, w in ipairs(wins or {}) do
        if not w.empty then
            if w.hi >= TP.OPEN_TOP then m = math.max(m, w.lo) else m = math.max(m, w.hi + 1) end
        end
    end
    return math.min(255, m)
end

-- the gate bar's step per stack
function TP.Step(W) return W + 2 end

-- The window on `owner` (the frame that owns the picture textures) for
-- lo .. hi; M = the bar's top, where the fill stops.
function TP.WindowMask(owner, key, fill, lo, hi, W, M)
    owner._adWin = owner._adWin or {}
    local m = owner._adWin[key]
    if not m then
        m = owner:CreateMaskTexture()
        m:SetTexture(TP.WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        owner._adWin[key] = m
    end
    local S = TP.Step(W)
    local x2 = W + 1 - lo * S
    local x1 = x2 - ((math.min(hi, M) - lo) * S + W + 2)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", fill, "TOPRIGHT", x2, 0)
    m:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", x1, 0)
    return m
end

-- A texture's masks, kept as a set: added once, removed when no longer wanted.
function TP.SetMasks(tex, list)
    tex._adMasks = tex._adMasks or {}
    local want = {}
    for _, m in ipairs(list) do want[m] = true end
    for m in pairs(tex._adMasks) do
        if not want[m] then
            tex:RemoveMaskTexture(m)
            tex._adMasks[m] = nil
        end
    end
    for m in pairs(want) do
        if not tex._adMasks[m] then
            tex:AddMaskTexture(m)
            tex._adMasks[m] = true
        end
    end
end

-- The share of the time left the time-left look starts at, nil = none (no
-- length for seconds, or switched off).
function TP.TimeFrac(rec)
    if R(rec, "texstate", "timeOn") ~= true then return nil end
    if not (Schema.TexTimeLook and Schema.TexTimeLook(rec)) then return nil end
    if (R(rec, "texstate", "timeUnit") or "pct") == "sec" then
        local sec = tonumber(R(rec, "texstate", "timeSec")) or 3
        if TP.Source(rec) == "rules" then return nil, sec end
        local len = tonumber(R(rec, "texstate", "timeLen")) or 0
        if len <= 0 then return nil end
        return math.min(1, sec / len)
    end
    return (tonumber(R(rec, "texstate", "timePct")) or 30) / 100
end

-- The time gate's bar: under `anchor`'s rect, so long and so shifted that its
-- fill jumps from nothing to past the picture as the elapsed share crosses
-- 1 - frac (the bar glows' and icons' gate, Factory ApplyTimeGate).
function TP.PlaceTimeBar(gb, anchor, W, H, frac)
    local E = math.max(W, H)
    local gw, gh = W + 2 * E, H + 2 * E
    local L = math.min(120000, gw / 0.0005)
    local g = 1 - frac
    gb:ClearAllPoints()
    gb:SetSize(L, gh)
    gb:SetPoint("LEFT", anchor, "CENTER", -gw / 2 - g * L, 0)
    gb:SetMinMaxValues(g, g + 0.0002)
end

-- The two time masks on `owner`: "after" = the gate's fill (the time-left
-- copies), "before" = from the fill's edge to the bar's end (the rest).
function TP.TimeMasks(owner, gb)
    local fill = gb:GetStatusBarTexture()
    local after, before = owner._adTimeAfter, owner._adTimeBefore
    if not after then
        after = owner:CreateMaskTexture()
        after:SetTexture(TP.WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        before = owner:CreateMaskTexture()
        before:SetTexture(TP.WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        owner._adTimeAfter, owner._adTimeBefore = after, before
    end
    after:ClearAllPoints()
    after:SetAllPoints(fill)
    before:ClearAllPoints()
    before:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    before:SetPoint("BOTTOMRIGHT", gb, "BOTTOMRIGHT", 0, 0)
    return after, before
end

function TP.MakeGateBar(parent)
    local gb = CreateFrame("StatusBar", nil, parent)
    gb:SetStatusBarTexture(TP.WHITE)
    -- never seen: its fill is only a rect
    gb:SetStatusBarColor(1, 1, 1, 0)
    gb:EnableMouse(false)
    return gb
end

-- Texts on the picture: their font objects follow the record, so a restyle
-- reaches an aura's texts even while its button is locked.
-- The face, size, outline and shadow on the entry's named font object for
-- that text (the picture's own font over the bars' default); returns it.
function TP.FontFor(fs, e, key)
    local rec = e.rec
    local pre = (key == "tpStk") and "ptStk" or "ptTime"
    local size = tonumber(R(rec, "pictext", pre .. "Size")) or 14
    local outline = R(rec, "pictext", "ptOutline") or "OUTLINE"
    local fo = K.StyleFont(fs, e, key, size, outline, R(rec, "pictext", "ptShadow") == true)
    local font = R(rec, "pictext", "ptFont")
    if type(font) == "string" and font ~= "" and Bars.ResolveFont then
        local flags = (outline ~= "NONE") and outline or ""
        local path = Bars.ResolveFont(font)
        if K.ProvenFontPath then path = K.ProvenFontPath(path, size, flags) end
        ;(fo or fs):SetFont(path, size, flags)
    end
    return fo
end

function TP.StyleText(fs, e, key)
    TP.FontFor(fs, e, key)
    local pre = (key == "tpStk") and "ptStk" or "ptTime"
    local c = R(e.rec, "pictext", pre .. "Color") or { 1, 1, 1, 1 }
    fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

function TP.PlaceTextOn(fs, frame, rec, key)
    local pre = (key == "tpStk") and "ptStk" or "ptTime"
    K.PlaceText(fs, frame, R(rec, "pictext", pre .. "Anchor") or (key == "tpStk" and "BOTTOMRIGHT" or "CENTER"),
        R(rec, "pictext", pre .. "X") or 0, R(rec, "pictext", pre .. "Y") or 0)
end

-- the stack count from 1 (0 shows nothing)
function TP.CountFormatter()
    if TP.countFmt ~= nil then return TP.countFmt or nil end
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        f:AddBreakpoint({ threshold = 0, format = "" })
        f:AddBreakpoint({ threshold = 1, format = "%d" })
        TP.countFmt = f
    else
        TP.countFmt = false
    end
    return TP.countFmt or nil
end

function TP.DurFormatter(rec)
    local F = NS.Factory
    if not (F and F.TimerFormatter) then return nil end
    local decTo = (R(rec, "pictext", "ptTimeDecimals") == true) and (tonumber(R(rec, "pictext", "ptTimeDecTo")) or 5) or 0
    return F.TimerFormatter(decTo, nil, 0, "down", K.BarRounding(rec))
end

-- Aura pictures: one slot on a container of our own, the aura icons' shape.
-- The engine shows the button with the aura and hides it without; the picture
-- or the fill on it goes with it.

-- A debuff lane on your target or focus waits while that unit is friendly:
-- the engine skips spell-ID filters there and would show any debuff. nil =
-- unknown (the answers can be secret in combat).
function TP.Hostile(unit)
    if not UnitExists then return false end
    local exists = UnitExists(unit)
    if IsSecret(exists) then return nil end
    if exists ~= true then return false end
    if not UnitCanAssist then return true end
    local assist = UnitCanAssist("player", unit, true, true)
    if IsSecret(assist) then return nil end
    return assist ~= true
end

function TP.AuraSig(e)
    local DA = NS.DriverAura
    local rec = e.rec
    local d = rec.driver
    local unit, harmful = DA.ShapeOf(d)
    local filter = DA.FilterForLane(d, { harmful = harmful })
    local mode = TP.Mode(rec)
    local fill = mode ~= "show"
    local drain = (R(rec, "texlook", "fillMode") or "drain") == "drain"
    local stacks = TP.ByStacks(rec)
    -- the ids stay out (an edit re-sends them); the binding's direction and
    -- source are baked into the engine's slot, so they are in
    local sig = table.concat({ unit, tostring(harmful), filter, mode, tostring(drain), tostring(stacks) }, "|")
    return sig, unit, harmful, filter, fill, drain
end

-- The candidate filters: the ids, or the never-matching 0 while parked. An
-- unknown answer keeps the last one (a swap to a new enemy mid-fight keeps
-- its debuff showing); a slot with no answer yet waits; combat end asks again.
function TP.AuraFilters(e)
    local DA = NS.DriverAura
    local sub = e.tpAura
    local parked = false
    if sub.harmful and (sub.unit == "target" or sub.unit == "focus") then
        local hostile = TP.Hostile(sub.unit)
        if hostile == nil then parked = sub.parked ~= false else parked = not hostile end
    end
    sub.parked = parked
    local ids = parked and { [0] = true } or DA.IncludeMap(e.rec.driver)
    return ids, parked
end

-- Sends the filters when they changed: every send restarts the slot.
function TP.PushAuraFilters(e)
    local sub = e.tpAura
    if not (sub and sub.container.SetAuraSlotCandidateFilters) then return end
    local ids = TP.AuraFilters(e)
    local fsig = NS.DriverAura.FilterSig(ids)
    if sub.filterSig == fsig then return end
    sub.filterSig = fsig
    sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = ids })
end

-- every region on a slot that runs a loop
function TP.SubRegions(sub)
    local out = {}
    for _, L in ipairs(sub.layers or {}) do
        out[#out + 1] = L.tex
        if L.copy then out[#out + 1] = L.copy end
    end
    if sub.bar then out[#out + 1] = sub.bar end
    if sub.barT then out[#out + 1] = sub.barT end
    return out
end

function TP.ParkAura(sub)
    if sub.container.SetAuraSlotCandidateFilters then
        sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = { [0] = true } })
    end
    sub.container:Hide()
    -- a parked slot never shows again: its loops would run on unseen
    if TP.Touchable(sub) then
        for _, region in ipairs(TP.SubRegions(sub)) do
            for _, k in ipairs({ "_adPulse", "_adMotion", "_adFlip" }) do
                if region[k] then region[k]:Stop() end
            end
        end
        if sub.pf and sub.pf._adMotion then sub.pf._adMotion:Stop() end
    end
end

-- The one writer of everything on an aura's button, from plain sources: the
-- pictures (main, stack pictures, their time-left copies) or the fill, the
-- stack windows, the time gate, the texts and the loops. At init and on every
-- accessible restyle; a binding is handed to the engine again only when it
-- changed.
function TP.StyleButton(e, sub)
    local b = sub.button
    if not b then return end
    local rec = e.rec
    local W, H = TP.PlainSize(e)
    local mode = TP.Mode(rec)
    local Interp = Enum and Enum.StatusBarInterpolation
    -- the picture frame: what a flash or a bounce moves
    local pf = sub.pf
    if not pf then
        pf = CreateFrame("Frame", nil, b)
        pf:SetAllPoints(b)
        pf:EnableMouse(false)
        sub.pf = pf
    end
    pf:SetFrameLevel((b._adLevel or b:GetFrameLevel()) + 1)
    local durTo, appTo
    sub.layers = sub.layers or {}
    if mode == "show" then
        if sub.bar then sub.bar:Hide() end
        local wins = TP.Windows(rec)
        local timeFrac = TP.TimeFrac(rec)
        if timeFrac and not (W and H) then timeFrac = nil end
        -- the layers: the main picture, then each stack picture
        local want = wins or { { k = 0, lo = 0, hi = TP.OPEN_TOP } }
        local gb, fill
        if wins and W and H then
            gb = sub.gb or TP.MakeGateBar(b)
            sub.gb = gb
            gb:ClearAllPoints()
            gb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 1)
            local M = TP.WindowMax(wins)
            gb:SetSize(M * TP.Step(W), H + 2)
            gb:Show()
            fill = gb:GetStatusBarTexture()
            appTo = { bar = gb, max = M }
        elseif sub.gb then
            sub.gb:Hide()
        end
        local after, before
        if timeFrac then
            local tb = sub.tb or TP.MakeGateBar(b)
            sub.tb = tb
            TP.PlaceTimeBar(tb, b, W, H, timeFrac)
            tb:Show()
            durTo = { bar = tb, time = true }
            after, before = TP.TimeMasks(pf, tb)
        elseif sub.tb then
            sub.tb:Hide()
        end
        local used = {}
        for i, wdef in ipairs(want) do
            local L = sub.layers[i]
            if not L then
                L = { tex = pf:CreateTexture(nil, "ARTWORK", nil, math.min(7, i)) }
                sub.layers[i] = L
            end
            used[i] = true
            local over = nil
            if wdef.k > 0 then
                over = { pic = TP.PictureOf(rec, wdef.k), color = R(rec, "texstate", "sb" .. wdef.k .. "Color") }
            end
            TP.Dress(L.tex, rec, false, pf, W, H, over)
            local win = fill and TP.WindowMask(pf, "w" .. i, fill, wdef.lo, wdef.hi, W, appTo.max) or nil
            local masks = {}
            if win then masks[#masks + 1] = win end
            if before then masks[#masks + 1] = before end
            TP.SetMasks(L.tex, masks)
            -- with no size yet there are no windows: the main picture alone
            local shown = not wdef.empty and (fill ~= nil or i == 1)
            L.tex:SetShown(shown)
            TP.Loops(L.tex, rec, shown)
            if timeFrac then
                if not L.copy then L.copy = pf:CreateTexture(nil, "ARTWORK", nil, math.min(7, i)) end
                local col = R(rec, "texstate", "timeColor") or { 1, 0.25, 0.25, 1 }
                TP.Dress(L.copy, rec, false, pf, W, H, { pic = over and over.pic or nil, color = col })
                local cm = {}
                if win then cm[#cm + 1] = win end
                cm[#cm + 1] = after
                TP.SetMasks(L.copy, cm)
                L.copy:SetShown(shown)
                TP.Loops(L.copy, rec, shown)
            elseif L.copy then
                TP.Loops(L.copy, rec, false)
                L.copy:Hide()
            end
        end
        for i, L in ipairs(sub.layers) do
            if not used[i] then
                TP.Loops(L.tex, rec, false)
                L.tex:Hide()
                if L.copy then
                    TP.Loops(L.copy, rec, false)
                    L.copy:Hide()
                end
            end
        end
    else
        -- a fill or a ring: the bar, bound to the time or the stack count
        for _, L in ipairs(sub.layers) do
            TP.Loops(L.tex, rec, false)
            L.tex:Hide()
            if L.copy then L.copy:Hide() end
        end
        if sub.tb then sub.tb:Hide() end
        local bar = sub.bar
        if not bar then
            bar = CreateFrame("StatusBar", nil, pf)
            bar:SetAllPoints(pf)
            -- the range before the binding: a later one drops the timer
            bar:SetMinMaxValues(0, 1)
            sub.bar = bar
        end
        bar:Show()
        local t, mp = TP.DressBar(bar, rec)
        TP.Pulse(bar, rec, true)
        if TP.ByStacks(rec) then
            local M = math.floor(tonumber(R(rec, "texlook", "fillMax")) or 0)
            if M <= 0 then M = TP.AuraMax(rec) end
            -- the gate's "at least" is the engine's own window here (it shows
            -- the bar from that count): Forever and 12.1.5 only
            local min = NS.AuraAppWindow and TP.Gate(rec) or nil
            if min and min >= M then M = min + 1 end
            appTo = { bar = bar, max = M, min = min, smooth = true }
            if sub.gb then sub.gb:Hide() end
        else
            durTo = { bar = bar }
            local wins = TP.Windows(rec)
            if wins and W and H then
                local gb = sub.gb or TP.MakeGateBar(b)
                sub.gb = gb
                gb:ClearAllPoints()
                gb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 1)
                local M = TP.WindowMax(wins)
                gb:SetSize(M * TP.Step(W), H + 2)
                gb:Show()
                appTo = { bar = gb, max = M }
                local fill = gb:GetStatusBarTexture()
                local m = TP.WindowMask(bar, "w1", fill, wins[1].lo, wins[1].hi, W, M)
                if t then TP.SetMasks(t, { m }) end
                if mp then TP.SetMasks(mp, { m, bar._adReveal }) end
            else
                if sub.gb then sub.gb:Hide() end
                if t then TP.SetMasks(t, {}) end
                if mp and bar._adReveal then TP.SetMasks(mp, { bar._adReveal }) end
            end
        end
    end
    TP.Motion(pf, rec, true, true)
    -- the engine's bindings, handed over again only when they changed
    local DIR = Enum and Enum.StatusBarTimerDirection
    if durTo then
        local drain = (R(rec, "texlook", "fillMode") or "drain") == "drain"
        local sig = tostring(durTo.bar) .. (durTo.time and ":t" or (drain and ":d" or ":f"))
        if sub.durSig ~= sig and b.SetDurationBar then
            sub.durSig = sig
            if durTo.time then
                b:SetDurationBar(durTo.bar, { interpolation = Interp and Interp.Immediate,
                    direction = DIR and DIR.ElapsedTime })
                -- the gate's range goes on after the binding, as the icons' does
                TP.PlaceTimeBar(durTo.bar, b, W, H, TP.TimeFrac(rec))
            else
                local o = {}
                if DIR then o.direction = drain and DIR.RemainingTime or DIR.ElapsedTime end
                b:SetDurationBar(durTo.bar, o)
            end
        end
    elseif sub.durSig and b.ClearDurationBar then
        sub.durSig = nil
        b:ClearDurationBar()
    end
    if appTo then
        local sig = tostring(appTo.bar) .. ":" .. appTo.max .. ":" .. tostring(appTo.min)
        if sub.appSig ~= sig and b.SetApplicationBar then
            sub.appSig = sig
            local o = { maxApplications = appTo.max }
            if appTo.min then o.minApplications = appTo.min end
            if Interp then o.interpolation = appTo.smooth and Interp.ExponentialEaseOut or Interp.Immediate end
            b:SetApplicationBar(appTo.bar, o)
        end
    elseif sub.appSig and b.ClearApplicationBar then
        sub.appSig = nil
        b:ClearApplicationBar()
    end
    TP.StyleAuraTexts(e, sub)
end

-- The aura's own most stacks: the game's answer, else five.
function TP.AuraMax(rec)
    local sid = NS.Store.TrackedAuraIDs(rec.driver)[1]
    local f = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
    local n = sid and f and f(sid)
    if type(n) == "number" and not IsSecret(n) and n > 1 then return math.min(255, math.floor(n)) end
    return 5
end

-- An aura's texts, the engine's to fill: bound once while on, cleared and
-- silenced when switched off.
function TP.StyleAuraTexts(e, sub)
    local b = sub.button
    local rec = e.rec
    local th = sub.th
    local stk = R(rec, "pictext", "ptStkShow") == true
    local tim = R(rec, "pictext", "ptTimeShow") == true
    if not (stk or tim or th) then return end
    if not th then
        th = CreateFrame("Frame", nil, b)
        th:SetAllPoints(b)
        th:EnableMouse(false)
        sub.th = th
    end
    th:SetFrameLevel((b._adLevel or b:GetFrameLevel()) + 4)
    for _, def in ipairs({ { key = "tpStk", on = stk, field = "stk" }, { key = "tpDur", on = tim, field = "dur" } }) do
        local fs = sub[def.field]
        if def.on then
            if not fs then
                fs = th:CreateFontString(nil, "OVERLAY")
                sub[def.field] = fs
            end
            -- the font before any binding writes text (law 17)
            TP.StyleText(fs, e, def.key)
            TP.PlaceTextOn(fs, th, rec, def.key)
            fs:SetAlpha(1)
            local bound = def.field .. "Bound"
            if not sub[bound] then
                sub[bound] = true
                if def.field == "stk" then
                    local f = TP.CountFormatter()
                    local o = {}
                    -- count from 1; 12.1.0 does not know the field and shows from 2
                    if not NS.AuraEngine1210 then o.minApplications = 1 end
                    if f then o.formatter = f end
                    b:SetApplicationCount(fs, o)
                else
                    local f = TP.DurFormatter(rec)
                    b:SetDurationText(fs, f and { textFormatter = f } or {})
                end
            end
        elseif fs then
            local bound = def.field .. "Bound"
            if sub[bound] then
                sub[bound] = nil
                if def.field == "stk" and b.ClearApplicationCount then b:ClearApplicationCount() end
                if def.field == "dur" and b.ClearDurationText then b:ClearDurationText() end
            end
            fs:SetAlpha(0)
        end
    end
end

-- Creates the slot once per recipe; false means retry on a later rebuild
-- (engine absent, or auras secret outside the login window).
function TP.EnsureAura(e)
    local DA = NS.DriverAura
    if not (DA and K.AuraEngineUp()) then return false end
    local rec = e.rec
    local sig, unit, harmful, filter = TP.AuraSig(e)
    local sub = e.tpAura
    if sub then
        if sub.sig == sig then
            TP.PushAuraFilters(e)
            return true
        end
        -- a new recipe cannot be made while auras are secret: the old slot
        -- keeps running (a stale look beats a dead picture)
        if K.AuraSecretNow() and not Bars.loadWindow then return true end
        TP.ParkAura(sub)
        e.tpAura = nil
    end
    if K.AuraSecretNow() and not Bars.loadWindow then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local shell = e.shell
    -- parented to the shell: the holder's opacity and conditions reach it
    local c = CreateFrame("AuraContainer", nil, shell, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraSlot) ~= "function" then return false end
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:Show()
    e.tpAuraGen = (e.tpAuraGen or 0) + 1
    local key = "adtexture" .. rec.id .. "_g" .. e.tpAuraGen
    sub = { container = c, key = key, sig = sig, unit = unit, harmful = harmful }
    e.tpAura = sub
    local ids = TP.AuraFilters(e)
    sub.filterSig = DA.FilterSig(ids)
    local id = rec.id
    c:AddAuraSlot(key, filter, {
        maxFrameCount = 1,
        -- The init window: everything built here descends from the button (the
        -- engine takes nothing else) and is anchored to our frames.
        initializeFrame = function(b)
            local cur = K.live[id]
            if not (cur and cur.tpAura == sub) then return end
            b:EnableMouse(false)
            b:SetAlpha(1)
            -- above the dim copy on our host; a plain copy of the level (law 9)
            local lvl = cur.tpHost:GetFrameLevel() + 2
            b:SetFrameLevel(lvl)
            b._adLevel = lvl
            b:ClearAllPoints()
            b:SetAllPoints(cur.shell)
            sub.button = b
            TP.StyleButton(cur, sub)
        end,
        candidateFilters = { includeSpellIDs = ids },
    })
    if type(c.UpdateAllAuras) == "function" then c:UpdateAllAuras() end
    return true
end

-- A unit token keeps its name when it points at someone new, and a container
-- re-reads only on its own unit's aura events: re-park and nudge on a swap.
-- unit "party": every party slot (a roster change moves them all).
function TP.OnUnitSwap(unit)
    K.ForEach("texture", function(e)
        -- a health picture on that unit reads its new owner
        if TP.Source(e.rec) == "health" then
            local u = e.rec.driver.unit or "player"
            if unit == nil or u == unit or (unit == "party" and u:sub(1, 5) == "party") then TP.Paint(e) end
        end
        local sub = e.tpAura
        if sub and (unit == nil or sub.unit == unit or (unit == "party" and sub.unit:sub(1, 5) == "party")) then
            TP.PushAuraFilters(e)
            if type(sub.container.UpdateAllAuras) == "function" then sub.container:UpdateAllAuras() end
        end
    end)
end

-- Value pictures: your power or a unit's health. A fill or a ring takes the
-- percent (0 .. 100 through the scale curve, so a secret value fills it as
-- is); a shown-by-value picture is cut by a razor bar the engine fills: its
-- range ends at the value set, so its fill is all or nothing and nothing is
-- compared in Lua.

function TP.IsValue(rec)
    local s = TP.Source(rec)
    return s == "power" or s == "health"
end

-- the power it reads: the one set, else the one you use now
function TP.PowerType(rec)
    local pt = rec.driver.powerType
    if pt == nil or pt < 0 then pt = (UnitPowerType and UnitPowerType("player")) or 0 end
    if IsSecret(pt) then pt = 0 end
    return pt
end

-- the percent now (may be secret), nil without the APIs
function TP.ValuePct(e)
    local rec = e.rec
    local scale = K.HealthScale and K.HealthScale()
    if not scale then return nil end
    if TP.Source(rec) == "power" then
        return UnitPowerPercent and UnitPowerPercent("player", TP.PowerType(rec), false, scale) or nil
    end
    return UnitHealthPercent and UnitHealthPercent(rec.driver.unit or "player", true, scale) or nil
end

-- The gate: "above" or "below", the razor range and the value fed to it; nil
-- = shown at any value. Points are whole, so half a point of range never
-- shows in part; a percent's range is a twentieth of one.
function TP.ValueGate(e)
    local rec = e.rec
    local show = R(rec, "texstate", "valShow")
    if show ~= "above" and show ~= "below" then return nil end
    if TP.Source(rec) == "power" and R(rec, "texstate", "valUnit") == "points" then
        local T = tonumber(R(rec, "texstate", "valPts")) or 50
        local v = UnitPower and UnitPower("player", TP.PowerType(rec))
        if v == nil then return nil end
        return show, T - 0.5, T, v
    end
    local T = tonumber(R(rec, "texstate", "valPct")) or 35
    local v = TP.ValuePct(e)
    if v == nil then return nil end
    return show, T - 0.05, T, v
end

-- Paints a value picture: the gate over the picture, then the whole picture
-- or the fill at the percent, each cut by the gate's fill (at or above) or its
-- rest (below). While you place it, it shows whole.
function TP.PaintValue(e, edit)
    local rec = e.rec
    local W, H = TP.PlainSize(e)
    local show, lo, hi, v = TP.ValueGate(e)
    local gate = show ~= nil and W ~= nil and H ~= nil and not edit
    local tb = e.tpTimeBar
    if gate then
        tb:ClearAllPoints()
        tb:SetSize(W + 2, H + 2)
        tb:SetPoint("CENTER", e.tpPicFrame, "CENTER", 0, 0)
        tb:SetMinMaxValues(lo, hi)
        tb:SetValue(v)
        tb:Show()
    else
        tb:Hide()
    end
    e.tpPicT:Hide()
    e.tpBarT:Hide()
    if e.tpTxtCD then
        e.tpTxtCD:Clear()
        e.tpTxtCD:Hide()
    end
    if e.tpSample then e.tpSample:Hide() end
    local function Cut(owner)
        if not gate then return nil end
        local after, before = TP.TimeMasks(owner, tb)
        return (show == "above") and after or before
    end
    if TP.FillMode(rec) then
        e.tpPic:Hide()
        local bar = e.tpBar
        bar:Show()
        bar:SetMinMaxValues(0, 100)
        local pct = (not edit) and TP.ValuePct(e) or nil
        local Interp = Enum and Enum.StatusBarInterpolation
        if pct ~= nil then
            bar:SetValue(pct, Interp and Interp.ExponentialEaseOut)
        else
            bar:SetValue(edit and 100 or 0)
        end
        local m = Cut(bar)
        local t = bar:GetStatusBarTexture()
        if t then TP.SetMasks(t, m and { m } or {}) end
        local mp = bar._adMaskPic
        if mp then
            local list = { bar._adReveal }
            if m then list[2] = m end
            TP.SetMasks(mp, list)
        end
        e.tpRunning = nil
    else
        e.tpBar:Hide()
        e.tpPic:Show()
        local m = Cut(e.tpPicFrame)
        TP.SetMasks(e.tpPic, m and { m } or {})
    end
end

-- a unit's health moved: its pictures repaint once, next frame
function TP.OnHealth(unit)
    if unit == nil or IsSecret(unit) then return end
    NS.Events.Coalesce("adtexture_hp_" .. unit, function()
        K.ForEach("texture", function(e)
            if TP.Source(e.rec) == "health" and (e.rec.driver.unit or "player") == unit then TP.Paint(e) end
        end)
    end)
end

-- Cooldown pictures: the main cooldown on one hidden Cooldown (state: on
-- cooldown or ready, the global cooldown kept out) and a charge spell's
-- recharge on another (what its fill runs with).

function TP.EnsureShadows(e)
    if e.tpCD then return end
    e.tpCD = K.MakeShadow()
    e.tpCharge = K.MakeShadow()
end

-- One re-read after the global cooldown: a real cooldown started under it
-- comes with no event of its own at its end.
function TP.RetryAfterGCD(e)
    if e.tpGcdQueued then return end
    e.tpGcdQueued = true
    local id = e.rec.id
    C_Timer.After(TP.GCD_RETRY, function()
        local cur = K.live[id]
        if not cur then return end
        cur.tpGcdQueued = nil
        if TP.Source(cur.rec) == "spellCd" then TP.Refresh(cur) end
    end)
end

function TP.FeedCooldown(e)
    TP.EnsureShadows(e)
    local rec = e.rec
    local sid = TP.EffSpell(rec)
    if not (sid and C_Spell and C_Spell.GetSpellCooldownDuration) then
        e.tpCD:Clear()
        e.tpCharge:Clear()
        e.tpMainDur, e.tpChargeDur, e.tpIsCharge = nil, nil, nil
        return
    end
    local DC = NS.DriverCooldown
    local wandLock = DC ~= nil and DC.WandLocked ~= nil and DC.WandLocked() and not DC.IsWandShot(sid)
    -- a running cooldown keeps its timing through the wand's lock
    if wandLock and e.tpCD:IsShown() == true then return end
    local main = (not wandLock) and C_Spell.GetSpellCooldownDuration(sid, true) or nil
    if main then e.tpCD:SetCooldownFromDurationObject(main, true) else e.tpCD:Clear() end
    local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    local maxC = ch and ch.maxCharges
    local isCharge = type(maxC) == "number" and not IsSecret(maxC) and maxC > 1
    local chDur = isCharge and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(sid, true) or nil
    if chDur then e.tpCharge:SetCooldownFromDurationObject(chDur, true) else e.tpCharge:Clear() end
    e.tpMainDur, e.tpChargeDur, e.tpIsCharge = main, chDur, isCharge
    -- the charges now, only ever fed to a bar (secret in instances)
    e.tpChargesNow = isCharge and ch.currentCharges or nil
    local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = info and info.isOnGCD
    if not IsSecret(onGcd) and onGcd == true and not wandLock then TP.RetryAfterGCD(e) end
end

-- The state the picture shows, from the source: active, and a running
-- duration object for a fill (nil = nothing runs).
function TP.StateOf(e)
    local rec = e.rec
    local s = TP.Source(rec)
    if s == "spellCd" then
        local m = e.tpCD ~= nil and e.tpCD:IsShown() == true
        local c = e.tpIsCharge == true and e.tpCharge:IsShown() == true
        local active
        local when = rec.driver.cdActive
        -- at a charge count the count gate decides (TP.CountGate)
        if when == "cooldown" then active = m elseif when == "charges" then active = true else active = not m end
        local run
        if R(rec, "texlook", "fillBy") == "cooldown" then
            if m then run = e.tpMainDur end
        elseif c then
            run = e.tpChargeDur
        elseif m then
            run = e.tpMainDur
        end
        return active, run
    elseif s == "rules" then
        local CU = NS.DriverCustom
        local st = CU and CU.Get(rec.id)
        if not st then return false, nil end
        local run
        if CU.Running(st) and st.start and st.dur and C_DurationUtil and C_DurationUtil.CreateDuration then
            e.tpRuleDur = e.tpRuleDur or C_DurationUtil.CreateDuration()
            e.tpRuleDur:SetTimeFromStart(st.start, st.dur)
            run = e.tpRuleDur
            e.tpRuleLen = st.dur
        end
        return CU.Active(st), run
    end
    return true, nil
end

-- A cooldown's or a rule's time-left look: our own gate bar fed the running
-- timer, so the share left is never read either. A rule's seconds use its
-- plain length.
function TP.OwnTimeFrac(e)
    local rec = e.rec
    local frac, sec = TP.TimeFrac(rec)
    if sec and TP.Source(rec) == "rules" then
        local len = tonumber(e.tpRuleLen) or 0
        if len <= 0 then return nil end
        return math.min(1, sec / len)
    end
    return frac
end

-- A cooldown's count now: its charges (maybe secret), or 1 ready / 0 not
-- for a spell without charges.
function TP.ChargeCount(e)
    if e.tpIsCharge == true then return e.tpChargesNow or 0 end
    return (e.tpCD ~= nil and e.tpCD:IsShown() == true) and 0 or 1
end

-- A cooldown at a charge count: a hidden bar of our own, 0 .. M, fed the
-- count (SetValue takes a secret), its fill's edge cutting the same windows
-- as an aura's stack windows (drawing law 25). Returns a maker of that window
-- for a frame that owns textures, or nil (no gate, edit mode, no size yet),
-- and true when the gate holds no count at all.
function TP.CountGate(e, W, H, edit)
    local rec = e.rec
    local cb = e.tpCountBar
    if edit or TP.Source(rec) ~= "spellCd" or rec.driver.cdActive ~= "charges" or not (W and H) then
        cb:Hide()
        return nil
    end
    local lo, hi = TP.Gate(rec, true)
    if lo > hi then
        cb:Hide()
        return nil, true
    end
    local M = TP.WindowMax({ { lo = lo, hi = hi } })
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", e.tpPicFrame, "TOPLEFT", 0, 1)
    cb:SetSize(M * TP.Step(W), H + 2)
    cb:SetMinMaxValues(0, M)
    cb:SetValue(TP.ChargeCount(e))
    cb:Show()
    local fill = cb:GetStatusBarTexture()
    return function(owner) return TP.WindowMask(owner, "c", fill, lo, hi, W, M) end
end

-- Paints a cooldown or rule picture: the whole picture while active, or the
-- fill running with its timer (full with nothing running but active, empty
-- when not), its time-left copy and countdown. While you place it (edit mode)
-- it always shows.
local function PaintPicture(e)
    local rec = e.rec
    local s = TP.Source(rec)
    local edit = K.IsEditMode()
    if s ~= "spellCd" then e.tpCountBar:Hide() end
    if s == "power" or s == "health" then
        TP.PaintValue(e, edit)
        return
    end
    if s == "aura" then
        -- the engine draws the live picture; ours stands in while you place it
        TP.SetMasks(e.tpPic, {})
        e.tpPic:SetShown(edit)
        e.tpBar:Hide()
        e.tpPicT:Hide()
        e.tpBarT:Hide()
        TP.PaintOwnText(e, nil, edit)
        return
    end
    local active, run = TP.StateOf(e)
    local frac = (run and not edit) and TP.OwnTimeFrac(e) or nil
    local W, H = TP.PlainSize(e)
    if frac and not (W and H) then frac = nil end
    local drain = (R(rec, "texlook", "fillMode") or "drain") == "drain"
    local gate, none = TP.CountGate(e, W, H, edit)
    if none then active = false end
    local after, before
    if frac then
        local tb = e.tpTimeBar
        TP.PlaceTimeBar(tb, e.tpPicFrame, W, H, frac)
        local DIR = Enum and Enum.StatusBarTimerDirection
        local Interp = Enum and Enum.StatusBarInterpolation
        if tb.SetTimerDuration and DIR and Interp then
            tb:SetTimerDuration(run, Interp.Immediate, DIR.ElapsedTime)
        end
        tb:Show()
    else
        e.tpTimeBar:Hide()
    end
    if TP.FillMode(rec) then
        e.tpPic:Hide()
        e.tpPicT:Hide()
        local bars = { e.tpBar }
        if frac then bars[2] = e.tpBarT end
        for i, bar in ipairs(bars) do
            bar:Show()
            local t = bar:GetStatusBarTexture()
            local mp = bar._adMaskPic
            local list = {}
            if frac then
                after, before = TP.TimeMasks(bar, e.tpTimeBar)
                list[1] = (i == 2) and after or before
            end
            if gate then list[#list + 1] = gate(bar) end
            if t then TP.SetMasks(t, list) end
            if mp then
                local ml = { bar._adReveal }
                for _, m in ipairs(list) do ml[#ml + 1] = m end
                TP.SetMasks(mp, ml)
            end
            if not (run and not edit and K.FeedStatusBarTimer(bar, run, true, drain)) then
                bar:SetMinMaxValues(0, 1)
                bar:SetValue((active or edit) and 1 or 0)
            end
        end
        if not frac then e.tpBarT:Hide() end
        e.tpRunning = run ~= nil and not edit
    else
        e.tpBar:Hide()
        e.tpBarT:Hide()
        local on = active or edit
        e.tpPic:SetShown(on)
        local win = gate and gate(e.tpPicFrame) or nil
        if frac then
            after, before = TP.TimeMasks(e.tpPicFrame, e.tpTimeBar)
            TP.SetMasks(e.tpPic, { before, win })
            TP.SetMasks(e.tpPicT, { after, win })
            e.tpPicT:SetShown(on)
        else
            TP.SetMasks(e.tpPic, { win })
            e.tpPicT:Hide()
        end
    end
    TP.PaintOwnText(e, run, edit)
end

-- A cooldown's or a rule's time text: a countdown of our own (no swipe)
-- fed the running timer; in edit mode a sample stands in, as for an aura.
function TP.PaintOwnText(e, run, edit)
    local rec = e.rec
    local on = R(rec, "pictext", "ptTimeShow") == true
    local cd = e.tpTxtCD
    local sample = e.tpSample
    if not on then
        if cd then cd:Clear() cd:Hide() end
        if sample then sample:Hide() end
        return
    end
    if edit or TP.Source(rec) == "aura" then
        if cd then cd:Clear() cd:Hide() end
        if edit then
            if not sample then
                sample = e.tpTextHost:CreateFontString(nil, "OVERLAY")
                e.tpSample = sample
            end
            TP.StyleText(sample, e, "tpDur")
            TP.PlaceTextOn(sample, e.tpTextHost, rec, "tpDur")
            sample:SetText("8")
            sample:Show()
        elseif sample then
            sample:Hide()
        end
        return
    end
    if sample then sample:Hide() end
    if not cd then
        cd = CreateFrame("Cooldown", nil, e.tpTextHost, "CooldownFrameTemplate")
        cd:SetAllPoints(e.tpTextHost)
        cd:EnableMouse(false)
        cd:SetDrawSwipe(false)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(false)
        e.tpTxtCD = cd
    end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        local fo = TP.FontFor(fs, e, "tpDur")
        -- the widget re-applies its countdown font on every start: ours by name
        if fo and cd.SetCountdownFont and cd._adFontName ~= fo:GetName() then
            cd._adFontName = fo:GetName()
            cd:SetCountdownFont(fo:GetName())
        end
        local c = R(rec, "pictext", "ptTimeColor") or { 1, 1, 1, 1 }
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        TP.PlaceTextOn(fs, e.tpTextHost, rec, "tpDur")
    end
    if cd.SetCountdownFormatter then
        local F = NS.Factory
        local decTo = (R(rec, "pictext", "ptTimeDecimals") == true) and (tonumber(R(rec, "pictext", "ptTimeDecTo")) or 5) or 0
        local f = F and F.TimerFormatter and F.TimerFormatter(decTo, nil, 0, "up", K.BarRounding(rec))
        -- pushed on change only (the formatters are cached by recipe)
        local sig = f or "stock"
        if cd._adFmtSig ~= sig then
            cd._adFmtSig = sig
            cd:SetCountdownFormatter(f)
        end
    end
    if run then
        cd:Show()
        cd:SetCooldownFromDurationObject(run, true)
    else
        cd:Clear()
        cd:Hide()
    end
end

function TP.Paint(e)
    if e.isPreview then return end
    PaintPicture(e)
    TP.LoopsOwn(e)
end

-- Our own pictures run their loops while they show.
function TP.LoopsOwn(e)
    local rec = e.rec
    for _, region in ipairs({ e.tpPic, e.tpPicT }) do TP.Loops(region, rec, region:IsShown()) end
    for _, bar in ipairs({ e.tpBar, e.tpBarT }) do TP.Pulse(bar, rec, bar:IsShown()) end
    TP.Motion(e.tpPicFrame, rec, e.tpPic:IsShown() or e.tpBar:IsShown(), true)
end
-- the name the earlier code used for it
TP.PulseOwn = TP.LoopsOwn

-- The custom engine's paint told every picture that reads that state.
function TP.OnCustomPaint(st)
    K.ForEach("texture", function(e)
        if e.rec.id == st.id and TP.Source(e.rec) == "rules" then TP.Paint(e) end
    end)
end

-- Events: each source arms only what it needs, while a picture with that
-- source is live.

local function RefreshWhere(key, pred)
    NS.Events.Coalesce("adtexture_" .. key, function()
        K.ForEach("texture", function(e)
            if pred(e) then TP.Refresh(e) end
        end)
    end)
end

local function IsCd(e) return TP.Source(e.rec) == "spellCd" end

local function IsPower(e) return TP.Source(e.rec) == "power" end

TP.HANDLERS = {
    -- your power: its value, its most, the power you use (a form, a spec)
    UNIT_POWER_FREQUENT = function(_, unit) if unit == "player" then RefreshWhere("power", IsPower) end end,
    UNIT_MAXPOWER = function(_, unit) if unit == "player" then RefreshWhere("power", IsPower) end end,
    UNIT_DISPLAYPOWER = function(_, unit) if unit == "player" then RefreshWhere("power", IsPower) end end,
    UPDATE_SHAPESHIFT_FORM = function() RefreshWhere("power", IsPower) end,
    -- a unit's health: one coalesced repaint per unit
    UNIT_HEALTH = function(_, unit) TP.OnHealth(unit) end,
    UNIT_MAXHEALTH = function(_, unit) TP.OnHealth(unit) end,
    SPELL_UPDATE_COOLDOWN = function() RefreshWhere("cd", IsCd) end,
    SPELL_UPDATE_CHARGES = function() RefreshWhere("cd", IsCd) end,
    SPELLS_CHANGED = function() RefreshWhere("cd", IsCd) end,
    -- your cast lands its cooldown before SPELL_UPDATE_COOLDOWN inside a charge
    -- GCD: the pictures on that spell re-read now
    UNIT_SPELLCAST_SUCCEEDED = function(_, unit, _, spellID)
        if unit ~= "player" or IsSecret(spellID) then return end
        K.ForEach("texture", function(e)
            if IsCd(e) and NS.Store.SpellMatch(e.rec.driver.spellID, spellID, TP.EffSpell(e.rec)) then TP.Refresh(e) end
        end)
    end,
    PLAYER_TARGET_CHANGED = function() TP.OnUnitSwap("target") end,
    PLAYER_FOCUS_CHANGED = function() TP.OnUnitSwap("focus") end,
    UNIT_PET = function(_, unit)
        if unit ~= nil and unit ~= "player" and not IsSecret(unit) then return end
        TP.OnUnitSwap("pet")
    end,
    GROUP_ROSTER_UPDATE = function() TP.OnUnitSwap("party") end,
    -- a hostility answer that was secret in combat is plain again
    PLAYER_REGEN_ENABLED = function() TP.OnUnitSwap(nil) end,
}

function TP.Needs()
    local n = {}
    K.ForEach("texture", function(e)
        local s = TP.Source(e.rec)
        if s == "spellCd" then
            n.SPELL_UPDATE_COOLDOWN, n.SPELL_UPDATE_CHARGES, n.SPELLS_CHANGED = true, true, true
            n.UNIT_SPELLCAST_SUCCEEDED = true
        elseif s == "rules" then
            n.custom = true
        elseif s == "power" then
            n.UNIT_POWER_FREQUENT, n.UNIT_MAXPOWER, n.UNIT_DISPLAYPOWER = true, true, true
            if (e.rec.driver.powerType or -1) < 0 then n.UPDATE_SHAPESHIFT_FORM = true end
        elseif s == "health" then
            n.UNIT_HEALTH, n.UNIT_MAXHEALTH = true, true
            local unit = e.rec.driver.unit or "player"
            if unit == "target" then n.PLAYER_TARGET_CHANGED = true
            elseif unit == "focus" then n.PLAYER_FOCUS_CHANGED = true
            elseif unit == "pet" then n.UNIT_PET = true
            elseif unit:sub(1, 5) == "party" then n.GROUP_ROSTER_UPDATE = true end
        else
            local unit, harmful = NS.DriverAura.ShapeOf(e.rec.driver)
            if unit == "target" then n.PLAYER_TARGET_CHANGED = true
            elseif unit == "focus" then n.PLAYER_FOCUS_CHANGED = true
            elseif unit == "pet" then n.UNIT_PET = true
            elseif unit:sub(1, 5) == "party" then n.GROUP_ROSTER_UPDATE = true end
            if harmful and (unit == "target" or unit == "focus") then n.PLAYER_REGEN_ENABLED = true end
        end
    end)
    return n
end

-- Arms and disarms against what the live pictures need; run after every
-- ensure and release.
function TP.Sync()
    local n = TP.Needs()
    for ev, fn in pairs(TP.HANDLERS) do
        if n[ev] and not TP.armed[ev] then
            TP.armed[ev] = true
            K.SafeOn(ev, TP.KEY, fn)
        elseif not n[ev] and TP.armed[ev] then
            TP.armed[ev] = nil
            NS.Events.Off(ev, TP.KEY)
        end
    end
    local CU = NS.DriverCustom
    if CU and CU.Watch then
        if n.custom and not TP.watching then
            TP.watching = true
            CU.Watch(TP.KEY, TP.OnCustomPaint)
        elseif not n.custom and TP.watching then
            TP.watching = nil
            CU.Unwatch(TP.KEY)
        end
    end
end

-- Kind registry hooks

function TP.Build(e)
    if e.tpHost then return end
    local shell = e.shell
    local host = CreateFrame("Frame", nil, shell)
    host:SetAllPoints(shell)
    host:SetFrameLevel(shell.overlay:GetFrameLevel() + 1)
    host:EnableMouse(false)
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    bg:Hide()
    -- the picture frame: what a flash or a bounce moves (the dim copy stays)
    local pf = CreateFrame("Frame", nil, host)
    pf:SetAllPoints(host)
    pf:EnableMouse(false)
    local pic = pf:CreateTexture(nil, "ARTWORK")
    pic:SetAllPoints(pf)
    pic:Hide()
    local picT = pf:CreateTexture(nil, "ARTWORK", nil, 1)
    picT:SetAllPoints(pf)
    picT:Hide()
    local bar = CreateFrame("StatusBar", nil, pf)
    bar:SetAllPoints(pf)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
    local barT = CreateFrame("StatusBar", nil, pf)
    barT:SetAllPoints(pf)
    barT:SetMinMaxValues(0, 1)
    barT:SetValue(0)
    barT:Hide()
    local tb = TP.MakeGateBar(pf)
    tb:Hide()
    -- a cooldown's charge gate (TP.CountGate)
    local cb = TP.MakeGateBar(pf)
    cb:Hide()
    e.tpCountBar = cb
    local th = CreateFrame("Frame", nil, host)
    th:SetAllPoints(host)
    th:SetFrameLevel(host:GetFrameLevel() + 6)
    th:EnableMouse(false)
    e.tpHost, e.tpBg, e.tpPic, e.tpBar = host, bg, pic, bar
    e.tpPicFrame, e.tpPicT, e.tpBarT, e.tpTimeBar, e.tpTextHost = pf, picT, barT, tb, th
    -- a crop is placed in pixels, so it follows the frame's size
    host:SetScript("OnSizeChanged", function() TP.Recrop(e) end)
end

-- What another source held: the aura slot, the rules sink.
function TP.DropOthers(e, keep)
    if keep ~= "rules" and NS.DriverCustom and NS.DriverCustom.DetachText then NS.DriverCustom.DetachText(e.rec.id) end
    if keep ~= "aura" and e.tpAura then
        TP.ParkAura(e.tpAura)
        e.tpAura = nil
    end
    if keep ~= "spellCd" and e.tpCD then
        e.tpCD:Clear()
        e.tpCharge:Clear()
        e.tpMainDur, e.tpChargeDur, e.tpIsCharge = nil, nil, nil
    end
end

function TP.Ensure(e)
    local s = TP.Source(e.rec)
    TP.DropOthers(e, s)
    if s == "aura" then
        TP.EnsureAura(e)
    elseif s == "spellCd" then
        TP.FeedCooldown(e)
    end
    TP.Sync()
    -- the sink attaches after the watcher is armed: its first paint reaches us
    if s == "rules" and NS.DriverCustom and NS.DriverCustom.AttachText then
        NS.DriverCustom.AttachText(e.rec, e)
    end
    TP.Paint(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

function TP.Refresh(e)
    if TP.Source(e.rec) == "spellCd" then TP.FeedCooldown(e) end
    TP.Paint(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

function TP.Release(e)
    TP.DropOthers(e, nil)
    e.tpGcdQueued = nil
    if e.tpPic then
        for _, region in ipairs({ e.tpPic, e.tpPicT }) do TP.Loops(region, e.rec, false) end
        TP.Pulse(e.tpBar, e.rec, false)
        TP.Pulse(e.tpBarT, e.rec, false)
        TP.Motion(e.tpPicFrame, e.rec, false, true)
        if e.tpTxtCD then e.tpTxtCD:Clear() end
    end
    TP.Sync()
end

-- ApplyStyle draws the bar's chrome: put it all away, then dress the
-- picture, the dim copy, the fill and the time-left copies (and the aura
-- button's while accessible).
function TP.Styled(e)
    local shell, rec = e.shell, e.rec
    shell.fill:Hide()
    shell.bg:Hide()
    for _, t in pairs(shell.edges) do t:Hide() end
    if shell.borderF then shell.borderF:Hide() end
    shell.sheen:Hide()
    local w, h = TP.FrameSize(e)
    TP.Dress(e.tpBg, rec, true, e.tpHost, w, h)
    e.tpBg:SetShown(R(rec, "texlook", "bgShow") == true)
    TP.Dress(e.tpPic, rec, false, e.tpPicFrame, w, h)
    local tcol = R(rec, "texstate", "timeColor") or { 1, 0.25, 0.25, 1 }
    TP.Dress(e.tpPicT, rec, false, e.tpPicFrame, w, h, { color = tcol })
    TP.DressBar(e.tpBar, rec)
    TP.DressBar(e.tpBarT, rec, { color = tcol })
    TP.LoopsOwn(e)
    local sub = e.tpAura
    if TP.Touchable(sub) then TP.StyleButton(e, sub) end
end

function TP.Diag(e)
    local active, run = false, nil
    if TP.Source(e.rec) ~= "aura" then active, run = TP.StateOf(e) end
    local sub = e.tpAura
    return ("%s [texture %s %s] active=%s running=%s aura=%s button=%s layers=%s"):format(tostring(e.rec.name),
        TP.Source(e.rec), TP.Mode(e.rec), tostring(active == true),
        tostring(run ~= nil), tostring(sub ~= nil), tostring(sub ~= nil and sub.button ~= nil),
        tostring(sub and sub.layers and #sub.layers or 0))
end

-- Editor preview: the picture as it looks while active (a fill or a ring at
-- 60%), its texts as samples.

function TP.PreviewModes()
    return { { key = "static", text = "Preview", tip = "The picture as it looks while active; a fill or a ring stands at 60%." } }
end

function TP.PreviewApply(e)
    local rec = e.rec
    e.tpPicT:Hide()
    e.tpBarT:Hide()
    e.tpTimeBar:Hide()
    e.tpCountBar:Hide()
    TP.SetMasks(e.tpPic, {})
    if TP.FillMode(rec) then
        e.tpPic:Hide()
        e.tpBar:Show()
        local t = e.tpBar:GetStatusBarTexture()
        if t then TP.SetMasks(t, {}) end
        e.tpBar:SetMinMaxValues(0, 1)
        e.tpBar:SetValue(0.6)
    else
        e.tpBar:Hide()
        e.tpPic:Show()
    end
    -- the texts as samples
    for _, def in ipairs({ { key = "tpStk", on = "ptStkShow", text = "3", f = "tpPvStk" },
            { key = "tpDur", on = "ptTimeShow", text = "8", f = "tpPvDur" } }) do
        local fs = e[def.f]
        local on = R(rec, "pictext", def.on) == true and (def.key ~= "tpStk" or TP.Source(rec) == "aura")
        if on then
            if not fs then
                fs = e.tpTextHost:CreateFontString(nil, "OVERLAY")
                e[def.f] = fs
            end
            TP.StyleText(fs, e, def.key)
            TP.PlaceTextOn(fs, e.tpTextHost, rec, def.key)
            fs:SetText(def.text)
            fs:Show()
        elseif fs then
            fs:Hide()
        end
    end
    TP.LoopsOwn(e)
end

-- What the sidebar and the layout cards say about a picture.
function TP.Describe(rec)
    local s = TP.Source(rec)
    local d = rec.driver or {}
    local L = Schema.TEXTURE_SOURCE_LABELS or {}
    local base = L[s] or s
    if s == "aura" then
        base = base .. ": " .. (d.spellID and tostring(d.spellID) or "no aura")
    elseif s == "spellCd" then
        local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID) -- raw-id: the typed spell, as the editor shows it
        if IsSecret(nm) then nm = nil end
        base = "Cooldown: " .. (nm or (d.spellID and ("spell " .. d.spellID)) or "no spell")
    elseif s == "health" then
        base = base .. ": " .. tostring(d.unit or "player")
    elseif s == "rules" then
        local n = type(d.rules) == "table" and #d.rules or 0
        base = base .. ", " .. n .. (n == 1 and " rule" or " rules")
    end
    local mode = TP.Mode(rec)
    if mode == "fill" then base = base .. ", fill" elseif mode == "ring" then base = base .. ", ring" end
    return base
end

Bars.RegisterKind("texture", {
    Build = TP.Build,
    Ensure = TP.Ensure,
    Refresh = TP.Refresh,
    Release = TP.Release,
    Styled = TP.Styled,
    Diag = TP.Diag,
    ownsName = true,
    PreviewModes = TP.PreviewModes,
    PreviewApply = TP.PreviewApply,
})
