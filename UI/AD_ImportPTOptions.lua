-- AD_ImportPTOptions: Import from ArcUI ProcTracker, the "Proc Tracker" tab of the
-- Import / Export page (UI\AD_Options.lua hosts it through PW.TabShown, PW.BuildPane and
-- PW.Refresh): a box of its icons beside one of its bars, a tick per part ArcUI
-- ProcTracker has settings for (the switched-on ones ticked); Import copies the ticked
-- ones through MigratePT.Import into a new layout, again any time. At each load the
-- switched-on ones move by themselves (PW.MigrateOnLogin). The New Layout card and
-- /arcui2 proctracker open the tab. Retail only.
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
    local Tr = NS.AT.Tr
    local text, text2, col = "", "", COL.ink
    if said then
        text, text2 = Tr(said.text or ""), Tr(said.text2 or "")
        col = said.bad and { 1, 0.45, 0.4 } or { 0.498, 0.824, 0.557 }
    elseif icons + bars == 0 then
        text, col = Tr("Nothing ticked yet."), COL.dim
    else
        local bits = {}
        if icons > 0 then bits[#bits + 1] = Tr(icons == 1 and "%d icon" or "%d icons"):format(icons) end
        if bars > 0 then bits[#bits + 1] = Tr(bars == 1 and "%d bar" or "%d bars"):format(bars) end
        local what = (#bits == 2) and Tr("%s and %s"):format(bits[1], bits[2]) or bits[1]
        text = Tr("Brings %s into a new ProcTracker layout."):format(what)
        if again > 0 then
            text2 = Tr(again == 1 and "%d of them is in Arc Auras already: importing again adds a second copy."
                or "%d of them are in Arc Auras already: importing again adds a second copy."):format(again)
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
            W.off:SetText(NS.AT.Tr("ArcUI ProcTracker is turned off, so its settings cannot be read. Turn it on and reload, then come back here."))
            W.onBtn:Show()
        else
            W.off:SetText(NS.AT.Tr("ArcUI ProcTracker has no trackers set up to copy."))
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
    W.note:SetText(AT.Tr("Pick what comes over from Proc Tracker into a ProcTracker layout. You can import again any time."))
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

-- The look both login windows share, after ArcUI ProcTracker's own move notice
-- (the logo, a cyan title, the words), so the two read as one story. Escape
-- closes it like any other window.
PW.LOGO = "Interface\\AddOns\\ArcAuras\\Textures\\ArcAuras_Icon_256"
PW.NOTE_W = 460
function PW.NoteFrame(name, titleText, bodyText, w)
    local AT, COL = NS.AT, NS.AT.COL
    w = w or PW.NOTE_W
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, 160)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    AT.Skin(f, COL.bg, COL.arc)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, name)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture(PW.LOGO)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(AT.FONT, 16, "")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    title:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    title:SetText(AT.Tr(titleText))
    local body = f:CreateFontString(nil, "OVERLAY")
    body:SetFont(AT.FONT, 12, "")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    -- a set width, so its height reads right before the window first draws
    body:SetWidth(w - 84 - 18)
    body:SetJustifyH("LEFT")
    body:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    body:SetText(AT.Tr(bodyText))
    f.title, f.body = title, body
    f:Hide()
    return f
end

-- After a move: what happened, one button.
local moved
function PW.BuildMoved()
    if moved then return moved end
    local AT = NS.AT
    local f = PW.NoteFrame("ArcAurasPTMoved", "ArcUI ProcTracker moved into Arc Auras",
        "Your trackers now run here, in the same places with the same looks: see the ProcTracker layout. They are switched off in ArcUI ProcTracker, so nothing shows twice.")
    local ok = AT.MakeSmallButton(f, "Got it", 96)
    ok:SetHeight(24)
    ok:SetPoint("BOTTOMRIGHT", -18, 18)
    ok:SetScript("OnClick", function() f:Hide() end)
    moved = f
    return f
end

-- The move at login: a tick per icon and bar this class has in ArcUI ProcTracker,
-- in two columns (ICONS, BARS). The switched-on ones start ticked; the switched-off
-- ones are listed unticked, for a spec that wants them. One button, Move them; the
-- unticked stay in ArcUI ProcTracker. Escape closes it and it asks again at the
-- next load while something switched on there has not moved.
PW.MOVE_W = 560
PW.MOVE_HEAD_H = 20
local move = { rows = {}, heads = {} }
-- for harnesses: the window's state and widgets
PW.MOVE = move
function PW.BuildMove()
    if move.f then return move.f end
    local AT, COL = NS.AT, NS.AT.COL
    local f = PW.NoteFrame("ArcAurasPTMove", "ArcUI ProcTracker is moving into Arc Auras",
        "Tick the trackers to bring over. They arrive in the same places with the same looks and switch off in ArcUI ProcTracker.",
        PW.MOVE_W)
    local go = AT.MakeSmallButton(f, "Move them", 110)
    go:SetHeight(24)
    go:SetPoint("BOTTOMRIGHT", -18, 18)
    go:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    go:SetScript("OnLeave", function()
        go:SetBackdropColor(COL.btn[1], COL.btn[2], COL.btn[3], 1)
        go:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    end)
    go:SetScript("OnClick", function() PW.MoveNow() end)
    local said = Font(f, 11, { 1, 0.45, 0.4 })
    said:SetPoint("BOTTOMLEFT", 84, 24)
    said:SetPoint("RIGHT", go, "LEFT", -10, 0)
    for i, B in ipairs(PW.BOXES) do
        move.heads[i] = Font(f, 10, COL.dim)
        move.heads[i]:SetText(AT.Tr(B[1]))
    end
    move.f, move.go, move.said = f, go, said
    return f
end

-- A tracker's row in the move window: its tick, its name, "off" when it is
-- switched off in ArcUI ProcTracker.
function PW.MoveRow(i)
    local r = move.rows[i]
    if r then return r end
    local AT, COL = NS.AT, NS.AT.COL
    r = CreateFrame("Button", nil, move.f)
    r:SetHeight(PW.ROW_H)
    r:SetHighlightTexture(AT.WHITE)
    r:GetHighlightTexture():SetVertexColor(COL.arcDeep[1], COL.arcDeep[2], COL.arcDeep[3], 0.35)
    r.check = Options.ImportKit.Check(r)
    r.check:SetPoint("LEFT", 4, 0)
    r.name = Font(r, 12, COL.ink)
    r.name:SetPoint("LEFT", r.check, "RIGHT", 9, 0)
    r.kind = Font(r, 11, COL.dim)
    r.kind:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    local function Flip() if r.onTick then r.onTick() end end
    r:SetScript("OnClick", Flip)
    r.check:SetScript("OnClick", Flip)
    r:HookScript("OnEnter", function() r.check:SetHover(true) end)
    r:HookScript("OnLeave", function() r.check:SetHover(false) end)
    move.rows[i] = r
    return r
end

-- Lays the two columns under the words and sizes the window to the taller one.
function PW.PaintMove()
    local f = move.f
    if not f then return end
    local AT, COL = NS.AT, NS.AT.COL
    local top = math.max(16 + 56 + 10, 18 + 20 + 8 + math.ceil(f.body:GetStringHeight() or 30) + 12)
    local colW = math.floor((PW.MOVE_W - 80 - 18 - 16) / 2)
    local tallest, n = 0, 0
    for _, r in ipairs(move.rows) do r:Hide() end
    for bi, B in ipairs(PW.BOXES) do
        local x = 80 + (bi - 1) * (colW + 16)
        local head = move.heads[bi]
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", f, "TOPLEFT", x + 4, -top)
        local y, count = top + PW.MOVE_HEAD_H, 0
        for _, c in ipairs(move.list or {}) do
            if B[2][c.part] then
                n, count = n + 1, count + 1
                local r = PW.MoveRow(n)
                r.key = c.key
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
                r:SetWidth(colW)
                local on = move.picks[c.key] == true
                r.check:SetState(on and "on" or "off")
                r.name:SetText(c.name)
                local col = on and COL.ink or COL.dim
                r.name:SetTextColor(col[1], col[2], col[3])
                r.kind:SetText(c.off and AT.Tr("off") or "")
                r.onTick = function()
                    move.picks[c.key] = (not move.picks[c.key]) or nil
                    move.err = nil
                    PW.PaintMove()
                end
                r:Show()
                y = y + PW.ROW_H
            end
        end
        head:SetShown(count > 0)
        if count > 0 then tallest = math.max(tallest, y) end
    end
    f:SetHeight(math.max(tallest, top) + 12 + 24 + 18)
    local any = next(move.picks) ~= nil
    move.go:SetAlpha(any and 1 or 0.45)
    move.go:EnableMouse(any)
    move.said:SetText(move.err and AT.Tr(move.err) or "")
end

-- The switched-on parts start ticked, the switched-off ones unticked.
function PW.ShowMove(list)
    local f = PW.BuildMove()
    move.list, move.picks, move.err = list, {}, nil
    for _, c in ipairs(list) do
        if not c.off then move.picks[c.key] = true end
    end
    PW.PaintMove()
    f:Show()
end

-- Move them: the ticked trackers come over, then the note says so.
function PW.MoveNow()
    local MP = NS.MigratePT
    if not (MP and move.picks) or next(move.picks) == nil then return end
    local res, err = MP.Import(move.picks)
    if not res then
        move.err = err or "The move did not run."
        PW.PaintMove()
        return
    end
    local ui = NS.Store.UI and NS.Store.UI()
    if ui then ui.ptOffer = "done" end
    picks = nil
    move.f:Hide()
    if Options.RefreshAll then Options.RefreshAll() end
    PW.BuildMoved():Show()
end

-- After each load, never in combat (it waits for the fight to end): while
-- ArcUI ProcTracker has something switched on for this class that has not moved,
-- the move window lists every part this class has there. Another class's wait
-- for that class to log in. An old "Don't ask again" answer still holds.
function PW.MigrateOnLogin()
    local MP, Store = NS.MigratePT, NS.Store
    local ui = Store and Store.UI and Store.UI()
    if not (MP and ui and MP.Loaded()) or ui.ptOffer == "never" then return end
    if InCombatLockdown and InCombatLockdown() then
        if not PW.waitFight then
            PW.waitFight = CreateFrame("Frame")
            PW.waitFight:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                PW.MigrateOnLogin()
            end)
        end
        PW.waitFight:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local list, anyOn = {}, false
    for _, c in ipairs(MP.Candidates()) do
        if not c.other then
            if MP.PartLive(c.key) then
                -- in Arc Auras already from an earlier import (switched back on in
                -- ProcTracker since): only switched off there, never a second copy
                if not c.off then MP.SwitchOffInPT(c) end
            else
                list[#list + 1] = c
                if not c.off then anyOn = true end
            end
        end
    end
    -- only switched-off parts left: nothing to move, so nothing to ask
    if not anyOn then return end
    PW.ShowMove(list)
end

-- After the first PLAYER_ENTERING_WORLD: the game closes windows opened
-- before it, and the store settles on the live saved variables there.
local loginEv = CreateFrame("Frame")
loginEv:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEv:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(3, PW.MigrateOnLogin)
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
