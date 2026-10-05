-- AD_CustomOptions: the Custom Icon and Custom Bar editors (the timer kind): the Tracking rows (art, Show while, seconds, stacks), the Triggers tab's rule editor and the Add window's rows.
-- AD_Options calls in behind nil checks (Options.CustomIconRows / CustomBarRows / CustomAddRows / CustomCreate / CustomBarDriver / CustomWhat); every write goes through NS.DriverCustom.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local CO = { showIf = {} }
Options.Custom = CO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
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
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
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
    local words = (n == 1) and "1 rule" or (n .. " rules")
    if rec.type == "bar" then
        return "Custom bar  -  " .. ((rec.barMode == "stack") and "stacks" or "timer") .. ", " .. words
    end
    return "custom icon, " .. words
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

function CO.AddFields(addState, which)
    local name = Trim(addState.customName)
    if name == "" then name = (which == "Bar") and "Custom Bar" or "Custom Icon" end
    local art = CO.ParseSpell(addState.customArt)
    return name, art
end

function Options.CustomCreate(addState, dest, layoutId)
    local name, art = CO.AddFields(addState, "Icon")
    return NS.Store.NewIcon("timer", { spellID = art, rules = {} }, dest, layoutId, name)
end

function Options.CustomBarDriver(addState)
    local name, art = CO.AddFields(addState, "Bar")
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
    AT.Section(pg, isBar and "Custom Bar" or "Custom Icon", { visibleFn = vis })
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
    nameFS:SetFont(STANDARD_TEXT_FONT, 11, "")
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
    AT.RowDropdown(pg, owner, "Show as active while",
        function()
            local r = Rec()
            return (r and r.driver.showWhile) or "timer"
        end,
        function(v) Set("showWhile", (v ~= "timer") and v or nil) end,
        Items(S.CUSTOM_SHOW_WHILE, S.CUSTOM_SHOW_WHILE_LABELS), vis)
    AT.RowDesc(pg, isBar and "Active: the bar shows (Hide when inactive hides it otherwise)."
        or "Conditions sets its Active and Not active looks. With no rules yet it shows as active.",
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
            if n and n > 0 then Set("duration", math.min(3600, n)) end
        end,
        vis, "How long the timer runs when a rule starts it with no seconds of its own. Enter applies it.", "Set per rule")
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
    AT.RowToggle(pg, "Clear stacks when the timer ends",
        function()
            local r = Rec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) Set("clearOnEnd", v or nil) end,
        vis, "When the timer runs out, the stacks go back to 0 with it.")
end

-- Every custom item, for the "another item's timer ended" pick.
function CO.ChainItems(self)
    local Store = NS.Store
    local out = { { value = 0, text = "Pick an item" } }
    for _, lay in ipairs(Store.Layouts()) do
        for _, m in ipairs(Store.MembersOf(lay)) do
            if m.type == "group" then
                for _, ic in ipairs(Store.IconsOf(m)) do
                    if ic.kind == "timer" and ic.id ~= self then
                        out[#out + 1] = { value = ic.id, text = tostring(ic.name) .. " (icon)" }
                    end
                end
            elseif (m.type == "icon" and m.kind == "timer") or (m.type == "bar" and m.barKind == "timer") then
                if m.id ~= self then
                    out[#out + 1] = { value = m.id, text = tostring(m.name) .. ((m.type == "bar") and " (bar)" or " (icon)") }
                end
            end
        end
    end
    return out
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
        out[#out + 1] = { value = opt.entryID, text = tostring(opt.name) .. (yours and "  (yours)" or "") }
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = "Choice " .. current .. " (not in this tree)" }
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
        out[#out + 1] = { value = e.nodeID, text = name .. ((e.rank or 0) > 0 and "  (yours)" or "") }
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = "Talent " .. current .. " (not in this tree)" }
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
            out[#out + 1] = { value = id, text = (type(name) == "string" and name ~= "") and name or ("Spec " .. id) }
        end
    end
    if current and current ~= 0 and not seen then
        out[#out + 1] = { value = current, text = "Spec " .. current .. " (another class)" }
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
        for _, g in ipairs(groups) do out[#out + 1] = { value = g.key, text = g.label } end
        local E = CU()
        if E and E.CUSTOM_TARGET_FEEDBACK then out[#out + 1] = { value = "target", text = "Your target" } end
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

        AT.Section(pg, "Rule " .. i, { visibleFn = vis })
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
        local idRow = AT.RowInput(pg, "Spell ID",
            function()
                local r = Rule(i)
                return (r and r.spellID) and tostring(r.spellID) or ""
            end,
            function(v)
                local id = CO.ParseSpell(v)
                if v ~= "" and not id then return end
                Set("spellID", id)
            end,
            spellVis, "The spell this trigger watches: a spell ID, a link, or the name of a spell you know. Any rank matches.",
            "e.g. 6572")
        local nameFS = idRow:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont(STANDARD_TEXT_FONT, 11, "")
        nameFS:SetPoint("LEFT", idRow._colCtrl, "RIGHT", 8, 0)
        nameFS:SetPoint("RIGHT", idRow, "RIGHT", -10, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local idSync = idRow._sync
        idRow._sync = function()
            idSync()
            local r = Rule(i)
            nameFS:SetText(r and CO.SpellName(r.spellID) or "")
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
            "On: the spell's own requirement decides (a dodge, a proc, enough mana), even while it is still cooling down. Off: only when it can be cast now, usable and off cooldown.")
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
        if opts.triggerRows then opts.triggerRows(pg, i, api) end

        -- the guards, behind one switch: off drops them all
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
        AT.RowDropdown(pg, owner, "Within seconds after rule",
            function()
                local r = Rule(i)
                return (r and r.withinRule) or 0
            end,
            function(v) Set("withinRule", (v ~= 0) and v or nil) end,
            function()
                local out = { { value = 0, text = "No such condition" } }
                for k = 1, #Rules() do
                    if k ~= i then out[#out + 1] = { value = k, text = "Rule " .. k } end
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
            "How long after that rule last fired this one may fire. Enter applies it.")
        AT.RowDropdown(pg, owner, "Timer",
            function()
                local r = Rule(i)
                return (r and r.timer) or "any"
            end,
            function(v) Set("timer", (v ~= "any") and v or nil) end,
            Items(S.CUSTOM_TIMER_STATES, S.CUSTOM_TIMER_STATE_LABELS), gtv)

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
                if n and n >= 0 then Set("secs", (n > 0) and math.min(3600, n) or nil) end
            end,
            function()
                local r = Rule(i)
                return rv() and (r.act == "start" or (r.act == "add" and r.restartToo == true))
            end,
            "How long the timer runs; 0 takes the item's Default seconds. Decimals work (1.5). Enter applies it.")
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
        local trow = AT.RowInput(pg, "Text",
            function()
                local r = Rule(i)
                return (r and r.text) or ""
            end,
            function(v)
                v = Trim(v)
                Set("text", (v ~= "") and v:sub(1, 200) or nil)
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

-- The icon editor's hook: trackVis / trigVis are the Tracking and Triggers
-- tabs' gates for the open icon.
function Options.CustomIconRows(pg, ctx, trackVis, trigVis, owner)
    local function Rec()
        local r = ctx()
        return (r and r.type == "icon" and r.kind == "timer") and r or nil
    end
    local tv = function() return trackVis() and Rec() ~= nil end
    local gv = function() return trigVis() and Rec() ~= nil end
    CO.TrackRows(pg, Rec, tv, owner, false)
    CO.RuleRows(pg, Rec, gv, owner, false)
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
