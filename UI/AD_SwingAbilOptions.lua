-- AD_SwingAbilOptions: a main-hand swing bar's next-swing abilities as a list, in the Next Swing block of the bar editor's Appearance > Swing.
-- AD_Options calls Options.SwingAbilRows while it builds the bar pane; every edit goes through NS.Bars.SwingAbil.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local function SA() return NS.Bars and NS.Bars.SwingAbil end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- A row's label: the spell's icon, then its name (the rank the player knows),
-- marked while no rank of it is known.
function Options.SwingAbilLabel(id)
    local CS, St = C_Spell, NS.Store
    -- the one resolve, as the markers read it
    local sid = St.TrackedSpellID(tonumber(id), true, false) or id
    local known = St.KnowsSpell(tonumber(id)) ~= false
    local tex = (CS and CS.GetSpellTexture and CS.GetSpellTexture(sid)) or 134400
    local nm = CS and CS.GetSpellName and CS.GetSpellName(sid)
    if Secret(nm) or type(nm) ~= "string" or nm == "" then nm = "Spell " .. tostring(id) end
    local text = ("|T%s:18:18:0:0:64:64:5:59:5:59|t  %s"):format(tostring(tex), nm)
    if not known then
        local f = NS.AT.COL.faint
        local function B(v) return math.floor(v * 255 + 0.5) end
        text = text .. ("  |cff%02x%02x%02x(not known yet)|r"):format(B(f[1]), B(f[2]), B(f[3]))
    end
    return text
end

-- The rank picks for one ability: any, the highest, then each rank the
-- player knows; a picked rank that is not known stays listed so it shows.
function Options.SwingAbilRankItems(id, cur)
    local out = { { value = 0, text = "Any rank" }, { value = -1, text = "Highest rank" } }
    local S = SA()
    local seen = {}
    if id and S and S.Ranks then
        for _, r in ipairs(S.Ranks(id)) do
            if r.rank and not seen[r.rank] then
                seen[r.rank] = true
                out[#out + 1] = { value = r.rank, text = "Rank " .. r.rank }
            end
        end
    end
    cur = tonumber(cur)
    if cur and cur > 0 and not seen[cur] then
        out[#out + 1] = { value = cur, text = "Rank " .. cur .. " (not known)" }
    end
    return out
end

-- vis: the Next Swing block's own gate. owner: the window the dropdown lists
-- open on. Returns the add row.
function Options.SwingAbilRows(pg, ctx, vis, owner)
    local AT = NS.AT
    local function Rec()
        local r = ctx()
        return (r and r.barKind == "swing" and SA()) and r or nil
    end
    local function List()
        local r = Rec()
        return r and SA().List(r) or {}
    end
    -- the list shows while the switch is on, for one bar at a time (the
    -- abilities are that bar's own)
    local function onVis()
        local r = Rec()
        return vis() and r ~= nil and not r._adMulti
            and NS.Store.Resolve(r, "fill", "swingAbilities") == true
    end
    -- an edit, then the page again at once (the store's refresh comes a frame later)
    local function Edit(fn)
        local r = Rec()
        if r then fn(SA(), r) end
        AT.LayoutPage(pg)
    end
    -- ranks exist on Forever only
    local ranked = NS.IsForever == true
    local maxN = (SA() and SA().Max()) or 8
    local rankTip = "Any rank: the marker follows whichever rank you queue. Highest rank: only your best one. "
        .. "A rank: only that one, such as a cheaper rank you queue to save mana."

    AT.RowDesc(pg, "No abilities yet: add one below.", 20, function() return onVis() and #List() == 0 end)
    for i = 1, maxN do
        if Options.BuildYield then Options.BuildYield() end
        local row = AT.AddRow(pg, AT.LAY.rowH + 2, function() return onVis() and List()[i] ~= nil end)
        local lbl = AT.RowLabel(row, "")
        local dd
        if ranked then
            dd = AT.MakeDropdown(owner, row, 130,
                function()
                    local a = List()[i]
                    return Options.SwingAbilRankItems(a and a.id, a and a.rank)
                end,
                function()
                    local a = List()[i]
                    return a and a.rank or 0
                end,
                function(v) Edit(function(S, r) S.SetRank(r, i, v) end) end)
            dd:SetPoint("LEFT", row._ctrlX, 0)
            AT.Tooltip(dd, "Rank", rankTip)
        end
        local rm = AT.MakeQuietButton(row, "Remove", 70)
        if dd then
            rm:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        else
            rm:SetPoint("LEFT", row._ctrlX, 0)
        end
        rm:SetScript("OnClick", function()
            AT.CloseDropdown()
            Edit(function(S, r) S.Remove(r, i) end)
        end)
        row._colLabel, row._colCtrl = lbl, dd or rm
        row._colTrail = dd and 78 or 0
        row._adRank, row._adRemove = dd, rm
        row._sync = function()
            local a = List()[i]
            if not a then return end
            lbl:SetText(Options.SwingAbilLabel(a.id))
            if dd then dd.Refresh() end
        end
    end

    -- Add: a spell name or ID, then the button or Enter
    local pending = ""
    local addRow = AT.RowInput(pg, "Add an ability",
        function() return pending end,
        function(v) pending = v or "" end,
        function() return onVis() and #List() < maxN end,
        "A spell name or ID, such as Raptor Strike, Heroic Strike, Cleave or Maul. "
            .. "Its marker shows where it comes off cooldown and while it is queued.",
        "name or ID", true)
    local box = addRow._colCtrl
    -- the box is read and cleared before focus drops: the focus-lost commit
    -- would write its text back into `pending`
    local function DoAdd()
        local txt = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt == "" then return end
        local DR = NS.DriverRange
        local id = (DR and DR.ParseSpell and DR.ParseSpell(txt)) or tonumber(txt)
        -- a name the game does not know: the text stays, to fix
        if not id then return end
        local r = Rec()
        if r then SA().Add(r, id) end
        box:SetText("")
        pending = ""
        if box:HasFocus() then box:ClearFocus() end
        AT.LayoutPage(pg)
    end
    local add = AT.MakeSmallButton(addRow, "Add", 56)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    add:SetScript("OnClick", function()
        AT.CloseDropdown()
        DoAdd()
    end)
    box:HookScript("OnEnterPressed", DoAdd)
    addRow._colTrail = 62
    addRow._adAdd = add
    -- found by the search while the switch is off; the jump flashes the switch
    addRow._adMeta = { family = "bar", section = "fill", field = "swingAbilIDs",
        def = { label = "Add an ability", dep = { field = "swingAbilities" } }, baseVis = vis }
    return addRow
end
