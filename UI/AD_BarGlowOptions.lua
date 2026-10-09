-- AD_BarGlowOptions: the bar editor's Conditions > Glows sub-tab (a card per glow, "+ Add glow", the push bar).
-- AD_Options calls Options.BarGlowRows while it builds the bar pane; the runtime is Bars\AD_BarGlow.lua.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local BGO = {}
Options.BarGlowOptions = BGO

-- a card's rows in short words: the card names its glow
BGO.WORDS = { When = "Glow when", Type = "Style", Color = "Color", CombatOnly = "Only in combat",
    Speed = "Speed", Lines = "Lines", Thickness = "Thickness", Length = "Line length (0 = auto)",
    Particles = "Particles", Scale = "Size", Intensity = "Intensity", XOffset = "X offset", YOffset = "Y offset" }
-- the look and gates, then the tuning (folded away: "More glow options")
BGO.REST = { "Type", "Color", "CombatOnly", "Speed", "Lines", "Thickness", "Length", "Particles",
    "Scale", "Intensity", "XOffset", "YOffset" }
-- the card's note: when the glow shows
BGO.WHEN_WORDS = { up = "the aura is up", missing = "the aura is missing", ready = "it is ready",
    recharging = "it is recharging", cooldown = "it is on cooldown" }
-- Track's words, by the thing of its own the bar's kind has (Schema.BAR_GLOW_KINDS' own)
BGO.TRACK_WORDS = {
    aura = { own = "This bar's aura", aura = "Another aura", spell = "A spell's cooldown" },
    spell = { own = "This bar's spell", spell = "Another spell", aura = "An aura" },
    none = { aura = "An aura", spell = "A spell's cooldown" },
}
-- the spell suggestions: this many buttons under a status line
BGO.SUG_N = 5
-- the aura pick's field, worded as the aura icon's in the Add window
BGO.AURA_IDS = "Aura name or spell IDs"
BGO.STALE_NOTE = "This spell has no charges: Recharging never lights."

function BGO.Suf(k) return (k > 1) and tostring(k) or "" end
local function Glow() return NS.Bars and NS.Bars.Glow end

-- The Glows sub-tab is the one open: the editor preview draws every glow then.
function Options.BarGlowsOpen()
    local ui = Options.ui
    if not (ui and ui.barTab == "Conditions") then return false end
    return (ui.barSec and ui.barSec.Conditions) == "Glows"
end
if NS.Bars and NS.Bars.Glow then NS.Bars.Glow.PreviewOpen = Options.BarGlowsOpen end

-- glow k's own record (rec.driver.glows[k]): the aura pick and the spell pick; make = create it
function BGO.Aura(r, k, make)
    local Gl = Glow()
    return Gl and Gl.GlowRec(r, k, make) or nil
end

-- an aura bar watches its own aura unless "Another aura" was picked
function BGO.Own(r, k)
    local Gl = Glow()
    return Gl ~= nil and Gl.AuraOwn(r, k) == true
end

-- The words Track lists for this bar.
function BGO.TrackWords(r)
    local Gl = Glow()
    local own = (r and not r._adMulti and Gl) and Gl.OwnFamily(r) or nil
    return BGO.TRACK_WORDS[own or "none"]
end

-- A typed spell: its ID, or the exact name of a spell you know.
function BGO.ParseSpell(text)
    local DR = NS.DriverRange
    if DR and DR.ParseSpell then return DR.ParseSpell(text) end
    local n = tonumber(text)
    return (n and n > 0) and math.floor(n) or nil
end

-- Track: what lights glow k, an aura or a spell's cooldown (the bar's own one
-- first where it has one). Several bars at once pick only the kind of thing:
-- each keeps its own aura and spell picks.
function BGO.TrackRow(pg, ctx, win, k, cardVis)
    local AT = NS.AT
    local Store = NS.Store
    local suf = BGO.Suf(k)
    local function On()
        local r = ctx()
        return cardVis() and r ~= nil and Store.Resolve(r, "glows", "barGlow" .. suf) == true
    end
    local pick = {
        get = function()
            local r, Gl = ctx(), Glow()
            return (r and Gl) and Gl.Track(r, k) or nil
        end,
        set = function(v)
            local r, Gl = ctx(), Glow()
            if not (r and Gl) then return end
            Gl.SetTrack(r, k, v)
            if not r._adMulti then Store.Dirty("style", r.id) end
            AT.LayoutPage(pg)
        end,
        items = function()
            local r, Gl = ctx(), Glow()
            if not (r and Gl) then return {} end
            local words, cur = BGO.TrackWords(r), Gl.Track(r, k)
            local auraOK = NS.Schema.BarGlowAuraOK(false)
            local own = Gl.OwnFamily(r)
            local out = {}
            for _, v in ipairs(Gl.TrackChoices(r)) do
                local isAura = v == "aura" or (v == "own" and own == "aura")
                -- no aura engine: no aura choice, unless it is the one saved
                if v == cur or auraOK or not isAura then
                    out[#out + 1] = { value = v, text = words[v] or v }
                end
            end
            return out
        end,
    }
    local row = AT.RowDropdown(pg, win, "Track", pick.get, pick.set, pick.items, On)
    -- test handle: the pick's reader, writer and list
    row._adPick = pick
    AT.Tooltip(row, "Track", "What lights this glow: an aura (a buff or debuff, on any unit) or a spell's cooldown.")
    row._adMeta = { family = "bar", section = "glows", field = "glowTrack" .. suf,
        def = { label = "Track", dep = { field = "barGlow" .. suf } },
        baseVis = function() return cardVis() and ctx() ~= nil end }
    return row
end

-- The spell rows of glow k, when it tracks another spell than the bar's own:
-- Spell name or ID (+ suggestions from your spellbook), Follow my rank
-- (Forever). The pick is the glow's own record, apart from its aura pick.
function BGO.SpellRows(pg, ctx, win, k, cardVis)
    local AT = NS.AT
    local Store = NS.Store
    local suf = BGO.Suf(k)
    local function Rec()
        local r = ctx()
        if not r or r._adMulti then return nil end
        return r
    end
    local function spellVis()
        local r, Gl = Rec(), Glow()
        if not (cardVis() and r and Gl) then return false end
        if Store.Resolve(r, "glows", "barGlow" .. suf) ~= true then return false end
        return Gl.Family(r, k) == "spell" and not (Gl.CdSpell(r, k))
    end
    local function stampVis()
        return cardVis() and Rec() ~= nil
    end
    local function Edit(fn)
        local r = Rec()
        local g = r and BGO.Aura(r, k, true)
        if not g then return end
        fn(g)
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end
    local function Commit(v)
        local id = BGO.ParseSpell(v)
        if not id then return end
        Edit(function(g) g.cdSpellID = id end)
    end
    local idRow = AT.RowInput(pg, "Spell name or ID",
        function()
            local r = Rec()
            local g = r and BGO.Aura(r, k, false)
            return (g and g.cdSpellID) and tostring(g.cdSpellID) or ""
        end,
        Commit, spellVis,
        "Type the spell's name and click it below, or type its ID and press Enter.")
    idRow._adMeta = { family = "bar", section = "glows", field = "glowSpellID" .. suf,
        def = { label = "Spell name or ID", dep = { field = "barGlow" .. suf } }, baseVis = stampVis }
    local Suggest = BGO.SpellSuggest(pg, spellVis,
        function()
            local eb = idRow._colCtrl
            return eb and eb:GetText() or ""
        end,
        function(id)
            if idRow._colCtrl then idRow._colCtrl:SetText(tostring(id)) end
            Edit(function(g) g.cdSpellID = id end)
        end)
    if idRow._colCtrl then
        idRow._colCtrl:HookScript("OnTextChanged", function(_, userInput)
            if userInput then Suggest(false) end
        end)
    end
    -- test handles: the commit and the list's refresh
    idRow._adCommit, idRow._adSuggest = Commit, Suggest

    local rankRow = AT.RowToggle(pg, "Follow my rank",
        function()
            local r = Rec()
            local g = r and BGO.Aura(r, k, false)
            return g == nil or g.cdFollowRank ~= false
        end,
        function(v)
            Edit(function(g) if v then g.cdFollowRank = nil else g.cdFollowRank = false end end)
        end,
        function() return spellVis() and NS.IsForever == true end,
        "Follows the rank of this spell you know, so a newly trained rank keeps working.")
    rankRow._adMeta = { family = "bar", section = "glows", field = "glowSpellRank" .. suf,
        def = { label = "Follow my rank", dep = { field = "barGlow" .. suf } },
        baseVis = function() return stampVis() and NS.IsForever == true end }
end

-- Spell suggestions for a typed name, from your spellbook (NS.SpellCatalog):
-- a status line and up to BGO.SUG_N spells; a click picks one. Built on the
-- aura search's pattern (Options.AuraSuggestPanel). Plain buttons, so the
-- settings search skips them. Returns its refresh, as the aura one does.
function BGO.SpellSuggest(pg, visibleFn, getText, pick)
    local AT = NS.AT
    local COL = AT.COL
    -- as tall as what it shows (Options.SuggestFit): no gap under a set ID
    local row = AT.AddRow(pg, 14, visibleFn)
    local lines = {}
    local status = Options.SuggestLine(row, lines, 1)
    local btns, lastText = {}, nil
    local syncing = false
    local Refresh
    local function Btn(i)
        local b = btns[i]
        if b then return b end
        b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 8, -14 - (i - 1) * 23)
        b:SetPoint("TOPRIGHT", -12, -14 - (i - 1) * 23)
        AT.Skin(b, COL.well, COL.line)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetSize(18, 18)
        b.tex:SetPoint("LEFT", 3, 0)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.name = b:CreateFontString(nil, "OVERLAY")
        b.name:SetFont(AT.FONT, 11, "")
        b.name:SetPoint("LEFT", 27, 0)
        b.name:SetPoint("RIGHT", -110, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        b.id = b:CreateFontString(nil, "OVERLAY")
        b.id:SetFont(AT.FONT, 9, "")
        b.id:SetPoint("RIGHT", -6, 0)
        b.id:SetJustifyH("RIGHT")
        b.id:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
        b:SetScript("OnEnter", function()
            b:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
            local e = b._e
            if not e then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(e.spellID) -- raw-id: a catalog entry
            GameTooltip:AddLine("Spell ID: " .. e.spellID, COL.arc[1], COL.arc[2], COL.arc[3])
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            b:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
            if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end)
        b:SetScript("OnClick", function()
            local e = b._e
            if not e then return end
            pick(e.spellID)
            Refresh(true)
        end)
        btns[i] = b
        return b
    end
    local function Show(results, head)
        status:SetText(head)
        local shown = 0
        for i = 1, BGO.SUG_N do
            local b = Btn(i)
            local e = results and results[i]
            b._e = e
            if e then
                shown = shown + 1
                b.tex:SetTexture(e.texture or 134400)
                local mx = tonumber(e.maxCharges)
                b.name:SetText((mx and mx > 1) and (e.name .. "  |cff" .. AT.Hex(COL.arc) .. "(" .. mx .. " charges)|r")
                    or e.name)
                b.id:SetText(tostring(e.spellID))
                b:Show()
            else
                b:Hide()
            end
        end
        -- a pass running this places the new height itself
        if Options.SuggestFit(row, shown, 1, 0) and not syncing and row:IsShown() then
            AT.LayoutPage(pg)
        end
    end
    Refresh = function(force)
        if not row:IsShown() then return end
        local text = (getText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == lastText and not force then return end
        lastText = text
        if text == "" then
            Show(nil, "TYPE THE SPELL'S NAME to pick it from your spellbook, or type its ID")
            return
        end
        local id = tonumber(text)
        if id then
            local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the ID typed in the box
            Show(nil, nm and (id .. " is " .. nm) or (id .. " is no spell this game knows"))
            return
        end
        local results = NS.SpellCatalog and NS.SpellCatalog.Search(text, BGO.SUG_N) or {}
        if #results == 0 then
            Show(nil, "Nothing in your spellbook has that name: its spell ID still works")
        else
            Show(results, ("%d SPELL%s MATCH - click one to pick it"):format(#results, (#results == 1) and "" or "S"))
        end
    end
    -- every re-layout re-judges, but only a changed field searches again
    row._sync = function()
        syncing = true
        Refresh(false)
        syncing = false
    end
    -- test handles: the status line and the buttons
    row._adLines, row._adBtns = lines, btns
    return Refresh
end

-- The aura rows of glow k when it tracks another aura than the bar's own:
-- the aura bar's Tracking rows (name or ID, rank, type, unit, caster) pointed
-- at the glow's own record. One record each: hidden while several bars are
-- edited together.
function BGO.AuraRows(pg, ctx, win, k, cardVis)
    local AT = NS.AT
    local Store = NS.Store
    local DA = NS.DriverAura
    local suf = BGO.Suf(k)
    local function Rec()
        local r = ctx()
        if not r or r._adMulti then return nil end
        return r
    end
    -- the glow is on and tracks an aura
    local function auraVis()
        local r, Gl = Rec(), Glow()
        if not (cardVis() and r and Gl) then return false end
        if Store.Resolve(r, "glows", "barGlow" .. suf) ~= true then return false end
        return Gl.Family(r, k) == "aura"
    end
    local function otherVis()
        local r = Rec()
        return auraVis() and not BGO.Own(r, k)
    end
    local function Edit(fn)
        local r = Rec()
        if not r then return end
        fn(BGO.Aura(r, k, true), r)
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end
    -- found by the search with the glow off; the jump flashes the card's switch
    local function Stamp(row, field, label, baseVis)
        row._adMeta = { family = "bar", section = "glows", field = field,
            def = { label = label, dep = { field = "barGlow" .. suf } }, baseVis = baseVis }
    end
    local function stampVis()
        local r = Rec()
        return cardVis() and r ~= nil
    end
    local function stampOtherVis()
        local r = Rec()
        return stampVis() and not BGO.Own(r, k)
    end

    -- the glow's IDs as the aura icons keep theirs: spellID, spellIDs past one
    local function IDsText()
        local r = Rec()
        local g = r and BGO.Aura(r, k, false)
        return g and table.concat(Store.AuraIDList(g), ", ") or ""
    end
    -- every number typed, in order, once; words with no ID change nothing,
    -- and the same list is no edit, so its lane is never sent it again
    local function Commit(v)
        local ids = Options.ParseSpellIDs(v)
        if #ids == 0 or table.concat(ids, ", ") == IDsText() then return end
        Edit(function(g) Options.SetAuraSpellIDs(g, ids) end)
    end
    local idRow = AT.RowInput(pg, BGO.AURA_IDS, IDsText, Commit, otherVis,
        "Type the aura's name and click one to add its ID, or type IDs separated by commas or spaces. Any of them lights the glow.",
        "e.g. 2825, 32182")
    Stamp(idRow, "glowAuraID" .. suf, BGO.AURA_IDS, stampOtherVis)
    -- a pick from the name search joins the IDs already there
    local function Add(v)
        local r = Rec()
        if not r then return end
        local changed = Options.AddAuraSpellID(BGO.Aura(r, k, true), v)
        if changed then Store.Dirty("style", r.id) end
        if idRow._colCtrl then idRow._colCtrl:SetText(IDsText()) end
        AT.LayoutPage(pg)
    end
    -- a name typed after the IDs already in the box is what is searched
    local function Typed()
        local eb = idRow._colCtrl
        local t = eb and eb:GetText() or ""
        if t:find("%a") then t = t:gsub("^[%d%s,;]+", "") end
        return t
    end
    local Suggest = Options.AuraSuggestPanel and Options.AuraSuggestPanel(pg, otherVis, Typed, Add,
        false, nil, true)
    if Suggest and idRow._colCtrl then
        idRow._colCtrl:HookScript("OnTextChanged", function(_, userInput)
            if userInput then Suggest(false) end
        end)
    end
    -- test handles: the commit, the pick and the panel's refresh
    idRow._adCommit, idRow._adAdd, idRow._adSuggest = Commit, Add, Suggest

    AT.RowToggle(pg, "Follow my rank",
        function()
            local r = Rec()
            local g = r and BGO.Aura(r, k, false)
            return g == nil or g.followRank ~= false
        end,
        function(v)
            Edit(function(g) if v then g.followRank = nil else g.followRank = false end end)
        end,
        function() return otherVis() and NS.IsForever == true end,
        Options.FOLLOW_RANK_DESC)

    local typeRow = AT.RowDropdown(pg, win, "Aura type",
        function()
            local r = Rec()
            local g = r and BGO.Aura(r, k, false)
            return (g and g.auraType) or "buff"
        end,
        function(v)
            Edit(function(g)
                -- keep the unit it watches now, moved off one this type cannot match on
                local unit = DA.ShapeOf(g)
                g.auraType = v
                if not Options.AuraUnitAllowed(g, unit, v) then unit = "target" end
                g.unit = unit
            end)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        otherVis)
    Stamp(typeRow, "glowAuraType" .. suf, "Aura type", stampOtherVis)

    local unitRow = AT.RowDropdown(pg, win, "On unit",
        function()
            local r = Rec()
            return (DA.ShapeOf(r and BGO.Aura(r, k, false) or {}))
        end,
        function(v) Edit(function(g) g.unit = v end) end,
        function()
            local r = Rec()
            local g = r and BGO.Aura(r, k, false) or {}
            return Options.AuraUnitItems(g, nil, (DA.ShapeOf(g)))
        end,
        otherVis)
    AT.Tooltip(unitRow, "On unit", "Who carries the aura. Buffs match on friends and you, debuffs on enemies.")
    Stamp(unitRow, "glowAuraUnit" .. suf, "On unit", stampOtherVis)

    local casterRow = AT.RowDropdown(pg, win, "Cast by",
        function()
            local r = Rec()
            local _, _, caster = DA.ShapeOf(r and BGO.Aura(r, k, false) or {})
            return caster or "any"
        end,
        function(v)
            Edit(function(g)
                g.caster = (v ~= "any") and v or nil
                g.ownOnly = nil
            end)
        end,
        function() return Options.AURA_CASTER_ITEMS end,
        otherVis)
    AT.Tooltip(casterRow, "Cast by", "Anyone, only yours (or your pet's), or only other players' copies of the aura.")
    Stamp(casterRow, "glowAuraCaster" .. suf, "Cast by", stampOtherVis)
end

-- A saved Recharging on a spell with no charges: one plain line, never a
-- silent dead pick. One record's spell: hidden over several bars.
function BGO.StaleNote(pg, ctx, k, cardVis)
    local Store = NS.Store
    local suf = BGO.Suf(k)
    local row = NS.AT.RowDesc(pg, BGO.STALE_NOTE, 20, function()
        local r, Gl = ctx(), Glow()
        if not (cardVis() and r and Gl) or r._adMulti then return false end
        return Store.Resolve(r, "glows", "barGlow" .. suf) == true and Gl.StaleRecharge(r, k) == true
    end)
    row._adStale = k
    return row
end

-- c: AD_Options' block builders for the bar pane (BarBlock, SubPush,
-- SectionRows, BarTabVisible).
function Options.BarGlowRows(pg, ctx, win, c)
    local Store = NS.Store
    local Schema = NS.Schema
    local slots = (Schema and Schema.BAR_GLOW_SLOTS) or 3
    local vis1
    for k = 1, slots do
        if Options.BuildYield then Options.BuildYield() end
        local suf = BGO.Suf(k)
        local fields, labels = { "barGlow" .. suf, "barGlowWhen" .. suf }, {}
        labels["barGlowWhen" .. suf] = BGO.WORDS.When
        local rest = {}
        for _, key in ipairs(BGO.REST) do
            local f = "barGlow" .. key .. suf
            fields[#fields + 1] = f
            rest[#rest + 1] = f
            labels[f] = BGO.WORDS[key]
        end
        -- glow 1 carries the count in its push list
        if k == 1 then fields[#fields + 1] = "barGlowCount" end
        local vis
        -- registered as a look block for the Defaults page; glows never
        -- inherit, so the layout looks leave them out
        vis = c.BarBlock("Glow " .. k, "glows", "Conditions", fields,
            function(r) return k <= ((NS.Bars and NS.Bars.Glow and NS.Bars.Glow.Count(r)) or 1) end,
            "Glows", nil, { card = {
                when = function(r)
                    if Store.Resolve(r, "glows", "barGlow" .. suf) ~= true then return "" end
                    local w = BGO.WHEN_WORDS[Store.Resolve(r, "glows", "barGlowWhen" .. suf) or "up"]
                    return w and ("while " .. w) or ""
                end,
                word = "Glow " .. k,
                -- what it tracks, which one, then the state that lights it
                rows = function(cardVis)
                    BGO.TrackRow(pg, ctx, win, k, cardVis)
                    BGO.AuraRows(pg, ctx, win, k, cardVis)
                    BGO.SpellRows(pg, ctx, win, k, cardVis)
                    c.SectionRows(pg, "bar", "glows", ctx, cardVis, { "barGlowWhen" .. suf }, { labels = labels })
                    BGO.StaleNote(pg, ctx, k, cardVis)
                    c.SectionRows(pg, "bar", "glows", ctx, cardVis, rest, { labels = labels })
                end } })
        if k == 1 then vis1 = vis end
    end
    -- "+ Add glow" / "Remove last glow", then the push bar
    NS.AT.Section(pg, nil, { visibleFn = vis1 })
    c.SectionRows(pg, "bar", "glows", ctx, vis1, { "barGlowCount" })
    c.SubPush("Conditions", "Glows")
    -- the preview follows the sub-tab as it opens and closes
    if hooksecurefunc and not BGO.hooked then
        BGO.hooked = true
        hooksecurefunc(NS.AT, "LayoutPage", function(p)
            if p ~= pg then return end
            local open = Options.BarGlowsOpen()
            if open ~= BGO.lastOpen then
                BGO.lastOpen = open
                local G = NS.Bars and NS.Bars.Glow
                if G and G.PreviewSync then G.PreviewSync() end
            end
        end)
    end
end
