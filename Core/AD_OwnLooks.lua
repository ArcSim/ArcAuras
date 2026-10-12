-- AD_OwnLooks: an icon's own looks, rows under a state of its By State table
-- ("Missing, no target") that take that state's opacity, grey, tint and glow
-- over while every condition they name holds; the top one that holds wins.
-- An icon follows a list as it follows a look value: its own when it has one
-- (an empty one is none), else its layout's for its kind, else the Defaults
-- page's. Editing an inherited list copies it first, so an icon never edits
-- its layout or its defaults.
-- Factory.SetState asks OL.Active for each state in play; a watcher on the
-- conditions in use repaints only the icons whose looks name one that moved.
-- Every condition offered reads without secrets, and a repaint only rewrites
-- what Factory.SetState already paints on our own frames in combat.
local ADDON, NS = ...
local Store, Schema = NS.Store, NS.Schema

local OL = {}
NS.OwnLooks = OL

local EMPTY = {}

-- The conditions a look can name, in the panel's order, in the words of the
-- load conditions: { key = , text = } (also [1] key, [2] text).
OL.CONDITIONS = {}
OL.CONDITION_OK = {}
for _, key in ipairs(Schema.OWN_LOOK_CONDITIONS) do
    local d = NS.Conditions and NS.Conditions.ByKey(key)
    if d then
        OL.CONDITIONS[#OL.CONDITIONS + 1] = { key = key, text = d.text, key, d.text }
        OL.CONDITION_OK[key] = true
    end
end

-- The By State key of a kind's ready and cooldown buckets where it is not
-- "ready" / "cooldown"; Recharging and a Custom Icon's Ready are their own.
OL.BUCKETS = {
    timer = { ready = "active", cooldown = "inactive" },
    totem = { ready = "active", cooldown = "missing" },
    enchant = { ready = "active", cooldown = "missing" },
    groupbuff = { ready = "lacking", cooldown = "covered" },
    stance = { ready = "active", cooldown = "inactive" },
}

-- The part the Defaults page's parts carry to take a kind's own looks in
-- (Store.DefaultsOwnCount / DefaultsFollow / ResetDefaults / CopyDefaults).
OL.PART = { section = Store.OWN_LOOKS_PART, fields = {} }

function OL.StateKey(kind, bucket)
    local b = OL.BUCKETS[kind]
    return (b and b[bucket]) or bucket
end

-- What a state of this record's kind has (Schema.OWN_LOOK_STATES), or nil.
function OL.Spec(rec, stateKey)
    local states = rec and Schema.OWN_LOOK_STATES[rec.kind]
    return states and states[stateKey] or nil
end

-- Where a record keeps its list: "icon" (rec.ownLooks), "layout" (a layout's
-- for one kind, OL.LayoutRecord), "defaults" (one kind's on the Defaults page,
-- Store.DefaultsProxy), or nil (no list: the page's All row, a layout's look
-- proxy, several icons at once, a show-all group's type look).
local function Tier(rec)
    if rec == nil then return nil end
    if rec._adDefaults then
        return (rec.type == "icon" and rec.kind ~= nil and not rec._adKinds) and "defaults" or nil
    end
    if rec._adOwnLooksLayout then return "layout" end
    if rec.type ~= "icon" or rec._adLayoutTier or rec._adMulti or rec._adTypeLook then return nil end
    return "icon"
end

-- A layout's looks for one icon kind, as a record the API takes: its writes
-- land in the layout, and its other rows (Store.SetOverride) in the layout's
-- icon looks. nil for a kind with no states.
local layoutRecs = setmetatable({}, { __mode = "k" })
function OL.LayoutRecord(layout, kind)
    if not (layout and layout.type == "layout" and kind and Schema.OWN_LOOK_STATES[kind]) then return nil end
    local by = layoutRecs[layout]
    if not by then
        by = {}
        layoutRecs[layout] = by
    end
    local r = by[kind]
    if not r then
        r = { type = "icon", kind = kind, _adOwnLooksLayout = true, _adLayoutTier = true, _adLayout = layout,
            _adFamily = "icon", c = {}, driver = {} }
        by[kind] = r
    end
    local px = Store.LayoutProxy(layout, "icon")
    r.o = px and px.o or {}
    return r
end

-- A state this record's looks can take: a real icon's, a layout's for a kind,
-- or a kind's on the Defaults page.
function OL.Offered(rec, stateKey)
    return Tier(rec) ~= nil and OL.Spec(rec, stateKey) ~= nil
end

-- The list in play and where it comes from: "own" (the record holds it),
-- "layout" or "defaults" (followed), or nil, nil (none anywhere). Called on
-- every state write: no allocation.
function OL.Effective(rec)
    local tier = Tier(rec)
    if tier == "icon" then
        local own = rec.ownLooks
        if type(own) == "table" then return own, "own" end
        return Store.InheritedOwnLooks(rec)
    elseif tier == "layout" then
        local own = Store.LayoutOwnLooks(rec._adLayout, rec.kind)
        if own then return own, "own" end
        local d = Store.DefaultOwnLooks(rec.kind)
        if d then return d, "defaults" end
    elseif tier == "defaults" then
        local d = Store.DefaultOwnLooks(rec.kind)
        if d then return d, "own" end
    end
    return nil, nil
end

-- What the record would follow without a list of its own.
local function Inherited(rec, tier)
    if tier == "icon" then return (Store.InheritedOwnLooks(rec)) end
    if tier == "layout" then return Store.DefaultOwnLooks(rec.kind) end
    return nil
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Unit(v)
    if type(v) ~= "number" or v ~= v then return nil end
    return math.max(0, math.min(1, v))
end

local function Color(c)
    if type(c) ~= "table" or not (Unit(c[1]) and Unit(c[2]) and Unit(c[3])) then return nil end
    return { Unit(c[1]), Unit(c[2]), Unit(c[3]), Unit(c[4]) or 1 }
end

local function Switch(v)
    if v == nil then return nil end
    return v ~= false
end

-- Known keys once each, in order; nil when none is left.
local function CleanWhen(list)
    if type(list) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, k in ipairs(list) do
        if OL.CONDITION_OK[k] and not seen[k] then
            seen[k] = true
            out[#out + 1] = k
        end
    end
    return (#out > 0) and out or nil
end

-- several records written as one: the watcher syncs once at the end
local batching = false

local function Changed(rec)
    Store.Dirty("style", Tier(rec) == "icon" and rec.id or nil)
    if not batching then OL.Sync() end
end

-- The list a write may change: the record's own, copied from what it follows
-- first; a Defaults page kind's is a copy the write hands back to the store.
local function Writable(rec)
    local tier = Tier(rec)
    if tier == "defaults" then return Copy(Store.DefaultOwnLooks(rec.kind)) or {} end
    local list, src = OL.Effective(rec)
    if src == "own" then return list end
    list = Copy(list) or {}
    if tier == "icon" then
        rec.ownLooks = list
    elseif tier == "layout" then
        Store.SetLayoutOwnLooks(rec._adLayout, rec.kind, list)
    end
    return list
end

-- A written list kept: one that reads as what the record follows is dropped,
-- so the record follows again (the sparse rule of the other looks).
local function Commit(rec, list)
    local tier = Tier(rec)
    if tier == "defaults" then
        Store.SetDefaultOwnLooks(rec.kind, list, rec._adBatch)
    else
        local keep = not Store.SameLooks(list, Inherited(rec, tier))
        if tier == "icon" then
            rec.ownLooks = keep and list or nil
        else
            Store.SetLayoutOwnLooks(rec._adLayout, rec.kind, keep and list or nil)
        end
    end
    Changed(rec)
end

-- The followed list copied into the record (an icon's or a layout's), so it
-- can change apart from it. True when the record holds its own now.
function OL.MakeOwn(rec)
    local tier = Tier(rec)
    if not tier then return false end
    if tier == "defaults" or select(2, OL.Effective(rec)) == "own" then return true end
    Writable(rec)
    Changed(rec)
    return true
end

-- Drops the record's own list so it follows again: an icon its layout or
-- defaults, a layout the defaults, a Defaults page kind none (its followers
-- keep theirs under the page's batch). True when it changed.
function OL.Follow(rec)
    local tier = Tier(rec)
    if tier == "icon" then
        if rec.ownLooks == nil then return false end
        rec.ownLooks = nil
    elseif tier == "layout" then
        if not Store.SetLayoutOwnLooks(rec._adLayout, rec.kind, nil) then return false end
    elseif tier == "defaults" then
        if not Store.SetDefaultOwnLooks(rec.kind, nil, rec._adBatch) then return false end
    else
        return false
    end
    Changed(rec)
    return true
end

-- This state's looks in the order they win: { { index = i in the list in
-- play, look = entry, source = OL.Effective's }, ... }.
function OL.List(rec, stateKey)
    local out = {}
    local list, src = OL.Effective(rec)
    for i, l in ipairs(list or EMPTY) do
        if l.state == stateKey then out[#out + 1] = { index = i, look = l, source = src } end
    end
    return out
end

function OL.Has(rec, stateKey)
    for _, l in ipairs(OL.Effective(rec) or EMPTY) do
        if l.state == stateKey then return true end
    end
    return false
end

-- A Missing look that shows the icon: its Missing look needs its stage even
-- while the state's own hides it (DriverAura.GhostShown, DriverAuraRows.MissMode).
function OL.ShowsMissing(rec)
    for _, l in ipairs(OL.Effective(rec) or EMPTY) do
        if l.state == "missing" and type(l.alpha) == "number" and l.alpha > 0 then return true end
    end
    return false
end

-- A new look for the state under its others, while condKey holds. copy: the
-- state's look as the table shows it ({ alpha, grey, tint, tintColor, glow }),
-- so nothing changes until it is edited; what the state lacks is left out.
-- Returns its index in the list in play, or nil.
function OL.Add(rec, stateKey, condKey, copy)
    if not (OL.Offered(rec, stateKey) and OL.CONDITION_OK[condKey]) then return nil end
    local cur = OL.Effective(rec)
    if cur and #cur >= Schema.OWN_LOOK_MAX then return nil end
    local spec = OL.Spec(rec, stateKey)
    copy = type(copy) == "table" and copy or EMPTY
    local l = { state = stateKey, when = { condKey } }
    if spec.a then l.alpha = Unit(copy.alpha) end
    if spec.g then l.grey = Switch(copy.grey) end
    if spec.t then
        l.tint = Switch(copy.tint)
        l.tintColor = Color(copy.tintColor)
    end
    if spec.glow then l.glow = Switch(copy.glow) end
    local list = Writable(rec)
    list[#list + 1] = l
    Commit(rec, list)
    return #list
end

function OL.Remove(rec, index)
    local cur = OL.Effective(rec)
    if not (Tier(rec) and type(cur) == "table" and type(index) == "number" and cur[index]) then return false end
    local list = Writable(rec)
    table.remove(list, index)
    Commit(rec, list)
    return true
end

-- Swaps a look with the next one up (dir -1) or down (1) under the same
-- state. Returns its new index, or nil.
function OL.Move(rec, index, dir)
    local cur = OL.Effective(rec)
    local l = Tier(rec) and type(cur) == "table" and type(index) == "number" and cur[index] or nil
    if type(l) ~= "table" or (dir ~= -1 and dir ~= 1) then return nil end
    local j = index + dir
    while cur[j] and cur[j].state ~= l.state do j = j + dir end
    if not cur[j] then return nil end
    local list = Writable(rec)
    list[index], list[j] = list[j], list[index]
    Commit(rec, list)
    return j
end

-- One column of a look: alpha (0-1, nil = the state's own), grey, tint or
-- glow (true / false, nil = the state's own), tintColor ({ r, g, b, a } or
-- nil), when (a list of condition keys, at least one). A column the state
-- lacks is refused. Returns true when it was taken.
function OL.Set(rec, index, field, value)
    local cur = OL.Effective(rec)
    local l = Tier(rec) and type(cur) == "table" and type(index) == "number" and cur[index] or nil
    local spec = type(l) == "table" and OL.Spec(rec, l.state) or nil
    if not spec then return false end
    local v
    if field == "alpha" then
        if not spec.a or (value ~= nil and type(value) ~= "number") then return false end
        v = Unit(value)
    elseif field == "grey" then
        if not spec.g then return false end
        v = Switch(value)
    elseif field == "tint" then
        if not spec.t then return false end
        v = Switch(value)
    elseif field == "tintColor" then
        if not spec.t or (value ~= nil and not Color(value)) then return false end
        v = Color(value)
    elseif field == "glow" then
        if not spec.glow then return false end
        v = Switch(value)
    elseif field == "when" then
        v = CleanWhen(value)
        if not v then return false end
    else
        return false
    end
    local list = Writable(rec)
    list[index][field] = v
    Commit(rec, list)
    return true
end

-- Several icons at once

-- The same conditions, in any order.
local function SameWhen(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for _, k in ipairs(a) do
        local hit = false
        for _, x in ipairs(b) do
            if x == k then
                hit = true
                break
            end
        end
        if not hit then return false end
    end
    return true
end

-- The lead's look and, per record of recs, the index of its first look with
-- the same state and conditions: { { rec, index }, ... }, the lead first.
-- Read before any write, so a change of conditions still finds them.
local function Matches(recs, lead, index)
    local cur = OL.Effective(lead)
    local want = type(cur) == "table" and type(index) == "number" and cur[index] or nil
    if type(want) ~= "table" then return nil end
    local out, seen = { { lead, index } }, { [lead] = true }
    for _, r in ipairs(recs or EMPTY) do
        if not seen[r] then
            seen[r] = true
            for i, l in ipairs(OL.Effective(r) or EMPTY) do
                if type(l) == "table" and l.state == want.state and SameWhen(l.when, want.when) then
                    out[#out + 1] = { r, i }
                    break
                end
            end
        end
    end
    return out
end

local function Many(fn)
    batching = true
    local a, b = fn()
    batching = false
    OL.Sync()
    return a, b
end

-- The look onto each record (copyFn(rec): that record's copy of its state's
-- look). Returns how many took it.
function OL.AddMany(recs, stateKey, condKey, copyFn)
    return Many(function()
        local n = 0
        for _, r in ipairs(recs or EMPTY) do
            if OL.Add(r, stateKey, condKey, copyFn and copyFn(r) or nil) then n = n + 1 end
        end
        return n
    end)
end

-- OL.Set on the lead's look and on the matching look of every record of
-- recs that has one. Returns how many took it.
function OL.SetMatching(recs, lead, index, field, value)
    return Many(function()
        local n = 0
        for _, m in ipairs(Matches(recs, lead, index) or EMPTY) do
            if OL.Set(m[1], m[2], field, value) then n = n + 1 end
        end
        return n
    end)
end

-- OL.Remove likewise. Returns how many lost it.
function OL.RemoveMatching(recs, lead, index)
    return Many(function()
        local n = 0
        for _, m in ipairs(Matches(recs, lead, index) or EMPTY) do
            if OL.Remove(m[1], m[2]) then n = n + 1 end
        end
        return n
    end)
end

-- OL.Move likewise, each within its own list. Returns how many moved, and
-- the lead's new index (nil when it could not move).
function OL.MoveMatching(recs, lead, index, dir)
    return Many(function()
        local n, at = 0, nil
        for _, m in ipairs(Matches(recs, lead, index) or EMPTY) do
            local j = OL.Move(m[1], m[2], dir)
            if j then
                n = n + 1
                if m[1] == lead then at = j end
            end
        end
        return n, at
    end)
end

-- Follow counts

-- Icons of `kind` (every kind when nil) holding their own list where a tier
-- would hand them one: inside `layout` while it has a list for their kind;
-- with no layout, wherever their layout has none (the Defaults page's).
-- drop: they follow it.
local function OwnWalk(kind, layout, drop)
    local items = {}
    if layout then
        items = Store.LayoutItems(layout, "icon")
    else
        Store.EachRecord(function(_, r)
            if r.type == "icon" then items[#items + 1] = r end
        end)
    end
    local n = 0
    for _, r in ipairs(items) do
        if r.type == "icon" and (kind == nil or r.kind == kind) and r.ownLooks ~= nil then
            local _, src = Store.InheritedOwnLooks(r)
            if (layout ~= nil) == (src == "layout") then
                n = n + 1
                if drop then
                    r.ownLooks = nil
                    Store.Dirty("style", r.id)
                end
            end
        end
    end
    if drop and n > 0 then OL.Sync() end
    return n
end

function OL.CountOwn(kind, layout) return OwnWalk(kind, layout, false) end
function OL.FollowAll(kind, layout) return OwnWalk(kind, layout, true) end

-- The first look for the state whose every condition holds now, else nil.
-- Called on every state write: no allocation, one read per condition.
function OL.Active(rec, stateKey)
    if stateKey == nil then return nil end
    local list = OL.Effective(rec)
    if type(list) ~= "table" then return nil end
    local C = NS.Conditions
    if not C then return nil end
    for i = 1, #list do
        local l = list[i]
        local when = type(l) == "table" and l.state == stateKey and l.when or nil
        if type(when) == "table" and #when > 0 then
            local ok = true
            for j = 1, #when do
                if C.Read(when[j]) ~= true then
                    ok = false
                    break
                end
            end
            if ok then return l end
        end
    end
    return nil
end

-- The words after the state on a look's row: "no target", "out of combat and
-- in an instance", in the client's language.
function OL.Label(look)
    local L, C = NS.L, NS.Conditions
    local parts = {}
    for _, k in ipairs(type(look) == "table" and type(look.when) == "table" and look.when or EMPTY) do
        local d = C and C.ByKey(k)
        local w = d and d.text or tostring(k)
        if L then w = L[w] or w end
        parts[#parts + 1] = (w:gsub("^%u", string.lower))
    end
    local andWord = L and L["and"] or "and"
    return table.concat(parts, " " .. andWord .. " ")
end

-- Factory.SetState's glow word for each lane the look in play decides, on
-- f._adLookGlow (Factory.LookGlow reads it): off for every lane of the state
-- when the look says no glow; with a glow and none of the state's switched
-- on, its first lane. An aura's Missing glows are only ever turned off.
function OL.PutGlows(f, rec, stateKey, look)
    if not look or look.glow == nil then return end
    local spec = OL.Spec(rec, stateKey)
    local lanes = spec and spec.glow
    if not lanes then return end
    local T = f._adLookGlowT
    if not T then
        T = {}
        f._adLookGlowT = T
    end
    if f._adLookGlow ~= T then
        wipe(T)
        f._adLookGlow = T
    end
    if look.glow == false then
        for i = 1, #lanes do T[lanes[i]] = false end
    elseif lanes[1] ~= "missing" then
        local any = false
        for i = 1, #lanes do
            if Store.Resolve(rec, "states", lanes[i]) == true then any = true end
        end
        if not any then T[lanes[1]] = true end
    end
end

-- The watcher: each condition key in use, the icons whose looks name it and
-- the answer the last pass gave. No icon with looks, no watcher.
local users = {}
local last = {}
local due = {}

local function Plain(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) or v <= 0 then return nil end
    return v
end

-- Paints one icon's state again from what its drivers last reported: its
-- frame, its Missing look in a Dynamic aura group's row, and the Play on
-- screen copy over it. Our own frames only.
function OL.Repaint(id)
    local rec = Store.Get(id)
    if not rec then return end
    local AR = NS.DriverAuraRows
    if AR and AR.RepaintLook then AR.RepaintLook(id) end
    local F = NS.Factory
    local f = F and F.frames and F.frames[id]
    if f and f._adOnCooldown ~= nil then
        F.SetState(f, rec, f._adOnCooldown, f._adDesatState)
        if rec.kind == "aura" then
            -- the Missing glows are the holder's own frames, as DriverAura sizes them
            local DA, E = NS.DriverAura, NS.LayoutEngine
            local combat = (DA ~= nil and DA.InCombat ~= nil and DA.InCombat() == true)
                or (E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true)
            local h = Plain(f:GetHeight()) or 36
            F.ApplyMissingGlows(f, rec, Plain(f:GetWidth()) or h, h, combat)
        elseif OL.Has(rec, "toggle") then
            local DT = NS.DriverToggle
            if DT and DT.Apply then DT.Apply(f, rec) end
        end
    end
    local S = NS.IconScreen
    if S and S.On and S.Paint and S.On(id) then S.Paint(rec) end
end

-- After every conditions pass: repaint the icons whose looks name a key
-- whose answer moved.
function OL.OnPass()
    local C = NS.Conditions
    if not C then return end
    local any = false
    for k, ids in pairs(users) do
        local v = C.Read(k)
        if last[k] ~= v then
            last[k] = v
            for id in pairs(ids) do
                due[id] = true
                any = true
            end
        end
    end
    if not any then return end
    for id in pairs(due) do
        due[id] = nil
        OL.Repaint(id)
    end
end

-- Which icons' looks in play (their own, their layout's or the defaults')
-- name which keys, and the conditions watcher for them.
function OL.Sync()
    wipe(users)
    local keys
    Store.EachRecord(function(id, rec)
        local list = rec.type == "icon" and OL.Effective(rec)
        if type(list) ~= "table" then return end
        for _, l in ipairs(list) do
            local when = type(l) == "table" and l.when
            for _, k in ipairs(type(when) == "table" and when or EMPTY) do
                local set = users[k]
                if not set then
                    set = {}
                    users[k] = set
                end
                set[id] = true
                keys = keys or {}
                keys[k] = true
            end
        end
    end)
    for k in pairs(last) do
        if not users[k] then last[k] = nil end
    end
    local C = NS.Conditions
    if C and C.Watch then C.Watch("ownlooks", keys, OL.OnPass) end
end

-- The icons whose looks name a key ([id] = true), or nil.
function OL.Users(key) return users[key] end

local Events = NS.Events
if Events then
    Events.On("PLAYER_LOGIN", "ownlooks", OL.Sync)
    Events.On("PLAYER_ENTERING_WORLD", "ownlooks", OL.Sync)
    Events.OnMessage("AD_DIRTY", "ownlooks", function()
        Events.Coalesce("ad_ownlooks", OL.Sync)
    end)
end
