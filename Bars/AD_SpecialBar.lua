-- AD_SpecialBar: the Special Aura deck bar (barKind "special"), a tracker's deck as a fill with a mark where each proc landed and two deck texts (retail only).
-- Plugs into the bars runtime through Bars.RegisterKind and Bars.Kit; attaches to NS.Special and borrows NS.SpecialIcon's templates, art and proc state at call time.
-- Everything it draws is a plain number our own tracker hands over; nothing here reads the game.
local ADDON, NS = ...
if NS.IsForever == true then return end
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R

local SB = {}
NS.SpecialBars = SB

SB.TEXTS = { "pos", "proc" }
-- ProcTracker's bar draws at most this many proc marks
SB.MAX_MARKS = 16
-- The editor sample: a deck drawn in 12 spends, one every half second, with a
-- rest at its end; the still sample's marks.
SB.LOOP_SPENDS, SB.LOOP_STEP, SB.LOOP_REST = 12, 0.5, 0.5
SB.SAMPLE_MARKS = { 0.2, 0.4 }
SB.LOOP_CUTS = { 1 / 3, 2 / 3 }

function SB.TrackerID(rec)
    local d = rec and rec.driver
    return d and (d.tracker or d.special) or nil
end

function SB.Def(rec)
    local SP, id = NS.Special, SB.TrackerID(rec)
    return (SP and id) and SP.Get(id) or nil
end

-- A deck holds a set number of procs; a counter (Deeply Rooted Elements on
-- Restoration, Soulburst) climbs to a cap and has no proc to mark.
function SB.IsDeck(def)
    return def ~= nil and def.procs ~= nil
end

-- The deck's length and where it stands: a deck's size and position, a
-- counter's cap and count, held inside the bar.
function SB.Range(read)
    local size = tonumber(read and read.size) or 1
    if size <= 0 then size = 1 end
    local pos = tonumber(read and read.pos) or 0
    if pos < 0 then pos = 0 elseif pos > size then pos = size end
    return size, pos
end

-- "empty" (no proc used), "half" or "full" (every proc used), as on the icon
function SB.State(read)
    local SI = NS.SpecialIcon
    if SI and SI.ProcState and read then return SI.ProcState(read) end
    return "empty"
end

-- One text's settings into t, one reused table per text so a paint makes no
-- garbage. Every field is named in full.
function SB.ReadText(rec, which, t)
    if which == "pos" then
        t.show, t.template = R(rec, "deck", "posShow"), R(rec, "deck", "posTemplate")
        t.font, t.size = R(rec, "deck", "posFont"), R(rec, "deck", "posSize")
        t.outline, t.shadow = R(rec, "deck", "posOutline"), R(rec, "deck", "posShadow")
        t.anchor = R(rec, "deck", "posAnchor")
        t.x, t.y = R(rec, "deck", "posOffsetX"), R(rec, "deck", "posOffsetY")
        t.mode, t.color = R(rec, "deck", "posColorMode"), R(rec, "deck", "posColor")
        t.empty, t.half = R(rec, "deck", "posEmptyColor"), R(rec, "deck", "posHalfColor")
        t.full = R(rec, "deck", "posFullColor")
    else
        t.show, t.template = R(rec, "deck", "procShow"), R(rec, "deck", "procTemplate")
        t.font, t.size = R(rec, "deck", "procFont"), R(rec, "deck", "procSize")
        t.outline, t.shadow = R(rec, "deck", "procOutline"), R(rec, "deck", "procShadow")
        t.anchor = R(rec, "deck", "procAnchor")
        t.x, t.y = R(rec, "deck", "procOffsetX"), R(rec, "deck", "procOffsetY")
        t.mode, t.color = R(rec, "deck", "procColorMode"), R(rec, "deck", "procColor")
        t.empty, t.half = R(rec, "deck", "procEmptyColor"), R(rec, "deck", "procHalfColor")
        t.full = R(rec, "deck", "procFullColor")
    end
    return t
end

function SB.Cfg(e, which)
    e.deckCfg = e.deckCfg or {}
    local t = e.deckCfg[which]
    if not t then
        t = {}
        e.deckCfg[which] = t
    end
    return t
end

