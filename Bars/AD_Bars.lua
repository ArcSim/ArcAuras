-- Bar runtime: the shell shared by cooldown, aura, timer, swing, resource and
-- health bars. Bars.EnsureBar(rec, holder) runs on every rebuild with the
-- holder sized and placed; this file owns what is inside it and its alpha (a
-- pips bar also sizes it). Near the 200-local limit: new helpers go on Bars.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local AT = NS.AT

local Bars = {}
NS.Bars = Bars

-- Kind registry: a bar kind in its own file (Bars\AD_Castbar.lua) registers a
-- handler and uses the helpers in Bars.Kit. The seam calls it at fixed points,
-- after the built-in kinds. Optional fields: Build(e) (widgets, once per entry,
-- live and preview), Ensure(e) (after ApplyStyle), Refresh(e), Relayout(e)
-- (size change), Release(e) (after leaving `live`), TickUnit(e) -> max,
-- integerUnit, ownsName (writes the Name text itself), Styled(e) (end of
-- ApplyStyle), Diag(e) -> one /adbars diag line, PreviewModes(rec),
-- PreviewBuild(e), PreviewApply(e, loop, t, fresh).
Bars.KINDS = {}
function Bars.RegisterKind(kind, handler) Bars.KINDS[kind] = handler end

-- A bar pinned to a nameplate (Core\AD_Anchor.lua) can have a secret rect, and
-- math on its size or edges throws. Layout passes that read the rect check this
-- first and keep the last layout; a rebuild lays the bar out free before the
-- anchor pass pins it, so only event-driven re-layouts are skipped.
function Bars.RectHidden(r)
    if not (r and r.GetWidth and issecretvalue) then return false end
    return issecretvalue(r:GetWidth()) and true or false
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE_KEYS = { "top", "bottom", "left", "right" }
local GCD_SPELL = 61304

-- Status-bar timer API (12.0+). Enum tables are guarded (indexing a missing one
-- errors); without the API bars fall back to SetValue. Forever has no `None`
-- member, so the gate takes any interpolation member plus both directions.
local INTERP_SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
-- The no-interpolation member: `None` on some clients, `Immediate` on Forever.
local INTERP_NONE = Enum.StatusBarInterpolation
    and (Enum.StatusBarInterpolation.None or Enum.StatusBarInterpolation.Immediate)
local INTERP_ANY = INTERP_NONE or INTERP_SMOOTH
local DIR_REMAIN = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local DIR_ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local HAS_TIMER_API = (INTERP_ANY ~= nil) and (DIR_ELAPSED ~= nil) and (DIR_REMAIN ~= nil)

-- A capability probe: Forever's build number is lower than retail's.
local HAS_SWING = (C_SwingTimer ~= nil)

-- Bar textures by key: built-ins plus LibSharedMedia's (probed, not bundled).
local BUILTIN_TEXTURES = {
    ["Flat"] = WHITE,
    ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Blizzard Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    ["Character Skills"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}
Bars.BUILTIN_TEXTURES = BUILTIN_TEXTURES

local function GetLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end
Bars.GetLSM = GetLSM

-- Bar borders: "" is Flat (1px strips), a key an edge file drawn as a backdrop.
-- The built-ins carry LSM's own names, so with LSM loaded each is listed once.
local BUILTIN_BORDERS = {
    ["Blizzard Tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    ["Blizzard Dialog"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
    ["Blizzard Dialog Gold"] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    ["Blizzard Party"] = "Interface\\CharacterFrame\\UI-Party-Border",
    ["Blizzard Achievement Wood"] = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder",
    ["Blizzard Chat Bubble"] = "Interface\\Tooltips\\ChatBubble-Backdrop",
}
local BUILTIN_BORDER_ORDER = { "Blizzard Tooltip", "Blizzard Dialog", "Blizzard Dialog Gold",
    "Blizzard Party", "Blizzard Achievement Wood", "Blizzard Chat Bubble" }
Bars.BUILTIN_BORDERS = BUILTIN_BORDERS
Bars.BUILTIN_BORDER_ORDER = BUILTIN_BORDER_ORDER

-- nil = Flat strips
local function ResolveBorder(key)
    if not key or key == "" then return nil end
    if BUILTIN_BORDERS[key] then return BUILTIN_BORDERS[key] end
    local lsm = GetLSM()
    if lsm then
        local path = lsm:Fetch("border", key, true)
        if path and path ~= "" then return path end
    end
    return nil
end

local function ResolveBarTexture(key)
    if not key or key == "" then return WHITE end
    if BUILTIN_TEXTURES[key] then return BUILTIN_TEXTURES[key] end
    local lsm = GetLSM()
    if lsm then
        local path = lsm:Fetch("statusbar", key, true)
        if path then return path end
    end
    return WHITE
end

-- Bar fonts: one per bar (text.font, "" = the default face).
local BUILTIN_FONTS = {
    ["Default"] = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\skurri.ttf",
    ["Morpheus"] = "Fonts\\MORPHEUS.ttf",
}
local BUILTIN_FONT_ORDER = { "Default", "Arial Narrow", "Skurri", "Morpheus" }
Bars.BUILTIN_FONTS = BUILTIN_FONTS
Bars.BUILTIN_FONT_ORDER = BUILTIN_FONT_ORDER

local function ResolveFont(key)
    if not key or key == "" then return BUILTIN_FONTS["Default"] end
    if BUILTIN_FONTS[key] then return BUILTIN_FONTS[key] end
    local lsm = GetLSM()
    if lsm then
        local path = lsm:Fetch("font", key, true)
        if path then return path end
    end
    return BUILTIN_FONTS["Default"]
end
-- Also used by the icon texts.
Bars.ResolveFont = ResolveFont

local live = {}          -- [barId] = entry
local sharedArmed = false
local lsmOwner, lsmHooked = {}, false   -- the media library's callback owner

-- defined with the runtimes below; the resource cast-preview and swing
-- handlers close over it
local ForEach

-- the aura composition lives between the fill and the overlay host: one
-- engine button + its bar per slot, two levels each, base + up to 8 layers
-- (3 flip bands = 6, a max-colour layer, the shade) = levels fill+1..+18
local AURA_LAYER_LEVELS = 20

local function R(rec, section, field)
    return Store.Resolve(rec, section, field)
end

-- A preview frame carries _adPxRef, the real bar's frame, and measures in its
-- pixels, so a zoomed preview keeps the real bar's proportions.
local function Px(f)
    if not (AT and AT.Px) then return 1 end
    return AT.Px((f and f._adPxRef) or f)
end

-- A border n real pixels thick, never thinner than one screen pixel of f
-- (a zoomed-out preview would draw it too thin to show).
function Bars.StripPx(f, n)
    if not n or n <= 0 then return 0 end
    local own = (AT and AT.Px) and AT.Px(f) or 1
    return math.max(Px(f) * n, own)
end

local function IsEditMode()
    local LE = NS.LayoutEngine
    return (LE and LE.IsEditMode and LE.IsEditMode()) and true or false
end

-- How many of a section's three bands are in use (1-3; absent = all three).
local function BandCount(rec, section, field)
    local n = tonumber(R(rec, section, field)) or 3
    if n < 1 then n = 1 elseif n > 3 then n = 3 end
    return math.floor(n)
end

-- Shell: background, 1px strip border, inset fill, overlay host. Strips keep
-- the default texel sampling: SetSnapToPixelGrid can collapse a 1px strip to
-- nothing, and a backdrop edge drops a side at fractional positions.

local function BuildShell(holder)
    local f = CreateFrame("Frame", nil, holder)
    f:SetAllPoints(holder)
    f:EnableMouse(false)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    f.bg = bg

    local edges = {}
    for _, k in ipairs(EDGE_KEYS) do
        edges[k] = f:CreateTexture(nil, "BORDER")
    end
    edges.top:SetPoint("TOPLEFT")
    edges.top:SetPoint("TOPRIGHT")
    edges.bottom:SetPoint("BOTTOMLEFT")
    edges.bottom:SetPoint("BOTTOMRIGHT")
    edges.left:SetPoint("TOPLEFT")
    edges.left:SetPoint("BOTTOMLEFT")
    edges.right:SetPoint("TOPRIGHT")
    edges.right:SetPoint("BOTTOMRIGHT")
    f.edges = edges

    local fill = CreateFrame("StatusBar", nil, f)
    fill:SetStatusBarTexture(WHITE)
    fill:SetStatusBarColor(1, 1, 1, 1)
    -- A StatusBar with no range renders full. Start every bar empty so one the
    -- engine is not driving yet reads as idle, not as a full aura.
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    local tex = fill:GetStatusBarTexture()
    -- Exact-edge sampling on the fill, so slot boundaries land where the math
    -- puts them (only 1px strips need the default sampling).
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    f.fill = fill
    f.fillTex = tex

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(fill)
    -- Above the charge-slot stack and the aura colour layers.
    overlay:SetFrameLevel(fill:GetFrameLevel() + AURA_LAYER_LEVELS)
    f.overlay = overlay

    -- Sheen: a plain texture over the fill (statusbar fill textures drop a
    -- gradient on redraw). Aura bars put theirs on the engine-drawn fill.
    local sheen = overlay:CreateTexture(nil, "BACKGROUND")
    sheen:SetAllPoints(tex)
    sheen:SetTexture(WHITE)
    if sheen.SetGradient and CreateColor then
        sheen:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.22), CreateColor(1, 1, 1, 0.14))
    else
        sheen:SetAlpha(0)
    end
    f.sheen = sheen

    f.dividers = {}
    f.ticks = {}
    f.texts = {}

    -- Divider stride and recharge slot width come from the live fill width,
    -- which is unresolved on the first build and can change at any time.
    f:SetScript("OnSizeChanged", function(self)
        if self._adResize then self._adResize() end
    end)

    return f
end

