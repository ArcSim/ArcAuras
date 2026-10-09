-- AD_Looks: a resource bar's own look for each power it shows (a druid's forms),
-- for each spec, or with and without a talent. A look stores only what differs
-- from the bar's settings, so a field it leaves alone reads the bar's own.
-- Store.Resolve asks LK.Value first; while the options edit a look,
-- Store.SetOverride writes into it and the bar shows that look. Record shape:
-- rec.looks = { by = "power" | "spec" | "talent", power = { [powerType] = { [section] = { [field] = v } } },
--               spec = { [specID] = { ... } }, talent = { [1] = with it, [0] = without },
--               talentNode = nodeID, talentEntry = a choice node's option }
-- A talent change rebuilds every bar (AD_LayoutEngine), so the look follows it.
local ADDON, NS = ...
local Store, Schema = NS.Store, NS.Schema

local LK = {}
NS.Looks = LK

-- [recId] = the look the options are editing, while they do; LK.BASE is the
-- bar's own settings, so no look applies while they are edited
LK.editing = {}
LK.BASE = "base"
-- a talent's two looks
LK.WITH, LK.WITHOUT = 1, 0

-- a druid's form for each power, for the picker's words
LK.FORM_WORDS = { [0] = "caster and travel form", [1] = "Bear Form", [3] = "Cat Form", [8] = "Moonkin Form" }
-- the powers UnitPowerType can answer: the ones a bar can show as its own
LK.DISPLAY_POWERS = { 0, 1, 2, 3, 6, 8, 11, 13, 17, 18 }

function LK.Offered(rec)
    return rec ~= nil and rec.type == "bar" and rec.barKind == "resource"
end

-- "power" needs a bar that follows the shown power; "spec" a client with
-- specs; "talent" the talent catalog (both clients)
function LK.ModeOK(rec, mode)
    if not LK.Offered(rec) then return false end
    if mode == "power" then
        local pt = rec.driver and rec.driver.powerType
        return pt == nil or pt < 0
    end
    if mode == "spec" then return NS.IsForever ~= true end
    if mode == "talent" then return NS.TalentCatalog ~= nil end
    return false
end

-- Whether the picked talent is taken, as the custom engine's talent guard
-- reads it: a choice node counts only with the picked option active. nil with
-- no talent picked. Talents are never secret.
function LK.TalentTaken(lk)
    local T, node = NS.TalentCatalog, lk.talentNode
    if not (T and node) then return nil end
    local met = T.IsTaken(node) == true
    if met and lk.talentEntry then met = T.ActiveEntry ~= nil and T.ActiveEntry(node) == lk.talentEntry end
    return met
end

-- The look in play: the one being edited, else the power the bar shows now
-- (UnitPowerType is not secret and follows druid forms), the spec, or the
-- talent's look.
function LK.Key(rec, lk)
    -- LK.BASE names no look, so the bar's own settings read through
    local k = LK.editing[rec.id]
    if k ~= nil then return k end
    if lk.by == "power" then return UnitPowerType and (UnitPowerType("player")) or nil end
    if lk.by == "spec" then return Store.CurSpecID and Store.CurSpecID() or nil end
    if lk.by == "talent" then
        local met = LK.TalentTaken(lk)
        if met == nil then return nil end
        return met and LK.WITH or LK.WITHOUT
    end
    return nil
end

function LK.Value(rec, lk, section, field)
    local by = lk.by
    if not by or Schema.LOOK_SKIP[section] then return nil end
    local sets = lk[by]
    if not sets then return nil end
    local key = LK.Key(rec, lk)
    local set = key ~= nil and sets[key]
    local s = set and set[section]
    if s then return s[field] end
    return nil
end

-- A look's own state rows (set.resColors, Conditions > By State): the look in
-- play's list, else nil and the bar's own rows apply. An empty list is a look
-- with no states.
function LK.Rows(rec)
    local lk = rec and rec.looks
    local by = lk and lk.by
    local sets = by and lk[by]
    if not sets then return nil end
    local key = LK.Key(rec, lk)
    if key == nil or key == LK.BASE then return nil end
    local set = sets[key]
    return set and set.resColors or nil
end

-- The rows the editor writes while one of the bar's looks is edited: the
-- look's own, made from a copy of the bar's on the first edit (make). nil
-- while the bar's own settings are edited.
function LK.EditRows(rec, make)
    local lk = rec and rec.looks
    local by = lk and lk.by
    local key = rec and LK.editing[rec.id]
    if not (by and key ~= nil and key ~= LK.BASE) then return nil end
    local set = lk[by] and lk[by][key]
    if set and set.resColors then return set.resColors end
    if not make then return nil end
    lk[by] = lk[by] or {}
    set = lk[by][key] or {}
    lk[by][key] = set
    local rows = {}
    local function Copy(v)
        if type(v) ~= "table" then return v end
        local t = {}
        for k, x in pairs(v) do t[k] = Copy(x) end
        return t
    end
    for i, r in ipairs((rec.driver and rec.driver.resColors) or {}) do rows[i] = Copy(r) end
    set.resColors = rows
    return rows
end

-- A write while a look is edited: kept only where it differs from what the bar
-- reads without it. False when no look of this bar is being edited.
function LK.Set(rec, section, field, value)
    local lk = rec.looks
    local by = lk and lk.by
    local key = LK.editing[rec.id]
    if not (by and key ~= nil and key ~= LK.BASE) or Schema.LOOK_SKIP[section] then return false end
    lk[by] = lk[by] or {}
    local set = lk[by][key] or {}
    lk[by][key] = set
    local s = set[section] or {}
    set[section] = s
    local old = s[field]
    s[field] = nil
    if value ~= Store.Resolve(rec, section, field) then s[field] = value end
    if next(s) == nil then set[section] = nil end
    if next(set) == nil then lk[by][key] = nil end
    if next(lk[by]) == nil then lk[by] = nil end
    if old ~= value then Store.Dirty("style", rec.id) end
    return true
end

-- nothing left to keep: no mode, and no look stored in any
local function Empty(lk)
    if lk.by ~= nil then return false end
    for _, mode in ipairs(Schema.LOOK_MODES) do
        if lk[mode] then return false end
    end
    return true
end

function LK.SetMode(rec, mode)
    if mode ~= nil and not LK.ModeOK(rec, mode) then return end
    if mode == nil and not rec.looks then return end
    rec.looks = rec.looks or {}
    rec.looks.by = mode
    LK.editing[rec.id] = nil
    if Empty(rec.looks) then rec.looks = nil end
    Store.Dirty("style", rec.id)
end

-- The talent the talent looks follow (nil: none yet). Its looks stay, now
-- following this one; a choice belongs to its talent, so a new one drops it.
function LK.SetTalent(rec, node)
    if not LK.ModeOK(rec, "talent") then return end
    local lk = rec.looks or {}
    if lk.talentNode == node then return end
    rec.looks = lk
    lk.talentNode, lk.talentEntry = node, nil
    if Empty(lk) then rec.looks = nil end
    Store.Dirty("style", rec.id)
end

-- A choice node's option that counts (nil: either).
function LK.SetChoice(rec, entry)
    local lk = rec.looks
    if not (lk and lk.talentNode) or lk.talentEntry == entry then return end
    lk.talentEntry = entry
    Store.Dirty("style", rec.id)
end

-- The picked talent in words: its picked option, a choice node's options, or
-- its ID when this tree lacks it (another class's import).
function LK.TalentName(lk)
    local node = lk and lk.talentNode
    if not node then return nil end
    local T = NS.TalentCatalog
    local e = T and T.Known(node)
    if type(e) ~= "table" then return "talent " .. node end
    if lk.talentEntry and T.EntryInfo then
        local opt = T.EntryInfo(node, lk.talentEntry)
        if opt and opt.name then return tostring(opt.name) end
    end
    if type(e.entries) == "table" and #e.entries > 0 then
        local names = {}
        for _, opt in ipairs(e.entries) do names[#names + 1] = tostring(opt.name) end
        return table.concat(names, " / ")
    end
    return tostring(e.name)
end

-- Which look the options edit: nil is the bar's own. Editing one bar's look
-- ends any other's, so only the bar in the editor ever shows a forced look.
function LK.SetEditing(rec, key)
    for id in pairs(LK.editing) do
        if id ~= rec.id then
            LK.editing[id] = nil
            Store.Dirty("style", id)
        end
    end
    if LK.editing[rec.id] == key then return end
    LK.editing[rec.id] = key
    Store.Dirty("style", rec.id)
end

function LK.StopEditing()
    for id in pairs(LK.editing) do
        LK.editing[id] = nil
        Store.Dirty("style", id)
    end
end

function LK.HasLook(rec, key)
    local lk = rec and rec.looks
    local sets = lk and lk.by and lk[lk.by]
    return sets ~= nil and key ~= nil and sets[key] ~= nil
end

function LK.Reset(rec, key)
    local lk = rec and rec.looks
    local sets = lk and lk.by and lk[lk.by]
    if not (sets and key ~= nil and sets[key]) then return end
    sets[key] = nil
    if next(sets) == nil then lk[lk.by] = nil end
    Store.Dirty("style", rec.id)
end

-- The looks a mode offers, as picker items { value, text }; a talent's carry
-- `line`, when their look applies, for the editor's status line.
function LK.Keys(rec, mode)
    local out = {}
    if mode == "power" then
        local B = NS.Bars
        local all = B and (B.POWER_ALL or B.POWER_INFO) or {}
        local have
        local offered = B and B.ResPowers and B.ResPowers.Offered and B.ResPowers.Offered()
        if offered then
            have = {}
            for _, id in ipairs(offered) do have[id] = true end
        end
        local _, class = UnitClass("player")
        for _, id in ipairs(LK.DISPLAY_POWERS) do
            if (not have or have[id]) and all[id] then
                local text = all[id].name or ("Power " .. id)
                local form = class == "DRUID" and LK.FORM_WORDS[id]
                if form then text = text .. " (" .. form .. ")" end
                out[#out + 1] = { value = id, text = text }
            end
        end
    elseif mode == "spec" then
        -- the specs of this class, as the custom engine's picker reads them
        local SI = C_SpecializationInfo
        local n = (NS.IsForever ~= true and SI and SI.GetSpecializationInfo and GetNumSpecializations
            and GetNumSpecializations()) or 0
        for i = 1, n do
            local id, name = SI.GetSpecializationInfo(i)
            if type(id) == "number" and id > 0 then
                out[#out + 1] = { value = id, text = (type(name) == "string" and name ~= "") and name or ("Spec " .. id) }
            end
        end
    elseif mode == "talent" then
        local name = LK.TalentName(rec.looks)
        if name then
            out[1] = { value = LK.WITH, text = "With " .. name, line = "while you have " .. name }
            out[2] = { value = LK.WITHOUT, text = "Without " .. name, line = "while you don't have " .. name }
        end
    end
    return out
end
