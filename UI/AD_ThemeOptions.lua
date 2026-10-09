-- Settings > Theme: the options window's palette, finish and scroll bar width. Each
-- palette shows as a small sample drawn in its own colours. A pick is saved
-- and lands on the next reload: a built window keeps the colours it was
-- drawn with.

local ADDON, NS = ...
local Options = NS.Options
local AT = NS.AT
local COL, WHITE = AT.COL, AT.WHITE

local TH = {}
Options.Theme = TH

TH.LIST = {
    { key = "classic", name = "Classic", desc = "The original bright cyan." },
    { key = "ink", name = "Midnight Ink", desc = "Deep navy, a calm blue accent." },
    { key = "dusk", name = "Dusk", desc = "Midnight Ink, a step lighter." },
    { key = "graphite", name = "Graphite", desc = "Lighter charcoal, a blue accent." },
}

-- A sample is its title bar, tabs and section title (61), a box of three
-- ROW_H rows with 4 above and below, and 6 under the box.
local ROW_H = 18
local SAMPLE_H = 61 + 4 + 3 * ROW_H + 4 + 6
local CARD_H, GAP, MIN_W, MAX_W = SAMPLE_H + 52, 12, 160, 250

local function SavedTheme()
    local v = NS.Store.GetSetting("theme")
    if v and AT.PALETTES[v] then return v end
    return NS.THEME_DEFAULT or "classic"
end

local function SavedFinish()
    local v = NS.Store.GetSetting("panelFinish")
    return (v == "soft") and v or "flat"
end

local function SavedScroll()
    local v = NS.Store.GetSetting("scrollWidth")
    return AT.SCROLL_SIZES[v] and v or "normal"
end

-- At load, once the saved variables exist and before any window is built.
function TH.ApplySaved()
    AT.UsePalette(SavedTheme())
    AT.UseFinish(SavedFinish())
    AT.UseScrollWidth(SavedScroll())
end

-- A saved look this window is not drawn in yet.
function TH.Pending()
    return SavedTheme() ~= AT.PALETTE or SavedFinish() ~= AT.FINISH
        or AT.SCROLL_SIZES[SavedScroll()] ~= AT.ScrollW
end

-- The Reload button leaves a one-shot flag so the window comes back on
-- Settings, where the next theme is one click away.
function TH.ReopenAfterReload()
    local u = NS.Store.UI()
    if not (u and u.themeReopen) then return end
    u.themeReopen = nil
    -- Entering the world closes every Escape-closable window, so open after it.
    C_Timer.After(1, function()
        Options.Open()
        Options.Select("settings")
    end)
end

local function Col(pal, k)
    return AT.RGB(pal.col[k] or AT.PALETTES.classic.col[k])
end

local function Tex(parent, c, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], a or 1)
    return t
end

local function Text(parent, font, size, c, s)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font, size, "")
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetText(s)
    return fs
end

