-- AD_CDMMirror: reads the player's Cooldown Manager and says what Arc Auras builds from it.
-- Owns the read, Blizzard's list merge redone over plain tables, and the aura rule; no frames, no writes.
-- Only C calls touch the game here: a secret or missing answer marks the read incomplete, never empty.
local ADDON, NS = ...

local M = {}
NS.CDMMirror = M

-- Blizzard's own category list and order (the pseudo -1 / -2 are never asked for: they throw)
M.CATS = {
    "Essential", "Utility", "TrackedBuff", "TrackedBar",
    "EquipSlotEssential", "EquipSlotTracked", "SpecAgnosticEssential", "SpecAgnosticTracked",
}
M.NUM = {
    Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, GroupBuff = 4,
    SpecAgnosticEssential = 5, SpecAgnosticTracked = 6, EquipSlotEssential = 7, EquipSlotTracked = 8,
}
M.HIDDEN_ACTIVE, M.HIDDEN_PASSIVE = -1, -2
M.FLAG = { HideAura = 1, HideByDefault = 2, SelectHighestLevelLinkedSpell = 4 }

-- the bag-item categories retail's Cooldown Manager knows
M.ITEM_CATEGORY = { [4] = "combat potion", [30] = "health potion", [1711] = "healthstone", [2566] = "demonic healthstone" }

function M.Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

function M.Cat(name)
    local E = Enum and Enum.CooldownViewerCategory
    local v = E and E[name]
    if type(v) == "number" and M.Plain(v) then return v end
    return M.NUM[name]
end

function M.Flag(name)
    local E = Enum and Enum.CooldownSetSpellFlags
    local v = E and E[name]
    if type(v) == "number" and M.Plain(v) and v > 0 then return v end
    return M.FLAG[name]
end

function M.HasFlag(flags, bit)
    if type(flags) ~= "number" or type(bit) ~= "number" or bit <= 0 then return false end
    return flags % (bit * 2) >= bit
end

-- where Blizzard parks a default-hidden entry: item containers keep their own
function M.HiddenOf(cat)
    if cat == M.Cat("Essential") or cat == M.Cat("Utility") then return M.HIDDEN_ACTIVE end
    if cat == M.Cat("TrackedBuff") or cat == M.Cat("TrackedBar") then return M.HIDDEN_PASSIVE end
    return cat
end

function M.IsTracked(cat)
    return cat == M.Cat("TrackedBuff") or cat == M.Cat("TrackedBar")
        or cat == M.Cat("EquipSlotTracked") or cat == M.Cat("SpecAgnosticTracked")
end

-- the saved layouts are keyed class * 10 + spec, like Blizzard's; no spec = no layout
function M.Tag()
    local classID = UnitClass and select(3, UnitClass("player"))
    local SI = C_SpecializationInfo
    local spec = SI and SI.GetSpecialization and SI.GetSpecialization()
    if not (M.Plain(classID) and M.Plain(spec)) then return nil end
    if type(classID) ~= "number" or type(spec) ~= "number" then return nil end
    return classID * 10 + spec
end

-- "1|" .. Base64 of Deflate of CBOR, decoded the way Blizzard's serializer does
function M.Decode(raw)
    local U = C_EncodingUtil
    if type(raw) ~= "string" or not M.Plain(raw) then return nil end
    if not (U and U.DecodeBase64 and U.DecompressString and U.DeserializeCBOR) then return nil end
    local bar = raw:find("|", 1, true)
    if not bar or tonumber(raw:sub(1, bar - 1)) ~= 1 then return nil end
    local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
    if method == nil then return nil end
    local bin = U.DecodeBase64(raw:sub(bar + 1))
    if type(bin) ~= "string" then return nil end
    local inflated = U.DecompressString(bin, method)
    if type(inflated) ~= "string" then return nil end
    local t = U.DeserializeCBOR(inflated)
    if type(t) ~= "table" or type(t[1]) ~= "number" then return nil end
    return t
end

-- [2][tag] names the active layout, [3][tag][that] holds it; nil = the default layout
function M.ActiveLayout(t, tag)
    if type(t) ~= "table" or tag == nil then return nil end
    local active, lays = t[2], t[3]
    local key = type(active) == "table" and active[tag]
    local mine = type(lays) == "table" and lays[tag]
    if key == nil or type(mine) ~= "table" then return nil end
    local lay = mine[key]
    return type(lay) == "table" and lay or nil
