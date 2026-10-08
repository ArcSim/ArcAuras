-- AD_ImportPTOptions: the "Import from ArcUI ProcTracker" card on the New Layout page
-- and its window: a tick per tracker part ArcUI ProcTracker has settings for (its
-- icon, its bar, the Power Infusion icon), the switched-on ones ticked; Import
-- copies the ticked ones through MigratePT.Import into a new layout. At login, a
-- small offer opens the window while something there is switched on, until an
-- import or "Don't ask again" (Store.UI().ptOffer). Retail only.
local ADDON, NS = ...
if NS.IsForever == true then return end

local Options = NS.Options
if not Options then return end

local PW = {}
Options.ImportPT = PW

PW.MAX_ROWS = 20
PW.PART_WORDS = { icon = "icon", bar = "deck bar", aura = "icon" }

local win, page, status, done
local cands, picks = {}, {}

local function Line(pg, h, textFn, visibleFn)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(pg, h, visibleFn)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, 11, "")
    fs:SetPoint("TOPLEFT", 10, -3)
    fs:SetPoint("TOPRIGHT", -10, -3)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    row._sync = function() fs:SetText(textFn() or "") end
    row.fs = fs
    return row
end

local function Picked()
    local n = 0
    for _ in pairs(picks) do n = n + 1 end
    return n
end

-- A row's words: the tracker, the part, and a dim mark on one switched off there.
function PW.RowText(c)
    local note = ""
    if c.off then
        note = "  |cff8fa3b8(off in ProcTracker)|r"
    elseif c.other then
        local L = LOCALIZED_CLASS_NAMES_MALE
        note = "  |cff8fa3b8(" .. tostring((L and L[c.other]) or c.other) .. ")|r"
    end
    return c.name .. "  " .. (PW.PART_WORDS[c.part] or c.part) .. note
end

