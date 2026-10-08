-- Range bars (barKind "range"): the band the target is in, as one plate in the band's colour with its name, or as
-- a row of labelled cells with that band's cell lit; with no band, a neutral look. Plugged into the bars runtime through
-- Bars.RegisterKind and Bars.Kit; NS.DriverRange answers which band holds, from range events and a short item pulse.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R

local RB = {}
NS.RangeBars = RB

RB.OWNER = "adrangebar"
-- The editor preview shows each band this long, in seconds.
RB.CYCLE = 1.5
-- An unlit cell's label keeps this much of its colour, so the lit one leads.
RB.DIM_TEXT = 0.55

-- A distance check by yards: each item or interact index reads plain in combat
-- on hostile targets on WoW Forever. Schema.RANGE_YARDS lists the same yards.
RB.YARDS = {
    [5] = { "item", 8149 }, [10] = { "item", 9621 }, [20] = { "item", 10645 }, [28] = { "interact", 4 },
    [35] = { "item", 18904 }, [40] = { "item", 4945 },
}
-- Melee reach for any class, no melee spell needed: the 5 yard item reads true
-- in melee and false from there out, where interact 2 and 3 still read true.
RB.MELEE_YD = 5

-- The Hunter bands' colours; orange and gold are colour-picker values (n / 255).
local RED, GREEN, GREY = { 0.90, 0.22, 0.22, 1 }, { 0.30, 0.82, 0.36, 1 }, { 0.48, 0.50, 0.54, 1 }
local ORANGE, GOLD = { 1, 131 / 255, 27 / 255, 1 }, { 209 / 255, 184 / 255, 42 / 255, 1 }
local CYAN = { 0.247, 0.788, 0.949, 1 }
local CLEAR = { 0, 0, 0, 0 }

local function Spell(id, want) return { kind = "spell", id = id, want = want } end
local function Yards(yd, want) return { kind = "yd", yd = yd, want = want } end

RB.PRESETS = { "hunter", "melee", "caster" }
RB.PRESET_TEXT = { hunter = "Hunter bands", melee = "Melee: in or out of range",
    caster = "Caster: in or out of range", custom = "Custom bands" }

-- The class tables come in two versions, picked by the game version at load.
-- Forever: rank 1 IDs (the rank the player knows is found by name) and the
-- classic hunter dead zone. Retail: each class's base spell (a spec's
-- replacement follows through its override), spec tables keyed by spec ID
-- where the base spell is not that spec's, and no dead zone, since retail Auto
-- Shot reaches from melee out to 40 yards. A class or spec with no entry has
-- no default spell.
if NS.IsForever == true then
    -- Bands nearest first; the first whose checks all hold is the target's. Wing
    -- Clip reaches melee range, Auto Shot 8 to 35 yards.
    RB.HUNTER = {
        { text = "MELEE", color = RED, checks = { Spell(2974, true) } },
        { text = "DEAD", color = ORANGE, checks = { Spell(75, false), Yards(10, true) } },
        { text = "8 - 20", color = GOLD, checks = { Spell(75, true), Yards(20, true) } },
        { text = "20 - 40", color = GREEN, checks = { Spell(75, true), Yards(20, false) } },
        { text = "OUT", color = GREY, checks = { Spell(75, false), Yards(10, false) } },
    }
    RB.HUNTER_TEXT = "Wing Clip for melee, then Auto Shot with the 10 and 20 yard checks."
    -- The swing bar's range dim asks MELEE_SPELL; an untyped Melee bar checks
    -- RB.MELEE_YD, the item proven in combat here (MELEE_DEFAULT stays nil).
    RB.MELEE_SPELL = { WARRIOR = 78, ROGUE = 1752, HUNTER = 2974 }
    -- The spell a Caster bar checks when none is typed; a class with no
    -- always-usable one has none.
    RB.CASTER_SPELL = { MAGE = 133, WARLOCK = 686, PRIEST = 585, DRUID = 5176, SHAMAN = 403, HUNTER = 75 }
    -- A harmful spell each class learns early, asked when every check is an item or
    -- interact index: where UnitCanAttack reads secret, its range answer is what
    -- tells the engine the target is hostile, and that starts the item pulse.
    RB.GATE_SPELL = { WARRIOR = 78, ROGUE = 1752, HUNTER = 75, PALADIN = 853, SHAMAN = 403,
        PRIEST = 585, MAGE = 133, WARLOCK = 686, DRUID = 5176 }
