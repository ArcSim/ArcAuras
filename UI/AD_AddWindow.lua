-- AD_AddWindow: the Add window's start page, side list, ready-made tiles and pinned footer.
-- AD_Options builds the window and the form rows and calls in through Options.AddWin; the form's values stay in its addState.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, COL = NS.AT, NS.AT.COL
local Tr = AT.Tr

local AW = {}
Options.AddWin = AW

AW.W, AW.H = 968, 634
AW.REM_W, AW.REM_H = 500, 560
AW.LIST_W, AW.FOOT_H, AW.TOP = 202, 44, 31
AW.PAD, AW.GAP = 10, 9
AW.HEAD_H, AW.BOX_PAD, AW.ITEM_GAP, AW.ITEM_H = 26, 4, 5, 40
AW.PREV_W, AW.PREV_H, AW.ZONE_W = 40, 31, 36
-- The kind buttons' neutral grey: the art and colored bars carry the color.
AW.GRAPHITE = {
    top = { 0.173, 0.188, 0.212 }, bottom = { 0.122, 0.133, 0.153 }, hot = { 0.227, 0.247, 0.278 },
    edge = { 0.294, 0.314, 0.349 }, zone = { 0.075, 0.082, 0.094 }, rule = { 0.231, 0.247, 0.278 },
    name = { 0.957, 0.961, 0.969 }, hint = { 0.718, 0.733, 0.765 },
}
AW.TILE_H, AW.TILE_GAP, AW.TILE_COLS = 43, 5, 5
AW.TILE_W = 140

AW.SECTIONS = { "Icon", "Bar", "Group", "Text", "Extra" }
function AW.SectionTitle(sec)
    if sec == "Icon" then return Tr("Icons") end
    if sec == "Bar" then return Tr("Bars") end
    if sec == "Group" then return Tr("Groups") end
    if sec == "Text" then return Tr("Text and Textures") end
    return Tr("Wheels and Sounds")
end
function AW.SectionSub(sec)
    if sec == "Icon" then return Tr("One square that tracks one thing") end
    if sec == "Bar" then return Tr("A strip that fills or counts down") end
    if sec == "Group" then return Tr("Icons placed and packed together") end
    if sec == "Text" then return Tr("Words and pictures on screen") end
    return Tr("On a key, or by ear")
end

local CUSTOM_DEF = "Its rules (the Triggers tab) start its timer and count its stacks from events you pick."

