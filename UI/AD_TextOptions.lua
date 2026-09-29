-- AD_TextOptions: a Text element's Add window tab and its Tracking rows: the source, each source's own fields (words, power, unit, spell, aura shape, the rules) and the Format block.
-- AD_Options calls in behind nil checks (Options.TextAddRows / TextCreate / TextTrackRows / TextWhat); the runtime is Bars\AD_TextElement.lua, the rules editor UI\AD_CustomOptions.lua's.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TO = {}
Options.TextElement = TO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Items(values, labels)
    local out = {}
    for _, v in ipairs(values or {}) do out[#out + 1] = { value = v, text = (labels and labels[v]) or tostring(v) } end
    return out
end

function TO.Runtime() return NS.TextElements end

-- The sources this client can feed: an engine a source needs must be there.
function TO.SourceItems()
    local S = NS.Schema
    local out = {}
    for _, s in ipairs(S.TEXT_SOURCES or {}) do
        local ok = true
        if s == "auraTime" or s == "auraStacks" then
            ok = NS.DriverAura ~= nil and NS.DriverAura.IsAvailable ~= nil and NS.DriverAura.IsAvailable() == true
        elseif s == "rules" or s == "custom" then
            ok = NS.DriverCustom ~= nil
        elseif s == "range" then
            ok = NS.RangeBars ~= nil and NS.DriverRange ~= nil
        elseif s == "spellCd" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
        elseif s == "spellCharges" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCharges ~= nil
        elseif s == "petMood" then
            ok = NS.IsForever == true
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXT_SOURCE_LABELS[s] or s } end
    end
    return out
end