else
    RB.HUNTER = {
        { text = "MELEE", color = RED, checks = { Spell(195645, true) } },
        { text = "5 - 20", color = GOLD, checks = { Spell(75, true), Yards(20, true) } },
        { text = "20 - 40", color = GREEN, checks = { Spell(75, true), Yards(20, false) } },
        { text = "OUT", color = GREY, checks = { Spell(75, false) } },
    }
    RB.HUNTER_TEXT = "Wing Clip for melee, then Auto Shot with the 20 yard check."
    -- Survival fights in melee, so it starts on the Melee preset.
    RB.PRESET_BY_SPEC = { [255] = "melee" }
    RB.MELEE_SPELL = { WARRIOR = 1464, PALADIN = 35395, HUNTER = 195645, ROGUE = 1752,
        DEATHKNIGHT = 316239, SHAMAN = 73899, MONK = 100780, DEMONHUNTER = 344859 }
    -- The rogue builders and the druid forms' attacks; Devourer's Consume
    -- reaches 25 yards, so that spec has none (false).
    RB.MELEE_SPELL_SPEC = { [259] = 1329, [260] = 193315, [261] = 53, [103] = 5221, [104] = 33917,
        [1480] = false }
    -- An untyped Melee bar checks the class spell: spell range rides an event
    -- on retail while the item pulse is unproven there. Evokers and the druid
    -- caster specs fall back to RB.MELEE_YD.
    RB.MELEE_DEFAULT = RB.MELEE_SPELL
    RB.CASTER_SPELL = { MAGE = 116, WARLOCK = 686, PRIEST = 585, DRUID = 5176, SHAMAN = 188196,
        HUNTER = 75, PALADIN = 20271, WARRIOR = 57755, DEATHKNIGHT = 47541, MONK = 117952,
        DEMONHUNTER = 185123, EVOKER = 362969 }
    -- Survival has no Auto Shot; each rogue spec throws its own.
    RB.CASTER_SPELL_SPEC = { [255] = 185358, [259] = 185565, [260] = 185763, [261] = 114014 }
    RB.GATE_SPELL = { WARRIOR = 1464, PALADIN = 20271, HUNTER = 185358, ROGUE = 1752, PRIEST = 585,
        DEATHKNIGHT = 47541, SHAMAN = 188196, MAGE = 116, WARLOCK = 686, MONK = 117952, DRUID = 8921,
        DEMONHUNTER = 185123, EVOKER = 362969 }
end
-- A check's four kinds, as the band editor names them.
RB.CHOICES = { "spellin", "spellout", "within", "beyond" }
RB.CHOICE_TEXT = { spellin = "Spell in range", spellout = "Spell out of range",
    within = "Within", beyond = "Beyond" }

local function ClassTag()
    local _, tag = UnitClass("player")
    return tag
end

-- The player's spec ID, asked only where a spec table exists (retail); nil
-- when the game gives none or a secret.
local function SpecID()
    local SI = C_SpecializationInfo
    if not (SI and SI.GetSpecialization and SI.GetSpecializationInfo) then return nil end
    local idx = SI.GetSpecialization()
    if issecretvalue and issecretvalue(idx) then return nil end
    if type(idx) ~= "number" then return nil end
    local id = SI.GetSpecializationInfo(idx)
    if issecretvalue and issecretvalue(id) then return nil end
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-- A class table's entry for the player: the spec's where a spec table names
-- one (false = none for that spec), else the class's.
local function ClassSpell(byClass, bySpec)
    if bySpec then
        local v = bySpec[SpecID() or 0]
        if v == false then return nil end
        if v then return v end
    end
    return byClass and byClass[ClassTag() or ""] or nil
