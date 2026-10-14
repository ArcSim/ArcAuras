-- AD_BarSkins: skins for bars. A skin is a named look kept for the whole
-- account (the fill's colours, its texture, the background, the border, the
-- texts; never size or place) that any bar can wear. A bar lists the skins it
-- wears, each with when it switches on: a class, specs of that class, a talent
-- taken or not. The first whose conditions hold wins, else the bar's own look.
-- What one bar changes over its skin stays on that bar (the entry's o); Save to
-- skin moves it into the skin, for every bar that wears it.
-- Store.Resolve asks BS.Value after a resource bar's looks; while the options
-- edit an entry, Store.SetOverride writes into it. Shapes:
-- library (Store.SkinLib): [sid] = { name, parts = { colors = true, ... }, o = { [section] = { [field] = v } } }
-- rec.skins = { { id, skin = sid, cls = "SHAMAN", specs = { [specID] = true },
--   talentNode, talentEntry, without = true, o = { ... } }, ... }
-- An entry whose skin was deleted keeps it as `own` (name, parts, values), a
-- look of that bar alone.
local ADDON, NS = ...
local Store, Schema, Events = NS.Store, NS.Schema, NS.Events

local BS = {}
NS.BarSkins = BS

-- the bar's own look, picked in the editor's Skin dropdown
BS.BASE = "base"
-- [recId] = the entry id the options edit, or BS.BASE, while they do
BS.editing = {}
-- [recId] = the entry in play, false for none; dropped on a spec or talent change
BS.cache = {}
BS.MAX_ENTRIES = 20
BS.NAME_MAX = 40

BS.PARTS = { "colors", "texture", "background", "border", "texts" }
BS.PART_WORDS = { colors = "Colors", texture = "Texture", background = "Background",
    border = "Border", texts = "Texts" }

-- the part each field belongs to; the text section's go by name (TextPart)
local PART = {
    fill = { color = "colors", gradLowColor = "colors", gradMidColor = "colors", gradHighColor = "colors",
        castChannelOn = "colors", castChannelColor = "colors", castLockOn = "colors", castLockColor = "colors",
        useGradient = "colors", gradientDir = "colors", gradientColor = "colors", colorMode = "colors",
        texture = "texture", rotateTexture = "texture" },
    resource = { usePowerColor = "colors" },
    look = { bgShow = "background", bgTexture = "background", bgColor = "background", bgAlpha = "background",
        borderEnabled = "border", borderStyle = "border", borderColor = "border",
        borderThickness = "border", useClassColorBorder = "border" },
}
BS.SECTIONS = { "fill", "resource", "look", "text" }

-- a text's font, colours, outlines and shadows; its size, place and words stay the bar's
local textPart = {}
local function TextPart(field)
    local p = textPart[field]
    if p ~= nil then return p or nil end
    p = false
    local sec = Schema.bar and Schema.bar.text
    if sec and sec.fields[field] and type(field) == "string"
        and (field == "font" or field:find("Color$") or field:find("Outline$") or field:find("Shadow$")) then
        p = "texts"
    end
    textPart[field] = p
    return p or nil
end

function BS.PartOf(section, field)
    local s = PART[section]
    if s then return s[field] end
    if section == "text" then return TextPart(field) end
    return nil
end

-- every field a part holds, as { section, field } pairs, in schema order of sections
function BS.Fields(part)
    local out = {}
    for _, section in ipairs(BS.SECTIONS) do
        local sec = Schema.bar and Schema.bar[section]
        if sec then
            local names = {}
            for field in pairs(sec.fields) do
                if BS.PartOf(section, field) == part then names[#names + 1] = field end
            end
            table.sort(names)
            for _, field in ipairs(names) do out[#out + 1] = { section, field } end
        end
    end
    return out
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
BS.Copy = Copy

-- colours compare by their numbers, so a picked colour equal to the skin's stays unset
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
BS.Same = Same

function BS.Lib()
    return Store.SkinLib and Store.SkinLib() or {}
end

-- the skin an entry wears: its own copy, else the library's (nil: not on this account)
function BS.SkinOf(e)
    if not e then return nil end
    if e.own then return e.own end
    return e.skin and BS.Lib()[e.skin] or nil
end

function BS.Held(sk, section, field)
    local part = BS.PartOf(section, field)
    return part ~= nil and sk ~= nil and sk.parts ~= nil and sk.parts[part] == true
end

local myClass
function BS.MyClass()
    if myClass == nil then
        local _, tag = UnitClass("player")
        myClass = type(tag) == "string" and tag or false
    end
    return myClass or nil
end

function BS.SpecsOK()
    return not (Store.Specless and Store.Specless())
end

-- Whether an entry's conditions hold now, and whether that could not be told
-- yet (no spec at login, no talent catalog), which is never cached. Class,
-- spec and talents are never secret.
function BS.Applies(e)
    if e.cls and e.cls ~= BS.MyClass() then return false end
    if e.specs and next(e.specs) ~= nil and BS.SpecsOK() then
        local s = Store.CurSpecID and Store.CurSpecID()
        if not s then return false, true end
        if not e.specs[s] then return false end
    end
    if e.talentNode then
        local LK = NS.Looks
        local taken = LK and LK.TalentTaken(e)
        if taken == nil then return false, true end
        if taken == (e.without == true) then return false end
    end
    return true
end

function BS.Entry(rec, id)
    for _, e in ipairs(rec and rec.skins or {}) do
        if e.id == id then return e end
    end
    return nil
end

-- The entry in play: the one being edited, else the first that holds.
function BS.Active(rec)
    local list = rec.skins
    if not list then return nil end
    local k = BS.editing[rec.id]
    if k ~= nil then
        if k == BS.BASE then return nil end
        local e = BS.Entry(rec, k)
        return (e and BS.SkinOf(e)) and e or nil
    end
    local c = BS.cache[rec.id]
    if c ~= nil then return c or nil end
    local found, unsure = nil, false
    for _, e in ipairs(list) do
        if BS.SkinOf(e) then
            local ok, unknown = BS.Applies(e)
            if unknown then unsure = true end
            if ok then
                found = e
                break
            end
        end
    end
    if not unsure then BS.cache[rec.id] = found or false end
    return found
end

-- What the skin in play gives a field: this bar's change over it, else the
-- skin's value, for a part the skin holds. nil reads on down the chain.
function BS.Value(rec, section, field)
    local e = BS.Active(rec)
    if not e then return nil end
    local sk = BS.SkinOf(e)
    if not BS.Held(sk, section, field) then return nil end
    local o = e.o and e.o[section]
    if o and o[field] ~= nil then return o[field] end
    o = sk.o and sk.o[section]
    if o then return o[field] end
    return nil
end

function BS.Touch(rec)
    if rec and rec.id then
        BS.cache[rec.id] = nil
        Store.Dirty("style", rec.id)
    end
end

-- A skin's change reaches every bar that wears it.
function BS.TouchAll()
    wipe(BS.cache)
    Store.Dirty("style")
end

local function Prune(t, section)
    if t[section] and next(t[section]) == nil then t[section] = nil end
end

-- A write while an entry is edited: a part its skin holds lands on the entry,
-- kept only where it differs from the skin (an entry of its own writes its
-- copy). False for anything else, which then goes to the bar's own.
function BS.Set(rec, section, field, value)
    local k = BS.editing[rec.id]
    if k == nil or k == BS.BASE then return false end
    local e = BS.Entry(rec, k)
    local sk = BS.SkinOf(e)
    if not BS.Held(sk, section, field) then return false end
    local holder
    if e.own then
        e.own.o = e.own.o or {}
        holder = e.own.o
    else
        e.o = e.o or {}
        holder = e.o
    end
    local s = holder[section] or {}
    holder[section] = s
    local old = s[field]
    s[field] = nil
    if e.own or not Same(value, Store.Resolve(rec, section, field)) then s[field] = Copy(value) end
    Prune(holder, section)
    if not e.own and next(e.o) == nil then e.o = nil end
    if not Same(old, value) then BS.Touch(rec) end
    return true
end

-- Whether this bar changes its skin (a part the skin holds).
function BS.Changed(e)
    local sk = BS.SkinOf(e)
    if not (sk and e.o and not e.own) then return false end
    for section, vals in pairs(e.o) do
        for field in pairs(vals) do
            if BS.Held(sk, section, field) then return true end
        end
    end
    return false
end

function BS.ChangedField(e, section, field)
    local o = e and not e.own and e.o and e.o[section]
    return o ~= nil and o[field] ~= nil and BS.Held(BS.SkinOf(e), section, field)
end

-- Editing

-- Which look the options edit: an entry id, or BS.BASE. Editing one bar ends
-- any other's, so only the bar in the editor ever shows a forced look.
function BS.SetEditing(rec, key)
    for id in pairs(BS.editing) do
        if id ~= rec.id then
            BS.editing[id] = nil
            Store.Dirty("style", id)
        end
    end
    if BS.editing[rec.id] == key then return end
    BS.editing[rec.id] = key
    Store.Dirty("style", rec.id)
end

function BS.StopEditing()
    for id in pairs(BS.editing) do
        BS.editing[id] = nil
        Store.Dirty("style", id)
    end
end

-- The entry being edited, nil while the bar's own look is.
function BS.EditEntry(rec)
    local k = rec and BS.editing[rec.id]
    if k == nil or k == BS.BASE then return nil end
    return BS.Entry(rec, k)
end

-- Entries and their conditions

local function NextId(rec)
    local n = 0
    for _, e in ipairs(rec.skins or {}) do
        if type(e.id) == "number" and e.id > n then n = e.id end
    end
    return n + 1
end

function BS.AddEntry(rec, sid)
    if not (rec and rec.type == "bar") then return nil end
    rec.skins = rec.skins or {}
    if #rec.skins >= BS.MAX_ENTRIES then return nil end
    local e = { id = NextId(rec), skin = sid }
    rec.skins[#rec.skins + 1] = e
    BS.Touch(rec)
    return e
end

function BS.RemoveEntry(rec, id)
    local list = rec and rec.skins
    if not list then return end
    for i, e in ipairs(list) do
        if e.id == id then
            table.remove(list, i)
            break
        end
    end
    if #list == 0 then rec.skins = nil end
    if BS.editing[rec.id] == id then BS.editing[rec.id] = BS.BASE end
    BS.Touch(rec)
end

-- A class (nil: any). Its specs go; a talent goes with a class not yours,
-- since talents are picked on your own tree.
function BS.SetClass(rec, e, tag)
    if not e or e.cls == tag then return end
    e.cls = tag
    e.specs = nil
    if tag ~= nil and tag ~= BS.MyClass() then
        e.talentNode, e.talentEntry, e.without = nil, nil, nil
    end
    BS.Touch(rec)
end

function BS.ToggleSpec(rec, e, specID)
    if not (e and e.cls and type(specID) == "number") then return end
    e.specs = e.specs or {}
    e.specs[specID] = (not e.specs[specID]) or nil
    if next(e.specs) == nil then e.specs = nil end
    BS.Touch(rec)
end

function BS.ClearSpecs(rec, e)
    if not (e and e.specs) then return end
    e.specs = nil
    BS.Touch(rec)
end

-- A talent and its choice option (nil: any talent).
function BS.SetTalent(rec, e, node, entry)
    if not e then return end
    e.talentNode, e.talentEntry = node, node and entry or nil
    if not node then e.without = nil end
    BS.Touch(rec)
end

-- With the talent (false) or without it (true).
function BS.SetWithout(rec, e, without)
    if not (e and e.talentNode) then return end
    e.without = without and true or nil
    BS.Touch(rec)
end

-- Library

local function NewSid(lib)
    local t = time and time() or 0
    for _ = 1, 100 do
        local id = ("sk%x%04x"):format(t, math.random(0, 0xFFFF))
        if lib[id] == nil then return id end
    end
    return nil
end

-- What a bar shows now for the parts given: every field of them that its kind has.
function BS.Capture(rec, parts)
    local o = {}
    local kind, mode = Store.KindOf(rec), rec.barMode
    for _, part in ipairs(BS.PARTS) do
        if parts[part] then
            for _, sf in ipairs(BS.Fields(part)) do
                local sec = Schema.bar[sf[1]]
                local def = sec and sec.fields[sf[2]]
                if def and Schema.Applies(def, sec, kind, mode) then
                    local v = Store.Resolve(rec, sf[1], sf[2])
                    if v ~= nil then
                        o[sf[1]] = o[sf[1]] or {}
                        o[sf[1]][sf[2]] = Copy(v)
                    end
                end
            end
        end
    end
    return o
end

local function CleanName(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then name = "Skin" end
    if #name > BS.NAME_MAX then name = Store.CutText(name, BS.NAME_MAX) end
    return name
end

local function PartSet(parts)
    local out = {}
    for _, p in ipairs(BS.PARTS) do
        if parts and parts[p] then out[p] = true end
    end
    return out
end

-- Every field of the parts given at its default, so a skin made from nothing
-- shows the bars what its rows show.
function BS.Defaults(parts)
    local o = {}
    for _, part in ipairs(BS.PARTS) do
        if parts[part] then
            for _, sf in ipairs(BS.Fields(part)) do
                local def = Schema.bar[sf[1]].fields[sf[2]]
                if def and def.d ~= nil then
                    o[sf[1]] = o[sf[1]] or {}
                    o[sf[1]][sf[2]] = Copy(def.d)
                end
            end
        end
    end
    return o
end

-- A new skin of the parts given, from the look a bar shows now (none: the defaults).
function BS.Create(name, parts, rec)
    local lib = BS.Lib()
    local sid = NewSid(lib)
    if not sid then return nil end
    parts = PartSet(parts)
    lib[sid] = { name = CleanName(name), parts = parts, o = rec and BS.Capture(rec, parts) or BS.Defaults(parts) }
    return sid
end

-- "+ New skin from this look": the look being edited becomes a new skin. An
-- entry then wears it, its changes now the skin's; from the bar's own look the
-- new skin joins the bar with no conditions.
function BS.NewFromLook(rec, name, parts)
    if not (rec and rec.type == "bar") then return nil end
    local e = BS.EditEntry(rec)
    if not e and #(rec.skins or {}) >= BS.MAX_ENTRIES then return nil end
    local sid = BS.Create(name, parts, rec)
    if not sid then return nil end
    if e then
        e.skin, e.own, e.o = sid, nil, nil
        BS.Touch(rec)
    else
        e = BS.AddEntry(rec, sid)
    end
    BS.SetEditing(rec, e.id)
    return sid, e
end

-- The bars that wear a skin, by name.
function BS.WornBy(sid)
    local out = {}
    Store.EachRecord(function(_, rec)
        if rec.type == "bar" and rec.skins then
            for _, e in ipairs(rec.skins) do
                if e.skin == sid and not e.own then
                    out[#out + 1] = rec
                    break
                end
            end
        end
    end)
    table.sort(out, function(a, b)
        local x, y = tostring(a.name or ""), tostring(b.name or "")
        if x ~= y then return x < y end
        return (a.id or 0) < (b.id or 0)
    end)
    return out
end

-- Save to skin: this bar's changes become the skin's, for every bar.
function BS.SaveToSkin(rec, e)
    local sk = e and not e.own and BS.SkinOf(e)
    if not (sk and e.o) then return end
    sk.o = sk.o or {}
    for section, vals in pairs(e.o) do
        for field, v in pairs(vals) do
            if BS.Held(sk, section, field) then
                sk.o[section] = sk.o[section] or {}
                sk.o[section][field] = Copy(v)
                vals[field] = nil
            end
        end
        Prune(e.o, section)
    end
    if next(e.o) == nil then e.o = nil end
    BS.TouchAll()
end

-- Reset to skin: this bar's changes over its skin go.
function BS.ResetToSkin(rec, e)
    if not (e and e.o) then return end
    e.o = nil
    BS.Touch(rec)
end

function BS.Rename(sid, name)
    local sk = BS.Lib()[sid]
    if not sk then return end
    sk.name = CleanName(name)
    BS.TouchAll()
end

-- A name not taken yet: "Name copy", "Name copy 2", ...
function BS.FreeName(base)
    local taken = {}
    for _, sk in pairs(BS.Lib()) do taken[sk.name] = true end
    if not taken[base] then return base end
    for i = 2, 99 do
        local n = ("%s %d"):format(base, i)
        if not taken[n] then return n end
    end
    return base
end

function BS.Duplicate(sid)
    local lib = BS.Lib()
    local sk = lib[sid]
    if not sk then return nil end
    local nid = NewSid(lib)
    if not nid then return nil end
    lib[nid] = { name = CleanName(BS.FreeName(sk.name .. " copy")), parts = Copy(sk.parts), o = Copy(sk.o or {}) }
    return nid
end

-- A part on or off. A part switched on fills what the skin lacks from the
-- defaults, so its rows show what the bars then wear; one switched off keeps
-- its values for the next time.
function BS.SetPart(sid, part, on)
    local sk = BS.Lib()[sid]
    if not (sk and BS.PART_WORDS[part]) then return end
    sk.parts = sk.parts or {}
    if (sk.parts[part] == true) == (on == true) then return end
    sk.parts[part] = on and true or nil
    if on then
        sk.o = sk.o or {}
        for _, sf in ipairs(BS.Fields(part)) do
            local s = sk.o[sf[1]] or {}
            if s[sf[2]] == nil then
                local def = Schema.bar[sf[1]].fields[sf[2]]
                if def and def.d ~= nil then s[sf[2]] = Copy(def.d) end
            end
            if next(s) ~= nil then sk.o[sf[1]] = s end
        end
    end
    BS.TouchAll()
end

-- A skin's own value (the Skins page): its stored one, else the default.
function BS.SkinValue(sid, section, field)
    local sk = BS.Lib()[sid]
    local o = sk and sk.o and sk.o[section]
    if o and o[field] ~= nil then return o[field] end
    local sec = Schema.bar[section]
    local def = sec and sec.fields[field]
    return def and def.d
end

function BS.SetSkinValue(sid, section, field, value)
    local sk = BS.Lib()[sid]
    if not (sk and BS.PartOf(section, field)) then return end
    sk.o = sk.o or {}
    sk.o[section] = sk.o[section] or {}
    if Same(sk.o[section][field], value) then return end
    sk.o[section][field] = Copy(value)
    BS.TouchAll()
end

-- The skin's held values under one entry's changes.
local function Merged(sk, e)
    local vals = {}
    local function Put(src)
        for section, fields in pairs(src or {}) do
            for field, v in pairs(fields) do
                if BS.Held(sk, section, field) then
                    vals[section] = vals[section] or {}
                    vals[section][field] = Copy(v)
                end
            end
        end
    end
    Put(sk.o)
    Put(e.o)
    return vals
end

local function NoConditions(e)
    return e.cls == nil and e.specs == nil and e.talentNode == nil
end

-- Delete: every bar keeps the look it wore. A bar whose one skin was always on
-- takes it as its own look; any other entry keeps a copy of its own.
function BS.Delete(sid)
    local lib = BS.Lib()
    local sk = lib[sid]
    if not sk then return end
    for _, rec in ipairs(BS.WornBy(sid)) do
        local list = rec.skins
        for i = #list, 1, -1 do
            local e = list[i]
            if e.skin == sid and not e.own then
                local vals = Merged(sk, e)
                if #list == 1 and NoConditions(e) then
                    table.remove(list, i)
                    rec.skins = nil
                    for section, fields in pairs(vals) do
                        for field, v in pairs(fields) do
                            rec.o[section] = rec.o[section] or {}
                            rec.o[section][field] = nil
                            if not Same(v, Store.Resolve(rec, section, field)) then rec.o[section][field] = v end
                            Prune(rec.o, section)
                        end
                    end
                    if BS.editing[rec.id] ~= nil then BS.editing[rec.id] = BS.BASE end
                else
                    e.own = { name = sk.name, parts = Copy(sk.parts), o = vals }
                    e.skin, e.o = nil, nil
                end
            end
        end
        if rec.skins and #rec.skins == 0 then rec.skins = nil end
    end
    lib[sid] = nil
    BS.TouchAll()
end

-- The library by name.
function BS.List()
    local out = {}
    for sid, sk in pairs(BS.Lib()) do out[#out + 1] = { sid = sid, skin = sk } end
    table.sort(out, function(a, b)
        local x, y = a.skin.name:lower(), b.skin.name:lower()
        if x ~= y then return x < y end
        return a.sid < b.sid
    end)
    return out
end

-- Cleaning (Store.Normalize, imports)

local function PosInt(v)
    return (type(v) == "number" and v > 0 and v == math.floor(v)) and v or nil
end

-- a value from a share string: colours as numbers 0-1, switches as booleans,
-- a pick from its list; the rest as the store cleans overrides
local function CleanOne(def, v)
    if def.t == "color" then
        if type(v) ~= "table" then return nil end
        local c = {}
        for i = 1, 4 do
            local x = v[i]
            if type(x) == "number" and x == x then
                c[i] = math.max(0, math.min(1, x))
            elseif i <= 3 then
                return nil
            end
        end
        return c
    elseif def.t == "bool" then
        if type(v) == "boolean" then return v end
        return nil
    elseif def.t == "enum" and type(def.values) == "table" then
        for _, x in ipairs(def.values) do
            if x == v then return v end
        end
        return nil
    end
    return Store.CleanValue(def, v)
end

local function CleanVals(o)
    if type(o) ~= "table" then return nil end
    local out
    for section, vals in pairs(o) do
        local sec = type(section) == "string" and Schema.bar[section]
        if sec and type(vals) == "table" then
            for field, v in pairs(vals) do
                local def = BS.PartOf(section, field) and sec.fields[field]
                local c
                if def then c = CleanOne(def, v) end
                if c ~= nil then
                    out = out or {}
                    out[section] = out[section] or {}
                    out[section][field] = c
                end
            end
        end
    end
    return out
end

local function CleanSkin(s)
    if type(s) ~= "table" then return nil end
    local parts = {}
    for _, p in ipairs(BS.PARTS) do
        if type(s.parts) == "table" and s.parts[p] == true then parts[p] = true end
    end
    return { name = CleanName(s.name), parts = parts, o = CleanVals(s.o) or {} }
end

local function CleanSid(sid)
    return (type(sid) == "string" and sid ~= "" and #sid <= 40 and not sid:find("[^%w_]")) and sid or nil
end

function BS.CleanLib(lib)
    if type(lib) ~= "table" then return end
    for sid, s in pairs(lib) do
        local c = CleanSid(sid) and CleanSkin(s)
        lib[sid] = c or nil
    end
end

function BS.CleanRec(rec)
    local list = rec.skins
    if list == nil then return end
    if type(list) ~= "table" or rec.type ~= "bar" then
        rec.skins = nil
        return
    end
    local out, ids = {}, {}
    for _, e in ipairs(list) do
        if #out >= BS.MAX_ENTRIES then break end
        if type(e) == "table" then
            local own = e.own ~= nil and CleanSkin(e.own) or nil
            local sid = not own and CleanSid(e.skin) or nil
            if own or sid then
                local id = PosInt(e.id)
                if not id or ids[id] then
                    id = 1
                    while ids[id] do id = id + 1 end
                end
                ids[id] = true
                local c = { id = id, skin = sid, own = own }
                c.cls = (type(e.cls) == "string" and #e.cls <= 20 and e.cls:match("^%u+$")) and e.cls or nil
                if c.cls and type(e.specs) == "table" then
                    for k, v in pairs(e.specs) do
                        if PosInt(k) and v == true then
                            c.specs = c.specs or {}
                            c.specs[k] = true
                        end
                    end
                end
                c.talentNode = PosInt(e.talentNode)
                c.talentEntry = c.talentNode and PosInt(e.talentEntry) or nil
                c.without = (c.talentNode and e.without == true) or nil
                c.o = not own and CleanVals(e.o) or nil
                out[#out + 1] = c
            end
        end
    end
    rec.skins = (#out > 0) and out or nil
end

-- Share strings: the skins the bars in it wear travel with them; an import
-- adds the ones this account lacks and keeps its own copy of the rest.
function BS.ForExport(recs)
    local lib, out = BS.Lib(), nil
    for _, rec in ipairs(recs or {}) do
        for _, e in ipairs(type(rec.skins) == "table" and rec.skins or {}) do
            local sk = type(e) == "table" and e.skin and lib[e.skin]
            if sk then
                out = out or {}
                out[e.skin] = Copy(sk)
            end
        end
    end
    return out
end

function BS.TakeIn(skins)
    if type(skins) ~= "table" then return end
    local lib = BS.Lib()
    for sid, s in pairs(skins) do
        sid = CleanSid(sid)
        if sid and lib[sid] == nil then lib[sid] = CleanSkin(s) end
    end
end

-- One skin's own share string (the Skins page's Export).
function BS.ExportString(sid)
    local sk = BS.Lib()[sid]
    if not sk then return nil, "no such skin" end
    return Store.ExportSkin(sk)
end

-- A skin string pasted on the Skins page: always a new skin, under a free name.
function BS.ImportString(text)
    local s, err = Store.DecodeSkin(text)
    if not s then return nil, err end
    local c = CleanSkin(s)
    local lib = BS.Lib()
    local sid = NewSid(lib)
    if not (c and sid) then return nil, "corrupt string" end
    c.name = CleanName(BS.FreeName(c.name))
    lib[sid] = c
    return sid
end

-- a spec or talent change, or a login, can switch the skin in play; the
-- engine's coalesced rebuild repaints after this
local function Forget() wipe(BS.cache) end
do
    local list = { "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD" }
    local T = NS.TalentCatalog
    for _, e in ipairs(T and T.ValidEvents and T.ValidEvents() or {}) do list[#list + 1] = e end
    for _, e in ipairs(list) do Events.On(e, "adbarskins", Forget) end
end