end

M.INFO_KEYS = {
    "cooldownID", "spellID", "spellCategoryID", "overrideSpellID", "overrideTooltipSpellID",
    "equipSlot", "buffSlot", "selfAura", "hasAura", "charges", "isKnown", "isInvisible", "flags", "category",
}

-- a plain copy of the fields the mirror reads; nil when any of them is secret
function M.CopyInfo(info)
    if type(info) ~= "table" then return nil end
    local c = {}
    for _, k in ipairs(M.INFO_KEYS) do
        local v = info[k]
        if not M.Plain(v) then return nil end
        c[k] = v
    end
    local linked = {}
    local src = info.linkedSpellIDs
    if not M.Plain(src) then return nil end
    if type(src) == "table" then
        for i = 1, #src do
            local id = src[i]
            if not M.Plain(id) then return nil end
            if type(id) == "number" then linked[#linked + 1] = id end
        end
    end
    c.linkedSpellIDs = linked
    return c
end

-- one full read: the category sets, each entry's info, the saved arrangement
function M.Read()
    local CV = C_CooldownViewer
    local snap = { sets = {}, infos = {}, complete = false }
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo and CV.GetLayoutData) then
        snap.why = "no Cooldown Manager API"
        return snap
    end
    local avail = CV.IsCooldownViewerAvailable and CV.IsCooldownViewerAvailable()
    if avail ~= true then
        snap.why = "Cooldown Manager unavailable"
        return snap
    end
    for _, name in ipairs(M.CATS) do
        local cat = M.Cat(name)
        local ids = CV.GetCooldownViewerCategorySet(cat, true)
        if type(ids) ~= "table" or not M.Plain(ids) then
            snap.why = "no set for " .. name
            return snap
        end
        local list = {}
        for i = 1, #ids do
            local id = ids[i]
            if not M.Plain(id) or type(id) ~= "number" then
                snap.why = "unreadable entry in " .. name
                return snap
            end
            local raw = CV.GetCooldownViewerCooldownInfo(id)
            if raw ~= nil then
                local info = M.CopyInfo(raw)
                if not info then
                    snap.why = "unreadable info " .. id
                    return snap
                end
                snap.infos[id] = info
                list[#list + 1] = id
            end
        end
        snap.sets[cat] = list
    end
    local raw = CV.GetLayoutData()
    if type(raw) ~= "string" or not M.Plain(raw) then
        snap.why = "no saved layout answer"
        return snap
    end
    snap.raw, snap.tag = raw, M.Tag()
    if raw ~= "" then
        local t = M.Decode(raw)
        if not t then
            snap.why = "saved layout did not decode"
            return snap
        end
        snap.saved = t
        snap.layout = M.ActiveLayout(t, snap.tag)
    end
    snap.complete = true
    return snap
end

-- Blizzard's display list: defaults, then the active layout's order and moves
function M.Merge(snap)
    local infos, sets = snap.infos or {}, snap.sets or {}
    local default, catOf = {}, {}
    local hideByDefault = M.Flag("HideByDefault")
    for _, name in ipairs(M.CATS) do
        local cat = M.Cat(name)
        local list = sets[cat]
        if type(list) == "table" then
            for i = 1, #list do
                local id = list[i]
                local info = infos[id]
                if info and catOf[id] == nil then
                    local c = type(info.category) == "number" and info.category or cat
                    if M.HasFlag(info.flags, hideByDefault) then c = M.HiddenOf(c) end
                    catOf[id] = c
                    default[#default + 1] = id
                end
            end
        end
    end
    local order, seen = {}, {}
    local lay = snap.layout
    local saved = type(lay) == "table" and lay[1]
    if type(saved) == "table" then
        for i = 1, #saved do
            local id = saved[i]
            if catOf[id] ~= nil and not seen[id] then
                order[#order + 1] = id
                seen[id] = true
            end
        end
    end
    for i = 1, #default do
        local id = default[i]
        if not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end
    local moves = type(lay) == "table" and lay[2]
    if type(moves) == "table" then
        for cat, ids in pairs(moves) do
            local c = tonumber(cat)
            if c and type(ids) == "table" then
                for i = 1, #ids do
                    if catOf[ids[i]] ~= nil then catOf[ids[i]] = c end
                end
            end
        end
    end
    return { order = order, catOf = catOf }
end

-- the spell name every rank of a spell shares
M.names = {}
function M.NameOf(id)
    if type(id) ~= "number" then return nil end
    local n = M.names[id]
    if n then return n end
    local f = C_Spell and C_Spell.GetSpellName
    n = f and f(id) -- raw-id: a Cooldown Manager entry
    if type(n) ~= "string" or not M.Plain(n) or n == "" then return nil end
    M.names[id] = n
    return n
end

-- one key per spell across its ranks: the lowest ID of the linked ranks sharing its name
function M.FamilyKey(info)
    if type(info) ~= "table" then return nil end
    if type(info.equipSlot) == "number" then return "slot:" .. info.equipSlot end
    if type(info.spellCategoryID) == "number" then return "cat:" .. info.spellCategoryID end
    local sid = info.spellID
    if type(sid) ~= "number" then return info.cooldownID and ("cd:" .. info.cooldownID) or nil end
    local name, low = M.NameOf(sid), sid
    for _, id in ipairs(info.linkedSpellIDs or {}) do
        if id < low and name ~= nil and M.NameOf(id) == name then low = id end
    end
    return "spell:" .. low
end

-- what a Cooldown Manager bar shows, in order: known entries of that category, one per spell
function M.Shown(snap, merged, cat)
    local out, fam = {}, {}
    local hideInvisible = CDM_HIDE_INVISIBLE_ITEMS == true
    for i = 1, #merged.order do
        local id = merged.order[i]
        local info = snap.infos[id]
        if info and merged.catOf[id] == cat and info.isKnown == true
            and not (hideInvisible and info.isInvisible == true) then
            local key = M.FamilyKey(info) or id
            if not fam[key] then
                fam[key] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

function M.Harmful(id)
    local f = C_Spell and C_Spell.IsSpellHarmful
    if not (f and type(id) == "number") then return false end
    local v = f(id) -- raw-id: a Cooldown Manager entry
    return M.Plain(v) and v == true
end

-- The aura an icon shows, as Blizzard decides it: your own aura on you first, else on your
-- target, matching linked, tooltip, override and spell IDs, never with HideAura. The
-- selfAura / hasAura hints (unread by Blizzard's Lua) say which cooldowns ever have one.
-- Returns NS.DriverAura's shape: the entry's spell first, then the rest, as a set.
function M.AuraFor(info, tracked)
    if type(info) ~= "table" or M.HasFlag(info.flags, M.Flag("HideAura")) then return nil end
    local onYou, onTarget = info.selfAura == true, info.hasAura == true
    if not tracked and not onYou and not onTarget then return nil end
    local ids, seen = {}, {}
    local lists = { { info.spellID }, info.linkedSpellIDs or {}, { info.overrideTooltipSpellID }, { info.overrideSpellID } }
    for _, l in ipairs(lists) do
        for i = 1, #l do
            local id = l[i]
            if type(id) == "number" and id > 0 and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    if #ids == 0 then return nil end
    local harmful = M.Harmful(info.spellID)
    local d = { caster = "mine", spellID = ids[1], spellIDs = (#ids > 1) and ids or nil }
    if onYou and not onTarget then
        d.auraType, d.unit = "buff", "player"
    elseif onTarget and not onYou and harmful then
        d.auraType, d.unit = "debuff", "target"
    else
        d.auraType, d.unit, d.unit2 = harmful and "debuff" or "buff", "player", "target"
    end
    return d
end

-- what Arc Auras builds for one entry in its merged category
function M.PieceFor(info, cat)
    if type(info) ~= "table" then return nil end
    local tracked = M.IsTracked(cat)
    if tracked then
        local kind = cat == M.Cat("TrackedBar") and "aurabar" or "aura"
        local aura = M.AuraFor(info, true)
        if not aura then return nil end
        return { kind = kind, aura = aura }
    end
    if type(info.equipSlot) == "number" then
        return { kind = "trinket", slot = info.equipSlot }
    end
    if type(info.spellCategoryID) == "number" then
        return { kind = "item", spellCategoryID = info.spellCategoryID, what = M.ITEM_CATEGORY[info.spellCategoryID] }
    end
    if type(info.spellID) ~= "number" then return nil end
    return { kind = "spell", spellID = info.spellID, aura = M.AuraFor(info, false) }
end

-- the group buffs Blizzard offers, minus the ones the active layout hides
function M.GroupBuffs(snap)
    local CV = C_CooldownViewer
    local list = CV and CV.GetGroupBuffItems and CV.GetGroupBuffItems()
    if type(list) ~= "table" or not M.Plain(list) then return nil end
    local hidden = {}
    local lay = snap and snap.layout
    local h = type(lay) == "table" and lay[4]
    if type(h) == "table" then
        for k, v in pairs(h) do
            if type(v) == "number" then hidden[v] = true end
            if type(k) == "number" and v == true then hidden[k] = true end
        end
    end
    local out = {}
    for i = 1, #list do
        local b = list[i]
        if type(b) ~= "table" then return nil end
        local sid, known = b.spellID, b.isKnown
        if not (M.Plain(sid) and M.Plain(known)) then return nil end
        if type(sid) == "number" and known == true and not hidden[sid] then
            out[#out + 1] = sid
        end
    end
    return out
end

-- The Cooldown Manager's bars: frame, base icon size, the group it becomes,
-- and a fallback height (on a 1080 screen) when the bar cannot be measured.
M.VIEWERS = {
    { cat = "Essential", frame = "EssentialCooldownViewer", base = 50, name = "Essential", groupKind = "cooldown", y = -275 },
    { cat = "Utility", frame = "UtilityCooldownViewer", base = 30, name = "Utility", groupKind = "cooldown", y = -320 },
    { cat = "TrackedBuff", frame = "BuffIconCooldownViewer", base = 40, name = "Tracked Buffs", groupKind = "aura", y = -365 },
    { cat = "TrackedBar", frame = "BuffBarCooldownViewer", base = 30, name = "Tracked Bars", bars = true, y = -410 },
}
-- retail's own stand-in items for its healthstone categories; a bag item with none is skipped
M.ITEM_FALLBACK = { [1711] = 5512, [2566] = 224464 }

function M.Available()
    local CV = C_CooldownViewer
    return CV ~= nil and CV.GetCooldownViewerCategorySet ~= nil and CV.GetLayoutData ~= nil
end

function M.Num(v)
    if type(v) == "number" and M.Plain(v) then return v end
    return nil
end

function M.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- a frame's centre and size in UIParent units, the units our groups use
function M.Rect(f)
    if type(f) ~= "table" or not (f.GetCenter and f.GetEffectiveScale) then return nil end
    local x, y = f:GetCenter()
    local w, h = f:GetWidth(), f:GetHeight()
    local es, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    x, y, w, h, es, us = M.Num(x), M.Num(y), M.Num(w), M.Num(h), M.Num(es), M.Num(us)
    if not (x and y and w and h and es and us) or us <= 0 then return nil end
    local k = es / us
    return x * k, y * k, w * k, h * k
end

-- the bar's icons now showing these cooldownIDs, in the bar's order
function M.ShownIcons(f, want)
    local out = {}
    local function Walk(fr, depth)
        if depth > 2 or not fr.GetChildren then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            if type(c) == "table" then
                local id = M.Num(c.cooldownID)
                if id then
                    local shown = c.IsShown and c:IsShown()
                    if want[id] and M.Plain(shown) and shown == true then out[#out + 1] = c end
                else
                    Walk(c, depth + 1)
                end
            end
        end
    end
    Walk(f, 1)
    table.sort(out, function(a, b) return (M.Num(a.layoutIndex) or 0) < (M.Num(b.layoutIndex) or 0) end)
    return out
end

-- A bar's Edit Mode look in our group's terms. Blizzard sizes each icon base x
-- iconScale and spaces them iconPadding - 4 (bars - 2), its art 2 in from each
-- edge; iconLimit per row (per column when vertical); rows run by iconDirection
-- and stack down, columns run up when it is Right. Two icons on show give the
-- real spacing, and the icons on show give the place.
function M.Geometry(v, ids)
    local f = _G[v.frame]
    if type(f) ~= "table" then f = nil end
    local scale = f and M.Num(f.iconScale) or 1
    if scale <= 0 then scale = 1 end
    local pad = f and M.Num(f.iconPadding) or 6
    local limit = f and M.Num(f.iconLimit) or 0
    local orient = f and M.Num(f.orientationSetting)
    local horizontal = orient == nil or orient == 0
    local right = not (f and M.Num(f.iconDirection) == 0)
    local n = math.max(1, #ids)
    if limit < 1 then limit = n end
    local per = math.max(1, math.min(limit, n))
    local lines = math.ceil(n / per)
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local icons = f and M.ShownIcons(f, want) or {}
    local g = { combatOnly = f ~= nil and M.Num(f.visibleSetting) == 1,
        hideInactive = f ~= nil and f.hideWhenInactive == true,
        barContent = f and M.Num(f.barContent) or 0 }
    if v.bars then
        local bw = f and M.Num(f.baseBarWidth) or 220
        local bs = f and M.Num(f.barWidthScale) or 1
        g.width = M.Clamp(math.floor(bw * bs * scale + 0.5), 20, 1000)
        g.height = M.Clamp(math.floor(v.base * scale + 0.5), 4, 200)
        g.pitch = v.base * scale + pad - 2
        g.up = (not horizontal) and right
    else
        g.size = M.Clamp(math.floor((v.base - 4) * scale + 0.5), 8, 128)
        local pitch = v.base * scale + pad - 4
        if #icons >= 2 then
            local x1, y1 = M.Rect(icons[1])
            local x2, y2 = M.Rect(icons[2])
            if x1 and x2 then
                local along = horizontal and math.abs(x2 - x1) or math.abs(y2 - y1)
                local across = horizontal and math.abs(y2 - y1) or math.abs(x2 - x1)
                if across < 1 and along > 0 then pitch = along end
            end
        end
        g.spacing = M.Clamp(math.floor(pitch - g.size + 0.5), -20, 50)
        if horizontal then
            g.cols, g.rows = per, lines
            g.growthH, g.growthV = right and "RIGHT" or "LEFT", "DOWN"
        else
            g.cols, g.rows = lines, per
            g.growthH, g.growthV = "RIGHT", right and "UP" or "DOWN"
        end
        g.cols, g.rows = M.Clamp(g.cols, 1, 20), M.Clamp(g.rows, 1, 20)
        local point = f and f.GetPoint and f:GetPoint(1)
        if type(point) ~= "string" or not M.Plain(point) then point = "CENTER" end
        if horizontal then
            g.alignment = (point:find("LEFT") and "left") or (point:find("RIGHT") and "right") or "center"
        else
            g.alignment = (point:find("TOP") and "top") or (point:find("BOTTOM") and "bottom") or "center"
        end
    end
    local l, r, b, t
    local from = v.bars and { icons[1] } or icons
    for _, c in ipairs(from) do
        local x, y, w, h = M.Rect(c)
        if x then
            l, r = math.min(l or x - w / 2, x - w / 2), math.max(r or x + w / 2, x + w / 2)
            b, t = math.min(b or y - h / 2, y - h / 2), math.max(t or y + h / 2, y + h / 2)
        end
    end
    local cx, cy
    if l then
        cx, cy = (l + r) / 2, (b + t) / 2
    elseif f then
        cx, cy = M.Rect(f)
    end
    local ux, uy = UIParent:GetCenter()
    ux, uy = M.Num(ux), M.Num(uy)
    if cx and ux and uy then
        g.x, g.y = math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
    end
    return g
end

-- What the layout would hold: per bar, what each entry it shows now becomes.
function M.Plan(snap, merged)
    local plan = {}
    for _, v in ipairs(M.VIEWERS) do
        local pieces, ids = {}, {}
        for _, id in ipairs(M.Shown(snap, merged, M.Cat(v.cat))) do
            local p = M.PieceFor(snap.infos[id], merged.catOf[id])
            if p and not (p.kind == "item" and not M.ITEM_FALLBACK[p.spellCategoryID]) then
                pieces[#pieces + 1] = p
                ids[#ids + 1] = id
            end
        end
        if #pieces > 0 then plan[#plan + 1] = { viewer = v, pieces = pieces, ids = ids } end
    end
    return plan
end

function M.Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = (type(v) == "table") and M.Copy(v) or v end
    return c
end

function M.NewIconFor(p, groupId)
    local S = NS.Store
    if p.kind == "spell" then
        local d = { spellID = p.spellID }
        if p.aura then
            d.overlay = M.Copy(p.aura)
            d.overlay.on = true
        end
        return S.NewIcon("spell", d, groupId, nil, M.NameOf(p.spellID) or ("Spell " .. p.spellID))
    end
    if p.kind == "aura" then
        local d = M.Copy(p.aura)
        return S.NewIcon("aura", d, groupId, nil, M.NameOf(d.spellID) or ("Aura " .. d.spellID))
    end
    if p.kind == "trinket" then
        return S.NewIcon("trinket", { slotID = p.slot }, groupId, nil, p.slot == 14 and "Trinket 2" or "Trinket 1")
    end
    if p.kind == "item" then
        local iid = M.ITEM_FALLBACK[p.spellCategoryID]
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(iid)
        if type(name) ~= "string" or not M.Plain(name) then name = "Item " .. iid end
        return S.NewIcon("item", { itemID = iid }, groupId, nil, name)
    end
    return nil
end

function M.Arrange(g, geo, kind)
    local S = NS.Store
    S.SetOverride(g, "arrangement", "iconWidth", geo.size)
    S.SetOverride(g, "arrangement", "iconHeight", geo.size)
    S.SetOverride(g, "arrangement", "spacing", geo.spacing)
    S.SetOverride(g, "arrangement", "cols", geo.cols)
    if kind == "cooldown" then S.SetOverride(g, "arrangement", "rows", geo.rows) end
    S.SetOverride(g, "arrangement", "growthH", geo.growthH)
    S.SetOverride(g, "arrangement", "growthV", geo.growthV)
    S.SetOverride(g, "arrangement", "alignment", geo.alignment)
end

-- Blizzard's "In Combat" bar: full opacity in combat, hidden out of it
function M.CombatOnly(rec)
    local C = NS.Conditions
    local set = rec.c and rec.c.showWhen
    if C and C.Toggle and not (type(set) == "table" and set.inCombat) then C.Toggle(rec, "showWhen", "inCombat") end
end

-- Tracked Bars: aura bars stacked like the bar's own, each on its first unit.
function M.BuildBars(lay, part, geo, x, y)
    local S = NS.Store
    if not S.NewBar then return 0 end
    local made = 0
    for i, p in ipairs(part.pieces) do
        local a = p.aura
        local d = { spellID = a.spellID, spellIDs = a.spellIDs, auraType = a.auraType, unit = a.unit, caster = a.caster }
        local rec = S.NewBar(lay.id, "aura", d, M.NameOf(a.spellID) or ("Aura " .. a.spellID), "duration")
        if rec then
            made = made + 1
            local step = (i - 1) * geo.pitch
            rec.pos = { x = x, y = math.floor(y + (geo.up and step or -step) + 0.5) }
            S.SetOverride(rec, "size", "width", geo.width)
            S.SetOverride(rec, "size", "height", geo.height)
            if geo.barContent == 1 then S.SetOverride(rec, "text", "nameShow", false) end
            if geo.barContent == 2 then S.SetOverride(rec, "icon", "iconShow", false) end
            if geo.combatOnly then M.CombatOnly(rec) end
        end
    end
    return made
end

-- "From my Cooldown Manager": a new layout with a group per bar holding the
-- spells it shows now, in its order, placed and sized like it. Returns the
-- layout and the count built, or nil and why ("read" with its reason, "empty").
function M.Build()
    local S = NS.Store
    if not (S and S.NewLayout and S.NewGroup and S.NewIcon and S.SetOverride) then return nil, "store" end
    local snap = M.Read()
    if not snap.complete then return nil, "read", snap.why end
    local plan = M.Plan(snap, M.Merge(snap))
    if #plan == 0 then return nil, "empty" end
    local lay = S.NewLayout("Cooldown Manager")
    lay.pos = { x = 0, y = 0 }
    local h = M.Num(UIParent:GetHeight()) or 768
    if h <= 0 then h = 768 end
    local made = 0
    for _, part in ipairs(plan) do
        local v = part.viewer
        local geo = M.Geometry(v, part.ids)
        local x = geo.x or 0
        local y = geo.y or math.floor(v.y * h / 1080 + 0.5)
        if v.bars then
            made = made + M.BuildBars(lay, part, geo, x, y)
        else
            local g = S.NewGroup(lay.id, v.name, v.groupKind)
            if g then
                g.pos = { x = x, y = y }
                M.Arrange(g, geo, v.groupKind)
                if geo.combatOnly then M.CombatOnly(g) end
                for _, p in ipairs(part.pieces) do
                    local rec = M.NewIconFor(p, g.id)
                    if rec then
                        made = made + 1
                        if p.kind == "aura" and geo.hideInactive then
                            S.SetOverride(rec, "auraMissing", "showWhileMissing", false)
                        end
                    end
                end
            end
        end
    end
    return lay, made
end
