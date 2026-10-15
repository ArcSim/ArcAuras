-- AD_ImportArcUIIcon: phase two of the Arc UI import. One icon's v1 look (its effective settings,
-- merged as Arc UI merges them) becomes the Arc Auras overrides that draw the same thing. The rules
-- follow what Arc UI's runtime does with each key, not what its option labels say: the reference is
-- retail-port\10-v1-cooldown-icon-semantics.md (cooldown icons) and 11 (aura icons).
local ADDON, NS = ...

local IA = NS.ImportArcUI or {}
NS.ImportArcUI = IA

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Put(o, sec, f, v)
    if v == nil then return end
    o[sec] = o[sec] or {}
    o[sec][f] = v
end
IA.PutO = Put

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- v1 reads its colours three ways; each reader below copies one of them.
-- Per channel, named first then listed, each missing channel from `d` (the glows).
function IA.V1ColorMixed(c, d)
    if type(c) ~= "table" then return nil end
    return { c.r or c[1] or d[1], c.g or c[2] or d[2], c.b or c[3] or d[3], c.a or c[4] or d[4] or 1 }
end
-- Named channels only, each missing one from `d` (usability tints, the cooldown tint).
function IA.V1ColorNamed(c, d)
    if type(c) ~= "table" then return nil end
    return { c.r or d[1], c.g or d[2], c.b or d[3], c.a or d[4] or 1 }
end
-- Named when any named channel is there, else listed, a missing channel 1 (texts, borders).
function IA.V1Color(c)
    if type(c) ~= "table" then return nil end
    local r, g, b, a = c.r, c.g, c.b, c.a
    if r == nil and g == nil and b == nil then r, g, b, a = c[1], c[2], c[3], c[4] end
    if type(r) ~= "number" and type(g) ~= "number" and type(b) ~= "number" then return nil end
    return { type(r) == "number" and r or 1, type(g) == "number" and g or 1,
        type(b) == "number" and b or 1, type(a) == "number" and a or 1 }
end
-- The swipe's: named channels, a missing one 0, a missing alpha `a`.
function IA.V1SwipeColor(c, a)
    if type(c) ~= "table" then return nil end
    return { c.r or 0, c.g or 0, c.b or 0, c.a or a }
end
local V1Color, V1Mixed, V1Named = IA.V1Color, IA.V1ColorMixed, IA.V1ColorNamed
local WHITE = { 1, 1, 1, 1 }

-- Arc Auras sizes icon texts, their offsets, padding and swipe insets by the icon's height over
-- 36; Arc UI keeps them in fixed units. kS turns one into the other.
function IA.IconScale(ctx)
    local h = ctx and tonumber(ctx.H)
    return (h and h > 0) and (h / 36) or 1
end

-- The whole Arc Auras font size that draws nearest v1's absolute size at this icon height.
function IA.FontSize(s, kS)
    s = tonumber(s)
    if not s then return nil end
    local best, gap
    local a0 = math.floor(s / kS + 0.5)
    for a = a0 - 1, a0 + 1 do
        if a >= 1 then
            local d = math.abs(math.max(6, math.floor(a * kS + 0.5)) - s)
            if not gap or d < gap then best, gap = a, d end
        end
    end
    return best
end

-- A v1 length in fixed units as the Arc Auras value that lands nearest it.
function IA.Units(v, kS)
    v = tonumber(v)
    if not v then return nil end
    return math.floor(v / kS + 0.5)
end

-- Text anchors an Arc Auras icon text takes.
IA.ICON_TEXT_ANCHORS = { CENTER = true, TOP = true, BOTTOM = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true, LEFT = true, RIGHT = true }

