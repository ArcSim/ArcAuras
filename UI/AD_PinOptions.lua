-- AD_PinOptions: a group's "Frames that move with it" rows on Position > Anchor
-- (Core\AD_Pins.lua places the frames). Two rows a frame: its name, the pick
-- crosshair, what it is doing now and remove; then its side, X / Y and Snap
-- back. A pair of points no side names gets a third row with both points.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL = AT.COL

local NAME_W, SIDE_W, NUM_W, POINT_W, CHIP_W, BTN = 150, 150, 44, 110, 84, 20

-- A pin's word on its row, with why on hover.
Options.PIN_WORDS = {
    pinned = { text = "Pinned", col = { 0.48, 0.85, 0.56 }, tip = "It sits by the group and moves with it." },
    missing = { text = "Not there", col = COL.faint, tip = "No frame by that name right now. It pins once the frame exists." },
    combat = { text = "After combat", col = COL.dim, tip = "The game holds this frame still in combat. It moves when combat ends." },
    taken = { text = "Taken", col = COL.faint, tip = "Another group on screen already moves this frame. A frame moves with one group." },
    hidden = { text = "Not shown", col = COL.faint, tip = "This group is not on screen, so the frame stays where it was." },
    moves = { text = "Can't pin", col = COL.faint, tip = "This group follows the cursor or a nameplate. A frame can't keep up with it." },
    refused = { text = "Can't pin", col = COL.faint,
        tip = "That frame can't move this way: an Arc Auras frame, the whole screen, or what this group is anchored to." },
    fight = { text = "Moved away", col = COL.faint, tip = "Something else keeps moving this frame. Snap back pauses until the layout changes." },
    edit = { text = "Edit Mode", col = COL.dim, tip = "Blizzard's Edit Mode is open. The frame moves back when it closes." },
    wait = { text = "Waiting", col = COL.dim, tip = "The group's spot can't be read right now. The frame moves once it can." },
}
Options.PIN_BUSY = { text = "Not in combat", col = COL.faint, tip = "Picking a frame waits until combat ends." }
Options.PIN_EMPTY = "Nothing moves with it yet. Add a game frame, e.g. your player frame."

local function Pins() return NS.Pins end

-- pin i of the selected group, or nil
local function PinAt(ctx, i)
    local r, P = ctx(), Pins()
    if not (r and P) or i > P.Count(r) then return nil, r end
    local pin = r.pins[i]
    return type(pin) == "table" and pin or nil, r
end

-- a sunken text box; commit(text) on Enter or focus lost, Esc puts back saved()
local function Box(row, w, saved, commit, justify)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(w, 18)
    AT.Skin(box, COL.well, COL.line)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetJustifyH(justify or "LEFT")
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function() AT.BoxText(box, saved()); box:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function()
        box:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1)
    end)
    box:SetScript("OnEditFocusLost", function()
        box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        commit(box:GetText() or "")
    end)
    return box
end

-- a short dim word ahead of a box
local function Word(row, text, anchor, gap)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, 11, "")
    fs:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    fs:SetText(text)
    fs:SetPoint("LEFT", anchor, "RIGHT", gap or 10, 0)
    return fs
end