end

-- Hunter bands on a hunter, else Melee; a spec may start elsewhere.
function RB.DefaultPreset()
    local p = RB.PRESET_BY_SPEC and RB.PRESET_BY_SPEC[SpecID() or 0]
    if p then return p end
    return (ClassTag() == "HUNTER") and "hunter" or "melee"
end

function RB.Preset(rec)
    local d = rec and rec.driver
    local p = d and d.preset
    if p == "custom" and type(d.bands) == "table" then return "custom" end
    if p == "hunter" or p == "melee" or p == "caster" then return p end
    return RB.DefaultPreset()
end

-- A preset's class default when no spell is typed: a Caster bar's ranged spell,
-- a Melee bar's melee spell where MELEE_DEFAULT names one; nil otherwise.
function RB.DefaultSpell(preset)
    if preset == "caster" then return ClassSpell(RB.CASTER_SPELL, RB.CASTER_SPELL_SPEC) end
    if preset == "melee" then return ClassSpell(RB.MELEE_DEFAULT, RB.MELEE_SPELL_SPEC) end
    return nil
end

-- The typed spell, else the preset's class default; nil for the other presets
-- and for a Melee bar with none (it checks RB.MELEE_YD).
function RB.SpellFor(rec, preset)
    preset = preset or RB.Preset(rec)
    if preset ~= "melee" and preset ~= "caster" then return nil end
    local id = tonumber(rec.driver and rec.driver.spellID)
    if id and id > 0 then return id end
    return RB.DefaultSpell(preset)
end

-- A preset's bands; Melee and Caster are in or out of range of their one spell,
-- a Melee bar with no spell typed of the melee yards.
function RB.PresetBands(rec, preset)
    preset = preset or RB.Preset(rec)
    if preset == "hunter" then return RB.HUNTER end
    local sid = RB.SpellFor(rec, preset)
    if preset == "melee" and not sid then
        return {
            { text = "IN RANGE", color = GREEN, checks = { Yards(RB.MELEE_YD, true) } },
            { text = "OUT OF RANGE", color = GREY, checks = { Yards(RB.MELEE_YD, false) } },
        }
    end
    return {
        { text = "IN RANGE", color = GREEN, checks = { Spell(sid, true) } },
        { text = "OUT OF RANGE", color = GREY, checks = { Spell(sid, false) } },
    }
end

-- The bar's bands: its own list once edited, else its preset's.
function RB.BandsOf(rec)
    if RB.Preset(rec) == "custom" then return rec.driver.bands end
    return RB.PresetBands(rec)
end

