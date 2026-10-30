-- AD_CustomOptions: the Custom Icon and Custom Bar editors (the timer kind): the Tracking rows (art, Show while, seconds, stacks), the Triggers tab's rule editor and the Add window's rows.
-- AD_Options calls in behind nil checks (Options.CustomIconRows / CustomBarRows / CustomAddRows / CustomCreate / CustomBarDriver / CustomWhat); every write goes through NS.DriverCustom.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local Tr = NS.AT.Tr

local CO = { showIf = {} }
Options.Custom = CO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EnglishClient()
    local loc = GetLocale and GetLocale()
    return loc == nil or loc == "enUS" or loc == "enGB"
end

-- At most n bytes, never ending inside a character (a Korean syllable is
-- three bytes).
function CO.Cut(s, n)
    if #s <= n then return s end
    local i = n + 1
    while i > 1 do
        local b = s:byte(i)
        if b < 128 or b >= 192 then break end
        i = i - 1
    end
    return s:sub(1, i - 1)
end

-- A template's name as shown: the English as written on an English client; on
-- another, the game's name for its spell (showSpell) or item (showItem), else
-- the English. `name` stays English: it names what the template makes.
function CO.ShownName(t)
    if EnglishClient() then return t.name end
    local nm
    if t.showSpell then
        nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(t.showSpell) -- raw-id: a template's own spell
    elseif t.showItem then
        nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(t.showItem)
    end
    if type(nm) ~= "string" or nm == "" or (issecretvalue and issecretvalue(nm)) then return t.name end
    return nm
end

-- A template's class word ("Hunter") as the game names the class on this
-- client, else as written.
function CO.ClassWord(word)
    if type(word) ~= "string" or EnglishClient() then return word end
    local names = LOCALIZED_CLASS_NAMES_MALE
    local nm = type(names) == "table" and names[(word:upper():gsub("%s", ""))]
    return (type(nm) == "string" and nm ~= "") and nm or word
end

-- A typed spell: an ID, a pasted link, or the name of a spell you know.
function CO.ParseSpell(text)
    text = Trim(text)
    if text == "" then return nil end
    local RP = Options.ReminderPane
    if RP and RP.ParseSpell then return RP.ParseSpell(text) end
    local id = tonumber(text) or tonumber(text:match("Hspell:(%d+)"))
    if not id and NS.SpellCatalog then
        local hit = NS.SpellCatalog.Search(text, 1)[1]
        id = hit and hit.spellID
    end
    if not id or id <= 0 then return nil end
    return math.floor(id)
end

function CO.SpellName(id)
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
    return nm
end

