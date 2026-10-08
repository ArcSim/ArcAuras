-- Stance icons: the stance, form or aura you are in, read off the stance bar.
-- Your current stance shows the entry you are in, greyed while in none; One
-- stance lights up while you are in it. In it is the ready look, not in it
-- the cooldown look (Factory.SetState). Called through Driver.Attach /
-- Detach / Refeed in AD_DriverCooldown.

-- The bar's reads carry no secret annotation and are plain in combat on both
-- clients; a secret answer anyway keeps the last plain one. A rogue's Vanish
-- and Shadow Dance shift the bar's order, so a stance is matched by its spell
-- ID (or its name: another rank), never by its place on the bar.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local DS = {}
NS.DriverStance = DS

DS.KEY = "adstance"
DS.EVENTS = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS" }
DS.attached = {}   -- [iconId] = { rec, frame, on }
DS.armed = false
-- the bar's last plain read: { sid, icon } per entry, in the bar's order
DS.bar = {}
-- the stance you are in (its spell ID), false for none, nil before a plain read
DS.cur = nil
-- the last stance you were in this session: your current stance's art in none
DS.last = nil
-- [spellID] = its name, once the game answers one (names never change)
DS.names = {}

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- "current" or "one"
function DS.Mode(rec)
    return (rec and Store.Resolve(rec, "stance", "shows") == "one") and "one" or "current"
end

-- The picked stance's spell ID, or nil.
function DS.Pick(rec)
    local d = rec and rec.driver
    local sid = type(d) == "table" and tonumber(d.spellID) or nil
    if sid and sid > 0 then return sid end
    return nil
end

function DS.Name(sid)
    if type(sid) ~= "number" then return nil end
    local n = DS.names[sid]
    if n then return n end
    n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) -- raw-id: a bar entry or a typed pick, for its label
    if Secret(n) or type(n) ~= "string" or n == "" then return nil end
    DS.names[sid] = n
    return n
end

-- One stance: the picked one (`want`) and the bar's (`got`) through the one
-- matcher, any rank by name on either client.
function DS.Same(want, got)
    if type(want) ~= "number" or type(got) ~= "number" then return false end
    return Store.SpellMatch(want, got, nil, true)
end

-- Reads the bar: true with a plain answer, false with a secret one, which
-- leaves the last plain read in place.
function DS.Read()
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then
        DS.bar, DS.cur = {}, false
        return true
    end
    local n = GetNumShapeshiftForms()
    if Secret(n) then return false end
    if type(n) ~= "number" then n = 0 end
    local list, cur = {}, false
    for i = 1, n do
        local icon, active, _, sid = GetShapeshiftFormInfo(i)
        if Secret(active) or Secret(sid) then return false end
        if type(sid) == "number" then
            list[#list + 1] = { sid = sid, icon = icon }
            -- plain by now; an older client answers 1 rather than true
            if active and not cur then cur = sid end
        end
    end
    -- no entry marked active: the place the game names, read in the same pass
    if not cur and GetShapeshiftForm then
        local idx = GetShapeshiftForm()
        if Secret(idx) then return false end
        if type(idx) == "number" and idx >= 1 and idx <= n then
            local _, _, _, sid = GetShapeshiftFormInfo(idx)
            if Secret(sid) then return false end
            if type(sid) == "number" then cur = sid end
        end
    end
    DS.bar, DS.cur = list, cur
    if cur then DS.last = cur end
    return true
end

-- A read for a caller with no icon attached (the options, a style pass before
-- the first attach); while one is, the events keep the answer.
function DS.Fresh()
    if not DS.armed then DS.Read() end
end

-- The bar's entry for a stance: by spell ID, else another rank by name.
function DS.Entry(sid)
    if type(sid) ~= "number" then return nil end
    for _, e in ipairs(DS.bar) do
        if e.sid == sid then return e end
    end
    for _, e in ipairs(DS.bar) do
        if DS.Same(sid, e.sid) then return e end
    end
    return nil
end

-- In it: your current stance while you are in any, one stance while you are
-- in that one. Unknown (no plain read yet) is not in it.
function DS.Active(rec)
    local cur = DS.cur
    if not cur then return false end
    if DS.Mode(rec) == "current" then return true end
    return DS.Same(DS.Pick(rec), cur)
end

-- The stance an icon shows: one stance its pick; your current stance the one
-- you are in, else the last one you were in, else the bar's first.
function DS.Shown(rec)
    if DS.Mode(rec) == "one" then return DS.Pick(rec) end
    if DS.cur then return DS.cur end
    if DS.last and DS.Entry(DS.last) then return DS.last end
    local first = DS.bar[1]
    return first and first.sid or nil
end

-- Its art: the bar's own icon for that stance (the bar may show an active
-- look while you are in it), else the spell's; nil is the question mark.
function DS.Texture(rec)
    DS.Fresh()
    local sid = Store.RecordSpellID(rec.driver, DS.Shown(rec))
    if not sid then return nil end
    local e = DS.Entry(sid)
    if e and e.icon ~= nil then return e.icon end
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid) or nil
end

-- The bar's entries for the options' pick: { sid, name } in the bar's order.
function DS.BarList()
    DS.Fresh()
    local out = {}
    for _, e in ipairs(DS.bar) do out[#out + 1] = { sid = e.sid, name = DS.Name(e.sid) } end
    return out
end

-- The options' question: your bar's entry for a stance (any rank), or nil.
function DS.OnBar(sid)
    DS.Fresh()
    return DS.Entry(sid)
end

-- The stance it shows; your current stance in none says so.
function DS.Tooltip(rec)
    DS.Fresh()
    if DS.Mode(rec) == "current" and not DS.cur then
        GameTooltip:SetText(rec.name or "Stance")
        GameTooltip:AddLine("Not in a stance.", 0.7, 0.7, 0.7)
        return
    end
    local sid = Store.RecordSpellID(rec.driver, DS.Shown(rec))
    if sid and C_Spell and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(sid) then
        GameTooltip:SetSpellByID(sid)
    else
        GameTooltip:SetText(rec.name or "Stance")
    end
end

-- Its art every time (PaintArt skips an unchanged one); its state when it
-- flips, or forced after a style pass.
function DS.Paint(a, force)
    local F = NS.Factory
    local rec, f = a.rec, a.frame
    F.PaintArt(f, F.GetTexture(rec))
    local on = DS.Active(rec)
    if force or a.on ~= on then
        a.on = on
        F.SetState(f, rec, not on, not on)
    end
end

-- A stance change: one read of the bar, then every icon.
function DS.OnEvent()
    if not DS.Read() then return end
    for _, a in pairs(DS.attached) do DS.Paint(a) end
end

-- Events.On registers directly, and a client throws on an event it lacks.
function DS.Valid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e))
end

-- The events stay registered only while a stance icon is attached.
function DS.Arm()
    local want = next(DS.attached) ~= nil
    if want == DS.armed then return end
    DS.armed = want
    for _, e in ipairs(DS.EVENTS) do
        if want then
            if DS.Valid(e) then Events.On(e, DS.KEY, DS.OnEvent) end
        else
            Events.Off(e, DS.KEY)
        end
    end
end

function DS.Attach(rec, f)
    local a = DS.attached[rec.id] or {}
    DS.attached[rec.id] = a
    a.rec, a.frame = rec, f
    DS.Arm()
    DS.Read()
    DS.Paint(a, true)
end

function DS.Detach(id)
    if not DS.attached[id] then return end
    DS.attached[id] = nil
    DS.Arm()
end

function DS.Refeed(id)
    local a = DS.attached[id]
    if not a then return end
    DS.Read()
    DS.Paint(a, true)
end