-- The tracker's own text: its stack template for the deck position, its
-- first label for the proc count (the counters hand their own words there).
function SB.DefaultTemplate(def, which)
    if not def then return "" end
    if which == "pos" then return def.stack or "" end
    return (def.labels and def.labels[1]) or ""
end

function SB.Template(rec, which, t)
    local tpl = t and t.template
    if type(tpl) == "string" and tpl ~= "" then return tpl end
    return SB.DefaultTemplate(SB.Def(rec), which)
end

-- What an empty template field says it shows.
function SB.TemplateHint(rec, which)
    local tpl = SB.DefaultTemplate(SB.Def(rec), which)
    if tpl == "" then return "the tracker's own" end
    return "the tracker's own: " .. tpl
end

function SB.Expand(rec, which, t, read)
    local SI = NS.SpecialIcon
    if not (SI and SI.Expand and read) then return "" end
    return SI.Expand(SB.Template(rec, which, t), read, rec, SB.Def(rec))
end

function SB.FillColor(rec, read)
    if R(rec, "deck", "stateFill") == false then return K.BarColorOf(rec) end
    local state = SB.State(read)
    local c
    if state == "empty" and R(rec, "deck", "texEmptyEnabled") == true then
        c = R(rec, "deck", "texEmptyColor")
    elseif state == "full" then
        c = R(rec, "deck", "fullColor")
    elseif state == "half" then
        c = R(rec, "deck", "halfColor")
    else
        c = R(rec, "deck", "emptyColor")
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

function SB.TextColor(t, read)
    local c = t.color
    if t.mode == "state" then
        local s = SB.State(read)
        c = (s == "full" and t.full) or (s == "half" and t.half) or t.empty
    end
    c = c or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

-- Two strings on the overlay, above the fill and its marks. Each gets a face at
-- once: a string with no font refuses text.
function SB.Build(e)
    if e.deckFS then return end
    e.deckFS = {}
    for _, which in ipairs(SB.TEXTS) do
        local fs = e.shell.overlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        fs:SetWordWrap(false)
        fs:Hide()
        e.deckFS[which] = fs
    end
end

-- A deck text's face, size, outline and shadow; a bad font file falls back to
-- the default face through the bars' probe.
function SB.StyleDeckText(fs, t)
    local size = t.size or 14
    local outline = t.outline or "OUTLINE"
    local flags = (outline ~= "NONE") and outline or ""
    local path = Bars.ResolveFont(t.font)
    if K.ProvenFontPath then path = K.ProvenFontPath(path, size, flags) end
    fs:SetFont(path, size, flags)
    if t.shadow == true then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- The one place a deck text is anchored: every SetPoint of the two texts goes
-- through here.
function SB.PlaceDeckText(e, which, fs)
    fs = fs or (e.deckFS and e.deckFS[which])
    if not fs then return end
    local t = SB.ReadText(e.rec, which, SB.Cfg(e, which))
    local anchor, host = t.anchor or "CENTER", e.shell.overlay
    -- a text may ride another frame (Core\AD_TextAnchor.lua); the editor's
    -- preview keeps it on the bar
    local TA = (not e.isPreview) and NS.TextAnchor or nil
    if not TA then
        K.PlaceText(fs, host, anchor, t.x, t.y)
        return
    end
    local to, target
    if which == "pos" then
        to, target = R(e.rec, "deck", "posPinTo"), R(e.rec, "deck", "posPinTarget")
    else
        to, target = R(e.rec, "deck", "procPinTo"), R(e.rec, "deck", "procPinTarget")
    end
    local o = Bars.OUTER_POINTS and Bars.OUTER_POINTS[anchor]
    TA.Place(fs, e.shell, "deck:" .. which, to, target, o and o[1] or anchor, o and o[2] or anchor,
        t.x or 0, t.y or 0, function() K.PlaceText(fs, host, anchor, t.x, t.y) end)
end

function SB.StyleTexts(e)
    if not e.deckFS then return end
    for _, which in ipairs(SB.TEXTS) do
        local fs = e.deckFS[which]
        SB.StyleDeckText(fs, SB.ReadText(e.rec, which, SB.Cfg(e, which)))
        SB.PlaceDeckText(e, which, fs)
    end
end

