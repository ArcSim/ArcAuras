-- AD_SwingRange: a swing bar dims while the target is out of range of the bar's check spell (a melee hand
-- with none falls back to the range bar's melee yards, an item check on the range engine's pulse).
-- Owns each bar's consumer on the range engine (NS.DriverRange); the bars runtime calls in through Bars.SwingRange when it styles or releases a swing bar.
-- Spell range rides SPELL_RANGE_CHECK_UPDATE, plain in combat on Forever; no answer (no target, no check) never dims.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.ApplyVisibility and K.live) then return end

local SR = {}
Bars.SwingRange = SR

SR.OWNER = "adswingrange:"
local RANGED = 2
-- A ranged bar checks the shot: Auto Shot for hunters, Shoot for the wand
-- classes. The melee hands use the range bar's table (NS.RangeBars.MELEE_SPELL).
-- Rank 1 IDs: the engine checks the rank the player knows, found by name.
SR.RANGED_SPELL = { HUNTER = 75, MAGE = 5019, PRIEST = 5019, WARLOCK = 5019 }
-- owner key -> bar id, for the engine's callback
SR.ids = {}

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function ClassTag()
    local _, tag = UnitClass("player")
    return tag
end

-- The spell a bar's hand checks when none is typed, or nil (a class with no
-- ability of that reach, such as a paladin's melee hands).
function SR.DefaultSpell(rec)
    local tag = ClassTag() or ""
    if ((rec.driver and rec.driver.swingType) or 0) == RANGED then return SR.RANGED_SPELL[tag] end
    local RB = NS.RangeBars
    return RB and RB.MELEE_SPELL and RB.MELEE_SPELL[tag] or nil
end

-- The bar's own spell, else its hand's default.
function SR.SpellFor(rec)
    local id = tonumber(rec.driver and rec.driver.rangeSpell)
    if id and id > 0 then return math.floor(id) end
    return SR.DefaultSpell(rec)
end

-- The check a bar's hand makes: "spell", id; for a melee hand with no spell the
-- range bar's melee yards (an item); nil for a ranged hand with no shot spell.
function SR.CheckFor(rec)
    local sid = SR.SpellFor(rec)
    if sid then return "spell", sid end
    if ((rec.driver and rec.driver.swingType) or 0) == RANGED then return nil end
    local RB = NS.RangeBars
    local m = RB and RB.YARDS and RB.MELEE_YD and RB.YARDS[RB.MELEE_YD]
    if m then return m[1], m[2] end
    return nil
end

-- What an empty spell box stands for.
function SR.SpellHint(rec)
    local sid = SR.DefaultSpell(rec)
    if not sid then
        local RB = NS.RangeBars
        if ((rec.driver and rec.driver.swingType) or 0) ~= RANGED and RB and RB.MELEE_YD then
            return "melee range (" .. RB.MELEE_YD .. " yd)"
        end
        return "none for this hand: type a spell"
    end
    local CS = C_Spell
    local nm = CS and CS.GetSpellName and CS.GetSpellName(sid)
    if IsSecret(nm) or type(nm) ~= "string" or nm == "" then return tostring(sid) end
    return nm .. " (" .. sid .. ")"
end

-- A live bar with the switch on; the preview never asks the engine.
local function Wanted(e)
    return not e.isPreview and C_SwingTimer ~= nil and NS.DriverRange ~= nil
        and K.R(e.rec, "behavior", "rangeDim") == true
end

-- Out of range dims; in range, no target or no check never does. The engine
-- keeps its last plain answer when the game hands it a secret one.
local function Answer(s)
    local DR = NS.DriverRange
    if not (s and DR) then return nil end
    if s.kind == "item" then return DR.Item(s.id) end
    return DR.Spell(s.id)
end

local function Paint(e, quiet)
    local dim = (Answer(e.srange) == false) or nil
    if e.rangeDimmed == dim then return end
    e.rangeDimmed = dim
    if not quiet then K.ApplyVisibility(e) end
end

function SR.OnAnswer(owner)
    local id = SR.ids[owner]
    local e = id and K.live[id]
    if e and e.srange and e.srange.owner == owner then Paint(e) end
end

-- quiet: a released bar's frame is no longer its own to paint
local function Drop(e, quiet)
    local s = e.srange
    if s then
        e.srange = nil
        SR.ids[s.owner] = nil
        local DR = NS.DriverRange
        if DR then DR.Drop(s.owner) end
    end
    Paint(e, quiet)
end

-- Called at the end of every style pass: a new spell, hand or switch takes the
-- engine consumer with it.
function SR.Styled(e)
    local kind, id
    if Wanted(e) then kind, id = SR.CheckFor(e.rec) end
    if not kind then
        Drop(e)
        return
    end
    local owner = SR.OWNER .. tostring(e.rec.id)
    local s = e.srange
    if s and s.owner ~= owner then
        Drop(e, true)
        s = nil
    end
    if not s then
        s = { owner = owner }
        e.srange = s
    end
    s.kind, s.id = kind, id
    SR.ids[owner] = e.rec.id
    local need = { spells = { id } }
    if kind == "item" then
        local RB = NS.RangeBars
        local g = RB and RB.GATE_SPELL and RB.GATE_SPELL[ClassTag() or ""]
        need = { items = { id }, spells = g and { g } or nil, gate = true }
    end
    -- the same need again only swaps the callback, so a restyle costs nothing
    NS.DriverRange.Use(owner, need, SR.OnAnswer)
    Paint(e)
end

function SR.Release(e)
    Drop(e, true)
end

-- The /adbars diag line of a swing bar with the switch on.
function SR.Diag(e)
    local s = e.srange
    return ("%s [swing range] %s=%s answer=%s dimmed=%s"):format(tostring(e.rec.name),
        tostring(s and s.kind or "spell"), tostring(s and s.id), tostring(Answer(s)),
        tostring(e.rangeDimmed == true))
end