function TO.UnitItems()
    local hasFocus = not (C_EventUtils and C_EventUtils.IsEventValid)
        or C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")
    local out = {}
    for _, u in ipairs({ "player", "target", "focus", "pet" }) do
        if u ~= "focus" or hasFocus then out[#out + 1] = { value = u, text = Options.HealthUnitLabel(u) } end
    end
    return out
end

-- every range bar in the store, after the class preset
function TO.RangeItems()
    local Store = NS.Store
    local out = { { value = 0, text = "Your class preset" } }
    for _, lay in ipairs(Store.Layouts()) do
        for _, m in ipairs(Store.MembersOf(lay)) do
            if m.type == "bar" and m.barKind == "range" then
                out[#out + 1] = { value = m.id, text = tostring(m.name) .. " (" .. tostring(lay.name) .. ")" }
            end
        end
    end
    return out
end

function TO.DefaultName(source)
    local S = NS.Schema
    if source == "static" then return "Text" end
    return (S.TEXT_SOURCE_LABELS and S.TEXT_SOURCE_LABELS[source]) or "Text"
end

-- The sidebar's and cards' one line.
function Options.TextWhat(rec)
    local T = TO.Runtime()
    return T and T.Describe(rec) or "text"
end

-- The Add window's tab: what it shows and its name; the rest is set on
-- Tracking once it exists.
function Options.TextAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Text" end
    AT.RowDesc(pg, "A word or a number on screen: your power, a spell's cooldown, an aura's stacks and more.", 20, vis)
    AT.RowDropdown(pg, owner, "Shows",
        function() return addState.textSource or "static" end,
        function(v) addState.textSource = v end,
        TO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    AT.RowInput(pg, "Words",
        function() return addState.textWords or "" end,
        function(v) addState.textWords = v end,
        function() return vis() and (addState.textSource or "static") == "static" end,
        "What it says.", "e.g. Pull in 10", true)
    AT.RowInput(pg, "Name",
        function() return addState.textName or "" end,
        function(v) addState.textName = v end,
        vis, "What the sidebar calls it.", function() return TO.DefaultName(addState.textSource or "static") end, true)
end

function Options.TextCreate(addState, layoutId)
    local Store = NS.Store
    local s = addState.textSource or "static"
    local driver = { source = s }
    if s == "static" then
        local words = Trim(addState.textWords)
        driver.text = (words ~= "") and words or nil
    elseif s == "health" then
        driver.unit = "player"
    elseif s == "rules" then
        driver.rules = {}
    end
    local name = Trim(addState.textName)
    if name == "" then name = TO.DefaultName(s) end
    return Store.NewBar(layoutId, "text", driver, name)
end

-- The Tracking rows. ctx(): the open bar; vis: the Tracking tab. kit:
-- { SectionRows } from the bar pane, for the Format block's schema rows.
function Options.TextTrackRows(pg, ctx, trackVis, owner, kit)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local COL = AT.COL
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "text" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TO.Runtime()
        return (r and T) and T.Source(r) or "static"
    end
    local function Is(...)
        local want = { ... }
        return function()
            local r = Rec()
            if not (vis() and r) then return false end
            local s = Source(r)
            for _, w in ipairs(want) do
                if s == w then return true end
            end
            return false
        end
    end
    -- a driver edit: the record in place, then the page again at once
    local function Set(field, value)
        local r = Rec()
        if not r then return end
        if r.driver[field] == value then return end
        r.driver[field] = value
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end
    local function ParseSpell(text)
        local CO = Options.Custom
        if CO and CO.ParseSpell then return CO.ParseSpell(text) end
        local id = tonumber(Trim(text))
        return (id and id > 0) and math.floor(id) or nil
    end
    local function SpellName(id)
        local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
        return nm
    end
    local function NameBeside(row, get)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "")
        fs:SetPoint("LEFT", row._colCtrl, "RIGHT", 8, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        local sync = row._sync
        row._sync = function()
            if sync then sync() end
            fs:SetText(get() or "")
        end
    end

    AT.Section(pg, "Text", { visibleFn = vis })
    local srcRow = AT.RowDropdown(pg, owner, "Shows",
        function() return Source(Rec()) end,
        function(v)
            local r = Rec()
            if not r or Source(r) == v then return end
            r.driver.source = v
            -- a source's own defaults, so its first draw means something
            if v == "health" and not r.driver.unit then r.driver.unit = "player" end
            if v == "rules" and type(r.driver.rules) ~= "table" then r.driver.rules = {} end
            Store.Dirty("tree", r.id)
        end,
        TO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    -- the search finds the row on every text element (its own field name)
    srcRow._adMeta = { family = "bar", section = "textel", field = "textSource",
        def = { label = "Shows" }, baseVis = vis }
    AT.RowInput(pg, "Words",
        function()
            local r = Rec()
            return (r and r.driver.text) or ""
        end,
        function(v)
            v = Trim(v)
            Set("text", (v ~= "") and v:sub(1, 120) or nil)
        end,
        Is("static"), "What it says. Enter applies it.", "e.g. Pull in 10")
    -- power: which one, and what of it
    AT.RowDropdown(pg, owner, "Power shown",
        function()
            local r = Rec()
            local pt = r and r.driver.powerType
            return (pt == nil or pt < 0) and -1 or pt
        end,
        function(v) Set("powerType", (tonumber(v) and tonumber(v) >= 0) and tonumber(v) or nil) end,
        function()
            local r = Rec()
            if Options.PowerItems then return Options.PowerItems(r and r.driver.powerType) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        Is("power"))
    AT.RowDropdown(pg, owner, "Value",
        function()
            local r = Rec()
            return (r and r.driver.show) or "current"
        end,
        function(v) Set("show", (v ~= "current") and v or nil) end,
        function() return Items(S.TEXT_SHOWS, S.TEXT_SHOW_LABELS) end,
        Is("power", "health"))
    AT.RowDropdown(pg, owner, "Health of",
        function()
            local r = Rec()
            return (r and r.driver.unit) or "player"
        end,
        function(v) Set("unit", v) end,
        TO.UnitItems, Is("health"))
    AT.RowDesc(pg, "Combo points on your target, as the combo bar counts them.", 20, Is("combo"))
    AT.RowDesc(pg, "The count of your equipped ammo; blank with the slot empty.", 20, Is("ammo"))
    AT.RowDesc(pg, "Happy, Content or Unhappy; blank with no pet out.", 20, Is("petMood"))
    AT.RowDropdown(pg, owner, "Bands from",
        function()
            local r = Rec()
            return (r and r.driver.rangeFrom) or 0
        end,
        function(v) Set("rangeFrom", (v ~= 0) and v or nil) end,
        TO.RangeItems, Is("range"))
    AT.RowDesc(pg, "The band your target is in; blank with no target or a friendly one.", 20, Is("range"))
    AT.RowDesc(pg, "The game's clock, as the minimap shows it.", 20, Is("clock"))
    -- a spell's cooldown or charges
    local spellRow = AT.RowInput(pg, "Tracked spell",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = ParseSpell(v)
            if Trim(v) ~= "" and not id then return end
            Set("spellID", id)
        end,
        Is("spellCd", "spellCharges"), "A spell ID, a link, or the name of a spell you know. Enter applies it.",
        "e.g. 17364")
    NameBeside(spellRow, function()
        local r = Rec()
        return r and SpellName(r.driver.spellID)
    end)
    AT.RowToggle(pg, "Follow my rank",
        function()
            local r = Rec()
            return r ~= nil and r.driver.autoRank == true
        end,
        function(v) Set("autoRank", v or nil) end,
        function() return Is("spellCd", "spellCharges")() and NS.IsForever == true end,
        "On ranked realms, read whichever rank of this spell you know now.")
    AT.RowDesc(pg, "Counts down the spell's cooldown; blank while it is ready or only the global cooldown runs.", 20,
        Is("spellCd"))
    AT.RowDesc(pg, "How many charges are up; Blank at zero below hides the 0.", 20, Is("spellCharges"))
    -- an aura on a unit: the aura icons' shape
    local auraVis = Is("auraTime", "auraStacks")
    AT.RowInput(pg, "Aura spell IDs",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            local ids = (r and DA) and DA.SpellIDList(r.driver) or {}
            return table.concat(ids, ", ")
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            local old = NS.DriverAura and table.concat(NS.DriverAura.SpellIDList(r.driver), ",") or ""
            if table.concat(ids, ",") == old then return end
            Options.SetAuraSpellIDs(r.driver, ids)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        auraVis, "The aura's spell IDs, separated by commas or spaces; any of them fills the text.", "e.g. 13549, 13550")
    AT.RowDropdown(pg, owner, "Buff or debuff",
        function()
            local r = Rec()
            return (r and r.driver.auraType == "debuff") and "debuff" or "buff"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local DA = NS.DriverAura
            local unit = DA and DA.ShapeOf(r.driver) or "player"
            r.driver.auraType = v
            if not Options.AuraUnitAllowed(r.driver, unit, v) then unit = "target" end
            r.driver.unit = unit
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura on unit",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            return (r and DA) and (DA.ShapeOf(r.driver)) or "player"
        end,
        function(v) Set("unit", v) end,
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return {} end
            return Options.AuraUnitItems(r.driver, nil, (DA.ShapeOf(r.driver)))
        end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura cast by",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return "any" end
            local _, _, caster = DA.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v) Set("caster", (v ~= "any") and v or nil) end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)
    AT.RowDesc(pg, "Buffs work on you, your pet and friendly units; debuffs on a hostile target or focus.", 20, auraVis)
    -- rules of its own, or another custom item's value
    local rulesVis = Is("rules")
    AT.RowDropdown(pg, owner, "Custom item",
        function()
            local r = Rec()
            return (r and r.driver.srcId) or 0
        end,
        function(v) Set("srcId", (v ~= 0) and v or nil) end,
        function()
            local CO = Options.Custom
            return CO and CO.ChainItems and CO.ChainItems(nil) or { { value = 0, text = "Pick an item" } }
        end,
        Is("custom"))
    AT.RowDropdown(pg, owner, "Readout",
        function()
            local r = Rec()
            return (r and r.driver.show) or "stacks"
        end,
        function(v) Set("show", (v ~= "stacks") and v or nil) end,
        function() return Items(S.TEXT_READOUTS, S.TEXT_READOUT_LABELS) end,
        Is("rules", "custom"))
    AT.RowDesc(pg, "Its rules below start its timer and count its stacks from events you pick.", 20, rulesVis)
    local function SetCustom(field, value)
        local r, CU = Rec(), NS.DriverCustom
        if r and CU and CU.SetDriver then CU.SetDriver(r, field, value) end
        AT.LayoutPage(pg)
    end
    AT.RowInput(pg, "Timer seconds",
        function()
            local r = Rec()
            local d = r and tonumber(r.driver.duration)
            return d and ("%g"):format(d) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("duration", nil) return end
            if n and n > 0 then SetCustom("duration", math.min(3600, n)) end
        end,
        rulesVis, "How long the timer runs when a rule starts it with no seconds of its own. Enter applies it.",
        "Set per rule")
    AT.RowInput(pg, "Stack cap",
        function()
            local r = Rec()
            local m = r and tonumber(r.driver.maxStacks)
            return m and tostring(m) or ""
        end,
        function(v)
            local n = tonumber(v)
            if Trim(v) == "" then SetCustom("maxStacks", nil) return end
            if n and n >= 1 then SetCustom("maxStacks", math.floor(math.min(999, n))) end
        end,
        rulesVis, "Stacks never pass this. Empty = no cap. Enter applies it.", "No cap")
    AT.RowToggle(pg, "Stacks clear when the timer ends",
        function()
            local r = Rec()
            return r ~= nil and r.driver.clearOnEnd == true
        end,
        function(v) SetCustom("clearOnEnd", v or nil) end,
        rulesVis, "When the timer runs out, the stacks go back to 0 with it.")
    if Options.Custom and Options.Custom.RuleRows then
        Options.Custom.RuleRows(pg, Rec, rulesVis, owner, true)
    end

    -- The words around the value and its number or time format: the element's
    -- own, so no push bar; each row shows for the sources it reaches.
    AT.Section(pg, "Format", { visibleFn = vis })
    AT.RowDesc(pg, "The game draws this countdown itself: the prefix and suffix stay off it.", 20,
        Is("spellCd", "auraTime"))
    if kit and kit.SectionRows then
        kit.SectionRows(pg, "bar", "textel", ctx, vis, {
            "prefix", "suffix", "numFormat", "blankAtZero", "decimals", "decimalsBelow", "abbrev", "rounding",
        })
    end
    AT.Section(pg, nil)
end