-- The indexes of the bands a switch has not turned off, nearest first.
function RB.ShownIdx(list)
    local out = {}
    for i, b in ipairs(list) do
        if not b.off then out[#out + 1] = i end
    end
    return out
end

-- One band's checks as the range engine reads them ({ kind, id, inRange }). An
-- unfinished check (no spell yet) leaves the band none, so it never holds.
local function EngineChecks(band)
    local out = {}
    for _, k in ipairs(band.checks or {}) do
        local c
        if k.kind == "spell" then
            local id = tonumber(k.id)
            if id and id > 0 then c = { "spell", id, k.want == true } end
        elseif k.kind == "yd" then
            local m = RB.YARDS[tonumber(k.yd) or 0]
            if m then c = { m[1], m[2], k.want == true } end
        end
        if not c then return {} end
        out[#out + 1] = c
    end
    return out
end

function RB.EngineBands(list)
    local out = {}
    for i, b in ipairs(list) do out[i] = { key = i, checks = EngineChecks(b) } end
    return out
end

-- What the checks need from the range engine: spells, items and interact indexes,
-- plus the target gate (a dead target is in no band). Item and interact checks
-- are what switch the engine's pulse on. `d` (the record's driver) brings its
-- Auto rank and Ignore override to the spells' resolve.
function RB.Need(bands, d)
    local out, seen = { spells = {}, items = {}, interact = {}, gate = true }, {}
    if type(d) == "table" then
        out.follow, out.noOverride = NS.Store.AutoRankOn(d), d.ignoreSpellOverride == true
    end
    local list = { spell = out.spells, item = out.items, interact = out.interact }
    for _, b in ipairs(bands) do
        for _, c in ipairs(b.checks) do
            local k = c[1] .. c[2]
            if not seen[k] then
                seen[k] = true
                local l = list[c[1]]
                l[#l + 1] = c[2]
            end
        end
    end
    if #out.spells == 0 and (#out.items > 0 or #out.interact > 0) then
        local g = RB.GATE_SPELL[ClassTag() or ""]
        if g then out.spells[1] = g end
    end
    return out
end

-- Words

local function SpellName(sid)
    local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: a typed check's spell, for the editor's words
    if issecretvalue and issecretvalue(nm) then nm = nil end
    if type(nm) == "string" and nm ~= "" then return nm end
    return "spell " .. sid
end

function RB.CheckChoice(k)
    if k.kind == "spell" then return k.want and "spellin" or "spellout" end
    return k.want and "within" or "beyond"
end

function RB.CheckWords(k)
    if k.kind == "spell" then
        local id = tonumber(k.id)
        return (id and SpellName(id) or "a spell not picked yet") .. (k.want and " in range" or " out of range")
    end
    return (k.want and "within " or "beyond ") .. tostring(k.yd) .. " yd"
end

function RB.BandWords(b)
    local parts = {}
    for _, k in ipairs(b.checks or {}) do parts[#parts + 1] = RB.CheckWords(k) end
    if #parts == 0 then return "No checks yet: this band never holds." end
    return table.concat(parts, ", ")
end

-- The layout card's line.
function RB.Describe(rec)
    local preset = RB.Preset(rec)
    if preset == "hunter" then return "Hunter bands" end
    if preset == "custom" then return ("Custom, %d bands"):format(#rec.driver.bands) end
    local sid = RB.SpellFor(rec, preset)
    if preset == "melee" and not sid then return "Melee, " .. RB.MELEE_YD .. " yd" end
    return (preset == "caster" and "Caster" or "Melee") .. ", " .. (sid and SpellName(sid) or "no spell")
end

-- The Tracking tab's line: what the bands check.
function RB.CheckText(rec)
    local preset = RB.Preset(rec)
    if preset == "hunter" then return RB.HUNTER_TEXT end
    if preset == "custom" then
        local n = #rec.driver.bands
        return ("Custom: %d band%s, nearest first."):format(n, n == 1 and "" or "s")
    end
    local sid = RB.SpellFor(rec, preset)
    if preset == "melee" and not sid then
        return "In or out of melee range (" .. RB.MELEE_YD .. " yards), any class. A spell typed here replaces it."
    end
    if not sid then return "Type a spell: your class has no usual one for this preset." end
    return "In or out of range of " .. SpellName(sid) .. "."
end

-- What an empty Spell box stands for.
function RB.SpellHint(rec)
    local preset = RB.Preset(rec)
    local sid = RB.DefaultSpell(preset)
    if sid then return SpellName(sid) .. " (" .. sid .. ")" end
    if preset ~= "caster" then return "melee range (" .. RB.MELEE_YD .. " yd)" end
    return "type a spell"
end

-- Editing: the first edit copies the preset into the bar's own bands, which then
-- belong to the record (export, import and Duplicate carry them).

local function Dirty(rec)
    if NS.Store and NS.Store.Dirty then NS.Store.Dirty("style", rec.id) end
end

local function Copy(b)
    local c = b.color or GREY
    local nb = { text = b.text or "", color = { c[1], c[2], c[3], c[4] or 1 }, off = b.off, checks = {} }
    for _, k in ipairs(b.checks or {}) do
        nb.checks[#nb.checks + 1] = { kind = k.kind, id = k.id, yd = k.yd, want = k.want == true }
    end
    return nb
end

function RB.OwnBands(rec)
    local d = rec.driver
    if RB.Preset(rec) ~= "custom" then
        local list = {}
        for i, b in ipairs(RB.PresetBands(rec)) do list[i] = Copy(b) end
        d.bands = list
        d.preset = "custom"
    end
    return d.bands
end

function RB.MakeCustom(rec)
    if RB.Preset(rec) == "custom" then return end
    RB.OwnBands(rec)
    Dirty(rec)
end

-- Back to a preset: the bar's own bands go.
function RB.ResetTo(rec, preset)
    local d = rec.driver
    d.bands = nil
    d.spellID = nil
    d.preset = (preset == "hunter" or preset == "melee" or preset == "caster") and preset or RB.DefaultPreset()
    Dirty(rec)
end

-- Every setter leaves a band list untouched when nothing changes: focusing a box and
-- leaving it must not turn a preset into a copy.
function RB.SetBandText(rec, i, text)
    local cur = RB.BandsOf(rec)[i]
    text = tostring(text or ""):sub(1, 40)
    if not cur or cur.text == text then return end
    RB.OwnBands(rec)[i].text = text
    Dirty(rec)
end

function RB.SetBandColor(rec, i, c)
    local cur = RB.BandsOf(rec)[i]
    if not (cur and type(c) == "table") then return end
    local o = cur.color or GREY
    -- the opacity slider's alpha counts: an opacity-only edit is a change
    local a = c[4] or o[4] or 1
    if o[1] == c[1] and o[2] == c[2] and o[3] == c[3] and (o[4] or 1) == a then return end
    RB.OwnBands(rec)[i].color = { c[1], c[2], c[3], a }
    Dirty(rec)
end

function RB.SetBandOff(rec, i, off)
    local cur = RB.BandsOf(rec)[i]
    off = off and true or nil
    if not cur or cur.off == off then return end
    RB.OwnBands(rec)[i].off = off
    Dirty(rec)
end

function RB.AddBand(rec)
    local max = (NS.Schema and NS.Schema.RANGE_MAX_BANDS) or 8
    if #RB.BandsOf(rec) >= max then return end
    local list = RB.OwnBands(rec)
    list[#list + 1] = { text = "NEW BAND", color = { CYAN[1], CYAN[2], CYAN[3], 1 }, checks = { Yards(40, true) } }
    Dirty(rec)
end

-- The last band stays: a bar with none would have nothing to show.
function RB.RemoveBand(rec, i)
    local n = #RB.BandsOf(rec)
    if n <= 1 or i < 1 or i > n then return end
    table.remove(RB.OwnBands(rec), i)
    Dirty(rec)
end

function RB.MoveBand(rec, i, dir)
    local j = i + dir
    local n = #RB.BandsOf(rec)
    if i < 1 or i > n or j < 1 or j > n then return end
    local list = RB.OwnBands(rec)
    list[i], list[j] = list[j], list[i]
    Dirty(rec)
end

function RB.AddCheck(rec, i)
    local cur = RB.BandsOf(rec)[i]
    local max = (NS.Schema and NS.Schema.RANGE_MAX_CHECKS) or 4
    if not cur or #(cur.checks or {}) >= max then return end
    local b = RB.OwnBands(rec)[i]
    b.checks[#b.checks + 1] = Yards(10, true)
    Dirty(rec)
end

function RB.RemoveCheck(rec, i, j)
    local cur = RB.BandsOf(rec)[i]
    if not (cur and cur.checks and cur.checks[j]) then return end
    table.remove(RB.OwnBands(rec)[i].checks, j)
    Dirty(rec)
end

-- A new kind keeps its value within the same family (a spell, or yards).
function RB.SetCheckChoice(rec, i, j, choice)
    local cur = RB.BandsOf(rec)[i]
    local k = cur and cur.checks and cur.checks[j]
    if not k or RB.CheckChoice(k) == choice or not RB.CHOICE_TEXT[choice] then return end
    local nk = RB.OwnBands(rec)[i].checks[j]
    local spell = choice == "spellin" or choice == "spellout"
    if spell ~= (nk.kind == "spell") then
        nk.kind, nk.id, nk.yd = spell and "spell" or "yd", nil, (not spell) and 10 or nil
    end
    nk.want = choice == "spellin" or choice == "within"
    Dirty(rec)
end

function RB.SetCheckSpell(rec, i, j, id)
    local cur = RB.BandsOf(rec)[i]
    local k = cur and cur.checks and cur.checks[j]
    id = tonumber(id)
    if id and id <= 0 then id = nil end
    if not k or k.kind ~= "spell" or k.id == id then return end
    RB.OwnBands(rec)[i].checks[j].id = id and math.floor(id) or nil
    Dirty(rec)
end

function RB.SetCheckYards(rec, i, j, yd)
    local cur = RB.BandsOf(rec)[i]
    local k = cur and cur.checks and cur.checks[j]
    yd = tonumber(yd)
    if not k or k.kind ~= "yd" or not RB.YARDS[yd or 0] or k.yd == yd then return end
    RB.OwnBands(rec)[i].checks[j].yd = yd
    Dirty(rec)
end

-- Drawing

local function CustomName(rec)
    local v = R(rec, "text", "nameText")
    return type(v) == "string" and v ~= ""
end

function RB.Segmented(rec) return R(rec, "range", "style") == "segmented" end

-- The cells live on the shell, which can outlive the entry that built them.
local function Cells(shell)
    local C = shell._adRange
    if C then return C end
    C = { helpers = {}, cells = {} }
    C.host = CreateFrame("Frame", nil, shell)
    C.host:EnableMouse(false)
    C.host:SetAllPoints(shell.fill)
    -- the labels ride the text host, above every fill
    C.text = CreateFrame("Frame", nil, shell.overlay)
    C.text:EnableMouse(false)
    C.text:SetAllPoints(shell.overlay)
    shell._adRange = C
    return C
end

-- A boundary rides the fill edge of a helper bar that spans the cells and draws
-- nothing, so the game places it at any size with no reads.
local function Helper(C, k)
    local h = C.helpers[k]
    if not h then
        local bar = CreateFrame("StatusBar", nil, C.host)
        bar:EnableMouse(false)
        bar:SetStatusBarTexture(K.WHITE)
        bar:SetStatusBarColor(1, 1, 1, 0)
        bar:SetAllPoints(C.host)
        h = { bar = bar, tex = bar:GetStatusBarTexture() }
        C.helpers[k] = h
    end
    return h
end

local function Cell(C, k)
    local c = C.cells[k]
    if not c then
        local bar = CreateFrame("StatusBar", nil, C.host)
        bar:EnableMouse(false)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        local sheen = bar:CreateTexture(nil, "OVERLAY")
        sheen:SetTexture(K.WHITE)
        sheen:SetAllPoints(bar)
        local fs = C.text:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        fs:SetJustifyH("CENTER")
        c = { bar = bar, sheen = sheen, fs = fs }
        C.cells[k] = c
    end
    return c
end

local function HideCells(C)
    C.host:Hide()
    C.text:Hide()
end

-- One cell per shown band along the fill, the first at the fill's start (the
-- bottom of a standing bar). Anchors only: a boundary is a helper's fill edge,
-- and a gap splits into whole pixels on either side of it.
function RB.LayCells(e)
    local shell, rec = e.shell, e.rec
    local C = Cells(shell)
    local n = #RB.ShownIdx(RB.BandsOf(rec))
    local vertical = (R(rec, "fill", "orientation") or "HORIZONTAL") == "VERTICAL"
    local orient = vertical and "VERTICAL" or "HORIZONTAL"
    local px = K.Px(shell)
    local gap = math.max(0, math.floor(R(rec, "range", "cellGap") or 2))
    local lead, trail = math.floor(gap / 2) * px, (gap - math.floor(gap / 2)) * px
    local path = K.ResolveBarTexture(R(rec, "fill", "texture"))
    local rotate = R(rec, "fill", "rotateTexture") == true
    local sheenOn = R(rec, "fill", "useGradient") ~= false
    local nameOn = R(rec, "text", "nameShow") == true
    local size = R(rec, "text", "nameSize") or 11
    local outline = R(rec, "text", "nameOutline") or "OUTLINE"
    local shadow = R(rec, "text", "nameShadow") == true
    local level = shell.fill:GetFrameLevel() + 1
    C.host:SetFrameLevel(level)
    C.host:Show()
    C.text:SetShown(nameOn)
    for k = 1, math.max(n - 1, #C.helpers) do
        local h = (k < n) and Helper(C, k) or C.helpers[k]
        if k < n then
            h.bar:SetFrameLevel(level)
            h.bar:SetOrientation(orient)
            h.bar:SetReverseFill(false)
            h.bar:SetMinMaxValues(0, n)
            h.bar:SetValue(k)
            h.bar:Show()
        elseif h then
            h.bar:Hide()
        end
    end
    for k = 1, math.max(n, #C.cells) do
        local c = (k <= n) and Cell(C, k) or C.cells[k]
        if k <= n then
            local bar = c.bar
            bar:SetFrameLevel(level + 1)
            if c.path ~= path then
                c.path = path
                bar:SetStatusBarTexture(path)
                local t = bar:GetStatusBarTexture()
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
                if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
            end
            bar:SetOrientation(orient)
            bar:SetRotatesTexture(rotate)
            bar:ClearAllPoints()
            local lo = (k == 1) and C.host or C.helpers[k - 1].tex
            local hi = (k == n) and C.host or C.helpers[k].tex
            if vertical then
                bar:SetPoint("BOTTOMLEFT", lo, (k == 1) and "BOTTOMLEFT" or "TOPLEFT", 0, (k == 1) and 0 or trail)
                bar:SetPoint("TOPRIGHT", hi, "TOPRIGHT", 0, (k == n) and 0 or -lead)
            else
                bar:SetPoint("TOPLEFT", lo, (k == 1) and "TOPLEFT" or "TOPRIGHT", (k == 1) and 0 or trail, 0)
                bar:SetPoint("BOTTOMRIGHT", hi, "BOTTOMRIGHT", (k == n) and 0 or -lead, 0)
            end
            bar:Show()
            if sheenOn then K.ApplySheen(c.sheen, rec) end
            c.sheen:SetShown(sheenOn)
            K.StyleFont(c.fs, e, "rangecell", size, outline, shadow)
            c.fs:ClearAllPoints()
            c.fs:SetPoint("LEFT", bar, "LEFT", px, 0)
            c.fs:SetPoint("RIGHT", bar, "RIGHT", -px, 0)
            c.fs:Show()
        elseif c then
            c.bar:Hide()
            c.fs:Hide()
        end
    end
end

-- The shown bands' cells in their colours: the lit one full, the rest dimmed.
function RB.LightCells(e, list, lit)
    local C = e.shell._adRange
    if not C then return end
    local rec = e.rec
    local dim = R(rec, "range", "cellDim") or 0.25
    local nc = R(rec, "text", "nameColor") or { 1, 1, 1, 1 }
    local k = 0
    for i, b in ipairs(list) do
        if not b.off then
            k = k + 1
            local c = C.cells[k]
            if c then
                local on = i == lit
                local col = b.color or GREY
                c.bar:SetStatusBarColor(col[1], col[2], col[3], (col[4] or 1) * (on and 1 or dim))
                c.fs:SetText(b.text or "")
                c.fs:SetTextColor(nc[1], nc[2], nc[3], (nc[4] or 1) * (on and 1 or RB.DIM_TEXT))
            end
        end
    end
end

-- i nil: the empty plate (or every cell dimmed) and no text.
function RB.Paint(e, i)
    local shell, rec = e.shell, e.rec
    local list = RB.BandsOf(rec)
    local b = i and list[i]
    if not b then i = nil end
    e.rbBand = i
    if RB.Segmented(rec) then
        RB.LightCells(e, list, i)
        if not CustomName(rec) then K.SetRunText(shell, "name", "") end
        return
    end
    local c = (b and b.color) or CLEAR
    shell.fill:SetMinMaxValues(0, 1)
    shell.fill:SetValue(b and 1 or 0)
    shell.fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if not CustomName(rec) then K.SetRunText(shell, "name", (b and b.text) or "") end
    local fs = shell.texts.name
    if fs and b and R(rec, "range", "textBandColor") == true then
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function RB.Watch(e)
    e.rbBands = RB.EngineBands(RB.BandsOf(e.rec))
    local DR = NS.DriverRange
    if not DR then return end
    local id = e.rec.id
    DR.Use(RB.OWNER .. id, RB.Need(e.rbBands, e.rec.driver), function()
        local cur = K.live[id]
        if cur then RB.Refresh(cur) end
    end)
end

-- No band (no target, a dead or friendly one, a switched-off band) is the neutral
-- look, never a hide: hiding with no target is the Load When and Visibility
-- conditions' job.
function RB.Refresh(e)
    if e.isPreview then return end
    local DR = NS.DriverRange
    local list = RB.BandsOf(e.rec)
    local i = DR and DR.Band(e.rbBands or RB.EngineBands(list), e.rec.driver)
    if i and (not list[i] or list[i].off) then i = nil end
    RB.Paint(e, i)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

-- Kind registry hooks

function RB.Ensure(e)
    RB.Watch(e)
    RB.Refresh(e)
end

function RB.Release(e)
    local DR = NS.DriverRange
    if DR and e.rec then DR.Drop(RB.OWNER .. e.rec.id) end
    e.rbBand = nil
end

-- ApplyStyle draws the whole shell in the fill colour: put the band back. The plate
-- style can drop to its text alone; the segmented one draws its cells instead of the fill.
function RB.Styled(e)
    local shell, rec = e.shell, e.rec
    local seg = RB.Segmented(rec)
    local plate = seg or R(rec, "range", "plateShow") ~= false
    shell.fill:SetShown(plate and not seg)
    shell.bg:SetShown(plate)
    for _, t in pairs(shell.edges) do t:SetShown(plate) end
    if shell.borderF then shell.borderF:SetShown(plate and e.borderFWanted == true) end
    shell.sheen:SetShown(plate and not seg and R(rec, "fill", "useGradient") ~= false)
    if seg then
        RB.LayCells(e)
    elseif shell._adRange then
        HideCells(shell._adRange)
    end
    RB.Paint(e, e.rbBand)
end

function RB.Diag(e)
    local DR = NS.DriverRange
    return ("%s [range %s, %s] band=%s %s"):format(tostring(e.rec.name), RB.Describe(e.rec),
        RB.Segmented(e.rec) and "segmented" or "plate", tostring(e.rbBand), DR and DR.Diag() or "no range engine")
end

-- Editor preview: the bands that show, one at a time, then the look with no band.
function RB.PreviewModes()
    return {
        { key = "static", text = "Preview", tip = "The nearest band that shows, standing still." },
        { key = "loop", text = "Cycle bands",
          tip = "Each band that shows in turn, nearest first, then the look with no target, one and a half seconds each." },
    }
end

function RB.PreviewBuild(e)
    e.pvRbIdx = RB.ShownIdx(RB.BandsOf(e.rec))
end

function RB.PreviewApply(e, loop, t, fresh)
    local idx = e.pvRbIdx
    if fresh or not idx then
        idx = RB.ShownIdx(RB.BandsOf(e.rec))
        e.pvRbIdx = idx
    end
    local i = idx[1]
    -- the step past the last band is the no-band look
    if loop then i = idx[math.floor((t or 0) / RB.CYCLE) % (#idx + 1) + 1] end
    if fresh or i ~= e.rbBand then RB.Paint(e, i) end
end

Bars.RegisterKind("range", {
    Ensure = RB.Ensure,
    Refresh = RB.Refresh,
    Release = RB.Release,
    Styled = RB.Styled,
    Diag = RB.Diag,
    ownsName = true,
    PreviewModes = RB.PreviewModes,
    PreviewBuild = RB.PreviewBuild,
    PreviewApply = RB.PreviewApply,
})
