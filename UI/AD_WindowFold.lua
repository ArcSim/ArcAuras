-- AD_WindowFold: the main window folds down to its title bar and back. While
-- folded the bar names what is being edited, and the Edit chips on screen
-- keep picking, so the player edits with the panel out of the way.
-- AD_Options calls Fold.Attach(win) once the window is built and Fold.Sync()
-- from its refresh; a fresh open always starts unfolded.
-- Folding never changes the window's size or place: it hides everything
-- under the title bar (frames and the window's own fill and edge) and a strip
-- of ours draws the folded bar's edge and carries the drag. Unfolding only
-- shows them again, so the window always comes back at its own size.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL = AT.COL
local ui = Options.ui

local Fold = { folded = false }
Options.Fold = Fold

-- the title bar is 30 tall inside the window's 1px border
local FOLDED_H = 32

local function SelectedRecord()
    if not ui then return nil end
    if ui.grpMode == "rem" and ui.selRemId and ui.selType == "group" then
        return Store.Get(ui.selRemId)
    end
    if ui.selIconId and (ui.selType == "free" or (ui.selType == "group" and ui.grpMode == "ico")) then
        return Store.Get(ui.selIconId)
    end
    if ui.selId and ui.selType then return Store.Get(ui.selId) end
    return nil
end

local function PaintButton(b, hot)
    local c = hot and COL.arc or COL.line2
    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    b.chev:SetColor(hot and COL.arc or COL.dim)
end

-- A frame under the window's title bar is watched once: one shown while
-- folded (a refresh, a pick) hides at once and comes back on unfold.
function Fold.Watch(child)
    if child._adFoldHook then return end
    child._adFoldHook = true
    child:HookScript("OnShow", function(c)
        if Fold.folded and Fold.restore then
            Fold.restore[c] = true
            c:Hide()
        end
    end)
end

-- Every frame under the title bar but the strip hides, and shows again on
-- unfold if it was shown; a new one made while folded too (Fold.Sync).
function Fold.HideBody()
    local win = Fold.win
    for _, child in ipairs({ win:GetChildren() }) do
        if child ~= win.titleBar and child ~= Fold.edge then
            Fold.Watch(child)
            if child:IsShown() then
                Fold.restore[child] = true
                child:Hide()
            end
        end
    end
end

function Fold.Sync()
    if Fold.folded and Fold.win then Fold.HideBody() end
    local chip = Fold.chip
    if not chip then return end
    local rec = Fold.folded and SelectedRecord()
    if not rec or not rec.name then
        chip:Hide()
        return
    end
    chip.fs:SetText("Editing: |cff" .. AT.Hex(COL.arc) .. rec.name .. "|r")
    chip:SetWidth(math.ceil(chip.fs:GetStringWidth()) + 16)
    chip:Show()
end

function Fold.Set(on)
    local win = Fold.win
    if not win or Fold.folded == (on and true or false) then return end
    AT.CloseDropdown()
    if on then
        Fold.folded = true
        Fold.restore = {}
        Fold.HideBody()
        -- the window's own fill and edge
        Fold.regions = {}
        for _, r in ipairs({ win:GetRegions() }) do
            if r:IsShown() then
                Fold.regions[#Fold.regions + 1] = r
                r:Hide()
            end
        end
        -- the empty body takes no clicks and may hang off the screen
        Fold.mouse = win:IsMouseEnabled()
        win:EnableMouse(false)
        local l, r, t, b = win:GetClampRectInsets()
        Fold.clamp = { l or 0, r or 0, t or 0, b or 0 }
        local h = win:GetHeight()
        local hang = (type(h) == "number" and h > FOLDED_H) and (h - FOLDED_H) or 0
        win:SetClampRectInsets(Fold.clamp[1], Fold.clamp[2], Fold.clamp[3], Fold.clamp[4] + hang)
        Fold.edge:SetFrameLevel(win:GetFrameLevel())
        Fold.edge:Show()
    else
        Fold.folded = false
        Fold.edge:Hide()
        local c = Fold.clamp
        if c then win:SetClampRectInsets(c[1], c[2], c[3], c[4]) end
        win:EnableMouse(Fold.mouse ~= false)
        for _, r in ipairs(Fold.regions or {}) do r:Show() end
        for child in pairs(Fold.restore or {}) do child:Show() end
        Fold.restore, Fold.regions, Fold.clamp = nil, nil, nil
        -- placed again, so the screen's clamp holds the whole window
        AT.SnapWindow(win)
        if Options.RefreshAll then Options.RefreshAll() end
    end
    Fold.button.chev:SetDir(Fold.folded and "down" or "up")
    Fold.Sync()
end

-- bounds: the window's own resize bounds { minW, minH, maxW, maxH }; its min
-- height is the floor Fold.Repair keeps.
function Fold.Attach(win, bounds)
    if Fold.win then return end
    Fold.win = win
    Fold.bounds = bounds
    local bar = win.titleBar

    -- The folded bar's edge, as the window's own over its top 32: shown only
    -- while folded, under the title bar, and the drag handle while the
    -- window's body takes no clicks.
    local edge = CreateFrame("Frame", nil, win)
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", 0, 0)
    edge:SetHeight(FOLDED_H)
    AT.Skin(edge, COL.bg, COL.line2)
    edge:EnableMouse(true)
    edge:RegisterForDrag("LeftButton")
    edge:SetScript("OnDragStart", function() win:StartMoving() end)
    edge:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        AT.SnapWindow(win)
    end)
    edge:Hide()
    Fold.edge = edge

    -- Square button left of the close x, the close button's look.
    local b = CreateFrame("Button", nil, bar, "BackdropTemplate")
    b:SetSize(18, 18)
    b:SetPoint("RIGHT", -28, 0)
    AT.Skin(b, COL.well, COL.line2)
    b.chev = AT.MakeChevron(b)
    b.chev:SetPoint("CENTER")
    b.chev:SetDir("up")
    PaintButton(b, false)
    b:SetScript("OnEnter", function(s) PaintButton(s, true) end)
    b:SetScript("OnLeave", function(s) PaintButton(s, false) end)
    b:SetScript("OnClick", function() Fold.Set(not Fold.folded) end)
    AT.Tooltip(b, "Fold", "Folds the window down to its title bar. Click an Edit button on screen to switch what you edit; click here again to see its settings.")
    Fold.button = b

    -- "Editing: <name>" right after the title (and version), only while folded.
    local anchor = win.titleText
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= win.titleText and r.IsObjectType and r:IsObjectType("FontString") then anchor = r end
    end
    local chip = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    chip:SetHeight(18)
    chip:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
    AT.Skin(chip, COL.well, COL.line)
    chip.fs = chip:CreateFontString(nil, "OVERLAY")
    chip.fs:SetFont(AT.FONT, 11, "")
    chip.fs:SetPoint("LEFT", 8, 0)
    chip.fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    chip:Hide()
    Fold.chip = chip

    -- A close (the x, Escape, combat) ends the fold, so the next open is whole.
    win:HookScript("OnHide", function() Fold.Set(false) end)
    -- every open starts whole, even from a size an older fold left behind
    win:HookScript("OnShow", function()
        Fold.Repair()
        C_Timer.After(0, Fold.Repair)
    end)
end

-- An older fold shrank the window itself, and the game keeps a placed
-- window's size across a reload: a window shorter than its floor goes back to
-- its full height.
function Fold.Repair()
    local win = Fold.win
    if not (win and Fold.bounds) or Fold.folded or not win:IsShown() then return end
    local h = win:GetHeight()
    if type(h) == "number" and h >= Fold.bounds[2] then return end
    win:SetHeight(math.max(Fold.bounds[2], Options.MAIN_H or 0))
    AT.SnapWindow(win)
end