-- One read onto the bar: the fill, its colour and both texts.
function SB.Paint(e, read)
    if not read then return end
    local rec, fill = e.rec, e.shell.fill
    local size, pos = SB.Range(read)
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    fill:SetMinMaxValues(0, size)
    fill:SetValue(drain and (size - pos) or pos)
    fill:SetStatusBarColor(SB.FillColor(rec, read))
    for _, which in ipairs(SB.TEXTS) do
        local fs = e.deckFS and e.deckFS[which]
        if fs then
            local t = SB.ReadText(rec, which, SB.Cfg(e, which))
            local text = (t.show == true) and SB.Expand(rec, which, t, read) or ""
            if text ~= "" then
                fs:SetText(text)
                fs:SetTextColor(SB.TextColor(t, read))
                fs:Show()
            else
                fs:SetText("")
                fs:Hide()
            end
        end
    end
end

-- No tracker to read (a record from a newer version): an empty bar.
function SB.Empty(e)
    local fill = e.shell.fill
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    for _, which in ipairs(SB.TEXTS) do
        local fs = e.deckFS and e.deckFS[which]
        if fs then
            fs:SetText("")
            fs:Hide()
        end
    end
end

-- The marks are the hub's (NS.Special.marks): ProcTracker's memory of where each
-- proc of the deck landed, kept for the session whether a bar shows or not.
function SB.Marks(rec)
    local SP, id = NS.Special, SB.TrackerID(rec)
    return (SP and SP.marks and id) and SP.marks[id] or nil
end

-- The hub's push: every Read() of the tracker while this bar is attached.
function SB.OnUpdate(rec, read)
    local e = K.live[rec.id]
    if not (e and e.kind == "special") then return end
    e.read = read
    local m = SB.IsDeck(SB.Def(rec)) and SB.Marks(rec) or nil
    SB.Paint(e, read)
    local ver = m and m.ver or -1
    if e.tickVer ~= ver then
        e.tickVer = ver
        K.LayoutTicks(e)
    end
end

-- The hub's proc edge: the marks follow the count, so it only stamps the time
-- for the diag line.
function SB.OnProc(rec)
    local e = K.live[rec.id]
    if e then e.lastProcAt = GetTime() end
end

SB.SINK = { Update = SB.OnUpdate, Proc = SB.OnProc }

