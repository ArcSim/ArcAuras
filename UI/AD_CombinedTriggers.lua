-- AD_CombinedTriggers: combined triggers on a cooldown icon's Effects tab ("Ready and aura missing"): a state joined with the aura on the icon being down and with plain parts (another of the spell's states, conditions), all of which must hold for its glow.
-- Saved on a numbered aura glow (auraActive.activeGlow<k>, When missing, activeGlowState<k>, activeGlowAnd<k>); Drivers\AD_DriverAura.lua draws and gates it. UI\AD_EffectsTab.lua's WHEN row writes through here.
local ADDON, NS = ...
local Store, Schema = NS.Store, NS.Schema
if not (Store and Schema) then return end

local CT = {}
NS.CombinedTriggers = CT

local A = "auraActive"
local EMPTY = {}

-- The spell's states a part can name, by family: a spell is in one of each
-- at a time (its cooldown, its usability), so a trigger takes one of each.
CT.FAMILY = { ready = "bucket", recharge = "bucket", cooldown = "bucket",
    unusable = "use", nomana = "use", range = "use" }
CT.STATE_ORDER = { "ready", "recharge", "cooldown", "unusable", "nomana", "range" }
-- the states whose card can start one: those with a glow of their own, and
-- that glow's field prefix
CT.GLOW_PRE = { ready = "ready", recharge = "recharge", cooldown = "cooldown", range = "range" }
-- the aura part: its glow while the aura is down (its layer) or up (its lane)
CT.AURA_WHEN = { auraMissing = "missing", auraUp = "always" }
-- a glow's style, moved between a state's glow and the trigger's
local STYLE = { "Type", "Native", "Color", "Speed", "Lines", "Thickness", "Length", "Backing", "Particles",
    "Intensity", "Scale", "XOffset", "YOffset", "MoveX", "MoveY", "CombatOnly" }

local function DA() return NS.DriverAura end
local function Slots() return Schema.AURA_GLOW_SLOTS or 1 end
local function Get(rec, field, k) return Store.Resolve(rec, A, field .. k) end
local function Put(rec, field, k, v) Store.SetOverride(rec, A, field .. k, v) end