-- A window in miniature, by the palette's own colours, look and font.
local function Sample(card, key)
    local pal = AT.PALETTES[key]
    local look = pal.look or {}
    local font = AT.PaletteFont(key)
    local s = CreateFrame("Frame", nil, card)
    s:SetPoint("TOPLEFT", 6, -6)
    s:SetPoint("TOPRIGHT", -6, -6)
    s:SetHeight(SAMPLE_H)
    AT.Skin(s, Col(pal, "panel"), Col(pal, "line2"))

    local bar = CreateFrame("Frame", nil, s)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(16)
    AT.Skin(bar, Col(pal, "bg"))
    local brand = Text(bar, font, 10, Col(pal, "ink"), "|cff" .. AT.Hex(Col(pal, "arc")) .. "Arc|r|cff"
        .. AT.Hex(Col(pal, "word")) .. " Auras|r")
    brand:SetPoint("LEFT", 6, 0)

    -- tabs: underline words, or chips on an accent line; the words ride a
    -- layer above the chips
    local words = CreateFrame("Frame", nil, s)
    words:SetAllPoints()
    words:SetFrameLevel(s:GetFrameLevel() + 3)
    local prev
    for i, word in ipairs({ "Icons", "Look", "Load" }) do
        local open = i == 2
        local fs = Text(words, font, 9, Col(pal, open and "ink" or "dim"), word)
        if prev then fs:SetPoint("LEFT", prev, "RIGHT", 12, 0) else fs:SetPoint("TOPLEFT", 10, -23) end
        if look.tabs == "underline" then
            if open then
                local ul = Tex(s, Col(pal, "arc"))
                ul:SetHeight(2)
                ul:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -2, -2)
                ul:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 2, -2)
            end
        else
            local chip = CreateFrame("Frame", nil, s)
            chip:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 3)
            chip:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -3)
            chip:SetFrameLevel(s:GetFrameLevel() + 1)
            AT.Skin(chip, Col(pal, open and "box" or "well"), Col(pal, open and "arc" or "line"))
        end
        prev = fs
    end
    local strip = Tex(s, look.tabs == "underline" and Col(pal, "rule") or Col(pal, "arc"),
        look.tabs == "underline" and 1 or 0.9)
    strip:SetHeight(1)
    strip:SetPoint("TOPLEFT", 1, -38)
    strip:SetPoint("TOPRIGHT", -1, -38)

    local title = Text(s, font, 9, Col(pal, "title"), "APPEARANCE")
    title:SetPoint("TOPLEFT", 10, -45)
    local hair = Tex(s, Col(pal, "hair"))
    hair:SetHeight(1)
    hair:SetPoint("TOPLEFT", 8, -57)
    hair:SetPoint("TOPRIGHT", -8, -57)

    -- three rows of ROW_H, each label and control centred on its row's line
    local box = CreateFrame("Frame", nil, s)
    box:SetPoint("TOPLEFT", 8, -61)
    box:SetPoint("BOTTOMRIGHT", -8, 6)
    AT.Skin(box, Col(pal, "box"), Col(pal, "line"))
    local function Mid(i) return -(4 + (i - 0.5) * ROW_H) end

    Text(box, font, 9, Col(pal, "ink"), "Glow"):SetPoint("LEFT", box, "TOPLEFT", 8, Mid(1))
    local cb = CreateFrame("Frame", nil, box)
    cb:SetSize(10, 10)
    cb:SetPoint("RIGHT", box, "TOPRIGHT", -8, Mid(1))
    AT.Skin(cb, Col(pal, "well"), Col(pal, "line2"))
    local tick = Tex(cb, Col(pal, "arc"))
    tick:SetPoint("TOPLEFT", 2, -2)
    tick:SetPoint("BOTTOMRIGHT", -2, 2)

    Text(box, font, 9, Col(pal, "ink"), "Size"):SetPoint("LEFT", box, "TOPLEFT", 8, Mid(2))
    local track = CreateFrame("Frame", nil, box)
    track:SetSize(64, 6)
    track:SetPoint("RIGHT", box, "TOPRIGHT", -10, Mid(2))
    AT.Skin(track, Col(pal, "well"), Col(pal, "line"))
    if look.sliderFill then
        local fill = Tex(track, Col(pal, "fill"))
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", 1, 1)
        fill:SetWidth(37)
    end
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    local tc = Col(pal, "arc")
    thumb:SetVertexColor(tc[1], tc[2], tc[3], 1)
    thumb:SetSize(4, 10)
    thumb:SetPoint("CENTER", track, "LEFT", 38, 0)

    Text(box, font, 9, Col(pal, "dim"), "Every icon"):SetPoint("LEFT", box, "TOPLEFT", 8, Mid(3))
    local btn = CreateFrame("Frame", nil, box)
    btn:SetSize(48, 14)
    btn:SetPoint("RIGHT", box, "TOPRIGHT", -8, Mid(3))
    AT.Skin(btn, Col(pal, "btn"), Col(pal, "steel"))
    Text(btn, font, 9, Col(pal, "lead"), "Apply"):SetPoint("CENTER", 0, 0)
    return s
end

