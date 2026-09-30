-- AD_TextureOptions: a texture's Add window tab, its Tracking rows (what drives it: an aura, a spell's cooldown or custom triggers), its tab list and the picture picker the Appearance block draws.
-- AD_Options calls in behind nil checks; the runtime is Bars\AD_TextureElement.lua, the triggers are UI\AD_TextOptions.lua's shared block.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TPO = {}
Options.TextureElement = TPO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function TPO.Runtime() return NS.TextureElements end

-- The sources this client can feed: an engine a source needs must be there.
function TPO.SourceItems()
    local S = NS.Schema
    local out = {}
    for _, s in ipairs(S.TEXTURE_SOURCES or {}) do
        local ok = true
        if s == "aura" then
            ok = NS.DriverAura ~= nil and NS.DriverAura.IsAvailable ~= nil and NS.DriverAura.IsAvailable() == true
        elseif s == "rules" then
            ok = NS.DriverCustom ~= nil
        elseif s == "spellCd" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXTURE_SOURCE_LABELS[s] or s } end
    end
    return out
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

-- The picker's list: the spell's icon (empty), every library picture by
-- group, and the current picture of your own when there is one.
function TPO.PictureItems(cur)
    local out = { { value = "", text = "The spell's icon" } }
    for _, g in ipairs(Options.TEXTURE_LIBRARY or {}) do
        for _, p in ipairs(g.pictures) do
            out[#out + 1] = { value = tostring(p.id), text = g.name .. ": " .. p.name }
        end
    end
    if cur and cur ~= "" and not TPO.InLibrary(cur) then
        out[#out + 1] = { value = cur, text = "Your own: " .. cur }
    end
    return out
end

function TPO.InLibrary(v)
    local n = tonumber(v)
    return n ~= nil and Options.TEXTURE_NAMES ~= nil and Options.TEXTURE_NAMES[n] ~= nil
end

function TPO.DefaultName(source, spellID)
    local nm = SpellName(spellID)
    if source == "rules" then return "Custom texture" end
    if nm ~= "" then return nm end
    return (source == "spellCd") and "Cooldown texture" or "Aura texture"
end

-- The sidebar's and cards' one line.
function Options.TextureWhat(rec)
    local T = TPO.Runtime()
    return T and T.Describe(rec) or "texture"
end

-- The editor tabs: Triggers only for a picture with custom triggers.
function Options.TextureTabs(rec)
    local tabs = { "Tracking" }
    if rec.driver and rec.driver.source == "rules" then tabs[#tabs + 1] = "Triggers" end
    for _, t in ipairs({ "Appearance", "Show & Hide", "Position", "Load Conditions" }) do tabs[#tabs + 1] = t end
    return tabs
end

-- The picture picker (SectionRows draws it for a `picture` field): the library
-- by group, a thumbnail of what shows now, and a box under it for a picture of
-- your own (a FileDataID or a file path).
function Options.PictureRow(pg, owner, label, section, field, ctx, visible)
    local AT, Store = NS.AT, NS.Store
    local function Cur()
        local r = ctx()
        local v = r and Store.Resolve(r, section, field)
        return (v ~= nil) and tostring(v) or ""
    end
    local row = AT.RowDropdown(pg, owner, label,
        Cur,
        function(v)
            local r = ctx()
            if r then Store.SetOverride(r, section, field, tostring(v or "")) end
        end,
        function() return TPO.PictureItems(Cur()) end,
        visible, function() AT.LayoutPage(pg) end)
    -- what shows now: the picture, or the spell's icon when none is set
    local thumb = row:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(20, 20)
    if row._colCtrl then thumb:SetPoint("LEFT", row._colCtrl, "RIGHT", 8, 0) end
    local sync = row._sync
    row._sync = function()
        if sync then sync() end
        local r, T = ctx(), TPO.Runtime()
        if r and T then thumb:SetTexture(T.PictureOf(r)) end
    end
    AT.RowInput(pg, "Picture ID or path",
        function()
            local v = Cur()
            return (v ~= "" and not TPO.InLibrary(v)) and v or ""
        end,
        function(v)
            local r = ctx()
            if not r then return end
            Store.SetOverride(r, section, field, Trim(v))
            AT.LayoutPage(pg)
        end,
        visible, "A picture of your own: its FileDataID, or its path such as Interface/AddOns/MyMedia/glow. Enter applies it; empty = pick one above.",
        "e.g. 450917")
    return row
end

-- The Add window's tab: what drives it, the aura or spell, the picture and a
-- name; the rest is set in the editor once it exists.
function Options.TextureAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Texture" end
    local function Src() return addState.texSource or "aura" end
    AT.RowDesc(pg, "A picture on screen: it shows with an aura, a cooldown or your own triggers, or fills like a bar.", 20, vis)
    AT.RowDropdown(pg, owner, "Picture driven by",
        Src,
        function(v) addState.texSource = v end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    AT.RowInput(pg, "Aura or spell",
        function() return addState.texSpell or "" end,
        function(v)
            addState.texSpell = v
            -- the page again, so Create is judged with it
            AT.LayoutPage(pg)
        end,
        function() return vis() and Src() ~= "rules" end,
        "The aura's spell ID, or the spell whose cooldown it follows: an ID, a link or the name of a spell you know. Enter applies it.",
        "e.g. 1459")
    AT.RowDropdown(pg, owner, "Picture to show",
        function() return addState.texImage or "" end,
        function(v) addState.texImage = v end,
        function() return TPO.PictureItems(addState.texImage) end, vis)
    AT.RowInput(pg, "Texture name",
        function() return addState.texName or "" end,
        function(v) addState.texName = v end,
        vis, "What the sidebar calls it.",
        function() return TPO.DefaultName(Src(), ParseSpell(addState.texSpell or "")) end, true)
end

-- An aura or a cooldown needs its spell; custom triggers are set afterwards.
function Options.TextureCanCreate(addState)
    if (addState.texSource or "aura") == "rules" then return true end
    return ParseSpell(addState.texSpell or "") ~= nil
end

function Options.TextureCreate(addState, layoutId)
    local Store = NS.Store
    local s = addState.texSource or "aura"
    local driver = { source = s }
    local sid
    if s == "rules" then
        driver.rules = {}
    else
        sid = ParseSpell(addState.texSpell or "")
        driver.spellID = sid
    end
    local name = Trim(addState.texName)
    if name == "" then name = TPO.DefaultName(s, sid) end
    local rec = Store.NewBar(layoutId, "texture", driver, name)
    local img = Trim(addState.texImage)
    if rec and img ~= "" then Store.SetOverride(rec, "texlook", "image", img) end
    return rec
end

-- The Tracking rows. ctx(): the open bar; trackVis: the Tracking tab.
function Options.TextureTrackRows(pg, ctx, trackVis, owner)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "texture" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TPO.Runtime()
        return (r and T) and T.Source(r) or "aura"
    end
    local function Is(want)
        return function()
            local r = Rec()
            return vis() and r ~= nil and Source(r) == want
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

    AT.Section(pg, "What drives it", { visibleFn = vis })
    local srcRow = AT.RowDropdown(pg, owner, "Driven by",
        function() return Source(Rec()) end,
        function(v)
            local r = Rec()
            if not r or Source(r) == v then return end
            r.driver.source = v
            if v == "rules" and type(r.driver.rules) ~= "table" then r.driver.rules = {} end
            Store.Dirty("tree", r.id)
        end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    -- the search finds the row on every texture (its own field name)
    srcRow._adMeta = { family = "bar", section = "texlook", field = "textureSource",
        def = { label = "Driven by" }, baseVis = vis }

    -- an aura on a unit: the aura icons' shape
    local auraVis = Is("aura")
    AT.RowInput(pg, "Aura to watch",
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
        auraVis, "The aura's spell IDs, separated by commas or spaces; any of them shows the picture.", "e.g. 1459, 10157")
    AT.RowDropdown(pg, owner, "Buff or debuff to watch",
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
    AT.RowDropdown(pg, owner, "Aura on whom",
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
    AT.RowDropdown(pg, owner, "Aura put there by",
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
    AT.RowDesc(pg, "The game draws it with the aura, in combat too. Buffs work on you, your pet and friendly units; debuffs on a hostile target or focus.", 20, auraVis)

    -- a spell's cooldown
    local cdVis = Is("spellCd")
    local spellRow = AT.RowInput(pg, "Spell to watch",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = ParseSpell(v)
            if Trim(v) ~= "" and not id then return end
            Set("spellID", id)
        end,
        cdVis, "A spell ID, a link, or the name of a spell you know. Enter applies it.", "e.g. 17364")
    local nameFS = spellRow:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(STANDARD_TEXT_FONT, 11, "")
    if spellRow._colCtrl then nameFS:SetPoint("LEFT", spellRow._colCtrl, "RIGHT", 8, 0) end
    nameFS:SetPoint("RIGHT", spellRow, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local sync = spellRow._sync
    spellRow._sync = function()
        if sync then sync() end
        local r = Rec()
        nameFS:SetText(r and SpellName(r.driver.spellID) or "")
    end
    AT.RowToggle(pg, "Use my current rank",
        function()
            local r = Rec()
            return r ~= nil and r.driver.autoRank == true
        end,
        function(v) Set("autoRank", v or nil) end,
        function() return cdVis() and NS.IsForever == true end,
        "On ranked realms, follow whichever rank of this spell you know now.")
    AT.RowDropdown(pg, owner, "Picture active while",
        function()
            local r = Rec()
            return (r and r.driver.cdActive) or "ready"
        end,
        function(v) Set("cdActive", (v ~= "ready") and v or nil) end,
        function()
            local out = {}
            for _, k in ipairs(S.TEXTURE_CD_ACTIVE) do
                out[#out + 1] = { value = k, text = S.TEXTURE_CD_ACTIVE_LABELS[k] or k }
            end
            return out
        end,
        function()
            local r = Rec()
            return cdVis() and r ~= nil and not (TPO.Runtime() and TPO.Runtime().FillMode(r))
        end)
    AT.RowDesc(pg, "A fill runs while the spell is on cooldown (a charge spell: while a charge comes back) and stands full when it is ready.", 20,
        function()
            local r = Rec()
            return cdVis() and r ~= nil and TPO.Runtime() ~= nil and TPO.Runtime().FillMode(r)
        end)

    -- custom triggers: the rows live on the Triggers tab
    AT.RowDesc(pg, "Its triggers are on the Triggers tab: they decide when the picture shows, and a fill runs with their timer.", 20,
        Is("rules"))
    AT.Section(pg, nil)
end