-- One icon's own trigger list: a spell, item or trinket icon whose aura's
-- Missing glows get layers of their own (not several icons, not a kind's defaults).
function CT.On(rec)
    local D = DA()
    return rec ~= nil and rec.type == "icon" and not (rec._adMulti or rec._adDefaults or rec._adLayoutTier)
        and rec.kind ~= "aura" and rec.kind ~= "timer"
        and D ~= nil and D.MissingGlowOK ~= nil and D.MissingGlowOK(rec) == true
end

local function List(rec, field, k)
    local D = DA()
    local l = D and D.GateList and D.GateList(Get(rec, field, k))
    local out = {}
    for i, v in ipairs(l or EMPTY) do out[i] = v end
    return out
end

-- A slot's parts: its states (the first is the card it was made from) and its conditions.
function CT.Parts(rec, k)
    return List(rec, "activeGlowState", k), List(rec, "activeGlowAnd", k)
end

-- The slots that are combined triggers: a Missing glow that waits on parts.
function CT.Slots(rec)
    local out = {}
    for k = 2, Slots() do
        local st = CT.Parts(rec, k)
        local when = Get(rec, "activeGlowWhen", k)
        if st[1] and CT.Lit(rec, k) and (when == "missing" or when == "always" or when == "parts") then
            out[#out + 1] = k
        end
    end
    return out
end

-- the aura part of a combined trigger: "auraMissing", "auraUp", or nil (none)
function CT.AuraPart(rec, k)
    local when = Get(rec, "activeGlowWhen", k)
    if when == "missing" then return "auraMissing" end
    if when == "always" then return "auraUp" end
    return nil
end

-- Any of: any one part is enough (its own state is one of them)
function CT.Any(rec, k) return Get(rec, "activeGlowAny", k) == true end
function CT.SetAny(rec, k, on)
    Put(rec, "activeGlowAny", k, on and true or nil)
    -- its look is drawn only where exact (CT.LookOK)
end

-- the trigger does something: its glow, or its look
function CT.Lit(rec, k)
    return Get(rec, "activeGlow", k) == true or Get(rec, "activeGlowGrey", k) == true
        or Get(rec, "activeGlowTint", k) == true
end

-- Its look can be drawn exactly: the aura part is the aura missing and the
-- aura's button covers the icon while up (Factory.ComboLook).
function CT.LookOK(rec, k)
    if k == nil then return false end
    -- no aura part: its parts alone decide, on the icon's own art
    if Get(rec, "activeGlowWhen", k) == "parts" then return true end
    local F = NS.Factory
    return not CT.Any(rec, k) and CT.AuraPart(rec, k) == "auraMissing" and F ~= nil and F.AuraCovers ~= nil
        and F.AuraCovers(rec) == true
end

-- the first numbered glow that is off and no trigger's
function CT.FreeSlot(rec)
    for k = 2, Slots() do
        if Get(rec, "activeGlow", k) ~= true and not CT.Parts(rec, k)[1] and not List(rec, "activeGlowAnd", k)[1] then
            return k
        end
    end
    return nil
end

-- the state's grey and tint switches, where its look has them
local function LookSpec(rec, stKey)
    local ET = NS.Options and NS.Options.EditorTabs
    for _, st in ipairs((ET and ET.StatesFor and ET.StatesFor(rec)) or EMPTY) do
        if st.key == stKey then return st end
    end
    return nil
end
-- the state's grey and tint onto slot k (and the state's back to none), or back
local function MoveLook(rec, stKey, k, toSlot)
    local st = LookSpec(rec, stKey)
    if not st then return end
    if st.grey then
        if toSlot then
            if Store.Resolve(rec, st.grey[1], st.grey[2]) == true then
                Put(rec, "activeGlowGrey", k, true)
                Store.SetOverride(rec, st.grey[1], st.grey[2], false)
            end
        elseif Get(rec, "activeGlowGrey", k) == true then
            Store.SetOverride(rec, st.grey[1], st.grey[2], true)
        end
    end
    local t = st.tint
    if t and t.on then
        if toSlot then
            if Store.Resolve(rec, t[1], t.on) == true then
                Put(rec, "activeGlowTint", k, true)
                Put(rec, "activeGlowTintColor", k, Store.Resolve(rec, t[1], t[2]))
                Store.SetOverride(rec, t[1], t.on, false)
            end
        elseif Get(rec, "activeGlowTint", k) == true then
            Store.SetOverride(rec, t[1], t.on, true)
            Store.SetOverride(rec, t[1], t[2], Get(rec, "activeGlowTintColor", k))
        end
    end
end

-- Every field of slot k back to its default.
function CT.Clear(rec, k)
    for _, name in ipairs(Schema.AURA_GLOW_FIELDS or EMPTY) do Put(rec, name, k, nil) end
end

local function StateField(pre, part) return pre .. "Glow" .. part end
local function HasState(field)
    local sec = Schema.icon and Schema.icon.states
    return sec ~= nil and sec.fields[field] ~= nil
end
local function HasSlot(field, k)
    local sec = Schema.icon and Schema.icon.auraActive
    return sec ~= nil and sec.fields[field .. k] ~= nil
end

-- A combined trigger from a state's card and the aura being down: the state's
-- glow (its look) moves onto it. Returns its slot, or nil when none is free.
function CT.Make(rec, base, aura)
    aura = aura or "auraMissing"
    if not (CT.On(rec) and CT.GLOW_PRE[base] and CT.AURA_WHEN[aura]) then return nil end
    local k = CT.FreeSlot(rec)
    if not k then return nil end
    CT.Clear(rec, k)
    local pre = CT.GLOW_PRE[base]
    if Store.Resolve(rec, "states", pre .. "Glow") == true then
        for _, p in ipairs(STYLE) do
            local sf = StateField(pre, p)
            if HasState(sf) and HasSlot("activeGlow" .. p, k) then
                Put(rec, "activeGlow" .. p, k, Store.Resolve(rec, "states", sf))
            end
        end
        Store.SetOverride(rec, "states", pre .. "Glow", false)
    end
    Put(rec, "activeGlow", k, true)
    Put(rec, "activeGlowWhen", k, CT.AURA_WHEN[aura])
    Put(rec, "activeGlowState", k, base)
    if CT.LookOK(rec, k) then MoveLook(rec, base, k, true) end
    return k
end

local function Save(rec, field, k, list)
    Put(rec, field, k, (#list > 0) and table.concat(list, ",") or nil)
end

-- A part the trigger can still take: a state of the family it has none of,
-- or a condition it does not name.
function CT.CanAdd(rec, k, part)
    local states, conds = CT.Parts(rec, k)
    if not states[1] then return false end
    if CT.AURA_WHEN[part] then return CT.AuraPart(rec, k) == nil end
    local fam = CT.FAMILY[part]
    if fam then
        local any = CT.Any(rec, k)
        for _, s in ipairs(states) do
            if s == part or (not any and CT.FAMILY[s] == fam) then return false end
        end
        return true
    end
    local OL = NS.OwnLooks
    if not (OL and OL.CONDITION_OK and OL.CONDITION_OK[part]) then return false end
    for _, c in ipairs(conds) do
        if c == part then return false end
    end
    return true
end

function CT.AddPart(rec, k, part)
    if not CT.CanAdd(rec, k, part) then return false end
    local states, conds = CT.Parts(rec, k)
    if CT.AURA_WHEN[part] then
        Put(rec, "activeGlowWhen", k, CT.AURA_WHEN[part])
    elseif CT.FAMILY[part] then
        states[#states + 1] = part
        Save(rec, "activeGlowState", k, states)
    else
        conds[#conds + 1] = part
        Save(rec, "activeGlowAnd", k, conds)
    end
    return true
end

-- Takes a part off; the state it was made from stays (Remove trigger or the
-- aura's x undo the trigger itself).
function CT.RemovePart(rec, k, part)
    local states, conds = CT.Parts(rec, k)
    for i = 2, #states do
        if states[i] == part then
            table.remove(states, i)
            Save(rec, "activeGlowState", k, states)
            return true
        end
    end
    for i, c in ipairs(conds) do
        if c == part then
            table.remove(conds, i)
            Save(rec, "activeGlowAnd", k, conds)
            return true
        end
    end
    return false
end

-- The state's entry on this icon (its card's: words, look columns).
local function StateEntry(rec, key)
    local ET = NS.Options and NS.Options.EditorTabs
    for _, st in ipairs((ET and ET.StatesFor and ET.StatesFor(rec)) or EMPTY) do
        if st.key == key then return st, ET end
    end
    return nil, ET
end
CT.StateEntry = StateEntry

-- A look's columns written back onto its state (a look's last part taken off).
function CT.LookToState(rec, stKey, look)
    local st = StateEntry(rec, stKey)
    if not (st and type(look) == "table") then return end
    local function Set(spec, field, v) Store.SetOverride(rec, spec[1], field, v) end
    if look.alpha ~= nil and st.alpha then
        if st.alpha.on then Set(st.alpha, st.alpha.on, true) end
        Set(st.alpha, st.alpha[2], look.alpha)
    end
    if look.grey ~= nil and st.grey then Set(st.grey, st.grey[2], look.grey) end
    if look.tint ~= nil and st.tint then
        if st.tint.on then Set(st.tint, st.tint.on, look.tint) end
        if look.tintColor then Set(st.tint, st.tint[2], look.tintColor) end
    end
    local pre = CT.GLOW_PRE[stKey]
    if look.glow ~= nil and pre then Store.SetOverride(rec, "states", pre .. "Glow", look.glow) end
end

-- An own look of the state that waits on parts (the spell's states and
-- conditions) and carries the given columns; its place under the state, or nil.
local function AddLook(rec, stKey, parts, cols)
    local OL = NS.OwnLooks
    if not (OL and OL.Add and parts[1]) then return nil end
    local key = OL.StateKey(rec.kind, stKey)
    local idx = OL.Add(rec, key, parts[1], cols)
    if not idx then return nil end
    OL.Set(rec, idx, "when", parts)
    return #(OL.List(rec, key) or EMPTY)
end

-- The aura part taken off: the trigger goes on as its state's, waiting on its
-- other parts as an own look of that state (with its glow), or as the
-- state's own glow when it had none. Returns the card to open: a state key,
-- or { state, n } for a look.
function CT.Dissolve(rec, k)
    local states, conds = CT.Parts(rec, k)
    local base = states[1]
    local pre = base and CT.GLOW_PRE[base]
    if not pre then
        CT.Clear(rec, k)
        return nil
    end
    for _, p in ipairs(STYLE) do
        local sf = StateField(pre, p)
        if HasState(sf) and HasSlot("activeGlow" .. p, k) then
            Store.SetOverride(rec, "states", sf, Get(rec, "activeGlow" .. p, k))
        end
    end
    local parts = {}
    for i = 2, #states do parts[#parts + 1] = states[i] end
    for _, c in ipairs(conds) do parts[#parts + 1] = c end
    local open = base
    local glow = Get(rec, "activeGlow", k) == true
    -- no glow on it: the look leaves the state's glow alone
    local cols = { glow = glow or nil }
    if Get(rec, "activeGlowGrey", k) == true then cols.grey = true end
    if Get(rec, "activeGlowTint", k) == true then
        cols.tint, cols.tintColor = true, Get(rec, "activeGlowTintColor", k)
    end
    local n = parts[1] and AddLook(rec, base, parts, cols)
    if n then
        open = { state = base, n = n }
    else
        if glow then Store.SetOverride(rec, "states", pre .. "Glow", true) end
        MoveLook(rec, base, k, false)
    end
    CT.Clear(rec, k)
    return open
end

-- An own look given the aura part: it becomes a combined trigger (its state,
-- its parts, its glow on the next free numbered glow) and the look goes.
-- Returns the slot, or nil.
function CT.FromLook(rec, stKey, index, look, aura)
    aura = aura or "auraMissing"
    if not (CT.On(rec) and CT.GLOW_PRE[stKey] and type(look) == "table" and CT.AURA_WHEN[aura]) then return nil end
    local k = CT.FreeSlot(rec)
    if not k then return nil end
    CT.Clear(rec, k)
    local pre = CT.GLOW_PRE[stKey]
    for _, p in ipairs(STYLE) do
        local sf = StateField(pre, p)
        if HasState(sf) and HasSlot("activeGlow" .. p, k) then
            Put(rec, "activeGlow" .. p, k, Store.Resolve(rec, "states", sf))
        end
    end
    local states, conds = { stKey }, {}
    for _, part in ipairs(look.when or EMPTY) do
        if CT.FAMILY[part] then states[#states + 1] = part else conds[#conds + 1] = part end
    end
    Put(rec, "activeGlow", k, look.glow ~= false)
    Put(rec, "activeGlowWhen", k, CT.AURA_WHEN[aura])
    Save(rec, "activeGlowState", k, states)
    Save(rec, "activeGlowAnd", k, conds)
    if CT.LookOK(rec, k) then
        if look.grey then Put(rec, "activeGlowGrey", k, true) end
        if look.tint then
            Put(rec, "activeGlowTint", k, true)
            if look.tintColor then Put(rec, "activeGlowTintColor", k, look.tintColor) end
        end
    end
    local OL = NS.OwnLooks
    if OL and OL.Remove and index then OL.Remove(rec, index) end
    return k
end

-- An own look switched to Any of: a combined trigger with no aura part (its
-- state stops being required), carrying its glow, grey and tint. A look with
-- an opacity of its own stays (a combined trigger has none). Returns the slot.
function CT.FromLookAny(rec, stKey, index, look)
    if not (CT.On(rec) and CT.GLOW_PRE[stKey] and type(look) == "table") or look.alpha ~= nil then return nil end
    local k = CT.FreeSlot(rec)
    if not k then return nil end
    CT.Clear(rec, k)
    local pre = CT.GLOW_PRE[stKey]
    for _, p in ipairs(STYLE) do
        local sf = StateField(pre, p)
        if HasState(sf) and HasSlot("activeGlow" .. p, k) then
            Put(rec, "activeGlow" .. p, k, Store.Resolve(rec, "states", sf))
        end
    end
    local states, conds = { stKey }, {}
    for _, part in ipairs(look.when or EMPTY) do
        if CT.FAMILY[part] then states[#states + 1] = part else conds[#conds + 1] = part end
    end
    Put(rec, "activeGlow", k, look.glow == true)
    Put(rec, "activeGlowWhen", k, "parts")
    Put(rec, "activeGlowAny", k, true)
    Save(rec, "activeGlowState", k, states)
    Save(rec, "activeGlowAnd", k, conds)
    if look.grey then Put(rec, "activeGlowGrey", k, true) end
    if look.tint then
        Put(rec, "activeGlowTint", k, true)
        if look.tintColor then Put(rec, "activeGlowTintColor", k, look.tintColor) end
    end
    local OL = NS.OwnLooks
    if OL and OL.Remove and index then OL.Remove(rec, index) end
    return k
end

-- The aura's x on a combined trigger: while Any of, or with no other way to
-- keep its parts, the trigger goes on with no aura part; else it dissolves.
function CT.DropAura(rec, k)
    if CT.Any(rec, k) then
        Put(rec, "activeGlowWhen", k, "parts")
        return "combo" .. k
    end
    return CT.Dissolve(rec, k)
end

-- Words

local function Tr(s)
    local AT = NS.AT
    return (AT and AT.Tr) and AT.Tr(s) or s
end
local function Lower(s) return (s:gsub("^%u", string.lower)) end

-- A state's word on this icon (its card's: "No charges" on a charge spell).
function CT.StateWord(rec, key)
    local st, ET = StateEntry(rec, key)
    if st and ET then return Tr(ET.StateWord(rec, st)) end
    return key
end

function CT.CondWord(key)
    local C = NS.Conditions
    local d = C and C.ByKey and C.ByKey(key)
    return Tr((d and d.text) or key)
end

-- a part's word: a state's, the aura's, a condition's
function CT.PartWord(rec, part)
    if part == "auraMissing" then return Tr("Aura missing") end
    if part == "auraUp" then return Tr("Aura active") end
    if CT.FAMILY[part] then return CT.StateWord(rec, part) end
    return CT.CondWord(part)
end

-- "Ready and aura missing and in combat"
function CT.Name(rec, k)
    local states, conds = CT.Parts(rec, k)
    if not states[1] then return "" end
    local parts = { CT.StateWord(rec, states[1]) }
    local aura = CT.AuraPart(rec, k)
    if aura then parts[2] = Lower(CT.PartWord(rec, aura)) end
    for i = 2, #states do parts[#parts + 1] = Lower(CT.StateWord(rec, states[i])) end
    for _, c in ipairs(conds) do parts[#parts + 1] = Lower(CT.CondWord(c)) end
    return table.concat(parts, " " .. CT.Joiner(rec, k) .. " ")
end

-- Each part as the end of "While ...", in the client's language.
local function Clauses()
    return {
        ready = Tr("it is ready"), recharge = Tr("a charge comes back"), cooldown = Tr("it is on cooldown"),
        unusable = Tr("it can't be used"), nomana = Tr("you lack the resource for it"),
        range = Tr("your target is out of range"), auraMissing = Tr("its aura is down"),
        auraUp = Tr("its aura is up"),
        inCombat = Tr("you are in combat"), outOfCombat = Tr("you are out of combat"),
        hasTarget = Tr("you have a target"), noTarget = Tr("you have no target"),
        targetHostile = Tr("your target is hostile"), targetDead = Tr("your target is dead"),
        solo = Tr("you are not in a group"), raid = Tr("you are in a raid group"),
        instance = Tr("you are in an instance"), encounter = Tr("a boss fight is on"),
        mounted = Tr("you are mounted"), stealthed = Tr("you are stealthed"),
    }
end

-- the word between parts: "and", or "or" for Any of
function CT.Joiner(rec, k)
    if k and CT.Any(rec, k) then return Tr("or") end
    return Tr("and")
end

-- "While it is ready and its aura is down and you are in combat", from the parts in order.
function CT.WhenLine(parts, any)
    local C = Clauses()
    local out = {}
    for _, p in ipairs(parts) do out[#out + 1] = C[p] or Lower(CT.CondWord(p)) end
    return Tr("While %s"):format(table.concat(out, " " .. (any and Tr("or") or Tr("and")) .. " "))
end

-- a combined trigger's parts in its name's order
function CT.PartList(rec, k)
    local states, conds = CT.Parts(rec, k)
    local out = { states[1] }
    local aura = CT.AuraPart(rec, k)
    if aura then out[2] = aura end
    for i = 2, #states do out[#out + 1] = states[i] end
    for _, c in ipairs(conds) do out[#out + 1] = c end
    return out
end

-- + And...'s groups: { title, items = { key, text, on } }. On a state's card
-- (k and look nil), an own look's (look) or a combined trigger's (k).
function CT.Offer(rec, k, base, look)
    local OL = NS.OwnLooks
    local groups = {}
    local have = {}
    if k then
        for _, p in ipairs(CT.PartList(rec, k)) do have[p] = true end
    else
        have[base] = true
        for _, p in ipairs((look and look.when) or EMPTY) do have[p] = true end
    end
    -- the families the trigger already has a state of
    local fam = {}
    for p in pairs(have) do
        if CT.FAMILY[p] then fam[CT.FAMILY[p]] = true end
    end
    if CT.On(rec) and CT.GLOW_PRE[base] then
        local auraOK = (k == nil and CT.FreeSlot(rec) ~= nil) or (k ~= nil and CT.AuraPart(rec, k) == nil)
        groups[#groups + 1] = { title = Tr("ITS AURA"), items = {
            { key = "auraUp", text = Tr("Aura active"), on = auraOK },
            { key = "auraMissing", text = Tr("Aura missing"), on = auraOK },
        } }
    end
    local stateOK = Schema.OWN_LOOK_STATE_KINDS ~= nil and Schema.OWN_LOOK_STATE_KINDS[rec.kind] == true
    local looksOK = OL ~= nil and OL.Offered ~= nil and OL.Offered(rec, OL.StateKey(rec.kind, base)) == true
    if stateOK and (k or looksOK) then
        local spell = { title = Tr("THE SPELL"), items = {} }
        local any = k ~= nil and CT.Any(rec, k)
        for _, s in ipairs(CT.STATE_ORDER) do
            if (any and not have[s]) or (not any and not fam[CT.FAMILY[s]]) then
                spell.items[#spell.items + 1] = { key = s, text = CT.StateWord(rec, s), on = true }
            end
        end
        if spell.items[1] then groups[#groups + 1] = spell end
    end
    if k or looksOK then
        local when = { title = Tr("WHEN"), items = {} }
        for _, c in ipairs((OL and OL.CONDITIONS) or EMPTY) do
            when.items[#when.items + 1] = { key = c.key, text = CT.CondWord(c.key), on = not have[c.key] }
        end
        groups[#groups + 1] = when
    end
    return groups
end
