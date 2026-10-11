-- AD_TexturePicker: the bar texture picker. A texture row shows the texture
-- on a small bar and opens a window that draws every texture on a bar in the
-- bar's own colour: grouped by the addon its file comes from, searched by
-- name, with favorites and the last ones used. The texture under the mouse
-- (else the one clicked) shows on the real bar until the window closes; Use
-- texture keeps the pick, any other way out puts the old one back.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end
local AT, Store = NS.AT, NS.Store
local COL, WHITE = AT.COL, AT.WHITE

local TP = { group = "all", q = "", hover = nil }
NS.TexturePicker = TP

local W, H = 720, 540
local BAR_W = 34           -- the swatch: a bar 72% full, the way a texture reads
local ROW_H, ROW_BAR_H = 34, 24
local GROUP_W, GROUP_H = 210, 28
local OWN = "Arc Auras"
local GREEN = { 0.482, 0.847, 0.561 }
local GREEN_EDGE = { 0.180, 0.353, 0.227 }
local BAR_BG = { 0.063, 0.078, 0.122 }
local BLACK = { 0, 0, 0 }
local CLEAR = { 0, 0, 0, 0 }
local STAR = "Interface\\Common\\ReputationStar"

local function Bars() return NS.Bars end

local function FolderOf(path)
    if type(path) ~= "string" then return nil end
    return path:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee][\\/][Aa][Dd][Dd][Oo][Nn][Ss][\\/]([^\\/]+)")
end

local function SameFile(path)
    if type(path) ~= "string" then return tostring(path) end
    return (path:lower():gsub("/", "\\"):gsub("%.%a+$", ""))
end

local function Lower(a, b) return a.name:lower() < b.name:lower() end

