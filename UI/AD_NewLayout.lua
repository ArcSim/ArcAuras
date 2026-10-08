-- AD_NewLayout: the New Layout page's cards, the templates, Empty and Import.
-- UI\AD_Options.lua owns the pane and its header; it calls Fill once when the
-- window builds and Refresh whenever the page shows or the window resizes.
local ADDON, NS = ...

local NL = {}
NS.NewLayout = NL

-- CARD_H carries room for an optional secondary button (only the Starter
-- card uses one today) so every card in a row still lines up.
NL.CARD_W, NL.CARD_H, NL.GAP = 200, 190, 12
NL.PREV_H = 76
-- the picture area inside a card's preview: a narrow card keeps all of it
NL.STAGE_W, NL.STAGE_H = 160, 60
NL.MIN_W = NL.STAGE_W + 16

-- The template cards, in order: { key, title, desc, rows, class, make }.
-- rows (a table, or a function returning one) are the groups the preview
-- draws, each { kind, y, size, n } with n squares (6 when unset), or
-- { kind, y, size, w } for one bar w wide and size tall; class shows the card
-- to that class only; make returns the new layout record.
NL.TEMPLATES = {}

function NL.AddTemplate(t)
    NL.TEMPLATES[#NL.TEMPLATES + 1] = t
end

-- Spotlight cards: whole layouts players made, in their own section after the
-- templates. Same entry shape as a template plus the picture's source: image
-- (a 2:1 screenshot texture) or text (the share string, drawn from its own
-- records); make may return nil (an import that failed), and then nothing opens.
-- A pack with versions adds notes (what the newest string changed), owned()
-- (the player has a layout from it), hasUpdate() (theirs is older) and update()
-- (offers the newer one for their copy).
NL.SPOTLIGHT = {}
-- a screenshot's width over its height, and the size of the hover picture
NL.IMAGE_ASPECT = 2
NL.BIG_W, NL.BIG_H = 448, 224

function NL.AddSpotlight(t)
    NL.SPOTLIGHT[#NL.SPOTLIGHT + 1] = t
end

-- Cards other files add under "Start blank or import" (an importer): the card
-- entry plus an `avail` test, read once when the window builds.
NL.EXTRA = {}

function NL.AddOwnCard(entry)
    NL.EXTRA[#NL.EXTRA + 1] = entry
end

NL.AddTemplate({
    key = "starter",
    title = "Starter Layout",
    desc = "Cooldowns, Utility and Buffs groups under your character, ready to fill.",
    rows = function() return NS.Store.STARTER_ROWS end,
    make = function() return NS.Store.NewStarterLayout() end,
    -- A second, explicit action so the plain card click still just makes an
    -- empty starter layout with nothing extra.
    secondary = {
        label = "+ My Action Bars",
        tip = "Also finds the spells and items on your action bars and lets you pick which become icons. Out of combat only.",
        pick = function()
            local rec = NS.Store.NewStarterLayout()
            NS.Options.OpenLayout(rec)
            if NS.Options.BarImport then NS.Options.BarImport.OpenForStarter(rec) end
        end,
    },
})

-- A template's groups in miniature: a row of squares per group, sized and
-- spaced like the real ones and scaled to fit, in the sidebar's kind colour.
-- A bar row is one strip; a kind with no sidebar colour takes the accent.
function NL.DrawRows(stage, rows)
    local COL = NS.AT.COL
    local GC = NS.Options and NS.Options.GROUP_COLORS or {}
    local top, bottom, wide
    for _, r in ipairs(rows) do
        local n = r.n or 6
        local w = r.w or (n * r.size + (n - 1) * 2)
        if not wide or w > wide then wide = w end
        local t, b = r.y + r.size / 2, r.y - r.size / 2
        if not top or t > top then top = t end
        if not bottom or b < bottom then bottom = b end
    end
    if not wide or top <= bottom then return end
    local s = math.min(NL.STAGE_W / wide, NL.STAGE_H / (top - bottom))
    -- a height-bound picture fills the stage exactly, which float error can
    -- tip to -1
    local padY = math.max(0, math.floor((NL.STAGE_H - (top - bottom) * s) / 2))
    for _, r in ipairs(rows) do
        local y0 = padY + math.floor((top - (r.y + r.size / 2)) * s + 0.5)
        local c = NS.AT.Mute(GC[r.kind] or COL.arc)
        if r.w then
            local bw = math.max(3, math.floor(r.w * s + 0.5))
            local bh = math.max(2, math.floor(r.size * s + 0.5))
            local t = stage:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(c[1], c[2], c[3], 0.9)
            t:SetSize(bw, bh)
            t:SetPoint("TOPLEFT", stage, "TOPLEFT", math.floor((NL.STAGE_W - bw) / 2), -y0)
        else
            local n = r.n or 6
            local sz = math.max(3, math.floor(r.size * s + 0.5))
            local gap = math.max(1, math.floor(2 * s + 0.5))
            local x0 = math.floor((NL.STAGE_W - (n * sz + (n - 1) * gap)) / 2)
            for i = 1, n do
                local t = stage:CreateTexture(nil, "ARTWORK")
                t:SetColorTexture(c[1], c[2], c[3], 0.9)
                t:SetSize(sz, sz)
                t:SetPoint("TOPLEFT", stage, "TOPLEFT", x0 + (i - 1) * (sz + gap), -y0)
            end
        end
    end
end

-- A blank page with a plus.
function NL.DrawEmpty(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local f = CreateFrame("Frame", nil, stage, "BackdropTemplate")
    f:SetSize(72, 44)
    f:SetPoint("TOPLEFT", stage, "TOPLEFT", (NL.STAGE_W - 72) / 2, -(NL.STAGE_H - 44) / 2)
    AT.Skin(f, COL.box, COL.line2)
    for _, wh in ipairs({ { 16, 2 }, { 2, 16 } }) do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        t:SetSize(wh[1], wh[2])
        t:SetPoint("CENTER")
    end
end

-- An arrow dropping into a tray. The theme's chevron doubled is the head: its
-- offsets are in its own scale, hence the halving.
function NL.DrawImport(stage)
    local AT, COL = NS.AT, NS.AT.COL
    local cx = NL.STAGE_W / 2
    local function Bar(w, h, x, y, c)
        local t = stage:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:SetSize(w, h)
        t:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -y)
    end
    Bar(2, 22, cx - 1, 8, COL.arc)
    local head = AT.MakeChevron(stage)
    head:SetDir("down")
    head:SetColor(COL.arc)
    head:SetScale(2)
    head:SetPoint("CENTER", stage, "TOPLEFT", cx / 2, -28 / 2)
    Bar(44, 2, cx - 22, 48, COL.dim)
    Bar(2, 10, cx - 22, 38, COL.dim)
    Bar(2, 10, cx + 20, 38, COL.dim)
end

-- Rest and hover looks: the theme's cyan edge only under the mouse.
function NL.Paint(c, hot)
    local COL = NS.AT.COL
    local fill = hot and COL.btn or COL.panel
    local edge = hot and COL.arc or COL.line
    local ink = hot and COL.arc or COL.ink
    c:SetBackdropColor(fill[1], fill[2], fill[3], 1)
    c:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    c.title:SetTextColor(ink[1], ink[2], ink[3])
end

-- A screenshot, as large as fits w x h at its own shape, centred on parent.
function NL.DrawImage(parent, path, w, h)
    local iw, ih = w, w / NL.IMAGE_ASPECT
    if ih > h then iw, ih = h * NL.IMAGE_ASPECT, h end
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(path)
    t:SetSize(math.floor(iw), math.floor(ih))
    t:SetPoint("CENTER")
    return t
end

-- A template's picture into a w x h stage: its screenshot, else the layout
-- drawn from its share string, else its rows. On a card (onCard) a screenshot
-- fills the preview box, which is larger than the stage.
function NL.DrawEntry(stage, t, w, h, onCard)
    if t.image then
        if onCard then
            NL.DrawImage(stage:GetParent(), t.image, NL.MIN_W - 18, NL.PREV_H - 2)
        else
            NL.DrawImage(stage, t.image, w, h)
        end
        return
    end
    local LP = NS.LayoutPreview
    if t.text and LP and LP.Draw(stage, t.text, w, h) then return end
    local rows = type(t.rows) == "function" and t.rows() or t.rows
    if rows then NL.DrawRows(stage, rows) end
end

-- The hover picture: the card's layout at a larger size beside the card, one
-- stage per template, drawn on first hover and kept.
function NL.ShowBig(card)
    local t = card.entry and card.entry.src
    if not t then return end
    local AT, COL = NS.AT, NS.AT.COL
    local big = NL.big
    if not big then
        big = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        big:SetFrameStrata("TOOLTIP")
        big:SetSize(NL.BIG_W + 16, NL.BIG_H + 16)
        big:SetClampedToScreen(true)
        AT.Skin(big, COL.well, COL.line)
        big.stages = {}
        NL.big = big
    end
    for _, st in pairs(big.stages) do st:Hide() end
    local st = big.stages[t]
    if not st then
        st = CreateFrame("Frame", nil, big)
        st:SetSize(NL.BIG_W, NL.BIG_H)
        st:SetPoint("TOP", 0, -8)
        NL.DrawEntry(st, t, NL.BIG_W, NL.BIG_H, false)
        big.stages[t] = st
    end
    st:Show()
    -- a pack's newest notes under its picture
    if not big.notes then
        big.notes = big:CreateFontString(nil, "OVERLAY")
        big.notes:SetFont(NS.AT.FONT, 11, "")
        big.notes:SetPoint("TOPLEFT", 10, -(NL.BIG_H + 14))
        big.notes:SetPoint("TOPRIGHT", -10, -(NL.BIG_H + 14))
        big.notes:SetJustifyH("LEFT")
        big.notes:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    end
    local notes = (t.notes and #t.notes > 0) and table.concat(t.notes, " ") or nil
    if notes then
        big.notes:SetText("What's new: " .. notes)
        big.notes:Show()
        big:SetHeight(NL.BIG_H + 16 + math.ceil(big.notes:GetStringHeight() or 14) + 10)
    else
        big.notes:Hide()
        big:SetHeight(NL.BIG_H + 16)
    end
    big:ClearAllPoints()
    big:SetPoint("LEFT", card, "RIGHT", 8, 0)
    big:Show()
end

function NL.HideBig()
    if NL.big then NL.big:Hide() end
end

-- entry = { title, desc, draw(stage), pick(), src }: src (a Spotlight
-- template) adds the hover picture.
function NL.MakeCard(parent, entry)
    local AT, COL = NS.AT, NS.AT.COL
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(NL.CARD_W, NL.CARD_H)
    c:RegisterForClicks("LeftButtonUp")
    AT.Skin(c, COL.panel, COL.line)
    c.entry = entry
    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 8, -8)
    box:SetPoint("TOPRIGHT", -8, -8)
    box:SetHeight(NL.PREV_H)
    AT.Skin(box, COL.well, COL.line)
    c.preview = box
    local stage = CreateFrame("Frame", nil, box)
    stage:SetSize(NL.STAGE_W, NL.STAGE_H)
    stage:SetPoint("CENTER")
    c.stage = stage
    entry.draw(stage)
    c.title = c:CreateFontString(nil, "OVERLAY")
    c.title:SetFont(NS.AT.FONT, 13, "")
    c.title:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -9)
    c.title:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", -2, -9)
    c.title:SetJustifyH("LEFT")
    c.title:SetWordWrap(false)
    c.title:SetText(entry.title)
    c.desc = c:CreateFontString(nil, "OVERLAY")
    c.desc:SetFont(NS.AT.FONT, 11, "")
    c.desc:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.desc:SetPoint("TOPRIGHT", c.title, "BOTTOMRIGHT", 0, -5)
    c.desc:SetJustifyH("LEFT")
    c.desc:SetJustifyV("TOP")
    c.desc:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    c.desc:SetText(entry.desc)
    -- An optional second action (Starter's "+ My Action Bars"): a slim button
    -- of its own, so the card's own click still just makes the plain layout.
    if entry.secondary then
        local sec = AT.MakeQuietButton(c, entry.secondary.label, NL.CARD_W - 16)
        sec:SetHeight(18)
        sec:SetPoint("BOTTOM", 0, 7)
        sec:SetScript("OnClick", function() entry.secondary.pick() end)
        if entry.secondary.tip then AT.Tooltip(sec, entry.secondary.label, entry.secondary.tip) end
        c.secondaryBtn = sec
    end
    -- a mark on its picture while a newer version waits for the player's
    -- copy (NL.SyncCard keeps it current)
    if entry.hasUpdate then
        c.updMark = AT.NewChip(box, "NEW VERSION")
        c.updMark:SetPoint("TOPRIGHT", -4, -4)
        c.updMark:SetFrameLevel(box:GetFrameLevel() + 5)
    end
    -- the maker's link, boxed on the picture's corner (UI\AD_Spotlight.lua)
    local SP = NS.Spotlight
    c.link = SP and SP.LinkButton and SP.LinkButton(box, entry, true)
    if c.link then
        c.link:SetPoint("BOTTOMLEFT", 4, 4)
        c.link:SetFrameLevel(box:GetFrameLevel() + 5)
    end
    NL.SyncCard(c)
    NL.Paint(c, false)
    c:SetScript("OnEnter", function(s)
        NL.Paint(s, true)
        if entry.src then NL.ShowBig(s) end
    end)
    c:SetScript("OnLeave", function(s)
        NL.Paint(s, false)
        if entry.src then NL.HideBig() end
    end)
    c:SetScript("OnClick", function() entry.pick() end)
    return c
end

-- What changes on a card while the window is open: an update button and mark
-- that show only while the player's copy of the pack is older.
function NL.SyncCard(c)
    local e = c.entry
    local upd = e.hasUpdate and e.hasUpdate() == true
    if c.updMark then c.updMark:SetShown(upd) end
    if c.secondaryBtn and e.secondary and e.secondary.visible then
        c.secondaryBtn:SetShown(e.secondary.visible() == true)
    end
end

-- Cards wrap to the page's width. A row sits 12 inside the page (box and row
-- insets) and the cards start on the label margin, so a page w wide gives
-- them w - 44; a single card narrower than that shrinks, never under MIN_W.
function NL.Grid(row, pageW)
    if pageW < 60 then row._pg._sizeUnresolved = true return end
    local usable = pageW - 44
    local cols = math.max(1, math.floor((usable + NL.GAP) / (NL.CARD_W + NL.GAP)))
    local cw = NL.CARD_W
    if cols == 1 and usable < cw then cw = math.max(NL.MIN_W, math.floor(usable)) end
    for i, c in ipairs(row._cards) do
        local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
        c:SetWidth(cw)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + col * (cw + NL.GAP), -8 - r * (NL.CARD_H + NL.GAP))
    end
    local n = math.max(1, math.ceil(#row._cards / cols))
    local want = 8 + n * NL.CARD_H + (n - 1) * NL.GAP + 10
    if row._h ~= want then row._h = want row:SetHeight(want) end
end

function NL.CardRow(pg, entries)
    local row = NS.AT.AddRow(pg, NL.CARD_H + 18)
    row._cards = {}
    for i, e in ipairs(entries) do row._cards[i] = NL.MakeCard(row, e) end
    row._sync = function()
        for _, c in ipairs(row._cards) do NL.SyncCard(c) end
        NL.Grid(row, pg:GetWidth() or 0)
    end
    return row
end

-- Card entries for a template list, this class's own and the class-free ones.
function NL.Cards(list)
    local O = NS.Options
    local _, class = UnitClass("player")
    local out = {}
    for _, t in ipairs(list) do
        if not t.class or t.class == class then
            -- a pack's newer version: its own button, only while the player's
            -- copy is older; the card's click still makes a fresh layout
            local sec = t.secondary
            if not sec and t.update and t.hasUpdate then
                sec = { label = "Update my copy", pick = function() NL.HideBig() t.update() end,
                    visible = t.hasUpdate,
                    tip = "A newer version of this layout is out. Updates the layout you made from it; your own sizes and positions stay." }
            end
            out[#out + 1] = {
                title = t.title, desc = t.desc,
                draw = function(stage) NL.DrawEntry(stage, t, NL.STAGE_W, NL.STAGE_H, true) end,
                src = (t.image or t.text) and t or nil,
                pick = function()
                    NL.HideBig()
                    local rec = t.make()
                    if rec then O.OpenLayout(rec) end
                end,
                secondary = sec,
                hasUpdate = t.hasUpdate,
                link = t.link, linkLabel = t.linkLabel,
            }
        end
    end
    return out
end

-- The template lists are read once, when the window builds: a template added
-- later shows after a /reload.
function NL.Fill(pane)
    local AT = NS.AT
    local O, S = NS.Options, NS.Store
    local pg = AT.NewPage(pane)
    AT.MakeScrollable(pg)
    pg:SetPoint("TOPLEFT", 0, -36)
    pg:SetPoint("BOTTOMRIGHT", 0, 0)
    pg:Show()
    NL.pg = pg
    -- the packs the player has, and their updates, are on Home (UI\AD_Home.lua)
    AT.Section(pg, "Start from a template")
    NL.tplRow = NL.CardRow(pg, NL.Cards(NL.TEMPLATES))
    local spot = NL.Cards(NL.SPOTLIGHT)
    NL.spotRow = nil
    AT.Section(pg, "Layout Packs")
    if #spot > 0 then
        NL.spotRow = NL.CardRow(pg, spot)
    else
        -- no packs for this game yet (retail): the invite
        AT.RowDesc(pg, "No layout packs here yet. Made a layout others would like? Post it with a screenshot on the Arc UI Discord to be featured here.", 34)
    end
    AT.Section(pg, "Start blank or import")
    local own = {
        { title = "Empty Layout", desc = "A blank layout. Add your own groups, icons and bars.",
          draw = NL.DrawEmpty, pick = function() O.OpenLayout(S.NewLayout()) end },
        { title = "Import a Layout", desc = "Paste a layout someone shared with you.",
          draw = NL.DrawImport, pick = function() O.Select("ie") end },
    }
    for _, e in ipairs(NL.EXTRA) do
        if not e.avail or e.avail() then own[#own + 1] = e end
    end
    NL.ownRow = NL.CardRow(pg, own)
    AT.LayoutPage(pg)
end

function NL.Refresh()
    if NL.pg then NS.AT.LayoutPage(NL.pg) end
end