local function Items(values, labels)
    return function()
        local out = {}
        for _, v in ipairs(values) do out[#out + 1] = { value = v, text = labels[v] or tostring(v) } end
        return out
    end
end

-- The sidebar's and cards' one line for a custom item.
function Options.CustomWhat(rec)
    local CU = NS.DriverCustom
    local rules = CU and CU.Rules(rec) or nil
    local n = rules and #rules or 0
    local words = (n == 1) and Tr("1 rule") or Tr("%d rules"):format(n)
    if rec.type == "bar" then
        return ((rec.barMode == "stack") and Tr("Custom bar  -  stacks, %s") or Tr("Custom bar  -  timer, %s"))
            :format(words)
    end
    return Tr("custom icon, %s"):format(words)
end

-- Ready-made Custom Bars (WoW Forever): picked in the Add window, made with
-- their rules. Every class sees every template, so players know they exist;
-- the tooltip names the class. Rule spells are rank 1; every rank matches by
-- name there.
CO.TEMPLATES_FOREVER = {
    -- The debuff on you can't be tracked by spell ID, so the casts count it:
    -- each adds a stack (4 at most) and restarts its 8 s; the time running
    -- out, casting any other spell, or dying clears them all.
    { key = "arcaneblast", class = "Mage", name = "Arcane Blast", art = 400574, showSpell = 400574, mode = "stack",
      tip = "Your Arcane Blast stacks: up to 4, each cast restarts their 8 seconds; any other spell or dying clears them.",
      driver = { duration = 8, maxStacks = 4, clearOnEnd = true, showWhile = "stacks", rules = {
          { when = "cast", spellID = 400574, act = "add", restartToo = true, secs = 8 },
          { when = "cast_except", spellID = 400574, act = "reset" },
          { when = "cond_on", cond = "dead", act = "reset" },
      } } },
}

-- A hunter trap's minute on the ground. When it springs the game sends the
-- trap's cooldown update again; the cast sends one too, so the stop skips the
-- moment the start fires. One fire and one frost trap can be out at a time,
-- so laying the other trap of its element removes this one.
-- What a trap leaves on the mob, every rank (Forever's own Freezing Trap ID
-- too): the debuff a trap icon shows while it is up.
CO.TRAP_AURAS = {
    [13795] = { 13797, 14298, 14299, 14300, 14301 },
    [13813] = { 13812, 14314, 14315 },
    [1499] = { 3355, 14308, 14309, 1324500 },
    [13809] = { 13810 },
}
-- the debuff on your target, your own copy, the IDs as listed
function CO.TrapOverlay(sids)
    local ids = {}
    for _, sid in ipairs(sids) do
        for _, a in ipairs(CO.TRAP_AURAS[sid] or {}) do ids[#ids + 1] = a end
    end
    return { on = true, auraType = "debuff", unit = "target", caster = "mine", followRank = false,
        spellID = ids[1], spellIDs = (#ids > 1) and ids or nil }
end
-- Armed for a minute, ends when it springs, and its debuff and cooldown after.
function CO.TrapDriver(sid, rival)
    return { duration = 60, cdOn = true, overlay = CO.TrapOverlay({ sid }), rules = {
        { when = "cast", spellID = sid, act = "start", mode = "restart", secs = 60 },
        { when = "spell_update", spellID = sid, act = "stop", withinRule = 1, withinSecs = 0.3, withinNot = true },
        { when = "cast", spellID = rival, act = "stop" },
    } }
end
-- One icon for an element's two traps: it wears the one you laid.
function CO.TrapSlotDriver(sids)
    return { duration = 60, cdOn = true, artFollow = true, overlay = CO.TrapOverlay(sids), rules = {
        { when = "cast", spellID = sids[1], spellIDs = sids, act = "start", mode = "restart", secs = 60 },
        { when = "spell_update", spellID = sids[1], spellIDs = sids, act = "stop",
            withinRule = 1, withinSecs = 0.3, withinNot = true },
    } }
end
-- On cooldown dims and greys it; Ready glows, the cue to lay it again.
CO.TRAP_LOOKS = { states = { cooldownAlpha = 0.4, idleGlow = true } }

for _, t in ipairs({
    { key = "immolationtrap", name = "Immolation Trap", art = 13795, rival = 13813, rivalName = "Explosive Trap" },
    { key = "explosivetrap", name = "Explosive Trap", art = 13813, rival = 13795, rivalName = "Immolation Trap" },
    { key = "freezingtrap", name = "Freezing Trap", art = 1499, rival = 13809, rivalName = "Ice Trap" },
    { key = "icetrap", name = "Ice Trap", art = 13809, rival = 1499, rivalName = "Freezing Trap" },
    { key = "firetrap", name = "Fire Trap", art = 13795, slot = { 13795, 13813 },
      tip = "Your fire trap, Immolation or Explosive: 60 seconds from laying it, then its burn on your target, its cooldown and Ready." },
    { key = "frosttrap", name = "Frost Trap", art = 1499, slot = { 1499, 13809 },
      tip = "Your frost trap, Freezing or Ice: 60 seconds from laying it, then its effect on your target, its cooldown and Ready." },
}) do
    t.which, t.class, t.o = "Icon", "Hunter", CO.TRAP_LOOKS
    -- one trap is its spell; Fire Trap and Frost Trap are our own words
    if not t.slot then t.showSpell = t.art end
    t.driver = t.slot and CO.TrapSlotDriver(t.slot) or CO.TrapDriver(t.art, t.rival)
    -- the whole English line per trap: the tooltip translates it as one key
    t.tip = t.tip or ("Your %s: 60 seconds from laying it (%s replaces it), then its effect on your target, its cooldown and Ready.")
        :format(t.name, t.rivalName)
    t.rival, t.rivalName, t.slot = nil, nil, nil
    CO.TEMPLATES_FOREVER[#CO.TEMPLATES_FOREVER + 1] = t
end

-- The Add window's Hunter Traps group (Forever): an Icon Group of the four
-- traps that shows only what is out. Each is armed for a minute and, once it
-- springs, runs its effect or ends (a freeze can break unseen); Not active is
-- hidden and Close gaps closes the spots. The effect is timed from the spring,
-- not read from the mob: the game shows a debuff only on your target or focus,
-- and the group must keep it while you look elsewhere.
-- burn: the effect is a debuff on the mob (ends with it); Ice Trap's is a
-- patch of ice on the ground.
CO.TRAP_GROUP = {
    { name = "Immolation Trap", sid = 13795, rival = 13813, effect = 15, burn = true },
    { name = "Explosive Trap", sid = 13813, rival = 13795, effect = 20, burn = true },
    { name = "Freezing Trap", sid = 1499, rival = 13809 },
    { name = "Ice Trap", sid = 13809, rival = 1499, effect = 30 },
}
function CO.TrapGroupDriver(e)
    local function Spring(act)
        return { when = "spell_update", spellID = e.sid, act = act, withinRule = 1, withinSecs = 0.3, withinNot = true }
    end
    if not e.effect then
        return { duration = 60, spellID = e.sid, rules = {
            { when = "cast", spellID = e.sid, act = "start", mode = "restart", secs = 60 },
            Spring("stop"),
            { when = "cast", spellID = e.rival, act = "stop" },
        } }
    end
    -- its stacks mark the phase, never shown: 0 armed, 1 sprung
    local spring = Spring("start")
    spring.mode, spring.secs = "restart", e.effect
    local mark = Spring("set")
    mark.n = 1
    local rules = {
        { when = "cast", spellID = e.sid, act = "start", mode = "restart", secs = 60 },
        { when = "cast", spellID = e.sid, act = "remove", n = 1 },
        spring, mark,
        -- the other trap of its element removes an armed trap, not a burn on a mob
        { when = "cast", spellID = e.rival, act = "stop", stacksMax = 0 },
    }
    -- once sprung: your target dying ends a burn, leaving combat ends any
    -- effect (the mob is dead or gone); an armed trap waits on either
    if e.burn then rules[#rules + 1] = { when = "target_died", act = "stop", stacksMin = 1 } end
    rules[#rules + 1] = { when = "combat_end", act = "stop", stacksMin = 1 }
    return { duration = 60, spellID = e.sid, clearOnEnd = true, rules = rules }
end
function CO.TrapGroupCreate(addState, layoutId)
    local Store = NS.Store
    local nm = (type(addState.groupName) == "string") and addState.groupName:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local g = Store.NewGroup(layoutId, (nm ~= "") and nm or "Hunter Traps", "cooldown")
    if not g then return nil end
    Store.SetOverride(g, "arrangement", "dynamicLayout", true)
    Store.SetOverride(g, "arrangement", "dynamicCollapse", "hidden")
    Store.SetOverride(g, "arrangement", "cols", #CO.TRAP_GROUP)
    for _, e in ipairs(CO.TRAP_GROUP) do
        local r = Store.NewIcon("timer", CO.TrapGroupDriver(e), g.id, layoutId, e.name)
        if r then
            Store.SetOverride(r, "states", "cooldownAlpha", 0)
            Store.SetOverride(r, "text", "stackText", false)
            r.c.classes = { HUNTER = true }
        end
    end
    Store.Dirty("tree")
    return g
end
-- the template square under Add > Group > Icon Group
CO.TEMPLATES_FOREVER[#CO.TEMPLATES_FOREVER + 1] = { key = "huntertraps", which = "Group", class = "Hunter",
    name = "Hunter Traps", art = 13795, make = CO.TrapGroupCreate,
    tip = "Your traps in a row: each shows while it is armed or burning, the rest close up." }

-- Ready-made Custom Icons (retail): an item's buff as a timer from its use.
-- The cast starts it, dying clears it.
CO.TEMPLATES_RETAIL = {
    -- a second use while it runs keeps the first timer
    { key = "puzzlebox", which = "Icon", name = "Algeth'ar Puzzle Box", art = 383781, showItem = 193701,
      tip ="The Algeth'ar Puzzle Box's haste: 20 seconds from its use; dying clears it.",
      driver = { duration = 20, rules = {
          { when = "cast", spellID = 383781, act = "start", mode = "idle", secs = 20 },
          { when = "cond_on", cond = "dead", timer = "running", act = "reset" },
      } } },
    { key = "lightspotential", which = "Icon", name = "Light's Potential", art = 1236616, showSpell = 1236616,
      tip ="The Light's Potential potion: 30 seconds from the drink, each drink restarts it; dying clears it.",
      driver = { duration = 30, rules = {
          { when = "cast", spellID = 1236616, act = "start", mode = "restart", secs = 30 },
          { when = "cond_on", cond = "dead", timer = "running", act = "reset" },
      } } },
}

-- the templates this client gets; which = "Icon" or "Bar" (a template
-- without one is a bar), nil for every one
function CO.Templates(which)
    local all = (NS.IsForever == true) and CO.TEMPLATES_FOREVER or CO.TEMPLATES_RETAIL
    if not which then return all end
    local out = {}
    for _, t in ipairs(all) do
        if (t.which or "Bar") == which then out[#out + 1] = t end
    end
    return out
end

function CO.Template(key, which)
    for _, t in ipairs(CO.Templates(which)) do
        if t.key == key then return t end
    end
    return nil
end

-- a template picked into the Add window's state: its name, art and a bar's
-- mode fill the form
function CO.Pick(addState, key)
    local t = CO.Template(key)
    if not t then return false end
    if t.which == "Group" then
        addState.groupTemplate, addState.groupName = t.key, t.name
        return true
    end
    addState.customTemplate = t.key
    addState.customName, addState.customArt = t.name, tostring(t.art)
    if t.mode then addState.barMode = t.mode end
    return true
end

function CO.Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = (type(v) == "table") and CO.Copy(v) or v end
    return c
end

CO.CELL, CO.PITCH = 32, 36

-- One square per template of that kind (which: "Icon" or "Bar"), on the
-- label margin: a click picks it (name, art and mode filled in, the pick
-- cyan), a second click lets it go.
function CO.TemplateRow(pg, addState, vis, which)
    local AT, COL = NS.AT, NS.AT.COL
    local list = CO.Templates(which or "Bar")
    if #list == 0 then return nil end
    local field = (which == "Group") and "groupTemplate" or "customTemplate"
    local row = AT.AddRow(pg, CO.PITCH + 8, vis)
    local cells = {}
    for i, t in ipairs(list) do
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(CO.CELL, CO.CELL)
        b:SetPoint("LEFT", row, "LEFT", 10 + (i - 1) * CO.PITCH, 0)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.tex:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(t.art) or 134400) -- raw-id: a template's own art
        function b.Edge(hot)
            local c = (addState[field] == t.key and COL.arc) or (hot and COL.focus) or COL.line
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        b:SetScript("OnEnter", function()
            b.Edge(true)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(CO.ShownName(t), COL.ink[1], COL.ink[2], COL.ink[3])
            if t.class then
                GameTooltip:AddLine(Tr("%s template"):format(CO.ClassWord(t.class)), COL.arc[1], COL.arc[2], COL.arc[3])
            end
            GameTooltip:AddLine(Tr(t.tip), COL.dim[1], COL.dim[2], COL.dim[3], true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b.Edge(false)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            AT.CloseDropdown()
            if addState[field] == t.key then
                addState[field] = nil
                -- a group's name came with the pick and goes with it
                if which == "Group" and addState.groupName == t.name then addState.groupName = nil end
            else
                CO.Pick(addState, t.key)
            end
            AT.LayoutPage(pg)
        end)
        b._adTemplate = t.key
        cells[i] = b
    end
    row._cells = cells
    row._sync = function()
        for _, b in ipairs(cells) do b.Edge(false) end
    end
    return row
end

-- The Add window's rows for a Custom Icon (which = "Icon") or a Custom Bar
-- ("Bar"): a name and an optional art spell. The rules come after, on the
-- item's Triggers tab.
function Options.CustomAddRows(pg, owner, addState, which)
    local AT = NS.AT
    local vis
    if which == "Bar" then
        vis = function() return addState.cat == "Bar" and addState.barKind == "timer" end
    else
        vis = function()
            return addState.cat == "Icon" and (addState.iconKind or "spell") == "timer" and not addState.remGroupId
        end
    end
    AT.RowDesc(pg, "Its rules (the Triggers tab) start its timer and count its stacks from events you pick.", 20, vis)
    CO.TemplateRow(pg, addState, vis, which)
    AT.RowInput(pg, "Name",
        function() return addState.customName or "" end,
        function(v) addState.customName = v end,
        vis, "What the sidebar calls it.", (which == "Bar") and "Custom Bar" or "Custom Icon", true)
    AT.RowInput(pg, "Art from spell ID (optional)",
        function() return addState.customArt or "" end,
        function(v) addState.customArt = v end,
        vis, "The spell whose icon it wears. A spell ID, a link, or the name of a spell you know.",
        "Question mark until set", true)
end

-- Add > Group > Icon Group: the ready-made groups' squares
function Options.GroupTemplateRows(pg, addState)
    CO.TemplateRow(pg, addState, function()
        return addState.cat == "Group" and (addState.groupKind or "cooldown") == "cooldown"
    end, "Group")
end

-- the picked group template, or nil; used once
function Options.GroupTemplateMake(addState, layoutId)
    local t = addState.groupTemplate and CO.Template(addState.groupTemplate, "Group")
    addState.groupTemplate = nil
    local g = t and t.make(addState, layoutId)
    -- the next group starts unnamed, not under the template's name
    addState.groupName = nil
    return g
end

function CO.AddFields(addState, which)
    local name = Trim(addState.customName)
    if name == "" then name = (which == "Bar") and "Custom Bar" or "Custom Icon" end
    local art = CO.ParseSpell(addState.customArt)
    return name, art
end

-- a picked Custom Icon template comes with its rules, like a bar's below
function Options.CustomCreate(addState, dest, layoutId)
    local name, art = CO.AddFields(addState, "Icon")
    local t = addState.customTemplate and CO.Template(addState.customTemplate, "Icon")
    addState.customTemplate = nil
    local d = { spellID = art, rules = {} }
    if t then
        d = CO.Copy(t.driver)
        d.spellID = art or t.art
    end
    local rec = NS.Store.NewIcon("timer", d, dest, layoutId, name)
    -- a template's own looks (a trap's dim On cooldown and Ready glow)
    if rec and t and t.o then
        for sec, fields in pairs(t.o) do
            for k, v in pairs(fields) do NS.Store.SetOverride(rec, sec, k, v) end
        end
    end
    return rec
end

-- a picked template's rules and settings, its art unless another was typed;
-- the pick is used once
function Options.CustomBarDriver(addState)
    local name, art = CO.AddFields(addState, "Bar")
    local t = addState.customTemplate and CO.Template(addState.customTemplate, "Bar")
    addState.customTemplate = nil
    if t then
        local d = CO.Copy(t.driver)
        d.spellID = art or t.art
        return d, name
    end
    return { spellID = art, rules = {} }, name
end

-- The Tracking rows every custom item has. Rec(): the open item when it is a
-- custom one; vis: the Tracking tab.
function CO.TrackRows(pg, Rec, vis, owner, isBar)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local function CU() return NS.DriverCustom end
    local function Set(field, value)
        local r, E = Rec(), CU()
        if r and E then E.SetDriver(r, field, value) end
        AT.LayoutPage(pg)
    end
    -- an icon's aura and cooldown sections stack beside it (CO.SourceRows)
    AT.Section(pg, isBar and "Custom Bar" or "Custom Icon", { visibleFn = vis, side = (not isBar) and "L" or nil })
    AT.RowDesc(pg, "Its rules on the Triggers tab start its timer and count its stacks.", 20, vis)
    if isBar then
        AT.RowDropdown(pg, owner, "Shows",
            function()
                local r = Rec()
                return (r and r.barMode == "stack") and "stack" or "duration"
            end,
            function(v)
                local r = Rec()
                if not r or r.barMode == v then return end
                r.barMode = v
                if Store.StackModeTicks then Store.StackModeTicks(r, v == "stack") end
                Store.Dirty("tree", r.id)
            end,
            function() return {
                { value = "duration", text = "The timer" },
                { value = "stack", text = "The stacks" },
            } end,
            vis)
    end
    local artRow = AT.RowInput(pg, "Art from spell ID",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = CO.ParseSpell(v)
            if v ~= "" and not id then return end
            Set("spellID", id)
        end,
        vis, "The spell whose icon it wears; Appearance > Icon > Art > Custom icon wins over it. A spell ID, a link, or the name of a spell you know.",
        "Question mark until set")
    local nameFS = artRow:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(NS.AT.FONT, 11, "")
    nameFS:SetPoint("LEFT", artRow._colCtrl, "RIGHT", 8, 0)
    nameFS:SetPoint("RIGHT", artRow, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local artSync = artRow._sync
    artRow._sync = function()
        artSync()
        local r = Rec()
        nameFS:SetText(r and CO.SpellName(r.driver.spellID) or "")
    end
    if not isBar then
        AT.RowToggle(pg, "Art follows the spell that starts it",
            function() local r = Rec() return r ~= nil and r.driver.artFollow == true end,
            function(v) Set("artFollow", v or nil) end,
            vis, "It wears the spell whose cast started its timer: one Fire Trap icon for whichever fire trap you laid.")
    end
    -- The spell above gates the item as on a spell icon: Store.IsLoaded reads
    -- driver.onlyKnown with driver.spellID, so a change is a load pass.
    local function HasSpell()
        local r = Rec()
        return vis() and r ~= nil and r.driver.spellID ~= nil
    end
    AT.RowToggle(pg, "Only load once learned",
        function() local r = Rec() return r ~= nil and r.driver.onlyKnown == true end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.onlyKnown = v and true or nil
            Store.Dirty("load")
            AT.LayoutPage(pg)
        end,
        HasSpell, "Doesn't load until your character knows the spell above (any rank), and loads by itself the moment you learn it.")
    AT.RowToggle(pg, "Only this rank",
        function() local r = Rec() return r ~= nil and r.driver.knownExact == true end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.knownExact = v and true or nil
            Store.Dirty("load")
        end,
        function()
            local r = Rec()
            return HasSpell() and r.driver.onlyKnown == true and NS.IsForever == true
        end,
        "Waits for this exact rank (the spell ID above), not just any rank of the spell.")
    if NS.Options.BuildYield then NS.Options.BuildYield() end
    AT.RowDropdown(pg, owner, "Show as active while",
        function()
            local r = Rec()
            return (r and r.driver.showWhile) or "timer"
        end,
        function(v) Set("showWhile", (v ~= "timer") and v or nil) end,
        Items(S.CUSTOM_SHOW_WHILE, S.CUSTOM_SHOW_WHILE_LABELS), vis)
    AT.RowDesc(pg, isBar and "Active: the bar shows (Hide when inactive hides it otherwise)."
        or "Conditions sets a look for each state it can be in.",
        20, vis)
    AT.RowInput(pg, "Default seconds",
        function()
            local r = Rec()
            local d = r and tonumber(r.driver.duration)
            return d and ("%g"):format(d) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("duration", nil) return end
            if n and n > 0 then Set("duration", math.min(S.CUSTOM_MAX_SECONDS or 7200, n)) end
        end,
        vis, "How long the timer runs, and each stack when stacks run out on their own, when a rule gives no seconds. Enter applies it.",
        "Set per rule")
    AT.RowInput(pg, "Max stacks",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("maxStacks", nil) return end
            if n and n >= 1 then Set("maxStacks", math.floor(math.min(999, n))) end
        end,
        vis, isBar and "Stacks never pass this; in stack mode the bar is full here. Empty = no cap. Enter applies it."
            or "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Each stack runs out on its own",
        function()
            local r = Rec()
            return r ~= nil and r.driver.stackTimers == true
        end,
        function(v) Set("stackTimers", v or nil) end,
        vis, "Every stack added runs its own timer (the rule's seconds, else Default seconds) and drops off when it ends.")
    AT.RowInput(pg, "Full pool while idle",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.idleCount)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("idleCount", nil) return end
            if n and n >= 1 then Set("idleCount", math.floor(math.min(999, n))) end
        end,
        vis, "While the timer is idle at 0 stacks, the count shows this many: a pool reads full before its first use. Empty = off.",
        "Off")
    AT.RowToggle(pg, "Clear stacks when the timer ends",
        function()
            local r = Rec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) Set("clearOnEnd", v or nil) end,
        vis, "When the timer runs out, the stacks go back to 0 with it.")
    if not isBar then CO.SourceRows(pg, Rec, vis, owner) end
end

-- A Custom Icon's right column: an aura the game shows over it while it is up
-- (a spell icon's "On this icon" shape on driver.overlay, the engine's button,
-- so it works in combat) and a spell's cooldown while its timer is idle.
-- Offered only with the game's aura container for the aura.
-- pair: the two side by side (the On the icon sub-tab), else stacked in the right column.
CO.AURA_UNITS = { "target", "focus", "mouseover", "player", "pet" }
CO.AURA_UNIT_WORDS = { target = "Target", focus = "Focus", mouseover = "Mouseover", player = "Player", pet = "Pet" }
function CO.SourceRows(pg, Rec, vis, owner, pair)
    local AT, Store, O = NS.AT, NS.Store, NS.Options
    local function Ov()
        local r = Rec()
        local ov = r and r.driver and r.driver.overlay
        return type(ov) == "table" and ov or nil
    end
    local function Dirty()
        local r = Rec()
        if r then Store.Dirty("style", r.id) end
        AT.LayoutPage(pg)
    end
    local auraVis = function()
        local DA = NS.DriverAura
        return vis() and DA ~= nil and DA.IsAvailable ~= nil and DA.IsAvailable() == true
    end
    local auraOn = function()
        local ov = Ov()
        return auraVis() and ov ~= nil and ov.on == true
    end
    if O.BuildYield then O.BuildYield() end
    AT.Section(pg, "Aura on this icon", { visibleFn = auraVis, side = pair and "L" or "R" })
    AT.RowToggle(pg, "Show an aura",
        function() local ov = Ov() return ov ~= nil and ov.on == true end,
        function(v)
            local r = Rec()
            if not (r and O and O.SetOverlayOn) then return end
            O.SetOverlayOn(r, v)
            -- the phase's rows on Conditions come and go with it
            if O.RefreshAll then O.RefreshAll() end
        end,
        auraVis, "While the aura is up the game shows it over the icon: its time, and gone the moment it drops. Works in combat.")
    AT.RowInput(pg, "Aura spell IDs",
        function()
            local ov = Ov()
            return ov and table.concat(Store.AuraIDList(ov), ", ") or ""
        end,
        function(v)
            local ov = Ov()
            if not (ov and O and O.ParseSpellIDs) then return end
            local ids = O.ParseSpellIDs(v)
            if #ids == 0 then return end
            O.SetAuraSpellIDs(ov, ids)
            Dirty()
        end,
        auraOn, "The aura's spell IDs, separated by commas. A debuff usually has the ID of the spell that puts it up.",
        "e.g. 13797")
    AT.RowDropdown(pg, owner, "Unit",
        function()
            local ov = Ov()
            return (ov and ov.unit) or "target"
        end,
        function(v)
            local ov = Ov()
            if not ov then return end
            -- your target, focus or mouseover carries your debuff; you or your pet a buff
            ov.unit = v
            ov.auraType = (v == "player" or v == "pet") and "buff" or "debuff"
            Dirty()
        end,
        function()
            local out = {}
            for _, u in ipairs(CO.AURA_UNITS) do out[#out + 1] = { value = u, text = CO.AURA_UNIT_WORDS[u] } end
            return out
        end,
        auraOn)
    AT.RowToggle(pg, "Only your own",
        function() local ov = Ov() return ov ~= nil and ov.caster == "mine" end,
        function(v)
            local ov = Ov()
            if not ov then return end
            ov.caster = v and "mine" or nil
            Dirty()
        end,
        auraOn, "Only your own copy of the aura shows, not another player's.")
    if O.BuildYield then O.BuildYield() end
    AT.Section(pg, "Cooldown on this icon", { visibleFn = vis, side = "R" })
    AT.RowToggle(pg, "Show a cooldown",
        function() local r = Rec() return r ~= nil and r.driver.cdOn == true end,
        function(v)
            local r, E = Rec(), NS.DriverCustom
            if r and E then E.SetDriver(r, "cdOn", v or nil) end
            if O and O.RefreshAll then O.RefreshAll() end
        end,
        vis, "While its timer is idle it shows this spell's cooldown, then its Ready look.")
    local cdRow = AT.RowInput(pg, "Spell ID",
        function()
            local r = Rec()
            return (r and r.driver.cdSpell) and tostring(r.driver.cdSpell) or ""
        end,
        function(v)
            local r, E = Rec(), NS.DriverCustom
            if not (r and E) then return end
            local id = CO.ParseSpell(v)
            if v ~= "" and not id then return end
            E.SetDriver(r, "cdSpell", id)
            AT.LayoutPage(pg)
        end,
        function() local r = Rec() return vis() and r ~= nil and r.driver.cdOn == true end,
        "The spell whose cooldown it shows. Empty: the art's spell.",
        "The art's spell")
    local cdName = cdRow:CreateFontString(nil, "OVERLAY")
    cdName:SetFont(NS.AT.FONT, 11, "")
    cdName:SetPoint("LEFT", cdRow._colCtrl, "RIGHT", 8, 0)
    cdName:SetPoint("RIGHT", cdRow, "RIGHT", -10, 0)
    cdName:SetJustifyH("LEFT")
    cdName:SetWordWrap(false)
    cdName:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local cdSync = cdRow._sync
    cdRow._sync = function()
        cdSync()
        local r = Rec()
        local sid = r and (r.driver.cdSpell or r.driver.spellID)
        cdName:SetText(sid and CO.SpellName(sid) or "")
    end
end

-- Every custom item, for the "another item's timer ended" pick.
function CO.ChainItems(self)
    local Store = NS.Store
    local out = { { value = 0, text = "Pick an item" } }
    for _, lay in ipairs(Store.Layouts()) do
        for _, m in ipairs(Store.MembersOf(lay)) do
            if m.type == "group" then
                for _, ic in ipairs(Store.IconsOf(m)) do
                    -- a name is the player's: drawn as typed (raw)
                    if ic.kind == "timer" and ic.id ~= self then
                        out[#out + 1] = { value = ic.id, text = Tr("%s (icon)"):format(tostring(ic.name)), raw = true }
                    end
                end
            elseif (m.type == "icon" and m.kind == "timer") or (m.type == "bar" and m.barKind == "timer") then
                if m.id ~= self then
                    out[#out + 1] = { value = m.id, raw = true,
                        text = ((m.type == "bar") and Tr("%s (bar)") or Tr("%s (icon)")):format(tostring(m.name)) }
                end
            end
        end
    end
    return out
end

-- The conditions a rule's edge can name: by category, your class's rows only
-- (and the one already picked, even if it is another's).
function CO.CondItems(r)
    local C, CU = NS.Conditions, NS.DriverCustom
    local out = { { value = "", text = "Pick a condition" } }
    if not (C and C.VOCAB and C.CATEGORIES and CU and CU.CondOK) then return out end
    local cur = r and r.cond
    local class = NS.Store.ClassTag and NS.Store.ClassTag()
    local seen = false
    for _, c in ipairs(C.CATEGORIES) do
        for _, d in ipairs(C.VOCAB) do
            if d.cat == c.id and CU.CondOK(d.key) and (not d.class or d.class == class or d.key == cur) then
                if d.key == cur then seen = true end
                out[#out + 1] = { value = d.key, text = Tr(c.text) .. ": " .. Tr(d.text), raw = true }
            end
        end
    end
    if cur and not seen then
        out[#out + 1] = { value = cur, text = Tr("%s (not on this client)"):format(tostring(cur)), raw = true }
    end
    return out
end

-- A rule's spells as typed: its one, or its list.
function CO.RuleSpells(r)
    if not r then return {} end
    if type(r.spellIDs) == "table" and #r.spellIDs > 0 then return r.spellIDs end
    return r.spellID and { r.spellID } or {}
end

-- A choice node (two or more options, retail): its rule can name one.
function CO.IsChoice(nodeID)
    local T = NS.TalentCatalog
    local e = T and nodeID and T.Known(nodeID)
    return type(e) == "table" and type(e.entries) == "table"
end

-- A choice node's options, for the "which choice" row.
function CO.ChoiceItems(nodeID, current)
    local out = { { value = 0, text = "Either choice" } }
    local T = NS.TalentCatalog
    local e = T and nodeID and T.Known(nodeID)
    if type(e) ~= "table" then e = nil end
    local seen = false
    for _, opt in ipairs((e and e.entries) or {}) do
        if opt.entryID == current then seen = true end
        local yours = (e.rank or 0) > 0 and e.activeEntryID == opt.entryID
        -- the game's talent names, already in the client's words
        local nm = tostring(opt.name)
        out[#out + 1] = { value = opt.entryID, text = yours and Tr("%s  (yours)"):format(nm) or nm, raw = true }
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = Tr("Choice %s (not in this tree)"):format(current), raw = true }
    end
    return out
end

-- The talents of your class, for the talent guard.
function CO.TalentItems(current)
    local out = { { value = 0, text = "Any talent build" } }
    local T = NS.TalentCatalog
    local seen = false
    for _, e in ipairs(T and T.All() or {}) do
        if e.nodeID == current then seen = true end
        local name = e.name
        -- a choice node lists its options; the row under it names one
        if type(e.entries) == "table" then
            local names = {}
            for _, opt in ipairs(e.entries) do names[#names + 1] = tostring(opt.name) end
            name = table.concat(names, " / ")
        end
        out[#out + 1] = { value = e.nodeID, raw = true,
            text = ((e.rank or 0) > 0) and Tr("%s  (yours)"):format(name) or name }
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = Tr("Talent %s (not in this tree)"):format(current), raw = true }
    end
    return out
end

-- Your class's specs, for the "spec" guard (retail only: WoW Forever has none).
function CO.SpecItems(current)
    local out = { { value = 0, text = "Any spec" } }
    local SI = C_SpecializationInfo
    local n = (NS.IsForever ~= true and SI and SI.GetSpecializationInfo and GetNumSpecializations
        and GetNumSpecializations()) or 0
    local seen = false
    for i = 1, n do
        local id, name = SI.GetSpecializationInfo(i)
        if type(id) == "number" and id > 0 then
            if id == current then seen = true end
            out[#out + 1] = { value = id, raw = true,
                text = (type(name) == "string" and name ~= "") and name or Tr("Spec %s"):format(id) }
        end
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = Tr("Spec %s (another class)"):format(current), raw = true }
    end
    return out
end

-- The rule editor: one titled section per rule, Schema.CUSTOM_MAX_RULES slots
-- built ahead and shown while that rule exists; every edit goes through the
-- engine and re-lays the page at once. opts (a Sound item's editor): groups,
-- actions and section, the empty line, noTimer (no timer or stacks guards),
-- noGuards(r) / actionsFor(r) / soundItems(r) per rule, and triggerRows /
-- actRows(pg, i, api) for rows of its own under the trigger and the action.
function CO.RuleRows(pg, Rec, vis, owner, isBar, opts)
    local AT, S = NS.AT, NS.Schema
    local COL = AT.COL
    opts = opts or {}
    local function CU() return NS.DriverCustom end
    local function Rules()
        local r, E = Rec(), CU()
        return (r and E) and (E.Rules(r) or {}) or {}
    end
    local function Rule(i) return Rules()[i] end
    local function Edit(fn)
        local r, E = Rec(), CU()
        if r and E then fn(E, r) end
        AT.LayoutPage(pg)
    end
    local function Stamp(row, field, label)
        row._adMeta = { family = isBar and "bar" or "icon", section = opts.section or "custom", field = field,
            def = { label = label }, baseVis = vis }
    end
    local groups = opts.groups or S.CUSTOM_TRIGGER_GROUPS
    local function GroupItems()
        local out = {}
        local E = CU()
        local target = E and E.CUSTOM_TARGET_FEEDBACK
        for _, g in ipairs(groups) do
            out[#out + 1] = { value = g.key, text = g.label }
            -- your attacks on the target sit with your own and your pet's
            if target and g.key == "pet" then
                out[#out + 1] = { value = "target", text = "Your target" }
                target = false
            end
        end
        if target then out[#out + 1] = { value = "target", text = "Your target" } end
        return out
    end
    local function GroupList(key)
        for _, g in ipairs(groups) do
            if g.key == key then return g.list end
        end
        if key == "target" then return S.CUSTOM_TARGET_TRIGGERS end
        return groups[1].list
    end
    local function GroupOf(r)
        local E = CU()
        return (r and E and E.GROUP_OF[r.when]) or "spell"
    end

    AT.Section(pg, "Triggers", { visibleFn = vis })
    AT.RowDesc(pg, "Each rule: when something happens, only if its conditions hold, then what it does.", 20, vis)
    AT.RowDesc(pg, opts.empty or "No rules yet: it shows as active until a rule starts its timer or counts stacks.", 20,
        function() return vis() and #Rules() == 0 end)

    for i = 1, S.CUSTOM_MAX_RULES do
        if Options.BuildYield then Options.BuildYield() end
        local rv = function() return vis() and Rule(i) ~= nil end
        local function Is(field, ...)
            local want = { ... }
            return function()
                local r = Rule(i)
                if not (vis() and r) then return false end
                for _, w in ipairs(want) do
                    if r[field] == w then return true end
                end
                return false
            end
        end
        local function Set(field, value) Edit(function(E, r) E.SetRule(r, i, field, value) end) end
        local key = function()
            local r = Rec()
            return (r and r.id or 0) .. ":" .. i
        end
        local function Gated()
            local r = Rule(i)
            if not r then return false end
            return r.combat ~= nil or r.talent ~= nil or r.spec ~= nil or r.spellReady ~= nil or r.stacksMin ~= nil
                or r.stacksMax ~= nil or r.withinRule ~= nil or r.timer ~= nil or CO.showIf[key()] == true
        end
        -- a rule the game plays (a Sound item's aura rule) takes no guards
        local iv = function() return rv() and not (opts.noGuards and opts.noGuards(Rule(i))) end
        local gv = function() return iv() and Gated() end
        local gtv = function() return gv() and not opts.noTimer end
        local api = { Rule = function() return Rule(i) end, Set = Set, Is = Is, rv = rv, Rec = Rec, Stamp = Stamp,
            i = i }

        AT.Section(pg, Tr("Rule %d"):format(i), { visibleFn = vis })
        local grpRow = AT.RowDropdown(pg, owner, "Trigger group",
            function() return GroupOf(Rule(i)) end,
            function(v)
                local r = Rule(i)
                if r and GroupOf(r) ~= v then Set("when", GroupList(v)[1]) end
            end,
            GroupItems, rv)
        local whenRow = AT.RowDropdown(pg, owner, "When",
            function()
                local r = Rule(i)
                return r and r.when or "cast"
            end,
            function(v) Set("when", v) end,
            function()
                local out = {}
                for _, k in ipairs(GroupList(GroupOf(Rule(i)))) do
                    out[#out + 1] = { value = k, text = S.CUSTOM_TRIGGER_LABELS[k] or k }
                end
                return out
            end,
            rv)
        local spellVis = function()
            local r, E = Rule(i), CU()
            return vis() and r ~= nil and E ~= nil and E.SPELL_TRIGGERS[r.when] == true
        end
        if Options.BuildYield then Options.BuildYield() end
        local idRow = AT.RowInput(pg, "Spell IDs",
            function()
                local t = {}
                for _, v in ipairs(CO.RuleSpells(Rule(i))) do t[#t + 1] = tostring(v) end
                return table.concat(t, ", ")
            end,
            function(v)
                local ids, seen = {}, {}
                for part in tostring(v or ""):gmatch("[^,]+") do
                    if Trim(part) ~= "" then
                        local id = CO.ParseSpell(part)
                        -- an entry that names no spell changes nothing
                        if not id then return end
                        if not seen[id] and #ids < (S.CUSTOM_RULE_MAX_SPELLS or 13) then
                            seen[id] = true
                            ids[#ids + 1] = id
                        end
                    end
                end
                Edit(function(E, r)
                    E.SetRule(r, i, "spellID", ids[1])
                    E.SetRule(r, i, "spellIDs", (#ids > 1) and ids or nil)
                end)
            end,
            spellVis, "The spells it watches (any spell but these: the ones it skips), comma separated: IDs, links or names. Any rank.",
            "e.g. 6572")
        local nameFS = idRow:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont(NS.AT.FONT, 11, "")
        nameFS:SetPoint("LEFT", idRow._colCtrl, "RIGHT", 8, 0)
        nameFS:SetPoint("RIGHT", idRow, "RIGHT", -10, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local idSync = idRow._sync
        idRow._sync = function()
            idSync()
            local r = Rule(i)
            local nm = r and CO.SpellName(r.spellID) or ""
            local n = #CO.RuleSpells(r)
            if n > 1 then nm = nm .. ((nm ~= "") and " " or "") .. Tr("+ %d more"):format(n - 1) end
            nameFS:SetText(nm)
        end
        AT.RowDesc(pg, "Fires each time the game updates this spell's cooldown, and for some buffs as they come and go.",
            20, Is("when", "spell_update"))
        AT.RowToggle(pg, "Your pet's casts count too",
            function()
                local r = Rule(i)
                return r ~= nil and r.pet == true
            end,
            function(v) Set("pet", v or nil) end,
            Is("when", "cast"), "On: the trigger fires for your pet's casts of the spell as well as yours.")
        local cdRow = AT.RowToggle(pg, "Fire even while on cooldown",
            function()
                local r = Rule(i)
                return r ~= nil and r.ignoreCooldown == true
            end,
            function(v) Set("ignoreCooldown", v or nil) end,
            Is("when", "usable_on", "usable_off"),
            "On: the spell's own requirement decides (a proc, enough mana), even on cooldown. Off: only when it can be cast now.")
        if Options.BuildYield then Options.BuildYield() end
        AT.RowDropdown(pg, owner, "Totem slot",
            function()
                local r = Rule(i)
                return (r and r.slot) or 0
            end,
            function(v) Set("slot", (v ~= 0) and v or nil) end,
            function()
                local out = { { value = 0, text = "Any slot" } }
                for _, it in ipairs(Options.TotemSlotItems()) do out[#out + 1] = it end
                return out
            end,
            Is("when", "totem_placed", "totem_gone"))
        AT.RowDropdown(pg, owner, "Item",
            function()
                local r = Rule(i)
                return (r and r.srcId) or 0
            end,
            function(v) Set("srcId", (v ~= 0) and v or nil) end,
            function()
                local r = Rec()
                return CO.ChainItems(r and r.id)
            end,
            Is("when", "chain"))
        local condRow = AT.RowDropdown(pg, owner, "Condition",
            function()
                local r = Rule(i)
                return (r and r.cond) or ""
            end,
            function(v) Set("cond", (type(v) == "string" and v ~= "") and v or nil) end,
            function() return CO.CondItems(Rule(i)) end,
            Is("when", "cond_on", "cond_off"))
        if opts.triggerRows then opts.triggerRows(pg, i, api) end

        -- the guards, behind one switch: off drops them all
        if Options.BuildYield then Options.BuildYield() end
        local ifRow = AT.RowToggle(pg, "Only if",
            Gated,
            function(v)
                CO.showIf[key()] = v or nil
                if not v then
                    Edit(function(E, r)
                        for _, f in ipairs({ "combat", "talent", "spec", "spellReady", "stacksMin", "stacksMax",
                            "withinRule", "timer" }) do
                            E.SetRule(r, i, f, nil)
                        end
                    end)
                end
                AT.LayoutPage(pg)
            end,
            iv, "On: the rule fires only while the conditions below hold. Off drops them.")
        AT.RowDropdown(pg, owner, "Combat",
            function()
                local r = Rule(i)
                return (r and r.combat) or "any"
            end,
            function(v) Set("combat", (v ~= "any") and v or nil) end,
            Items(S.CUSTOM_COMBAT, S.CUSTOM_COMBAT_LABELS), gv)
        -- the talent, picked on the Load Conditions talent tree: a choice
        -- node's option is its own button, a second click is Not taken
        Options.TalentPickRow(pg, "Talent", function()
            local rec, E = Rec(), CU()
            if not (rec and E) then return nil end
            local function R() return (E.Rules(rec) or {})[i] end
            local function W(field, value)
                E.SetRule(rec, i, field, value)
                AT.LayoutPage(pg)
            end
            return {
                talentTarget = true,
                State = function(node)
                    local r = R()
                    if not (r and r.talent == node) then return nil end
                    return r.talentNot and "not" or "req", r.talentEntry
                end,
                Set = function(node, state, entry)
                    local r = R()
                    if not r then return end
                    if state == nil then
                        if r.talent == node then W("talent", nil) end
                        return
                    end
                    if r.talent ~= node then W("talent", node) end
                    W("talentEntry", entry)
                    W("talentNot", (state == "not") or nil)
                end,
                List = function()
                    local r = R()
                    if not (r and r.talent) then return {} end
                    return { { nodeID = r.talent, excluded = r.talentNot == true } }
                end,
                Clear = function()
                    local r = R()
                    if r and r.talent then W("talent", nil) end
                end,
            }
        end, gv, "Opens the talent tree: click a talent for this rule, again for Not taken.")
        if Options.BuildYield then Options.BuildYield() end
        AT.RowDropdown(pg, owner, "Talent is",
            function()
                local r = Rule(i)
                return (r and r.talentNot) and "not" or "taken"
            end,
            function(v) Set("talentNot", (v == "not") or nil) end,
            function() return { { value = "taken", text = "Taken" }, { value = "not", text = "Not taken" } } end,
            function()
                local r = Rule(i)
                return gv() and r.talent ~= nil
            end)
        AT.RowDropdown(pg, owner, "Spec",
            function()
                local r = Rule(i)
                return (r and r.spec) or 0
            end,
            function(v) Set("spec", (v ~= 0) and v or nil) end,
            function()
                local r = Rule(i)
                return CO.SpecItems(r and r.spec)
            end,
            function() return gv() and NS.IsForever ~= true end)
        AT.RowInput(pg, "Spell is ready",
            function()
                local r = Rule(i)
                return (r and r.spellReady) and tostring(r.spellReady) or ""
            end,
            function(v)
                local id = CO.ParseSpell(v)
                if v ~= "" and not id then return end
                Set("spellReady", id)
            end,
            gv, "The rule fires only while this spell is off its cooldown (the GCD never counts). Empty = no such condition.",
            "Any spell ID")
        if Options.BuildYield then Options.BuildYield() end
        AT.RowInput(pg, "Stacks at least",
            function()
                local r = Rule(i)
                return (r and r.stacksMin) and tostring(r.stacksMin) or ""
            end,
            function(v)
                local n = tonumber(v)
                if v == "" then Set("stacksMin", nil) return end
                if n and n >= 0 then Set("stacksMin", math.floor(math.min(999, n))) end
            end,
            gtv, "The item's own stacks, before this rule acts. Empty = no such condition.", "Any")
        AT.RowInput(pg, "Stacks at most",
            function()
                local r = Rule(i)
                return (r and r.stacksMax) and tostring(r.stacksMax) or ""
            end,
            function(v)
                local n = tonumber(v)
                if v == "" then Set("stacksMax", nil) return end
                if n and n >= 0 then Set("stacksMax", math.floor(math.min(999, n))) end
            end,
            gtv, "The item's own stacks, before this rule acts. Empty = no such condition.", "Any")
        -- a negative value is the same rule with "did not fire" (withinNot)
        AT.RowDropdown(pg, owner, "Within seconds after rule",
            function()
                local r = Rule(i)
                if not (r and r.withinRule) then return 0 end
                return r.withinNot and -r.withinRule or r.withinRule
            end,
            function(v)
                Set("withinRule", (v ~= 0) and math.abs(v) or nil)
                if v ~= 0 then Set("withinNot", (v < 0) or nil) end
            end,
            function()
                local out = { { value = 0, text = "No such condition" } }
                for k = 1, #Rules() do
                    if k ~= i then out[#out + 1] = { value = k, text = Tr("Rule %d"):format(k) } end
                end
                for k = 1, #Rules() do
                    if k ~= i then out[#out + 1] = { value = -k, text = Tr("Not after rule %d"):format(k) } end
                end
                return out
            end,
            gv)
        AT.RowInput(pg, "Within seconds",
            function()
                local r = Rule(i)
                return ("%g"):format(tonumber(r and r.withinSecs) or 1)
            end,
            function(v)
                local n = tonumber(v)
                if n and n > 0 then Set("withinSecs", math.max(0.1, math.min(600, n))) end
            end,
            function()
                local r = Rule(i)
                return gv() and r.withinRule ~= nil
            end,
            "How long after that rule last fired this one may fire (Not after: may not fire). Enter applies it.")
        AT.RowDropdown(pg, owner, "Timer",
            function()
                local r = Rule(i)
                return (r and r.timer) or "any"
            end,
            function(v) Set("timer", (v ~= "any") and v or nil) end,
            Items(S.CUSTOM_TIMER_STATES, S.CUSTOM_TIMER_STATE_LABELS), gtv)

        if Options.BuildYield then Options.BuildYield() end
        local thenRow = AT.RowDropdown(pg, owner, "Then",
            function()
                local r = Rule(i)
                return (r and r.act) or "start"
            end,
            function(v) Set("act", v) end,
            opts.actionsFor and function() return opts.actionsFor(Rule(i)) end
                or Items(opts.actions or S.CUSTOM_ACTIONS, S.CUSTOM_ACTION_LABELS), rv)
        AT.RowInput(pg, "Seconds (0 = the default)",
            function()
                local r = Rule(i)
                return ("%g"):format(tonumber(r and r.secs) or 0)
            end,
            function(v)
                local n = tonumber(v)
                if n and n >= 0 then Set("secs", (n > 0) and math.min(S.CUSTOM_MAX_SECONDS or 7200, n) or nil) end
            end,
            function()
                local r, rec = Rule(i), Rec()
                if not (rv() and r) then return false end
                local timed = rec ~= nil and rec.driver.stackTimers == true
                return r.act == "start" or (r.act == "add" and (r.restartToo == true or timed))
                    or (r.act == "set" and timed)
            end,
            "How long the timer runs, or an added stack lasts; 0 takes the item's Default seconds. Decimals work (1.5). Enter applies it.")
        AT.RowDropdown(pg, owner, "Start mode",
            function()
                local r = Rule(i)
                return (r and r.mode) or "restart"
            end,
            function(v) Set("mode", (v ~= "restart") and v or nil) end,
            Items(S.CUSTOM_START_MODES, S.CUSTOM_START_MODE_LABELS), Is("act", "start"))
        -- unset, the engine adds or removes 1 and sets 0: the row says so,
        -- and a set takes a typed 0 (stored as unset)
        AT.RowInput(pg, "How many",
            function()
                local r = Rule(i)
                return tostring(tonumber(r and r.n) or ((r and r.act == "set") and 0 or 1))
            end,
            function(v)
                local r = Rule(i)
                local n = tonumber(v)
                if not (r and n) then return end
                n = math.floor(math.min(999, n))
                if n >= 1 then
                    Set("n", n)
                elseif n == 0 and r.act == "set" then
                    Set("n", nil)
                end
            end,
            Is("act", "add", "remove", "set"), "Stacks to add, remove or set (set takes 0). Enter applies it.")
        if Options.BuildYield then Options.BuildYield() end
        AT.RowToggle(pg, "Restart the timer too",
            function()
                local r = Rule(i)
                return r ~= nil and r.restartToo == true
            end,
            function(v) Set("restartToo", v or nil) end,
            Is("act", "add"), "On: adding stacks also starts the timer over, with the seconds below.")
        local srow = AT.RowDropdown(pg, owner, "Sound",
            function()
                local r = Rule(i)
                return (r and r.sound) or ""
            end,
            function(v) Set("sound", (type(v) == "string" and v ~= "") and v or nil) end,
            function()
                if opts.soundItems then return opts.soundItems(Rule(i)) end
                if NS.Sounds then return NS.Sounds.Items() end
                return { { value = "", text = "None" } }
            end,
            Is("act", "sound"))
        local play = AT.MakeSmallButton(srow, "Play", 52)
        play:SetPoint("LEFT", srow._colCtrl, "RIGHT", 6, 0)
        play:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r, E = Rule(i), CU()
            if not (r and r.sound and E and NS.Sounds) then return end
            NS.Sounds.Preview(r.sound, E.Channel(Rec()))
        end)
        AT.Tooltip(play, "Play", "Hear the chosen sound once.")
        if Options.BuildYield then Options.BuildYield() end
        local trow = AT.RowInput(pg, "Text",
            function()
                local r = Rule(i)
                return (r and r.text) or ""
            end,
            function(v)
                v = Trim(v)
                Set("text", (v ~= "") and CO.Cut(v, 200) or nil)
            end,
            Is("act", "speak"), "Spoken by the game's text to speech, in the voice its options pick.", "What to say")
        local speak = AT.MakeSmallButton(trow, "Speak", 56)
        speak:SetPoint("LEFT", trow._colCtrl, "RIGHT", 6, 0)
        speak:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r, E = Rule(i), CU()
            if r and E then E.Speak(r.text) end
        end)
        AT.Tooltip(speak, "Speak", "Hear the text once.")
        if opts.actRows then opts.actRows(pg, i, api) end
        AT.RowActions(pg, {
            { label = "Move up", w = 80, quiet = true,
              onClick = function() Edit(function(E, r) E.MoveRule(r, i, -1) end) end,
              visibleFn = function() return i > 1 end },
            { label = "Move down", w = 90, quiet = true,
              onClick = function() Edit(function(E, r) E.MoveRule(r, i, 1) end) end,
              visibleFn = function() return i < #Rules() end },
            { label = "Remove", w = 80, quiet = true,
              onClick = function() Edit(function(E, r) E.RemoveRule(r, i) end) end },
        }, "left", rv)
        if i == 1 then
            Stamp(grpRow, "ruleGroup", "Trigger group")
            Stamp(whenRow, "ruleWhen", "When")
            Stamp(cdRow, "ruleUsableCd", "Fire even while on cooldown")
            Stamp(ifRow, "ruleIf", "Only if")
            Stamp(condRow, "ruleCond", "Condition")
            Stamp(thenRow, "ruleThen", "Then")
        end
    end
    AT.Section(pg, nil, { visibleFn = vis })
    local add = AT.RowActions(pg, {
        { label = "+ Add rule", w = 100,
          onClick = function() Edit(function(E, r) E.AddRule(r) end) end },
    }, "left", function() return vis() and #Rules() < S.CUSTOM_MAX_RULES end)
    Stamp(add, "ruleAdd", "+ Add rule")
end

-- A Custom Icon's Tracking tab in four sub-tabs (the icon editor's panes):
-- Rules, each rule one sentence that opens as When / Only if / Then; Timer
-- and active; Icon; On the icon. Custom Bars keep TrackRows and RuleRows.

-- Each trigger as the start of a sentence; %s: its spells, item or condition.
CO.WHEN_WORDS = {
    cast = "When you cast %s", cast_except = "When you cast any spell but %s",
    cd_start = "When the cooldown of %s starts", cd_end = "When the cooldown of %s ends",
    spell_update = "When the game updates %s", usable_on = "When %s becomes usable",
    usable_off = "When %s stops being usable", proc_on = "When the proc glow of %s starts",
    proc_off = "When the proc glow of %s ends",
    dodge = "When you dodge", parry = "When you parry", block = "When you block", miss = "When an attack misses you",
    hit = "When you are hit", crit = "When you take a critical hit", absorb = "When you absorb an attack",
    resist = "When you resist a spell", immune = "When you are immune",
    avoided = "When you evade, deflect or reflect",
    pet_dodge = "When your pet dodges", pet_parry = "When your pet parries", pet_block = "When your pet blocks",
    pet_hit = "When your pet is hit", pet_crit = "When your pet takes a critical hit",
    extra_attacks = "When you gain extra attacks", reactive = "When a reactive ability lights up",
    health_low = "When your health is low", mana_low = "When your mana is low",
    combo_points = "When your combo points change", interrupted = "When your cast is interrupted",
    energize = "When you gain a resource", healed = "When you are healed", heal_crit = "When you take a critical heal",
    combat_start = "When you enter combat", combat_end = "When you leave combat",
    target_changed = "When your target changes", target_died = "When your target dies",
    totem_placed = "When a totem is placed", totem_gone = "When a totem is gone",
    ended = "When this timer ends", chain = "When the timer of %s ends",
    target_dodge = "When your attack is dodged", target_parry = "When your attack is parried",
    target_block = "When your attack is blocked", target_miss = "When your attack misses",
    target_hit = "When you hit the target", target_crit = "When you crit the target",
    cond_on = "When %s turns on", cond_off = "When %s turns off",
}
-- what a %s reads with nothing picked yet
CO.WHEN_EMPTY = { chain = "another item", cond_on = "a condition", cond_off = "a condition" }

local function Lit(s) return "|cff" .. NS.AT.Hex(NS.AT.COL.arc) .. s .. "|r" end
local function SpellWord(id)
    local nm = CO.SpellName(id)
    return (nm ~= "") and nm or tostring(id)
end

-- a rule's spells by name: one, two, or the first and how many more
function CO.SpellList(r)
    local ids = CO.RuleSpells(r)
    if #ids == 0 then return nil end
    if #ids == 1 then return SpellWord(ids[1]) end
    if #ids == 2 then return SpellWord(ids[1]) .. ", " .. SpellWord(ids[2]) end
    return Tr("%s + %d more"):format(SpellWord(ids[1]), #ids - 1)
end

-- what the trigger's %s names: the spells, the other item, the condition
function CO.WhenSubject(r)
    if r.when == "chain" then
        local it = r.srcId and NS.Store.Get(r.srcId)
        return it and tostring(it.name) or nil
    end
    if r.when == "cond_on" or r.when == "cond_off" then
        local C = NS.Conditions
        for _, d in ipairs((C and C.VOCAB) or {}) do
            if d.key == r.cond then return Tr(d.text) end
        end
        return nil
    end
    return CO.SpellList(r)
end

-- the conditions a rule waits on, each a few words
function CO.GuardWords(r)
    local out = {}
    if r.timer == "idle" then out[#out + 1] = Tr("if the timer is not running")
    elseif r.timer == "running" then out[#out + 1] = Tr("if the timer is running") end
    if r.combat == "in" then out[#out + 1] = Tr("in combat")
    elseif r.combat == "out" then out[#out + 1] = Tr("out of combat") end
    if r.talent then
        local nm = Options.TalentPickName and Options.TalentPickName(r.talent, r.talentEntry)
        nm = (nm and nm ~= "") and nm or Tr("Talent %s"):format(r.talent)
        out[#out + 1] = (r.talentNot and Tr("without %s") or Tr("with %s")):format(Lit(nm))
    end
    if r.spec then
        local _, nm = GetSpecializationInfoByID and GetSpecializationInfoByID(r.spec)
        out[#out + 1] = Tr("as %s"):format(Lit(type(nm) == "string" and nm or tostring(r.spec)))
    end
    if r.spellReady then out[#out + 1] = Tr("while %s is ready"):format(Lit(SpellWord(r.spellReady))) end
    if r.stacksMin then out[#out + 1] = Tr("at %d or more stacks"):format(r.stacksMin) end
    if r.stacksMax then out[#out + 1] = Tr("at %d or fewer stacks"):format(r.stacksMax) end
    if r.withinRule then
        local secs = ("%g"):format(tonumber(r.withinSecs) or 1)
        out[#out + 1] = (r.withinNot and Tr("not within %s s of rule %d") or Tr("within %s s of rule %d"))
            :format(secs, r.withinRule)
    end
    return out
end

-- what it does: its verb (lit) and the rest
function CO.ThenWords(r, rec)
    local act = r.act or "start"
    local n = tonumber(r.n)
    if act == "start" then
        local secs = tonumber(r.secs) or (rec and tonumber(rec.driver.duration))
        local rest = secs and Tr("for %s s"):format(("%g"):format(secs)) or ""
        if r.mode == "extend" then
            rest = rest .. Tr(", or add the time if it runs")
        elseif r.mode == "idle" and r.timer ~= "idle" then
            rest = rest .. Tr(", unless it runs")
        end
        return Tr("start the timer"), rest
    end
    if act == "stop" then return Tr("stop the timer"), "" end
    if act == "add" then
        n = n or 1
        return (n == 1 and Tr("add %d stack") or Tr("add %d stacks")):format(n),
            (r.restartToo and Tr("and restart the timer") or "")
    end
    if act == "remove" then
        n = n or 1
        return (n == 1 and Tr("remove %d stack") or Tr("remove %d stacks")):format(n), ""
    end
    if act == "set" then return Tr("set the stacks to %d"):format(n or 0), "" end
    if act == "reset" then return Tr("reset the timer and stacks"), "" end
    if act == "sound" then return Tr("play a sound"), "" end
    if act == "speak" then
        return Tr("speak"), (r.text and r.text ~= "") and ("\"" .. r.text .. "\"") or ""
    end
    return Tr(NS.Schema.CUSTOM_ACTION_LABELS[act] or act), ""
end

-- The rule as one sentence: "When you cast Ghost Wolf, if the timer is not
-- running: start the timer for 20 s."
function CO.RuleSentence(r, rec)
    local fmt = CO.WHEN_WORDS[r.when]
    local when
    if not fmt then
        when = Tr(NS.Schema.CUSTOM_TRIGGER_LABELS[r.when] or tostring(r.when))
    elseif fmt:find("%%s") then
        local subj = CO.WhenSubject(r)
        when = Tr(fmt):format(subj and Lit(subj) or Tr(CO.WHEN_EMPTY[r.when] or "a spell"))
    else
        when = Tr(fmt)
    end
    if r.slot and (r.when == "totem_placed" or r.when == "totem_gone") then
        when = when .. " " .. Tr("(slot %d)"):format(r.slot)
    end
    local guards = CO.GuardWords(r)
    local verb, rest = CO.ThenWords(r, rec)
    local s = when
    if #guards > 0 then s = s .. ", " .. table.concat(guards, ", ") end
    s = s .. ": " .. Lit(verb)
    if rest ~= "" then s = s .. ((rest:sub(1, 1) == ",") and "" or " ") .. rest end
    return s .. "."
end

-- Which rule is open in the editor, per icon, and the conditions added to a
-- rule but not set yet: both for this session only.
CO.open = {}
CO.added = {}

-- A small sunken text box (the theme's RowInput field) for the rule boxes.
function CO.MiniBox(parent, get, set, hint)
    local AT, COL = NS.AT, NS.AT.COL
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetHeight(18)
    AT.Skin(box, COL.well)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    local hintFS = box:CreateFontString(nil, "OVERLAY")
    hintFS:SetFont(AT.FONT, 11, "")
    hintFS:SetPoint("LEFT", 6, 0)
    hintFS:SetPoint("RIGHT", -6, 0)
    hintFS:SetJustifyH("LEFT")
    hintFS:SetWordWrap(false)
    hintFS:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    local function Hint()
        hintFS:SetText(hint and Tr(hint) or "")
        hintFS:SetShown((box:GetText() or "") == "")
    end
    box:SetScript("OnTextChanged", Hint)
    local function commit()
        set(box:GetText() or "")
        AT.BoxText(box, get() or "")
        Hint()
    end
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function() AT.BoxText(box, get() or "") box:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
    box:SetScript("OnEditFocusLost", function()
        commit()
        box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
    end)
    box.Refresh = function()
        if not box:HasFocus() then AT.BoxText(box, get() or "") end
        Hint()
    end
    box.Refresh()
    return box
end

-- The Rules pane: one box, a line per rule, the open rule's three boxes
-- under its line, + Add rule at the end.
CO.BLOCK_GAP, CO.EDIT_INSET, CO.MINI_H, CO.BLOCK_HEAD = 10, 30, 26, 22
CO.BLOCK_SHARE = { 1.3, 1, 1.2 }
function CO.RuleSentences(pg, Rec, vis, owner)
    local AT, S = NS.AT, NS.Schema
    local COL = AT.COL
    local function CU() return NS.DriverCustom end
    local function Rules()
        local r, E = Rec(), CU()
        return (r and E) and (E.Rules(r) or {}) or {}
    end
    local function Rule(i) return Rules()[i] end
    local function Edit(fn)
        local r, E = Rec(), CU()
        if r and E then fn(E, r) end
        AT.LayoutPage(pg)
    end
    local function OpenIdx()
        local r = Rec()
        return r and CO.open[r.id] or nil
    end
    local function SetOpen(i)
        local r = Rec()
        if r then CO.open[r.id] = i end
        AT.CloseDropdown()
        AT.LayoutPage(pg)
    end
    -- the page's width before its first layout, from the page itself
    local function RowW(row)
        local w = row:GetWidth() or 0
        if w < 60 then
            w = (pg:GetWidth() or 0) - 8
            if w < 60 then
                pg._sizeUnresolved = true
                w = 760
            end
        end
        return w
    end

    AT.Section(pg, "What starts and stops it", { visibleFn = vis })
    AT.RowDesc(pg, "No rules yet: it shows as active until a rule starts its timer or counts stacks.", 20,
        function() return vis() and #Rules() == 0 end)

    for i = 1, S.CUSTOM_MAX_RULES do
        if Options.BuildYield then Options.BuildYield() end
        local rv = function() return vis() and Rule(i) ~= nil end
        local function Set(field, value) Edit(function(E, r) E.SetRule(r, i, field, value) end) end
        local function Toggle()
            if OpenIdx() == i then SetOpen(nil) else SetOpen(i) end
        end

        -- the line: number, sentence, Edit / Done, the moves, Remove
        local line = AT.AddRow(pg, 30, rv)
        local badge = CreateFrame("Frame", nil, line, "BackdropTemplate")
        badge:SetSize(20, 20)
        badge:SetPoint("LEFT", 12, 0)
        AT.Skin(badge, COL.btn, COL.line2)
        local num = badge:CreateFontString(nil, "OVERLAY")
        num:SetFont(AT.FONT, 11, "")
        num:SetPoint("CENTER", 0, 0)
        num:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
        num:SetText(tostring(i))
        local words = line:CreateFontString(nil, "OVERLAY")
        words:SetFont(AT.FONT, 12, "")
        words:SetJustifyH("LEFT")
        words:SetWordWrap(true)
        words:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        words:SetPoint("LEFT", badge, "RIGHT", 8, 0)
        local rm = AT.MakeQuietButton(line, "Remove", 70)
        local ed = AT.MakeSmallButton(line, "Edit", 56)
        local dn = AT.MakeQuietButton(line, "Move down", 86)
        local up = AT.MakeQuietButton(line, "Move up", 74)
        rm:SetScript("OnClick", function()
            AT.CloseDropdown()
            local r = Rec()
            if r and CO.open[r.id] == i then CO.open[r.id] = nil end
            Edit(function(E, rec) E.RemoveRule(rec, i) end)
        end)
        ed:SetScript("OnClick", Toggle)
        up:SetScript("OnClick", function()
            Edit(function(E, r) E.MoveRule(r, i, -1) end)
            local r = Rec()
            if r and CO.open[r.id] == i then SetOpen(i - 1) end
        end)
        dn:SetScript("OnClick", function()
            Edit(function(E, r) E.MoveRule(r, i, 1) end)
            local r = Rec()
            if r and CO.open[r.id] == i then SetOpen(i + 1) end
        end)
        line:EnableMouse(true)
        line:SetScript("OnMouseUp", Toggle)
        AT.Tooltip(line, "Rule", "Click it, or Edit, to change it.")
        line._adWords = words
        line._sync = function()
            local r = Rule(i)
            if not r then return end
            words:SetText(CO.RuleSentence(r, Rec()))
            ed:SetLabel((OpenIdx() == i) and "Done" or "Edit", 56)
            local n = #Rules()
            up:SetShown(i > 1)
            dn:SetShown(i < n)
            rm:ClearAllPoints()
            rm:SetPoint("RIGHT", -12, 0)
            local left = rm
            for _, b in ipairs({ ed, dn, up }) do
                if b:IsShown() then
                    b:ClearAllPoints()
                    b:SetPoint("RIGHT", left, "LEFT", -6, 0)
                    left = b
                end
            end
            words:ClearAllPoints()
            words:SetPoint("LEFT", badge, "RIGHT", 8, 0)
            words:SetPoint("RIGHT", left, "LEFT", -10, 0)
            -- a long sentence wraps and the line grows with it
            local room = RowW(line) - 12 - 20 - 8 - 10 - 12
            for _, b in ipairs({ rm, ed, dn, up }) do
                if b:IsShown() then room = room - (b:GetWidth() or 0) - 6 end
            end
            words:SetWidth(math.max(80, room))
            local want = math.max(30, math.floor((words:GetStringHeight() or 14) + 14.5))
            if line._h ~= want then line._h = want line:SetHeight(want) end
        end

        -- the open rule's three boxes
        local edVis = function() return rv() and OpenIdx() == i end
        local editor = AT.AddRow(pg, 120, edVis)
        line._adEditor = editor
        local blocks = {}
        local function Block(title)
            local b = CreateFrame("Frame", nil, editor, "BackdropTemplate")
            AT.Skin(b, COL.well, COL.line2)
            local hd = CreateFrame("Frame", nil, b, "BackdropTemplate")
            hd:SetPoint("TOPLEFT", 1, -1)
            hd:SetPoint("TOPRIGHT", -1, -1)
            hd:SetHeight(CO.BLOCK_HEAD)
            AT.Skin(hd, COL.btn)
            local t = hd:CreateFontString(nil, "OVERLAY")
            t:SetFont(AT.FONT, 10, "")
            t:SetPoint("LEFT", 8, 0)
            t:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
            t:SetText(Tr(title):upper())
            b._title, b.rows = t, {}
            blocks[#blocks + 1] = b
            return b
        end
        -- a row in a box: label, then the control filling the rest; vis(r)
        local function Mini(b, label, lw, vis2, make)
            -- the panel builds in slices: each box row is one
            if Options.BuildYield then Options.BuildYield() end
            local m = CreateFrame("Frame", nil, b)
            m:SetHeight(CO.MINI_H)
            local fs = m:CreateFontString(nil, "OVERLAY")
            fs:SetFont(AT.FONT, 11, "")
            fs:SetPoint("LEFT", 8, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
            if label then fs:SetText(Tr(label)) end
            m._label, m._lw, m._vis = fs, lw, vis2
            m._ctrl = make(m)
            b.rows[#b.rows + 1] = m
            return m
        end
        local function DD(itemsFn, get, set)
            return function(m)
                local dd = AT.MakeDropdown(owner, m, 100, itemsFn, get, set)
                m._fill = dd
                m._refresh = dd.Refresh
                return dd
            end
        end
        local function Box(get, set, hint)
            return function(m)
                local box = CO.MiniBox(m, get, set, hint)
                m._fill = box
                m._refresh = box.Refresh
                return box
            end
        end
        local function Check(get, set)
            return function(m)
                local cb = AT.MakeCheckbox(m)
                cb:SetScript("OnClick", function() set(not get()) cb:SetOn(get()) end)
                m._refresh = function() cb:SetOn(get()) end
                return cb
            end
        end
        local function Is(field, ...)
            local want = { ... }
            return function(r)
                for _, w in ipairs(want) do
                    if r[field] == w then return true end
                end
                return false
            end
        end
        local function Always() return true end

        -- WHEN
        local groups = S.CUSTOM_TRIGGER_GROUPS
        local function GroupOf(r)
            local E = CU()
            return (r and E and E.GROUP_OF[r.when]) or "spell"
        end
        local function GroupList(key)
            for _, g in ipairs(groups) do
                if g.key == key then return g.list end
            end
            if key == "target" then return S.CUSTOM_TARGET_TRIGGERS end
            return groups[1].list
        end
        local wb = Block("When")
        Mini(wb, "Group", 46, Always, DD(function()
            local out = {}
            local E = CU()
            local target = E and E.CUSTOM_TARGET_FEEDBACK
            for _, g in ipairs(groups) do
                out[#out + 1] = { value = g.key, text = g.label }
                if target and g.key == "pet" then
                    out[#out + 1] = { value = "target", text = "Your target" }
                    target = false
                end
            end
            if target then out[#out + 1] = { value = "target", text = "Your target" } end
            return out
        end, function() return GroupOf(Rule(i)) end, function(v)
            local r = Rule(i)
            if r and GroupOf(r) ~= v then Set("when", GroupList(v)[1]) end
        end))
        local whenM = Mini(wb, "When", 46, Always, DD(function()
            local out = {}
            for _, k in ipairs(GroupList(GroupOf(Rule(i)))) do
                out[#out + 1] = { value = k, text = S.CUSTOM_TRIGGER_LABELS[k] or k }
            end
            return out
        end, function() local r = Rule(i) return r and r.when or "cast" end, function(v) Set("when", v) end))
        AT.Tooltip(whenM._ctrl, "When", function()
            local r = Rule(i)
            if r and r.when == "spell_update" then
                return "Fires each time the game updates this spell's cooldown, and for some buffs as they come and go."
            end
            return "What makes this rule fire."
        end)
        local spellM = Mini(wb, "Spells", 46, function(r)
            local E = CU()
            return E ~= nil and E.SPELL_TRIGGERS[r.when] == true
        end, Box(function()
            local t = {}
            for _, v in ipairs(CO.RuleSpells(Rule(i))) do t[#t + 1] = tostring(v) end
            return table.concat(t, ", ")
        end, function(v)
            local ids, seen = {}, {}
            for part in tostring(v or ""):gmatch("[^,]+") do
                if Trim(part) ~= "" then
                    local id = CO.ParseSpell(part)
                    -- an entry that names no spell changes nothing
                    if not id then return end
                    if not seen[id] and #ids < (S.CUSTOM_RULE_MAX_SPELLS or 13) then
                        seen[id] = true
                        ids[#ids + 1] = id
                    end
                end
            end
            Edit(function(E, r)
                E.SetRule(r, i, "spellID", ids[1])
                E.SetRule(r, i, "spellIDs", (#ids > 1) and ids or nil)
            end)
        end, "e.g. 6572"))
        -- the spells' names, dim inside the box's right end
        local spellName = spellM._ctrl:CreateFontString(nil, "OVERLAY")
        spellName:SetFont(AT.FONT, 11, "")
        spellName:SetPoint("RIGHT", -6, 0)
        spellName:SetJustifyH("RIGHT")
        spellName:SetWordWrap(false)
        spellName:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local spellRefresh = spellM._refresh
        spellM._refresh = function()
            spellRefresh()
            local r = Rule(i)
            spellName:SetText((r and not spellM._ctrl:HasFocus() and CO.SpellList(r)) or "")
        end
        AT.Tooltip(spellM._ctrl, "Spells", "The spells it watches, comma separated: IDs, links or names. Any rank.")
        Mini(wb, "Pet's casts too", 110, Is("when", "cast"), Check(function()
            local r = Rule(i)
            return r ~= nil and r.pet == true
        end, function(v) Set("pet", v or nil) end))
        Mini(wb, "On cooldown too", 110, Is("when", "usable_on", "usable_off"), Check(function()
            local r = Rule(i)
            return r ~= nil and r.ignoreCooldown == true
        end, function(v) Set("ignoreCooldown", v or nil) end))
        Mini(wb, "Slot", 46, Is("when", "totem_placed", "totem_gone"), DD(function()
            local out = { { value = 0, text = "Any slot" } }
            for _, it in ipairs(Options.TotemSlotItems()) do out[#out + 1] = it end
            return out
        end, function() local r = Rule(i) return (r and r.slot) or 0 end,
            function(v) Set("slot", (v ~= 0) and v or nil) end))
        Mini(wb, "Item", 46, Is("when", "chain"), DD(function()
            local r = Rec()
            return CO.ChainItems(r and r.id)
        end, function() local r = Rule(i) return (r and r.srcId) or 0 end,
            function(v) Set("srcId", (v ~= 0) and v or nil) end))
        Mini(wb, "Condition", 64, Is("when", "cond_on", "cond_off"), DD(function() return CO.CondItems(Rule(i)) end,
            function() local r = Rule(i) return (r and r.cond) or "" end,
            function(v) Set("cond", (type(v) == "string" and v ~= "") and v or nil) end))

        -- ONLY IF: the conditions that are set, then + Add a condition
        local function key() local r = Rec() return (r and r.id or 0) .. ":" .. i end
        local function Added(g) local a = CO.added[key()] return a ~= nil and a[g] == true end
        local function Drop(g)
            local a = CO.added[key()]
            if a then a[g] = nil end
        end
        local GUARDS = {
            { key = "timer", label = "Timer", items = { { value = "any", text = "Running or not" },
                { value = "running", text = "Running" }, { value = "idle", text = "Not running" } }, neutral = "any" },
            { key = "combat", label = "Combat", items = { { value = "any", text = "In or out" },
                { value = "in", text = "In combat" }, { value = "out", text = "Out of combat" } }, neutral = "any" },
            { key = "talent", label = "Talent" },
            { key = "spec", label = "Spec", retail = true },
            { key = "spellReady", label = "Spell ready", box = true, hint = "Spell ID" },
            { key = "stacksMin", label = "Stacks at least", box = true, num = true },
            { key = "stacksMax", label = "Stacks at most", box = true, num = true },
            { key = "withinRule", label = "After rule" },
        }
        local function GuardOn(g, r) return r[g.key] ~= nil or Added(g.key) end
        local function GuardOK(g) return not (g.retail and NS.IsForever == true) end
        local ob = Block("Only if")
        local GLW = 92
        for _, g in ipairs(GUARDS) do
            local gv = function(r) return GuardOK(g) and GuardOn(g, r) end
            if g.items then
                Mini(ob, g.label, GLW, gv, DD(function() return g.items end,
                    function() local r = Rule(i) return (r and r[g.key]) or g.neutral end,
                    function(v)
                        if v == g.neutral then Drop(g.key) end
                        Set(g.key, (v ~= g.neutral) and v or nil)
                    end))
            elseif g.key == "talent" then
                Mini(ob, g.label, GLW, gv, function(m)
                    local b = AT.MakeSmallButton(m, "Choose talent", 100)
                    m._fill = b
                    b:SetScript("OnClick", function()
                        local rec, E = Rec(), CU()
                        if not (rec and E and Options.OpenTalentPicker) then return end
                        Options.OpenTalentPicker(function()
                            local function R() return (E.Rules(rec) or {})[i] end
                            local function W(field, value)
                                E.SetRule(rec, i, field, value)
                                AT.LayoutPage(pg)
                            end
                            return {
                                talentTarget = true,
                                State = function(node)
                                    local r = R()
                                    if not (r and r.talent == node) then return nil end
                                    return r.talentNot and "not" or "req", r.talentEntry
                                end,
                                Set = function(node, state, entry)
                                    local r = R()
                                    if not r then return end
                                    if state == nil then
                                        if r.talent == node then W("talent", nil) Drop("talent") end
                                        return
                                    end
                                    if r.talent ~= node then W("talent", node) end
                                    W("talentEntry", entry)
                                    W("talentNot", (state == "not") or nil)
                                end,
                                List = function()
                                    local r = R()
                                    if not (r and r.talent) then return {} end
                                    return { { nodeID = r.talent, excluded = r.talentNot == true } }
                                end,
                                Clear = function()
                                    local r = R()
                                    if r and r.talent then W("talent", nil) end
                                    Drop("talent")
                                end,
                            }
                        end)
                    end)
                    m._refresh = function()
                        local r = Rule(i)
                        local nm = r and r.talent and Options.TalentPickName and Options.TalentPickName(r.talent, r.talentEntry)
                        b:SetLabel((nm and nm ~= "") and nm or "Choose talent", 100)
                    end
                    AT.Tooltip(b, "Talent", "Opens the talent tree: click a talent for this rule, again for Not taken.")
                    return b
                end)
            elseif g.key == "spec" then
                Mini(ob, g.label, GLW, gv, DD(function()
                    local r = Rule(i)
                    return CO.SpecItems(r and r.spec)
                end, function() local r = Rule(i) return (r and r.spec) or 0 end,
                    function(v)
                        if v == 0 then Drop("spec") end
                        Set("spec", (v ~= 0) and v or nil)
                    end))
            elseif g.key == "withinRule" then
                Mini(ob, g.label, GLW, gv, DD(function()
                    local out = { { value = 0, text = "Any time" } }
                    for k = 1, #Rules() do
                        if k ~= i then out[#out + 1] = { value = k, text = Tr("Rule %d"):format(k) } end
                    end
                    for k = 1, #Rules() do
                        if k ~= i then out[#out + 1] = { value = -k, text = Tr("Not after rule %d"):format(k) } end
                    end
                    return out
                end, function()
                    local r = Rule(i)
                    if not (r and r.withinRule) then return 0 end
                    return r.withinNot and -r.withinRule or r.withinRule
                end, function(v)
                    if v == 0 then Drop("withinRule") end
                    Set("withinRule", (v ~= 0) and math.abs(v) or nil)
                    if v ~= 0 then Set("withinNot", (v < 0) or nil) end
                end))
                Mini(ob, "Within (s)", GLW, function(r) return GuardOK(g) and r.withinRule ~= nil end, Box(function()
                    local r = Rule(i)
                    return ("%g"):format(tonumber(r and r.withinSecs) or 1)
                end, function(v)
                    local n = tonumber(v)
                    if n and n > 0 then Set("withinSecs", math.max(0.1, math.min(600, n))) end
                end))
            elseif g.box then
                Mini(ob, g.label, GLW, gv, Box(function()
                    local r = Rule(i)
                    return (r and r[g.key]) and tostring(r[g.key]) or ""
                end, function(v)
                    if v == "" then
                        Drop(g.key)
                        Set(g.key, nil)
                        return
                    end
                    if g.num then
                        local n = tonumber(v)
                        if n and n >= 0 then Set(g.key, math.floor(math.min(999, n))) end
                    else
                        local id = CO.ParseSpell(v)
                        if id then Set(g.key, id) end
                    end
                end, g.hint or "Any"))
            end
        end
        Mini(ob, nil, 0, Always, function(m)
            local dd = AT.MakeDropdown(owner, m, 100, function()
                local out = { { value = "", text = "+ Add a condition" } }
                local r = Rule(i)
                for _, g in ipairs(GUARDS) do
                    if r and GuardOK(g) and not GuardOn(g, r) then out[#out + 1] = { value = g.key, text = g.label } end
                end
                return out
            end, function() return "" end, function(v)
                if v == "" then return end
                CO.added[key()] = CO.added[key()] or {}
                CO.added[key()][v] = true
                AT.LayoutPage(pg)
            end)
            dd:SetBackdropBorderColor(CO.ADD_EDGE[1], CO.ADD_EDGE[2], CO.ADD_EDGE[3], 1)
            dd:SetScript("OnLeave", function() dd:SetBackdropBorderColor(CO.ADD_EDGE[1], CO.ADD_EDGE[2], CO.ADD_EDGE[3], 1) end)
            m._fill = dd
            m._refresh = function()
                dd.Refresh()
                dd:SetBackdropBorderColor(CO.ADD_EDGE[1], CO.ADD_EDGE[2], CO.ADD_EDGE[3], 1)
            end
            return dd
        end)

        -- THEN
        local tb = Block("Then")
        Mini(tb, "Do", 64, Always, DD(Items(S.CUSTOM_ACTIONS, S.CUSTOM_ACTION_LABELS),
            function() local r = Rule(i) return (r and r.act) or "start" end, function(v) Set("act", v) end))
        local function Timed(r)
            local rec = Rec()
            local timed = rec ~= nil and rec.driver.stackTimers == true
            return r.act == "start" or r.act == nil or (r.act == "add" and (r.restartToo == true or timed))
                or (r.act == "set" and timed)
        end
        Mini(tb, "Seconds", 64, Timed, Box(function()
            local r = Rule(i)
            local n = tonumber(r and r.secs)
            return n and ("%g"):format(n) or ""
        end, function(v)
            local n = tonumber(v)
            if v == "" then Set("secs", nil) return end
            if n and n >= 0 then Set("secs", (n > 0) and math.min(S.CUSTOM_MAX_SECONDS or 7200, n) or nil) end
        end, "Default"))
        Mini(tb, "If it runs", 64, function(r) return r.act == "start" or r.act == nil end, DD(function()
            return { { value = "restart", text = "Restart it" }, { value = "extend", text = "Add the seconds" },
                { value = "idle", text = "Leave it" } }
        end, function() local r = Rule(i) return (r and r.mode) or "restart" end,
            function(v) Set("mode", (v ~= "restart") and v or nil) end))
        Mini(tb, "How many", 64, Is("act", "add", "remove", "set"), Box(function()
            local r = Rule(i)
            return tostring(tonumber(r and r.n) or ((r and r.act == "set") and 0 or 1))
        end, function(v)
            local r = Rule(i)
            local n = tonumber(v)
            if not (r and n) then return end
            n = math.floor(math.min(999, n))
            if n >= 1 then Set("n", n) elseif n == 0 and r.act == "set" then Set("n", nil) end
        end))
        Mini(tb, "Restart the timer too", 130, Is("act", "add"), Check(function()
            local r = Rule(i)
            return r ~= nil and r.restartToo == true
        end, function(v) Set("restartToo", v or nil) end))
        Mini(tb, "Sound", 64, Is("act", "sound"), function(m)
            local dd = AT.MakeDropdown(owner, m, 100, function()
                if NS.Sounds then return NS.Sounds.Items() end
                return { { value = "", text = "None" } }
            end, function() local r = Rule(i) return (r and r.sound) or "" end,
                function(v) Set("sound", (type(v) == "string" and v ~= "") and v or nil) end)
            local play = AT.MakeSmallButton(m, "Play", 44)
            play:SetScript("OnClick", function()
                AT.CloseDropdown()
                local r, E = Rule(i), CU()
                if r and r.sound and E and NS.Sounds then NS.Sounds.Preview(r.sound, E.Channel(Rec())) end
            end)
            m._fill, m._tail = dd, play
            m._refresh = dd.Refresh
            return dd
        end)
        Mini(tb, "Text", 64, Is("act", "speak"), function(m)
            local box = CO.MiniBox(m, function() local r = Rule(i) return (r and r.text) or "" end, function(v)
                v = Trim(v)
                Set("text", (v ~= "") and CO.Cut(v, 200) or nil)
            end, "What to say")
            local sp = AT.MakeSmallButton(m, "Speak", 52)
            sp:SetScript("OnClick", function()
                AT.CloseDropdown()
                local r, E = Rule(i), CU()
                if r and E then E.Speak(r.text) end
            end)
            m._fill, m._tail = box, sp
            m._refresh = box.Refresh
            return box
        end)

        -- lay the three boxes: widths by share, each as tall as its rows
        editor._adBlocks = blocks
        editor._sync = function()
            local r = Rule(i)
            if not r then return end
            local w = RowW(editor) - CO.EDIT_INSET - 12 - CO.BLOCK_GAP * 2
            local total = 0
            for _, s in ipairs(CO.BLOCK_SHARE) do total = total + s end
            local x, tallest = CO.EDIT_INSET + 12, 0
            for bi, b in ipairs(blocks) do
                local bw = math.floor(w * CO.BLOCK_SHARE[bi] / total)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -4)
                b:SetWidth(bw)
                x = x + bw + CO.BLOCK_GAP
                local y = -(CO.BLOCK_HEAD + 5)
                for _, m in ipairs(b.rows) do
                    local on = m._vis(r) == true
                    m:SetShown(on)
                    if on then
                        if m._refresh then m._refresh() end
                        m:ClearAllPoints()
                        m:SetPoint("TOPLEFT", b, "TOPLEFT", 0, y)
                        m:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, y)
                        local cx = (m._lw > 0) and (8 + m._lw + 6) or 8
                        m._label:SetWidth(math.max(1, m._lw))
                        m._label:SetShown(m._lw > 0)
                        local tail = m._tail and ((m._tail:GetWidth() or 0) + 4) or 0
                        local cw = math.max(40, bw - cx - 8 - tail)
                        local c = m._fill or m._ctrl
                        c:ClearAllPoints()
                        c:SetPoint("LEFT", m, "LEFT", cx, 0)
                        if m._fill then c:SetWidth(cw) end
                        if m._tail then
                            m._tail:ClearAllPoints()
                            m._tail:SetPoint("LEFT", c, "RIGHT", 4, 0)
                        end
                        y = y - CO.MINI_H
                    end
                end
                local bh = -y + 6
                b:SetHeight(bh)
                if bh > tallest then tallest = bh end
            end
            local want = tallest + 10
            if editor._h ~= want then editor._h = want editor:SetHeight(want) end
        end
    end
    -- + Add rule in the panel's add green: a green edge and words on no fill
    local addRow = AT.AddRow(pg, 32, function() return vis() and #Rules() < S.CUSTOM_MAX_RULES end)
    local addB = AT.MakeSmallButton(addRow, "+ Add rule", 100)
    addB:SetPoint("LEFT", 12, 0)
    local function PaintAdd(hot)
        local e = hot and CO.ADD_GREEN or CO.ADD_EDGE
        addB:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], hot and 1 or 0)
        addB:SetBackdropBorderColor(e[1], e[2], e[3], 1)
        addB.fs:SetTextColor(CO.ADD_GREEN[1], CO.ADD_GREEN[2], CO.ADD_GREEN[3])
    end
    PaintAdd(false)
    addB:SetScript("OnEnter", function() PaintAdd(true) end)
    addB:SetScript("OnLeave", function() PaintAdd(false) end)
    addB:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = Rec()
        Edit(function(E, rec) E.AddRule(rec) end)
        -- the new rule opens, ready to fill in
        if r then SetOpen(#Rules()) end
    end)
    AT.Tooltip(addB, "Add rule", "A new rule: when something happens, what it does.")
end
-- the Effects tab's add green (+ Add a trigger)
CO.ADD_GREEN, CO.ADD_EDGE = { 0.482, 0.847, 0.561 }, { 0.243, 0.478, 0.267 }

-- The words for what Effects will list, from Active while and what is on the icon.
function CO.ActiveReadout(r)
    local ET = Options.EditorTabs
    if not (r and ET and ET.ActiveWords) then return "" end
    if ET.NeverInactive(r) then return Tr("Always active: it never goes Not active, On cooldown or Ready.") end
    local names = {}
    -- the warnings are glows of their own, not states the timer makes
    for _, st in ipairs(ET.StatesFor(r) or {}) do
        if st.key ~= "warn" then names[#names + 1] = Tr(ET.StateWord(r, st)) end
    end
    return Tr("Effects lists: %s."):format(table.concat(names, ", "))
end

-- Timer and active: Active while (with what it makes) beside the timer and its stacks.
function CO.TimerPane(pg, Rec, vis, owner)
    local AT, S = NS.AT, NS.Schema
    local function Set(field, value)
        local r, E = Rec(), NS.DriverCustom
        if r and E then E.SetDriver(r, field, value) end
        if Options.RefreshAll then Options.RefreshAll() else AT.LayoutPage(pg) end
    end
    AT.Section(pg, "Active while", { visibleFn = vis, side = "L" })
    local swRow = AT.RowDropdown(pg, owner, "Active while",
        function()
            local r = Rec()
            return (r and r.driver.showWhile) or "timer"
        end,
        function(v) Set("showWhile", (v ~= "timer") and v or nil) end,
        Items(S.CUSTOM_SHOW_WHILE, S.CUSTOM_ACTIVE_WHILE_LABELS or S.CUSTOM_SHOW_WHILE_LABELS), vis)
    CO.activeRow = swRow
    AT.Tooltip(swRow, "Active while", "What makes the icon active. Effects sets a look for each state this makes.")
    -- one line: the states Effects lists, as the setting makes them
    local note = AT.AddRow(pg, 22, vis)
    local nfs = note:CreateFontString(nil, "OVERLAY")
    nfs:SetFont(AT.FONT, 11, "")
    nfs:SetPoint("TOPLEFT", 10, -3)
    nfs:SetJustifyH("LEFT")
    nfs:SetJustifyV("TOP")
    nfs:SetWordWrap(true)
    nfs:SetTextColor(AT.COL.title[1], AT.COL.title[2], AT.COL.title[3])
    note._adText = nfs
    note._sync = function()
        nfs:SetText(CO.ActiveReadout(Rec()))
        local w = note:GetWidth() or 0
        if w < 60 then
            w = ((pg:GetWidth() or 0) / 2) - 12
            if w < 60 then pg._sizeUnresolved = true return end
        end
        nfs:SetWidth(w - 20)
        local want = math.max(22, math.floor((nfs:GetStringHeight() or 12) + 8))
        if note._h ~= want then note._h = want note:SetHeight(want) end
    end
    CO.activeNote = note
    AT.RowActions(pg, {
        { label = "Set each state's look on Effects", w = 220,
          onClick = function() if Options.OpenEffectsTab then Options.OpenEffectsTab() end end },
    }, "left", vis)

    AT.Section(pg, "Timer and stacks", { visibleFn = vis, side = "R" })
    AT.RowInput(pg, "Default seconds",
        function()
            local r = Rec()
            local d = r and tonumber(r.driver.duration)
            return d and ("%g"):format(d) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("duration", nil) return end
            if n and n > 0 then Set("duration", math.min(S.CUSTOM_MAX_SECONDS or 7200, n)) end
        end,
        vis, "How long the timer runs, and each stack when stacks run out on their own, when a rule gives no seconds. Enter applies it.",
        "Set per rule")
    local ET = Options.EditorTabs
    local fold = ET and ET.NewFold and ET.NewFold(pg, "custom.stacks", nil, Rec,
        { title = "Stacks", noCount = true, tip = "Its stack options. Click to show or hide them." })
    local function F(v) return fold and fold:Add(vis, v, function() return false end) or v end
    AT.RowInput(pg, "Max stacks",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("maxStacks", nil) return end
            if n and n >= 1 then Set("maxStacks", math.floor(math.min(999, n))) end
        end,
        F(vis), "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Each stack runs out on its own",
        function() local r = Rec() return r ~= nil and r.driver.stackTimers == true end,
        function(v) Set("stackTimers", v or nil) end,
        F(vis), "Every stack added runs its own timer (the rule's seconds, else Default seconds) and drops off when it ends.")
    AT.RowInput(pg, "Full pool while idle",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.idleCount)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if v == "" then Set("idleCount", nil) return end
            if n and n >= 1 then Set("idleCount", math.floor(math.min(999, n))) end
        end,
        F(vis), "While the timer is idle at 0 stacks, the count shows this many: a pool reads full before its first use. Empty = off.",
        "Off")
    AT.RowToggle(pg, "Clear stacks when the timer ends",
        function() local r = Rec() return r ~= nil and r.driver.clearOnEnd == true end,
        function(v) Set("clearOnEnd", v or nil) end,
        F(vis), "When the timer runs out, the stacks go back to 0 with it.")
end

-- Icon: the art it wears and when it loads.
function CO.IconPane(pg, Rec, vis)
    local AT = NS.AT
    local Store = NS.Store
    AT.Section(pg, "Icon", { visibleFn = vis })
    local artRow = AT.RowInput(pg, "Art from spell ID",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = CO.ParseSpell(v)
            if v ~= "" and not id then return end
            local r, E = Rec(), NS.DriverCustom
            if r and E then E.SetDriver(r, "spellID", id) end
            AT.LayoutPage(pg)
        end,
        vis, "The spell whose icon it wears; Appearance > Icon > Art > Custom icon wins over it. A spell ID, a link, or the name of a spell you know.",
        "Question mark until set")
    local nameFS = artRow:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(AT.FONT, 11, "")
    nameFS:SetPoint("LEFT", artRow._colCtrl, "RIGHT", 8, 0)
    nameFS:SetPoint("RIGHT", artRow, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local artSync = artRow._sync
    artRow._sync = function()
        artSync()
        local r = Rec()
        nameFS:SetText(r and CO.SpellName(r.driver.spellID) or "")
    end
    AT.RowToggle(pg, "Art follows the spell that starts it",
        function() local r = Rec() return r ~= nil and r.driver.artFollow == true end,
        function(v)
            local r, E = Rec(), NS.DriverCustom
            if r and E then E.SetDriver(r, "artFollow", v or nil) end
            AT.LayoutPage(pg)
        end,
        vis, "It wears the spell whose cast started its timer: one Fire Trap icon for whichever fire trap you laid.")
    local function HasSpell()
        local r = Rec()
        return vis() and r ~= nil and r.driver.spellID ~= nil
    end
    AT.RowToggle(pg, "Only load once learned",
        function() local r = Rec() return r ~= nil and r.driver.onlyKnown == true end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.onlyKnown = v and true or nil
            Store.Dirty("load")
            AT.LayoutPage(pg)
        end,
        HasSpell, "Doesn't load until your character knows the spell above (any rank), and loads by itself the moment you learn it.")
    AT.RowToggle(pg, "Only this rank",
        function() local r = Rec() return r ~= nil and r.driver.knownExact == true end,
        function(v)
            local r = Rec()
            if not r then return end
            r.driver.knownExact = v and true or nil
            Store.Dirty("load")
        end,
        function()
            local r = Rec()
            return HasSpell() and r.driver.onlyKnown == true and NS.IsForever == true
        end,
        "Waits for this exact rank (the spell ID above), not just any rank of the spell.")
end

-- The icon editor's hook: panes = the Tracking tab's four sub-tab gates
-- (rules, timer, icon, onIcon) for the open icon.
function Options.CustomIconRows(pg, ctx, panes, owner)
    local function Rec()
        local r = ctx()
        return (r and r.type == "icon" and r.kind == "timer") and r or nil
    end
    local function G(f) return function() return f() and Rec() ~= nil end end
    CO.RuleSentences(pg, Rec, G(panes.rules), owner)
    if Options.BuildYield then Options.BuildYield() end
    CO.TimerPane(pg, Rec, G(panes.timer), owner)
    if Options.BuildYield then Options.BuildYield() end
    CO.IconPane(pg, Rec, G(panes.icon))
    if Options.BuildYield then Options.BuildYield() end
    CO.SourceRows(pg, Rec, G(panes.onIcon), owner, true)
    NS.AT.Section(pg, nil)
end

function Options.CustomBarRows(pg, ctx, trackVis, trigVis, owner)
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "timer") and r or nil
    end
    local tv = function() return trackVis() and Rec() ~= nil end
    local gv = function() return trigVis() and Rec() ~= nil end
    CO.TrackRows(pg, Rec, tv, owner, true)
    CO.RuleRows(pg, Rec, gv, owner, true)
    NS.AT.Section(pg, nil)
end