-- Which parts are ticked (the window's picks), for a check.
function PW.Ticked(key) return picks[key] == true end

-- One tickable row per candidate, pooled: the list is read on every open.
local function PickRow(i)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(page, 22, function() return cands[i] ~= nil end)
    row.box = AT.MakeCheckbox(row)
    row.box:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.fs = row:CreateFontString(nil, "OVERLAY")
    row.fs:SetFont(NS.AT.FONT, 12, "")
    row.fs:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.fs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.fs:SetJustifyH("LEFT")
    row.fs:SetWordWrap(false)
    row.fs:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local function Flip()
        local c = cands[i]
        if not c then return end
        picks[c.key] = (not picks[c.key]) or nil
        PW.Refresh()
    end
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", Flip)
    row.box:SetScript("OnClick", Flip)
    row:HookScript("OnEnter", function() row.box:SetHover(true) end)
    row:HookScript("OnLeave", function() row.box:SetHover(false) end)
    row._sync = function()
        local c = cands[i]
        if not c then return end
        row.fs:SetText(PW.RowText(c))
        row.box:SetOn(picks[c.key] == true)
    end
    return row
end

function PW.Build()
    if win then return end
    local AT, COL = NS.AT, NS.AT.COL
    win = AT.CreateWindow("ArcAurasImportPT", {
        w = 480, h = 560, minW = 400, minH = 360, maxW = 900, maxH = 1000,
        title = NS.AT.Brand("Arc", " Auras"),
        onResize = function() if page then AT.LayoutPage(page) end end,
    })
    page = AT.NewPage(win)
    AT.MakeScrollable(page)
    page:SetPoint("TOPLEFT", 8, -38)
    page:SetPoint("BOTTOMRIGHT", -8, 8)
    page:Show()

    AT.Section(page, "Import from ArcUI ProcTracker")
    AT.RowDesc(page, "Copies the trackers you tick into a new ProcTracker layout, with the same places, sizes, texts, colors and sounds. Each one imported is switched off in ArcUI ProcTracker, so nothing shows twice.", 34)
    Line(page, 32, function()
        local MP = NS.MigratePT
        if MP and not MP.Loaded() then
            return "ArcUI ProcTracker is turned off, so its settings cannot be read. Turn it on and reload, then open this again."
        end
        if #cands == 0 then return "ArcUI ProcTracker has no trackers set up to copy." end
        return ""
    end, function()
        local MP = NS.MigratePT
        return (MP ~= nil and not MP.Loaded()) or #cands == 0
    end)
    local offVis = function() local MP = NS.MigratePT return MP ~= nil and not MP.Loaded() end
    AT.RowActions(page, {
        { label = "Turn it on and reload", w = 170, onClick = function() PW.SetAddon(true) end, visibleFn = offVis },
    }, "left", offVis)

    AT.Section(page, "What to import", { visibleFn = function() return #cands > 0 end })
    for i = 1, PW.MAX_ROWS do PickRow(i) end

    AT.Section(page, nil)
    AT.RowActions(page, {
        { label = "Import selected", w = 130, onClick = function() PW.DoImport() end,
            visibleFn = function() return #cands > 0 end },
        { label = "Close", w = 80, quiet = true, onClick = function() win:Hide() end },
    }, "left")
    status = Line(page, 34, function() return PW.StatusText() end).fs
    status:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    -- once the trackers moved, ArcUI ProcTracker can go
    local onVis = function() local MP = NS.MigratePT return done ~= nil and MP ~= nil and MP.Loaded() end
    AT.RowActions(page, {
        { label = "Turn ArcUI ProcTracker off and reload", w = 250, onClick = function() PW.SetAddon(false) end,
            visibleFn = onVis },
    }, "left", onVis)
    AT.LayoutPage(page)
end

function PW.StatusText()
    if done then
        local MP = NS.MigratePT
        local left = MP ~= nil and MP.AnyOn()
        return ("Imported %d icons and %d bars into the layout %s and switched them off in ArcUI ProcTracker.%s")
            :format(done.icons, done.bars, done.name or "ProcTracker",
                left and "" or " Nothing is left on there: you can turn it off.")
    end
    if #cands == 0 then return "" end
    return ("%d of %d ticked. Import makes a new layout; nothing you have in Arc Auras is touched."):format(Picked(), #cands)
end

-- ArcUI ProcTracker on (to read its settings) or off (once imported), then reload.
function PW.SetAddon(on)
    local A = C_AddOns
    if not (A and A.EnableAddOn and A.DisableAddOn) then return end
    local MP = NS.MigratePT
    local name = MP and MP.ADDON or "ArcUI_ProcTracker"
    if on then A.EnableAddOn(name) else A.DisableAddOn(name) end
    if ReloadUI then ReloadUI() end
end

function PW.Refresh()
    if not win then return end
    NS.AT.LayoutPage(page)
end

function PW.DoImport()
    local MP = NS.MigratePT
    if not MP then return end
    local res, err = MP.Import(picks)
    if not res then
        status:SetText(err or "The import did not run.")
        return
    end
    local L = NS.Store.Get(res.layoutId)
    done = { icons = res.icons, bars = res.bars, name = L and L.name }
    -- imported: the login offer has done its job
    local ui = NS.Store.UI and NS.Store.UI()
    if ui then ui.ptOffer = "done" end
    picks = {}
    PW.Refresh()
    if Options.RefreshAll then Options.RefreshAll() end
    if L and Options.OpenLayout then
        -- From the login offer the panel was never opened: open it on the new
        -- layout, then keep this window over it.
        if Options.Open then Options.Open() end
        Options.OpenLayout(L)
        if Options.WhenBuilt then
            Options.WhenBuilt(function() if win:IsShown() then win:Raise() end end)
        end
    end
end

function PW.Open()
    PW.Build()
    local MP = NS.MigratePT
    cands = MP and MP.Candidates() or {}
    while #cands > PW.MAX_ROWS do table.remove(cands) end
    picks, done = {}, nil
    for _, c in ipairs(cands) do
        if not c.off and not c.other then picks[c.key] = true end
    end
    win:Show()
    PW.Refresh()
end

-- The login offer: a small window, its three answers. "Not now" asks again
-- at the next login.
local offer
function PW.BuildOffer()
    if offer then return offer end
    local AT = NS.AT
    offer = AT.CreateWindow("ArcAurasImportPTOffer", {
        w = 460, h = 190, minW = 460, minH = 190, maxW = 460, maxH = 190,
        title = NS.AT.Brand("Arc", " Auras"),
    })
    local pg = AT.NewPage(offer)
    pg:SetPoint("TOPLEFT", 8, -38)
    pg:SetPoint("BOTTOMRIGHT", -8, 8)
    pg:Show()
    AT.Section(pg, "ArcUI ProcTracker found")
    AT.RowDesc(pg, "Trackers are switched on in ArcUI ProcTracker. Pick which ones come into Arc Auras, placed as they are.", 34)
    AT.RowActions(pg, {
        { label = "Start the import", w = 140, onClick = function()
            offer:Hide()
            PW.Open()
        end },
        { label = "Not now", w = 90, onClick = function() offer:Hide() end },
        { label = "Don't ask again", w = 130, quiet = true, onClick = function()
            local ui = NS.Store.UI and NS.Store.UI()
            if ui then ui.ptOffer = "never" end
            offer:Hide()
        end },
    }, "left")
    AT.LayoutPage(pg)
    return offer
end

-- Asked once a session while ArcUI ProcTracker has something switched on and
-- no import or "Don't ask again" answered it; never in combat (it waits for
-- the fight to end).
function PW.OfferOnLogin()
    local MP, Store = NS.MigratePT, NS.Store
    local ui = Store and Store.UI and Store.UI()
    if not (MP and ui and MP.Loaded()) or ui.ptOffer ~= nil then return end
    if InCombatLockdown and InCombatLockdown() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            PW.OfferOnLogin()
        end)
        return
    end
    if not MP.AnyOn() then return end
    PW.BuildOffer():Show()
end

-- After the first PLAYER_ENTERING_WORLD: the game closes windows opened
-- before it, and the store settles on the live saved variables there.
local loginEv = CreateFrame("Frame")
loginEv:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEv:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(3, PW.OfferOnLogin)
end)

-- The card's picture: a deck card handing its icon to an Arc Auras square.
function PW.DrawCard(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local NL = NS.NewLayout
    local W, H = NL.STAGE_W, NL.STAGE_H
    local function Box(x, y, w, h, c, n)
        local f = CreateFrame("Frame", nil, stage, "BackdropTemplate")
        f:SetSize(w, h)
        f:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -y)
        AT.Skin(f, COL.box, c)
        for i = 1, n do
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(c[1], c[2], c[3], 0.9)
            t:SetSize(w - 10, 4)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -6 - (i - 1) * 8)
        end
        return f
    end
    Box(W / 2 - 66, (H - 44) / 2, 34, 44, COL.dim, 3)
    Box(W / 2 + 22, (H - 36) / 2, 44, 36, COL.arc, 1)
    local head = AT.MakeChevron(stage)
    head:SetDir("right")
    head:SetColor(COL.arc)
    head:SetScale(2)
    head:SetPoint("CENTER", stage, "TOPLEFT", (W / 2) / 2, -(H / 2) / 2)
end

if NS.NewLayout and NS.NewLayout.AddOwnCard then
    PW.entry = {
        title = "Import from ArcUI ProcTracker",
        desc = "Pick which ArcUI ProcTracker icons and bars come into Arc Auras, placed as they are.",
        draw = PW.DrawCard,
        pick = function() PW.Open() end,
        avail = function()
            local MP = NS.MigratePT
            return MP ~= nil and MP.Installed()
        end,
    }
    NS.NewLayout.AddOwnCard(PW.entry)
end