-- Every kind of a section on this client, in the order it shows.
function AW.Kinds(sec)
    local out = {}
    local function K(id, name, short, hint, def)
        out[#out + 1] = { id = id, name = name, short = short or name, hint = hint, def = def }
    end
    local SO = Options.Special
    local procs = SO and SO.On and SO.On()
    if sec == "Icon" then
        K("spell", Tr("Spell Cooldown"), nil, Tr("When a spell is ready"), Tr("A spell's cooldown as an icon."))
        K("aura", Tr("Aura (buff / debuff)"), Tr("Aura"), Tr("A buff or debuff you watch"), Tr("A buff or debuff as an icon; several IDs can light one icon."))
        K("groupbuff", Tr("Group Buff (party / raid)"), Tr("Group Buff"), Tr("Who in the group has it"), Tr("How many in your party or raid have a buff."))
        K("item", Tr("Item"), nil, Tr("Potions, food, gear"), Tr("An item's cooldown and count, by item ID."))
        K("trinket", Tr("Trinket"), nil, Tr("Whatever is in the slot"), Tr("The cooldown of the trinket you wear in a slot."))
        K("totem", Tr("Totem / Guardian Duration"), Tr("Totem / Guardian"), Tr("Time left on what you drop"), Tr("A totem or guardian in its slot, or one of them by the spell that puts it down."))
        if NS.IsForever == true then K("ammo", Tr("Ammo"), nil, Tr("How much is left"), Tr("Your equipped ammo and its count.")) end
        K("enchant", Tr("Weapon Enchant"), nil, Tr("Imbues, poisons, oils"), Tr("Lit while an enchant is on the weapon: an imbue, a poison, an oil or a stone."))
        if NS.DriverStance then K("stance", Tr("Stance"), nil, Tr("Stances and forms"), Tr("The stance or form you are in, or one lit while you are in it.")) end
        if NS.DriverCustom then K("timer", Tr("Custom Icon"), nil, Tr("Your own rules"), Tr(CUSTOM_DEF)) end
        if procs then K("special", Tr("Arc Proc"), nil, Tr("Trackers we built"), Tr("A ready-made proc tracker for your class.")) end
    elseif sec == "Bar" then
        K("cooldown", Tr("Cooldown Bar"), nil, Tr("A spell, as a bar"), Tr("A spell's cooldown or its charges as a bar."))
        K("aura", Tr("Aura Bar"), nil, Tr("A buff or debuff, as a bar"), Tr("A buff or debuff's time left or stacks as a bar."))
        if Options.CDMBarAddRows and NS.CDMBars then
            K("cdmbar", Tr("Cooldown Manager Bar"), nil, Tr("Copy a Tracked Bar"), Tr("Copies one of the Cooldown Manager's Tracked Bars, its timer and all."))
        end
        if Options.TotemBarAddRows and NS.TotemBars then
            K("totembar", Tr("Totem Bar"), nil, Tr("Time left on a totem"), Tr("The time left on one of your totems or guardians, by the spell that puts it down or by its slot."))
        end
        if C_SwingTimer then K("swing", Tr("Swing Bar"), nil, Tr("Your weapon swings"), Tr("The time to your next swing or shot.")) end
        K("resource", Tr("Resource Bar"), nil, Tr("Mana, rage, energy"), Tr("A power bar; Automatic follows the power you are using."))
        K("health", Tr("Health Bar"), nil, Tr("You, a target, a focus"), Tr("A unit's health, with incoming heals and shields."))
        K("cast", Tr("Castbar"), nil, Tr("Yours or an enemy's"), Tr("Casts of you, your target or your focus; hidden between casts."))
        K("enchant", Tr("Weapon Enchant Bar"), nil, Tr("Time left, charges"), Tr("The time left on a weapon's enchant, with its charges."))
        if C_Spell and C_Spell.IsSpellInRange then
            K("range", Tr("Range Bar"), nil, Tr("How far your target is"), Tr("How far your target is, in colored range bands you can edit."))
        end
        if NS.DriverCustom then K("timer", Tr("Custom Bar"), nil, Tr("Your own rules"), Tr(CUSTOM_DEF)) end
        if procs then K("special", Tr("Arc Proc (deck bar)"), nil, Tr("Trackers we built"), Tr("A ready-made proc tracker as a deck bar.")) end
    elseif sec == "Group" then
        K("cooldown", Tr("Icon Group"), nil, Tr("Any icons, in a grid"), Tr("Any icons together; it can close the gaps when some are hidden."))
        K("aura", Tr("Aura Group"), nil, Tr("Aura icons that pack"), Tr("Aura icons only: they pack together as auras come and go."))
        if NS.Reminders then K("reminder", Tr("Reminder Group"), nil, Tr("Pulses mid-screen"), Tr("A spot mid-screen where your cooldowns pulse as they come back.")) end
        if Options.MissingBuffsAddRows then K("missing", Tr("Missing Buffs"), nil, Tr("Shows what you forgot"), Tr("Each icon shows only while its buff is missing, in combat too.")) end
        if Options.BarImport then K("frombars", Tr("From my action bars"), Tr("My Action Bars"), Tr("Pick from your bars"), Tr("A new Icon Group: pick its spells and items from your action bars. Out of combat only.")) end
        if NS.CDMMirror and NS.CDMMirror.Available and NS.CDMMirror.Available() and NS.CDMMirrorOptions then
            K("fromcdm", Tr("From Cooldown Manager"), Tr("Cooldown Manager"), Tr("Copy it into a layout"), Tr("Copies the game's Cooldown Manager into a layout: its bars, spells, auras, totems and items."))
        end
    elseif sec == "Text" then
        if Options.TextAddRows then K("text", Tr("Text"), nil, Tr("Words or numbers on screen"), Tr("Pick what the text is, then what drives it.")) end
        if Options.TextureAddRows then K("texture", Tr("Texture"), nil, Tr("A picture on screen"), Tr("A picture that follows an aura, a cooldown, your power, health or triggers.")) end
    else
        if Options.WheelAddRows then K("wheel", Tr("Wheel"), nil, Tr("A ring of spells on a key"), Tr("A ring of your spells and items: hold its key, point at one and let go to cast it.")) end
        if Options.SoundAddRows then K("sound", Tr("Sound"), nil, Tr("Plays when something happens"), Tr("Plays a sound or speaks when something happens. Nothing shows on screen.")) end
    end
    return out
end

function AW.KindOf(sec, id)
    for _, k in ipairs(AW.Kinds(sec)) do
        if k.id == id then return k end
    end
    return nil
end

-- A kind's mark: the colour its sidebar pill wears.
function AW.DotColor(sec, id)
    local c
    if sec == "Icon" then
        c = select(2, Options.IconPillText(id))
    elseif sec == "Bar" then
        c = select(2, Options.BarPillText(id))
    elseif sec == "Group" then
        local g = (id == "frombars" and "cooldown") or (id == "fromcdm" and "aura") or (id == "missing" and "aura") or id
        c = Options.GROUP_COLORS[g]
    else
        c = select(2, Options.BarPillText(id))
    end
    return c or COL.dim
end

-- One kind into the form's state: the rows below follow cat and the kind fields.
function AW.WriteKind(sec, id)
    local st = AW.st
    if sec == "Icon" then
        st.cat, st.iconKind = "Icon", id
    elseif sec == "Bar" then
        st.cat, st.barKind = "Bar", id
    elseif sec == "Group" then
        st.cat = "Group"
        st.groupKind = (id == "frombars") and "cooldown" or id
        st.fillFromBars = (id == "frombars") or nil
    elseif sec == "Text" then
        st.cat = (id == "texture") and "Texture" or "Text"
    else
        st.cat = (id == "sound") and "Sound" or "Wheel"
    end
end

-- A class word ("Death Knight") as UnitClass's token.
function AW.Token(word)
    return (tostring(word):upper():gsub("%s", ""))
end

-- Every ready-made this client has, one shape: where it shows (shows), whose
-- class it is, and what a pick writes (kind).
function AW.Ready()
    local out = {}
    local CO, IS, AP = Options.Custom, NS.ItemSets, Options.AuraPicker
    local tex = C_Spell and C_Spell.GetSpellTexture
    if AP and AP.TemplateEntries then
        for _, e in ipairs(AP.TemplateEntries()) do
            out[#out + 1] = { key = e.key, kind = "aura", which = "Icon", e = e, name = e.name, tip = e.tip,
                art = e.texture or 134400, shows = { "Icon:aura", "Bar:aura" } }
        end
    end
    if IS and NS.IsForever ~= true then
        for _, s in ipairs(IS.SPELLS) do
            local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s.spellID) -- raw-id: the template's own spell
            out[#out + 1] = { key = s.key, kind = "spell", which = "Icon", cls = s.class, classWord = s.word, s = s,
                name = nm or s.key, tip = Tr(s.tip), art = (tex and tex(s.spellID)) or 134400, shows = { "Icon:spell" } } -- raw-id: the template's own spell
        end
    end
    if CO and CO.Templates then
        for _, t in ipairs(CO.Templates()) do
            local which = t.which or "Bar"
            out[#out + 1] = { key = t.key, kind = (which == "Group") and "group" or "custom", which = which, t = t,
                cls = t.class and AW.Token(t.class) or nil, classWord = t.class, name = CO.ShownName(t),
                tip = Tr(t.tip), art = (tex and tex(t.art)) or 134400, shows = t.shows } -- raw-id: a template's own art
        end
    end
    if IS and IS.List then
        for _, s in ipairs(IS.List()) do
            local tip = s.category and Tr("Every item of this kind: the icon follows the one you last used, as the Cooldown Manager's does.")
                or Tr("Any of %d items: the icon shows the best one you carry and can use."):format(#s.ids)
            out[#out + 1] = { key = s.key, kind = "list", which = "Icon", list = true, s = s, name = Tr(s.name), tip = tip,
                art = IS.Art(s), shows = { "Icon:item" } }
        end
    end
    return out
end

function AW.ViewClass()
    if AW.st.readyCls then return AW.st.readyCls end
    local _, token = UnitClass("player")
    return token
end

local function ForView(e, view) return e.cls == nil or e.cls == view end

-- The ready-mades of a flow ("Icon:spell") for the class on view; nil flow:
-- the start page's, every one but the item lists.
function AW.ReadyFor(flow)
    local out, view = {}, AW.ViewClass()
    for _, e in ipairs(AW.Ready()) do
        if ForView(e, view) then
            if flow == nil then
                if not e.list then out[#out + 1] = e end
            else
                for _, f in ipairs(e.shows) do
                    if f == flow then out[#out + 1] = e break end
                end
            end
        end
    end
    -- a template with an icon and a bar: the icon comes first
    local RANK = { Icon = 1, Bar = 2, Group = 3 }
    for i, e in ipairs(out) do e._i = i end
    table.sort(out, function(a, b)
        local ra, rb = RANK[a.which] or 9, RANK[b.which] or 9
        if ra ~= rb then return ra < rb end
        return a._i < b._i
    end)
    return out
end

function AW.ReadyByKey(key)
    for _, e in ipairs(AW.Ready()) do
        if e.key == key then return e end
    end
    return nil
end

-- The second line under a ready-made's name.
function AW.ReadySub(e)
    if e.list then return Tr("Item list") end
    local CO = Options.Custom
    if e.classWord or e.cls then
        local word = CO.ClassWord(e.classWord or (e.cls:sub(1, 1) .. e.cls:sub(2):lower()))
        if e.which == "Bar" then return Tr("%s bar"):format(word) end
        if e.which == "Group" then return Tr("%s group"):format(word) end
        return Tr("%s icon"):format(word)
    end
    if e.which == "Bar" then return Tr("Any class, bar") end
    if e.which == "Group" then return Tr("Any class, group") end
    return Tr("Any class, icon")
end

-- The field a ready-made's Name row edits.
function AW.NameField(e)
    if e.kind == "custom" then return "customName" end
    if e.kind == "group" then return "groupName" end
    if e.kind == "list" then return "itemName" end
    if e.kind == "spell" then return "spellName" end
    return (AW.st.addSec == "Bar") and "barAuraName" or "auraName"
end

-- A pick let go: what it wrote comes out, the kind on view goes back in.
function AW.ClearReady(noWrite)
    local st = AW.st
    local e = st.readyE
    if not e then return end
    if e.kind == "custom" then
        st.customTemplate, st.customName, st.customArt = nil, nil, nil
        if e.t.mode then st.barMode = nil end
    elseif e.kind == "group" then
        st.groupTemplate, st.groupName = nil, nil
    elseif e.kind == "list" then
        st.itemID, st.itemName, st.itemSet, st.itemCategory = nil, nil, nil, nil
    elseif e.kind == "aura" then
        st.auraID, st.auraName, st.auraCaster = nil, nil, nil
        st.barAuraID, st.barAuraName, st.barAuraCaster = nil, nil, nil
    elseif e.kind == "spell" then
        st.spellID, st.spellName = nil, nil
    end
    st.ready, st.readyE = nil, nil
    if not noWrite and st.addSec then AW.WriteKind(st.addSec, st.addKind) end
end

function AW.ApplyReady(e)
    local st = AW.st
    local CO, AP = Options.Custom, Options.AuraPicker
    AW.ClearReady(true)
    st.ready, st.readyE = e.key, e
    if e.kind == "custom" then
        if e.which == "Icon" then st.cat, st.iconKind = "Icon", "timer" else st.cat, st.barKind = "Bar", "timer" end
        CO.Pick(st, e.key)
    elseif e.kind == "group" then
        st.cat, st.groupKind = "Group", "cooldown"
        st.fillFromBars = nil
        CO.Pick(st, e.key)
    elseif e.kind == "list" then
        st.cat, st.iconKind = "Icon", "item"
        local s = e.s
        if s.category then
            st.itemID, st.itemName, st.itemSet, st.itemCategory = "", s.name, s.key, s.category
        else
            local t = {}
            for k, id in ipairs(s.ids) do t[k] = tostring(id) end
            st.itemID, st.itemName, st.itemSet, st.itemCategory = table.concat(t, ", "), s.name, s.key, nil
        end
    elseif e.kind == "aura" then
        if st.addSec == "Bar" then
            st.cat, st.barKind = "Bar", "aura"
            AP.Fill(st, e.e, AP.BAR_KEYS)
        else
            st.cat, st.iconKind = "Icon", "aura"
            AP.Fill(st, e.e, AP.ICON_KEYS)
        end
    elseif e.kind == "spell" then
        st.cat, st.iconKind = "Icon", "spell"
        st.spellID, st.spellName = tostring(e.s.spellID), e.name
    end
end

function AW.Relay()
    AT.CloseDropdown()
    AW.SyncList()
    AW.SetFormSize()
    AT.LayoutPage(AW.pg)
    AW.hooks.update()
end

function AW.PickKind(sec, id)
    local st = AW.st
    AW.ClearReady(true)
    st.addSec, st.addKind, st.addStep = sec, id, "form"
    AW.WriteKind(sec, id)
    AW.SetMode(AW.FormMode())
    AW.Relay()
end

function AW.ToggleReady(e)
    if AW.st.ready == e.key then AW.ClearReady() else AW.ApplyReady(e) end
    AW.Relay()
end

-- From the start page, or a search jump: its first home, picked.
function AW.GoReady(e)
    local st = AW.st
    AW.ClearReady(true)
    local sec, id = e.shows[1]:match("^(%a+):(%a+)$")
    st.addSec, st.addKind, st.addStep = sec, id, "form"
    AW.WriteKind(sec, id)
    AW.ApplyReady(e)
    AW.SetMode(AW.FormMode())
    AW.Relay()
end

function AW.BackToStart()
    local st = AW.st
    AW.ClearReady()
    st.addStep = "start"
    AW.SetMode("start")
    AT.CloseDropdown()
end

-- The kinds the side list offers: a group's + shows only what that group takes.
function AW.ListKinds()
    local st, out = AW.st, {}
    local g = st.groupOnly and st.destGroupId and NS.Store.Get(st.destGroupId)
    for _, k in ipairs(AW.Kinds(st.addSec)) do
        if not g or NS.Store.GroupTakes(g, k.id) then out[#out + 1] = k end
    end
    return out
end

local function NewFS(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-- The game's own pictures for the previews, by file so nothing needs a spell
-- to be known; every one is in both games' files.
AW.ART = { storm = 132314, shield = 136051, fort = 135987, totem = 136023, stance = 132349, glow = 449490,
    flame = 135813, flask = 134842, medal = 133434, arrow = 132382, sword = 135349, oil = 134727, watch = 134376,
    question = 134400 }
AW.RING = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Rings\\AD_Ring_thin"

-- What a preview draws: pictures, boxes, words, in the frame's own units.
function AW.PreviewParts(sec, id)
    local c = AW.DotColor(sec, id)
    local track, white = COL.btn, { 1, 1, 1 }
    local function Pic(a, x, y, w, h, grey) return { pic = AW.ART[a], x = x, y = y, w = w, h = h, grey = grey } end
    local function Rect(x, y, w, h, col, edge) return { x = x, y = y, w = w, h = h, col = col, edge = edge } end
    local function Num(t, x, y, size, col) return { text = t, x = x, y = y, size = size, col = col } end
    local function Icon(a, frame)
        local out = { Pic(a, 5, 1, 27, 27) }
        if frame then out[#out + 1] = Rect(5, 1, 27, 27, nil, c) end
        return out
    end
    local function Bar(pct, extra)
        local out = { Rect(3, 11, 33, 8, track, COL.steel), Rect(4, 12, math.floor(31 * pct + 0.5), 6, c) }
        if extra then out[#out + 1] = extra end
        return out
    end
    if sec == "Icon" then
        if id == "spell" then return { Pic("storm", 5, 1, 27, 27), Rect(5, 1, 27, 16, { 0, 0, 0, 0.62 }) } end
        if id == "aura" then return Icon("shield", true) end
        if id == "groupbuff" then return Icon("fort") end
        if id == "item" then return Icon("flask") end
        if id == "trinket" then return Icon("medal") end
        if id == "totem" then return Icon("totem") end
        if id == "ammo" then return Icon("arrow") end
        if id == "enchant" then
            local oil = Pic("oil", 22, 16, 11, 11)
            oil.over = true
            return { Pic("sword", 5, 1, 27, 27), Rect(21, 15, 13, 13, COL.well, c), oil }
        end
        if id == "stance" then return Icon("stance", true) end
        if id == "special" then return Icon("flame", true) end
        return Icon("question")
    elseif sec == "Bar" then
        if id == "swing" then return { Rect(3, 14, 33, 3, COL.steel), Rect(3, 14, 22, 3, c), Rect(25, 10, 2, 10, white) } end
        if id == "range" then
            return { Rect(3, 11, 11, 8, { 0.35, 0.85, 0.45 }), Rect(14, 11, 10, 8, { 0.95, 0.76, 0.31 }), Rect(24, 11, 12, 8, { 0.92, 0.34, 0.34 }) }
        end
        if id == "special" then
            local out = {}
            for i = 0, 3 do out[#out + 1] = Rect(3 + i * 9, 11, 7, 8, (i < 3) and c or track, COL.steel) end
            return out
        end
        if id == "cast" then return Bar(0.55, Rect(20, 10, 2, 10, white)) end
        if id == "health" then return Bar(0.65, Rect(24, 12, 5, 6, { c[1], c[2], c[3], 0.4 })) end
        local PCT = { cooldown = 0.6, aura = 0.35, cdmbar = 0.7, totembar = 0.5, resource = 0.8, enchant = 0.3, timer = 0.45 }
        return Bar(PCT[id] or 0.5)
    elseif sec == "Group" then
        if id == "cooldown" then return { Pic("storm", 7, 2, 12, 12), Pic("flame", 20, 2, 12, 12), Pic("totem", 7, 15, 12, 12), Pic("fort", 20, 15, 12, 12) } end
        if id == "aura" then return { Pic("shield", 3, 10, 10, 10), Pic("fort", 14, 10, 10, 10), Pic("flame", 25, 10, 10, 10) } end
        if id == "reminder" then
            return { Pic("watch", 11, 7, 15, 15),
                { ring = true, x = 4, y = 0, w = 29, h = 29, col = { c[1], c[2], c[3], 0.4 } },
                { ring = true, x = 8, y = 3, w = 22, h = 22, col = c } }
        end
        if id == "missing" then return { Pic("shield", 3, 10, 10, 10, true), Pic("fort", 14, 10, 10, 10, true), Rect(25, 10, 10, 10, nil, COL.faint) } end
        if id == "frombars" then return { Pic("storm", 3, 4, 10, 10), Pic("flame", 14, 4, 10, 10), Pic("totem", 25, 4, 10, 10), Rect(3, 19, 33, 6, track, COL.steel) } end
        return { Pic("storm", 3, 3, 10, 10), Pic("flame", 14, 3, 10, 10), Pic("shield", 25, 3, 10, 10), Rect(3, 17, 33, 8, track, COL.steel), Rect(4, 18, 19, 6, c) }
    end
    if id == "text" then return { Num("Aa", 8, 5, 18, c) } end
    if id == "texture" then
        local art = Pic("glow", 1, 0, 36, 29)
        art.add = true
        return { art }
    end
    if id == "wheel" then
        local out = {}
        for _, p in ipairs({ { 16, 1 }, { 27, 7 }, { 27, 18 }, { 16, 23 }, { 6, 18 }, { 6, 7 } }) do
            out[#out + 1] = { x = p[1], y = p[2], w = 6, h = 6, col = c, disc = true }
        end
        return out
    end
    return { Rect(5, 10, 3, 10, c), Rect(11, 7, 3, 16, c), Rect(17, 3, 3, 23, c), Rect(23, 8, 3, 15, c), Rect(29, 11, 3, 9, c) }
end

-- A kind's small picture of what it makes, drawn from whole units.
function AW.Preview(parent, sec, id)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(AW.PREV_W, AW.PREV_H)
    -- a bordered part is a child frame, drawn over its parent's textures: what
    -- goes on top of one needs a frame of its own above them
    local top = CreateFrame("Frame", nil, box)
    top:SetAllPoints()
    top:SetFrameLevel(box:GetFrameLevel() + 3)
    box._top = top
    for _, p in ipairs(AW.PreviewParts(sec, id)) do
        if p.pic then
            local t = (p.over and top or box):CreateTexture(nil, "ARTWORK")
            t:SetTexture(p.pic)
            if p.add then
                -- spell-effect art on black: the black adds nothing
                t:SetBlendMode("ADD")
            else
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            if p.grey then t:SetDesaturated(true) end
            t:SetSize(p.w, p.h)
            t:SetPoint("TOPLEFT", 1 + p.x, -1 - p.y)
        elseif p.ring then
            local t = top:CreateTexture(nil, "OVERLAY")
            t:SetTexture(AW.RING)
            t:SetVertexColor(p.col[1], p.col[2], p.col[3], p.col[4] or 1)
            t:SetSize(p.w, p.h)
            t:SetPoint("TOPLEFT", 1 + p.x, -1 - p.y)
        elseif p.text then
            local fs = top:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, p.size, "OUTLINE")
            local c = p.col or { 1, 1, 1 }
            fs:SetTextColor(c[1], c[2], c[3])
            fs:SetPoint("TOPLEFT", 1 + p.x, -1 - p.y)
            fs:SetText(p.text)
        elseif p.edge then
            local f = CreateFrame("Frame", nil, box, "BackdropTemplate")
            f:SetSize(p.w, p.h)
            f:SetPoint("TOPLEFT", 1 + p.x, -1 - p.y)
            AT.Skin(f, p.col or { 0, 0, 0, 0 }, p.edge)
        else
            local t = top:CreateTexture(nil, "OVERLAY")
            t:SetTexture(p.disc and "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" or AT.WHITE)
            t:SetVertexColor(p.col[1], p.col[2], p.col[3], p.col[4] or 1)
            t:SetSize(p.w, p.h)
            t:SetPoint("TOPLEFT", 1 + p.x, -1 - p.y)
        end
    end
    return box
end

-- A kind's button: a soft shine, its picture in a dark panel running edge to
-- edge on the left, then its name and few words. Light shows the pick.
function AW.KindButton(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    local G = AW.GRAPHITE
    AT.Skin(b, G.bottom, G.edge)
    b.grad = b:CreateTexture(nil, "BORDER")
    b.grad:SetTexture(AT.WHITE)
    b.grad:SetPoint("TOPLEFT", 1, -1)
    b.grad:SetPoint("BOTTOMRIGHT", -1, 1)
    b.zone = b:CreateTexture(nil, "ARTWORK")
    b.zone:SetTexture(AT.WHITE)
    b.zone:SetVertexColor(G.zone[1], G.zone[2], G.zone[3], 1)
    b.zone:SetPoint("TOPLEFT", 1, -1)
    b.zone:SetPoint("BOTTOMLEFT", 1, 1)
    b.zone:SetWidth(AW.ZONE_W)
    local rule = b:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(AT.WHITE)
    rule:SetVertexColor(G.rule[1], G.rule[2], G.rule[3], 1)
    rule:SetPoint("TOPLEFT", b.zone, "TOPRIGHT", 0, 0)
    rule:SetPoint("BOTTOMLEFT", b.zone, "BOTTOMRIGHT", 0, 0)
    rule:SetWidth(1)
    local bevel = b:CreateTexture(nil, "ARTWORK")
    bevel:SetTexture(AT.WHITE)
    bevel:SetVertexColor(1, 1, 1, 0.07)
    bevel:SetPoint("TOPLEFT", 1, -1)
    bevel:SetPoint("TOPRIGHT", -1, -1)
    bevel:SetHeight(1)
    b._w, b._hh = w, h
    b._prevs = {}
    local textX = 1 + AW.ZONE_W + 9
    b.nameFS = NewFS(b, 13, G.name)
    b.nameFS:SetWidth(w - textX - 5)
    b.nameFS:SetWordWrap(false)
    b.hintFS = NewFS(b, 10, G.hint)
    b.hintFS:SetWidth(w - textX - 5)
    b.hintFS:SetJustifyV("TOP")
    b.hintFS:SetWordWrap(true)
    function b.Paint(hot)
        local edge = (b._on and COL.arc) or (hot and COL.focus) or G.edge
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        local top, bottom = G.top, G.bottom
        if b._on then top, bottom = COL.sel, COL.sel elseif hot then top, bottom = G.hot, G.hot end
        b:SetBackdropColor(bottom[1], bottom[2], bottom[3], 1)
        if CreateColor then
            b.grad:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
        end
        local ink = b._on and COL.ink or G.name
        b.nameFS:SetTextColor(ink[1], ink[2], ink[3])
    end
    b:SetScript("OnEnter", function()
        b.Paint(true)
        if b._kind then
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(b._kind.name, COL.ink[1], COL.ink[2], COL.ink[3])
            GameTooltip:AddLine(b._kind.def, COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        b.Paint(false)
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end)
    b.Paint(false)
    return b
end

function AW.SetKindButton(b, sec, k)
    b._kind, b._adKind = k, sec .. ":" .. k.id
    b.nameFS:SetText(k.short)
    b.hintFS:SetText(k.hint)
    for _, p in pairs(b._prevs) do p:Hide() end
    local key = sec .. ":" .. k.id
    if not b._prevs[key] then
        local p = AW.Preview(b, sec, k.id)
        p:SetPoint("TOPLEFT", 1 + math.floor((AW.ZONE_W - AW.PREV_W) / 2), -math.floor((b._hh - AW.PREV_H) / 2))
        b._prevs[key] = p
    end
    b._prevs[key]:Show()
    -- the words sit centred, a wrapped hint takes the room the centring left
    local hh = b.hintFS:GetStringHeight() or 12
    local gap = (hh > 13) and 14 or 16
    local top = math.floor((b._hh - gap - hh) / 2)
    if top < 1 then top = 1 end
    local x = 1 + AW.ZONE_W + 9
    b.nameFS:ClearAllPoints()
    b.nameFS:SetPoint("TOPLEFT", x, -top)
    b.hintFS:ClearAllPoints()
    b.hintFS:SetPoint("TOPLEFT", x, -(top + gap))
end

local function Tooltipped(b, e)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.name, COL.ink[1], COL.ink[2], COL.ink[3])
    GameTooltip:AddLine(e.tip, COL.dim[1], COL.dim[2], COL.dim[3], true)
    GameTooltip:Show()
end

-- A square of art: every ready-made's look.
local function Art(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-- A section header's small picture, plain theme boxes in the accent colour.
function AW.Glyph(head, sec)
    local holder = CreateFrame("Frame", nil, head)
    holder:SetSize(20, 14)
    holder:SetPoint("LEFT", 8, 0)
    local clear, A = { 0, 0, 0, 0 }, COL.arc
    local function Box(x, y, w, h)
        local f = CreateFrame("Frame", nil, holder, "BackdropTemplate")
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", x, y)
        AT.Skin(f, clear, A)
        return f
    end
    local function Fill(x, y, w, h, c)
        local t = holder:CreateTexture(nil, "ARTWORK")
        t:SetTexture(AT.WHITE)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", x, y)
        return t
    end
    if sec == "Icon" then
        -- a small real icon with a cooldown across it
        local pic = holder:CreateTexture(nil, "ARTWORK", nil, 1)
        pic:SetTexture(AW.ART.storm)
        pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pic:SetSize(16, 16)
        pic:SetPoint("TOPLEFT", 2, 1)
        local sweep = holder:CreateTexture(nil, "ARTWORK", nil, 2)
        sweep:SetTexture(AT.WHITE)
        sweep:SetVertexColor(0, 0, 0, 0.6)
        sweep:SetSize(8, 16)
        sweep:SetPoint("TOPLEFT", 2, 1)
        holder._iconArt = pic
    elseif sec == "Bar" then
        Box(0, -4, 20, 6)
        Fill(1, -5, 11, 4, A)
    elseif sec == "Group" then
        Box(2, 0, 7, 6) Box(11, 0, 7, 6) Box(2, -8, 7, 6) Box(11, -8, 7, 6)
    elseif sec == "Text" then
        Fill(3, -1, 14, 2, A)
        Fill(9, -1, 2, 12, A)
    elseif sec == "Extra" then
        local ring = holder:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        ring:SetVertexColor(A[1], A[2], A[3], 1)
        ring:SetSize(12, 12)
        ring:SetPoint("TOPLEFT", 4, -1)
        local hole = holder:CreateTexture(nil, "ARTWORK", nil, 2)
        hole:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        hole:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        hole:SetSize(8, 8)
        hole:SetPoint("TOPLEFT", 6, -3)
    else
        local star = holder:CreateTexture(nil, "ARTWORK")
        star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        star:SetDesaturated(true)
        star:SetVertexColor(A[1], A[2], A[3], 1)
        star:SetSize(14, 14)
        star:SetPoint("TOPLEFT", 3, 0)
    end
    return holder
end

-- One titled section box, the kinds inside, cols across.
function AW.SectionBox(parent, sec, w, cols)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    AT.Skin(box, COL.box, COL.line2)
    box:SetWidth(w)
    local head = CreateFrame("Frame", nil, box)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(AW.HEAD_H - 1)
    local bg = head:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(AT.WHITE)
    bg:SetVertexColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
    local glyph = AW.Glyph(head, sec)
    local title = NewFS(head, 13, COL.ink)
    title:SetPoint("LEFT", glyph, "RIGHT", 7, 0)
    title:SetText(AW.SectionTitle(sec))
    local sub = NewFS(head, 10, COL.dim)
    sub:SetPoint("LEFT", title, "RIGHT", 7, 0)
    sub:SetText(AW.SectionSub(sec))
    box._sec, box._head, box._titleFS = sec, head, title
    local inner = w - 2 - AW.BOX_PAD * 2
    local cw = math.floor((inner - (cols - 1) * AW.ITEM_GAP) / cols)
    local kinds = AW.Kinds(sec)
    box._btns = {}
    for i, k in ipairs(kinds) do
        local b = AW.KindButton(box, cw, AW.ITEM_H)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", 1 + AW.BOX_PAD + col * (cw + AW.ITEM_GAP), -(AW.HEAD_H + AW.BOX_PAD + row * (AW.ITEM_H + AW.ITEM_GAP)))
        AW.SetKindButton(b, sec, k)
        b:SetScript("OnClick", function() AW.PickKind(sec, k.id) end)
        box._btns[i] = b
    end
    local rows = math.ceil(#kinds / cols)
    box._height = AW.HEAD_H + AW.BOX_PAD * 2 + 1 + rows * AW.ITEM_H + math.max(0, rows - 1) * AW.ITEM_GAP
    box:SetHeight(box._height)
    box._empty = #kinds == 0
    return box
end

function AW.BuildStart()
    local win = AW.win
    local page = CreateFrame("Frame", nil, win)
    page:SetPoint("TOPLEFT", AW.PAD, -(AW.TOP + AW.PAD - 6))
    page:SetPoint("BOTTOMRIGHT", -AW.PAD, AW.PAD)
    AW.start = page
    local inner = AW.W - AW.PAD * 2
    local strip = CreateFrame("Frame", nil, page, "BackdropTemplate")
    AT.Skin(strip, COL.btn, COL.line2)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetWidth(inner)
    strip._glyph = AW.Glyph(strip, "Ready")
    strip._label = NewFS(strip, 13, COL.ink)
    strip._label:SetPoint("LEFT", strip._glyph, "RIGHT", 7, 0)
    strip._label:SetText(Tr("Ready-made"))
    strip._chips = {}
    AW.strip = strip
    local two = math.floor((inner - AW.GAP) / 2)
    AW.bands = {
        { AW.SectionBox(page, "Icon", inner, 5) },
        { AW.SectionBox(page, "Bar", inner, 5) },
        { AW.SectionBox(page, "Group", inner, 5) },
        { AW.SectionBox(page, "Text", two, 2), AW.SectionBox(page, "Extra", inner - two - AW.GAP, 2) },
    }
    page:Hide()
end

function AW.StripChip(i)
    local strip = AW.strip
    local b = strip._chips[i]
    if b then return b end
    b = CreateFrame("Button", nil, strip, "BackdropTemplate")
    b:SetHeight(30)
    AT.Skin(b, COL.box, COL.line2)
    b.tex = Art(b, 22)
    b.tex:SetPoint("LEFT", 3, 0)
    b.fs = NewFS(b, 11, COL.ink)
    b.fs:SetPoint("LEFT", b.tex, "RIGHT", 6, 0)
    b.fs:SetWordWrap(false)
    b:SetScript("OnEnter", function()
        b:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
        if b._e then Tooltipped(b, b._e) end
    end)
    b:SetScript("OnLeave", function()
        b:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1)
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function() if b._e then AW.GoReady(b._e) end end)
    strip._chips[i] = b
    return b
end

-- The strip's chips, wrapping when a long language needs a second line, then
-- the section bands under it. All from known sizes: nothing waits on a resize.
function AW.LayStart()
    local strip = AW.strip
    local list = AW.ReadyFor(nil)
    local inner = AW.W - AW.PAD * 2
    local x0 = 36 + math.ceil(strip._label:GetStringWidth() or 70) + 10
    local x, y, lineH = x0, -5, 30
    local CH = 35
    for i, e in ipairs(list) do
        local b = AW.StripChip(i)
        b._e, b._adTemplate = e, e.key
        b.tex:SetTexture(e.art)
        b.fs:SetText((e.which == "Bar") and Tr("%s bar"):format(e.name) or e.name)
        local tw = b.fs:GetStringWidth() or 0
        if tw <= 0 then tw = #b.fs:GetText() * 6 end
        local w = math.ceil(tw) + 3 + 22 + 6 + 8
        if x + w > inner - 8 and x > x0 then
            x, y = x0, y - CH
        end
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, y)
        b:Show()
        x = x + w + 5
    end
    for i = #list + 1, #strip._chips do
        strip._chips[i]._e = nil
        strip._chips[i]:Hide()
    end
    local top = 0
    if #list > 0 then
        local h = -y + lineH + 5
        strip:SetHeight(h)
        strip:Show()
        top = h + AW.GAP
    else
        strip:Hide()
    end
    for _, band in ipairs(AW.bands) do
        local bx, tall, any = 0, 0, false
        for _, box in ipairs(band) do
            if box._empty then
                box:Hide()
            else
                any = true
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", bx, -top)
                box:Show()
                bx = bx + box:GetWidth() + AW.GAP
                tall = math.max(tall, box._height)
            end
        end
        if any then top = top + tall + AW.GAP end
    end
    AW.startH = top - AW.GAP
end

function AW.BuildList()
    local win = AW.win
    local list = CreateFrame("Frame", nil, win, "BackdropTemplate")
    AT.Skin(list, COL.well)
    list:SetPoint("TOPLEFT", 1, -AW.TOP)
    list:SetPoint("BOTTOMLEFT", 1, AW.FOOT_H + 1)
    list:SetWidth(AW.LIST_W)
    local rule = list:CreateTexture(nil, "OVERLAY")
    rule:SetTexture(AT.WHITE)
    rule:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    rule:SetPoint("TOPRIGHT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetWidth(1)
    local back = AT.MakeSmallButton(list, "< All kinds", AW.LIST_W - 14)
    back:SetPoint("TOPLEFT", 7, -7)
    back:SetHeight(22)
    back:SetScript("OnClick", AW.BackToStart)
    list._back = back
    list._title = NewFS(list, 13, COL.ink)
    list._title:SetPoint("TOPLEFT", 9, -35)
    list._btns = {}
    AW.list = list
    list:Hide()
end

function AW.SyncList()
    local list, st = AW.list, AW.st
    if not st.addSec then return end
    local hasBack = not st.groupOnly
    list._back:SetShown(hasBack)
    list._title:SetText(AW.SectionTitle(st.addSec))
    local top = hasBack and -56 or -30
    list._title:ClearAllPoints()
    list._title:SetPoint("TOPLEFT", 9, hasBack and -35 or -9)
    local kinds = AW.ListKinds()
    for i, k in ipairs(kinds) do
        local b = list._btns[i]
        if not b then
            b = AW.KindButton(list, AW.LIST_W - 14, 40)
            b:SetScript("OnClick", function() if b._kind then AW.PickKind(b._sec, b._kind.id) end end)
            list._btns[i] = b
        end
        b._sec = st.addSec
        AW.SetKindButton(b, st.addSec, k)
        b._on = (k.id == st.addKind)
        b.Paint(false)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 7, top - (i - 1) * 42)
        b:Show()
    end
    for i = #kinds + 1, #list._btns do
        list._btns[i]._kind = nil
        list._btns[i]:Hide()
    end
end

function AW.BuildFoot()
    local win = AW.win
    local foot = CreateFrame("Frame", nil, win, "BackdropTemplate")
    AT.Skin(foot, COL.panel)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(AW.FOOT_H)
    foot:SetFrameLevel(win:GetFrameLevel() + 20)
    local rule = foot:CreateTexture(nil, "OVERLAY")
    rule:SetTexture(AT.WHITE)
    rule:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    rule:SetPoint("TOPLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", 0, 0)
    rule:SetHeight(1)
    local create = AT.MakeSmallButton(foot, "Create", 94)
    create:SetHeight(26)
    create:SetPoint("LEFT", 12, 0)
    local cancel = AT.MakeSmallButton(foot, "Cancel", 72)
    cancel:SetHeight(26)
    cancel:SetPoint("LEFT", create, "RIGHT", 6, 0)
    cancel:SetScript("OnClick", function() win:Hide() end)
    local st = AW.st
    local dd = AT.MakeDropdown(win, foot, 222, AW.hooks.destItems,
        function() return st.destGroupId or 0 end,
        function(v) st.destGroupId = (v ~= 0) and v or nil end,
        function() AT.LayoutPage(AW.pg) end)
    dd:SetHeight(24)
    dd:SetPoint("RIGHT", -12, 0)
    local label = NewFS(foot, 12, COL.ink)
    label:SetPoint("RIGHT", dd, "LEFT", -8, 0)
    label:SetText(Tr("Add to"))
    foot._create, foot._cancel, foot._dd, foot._label = create, cancel, dd, label
    AW.foot = foot
end

function AW.ClassItems()
    local seen, out = {}, {}
    local CO = Options.Custom
    local function Add(token, word)
        if token and not seen[token] then
            seen[token] = true
            out[#out + 1] = { value = token, text = word, raw = true }
        end
    end
    local shown, token = UnitClass("player")
    Add(token, shown)
    for _, e in ipairs(AW.Ready()) do
        if e.cls then
            local word = e.classWord or (e.cls:sub(1, 1) .. e.cls:sub(2):lower())
            Add(e.cls, CO and CO.ClassWord(word) or word)
        end
    end
    return out
end

function AW.BuildClassPick()
    local win, st = AW.win, AW.st
    local holder = CreateFrame("Frame", nil, win)
    holder:SetSize(240, 24)
    holder:SetPoint("TOPRIGHT", -36, -3)
    holder:SetFrameLevel(win:GetFrameLevel() + 25)
    local dd = AT.MakeDropdown(win, holder, 103, AW.ClassItems,
        function() return AW.ViewClass() end,
        function(v) st.readyCls = v end,
        function()
            AW.ClearReady()
            if st.addStep == "start" then AW.LayStart() else AW.Relay() end
        end)
    dd:SetPoint("RIGHT", 0, 0)
    local label = NewFS(holder, 11, COL.dim)
    label:SetPoint("RIGHT", dd, "LEFT", -7, 0)
    label:SetText(Tr("Ready-mades for"))
    holder._dd = dd
    AW.classPick = holder
    local view = AT.MakeSmallButton(win, "Classic view", 92)
    view:SetHeight(22)
    view:SetFrameLevel(win:GetFrameLevel() + 25)
    view:SetScript("OnClick", AW.ToggleClassic)
    AW.viewBtn = view
end

-- Classic view: the old tabs and dropdown, for whoever prefers them; each
-- player's choice is kept.
function AW.Classic()
    return NS.Store.UI().addClassic == true and AW.st.remGroupId == nil
end

-- The small window: a Reminder group's add and Classic view.
function AW.Small()
    return AW.st.remGroupId ~= nil or AW.Classic()
end

function AW.FormMode()
    return AW.Classic() and "classic" or "form"
end

function AW.ToggleClassic()
    local st, ui = AW.st, NS.Store.UI()
    AT.CloseDropdown()
    AW.ClearReady()
    ui.addClassic = (ui.addClassic ~= true) or nil
    if AW.Classic() or st.groupOnly then
        st.addStep = "form"
        AW.WriteKind(st.addSec, st.addKind)
        AW.SetMode(AW.FormMode())
        AW.Relay()
    else
        st.addStep = "start"
        AW.SetMode("start")
    end
end

function AW.ClassicTabs()
    if AW.st.groupOnly then return { "Icon" } end
    local tabs = { "Icon", "Bar", "Group" }
    if Options.TextAddRows then tabs[#tabs + 1] = "Text" end
    if Options.TextureAddRows then tabs[#tabs + 1] = "Texture" end
    if Options.WheelAddRows then tabs[#tabs + 1] = "Wheel" end
    if Options.SoundAddRows then tabs[#tabs + 1] = "Sound" end
    local SO = Options.Special
    if SO and SO.On and SO.On() then tabs[#tabs + 1] = "Arc Procs" end
    return tabs
end

function AW.ClassicTab()
    local st = AW.st
    if st.addSec == "Text" then return (st.addKind == "texture") and "Texture" or "Text" end
    if st.addSec == "Extra" then return (st.addKind == "sound") and "Sound" or "Wheel" end
    if st.addSec == "Icon" and st.addKind == "special" then return "Arc Procs" end
    return st.addSec
end

function AW.PickTab(name)
    local st = AW.st
    if name == "Icon" then
        AW.PickKind("Icon", (st.iconKind == "special") and "spell" or st.iconKind or "spell")
    elseif name == "Bar" then
        AW.PickKind("Bar", st.barKind or "cooldown")
    elseif name == "Group" then
        AW.PickKind("Group", (st.groupKind == "fromcdm") and "cooldown" or st.groupKind or "cooldown")
    elseif name == "Text" then
        AW.PickKind("Text", "text")
    elseif name == "Texture" then
        AW.PickKind("Text", "texture")
    elseif name == "Wheel" then
        AW.PickKind("Extra", "wheel")
    elseif name == "Sound" then
        AW.PickKind("Extra", "sound")
    else
        AW.PickKind("Icon", "special")
    end
end

-- Classic's kind dropdown items: the list a group's + allows, without the
-- two ways to fill a group, which have no place in its dropdown.
function AW.ClassicItems(sec)
    local st, out = AW.st, {}
    local g = st.groupOnly and st.destGroupId and NS.Store.Get(st.destGroupId)
    for _, k in ipairs(AW.Kinds(sec)) do
        if k.id ~= "frombars" and k.id ~= "fromcdm" and (not g or NS.Store.GroupTakes(g, k.id)) then
            out[#out + 1] = { value = k.id, text = k.name, raw = true }
        end
    end
    return out
end

-- Classic's unnamed squares: each template where it always lived.
function AW.ClassicReady()
    local st, out = AW.st, {}
    if not st.addSec then return out end
    local flow = st.addSec .. ":" .. st.addKind
    local _, token = UnitClass("player")
    for _, e in ipairs(AW.Ready()) do
        if e.shows[1] == flow and (e.kind ~= "spell" or e.cls == token) then out[#out + 1] = e end
    end
    return out
end

function AW.SquaresRow(pg, vis)
    local CELL, PITCH, ACROSS = 32, 36, 12
    local row = AT.AddRow(pg, PITCH + 8, function() return vis() and #AW.ClassicReady() > 0 end)
    row._awKeep = true
    row._cells = {}
    row._sync = function()
        local list = AW.ClassicReady()
        for i, e in ipairs(list) do
            local b = row._cells[i]
            if not b then
                b = CreateFrame("Button", nil, row, "BackdropTemplate")
                b:SetSize(CELL, CELL)
                AT.Skin(b, COL.well, COL.line)
                b.tex = b:CreateTexture(nil, "ARTWORK")
                b.tex:SetPoint("TOPLEFT", 2, -2)
                b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
                b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                function b.Edge(hot)
                    local c = (b._e and AW.st.ready == b._e.key and COL.arc) or (hot and COL.focus) or COL.line
                    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                end
                b:SetScript("OnEnter", function()
                    b.Edge(true)
                    if b._e then Tooltipped(b, b._e) end
                end)
                b:SetScript("OnLeave", function()
                    b.Edge(false)
                    if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
                end)
                b:SetScript("OnClick", function() if b._e then AW.ToggleReady(b._e) end end)
                row._cells[i] = b
            end
            b._e, b._adTemplate, b._adSet, b._adTpl = e, e.key, e.key, e.key
            b.tex:SetTexture(e.art)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + ((i - 1) % ACROSS) * PITCH, -(4 + math.floor((i - 1) / ACROSS) * PITCH))
            b.Edge(false)
            b:Show()
        end
        for i = #list + 1, #row._cells do
            row._cells[i]._e = nil
            row._cells[i]:Hide()
        end
        local want = math.max(1, math.ceil(#list / ACROSS)) * PITCH + 8
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
    return row
end

-- Classic's one line saying what the kind is.
function AW.ClassicDesc(pg, vis)
    local st = AW.st
    local row = AT.AddRow(pg, 20, vis)
    row._awKeep = true
    row.fs = NewFS(row, 11, COL.dim)
    row.fs:SetPoint("TOPLEFT", 10, -2)
    row.fs:SetWidth(AW.REM_W - 56)
    row.fs:SetJustifyV("TOP")
    row.fs:SetWordWrap(true)
    row._sync = function()
        local k = st.addSec and AW.KindOf(st.addSec, st.addKind)
        row.fs:SetText(k and k.def or "")
        local want = math.max(20, math.floor((row.fs:GetStringHeight() or 12) + 8))
        if row._h ~= want then row._h = want row:SetHeight(want) end
    end
end

function AW.ClassicRows(pg, win)
    local st = AW.st
    local function Is(sec) return function() return AW.Classic() and st.addSec == sec end end
    local function Dropdown(label, sec)
        AT.RowDropdown(pg, win, label, function() return st.addKind end,
            function(v) AW.PickKind(sec, v) end,
            function() return AW.ClassicItems(sec) end,
            function() return Is(sec)() and st.addKind ~= "special" end)
    end
    Dropdown("Icon kind", "Icon")
    Dropdown("Bar category", "Bar")
    local notGroup = function() return AW.Classic() and st.addSec ~= "Group" end
    AW.ClassicDesc(pg, notGroup)
    AW.SquaresRow(pg, notGroup)
end

-- Classic's Group kind sits under Group name, as it always did.
function AW.ClassicGroupRows(pg, win)
    local st = AW.st
    local isGroup = function() return AW.Classic() and st.addSec == "Group" end
    AT.RowDropdown(pg, win, "Group kind", function() return st.addKind end,
        function(v) AW.PickKind("Group", v) end,
        function() return AW.ClassicItems("Group") end,
        isGroup)
    AW.ClassicDesc(pg, isGroup)
    AW.SquaresRow(pg, isGroup)
    AT.RowToggle(pg, "Fill it from my action bars",
        function() return st.fillFromBars == true end,
        function(v) st.fillFromBars = v or nil end,
        function() return isGroup() and st.addKind == "cooldown" and not st.groupTemplate end,
        "Opens a picker for this group's spells and items right after Create. Out of combat only.")
end

-- The right side's size: the window never changes between its two pages.
function AW.SetFormSize()
    local st, pg, win = AW.st, AW.pg, AW.win
    pg:ClearAllPoints()
    if AW.Small() then
        pg:SetPoint("TOPLEFT", 10, -40)
        pg:SetPoint("BOTTOMRIGHT", -10, AW.FOOT_H + 4)
    else
        pg:SetPoint("TOPLEFT", AW.LIST_W + 12, -(AW.TOP + 4))
        pg:SetPoint("BOTTOMRIGHT", -10, AW.FOOT_H + 4)
    end
end

function AW.PageH()
    if AW.Small() then return AW.REM_H - 40 - AW.FOOT_H - 4 end
    return AW.H - (AW.TOP + 4) - AW.FOOT_H - 4
end

function AW.SetMode(mode)
    local win = AW.win
    local small = mode == "reminder" or mode == "classic"
    if small then win:SetSize(AW.REM_W, AW.REM_H) else win:SetSize(AW.W, AW.H) end
    -- built on its first showing: the window's background build stays light
    if mode == "start" and not AW.start then AW.BuildStart() end
    if AW.start then AW.start:SetShown(mode == "start") end
    AW.list:SetShown(mode == "form")
    AW.pg:SetShown(mode ~= "start")
    AW.foot:SetShown(mode ~= "start")
    AW.classPick:SetShown(not small)
    AW.classPick._dd.Refresh()
    local view = AW.viewBtn
    view:SetShown(mode ~= "reminder")
    view.fs:SetText(Tr((mode == "classic") and "New view" or "Classic view"))
    view:ClearAllPoints()
    view:SetPoint("TOPRIGHT", small and -36 or -286, -4)
    if mode == "start" then
        AW.LayStart()
    else
        AW.SetFormSize()
        AW.SyncList()
    end
end

-- Called as the window opens, after OpenAdd has set the destination.
function AW.Open()
    local st = AW.st
    AW.ClearReady(true)
    st.readyCls = nil
    if st.remGroupId then
        AW.SetMode("reminder")
        return
    end
    if st.groupOnly then
        st.addSec, st.addKind, st.addStep = "Icon", st.iconKind or "spell", "form"
        AW.WriteKind("Icon", st.addKind)
        AW.SetMode(AW.FormMode())
        return
    end
    st.addSec, st.addKind = st.addSec or "Icon", st.addKind or "spell"
    AW.WriteKind(st.addSec, st.addKind)
    if AW.Classic() then
        st.addStep = "form"
        AW.SetMode("classic")
        return
    end
    st.addStep = "start"
    AW.SetMode("start")
end

-- After every layout of the form: Create and the footer's Add to follow it.
function AW.AfterLayout()
    local st = AW.st
    AW.hooks.update()
    local dest = st.cat == "Icon" and not st.remGroupId
    AW.foot._dd:SetShown(dest)
    AW.foot._label:SetShown(dest)
    if AW.foot._dd.Refresh then AW.foot._dd.Refresh() end
end

-- A search hit on a template: the window opens on it, picked.
function AW.OpenReady(key)
    local e = AW.ReadyByKey(key)
    if e then AW.GoReady(e) end
end

-- The rows above the form. Marked to stay through a ready-made's pick; Finish
-- hides every other row while one is picked.
function AW.TopRows(pg)
    local st = AW.st
    local notRem = function() return not AW.Small() end
    local head = AT.AddRow(pg, 46, notRem)
    head._awKeep = true
    head.title = NewFS(head, 16, COL.ink)
    head.title:SetPoint("TOPLEFT", 10, -2)
    head.def = NewFS(head, 12, COL.dim)
    head.def:SetPoint("TOPLEFT", 10, -24)
    head.def:SetWordWrap(false)
    head._sync = function()
        local k = st.addSec and AW.KindOf(st.addSec, st.addKind)
        local e = st.readyE
        head.title:SetText(e and e.name or (k and k.name) or "")
        head.def:SetText(e and AW.ReadySub(e) or (k and k.def) or "")
    end
    AW.headRow = head

    local tiles = AT.AddRow(pg, 70, function()
        return notRem() and st.addSec ~= nil and #AW.ReadyFor(st.addSec .. ":" .. st.addKind) > 0
    end)
    tiles._awKeep = true
    tiles.cap = NewFS(tiles, 11, COL.title)
    tiles.cap:SetPoint("TOPLEFT", 10, -2)
    tiles.cap:SetText(Tr("READY-MADE"))
    tiles._cells = {}
    tiles._sync = function() AW.SyncTiles(tiles) end
    AW.tilesRow = tiles

    local tip = AT.AddRow(pg, 34, function() return st.readyE ~= nil and not AW.Classic() end)
    tip._awKeep = true
    tip.fs = NewFS(tip, 11, COL.dim)
    tip.fs:SetPoint("TOPLEFT", 10, -2)
    tip.fs:SetWidth(AW.W - AW.LIST_W - 50)
    tip.fs:SetJustifyV("TOP")
    tip.fs:SetWordWrap(true)
    tip._sync = function() tip.fs:SetText(st.readyE and st.readyE.tip or "") end

    local function NameRow(label, isGroup)
        local row = AT.RowInput(pg, label,
            function() local e = st.readyE return e and st[AW.NameField(e)] or "" end,
            function(v)
                local e = st.readyE
                if e then st[AW.NameField(e)] = (v ~= "") and v or e.name end
            end,
            function() return st.readyE ~= nil and not AW.Classic() and (st.readyE.kind == "group") == isGroup end,
            "What the sidebar calls it.", nil, true)
        row._awKeep = true
    end
    NameRow("Name", false)
    NameRow("Group name", true)
end

function AW.TileCell(tiles, i)
    local b = tiles._cells[i]
    if b then return b end
    b = CreateFrame("Button", nil, tiles, "BackdropTemplate")
    b:SetSize(AW.TILE_W, AW.TILE_H)
    AT.Skin(b, COL.box, COL.line2)
    b.tex = Art(b, 29)
    b.tex:SetPoint("LEFT", 7, 0)
    b.nameFS = NewFS(b, 12, COL.ink)
    b.nameFS:SetPoint("TOPLEFT", b.tex, "TOPRIGHT", 7, 1)
    b.nameFS:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    b.nameFS:SetWordWrap(false)
    b.subFS = NewFS(b, 10, COL.faint)
    b.subFS:SetPoint("BOTTOMLEFT", b.tex, "BOTTOMRIGHT", 7, 0)
    b.subFS:SetPoint("RIGHT", b, "RIGHT", -3, 0)
    b.subFS:SetWordWrap(false)
    function b.Paint(hot)
        local on = b._e ~= nil and AW.st.ready == b._e.key
        local bg = on and COL.sel or COL.box
        local edge = (on and COL.arc) or (hot and COL.focus) or COL.line2
        b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    b:SetScript("OnEnter", function()
        b.Paint(true)
        if b._e then Tooltipped(b, b._e) end
    end)
    b:SetScript("OnLeave", function()
        b.Paint(false)
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function() if b._e then AW.ToggleReady(b._e) end end)
    tiles._cells[i] = b
    return b
end

function AW.SyncTiles(tiles)
    local st = AW.st
    if not st.addSec then return end
    local list = AW.ReadyFor(st.addSec .. ":" .. st.addKind)
    local pitchX, pitchY = AW.TILE_W + AW.TILE_GAP, AW.TILE_H + AW.TILE_GAP
    for i, e in ipairs(list) do
        local b = AW.TileCell(tiles, i)
        b._e, b._adTemplate, b._adSet, b._adTpl = e, e.key, e.key, e.key
        b.tex:SetTexture(e.art)
        b.nameFS:SetText(e.name)
        b.subFS:SetText(AW.ReadySub(e))
        b:ClearAllPoints()
        local col, row = (i - 1) % AW.TILE_COLS, math.floor((i - 1) / AW.TILE_COLS)
        b:SetPoint("TOPLEFT", 10 + col * pitchX, -(20 + row * pitchY))
        b.Paint(false)
        b:Show()
    end
    for i = #list + 1, #tiles._cells do
        tiles._cells[i]._e = nil
        tiles._cells[i]:Hide()
    end
    local rows = math.ceil(#list / AW.TILE_COLS)
    local want = 20 + rows * pitchY + 5
    if tiles._h ~= want then tiles._h = want tiles:SetHeight(want) end
end

-- The line under a name field when a ready-made covers what was typed. Its
-- room is always kept, so typing never moves the rows below.
AW.HINT_FIELD = { ["Icon:spell"] = "spellID", ["Icon:aura"] = "auraID", ["Bar:cooldown"] = "barSpell", ["Bar:aura"] = "barAuraID" }
AW.hintRows = {}

function AW.HintMatch()
    local st = AW.st
    if st.ready or not st.addSec then return nil end
    local flow = st.addSec .. ":" .. st.addKind
    local field = AW.HINT_FIELD[flow]
    local text = field and tostring(st[field] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not text or #text < 3 or not text:find("%a") then return nil end
    for _, e in ipairs(AW.ReadyFor(flow)) do
        if e.name:lower():find(text, 1, true) then return e end
    end
    return nil
end

function AW.HintRow(pg, vis)
    local row = AT.AddRow(pg, 26, function() return vis() and not AW.Classic() end)
    row.fs = NewFS(row, 12, COL.ink)
    row.btn = AT.MakeSmallButton(row, "Use it", 62)
    row.btn:SetHeight(22)
    row.btn:SetScript("OnClick", function()
        if row._e then AW.ApplyReady(row._e) AW.Relay() end
    end)
    row._sync = function() AW.SyncHintRow(row) end
    AW.hintRows[#AW.hintRows + 1] = row
    return row
end

function AW.SyncHintRow(row)
    local e = AW.HintMatch()
    row._e = e
    row.fs:ClearAllPoints()
    row.fs:SetPoint("LEFT", row._ctrlX, 0)
    if e then
        row.fs:SetText(Tr("%s has a ready-made."):format(e.name))
        row.fs:Show()
        row.btn:ClearAllPoints()
        row.btn:SetPoint("LEFT", row.fs, "RIGHT", 8, 0)
        row.btn:Show()
    else
        row.fs:Hide()
        row.btn:Hide()
    end
end

function AW.RefreshHints()
    for _, row in ipairs(AW.hintRows) do AW.SyncHintRow(row) end
end

-- A dropdown that had only two entries: the two, side by side.
function AW.PairRow(pg, label, options, get, set, vis)
    local row = AT.AddRow(pg, 24, function() return vis() and not AW.Classic() end)
    local lbl = AT.RowLabel(row, label)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetSize(258, 22)
    holder:SetPoint("LEFT", row._ctrlX, 0)
    row._colLabel, row._colCtrl = lbl, holder
    row._btns = {}
    for i, o in ipairs(options) do
        local b = AT.MakeSmallButton(holder, o.text, 127)
        b:SetHeight(22)
        b:SetPoint("LEFT", (i - 1) * 131, 0)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            set(o.value)
            AT.LayoutPage(pg)
        end)
        b._value = o.value
        row._btns[i] = b
    end
    row._sync = function()
        local cur = get()
        for _, b in ipairs(row._btns) do
            local on = b._value == cur
            local bg, edge, ink = on and COL.sel or COL.btn, on and COL.arc or COL.line2, on and COL.ink or COL.dim
            b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
            b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            b.fs:SetTextColor(ink[1], ink[2], ink[3])
        end
    end
    return row
end

-- After every form row exists: a ready-made's pick shows only the kept rows.
function AW.Finish(pg)
    local function Wrap(row)
        if row._awKeep then return end
        local orig = row._visibleFn
        row._visibleFn = function()
            if AW.st.readyE and not AW.Classic() then return false end
            return orig == nil or orig()
        end
    end
    for _, row in ipairs(pg._rows or {}) do Wrap(row) end
    for _, sec in ipairs(pg._sections or {}) do
        for _, row in ipairs(sec.rows or {}) do Wrap(row) end
    end
end

function AW.Build(win, pg, st, hooks)
    AW.win, AW.pg, AW.st, AW.hooks = win, pg, st, hooks
    AW.BuildList()
    AW.BuildFoot()
    AW.BuildClassPick()
end