-- The Theme section, first on the Settings page.
function TH.Build(pg, owner)
    local cards = {}
    local function Paint()
        local saved = SavedTheme()
        for _, c in ipairs(cards) do
            local picked = c.key == saved
            -- hover takes line2, not focus: in ink focus is the accent, the
            -- picked card's own edge
            local e = (picked and COL.arc) or (c._hover and COL.line2) or COL.line
            c:SetBackdropBorderColor(e[1], e[2], e[3], 1)
            if c.key == AT.PALETTE then
                c.tag:SetText("In use")
                c.tag:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
            elseif picked then
                c.tag:SetText("After reload")
                c.tag:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
            else
                c.tag:SetText("")
            end
        end
    end

    AT.Section(pg, "Theme")
    local row = AT.AddRow(pg, CARD_H + 8)
    for _, t in ipairs(TH.LIST) do
        local c = CreateFrame("Button", nil, row, "BackdropTemplate")
        c.key = t.key
        AT.Skin(c, COL.box, COL.line)
        Sample(c, t.key)
        c.name = c:CreateFontString(nil, "OVERLAY")
        c.name:SetFont(AT.FONT, 12, "")
        c.name:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        c.name:SetPoint("TOPLEFT", 8, -(SAMPLE_H + 14))
        c.name:SetText(t.name)
        c.tag = c:CreateFontString(nil, "OVERLAY")
        c.tag:SetFont(AT.FONT, 10, "")
        c.tag:SetPoint("TOPRIGHT", -8, -(SAMPLE_H + 15))
        c.desc = c:CreateFontString(nil, "OVERLAY")
        c.desc:SetFont(AT.FONT, 10, "")
        c.desc:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        c.desc:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
        c.desc:SetPoint("RIGHT", -8, 0)
        c.desc:SetJustifyH("LEFT")
        c.desc:SetWordWrap(false)
        c.desc:SetText(t.desc)
        c:SetScript("OnEnter", function(self) self._hover = true Paint() end)
        c:SetScript("OnLeave", function(self) self._hover = false Paint() end)
        c:SetScript("OnClick", function(self)
            AT.CloseDropdown()
            NS.Store.SetSetting("theme", self.key)
            Paint()
            AT.LayoutPage(pg)
        end)
        cards[#cards + 1] = c
    end
    -- As many columns as fit, then evened out over the rows they need, so
    -- no card sits alone on a row; the row grows to hold them.
    row._sync = function()
        local w = (pg:GetWidth() or 0) - 34
        if w < 60 then pg._sizeUnresolved = true return end
        local cols = math.max(1, math.min(#cards, math.floor((w + GAP) / (MIN_W + GAP))))
        cols = math.ceil(#cards / math.ceil(#cards / cols))
        local cw = math.min(MAX_W, math.floor((w - (cols - 1) * GAP) / cols))
        -- size and gap snap once and every step adds them, so all gaps, across
        -- and down, are the same whole number of pixels
        local px = AT.Px(row)
        local function Snap(v) return math.floor(v / px + 0.5) * px end
        local w, h, g = Snap(cw), Snap(CARD_H), Snap(GAP)
        local x0, y0 = Snap(10), Snap(4)
        for i, c in ipairs(cards) do
            local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", row, "TOPLEFT", x0 + col * (w + g), -(y0 + r * (h + g)))
            c:SetSize(w, h)
        end
        local rows = math.ceil(#cards / cols)
        local want = 8 + rows * CARD_H + (rows - 1) * GAP
        if row._h ~= want then
            row._h = want
            row:SetHeight(want)
        end
        Paint()
    end

    AT.RowToggle(pg, "Soft light",
        function() return SavedFinish() == "soft" end,
        function(v)
            NS.Store.SetSetting("panelFinish", v and "soft" or nil)
            AT.LayoutPage(pg)
        end,
        nil, "Brightens the top of the window and shades its foot, for a little depth.")
    AT.RowDropdown(pg, owner, "Scroll bar width",
        function() return SavedScroll() end,
        function(v)
            NS.Store.SetSetting("scrollWidth", v ~= "normal" and v or nil)
            AT.LayoutPage(pg)
        end,
        function()
            return { { value = "thin", text = "Thin" }, { value = "normal", text = "Normal" },
                { value = "wide", text = "Wide" } }
        end)
    AT.RowButton(pg, "Reload now", function()
        local u = NS.Store.UI()
        if u then u.themeReopen = true end
        ReloadUI()
    end, TH.Pending, 120, "The new look shows after a reload")
end