local function BarColorOf(rec)
    local c = R(rec, "fill", "color") or { 0.247, 0.788, 0.949, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

-- An aura composition may give the base fill a band colour (the segmented style
-- paints the top band from the base).
local function FillBaseColor(entry)
    local c = entry.auraFillColor
    if c then return c[1], c[2], c[3], c[4] or 1 end
    return BarColorOf(entry.rec)
end

-- Bar math: pure helpers, exported on Bars for the offline harness.

-- the stack-colour bands of an aura stack bar: sorted ascending, each
-- { from = stack, color }, only bands inside (1, max]; nil when off. Equal
-- starts keep the later band.
local function StackBands(rec, maxStacks)
    if R(rec, "stackcolors", "scEnabled") ~= true then return nil end
    local list = {}
    for i = 2, 1 + BandCount(rec, "stackcolors", "scCount") do
        local v = R(rec, "stackcolors", "sc" .. i .. "Value") or 0
        if v > 1 and v <= maxStacks then
            list[#list + 1] = { from = v, n = i,
                color = R(rec, "stackcolors", "sc" .. i .. "Color") or { 1, 1, 1, 1 } }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.from < b.from end)
    local out = {}
    for _, b in ipairs(list) do
        if out[#out] and out[#out].from == b.from then out[#out] = b else out[#out + 1] = b end
    end
    return out
end
Bars.StackBands = StackBands

-- The time bands of a duration bar, sorted ascending by fraction of the full
-- duration (0 = expired): each { f, secs, color }; nil when off. `ref` is the
-- full duration in seconds the values convert against (seconds mode needs it
-- for the fraction, percent mode for the seconds).
local function DurationBands(rec, ref)
    if R(rec, "thresholds", "threshEnabled") ~= true then return nil end
    local asSec = R(rec, "thresholds", "threshAsSeconds") ~= false
    ref = tonumber(ref) or 0
    local list = {}
    for i = 2, 1 + BandCount(rec, "thresholds", "threshCount") do
        local v = R(rec, "thresholds", "thresh" .. i .. "Value") or 0
        if v > 0 then
            local f, secs
            if asSec then
                secs = v
                f = ref > 0 and (v / ref) or nil
            else
                f = v / 100
                secs = ref > 0 and (v / 100 * ref) or nil
            end
            if f and f > 0.001 and f < 0.999 then
                list[#list + 1] = { f = f, secs = secs,
                    color = R(rec, "thresholds", "thresh" .. i .. "Color") or { 1, 1, 1, 1 } }
            end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.f < b.f end)
    local out = {}
    for _, b in ipairs(list) do
        if out[#out] and math.abs(out[#out].f - b.f) < 0.0005 then out[#out] = b else out[#out + 1] = b end
    end
    return out
end
Bars.DurationBands = DurationBands

-- Aura stack composition: the extra engine-driven fills a bar needs and where
-- they sit. Each layer: { kind = "band"|"max", minA, maxA (the engine's
-- applications window), x0, x1 (fractions of the bar), color, imm }. The
-- engine shows a fill only while count >= minA and stretches it across
-- minA..maxA, so a rect pre-sized to [x0..x1] paints exactly its region with
-- no reads. Returns the layers and the base fill colour.
local function StackLayerPlan(rec, maxStacks, segmented)
    local M = math.max(1, maxStacks or 1)
    local bands = StackBands(rec, M)
    local layers = {}
    local baseColor = R(rec, "fill", "color") or { 0.247, 0.788, 0.949, 1 }
    local fillColor = baseColor
    if bands then
        if segmented then
            -- Position colouring: the base paints the top band's colour
            -- and each boundary gets a saturating overlay painting the
            -- colour below it over [0 .. boundary); the largest boundary
            -- at the bottom of the stack, the smallest on top.
            fillColor = bands[#bands].color
            for k = #bands, 1, -1 do
                local T = bands[k].from
                layers[#layers + 1] = { kind = "band", minA = 0, maxA = T - 1,
                    x0 = 0, x1 = (T - 1) / M,
                    color = (k > 1) and bands[k - 1].color or baseColor }
            end
        else
            -- Flip colouring: at count >= T the whole fill takes the band
            -- colour. P paints [T .. count] (hidden under T); Q paints
            -- [0 .. T] once the count reaches T (hidden under T-1, empty at
            -- T-1, so the wipe hides inside one integer step). Higher bands
            -- draw on top.
            for k = 1, #bands do
                local T, c = bands[k].from, bands[k].color
                if T < M then
                    layers[#layers + 1] = { kind = "band", minA = T, maxA = M,
                        x0 = T / M, x1 = 1, color = c }
                end
                layers[#layers + 1] = { kind = "band", minA = T - 1, maxA = T,
                    x0 = 0, x1 = T / M, color = c, imm = true }
            end
        end
    end
    if R(rec, "stackcolors", "maxColorEnabled") == true then
        -- continuous: the whole fill at max; segmented: the last segment
        layers[#layers + 1] = { kind = "max", minA = M - 1, maxA = M,
            x0 = segmented and (M - 1) / M or 0, x1 = 1,
            color = R(rec, "stackcolors", "maxColor") or { 0, 1, 0, 1 }, imm = true }
    end
    return layers, fillColor
end
Bars.StackLayerPlan = StackLayerPlan

-- Aura duration composition. Each layer is a full fill clipped by a mask
-- (AuraMaskRect). Fractions are of the full duration; a drain bar paints the
-- remaining fraction from the origin, a fill bar the elapsed fraction. Each
-- layer: { kind = "track"|"step", side = "low"|"high", f, color, imm }:
--   track = a full-length fill clipped to one side of f (follows the base)
--   step  = an overhanging fill clipped to [0..f]: empty below f, full above
--           it, the whole window crossed within 0.05% of the aura's life.
local function DurationLayerPlan(bands, drain, baseColor)
    if not bands or #bands == 0 then return nil end
    local layers, n = {}, #bands
    if drain then
        -- Base c0; track(low, f_i, c_i) for i = n..1, then step(low, f_i,
        -- the colour above f_i) for i = 1..n. Below f_1 the top track wins;
        -- between f_i and f_i+1 step_i repaints [0..X_i] in c_i+1 exactly where
        -- track_i+1 already paints c_i+1; above f_n step_n restores the base.
        for i = n, 1, -1 do
            layers[#layers + 1] = { kind = "track", side = "low", f = bands[i].f, color = bands[i].color }
        end
        for i = 1, n do
            layers[#layers + 1] = { kind = "step", side = "low", f = bands[i].f,
                color = (i < n) and bands[i + 1].color or baseColor, imm = true }
        end
    else
        -- Fill (value = elapsed): band i applies once elapsed >= 1 - f_i.
        -- Pairs from the least urgent up: track(high, q_i) paints the fill
        -- beyond q_i, step(low, q_i) covers [0..q_i] once it is reached.
        for i = n, 1, -1 do
            local q = 1 - bands[i].f
            layers[#layers + 1] = { kind = "track", side = "high", f = q, color = bands[i].color }
            layers[#layers + 1] = { kind = "step", side = "low", f = q, color = bands[i].color, imm = true }
        end
    end
    return layers
end
Bars.DurationLayerPlan = DurationLayerPlan

-- tick positions as fractions of the bar (0 < p < 1) from the ticks section.
-- unitMax = the bar's full value in its own unit (stacks / seconds / power)
-- or nil when unknown; integerUnit = discrete units; costs = extra fractions
-- already resolved (resource spell costs).
local function TickFractions(rec, unitMax, integerUnit, costs)
    if R(rec, "ticks", "ticksShow") ~= true then return nil end
    local mode = R(rec, "ticks", "tickMode") or "percent"
    -- "pertick" marks come in through costs from a player castbar; a push or
    -- a unit change can leave the value on any other bar
    if mode == "pertick" and not (rec.barKind == "cast"
        and ((rec.driver and rec.driver.unit) or "player") == "player") then
        mode = "percent"
    end
    local out = {}
    local function add(p)
        if p and p > 0.0005 and p < 0.9995 then out[#out + 1] = p end
    end
    if mode == "all" then
        -- one per unit while that is a sane count, else percent steps
        if unitMax and integerUnit and unitMax >= 2 and unitMax <= 60 then
            for i = 1, math.floor(unitMax) - 1 do add(i / unitMax) end
        else
            mode = "percent"
        end
    end
    if mode == "percent" then
        local pct = R(rec, "ticks", "tickPercent") or 25
        if pct < 1 then pct = 1 end
        for i = 1, math.floor(100 / pct) do add(i * pct / 100) end
    elseif mode == "custom" then
        local asPct = R(rec, "ticks", "tickAsPercent") == true
        local scale = R(rec, "ticks", "tickScale") or 0
        if scale <= 0 then scale = unitMax or 0 end
        for v in tostring(R(rec, "ticks", "tickValues") or ""):gmatch("[%d%.]+") do
            local n = tonumber(v)
            if n then
                if asPct then add(n / 100) elseif scale > 0 then add(n / scale) end
            end
        end
    end
    for _, p in ipairs(costs or {}) do add(p) end
    if #out == 0 then return nil end
    table.sort(out)
    local dd = {}
    for _, p in ipairs(out) do
        if not dd[#dd] or math.abs(dd[#dd] - p) > 0.0005 then dd[#dd + 1] = p end
    end
    return dd
end
Bars.TickFractions = TickFractions

-- Text runs: flat-prefixed fields in Schema.bar.text

local TEXT_DEFS = {
    { key = "dur",   show = "durShow",   size = "durSize",   anchor = "durAnchor",
      x = "durOffsetX", y = "durOffsetY", colour = "durColor", outline = "durOutline", shadow = "durShadow" },
    { key = "stk",   show = "stkShow",   size = "stkSize",   anchor = "stkAnchor",
      x = "stkOffsetX", y = "stkOffsetY", colour = "stkColor", outline = "stkOutline", shadow = "stkShadow" },
    { key = "name",  show = "nameShow",  size = "nameSize",  anchor = "nameAnchor",
      x = "nameOffsetX", y = "nameOffsetY", colour = "nameColor", outline = "nameOutline", shadow = "nameShadow" },
    -- ready shares the duration text's styling
    { key = "ready", show = "readyShow", size = "durSize",   anchor = "durAnchor",
      x = "durOffsetX", y = "durOffsetY", colour = "readyColor", outline = "durOutline", shadow = "durShadow" },
    -- own run: a resource bar has no duration run to borrow and no stack run
    { key = "res",   show = "resShow",   size = "resSize",   anchor = "resAnchor",
      x = "resOffsetX", y = "resOffsetY", colour = "resColor", outline = "resOutline", shadow = "resShadow" },
    { key = "hp",    show = "hpShow",    size = "hpSize",    anchor = "hpAnchor",
      x = "hpOffsetX", y = "hpOffsetY", colour = "hpColor", outline = "hpOutline", shadow = "hpShadow" },
    -- Texts 2 and 3 of a resource or health bar, shown while its text count
    -- reaches them; they share text 1's outline and shadow.
    { key = "res2", show = "resShow", countField = "resCount", count = 2, size = "res2Size",
      anchor = "res2Anchor", x = "res2OffsetX", y = "res2OffsetY", colour = "res2Color",
      outline = "resOutline", shadow = "resShadow" },
    { key = "res3", show = "resShow", countField = "resCount", count = 3, size = "res3Size",
      anchor = "res3Anchor", x = "res3OffsetX", y = "res3OffsetY", colour = "res3Color",
      outline = "resOutline", shadow = "resShadow" },
    { key = "hp2", show = "hpShow", countField = "hpCount", count = 2, size = "hp2Size",
      anchor = "hp2Anchor", x = "hp2OffsetX", y = "hp2OffsetY", colour = "hp2Color",
      outline = "hpOutline", shadow = "hpShadow" },
    { key = "hp3", show = "hpShow", countField = "hpCount", count = 3, size = "hp3Size",
      anchor = "hp3Anchor", x = "hp3OffsetX", y = "hp3OffsetY", colour = "hp3Color",
      outline = "hpOutline", shadow = "hpShadow" },
}
local TEXT_DEF_BY_KEY = {}
for _, def in ipairs(TEXT_DEFS) do TEXT_DEF_BY_KEY[def.key] = def end

-- Each text run owns a Font object its strings inherit; face, size, outline and
-- shadow are written to the object, so every string using it re-renders. That
-- reaches engine-bound aura texts while their buttons are forbidden in combat,
-- and the Cooldown widget, which re-applies its countdown font on every start,
-- takes ours through SetCountdownFont. A bad font file fails silently, so the
-- path is proved first on a hidden string, whose SetFont reports success (an
-- object's does not).
local fontObjects = {}      -- [name] = Font
local fontProbe
local function FontObjectFor(entry, runKey)
    if not CreateFont then return nil end
    local name = "ArcUIv2BarFont_" .. tostring(entry.rec.id) .. "_" .. runKey
    local fo = fontObjects[name]
    if not fo then
        fo = CreateFont(name)
        fontObjects[name] = fo
    end
    return fo
end

local function ProvenFontPath(path, size, flags)
    if not fontProbe then
        fontProbe = UIParent:CreateFontString(nil, "OVERLAY")
        fontProbe:Hide()
    end
    if fontProbe:SetFont(path, size, flags) then return path end
    return BUILTIN_FONTS["Default"]
end

-- the recipe written to the run's Font object (or, on a client without
-- CreateFont, straight onto the string); returns the object
local function FontRecipe(entry, runKey, size, outline, shadow, fs)
    local rec = entry.rec
    size = size or 12
    local flags = (outline and outline ~= "NONE") and outline or ""
    local path = ProvenFontPath(ResolveFont(R(rec, "text", "font")), size, flags)
    local fo = FontObjectFor(entry, runKey)
    local target = fo or fs
    if not target then return nil end
    target:SetFont(path, size, flags)
    if shadow then
        target:SetShadowColor(0, 0, 0, 1)
        target:SetShadowOffset(1, -1)
    else
        target:SetShadowOffset(0, 0)
    end
    return fo
end

local function StyleFont(fs, entry, runKey, size, outline, shadow)
    local fo = FontRecipe(entry, runKey, size, outline, shadow, fs)
    if fo and fs:GetFontObject() ~= fo then fs:SetFontObject(fo) end
    return fo
end

-- Aura texts inherit their Font objects, so refreshing the objects reaches them
-- even while the engine forbids the buttons.
local function RefreshAuraFonts(entry)
    local rec = entry.rec
    for _, key in ipairs({ "dur", "stk" }) do
        local def = TEXT_DEF_BY_KEY[key]
        FontRecipe(entry, key, R(rec, "text", def.size) or 12,
            R(rec, "text", def.outline) or "OUTLINE", R(rec, "text", def.shadow) == true, nil)
    end
end

-- text anchors: the nine frame points, plus the OUTER family that hangs the
-- text off the bar's edge (above / below / left / right)
local OUTER_POINTS = {
    OUTERTOP = { "BOTTOM", "TOP" }, OUTERBOTTOM = { "TOP", "BOTTOM" },
    OUTERLEFT = { "RIGHT", "LEFT" }, OUTERRIGHT = { "LEFT", "RIGHT" },
    -- The corners: the text's near corner on the bar's far corner, so it runs
    -- inward along the edge (above-left reads left to right).
    OUTERTOPLEFT = { "BOTTOMLEFT", "TOPLEFT" }, OUTERTOPRIGHT = { "BOTTOMRIGHT", "TOPRIGHT" },
    OUTERBOTTOMLEFT = { "TOPLEFT", "BOTTOMLEFT" }, OUTERBOTTOMRIGHT = { "TOPRIGHT", "BOTTOMRIGHT" },
}
local function PlaceText(fs, host, anchor, x, y)
    fs:ClearAllPoints()
    local o = OUTER_POINTS[anchor]
    if o then
        fs:SetPoint(o[1], host, o[2], x or 0, y or 0)
    else
        anchor = anchor or "CENTER"
        fs:SetPoint(anchor, host, anchor, x or 0, y or 0)
    end
end

-- defined in the cooldown section; the text and icon builders need them early
local SpellIDFor, CooldownRefSeconds

-- Countdown colour bands in seconds, for the shared formatter. Percent
-- thresholds convert against the cooldown reference or the aura's duration.
local function TextBands(entry)
    local rec = entry.rec
    if R(rec, "thresholds", "threshEnabled") ~= true
        or R(rec, "thresholds", "threshText") ~= true then return nil end
    local ref
    if entry.kind == "aura" then
        ref = R(rec, "thresholds", "threshRef") or 30
    else
        -- The same reference as the fill curve and the tick scale
        -- (CooldownRefSeconds), else 30 s, so the three always agree.
        ref = (CooldownRefSeconds and CooldownRefSeconds(entry)) or 30
    end
    local bands = DurationBands(rec, ref)
    if not bands then return nil end
    local out = {}
    for _, b in ipairs(bands) do
        if b.secs and b.secs > 0 then out[#out + 1] = { t = b.secs, c = b.color } end
    end
    if #out == 0 then return nil end
    return out
end

-- Whether a text run renders. Store.Resolve ignores `kinds`, so a run that does
-- not apply to this bar kind still resolves to its default and would render an
-- empty fontstring; this uses the options panel's rule. A cooldown bar's
-- duration text is drawn by its Cooldown widget.
local function TextRunWanted(entry, def)
    local rec = entry.rec
    local want = R(rec, "text", def.show)
    if want == nil then want = false end
    local secDef = NS.Schema and NS.Schema.bar and NS.Schema.bar.text
    if want and secDef and NS.Schema.Applies then
        local fDef = secDef.fields and secDef.fields[def.show]
        if not NS.Schema.Applies(fDef, secDef, entry.kind, rec.barMode) then
            want = false
        end
    end
    if def.key == "dur" and entry.kind == "cooldown" then want = false end
    if want and def.countField and (R(rec, "text", def.countField) or 1) < def.count then
        want = false
    end
    return want
end

-- The custom name text, or nil; it wins over the bar's name and the unit's.
local function BarCustomName(rec)
    local v = R(rec, "text", "nameText")
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- The bar's own timer rounding, else the Settings choice.
local function BarRounding(rec)
    local v = R(rec, "text", "durRounding")
    if v == "up" or v == "down" then return v end
    return (NS.Factory and NS.Factory.TimerRounding and NS.Factory.TimerRounding()) or "up"
end

local function ApplyTexts(entry)
    local shell, rec = entry.shell, entry.rec
    for _, def in ipairs(TEXT_DEFS) do
        local fs = shell.texts[def.key]
        local want = TextRunWanted(entry, def)
        -- Aura duration and stack texts are engine bindings on the button; only
        -- the editor preview (no engine button) writes them here.
        if entry.kind == "aura" and not entry.isPreview and (def.key == "dur" or def.key == "stk") then
            want = false
        end
        if want and not fs then
            fs = shell.overlay:CreateFontString(nil, "OVERLAY")
            fs:SetWordWrap(false)
            shell.texts[def.key] = fs
        end
        if fs then
            if want then
                StyleFont(fs, entry, def.key, R(rec, "text", def.size) or 12,
                    R(rec, "text", def.outline) or "OUTLINE",
                    R(rec, "text", def.shadow) == true)
                local c = R(rec, "text", def.colour) or { 1, 1, 1, 1 }
                fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                PlaceText(fs, shell.overlay, R(rec, "text", def.anchor) or "CENTER",
                    R(rec, "text", def.x), R(rec, "text", def.y))
                fs:Show()
            else
                fs:SetText("")
                fs:Hide()
            end
        end
    end
    -- Static text, except a health bar's live unit name (HB.Name writes it) and
    -- a registered kind that writes its own (a cast bar's spell).
    local nameFS = shell.texts.name
    local customName = BarCustomName(rec)
    local ownKind = Bars.KINDS[entry.kind]
    if nameFS and nameFS:IsShown() and (customName or not ((entry.kind == "health"
        and (R(rec, "text", "nameSource") or "unit") == "unit")
        or (ownKind and ownKind.ownsName))) then
        nameFS:SetText(customName or rec.name or "")
    end

    -- A durObj's remaining time is secret and cannot become a string in Lua,
    -- so a Cooldown widget with the swipe off renders the countdown C-side from
    -- the same durObj; its fontstring takes the bar's duration-text style.
    if entry.durCD then
        local show = R(rec, "text", "durShow") ~= false
        entry.durCD:SetHideCountdownNumbers(not show)
        -- Decimals and colour bands come from the shared formatter, applied by
        -- the engine to the real remaining time. Pushed only on change (the
        -- Factory caches by recipe, so identity is the signature); nil = stock.
        if entry.durCD.SetCountdownFormatter then
            local fmt
            local decOn = show and R(rec, "text", "durDecimalsEnabled") == true
            local bands = show and TextBands(entry) or nil
            -- TimerFormatter: the options recipe, or a plain one when the
            -- Settings > Timers rounding is "down" (the stock rounds up)
            if NS.Factory and NS.Factory.TimerFormatter then
                fmt = NS.Factory.TimerFormatter(
                    decOn and (R(rec, "text", "durDecimalThreshold") or 10) or 0, bands,
                    show and (R(rec, "text", "durAbbrev") or 0) or 0, nil, BarRounding(rec))
            end
            local sig = fmt or "stock"
            if entry.durCD._adFmtSig ~= sig then
                entry.durCD._adFmtSig = sig
                entry.durCD:SetCountdownFormatter(fmt)
            end
        end
        local fs = entry.durCD.GetCountdownFontString and entry.durCD:GetCountdownFontString()
        if fs then
            if show then
                local fo = StyleFont(fs, entry, "durcd", R(rec, "text", "durSize") or 12,
                    R(rec, "text", "durOutline") or "OUTLINE",
                    R(rec, "text", "durShadow") == true)
                -- the widget re-applies its countdown Font object on every
                -- cooldown start: hand it ours by name and the face sticks
                if fo and entry.durCD.SetCountdownFont and entry.durCD._adFontName ~= fo:GetName() then
                    entry.durCD._adFontName = fo:GetName()
                    entry.durCD:SetCountdownFont(fo:GetName())
                end
                local c = R(rec, "text", "durColor") or { 0.95, 0.97, 1, 1 }
                fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                PlaceText(fs, entry.durCD, R(rec, "text", "durAnchor") or "RIGHT",
                    R(rec, "text", "durOffsetX"), R(rec, "text", "durOffsetY"))
            end
        end
    end
end

-- "Stack hides at zero": a charge count is secret in restricted content, so
-- `count == 0` throws. C_StringUtil.TruncateWhenZero blanks a zero without Lua
-- reading it (the icons do the same for hideChargeAtZero).
local function StackCount(rec, count)
    if count ~= nil and R(rec, "text", "stkHideAtZero") == true
        and C_StringUtil and C_StringUtil.TruncateWhenZero then
        return C_StringUtil.TruncateWhenZero(count)
    end
    return count
end

local function SetRunText(shell, key, value)
    local fs = shell.texts[key]
    if fs and fs:IsShown() then
        -- SetText is a secret-safe sink; callers may pass secret counts
        fs:SetText(value)
    end
end

-- Segments: n-1 dividers straddling each boundary, on the overlay host

local function LayoutDividers(shell, rec, n)
    if Bars.RectHidden(shell.fill) then return end   -- pinned to a nameplate
    local show = R(rec, "segments", "segmentsShow")
    local count = (show and n and n > 1) and (n - 1) or 0
    -- Along the fill axis: a vertical bar's segments stack bottom to top.
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local len = (vertical and shell.fill:GetHeight() or shell.fill:GetWidth()) or 0
    local stride = (count > 0 and len > 0) and (len / n) or 0
    local c = R(rec, "segments", "dividerColor") or { 0.039, 0.067, 0.125, 1 }
    -- segmentSpacing is the gap width in physical pixels. A divider is a
    -- hairline strip, so it is never thinner than 2 pixels (see LayoutTicks).
    local px = Px(shell) * math.max(2, R(rec, "segments", "segmentSpacing") or 2)
    for i = 1, count do
        local d = shell.dividers[i]
        if not d then
            d = shell.overlay:CreateTexture(nil, "ARTWORK")
            shell.dividers[i] = d
        end
        d:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        d:ClearAllPoints()
        local at = stride * i - px * 0.5
        if vertical then
            d:SetPoint("BOTTOMLEFT", shell.fill, "BOTTOMLEFT", 0, at)
            d:SetPoint("BOTTOMRIGHT", shell.fill, "BOTTOMRIGHT", 0, at)
            d:SetHeight(px)
        else
            d:SetPoint("TOPLEFT", shell.fill, "TOPLEFT", at, 0)
            d:SetPoint("BOTTOMLEFT", shell.fill, "BOTTOMLEFT", at, 0)
            d:SetWidth(px)
        end
        d:Show()
    end
    for i = count + 1, #shell.dividers do
        shell.dividers[i]:Hide()
    end
end

-- Style: the single writer of a bar's styled properties

-- defined with the aura runtime; ApplyStyle re-pushes the composition's
-- styling (colours, texture, fonts) while the engine buttons are accessible
local AuraRestyle
-- defined with the aura runtime too: mirrors the shell's chrome onto the
-- button-owned copies (Hide when inactive, see AuraOwnChromeBuild)
local AuraOwnChromeSync

-- While the engine's base button owns an aura bar's chrome, the shell's copies
-- are hidden with Hide/Show, not alpha: a texture's alpha and tint share one
-- channel that SetColorTexture does not rewrite, so a border silenced by alpha
-- would stay invisible in the next edit session. The owned copies are anchored
-- from geometry, not to these originals. The icon frame uses alpha: a frame's
-- alpha is its own channel, and its regions stay anchor targets.
local function ApplyChromeOwnership(entry)
    local sh = entry.shell
    local own = entry.chromeOwned == true
    sh.bg:SetShown(not own)
    for _, k in ipairs(EDGE_KEYS) do sh.edges[k]:SetShown(not own) end
    for i = 1, entry.tickCount or 0 do
        if sh.ticks[i] then sh.ticks[i]:SetShown(not own) end
    end
    if entry.iconF then entry.iconF:SetAlpha(own and 0 or 1) end
    if own then
        if sh.borderF then sh.borderF:Hide() end
        if sh.texts.name then sh.texts.name:Hide() end
    end
end

-- Bar icon: a textured square with a strip border, anchored outside the bar's
-- edge (left, right, top or bottom), so the bar's own size never changes.
local function ApplyBarIcon(entry)
    local shell, rec = entry.shell, entry.rec
    local show = R(rec, "icon", "iconShow") == true
    local f = entry.iconF
    if not show then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, shell)
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.edges = {}
        for _, k in ipairs(EDGE_KEYS) do
            f.edges[k] = f:CreateTexture(nil, "OVERLAY")
        end
        f.edges.top:SetPoint("TOPLEFT")
        f.edges.top:SetPoint("TOPRIGHT")
        f.edges.bottom:SetPoint("BOTTOMLEFT")
        f.edges.bottom:SetPoint("BOTTOMRIGHT")
        f.edges.left:SetPoint("TOPLEFT")
        f.edges.left:SetPoint("BOTTOMLEFT")
        f.edges.right:SetPoint("TOPRIGHT")
        f.edges.right:SetPoint("BOTTOMRIGHT")
        entry.iconF = f
    end
    -- Own size by default; "Match the bar's size" follows the bar's thickness
    -- (its short side). From the settings, not the rect, snapped to whole
    -- pixels; a stored 0 also means follow.
    local size = R(rec, "icon", "iconSize") or 24
    if R(rec, "icon", "iconFollowBar") == true or size <= 0 then
        local bw = R(rec, "size", "width") or 193
        local bh = R(rec, "size", "height") or 24
        size = math.min(bw, bh) * (R(rec, "size", "scale") or 1)
    end
    local ipx = Px(shell)
    size = math.max(ipx, math.floor(size / ipx + 0.5) * ipx)
    f:SetSize(size, size)
    local side = R(rec, "icon", "iconSide") or "LEFT"
    local gap = R(rec, "icon", "iconSpacing") or 2
    local ox = R(rec, "icon", "iconOffsetX") or 0
    local oy = R(rec, "icon", "iconOffsetY") or 0
    f:ClearAllPoints()
    if side == "RIGHT" then
        f:SetPoint("LEFT", shell, "RIGHT", gap + ox, oy)
    elseif side == "TOP" then
        f:SetPoint("BOTTOM", shell, "TOP", ox, gap + oy)
    elseif side == "BOTTOM" then
        f:SetPoint("TOP", shell, "BOTTOM", ox, -gap + oy)
    else
        f:SetPoint("RIGHT", shell, "LEFT", -gap + ox, oy)
    end
    local tex
    local ov = R(rec, "icon", "iconOverride") or 0
    if ov and ov > 0 then
        tex = (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ov)) or ov
    else
        local sid = SpellIDFor and SpellIDFor(rec)
        tex = sid and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
    end
    f.tex:SetTexture(tex or 134400)
    local bOn = R(rec, "icon", "iconBorderEnabled") ~= false
    local bc = R(rec, "icon", "iconBorderColor") or { 0, 0, 0, 1 }
    local bpx = Bars.StripPx(shell, R(rec, "icon", "iconBorderThickness") or 1)
    entry.iconEdgeRGBA = { bc[1], bc[2], bc[3], bOn and (bc[4] or 1) or 0 }   -- for the owned copies
    for _, k in ipairs(EDGE_KEYS) do
        local t = f.edges[k]
        t:SetColorTexture(bc[1], bc[2], bc[3], bOn and (bc[4] or 1) or 0)
        if k == "top" or k == "bottom" then t:SetHeight(bpx) else t:SetWidth(bpx) end
    end
    local ti = bOn and bpx or 0
    f.tex:ClearAllPoints()
    f.tex:SetPoint("TOPLEFT", ti, -ti)
    f.tex:SetPoint("BOTTOMRIGHT", -ti, ti)
    f:Show()
end

-- Gradient overlay: a plain texture over the fill (statusbar fill textures do
-- not hold gradients), clear at one side and the end colour at the other (the
-- bottom for VERTICAL, the far end for HORIZONTAL). Plain sources only.
local function ApplySheen(tex, rec)
    if not (tex.SetGradient and CreateColor) then return end
    local c = R(rec, "fill", "gradientColor") or { 0, 0, 0, 0.45 }
    local clear = CreateColor(c[1], c[2], c[3], 0)
    local full = CreateColor(c[1], c[2], c[3], c[4] or 0.45)
    if (R(rec, "fill", "gradientDir") or "VERTICAL") == "HORIZONTAL" then
        tex:SetGradient("HORIZONTAL", clear, full)
    else
        tex:SetGradient("VERTICAL", full, clear)
    end
end

local function ApplyStyle(entry)
    local shell, rec = entry.shell, entry.rec

    -- Pips (one cell per item): the shell's own background, border and sheen
    -- stand down, since every cell carries them (LayoutPips).
    local pipsOn = entry.kind == "resource" and R(rec, "resource", "style") == "pips"
    entry.pipsOn = pipsOn

    -- The background defaults to the fill's texture, dimmed, so the empty
    -- part of the bar shows the pattern faintly.
    local bgShow = R(rec, "look", "bgShow") ~= false and not pipsOn
    local bgC = R(rec, "look", "bgColor") or { 0.039, 0.067, 0.125, 1 }
    local bgKey = R(rec, "look", "bgTexture")
    shell.bg:SetTexture(ResolveBarTexture((bgKey == nil or bgKey == "") and R(rec, "fill", "texture") or bgKey))
    -- The opacity slider is the only alpha: the colour picker cannot show the
    -- colour's own, so a hidden one would cap the slider below 100.
    local bgA = R(rec, "look", "bgAlpha") or 1
    shell.bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgShow and bgA or 0)

    local borderOn = R(rec, "look", "borderEnabled") ~= false and not pipsOn
    local bc = R(rec, "look", "borderColor") or { 0.114, 0.165, 0.247, 1 }
    if R(rec, "look", "useClassColorBorder") == true then
        local _, tag = UnitClass("player")
        local cc = tag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
        if cc then bc = { cc.r, cc.g, cc.b, 1 } end
    end
    local th = R(rec, "look", "borderThickness") or 1
    local px = Bars.StripPx(shell, th)
    -- Border style: Flat is the 1px strips (default); any other is an edge
    -- file drawn as a backdrop at the thickness, one level under the overlay
    -- so it clears every fill layer and stays under the texts.
    local edgeFile = ResolveBorder(R(rec, "look", "borderStyle"))
    local strips = borderOn and not edgeFile
    -- The resolved strip colour, kept for the button-owned copies: a colour set
    -- with SetColorTexture does not read back through GetVertexColor.
    entry.edgeRGBA = { bc[1], bc[2], bc[3], strips and (bc[4] or 1) or 0 }
    for _, k in ipairs(EDGE_KEYS) do
        local t = shell.edges[k]
        t:SetColorTexture(bc[1], bc[2], bc[3], strips and (bc[4] or 1) or 0)
        if k == "top" or k == "bottom" then t:SetHeight(px) else t:SetWidth(px) end
    end
    if borderOn and edgeFile then
        local bf = shell.borderF
        if not bf then
            bf = CreateFrame("Frame", nil, shell, BackdropTemplateMixin and "BackdropTemplate" or nil)
            bf:SetAllPoints(shell)
            bf:EnableMouse(false)
            shell.borderF = bf
        end
        bf:SetFrameLevel(shell.overlay:GetFrameLevel() - 1)
        if bf.SetBackdrop then
            if bf._adEdge ~= edgeFile or bf._adSize ~= px then
                bf._adEdge, bf._adSize = edgeFile, px
                bf:SetBackdrop({ edgeFile = edgeFile, edgeSize = px })
            end
            bf:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        end
        bf:Show()
    elseif shell.borderF then
        shell.borderF:Hide()
    end
    entry.borderFWanted = (borderOn and edgeFile ~= nil) or false

    -- The fill sits inside the border plus fillInset; in pips style the fill
    -- (the pip host) spans the whole frame.
    local inset = (borderOn and px or 0)
        + (pipsOn and 0 or Px(shell) * (R(rec, "fill", "fillInset") or 0))
    shell.fill:ClearAllPoints()
    shell.fill:SetPoint("TOPLEFT", shell, "TOPLEFT", inset, -inset)
    shell.fill:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -inset, inset)
    -- kept for a swing bar's off-hand track, which splits this rect
    entry.fillInset = inset
    shell.fill:SetOrientation(R(rec, "fill", "orientation") or "HORIZONTAL")
    shell.fill:SetReverseFill(R(rec, "fill", "reverseFill") == true)

    -- A texture swap creates a new texture object: refresh the cached ref and
    -- re-apply sampling and the sheen anchor. While an aura composition has
    -- colour layers the base fill goes flat and its shade layer carries the
    -- texture for all of them, so no seam shows two shades.
    local texPath = entry.auraSplit and WHITE or ResolveBarTexture(R(rec, "fill", "texture"))
    if entry.texApplied ~= texPath then
        entry.texApplied = texPath
        shell.fill:SetStatusBarTexture(texPath)
        local t = shell.fill:GetStatusBarTexture()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        shell.fillTex = t
    end
    shell.sheen:ClearAllPoints()
    shell.sheen:SetAllPoints(shell.fillTex)
    ApplySheen(shell.sheen, rec)
    shell.fill:SetRotatesTexture(R(rec, "fill", "rotateTexture") == true)

    -- Fill colour goes through SetStatusBarColor, reasserted here and after
    -- every refresh write; the curve ticker owns it while it runs.
    if not entry.colorTicking then
        shell.fill:SetStatusBarColor(FillBaseColor(entry))
    end
    if entry.kind == "aura" and AuraRestyle then AuraRestyle(entry) end
    -- an aura bar's sheen rides its engine-drawn fill (AuraStyleSlot); a
    -- pips bar has no continuous fill to shade
    shell.sheen:SetShown(R(rec, "fill", "useGradient") ~= false and entry.kind ~= "aura" and not pipsOn)

    ApplyBarIcon(entry)
    ApplyTexts(entry)
    if entry.kind == "aura" then
        RefreshAuraFonts(entry)
        -- Last, so the owned copies take the freshly painted values: the
        -- shell's chrome goes silent while the button owns it.
        ApplyChromeOwnership(entry)
        if AuraOwnChromeSync then AuraOwnChromeSync(entry) end
    end
    -- a kind in its own file puts back what this pass reset while it is
    -- showing something (a castbar's spell icon and colours, mid-cast)
    local KS = Bars.KINDS[entry.kind]
    if KS and KS.Styled then KS.Styled(entry) end
    -- a main-hand swing bar's off-hand track (Bars\AD_SwingOffhand.lua)
    if entry.kind == "swing" and Bars.SwingOH then Bars.SwingOH.Styled(entry) end
    -- a swing bar's closing halves and ticks (Bars\AD_SwingClosing.lua), after
    -- the off-hand pass, which may have split the fill
    if entry.kind == "swing" and Bars.SwingClose then Bars.SwingClose.Styled(entry) end
    -- the spark on a swing or timer bar's moving edge (Bars\AD_BarSpark.lua),
    -- after the closing pass: its mirror half gets one too
    if (entry.kind == "swing" or entry.kind == "timer") and Bars.Spark then Bars.Spark.Styled(entry) end
    -- a swing bar's out-of-range dim (Bars\AD_SwingRange.lua)
    if entry.kind == "swing" and Bars.SwingRange then Bars.SwingRange.Styled(entry) end
    -- a main-hand swing bar's next-swing ability markers (Bars\AD_SwingAbilities.lua),
    -- they ride the main fill as the two passes above left it
    if entry.kind == "swing" and Bars.SwingAbil then Bars.SwingAbil.Styled(entry) end
    -- a swing bar's ability colours (Bars\AD_SwingColors.lua), last: its hook
    -- takes over the fill colour this pass wrote, and the closing mirror too
    if entry.kind == "swing" and Bars.SwingColor then Bars.SwingColor.Styled(entry) end
end

-- Visibility: opacity x state hides x conditions; edit mode always wins

local function ApplyVisibility(entry)
    local rec = entry.rec
    local hidden = false
    if entry.stateHidden then hidden = true end
    if IsEditMode() then hidden = false end
    local alpha
    if hidden then
        alpha = R(rec, "behavior", "hiddenAlpha") or 0
    else
        alpha = R(rec, "size", "opacity") or 1
        -- A swing bar's out-of-range dim (Bars\AD_SwingRange.lua), Blizzard's
        -- own 0.4; never in edit sessions.
        if entry.rangeDimmed and not IsEditMode() then alpha = alpha * 0.4 end
    end
    -- Conditions: 0 while the bar is inert, else its Visibility fade; 1 in edit
    -- sessions.
    if NS.Conditions then alpha = alpha * NS.Conditions.AlphaFor(rec) end
    entry.holder:SetAlpha(alpha)
end

-- The conditions module paints bars through this writer, since the holder
-- alpha is set only here; every bar kind gets Load when and Visibility.
if NS.Conditions then
    NS.Conditions.RegisterSubject("bar", {
        each = function(fn)
            for id in pairs(live) do fn(id) end
        end,
        apply = function(rec)
            local e = live[rec.id]
            if e and e.holder then ApplyVisibility(e) end
        end,
    })
end

-- Cooldown runtime: the dual-shadow model, same rules as the cooldown driver

local function MakeShadow()
    local w = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    w:SetSize(1, 1)
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    w:SetAlpha(0)
    w:EnableMouse(false)
    w:SetHideCountdownNumbers(true)
    w:SetDrawEdge(false)
    w:SetDrawBling(false)
    w:Show()      -- a hidden parent would freeze IsShown transitions
    return w
end

-- assigns the forward-declared local above (ApplyBarIcon closes over it)
function SpellIDFor(rec)
    if R(rec, "behavior", "gcdMode") then return GCD_SPELL end
    local d = rec.driver
    if not d then return nil end
    -- Ranked realms (Forever): resolve by name on each feed so the bar follows
    -- the player's known rank; SPELLS_CHANGED re-feeds cover rank-ups.
    local sid = d.spellID
    if d.autoRank and sid and C_Spell.GetSpellIDForSpellIdentifier then
        local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
        if nm then
            local rid = C_Spell.GetSpellIDForSpellIdentifier(nm)
            if rid then sid = rid end
        end
    end
    -- Talent overrides: follow the active override on each feed (SPELLS_CHANGED
    -- re-feeds cover flips); driver.ignoreSpellOverride pins the base spell.
    if sid and not d.ignoreSpellOverride and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if ov and ov ~= 0 then sid = ov end
    end
    return sid
end

-- The plain full cooldown length (seconds) that thresholds, text bands and the
-- tick scale convert against, or nil: the typed "Cooldown length", else the
-- last plain length CooldownRefresh saw for this spell (the real, modified
-- one; secret ones are skipped), else GetSpellBaseCooldown, a legacy global
-- with no C_Spell form that is 0 for charge spells. Callers fall back to 30 s
-- (curve, text) or skip (ticks).
function CooldownRefSeconds(entry)
    local rec = entry.rec
    local typed = tonumber(R(rec, "thresholds", "threshCdSeconds")) or 0
    if typed > 0 then return typed end
    local sid = SpellIDFor(rec)
    if sid and entry.cdLenSid == sid and entry.cdLenPlain then
        return entry.cdLenPlain
    end
    if sid and GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(sid)
        if ms and not (issecretvalue and issecretvalue(ms))
            and type(ms) == "number" and ms > 0 then
            return ms / 1000
        end
    end
    return nil
end

-- Threshold color curve (cooldown bars). The remaining time is secret, so
-- durObj:EvaluateRemainingPercent(curve) maps it C-side to a color for
-- SetVertexColor. Curves interpolate, so steps get epsilon gaps. Domain: the
-- remaining fraction, 0 = ready, 1 = full duration.

local function BuildCooldownCurve(entry)
    local rec = entry.rec
    if R(rec, "thresholds", "threshEnabled") ~= true then return nil, nil end
    -- Probe the table, not just the method: indexing a missing table errors.
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
        return nil, nil
    end
    local base = R(rec, "fill", "color") or { 0.247, 0.788, 0.949, 1 }
    local asSec = R(rec, "thresholds", "threshAsSeconds") ~= false
    -- Seconds mode needs a plain reference duration to place the points:
    -- CooldownRefSeconds, else 30 s. It is part of the hash, so a newly taught
    -- length rebuilds the curve. Percent mode needs none and is exact.
    local ref = 30
    if asSec then
        ref = CooldownRefSeconds(entry) or 30
    end
    local bands = {}
    for i = 2, 1 + BandCount(rec, "thresholds", "threshCount") do
        local v = R(rec, "thresholds", "thresh" .. i .. "Value") or 0
        if v > 0 then
            bands[#bands + 1] = {
                value = v,
                color = R(rec, "thresholds", "thresh" .. i .. "Color") or { 1, 1, 1, 1 },
            }
        end
    end
    if #bands == 0 then return nil, nil end
    table.sort(bands, function(a, b) return a.value > b.value end)

    local hash = (asSec and "s" or "p") .. string.format("%.1f", ref)
    for _, b in ipairs(bands) do
        hash = hash .. string.format("|%g:%.2f,%.2f,%.2f", b.value, b.color[1], b.color[2], b.color[3])
    end
    hash = hash .. string.format("|%.2f,%.2f,%.2f", base[1], base[2], base[3])
    if entry.curve and entry.curveHash == hash then return entry.curve, hash end

    local curve = C_CurveUtil.CreateColorCurve()
    local EPS = 0.0001
    local lowest = bands[#bands]
    curve:AddPoint(0, CreateColor(lowest.color[1], lowest.color[2], lowest.color[3], lowest.color[4] or 1))
    for i = #bands, 1, -1 do
        local b = bands[i]
        local pct = asSec and (b.value / ref) or (b.value / 100)
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        local nextC = (i == 1) and base or bands[i - 1].color
        if pct > EPS then
            curve:AddPoint(pct - EPS, CreateColor(b.color[1], b.color[2], b.color[3], b.color[4] or 1))
        end
        curve:AddPoint(pct, CreateColor(nextC[1], nextC[2], nextC[3], nextC[4] or 1))
    end
    curve:AddPoint(1, CreateColor(base[1], base[2], base[3], base[4] or 1))
    return curve, hash
end

-- Reassert the base colors on every colored surface: the restore path after
-- the curve ticker, and the per-refresh writer for stack slots.
local function ReassertBaseColors(entry)
    local rec = entry.rec
    local r, g, b, a = BarColorOf(rec)
    entry.shell.fill:SetStatusBarColor(r, g, b, a)
    if entry.slotList then
        local rcOn = R(rec, "segments", "rechargeColorEnabled") == true
        local rc = rcOn and (R(rec, "segments", "rechargeColor") or { r, g, b, 0.55 })
        for i = 1, entry.slots or 0 do
            local s = entry.slotList[i]
            if s then
                if rc then
                    s.recharge:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4] or 1)
                else
                    s.recharge:SetStatusBarColor(r, g, b, a)
                end
            end
        end
    end
end

local function StopColorTicker(entry, restore)
    if entry.colorTicking then
        entry.colorTicking = nil
        entry.shell.fill:SetScript("OnUpdate", nil)
    end
    if restore then ReassertBaseColors(entry) end
end

local function StartColorTicker(entry)
    local sid = SpellIDFor(entry.rec)
    if not (sid and entry.curve) then return end
    -- the fallback animator owns the fill's OnUpdate slot; curve colors sit
    -- out while it drives (degraded mode on clients without the timer API)
    if entry.fbRunning then return end
    -- The source (charge or plain cooldown) is fixed at setup and every tick
    -- takes a fresh durObj from it; switching sources mid-run flickers. Stack
    -- mode colors each slot's recharge texture (the SetStatusBarColor channel).
    local useCharge = entry.isCharge
    local targets = {}
    if entry.mode == "stack" and entry.slotList then
        for i = 1, entry.slots or 0 do
            local s = entry.slotList[i]
            if s then targets[#targets + 1] = s.recharge:GetStatusBarTexture() end
        end
    else
        targets[1] = entry.shell.fillTex
    end
    if #targets == 0 then return end
    entry.colorTicking = true
    local acc = 1   -- first frame paints immediately
    entry.shell.fill:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end   -- 20fps: color bands, not motion
        acc = 0
        local durObj
        if useCharge then
            durObj = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(sid, true)
        else
            durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid, true)
        end
        if durObj then
            local col = durObj:EvaluateRemainingPercent(entry.curve)
            if col then
                for i = 1, #targets do
                    targets[i]:SetVertexColor(col:GetRGB())
                end
            end
        end
    end)
end

local function CooldownBuild(entry)
    local shell = entry.shell
    entry.sCD = entry.sCD or MakeShadow()
    entry.sCharge = entry.sCharge or MakeShadow()

    -- Cooldown expiry fires no reliable event, so the shadow's OnCooldownDone
    -- triggers a refresh (nothing is read in the hook), coalesced so a Clear()
    -- inside our own feed cannot re-enter the refresh synchronously.
    if not entry.doneHooked then
        entry.doneHooked = true
        local barId = entry.rec.id
        local function onDone()
            local e2 = live[barId]
            if not e2 or e2.feeding then return end
            Events.Coalesce("adbars_done" .. barId, function()
                if live[barId] then Bars.Refresh(barId) end
            end)
        end
        entry.sCD:SetScript("OnCooldownDone", onDone)
        entry.sCharge:SetScript("OnCooldownDone", onDone)
    end

    if not entry.slotHost then
        entry.slotHost = CreateFrame("Frame", nil, shell)
        entry.slotHost:SetAllPoints(shell.fill)
        entry.slotHost:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
        entry.slotList = {}
    end

    if not entry.durCD then
        -- Text only: the client renders the countdown from a secret durObj.
        local dcd = CreateFrame("Cooldown", nil, shell.overlay, "CooldownFrameTemplate")
        dcd:SetAllPoints(shell.overlay)
        dcd:SetDrawSwipe(false)
        dcd:SetDrawEdge(false)
        dcd:SetDrawBling(false)
        dcd:SetHideCountdownNumbers(false)
        -- The widget draws numbers only above its minimum duration, which hides
        -- a 2 s cooldown by default. The GCD never reaches it (ignoreGCD feed).
        if dcd.SetMinimumCountdownDuration then dcd:SetMinimumCountdownDuration(0) end
        dcd:EnableMouse(false)
        dcd:Show()
        entry.durCD = dcd
    end
end

-- Charge-slot model (stack mode). Each slot: a dim bg texture, a rechargeBar
-- (engine-fed, level +1) and a fullBar (level +2) whose min/max (i-0.5, i) and
-- SetValue(count) render full or empty straight from the possibly secret count,
-- with no Lua compare. An offscreen 1px detector per slot shares the min/max;
-- its texture width is piped into the next slot's SetAlpha, so only the active
-- refill slot shows past the full ones.

local function EnsureSlot(entry, i)
    local s = entry.slotList[i]
    if s then return s end
    local host = entry.slotHost
    s = {}
    s.bg = host:CreateTexture(nil, "BACKGROUND")
    s.recharge = CreateFrame("StatusBar", nil, host)
    s.recharge:SetFrameLevel(host:GetFrameLevel() + 1)
    s.recharge:SetMinMaxValues(0, 1)
    s.recharge:SetValue(0)
    s.full = CreateFrame("StatusBar", nil, host)
    s.full:SetFrameLevel(host:GetFrameLevel() + 2)
    s.full:SetMinMaxValues(i - 0.5, i)
    s.full:SetValue(0)
    -- Slot gradient (the shell sheen rides the continuous fill, which stack
    -- mode never paints), re-anchored when LayoutSlots swaps the texture.
    s.sheen = s.full:CreateTexture(nil, "OVERLAY")
    s.sheen:SetTexture(WHITE)
    if not (s.sheen.SetGradient and CreateColor) then s.sheen:SetAlpha(0) end
    s.detector = CreateFrame("StatusBar", nil, UIParent)
    s.detector:SetSize(1, 10)
    s.detector:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
    s.detector:SetStatusBarTexture(WHITE)
    s.detector:SetStatusBarColor(1, 1, 1, 1)
    s.detector:SetAlpha(0)
    s.detector:SetMinMaxValues(i - 0.5, i)
    s.detector:SetValue(0)
    s.detector:Show()
    s.detectorTex = s.detector:GetStatusBarTexture()
    entry.slotList[i] = s
    return s
end

local function HideSlots(entry)
    for _, s in pairs(entry.slotList or {}) do
        s.bg:Hide()
        s.recharge:Hide()
        s.full:Hide()
        s.detector:SetValue(0)
    end
end

local function LayoutSlots(entry)
    if entry.mode ~= "stack" or not entry.slotHost then return end
    if Bars.RectHidden(entry.shell.fill) then return end   -- pinned to a nameplate
    local rec = entry.rec
    local n = entry.slots or 1
    local totalW = entry.shell.fill:GetWidth() or 0
    local totalH = entry.shell.fill:GetHeight() or 0
    if totalW <= 0 or totalH <= 0 then return end
    local gap = 0
    if n > 1 and R(rec, "segments", "segmentsShow") ~= false then
        gap = Px(entry.shell) * math.max(1, R(rec, "segments", "segmentSpacing") or 1)
    end
    local slotW = math.max((totalW - gap * (n - 1)) / n, 1)
    local texPath = ResolveBarTexture(R(rec, "fill", "texture"))
    -- the slot backgrounds follow the bar's Background block: its texture
    -- (the fill's by default) and its toggle (off = alpha 0, like the shell)
    local bgKey = R(rec, "look", "bgTexture")
    local bgTex = ResolveBarTexture((bgKey == nil or bgKey == "") and R(rec, "fill", "texture") or bgKey)
    local bgC = R(rec, "look", "bgColor") or { 0.039, 0.067, 0.125, 1 }
    local bgA = (R(rec, "look", "bgShow") ~= false) and (R(rec, "look", "bgAlpha") or 1) or 0
    local rot = R(rec, "fill", "rotateTexture") == true
    local gradientOn = R(rec, "fill", "useGradient") ~= false
    for i = 1, n do
        local s = EnsureSlot(entry, i)
        local x = (i - 1) * (slotW + gap)
        s.bg:ClearAllPoints()
        s.bg:SetPoint("TOPLEFT", entry.slotHost, "TOPLEFT", x, 0)
        s.bg:SetSize(slotW, totalH)
        s.bg:SetTexture(bgTex)
        s.bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgA)
        s.bg:Show()
        for _, sb in ipairs({ s.recharge, s.full }) do
            sb:ClearAllPoints()
            sb:SetPoint("TOPLEFT", entry.slotHost, "TOPLEFT", x, 0)
            sb:SetSize(slotW, totalH)
            sb:SetOrientation("HORIZONTAL")
            sb:SetRotatesTexture(rot)
            if sb._adTex ~= texPath then
                sb._adTex = texPath
                sb:SetStatusBarTexture(texPath)
                local t = sb:GetStatusBarTexture()
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
                if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
                if sb == s.full and s.sheen then
                    s.sheen:ClearAllPoints()
                    s.sheen:SetAllPoints(t)
                end
            end
            sb:Show()
        end
        if s.sheen then
            ApplySheen(s.sheen, rec)
            s.sheen:SetShown(gradientOn)
        end
    end
    for i = n + 1, #entry.slotList do
        local s = entry.slotList[i]
        s.bg:Hide()
        s.recharge:Hide()
        s.full:Hide()
        s.detector:SetValue(0)
    end
end

-- Mode-aware geometry:
--   duration  continuous engine-driven fill, no slots
--   stack     the charge-slot model above (a single-charge spell gets one slot)
local function CooldownChargeState(entry)
    local sid = SpellIDFor(entry.rec)
    local info = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    -- maxCharges > 1 marks a charge spell (single-charge spells return a
    -- chargeInfo table too); maxCharges is not secret on 12.0.1 and later.
    local maxCharges = (info and info.maxCharges) or 0
    entry.isCharge = maxCharges > 1
    entry.maxCharges = entry.isCharge and maxCharges or 0

    if entry.mode == "stack" then
        local slots = entry.isCharge and maxCharges or 1
        local segs = R(entry.rec, "segments", "segmentCount") or 0
        if segs > 0 then slots = segs end     -- manual override
        entry.slots = slots
        -- the continuous fill never paints in stack mode - slots render
        entry.shell.fill:SetMinMaxValues(0, 1)
        entry.shell.fill:SetValue(0)
        LayoutSlots(entry)
        -- "/max" suffix: maxCharges is non-secret, the count is never read
        local maxFS = entry.shell.texts.stkMax
        local wantMax = entry.isCharge and R(entry.rec, "text", "stkShowMax") == true
            and R(entry.rec, "text", "stkShow") ~= false
        if wantMax and not maxFS then
            maxFS = entry.shell.overlay:CreateFontString(nil, "OVERLAY")
            entry.shell.texts.stkMax = maxFS
        end
        if maxFS then
            if wantMax and entry.shell.texts.stk then
                StyleFont(maxFS, entry, "stkMax", R(entry.rec, "text", "stkSize") or 12,
                    R(entry.rec, "text", "stkOutline") or "OUTLINE",
                    R(entry.rec, "text", "stkShadow") == true)
                local c = R(entry.rec, "text", "stkColor") or { 0.95, 0.97, 1, 1 }
                maxFS:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                maxFS:ClearAllPoints()
                maxFS:SetPoint("LEFT", entry.shell.texts.stk, "RIGHT", 1, 0)
                maxFS:SetText("/" .. maxCharges)
                maxFS:Show()
            else
                maxFS:Hide()
            end
        end
    else
        entry.slots = 0
        HideSlots(entry)
        entry.shell.fill:SetMinMaxValues(0, 1)
        if entry.shell.texts.stkMax then entry.shell.texts.stkMax:Hide() end
    end
    -- charge-ness may have flipped (talent swap): the color ticker's frozen
    -- source and targets are stale - stop it, the next refresh restarts it
    StopColorTicker(entry, false)
end

local function CooldownPushState(entry)
    local m = entry.sCD:IsShown() == true
    local c = entry.isCharge and entry.sCharge:IsShown() == true or false
    -- hideWhenReady needs two consecutive ready reads: one transient ready
    -- read mid-GCD must not blink the bar away.
    local rec = entry.rec
    local ready = not m and not c
    local wantHide = false
    if R(rec, "behavior", "hideWhenFullCharges") and entry.isCharge and ready then
        wantHide = true          -- charge bars hide without the debounce
    elseif R(rec, "behavior", "hideWhenReady") and ready then
        if entry.pendingReady then
            wantHide = true      -- second consecutive read confirms it
        else
            entry.pendingReady = true
            wantHide = entry.stateHidden or false
        end
    else
        entry.pendingReady = false
    end
    -- The GCD tracker is inverted (shown while on the GCD), with no debounce.
    if R(rec, "behavior", "gcdMode") then
        wantHide = ready
        entry.pendingReady = false
    end
    entry.stateHidden = wantHide
    ApplyVisibility(entry)

    local readyFS = entry.shell.texts.ready
    if readyFS and readyFS:IsShown() then
        readyFS:SetText(ready and (R(rec, "text", "readyText") or "Ready") or "")
    end
end

local function CooldownSchedulePostGCD(entry)
    if entry.postGCDQueued then return end
    entry.postGCDQueued = true
    local delay = 0.3
    local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(GCD_SPELL)
    if cd then
        local s, d = cd.startTime, cd.duration
        if not (issecretvalue and (issecretvalue(s) or issecretvalue(d)))
            and type(s) == "number" and type(d) == "number" and d > 0 then
            local rem = (s + d) - GetTime()
            if rem > 0 and rem < 2 then delay = rem + 0.05 end
        end
    end
    C_Timer.After(delay, function()
        entry.postGCDQueued = nil
        if live[entry.rec.id] then Bars.Refresh(entry.rec.id) end
    end)
end

local function FeedStatusBarTimer(bar, durObj, smooth, drain)
    if not (HAS_TIMER_API and bar.SetTimerDuration and durObj) then return false end
    -- Fall back to whatever interpolation exists rather than fail the feed.
    local interp = smooth and (INTERP_SMOOTH or INTERP_ANY) or (INTERP_NONE or INTERP_ANY)
    local dir = drain and DIR_REMAIN or DIR_ELAPSED
    if interp == nil or dir == nil then return false end
    bar:SetTimerDuration(durObj, interp, dir)
    if bar.SetToTargetValue then bar:SetToTargetValue() end   -- kills the 0->100 pop
    return true
end

-- Plain-time fallback for clients without the engine timer feed: the fill
-- animates from plain cooldown numbers, guarded with issecretvalue, and holds
-- still rather than guess when they are secret. One animator per entry on
-- shell.fill's OnUpdate (the fill, or every slot's rechargeBar in stack mode),
-- stopped as soon as the cooldown ends or the engine path takes over.

local function StopPlainFallback(entry)
    if entry.fbRunning then
        entry.fbRunning = nil
        entry.shell.fill:SetScript("OnUpdate", nil)
    end
end

local function StartPlainFallback(entry, sid, srcCharge, drain)
    local s, d
    if srcCharge then
        local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        s = ci and ci.cooldownStartTime
        d = ci and ci.cooldownDuration
    else
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
        s = cd and cd.startTime
        d = cd and cd.duration
    end
    if s == nil or d == nil then return false end
    if issecretvalue and (issecretvalue(s) or issecretvalue(d)) then return false end
    if type(s) ~= "number" or type(d) ~= "number" or d <= 0 then return false end
    entry.fbEnd = s + d
    entry.fbDur = d
    entry.fbDrain = drain
    if entry.fbRunning then return true end     -- retargeted via fbEnd/fbDur
    entry.fbRunning = true
    local barId = entry.rec.id
    entry.shell.fill:SetScript("OnUpdate", function(bar)
        local e2 = live[barId]
        if not e2 or not e2.fbRunning then
            bar:SetScript("OnUpdate", nil)
            return
        end
        local remaining = e2.fbEnd - GetTime()
        if remaining <= 0 then
            StopPlainFallback(e2)
            Bars.Refresh(barId)                 -- the ready edge
            return
        end
        if e2.mode == "stack" then
            local frac = 1 - (remaining / e2.fbDur)   -- refill rises
            for i = 1, e2.slots or 0 do
                local sl = e2.slotList and e2.slotList[i]
                if sl then
                    sl.recharge:SetMinMaxValues(0, 1)
                    sl.recharge:SetValue(frac)
                end
            end
        else
            bar:SetMinMaxValues(0, e2.fbDur)
            bar:SetValue(e2.fbDrain and remaining or (e2.fbDur - remaining))
        end
    end)
    return true
end

-- While a real cooldown runs (the shadows ignore the GCD), the refresh passes
-- the full length it saw: the recharge length for charge spells, else the
-- cooldown length. Kept only when plain (it is secret in combat on Forever,
-- in instances on retail); the 1.5 s floor drops a stray GCD read. Keyed by
-- spell, so an edited or overridden spell never inherits it.
local OnCooldownLengthLearned   -- defined after LayoutTicks, which it re-runs
local function TeachCooldownLength(entry, sid, len)
    if len == nil or (issecretvalue and issecretvalue(len)) then return end
    if type(len) ~= "number" or len <= 1.5 then return end
    if entry.cdLenSid == sid and entry.cdLenPlain == len then return end
    entry.cdLenSid, entry.cdLenPlain = sid, len
    OnCooldownLengthLearned(entry)
end

local function CooldownRefresh(entry)
    local rec = entry.rec
    local sid = SpellIDFor(rec)
    if not sid or not C_Spell.GetSpellCooldownDuration then return end

    -- The wand's lock is ignored like the GCD (DriverCooldown.WandLocked). A
    -- cooldown already running keeps its own timing: nothing to re-read.
    -- cdLive marks one this refresh accepted: a new shadow shows before its
    -- first feed. On the wand's own bar the lock is its real cooldown.
    local dc = NS.DriverCooldown
    local wandLock = dc ~= nil and dc.WandLocked() and not dc.IsWandShot(sid)
    if wandLock and entry.cdLive and entry.sCD:IsShown() == true then return end

    -- shadows always read ignoreGCD=true: state must never see the GCD.
    -- entry.feeding brackets the feeds so OnCooldownDone (fired by Clear)
    -- can never re-enter this refresh synchronously.
    entry.feeding = true
    local mainDur = C_Spell.GetSpellCooldownDuration(sid, true)
    if wandLock then mainDur = nil end
    if mainDur then
        entry.sCD:SetCooldownFromDurationObject(mainDur, true)
    else
        entry.sCD:Clear()
    end
    entry.cdLive = entry.sCD:IsShown() == true
    local chargeDur
    if entry.isCharge and C_Spell.GetSpellChargeDuration then
        chargeDur = C_Spell.GetSpellChargeDuration(sid, true)
        if chargeDur then
            entry.sCharge:SetCooldownFromDurationObject(chargeDur, true)
        else
            entry.sCharge:Clear()
        end
    end
    entry.feeding = nil

    local m = entry.sCD:IsShown() == true
    local c = entry.isCharge and entry.sCharge:IsShown() == true or false
    local smooth = R(rec, "fill", "smoothing") ~= false
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"

    if entry.mode == "stack" then
        -- The possibly secret count goes into every slot's fullBar and
        -- detector through SetValue; the widget's min/max does the comparing.
        -- Slot 1 always shows; slot i's alpha is the previous detector's width.
        -- A nil chargeInfo is mid-GCD: keep the last state to avoid flicker.
        local info = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        local n = entry.slots or 1
        local count
        if entry.isCharge then
            count = info and info.currentCharges
        else
            count = m and 0 or 1     -- one slot: full exactly when ready
        end
        local fullOn = R(rec, "segments", "fullColorEnabled") == true
        local fc = fullOn and (R(rec, "segments", "fullColor") or { 0.482, 0.847, 0.561, 1 })
        local br, bg2, bb, ba = BarColorOf(rec)
        for i = 1, n do
            local s = entry.slotList[i]
            if s then
                if count ~= nil then
                    s.full:SetValue(count)
                    s.detector:SetValue(count)
                end
                if fc then
                    s.full:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
                else
                    s.full:SetStatusBarColor(br, bg2, bb, ba)
                end
                if i == 1 then
                    s.recharge:SetAlpha(1)
                    s.full:SetAlpha(1)
                else
                    local prev = entry.slotList[i - 1]
                    local w = prev and prev.detectorTex and prev.detectorTex:GetWidth() or 1
                    -- the width goes straight into SetAlpha, never compared
                    s.recharge:SetAlpha(w)
                    s.full:SetAlpha(w)
                end
            end
        end
        if not entry.colorTicking then ReassertBaseColors(entry) end
        -- The recharge animation runs on every slot (full ones are covered);
        -- charge slots take the possibly secret recharge length as their max.
        local rDur = entry.isCharge and chargeDur or mainDur
        local running = entry.isCharge and c or m
        if running and rDur then
            local engineFed = true
            for i = 1, n do
                local s = entry.slotList[i]
                if s then
                    if entry.isCharge and info then
                        s.recharge:SetMinMaxValues(0, info.cooldownDuration)
                    else
                        s.recharge:SetMinMaxValues(0, 1)
                    end
                    if not FeedStatusBarTimer(s.recharge, rDur, smooth, false) then
                        engineFed = false
                    end
                end
            end
            if engineFed then
                StopPlainFallback(entry)
            elseif not StartPlainFallback(entry, sid, entry.isCharge, false) then
                -- secret numbers + no engine path: hold static, never guess
                for i = 1, n do
                    local s = entry.slotList[i]
                    if s then s.recharge:SetValue(0) end
                end
            end
        elseif not running then
            StopPlainFallback(entry)
            for i = 1, n do
                local s = entry.slotList[i]
                if s then s.recharge:SetValue(0) end
            end
        end
        if entry.isCharge and info then
            SetRunText(entry.shell, "stk", StackCount(rec, info.currentCharges))
        end
    else
        -- Duration mode: charge spells ride the charge duration, all others
        -- (single-charge too) the main cooldown; never switched mid-run.
        local src = entry.isCharge and chargeDur or mainDur
        local active = entry.isCharge and c or m
        if active then
            if FeedStatusBarTimer(entry.shell.fill, src, smooth, drain) then
                StopPlainFallback(entry)
            elseif not StartPlainFallback(entry, sid, entry.isCharge, drain) then
                -- secret numbers + no engine path: hold static, never guess
                entry.shell.fill:SetValue(drain and 1 or 0)
            end
        else
            StopPlainFallback(entry)
            entry.shell.fill:SetMinMaxValues(0, 1)
            -- A plain SetValue overrides the timer binding: full when ready, or
            -- empty with idleEmpty on.
            entry.shell.fill:SetValue(R(rec, "fill", "idleEmpty") == true and 0 or 1)
        end
        -- Reassert the fill colour after the value write (the ticker owns it
        -- while a threshold curve runs).
        if not entry.colorTicking then
            entry.shell.fill:SetStatusBarColor(BarColorOf(rec))
        end
        -- charge spells keep their count text in duration mode
        if entry.isCharge then
            local info = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
            if info then SetRunText(entry.shell, "stk", StackCount(rec, info.currentCharges)) end
        end
    end

    if not entry.isCharge then
        local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
        local onGcd = info and info.isOnGCD
        if issecretvalue and issecretvalue(onGcd) then onGcd = nil end
        if onGcd == true then CooldownSchedulePostGCD(entry) end
        if m and info then TeachCooldownLength(entry, sid, info.duration) end
    elseif c and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(sid)
        if info then TeachCooldownLength(entry, sid, info.cooldownDuration) end
    end

    -- The threshold color ticker runs only while something is running and a
    -- curve exists; ready restores the base color.
    if entry.curve then
        if m or c then
            if not entry.colorTicking then StartColorTicker(entry) end
        else
            StopColorTicker(entry, true)
        end
    else
        StopColorTicker(entry, false)
    end

    -- Duration text: the text-only Cooldown gets the same durObj (the charge
    -- timer while a charge recharges, else the full cooldown), rendered C-side.
    if entry.durCD then
        local textDur = mainDur
        if entry.isCharge and c and not m then textDur = chargeDur end
        if textDur then
            entry.durCD:SetCooldownFromDurationObject(textDur, true)
        else
            entry.durCD:Clear()
        end
    end

    CooldownPushState(entry)
end

-- Timer runtime: plain GetTime math; OnUpdate only while running

local function TimerStop(entry)
    entry.running = false
    entry.shell.fill:SetScript("OnUpdate", nil)
    entry.shell.fill:SetValue(0)
    if Bars.Spark then Bars.Spark.Sync(entry) end
    SetRunText(entry.shell, "dur", "")
    entry.shell.fill:SetStatusBarColor(BarColorOf(entry.rec))
    -- the text bands may have recoloured the countdown: restore its colour
    local fs = entry.shell.texts.dur
    if fs then
        local c = R(entry.rec, "text", "durColor") or { 0.95, 0.97, 1, 1 }
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    entry.stateHidden = R(entry.rec, "behavior", "hideWhenInactive") and true or false
    ApplyVisibility(entry)
end

-- Timer thresholds compare plainly: the remaining time is our own GetTime math,
-- never secret. Bands sort ascending; the smallest band the value fits wins.
local function BuildPlainBands(rec)
    if R(rec, "thresholds", "threshEnabled") ~= true then return nil end
    local bands = {}
    for i = 2, 1 + BandCount(rec, "thresholds", "threshCount") do
        local v = R(rec, "thresholds", "thresh" .. i .. "Value") or 0
        if v > 0 then
            bands[#bands + 1] = {
                value = v,
                color = R(rec, "thresholds", "thresh" .. i .. "Color") or { 1, 1, 1, 1 },
            }
        end
    end
    if #bands == 0 then return nil end
    table.sort(bands, function(a, b) return a.value < b.value end)
    return {
        asSeconds = R(rec, "thresholds", "threshAsSeconds") ~= false,
        base = R(rec, "fill", "color") or { 0.247, 0.788, 0.949, 1 },
        bands = bands,
        -- the countdown text takes the band colour too (plain math here)
        text = R(rec, "thresholds", "threshText") == true,
        textBase = R(rec, "text", "durColor") or { 0.95, 0.97, 1, 1 },
    }
end

-- one GetTime fill loop shared by the timer and swing runtimes; onDone is
-- the runtime's own idle transition
local function RunTimedFill(entry, duration, onDone)
    duration = tonumber(duration) or 0
    if duration <= 0 then return end
    local shell, rec = entry.shell, entry.rec
    entry.duration = duration
    entry.endTime = GetTime() + duration
    entry.running = true
    entry.textAcc = 1
    entry.stateHidden = false
    ApplyVisibility(entry)

    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    shell.fill:SetMinMaxValues(0, duration)
    shell.fill:SetValue(drain and duration or 0)
    shell.fill:SetStatusBarColor(BarColorOf(rec))
    -- the spark rides the fill's edge while it runs (Bars\AD_BarSpark.lua)
    if Bars.Spark then Bars.Spark.Sync(entry) end
    -- decimals below the threshold only (mirrors the shared formatter's
    -- band recipe; this text is our own GetTime math, so plain formatting)
    local decOn = R(rec, "text", "durDecimalsEnabled") == true
    local decTo = R(rec, "text", "durDecimalThreshold") or 10
    -- whole seconds round the way Settings > Timers says (up by default)
    local roundDown = BarRounding(rec) == "down"
    local abbrev = R(rec, "text", "durAbbrev") or 0

    shell.fill:SetScript("OnUpdate", function(bar, elapsed)
        local remaining = entry.endTime - GetTime()
        if remaining <= 0 then
            onDone(entry)
            return
        end
        bar:SetValue(drain and remaining or (entry.duration - remaining))
        entry.textAcc = (entry.textAcc or 0) + elapsed
        if entry.textAcc >= 0.05 then
            entry.textAcc = 0
            SetRunText(shell, "dur", NS.Factory.FormatCountdown(remaining,
                decOn and decTo or 0, abbrev, roundDown))
            local pt = entry.plainThresh
            if pt then
                local x = pt.asSeconds and remaining
                    or (remaining / entry.duration * 100)
                local col, hit = pt.base, false
                for i = 1, #pt.bands do
                    if x <= pt.bands[i].value then
                        col = pt.bands[i].color
                        hit = true
                        break
                    end
                end
                bar:SetStatusBarColor(col[1], col[2], col[3], 1)
                if pt.text then
                    local fs = shell.texts.dur
                    if fs then
                        local tc = hit and col or pt.textBase
                        fs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
                    end
                end
            end
        end
    end)
end

local function TimerStart(entry, duration)
    -- Bands are fixed at start; a settings change lands on the next trigger.
    entry.plainThresh = BuildPlainBands(entry.rec)
    RunTimedFill(entry,
        tonumber(duration) or tonumber(entry.rec.driver and entry.rec.driver.duration) or 0,
        TimerStop)
end

-- Stack runtime, legacy power bars: UnitPower into SetValue (secret-safe)

local function StackRefresh(entry)
    local rec = entry.rec
    local pt = rec.driver and rec.driver.powerType
    if not pt then return end
    -- UnitPowerMax is SecretWhenUnitPowerMaxRestricted: a secret max is never
    -- compared and the last plain one stands (1 until one has been seen).
    local maxv = UnitPowerMax("player", pt)
    if maxv ~= nil and not (issecretvalue and issecretvalue(maxv)) and maxv > 0 then
        entry.plainMax = maxv
    end
    maxv = entry.plainMax or 1
    entry.shell.fill:SetMinMaxValues(0, maxv)
    local cur = UnitPower("player", pt)
    if cur ~= nil then
        entry.shell.fill:SetValue(cur)   -- displayed, never compared
        SetRunText(entry.shell, "stk", StackCount(rec, cur))
    end
    entry.shell.fill:SetStatusBarColor(BarColorOf(rec))
    local segs = R(rec, "segments", "segmentCount") or 0
    if segs == 0 then segs = maxv end
    if segs ~= entry.segments then
        entry.segments = segs
        LayoutDividers(entry.shell, rec, segs)
    end
end

-- Resource runtime: the player's primary power bar (mana, rage, energy).
-- Forever is Classic-era on the modern engine: UnitPower and UnitPowerMax can
-- be secret, and combat secrecy is broader than on retail. So the value is
-- never read back: SetMinMaxValues takes the last plain max (the widget needs
-- a real range), SetValue takes the power raw, the colour keys off the power
-- type (UnitPowerType is not secret) and texts use secret-safe formatters.
-- Power colours are our own: PowerBarColor does not exist on Forever
-- (PowerBarColorUtil.lua loads only on mainline).

-- id -> { token, name, color, frequent, classic }. `frequent` types ride
-- UNIT_POWER_FREQUENT, the rest UNIT_POWER_UPDATE (never both), so mana skips
-- the fast-regen rate. The runtime reads POWER_ALL, so a record synced from
-- another machine keeps its colour where that power does not exist locally.
local POWER_ALL = {
    [0] = { token = "MANA",        name = "Mana",        color = { 0, 0.5, 1 },                     classic = true },
    [1] = { token = "RAGE",        name = "Rage",        color = { 1, 0, 0 },      frequent = true, classic = true },
    [2] = { token = "FOCUS",       name = "Focus",       color = { 1, 0.5, 0.25 }, frequent = true },
    [3] = { token = "ENERGY",      name = "Energy",      color = { 1, 1, 0 },      frequent = true, classic = true },
    -- Combo points: Blizzard's own colour; UNIT_POWER_UPDATE carries them
    -- (token COMBO_POINTS). Target-bound on Forever, see ResourceCurrent.
    [4] = { token = "COMBO_POINTS", name = "Combo Points", color = { 1, 0.96, 0.41 }, classic = true },
    [6] = { token = "RUNIC_POWER", name = "Runic Power", color = { 0, 0.82, 1 },   frequent = true },
}
Bars.POWER_ALL = POWER_ALL

-- POWER_INFO is what the options panel may offer on this client; Classic has
-- only a handful (druids switch with form: the picker's Automatic entry). Runic
-- power is left out (no Death Knights), and so is focus, which belongs to the
-- pet in this era. Both stay in POWER_ALL so synced records still render.
-- NS.IsForever is set by Core\AD_Forever.lua, which loads before this file.
local POWER_INFO = {}
for id, info in pairs(POWER_ALL) do
    if info.classic or NS.IsForever ~= true then POWER_INFO[id] = info end
end
Bars.POWER_INFO = POWER_INFO

local cachedMax = {}        -- [powerType] = last plain max (secret ones dropped)
local formPending = false   -- one settle timer for shapeshift, never a stack

-- The max a resource entry lays its cells, ticks and absolute bands out
-- against. The editor preview uses the range it paints (PV.ResourceRange),
-- since the live cache is empty without this power. Combo points with no
-- plain max yet (a login in combat, a class without them) lay out 5.
function Bars.PlainMax(entry)
    if entry.isPreview and entry.lastMax then return entry.lastMax end
    local pt = entry.powerType
    local m = pt and cachedMax[pt]
    if m == nil and pt == 4 then m = 5 end
    return m
end

-- Events.On calls RegisterEvent directly, and Forever throws on an event name
-- it does not have, so every power event goes through the probe.
local function SafeOn(event, key, fn)
    if C_EventUtils and C_EventUtils.IsEventValid
        and not C_EventUtils.IsEventValid(event) then return end
    Events.On(event, key, fn)
end

-- defined with the resource runtime below (ticks and the refresh read them)
local ResourceCostFractions, ResourceCostList, PredictLayout, EnsurePredictEvents

-- Ticks: laid out once per size or setting change, never per update

-- the bar's full value in its own unit, whether that unit is discrete, and
-- any extra tick fractions (resource spell costs). nil = unknown (duration
-- bars whose length only the engine knows): custom ticks then need percent
-- or a typed scale, and "all" falls back to percent.
local AuraMaxStacks   -- the aura maximum reader (typed > game > 5), defined with the aura runtime

local function TickUnit(entry)
    local rec, kind = entry.rec, entry.kind
    if kind == "cooldown" then
        if entry.mode == "stack" then return entry.slots or 1, true end
        -- the same reference the thresholds use; nil until something plain
        -- is known (typed, taught by a cast, or the base cooldown)
        local ref = CooldownRefSeconds(entry)
        if ref then return ref, true end
        return nil, false
    elseif kind == "aura" then
        if entry.mode == "stack" then
            -- The same maximum the composition uses, so "Every point" marks
            -- match the cells: typed, else the game's, else 5.
            local m = AuraMaxStacks and AuraMaxStacks(rec)
                or tonumber(rec.driver and rec.driver.maxStacks) or 5
            return math.max(1, math.floor(m)), true
        end
        return nil, false
    elseif kind == "timer" then
        return tonumber(rec.driver and rec.driver.duration), true
    elseif kind == "resource" then
        local range = Bars.PlainMax(entry)
        return range, true, ResourceCostFractions and ResourceCostFractions(entry, range) or nil
    elseif kind == "health" then
        -- health points: the plain cached max (custom ticks typed in health
        -- need it; "Every point" falls back to percent at any real maximum)
        return entry.hpMax, true
    elseif kind == "stack" then
        return entry.segments, true
    elseif kind == "swing" then
        -- The swing length in seconds: the last PLAYER_SWING duration, else the
        -- hand's attack speed while it reads plain; it can be secret in combat.
        local len = entry.swingLen
        if not len then
            local st = (rec.driver and rec.driver.swingType) or 0
            local v
            if st == 2 then
                v = UnitRangedDamage and UnitRangedDamage("player")
            elseif UnitAttackSpeed then
                local mh, oh = UnitAttackSpeed("player")
                if st == 1 then v = oh else v = mh end
            end
            if v ~= nil and not (issecretvalue and issecretvalue(v))
                and type(v) == "number" and v > 0 then
                len = v
            end
        end
        return len, false
    end
    local KT = Bars.KINDS[kind]
    if KT and KT.TickUnit then return KT.TickUnit(entry) end
    return nil, false
end

-- Cost icons: each "cost ticks" spell gets its icon at its tick, above, below
-- or on the bar. "Dim icons you cannot afford" never compares the power: a 1px
-- detector StatusBar with the window (cost - 0.5, cost) is fed the possibly
-- secret value, and its texture width goes straight into the lit copy's
-- SetAlpha. A desaturated copy underneath keeps an unaffordable spell visible.
local function EnsureCostIcon(entry, i)
    entry.costIcons = entry.costIcons or {}
    local ci = entry.costIcons[i]
    if ci then return ci end
    local shell = entry.shell
    local f = CreateFrame("Frame", nil, shell)
    f:SetFrameLevel(shell.overlay:GetFrameLevel() + 1)
    f:EnableMouse(false)
    local dim = f:CreateTexture(nil, "ARTWORK")
    dim:SetAllPoints()
    dim:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dim:SetDesaturated(true)
    local lit = f:CreateTexture(nil, "ARTWORK", nil, 1)
    lit:SetAllPoints()
    lit:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local det = CreateFrame("StatusBar", nil, UIParent)
    det:SetSize(1, 10)
    det:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
    det:SetStatusBarTexture(WHITE)
    det:SetStatusBarColor(1, 1, 1, 1)
    det:SetAlpha(0)
    det:Show()
    ci = { f = f, dim = dim, lit = lit, det = det, detTex = det:GetStatusBarTexture() }
    entry.costIcons[i] = ci
    return ci
end

local function LayoutCostIcons(entry)
    local list = entry.costIcons
    local rec, shell = entry.rec, entry.shell
    if Bars.RectHidden(shell.fill) then return end   -- pinned to a nameplate
    local want = R(rec, "ticks", "ticksShow") == true and R(rec, "ticks", "tickSpellIcons") == true
    local range = Bars.PlainMax(entry)
    local items = want and ResourceCostList and ResourceCostList(entry, range) or nil
    local fill = shell.fill
    local W, H = fill:GetWidth() or 0, fill:GetHeight() or 0
    if not items or W <= 1 or H <= 1 then
        for _, ci in ipairs(list or {}) do ci.f:Hide() end
        entry.costIconsOn = false
        return
    end
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local side = R(rec, "ticks", "tickIconSide") or "TOP"
    local size = R(rec, "ticks", "tickIconSize") or 0
    if size <= 0 then size = vertical and W or H end
    local px = Px(shell)
    local len = vertical and H or W
    local dimOn = R(rec, "ticks", "tickIconDim") == true
    local n = 0
    for _, it in ipairs(items) do
        if n >= 20 then break end
        n = n + 1
        local ci = EnsureCostIcon(entry, n)
        local tex = (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(it.id)) or 134400
        ci.dim:SetTexture(tex)
        ci.lit:SetTexture(tex)
        ci.f:SetSize(size, size)
        -- centred on the tick position, measured from the fill origin
        local pos = math.floor(len * it.frac / px + 0.5) * px
        ci.f:ClearAllPoints()
        if vertical then
            local y = rev and -pos or pos
            local edge = rev and "TOP" or "BOTTOM"
            if side == "TOP" then
                ci.f:SetPoint("LEFT", fill, edge .. "RIGHT", 2, y)     -- beside, to the right
            elseif side == "BOTTOM" then
                ci.f:SetPoint("RIGHT", fill, edge .. "LEFT", -2, y)    -- beside, to the left
            else
                ci.f:SetPoint("CENTER", fill, edge, 0, y)
            end
        else
            local x = rev and -pos or pos
            local edge = rev and "RIGHT" or "LEFT"
            if side == "TOP" then
                ci.f:SetPoint("BOTTOM", fill, "TOP" .. edge, x, 2)
            elseif side == "BOTTOM" then
                ci.f:SetPoint("TOP", fill, "BOTTOM" .. edge, x, -2)
            else
                ci.f:SetPoint("CENTER", fill, edge, x, 0)
            end
        end
        -- the lit copy is full once the value reaches the cost and gone half a
        -- unit below it; without dimming it simply stays on
        ci.det:SetMinMaxValues(it.cost - 0.5, it.cost)
        if dimOn then
            ci.dim:SetAlpha(0.35)
            ci.dim:Show()
        else
            ci.dim:Hide()
            ci.lit:SetAlpha(1)
        end
        ci.f:Show()
    end
    for i = n + 1, #(list or {}) do entry.costIcons[i].f:Hide() end
    entry.costIconsOn = dimOn and n > 0
    entry.costIconCount = n
end

local function LayoutTicks(entry)
    local shell, rec = entry.shell, entry.rec
    if Bars.RectHidden(shell.fill) then return end   -- pinned to a nameplate
    local pool = shell.ticks
    if entry.kind == "resource" then LayoutCostIcons(entry) end
    -- A charge-slot cooldown bar has no ticks (its slot gaps are the marks);
    -- a pips bar draws cells. Other counted bars draw "Every point" marks
    -- from the live maximum.
    local fracs
    if not (entry.mode == "stack" and entry.kind == "cooldown") and not entry.pipsOn then
        local unitMax, integerUnit, costs = TickUnit(entry)
        fracs = TickFractions(rec, unitMax, integerUnit, costs)
    end
    if not fracs then
        for _, t in ipairs(pool) do t:Hide() end
        entry.tickCount = 0
        if entry.kind == "aura" and entry.chromeOwned and AuraOwnChromeSync then
            AuraOwnChromeSync(entry)
        end
        return
    end
    local fill = shell.fill
    local W, H = fill:GetWidth() or 0, fill:GetHeight() or 0
    if W <= 1 or H <= 1 then return end   -- not sized yet; the resize hook re-runs us
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local px = Px(shell)
    -- A strip one physical pixel thick at a fractional position can rasterise
    -- to nothing, and a dragged bar is fractional every frame, so a mark is at
    -- least two physical pixels (like the theme's AT.Hairline), which always
    -- cover a pixel centre. SetSnapToPixelGrid is no fix: strips keep the
    -- default sampling.
    local thick = px * math.max(2, R(rec, "ticks", "tickThickness") or 2)
    local hp = (R(rec, "ticks", "tickHeight") or 100) / 100
    local anchor = R(rec, "ticks", "tickHeightAnchor") or "center"
    local c = R(rec, "ticks", "tickColor") or { 0, 0, 0, 1 }
    entry.tickRGBA = c   -- for the button-owned copies (see ApplyStyle's edgeRGBA)
    local len = vertical and H or W
    local cross = vertical and W or H
    local tickCross = math.max(px, math.floor(cross * hp / px + 0.5) * px)
    local n = 0
    for _, p in ipairs(fracs) do
        if n >= 100 then break end
        n = n + 1
        local t = pool[n]
        if not t then
            t = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
            pool[n] = t
        end
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:ClearAllPoints()
        -- centred on the snapped position, measured from the fill origin
        local pos = math.floor(len * p / px + 0.5) * px - thick * 0.5
        if vertical then
            t:SetSize(tickCross, thick)
            local y = rev and -pos or pos
            local edge = rev and "TOP" or "BOTTOM"
            if anchor == "start" then
                t:SetPoint(edge .. "LEFT", fill, edge .. "LEFT", 0, y)
            elseif anchor == "end" then
                t:SetPoint(edge .. "RIGHT", fill, edge .. "RIGHT", 0, y)
            else
                t:SetPoint(edge, fill, edge, 0, y)
            end
        else
            t:SetSize(thick, tickCross)
            local x = rev and -pos or pos
            local edge = rev and "RIGHT" or "LEFT"
            if anchor == "start" then
                t:SetPoint("TOP" .. edge, fill, "TOP" .. edge, x, 0)
            elseif anchor == "end" then
                t:SetPoint("BOTTOM" .. edge, fill, "BOTTOM" .. edge, x, 0)
            else
                t:SetPoint(edge, fill, edge, x, 0)
            end
        end
        -- a registered kind may hold its marks back (a castbar's "tick marks
        -- on channels only" while a cast that is not a channel shows)
        t:SetShown(not entry.ticksOff)
    end
    for i = n + 1, #pool do pool[i]:Hide() end
    entry.tickCount = n
    if entry.kind == "aura" and entry.chromeOwned then
        ApplyChromeOwnership(entry)
        if AuraOwnChromeSync then AuraOwnChromeSync(entry) end
    end
end

-- A newly taught cooldown length moves every seconds-mode reference: rebuild
-- the threshold curve (the running ticker reads entry.curve on every paint),
-- re-hand the countdown formatter and re-lay the ticks. Runs once per spell
-- per session, and again only if the real length changes.
function OnCooldownLengthLearned(entry)
    if entry.kind ~= "cooldown" then return end
    if entry.curve or R(entry.rec, "thresholds", "threshEnabled") == true then
        entry.curve, entry.curveHash = BuildCooldownCurve(entry)
        if not entry.curve then StopColorTicker(entry, false) end
    end
    ApplyTexts(entry)
    LayoutTicks(entry)
end

-- Resource runtime, continued

local function PowerColorOf(rec, pt)
    if R(rec, "resource", "usePowerColor") == false then
        -- pips have their own point colour (Fill is hidden in that style)
        if R(rec, "resource", "style") == "pips" then
            local c = R(rec, "resource", "pointColor") or { 0.247, 0.788, 0.949, 1 }
            return c[1], c[2], c[3], c[4] or 1
        end
        return BarColorOf(rec)
    end
    local info = POWER_ALL[pt]
    if info then
        local c = info.color
        return c[1], c[2], c[3], 1
    end
    -- an unlisted type: UnitPowerType's rgb returns are not secret and exist
    -- on Forever, where the PowerBarColor global does not
    local _, _, r, g, b = UnitPowerType("player")
    if r then return r, g, b, 1 end
    return BarColorOf(rec)
end

-- Which power this bar tracks: an explicit choice, else the live display power
-- (UnitPowerType is not secret and follows druid forms).
local function ResourceSyncType(entry)
    local d = entry.rec.driver
    local want = d and d.powerType
    if want == nil or want < 0 then want = UnitPowerType("player") end
    if want == nil or entry.powerType == want then return false end
    entry.powerType = want
    entry.lastMax = nil
    entry.cr, entry.cg, entry.cb = nil, nil, nil
    return true
end

-- Threshold colours: a colour curve on the percent domain (0..1).
-- UnitPowerPercent(unit, pt, false, curve) evaluates the possibly secret
-- percent C-side and returns a plain colour (the curve is ours). Steps are
-- epsilon pairs. "below": band k covers (p_k-1, p_k], the lowest from 0, the
-- base above the last; "above": band k covers [p_k, p_k+1), the base below
-- the first. The full colour is a final step at 1.0. Cached by recipe.
local function ResourceCurve(entry)
    local rec = entry.rec
    local on = R(rec, "powerthresholds", "pthEnabled") == true
    local fullOn = R(rec, "powerthresholds", "pthFullEnabled") == true
    if not (on or fullOn) then
        entry.pthCurve, entry.pthHash = nil, nil
        return nil
    end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and UnitPowerPercent) then
        return nil
    end
    local br, bg, bb = PowerColorOf(rec, entry.powerType)
    local base = { br, bg, bb, 1 }
    local below = (R(rec, "powerthresholds", "pthDirection") or "below") ~= "above"
    local bands = {}
    -- Percent by default; "power units" convert through the plain cached max,
    -- so the value never reaches Lua. No plain max yet means no bands until the
    -- first unrestricted refresh brings one (the range change re-enters here).
    local absolute = R(rec, "powerthresholds", "pthAbsolute") == true
    local domain = absolute and Bars.PlainMax(entry) or 100
    if on and domain and domain > 0 then
        for i = 2, 1 + BandCount(rec, "powerthresholds", "pthCount") do
            local v = R(rec, "powerthresholds", "pth" .. i .. "Value") or 0
            local p = v / domain
            if p > 0 and p < 1 then
                bands[#bands + 1] = { p = p,
                    color = R(rec, "powerthresholds", "pth" .. i .. "Color") or { 1, 1, 1, 1 } }
            end
        end
        table.sort(bands, function(a, b) return a.p < b.p end)
        local dd = {}
        for _, b in ipairs(bands) do
            if dd[#dd] and math.abs(dd[#dd].p - b.p) < 0.0005 then dd[#dd] = b else dd[#dd + 1] = b end
        end
        bands = dd
    end
    local full = fullOn and (R(rec, "powerthresholds", "pthFullColor") or { 0, 1, 0, 1 }) or nil
    local hash = (below and "b" or "a") .. (absolute and ("u" .. tostring(domain)) or "")
        .. string.format("|%.2f,%.2f,%.2f", base[1], base[2], base[3])
    for _, b in ipairs(bands) do
        hash = hash .. string.format("|%.3f:%.2f,%.2f,%.2f", b.p, b.color[1], b.color[2], b.color[3])
    end
    if full then hash = hash .. string.format("|F%.2f,%.2f,%.2f", full[1], full[2], full[3]) end
    if entry.pthCurve and entry.pthHash == hash then return entry.pthCurve end

    local EPS = 0.0001
    local curve = C_CurveUtil.CreateColorCurve()
    local function P(x, c) curve:AddPoint(x, CreateColor(c[1], c[2], c[3], c[4] or 1)) end
    if below then
        P(0, bands[1] and bands[1].color or base)
        for i = 1, #bands do
            P(bands[i].p, bands[i].color)
            P(bands[i].p + EPS, bands[i + 1] and bands[i + 1].color or base)
        end
        if full then P(1 - EPS, base) end
        P(1, full or base)
    else
        P(0, base)
        for i = 1, #bands do
            P(bands[i].p - EPS, bands[i - 1] and bands[i - 1].color or base)
            P(bands[i].p, bands[i].color)
        end
        local top = bands[#bands] and bands[#bands].color or base
        if full then P(1 - EPS, top) end
        P(1, full or top)
    end
    entry.pthCurve, entry.pthHash = curve, hash
    return curve
end

-- the fill colour for this refresh: the power colour, or the curve's answer
-- (a plain colour object; its components are guarded anyway)
local function ResourceColor(entry)
    local rec = entry.rec
    local r, g, b, a = PowerColorOf(rec, entry.powerType)
    local curve = ResourceCurve(entry)
    if curve then
        local col = UnitPowerPercent("player", entry.powerType, false, curve)
        if col ~= nil and type(col) ~= "number" and col.GetRGB then
            local cr, cg, cb = col:GetRGB()
            if cr ~= nil and not (issecretvalue and issecretvalue(cr)) then
                r, g, b, a = cr, cg, cb, 1
            end
        end
    end
    return r, g, b, a, curve ~= nil
end

-- Power can read secret, and a rule formatter's FormatNumber takes a secret
-- only from untainted code (it threw on mana in combat). These two C_StringUtil
-- calls take secrets from addon code, so the text is rounded and joined C-side.
local function SecretSafeText(v, suffix)
    local SU = C_StringUtil
    if not (SU and SU.RoundToNearestString and SU.WrapString) then return nil end
    return SU.WrapString(SU.RoundToNearestString(v), nil, suffix)
end

-- "47%": the client scales the value through a 0..100 curve first
local pctCurve
local function PercentText(pt)
    if not (UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    if not pctCurve then
        pctCurve = C_CurveUtil.CreateCurve()
        pctCurve:AddPoint(0, 0)
        pctCurve:AddPoint(1, 100)
    end
    local v = UnitPowerPercent("player", pt, false, pctCurve)
    if v == nil then return nil end
    return SecretSafeText(v, "%")
end

-- "1234 / 5000": the range is plain (the cached max)
local function ValueMaxText(cur, range)
    return SecretSafeText(cur, " / " .. tostring(range))
end

-- The resource readouts: text 1 ("res"), then 2 and 3 as the count allows,
-- each with its own format; every path hands the value straight to a sink.
local RES_RUNS = {
    { key = "res",  fmt = "resFormat",  n = 1 },
    { key = "res2", fmt = "res2Format", n = 2 },
    { key = "res3", fmt = "res3Format", n = 3 },
}

local function ResourceRunText(entry, key, fmt, cur, range)
    local shell = entry.shell
    if fmt == "none" then
        SetRunText(shell, key, "")
        return
    end
    if fmt == "abbreviated" and AbbreviateNumbers then
        SetRunText(shell, key, AbbreviateNumbers(cur))   -- takes secrets
        return
    elseif fmt == "percent" then
        local s = PercentText(entry.powerType)
        if s ~= nil then SetRunText(shell, key, s) return end
    elseif fmt == "valuemax" then
        local s = ValueMaxText(cur, range)
        if s ~= nil then SetRunText(shell, key, s) return end
    end
    SetRunText(shell, key, cur)   -- the raw value is always a legal SetText
end

local function ResourceText(entry, cur, range)
    local rec = entry.rec
    local count = R(rec, "text", "resCount") or 1
    for _, run in ipairs(RES_RUNS) do
        if run.n <= count then
            ResourceRunText(entry, run.key, R(rec, "text", run.fmt) or "value", cur, range)
        end
    end
end

-- The cell count of a pips resource bar: the plain max while it is a small
-- count (combo points 5, not mana 5000). Resource bars have no typed count.
local function ResourceSegmentCount(entry, range)
    return (range and range >= 2 and range <= 20) and math.floor(range) or 1
end

-- The current value. Combo points on Forever are target-bound (classic rules):
-- GetComboPoints("player", "target"), refreshed on PLAYER_TARGET_CHANGED since
-- a target swap fires no power event. Everything else is UnitPower. Both can be
-- secret, so the value only ever goes into a sink.
local function ResourceCurrent(pt)
    if pt == 4 and NS.IsForever == true and GetComboPoints then
        return GetComboPoints("player", "target")
    end
    return UnitPower("player", pt)
end

-- Pips: one cell per point; the bar's own background, border, fill and sheen
-- stand down (ApplyStyle). Each cell, from the back: a border texture, a
-- background texture inset by the border thickness, a dim texture (the point
-- colour at the "Empty pip tint"), and on its own frame the lit StatusBar with
-- the window (i-0.5, i), fed the possibly secret value so the widget renders it
-- full or empty with no read. A detector width piped into a frame alpha would
-- lag a step (the width only moves at layout). Shapes: square, circle (portrait
-- alpha mask), diamond (rotated 45 degrees at 1/sqrt(2)). No border styles.
local PIP_CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function EnsurePip(entry, i)
    entry.pips = entry.pips or {}
    local p = entry.pips[i]
    if p then return p end
    local shell = entry.shell
    if not entry.pipHost then
        entry.pipHost = CreateFrame("Frame", nil, shell)
        entry.pipHost:SetAllPoints(shell.fill)
        entry.pipHost:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
    end
    local f = CreateFrame("Frame", nil, entry.pipHost)
    local border = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    local dim = f:CreateTexture(nil, "ARTWORK")
    -- the lit layer: a StatusBar whose window (i-0.5, i) turns the fed value
    -- into full / empty with no Lua read (the charge-slot model)
    local litBar = CreateFrame("StatusBar", nil, f)
    litBar:SetFrameLevel(f:GetFrameLevel() + 1)
    litBar:SetStatusBarTexture(WHITE)
    litBar:SetMinMaxValues(i - 0.5, i)
    litBar:SetValue(0)
    -- masks live on the frame that owns the texture they clip
    local maskOuter = f:CreateMaskTexture()
    local maskInner = f:CreateMaskTexture()
    local maskLit = litBar:CreateMaskTexture()
    border:AddMaskTexture(maskOuter)
    bg:AddMaskTexture(maskInner)
    dim:AddMaskTexture(maskInner)
    p = { f = f, border = border, bg = bg, dim = dim, litBar = litBar,
        maskOuter = maskOuter, maskInner = maskInner, maskLit = maskLit }
    entry.pips[i] = p
    return p
end

-- the colour of pip i of n: the max colour on the last cell, else the
-- position band it falls in (stack colours), else this refresh's bar colour
local function PipColor(entry, i, n, r, g, b)
    local rec = entry.rec
    if i == n and R(rec, "stackcolors", "maxColorEnabled") == true then
        local c = R(rec, "stackcolors", "maxColor") or { 0, 1, 0, 1 }
        return c[1], c[2], c[3]
    end
    if R(rec, "stackcolors", "scEnabled") == true then
        local bands = StackBands(rec, n)
        if bands then
            for k = #bands, 1, -1 do
                if i >= bands[k].from then
                    local c = bands[k].color
                    return c[1], c[2], c[3]
                end
            end
        end
    end
    return r, g, b
end

-- Colours only: lit or unlit comes from the value fed to each lit bar.
local function PaintPips(entry)
    local n = entry.pipCount or 0
    if n == 0 then return end
    local r, g, b = entry.cr, entry.cg, entry.cb
    if not r then r, g, b = PowerColorOf(entry.rec, entry.powerType) end
    local tint = R(entry.rec, "resource", "pipEmptyTint")
    if tint == nil then tint = 0 end
    for i = 1, n do
        local p = entry.pips[i]
        local pr, pg, pb = PipColor(entry, i, n, r, g, b)
        p.litBar:SetStatusBarColor(pr, pg, pb, 1)
        p.dim:SetVertexColor(pr, pg, pb, tint)
    end
end

-- Geometry, dress and shape for every cell, on size or setting changes only:
-- the Border and Background blocks dress each cell, the Fill texture lights it.
local function LayoutPips(entry)
    local rec, shell = entry.rec, entry.shell
    local on = R(rec, "resource", "style") == "pips"
    entry.pipsOn = on
    if not on then
        for _, p in ipairs(entry.pips or {}) do p.f:Hide() end
        entry.pipCount = 0
        return
    end
    local fill = shell.fill
    local range = Bars.PlainMax(entry)
    local n = ResourceSegmentCount(entry, range)
    if n > 20 then n = 20 elseif n < 1 then n = 1 end
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local px = Px(shell)
    -- Whole pixels throughout: the bar's scale multiplies the cell sizes, which
    -- would put edges on fractional pixels and soften them. Square textures
    -- anchor at the cell's corner with pixel offsets; circles and diamonds keep
    -- the centre anchor (rotation and the mask need it; their edges are soft).
    local function P(v) return math.max(px, math.floor(v / px + 0.5) * px) end
    local gap = math.floor((px * (R(rec, "resource", "pipSpacing") or 4)) / px + 0.5) * px
    local sc = R(rec, "size", "scale") or 1
    local pw = P(px * (R(rec, "resource", "pipWidth") or 28) * sc)
    local ph = P(px * (R(rec, "resource", "pipHeight") or 28) * sc)
    local along = vertical and ph or pw
    local cross = vertical and pw or ph
    local envAlong = along * n + gap * (n - 1)
    -- The pips size the bar (Bar Size is hidden in this style) to the row of
    -- cells plus gaps. A CENTER-anchored frame grows around its centre and can
    -- land its corner on a half pixel, so the corner is re-snapped the way the
    -- engine's SnapPlacement does, unless an anchor owns the position.
    local holder = entry.holder
    -- pinned to a nameplate (secret rect): the rebuild already sized it free
    if holder and not Bars.RectHidden(holder) then
        local wantW = vertical and cross or envAlong
        local wantH = vertical and envAlong or cross
        local hw, hh = holder:GetWidth() or 0, holder:GetHeight() or 0
        if math.abs(hw - wantW) > 0.5 or math.abs(hh - wantH) > 0.5 then
            holder:SetSize(wantW, wantH)
            if not (NS.Anchor and NS.Anchor.IsEnabled and NS.Anchor.IsEnabled(rec))
                and holder:GetNumPoints() == 1 then
                local pt, relTo, relPt, ox, oy = holder:GetPoint(1)
                local l, b = holder:GetLeft(), holder:GetBottom()
                if pt and relTo and l and b then
                    local dx = l - math.floor(l / px + 0.5) * px
                    local dy = b - math.floor(b / px + 0.5) * px
                    if dx ~= 0 or dy ~= 0 then
                        holder:SetPoint(pt, relTo, relPt, (ox or 0) - dx, (oy or 0) - dy)
                    end
                end
            end
        end
    end
    -- The cells need no rect: they anchor to the pip host (the fill, spanning
    -- the frame in pips style) at offsets known here, so they are right as soon
    -- as the frame has its size. The fill's rect reads 0 until layout runs.
    local cell = along
    local shape = R(rec, "resource", "pipShape") or "square"
    local square = shape == "square"
    local rot = (shape == "diamond") and (math.pi / 4) or 0
    local borderOn = R(rec, "look", "borderEnabled") ~= false
    local bc = R(rec, "look", "borderColor") or { 0.114, 0.165, 0.247, 1 }
    if R(rec, "look", "useClassColorBorder") == true then
        local _, tag = UnitClass("player")
        local cc = tag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
        if cc then bc = { cc.r, cc.g, cc.b, 1 } end
    end
    local th = borderOn and P(px * (R(rec, "look", "borderThickness") or 1)) or 0
    -- a border that would swallow the cell leaves one pixel of inside
    if th * 2 >= math.min(pw, ph) then
        th = math.max(0, math.floor((math.min(pw, ph) - px) / 2 / px) * px)
    end
    local bgShow = R(rec, "look", "bgShow") ~= false
    local bgC = R(rec, "look", "bgColor") or { 0.039, 0.067, 0.125, 1 }
    local bgA = bgShow and (R(rec, "look", "bgAlpha") or 1) or 0
    local bgKey = R(rec, "look", "bgTexture")
    local fillPath = ResolveBarTexture(R(rec, "fill", "texture"))
    local bgPath = ResolveBarTexture((bgKey == nil or bgKey == "") and R(rec, "fill", "texture") or bgKey)
    local maskPath = (shape == "circle") and PIP_CIRCLE_MASK or WHITE
    fill:SetValue(0)
    for i = 1, n do
        local p = EnsurePip(entry, i)
        local at = (i - 1) * (cell + gap)
        p.f:ClearAllPoints()
        -- corner anchors, never LEFT / BOTTOM: a centred anchor halves an
        -- odd size difference into a half pixel
        if vertical then
            p.f:SetSize(cross, cell)
            if rev then
                p.f:SetPoint("TOPLEFT", entry.pipHost, "TOPLEFT", 0, -at)
            else
                p.f:SetPoint("BOTTOMLEFT", entry.pipHost, "BOTTOMLEFT", 0, at)
            end
        else
            p.f:SetSize(cell, cross)
            if rev then
                p.f:SetPoint("TOPRIGHT", entry.pipHost, "TOPRIGHT", -at, 0)
            else
                p.f:SetPoint("TOPLEFT", entry.pipHost, "TOPLEFT", at, 0)
            end
        end
        -- outer size: a square is the cell; a circle the smaller side; a
        -- diamond that side scaled so its corners touch the cell's edges
        local cw, chh = (vertical and cross or cell), (vertical and cell or cross)
        local ow, oh
        if square then
            ow, oh = cw, chh
        else
            local s = P(math.min(cw, chh) * ((shape == "diamond") and 0.7071 or 1))
            ow, oh = s, s
        end
        local iw, ih = math.max(px, ow - 2 * th), math.max(px, oh - 2 * th)
        local function PlaceTex(t, w, h, inset)
            t:ClearAllPoints()
            if square then
                t:SetPoint("TOPLEFT", p.f, "TOPLEFT", inset, -inset)
            else
                t:SetPoint("CENTER", p.f, "CENTER", 0, 0)
            end
            t:SetSize(w, h)
            t:SetRotation(rot)
        end
        PlaceTex(p.border, ow, oh, 0)
        p.border:SetTexture(WHITE)
        p.border:SetVertexColor(bc[1], bc[2], bc[3], borderOn and (bc[4] or 1) or 0)
        PlaceTex(p.bg, iw, ih, th)
        PlaceTex(p.dim, iw, ih, th)
        p.bg:SetTexture(bgPath)
        p.bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgA)
        p.dim:SetTexture(fillPath)
        -- the lit bar fills the inset rect; swapping its texture makes a new
        -- texture object, so the mask and rotation go on whatever is current
        local lb = p.litBar
        lb:ClearAllPoints()
        if square then
            lb:SetPoint("TOPLEFT", p.f, "TOPLEFT", th, -th)
        else
            lb:SetPoint("CENTER", p.f, "CENTER", 0, 0)
        end
        lb:SetSize(iw, ih)
        lb:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        lb:SetReverseFill(rev)
        if p.litPath ~= fillPath then
            p.litPath = fillPath
            lb:SetStatusBarTexture(fillPath)
        end
        local lt = lb:GetStatusBarTexture()
        if p.litTex ~= lt then
            p.litTex = lt
            lt:AddMaskTexture(p.maskLit)
        end
        lt:SetRotation(rot)
        lb:SetMinMaxValues(i - 0.5, i)
        -- Masks: the circle mask on circles, else plain white oversized by a
        -- pixel each side, so a mask edge never sits on the texture's edge
        -- (that softens it). A bilinear mask fades its outer half texel across
        -- the cell (an 8x8 mask blurs about 4px of a 60px cell), so squares
        -- sample NEAREST; the circle keeps its smooth edge, and a diamond's
        -- rotated edge resamples either way.
        for _, m in ipairs({ p.maskOuter, p.maskInner, p.maskLit }) do
            m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE",
                square and "NEAREST" or "LINEAR")
            m:ClearAllPoints()
            m:SetRotation(rot)
        end
        if square then
            p.maskOuter:SetPoint("TOPLEFT", p.f, "TOPLEFT", -px, px)
            p.maskOuter:SetSize(ow + 2 * px, oh + 2 * px)
            p.maskInner:SetPoint("TOPLEFT", p.f, "TOPLEFT", th - px, -(th - px))
            p.maskInner:SetSize(iw + 2 * px, ih + 2 * px)
            p.maskLit:SetPoint("TOPLEFT", lb, "TOPLEFT", -px, px)
            p.maskLit:SetSize(iw + 2 * px, ih + 2 * px)
        else
            p.maskOuter:SetPoint("CENTER", p.f, "CENTER", 0, 0)
            p.maskOuter:SetSize(ow, oh)
            p.maskInner:SetPoint("CENTER", p.f, "CENTER", 0, 0)
            p.maskInner:SetSize(iw, ih)
            p.maskLit:SetPoint("CENTER", lb, "CENTER", 0, 0)
            p.maskLit:SetSize(iw, ih)
        end
        p.f:Show()
    end
    for i = n + 1, #(entry.pips or {}) do entry.pips[i].f:Hide() end
    entry.pipCount = n
    PaintPips(entry)
end

-- The per-tick path: max, colour, value and text only; re-running visibility
-- and layout per power tick costs idle CPU. Setters are memoised; segments,
-- ticks and the cost preview re-lay only when the plain max changes.
local function ResourceRefresh(entry)
    local shell, rec = entry.shell, entry.rec
    local pt = entry.powerType
    if not pt then return end

    local maxv = UnitPowerMax("player", pt)
    if maxv ~= nil and not (issecretvalue and issecretvalue(maxv)) and maxv > 0 then
        cachedMax[pt] = maxv
    end
    local range = cachedMax[pt] or 100
    if entry.lastMax ~= range then
        entry.lastMax = range
        shell.fill:SetMinMaxValues(0, range)
        -- No dividers on a resource bar: tick marks are its per-point marks,
        -- and a pips bar draws its own cells.
        if entry.segments ~= 1 then
            entry.segments = 1
            LayoutDividers(shell, rec, 1)
        end
        LayoutPips(entry)
        LayoutTicks(entry)
        PredictLayout(entry)
    end

    local r, g, b, a, curved = ResourceColor(entry)
    if entry.cr ~= r or entry.cg ~= g or entry.cb ~= b then
        entry.cr, entry.cg, entry.cb = r, g, b
        shell.fill:SetStatusBarColor(r, g, b, a)
        if entry.pipsOn then PaintPips(entry) end
        -- "colour the text too" rides the same answer, on every readout;
        -- off = each text's own colour
        local tinted = curved and R(rec, "powerthresholds", "pthText") == true
        for _, run in ipairs(RES_RUNS) do
            local fs = shell.texts[run.key]
            if fs then
                if tinted then
                    fs:SetTextColor(r, g, b, 1)
                else
                    local c = R(rec, "text", TEXT_DEF_BY_KEY[run.key].colour) or { 0.95, 0.97, 1, 1 }
                    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                end
            end
        end
    end

    local cur = ResourceCurrent(pt)
    if cur == nil then return end
    -- Displayed, never compared; smoothing is the engine's interpolation.
    -- Pips keep the continuous fill empty and light their cells instead.
    if not entry.pipsOn then
        local interp = (R(rec, "fill", "smoothing") ~= false) and INTERP_SMOOTH or INTERP_NONE
        if interp then shell.fill:SetValue(cur, interp) else shell.fill:SetValue(cur) end
    end
    ResourceText(entry, cur, range)
    if entry.pipsOn then
        -- the value straight into every lit bar: the widget lights the cell
        -- whose window it falls in, nothing is read back
        for i = 1, entry.pipCount or 0 do
            local p = entry.pips[i]
            if p then p.litBar:SetValue(cur) end
        end
    end
    -- Cost icons: the value into every detector, each detector's width into its
    -- lit copy's alpha (never compared). The width moves at layout, one tick
    -- after SetValue, so it is read now and again on the next frame.
    if entry.costIconsOn then
        for i = 1, entry.costIconCount or 0 do
            local ci = entry.costIcons[i]
            if ci then
                ci.det:SetValue(cur)
                ci.lit:SetAlpha(ci.detTex:GetWidth() or 1)
            end
        end
        if NS.Events and NS.Events.Coalesce then
            NS.Events.Coalesce("adbars_cost_" .. tostring(rec.id), function()
                if not entry.costIconsOn then return end
                for i = 1, entry.costIconCount or 0 do
                    local ci = entry.costIcons[i]
                    if ci then ci.lit:SetAlpha(ci.detTex:GetWidth() or 1) end
                end
            end)
        end
    end
end

-- full (re)setup for one resource bar: type, range, segments, ticks, colour
local function ResourceEnsure(entry)
    ResourceSyncType(entry)
    entry.lastMax = nil      -- re-derive the range: segments, ticks, preview
    entry.cr, entry.cg, entry.cb = nil, nil, nil
    entry.pthCurve, entry.pthHash = nil, nil
    ResourceRefresh(entry)
    entry.stateHidden = false
    ApplyVisibility(entry)
    EnsurePredictEvents()
end

local function ResourceIsFrequent(entry)
    local info = POWER_ALL[entry.powerType]
    return (info and info.frequent) == true
end

-- Spell costs: plain numbers (GetSpellPowerCost is not secret)
local function SpellCostFor(spellID, pt)
    if not (spellID and pt and C_Spell.GetSpellPowerCost) then return nil end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return nil end
    for _, c in ipairs(costs) do
        if c.type == pt then
            local v = c.cost
            if v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "number" and v > 0 then
                return v
            end
        end
    end
    return nil
end

-- the "cost ticks" spell list resolved against this bar's power: one
-- { id, cost, frac } per spell that costs it (re-laid on SPELLS_CHANGED)
function ResourceCostList(entry, range)
    if not range or range <= 0 then return nil end
    local list = R(entry.rec, "ticks", "tickSpells") or ""
    if list == "" then return nil end
    local out = {}
    for id in tostring(list):gmatch("%d+") do
        local sid = tonumber(id)
        local cost = SpellCostFor(sid, entry.powerType)
        if cost then out[#out + 1] = { id = sid, cost = cost, frac = cost / range } end
    end
    if #out == 0 then return nil end
    return out
end

function ResourceCostFractions(entry, range)
    local items = ResourceCostList(entry, range)
    if not items then return nil end
    local out = {}
    for i, it in ipairs(items) do out[i] = it.frac end
    return out
end

-- Spell cost preview: on UNIT_SPELLCAST_START (the player's casts are not
-- secret) the spell's cost becomes a texture anchored to the fill edge, which
-- the engine places from the secret value, running back by cost/max; a clipping
-- host keeps it inside the bar. Instant casts never start, so they never draw.
local predictArmed = false

function PredictLayout(entry)
    local shell, rec = entry.shell, entry.rec
    if Bars.RectHidden(shell.fill) then return end   -- pinned to a nameplate
    local cost = entry.predCost
    local tex = entry.predTex
    if not cost or R(rec, "predict", "predictEnabled") ~= true then
        if tex then tex:Hide() end
        return
    end
    local range = entry.lastMax or (entry.powerType and cachedMax[entry.powerType]) or 0
    local fill = shell.fill
    local W, H = fill:GetWidth() or 0, fill:GetHeight() or 0
    if range <= 0 or W <= 1 or H <= 1 then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        local clip = CreateFrame("Frame", nil, shell)
        clip:SetAllPoints(fill)
        clip:SetFrameLevel(fill:GetFrameLevel() + 1)
        clip:SetClipsChildren(true)
        tex = clip:CreateTexture(nil, "ARTWORK")
        entry.predClip, entry.predTex = clip, tex
    end
    local c = R(rec, "predict", "predictColor") or { 1, 1, 1, 1 }
    tex:SetColorTexture(c[1], c[2], c[3], R(rec, "predict", "predictAlpha") or 0.5)
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local frac = math.min(1, cost / range)
    local ft = shell.fillTex
    tex:ClearAllPoints()
    if vertical then
        tex:SetSize(W, math.max(1, H * frac))
        if rev then tex:SetPoint("BOTTOM", ft, "BOTTOM") else tex:SetPoint("TOP", ft, "TOP") end
    else
        tex:SetSize(math.max(1, W * frac), H)
        if rev then tex:SetPoint("LEFT", ft, "LEFT") else tex:SetPoint("RIGHT", ft, "RIGHT") end
    end
    tex:Show()
end

local function PredictStart(spellID)
    ForEach("resource", function(e)
        if R(e.rec, "predict", "predictEnabled") == true then
            e.predCost = SpellCostFor(spellID, e.powerType)
            PredictLayout(e)
        end
    end)
end

local function PredictClear()
    ForEach("resource", function(e)
        if e.predCost then
            e.predCost = nil
            PredictLayout(e)
        end
    end)
end

local function AnyPredict()
    for _, e in pairs(live) do
        if e.kind == "resource" and R(e.rec, "predict", "predictEnabled") == true then return true end
    end
    return false
end

local PREDICT_END_EVENTS = { "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

-- armed only while a resource bar wants the preview; own subscriber key, so
-- the shared "adbars" cast handler is untouched
function EnsurePredictEvents()
    if predictArmed or not AnyPredict() then return end
    predictArmed = true
    SafeOn("UNIT_SPELLCAST_START", "adbarspred", function(_, unit, _, spellID)
        if unit == "player" then PredictStart(spellID) end
    end)
    for _, ev in ipairs(PREDICT_END_EVENTS) do
        SafeOn(ev, "adbarspred", function(_, unit)
            if unit == "player" then PredictClear() end
        end)
    end
end

local function ReleasePredictEvents()
    if not predictArmed or AnyPredict() then return end
    predictArmed = false
    Events.Off("UNIT_SPELLCAST_START", "adbarspred")
    for _, ev in ipairs(PREDICT_END_EVENTS) do Events.Off(ev, "adbarspred") end
end

-- Health runtime: one unit's health (rec.driver.unit) with incoming heals,
-- absorb shields and heal absorbs drawn against it. On Forever everything it
-- reads can be secret: UnitHealth, UnitHealthPercent and heal or absorb
-- amounts always, UnitHealthMax for units that are not player-controlled,
-- UnitExists in combat (the docs call it plain). Nothing is compared or
-- truth-tested; values only go into secret-safe sinks. NumericRuleFormatter's
-- FormatNumber is untainted-only: never pass it health. Target of target is
-- not offered (no events; it would need polling). One table (HB): near the
-- 200-local limit.

local HB = {}
HB.KEY = "adbarshp"
HB.PREVIEW = 0.65        -- the edit-session preview: this much health
HB.EPS = 0.0001          -- curve step width (curves interpolate)
HB.SHIELD_FILL = "Interface\\RaidFrame\\Shield-Fill"
HB.SHIELD_STRIPES = "Interface\\RaidFrame\\Shield-Overlay"
HB.SHIELD_GLOW = "Interface\\RaidFrame\\Shield-Overshield"
HB.PREVIEW_NAMES = { player = "Player", target = "Target", focus = "Focus", pet = "Pet",
    party1 = "Party 1", party2 = "Party 2", party3 = "Party 3", party4 = "Party 4" }

function HB.Unit(entry)
    local d = entry.rec.driver
    return (d and d.unit) or "player"
end

function HB.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The unit is plainly not there (edit-session preview only; a secret answer
-- never counts as missing).
function HB.Missing(unit)
    if unit == "player" then return false end
    local ex = UnitExists(unit)
    if issecretvalue and issecretvalue(ex) then return false end
    return not ex
end

-- 0..1 -> 0..100 for the percent text (Blizzard's own constant when present)
function HB.Scale()
    if HB.scale == nil then
        if CurveConstants and CurveConstants.ScaleTo100 then
            HB.scale = CurveConstants.ScaleTo100
        elseif C_CurveUtil and C_CurveUtil.CreateCurve then
            local c = C_CurveUtil.CreateCurve()
            c:AddPoint(0, 0)
            c:AddPoint(1, 100)
            HB.scale = c
        else
            HB.scale = false
        end
    end
    return HB.scale or nil
end

-- Colour sources
function HB.ClassColor(unit)
    local _, token = UnitClass(unit)
    if token == nil then return nil end
    if not (issecretvalue and issecretvalue(token)) then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        return c and CreateColor(c.r, c.g, c.b, 1) or nil
    end
    -- a secret class token: the class colour API takes it as-is
    if C_ClassColor and C_ClassColor.GetClassColor then
        return C_ClassColor.GetClassColor(token)
    end
    return nil
end

-- reaction (hostile / neutral / friendly), grey when another player tapped
-- it; a secret reaction falls back to the selection colour, a pure sink
function HB.ReactionColor(unit)
    local pc = HB.Plain(UnitPlayerControlled and UnitPlayerControlled(unit))
    local td = HB.Plain(UnitIsTapDenied and UnitIsTapDenied(unit))
    if pc == false and td == true then return CreateColor(0.5, 0.5, 0.5, 1) end
    local r = HB.Plain(UnitReaction and UnitReaction(unit, "player"))
    local c = r and FACTION_BAR_COLORS and FACTION_BAR_COLORS[r]
    if c then return CreateColor(c.r, c.g, c.b, 1) end
    if UnitSelectionColor then return CreateColor(UnitSelectionColor(unit)) end
    return nil
end

-- the gradient: empty -> half -> full, plain colours, cached by recipe
function HB.GradientCurve(entry)
    local rec = entry.rec
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local lo = R(rec, "fill", "gradLowColor") or { 1, 0.15, 0.15, 1 }
    local mid = R(rec, "fill", "gradMidColor") or { 1, 0.82, 0.1, 1 }
    local hi = R(rec, "fill", "gradHighColor") or { 0.2, 0.85, 0.3, 1 }
    local hash = string.format("%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f",
        lo[1], lo[2], lo[3], mid[1], mid[2], mid[3], hi[1], hi[2], hi[3])
    if entry.hpGrad and entry.hpGradHash == hash then return entry.hpGrad end
    local c = C_CurveUtil.CreateColorCurve()
    c:AddPoint(0, CreateColor(lo[1], lo[2], lo[3], 1))
    c:AddPoint(0.5, CreateColor(mid[1], mid[2], mid[3], 1))
    c:AddPoint(1, CreateColor(hi[1], hi[2], hi[3], 1))
    entry.hpGrad, entry.hpGradHash = c, hash
    return c
end

-- the fill colour for this refresh, painted straight onto the fill. Every
-- path ends in a setter that takes secrets; nothing is read back.
function HB.PaintBase(entry, unit, preview)
    local rec, fill = entry.rec, entry.shell.fill
    local mode = R(rec, "fill", "colorMode") or "fill"
    local col
    if mode == "gradient" then
        local curve = HB.GradientCurve(entry)
        if curve then
            if preview then col = curve:Evaluate(HB.PREVIEW)
            else col = UnitHealthPercent(unit, true, curve) end
        end
    elseif mode == "class" then
        if unit == "player" or preview then
            col = HB.ClassColor("player")
        else
            -- class for a player, reaction for a creature; an unknown
            -- (secret) answer picks between the two C-side
            local isPlayer = UnitIsPlayer(unit)
            local cc, rc = HB.ClassColor(unit), HB.ReactionColor(unit)
            if issecretvalue and issecretvalue(isPlayer) then
                local tex = entry.shell.fillTex
                if cc and rc and tex.SetVertexColorFromBoolean then
                    tex:SetVertexColorFromBoolean(isPlayer, cc, rc)
                    return
                end
                col = rc or cc
            elseif isPlayer then
                col = cc or rc
            else
                col = rc
            end
        end
    elseif mode == "reaction" then
        if preview then
            local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[2]
            col = CreateColor(c and c.r or 1, c and c.g or 0.1, c and c.b or 0.1, 1)
        else
            col = HB.ReactionColor(unit)
        end
    end
    if col and col.GetRGB then
        fill:SetStatusBarColor(col:GetRGB())
    else
        fill:SetStatusBarColor(BarColorOf(rec))
    end
end

-- Threshold bands: textures over the fill, alpha from a step curve.
-- The bands in play, ascending: { p = 0..1, color }; nil when off.
function HB.Bands(rec)
    if R(rec, "healththresholds", "hpthEnabled") ~= true then return nil end
    local list = {}
    for i = 2, 1 + BandCount(rec, "healththresholds", "hpthCount") do
        local v = tonumber(R(rec, "healththresholds", "hpth" .. i .. "Value")) or 0
        if v > 0 and v < 100 then
            list[#list + 1] = { p = v / 100,
                color = R(rec, "healththresholds", "hpth" .. i .. "Color") or { 1, 0, 0, 1 } }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.p < b.p end)
    local dd = {}
    for _, b in ipairs(list) do
        if dd[#dd] and math.abs(dd[#dd].p - b.p) < 0.0005 then dd[#dd] = b else dd[#dd + 1] = b end
    end
    return dd
end

-- (Re)build the band textures and their alpha curves. The textures live on the
-- fill, under the sheen, covering the fill texture, so a band paints only the
-- filled part. "Below": the lowest band that holds wins; "above": the highest.
function HB.BuildBands(entry)
    local rec, shell = entry.rec, entry.shell
    local bands = HB.Bands(rec)
    local below = (R(rec, "healththresholds", "hpthDirection") or "below") ~= "above"
    local texPath = ResolveBarTexture(R(rec, "fill", "texture"))
    entry.hpBandTex = entry.hpBandTex or {}
    local n = (bands and C_CurveUtil and C_CurveUtil.CreateCurve) and #bands or 0
    local hash = (below and "b" or "a") .. texPath
    for k = 1, n do
        local b = bands[k]
        hash = hash .. string.format("|%.3f:%.2f,%.2f,%.2f", b.p, b.color[1], b.color[2], b.color[3])
    end
    if entry.hpBandHash ~= hash then
        entry.hpBandHash = hash
        entry.hpBandCurves = {}
        for k = 1, n do
            local b = bands[k]
            local c = C_CurveUtil.CreateCurve()
            if below then
                c:AddPoint(0, 1)
                c:AddPoint(b.p, 1)
                c:AddPoint(b.p + HB.EPS, 0)
                c:AddPoint(1, 0)
            else
                c:AddPoint(0, 0)
                c:AddPoint(b.p - HB.EPS, 0)
                c:AddPoint(b.p, 1)
                c:AddPoint(1, 1)
            end
            entry.hpBandCurves[k] = c
        end
    end
    for k = 1, n do
        local b = bands[k]
        local t = entry.hpBandTex[k]
        if not t then
            t = shell.fill:CreateTexture(nil, "ARTWORK")
            entry.hpBandTex[k] = t
        end
        t:SetDrawLayer("ARTWORK", below and (1 + n - k) or k)
        -- Re-anchored every pass: a texture swap makes a new fill texture.
        t:ClearAllPoints()
        t:SetAllPoints(shell.fillTex)
        t:SetTexture(texPath)
        t:SetVertexColor(b.color[1], b.color[2], b.color[3], 1)
        t:Show()
    end
    for k = n + 1, #entry.hpBandTex do entry.hpBandTex[k]:Hide() end
    entry.hpBandN = n
end

function HB.PaintBands(entry, unit, preview)
    local curves = entry.hpBandCurves
    for k = 1, entry.hpBandN or 0 do
        local t, c = entry.hpBandTex[k], curves and curves[k]
        if t and c then
            if preview then t:SetAlpha(c:Evaluate(HB.PREVIEW))
            else t:SetAlpha(UnitHealthPercent(unit, true, c)) end
        end
    end
end

-- Health text. "Color the health text too": one colour curve from the text's
-- own colour and the bands (all plain), evaluated from the secret percent.
function HB.TextCurve(entry)
    local rec = entry.rec
    if R(rec, "healththresholds", "hpthText") ~= true then return nil end
    local bands = HB.Bands(rec)
    if not (bands and C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local base = R(rec, "text", "hpColor") or { 0.95, 0.97, 1, 1 }
    local below = (R(rec, "healththresholds", "hpthDirection") or "below") ~= "above"
    local hash = (below and "b" or "a") .. string.format("|%.2f,%.2f,%.2f", base[1], base[2], base[3])
    for _, b in ipairs(bands) do
        hash = hash .. string.format("|%.3f:%.2f,%.2f,%.2f", b.p, b.color[1], b.color[2], b.color[3])
    end
    if entry.hpTextCurve and entry.hpTextHash == hash then return entry.hpTextCurve end
    local curve = C_CurveUtil.CreateColorCurve()
    local function P(x, c) curve:AddPoint(x, CreateColor(c[1], c[2], c[3], c[4] or 1)) end
    if below then
        P(0, bands[1].color)
        for i = 1, #bands do
            P(bands[i].p, bands[i].color)
            P(bands[i].p + HB.EPS, bands[i + 1] and bands[i + 1].color or base)
        end
        P(1, base)
    else
        P(0, base)
        for i = 1, #bands do
            P(bands[i].p - HB.EPS, bands[i - 1] and bands[i - 1].color or base)
            P(bands[i].p, bands[i].color)
        end
        P(1, bands[#bands].color)
    end
    entry.hpTextCurve, entry.hpTextHash = curve, hash
    return curve
end

-- The health readouts: text 1 ("hp"), then 2 and 3 as the count allows.
HB.RUNS = {
    { key = "hp",  fmt = "hpFormat",  n = 1 },
    { key = "hp2", fmt = "hp2Format", n = 2 },
    { key = "hp3", fmt = "hp3Format", n = 3 },
}

function HB.Text(entry, unit, preview)
    local count = R(entry.rec, "text", "hpCount") or 1
    local col
    local curve = HB.TextCurve(entry)
    if curve then
        if preview then col = curve:Evaluate(HB.PREVIEW)
        else col = UnitHealthPercent(unit, true, curve) end
    end
    for _, run in ipairs(HB.RUNS) do
        local fs = entry.shell.texts[run.key]
        if run.n <= count and fs and fs:IsShown() then
            HB.TextRun(fs, R(entry.rec, "text", run.fmt) or "value", unit, preview)
            if col and col.GetRGBA then fs:SetTextColor(col:GetRGBA()) end
        end
    end
end

-- one readout in one format; every live value goes straight into a sink
function HB.TextRun(fs, fmt, unit, preview)
    if fmt == "none" then
        fs:SetText("")
        return
    end
    if preview then
        local max = 10000
        local cur = math.floor(max * HB.PREVIEW + 0.5)
        if fmt == "percent" then fs:SetFormattedText("%.0f%%", HB.PREVIEW * 100)
        elseif fmt == "abbreviated" and AbbreviateNumbers then fs:SetText(AbbreviateNumbers(cur))
        elseif fmt == "valuemax" then fs:SetFormattedText("%d / %d", cur, max)
        else fs:SetText(cur) end
    elseif fmt == "percent" and HB.Scale() and UnitHealthPercent then
        fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, HB.Scale()))
    elseif fmt == "abbreviated" and AbbreviateNumbers then
        fs:SetText(AbbreviateNumbers(UnitHealth(unit)))
    elseif fmt == "valuemax" then
        fs:SetFormattedText("%d / %d", UnitHealth(unit), UnitHealthMax(unit))
    else
        fs:SetText(UnitHealth(unit))
    end
end

-- the Name run on a health bar showing its unit's name (ApplyTexts leaves it
-- alone then): the live name, secret in instances, straight into SetText
function HB.Name(entry, unit, preview)
    local fs = entry.shell.texts.name
    if not (fs and fs:IsShown()) then return end
    if (R(entry.rec, "text", "nameSource") or "unit") ~= "unit" then return end
    if BarCustomName(entry.rec) then return end   -- the custom name owns the run
    if preview then
        fs:SetText(HB.PREVIEW_NAMES[unit] or unit)
    else
        fs:SetText(UnitName(unit))
    end
end

-- Heals, shields, heal absorbs: one calculator per bar. Incoming heals clamp at
-- the missing health (the clip frame ends at the bar's end), shields at what is
-- left after heals (so its clamped flag means "more shield than room"), heal
-- absorbs at the current health. Enum tables are guarded.
function HB.Calc(entry)
    if entry.hpCalc == nil then
        entry.hpCalc = false
        if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
            local c = CreateUnitHealPredictionCalculator()
            if c then
                local E = Enum
                local m = E.UnitIncomingHealClampMode and E.UnitIncomingHealClampMode.MissingHealth
                if m ~= nil and c.SetIncomingHealClampMode then c:SetIncomingHealClampMode(m) end
                if c.SetIncomingHealOverflowPercent then c:SetIncomingHealOverflowPercent(1) end
                m = E.UnitDamageAbsorbClampMode and E.UnitDamageAbsorbClampMode.MissingHealth
                if m ~= nil and c.SetDamageAbsorbClampMode then c:SetDamageAbsorbClampMode(m) end
                m = E.UnitHealAbsorbClampMode and E.UnitHealAbsorbClampMode.CurrentHealth
                if m ~= nil and c.SetHealAbsorbClampMode then c:SetHealAbsorbClampMode(m) end
                entry.hpCalc = c
            end
        end
    end
    return entry.hpCalc or nil
end

-- A status bar texture swap makes a new texture object: cache the path and
-- re-apply exact-edge sampling on the new object.
function HB.SetTex(bar, path)
    if bar._adTex == path then return end
    bar._adTex = path
    bar:SetStatusBarTexture(path)
    local t = bar:GetStatusBarTexture()
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
end

-- the overlay frames, made the first time any overlay is on
function HB.Overlays(entry)
    local o = entry.hpOv
    if o then return o end
    local shell = entry.shell
    local clip = CreateFrame("Frame", nil, shell)
    clip:SetAllPoints(shell.fill)
    clip:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
    clip:SetClipsChildren(true)
    local function Bar(level)
        local b = CreateFrame("StatusBar", nil, clip)
        b:SetFrameLevel(clip:GetFrameLevel() + level)
        HB.SetTex(b, WHITE)
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        return b
    end
    o = { clip = clip }
    o.all = Bar(1)          -- everyone's heals, in the other-heals colour
    o.mine = Bar(2)         -- yours, over the first stretch of the same edge
    o.absorb = Bar(3)       -- shields, after all heals
    o.healAbsorb = Bar(4)   -- heal absorbs, backward from the health edge
    o.stripes = o.absorb:CreateTexture(nil, "ARTWORK", nil, 2)
    -- the over-shield glow sits at the bar's end, outside the clip, under
    -- the texts on the overlay host
    o.glow = shell.overlay:CreateTexture(nil, "ARTWORK", nil, 2)
    o.glow:SetTexture(HB.SHIELD_GLOW)
    o.glow:SetBlendMode("ADD")
    o.glow:SetAlpha(0)
    o.glow:Hide()
    entry.hpOv = o
    return o
end

-- which point of an overlay meets which point of the thing it follows:
-- FWD = past the health edge (heals, shields), BACK = back into the health
-- (heal absorbs); per orientation and fill direction
HB.FWD = {
    H  = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } },
    HR = { { "TOPRIGHT", "TOPLEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" } },
    V  = { { "BOTTOMLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" } },
    VR = { { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } },
}
HB.BACK = {
    H  = { { "TOPRIGHT", "TOPRIGHT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
    HR = { { "TOPLEFT", "TOPLEFT" }, { "BOTTOMLEFT", "BOTTOMLEFT" } },
    V  = { { "TOPLEFT", "TOPLEFT" }, { "TOPRIGHT", "TOPRIGHT" } },
    VR = { { "BOTTOMLEFT", "BOTTOMLEFT" }, { "BOTTOMRIGHT", "BOTTOMRIGHT" } },
}

function HB.Place(bar, anchor, pts, vertical, reverse, W, H)
    bar:ClearAllPoints()
    bar:SetPoint(pts[1][1], anchor, pts[1][2])
    bar:SetPoint(pts[2][1], anchor, pts[2][2])
    if vertical then bar:SetHeight(H) else bar:SetWidth(W) end
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(reverse)
end

-- Geometry, on style and size changes only; skipped until the fill has a size
-- (the resize hook re-runs it).
function HB.Layout(entry)
    local o = entry.hpOv
    if not o then return end
    local shell, rec = entry.shell, entry.rec
    local fill = shell.fill
    if Bars.RectHidden(fill) then return end   -- pinned to a nameplate
    local W, H = fill:GetWidth() or 0, fill:GetHeight() or 0
    if W <= 1 or H <= 1 then return end
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local key = (vertical and "V" or "H") .. (rev and "R" or "")
    local fwd, back = HB.FWD[key], HB.BACK[key]
    local edge = shell.fillTex
    HB.Place(o.all, edge, fwd, vertical, rev, W, H)
    HB.Place(o.mine, edge, fwd, vertical, rev, W, H)
    -- shields start where all heals end (or at the health edge without them)
    local after = o.healOn and o.all:GetStatusBarTexture() or edge
    HB.Place(o.absorb, after, fwd, vertical, rev, W, H)
    HB.Place(o.healAbsorb, edge, back, vertical, not rev, W, H)
    o.stripes:ClearAllPoints()
    o.stripes:SetAllPoints(o.absorb:GetStatusBarTexture())
    -- the glow straddles the bar's far end (Blizzard's 16px, 7 inside)
    local g = o.glow
    g:ClearAllPoints()
    -- Texcoords first: setting them can reset a rotation.
    if vertical then
        g:SetTexCoord(0, 1, 0, 1)
        if g.SetRotation then g:SetRotation(math.pi / 2) end
        if rev then
            g:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 7)
            g:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, 7)
        else
            g:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -7)
            g:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -7)
        end
        g:SetHeight(16)
    else
        if rev then g:SetTexCoord(1, 0, 0, 1) else g:SetTexCoord(0, 1, 0, 1) end
        if g.SetRotation then g:SetRotation(0) end
        if rev then
            g:SetPoint("TOPRIGHT", fill, "TOPLEFT", 7, 0)
            g:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT", 7, 0)
        else
            g:SetPoint("TOPLEFT", fill, "TOPRIGHT", -7, 0)
            g:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", -7, 0)
        end
        g:SetWidth(16)
    end
end

-- colours, textures and which overlays show (style passes only)
function HB.StyleOverlays(entry)
    local rec = entry.rec
    local healOn = R(rec, "healpred", "healShow") == true
    local absOn = R(rec, "healpred", "absorbShow") == true
    local haOn = R(rec, "healpred", "healAbsorbShow") == true
    if not (healOn or absOn or haOn) then
        if entry.hpOv then
            entry.hpOv.clip:Hide()
            entry.hpOv.glow:Hide()
        end
        return
    end
    local o = HB.Overlays(entry)
    o.healOn, o.absOn, o.haOn = healOn, absOn, haOn
    local texPath = ResolveBarTexture(R(rec, "fill", "texture"))
    local rotate = R(rec, "fill", "rotateTexture") == true
    HB.SetTex(o.all, texPath)
    HB.SetTex(o.mine, texPath)
    HB.SetTex(o.healAbsorb, texPath)
    local ha = R(rec, "healpred", "healAlpha") or 0.6
    local mc = R(rec, "healpred", "healMyColor") or { 0.35, 1, 0.55, 1 }
    local oc = R(rec, "healpred", "healOtherColor") or { 0.1, 0.75, 0.4, 1 }
    o.mine:SetStatusBarColor(mc[1], mc[2], mc[3], ha)
    o.all:SetStatusBarColor(oc[1], oc[2], oc[3], ha)
    o.all:SetShown(healOn)
    o.mine:SetShown(healOn)
    local stripes = (R(rec, "healpred", "absorbStyle") or "stripes") == "stripes"
    HB.SetTex(o.absorb, stripes and HB.SHIELD_FILL or texPath)
    local ac = R(rec, "healpred", "absorbColor") or { 0.8, 0.93, 1, 1 }
    local aa = R(rec, "healpred", "absorbAlpha") or 0.55
    o.absorb:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    o.absorb:SetShown(absOn)
    -- the stripes tile at their own size (never stretched, no maths on the
    -- secret width): a plain texture over the shield's fill texture
    o.stripes:SetTexture(HB.SHIELD_STRIPES, "REPEAT", "REPEAT")
    if o.stripes.SetHorizTile then o.stripes:SetHorizTile(true) end
    if o.stripes.SetVertTile then o.stripes:SetVertTile(true) end
    o.stripes:SetVertexColor(ac[1], ac[2], ac[3], math.min(1, aa + 0.25))
    o.stripes:SetShown(absOn and stripes)
    o.glowOn = absOn and R(rec, "healpred", "absorbOverflow") == true
    o.glow:SetVertexColor(ac[1], ac[2], ac[3], 1)
    o.glow:SetShown(o.glowOn)
    local hc = R(rec, "healpred", "healAbsorbColor") or { 0.55, 0.05, 0.2, 1 }
    o.healAbsorb:SetStatusBarColor(hc[1], hc[2], hc[3], R(rec, "healpred", "healAbsorbAlpha") or 0.7)
    o.healAbsorb:SetShown(haOn)
    for _, b in ipairs({ o.all, o.mine, o.absorb, o.healAbsorb }) do b:SetRotatesTexture(rotate) end
    o.clip:Show()
    HB.Layout(entry)
end

-- the amounts, straight into the overlays (every one of them secret)
function HB.Predict(entry, unit, preview)
    local o = entry.hpOv
    if not (o and o.clip:IsShown()) then return end
    local bars = { o.all, o.mine, o.absorb, o.healAbsorb }
    if preview then
        for _, b in ipairs(bars) do b:SetMinMaxValues(0, 1) end
        o.all:SetValue(0.2)
        o.mine:SetValue(0.12)
        o.absorb:SetValue(o.healOn and 0.15 or 0.35)
        o.healAbsorb:SetValue(0.08)
        if o.glowOn then o.glow:SetAlpha(1) end
        return
    end
    local maxv = UnitHealthMax(unit)
    local all, mine, absorb, clamped, healAbsorb
    local calc = HB.Calc(entry)
    if calc then
        UnitGetDetailedHealPrediction(unit, "player", calc)
        all, mine = calc:GetIncomingHeals()
        absorb, clamped = calc:GetDamageAbsorbs()
        healAbsorb = calc:GetHealAbsorbs()
    else
        -- no calculator on this client: the raw amounts, clipped at the end
        all = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
        mine = UnitGetIncomingHeals and UnitGetIncomingHeals(unit, "player")
        absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
        healAbsorb = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)
    end
    -- nil checks only (a secret number is never compared)
    if all == nil then all = 0 end
    if mine == nil then mine = 0 end
    if absorb == nil then absorb = 0 end
    if healAbsorb == nil then healAbsorb = 0 end
    local pm = HB.Plain(maxv)
    if pm ~= nil and pm <= 0 then maxv = 1 end
    for _, b in ipairs(bars) do b:SetMinMaxValues(0, maxv) end
    if o.healOn then
        o.all:SetValue(all)
        o.mine:SetValue(mine)
    end
    if o.absOn then o.absorb:SetValue(absorb) end
    if o.haOn then o.healAbsorb:SetValue(healAbsorb) end
    if o.glowOn then
        if clamped ~= nil and o.glow.SetAlphaFromBoolean then
            o.glow:SetAlphaFromBoolean(clamped, 1, 0)
        else
            o.glow:SetAlpha(0)
        end
    end
end

-- The bar. The shell's alpha follows the unit's existence (the holder's is
-- ApplyVisibility's); always shown for the player and in edit sessions.
function HB.Gate(entry, unit)
    local shell = entry.shell
    if unit == "player" or IsEditMode() then
        shell:SetAlpha(1)
        return
    end
    local ex = UnitExists(unit)
    if issecretvalue and issecretvalue(ex) then
        if shell.SetAlphaFromBoolean then shell:SetAlphaFromBoolean(ex, 1, 0) else shell:SetAlpha(1) end
    else
        shell:SetAlpha(ex and 1 or 0)
    end
end

-- the value pass: every UNIT_HEALTH / UNIT_MAXHEALTH. snap = a new unit
-- (never animate one unit's health into another's)
function HB.Values(entry, snap)
    local shell, rec = entry.shell, entry.rec
    local unit, preview = entry.hpUnit or HB.Unit(entry), entry.hpPreview
    local fill = shell.fill
    if preview then
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(HB.PREVIEW)
    else
        local maxv = UnitHealthMax(unit)
        local pm = HB.Plain(maxv)
        if pm ~= nil then
            if pm <= 0 then
                maxv = 1
            elseif entry.hpMax ~= pm then
                -- the last plain maximum: value / max text and ticks typed
                -- in health points need it; a secret one is fed, never kept
                entry.hpMax = pm
                LayoutTicks(entry)
            end
        end
        fill:SetMinMaxValues(0, maxv)
        local cur = UnitHealth(unit)
        local interp = (R(rec, "fill", "smoothing") ~= false) and INTERP_SMOOTH or nil
        if interp and not snap then
            fill:SetValue(cur, interp)
        else
            fill:SetValue(cur)
            if fill.SetToTargetValue then fill:SetToTargetValue() end
        end
    end
    if (R(rec, "fill", "colorMode") or "fill") == "gradient" then
        HB.PaintBase(entry, unit, preview)
    end
    HB.PaintBands(entry, unit, preview)
    HB.Text(entry, unit, preview)
    HB.Predict(entry, unit, preview)
end

function HB.Refresh(entry, snap)
    local unit = HB.Unit(entry)
    if entry.hpUnit ~= unit then
        entry.hpUnit = unit
        entry.hpMax = nil
        snap = true
    end
    entry.hpPreview = IsEditMode() and HB.Missing(unit) or false
    HB.Gate(entry, unit)
    HB.PaintBase(entry, unit, entry.hpPreview)
    HB.Name(entry, unit, entry.hpPreview)
    HB.Values(entry, snap)
end

-- a different unit behind the same token (new target, new pet, roster)
function HB.Swap(entry)
    entry.hpMax = nil
    HB.Refresh(entry, true)
end

-- style + setup, after ApplyStyle on every rebuild
function HB.Ensure(entry)
    HB.BuildBands(entry)
    HB.StyleOverlays(entry)
    entry.stateHidden = false
    ApplyVisibility(entry)
    HB.Refresh(entry, true)
    HB.Arm()
end

function HB.ForUnit(unit, fn)
    if unit == nil or (issecretvalue and issecretvalue(unit)) then return end
    for _, e in pairs(live) do
        if e.kind == "health" and e.hpUnit == unit then fn(e) end
    end
end

HB.VALUE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
HB.PREDICT_EVENTS = { "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }
HB.LOOK_EVENTS = { "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION" }
HB.SWAP_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET",
    "GROUP_ROSTER_UPDATE" }

-- Armed while any health bar exists, released with the last one. Unit events
-- filter on the payload before any work, and Forever throws on an unknown
-- event name, so every one goes through the probe.
function HB.Arm()
    if HB.armed then return end
    HB.armed = true
    for _, ev in ipairs(HB.VALUE_EVENTS) do
        SafeOn(ev, HB.KEY, function(_, unit) HB.ForUnit(unit, HB.Values) end)
    end
    for _, ev in ipairs(HB.PREDICT_EVENTS) do
        SafeOn(ev, HB.KEY, function(_, unit)
            HB.ForUnit(unit, function(e) HB.Predict(e, e.hpUnit, e.hpPreview) end)
        end)
    end
    for _, ev in ipairs(HB.LOOK_EVENTS) do
        SafeOn(ev, HB.KEY, function(_, unit)
            HB.ForUnit(unit, function(e) HB.PaintBase(e, e.hpUnit, e.hpPreview) end)
        end)
    end
    SafeOn("UNIT_NAME_UPDATE", HB.KEY, function(_, unit)
        HB.ForUnit(unit, function(e) HB.Name(e, e.hpUnit, e.hpPreview) end)
    end)
    SafeOn("PLAYER_TARGET_CHANGED", HB.KEY, function() HB.ForUnit("target", HB.Swap) end)
    SafeOn("PLAYER_FOCUS_CHANGED", HB.KEY, function() HB.ForUnit("focus", HB.Swap) end)
    SafeOn("UNIT_PET", HB.KEY, function(_, unit)
        if unit == "player" then HB.ForUnit("pet", HB.Swap) end
    end)
    SafeOn("GROUP_ROSTER_UPDATE", HB.KEY, function()
        for i = 1, 4 do HB.ForUnit("party" .. i, HB.Swap) end
    end)
end

function HB.Disarm()
    if not HB.armed then return end
    for _, e in pairs(live) do
        if e.kind == "health" then return end
    end
    HB.armed = false
    for _, list in ipairs({ HB.VALUE_EVENTS, HB.PREDICT_EVENTS, HB.LOOK_EVENTS, HB.SWAP_EVENTS }) do
        for _, ev in ipairs(list) do Events.Off(ev, HB.KEY) end
    end
    Events.Off("UNIT_NAME_UPDATE", HB.KEY)
end

-- Swing runtime: C_SwingTimer (Forever), capability-probed; see
-- Blizzard_SwingTimer.lua. PLAYER_SWING's duration is plain, so the fill is
-- the shared GetTime loop. Its range check never answers on Forever, so the
-- out-of-range dim reads spell range instead (Bars\AD_SwingRange.lua). Without
-- the API the bar keeps its settings and stays hidden outside edit sessions.

local swingArmed = false

-- does the configured hand exist right now? (Blizzard's gate: main hand
-- always, off hand via UnitAttackSpeed's second return, ranged via speed)
local function SwingHandExists(swingType)
    if swingType == 1 then
        local _, off = UnitAttackSpeed("player")
        return off ~= nil
    elseif swingType == 2 then
        local speed = UnitRangedDamage and UnitRangedDamage("player")
        if speed == nil then return false end
        -- Secret in combat on Forever and cannot be compared; it is still a
        -- value, so the hand counts as present rather than hiding the bar.
        if issecretvalue and issecretvalue(speed) then return true end
        return speed > 0
    end
    return true
end

local function SwingIdle(entry)
    entry.running = false
    entry.shell.fill:SetScript("OnUpdate", nil)
    local drain = (R(entry.rec, "fill", "fillMode") or "drain") == "drain"
    -- Between swings a drain bar is empty and a fill bar is full, unless
    -- idleEmpty asks for an empty bar either way.
    local empty = drain or R(entry.rec, "fill", "idleEmpty") == true
    entry.shell.fill:SetMinMaxValues(0, 1)
    entry.shell.fill:SetValue(empty and 0 or 1)
    entry.shell.fill:SetStatusBarColor(BarColorOf(entry.rec))
    if Bars.Spark then Bars.Spark.Sync(entry) end
    SetRunText(entry.shell, "dur", "")
    local st = (entry.rec.driver and entry.rec.driver.swingType) or 0
    if not HAS_SWING or not SwingHandExists(st) then
        entry.stateHidden = true          -- no API here, or no weapon in that hand
    else
        entry.stateHidden = R(entry.rec, "behavior", "hideWhenInactive") and true or false
    end
    ApplyVisibility(entry)
end

local function EnsureSwingEvents()
    if swingArmed or not HAS_SWING then return end
    swingArmed = true
    Events.On("PLAYER_SWING", "adbarsswing", function(_, swingDuration, swingType)
        ForEach("swing", function(e)
            local st = (e.rec.driver and e.rec.driver.swingType) or 0
            if st == swingType then
                RunTimedFill(e, swingDuration, SwingIdle)
                -- the tick unit follows the swing's length (haste moves it):
                -- re-lay only when it really changed
                if not (issecretvalue and issecretvalue(swingDuration))
                    and type(swingDuration) == "number"
                    and math.abs((e.swingLen or 0) - swingDuration) > 0.01 then
                    e.swingLen = swingDuration
                    LayoutTicks(e)
                end
            end
        end)
    end)
    -- hand-existence re-gates (weapon swapped, form changed attack speed)
    Events.On("WEAPON_SLOT_CHANGED", "adbarsswing", function()
        ForEach("swing", function(e)
            if not e.running then SwingIdle(e) end
        end)
    end)
    Events.On("UNIT_ATTACK_SPEED", "adbarsswing", function(_, unit)
        if unit and unit ~= "player" then return end
        ForEach("swing", function(e)
            if not e.running then SwingIdle(e) end
        end)
    end)
end

local function ReleaseSwingEvents()
    if not swingArmed then return end
    for _, e in pairs(live) do
        if e.rec.barKind == "swing" then return end
    end
    swingArmed = false
    for _, ev in ipairs({
        "PLAYER_SWING", "WEAPON_SLOT_CHANGED", "UNIT_ATTACK_SPEED",
    }) do
        Events.Off(ev, "adbarsswing")
    end
end

local function SwingRefresh(entry)
    if entry.running then
        ApplyVisibility(entry)
    else
        SwingIdle(entry)
    end
end

-- Aura runtime. One AuraContainer per aura bar with one AddAuraSlot at
-- creation; later changes go through the slot filters or a fresh container.
-- initializeFrame builds the driven widgets on the engine button, which fills
-- them from the secret aura time and count with no reads or ticks. Everything
-- handed over comes from plain rec/cfg values; nothing is read back. Presence
-- is the one thing the engine cannot hand us: a nil check on the aura fetch
-- drives hideWhenInactive, off UNIT_AURA. Harmful lanes on a friendly target
-- park, since identity filters are skipped there.

local auraTargetArmed = false

local function AuraEngineUp()
    return NS.DriverAura and NS.DriverAura.IsAvailable
        and NS.DriverAura.IsAvailable() == true
end

-- On Forever this probe can return a secret boolean, and a truth test on it
-- throws exactly when restrictions are on; a secret answer means they are.
local function AuraSecretNow()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end

-- The bar's aura lane, read as the aura icons read theirs (ShapeOf): the unit,
-- harmful, who cast it. A bar without a unit keeps the older shape (a debuff
-- on the target, a buff on you), so its signature does not change.
local function AuraShape(d)
    if NS.DriverAura and NS.DriverAura.ShapeOf then return NS.DriverAura.ShapeOf(d) end
    local debuff = (d.auraType or "buff") == "debuff"
    return debuff and "target" or "player", debuff, d.ownOnly and "mine" or nil
end

-- the engine filter for a bar's lane: HARMFUL or HELPFUL, plus the caster
-- token - |PLAYER = yours / your pet's / your vehicle's, |!PLAYER = anyone
-- else's (AuraUtil's negation)
local function AuraFilter(d)
    local _, harmful, caster = AuraShape(d)
    local f = harmful and "HARMFUL" or "HELPFUL"
    if caster == "mine" then return f .. "|PLAYER" end
    if caster == "others" then return f .. "|!PLAYER" end
    return f
end

-- Presence without secrets: a table-or-nil fetch is nil-testable, and the
-- by-name fetch takes the engine's filter string, so own-only presence matches
-- own-only display. Returns true, false or nil (unknown): both fetches return
-- nothing while the aura is secret (all of combat on Forever, restricted
-- instances on retail, where a plain nil comes back buff or not). Guards: the
-- ShouldAurasBeSecret window, then the zero-value return shape (select("#")).
local function AuraFetchCount(...) return select("#", ...), (...) end
local function AuraPresent(entry)
    local d = entry.rec.driver or {}
    local sid = d.spellID
    if not sid then return false end
    if AuraSecretNow() then return nil end
    local unit, harmful, caster = AuraShape(d)
    local n, data
    -- By name with the lane's own filter string, so a caster choice narrows
    -- presence as it narrows the display; by ID covers any-caster buffs on you.
    if unit ~= "player" or harmful or caster ~= nil then
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
            and C_Spell.GetSpellName) then return false end
        local nm = C_Spell.GetSpellName(sid)
        if issecretvalue and issecretvalue(nm) then return nil end
        if not nm then return false end
        n, data = AuraFetchCount(C_UnitAuras.GetAuraDataBySpellName(
            unit, nm, AuraFilter(d)))
    else
        if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
        n, data = AuraFetchCount(C_UnitAuras.GetPlayerAuraBySpellID(sid))
    end
    if n == 0 then return nil end
    return data ~= nil
end

local function AuraPresentText(entry)
    local p = AuraPresent(entry)
    if p == nil then return "unknown" end
    return tostring(p)
end

-- Hostility gate: a harmful slot on an assistable target or focus must be
-- parked, or the identity filter (skipped there) matches the wrong auras.
-- Returns true, false or nil (unknown): on Forever UnitExists and UnitCanAssist
-- can be secret in combat, and comparing one throws. Unknown never flips a
-- park; the target watch settles it when combat ends.
local function TargetHostileNow(unit)
    unit = unit or "target"
    if not UnitExists then return false end
    local exists = UnitExists(unit)
    if issecretvalue and issecretvalue(exists) then return nil end
    if exists ~= true then return false end
    if not UnitCanAssist then return true end
    local assist = UnitCanAssist("player", unit)
    if issecretvalue and issecretvalue(assist) then return nil end
    return assist ~= true
end

local function AuraSlotFilters(entry, parked)
    local d = entry.rec.driver or {}
    return { includeSpellIDs = parked and { [0] = true }
        or { [d.spellID or 0] = true } }
end

local function AuraSetParked(entry, parked)
    local sub = entry.auraSub
    if not sub or sub.parked == parked then return end
    -- candidate filters are data-only (combat-legal by the engine contract);
    -- every slot of the composition parks together
    local f = AuraSlotFilters(entry, parked)
    for _, k in ipairs(sub.keys) do
        sub.container:SetAuraSlotCandidateFilters(k, f)
    end
    sub.parked = parked
end

-- The hide-when-inactive verdict off the non-secret presence. The engine
-- bindings own the fill value and the dur / stk texts and empty themselves when
-- the aura ends (the engine hides its button too). The shell's own fill stays
-- at 0 on an aura bar; it is only a rect.
local function AuraPresenceSync(entry)
    -- the button owns the chrome: the engine hides the whole bar with the
    -- aura, the holder never does
    if entry.chromeOwned then
        entry.stateHidden = false
        ApplyVisibility(entry)
        return
    end
    local present = AuraPresent(entry)
    if present == nil then
        -- Unknown (auras secret): never hide on a refused lookup. The engine
        -- keeps painting the truth and hides it when the aura ends; "hide when
        -- inactive" resumes on the first plain verdict (combat end re-syncs).
        entry.stateHidden = false
    else
        entry.stateHidden = (not present)
            and R(entry.rec, "behavior", "hideWhenInactive") == true or false
    end
    ApplyVisibility(entry)
end

local function ArmAuraTargetWatch()
    if auraTargetArmed then return end
    auraTargetArmed = true
    -- Every lane off the player on `unit` (nil = all): re-decide its park and
    -- nudge its slots, since a container refreshes only on UNIT_AURA of its
    -- unit and goes stale when the token points at someone else. Runs on each
    -- swap and again at combat end, because a change in combat cannot decide
    -- (the answer is secret) and the combat-end rebuild skips a composition it
    -- already has. Returns false while a park is still unknown.
    local function SyncParks(unit)
        local settled = true
        ForEach("aura", function(e)
            local sub = e.auraSub
            if sub and sub.unit ~= "player" and (unit == nil or sub.unit == unit) then
                if sub.hostilePark then
                    local hostile = TargetHostileNow(sub.unit)
                    if hostile == nil then settled = false else AuraSetParked(e, not hostile) end
                end
                if type(sub.container.UpdateAllAuras) == "function" then
                    sub.container:UpdateAllAuras()
                end
                AuraPresenceSync(e)
            end
        end)
        return settled
    end
    -- the client throws on an event name it does not have (focus is not
    -- promised everywhere): probe each one first
    local function valid(ev)
        return (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev)
    end
    Events.On("PLAYER_TARGET_CHANGED", "adbarsaura", function() SyncParks("target") end)
    if valid("PLAYER_FOCUS_CHANGED") then
        Events.On("PLAYER_FOCUS_CHANGED", "adbarsaura", function() SyncParks("focus") end)
    end
    if valid("UNIT_PET") then
        Events.On("UNIT_PET", "adbarsaura", function(_, u)
            if u == nil or u == "player" then SyncParks("pet") end
        end)
    end
    if valid("GROUP_ROSTER_UPDATE") then
        Events.On("GROUP_ROSTER_UPDATE", "adbarsaura", function()
            for i = 1, 4 do SyncParks("party" .. i) end
        end)
    end
    -- secrecy can lift a beat after the event: an unknown answer gets two
    -- more looks, then waits for the next swap
    Events.On("PLAYER_REGEN_ENABLED", "adbarsaura", function()
        if SyncParks() then return end
        C_Timer.After(0.3, function()
            if not SyncParks() then C_Timer.After(1, SyncParks) end
        end)
    end)
end

local function ReleaseAuraTargetWatch()
    if not auraTargetArmed then return end
    for _, e in pairs(live) do
        if e.auraSub and e.auraSub.unit ~= "player" then return end
    end
    auraTargetArmed = false
    Events.Off("PLAYER_TARGET_CHANGED", "adbarsaura")
    Events.Off("PLAYER_FOCUS_CHANGED", "adbarsaura")
    Events.Off("UNIT_PET", "adbarsaura")
    Events.Off("GROUP_ROSTER_UPDATE", "adbarsaura")
    Events.Off("PLAYER_REGEN_ENABLED", "adbarsaura")
end

-- The composition: driven widgets live on the engine's buttons.
-- SetDurationBar, SetApplicationBar, SetDurationText and SetApplicationCount
-- accept only the aura button or a descendant (checked in
-- AuraContainerUtil.ValidateInboundScriptObjectInternal); an addon frame
-- throws inside initializeFrame and nothing is driven. So each slot's
-- StatusBar, mask and sheen, and the base slot's text host, are created on
-- the button in the init window. After that no button is moved: it follows
-- our window frame, its bar our fill or overhang frame, so a resize only
-- re-lays our frames. Styling is re-pushed while the hierarchy is accessible
-- (it is forbidden while auras are secret). Structure and binding recipes
-- are baked into the composition signature: a change parks the old container
-- for a fresh one (containers are never destroyed).

local AURA_STEP_DELTA = 0.0005      -- the step wipe, as a fraction of the aura's life
local AURA_STEP_MAXLEN = 120000     -- the overhang cap in pixels
local AURA_MASK_PAD = 400           -- a mask's reach past an edge that cuts nothing

-- The client's own stack maximum (GetSpellMaxCumulativeAuraApplications). It
-- is secret while auras are restricted, so the last plain answer per spell
-- serves. A 0 or 1 means the client does not know it as a stacking aura:
-- unknown for a stack bar. Never returns a secret.
local maxStackCache = {}
local function ClientMaxStacks(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications) then
        return nil
    end
    local n = C_Spell.GetSpellMaxCumulativeAuraApplications(spellID)
    if n ~= nil and not (issecretvalue and issecretvalue(n))
        and type(n) == "number" and n >= 2 then
        n = math.floor(n)
        maxStackCache[spellID] = n
        return n
    end
    return maxStackCache[spellID]
end
Bars.ClientMaxStacks = ClientMaxStacks

-- a typed maximum wins; else the client's; else 5 (an unknown aura while
-- restricted - the first plain answer re-plans the composition)
AuraMaxStacks = function(rec)   -- forward-declared above TickUnit (the seam reads it too)
    local d = rec.driver or {}
    local m = tonumber(d.maxStacks)
    if not m or m < 1 then m = ClientMaxStacks(d.spellID) end
    if not m or m < 1 then m = 5 end
    return math.floor(m)
end

-- the bar's stack maximum for the editor (the stack threshold sliders run
-- 2..this): aura = the aura maximum; resource = the plain cached power max
function Bars.MaxStacksFor(rec)
    if not rec then return 5 end
    if rec.barKind == "aura" then return AuraMaxStacks(rec) end
    if rec.barKind == "resource" then
        local d = rec.driver or {}
        local pt = d.powerType
        if pt == nil or pt < 0 then pt = UnitPowerType and UnitPowerType("player") end
        local m = pt and cachedMax[pt]
        if m and m >= 2 and m <= 20 then return math.floor(m) end
    end
    return 5
end

-- the countdown text recipe: decimals, M:SS and colour bands, one shared formatter
-- (bindings are init-only, so the recipe is part of the composition sig)
local function AuraDurFormatter(entry)
    if not (NS.Factory and NS.Factory.TimerFormatter) then return nil end
    local rec = entry.rec
    local decTo = (R(rec, "text", "durDecimalsEnabled") == true)
        and (R(rec, "text", "durDecimalThreshold") or 10) or 0
    local bands = (entry.mode == "duration") and TextBands(entry) or nil
    -- stock "down": the engine's own duration text drops the fraction, so
    -- the default "up" rounding needs a formatter here (Settings > Timers)
    return NS.Factory.TimerFormatter(decTo, bands, R(rec, "text", "durAbbrev") or 0, "down",
        BarRounding(rec))
end

-- The stack count from 1: the engine's default hides 0 and 1; this one hides
-- only 0.
local auraCountFmt
local function AuraCountFormatter()
    if auraCountFmt ~= nil then return auraCountFmt or nil end
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        local f = C_StringUtil.CreateNumericRuleFormatter()
        f:AddBreakpoint({ threshold = 0, format = "" })
        f:AddBreakpoint({ threshold = 1, format = "%d" })
        auraCountFmt = f
    else
        auraCountFmt = false
    end
    return auraCountFmt or nil
end

-- The text runs the engine renders on the button, by the shell's rule.
local function AuraTextWanted(entry, key)
    return TextRunWanted(entry, TEXT_DEF_BY_KEY[key]) == true
end

local function ColorKey(c)
    c = c or {}
    return string.format("%02x%02x%02x%02x",
        math.floor((c[1] or 1) * 255 + 0.5), math.floor((c[2] or 1) * 255 + 0.5),
        math.floor((c[3] or 1) * 255 + 0.5), math.floor((c[4] or 1) * 255 + 0.5))
end

-- Computed before styling on every rebuild: the layer plan, whether the base
-- fill goes flat, the base colour and the composition signature (lane, filter,
-- structure, binding recipes). Colours and the spell id stay out of it: they
-- are pushed live or retargeted through the filters.
local function AuraPlan(entry)
    local rec = entry.rec
    local d = rec.driver or {}
    local texPath = ResolveBarTexture(R(rec, "fill", "texture"))
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    local layers, fillColor, parts = {}, nil, {}
    if entry.mode == "stack" then
        local M = AuraMaxStacks(rec)
        -- colour by position (each cell keeps its band) or the flip model
        local segmented = R(rec, "stackcolors", "scPosition") ~= false
        layers, fillColor = StackLayerPlan(rec, M, segmented)
        parts[#parts + 1] = "S" .. M .. (segmented and "g" or "c")
        for _, L in ipairs(layers) do
            parts[#parts + 1] = string.format("%s:%d:%d:%.4f:%.4f", L.kind, L.minA, L.maxA, L.x0, L.x1)
        end
    else
        local bands = DurationBands(rec, R(rec, "thresholds", "threshRef") or 30)
        layers = DurationLayerPlan(bands, drain,
            R(rec, "fill", "color") or { 0.247, 0.788, 0.949, 1 }) or {}
        parts[#parts + 1] = "D" .. (drain and "d" or "f")
        for _, L in ipairs(layers) do
            parts[#parts + 1] = string.format("%s:%s:%.4f", L.kind, L.side, L.f)
        end
        -- the text formatter bakes the band seconds and colours
        if R(rec, "thresholds", "threshText") == true and bands then
            for _, b in ipairs(bands) do
                parts[#parts + 1] = string.format("b%.1f:%s", b.secs or 0, ColorKey(b.color))
            end
        end
    end
    -- the text bindings are init-only too: their recipe joins the signature,
    -- the Settings > Timers rounding with it
    parts[#parts + 1] = "t" .. ((R(rec, "text", "durDecimalsEnabled") == true)
        and (R(rec, "text", "durDecimalThreshold") or 10) or 0)
        .. BarRounding(rec) .. "a" .. (R(rec, "text", "durAbbrev") or 0)
    parts[#parts + 1] = (R(rec, "fill", "smoothing") ~= false) and "sm" or "im"
    parts[#parts + 1] = "d" .. (AuraTextWanted(entry, "dur") and 1 or 0)
        .. "k" .. (AuraTextWanted(entry, "stk") and 1 or 0)
    -- Orientation and reverse are baked into the layer masks at init
    -- (AuraMaskRect cuts one axis and pads the other), so a flip builds a
    -- fresh composition instead of restyling the old one.
    parts[#parts + 1] = ((R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL" and "V" or "H")
        .. ((R(rec, "fill", "reverseFill") == true) and "r" or "")
    local split = #layers > 0
    local shade = split and texPath ~= WHITE
    if shade then layers[#layers + 1] = { kind = "shade" } end
    entry.auraPlan = layers
    entry.auraSplit = split
    entry.auraFillColor = fillColor
    -- Button-owned chrome: Hide when inactive hands the bar's chrome to the
    -- base button (built at init, so it joins the signature); an edit session
    -- keeps the shell's copies so an absent aura can still be placed.
    entry.chromeOwned = R(rec, "behavior", "hideWhenInactive") == true and not IsEditMode()
    entry.auraSig = (AuraShape(d))
        .. "|" .. AuraFilter(d) .. "|" .. table.concat(parts, "|") .. (shade and "|sh" or "")
        .. (entry.chromeOwned and "|own" or "")
end

-- Per layer, pooled: the window the engine button takes and the step overhang
-- its bar takes. Plain frames, born spanning the fill so an early anchor has a
-- rect. No clipping anywhere: a clipping ancestor blanks engine buttons, so the
-- masks clip instead.
local function AuraLayerHost(entry, i)
    entry.auraLayers = entry.auraLayers or {}
    local lay = entry.auraLayers[i]
    if lay then return lay end
    local host = CreateFrame("Frame", nil, entry.shell)
    host:SetAllPoints(entry.shell.fill)
    local step = CreateFrame("Frame", nil, entry.shell)
    step:SetAllPoints(entry.shell.fill)
    lay = { host = host, stepRect = step }
    entry.auraLayers[i] = lay
    return lay
end

-- anchor a frame to the window [a..b] (pixels from the fill origin) along
-- the fill axis, full cross-axis, for any orientation / reverse
local function AuraAxisRect(f, fill, a, b, vertical, rev)
    f:ClearAllPoints()
    if vertical then
        if rev then
            f:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, -a)
            f:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -b)
        else
            f:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, a)
            f:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, b)
        end
    else
        if rev then
            f:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -a, 0)
            f:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", -b, 0)
        else
            f:SetPoint("TOPLEFT", fill, "TOPLEFT", a, 0)
            f:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT", b, 0)
        end
    end
end

-- The mask window over the button rect (the button is the layer window).
-- Along the fill axis the origin and far edges each "pad" (400px out, nothing
-- to cut), cut "exact" (the overhang at the bar origin) or reach "over" 1px
-- into the neighbour (both paint the same colour, so overlap is free and a gap
-- is not). The cross-axis edges always pad. Anchored once, at init.
local function AuraMaskRect(mask, btn, vertical, rev, originMode, farMode, px)
    local function Ext(mode)
        if mode == "pad" then return AURA_MASK_PAD end
        if mode == "over" then return px end
        return 0
    end
    local o, f = Ext(originMode), Ext(farMode)
    local l, r, t, b
    if vertical then
        l, r = AURA_MASK_PAD, AURA_MASK_PAD
        if rev then t, b = o, f else b, t = o, f end
    else
        t, b = AURA_MASK_PAD, AURA_MASK_PAD
        if rev then r, l = o, f else l, r = o, f end
    end
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", btn, "TOPLEFT", -l, t)
    mask:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", r, -b)
end

local function AuraStyleText(fs, entry, def)
    local rec = entry.rec
    StyleFont(fs, entry, def.key, R(rec, "text", def.size) or 12,
        R(rec, "text", def.outline) or "OUTLINE", R(rec, "text", def.shadow) == true)
    local c = R(rec, "text", def.colour) or { 1, 1, 1, 1 }
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    PlaceText(fs, entry.shell.overlay, R(rec, "text", def.anchor) or "CENTER",
        R(rec, "text", def.x), R(rec, "text", def.y))
end

-- The only writer of a slot's styled properties, from plain sources: at init
-- and on rebuilds while the hierarchy is accessible. s.i = layer index (0 =
-- base), s.bar the driven statusbar, s.tex its fill texture, then optional
-- s.mask / s.sheen / s.dur / s.stk.
local function AuraStyleSlot(entry, s)
    local rec = entry.rec
    local L = (s.i > 0) and entry.auraPlan and entry.auraPlan[s.i] or nil
    local kind = L and L.kind or "base"
    local bar = s.bar
    bar:SetOrientation(R(rec, "fill", "orientation") or "HORIZONTAL")
    bar:SetReverseFill(R(rec, "fill", "reverseFill") == true)
    bar:SetRotatesTexture(R(rec, "fill", "rotateTexture") == true)
    -- Colour/texture split: with colour layers the base and every layer go
    -- flat and the shade carries the texture, MOD-blended over them, so no
    -- seam shows two shades; otherwise the base carries the user's texture.
    local texPath = ResolveBarTexture(R(rec, "fill", "texture"))
    local want = (kind == "shade" or (kind == "base" and not entry.auraSplit)) and texPath or WHITE
    if s.texApplied ~= want then
        s.texApplied = want
        bar:SetStatusBarTexture(want)
        -- a swap can create a new texture object: re-read it (init window
        -- or an accessible rebuild, both allowed) and re-attach the exact-edge
        -- sampling, the mask and the sheen
        local t = bar:GetStatusBarTexture()
        if t ~= s.tex then
            s.tex = t
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
            if s.mask and t.AddMaskTexture then t:AddMaskTexture(s.mask) end
            if s.sheen then
                s.sheen:ClearAllPoints()
                s.sheen:SetAllPoints(t)
            end
        end
        if s.tex.SetBlendMode then s.tex:SetBlendMode(kind == "shade" and "MOD" or "BLEND") end
    end
    if kind == "shade" then
        bar:SetStatusBarColor(1, 1, 1, 1)
    elseif kind == "base" then
        bar:SetStatusBarColor(FillBaseColor(entry))
    else
        local c = L.color or { 1, 1, 1, 1 }
        bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
    if s.sheen then
        ApplySheen(s.sheen, rec)
        s.sheen:SetShown(R(rec, "fill", "useGradient") ~= false)
    end
    if s.dur then AuraStyleText(s.dur, entry, TEXT_DEF_BY_KEY.dur) end
    if s.stk then AuraStyleText(s.stk, entry, TEXT_DEF_BY_KEY.stk) end
end

-- Access probe: the engine forbids its button hierarchy while auras are secret
-- (any call errors). Without CanBeAccessedInContext, use the secrecy probe.
local function AuraTouchable(b)
    if b.CanBeAccessedInContext then return b:CanBeAccessedInContext() == true end
    return not AuraSecretNow()
end

-- Button-owned chrome: with Hide when inactive on, the background, border,
-- ticks, name and icon are built as children of the base engine button, so the
-- engine shows and hides the whole bar with the aura, in combat too, with no
-- presence reads (those fail closed under secrecy). Each copy takes its
-- original's geometry; only colours, textures, text and the border style are
-- mirrored, while the button is accessible. The shell's originals go silent.
local function AuraOwnChromeBuild(entry, b, s)
    local sh = entry.shell
    local oc = {}
    s.own = oc
    local lvl = b:GetFrameLevel()
    local ovl = sh.overlay:GetFrameLevel()
    -- background: the button's own level, under its bar (one level up)
    oc.bgHost = CreateFrame("Frame", nil, b)
    oc.bgHost:SetAllPoints(sh)
    oc.bgHost:SetFrameLevel(lvl)
    oc.bg = oc.bgHost:CreateTexture(nil, "BACKGROUND")
    oc.bg:SetAllPoints(sh)
    -- border strips + the border-style backdrop, at the overlay's level;
    -- the strips take the shell's own corner anchors (BuildShell's), their
    -- thickness follows in the sync
    oc.borderHost = CreateFrame("Frame", nil, b)
    oc.borderHost:SetAllPoints(sh)
    oc.borderHost:SetFrameLevel(ovl)
    oc.edges = {}
    for _, k in ipairs(EDGE_KEYS) do
        oc.edges[k] = oc.borderHost:CreateTexture(nil, "BORDER")
    end
    oc.edges.top:SetPoint("TOPLEFT", sh, "TOPLEFT")
    oc.edges.top:SetPoint("TOPRIGHT", sh, "TOPRIGHT")
    oc.edges.bottom:SetPoint("BOTTOMLEFT", sh, "BOTTOMLEFT")
    oc.edges.bottom:SetPoint("BOTTOMRIGHT", sh, "BOTTOMRIGHT")
    oc.edges.left:SetPoint("TOPLEFT", sh, "TOPLEFT")
    oc.edges.left:SetPoint("BOTTOMLEFT", sh, "BOTTOMLEFT")
    oc.edges.right:SetPoint("TOPRIGHT", sh, "TOPRIGHT")
    oc.edges.right:SetPoint("BOTTOMRIGHT", sh, "BOTTOMRIGHT")
    oc.borderF = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
    oc.borderF:SetAllPoints(sh)
    oc.borderF:SetFrameLevel(ovl - 1)
    oc.borderF:EnableMouse(false)
    oc.borderF:Hide()
    -- ticks: one copy per laid mark, anchored over it
    oc.tickHost = CreateFrame("Frame", nil, b)
    oc.tickHost:SetAllPoints(sh.overlay)
    oc.tickHost:SetFrameLevel(ovl)
    oc.ticks = {}
    -- the name, above the engine's own text host
    oc.textHost = CreateFrame("Frame", nil, b)
    oc.textHost:SetAllPoints(sh.overlay)
    oc.textHost:SetFrameLevel(ovl + 2)
    oc.name = oc.textHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    oc.name:SetWordWrap(false)
    -- the icon, when the shell has one (ApplyStyle ran before the slot)
    local f = entry.iconF
    if f then
        oc.iconHost = CreateFrame("Frame", nil, b)
        oc.iconHost:SetAllPoints(f)
        oc.iconHost:SetFrameLevel(ovl)
        oc.icon = oc.iconHost:CreateTexture(nil, "ARTWORK")
        oc.icon:SetAllPoints(f.tex)
        oc.iconEdges = {}
        for _, k in ipairs(EDGE_KEYS) do
            local t = oc.iconHost:CreateTexture(nil, "OVERLAY")
            t:SetAllPoints(f.edges[k])
            oc.iconEdges[k] = t
        end
    end
    AuraOwnChromeSync(entry)
end

-- assigns the forward-declared local: the mirror pass, from the shell's
-- painted values (never from the record twice). Skipped while the button
-- hierarchy is forbidden - the next accessible style pass catches up.
AuraOwnChromeSync = function(entry)
    local sub = entry.auraSub
    if not sub then return end
    local s
    for _, sl in ipairs(sub.slots) do
        if sl.i == 0 then s = sl break end
    end
    local oc = s and s.own
    if not oc then return end
    if not AuraTouchable(s.button) then return end
    local sh, rec = entry.shell, entry.rec
    -- pinned to a nameplate (secret rect): colours still copy, the sizes and
    -- points copied on the last plain pass stand
    local rectOK = not Bars.RectHidden(sh.fill)
    oc.bg:SetTexture(sh.bg:GetTexture())
    oc.bg:SetVertexColor(sh.bg:GetVertexColor())
    for _, k in ipairs(EDGE_KEYS) do
        local srcE, t = sh.edges[k], oc.edges[k]
        local e = entry.edgeRGBA or { 0, 0, 0, 1 }
        t:SetColorTexture(e[1], e[2], e[3], e[4])
        if rectOK then
            if k == "top" or k == "bottom" then t:SetHeight(srcE:GetHeight()) else t:SetWidth(srcE:GetWidth()) end
        end
    end
    local bf = sh.borderF
    if bf and entry.borderFWanted and oc.borderF.SetBackdrop then
        if oc.borderF._adEdge ~= bf._adEdge or oc.borderF._adSize ~= bf._adSize then
            oc.borderF._adEdge, oc.borderF._adSize = bf._adEdge, bf._adSize
            oc.borderF:SetBackdrop({ edgeFile = bf._adEdge, edgeSize = bf._adSize })
        end
        oc.borderF:SetBackdropBorderColor(bf:GetBackdropBorderColor())
        oc.borderF:Show()
    else
        oc.borderF:Hide()
    end
    local n = entry.tickCount or 0
    for i = 1, n do
        local srcT = sh.ticks[i]
        local t = oc.ticks[i]
        if not t then
            t = oc.tickHost:CreateTexture(nil, "ARTWORK", nil, 1)
            oc.ticks[i] = t
        end
        -- the mark's single point and explicit size are data, readable
        -- while the original is hidden (not while the rect is secret)
        if rectOK then
            local p, rel, rp, x, y = srcT:GetPoint(1)
            t:ClearAllPoints()
            if p then t:SetPoint(p, rel, rp, x, y) end
            t:SetSize(srcT:GetSize())
        end
        local tc = entry.tickRGBA or { 0, 0, 0, 1 }
        t:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        t:Show()
    end
    for i = n + 1, #oc.ticks do oc.ticks[i]:Hide() end
    local def = TEXT_DEF_BY_KEY.name
    if TextRunWanted(entry, def) then
        StyleFont(oc.name, entry, "name", R(rec, "text", def.size) or 12,
            R(rec, "text", def.outline) or "OUTLINE", R(rec, "text", def.shadow) == true)
        local c = R(rec, "text", def.colour) or { 1, 1, 1, 1 }
        oc.name:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        PlaceText(oc.name, sh.overlay, R(rec, "text", def.anchor) or "CENTER",
            R(rec, "text", def.x), R(rec, "text", def.y))
        oc.name:SetText(BarCustomName(rec) or rec.name or "")
        oc.name:Show()
    else
        oc.name:Hide()
    end
    local f = entry.iconF
    if oc.icon and f then
        if R(rec, "icon", "iconShow") == true then
            oc.icon:SetTexture(f.tex:GetTexture())
            oc.icon:SetTexCoord(f.tex:GetTexCoord())
            for _, k in ipairs(EDGE_KEYS) do
                local ie = entry.iconEdgeRGBA or { 0, 0, 0, 1 }
                oc.iconEdges[k]:SetColorTexture(ie[1], ie[2], ie[3], ie[4])
            end
            oc.iconHost:Show()
        else
            oc.iconHost:Hide()
        end
    end
end

-- Assigns the forward-declared local: ApplyStyle re-pushes a live composition's
-- styling on every rebuild (colour pickers stream edits; a rebuild per edit
-- would churn containers). Skipped while a swap is pending (the old structure
-- would take the new plan) or the hierarchy is forbidden.
function AuraRestyle(entry)
    local sub = entry.auraSub
    if not sub or sub.sig ~= entry.auraSig then return end
    for _, s in ipairs(sub.slots) do
        if not AuraTouchable(s.button) then return end
        AuraStyleSlot(entry, s)
    end
end

-- Geometry for every layer: only our window and overhang frames (the engine
-- widgets follow them). A composition awaiting its swap keeps its own plan.
local function AuraLayoutLayers(entry)
    local shell, rec = entry.shell, entry.rec
    local sub = entry.auraSub
    local plan = (sub and sub.sig ~= entry.auraSig) and sub.plan or entry.auraPlan
    if not plan or #plan == 0 then return end
    local fill = shell.fill
    if Bars.RectHidden(fill) then return end   -- pinned to a nameplate
    local W, H = fill:GetWidth() or 0, fill:GetHeight() or 0
    if W <= 1 or H <= 1 then return end
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local rev = R(rec, "fill", "reverseFill") == true
    local len, cross = vertical and H or W, vertical and W or H
    local px = Px(shell)
    local function Snap(v) return math.floor(v / px + 0.5) * px end
    for i, L in ipairs(plan) do
        local lay = AuraLayerHost(entry, i)
        if L.kind == "shade" then
            AuraAxisRect(lay.host, fill, 0, len, vertical, rev)
        elseif L.kind == "band" or L.kind == "max" then
            AuraAxisRect(lay.host, fill, Snap(len * L.x0), Snap(len * L.x1), vertical, rev)
        else
            local X = Snap(len * L.f)
            if L.kind == "track" and L.side == "high" then
                AuraAxisRect(lay.host, fill, X, len, vertical, rev)
            else
                AuraAxisRect(lay.host, fill, 0, X, vertical, rev)
            end
            if L.kind == "step" then
                -- the overhang: Lg long, its origin Lg*f before the bar
                -- origin, so its fill edge crosses the bar origin at the
                -- threshold and sweeps the window within X/Lg (0.05%) of
                -- the aura's life
                local Lg = math.min(AURA_STEP_MAXLEN, math.max(len, X / AURA_STEP_DELTA))
                local back = Lg * L.f
                local sr = lay.stepRect
                sr:ClearAllPoints()
                if vertical then
                    sr:SetSize(cross, Lg)
                    if rev then
                        sr:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, back)
                    else
                        sr:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, -back)
                    end
                else
                    sr:SetSize(Lg, cross)
                    if rev then
                        sr:SetPoint("TOPRIGHT", fill, "TOPRIGHT", back, 0)
                    else
                        sr:SetPoint("TOPLEFT", fill, "TOPLEFT", -back, 0)
                    end
                end
            end
        end
    end
end

-- The colour layers of an aura bar. A stack bar's per-stack marks are ticks
-- ("Every point", laid by the seam), not dividers.
local function AuraLayoutAll(entry)
    AuraLayoutLayers(entry)
    if entry.segments ~= 1 then
        entry.segments = 1
        LayoutDividers(entry.shell, entry.rec, 1)
    end
end

-- Creates the container and slots once per composition; false means retry on a
-- later rebuild (engine absent or auras secret-restricted; EnsureBar re-runs on
-- every rebuild, REGEN and PEW included). AuraPlan has already run.
local function AuraBarEnsure(entry)
    local rec = entry.rec
    local d = rec.driver or {}
    local wantSig = entry.auraSig
    if not d.spellID or not wantSig then return false end
    local wantUnit, harmful = AuraShape(d)
    local filter = AuraFilter(d)

    local sub = entry.auraSub
    if sub then
        if sub.sig == wantSig then
            if sub.spellID ~= d.spellID then
                sub.spellID = d.spellID
                if not sub.parked then
                    local f = AuraSlotFilters(entry, false)
                    for _, k in ipairs(sub.keys) do
                        sub.container:SetAuraSlotCandidateFilters(k, f)
                    end
                end
            end
            return true
        end
        -- a new composition cannot be created while the engine is absent or
        -- auras are secret-restricted: keep the old one running (a stale
        -- look beats a dead bar); the next rebuild swaps it
        if not AuraEngineUp() or AuraSecretNow() then return true end
        AuraSetParked(entry, true)
        sub.container:Hide()
        entry.auraSub = nil
    end

    if not AuraEngineUp() then return false end
    -- Creation is blocked while auras are secret-restricted; rebuilds retry.
    if AuraSecretNow() then return false end

    if C_AddOns and C_AddOns.IsAddOnLoaded
        and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local shell = entry.shell
    -- parented to the shell: the holder's alpha (opacity, hide when
    -- inactive, conditions) reaches the engine-drawn fill through it
    local c = CreateFrame("AuraContainer", nil, shell, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraSlot) ~= "function" then return false end
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    c:SetUnit(wantUnit)
    c:SetEnabled(true)
    c:Show()

    entry.auraGen = (entry.auraGen or 0) + 1
    local barId = rec.id
    local keyBase = "adbar" .. barId .. "_g" .. entry.auraGen
    -- A harmful lane on a unit that can be friendly (target, focus) parks while
    -- that unit is assistable: the engine skips spell-ID filters there. Unknown
    -- hostility (a secret answer) parks too, until the next swap or combat end.
    -- Debuffs on you, your pet or party are offered only for never-secret ids,
    -- which the engine always honours.
    local hostilePark = harmful and (wantUnit == "target" or wantUnit == "focus")
    local parked = hostilePark and not TargetHostileNow(wantUnit)
    local cf = { includeSpellIDs = parked and { [0] = true } or { [d.spellID] = true } }
    local plan = entry.auraPlan or {}
    -- The sub exists before the slots: the initializer runs inside
    -- AddAuraSlot and must already find it.
    sub = { container = c, keys = {}, slots = {}, unit = wantUnit, harmful = harmful,
        hostilePark = hostilePark, spellID = d.spellID,
        parked = parked, sig = wantSig, plan = plan }
    entry.auraSub = sub

    -- Hand-over options, baked at init and in the signature: probed enum
    -- members for direction and interpolation (nil = engine default).
    local smooth = R(rec, "fill", "smoothing") ~= false
    local interp = smooth and (INTERP_SMOOTH or INTERP_ANY) or (INTERP_NONE or INTERP_ANY)
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    local dir = drain and DIR_REMAIN or DIR_ELAPSED
    local M = AuraMaxStacks(rec)
    local durFmt = AuraDurFormatter(entry)
    local countFmt = AuraCountFormatter()
    local wantDur = AuraTextWanted(entry, "dur")
    local wantStk = AuraTextWanted(entry, "stk")
    local stackMode = entry.mode == "stack"
    -- the sheen rides the top fill: the shade layer when there is one
    local topIndex = 0
    for i, L in ipairs(plan) do
        if L.kind == "shade" then topIndex = i end
    end

    local function Live()
        local e2 = live[barId]
        if e2 and e2.auraSub == sub then return e2 end
        return nil
    end

    -- The init window: the one moment the button hierarchy is ours to build.
    -- Everything made here descends from the button (the engine checks), is
    -- anchored to our frames and is never moved again.
    local function Wire(b, i)
        local e2 = Live()
        if not e2 then return end
        e2.auraWired = (e2.auraWired or 0) + 1   -- /adbars diag: the engine reached us
        local sh = e2.shell
        local L = (i > 0) and plan[i] or nil
        local kind = L and L.kind or "base"
        b:EnableMouse(false)
        b:SetAlpha(1)
        -- The button's level first: SetFrameLevel on a parent shifts its
        -- children by the delta.
        local base = sh.fill:GetFrameLevel()
        b:SetFrameLevel(base + 1 + 2 * i)
        -- the button is the layer window: base and shade span the fill,
        -- every other layer takes its window frame
        b:ClearAllPoints()
        if L and kind ~= "shade" then
            b:SetAllPoints(AuraLayerHost(e2, i).host)
        else
            b:SetAllPoints(sh.fill)
        end
        local s = { i = i, button = b }

        local bar = CreateFrame("StatusBar", nil, b)
        bar:SetFrameLevel(base + 2 + 2 * i)
        s.bar = bar
        if kind == "track" then
            bar:SetAllPoints(sh.fill)                          -- full length, masked to the window
        elseif kind == "step" then
            bar:SetAllPoints(AuraLayerHost(e2, i).stepRect)    -- the overhang, masked to [0..X]
        else
            bar:SetAllPoints(b)
        end
        -- The range before any binding: the engine's timer maps onto the bar's
        -- range, and SetMinMaxValues after a timer push drops the timer.
        bar:SetMinMaxValues(0, 1)
        -- A path: this client's SetStatusBarTexture takes an asset, and a
        -- texture object leaves no fill. The object is read back here, in the
        -- init window (the one allowed read); exact-edge sampling for seams.
        bar:SetStatusBarTexture(WHITE)
        local t = bar:GetStatusBarTexture()
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
        if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        s.tex = t
        if kind == "track" or kind == "step" then
            local m = bar:CreateMaskTexture()
            -- CLAMPTOBLACKADDITIVE masks out everything outside the rect.
            -- NEAREST, since bilinear fades the outer half texel of the 8x8
            -- into a soft edge about 12px wide on a bar.
            m:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
            if m.SetSnapToPixelGrid then m:SetSnapToPixelGrid(false) end
            if m.SetTexelSnappingBias then m:SetTexelSnappingBias(0) end
            local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
            local rev = R(rec, "fill", "reverseFill") == true
            local px = Px(sh)
            if kind == "step" then
                AuraMaskRect(m, b, vertical, rev, "exact", "over", px)
            elseif L.side == "high" then
                AuraMaskRect(m, b, vertical, rev, "over", "pad", px)
            else
                AuraMaskRect(m, b, vertical, rev, "pad", "over", px)
            end
            t:AddMaskTexture(m)
            s.mask = m
        end

        -- The sheen rides the fill texture, covering only the filled part; it
        -- is anchored to GetStatusBarTexture before the bar is bound.
        if i == topIndex then
            local sn = bar:CreateTexture(nil, "OVERLAY")
            sn:SetAllPoints(t)
            sn:SetTexture(WHITE)
            if not (sn.SetGradient and CreateColor) then sn:SetAlpha(0) end
            s.sheen = sn   -- the gradient recipe lands in AuraStyleSlot below
        end

        -- the binding: stack layers take an applications window (shown from
        -- minA, full at maxA); duration layers the base's direction + timer
        local li = (L and L.imm) and (INTERP_NONE or interp) or interp
        if stackMode then
            local win = L and kind ~= "shade"
            local o = { maxApplications = win and L.maxA or M,
                minApplications = win and L.minA or 0 }
            if li then o.interpolation = li end
            b:SetApplicationBar(bar, o)
        else
            local o = {}
            if dir then o.direction = dir end
            if li then o.interpolation = li end
            b:SetDurationBar(bar, o)
        end

        -- Texts ride the base slot on a host above the overlay. Font before
        -- the binding: SetDurationText and SetApplicationCount write text on
        -- attach, and a FontString without a font throws "Font not set" in
        -- the initializer, aborting AddAuraSlot before the slot registers.
        if i == 0 and (wantDur or wantStk) then
            local th = CreateFrame("Frame", nil, b)
            th:SetAllPoints(sh.overlay)
            th:SetFrameLevel(sh.overlay:GetFrameLevel() + 1)
            if wantDur then
                local fs = th:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                fs:SetWordWrap(false)
                AuraStyleText(fs, e2, TEXT_DEF_BY_KEY.dur)
                s.dur = fs
                b:SetDurationText(fs, durFmt and { textFormatter = durFmt } or {})
            end
            if wantStk then
                local fs = th:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                fs:SetWordWrap(false)
                AuraStyleText(fs, e2, TEXT_DEF_BY_KEY.stk)
                s.stk = fs
                b:SetApplicationCount(fs, countFmt and { formatter = countFmt } or {})
            end
        end

        -- Button-owned chrome (Hide when inactive): the engine shows and hides
        -- the whole bar with the aura.
        if i == 0 and e2.chromeOwned then AuraOwnChromeBuild(e2, b, s) end

        AuraStyleSlot(e2, s)
        -- The record lands last: /adbars diag's `slots` counts only fully
        -- wired slots, so wired > slots means an initializer threw (the engine
        -- calls it through securecallfunction: silent with scriptErrors off).
        sub.slots[#sub.slots + 1] = s
    end

    -- slot 0: the base fill + the texts; one slot per colour layer
    local k0 = keyBase .. "_0"
    sub.keys[#sub.keys + 1] = k0
    c:AddAuraSlot(k0, filter, {
        initializeFrame = function(b) Wire(b, 0) end,
        candidateFilters = cf,
    })
    for i = 1, #plan do
        local k = keyBase .. "_" .. i
        sub.keys[#sub.keys + 1] = k
        c:AddAuraSlot(k, filter, {
            initializeFrame = function(b) Wire(b, i) end,
            candidateFilters = cf,
        })
    end
    -- a fresh composition takes over from the retired container: ask the
    -- engine for a full pass now
    if type(c.UpdateAllAuras) == "function" then c:UpdateAllAuras() end
    if wantUnit ~= "player" then ArmAuraTargetWatch() end
    return true
end

local function AuraBarRelease(entry)
    if entry.auraSub then
        AuraSetParked(entry, true)
        entry.auraSub.container:Hide()
        entry.auraSub = nil
    end
    ReleaseAuraTargetWatch()
end

-- Shared events: one registration set for every bar

-- assigns the forward-declared local above (the swing handlers close over it)
function ForEach(kind, fn)
    for _, e in pairs(live) do
        if not kind or e.rec.barKind == kind then fn(e) end
    end
end

local function EnsureSharedEvents()
    if sharedArmed then return end
    sharedArmed = true

    -- Late media: a font from an addon that loads after us
    -- falls back to the default face on the first style pass, so every bar
    -- restyles once (coalesced) when LSM announces a font, statusbar or border.
    local lsm = GetLSM()
    if lsm and lsm.RegisterCallback and not lsmHooked then
        lsmHooked = true
        lsm.RegisterCallback(lsmOwner, "LibSharedMedia_Registered", function(_, mediatype)
            if mediatype ~= "font" and mediatype ~= "statusbar" and mediatype ~= "border" then return end
            Events.Coalesce("adbars_media", function()
                ForEach(nil, function(e) ApplyStyle(e) end)
            end)
        end)
    end

    Events.On("SPELL_UPDATE_COOLDOWN", "adbars", function(_, spellID, baseSpellID)
        -- a wand shot's own update carries only its lock: only the bars tracking
        -- the wand itself re-read (it is their cooldown)
        local dc = NS.DriverCooldown
        if dc and (dc.IsWandShot(spellID) or dc.IsWandShot(baseSpellID)) then
            Events.Coalesce("adbars_cdwand", function()
                ForEach("cooldown", function(e)
                    if dc.IsWandShot(SpellIDFor(e.rec)) then CooldownRefresh(e) end
                end)
            end)
            return
        end
        Events.Coalesce("adbars_cd", function() ForEach("cooldown", CooldownRefresh) end)
    end)
    Events.On("SPELL_UPDATE_CHARGES", "adbars", function()
        Events.Coalesce("adbars_charges", function()
            ForEach("cooldown", function(e) if e.isCharge then CooldownRefresh(e) end end)
        end)
    end)
    Events.On("SPELLS_CHANGED", "adbars", function()
        Events.Coalesce("adbars_spells", function()
            ForEach("cooldown", function(e)
                CooldownChargeState(e)
                CooldownRefresh(e)
            end)
            -- spell costs (cost ticks) follow ranks and talents
            ForEach("resource", LayoutTicks)
        end)
    end)
    Events.On("PLAYER_ENTERING_WORLD", "adbars", function()
        Events.Coalesce("adbars_all", function()
            ForEach(nil, function(e) Bars.Refresh(e.rec.id) end)
        end)
    end)
    -- the player's own casts are non-secret even in combat: the cooldown
    -- re-feed that SPELL_UPDATE_COOLDOWN misses inside a charge GCD, and the
    -- timer bars' trigger
    Events.On("UNIT_SPELLCAST_SUCCEEDED", "adbars", function(_, unit, _, spellID)
        if unit ~= "player" then return end
        if NS.DriverCooldown then NS.DriverCooldown.NoteCast(spellID) end
        ForEach(nil, function(e)
            local d = e.rec.driver
            if e.rec.barKind == "cooldown" then
                if SpellIDFor(e.rec) == spellID then CooldownRefresh(e) end
            elseif e.rec.barKind == "timer" then
                local trig = d and d.triggerType or "cast"
                if trig == "cast" and d and d.spellID == spellID then
                    TimerStart(e, d.duration)
                end
            end
        end)
    end)
    -- aura-bar presence rides UNIT_AURA (vectors are non-secret to receive;
    -- only the nil-check is read), for every unit a lane can watch
    Events.On("UNIT_AURA", "adbars", function(_, unit)
        local units = NS.DriverAura and NS.DriverAura.AURA_UNITS
        if not (units and units[unit]) and unit ~= "player" and unit ~= "target" then return end
        ForEach("aura", function(e)
            local sub = e.auraSub
            if sub and sub.unit == unit then AuraPresenceSync(e) end
        end)
    end)
    -- Power events: each type rides exactly one of the two value events, so
    -- mana skips the fast-regen rate and energy misses no tick. The payload
    -- token filters before any work.
    Events.On("UNIT_POWER_FREQUENT", "adbars", function(_, unit, token)
        if unit ~= "player" then return end
        ForEach("stack", StackRefresh)
        ForEach("resource", function(e)
            if not ResourceIsFrequent(e) then return end
            local info = POWER_ALL[e.powerType]
            if token and info and info.token ~= token then return end
            ResourceRefresh(e)
        end)
    end)
    SafeOn("UNIT_POWER_UPDATE", "adbars", function(_, unit, token)
        if unit ~= "player" then return end
        ForEach("resource", function(e)
            if ResourceIsFrequent(e) then return end
            local info = POWER_ALL[e.powerType]
            if token and info and info.token ~= token then return end
            ResourceRefresh(e)
        end)
    end)
    Events.On("UNIT_MAXPOWER", "adbars", function(_, unit)
        if unit ~= "player" then return end
        ForEach("stack", StackRefresh)
        ForEach("resource", function(e)
            e.lastMax = nil           -- force the range re-read
            ResourceRefresh(e)
        end)
    end)
    -- the displayed power changed (druid form, vehicle): re-resolve the type
    SafeOn("UNIT_DISPLAYPOWER", "adbars", function(_, unit)
        if unit ~= "player" then return end
        ForEach("resource", ResourceEnsure)
    end)
    -- a shapeshift lands a moment before the new power's max is readable, so
    -- the form event gets one settle delay
    SafeOn("UPDATE_SHAPESHIFT_FORM", "adbars", function()
        if formPending then return end
        formPending = true
        C_Timer.After(0.1, function()
            formPending = false
            ForEach("resource", ResourceEnsure)
        end)
    end)
    -- Classic combo points live on the target: a swap changes the count
    -- without a power event (own key; the aura target watch has its own).
    if NS.IsForever == true then
        Events.On("PLAYER_TARGET_CHANGED", "adbarsres", function()
            ForEach("resource", function(e)
                if e.powerType == 4 then ResourceRefresh(e) end
            end)
        end)
    end
end

local function ReleaseSharedEvents()
    if not sharedArmed or next(live) then return end
    sharedArmed = false
    for _, ev in ipairs({
        "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED",
        "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA",
        "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
        -- the probe-registered ones too (Events.Off is a no-op for an event
        -- that never registered, so the probe needs no mirror here)
        "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UPDATE_SHAPESHIFT_FORM",
    }) do
        Events.Off(ev, "adbars")
    end
    Events.Off("PLAYER_TARGET_CHANGED", "adbarsres")
end

-- Engine seam

-- re-read the driver and repaint one bar
function Bars.Refresh(barId)
    local e = live[barId]
    if not e then return end
    local kind = e.rec.barKind
    if kind == "cooldown" then
        CooldownRefresh(e)
    elseif kind == "stack" then
        StackRefresh(e)
        ApplyVisibility(e)
    elseif kind == "resource" then
        -- A full refresh re-resolves the type and busts the setter memos;
        -- without it a resource bar would take the timer path and hide itself.
        ResourceEnsure(e)
    elseif kind == "health" then
        -- Same reason: without it a health bar would fall to the timer path.
        HB.Ensure(e)
    elseif kind == "swing" then
        SwingRefresh(e)
        if Bars.SwingOH then Bars.SwingOH.Refresh(e) end
    elseif kind == "aura" then
        if e.auraSub then
            AuraPresenceSync(e)
        else
            e.stateHidden = true
            ApplyVisibility(e)
        end
    elseif Bars.KINDS[kind] then
        local KR = Bars.KINDS[kind]
        if KR.Refresh then KR.Refresh(e) end
    else
        if not e.running then
            e.stateHidden = R(e.rec, "behavior", "hideWhenInactive") and true or false
        end
        ApplyVisibility(e)
    end
end

-- Called on every engine rebuild; the holder is already sized and placed.
function Bars.EnsureBar(rec, holder)
    if not (rec and holder) then return end
    local e = live[rec.id]

    -- A kind or mode change is a different bar: tear down first (aura too,
    -- since the engine widget slots differ per mode).
    if e and (e.kind ~= rec.barKind
        or ((rec.barKind == "cooldown" or rec.barKind == "aura")
            and e.mode ~= (rec.barMode or "duration"))) then
        Bars.Release(rec.id)
        e = nil
    end

    if not e then
        e = { rec = rec, holder = holder, kind = rec.barKind,
            mode = rec.barMode or "duration" }
        e.shell = BuildShell(holder)
        live[rec.id] = e
        if rec.barKind == "cooldown" then CooldownBuild(e) end
        local KB = Bars.KINDS[rec.barKind]
        if KB and KB.Build then KB.Build(e) end
        e.shell._adResize = function()
            local cur = live[rec.id]
            if not cur then return end
            if cur.kind == "cooldown" and cur.mode == "stack" then
                LayoutSlots(cur)
            elseif cur.kind == "stack" then
                LayoutDividers(cur.shell, cur.rec, cur.segments or 1)
            elseif cur.kind == "resource" then
                LayoutPips(cur)
                PredictLayout(cur)
            elseif cur.kind == "health" then
                HB.Layout(cur)
            elseif cur.kind == "aura" then
                AuraLayoutAll(cur)
            elseif Bars.KINDS[cur.kind] and Bars.KINDS[cur.kind].Relayout then
                Bars.KINDS[cur.kind].Relayout(cur)
            end
            LayoutTicks(cur)
        end
        EnsureSharedEvents()
    end

    -- the record and holder can both be re-created between rebuilds
    e.rec = rec
    if e.holder ~= holder then
        e.holder = holder
        e.shell:SetParent(holder)
        e.shell:SetAllPoints(holder)
    end

    -- Rebuild the threshold curve before styling: with no curve the ticker
    -- stops here, so ApplyStyle writes the base colour.
    if rec.barKind == "cooldown" then
        e.curve, e.curveHash = BuildCooldownCurve(e)
        if not e.curve then StopColorTicker(e, false) end
    else
        e.curve, e.curveHash = nil, nil
    end
    -- The aura composition plan before styling too: ApplyStyle needs to know
    -- whether the base fill goes flat and which colour it carries.
    if rec.barKind == "aura" then AuraPlan(e) end

    ApplyStyle(e)

    if rec.barKind == "cooldown" then
        CooldownChargeState(e)
        CooldownRefresh(e)
    elseif rec.barKind == "stack" then
        e.segments = nil          -- force a divider rebuild at the new width
        StackRefresh(e)
        ApplyVisibility(e)
    elseif rec.barKind == "resource" then
        ResourceEnsure(e)
    elseif rec.barKind == "health" then
        HB.Ensure(e)
    elseif rec.barKind == "swing" then
        LayoutDividers(e.shell, rec, 1)
        -- Threshold colours: the shared GetTime fill loop reads plainThresh
        -- every tick, so a settings change shows on the next one.
        e.plainThresh = BuildPlainBands(rec)
        EnsureSwingEvents()
        if e.running then
            ApplyVisibility(e)
        else
            SwingIdle(e)
        end
    elseif rec.barKind == "aura" then
        -- The engine drives the fill and every colour layer. AuraBarEnsure
        -- retries each rebuild while the engine or creation is unavailable.
        AuraLayoutAll(e)
        if AuraBarEnsure(e) then
            AuraPresenceSync(e)
        else
            -- no engine (or deferred): styled shell, edit sessions only
            e.shell.fill:SetMinMaxValues(0, 1)
            e.shell.fill:SetValue(0)
            e.stateHidden = true
            ApplyVisibility(e)
        end
    elseif Bars.KINDS[rec.barKind] then
        local KE = Bars.KINDS[rec.barKind]
        if KE.Ensure then KE.Ensure(e) end
    else
        e.shell.fill:SetMinMaxValues(0, 1)
        if not e.running then
            e.shell.fill:SetValue(0)
            e.stateHidden = R(rec, "behavior", "hideWhenInactive") and true or false
        end
        LayoutDividers(e.shell, rec, 1)
        ApplyVisibility(e)
    end

    -- ticks last: every kind's unit (slots, max stacks, range) is known now
    LayoutTicks(e)

    -- stays hidden while Play on screen draws the preview on this frame
    e.shell:SetShown(Bars.screenRecId ~= rec.id)
end

function Bars.Release(barId)
    local e = live[barId]
    if not e then return end
    if e.shell then
        e.shell.fill:SetScript("OnUpdate", nil)
        e.shell:Hide()
        e.shell:SetParent(UIParent)
        e.shell:ClearAllPoints()
    end
    if e.sCD then
        e.sCD:SetScript("OnShow", nil)
        e.sCD:SetScript("OnHide", nil)
        e.sCD:SetScript("OnCooldownDone", nil)
        e.sCD:Clear()
    end
    if e.sCharge then
        e.sCharge:SetScript("OnCooldownDone", nil)
        e.sCharge:Clear()
    end
    -- offscreen detectors are UIParent children: hide them with the entry
    if e.slotList then
        for _, s in pairs(e.slotList) do
            if s.detector then s.detector:Hide() end
        end
    end
    if e.predTex then e.predTex:Hide() end
    e.predCost = nil
    -- cost-icon detectors are UIParent children too
    if e.costIcons then
        for _, ci in ipairs(e.costIcons) do ci.det:Hide() ci.f:Hide() end
    end
    if e.pips then
        for _, p in ipairs(e.pips) do p.f:Hide() end
    end
    live[barId] = nil          -- out of `live` first: the aura release scans it
    AuraBarRelease(e)
    HB.Disarm()                -- the last health bar takes its events with it
    local KX = Bars.KINDS[e.kind]
    if KX and KX.Release then KX.Release(e) end
    if e.kind == "swing" and Bars.SwingOH then Bars.SwingOH.Release(e) end
    if e.kind == "swing" and Bars.SwingClose then Bars.SwingClose.Release(e) end
    if (e.kind == "swing" or e.kind == "timer") and Bars.Spark then Bars.Spark.Release(e) end
    if e.kind == "swing" and Bars.SwingRange then Bars.SwingRange.Release(e) end
    if e.kind == "swing" and Bars.SwingAbil then Bars.SwingAbil.Release(e) end
    if e.kind == "swing" and Bars.SwingColor then Bars.SwingColor.Release(e) end
    ReleaseSharedEvents()
    ReleaseSwingEvents()
    ReleasePredictEvents()
end

-- test hook: start a timer bar by hand
function Bars.StartTimer(barId, seconds)
    local e = live[barId]
    if e and e.kind == "timer" then TimerStart(e, seconds) end
end

-- Editor preview: built by the live pipeline (BuildShell, ApplyStyle, the
-- layouts), then fed simulated plain values so every style setting shows while
-- the bar's states loop. A preview entry is never in `live`, so no game event,
-- coalesce key or Bars.Refresh reaches it. It gets its own _adResize, no
-- CooldownBuild shadows (their OnCooldownDone refreshes the live bar) and no
-- aura container (containers are never destroyed, and creation is refused
-- while auras are secret); an aura preview is the shell, coloured from the
-- plain value. Colours and texts come from the plain fraction, never
-- UnitPowerPercent or a duration object. Entries are cached per kind and mode
-- and re-pointed at the selected record; frames are never destroyed.
local PV = { cache = {}, screenCache = {}, mode = "loop", t = 0, acc = 0 }

-- the chips the pane offers for this bar: "static" and, where the bar has
-- states to play, "loop"
function Bars.PreviewModes(rec)
    local k, stack = rec.barKind, rec.barMode == "stack"
    local KP = Bars.KINDS[k]
    if KP and KP.PreviewModes then return KP.PreviewModes(rec) end
    if k == "health" then
        return { { key = "static", text = "Preview",
            tip = "The health preview: 65% health with incoming heals and shields, in your colours and texts." } }
    elseif k == "stack" then
        -- the legacy stack kind (dormant, not creatable): its styled look only
        return { { key = "static", text = "Preview", tip = "The bar's look." } }
    elseif k == "resource" then
        return {
            { key = "static", text = "Static", tip = "The bar at 60%, standing still." },
            { key = "loop", text = "Fill loop",
              tip = "The value runs from empty to full and back: threshold colours, pips and every text follow it." },
        }
    elseif k == "cooldown" and stack then
        return {
            { key = "static", text = "Full", tip = "Every charge ready." },
            { key = "loop", text = "Charge loop",
              tip = "Every charge spent, then each one recharges in turn: slot fills, recharge colour, count and countdown." },
        }
    elseif k == "cooldown" then
        return {
            { key = "static", text = "Ready", tip = "The ready look, with the Ready text when it is on." },
            { key = "loop", text = "Cooldown loop",
              tip = "Ready, then a short cooldown, then ready again: the fill, threshold colours and countdown text." },
        }
    elseif k == "aura" and stack then
        return {
            { key = "static", text = "Stacks", tip = "The aura at 3 stacks." },
            { key = "loop", text = "Stack loop",
              tip = "The stacks climb to the maximum and drop: stack colours, the max colour and the count." },
        }
    elseif k == "aura" then
        return {
            { key = "static", text = "Aura up", tip = "The aura with 60% of its duration left." },
            { key = "loop", text = "Aura loop",
              tip = "The aura counts down, drops off, and comes back: threshold colours and the duration text." },
        }
    elseif k == "swing" then
        return {
            { key = "static", text = "Idle", tip = "The bar between swings." },
            { key = "loop", text = "Swing loop", tip = "Swing after swing at your weapon's speed." },
        }
    end
    return {
        { key = "static", text = "Idle", tip = "The bar with no timer running." },
        { key = "loop", text = "Timer loop", tip = "The timer runs out, rests, and starts again." },
    }
end

function Bars.PreviewTicking()
    return PV.e ~= nil and PV.mode == "loop" and PV.e.kind ~= "health" and PV.e.kind ~= "stack"
end

-- the plain maximum of a resource bar's power (the live cache, else a
-- plain read, else a sensible sample)
function PV.ResourceRange(e)
    local pt = e.powerType
    local m = pt and cachedMax[pt]
    if not m and pt and UnitPowerMax then
        local v = UnitPowerMax("player", pt)
        if v ~= nil and not (issecretvalue and issecretvalue(v)) and v > 0 then
            cachedMax[pt] = v      -- the same plain value ResourceRefresh keeps
            m = v
        end
    end
    return m or ((pt == 4) and 5 or 100)
end

-- the swing length a preview runs: the hand's plain speed, else 2.6 s
function PV.SwingLen(rec)
    local st = (rec.driver and rec.driver.swingType) or 0
    local v
    if st == 2 then
        v = UnitRangedDamage and UnitRangedDamage("player")
    elseif UnitAttackSpeed then
        local mh, oh = UnitAttackSpeed("player")
        v = (st == 1) and oh or mh
    end
    if v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "number" and v > 0 then
        return v
    end
    return 2.6
end

-- a preview length in seconds for duration kinds: the bar's own reference,
-- kept short enough to watch
function PV.Length(e)
    local rec, v = e.rec, nil
    if e.kind == "cooldown" then
        v = CooldownRefSeconds(e)
    elseif e.kind == "aura" then
        v = R(rec, "thresholds", "threshRef")
    elseif e.kind == "timer" then
        v = tonumber(rec.driver and rec.driver.duration)
    end
    v = tonumber(v) or 8
    if v < 3 then v = 3 elseif v > 12 then v = 12 end
    return v
end

-- the countdown as the live text would read it (plain math: the preview's
-- own clock). The aura engine's stock text adds " s"; decimals, M:SS or
-- colour bands switch it to the shared formatter's bare numbers.
function PV.DurText(e, remaining)
    if remaining <= 0 then return "" end
    local rec = e.rec
    local decOn = R(rec, "text", "durDecimalsEnabled") == true
    local decTo = R(rec, "text", "durDecimalThreshold") or 10
    local abbrev = R(rec, "text", "durAbbrev") or 0
    local down = BarRounding(rec) == "down"
    if decOn or abbrev > 60 or TextBands(e) ~= nil then
        return NS.Factory.FormatCountdown(remaining, decOn and decTo or 0, abbrev, down)
    end
    local s = down and math.floor(remaining) or math.ceil(remaining)
    return tostring(s) .. " s"
end

-- the duration band colour a plain remaining fraction falls in (the timer
-- rule: the smallest band the value fits under wins)
function PV.DurationColor(e, frac, ref)
    local bands = DurationBands(e.rec, ref)
    if bands then
        for _, b in ipairs(bands) do
            if frac <= b.f then return b.color, true end
        end
    end
    return { BarColorOf(e.rec) }, false
end

-- the stack colour a plain count shows (flip: the highest band reached;
-- the max colour on top at the maximum)
function PV.StackColor(e, count, M)
    local rec = e.rec
    if count >= M and R(rec, "stackcolors", "maxColorEnabled") == true then
        return R(rec, "stackcolors", "maxColor") or { 0, 1, 0, 1 }
    end
    local bands = StackBands(rec, M)
    if bands then
        for k = #bands, 1, -1 do
            if count >= bands[k].from then return bands[k].color end
        end
    end
    return { BarColorOf(rec) }
end

-- the cooldown parts a preview needs: the text-only Cooldown and the slot
-- host, never the dual shadows (they refresh the live bar by id)
function PV.CooldownParts(e)
    local shell = e.shell
    if not e.slotHost then
        e.slotHost = CreateFrame("Frame", nil, shell)
        e.slotHost:SetAllPoints(shell.fill)
        e.slotHost:SetFrameLevel(shell.fill:GetFrameLevel() + 1)
        e.slotList = {}
    end
    if not e.durCD then
        local dcd = CreateFrame("Cooldown", nil, shell.overlay, "CooldownFrameTemplate")
        dcd:SetAllPoints(shell.overlay)
        dcd:SetDrawSwipe(false)
        dcd:SetDrawEdge(false)
        dcd:SetDrawBling(false)
        dcd:SetHideCountdownNumbers(false)
        -- As on the live bar: the widget only draws numbers for a total
        -- duration above its minimum, and 0 shows every cooldown.
        if dcd.SetMinimumCountdownDuration then dcd:SetMinimumCountdownDuration(0) end
        dcd:EnableMouse(false)
        dcd:Show()
        e.durCD = dcd
    end
end

-- the size-dependent layouts, closed over the preview entry
function PV.Relayout(e)
    if e.kind == "cooldown" and e.mode == "stack" then
        LayoutSlots(e)
    elseif e.kind == "resource" then
        LayoutPips(e)
    elseif e.kind == "health" then
        HB.Layout(e)
    elseif e.kind == "aura" or e.kind == "timer" or e.kind == "swing" then
        LayoutDividers(e.shell, e.rec, 1)
    elseif Bars.KINDS[e.kind] and Bars.KINDS[e.kind].Relayout then
        Bars.KINDS[e.kind].Relayout(e)
    end
    LayoutTicks(e)
end

-- Painting one moment, per kind

function PV.PaintResource(e, cur)
    local shell, rec = e.shell, e.rec
    local range = PV.ResourceRange(e)
    if e.lastMax ~= range then
        e.lastMax = range
        shell.fill:SetMinMaxValues(0, range)
        LayoutPips(e)
        LayoutTicks(e)
    end
    local r, g, b = PowerColorOf(rec, e.powerType)
    local curve = ResourceCurve(e)
    if curve and range > 0 then
        local col = curve:Evaluate(cur / range)
        if col then r, g, b = col:GetRGB() end
    end
    e.cr, e.cg, e.cb = r, g, b
    shell.fill:SetStatusBarColor(r, g, b, 1)
    if e.pipsOn then
        PaintPips(e)
        for i = 1, e.pipCount or 0 do
            local p = e.pips[i]
            if p then p.litBar:SetValue(cur) end
        end
    else
        shell.fill:SetValue(cur)
    end
    -- a preview's cost icons read as affordable (their detectors stay idle)
    for i = 1, e.costIconCount or 0 do
        local ci = e.costIcons and e.costIcons[i]
        if ci then ci.lit:SetAlpha(1) end
    end
    local tinted = curve ~= nil and R(rec, "powerthresholds", "pthText") == true
    local count = R(rec, "text", "resCount") or 1
    for _, run in ipairs(RES_RUNS) do
        local fs = shell.texts[run.key]
        if fs and run.n <= count then
            local fmt = R(rec, "text", run.fmt) or "value"
            local s
            if fmt == "none" then s = ""
            elseif fmt == "abbreviated" and AbbreviateNumbers then s = AbbreviateNumbers(cur)
            elseif fmt == "percent" then s = string.format("%d%%", math.floor(cur / range * 100 + 0.5))
            elseif fmt == "valuemax" then s = string.format("%d / %d", cur, range)
            else s = tostring(cur) end
            SetRunText(shell, run.key, s)
            if tinted then
                fs:SetTextColor(r, g, b, 1)
            else
                local c = R(rec, "text", TEXT_DEF_BY_KEY[run.key].colour) or { 0.95, 0.97, 1, 1 }
                fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
end

function PV.PaintHealth(e)
    local unit = HB.Unit(e)
    e.hpUnit, e.hpPreview = unit, true
    e.shell:SetAlpha(1)
    HB.PaintBase(e, unit, true)
    HB.Name(e, unit, true)
    HB.Values(e, true)
end

-- a cooldown's continuous fill at `remaining` of `len` (0 = ready)
function PV.PaintCooldown(e, remaining, len, started)
    local shell, rec = e.shell, e.rec
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    local readyFS = shell.texts.ready
    if remaining <= 0 then
        shell.fill:SetMinMaxValues(0, 1)
        shell.fill:SetValue(R(rec, "fill", "idleEmpty") == true and 0 or 1)
        shell.fill:SetStatusBarColor(BarColorOf(rec))
        if e.durCD then e.durCD:Clear() end
        if readyFS and readyFS:IsShown() then readyFS:SetText(R(rec, "text", "readyText") or "Ready") end
        return
    end
    shell.fill:SetMinMaxValues(0, len)
    shell.fill:SetValue(drain and remaining or (len - remaining))
    if e.curve then
        local col = e.curve:Evaluate(remaining / len)
        if col then shell.fill:SetStatusBarColor(col:GetRGB()) end
    else
        shell.fill:SetStatusBarColor(BarColorOf(rec))
    end
    -- plain numbers on our own Cooldown widget: the countdown renders C-side
    -- with the bar's formatter, exactly as live (nothing here is secret)
    if started and e.durCD then e.durCD:SetCooldown(started, len) end
    if readyFS and readyFS:IsShown() then readyFS:SetText("") end
end

-- the charge slots with `count` full and the next one `p` of the way back
function PV.PaintCharges(e, count, p, rechargeStart, len)
    local rec = e.rec
    local n = e.slots or 1
    local fullOn = R(rec, "segments", "fullColorEnabled") == true
    local fc = fullOn and (R(rec, "segments", "fullColor") or { 0.482, 0.847, 0.561, 1 })
    local br, bg2, bb, ba = BarColorOf(rec)
    ReassertBaseColors(e)
    for i = 1, n do
        local s = e.slotList[i]
        if s then
            s.full:SetValue(count)
            if fc then s.full:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
            else s.full:SetStatusBarColor(br, bg2, bb, ba) end
            -- the cascade, plain: every slot up to the recharging one shows
            local a = (i <= count + 1) and 1 or 0
            s.recharge:SetAlpha(a)
            s.full:SetAlpha(a)
            s.recharge:SetMinMaxValues(0, 1)
            s.recharge:SetValue((i == count + 1) and p or 0)
            if i == count + 1 and e.curve and p > 0 then
                local col = e.curve:Evaluate(1 - p)
                if col then s.recharge:GetStatusBarTexture():SetVertexColor(col:GetRGB()) end
            end
        end
    end
    SetRunText(e.shell, "stk", StackCount(rec, count))
    if e.durCD then
        if rechargeStart and count < n then e.durCD:SetCooldown(rechargeStart, len)
        else e.durCD:Clear() end
    end
end

-- an aura at `remaining` of `len` (duration) or `count` of `M` (stack)
function PV.PaintAuraDuration(e, remaining, len)
    local shell, rec = e.shell, e.rec
    local drain = (R(rec, "fill", "fillMode") or "drain") == "drain"
    shell.fill:SetMinMaxValues(0, len)
    shell.fill:SetValue(remaining <= 0 and 0 or (drain and remaining or (len - remaining)))
    local col, hit = PV.DurationColor(e, remaining / len, len)
    shell.fill:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
    SetRunText(shell, "dur", PV.DurText(e, remaining))
    SetRunText(shell, "stk", remaining > 0 and StackCount(rec, 2) or "")
    local fs = shell.texts.dur
    if fs then
        local tc = (hit and R(rec, "thresholds", "threshText") == true) and col
            or (R(rec, "text", "durColor") or { 0.95, 0.97, 1, 1 })
        fs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    end
end

function PV.PaintAuraStack(e, count, M)
    local shell, rec = e.shell, e.rec
    shell.fill:SetMinMaxValues(0, M)
    shell.fill:SetValue(count)
    local col = PV.StackColor(e, count, M)
    shell.fill:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
    SetRunText(shell, "stk", StackCount(rec, count))
end

-- The current moment of the current mode

-- a triangle wave 0..1..0 over `period` seconds
function PV.Tri(t, period)
    local x = (t % period) / period
    return (x < 0.5) and (x * 2) or (2 - x * 2)
end

function PV.Apply(e, fresh)
    local rec, loop, t = e.rec, PV.mode == "loop", PV.t
    local kind = e.kind
    if kind == "health" then
        PV.PaintHealth(e)
    elseif kind == "resource" then
        local range = PV.ResourceRange(e)
        local cur
        if loop then
            local f = PV.Tri(t, 4)
            cur = math.floor(f * range + 0.5)
        else
            cur = math.floor(range * 0.6 + 0.5)
        end
        PV.PaintResource(e, cur)
    elseif kind == "cooldown" and e.mode == "stack" then
        local n = e.slots or 1
        local len = e.pvLen or 8
        if not loop then
            PV.PaintCharges(e, n, 0, nil, len)
        else
            -- spend everything, recharge one slot at a time, hold full
            local cycle = n * len + 1.5
            local x = t % cycle
            local count = math.min(n, math.floor(x / len))
            local p = (count < n) and ((x - count * len) / len) or 0
            local start = (count < n) and (GetTime() - (x - count * len)) or nil
            if fresh or count ~= e.pvCount then
                e.pvCount = count
                PV.PaintCharges(e, count, p, start, len)
            else
                PV.PaintCharges(e, count, p, nil, len)
            end
        end
    elseif kind == "cooldown" then
        local len = e.pvLen or 8
        if not loop then
            PV.PaintCooldown(e, 0, len)
        else
            local cycle = len + 1.5
            local x = t % cycle
            if x < 1.5 then
                e.pvCdOn = nil
                PV.PaintCooldown(e, 0, len)
            else
                local elapsed = x - 1.5
                local started
                if fresh or not e.pvCdOn then
                    e.pvCdOn = true
                    started = GetTime() - elapsed
                end
                PV.PaintCooldown(e, len - elapsed, len, started)
            end
        end
    elseif kind == "aura" and e.mode == "stack" then
        local M = e.pvM or 5
        local count
        if loop then
            local step = 0.5
            local cycle = (M + 1) * step + 1
            local x = t % cycle
            count = math.min(M, math.floor(x / step))
        else
            count = math.min(3, M)
        end
        PV.PaintAuraStack(e, count, M)
    elseif kind == "aura" then
        local len = e.pvLen or 8
        if loop then
            local x = t % (len + 1)
            PV.PaintAuraDuration(e, (x < len) and (len - x) or 0, len)
        else
            PV.PaintAuraDuration(e, len * 0.6, len)
        end
    elseif kind == "swing" or kind == "timer" then
        -- the live GetTime loop itself (RunTimedFill); the tick restarts it
        if not loop then
            e.shell.fill:SetScript("OnUpdate", nil)
            if kind == "swing" then SwingIdle(e) else TimerStop(e) end
        elseif fresh or not (e.running or e.pvRestartAt) then
            PV.RunTimed(e)
        end
        if kind == "swing" and Bars.SwingOH then Bars.SwingOH.Preview(e, loop, fresh) end
    elseif Bars.KINDS[kind] and Bars.KINDS[kind].PreviewApply then
        Bars.KINDS[kind].PreviewApply(e, loop, t, fresh)
    end
end

function PV.RunTimed(e)
    e.pvRestartAt = nil
    local len = (e.kind == "swing") and e.swingLen or (e.pvLen or 8)
    RunTimedFill(e, len, function(done)
        if done.kind == "swing" then SwingIdle(done) else TimerStop(done) end
        done.pvRestartAt = GetTime() + ((done.kind == "swing") and 0.35 or 0.8)
    end)
end

-- The API the options pane drives

-- (re)build the preview for `rec` on `holder` and paint the current moment.
-- Called on every pane refresh (settings changes arrive coalesced).
function Bars.PreviewBuild(rec, holder)
    return PV.Build(rec, holder, false)
end

-- screen = the Play on screen copy, drawn on the real bar's own frame: that
-- frame's size and opacity stay the live bar's, and it needs no pixel ref.
function PV.Build(rec, holder, screen)
    if not (rec and holder) then return nil end
    local mode = rec.barMode or "duration"
    local key = tostring(rec.barKind) .. ":" .. mode
    local cache = screen and PV.screenCache or PV.cache
    local e = cache[key]
    local cur = PV.e
    if screen then cur = PV.se end
    if cur and cur ~= e then
        if screen then
            PV.se = nil
            PV.Park(cur)
        else
            Bars.PreviewRelease()
        end
    end
    if not screen then
        local LE = NS.LayoutEngine
        holder._adPxRef = (LE and LE.GetBarFrame and LE.GetBarFrame(rec.id)) or UIParent
        -- the holder's size, the way the engine's PlaceBar sets it (scale
        -- multiplies width / height, never SetScale - the pane owns SetScale)
        local w = R(rec, "size", "width") or 220
        local h = R(rec, "size", "height") or 16
        local sc = R(rec, "size", "scale") or 1
        local px = Px(holder)
        local function Snap(v) return math.max(px, math.floor(v / px + 0.5) * px) end
        holder:SetSize(Snap(math.max(8, w * sc)), Snap(math.max(4, h * sc)))
    end
    if not e then
        e = { holder = holder, kind = rec.barKind, mode = mode, isPreview = true }
        e.shell = BuildShell(holder)
        if e.kind == "cooldown" then PV.CooldownParts(e) end
        -- a kind in its own file builds its widgets on the preview entry too
        local KB = Bars.KINDS[e.kind]
        if KB and KB.Build then KB.Build(e) end
        e.shell._adResize = function() if PV.e == e or PV.se == e then PV.Relayout(e) end end
        cache[key] = e
    end
    local newRec = e.rec ~= rec
    e.rec, e.holder = rec, holder
    if e.shell:GetParent() ~= holder then
        e.shell:SetParent(holder)
        e.shell:ClearAllPoints()
        e.shell:SetAllPoints(holder)
    end
    e.shell._adPxRef = (not screen) and holder._adPxRef or nil
    if newRec then
        e.lastMax, e.cr, e.cg, e.cb, e.segments = nil, nil, nil, nil, nil
        e.pvCount, e.pvCdOn, e.running = nil, nil, nil
    end
    -- The game's countdown keeps the font size it had when its cooldown last
    -- started, so after a zoom the countdown restarts at the same moment.
    local es = holder:GetEffectiveScale()
    if e.pvScale ~= es then
        e.pvScale = es
        e.pvCdOn, e.pvCount = nil, nil
        if e.durCD then e.durCD._adFontName = nil end
    end
    if screen then PV.se = e else PV.e = e end
    -- the recipes styling reads, as EnsureBar builds them (no aura plan: the
    -- preview's base fill keeps its texture and carries the band colours)
    if e.kind == "cooldown" then
        e.curve, e.curveHash = BuildCooldownCurve(e)
    else
        e.curve, e.curveHash = nil, nil
    end
    if e.kind == "resource" then
        ResourceSyncType(e)
        e.lastMax, e.pthCurve, e.pthHash = nil, nil, nil
    end
    if e.kind == "swing" then e.swingLen = PV.SwingLen(rec) end
    if e.kind == "swing" or e.kind == "timer" then e.plainThresh = BuildPlainBands(rec) end
    -- the loop's length and an aura's maximum, read once per build (the
    -- loop paints 30 times a second and must not re-ask the game)
    e.pvLen = PV.Length(e)
    e.pvM = (e.kind == "aura" and e.mode == "stack") and math.max(1, AuraMaxStacks(rec)) or nil
    ApplyStyle(e)
    -- the live aura sheen rides the engine fill; the preview uses the shell's
    if e.kind == "aura" then
        e.shell.sheen:SetShown(R(rec, "fill", "useGradient") ~= false)
    end
    if e.kind == "cooldown" then
        CooldownChargeState(e)
    elseif e.kind == "health" then
        HB.BuildBands(e)
        HB.StyleOverlays(e)
    elseif Bars.KINDS[e.kind] and Bars.KINDS[e.kind].PreviewBuild then
        Bars.KINDS[e.kind].PreviewBuild(e)
    end
    e.stateHidden = false
    if not screen then ApplyVisibility(e) end
    PV.Relayout(e)
    e.shell:Show()
    PV.Apply(e, newRec)
    return e
end

-- "static" or "loop": the loop clock starts over
function Bars.PreviewSetMode(mode)
    PV.mode = (mode == "static") and "static" or "loop"
    PV.t, PV.acc = 0, 0
    for _, e in pairs({ pane = PV.e, screen = PV.se }) do
        e.pvCount, e.pvCdOn, e.pvRestartAt = nil, nil, nil
        e.shell.fill:SetScript("OnUpdate", nil)
        e.running = nil
        PV.Apply(e, true)
    end
end

function Bars.PreviewMode() return PV.mode end

-- the pane's OnUpdate while a loop runs: ~30 paints a second, and the
-- swing / timer loops restart after their rest. The Play on screen copy
-- runs on the same clock.
function Bars.PreviewTick(elapsed)
    if not PV.e or PV.mode ~= "loop" then return end
    PV.t = PV.t + (elapsed or 0)
    PV.acc = PV.acc + (elapsed or 0)
    local paint = PV.acc >= 0.033
    if paint then PV.acc = 0 end
    PV.TickOne(PV.e, paint)
    PV.TickOne(PV.se, paint)
end

function PV.TickOne(e, paint)
    if not e then return end
    if e.kind == "swing" or e.kind == "timer" then
        if not e.running and e.pvRestartAt and GetTime() >= e.pvRestartAt then PV.RunTimed(e) end
        -- the off-hand track keeps its own clock, half a swing behind
        if e.kind == "swing" and Bars.SwingOH then Bars.SwingOH.Preview(e, true, false) end
    elseif paint then
        PV.Apply(e, false)
    end
end

-- stops an entry's loops and hides it; its frames stay cached
function PV.Park(e)
    e.shell.fill:SetScript("OnUpdate", nil)
    e.running, e.pvRestartAt = nil, nil
    if e.durCD then e.durCD:Clear() end
    e.shell:Hide()
    -- UIParent children (slot and cost detectors) hide with the entry
    for _, s in pairs(e.slotList or {}) do if s.detector then s.detector:Hide() end end
    for _, ci in ipairs(e.costIcons or {}) do ci.det:Hide() ci.f:Hide() end
end

function Bars.PreviewRelease()
    local e = PV.e
    if not e then return end
    PV.e = nil
    PV.Park(e)
end

-- Play on screen: the preview loop on the bar's real frame, in its real place
-- and size. The live shell hides meanwhile; EnsureBar keeps it hidden.
function Bars.PreviewScreenStart(rec)
    local LE = NS.LayoutEngine
    local f = rec and LE and LE.GetBarFrame and LE.GetBarFrame(rec.id)
    if not f then return false end
    if Bars.screenRecId and Bars.screenRecId ~= rec.id then Bars.PreviewScreenStop() end
    Bars.screenRecId = rec.id
    local le = live[rec.id]
    if le then le.shell:Hide() end
    PV.Build(rec, f, true)
    return true
end

function Bars.PreviewScreenStop()
    local id = Bars.screenRecId
    Bars.screenRecId = nil
    local e = PV.se
    if e then
        PV.se = nil
        PV.Park(e)
    end
    local le = id and live[id]
    if le then le.shell:Show() end
end

-- with an id: whether that bar is playing on screen
function Bars.PreviewScreenOn(id)
    return Bars.screenRecId ~= nil and (id == nil or Bars.screenRecId == id)
end

-- offline harness access
Bars._PV = PV

-- /adbars diag: what the timer path finds on this client, so a missing engine
-- piece shows directly. The addon never prints unprompted; these prints answer
-- the typed command, and no print belongs anywhere else.
SLASH_ADBARS1 = "/adbars"
SlashCmdList.ADBARS = function(msg)
    if msg ~= "diag" then
        print("|cff3fc9f2Arc Auras bars:|r /adbars diag - print the timer-path diagnosis")
        return
    end
    local count, fill = 0, nil
    for _, e in pairs(live) do
        count = count + 1
        if e.kind == "cooldown" and not fill then fill = e.shell.fill end
    end
    print("|cff3fc9f2Arc Auras bars diag|r")
    print("  live bars: " .. count)
    print("  HAS_TIMER_API: " .. tostring(HAS_TIMER_API))
    print("  interp smooth/none: " .. tostring(INTERP_SMOOTH) .. " / " .. tostring(INTERP_NONE))
    print("  dir remain/elapsed: " .. tostring(DIR_REMAIN) .. " / " .. tostring(DIR_ELAPSED))
    print("  fill:SetTimerDuration: " .. tostring(fill ~= nil and fill.SetTimerDuration ~= nil))
    print("  C_Spell.GetSpellCooldownDuration: " .. tostring(C_Spell.GetSpellCooldownDuration ~= nil))
    print("  GetSpellBaseCooldown (legacy global): " .. tostring(GetSpellBaseCooldown ~= nil))
    -- The health bars' client pieces: the heal calculator, the boolean-to-alpha
    -- and -colour sinks, the percent scale curve.
    print("  health: calculator=" .. tostring(CreateUnitHealPredictionCalculator ~= nil)
        .. " detailed=" .. tostring(UnitGetDetailedHealPrediction ~= nil)
        .. " alphaFromBool=" .. tostring(UIParent.SetAlphaFromBoolean ~= nil)
        .. " scaleTo100=" .. tostring(CurveConstants ~= nil and CurveConstants.ScaleTo100 ~= nil))
    for _, e in pairs(live) do
        if e.kind == "cooldown" then
            print(("  %s [%s] m=%s c=%s fallback=%s curveTick=%s cdRef=%s taught=%s"):format(
                tostring(e.rec.name), tostring(e.mode),
                tostring(e.sCD and e.sCD:IsShown() or false),
                tostring(e.sCharge and e.sCharge:IsShown() or false),
                tostring(e.fbRunning or false), tostring(e.colorTicking or false),
                tostring(CooldownRefSeconds(e)), tostring(e.cdLenPlain)))
        elseif e.kind == "aura" then
            -- every value through S(): a secret must never reach tostring
            local function S(v)
                if issecretvalue and issecretvalue(v) then return "<secret>" end
                return tostring(v)
            end
            local d = e.rec.driver or {}
            local sub = e.auraSub
            local s1 = sub and sub.slots[1]
            print(("  %s [aura %s] id=%s %s%s layers=%d bound=%s wired=%s slots=%s touch=%s unit=%s parked=%s shown=%s present=%s split=%s"):format(
                tostring(e.rec.name), tostring(e.mode), S(d.spellID), tostring(d.auraType or "buff"),
                " cast-by-" .. tostring(select(3, AuraShape(d)) or "anyone"), e.auraPlan and #e.auraPlan or 0,
                tostring(sub ~= nil), tostring(e.auraWired or 0), tostring(sub and #sub.slots or 0),
                tostring(s1 and AuraTouchable(s1.button) or false), tostring(sub and sub.unit),
                tostring(sub and sub.parked or false),
                tostring(sub and sub.container:IsShown() or false),
                AuraPresentText(e), tostring(e.auraSplit or false)))
        elseif e.kind == "resource" then
            -- secret=: whether this client hands the value secret right now;
            -- the probe reads, never compares
            local v = e.powerType and ResourceCurrent(e.powerType)
            print(("  %s [resource pt=%s] range=%s segments=%s curve=%s cost=%s secret=%s pips=%s"):format(
                tostring(e.rec.name), tostring(e.powerType), tostring(e.lastMax),
                tostring(e.segments), tostring(e.pthCurve ~= nil), tostring(e.predCost),
                tostring(issecretvalue and issecretvalue(v) or false),
                tostring(e.pipsOn and (e.pipCount or 0) or false)))
        elseif e.kind == "health" then
            -- every game value through S(): a secret must never reach tostring
            local function S(v)
                if issecretvalue and issecretvalue(v) then return "<secret>" end
                return tostring(v)
            end
            local u = e.hpUnit or "player"
            local o = e.hpOv
            print(("  %s [health %s] exists=%s max=%s plainMax=%s calc=%s heals=%s shields=%s healAbsorbs=%s glow=%s bands=%d preview=%s"):format(
                tostring(e.rec.name), u, S(UnitExists(u)), S(UnitHealthMax(u)), tostring(e.hpMax),
                tostring(e.hpCalc and true or false), tostring(o and o.healOn or false),
                tostring(o and o.absOn or false), tostring(o and o.haOn or false),
                tostring(o and o.glowOn or false), e.hpBandN or 0, tostring(e.hpPreview or false)))
        elseif e.kind == "swing" and e.srange and Bars.SwingRange then
            print("  " .. Bars.SwingRange.Diag(e))
        elseif Bars.KINDS[e.kind] and Bars.KINDS[e.kind].Diag then
            print("  " .. Bars.KINDS[e.kind].Diag(e))
        end
    end
end

-- Kit: the shared helpers a bar kind in its own file uses instead of copies.
-- Set here at the end, where every one of them exists.
Bars.Kit = {
    R = R, Px = Px, IsEditMode = IsEditMode, live = live, ForEach = ForEach,
    ApplyStyle = ApplyStyle, ApplyTexts = ApplyTexts, ApplyVisibility = ApplyVisibility,
    SetRunText = SetRunText, StyleFont = StyleFont, PlaceText = PlaceText,
    LayoutTicks = LayoutTicks, BarColorOf = BarColorOf, BarRounding = BarRounding,
    FeedStatusBarTimer = FeedStatusBarTimer, SafeOn = SafeOn,
    ResolveBarTexture = ResolveBarTexture, WHITE = WHITE,
    SwingHandExists = SwingHandExists, ApplySheen = ApplySheen, MakeShadow = MakeShadow,
    -- a running swing's start, length and end (GetTime plus PLAYER_SWING's
    -- plain duration), or nil between swings
    SwingClock = function(e)
        local endT, dur = e.endTime, e.duration
        if not (e.running and endT and dur) or GetTime() >= endT then return nil end
        return endT - dur, dur, endT
    end,
}
