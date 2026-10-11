-- AD_ImportPTOptions: Import from ArcUI ProcTracker, the "Proc Tracker" tab of the
-- Import / Export page (UI\AD_Options.lua hosts it through PW.TabShown, PW.BuildPane and
-- PW.Refresh): a box of its icons beside one of its bars, a tick per part ArcUI
-- ProcTracker has settings for (the switched-on ones ticked); Import copies the ticked
-- ones through MigratePT.Import into a new layout, again any time. The New Layout card,
-- the login offer (Store.UI().ptOffer) and /arcui2 proctracker open the tab. Retail only.
local ADDON, NS = ...
if NS.IsForever == true then return end

local Options = NS.Options
if not Options then return end

local PW = {}
Options.ImportPT = PW

PW.ROW_H = 24
PW.NOTE_H = 26
PW.GAP = 10
PW.FOOT_H = 40
PW.HEAD_H = 26
PW.BOXES = { { "ICONS", { icon = true, aura = true } }, { "BARS", { bar = true } } }

local pane
local cands, picks = {}, nil
-- the foot bar's lines after an import or a refusal: { text, text2, bad }
local said
local W = { rows = {} }
-- for harnesses: the widgets
PW.W = W

-- Which parts are ticked, for a check.
function PW.Ticked(key) return picks ~= nil and picks[key] == true end

local function Font(parent, size, col) return Options.ImportKit.Line(parent, size, col) end

-- A part's row: its tick, its name, then what it is there (imported, off, another class).
local function Row(i)
    local r = W.rows[i]
    if r then return r end
    local AT, COL = NS.AT, NS.AT.COL
    r = CreateFrame("Button", nil, pane)
    r:SetHeight(PW.ROW_H)
    r:SetHighlightTexture(AT.WHITE)
    r:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    r.check = Options.ImportKit.Check(r)
    r.check:SetPoint("LEFT", 10, 0)
    r.name = Font(r, 12, COL.ink)
    r.name:SetPoint("LEFT", r.check, "RIGHT", 9, 0)
    r.tag = Options.ImportKit.Pill(r)
    r.tag:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    local function Flip() if r.onTick then r.onTick() end end
    r:SetScript("OnClick", Flip)
    r.check:SetScript("OnClick", Flip)
    r:HookScript("OnEnter", function() r.check:SetHover(true) end)
    r:HookScript("OnLeave", function() r.check:SetHover(false) end)
    W.rows[i] = r
    return r
end