-- Every texture once: the built-ins first (Flat is ours, the rest are the
-- game's files), then LibSharedMedia's, a file already listed under another
-- name left out.
function TP.Catalog()
    local B = Bars()
    local out, names, files = {}, {}, {}
    local function add(name, path, src, first)
        if names[name] then return end
        local f = SameFile(path)
        if files[f] then return end
        names[name], files[f] = true, true
        out[#out + 1] = { name = name, path = path, src = src, first = first }
    end
    for _, k in ipairs(B.BUILTIN_TEXTURE_ORDER) do
        local p = B.BUILTIN_TEXTURES[k]
        add(k, p, (k == "Flat" or FolderOf(p)) and OWN or "Game", true)
    end
    local lsm = B.GetLSM and B.GetLSM()
    if lsm then
        -- A-Z, so of two names for one file the same one is always kept
        local media = {}
        for name, path in pairs(lsm:HashTable("statusbar") or {}) do
            if name ~= "None" then media[#media + 1] = { name = name, path = path } end
        end
        table.sort(media, Lower)
        for _, m in ipairs(media) do
            local f = FolderOf(m.path)
            add(m.name, m.path, (not f and "Game") or (f == ADDON and OWN) or f, false)
        end
    end
    return out
end

-- The texture a bar holds stays pickable even when the list left its name out
-- (another name for the same file), so it still reads In use.
function TP.Keep(items, name)
    if not name or name == "" then return end
    for _, it in ipairs(items) do if it.name == name then return end end
    -- a pack that is gone has no file to show
    local B = Bars()
    local lsm = B.GetLSM and B.GetLSM()
    local path = lsm and lsm:Fetch("statusbar", name, true)
    if not path then return end
    local f = FolderOf(path)
    items[#items + 1] = { name = name, path = path,
        src = (not f and "Game") or (f == ADDON and OWN) or f, first = false }
end

local function UI()
    local u = Store.UI()
    u.texFavs = u.texFavs or {}
    u.texRecent = u.texRecent or {}
    return u
end

local function Ctx() return TP.ctx end

local function PathOf(it)
    local K = Bars().Kit
    if it.isEmpty then
        local c = Ctx()
        return K.ResolveBarTexture(c and c.emptyKey and c.emptyKey() or "")
    end
    return it.path or K.ResolveBarTexture(it.name)
end

-- the bar's fill colour, or white for the texture's own art
local function Tint()
    if TP.white then return 1, 1, 1 end
    local c = Ctx()
    local v = c and c.tint and c.tint()
    if type(v) == "table" and v[1] then return v[1], v[2], v[3] end
    return 1, 1, 1
end

local function BarTint()
    local c = Ctx()
    local v = c and c.tint and c.tint()
    if type(v) == "table" and v[1] then return v[1], v[2], v[3] end
    return 1, 1, 1
end

-- What a name stores and previews as: the empty pick ("Same as fill") is "".
local function KeyOf(name)
    local c = Ctx()
    if c and c.empty and name == c.empty then return "" end
    return name
end

-- A dark well with a black edge and a StatusBar inset a pixel, a share full.
local function MakeBar(parent, w, h, share)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if w then f:SetSize(w, h) else f:SetHeight(h) end
    AT.Skin(f, BAR_BG, BLACK)
    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", -1, 1)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(share)
    f.sb = sb
    return f
end

-- The lists

local function Filtered()
    local all, q = TP.items or {}, (TP.q or ""):lower()
    local out = {}
    if q ~= "" then
        for _, it in ipairs(TP.ordered) do
            if it.name:lower():find(q, 1, true) then out[#out + 1] = it end
        end
        return out, #out .. (#out == 1 and " match" or " matches") .. " for \"" .. TP.q .. "\" in every group",
            "No texture has \"" .. TP.q .. "\" in its name."
    end
    local g = TP.group
    if g == "fav" then
        local favs = UI().texFavs
        for _, it in ipairs(all) do if favs[it.name] then out[#out + 1] = it end end
        table.sort(out, Lower)
        return out, "Favorites", "No favorites yet: click the star on a texture to keep it here."
    elseif g == "recent" then
        local by = {}
        for _, it in ipairs(all) do by[it.name] = it end
        for _, n in ipairs(UI().texRecent) do if by[n] then out[#out + 1] = by[n] end end
        return out, "Recently used", "Textures you use show here."
    elseif g == "all" then
        return TP.ordered, "All " .. #TP.ordered .. " textures", ""
    end
    for _, it in ipairs(all) do if it.src == g then out[#out + 1] = it end end
    table.sort(out, Lower)
    return out, #out .. " from " .. g, ""
end

-- The window

local function Hair(parent, edge)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    local px = AT.Hairline(parent)
    if edge == "bottom" then
        t:SetPoint("BOTTOMLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0); t:SetHeight(px)
    elseif edge == "top" then
        t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0); t:SetHeight(px)
    else
        t:SetPoint("TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", 0, 0); t:SetWidth(px)
    end
    return t
end

local function Font(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, size, "")
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    c = c or COL.ink
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

-- A two-way switch's half: lit while picked.
local function SegButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 26)
    AT.Skin(b, COL.well, COL.line2)
    b.fs = Font(b, 11)
    b.fs:SetPoint("CENTER", 0, 0)
    b.fs:SetText(text)
    function b:SetLit(on)
        local bg, edge, ink = COL.well, COL.line2, COL.dim
        if on then bg, edge, ink = COL.sel, COL.arc, COL.ink end
        self:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        self.fs:SetTextColor(ink[1], ink[2], ink[3])
    end
    return b
end

local function GroupButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(GROUP_H)
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetAllPoints()
    b.fill:SetTexture(WHITE)
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetTexture(WHITE)
    b.edge:SetPoint("TOPLEFT", 0, 0); b.edge:SetPoint("BOTTOMLEFT", 0, 0); b.edge:SetWidth(2)
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(COL.btnHover[1], COL.btnHover[2], COL.btnHover[3], 0.35)
    b.count = Font(b, 10, COL.dim)
    b.count:SetPoint("RIGHT", -8, 0)
    b.count:SetJustifyH("RIGHT")
    b.fs = Font(b, 12)
    b.fs:SetPoint("LEFT", 10, 0)
    b.fs:SetPoint("RIGHT", b.count, "LEFT", -6, 0)
    function b:SetLit(on)
        local s = on and COL.sel or CLEAR
        self.fill:SetVertexColor(s[1], s[2], s[3], on and 1 or 0)
        local e = on and COL.arc or CLEAR
        self.edge:SetVertexColor(e[1], e[2], e[3], on and 1 or 0)
        local c = on and COL.ink or COL.word
        self.fs:SetTextColor(c[1], c[2], c[3])
    end
    return b
end

local function ListRow(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    r:SetHeight(ROW_H)
    AT.Skin(r, CLEAR, CLEAR)
    r.star = CreateFrame("Button", nil, r)
    r.star:SetSize(24, 24)
    r.star:SetPoint("RIGHT", -4, 0)
    r.star.t = r.star:CreateTexture(nil, "ARTWORK")
    r.star.t:SetTexture(STAR)
    r.star.t:SetTexCoord(0, 0.5, 0, 0.5)
    r.star.t:SetDesaturated(true)
    r.star.t:SetSize(16, 16)
    r.star.t:SetPoint("CENTER", 0, 0)
    r.chip = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.chip:SetSize(44, 16)
    r.chip:SetPoint("RIGHT", r.star, "LEFT", -6, 0)
    AT.Skin(r.chip, CLEAR, GREEN_EDGE)
    r.chip.fs = Font(r.chip, 9, GREEN)
    r.chip.fs:SetPoint("CENTER", 0, 0)
    r.chip.fs:SetText("In use")
    r.bar = MakeBar(r, nil, ROW_BAR_H, 0.72)
    r.bar:SetPoint("LEFT", 4, 0)
    r.bar:EnableMouse(false)
    r.name = Font(r.bar, 11, { 1, 1, 1 })
    r.name:SetShadowColor(0, 0, 0, 1)
    r.name:SetShadowOffset(1, -1)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetPoint("RIGHT", -6, 0)
    return r
end

local function Draw()
    if not (TP.win and TP.win:IsShown()) then return end
    local list, title, empty = Filtered()
    TP.list = list
    TP.listTitle:SetText(title)
    TP.empty:SetText(empty)
    TP.empty:SetShown(#list == 0)
    -- the groups and their counts
    local favs, n = UI().texFavs, 0
    for _, it in ipairs(TP.items) do if favs[it.name] then n = n + 1 end end
    local recent = 0
    local seen = {}
    for _, it in ipairs(TP.items) do seen[it.name] = true end
    for _, nm in ipairs(UI().texRecent) do if seen[nm] then recent = recent + 1 end end
    for _, gb in ipairs(TP.groupButtons) do
        if gb.id == "fav" then gb.count:SetText(n)
        elseif gb.id == "recent" then gb.count:SetText(recent) end
        gb:SetLit(TP.q == "" and TP.group == gb.id)
    end
    TP.content:SetHeight(math.max(1, #list * ROW_H))
    TP.scroll:UpdateScroll()
end

-- Only the rows in sight exist: a pool follows the scroll.
local function DrawRows()
    local list = TP.list or {}
    local host = TP.scroll
    local off = host:GetVerticalScroll() or 0
    local first = math.floor(off / ROW_H)
    -- the list's own width until the first layout pass gives the real one
    local cw = TP.content:GetWidth() or 0
    if cw <= 1 then cw = W - 2 - GROUP_W - 22 end
    local r, g, b = Tint()
    local c = Ctx()
    local favs = UI().texFavs
    for i, row in ipairs(TP.rows) do
        local idx = first + i
        local it = list[idx]
        if it then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", TP.content, "TOPLEFT", 0, -(idx - 1) * ROW_H)
            row:SetWidth(cw)
            row.it = it
            row.bar.sb:SetStatusBarTexture(PathOf(it))
            row.bar.sb:SetStatusBarColor(r, g, b, 1)
            row.name:SetText(it.name)
            local inUse = it.name == TP.orig
            row.chip:SetShown(inUse)
            row.bar:SetPoint("RIGHT", inUse and row.chip or row.star, "LEFT", -6, 0)
            local fav = favs[it.name] and true or false
            row.star:SetShown(not it.isEmpty)
            local sc = fav and COL.arc or COL.steel
            row.star.t:SetVertexColor(sc[1], sc[2], sc[3], fav and 1 or 0.6)
            local picked, hot = it.name == TP.pending, it.name == TP.hover
            local fill = picked and COL.sel or CLEAR
            row:SetBackdropColor(fill[1], fill[2], fill[3], picked and 1 or 0)
            local edge = (picked and COL.arc) or (hot and COL.steel) or CLEAR
            row:SetBackdropBorderColor(edge[1], edge[2], edge[3], (picked or hot) and 1 or 0)
            row:Show()
        else
            row.it = nil
            row:Hide()
        end
    end
    -- the footer: the bar in its own colour with what it would show
    local shown = TP.hover or TP.pending
    local it = shown and TP.byName[shown]
    TP.footBar.sb:SetStatusBarTexture(it and PathOf(it) or WHITE)
    local br, bg, bb = BarTint()
    TP.footBar.sb:SetStatusBarColor(br, bg, bb, 1)
    TP.footName:SetText(shown or "")
    TP.footLabel:SetText(c and c.barName or "")
end

-- One restyle per frame however fast the mouse moves over the rows.
local function QueuePreview()
    if TP.queued then return end
    TP.queued = true
    C_Timer.After(0, function()
        TP.queued = false
        local c = Ctx()
        if not (c and c.liveId and TP.win and TP.win:IsShown()) then return end
        local shown = TP.hover or TP.pending
        local key = nil
        if shown ~= TP.orig then key = KeyOf(shown) end
        if key == TP.previewKey then return end
        TP.previewKey = key
        Bars().PreviewTexture(c.liveId, c.section, c.field, key)
    end)
end

local function Repaint()
    DrawRows()
    QueuePreview()
end

local function Remember(name)
    local u = UI()
    local out = { name }
    for _, n in ipairs(u.texRecent) do
        if n ~= name and #out < 6 then out[#out + 1] = n end
    end
    u.texRecent = out
end

function TP.Use()
    local c = Ctx()
    TP.used = true
    if c and TP.pending ~= nil then
        Remember(TP.pending)
        if TP.pending ~= TP.orig then c.set(TP.pending) end
    end
    TP.win:Hide()
end

function TP.Cancel()
    if TP.win then TP.win:Hide() end
end

local function Build()
    local p = AT.CreateWindow("ArcAurasTexturePicker", {
        w = W, h = H, minW = W, minH = H, resizable = false,
        title = "Bar texture", scaleH = Options.MAIN_H,
    })
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:Hide()
    TP.win = p
    TP.sub = Font(p.titleBar, 11, COL.dim)
    TP.sub:SetPoint("LEFT", p.titleText, "RIGHT", 8, 0)

    -- search, and the colour the textures are drawn in
    local tools = CreateFrame("Frame", nil, p)
    tools:SetPoint("TOPLEFT", 1, -31)
    tools:SetPoint("TOPRIGHT", -1, -31)
    tools:SetHeight(44)
    Hair(tools, "bottom")
    local box = CreateFrame("EditBox", nil, tools, "BackdropTemplate")
    box:SetSize(300, 26)
    box:SetPoint("LEFT", 12, 0)
    AT.Skin(box, COL.well, COL.line2)
    box:SetFont(AT.FONT, 12, "")
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    local hint = Font(box, 12, COL.faint)
    hint:SetPoint("LEFT", 8, 0)
    TP.hint = hint
    box:SetScript("OnTextChanged", function(self)
        TP.q = self:GetText() or ""
        hint:SetShown(TP.q == "")
        TP.scroll:SetVerticalScroll(0)
        Draw()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(COL.line2[1], COL.line2[2], COL.line2[3], 1) end)
    TP.box = box
    local white = SegButton(tools, "White", 64)
    white:SetPoint("RIGHT", -12, 0)
    local barc = SegButton(tools, "Bar color", 86)
    barc:SetPoint("RIGHT", white, "LEFT", 0, 0)
    local pin = Font(tools, 11, COL.dim)
    pin:SetPoint("RIGHT", barc, "LEFT", -10, 0)
    pin:SetText("Preview in")
    local function lit()
        barc:SetLit(not TP.white)
        white:SetLit(TP.white)
    end
    TP.litTint = lit
    barc:SetScript("OnClick", function() TP.white = false; UI().texWhite = nil; lit(); DrawRows() end)
    white:SetScript("OnClick", function() TP.white = true; UI().texWhite = true; lit(); DrawRows() end)

    -- the groups: what you keep, then one per addon the files come from
    local side = CreateFrame("Frame", nil, p, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 1, -75)
    side:SetPoint("BOTTOMLEFT", 1, 49)
    side:SetWidth(GROUP_W)
    AT.Skin(side, COL.well, COL.well)
    Hair(side, "right")
    local gHost, gContent = AT.MakeScroll(side)
    gHost:SetPoint("TOPLEFT", 8, -8)
    gHost:SetPoint("BOTTOMRIGHT", -8, 8)
    TP.gHost, TP.gContent = gHost, gContent
    TP.groupButtons = {}
    TP.fromLabel = Font(gContent, 10, COL.dim)
    TP.fromLabel:SetText("FROM")

    -- the list
    local main = CreateFrame("Frame", nil, p)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    main:SetPoint("BOTTOMRIGHT", -1, 49)
    TP.listTitle = Font(main, 10, COL.dim)
    TP.listTitle:SetPoint("TOPLEFT", 12, -9)
    TP.listTitle:SetPoint("TOPRIGHT", -12, -9)
    local host, content = AT.MakeScroll(main)
    host:SetPoint("TOPLEFT", 10, -28)
    host:SetPoint("BOTTOMRIGHT", -12, 8)
    TP.scroll, TP.content = host, content
    TP.empty = Font(main, 11, COL.dim)
    TP.empty:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -12)
    TP.empty:SetPoint("RIGHT", host, "RIGHT", -4, 0)
    TP.empty:SetWordWrap(true)
    host:SetScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
        -- the first open can ask for the current pick before the list has a size
        if TP.wantScroll and (self:GetHeight() or 0) > 1 then
            local want = TP.wantScroll
            TP.wantScroll = nil
            self:UpdateScroll()
            self:SetVerticalScroll(math.min(want, math.max(0, content:GetHeight() - self:GetHeight())))
        end
        self:UpdateScroll()
    end)
    local up = host.UpdateScroll
    function host:UpdateScroll()
        up(self)
        DrawRows()
        -- a scroll moves new textures under a resting mouse with no enter or
        -- leave, so the row under it is asked again
        local under
        for _, row in ipairs(TP.rows or {}) do
            if row:IsShown() and row.it and row:IsMouseOver() then under = row.it.name break end
        end
        if under ~= TP.hover then
            TP.hover = under
            Repaint()
        end
    end
    TP.rows = {}
    for i = 1, math.ceil((H - 75 - 49 - 36) / ROW_H) + 2 do
        local row = ListRow(content)
        row:SetScript("OnEnter", function(self)
            if self.it then TP.hover = self.it.name; Repaint() end
        end)
        row:SetScript("OnLeave", function(self)
            if TP.hover == (self.it and self.it.name) then TP.hover = nil; Repaint() end
        end)
        row:SetScript("OnClick", function(self)
            if self.it then TP.pending = self.it.name; Repaint() end
        end)
        row.star:SetScript("OnClick", function()
            local it = row.it
            if not it then return end
            local favs = UI().texFavs
            favs[it.name] = (not favs[it.name]) or nil
            Draw()
        end)
        AT.Tooltip(row.star, "Favorite", "Keep this texture under Favorites.")
        TP.rows[i] = row
    end

    -- the bar as it would look, then the way out
    local foot = CreateFrame("Frame", nil, p, "BackdropTemplate")
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(48)
    AT.Skin(foot, COL.well, COL.well)
    Hair(foot, "top")
    TP.footLabel = Font(foot, 11, COL.dim)
    TP.footLabel:SetPoint("LEFT", 12, 0)
    TP.footBar = MakeBar(foot, 220, 18, 0.64)
    TP.footBar:SetPoint("LEFT", TP.footLabel, "RIGHT", 10, 0)
    local use = AT.MakeSmallButton(foot, "Use texture", 110)
    use:SetHeight(26)
    use:SetPoint("RIGHT", -12, 0)
    use:SetScript("OnClick", TP.Use)
    local cancel = AT.MakeQuietButton(foot, "Cancel", 80)
    cancel:SetHeight(26)
    cancel:SetPoint("RIGHT", use, "LEFT", -8, 0)
    cancel:SetScript("OnClick", TP.Cancel)
    TP.footName = Font(foot, 11, COL.word)
    TP.footName:SetPoint("LEFT", TP.footBar, "RIGHT", 10, 0)
    TP.footName:SetPoint("RIGHT", cancel, "LEFT", -10, 0)

    -- Any way out puts the bar back unless Use texture kept the pick.
    p:HookScript("OnHide", function()
        TP.hover = nil
        local c = Ctx()
        if TP.previewKey ~= nil then
            TP.previewKey = nil
            Bars().PreviewTexture(nil)
        end
        if c and c.done then c.done() end
        TP.ctx = nil
        if TP.box then TP.box:ClearFocus() end
    end)
end

-- The groups for this open: Favorites, Recent, All, then a source each.
local function LayoutGroups()
    local srcs, have = {}, {}
    for _, it in ipairs(TP.items) do
        if it.src and not have[it.src] then
            have[it.src] = true
            if it.src ~= "Game" and it.src ~= OWN then srcs[#srcs + 1] = it.src end
        end
    end
    table.sort(srcs, function(a, b) return a:lower() < b:lower() end)
    local order = { { "fav", "Favorites" }, { "recent", "Recent" }, { "all", "All" } }
    if have.Game then order[#order + 1] = { "Game", "Game", true } end
    if have[OWN] then order[#order + 1] = { OWN, OWN, true } end
    for _, s in ipairs(srcs) do order[#order + 1] = { s, s, true } end
    local y, content, fromAt = 0, TP.gContent, nil
    local w = GROUP_W - 16
    for i, g in ipairs(order) do
        if g[3] and not fromAt then
            fromAt = y + 8
            TP.fromLabel:ClearAllPoints()
            TP.fromLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -fromAt)
            y = fromAt + 18
        end
        local b = TP.groupButtons[i]
        if not b then
            b = GroupButton(content)
            TP.groupButtons[i] = b
            b:SetScript("OnClick", function(self)
                TP.group = self.id
                TP.q = ""
                TP.box:SetText("")
                TP.scroll:SetVerticalScroll(0)
                Draw()
            end)
        end
        b.id = g[1]
        b.fs:SetText(g[2])
        local count = 0
        if g[3] then for _, it in ipairs(TP.items) do if it.src == g[1] then count = count + 1 end end
        elseif g[1] == "all" then count = #TP.ordered end
        b.count:SetText(count)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        b:SetWidth(w)
        b:Show()
        y = y + GROUP_H + 2
    end
    for i = #order + 1, #TP.groupButtons do
        TP.groupButtons[i]:Hide()
        TP.groupButtons[i].id = nil
    end
    content:SetSize(w, y)
    TP.gHost:UpdateScroll()
end

-- ctx: label, barName, get(), set(v), empty (a first pick that stores ""),
-- emptyKey() (what that pick draws), tint() (the bar's colour), liveId (the
-- bar the picks show on, nil for a proxy), section, field, done().
function TP.Open(ctx)
    if InCombatLockdown and InCombatLockdown() then return end
    if not TP.win then Build() end
    if TP.win:IsShown() then TP.win:Hide() end
    TP.ctx = ctx
    TP.used, TP.hover, TP.previewKey = false, nil, nil
    TP.orig = ctx.get()
    TP.pending = TP.orig
    TP.white = UI().texWhite == true
    TP.items = TP.Catalog()
    if ctx.empty then
        table.insert(TP.items, 1, { name = ctx.empty, isEmpty = true, first = true })
    end
    if TP.orig ~= ctx.empty then TP.Keep(TP.items, TP.orig) end
    local firsts, rest = {}, {}
    for _, it in ipairs(TP.items) do
        if it.first then firsts[#firsts + 1] = it else rest[#rest + 1] = it end
    end
    table.sort(rest, Lower)
    for _, it in ipairs(rest) do firsts[#firsts + 1] = it end
    TP.ordered = firsts
    TP.byName = {}
    for _, it in ipairs(TP.items) do TP.byName[it.name] = it end
    TP.q = ""
    TP.box:SetText("")
    TP.hint:SetText("Search all " .. #TP.ordered .. " textures")
    TP.hint:Show()
    TP.win.titleText:SetText(ctx.label or "Bar texture")
    TP.sub:SetText(ctx.barName or "")
    TP.litTint()
    -- beside the options window, where the board drew it
    local opts = _G.ArcUIv2Options
    TP.win:ClearAllPoints()
    if opts and opts:IsShown() then
        TP.win:SetPoint("TOPRIGHT", opts, "TOPRIGHT", -24, -92)
        if not TP.hooked then
            TP.hooked = true
            opts:HookScript("OnHide", TP.Cancel)
        end
    else
        TP.win:SetPoint("CENTER", 0, 40)
    end
    TP.win:Show()
    LayoutGroups()
    -- the current pick in sight, in its group
    if TP.group ~= "all" and TP.group ~= "fav" and TP.group ~= "recent" then
        local cur = TP.byName[TP.orig]
        TP.group = (cur and cur.src) or "all"
    end
    Draw()
    local list = TP.list or {}
    TP.wantScroll = nil
    for i, it in ipairs(list) do
        if it.name == TP.orig then
            local view = TP.scroll:GetHeight() or 0
            local sized = view > 1
            if not sized then view = H - 75 - 49 - 36 end
            local want = (i - 1) * ROW_H - math.floor(view / 2) + ROW_H
            local over = (#list * ROW_H) - view
            if want > over then want = over end
            if want < 0 then want = 0 end
            if sized then
                TP.scroll:SetVerticalScroll(want)
                TP.scroll:UpdateScroll()
            else
                TP.wantScroll = want
            end
            break
        end
    end
    DrawRows()
end

-- The row in an editor: a swatch of the texture on a small bar with its name
-- beside it, clicked like a colour swatch to open the picker window (not a
-- field: nothing drops down). opts: empty / emptyKey as for TP.Open, rec()
-- (the record or proxy being edited), section, field.
function Options.TextureRow(pg, owner, label, get, set, visibleFn, opts)
    opts = opts or {}
    local row = AT.AddRow(pg, AT.LAY.rowH, visibleFn)
    local lbl = AT.RowLabel(row, label)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(260, 20)
    b:SetPoint("LEFT", row._ctrlX, 0)
    local sw = MakeBar(b, 72, 16, 0.72)
    sw:SetPoint("LEFT", 0, 0)
    local fs = Font(b, 11)
    fs:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    fs:SetPoint("RIGHT", 0, 0)
    b:SetScript("OnEnter", function() sw:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
    b:SetScript("OnLeave", function() sw:SetBackdropBorderColor(0, 0, 0, 1) end)
    local function Rec() return opts.rec and opts.rec() end
    -- the colour the fill really shows (a resource bar's power colour)
    local function TintOf()
        local r = Rec()
        if not r then return nil end
        local B = NS.Bars
        if B and B.FillColorOf then
            local cr, cg, cb = B.FillColorOf(r)
            if cr then return { cr, cg, cb } end
        end
        return Store.Resolve(r, "fill", "color")
    end
    local function Refresh()
        local v = get()
        fs:SetText(v or "")
        local key = v
        if opts.empty and v == opts.empty then key = opts.emptyKey and opts.emptyKey() or "" end
        local K = NS.Bars and NS.Bars.Kit
        sw.sb:SetStatusBarTexture(K and K.ResolveBarTexture(key) or WHITE)
        local c = TintOf()
        if type(c) == "table" and c[1] then sw.sb:SetStatusBarColor(c[1], c[2], c[3], 1)
        else sw.sb:SetStatusBarColor(1, 1, 1, 1) end
    end
    Refresh()
    b:SetScript("OnClick", function()
        AT.CloseDropdown()
        local r = Rec()
        -- only a real bar shows the picks live; a layout, default or several
        -- bars at once take the pick on Use
        local live = r and r.id and Store.Get(r.id) == r and r.id or nil
        TP.Open({
            label = label, barName = live and r.name or nil,
            get = get, set = set, empty = opts.empty, emptyKey = opts.emptyKey,
            tint = TintOf, liveId = live, section = opts.section, field = opts.field,
            done = Refresh,
        })
    end)
    row._colLabel, row._colCtrl = lbl, b
    row._sync = Refresh
    return row
end