-- v1 glow types -> Arc Auras styles. v1 starts every proc glow without its burst (its "proc" and
-- the proc glow's "default" alike), which is Arc Auras' Proc loop. Its assisted-combat style is the
-- game's spell alert looping: the same art and timing on a 66/45 box, so Proc loop with the offset
-- carrying the size (IA.MapGlow).
IA.V1_GLOW = { button = "button", pixel = "pixel", autocast = "autocast", proc = "procloop",
    blizzard = "procloop", default = "procloop", ants = "ants", ach_proc = "procloop", cdm_flash = "flash" }
-- the aura-active lane draws its Proc as the loop already and has no Proc loop entry
IA.V1_GLOW_AURA = { button = "button", pixel = "pixel", autocast = "autocast", proc = "proc",
    blizzard = "proc", default = "proc", ants = "ants", ach_proc = "proc", cdm_flash = "flash" }
IA.V1_GLOW_GOLD = { 1, 0.85, 0.1, 1 }
IA.V1_PROC_GOLD = { 0.95, 0.95, 0.32, 1 }
local BLIZZ = 66 / 45
local TINTS = { "button", "proc", "blizzard", "default" }

local function Note(ctx, what)
    if ctx and ctx.notes then ctx.notes[#ctx.notes + 1] = what end
end

-- One v1 sound trigger: its sound plays unless its switch is off (a switch never set counts as
-- on once a sound is picked), and its spoken text the same way. An aura's moments are the game's
-- to play in Arc Auras: a sound, never words.
local function V1Alert(o, t, base, arc, ctx)
    local s = t[base .. "Sound"]
    local on = t[base .. "SoundOn"] ~= false and type(s) == "string" and s ~= "" and s ~= "None" and s ~= "__tts__"
    local x = t[base .. "TTS"]
    local say = t[base .. "TTSOn"] ~= false and type(x) == "string" and x ~= ""
    if say and arc:sub(1, 4) == "aura" then
        Note(ctx, "spoken aura alerts (the game plays an aura's sounds)")
        say = false
    end
    Put(o, "alerts", arc .. "SoundEnabled", on or say)
    if on then Put(o, "alerts", arc .. "Sound", s) end
    if say then Put(o, "alerts", arc .. "Speech", x:sub(1, 200)) end
end
local function V1Channel(o, t)
    if type(t.channel) == "string" and t.channel ~= "" then Put(o, "alerts", "soundChannel", t.channel) end
end
-- v1's oldest alerts (no option left for them, still played when a save carries one)
local function OldAlertEvents(eff, ctx)
    for _, e in pairs(type(eff.alertEvents) == "table" and eff.alertEvents or {}) do
        if type(e) == "table" and (e.playSound == true or e.showGlow == true) then
            Note(ctx, "an old alert event (sound or glow)")
            return
        end
    end
end

-- One v1 glow onto an Arc Auras glow lane. g = the v1 glow, already read:
--   on, type, color (nil = none set), native (v1 draws the game's own colour when none is set),
--   intensity, intensitySquared (v1 also fades the glow's frame), frameAlpha (the part of the
--   intensity v1 lays on the glow's frame, all a game-coloured proc glow keeps), scale, speed, lines, thickness,
--   particles, length (a pixel line's, where v1 passes it), x, y (expansion, before padding),
--   tx, ty (translate), strata, level (v1's offset over its icon), combat, fallback (the
--   colour drawn when none is set, when not the gold)
-- lane = { sec, prefix, suf (an aura icon's glow 2 to 4), aura (the aura-active lane), combat
-- (the lane takes combat only) }
-- ctx: pad (v1 padding), W, H (v1 icon size), nativeGlow (the account-wide switch), notes.
function IA.MapGlow(o, lane, g, ctx)
    local sec, p, suf = lane.sec, lane.prefix, lane.suf or ""
    local function F(name) return p .. name .. suf end
    Put(o, sec, F(""), g.on == true)
    if g.on ~= true then return end
    local v1type = g.type or "button"
    local map = lane.aura and IA.V1_GLOW_AURA or IA.V1_GLOW
    Put(o, sec, F("Type"), map[v1type] or "button")
    local tinted = false
    for _, t in ipairs(TINTS) do if v1type == t then tinted = true end end
    -- the game's own colour: v1 hands its button or proc glow no colour, so only the frame
    -- part of the intensity is left (a button glow skips even that)
    local native = tinted and (ctx.nativeGlow or (g.color == nil and g.native)) and true or false
    Put(o, sec, F("Native"), native)
    local col = Copy(g.color or g.fallback or IA.V1_GLOW_GOLD)
    col[4] = 1
    Put(o, sec, F("Color"), col)
    local inten = tonumber(g.intensity) or 1
    if g.intensitySquared and v1type ~= "button" then inten = inten * inten end
    if native then inten = (v1type == "button") and 1 or (tonumber(g.frameAlpha) or 1) end
    Put(o, sec, F("Intensity"), Clamp(inten, 0.1, 1))
    Put(o, sec, F("Speed"), Clamp(tonumber(g.speed) or 0.25, 0.05, 1))
    local scale = tonumber(g.scale) or 1
    local thick = tonumber(g.thickness) or 2
    if v1type == "pixel" and scale ~= 1 then thick = math.max(1, math.floor(thick * scale)) end
    Put(o, sec, F("Lines"), Clamp(math.floor((tonumber(g.lines) or 8) + 0.5), 1, 16))
    Put(o, sec, F("Thickness"), Clamp(math.floor(thick + 0.5), 1, 20))
    Put(o, sec, F("Particles"), Clamp(math.floor((tonumber(g.particles) or 4) + 0.5), 1, 16))
    -- the size: autocast's particles, a button or proc glow scaled whole (as v1 scales its frame)
    local sized = v1type == "autocast" or tinted
    Put(o, sec, F("Scale"), Clamp(sized and scale or 1, 0.5, 2))
    if sized and (scale < 0.5 or scale > 2) then Note(ctx, "a glow size past 0.5 to 2") end
    local len = tonumber(g.length)
    if v1type == "pixel" and len and len > 0 then
        if len > 40 then Note(ctx, "a pixel glow line longer than 40") end
        Put(o, sec, F("Length"), Clamp(math.floor(len + 0.5), 0, 40))
    end
    Put(o, sec, F("Backing"), v1type == "pixel" and not g.noBacking)
    -- expansion: v1 hugs the art (its offset minus the padding); Arc Auras' library glows hug
    -- the frame, its ants and flash take 66/45 of it, so the offset carries the rest of v1's size
    local pad = tonumber(ctx.pad) or 0
    local x, y = (tonumber(g.x) or 0) - pad, (tonumber(g.y) or 0) - pad
    local W, H = tonumber(ctx.W) or 36, tonumber(ctx.H) or 36
    if v1type == "ants" then
        x = (W * (scale - 1) * BLIZZ) / 2 + x * BLIZZ
        y = (H * (scale - 1) * BLIZZ) / 2 + y * BLIZZ
    elseif v1type == "cdm_flash" then
        x = (W * BLIZZ * (scale - 1)) / 2 + x
        y = (H * BLIZZ * (scale - 1)) / 2 + y
    elseif v1type == "ach_proc" then
        -- its 66/45 box (times its size) onto our proc loop's 1.4
        x = (W * (BLIZZ * scale - 1.4)) / 2 + x
        y = (H * (BLIZZ * scale - 1.4)) / 2 + y
    end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local tx, ty = math.floor((tonumber(g.tx) or 0) + 0.5), math.floor((tonumber(g.ty) or 0) + 0.5)
    for _, v in ipairs({ x, y, tx, ty }) do
        if v < -50 or v > 50 then Note(ctx, "a glow offset past 50") break end
    end
    Put(o, sec, F("XOffset"), Clamp(x, -50, 50))
    Put(o, sec, F("YOffset"), Clamp(y, -50, 50))
    Put(o, sec, F("MoveX"), Clamp(tx, -50, 50))
    Put(o, sec, F("MoveY"), Clamp(ty, -50, 50))
    -- v1's strata only where it set one: its forced MEDIUM put the glow under an icon
    -- whose group stands higher (a slip, not carried)
    local strata = g.strata
    if strata == "inherit" then strata = nil end
    if strata then Put(o, sec, F("Strata"), strata) end
    -- v1's level is an offset over its icon, which wears its own border; Arc Auras draws
    -- the border on a frame over the icon, so the offset counts from its own glow place
    -- (Core\AD_Factory.lua GLOW_LEVEL, over the border and the swipe), never under it
    if tonumber(g.level) then
        local lv = math.floor(tonumber(g.level) + 0.5) + (NS.GLOW_LEVEL or 7) - 1
        if lv > 100 then Note(ctx, "a glow frame level past 100") end
        Put(o, sec, F("Level"), Clamp(lv, 1, 100))
    end
    if lane.combat then Put(o, sec, F("CombatOnly"), g.combat == true) end
end

-- A v1 text (charge or countdown) onto an Arc Auras text: font, size, outline, colour, shadow,
-- and its place (an anchor point, or "free": the icon's centre plus offsets), in Arc Auras units.
-- Returns an anchor Arc Auras does not offer.
function IA.MapText(o, pre, t, kS, defaults)
    t = type(t) == "table" and t or {}
    Put(o, "text", pre .. "Size", IA.FontSize(t.size or defaults.size, kS))
    Put(o, "text", pre .. "Font", IA.CONV.font(t.font or "Friz Quadrata TT"))
    Put(o, "text", pre .. "Outline", IA.CONV.outline(t.outline or "OUTLINE"))
    Put(o, "text", pre .. "Color", V1Color(t.color) or { 1, 1, 1, 1 })
    Put(o, "text", pre .. "Shadow", t.shadow == true)
    if t.shadow == true then
        Put(o, "text", pre .. "ShadowColor", { 0, 0, 0, 0.8 })
        local sx, sy = tonumber(t.shadowOffsetX) or 1, tonumber(t.shadowOffsetY) or -1
        Put(o, "text", pre .. "ShadowX", Clamp(math.floor(sx + 0.5), -5, 5))
        Put(o, "text", pre .. "ShadowY", Clamp(math.floor(sy + 0.5), -5, 5))
    end
    local anchor, x, y
    if t.mode == "free" then
        anchor, x, y = "CENTER", t.freeX or 0, t.freeY or 0
    else
        anchor = t.anchor or defaults.anchor
        x, y = t.offsetX or defaults.x, t.offsetY or defaults.y
    end
    if not IA.ICON_TEXT_ANCHORS[anchor] then return anchor end
    Put(o, "text", pre .. "Anchor", anchor)
    Put(o, "text", pre .. "X", IA.Units(x, kS))
    Put(o, "text", pre .. "Y", IA.Units(y, kS))
end

-- v1's swipe insets onto the aura swipe: pad = the art's padding v1 adds to them (a
-- Cooldown Manager icon's; Arc UI's own aura icons add none), in Arc Auras units.
function IA.MapAuraSwipeInset(o, sw, kS, pad)
    pad = tonumber(pad) or 0
    local sep = sw.separateInsets == true
    Put(o, "auraSwipe", "separateInsets", sep)
    if sep then
        Put(o, "auraSwipe", "swipeInsetX", Clamp(IA.Units(pad + (tonumber(sw.swipeInsetX) or 0), kS), -20, 40))
        Put(o, "auraSwipe", "swipeInsetY", Clamp(IA.Units(pad + (tonumber(sw.swipeInsetY) or 0), kS), -20, 40))
    else
        Put(o, "auraSwipe", "swipeInset", Clamp(IA.Units(pad + (tonumber(sw.swipeInset) or 0), kS), -20, 40))
    end
end

-- v1's pandemic border: the Cooldown Manager's pandemic art in the game's pandemic window (here
-- the last 30 percent), on the next free aura glow in Arc Auras' Pandemic border style, sized a
-- sixth of the short side out from the button, less the padding, plus the crop (v1's formula).
-- used = the glows taken, max = the glows the icon has.
function IA.MapPandemicBorder(o, eff, ctx, kS, used, max)
    if not (type(eff.pandemicBorder) == "table" and eff.pandemicBorder.enabled == true) then return end
    if used >= max then
        Note(ctx, "the pandemic border (every glow is in use)")
        return
    end
    local suf = (used + 1 > 1) and tostring(used + 1) or ""
    Put(o, "auraActive", "activeGlow" .. suf, true)
    Put(o, "auraActive", "activeGlowType" .. suf, "pandemic")
    Put(o, "auraActive", "activeGlowNative" .. suf, true)
    Put(o, "auraActive", "activeGlowWhen" .. suf, "time")
    Put(o, "auraActive", "activeGlowTimeUnit" .. suf, "pct")
    Put(o, "auraActive", "activeGlowTimePct" .. suf, 30)
    Put(o, "auraActive", "activeGlowCombatOnly" .. suf, false)
    local W, H = tonumber(ctx.W) or 36, tonumber(ctx.H) or 36
    local off = (tonumber(eff.zoom) or 0.08) * math.min(W, H) - (tonumber(eff.padding) or 0)
    local u = Clamp(IA.Units(off, kS) or 0, -50, 50)
    Put(o, "auraActive", "activeGlowXOffset" .. suf, u)
    Put(o, "auraActive", "activeGlowYOffset" .. suf, u)
    Note(ctx, "the game's pandemic window as the last 30 percent")
end

-- v1's keybind look: its upper-case short form, the spec's find-and-replace lists as
-- FIND=REPL pairs, its outline. kb = the spec's keybind settings, use = the icon's own.
function IA.MapKeybindLook(o, kb, use)
    Put(o, "keybind", "keybindStyle", "upper")
    local find, with = kb.replaceFindText, kb.replaceWithText
    if type(find) == "string" and find:match("%S") then
        local froms, tos = {}, {}
        for item in find:gmatch("[^,]+") do
            local t = item:match("^%s*(.-)%s*$")
            if t ~= "" then froms[#froms + 1] = t:upper() end
        end
        for item in (type(with) == "string" and with or ""):gmatch("[^,]+") do
            tos[#tos + 1] = item:match("^%s*(.-)%s*$")
        end
        local pairs_ = {}
        for i, from in ipairs(froms) do pairs_[#pairs_ + 1] = from .. "=" .. (tos[i] or "") end
        if #pairs_ > 0 then Put(o, "keybind", "keybindReplace", table.concat(pairs_, ", ")) end
    end
    Put(o, "keybind", "keybindOutline", IA.CONV.outline(use.outline or kb.fontOutline or "OUTLINE"))
end

-- v1's Show below: the countdown waits under N seconds (v1 caps it at 59), and M:SS is off.
function IA.MapShowBelow(o, ct)
    local v = tonumber(ct.showBelowSeconds) or 0
    if v <= 0 then return end
    Put(o, "text", "durationShowBelow", Clamp(math.floor(math.min(v, 59) + 0.5), 1, 59))
    Put(o, "text", "durationAbbrev", 0)
end

-- v1's Color by Duration on aura icons when no band of its own is on (seconds left, colour).
IA.V1_CLASSIC_BANDS = { { 5, { 1, 0.39, 0.28, 1 } }, { 60, { 1, 1, 0, 1 } }, { 3600, { 1, 1, 1, 1 } } }

-- v1's duration colour bands (the ones switched on, by threshold) onto Arc Auras' three; the colour
-- above them is the text's own colour in both. A cooldown icon colours by its own bands only (none
-- on: no colour), percent ones included; an aura icon (aura) by seconds only, with no colour at all
-- when they are percent, and the classic three when none is on.
function IA.MapDurationBands(o, ct, ctx, aura)
    local on = ct.durationColor ~= nil and ct.durationColor ~= false
    local list = on and type(ct.durationColorCustom) == "table" and ct.durationColorCustom or nil
    if aura and ct.durationColorUsePercent then list, on = nil, false end
    local bands = {}
    for _, b in ipairs(list or {}) do
        if type(b) == "table" and b.enabled then
            local t = tonumber(b.threshold)
            if not aura then t = t or 0 end
            if t and (not aura or (t > 0 and type(b.color) == "table")) then
                bands[#bands + 1] = { t = t, c = V1Named(type(b.color) == "table" and b.color or {}, WHITE) }
            end
        end
    end
    if aura and on and #bands == 0 then
        for _, b in ipairs(IA.V1_CLASSIC_BANDS) do bands[#bands + 1] = { t = b[1], c = Copy(b[2]) } end
    end
    for _, b in ipairs(bands) do b.c[4] = 1 end
    table.sort(bands, function(a, b) return a.t < b.t end)
    Put(o, "text", "durationColorBands", #bands > 0)
    if #bands == 0 then return end
    -- a cooldown icon's bands in percent of the duration (an aura icon's draw none in v1)
    local pct = ct.durationColorUsePercent == true and not aura
    Put(o, "text", "durationBandsPercent", pct)
    if #bands > 5 then Note(ctx, "more than five duration colours") end
    Put(o, "text", "durBandCount", math.min(5, #bands))
    for i = 1, 5 do
        local b = bands[i]
        if b then
            if pct then
                Put(o, "text", "durBand" .. i .. "Pct", Clamp(math.floor(b.t + 0.5), 1, 99))
            else
                Put(o, "text", "durBand" .. i .. "Sec", Clamp(math.floor(b.t + 0.5), 1, 3600))
            end
            Put(o, "text", "durBand" .. i .. "Color", b.c)
        end
    end
end

-- The glows v1 reads off one settings table: its shape keys under `pre` ("glow" for
-- readyState / auraActiveState) and the translate pair. v1 gives these a gold colour when none is
-- set, so only the account-wide switch (or a lane that hands none, as an Arc spell's) untints them.
local function V1Glow(t, on, extra)
    local g = { on = on, type = t.glowType, intensity = t.glowIntensity, scale = t.glowScale,
        speed = t.glowSpeed, lines = t.glowLines, thickness = t.glowThickness, particles = t.glowParticles,
        x = t.glowXOffset, y = t.glowYOffset, tx = t.glowTranslateX, ty = t.glowTranslateY,
        strata = t.glowFrameStrata, level = t.glowFrameLevel, combat = t.glowCombatOnly,
        color = t.glowColor ~= nil and V1Mixed(t.glowColor, IA.V1_GLOW_GOLD) or nil, native = false,
        frameAlpha = t.glowIntensity }
    for k, v in pairs(extra or {}) do g[k] = v end
    return g
end

-- v1's Duration Override from a totem (its default source) or a fixed time after the cast: the
-- overlay from the spell's totem or a set duration on cast (Drivers\AD_DriverPhase.lua), drawn in
-- the icon's Aura Active look as v1 draws it (in colour, its aura glow, opacity and swipe).
-- Returns the overlay, or nil when v1 runs none (the aura source, or a fixed time of 0).
IA.PHASE_MAX_SECONDS = 3600
function IA.MapPhaseOverride(o, eff, dov, ctx)
    local mode = dov.mode or "totem"
    if mode == "aura" then return nil end
    local ends = {}
    for id in tostring(dov.endSpells or ""):gmatch("%d+") do
        local n = tonumber(id)
        if n and n > 0 then ends[#ends + 1] = n end
    end
    local ov
    if mode == "manual" then
        local secs = tonumber(dov.manual) or 0
        if secs <= 0 then return nil end
        if secs > IA.PHASE_MAX_SECONDS then Note(ctx, "a Duration Override longer than an hour") end
        ov = { on = true, source = "cast", seconds = math.min(secs, IA.PHASE_MAX_SECONDS) }
        if #ends > 0 then ov.endSpells = ends end
        if dov.endOnDeath == true then ov.endOnDeath = true end
    else
        ov = { on = true, source = "totem" }
        if #ends > 0 then Note(ctx, "spells that end a totem's time early") end
    end
    local aa = type(eff.auraActiveState) == "table" and eff.auraActiveState or {}
    local sw = type(eff.cooldownSwipe) == "table" and eff.cooldownSwipe or {}
    Put(o, "auraActive", "overlayArt", "spell")
    Put(o, "auraActive", "overlayDesatInactive", aa.desaturateWhenInactive == true)
    Put(o, "auraActive", "activeAlpha", aa.activeAlphaEnabled == true and (tonumber(aa.activeAlpha) or 1) or 1)
    IA.MapGlow(o, { sec = "auraActive", prefix = "activeGlow", aura = true, combat = true },
        V1Glow(aa, aa.glow == true, { length = aa.glowLength }), ctx)
    local asc = IA.V1SwipeColor(sw.auraSwipeColor, 0.7)
    if asc then Put(o, "auraSwipe", "overlaySwipeColor", asc) end
    Put(o, "auraSwipe", "overlaySwipeReverse", sw.reverse == true or sw.reverseWhileAura == true)
    return ov
end

-- The art and its frame, alike on every v1 icon: the crop, the inset art, the custom art, the
-- shadow (v1 draws it only with the spec's Cooldown Manager style) and the border. greys: the
-- icon ever greys, for the border that follows it.
local function MapAppearance(o, eff, ctx, kS, greys)
    local pad = tonumber(eff.padding) or 0
    Put(o, "appearance", "zoom", Clamp(tonumber(eff.zoom) or 0.08, 0, 0.4))
    Put(o, "appearance", "aspectRatio", Clamp(tonumber(eff.aspectRatio) or 1, 0.25, 2.5))
    if pad < 0 then Note(ctx, "a negative padding") end
    Put(o, "appearance", "padding", Clamp(IA.Units(math.max(0, pad), kS), 0, 20))
    local cid = tonumber(eff.customIconID)
    if eff.forceHideIcon == true or cid == 0 then
        Put(o, "appearance", "forceHideIcon", true)
    elseif cid and cid > 0 then
        Put(o, "appearance", "customIcon", cid)
        Put(o, "appearance", "customIconFrom", ctx.iconFrom or "icon")
    end
    Put(o, "appearance", "shadowEnabled", ctx.keepCDMStyle == true)
    if ctx.keepCDMStyle == true then
        Put(o, "appearance", "shadowSize", Clamp(tonumber(eff.shadowSize) or 1, 0.1, 3))
        Note(ctx, "the Cooldown Manager's rounded icon")
    end
    local bd = type(eff.border) == "table" and eff.border or {}
    Put(o, "appearance", "borderEnabled", bd.enabled == true)
    Put(o, "appearance", "borderColor", V1Color(bd.color) or { 1, 1, 1, 1 })
    Put(o, "appearance", "borderThickness", Clamp(math.floor((tonumber(bd.thickness) or 2) + 0.5), 1, 20))
    Put(o, "appearance", "borderInset", Clamp(math.floor((tonumber(bd.inset) or -3) + 0.5), -20, 20))
    Put(o, "appearance", "borderClassColor", bd.useClassColor == true)
    Put(o, "appearance", "borderFollowsGrey", bd.followDesaturation == true and greys and true or false)
end

-- A Cooldown Manager cooldown icon -> Arc Auras overrides. eff: v1's effective settings.
-- kind: spell / item / trinket. ctx: H, W (v1 icon size), keepCDMStyle (the spec's Cooldown
-- Manager style), nativeGlow (account-wide), keybinds (the spec's keybind setting), iconFrom
-- (custom icon: "spell" or "icon"), hasAura (the cooldown has an aura phase), notes.
-- v1's Assisted Combat highlight (one switch per character, ctx.ach): on a spell icon of the
-- Cooldown Manager, and on Arc UI's own with its "on Arc Auras" switch, the While suggested glow
-- in its style and colour. Its size scales the game's 66 / 45 art box, which Arc Auras grows by
-- twice its offsets; its own level, strata and always-animate are said.
IA.V1_ACH_STYLE = { ants = "ants", proc = "proc" }
function IA.MapAssist(o, ctx, arc, kS)
    local a = type(ctx.ach) == "table" and ctx.ach or nil
    if not (a and a.assistedCombatHighlight == true) then return end
    if arc and a.achOnArcAuras ~= true then return end
    Put(o, "states", "assistGlow", true)
    local style = IA.V1_ACH_STYLE[a.achStyle] or "ants"
    -- the proc style without its burst is the loop alone
    if style == "proc" and a.achShowBurst == false then style = "procloop" end
    Put(o, "states", "assistGlowType", style)
    if type(a.achColor) == "table" then Put(o, "states", "assistGlowColor", V1Named(a.achColor, { 1, 1, 1, 1 })) end
    Put(o, "states", "assistGlowCombatOnly", a.achCombatOnly == true)
    local lv, sc = tonumber(a.achLevel), tonumber(a.achScale)
    if not (sc and sc > 0) then sc = 1 end
    -- v1 draws it on the game's 66/45 box times its size; our ants share that box, our proc
    -- glows lay 1.4, so the offset carries the rest
    local base = (style == "proc" or style == "procloop") and 1.4 or (66 / 45)
    local W, H = tonumber(ctx.W) or 36, tonumber(ctx.H) or 36
    local ex, ey = W * ((66 / 45) * sc - base) / 2, H * ((66 / 45) * sc - base) / 2
    if math.abs(ex) >= 0.5 or math.abs(ey) >= 0.5 then
        Put(o, "states", "assistGlowXOffset", Clamp(IA.Units(ex, kS) or 0, -50, 50))
        Put(o, "states", "assistGlowYOffset", Clamp(IA.Units(ey, kS) or 0, -50, 50))
    end
    if (lv and lv ~= 5) or (a.achStrata ~= nil and a.achStrata ~= "INHERIT") or a.achAlwaysAnimate == true then
        Note(ctx, "an Assisted Combat highlight's own level, strata or animation")
    end
end

function IA.MapCooldownIcon(eff, kind, ctx)
    ctx = ctx or {}
    ctx.notes = ctx.notes or {}
    local o = {}
    local kS = IA.IconScale(ctx)
    local isSpell = kind == "spell"
    -- a trinket's on-use buff is its aura phase, as a spell's aura is
    local phased = isSpell or (kind == "trinket" and ctx.hasAura == true)
    local sv = type(eff.cooldownStateVisuals) == "table" and eff.cooldownStateVisuals or {}
    local rs = type(sv.readyState) == "table" and sv.readyState or {}
    local cs = type(sv.cooldownState) == "table" and sv.cooldownState or {}
    local su = type(eff.spellUsability) == "table" and eff.spellUsability or {}
    local aa = type(eff.auraActiveState) == "table" and eff.auraActiveState or {}
    local sw = type(eff.cooldownSwipe) == "table" and eff.cooldownSwipe or {}
    local ri = type(eff.rangeIndicator) == "table" and eff.rangeIndicator or {}
    local pg = type(eff.procGlow) == "table" and eff.procGlow or {}
    local pad = tonumber(eff.padding) or 0
    ctx.pad = pad

    MapAppearance(o, eff, ctx, kS, true)

    -- states: ready; on cooldown (the main cooldown, or the last charge spent: greyed unless
    -- v1's No desaturate); recharging (a charge left: coloured, on the cooldown look unless "wait
    -- for no charges" gives it the ready one). Keep bright in v1 whitens the art and lets its own
    -- cooldown grey through; it never touches the alpha.
    local keepBright = eff.keepBright == true
    local desatOK = not keepBright or eff.keepBrightAllowDesat == true
    local readyA = tonumber(rs.alpha) or 1
    local cdA = tonumber(cs.alpha) or 1
    local wait = cs.waitForNoCharges == true
    Put(o, "states", "readyAlpha", readyA)
    Put(o, "states", "cooldownAlpha", cdA)
    Put(o, "states", "cooldownDesaturate", cs.noDesaturate ~= true)
    -- v1 keeps the texts bright on the cooldown look only
    Put(o, "states", "preserveDurationText", cs.preserveDurationText == true)
    if cs.preserveDurationText == true then Put(o, "states", "preserveTextWhen", "cooldown") end
    -- v1 lifts the icon only while its own proc glow shows, and from the state whose switch is on
    local procShown = pg.enabled ~= false
    local poR, poC = procShown and rs.procOverride == true, procShown and cs.procOverride == true
    Put(o, "states", "procOverride", poR or poC)
    if poR ~= poC then Put(o, "states", "procOverrideWhen", poR and "ready" or "cooldown") end
    if isSpell and wait and (poR ~= poC or (cs.preserveDurationText == true and readyA < 1)) then
        Note(ctx, "a rule for one state on a charge spell that waits for no charges")
    end
    if isSpell then Put(o, "states", "ignoreHardICD", sw.ignoreHardICD == true) end

    -- tints in v1's order: the cooldown look's own tint, keep bright's white, the usability
    -- colours, the on-cooldown colour. With v1's usability tinting off its panel promises white;
    -- it left the game's blue and grey on, a slip not carried (the range red is its own switch).
    local suOn = su.enabled ~= false
    local cdTint = cs.tint == true and cs.tintColor ~= nil and V1Named(cs.tintColor, { 0.5, 0.5, 0.5, 1 }) or nil
    local onCd = suOn and su.useOnCooldownColor == true and V1Named(su.onCooldownColor or {}, { 0.4, 0.4, 0.4, 1 }) or nil
    -- keep bright whitens every tint but the cooldown look's own, which beats it while it shows
    local white = keepBright
    Put(o, "states", "cooldownTintEnabled", (cdTint or (not white and onCd)) and true or false)
    if cdTint or (not white and onCd) then Put(o, "states", "cooldownTintColor", cdTint or onCd) end
    local normal = (not white) and suOn and su.useNormalColor == true and V1Named(su.normalColor or {}, { 1, 1, 1, 1 }) or nil
    Put(o, "states", "readyTintEnabled", normal and true or false)
    if normal then Put(o, "states", "readyTintColor", normal) end
    local tinted = suOn and not white
    Put(o, "states", "resourceTintEnabled", tinted)
    Put(o, "states", "unusableTintEnabled", tinted)
    if tinted then
        Put(o, "states", "resourceTintColor", V1Named(su.notEnoughResourceColor or {}, { 0.5, 0.5, 1, 1 }))
        Put(o, "states", "unusableTintColor", V1Named(su.notUsableColor or {}, { 0.4, 0.4, 0.4, 1 }))
    end
    -- the range state stays on under keep bright (v1 still drops the usability dim out of range);
    -- only its red turns white
    Put(o, "states", "rangeTint", ri.enabled ~= false)
    Put(o, "states", "rangeTintColor", white and { 1, 1, 1, 1 } or { 0.64, 0.15, 0.15, 1 })
    -- the Cooldown Manager's out-of-range shadow, refitted by v1's size
    Put(o, "states", "rangeShadow", ri.enabled ~= false and ri.hideShadow ~= true)
    if ri.enabled ~= false and ri.hideShadow ~= true then
        Put(o, "states", "rangeShadowSize", Clamp(tonumber(ri.shadowScale) or 1, 0.5, 1.5))
    end
    Put(o, "states", "rangeAlpha", 1)
    Put(o, "states", "rangeDesaturate", false)
    -- usability alpha and grey (v1 applies them while ready)
    Put(o, "states", "resourceAlpha", suOn and (tonumber(su.notEnoughResourceAlpha) or 1) or 1)
    Put(o, "states", "unusableAlpha", suOn and (tonumber(su.notUsableAlpha) or 1) or 1)
    Put(o, "states", "resourceDesaturate", suOn and desatOK and su.notEnoughResourceDesaturate == true)
    Put(o, "states", "unusableDesaturate", suOn and desatOK and su.notUsableDesaturate == true)
    Put(o, "states", "readyDesaturate", suOn and desatOK and su.normalDesaturate == true)
    -- v1's ready grey waits while the spell is out of range or not usable
    Put(o, "states", "readyGreyUsable", suOn and desatOK and su.normalDesaturate == true)
    -- a usability opacity v1 sets replaces the ready one; one left unset keeps it
    local replace = suOn and (su.notEnoughResourceAlpha ~= nil or su.notUsableAlpha ~= nil)
    Put(o, "states", "usabilityAlphaReplaces", replace and true or false)
    if replace then
        Put(o, "states", "resourceAlpha", tonumber(su.notEnoughResourceAlpha) or readyA)
        Put(o, "states", "unusableAlpha", tonumber(su.notUsableAlpha) or readyA)
    end
    if isSpell then
        -- the tints stay on a cooling spell, as the game's do, unless a cooldown colour or keep bright
        -- covers them; a charge coming back keeps them but none of the usability dims or greys
        local cooling = not white and not cdTint and not onCd
        Put(o, "states", "usabilityOnCooldown", cooling)
        Put(o, "states", "usabilityReadyOnly", not wait)
        if cooling and suOn and (su.notEnoughResourceColor ~= nil or su.notUsableColor ~= nil) then
            Note(ctx, "the game's usability colours over custom ones on a cooling spell")
        end
        -- v1's on-cooldown colour stops at the last charge: one coming back shows the game's tints
        if not white and not cdTint and onCd and not wait then
            Note(ctx, "the game's usability colours while a charge comes back, under an on-cooldown colour")
        end
        if su.procOverride == true and pg.enabled ~= false then Note(ctx, "a proc that lifts only the usability dim") end
    end

    -- recharging: written in full so the store's fold for old records leaves it alone
    if isSpell then
        Put(o, "states", "rechargeAlpha", wait and readyA or cdA)
        Put(o, "states", "rechargeDesaturate", wait and suOn and desatOK and su.normalDesaturate == true or false)
        local rTint
        if wait then rTint = normal else rTint = cdTint end
        Put(o, "states", "rechargeTintEnabled", rTint and true or false)
        if rTint then Put(o, "states", "rechargeTintColor", rTint) end
    end

    -- glows: ready (kept while recharging when v1 glows while charges remain), proc, usable
    local ready = V1Glow(rs, rs.glow == true, { intensitySquared = true })
    IA.MapGlow(o, { sec = "states", prefix = "readyGlow", combat = true }, ready, ctx)
    if isSpell then
        local rg = Copy(ready)
        rg.on = rs.glow == true and rs.glowWhileChargesAvailable == true
        IA.MapGlow(o, { sec = "states", prefix = "rechargeGlow", combat = true }, rg, ctx)
        if rs.glowFollowPandemic == true and rs.glow == true then Note(ctx, "a ready glow only in the aura's pandemic window") end
        local pType = pg.glowType or "default"
        local pCol = pg.color ~= nil and V1Mixed(pg.color, IA.V1_PROC_GOLD) or nil
        IA.MapGlow(o, { sec = "states", prefix = "procGlow" }, {
            on = pg.enabled ~= false, type = pType, color = pCol or ((pType ~= "default" and pType ~= "proc"
                and pType ~= "button") and IA.V1_PROC_GOLD or nil),
            native = true, intensity = pCol and (tonumber(pg.alpha) or 1) or 1, scale = pg.scale,
            speed = pg.speed, lines = pg.lines, thickness = pg.thickness, particles = pg.particles,
            x = pg.xOffset, y = pg.yOffset, tx = pg.translateX, ty = pg.translateY, strata = pg.strata,
            level = pg.frameLevel,
        }, ctx)
        local uType = su.usableGlowType or "button"
        if uType == "glow" or uType == "blizzard" then uType = "proc" end
        local uCol = su.usableGlowColor ~= nil and V1Mixed(su.usableGlowColor, IA.V1_GLOW_GOLD) or nil
        IA.MapGlow(o, { sec = "states", prefix = "usableGlow", combat = true }, {
            on = su.usableGlow == true, type = uType, color = uCol,
            native = su.usableGlowType == "default" or su.usableGlowType == "blizzard" or su.usableGlowType == "glow",
            intensity = uCol and uCol[4] or 1, scale = su.usableGlowScale, speed = su.usableGlowSpeed,
            lines = su.usableGlowLines, thickness = su.usableGlowThickness, particles = su.usableGlowParticles,
            x = su.usableGlowXOffset, y = su.usableGlowYOffset, strata = su.usableGlowFrameStrata,
            level = su.usableGlowFrameLevel, combat = su.usableGlowCombatOnly,
        }, ctx)
    end

    -- Duration Override (12.1): its aura source lays that aura (by spell id, on you, any caster)
    -- over the icon while it is up: the icon's own art, the game's default cooldown swipe and
    -- countdown. That is Arc Auras' aura on this icon; the planner puts it on the driver
    -- (ctx.overlayAura). Its totem and fixed-time sources are the overlay from the totem or a set
    -- duration on cast, in the Aura Active look (IA.MapPhaseOverride). An item's or a trinket's use
    -- spell stands in for the spell.
    local dov = type(eff.durationOverride) == "table" and eff.durationOverride or {}
    local ovKind = isSpell or kind == "item" or kind == "trinket"
    local doAura = ovKind and dov.enabled == true and dov.mode == "aura" and tonumber(dov.auraSpellID) or nil
    local doPhase = ovKind and dov.enabled == true and not doAura and IA.MapPhaseOverride(o, eff, dov, ctx) or nil
    if doPhase then
        ctx.overlayAura = doPhase
    elseif doAura then
        ctx.overlayAura = { on = true, spellID = doAura, auraType = "buff", unit = "player" }
        Put(o, "auraActive", "overlayArt", "spell")
        Put(o, "auraActive", "overlayDesatInactive", false)
        Put(o, "auraActive", "activeAlpha", 1)
        Put(o, "auraActive", "activeGlow", false)
        Put(o, "auraSwipe", "overlaySwipeColor", { 0, 0, 0, 0.64 })
        Put(o, "auraSwipe", "overlaySwipeReverse", false)
        Put(o, "auraSwipe", "swipeEdge", false)
        Put(o, "auraSwipe", "swipeBling", false)
    end

    -- the aura on a cooldown icon: v1's aura look while it is up. Ignore Aura Override keeps the
    -- spell's cooldown on the icon instead (no aura phase here), so the looks that follow the aura
    -- have nothing to read. An icon whose aura the game has not answered for (offline) is planned
    -- as one that may have it. A Duration Override covers the spell's own aura phase; its totem or
    -- fixed time wears the Aura Active look, written with it.
    if phased and doPhase then
        if ctx.hasAura == true and not ctx.iao then Note(ctx, "a Duration Override over the spell's own aura phase") end
        if aa.glowWhenMissing == true then Note(ctx, "a glow while the aura is missing, beside a Duration Override") end
    elseif phased and ctx.iao and ctx.hasAura ~= false then
        if aa.desaturateWhenInactive == true then Note(ctx, "grey while the aura is down, on an icon that ignores its aura") end
        if aa.glow == true or aa.glowWhenMissing == true then Note(ctx, "an aura glow on an icon that ignores its aura") end
        if aa.activeAlphaEnabled == true then Note(ctx, "an aura opacity on an icon that ignores its aura") end
    elseif phased and ctx.hasAura ~= false and doAura then
        if ctx.hasAura == true then Note(ctx, "a Duration Override aura over the spell's own aura phase") end
    elseif phased and ctx.hasAura ~= false then
        Put(o, "auraActive", "overlayArt", "spell")
        Put(o, "auraActive", "overlayDesatInactive", aa.desaturateWhenInactive == true)
        Put(o, "auraActive", "activeAlpha", aa.activeAlphaEnabled == true and (tonumber(aa.activeAlpha) or 1) or 1)
        IA.MapGlow(o, { sec = "auraActive", prefix = "activeGlow", aura = true, combat = true },
            V1Glow(aa, aa.glow == true, { length = aa.glowLength }), ctx)
        if aa.glow == true and aa.glowFollowPandemic == true then
            Note(ctx, "an aura glow set to the pandemic window, which v1 never draws")
        end
        local asc = IA.V1SwipeColor(sw.auraSwipeColor, 0.7)
        if asc then Put(o, "auraSwipe", "overlaySwipeColor", asc) end
        Put(o, "auraSwipe", "overlaySwipeReverse", sw.reverse == true or sw.reverseWhileAura == true)
        if aa.glowWhenMissing == true then Note(ctx, "a spell icon's glow while its aura is missing") end
    elseif isSpell then
        -- no aura ever shows here: v1's missing-aura glow glows the whole time, and its grey
        -- while the aura is down greys it the whole time
        if aa.glowWhenMissing == true then
            local miss = V1Glow(aa, true, { length = aa.glowLength })
            IA.MapGlow(o, { sec = "states", prefix = "cooldownGlow", combat = true }, miss, ctx)
            if rs.glow ~= true then IA.MapGlow(o, { sec = "states", prefix = "readyGlow", combat = true }, miss, ctx) end
            if rs.glowWhileChargesAvailable ~= true then
                IA.MapGlow(o, { sec = "states", prefix = "rechargeGlow", combat = true }, miss, ctx)
            end
        end
        if aa.desaturateWhenInactive == true then
            if doAura then
                -- the Duration Override's cover is in colour, so the grey shows only while it is down
                Put(o, "auraActive", "overlayDesatInactive", true)
            else
                Put(o, "states", "readyDesaturate", true)
                Put(o, "states", "cooldownDesaturate", true)
                Put(o, "states", "rechargeDesaturate", true)
            end
        end
    end

    -- the swipe and its edge (v1's swipe colour when unset is the Cooldown Manager's 0.7 black)
    Put(o, "swipe", "showSwipe", sw.showSwipe ~= false)
    Put(o, "swipe", "showEdge", sw.showEdge ~= false)
    Put(o, "swipe", "showBling", sw.showBling ~= false)
    Put(o, "swipe", "reverse", sw.reverse == true)
    Put(o, "swipe", "swipeColor", IA.V1SwipeColor(sw.swipeColor, 0.8) or { 0, 0, 0, 0.7 })
    if type(sw.edgeColor) == "table" then Put(o, "swipe", "edgeColor", V1Named(sw.edgeColor, WHITE)) end
    if ctx.cdm ~= false then
        IA.MapEdgeScale(o, "swipe", sw.edgeScale, ctx)
    elseif tonumber(sw.edgeScale) then
        Put(o, "swipe", "edgeScale", Clamp(tonumber(sw.edgeScale), 0.1, 3))
    end
    if isSpell then
        -- v1 drew the GCD on a Cooldown Manager icon with the icon's own edge switch
        local gcd = (ctx.cdm == false or sw.showEdge ~= false) and "both" or "swipe"
        Put(o, "swipe", "gcdSwipe", sw.noGCDSwipe == true and "hidden" or gcd)
        Put(o, "swipe", "swipeWaitForNoCharges", sw.swipeWaitForNoCharges == true)
        Put(o, "swipe", "edgeWaitForNoCharges", sw.edgeWaitForNoCharges == true)
    end
    Put(o, "swipe", "separateInsets", sw.separateInsets == true)
    Put(o, "swipe", "swipeInset", Clamp(IA.Units(tonumber(sw.swipeInset) or 0, kS), -20, 40))
    Put(o, "swipe", "swipeInsetX", Clamp(IA.Units(tonumber(sw.swipeInsetX) or 0, kS), -20, 40))
    Put(o, "swipe", "swipeInsetY", Clamp(IA.Units(tonumber(sw.swipeInsetY) or 0, kS), -20, 40))

    -- texts: the charge count and the countdown, sized and placed in fixed units as v1 draws them
    local ch = type(eff.chargeText) == "table" and eff.chargeText or {}
    Put(o, "text", "stackText", ch.enabled ~= false)
    local bad = IA.MapText(o, "stack", ch, kS, { size = 16, anchor = "BOTTOMRIGHT", x = -2, y = 2 })
    if bad then Note(ctx, "a charge text anchored " .. tostring(bad)) end
    if isSpell then Put(o, "text", "hideChargeAtZero", ch.hideAtZero == true) end
    local ct = type(eff.cooldownText) == "table" and eff.cooldownText or {}
    Put(o, "text", "durationText", ct.enabled ~= false)
    bad = IA.MapText(o, "duration", ct, kS, { size = 14, anchor = "CENTER", x = 0, y = 0 })
    if bad then Note(ctx, "a countdown anchored " .. tostring(bad)) end
    if isSpell then Put(o, "text", "hideDurWithCharges", ct.hideWhenHasCharges == true) end
    local dec = (tonumber(ct.decimals) or 0) > 0
    Put(o, "text", "durationDecimals", dec)
    if dec then
        -- v1's 0 is "always"; a minute is Arc Auras' widest
        local dt = tonumber(ct.decimalThreshold) or 0
        if dt <= 0 then dt = 60 end
        Put(o, "text", "durationDecimalThreshold", Clamp(math.floor(dt + 0.5), 2, 60))
    end
    Put(o, "text", "durationAbbrev", IA.CONV.abbrev(tonumber(ct.abbrevThreshold) or 0))
    IA.MapShowBelow(o, ct)
    IA.MapDurationBands(o, ct, ctx)

    -- the keybind: shown when the spec's keybind setting is on and the icon does not hide it,
    -- styled by the icon's own override when it has one, else by the spec's
    if isSpell or kind == "item" or kind == "trinket" then
        local kb = ctx.keybinds or {}
        local own = type(eff.keybindText) == "table" and eff.keybindText or {}
        local use = own.enabled == true and own or {}
        Put(o, "keybind", "keybindEnabled", kb.enabled == true and eff.hideKeybind ~= true)
        Put(o, "keybind", "keybindSize", IA.FontSize(use.size or kb.fontSize or 12, kS))
        Put(o, "keybind", "keybindFont", IA.CONV.font(use.font or kb.font or "Friz Quadrata TT"))
        Put(o, "keybind", "keybindColor", V1Color(use.color or kb.color) or { 1, 1, 1, 1 })
        local an = use.anchor or kb.anchor or "TOPRIGHT"
        if IA.ICON_TEXT_ANCHORS[an] then Put(o, "keybind", "keybindAnchor", an)
        else Note(ctx, "a keybind anchored " .. tostring(an)) end
        Put(o, "keybind", "keybindX", IA.Units(use.offsetX or kb.offsetX or -1, kS))
        Put(o, "keybind", "keybindY", IA.Units(use.offsetY or kb.offsetY or -1, kS))
        -- v1 writes its own short form (S / C / A first, M4, WU, N1, PU...) after the spec's
        -- find-and-replace lists
        if kb.enabled == true and eff.hideKeybind ~= true then IA.MapKeybindLook(o, kb, use) end
    end

    -- custom labels: as many as v1's label count shows. v1 draws them at full opacity through
    -- every dim; Arc Auras' dims take them along unless the texts are kept bright.
    local os = type(eff.outOfStockState) == "table" and eff.outOfStockState or {}
    local dims = readyA < 1 or cdA < 1
        or (suOn and ((tonumber(su.notEnoughResourceAlpha) or 1) < 1 or (tonumber(su.notUsableAlpha) or 1) < 1))
        or (os.alphaEnabled == true and (tonumber(os.alpha) or 1) < 1)
    if IA.MapLabels(o, eff, kS, ctx, false) and dims then Put(o, "states", "labelsFullOpacity", true) end

    -- sounds: the cooldown kinds' triggers (a charge spell's two of its own)
    local al = type(eff.cooldownAlerts) == "table" and eff.cooldownAlerts or {}
    if kind == "spell" or kind == "item" or kind == "trinket" or kind == "timer" then
        V1Channel(o, al)
        V1Alert(o, al, "ready", "ready", ctx)
        V1Alert(o, al, "cooldown", "cooldown", ctx)
        if isSpell then
            V1Alert(o, al, "recharging", "recharge", ctx)
            V1Alert(o, al, "charge", "chargeGained", ctx)
        end
    end
    OldAlertEvents(eff, ctx)
    if isSpell then IA.MapAssist(o, ctx, false, kS) end

    -- out of stock (bag items: the one kind Arc Auras gives the look)
    if kind == "item" then
        Put(o, "outOfStock", "outDesaturate", os.desaturate ~= false)
        if cs.dimWhenEmpty == true then
            Put(o, "outOfStock", "outAlphaEnabled", true)
            Put(o, "outOfStock", "outAlpha", cdA)
        else
            Put(o, "outOfStock", "outAlphaEnabled", os.alphaEnabled == true)
            if os.alphaEnabled == true then Put(o, "outOfStock", "outAlpha", tonumber(os.alpha) or 1) end
        end
        Put(o, "outOfStock", "outTintEnabled", os.tint == true)
        if os.tint == true then Put(o, "outOfStock", "outTintColor", V1Named(os.tintColor or {}, { 0.5, 0.5, 0.5, 1 })) end
    end
    if phased and ctx.hasAura ~= false and not ctx.iao then
        IA.MapPandemicBorder(o, eff, ctx, kS, (aa.glow == true) and 1 or 0, 1)
        IA.MapAuraSwipeInset(o, sw, kS, pad)
    end
    return o
end

local function Tab(v) return type(v) == "table" and v or {} end

-- Arc UI's own cooldown icons (arc_spell / arc_item / arc_trinket / arc_totem) -> Arc Auras
-- overrides. v1 paints their states with two painters of its own (spells and totems; items and
-- trinkets) and styles the rest as it styles a Cooldown Manager icon. Reference: retail-port\12.
-- ctx as IA.MapCooldownIcon (cdm false), plus arcDef: the icon's kind definition.
function IA.MapArcCooldownIcon(eff, kind, ctx)
    ctx = ctx or {}
    ctx.notes = ctx.notes or {}
    local o = {}
    local kS = IA.IconScale(ctx)
    local isSpell, isTimer = kind == "spell", kind == "timer"
    -- a custom timer paints as a totem does: running = the ready look, idle = the cooldown look
    local isTotem = kind == "totem" or isTimer
    local isItem = kind == "item" or kind == "trinket"
    local sv = Tab(eff.cooldownStateVisuals)
    local rs, cs = Tab(sv.readyState), Tab(sv.cooldownState)
    local su, sw, pg, ri = Tab(eff.spellUsability), Tab(eff.cooldownSwipe), Tab(eff.procGlow), Tab(eff.rangeIndicator)
    local def = Tab(ctx.arcDef)
    -- no -padding under an Arc icon's glows: v1 offsets them from the frame
    ctx.pad = 0
    if eff._arcWide then Note(ctx, "Arc UI's Arc-wide settings over an icon's own") end

    -- appearance: the Cooldown Manager styler's; the kind's own art override sits under the
    -- per-icon custom icon (0: no art)
    MapAppearance(o, eff, ctx, kS, true)
    local ov = tonumber(def.iconOverride) or (isTimer and tonumber(def.icon)) or nil
    if (kind ~= "totem") and ov and eff.forceHideIcon ~= true and tonumber(eff.customIconID) == nil then
        if ov == 0 then
            Put(o, "appearance", "forceHideIcon", true)
        else
            Put(o, "appearance", "customIcon", ov)
            Put(o, "appearance", "customIconFrom", "icon")
        end
    end

    local readyA, cdA = tonumber(rs.alpha) or 1, tonumber(cs.alpha) or 1
    local wait = isSpell and cs.waitForNoCharges == true
    local suOn = su.enabled ~= false
    local function NamedR(c) return type(c) == "table" and c.r ~= nil and V1Named(c, WHITE) or nil end
    Put(o, "states", "readyAlpha", readyA)
    Put(o, "states", "cooldownAlpha", cdA)
    Put(o, "states", "preserveDurationText", (isItem and cs.preserveDurationText == true)
        or ((isSpell or isTotem) and (cs.preserveDurationText == true or rs.preserveDurationText == true)))
    if (isSpell or isTotem) and (cs.preserveDurationText == true) ~= (rs.preserveDurationText == true) then
        Put(o, "states", "preserveTextWhen", rs.preserveDurationText == true and "ready" or "cooldown")
        if wait then Note(ctx, "a rule for one state on a charge spell that waits for no charges") end
    end
    Put(o, "states", "readyTintEnabled", false)
    Put(o, "states", "cooldownTintEnabled", false)

    if isItem then
        -- items and trinkets: on cooldown grey unless No Desaturation; an item out of stock greys
        -- (and with "dim when empty" takes the cooldown opacity); keep bright blocks every grey of
        -- an item; tint on cooldown only with its switch and a colour. v1's No Desaturation also
        -- blocks the out-of-stock and can't-use greys (12 B6), a slip: its panel names the
        -- cooldown's grey only.
        local keep = eff.keepBright == true and eff.keepBrightAllowDesat ~= true
        local block = cs.noDesaturate == true or keep
        Put(o, "states", "cooldownDesaturate", not block)
        Put(o, "states", "readyDesaturate", false)
        if cs.tint == true and type(cs.tintColor) == "table" then
            Put(o, "states", "cooldownTintEnabled", true)
            Put(o, "states", "cooldownTintColor", V1Named(cs.tintColor, { 0.5, 0.5, 0.5, 1 }))
        end
        if kind == "item" then
            Put(o, "outOfStock", "outDesaturate", not keep)
            Put(o, "outOfStock", "outAlphaEnabled", cs.dimWhenEmpty == true)
            if cs.dimWhenEmpty == true then Put(o, "outOfStock", "outAlpha", cdA) end
            -- one you carry but can't use yet: grey, the cooldown opacity, no tint (v1's fixed rule)
            Put(o, "states", "itemUsability", true)
            Put(o, "states", "unusableDesaturate", not keep)
            Put(o, "states", "unusableTintEnabled", false)
            Put(o, "states", "unusableAlpha", cdA)
            Put(o, "states", "usabilityAlphaReplaces", true)
        end
    elseif isTotem then
        -- a totem's ready look is its totem out, its cooldown look the empty slot; each greys by its
        -- own switch; the empty slot tints by a stored colour (its switch unread), the totem out by
        -- its ready tint, else the ready Custom Tint
        Put(o, "states", "readyDesaturate", rs.desaturate == true)
        Put(o, "states", "cooldownDesaturate", cs.desaturate == true)
        local up = (rs.tint == true and NamedR(rs.tintColor)) or (su.useNormalColor == true and (NamedR(su.normalColor) or Copy(WHITE))) or nil
        if up then
            Put(o, "states", "readyTintEnabled", true)
            Put(o, "states", "readyTintColor", up)
        end
        local down = NamedR(cs.tintColor)
        if down then
            Put(o, "states", "cooldownTintEnabled", true)
            Put(o, "states", "cooldownTintColor", down)
        end
    else
        -- a spell: v1's spell painter (AAC _ASV). Cooldown look: grey unless No Desaturation, a
        -- stored cooldown colour (its switch unread), else the usability colour. Ready look: grey by
        -- its own switch or the ready Custom Tint's, else the usability grey; tint by its own colour,
        -- else the ready Custom Tint, else the usability colour. Recharging: the cooldown look in
        -- colour, or the ready look with "wait for no charges".
        local readyGrey = rs.desaturate == true or su.normalDesaturate == true
        Put(o, "states", "cooldownDesaturate", cs.noDesaturate ~= true)
        Put(o, "states", "readyDesaturate", readyGrey)
        local cdTint = NamedR(cs.tintColor)
        if cdTint then
            Put(o, "states", "cooldownTintEnabled", true)
            Put(o, "states", "cooldownTintColor", cdTint)
        end
        local up = (rs.tint == true and NamedR(rs.tintColor)) or (su.useNormalColor == true and (NamedR(su.normalColor) or Copy(WHITE))) or nil
        if up then
            Put(o, "states", "readyTintEnabled", true)
            Put(o, "states", "readyTintColor", up)
        end
        -- usability: v1's colours (the game's while its switch is off: white), alphas and greys
        Put(o, "states", "resourceTintEnabled", suOn)
        Put(o, "states", "unusableTintEnabled", suOn)
        if suOn then
            Put(o, "states", "resourceTintColor", NamedR(su.notEnoughResourceColor) or { 0.5, 0.5, 1, 1 })
            Put(o, "states", "unusableTintColor", NamedR(su.notUsableColor) or { 0.4, 0.4, 0.4, 1 })
        end
        Put(o, "states", "resourceAlpha", suOn and (tonumber(su.notEnoughResourceAlpha) or 1) or 1)
        Put(o, "states", "unusableAlpha", suOn and (tonumber(su.notUsableAlpha) or 1) or 1)
        Put(o, "states", "resourceDesaturate", suOn and su.notEnoughResourceDesaturate == true)
        Put(o, "states", "unusableDesaturate", suOn and su.notUsableDesaturate == true)
        Put(o, "states", "rangeTint", ri.enabled ~= false)
        Put(o, "states", "rangeTintColor", { 0.64, 0.15, 0.15, 1 })
        Put(o, "states", "rangeAlpha", 1)
        Put(o, "states", "rangeDesaturate", false)
        local procShown = pg.enabled ~= false
        local poR, poC = procShown and rs.procOverride == true, procShown and cs.procOverride == true
        Put(o, "states", "procOverride", poR or poC)
        if poR ~= poC then
            Put(o, "states", "procOverrideWhen", poR and "ready" or "cooldown")
            if wait then Note(ctx, "a rule for one state on a charge spell that waits for no charges") end
        end
        Put(o, "states", "ignoreHardICD", sw.ignoreHardICD == true)
        Put(o, "states", "rechargeAlpha", wait and readyA or cdA)
        Put(o, "states", "rechargeDesaturate", wait and readyGrey or false)
        local rTint = wait and up or (not wait and cdTint) or nil
        Put(o, "states", "rechargeTintEnabled", rTint and true or false)
        if rTint then Put(o, "states", "rechargeTintColor", rTint) end
        -- v1's spell painter: the usability colour on a cooling spell unless a stored cooldown
        -- colour covers it; a charge coming back keeps it but none of the usability dims or greys;
        -- a usability opacity it sets replaces the ready one. Its ready colour over the usability
        -- ones (only its own spells do that) is a slip: the usability colours show over it.
        Put(o, "states", "usabilityOnCooldown", not cdTint)
        Put(o, "states", "usabilityReadyOnly", not wait)
        local replace = suOn and (su.notEnoughResourceAlpha ~= nil or su.notUsableAlpha ~= nil)
        Put(o, "states", "usabilityAlphaReplaces", replace and true or false)
        if replace then
            Put(o, "states", "resourceAlpha", tonumber(su.notEnoughResourceAlpha) or readyA)
            Put(o, "states", "unusableAlpha", tonumber(su.notUsableAlpha) or readyA)
        end
    end

    -- glows: v1 offsets an Arc icon's glows from the frame, keeps their strata, and leaves an
    -- unset colour to the glow's own (items: gold)
    local itemGold = { 1, 0.85, 0, 1 }
    local ready = V1Glow(rs, rs.glow == true, { intensitySquared = isItem,
        fallback = isItem and itemGold or IA.V1_PROC_GOLD, native = not isItem })
    -- an item's ready glow stops while it can't be used or is out of stock: the usable glow
    local readyLane = kind == "item" and "usableGlow" or "readyGlow"
    if readyLane ~= "readyGlow" then Put(o, "states", "readyGlow", false) end
    IA.MapGlow(o, { sec = "states", prefix = readyLane, combat = true }, ready, ctx)
    if isSpell then
        local rg = Copy(ready)
        rg.on = rs.glow == true and rs.glowWhileChargesAvailable == true
        IA.MapGlow(o, { sec = "states", prefix = "rechargeGlow", combat = true }, rg, ctx)
        local pType = pg.glowType or "default"
        IA.MapGlow(o, { sec = "states", prefix = "procGlow" }, {
            on = pg.enabled ~= false, type = pType, native = true, fallback = IA.V1_PROC_GOLD,
            color = pg.color ~= nil and V1Mixed(pg.color, IA.V1_PROC_GOLD) or nil,
            scale = pg.scale, speed = pg.speed, lines = pg.lines, thickness = pg.thickness, particles = pg.particles,
            x = pg.xOffset, y = pg.yOffset, strata = pg.strata, level = pg.frameLevel or 1,
        }, ctx)
        -- the usable glow: v1's "Default (Golden)" draws nothing on an Arc spell
        local uType = su.usableGlowType or "button"
        if uType == "blizzard" or uType == "glow" then uType = "proc" end
        local uCol = su.usableGlowColor ~= nil and V1Mixed(su.usableGlowColor, IA.V1_GLOW_GOLD) or nil
        IA.MapGlow(o, { sec = "states", prefix = "usableGlow", combat = true }, {
            on = su.usableGlow == true and uType ~= "default", type = uType, color = uCol,
            native = true, fallback = IA.V1_PROC_GOLD,
            intensity = uCol and uCol[4] or 1, scale = su.usableGlowScale, speed = su.usableGlowSpeed,
            lines = su.usableGlowLines, thickness = su.usableGlowThickness, particles = su.usableGlowParticles,
            x = su.usableGlowXOffset, y = su.usableGlowYOffset, strata = su.usableGlowFrameStrata,
            level = su.usableGlowFrameLevel, combat = su.usableGlowCombatOnly,
        }, ctx)
    end
    local tg = Tab(eff.thresholdGlow)
    if isItem and tg.enabled == true then Note(ctx, "Arc UI's item threshold glow") end

    -- Duration Override (spells, items, trinkets), as on a Cooldown Manager icon; an item's or
    -- a trinket's use spell stands in for the spell (v1 runs none on timers and totems)
    local dov = Tab(eff.durationOverride)
    if dov.enabled == true and (isSpell or isItem) then
        if dov.mode == "aura" and tonumber(dov.auraSpellID) then
            ctx.overlayAura = { on = true, spellID = tonumber(dov.auraSpellID), auraType = "buff", unit = "player" }
            Put(o, "auraActive", "overlayArt", "spell")
            Put(o, "auraActive", "overlayDesatInactive", false)
            Put(o, "auraActive", "activeAlpha", 1)
            Put(o, "auraActive", "activeGlow", false)
            Put(o, "auraSwipe", "overlaySwipeColor", { 0, 0, 0, 0.64 })
            Put(o, "auraSwipe", "overlaySwipeReverse", false)
            Put(o, "auraSwipe", "swipeEdge", false)
            Put(o, "auraSwipe", "swipeBling", false)
        else
            local ph = IA.MapPhaseOverride(o, eff, dov, ctx)
            if ph then ctx.overlayAura = ph end
        end
    end

    -- the swipe and its edge (the same textures as a Cooldown Manager icon)
    Put(o, "swipe", "showSwipe", sw.showSwipe ~= false)
    Put(o, "swipe", "showEdge", sw.showEdge ~= false)
    Put(o, "swipe", "showBling", sw.showBling ~= false)
    Put(o, "swipe", "reverse", sw.reverse == true)
    Put(o, "swipe", "swipeColor", IA.V1SwipeColor(sw.swipeColor, 0.8) or { 0, 0, 0, 0.7 })
    if type(sw.edgeColor) == "table" then Put(o, "swipe", "edgeColor", V1Named(sw.edgeColor, WHITE)) end
    IA.MapEdgeScale(o, "swipe", sw.edgeScale, ctx)
    if isSpell then
        Put(o, "swipe", "gcdSwipe", sw.noGCDSwipe == true and "hidden" or "both")
        Put(o, "swipe", "swipeWaitForNoCharges", sw.swipeWaitForNoCharges == true)
        Put(o, "swipe", "edgeWaitForNoCharges", sw.edgeWaitForNoCharges == true)
    end
    Put(o, "swipe", "separateInsets", sw.separateInsets == true)
    Put(o, "swipe", "swipeInset", Clamp(IA.Units(tonumber(sw.swipeInset) or 0, kS), -20, 40))
    Put(o, "swipe", "swipeInsetX", Clamp(IA.Units(tonumber(sw.swipeInsetX) or 0, kS), -20, 40))
    Put(o, "swipe", "swipeInsetY", Clamp(IA.Units(tonumber(sw.swipeInsetY) or 0, kS), -20, 40))

    -- texts: the count (spells blank it at 0 with Hide at 0; an item shows its "0") and the countdown
    local ch = Tab(eff.chargeText)
    if kind ~= "totem" then
        -- a timer that tracks stacks shows its "0" unless Hide at 0 blanks it
        if isTimer then
            Put(o, "text", "stackShowZero", Tab(def.startTrigger).trackStacks == true and ch.hideAtZero ~= true)
        end
        Put(o, "text", "stackText", ch.enabled ~= false)
        local bad = IA.MapText(o, "stack", ch, kS, { size = 16, anchor = "BOTTOMRIGHT", x = -2, y = 2 })
        if bad then Note(ctx, "a charge text anchored " .. tostring(bad)) end
        if isSpell then Put(o, "text", "hideChargeAtZero", ch.hideAtZero == true) end
    end
    local ct = Tab(eff.cooldownText)
    Put(o, "text", "durationText", ct.enabled ~= false)
    local bad = IA.MapText(o, "duration", ct, kS, { size = 14, anchor = "CENTER", x = 0, y = 0 })
    if bad then Note(ctx, "a countdown anchored " .. tostring(bad)) end
    if isSpell then Put(o, "text", "hideDurWithCharges", false) end
    local dec = (tonumber(ct.decimals) or 0) > 0
    Put(o, "text", "durationDecimals", dec)
    if dec then
        local dt = tonumber(ct.decimalThreshold) or 0
        if dt <= 0 then dt = 60 end
        Put(o, "text", "durationDecimalThreshold", Clamp(math.floor(dt + 0.5), 2, 60))
    end
    Put(o, "text", "durationAbbrev", IA.CONV.abbrev(tonumber(ct.abbrevThreshold) or 0))
    IA.MapShowBelow(o, ct)
    IA.MapDurationBands(o, ct, ctx)

    -- the keybind, on every kind Arc Auras gives one
    local kb = ctx.keybinds or {}
    if isSpell or isTimer or isItem or kind == "totem" then
        local own = Tab(eff.keybindText)
        local use = own.enabled == true and own or {}
        Put(o, "keybind", "keybindEnabled", kb.enabled == true and eff.hideKeybind ~= true)
        Put(o, "keybind", "keybindSize", IA.FontSize(use.size or kb.fontSize or 12, kS))
        Put(o, "keybind", "keybindFont", IA.CONV.font(use.font or kb.font or "Friz Quadrata TT"))
        Put(o, "keybind", "keybindColor", V1Color(use.color or kb.color) or { 1, 1, 1, 1 })
        local an = use.anchor or kb.anchor or "TOPRIGHT"
        if IA.ICON_TEXT_ANCHORS[an] then Put(o, "keybind", "keybindAnchor", an)
        else Note(ctx, "a keybind anchored " .. tostring(an)) end
        Put(o, "keybind", "keybindX", IA.Units(use.offsetX or kb.offsetX or -1, kS))
        Put(o, "keybind", "keybindY", IA.Units(use.offsetY or kb.offsetY or -1, kS))
        if kb.enabled == true and eff.hideKeybind ~= true then IA.MapKeybindLook(o, kb, use) end
    end

    -- custom labels: v1 shows a label by the icon's two states (a recharging spell counts as
    -- ready there); it keeps them at full opacity through every dim
    local any = IA.MapLabels(o, eff, kS, ctx, false)
    local cl = Tab(eff.customLabel)
    if any and isSpell then
        for _, suf in ipairs({ "", "2", "3" }) do
            if (cl["showInReadyState" .. suf] ~= false) ~= (cl["showInCooldownState" .. suf] ~= false) then
                Note(ctx, "a label's recharge look (Arc UI shows its ready one)")
                break
            end
        end
    end
    if any and (readyA < 1 or cdA < 1 or (isSpell and suOn and ((tonumber(su.notEnoughResourceAlpha) or 1) < 1
        or (tonumber(su.notUsableAlpha) or 1) < 1))) then
        Put(o, "states", "labelsFullOpacity", true)
    end

    -- sounds: ready and on cooldown (spells, items, trinkets), a charge spell's two of its own
    local al = Tab(eff.cooldownAlerts)
    if not isTotem then
        V1Channel(o, al)
        V1Alert(o, al, "ready", "ready", ctx)
        V1Alert(o, al, "cooldown", "cooldown", ctx)
        if isSpell then
            V1Alert(o, al, "recharging", "recharge", ctx)
            V1Alert(o, al, "charge", "chargeGained", ctx)
        end
    end
    if isSpell then IA.MapAssist(o, ctx, true, kS) end
    return o
end

-- v1's aura glow packs (on the arc aura icons) -> Arc Auras aura glow styles
IA.V1_PACK = { pixel = "pixel", autocast = "autocast", proc = "proc", ach_proc = "proc", button = "button",
    cdm_flash = "button", ants = "ants" }

-- Arc UI's own aura icons (arc_aura_*) -> Arc Auras aura overrides. v1 paints them itself: the live
-- look on the game's aura button, the missing look on the holder's own art (the "ghost"), with no
-- state switch (active = Ready's opacity and grey, missing = On Cooldown's). Reference:
-- retail-port\13 section 2. ctx as IA.MapAuraIcon, plus arcDef (the aura definition).
function IA.MapArcAuraIcon(eff, ctx)
    ctx = ctx or {}
    ctx.notes = ctx.notes or {}
    local o = {}
    local kS = IA.IconScale(ctx)
    local sv = Tab(eff.cooldownStateVisuals)
    local rs, cs = Tab(sv.readyState), Tab(sv.cooldownState)
    local aa, sw = Tab(eff.auraActiveState), Tab(eff.cooldownSwipe)
    local def = Tab(ctx.arcDef)
    ctx.pad = 0
    if eff._arcWide then Note(ctx, "Arc UI's Arc-wide settings over an icon's own") end

    -- the two looks; keep bright and No Desaturation keep the ghost in colour
    local upA, missA = Clamp(tonumber(rs.alpha) or 1, 0, 1), Clamp(tonumber(cs.alpha) or 1, 0, 1)
    local block = cs.noDesaturate == true or (eff.keepBright == true and eff.keepBrightAllowDesat ~= true)
    Put(o, "auraActive", "activeAlpha", upA)
    Put(o, "auraActive", "activeDesaturate", rs.desaturate == true)
    Put(o, "auraActive", "activeTintEnabled", false)
    Put(o, "auraActive", "activePreserveText", rs.preserveDurationText == true)
    -- the ghost always shows (at no opacity it keeps its slot unseen)
    Put(o, "auraMissing", "showWhileMissing", true)
    Put(o, "auraMissing", "missingAlpha", missA)
    Put(o, "auraMissing", "missingDesaturate", cs.desaturate == true and not block)
    Put(o, "auraMissing", "missingPreserveText", true)

    -- appearance: the styler's, with v1's crop and inset on the ghost only; the definition's art on
    -- both looks, a per-icon custom icon on the ghost only
    MapAppearance(o, eff, ctx, kS, false)
    if (tonumber(eff.aspectRatio) or 1) ~= 1 or (tonumber(eff.padding) or 0) ~= 0 then
        Note(ctx, "an aspect ratio or padding Arc UI draws on the missing look only")
    end
    local cid = tonumber(eff.customIconID)
    if o.appearance then o.appearance.customIcon, o.appearance.customIconFrom = nil, nil end
    local ov = tonumber(def.iconOverride)
    if ov and ov > 0 then
        Put(o, "appearance", "customIcon", ov)
        Put(o, "appearance", "customIconFrom", "icon")
    end
    if cid and cid > 0 and eff.forceHideIcon ~= true then
        Put(o, "auraMissing", "missingIcon", cid)
        Put(o, "auraMissing", "missingIconFrom", ctx.iconFrom or "icon")
    elseif cid == 0 and eff.forceHideIcon ~= true then
        if o.appearance then o.appearance.forceHideIcon = nil end
        Note(ctx, "a missing look with no art (Arc UI hides the ghost's art only)")
    end
    Put(o, "appearance", "dispelBorder", false)

    -- glows: Ready's glow on the live button (v1's glow packs: Pixel when no style is set, its
    -- offsets moving the whole glow, its level absolute), the pandemic swap's second style in the
    -- pandemic window, Glow When Missing under the button
    local slots = {}
    if rs.glow == true then
        local g = V1Glow(rs, true, { type = IA.V1_PACK[rs.glowType or "pixel"] or "pixel",
            length = rs.glowLength, thickness = rs.glowThickness or 3, x = 0, y = 0,
            tx = rs.glowXOffset, ty = rs.glowYOffset, particles = 4, combat = false, native = false, noBacking = true })
        g.level = nil
        slots[#slots + 1] = { g = g, timed = rs.glowFollowPandemic == true, pack = true }
        if rs.pandemicSwap == true and rs.glowFollowPandemic ~= true then
            local w = Copy(g)
            w.type = IA.V1_PACK[rs.pandemicSwapType or rs.glowType or "pixel"] or g.type
            w.color = V1Mixed(rs.pandemicSwapColor or {}, { 1, 0.2, 0.2, 1 })
            slots[#slots + 1] = { g = w, timed = true, pack = true }
            Note(ctx, "a glow that swaps its style in the pandemic window")
        end
        if tonumber(rs.glowFrameLevel) then Note(ctx, "an aura glow level Arc UI sets absolute") end
    end
    if aa.glowWhenMissing == true then
        local g = V1Glow(aa, true, { length = aa.glowLength })
        g.strata, g.level, g.tx, g.ty = nil, nil, nil, nil
        slots[#slots + 1] = { g = g, when = "missing", pad = 1 }
        if missA <= 0 then Note(ctx, "a missing glow that shows at no opacity (Arc UI)") end
    end
    Put(o, "auraActive", "activeGlow", false)
    for k, s in ipairs(slots) do
        local suf = (k > 1) and tostring(k) or ""
        ctx.pad = s.pad or 0
        -- Arc UI's glow packs draw their own colour whatever the account-wide native switch says
        local native = ctx.nativeGlow
        if s.pack then ctx.nativeGlow = nil end
        IA.MapGlow(o, { sec = "auraActive", prefix = "activeGlow", suf = suf, aura = true, combat = true }, s.g, ctx)
        ctx.nativeGlow = native
        if s.timed then
            Put(o, "auraActive", "activeGlowWhen" .. suf, "time")
            Put(o, "auraActive", "activeGlowTimeUnit" .. suf, "pct")
            Put(o, "auraActive", "activeGlowTimePct" .. suf, 30)
            Note(ctx, "the game's pandemic window as the last 30 percent")
        else
            Put(o, "auraActive", "activeGlowWhen" .. suf, s.when or "always")
        end
    end
    ctx.pad = 0
    IA.MapPandemicBorder(o, eff, ctx, kS, #slots, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 4)

    -- the swipe: forward with its edge, no finish flash; an unset edge is the game's at 1
    Put(o, "auraSwipe", "swipeShow", sw.showSwipe ~= false)
    Put(o, "auraSwipe", "swipeColor", IA.V1SwipeColor(sw.swipeColor, 0.8) or { 0, 0, 0, 0.7 })
    Put(o, "auraSwipe", "swipeReverse", sw.reverse == true)
    Put(o, "auraSwipe", "swipeEdge", sw.showEdge == true)
    if type(sw.edgeColor) == "table" then Put(o, "auraSwipe", "edgeColor", V1Named(sw.edgeColor, WHITE)) end
    IA.MapEdgeScale(o, "auraSwipe", sw.edgeScale, ctx)
    Put(o, "auraSwipe", "swipeBling", false)
    IA.MapAuraSwipeInset(o, sw, kS, 0)

    -- texts: the count with its 12.1 rules; the countdown with the cooldown icons' colour rule
    local ch = Tab(eff.chargeText)
    Put(o, "text", "stackText", ch.enabled ~= false)
    local bad = IA.MapText(o, "stack", ch, kS, { size = 16, anchor = "BOTTOMRIGHT", x = -2, y = 2 })
    if bad then Note(ctx, "a stack text anchored " .. tostring(bad)) end
    IA.MapStackBands(o, ch, ctx)
    local ct = Tab(eff.cooldownText)
    Put(o, "text", "durationText", ct.enabled ~= false)
    bad = IA.MapText(o, "duration", ct, kS, { size = 14, anchor = "CENTER", x = 0, y = 0 })
    if bad then Note(ctx, "a countdown anchored " .. tostring(bad)) end
    local dec = (tonumber(ct.decimals) or 0) > 0
    Put(o, "text", "durationDecimals", dec)
    if dec then
        local dt = tonumber(ct.decimalThreshold) or 0
        if dt <= 0 then dt = 60 end
        Put(o, "text", "durationDecimalThreshold", Clamp(math.floor(dt + 0.5), 2, 60))
    end
    Put(o, "text", "durationAbbrev", IA.CONV.abbrev(tonumber(ct.abbrevThreshold) or 0))
    -- a coloured countdown is v1's bound text, which has no Show below
    if ct.durationColor ~= true then IA.MapShowBelow(o, ct) end
    IA.MapDurationBands(o, ct, ctx)

    -- labels: only on the live look, dimming with it
    local cl = Tab(eff.customLabel)
    local any = IA.MapLabels(o, eff, kS, ctx, true, true)
    for _, suf in ipairs({ "", "2", "3" }) do
        if o.label and o.label["labelText" .. suf] and o.label["labelText" .. suf] ~= "" then
            if cl["showWhenActive" .. suf] == false then
                o.label["labelText" .. suf] = ""
            else
                o.label["labelActiveOnly" .. suf] = true
                o.label["labelMissingOnly" .. suf] = false
            end
        end
    end
    if any and rs.preserveDurationText == true and upA < 1 then Note(ctx, "labels that dim with the icon (Arc UI)") end

    -- sounds: the game plays them on the units of the icon's old unit setting
    local al = Tab(eff.auraAlerts)
    local fires = IA.V1AuraSoundsFire(def)
    V1Channel(o, al)
    if fires then
        V1Alert(o, al, "gained", "auraGain", ctx)
        V1Alert(o, al, "stacks", "auraStack", ctx)
        V1Alert(o, al, "removed", "auraLost", ctx)
    else
        for _, b in ipairs({ "gained", "stacks", "removed" }) do
            if type(al[b .. "Sound"]) == "string" and al[b .. "Sound"] ~= "" and al[b .. "SoundOn"] ~= false then
                Note(ctx, "aura sounds Arc UI never played (they follow an old unit setting)")
                break
            end
        end
    end
    return o
end

-- v1's aura lanes for a definition (AuraIcons.LanesFor): the old unitMode when no units are
-- set, else every unit (party = party1-4) on the helpful and / or harmful side of auraType.
IA.V1_LEGACY_LANES = {
    buff = { { "player", false } }, debuff = { { "target", true } }, focusdebuff = { { "focus", true } },
    selfdebuff = { { "player", true } }, pet = { { "pet", false } },
    both = { { "player", false }, { "target", true } },
}
function IA.V1AuraLanes(def)
    def = Tab(def)
    local out = {}
    local units = def.units
    if type(units) ~= "table" or next(units) == nil then
        for _, l in ipairs(IA.V1_LEGACY_LANES[def.unitMode] or IA.V1_LEGACY_LANES.buff) do out[#out + 1] = { unit = l[1], harmful = l[2] } end
        return out
    end
    local t = def.auraType or "buff"
    local tokens = { player = { "player" }, target = { "target" }, focus = { "focus" }, pet = { "pet" },
        party = { "party1", "party2", "party3", "party4" } }
    for _, choice in ipairs({ "player", "target", "focus", "pet", "party" }) do
        if units[choice] then
            for _, tok in ipairs(tokens[choice]) do
                if t ~= "debuff" then out[#out + 1] = { unit = tok, harmful = false } end
                if t ~= "buff" then out[#out + 1] = { unit = tok, harmful = true } end
            end
        end
    end
    if #out == 0 then out[1] = { unit = "player", harmful = false } end
    return out
end

-- v1 registers an aura icon's sounds on its old unitMode's lanes only: they play when one of
-- those is one of the icon's own lanes.
function IA.V1AuraSoundsFire(def)
    def = Tab(def)
    local real = {}
    for _, l in ipairs(IA.V1AuraLanes(def)) do real[l.unit .. (l.harmful and ":h" or ":b")] = true end
    for _, l in ipairs(IA.V1_LEGACY_LANES[def.unitMode] or IA.V1_LEGACY_LANES.buff) do
        if real[l[1] .. (l[2] and ":h" or ":b")] then return true end
    end
    return false
end

-- v1 timer events -> Arc Auras rule triggers (death is the dead condition's edge; a timer's own
-- end is the "this timer ended" trigger)
IA.V1_TIMER_WHEN = { cast = "cast", cooldown = "spell_update", proc = "proc_on", procEnd = "proc_off" }

-- One v1 custom timer (arc_timer_*) -> an Arc Auras timer driver: its spell, length, stack cap,
-- clear-on-end switch and rules (the Custom engine, Drivers\AD_DriverCustom.lua), written
-- by the recipes of retail-port\13 section 4.6. notes: what the engine cannot do as v1 did.
function IA.MapArcTimerDriver(def, notes)
    def = Tab(def)
    local W = IA.V1_TIMER_WHEN
    local function N(what) notes[#notes + 1] = what end
    local st, et = Tab(def.startTrigger), Tab(def.endTrigger)
    local sid = tonumber(def.spellID)
    local dur = tonumber(def.duration) or 0
    local maxSecs = (NS.Schema and NS.Schema.CUSTOM_MAX_SECONDS) or 7200
    if dur > maxSecs then N("a timer longer than two hours") end
    -- the length lives on the item, so no rule carries seconds of its own
    local d = { spellID = sid, duration = dur > 0 and math.min(dur, maxSecs) or nil, showWhile = "timer" }
    -- an event set, else the old single event
    local function Events(t, allowed)
        local out = {}
        for _, k in ipairs(allowed) do
            if type(t.events) == "table" and t.events[k] then out[#out + 1] = k end
        end
        if #out == 0 then
            for _, k in ipairs(allowed) do
                if t.event == k then out[1] = k end
            end
        end
        return out
    end
    local function Ids(primary, extras)
        local out, seen = {}, {}
        local function One(v)
            local n = tonumber(v)
            if n and n > 0 and not seen[n] then seen[n] = true out[#out + 1] = n end
        end
        One(primary)
        for _, v in ipairs(type(extras) == "table" and extras or {}) do One(v) end
        return out
    end
    local function Amount(v)
        v = tonumber(v)
        if not v or v <= 0 then return 1 end
        return math.max(1, math.min(999, math.floor(v)))
    end
    local starts = Events(st, { "cast", "cooldown", "proc" })
    if #starts == 0 then starts[1] = def.triggerType == "cooldown" and "cooldown" or "cast" end
    local ends = Events(et, { "cast", "proc", "procEnd", "death" })
    if def.resetOnDeath == true then
        local has = false
        for _, e in ipairs(ends) do if e == "death" then has = true end end
        if not has then ends[#ends + 1] = "death" end
    end
    local startIds = Ids(tonumber(st.spellID) or sid, st.extraSpellIDs)
    local endIds = Ids(tonumber(et.spellID) or sid, et.extraSpellIDs)
    local restart = st.restartOnRefire
    if type(restart) ~= "boolean" then restart = def.resetOnRecast == true end
    local track = st.trackStacks == true
    local mode = st.stackMode
    if mode ~= "independent" and mode ~= "consume" then mode = "refresh" end
    local rules = {}
    local function Add(r)
        rules[#rules + 1] = r
        return #rules
    end
    -- a rule hears its spells: the first, and the whole list when there are more
    local function Hears(r, ids)
        r.spellID = ids[1]
        if #ids > 1 then
            local l = {}
            for i, v in ipairs(ids) do l[i] = v end
            r.spellIDs = l
        end
        return r
    end
    -- the spells one kind of rule hears, in order (item.k = the kind); a full rule opens
    -- another. An event names one spell, so per event the same rules fire as one per spell.
    local maxIds = (NS.Schema and NS.Schema.CUSTOM_RULE_MAX_SPELLS) or 13
    local function Group(items)
        local out, open = {}, {}
        for _, it in ipairs(items) do
            local g = open[it.k]
            if not g or #g.ids >= maxIds then
                g = { ids = {}, first = it }
                open[it.k] = g
                out[#out + 1] = g
            end
            g.ids[#g.ids + 1] = it.s
            it.g = g
        end
        return out
    end
    -- an end stops only a running timer and is heard first: v1's end wins a tie
    local endsOn = {}
    for _, e in ipairs(ends) do
        if e == "death" then
            Add({ when = "cond_on", cond = "dead", timer = "running", act = "reset" })
        else
            local items = {}
            for _, s in ipairs(endIds) do
                endsOn[e .. ":" .. s] = true
                items[#items + 1] = { k = e, s = s }
            end
            for _, g in ipairs(Group(items)) do
                Add(Hears({ when = W[e], timer = "running", act = "reset" }, g.ids))
            end
        end
    end
    -- the starts, less any the end also names (v1 never starts on those)
    local fires = {}
    for _, e in ipairs(starts) do
        for _, s in ipairs(startIds) do
            local key = e .. ":" .. s
            if not endsOn[key] then fires[#fires + 1] = { e = e, s = s, key = key } end
        end
    end
    for _, p in ipairs(fires) do p.k = p.e end
    if not track then
        for _, g in ipairs(Group(fires)) do
            Add(Hears({ when = W[g.first.e], act = "start", mode = not restart and "idle" or nil }, g.ids))
        end
    elseif mode ~= "consume" then
        -- independent stacks each run out on their own, and the timer restarts with every new one
        -- so it ends with the last (v1 without Restart on Refire cleared the later stacks at the
        -- first one's end, a slip; its own preset restarts)
        local independent = mode == "independent"
        if independent then d.stackTimers = true end
        d.clearOnEnd = true
        for _, g in ipairs(Group(fires)) do
            local w = W[g.first.e]
            if restart or independent then
                Add(Hears({ when = w, act = "add", n = 1, restartToo = true }, g.ids))
            else
                Add(Hears({ when = w, timer = "idle", act = "start" }, g.ids))
                Add(Hears({ when = w, act = "add", n = 1 }, g.ids))
            end
        end
    else
        local noMax = st.noMaxStacks == true
        local maxS = tonumber(st.maxStacks) or 5
        if maxS <= 0 then maxS = 5 end
        if not noMax then d.maxStacks = math.min(math.floor(maxS), 999) end
        local initial = tonumber(st.initialStacks) or 0
        if initial < 0 then initial = 0 end
        if not noMax and initial > maxS then initial = maxS end
        initial = math.min(math.floor(initial), 999)
        -- per event and spell, the first spender, else the first generator (v1 spends first);
        -- Timer Complete takes the first entry naming it the same way
        local econ, order, expire = {}, {}, nil
        for _, side in ipairs({ { st.spenders, "remove" }, { st.generators, "add" } }) do
            for _, en in ipairs(type(side[1]) == "table" and side[1] or {}) do
                local ev = type(en) == "table" and type(en.events) == "table" and en.events or nil
                local es = ev and tonumber(en.spellID)
                if ev and ev.expire and not expire then expire = { act = side[2], n = Amount(en.amount) } end
                for _, k in ipairs({ "cast", "cooldown", "proc" }) do
                    local key = es and es > 0 and ev[k] and (k .. ":" .. es)
                    if key and not econ[key] then
                        econ[key] = { e = k, s = es, act = side[2], n = Amount(en.amount) }
                        order[#order + 1] = key
                    end
                end
            end
        end
        local recharge = st.rechargeUntilFull == true
        local keepPool = expire ~= nil or recharge
        local stop = st.onEmptyAction == "stop"
        if st.onEmptyAction == "hide" then N("a timer hidden at 0 stacks") end
        -- v1 seeds the pool on every start; the seed is written only where the pool can differ
        local function Start(g, idle)
            local w = W[g.first.e]
            if initial > 0 or keepPool or not idle then
                Add(Hears({ when = w, timer = idle and "idle" or nil, act = "set", n = initial > 0 and initial or nil },
                    g.ids))
            end
            Add(Hears({ when = w, act = "start", mode = idle and "idle" or nil }, g.ids))
        end
        -- a start the economy also hears starts only when idle (the economy has it while running);
        -- with Start full a start that spends starts first, then spends
        local early, later = {}, {}
        for _, p in ipairs(fires) do
            local x = econ[p.key]
            if st.startFull == true and x and x.act == "remove" then
                early[#early + 1] = p
            else
                p.idle = x ~= nil or not restart
                p.k = p.e .. (p.idle and ":idle" or ":run")
                later[#later + 1] = p
            end
        end
        for _, g in ipairs(Group(early)) do Start(g, true) end
        -- the economy: one rule per event, action and amount
        local spend = {}
        for _, key in ipairs(order) do
            local x = econ[key]
            spend[#spend + 1] = { k = x.e .. ":" .. x.act .. ":" .. x.n, s = x.s, x = x }
        end
        local spendRules = Group(spend)
        for _, g in ipairs(spendRules) do
            local x = g.first.x
            g.at = Add(Hears({ when = W[x.e], timer = "running", stacksMin = (stop and x.act == "remove") and 1 or nil,
                act = x.act, n = x.n }, g.ids))
        end
        -- the timer's own end: a gain below the cap runs it again when recharging
        if expire then
            local cap = d.maxStacks
            if expire.act == "add" and recharge and cap then
                Add({ when = "ended", stacksMin = math.max(0, cap - expire.n), act = "add", n = expire.n })
                if cap - expire.n - 1 >= 0 then
                    Add({ when = "ended", stacksMax = cap - expire.n - 1, act = "add", n = expire.n, restartToo = true })
                end
            else
                Add({ when = "ended", act = expire.act, n = expire.n })
            end
        end
        for _, g in ipairs(Group(later)) do Start(g, g.first.idle) end
        -- a spend that empties the pool stops the timer: its spender fired on this event
        if stop then
            for _, g in ipairs(spendRules) do
                local x = g.first.x
                if x.act == "remove" then
                    Add(Hears({ when = W[x.e], timer = "running", stacksMax = 0, withinRule = g.at, withinSecs = 0.1,
                        act = "stop" }, g.ids))
                end
            end
        end
        d.clearOnEnd = not keepPool or nil
        -- Start full: the pool reads full while the timer is idle at no stacks
        if st.startFull == true and initial > 0 then d.idleCount = initial end
    end
    local cap = NS.Schema and NS.Schema.CUSTOM_MAX_RULES or 8
    if #rules > cap then
        N("more than 8 timer rules")
        for i = #rules, cap + 1, -1 do rules[i] = nil end
    end
    d.rules = rules
    return d
end

local function SameRGB(a, b)
    return math.abs(a[1] - b[1]) < 1e-3 and math.abs(a[2] - b[2]) < 1e-3 and math.abs(a[3] - b[3]) < 1e-3
end

-- v1's stack colours on an aura icon (12.1): the bands switched on from 1 stack up, each
-- colouring the counts from its threshold to the next one's, under the lowest the text's own
-- colour. The count shows from 2 stacks, or from 1 with Show at 1 Stack.
function IA.MapStackBands(o, ch, ctx)
    local shown = ch.enabled ~= false
    local single = shown and ch.showSingleStack == true
    Put(o, "text", "stackShowSingle", single)
    local from = single and 1 or 2
    local bands = {}
    if shown and ch.thresholdColorEnabled and type(ch.thresholdBands) == "table" then
        for i = 1, 6 do
            local b = ch.thresholdBands[i]
            local t = type(b) == "table" and b.enabled and tonumber(b.threshold)
            if t and t >= 1 and type(b.color) == "table" then
                local c = V1Named(b.color, WHITE)
                c[4] = 1
                bands[#bands + 1] = { t = math.ceil(t), c = c }
            end
        end
    end
    table.sort(bands, function(a, b) return a.t < b.t end)
    -- the first count shown takes the last band at or under it, a count the last band reaching
    -- it, and a band in the colour of the one before changes nothing
    local kept = {}
    for _, b in ipairs(bands) do
        local last = kept[#kept]
        if last and (last.t == b.t or (last.t <= from and b.t <= from)) then
            kept[#kept] = b
        elseif not (last and SameRGB(last.c, b.c)) then
            kept[#kept + 1] = b
        end
    end
    Put(o, "text", "stackColorBands", #kept > 0)
    if #kept == 0 then return end
    if #kept > 6 then Note(ctx, "more than six stack colours") end
    Put(o, "text", "stkBandCount", math.min(6, #kept))
    for i = 1, math.min(6, #kept) do
        local b = kept[i]
        if b.t > 999 then Note(ctx, "a stack colour from more than 999 stacks") end
        Put(o, "text", "stkBand" .. i .. "Min", Clamp(b.t, 1, 999))
        Put(o, "text", "stkBand" .. i .. "Color", b.c)
    end
end

-- A Cooldown Manager aura icon (a buff or debuff the game tracks) -> Arc Auras overrides.
-- eff: v1's effective settings (the aura layer). ctx: H, W (v1 icon size), keepCDMStyle,
-- nativeGlow, iconFrom (as on a cooldown icon), cdmHidesMissing (the Tracked Buffs viewer's
-- Hide When Inactive, nil when unknown), notes. Reference: retail-port\11.
function IA.MapAuraIcon(eff, ctx)
    ctx = ctx or {}
    ctx.notes = ctx.notes or {}
    local o = {}
    local kS = IA.IconScale(ctx)
    local sv = type(eff.cooldownStateVisuals) == "table" and eff.cooldownStateVisuals or {}
    local rs = type(sv.readyState) == "table" and sv.readyState or {}
    local cs = type(sv.cooldownState) == "table" and sv.cooldownState or {}
    local aa = type(eff.auraActiveState) == "table" and eff.auraActiveState or {}
    local sw = type(eff.cooldownSwipe) == "table" and eff.cooldownSwipe or {}
    ctx.pad = tonumber(eff.padding) or 0

    -- the two states. v1 paints them only once one is set up (a state key off its default);
    -- until then both keep the icon's base opacity, in full colour. Its hidden Ignore Aura
    -- Override leaves every state look to the game.
    local stateOn = (rs.alpha ~= nil and rs.alpha ~= 1) or rs.glow == true or rs.desaturate == true
        or rs.tint == true or (cs.alpha ~= nil and cs.alpha ~= 1) or cs.desaturate == true or cs.tint == true
        or cs.noDesaturate == true or cs.preserveDurationText == true or cs.waitForNoCharges == true
    local iao = (aa.ignoreAuraOverride or sw.ignoreAuraOverride) and true or false
    local base = tonumber(eff.alpha) or 1
    local upA, missA, upGrey, missGrey, missTint = base, base, false, false, nil
    if iao then
        if stateOn then upA, missA = 1, 1 end
        Note(ctx, "an aura icon set to ignore its aura")
    elseif stateOn then
        upA, missA = tonumber(rs.alpha) or 1, tonumber(cs.alpha) or 1
        upGrey, missGrey = rs.desaturate == true, cs.desaturate == true
        if cs.tint == true and type(cs.tintColor) == "table" then missTint = V1Named(cs.tintColor, { 0.5, 0.5, 0.5, 1 }) end
    end
    upA, missA = Clamp(upA, 0, 1), Clamp(missA, 0, 1)
    -- a missing aura keeps its slot at the missing opacity; at none a Dynamic Auras group closes
    -- the gap. The game's own Hide When Inactive hides it unless v1 paints the states.
    local shown = missA > 0.01
    if ctx.cdmHidesMissing == true then
        if stateOn and not iao then Note(ctx, "a missing aura the Cooldown Manager hides and Arc UI shows")
        else shown = false end
    end
    Put(o, "auraMissing", "showWhileMissing", shown)
    Put(o, "auraMissing", "missingAlpha", missA)
    Put(o, "auraMissing", "missingDesaturate", missGrey)
    -- only labels show while the aura is missing, and v1 keeps them at full opacity
    Put(o, "auraMissing", "missingPreserveText", true)
    Put(o, "auraMissing", "missingTintEnabled", missTint and true or false)
    if missTint then Put(o, "auraMissing", "missingTintColor", missTint) end
    Put(o, "auraActive", "activeAlpha", upA)
    Put(o, "auraActive", "activeDesaturate", upGrey)
    Put(o, "auraActive", "activeTintEnabled", false)
    -- the countdown and the count stay bright under the active dim only with Preserve Duration Text
    local keepUp = stateOn and not iao and rs.preserveDurationText == true
    Put(o, "auraActive", "activePreserveText", keepUp)

    MapAppearance(o, eff, ctx, kS, upGrey or missGrey)
    local db = type(eff.debuffBorder) == "table" and eff.debuffBorder or {}
    Put(o, "appearance", "dispelBorder", db.enabled == true)
    -- v1 shows the Cooldown Manager's own dispel-type border art
    if db.enabled == true then Put(o, "appearance", "dispelBorderStyle", "game") end

    -- glows, each on a glow of its own: the ready glow while the aura is up (with CDM Pandemic
    -- Timing only in the game's pandemic window, the last 30 percent here), the hidden aura glow
    -- while it is up, and Glow When Missing. A glow on a state drawn at no opacity never shows.
    local slots = {}
    if not iao then
        if rs.glow == true and upA > 0 then
            local g = V1Glow(rs, true, { intensitySquared = true })
            slots[#slots + 1] = { g = g, timed = rs.glowFollowPandemic == true, when = "always" }
        end
        if aa.glow == true and upA > 0 then
            local g = V1Glow(aa, true, { length = aa.glowLength, level = aa.glowFrameLevel or 1 })
            slots[#slots + 1] = { g = g, timed = aa.glowFollowPandemic == true, when = "always" }
        end
        if aa.glowWhenMissing == true and aa.glowFollowPandemic ~= true and shown then
            local g = V1Glow(aa, true, { length = aa.glowLength })
            g.strata, g.level = nil, nil
            slots[#slots + 1] = { g = g, when = "missing" }
        end
    end
    Put(o, "auraActive", "activeGlow", false)
    for k, s in ipairs(slots) do
        local suf = (k > 1) and tostring(k) or ""
        IA.MapGlow(o, { sec = "auraActive", prefix = "activeGlow", suf = suf, aura = true, combat = true }, s.g, ctx)
        if s.timed then
            Put(o, "auraActive", "activeGlowWhen" .. suf, "time")
            Put(o, "auraActive", "activeGlowTimeUnit" .. suf, "pct")
            Put(o, "auraActive", "activeGlowTimePct" .. suf, 30)
            Note(ctx, "the game's pandemic window as the last 30 percent")
        else
            Put(o, "auraActive", "activeGlowWhen" .. suf, s.when)
        end
    end

    IA.MapPandemicBorder(o, eff, ctx, kS, #slots, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 4)

    -- the swipe: v1 turns the game's reversed aura swipe forward and draws its edge and finish
    -- flash, in the Cooldown Manager's 0.7 black unless a colour is set
    Put(o, "auraSwipe", "swipeShow", sw.showSwipe ~= false)
    Put(o, "auraSwipe", "swipeColor", IA.V1SwipeColor(sw.swipeColor, 0.8) or { 0, 0, 0, 0.7 })
    Put(o, "auraSwipe", "swipeReverse", sw.reverse == true)
    Put(o, "auraSwipe", "swipeEdge", sw.showEdge ~= false)
    if type(sw.edgeColor) == "table" then Put(o, "auraSwipe", "edgeColor", V1Named(sw.edgeColor, WHITE)) end
    IA.MapEdgeScale(o, "auraSwipe", sw.edgeScale, ctx)
    Put(o, "auraSwipe", "swipeBling", sw.showBling ~= false)
    IA.MapAuraSwipeInset(o, sw, kS, tonumber(eff.padding) or 0)

    -- texts: the count (with its colours and Show at 1 Stack) and the countdown
    local ch = type(eff.chargeText) == "table" and eff.chargeText or {}
    Put(o, "text", "stackText", ch.enabled ~= false)
    local bad = IA.MapText(o, "stack", ch, kS, { size = 16, anchor = "BOTTOMRIGHT", x = -2, y = 2 })
    if bad then Note(ctx, "a stack text anchored " .. tostring(bad)) end
    IA.MapStackBands(o, ch, ctx)
    local ct = type(eff.cooldownText) == "table" and eff.cooldownText or {}
    Put(o, "text", "durationText", ct.enabled ~= false)
    bad = IA.MapText(o, "duration", ct, kS, { size = 14, anchor = "CENTER", x = 0, y = 0 })
    if bad then Note(ctx, "a countdown anchored " .. tostring(bad)) end
    local dec = (tonumber(ct.decimals) or 0) > 0
    Put(o, "text", "durationDecimals", dec)
    if dec then
        local dt = tonumber(ct.decimalThreshold) or 0
        if dt <= 0 then dt = 60 end
        Put(o, "text", "durationDecimalThreshold", Clamp(math.floor(dt + 0.5), 2, 60))
    end
    Put(o, "text", "durationAbbrev", IA.CONV.abbrev(tonumber(ct.abbrevThreshold) or 0))
    IA.MapShowBelow(o, ct)
    IA.MapDurationBands(o, ct, ctx, true)

    -- custom labels: v1 keeps them at full opacity through the active dim unless the texts are
    -- kept bright
    local any, up = IA.MapLabels(o, eff, kS, ctx, true)
    if any and up and upA > 0 and upA < 1 and not keepUp then Put(o, "auraActive", "activeLabelsBright", true) end

    -- sounds when the aura appears and drops
    local al = type(eff.auraAlerts) == "table" and eff.auraAlerts or {}
    V1Channel(o, al)
    V1Alert(o, al, "gained", "auraGain", ctx)
    V1Alert(o, al, "removed", "auraLost", ctx)
    OldAlertEvents(eff, ctx)
    return o
end

-- v1's edge length on a Cooldown Manager icon: its scale of the game's edge, which Arc Auras
-- draws at 1.8 of its own (unset: Arc Auras' default, the same edge).
function IA.MapEdgeScale(o, sec, s, ctx)
    s = tonumber(s)
    if not s then return end
    local v = 1.8 * s
    if v > 6 then Note(ctx, "a swipe edge longer than Arc Auras draws") end
    Put(o, sec, "edgeScale", Clamp(v, 0.1, 6))
end

-- v1's custom labels: as many as its label count shows, each with its text, size, colour,
-- anchor and offsets in fixed units, and (cooldown icons) its ready / cooldown switches, or
-- (aura icons) its active / missing pair. Returns whether one shows, and whether one shows
-- while the aura is up.
function IA.MapLabels(o, eff, kS, ctx, aura, noLayer)
    local cl = type(eff.customLabel) == "table" and eff.customLabel or {}
    local count = math.max(1, math.min(3, math.floor(tonumber(cl.labelCount) or 1)))
    local any, upAny = false, false
    for i = 1, 3 do
        local suf = (i == 1) and "" or tostring(i)
        local text = cl["text" .. suf]
        if i <= count and type(text) == "string" and text ~= "" then
            any = true
            Put(o, "label", "labelText" .. suf, text)
            Put(o, "label", "labelSize" .. suf, IA.FontSize(cl["size" .. suf] or 12, kS))
            Put(o, "label", "labelColor" .. suf, V1Color(cl["color" .. suf]) or { 1, 1, 1, 1 })
            local an = cl["anchor" .. suf] or "CENTER"
            if IA.ICON_TEXT_ANCHORS[an] then Put(o, "label", "labelAnchor" .. suf, an)
            else Note(ctx, "a label anchored " .. tostring(an)) end
            Put(o, "label", "labelX" .. suf, IA.Units(cl["xOffset" .. suf] or 0, kS))
            Put(o, "label", "labelY" .. suf, IA.Units(cl["yOffset" .. suf] or 0, kS))
            if aura then
                local up, down = cl["showWhenActive" .. suf], cl["showWhenInactive" .. suf]
                Put(o, "label", "labelActiveOnly" .. suf, up ~= false and down == false)
                Put(o, "label", "labelMissingOnly" .. suf, down ~= false and up == false)
                if up == false and down == false then Put(o, "label", "labelText" .. suf, "") end
                if up ~= false then upAny = true end
            else
                Put(o, "label", "labelShowReady" .. suf, cl["showInReadyState" .. suf] ~= false)
                Put(o, "label", "labelShowCooldown" .. suf, cl["showInCooldownState" .. suf] ~= false)
                if cl["showWhileRecharging" .. suf] == false then Note(ctx, "a label hidden while recharging") end
                if cl["showWhenAuraActive" .. suf] == false or cl["showWhenAuraInactive" .. suf] == false then
                    Note(ctx, "a label tied to the spell's aura")
                end
            end
        end
    end
    if any then
        local f = IA.CONV.font(cl.font or "Friz Quadrata TT")
        Put(o, "label", "labelFont", f)
        Put(o, "label", "labelFont2", f)
        Put(o, "label", "labelFont3", f)
        Put(o, "label", "labelOutline", IA.CONV.outline(cl.outline or "OUTLINE"))
        if not noLayer and (cl.frameStrata ~= nil or cl.frameLevel ~= nil) then Note(ctx, "a label's own strata or level") end
    end
    return any, upAny
end
