-- AD_TextPinOptions: the rows under a text that pin it to another frame
-- (Core\AD_TextAnchor.lua): where it rides, the frame name, the spell or the
-- cooldown ID, Pick Frame, and a line saying where it is now. One builder for
-- every text, called behind a nil check by the editors.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

-- pg / ctx / vis as every row builder; family, section and the two field
-- names say where the pin lives; word names the text ("Stack text").
function Options.TextPinRows(pg, ctx, vis, family, section, toKey, targetKey, owner, word)
    local AT, Store, Schema, COL = NS.AT, NS.Store, NS.Schema, NS.AT.COL
    local FP = NS.FramePicker
    local defs = Schema[family] and Schema[family][section] and Schema[family][section].fields or {}
    local function Kind()
        local r = ctx()
        return r and Store.Resolve(r, section, toKey) or "own"
    end
    local function Target()
        local r = ctx()
        return r and (Store.Resolve(r, section, targetKey) or "") or ""
    end
    local function SetTarget(v)
        local r = ctx()
        if r and v then Store.SetOverride(r, section, targetKey, v) end
    end
    local function Is(...)
        local k = Kind()
        for i = 1, select("#", ...) do if k == select(i, ...) then return true end end
        return false
    end
    local pinned = function() return vis() and Is("frame", "action", "cdm") end
    local function Stamp(row, field)
        row._adMeta = { family = family, section = section, field = field, def = defs[field], baseVis = vis }
    end

    local items = {}
    for _, k in ipairs(Schema.PIN_TO) do items[#items + 1] = { value = k, text = Schema.PIN_LABELS[k] } end
    local ddRow = AT.RowDropdown(pg, owner, word .. " pinned to",
        function() return Kind() end,
        function(v)
            local r = ctx()
            if not r then return end
            -- a frame name is no spell and a spell no frame: a switch starts empty
            if v ~= Kind() then Store.SetOverride(r, section, targetKey, "") end
            Store.SetOverride(r, section, toKey, v)
        end,
        function() return items end, vis,
        function() AT.LayoutPage(pg) end)
    Stamp(ddRow, toKey)
    AT.Tooltip(ddRow, word .. " pinned to",
        "Its own spot, or riding another frame: it follows that frame and goes back to its own spot while the frame is not on screen.")

    local nameRow = AT.RowInput(pg, "Frame name", Target,
        function(v) SetTarget((tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))) end,
        function() return vis() and Is("frame") end,
        "The game frame's name, as Pick Frame shows it. Enter applies it.", "e.g. PlayerFrame")
    Stamp(nameRow, targetKey)
    if FP and FP.CommonItems then
        AT.RowDropdown(pg, owner, "Common frames",
            function() local n = Target(); return (FP.IsCommon(n) and n) or "" end,
            function(v) if v ~= "" then SetTarget(v) end end,
            FP.CommonItems, function() return vis() and Is("frame") end,
            function() AT.LayoutPage(pg) end)
    end
    AT.RowInput(pg, "Spell",
        function()
            local t = Target()
            return (FP and FP.CooldownID(t)) and "" or t
        end,
        function(v)
            local spec = FP and FP.SpellSpec(v)
            if spec then SetTarget(spec) end
        end,
        function() return vis() and Is("action", "cdm") end,
        "The spell whose button or icon it rides: a spell ID, a link or the name of a spell you know. Enter applies it.",
        "e.g. 17364")
    AT.RowInput(pg, "Cooldown ID",
        function() return tostring((FP and FP.CooldownID(Target())) or "") end,
        function(v)
            local spec = FP and FP.CooldownSpec(v)
            if spec then SetTarget(spec) end
        end,
        function() return vis() and Is("cdm") end,
        "The icon's exact entry in the Cooldown Manager; Pick Frame on an icon fills it. Empty uses the spell above.",
        "e.g. 12821")

    local pick
    pick = AT.RowButton(pg, "Pick Frame", function()
        local r = ctx()
        if not (r and FP) then return end
        local id = r.id
        local ok = FP.Start(function(name, item)
            local rec = Store.Get(id)
            if not rec then return end
            if item and item.spec then
                Store.SetOverride(rec, section, toKey, item.value)
                Store.SetOverride(rec, section, targetKey, item.spec)
            elseif name then
                Store.SetOverride(rec, section, toKey, "frame")
                Store.SetOverride(rec, section, targetKey, name)
            end
            AT.LayoutPage(pg)
        end, r, true)
        if not ok then
            pick.button.fs:SetText("Not in combat")
            C_Timer.After(2, function() pick.button.fs:SetText("Pick Frame") end)
        end
    end, pinned, 110, "Pick it on screen")
    AT.Tooltip(pick.button, "Pick Frame",
        "Hover a game frame, an action button or a Cooldown Manager icon and left-click it. Right-click or Esc cancels.")

    -- where it is now, in words
    local line = AT.AddRow(pg, 30, pinned)
    local fs = line:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -4)
    fs:SetPoint("TOPRIGHT", -10, -4)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    line._sync = function()
        local TA = NS.TextAnchor
        fs:SetText(TA and TA.Describe(Kind(), Target()) or "")
    end
    pg:HookScript("OnHide", function() if FP then FP.Stop() end end)
end