-- What Import brings, and whether some of it is here already.
local function PaintFoot()
    local COL = NS.AT.COL
    local MP = NS.MigratePT
    local icons, bars, again = 0, 0, 0
    for _, c in ipairs(cands) do
        if picks and picks[c.key] then
            if c.part == "bar" then bars = bars + 1 else icons = icons + 1 end
            if MP and MP.PartLive(c.key) then again = again + 1 end
        end
    end
    local text, text2, col = "", "", COL.ink
    if said then
        text, text2 = said.text or "", said.text2 or ""
        col = said.bad and { 1, 0.45, 0.4 } or { 0.498, 0.824, 0.557 }
    elseif icons + bars == 0 then
        text, col = "Nothing ticked yet.", COL.dim
    else
        local bits = {}
        if icons > 0 then bits[#bits + 1] = icons .. (icons == 1 and " icon" or " icons") end
        if bars > 0 then bits[#bits + 1] = bars .. (bars == 1 and " bar" or " bars") end
        text = "Brings " .. table.concat(bits, " and ") .. " into a new ProcTracker layout."
        if again > 0 then
            text2 = ((again == 1) and "1 of them is" or (again .. " of them are"))
                .. " in Arc Auras already: importing again adds a second copy."
        end
    end
    W.sum:SetText(text)
    W.sum:SetTextColor(col[1], col[2], col[3])
    W.sum2:SetText(text2)
    W.sum2:SetShown(text2 ~= "")
    W.sum:ClearAllPoints()
    W.sum:SetPoint("LEFT", W.foot, "LEFT", 12, (text2 ~= "") and 7 or 0)
    W.sum:SetPoint("RIGHT", W.importBtn, "LEFT", -12, (text2 ~= "") and 7 or 0)
    -- once the trackers moved and nothing is on there, ArcUI ProcTracker can go
    local spent = said ~= nil and not said.bad and MP ~= nil and MP.Loaded() and not MP.AnyOn()
    W.offPT:SetShown(spent)
    local any = icons + bars > 0
    W.importBtn:SetAlpha(any and 1 or 0.45)
    W.importBtn:EnableMouse(any)
end

function PW.Paint()
    if not pane then return end
    local COL = NS.AT.COL
    local MP = NS.MigratePT
    local ok = MP ~= nil and MP.Loaded() and #cands > 0
    for _, b in ipairs(W.boxes) do b:SetShown(ok) end
    W.foot:SetShown(ok)
    W.onBtn:Hide()
    for _, r in ipairs(W.rows) do r:Hide() end
    if not ok then
        if MP and not MP.Loaded() then
            W.off:SetText("ArcUI ProcTracker is turned off, so its settings cannot be read. Turn it on and reload, then come back here.")
            W.onBtn:Show()
        else
            W.off:SetText("ArcUI ProcTracker has no trackers set up to copy.")
        end
        W.off:Show()
        return
    end
    W.off:Hide()
    -- the two boxes side by side, each as tall as its rows
    local pw = (pane:GetWidth() or 0)
    if pw < 200 then pw = 760 end
    local bw = math.floor((pw - 4 - PW.GAP) / 2)
    local n = 0
    for bi, B in ipairs(PW.BOXES) do
        local box = W.boxes[bi]
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", pane, "TOPLEFT", (bi - 1) * (bw + PW.GAP), -PW.NOTE_H)
        box:SetWidth(bw)
        local y, count = PW.HEAD_H + 2, 0
        for _, c in ipairs(cands) do
            if B[2][c.part] then
                n, count = n + 1, count + 1
                local r = Row(n)
                r:SetParent(box)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -y)
                r:SetWidth(bw - 2)
                local on = picks and picks[c.key] == true
                r.check:SetState(on and "on" or "off")
                r.name:SetText(c.name)
                r.name:SetTextColor((on and COL.ink or COL.dim)[1], (on and COL.ink or COL.dim)[2], (on and COL.ink or COL.dim)[3])
                local tag
                if MP.PartLive(c.key) then
                    tag = Options.ImportKit.TAGS.done
                    r.tag:Set(tag)
                elseif c.other then
                    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
                    tag = Options.ImportKit.TAGS.later
                    r.tag:Set(tag, tostring((names and names[c.other]) or c.other))
                elseif c.off then
                    tag = Options.ImportKit.TAGS.off
                    r.tag:Set(tag)
                end
                r.tag:SetShown(tag ~= nil)
                r.onTick = function()
                    picks = picks or {}
                    picks[c.key] = (not picks[c.key]) or nil
                    said = nil
                    PW.Paint()
                end
                r:Show()
                y = y + PW.ROW_H
            end
        end
        box.right:SetText(tostring(count))
        box:SetHeight(y + 3)
    end
    PaintFoot()
end

-- Reads ArcUI ProcTracker's parts each time the tab shows (an import switches them
-- off there); the switched-on ones start ticked.
function PW.Refresh()
    if not pane then return end
    local MP = NS.MigratePT
    cands = MP and MP.Loaded() and MP.Candidates() or {}
    if picks == nil then
        picks = {}
        for _, c in ipairs(cands) do
            if not c.off and not c.other then picks[c.key] = true end
        end
    end
    PW.Paint()
end

-- The tab shows while ArcUI ProcTracker is installed (its settings read once it is on).
function PW.TabShown()
    local MP = NS.MigratePT
    return MP ~= nil and MP.Installed()
end