-- Frame i: name, crosshair, its word, remove.
local function NameRow(pg, ctx, vis, i, rows)
    local shows = function()
        local r, P = ctx(), Pins()
        return vis() and r ~= nil and P ~= nil and i <= P.Count(r)
    end
    local row = AT.AddRow(pg, AT.LAY.rowH, shows)
    rows[#rows + 1] = row
    local lbl = AT.RowLabel(row, "Frame " .. i)
    local function saved()
        local pin = PinAt(ctx, i)
        return pin and type(pin.frame) == "string" and pin.frame or ""
    end
    local box
    box = Box(row, NAME_W, saved, function(text)
        local pin, r = PinAt(ctx, i)
        if pin and text ~= saved() then Pins().Set(r, i, "frame", text) end
        AT.LayoutPage(pg)
    end)
    local hint = box:CreateFontString(nil, "OVERLAY")
    hint:SetFont(AT.FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetPoint("RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("e.g. PlayerFrame")
    local function syncHint() hint:SetShown((box:GetText() or "") == "") end
    box:SetScript("OnTextChanged", syncHint)
    AT.Tooltip(box, "Frame name", "The global name of a game frame, e.g. PlayerFrame or ElvUF_Player.")
    row._colLabel, row._colCtrl = lbl, box

    local pick = Options.SlotButton(row, "Pick Frame",
        "Hover a game frame on screen and click it. Right-click or Esc cancels.")
    Options.Crosshair(pick)
    pick:SetPoint("LEFT", box, "RIGHT", 6, 0)

    local chip = CreateFrame("Frame", nil, row, "BackdropTemplate")
    chip:SetSize(CHIP_W, 16)
    chip:SetPoint("LEFT", pick, "RIGHT", 6, 0)
    AT.Skin(chip, { 0, 0, 0, 0 }, COL.line)
    chip.fs = chip:CreateFontString(nil, "OVERLAY")
    chip.fs:SetFont(AT.FONT, 10, "")
    chip.fs:SetPoint("CENTER", 0, 0)
    -- hover says why
    chip:EnableMouse(true)
    local function Shown()
        if row._adNoCombat then return Options.PIN_BUSY end
        local r, P = ctx(), Pins()
        return r and P and Options.PIN_WORDS[P.Status(r.id, i) or ""] or nil
    end
    AT.Tooltip(chip, function() local w = Shown() return w and w.text or "" end,
        function() local w = Shown() return w and w.tip or "" end)
    pick:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r, FP = ctx(), NS.FramePicker
        if not (r and FP) then return end
        local id = r.id
        local ok = FP.Start(function(name)
            local g = Store.Get(id)
            if g and type(name) == "string" and name ~= "" and Pins() then Pins().Set(g, i, "frame", name) end
            AT.LayoutPage(pg)
        end, nil)
        if not ok then
            row._adNoCombat = true
            row._sync()
            C_Timer.After(2, function()
                row._adNoCombat = nil
                row._sync()
            end)
        end
    end)

    local del = AT.MakeQuietButton(row, "x", BTN)
    del:SetSize(BTN, BTN)
    del:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    AT.Tooltip(del, "Remove", "This frame stops moving with the group and goes back to where it was.")
    del:SetScript("OnClick", function()
        AT.CloseDropdown()
        local _, r = PinAt(ctx, i)
        if r and Pins() then Pins().Remove(r, i) end
        AT.LayoutPage(pg)
    end)
    row._colTrail = 6 + BTN + 6 + CHIP_W
    row._adPin = { box = box, pick = pick, chip = chip, del = del }

    row._sync = function()
        if not box:HasFocus() then AT.BoxText(box, saved()) end
        syncHint()
        local w = Shown()
        chip:SetShown(w ~= nil)
        if w then
            chip.fs:SetText(w.text)
            AT.PaintPill(chip, chip.fs, w.col)
        end
    end
end

-- Frame i's side, X / Y and Snap back; "custom" shows the points row under it.
local function SideRow(pg, ctx, vis, i, rows, owner, open)
    local shows = function()
        local r, P = ctx(), Pins()
        return vis() and r ~= nil and P ~= nil and i <= P.Count(r)
    end
    local row = AT.AddRow(pg, AT.LAY.rowH, shows)
    rows[#rows + 1] = row
    local lbl = AT.RowLabel(row, "Side")
    local dd = AT.MakeDropdown(owner, row, SIDE_W,
        function()
            local items = {}
            for _, s in ipairs(Pins().SIDES) do items[#items + 1] = { value = s.value, text = s.text } end
            items[#items + 1] = { value = "custom", text = "Custom points" }
            return items
        end,
        function()
            local pin, r = PinAt(ctx, i)
            if not pin then return "above" end
            if open[r.id .. ":" .. i] then return "custom" end
            return Pins().SideOf(pin)
        end,
        function(v)
            local pin, r = PinAt(ctx, i)
            if not pin then return end
            open[r.id .. ":" .. i] = (v == "custom") or nil
            if v ~= "custom" then Pins().Set(r, i, "side", v) end
        end,
        function() AT.LayoutPage(pg) end)
    AT.Tooltip(dd, "Side", "Where it sits: its edge against the group's.")
    row._colLabel, row._colCtrl = lbl, dd

    local function Num(field)
        return function()
            local pin = PinAt(ctx, i)
            return tostring(pin and math.floor((tonumber(pin[field]) or 0) + 0.5) or 0)
        end
    end
    local function Commit(field)
        return function(text)
            local pin, r = PinAt(ctx, i)
            local n = tonumber(text)
            if pin and n and math.floor(n + 0.5) ~= (tonumber(pin[field]) or 0) then Pins().Set(r, i, field, n) end
            AT.LayoutPage(pg)
        end
    end
    local wx = Word(row, "X", dd, 10)
    local bx = Box(row, NUM_W, Num("x"), Commit("x"), "CENTER")
    bx:SetPoint("LEFT", wx, "RIGHT", 4, 0)
    AT.Tooltip(bx, "X offset", "Moves it right (or left, below zero) from that spot.")
    local wy = Word(row, "Y", bx, 8)
    local by = Box(row, NUM_W, Num("y"), Commit("y"), "CENTER")
    by:SetPoint("LEFT", wy, "RIGHT", 4, 0)
    AT.Tooltip(by, "Y offset", "Moves it up (or down, below zero) from that spot.")

    local cb = AT.MakeCheckbox(row)
    cb:SetPoint("LEFT", by, "RIGHT", 12, 0)
    local cw = Word(row, "Snap back", cb, 5)
    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", cw:GetStringWidth() + 5, 0)
    local function flip()
        AT.CloseDropdown()
        local pin, r = PinAt(ctx, i)
        if not pin then return end
        local on = pin.snap ~= true
        Pins().Set(r, i, "snap", on)
        cb:SetOn(on)
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    end
    cb:SetScript("OnClick", flip)
    hit:SetScript("OnClick", flip)
    hit:SetScript("OnEnter", function() cb:SetHover(true) end)
    hit:SetScript("OnLeave", function() cb:SetHover(false) end)
    local snapTip = "Puts it back at once when the game or another addon moves it. Off: it goes back the next time the group moves."
    AT.Tooltip(hit, "Snap back", snapTip)
    AT.Tooltip(cb, "Snap back", snapTip)
    row._colTrail = 10 + 8 + 4 + NUM_W + 8 + 8 + 4 + NUM_W + 12 + 18 + 5 + 60
    row._adPin = { dd = dd, x = bx, y = by, snap = cb, hit = hit }

    row._sync = function()
        dd.Refresh()
        local pin = PinAt(ctx, i)
        if not bx:HasFocus() then AT.BoxText(bx, Num("x")()) end
        if not by:HasFocus() then AT.BoxText(by, Num("y")()) end
        cb:SetOn(pin ~= nil and pin.snap == true)
    end
end

-- Frame i's two points, while its side is Custom points.
local function PointsRow(pg, ctx, vis, i, rows, owner, open)
    local shows = function()
        local pin, r = PinAt(ctx, i)
        if not (vis() and pin) then return false end
        return open[r.id .. ":" .. i] == true or Pins().SideOf(pin) == "custom"
    end
    local row = AT.AddRow(pg, AT.LAY.rowH, shows)
    rows[#rows + 1] = row
    local lbl = AT.RowLabel(row, "Points")
    local function Items()
        local items = {}
        for _, p in ipairs(Pins().POINTS) do
            items[#items + 1] = { value = p, text = p:sub(1, 1) .. p:sub(2):lower() }
        end
        return items
    end
    local function Point(field)
        return AT.MakeDropdown(owner, row, POINT_W, Items,
            function()
                local pin = PinAt(ctx, i)
                if not pin then return "CENTER" end
                return field == "src" and Pins().Src(pin) or Pins().Dst(pin)
            end,
            function(v)
                local pin, r = PinAt(ctx, i)
                if pin then Pins().Set(r, i, field, v) end
            end,
            function() AT.LayoutPage(pg) end)
    end
    local src = Point("src")
    AT.Tooltip(src, "Its point", "The point of the frame that goes on the group.")
    local on = Word(row, "on the group's", src, 8)
    local dst = Point("dst")
    dst:SetPoint("LEFT", on, "RIGHT", 8, 0)
    AT.Tooltip(dst, "The group's point", "Where on the group that point goes.")
    row._colLabel, row._colCtrl = lbl, src
    row._colTrail = 8 + 90 + 8 + POINT_W
    row._adPin = { src = src, dst = dst }
    row._sync = function()
        src.Refresh()
        dst.Refresh()
    end
end

-- The section: a line while there is none, two rows a frame, then + Add.
-- owner: the options window, which the dropdown lists open over.
function Options.PinRows(pg, ctx, vis, owner)
    local P = Pins()
    if not P then return end
    AT.Section(pg, "Frames that move with it", { visibleFn = vis })
    AT.RowDesc(pg, Options.PIN_EMPTY, 20, function()
        local r = ctx()
        return vis() and r ~= nil and P.Count(r) == 0
    end)
    local rows, open = {}, {}
    for i = 1, P.MAX do
        NameRow(pg, ctx, vis, i, rows)
        SideRow(pg, ctx, vis, i, rows, owner, open)
        PointsRow(pg, ctx, vis, i, rows, owner, open)
    end
    AT.RowButton(pg, "+ Add", function()
        local r = ctx()
        if r then P.Add(r) end
        AT.LayoutPage(pg)
    end, function()
        local r = ctx()
        return vis() and r ~= nil and P.Count(r) < P.MAX
    end, 80, "Another frame")
    -- a change places the frames a frame later: the words follow then
    P.OnChange("options", function()
        if not pg:IsVisible() then return end
        for _, row in ipairs(rows) do
            if row:IsShown() and row._sync then row._sync() end
        end
    end)
    pg:HookScript("OnHide", function()
        if NS.FramePicker then NS.FramePicker.Stop() end
    end)
end