-- The marks for the host's LayoutTicks: where each proc landed, as fractions
-- from the fill's start (a draining bar starts from the full end); the first
-- 16, the ends included, as ProcTracker draws them.
function SB.TickFractions(e)
    local rec = e.rec
    if R(rec, "ticks", "ticksShow") ~= true or R(rec, "deck", "procTicks") == false then return nil end
    local list
    if e.isPreview then
        list = e.pvFracs
    elseif SB.IsDeck(SB.Def(rec)) then
        local m = SB.Marks(rec)
        list = m and m.fracs
    end
    if not (list and #list > 0) then return nil end
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    local out = {}
    for i = 1, math.min(#list, SB.MAX_MARKS) do
        local f = list[i]
        out[#out + 1] = drain and (1 - f) or f
    end
    return out
end

-- Kind registry hooks

-- The attach pushes a read at once, so the bar paints before the host's
-- last LayoutTicks. Without a tracker the bar stays empty and shown.
function SB.Ensure(e)
    if e.isPreview then return end
    e.stateHidden = false
    local SP = NS.Special
    e.attached = (SP ~= nil and SP.Attach(e.rec, SB.SINK)) and true or false
    if not e.attached then
        e.read = nil
        SB.Empty(e)
    end
    K.ApplyVisibility(e)
end

function SB.Refresh(e)
    if e.isPreview then return end
    if e.read then SB.Paint(e, e.read) else SB.Empty(e) end
    K.ApplyVisibility(e)
end

-- Out of `live` already; the marks stay with the tracker for the session.
function SB.Release(e)
    local SP = NS.Special
    if SP then SP.Detach(e.rec.id) end
    e.attached, e.read, e.tickVer = false, nil, nil
end

-- ApplyStyle resets the side icon and the fill colour: put back the tracker's
-- art (an override keeps its own), the texts' looks and places, and the last read.
function SB.Styled(e)
    local rec = e.rec
    if e.iconF and e.iconF.tex and (tonumber(R(rec, "icon", "iconOverride")) or 0) <= 0 then
        local SI = NS.SpecialIcon
        e.iconF.tex:SetTexture((SI and SI.Texture and SI.Texture(rec)) or 134400)
    end
    SB.StyleTexts(e)
    local read = e.read
    if e.isPreview then read = e.pvRead end
    if read then SB.Paint(e, read) end
end

function SB.Diag(e)
    local r = e.read
    local m = SB.Marks(e.rec)
    return ("%s [special %s] attached=%s pos=%s/%s procs=%s/%s deck=%s marks=%d lastProc=%s"):format(
        tostring(e.rec.name), tostring(SB.TrackerID(e.rec)), tostring(e.attached == true),
        tostring(r and r.pos), tostring(r and r.size), tostring(r and r.procs), tostring(r and r.max),
        tostring(r and r.deck), m and #m.fracs or 0,
        e.lastProcAt and ("%.1f s ago"):format(GetTime() - e.lastProcAt) or "none")
end

-- Editor preview: a sample deck, standing half drawn or drawn spend by spend.

function SB.PreviewModes()
    return {
        { key = "static", text = "Preview", tip = "The deck half drawn, with a mark where each proc landed." },
        { key = "loop", text = "Deck loop",
          tip = "A spend every half second, a proc at a third and two thirds of the deck, then a new deck." },
    }
end

function SB.PreviewBuild(e)
    SB.Build(e)
end

-- The sample's shape: the tracker's size and procs, a counter's cap.
function SB.SampleShape(def)
    local size = tonumber(def and (def.size or def.cap)) or 100
    if size <= 0 then size = 100 end
    return size, SB.IsDeck(def) and (tonumber(def.procs) or 1) or nil
end

-- A sample read after n of the 12 spends, and its marks.
function SB.SampleRead(def, n, loop)
    local size, max = SB.SampleShape(def)
    local fracs = {}
    if not max then
        local count = math.floor(size * n / SB.LOOP_SPENDS)
        local pct = (def and def.ChanceAt) and (def.ChanceAt(count + 1) * 100) or math.min(100, (count + 1) * 100 / size)
        return { pos = count, size = size, left = size - count, drawn = count, procs = 0, max = 1, procsLeft = 1,
            count = count, chance = pct, viol = 0, deck = 1,
            text = { pos = ("%.0f%%"):format(pct), procs = tostring(count) } }, fracs
    end
    local pos = math.floor(size * n / SB.LOOP_SPENDS + 0.5)
    local procs = 0
    if loop then
        for _, cut in ipairs(SB.LOOP_CUTS) do
            if n / SB.LOOP_SPENDS >= cut - 0.0001 and procs < max then
                procs = procs + 1
                fracs[#fracs + 1] = cut
            end
        end
    else
        procs = math.max(1, math.min(2, max - 1))
        for i = 1, procs do fracs[i] = SB.SAMPLE_MARKS[i] end
    end
    local SP = NS.Special
    local chance = SP and SP.DeckChance and SP.DeckChance(size, max, pos, procs, 10) or nil
    return { pos = pos, size = size, left = size - pos, drawn = pos, procs = procs, max = max,
        procsLeft = max - procs, chance = chance, viol = 0, deck = 1 }, fracs
end

function SB.PreviewApply(e, loop, t, fresh)
    local n, key
    if loop then
        local cycle = SB.LOOP_SPENDS * SB.LOOP_STEP + SB.LOOP_REST
        n = math.min(SB.LOOP_SPENDS, math.floor(((t or 0) % cycle) / SB.LOOP_STEP))
        key = "L" .. n
    else
        n, key = SB.LOOP_SPENDS / 2, "S"
    end
    if not fresh and key == e.pvKey then return end
    e.pvKey = key
    local read, fracs = SB.SampleRead(SB.Def(e.rec), n, loop)
    e.pvRead, e.pvFracs = read, fracs
    SB.Paint(e, read)
    local marks = table.concat(fracs, ",")
    if fresh or marks ~= e.pvMarks then
        e.pvMarks = marks
        K.LayoutTicks(e)
    end
end

Bars.RegisterKind("special", {
    Build = SB.Build,
    Ensure = SB.Ensure,
    Refresh = SB.Refresh,
    Release = SB.Release,
    Styled = SB.Styled,
    TickFractions = SB.TickFractions,
    Diag = SB.Diag,
    PreviewModes = SB.PreviewModes,
    PreviewBuild = SB.PreviewBuild,
    PreviewApply = SB.PreviewApply,
})