function PW.BuildPane(parent)
    if pane then return pane end
    local AT, COL = NS.AT, NS.AT.COL
    pane = CreateFrame("Frame", nil, parent)
    W.note = Font(pane, 12, COL.ink)
    W.note:SetPoint("TOPLEFT", 4, -2)
    W.note:SetText("Pick what comes over from Proc Tracker into a ProcTracker layout. You can import again any time.")
    W.boxes = {}
    for i, B in ipairs(PW.BOXES) do
        W.boxes[i] = Options.ImportKit.Box(pane, B[1])
    end
    -- the foot bar: what Import brings, then Import
    local fb = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    AT.Skin(fb, COL.box, COL.line2)
    fb:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 6)
    fb:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -4, 6)
    fb:SetHeight(PW.FOOT_H)
    W.foot = fb
    local imp = AT.MakeSmallButton(fb, "Import", 84)
    imp:SetHeight(24)
    imp:SetPoint("RIGHT", -8, 0)
    imp:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    imp:SetScript("OnLeave", function()
        imp:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        imp:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end)
    imp:SetScript("OnClick", function() PW.DoImport() end)
    W.importBtn = imp
    local offPT = AT.MakeQuietButton(fb, "Turn ArcUI ProcTracker off and reload", 250)
    offPT:SetHeight(24)
    offPT:SetPoint("RIGHT", imp, "LEFT", -8, 0)
    offPT:SetScript("OnClick", function() PW.SetAddon(false) end)
    offPT:Hide()
    W.offPT = offPT
    W.sum = Font(fb, 12, COL.ink)
    W.sum2 = Font(fb, 11, COL.dim)
    W.sum2:SetPoint("LEFT", fb, "LEFT", 12, -8)
    W.sum2:SetPoint("RIGHT", imp, "LEFT", -12, -8)
    -- ArcUI ProcTracker off, or nothing to copy: one line where the boxes would be
    W.off = Font(pane, 12, COL.dim)
    W.off:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -(PW.NOTE_H + 4))
    W.off:SetPoint("RIGHT", pane, "RIGHT", -10, 0)
    W.off:SetWordWrap(true)
    W.onBtn = AT.MakeSmallButton(pane, "Turn it on and reload", 170)
    W.onBtn:SetPoint("TOPLEFT", W.off, "BOTTOMLEFT", 0, -10)
    W.onBtn:SetScript("OnClick", function() PW.SetAddon(true) end)
    pane:SetScript("OnSizeChanged", function() PW.Paint() end)
    pane:SetScript("OnShow", function() PW.Refresh() end)
    return pane
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

function PW.DoImport()
    local MP = NS.MigratePT
    if not (MP and picks) or next(picks) == nil then return end
    local res, err = MP.Import(picks)
    if not res then
        said = { text = err or "The import did not run.", bad = true }
        PW.Paint()
        return
    end
    -- imported: the login offer has done its job
    local ui = NS.Store.UI and NS.Store.UI()
    if ui then ui.ptOffer = "done" end
    picks = {}
    said = { text = "Imported: the new ProcTracker layout is in the sidebar.",
        text2 = "Not right? Delete the layout and import it again." }
    if Options.RefreshAll then Options.RefreshAll() end
    PW.Refresh()
end

-- Opens the tab: the card, the login offer and /arcui2 proctracker come here.
function PW.Open()
    if Options.OpenImportTab then Options.OpenImportTab("pt") end
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

-- The card's picture: ProcTracker's own icon handing its icons to an Arc
-- Auras square.
PW.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\ProcTracker_Icon_128"
function PW.DrawCard(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local NL = NS.NewLayout
    local W2, H = NL.STAGE_W, NL.STAGE_H
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
    NL.SourceIcon(stage, PW.ICON)
    Box(W2 / 2 + 22, (H - 36) / 2, 44, 36, COL.arc, 1)
    local head = AT.MakeChevron(stage)
    head:SetDir("right")
    head:SetColor(COL.arc)
    head:SetScale(2)
    head:SetPoint("CENTER", stage, "TOPLEFT", (W2 / 2) / 2, -(H / 2) / 2)
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
