-- AD_TextureOptions: a texture's Add window tab, its Tracking rows (what drives it: an aura, a spell's cooldown or custom triggers), its tab list and the picture picker the Appearance block draws.
-- AD_Options calls in behind nil checks; the runtime is Bars\AD_TextureElement.lua, the triggers are UI\AD_TextOptions.lua's shared block.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local TPO = {}
Options.TextureElement = TPO

local function Trim(v)
    return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function TPO.Runtime() return NS.TextureElements end

-- The sources this client can feed: an engine a source needs must be there.
function TPO.SourceItems()
    local S = NS.Schema
    local out = {}
    for _, s in ipairs(S.TEXTURE_SOURCES or {}) do
        local ok = true
        if s == "aura" then
            ok = NS.DriverAura ~= nil and NS.DriverAura.IsAvailable ~= nil and NS.DriverAura.IsAvailable() == true
        elseif s == "rules" then
            ok = NS.DriverCustom ~= nil
        elseif s == "spellCd" then
            ok = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil
        elseif s == "power" then
            ok = UnitPowerPercent ~= nil
        elseif s == "health" then
            ok = UnitHealthPercent ~= nil
        end
        if ok then out[#out + 1] = { value = s, text = S.TEXTURE_SOURCE_LABELS[s] or s } end
    end
    return out
end

local function ParseSpell(text)
    local CO = Options.Custom
    if CO and CO.ParseSpell then return CO.ParseSpell(text) end
    local id = tonumber(Trim(text))
    return (id and id > 0) and math.floor(id) or nil
end

local function SpellName(id)
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
    if (issecretvalue and issecretvalue(nm)) or type(nm) ~= "string" then return "" end
    return nm
end

-- a value that names one of the client's atlases
function TPO.IsAtlas(v)
    return type(v) == "string" and v ~= "" and not tonumber(v) and C_Texture ~= nil
        and C_Texture.GetAtlasExists ~= nil and C_Texture.GetAtlasExists(v) == true
end

-- The shared media pictures (backgrounds and bar textures): path -> name.
function TPO.MediaNames()
    local lsm = NS.Bars and NS.Bars.GetLSM and NS.Bars.GetLSM()
    local out = {}
    if not lsm then return out end
    for _, kind in ipairs({ "background", "statusbar" }) do
        for name, path in pairs(lsm:HashTable(kind) or {}) do
            if type(path) == "string" or type(path) == "number" then out[tostring(path)] = name end
        end
    end
    return out
end

-- Picked from the picker (a library picture, an animated sheet, shared media
-- or an atlas), so the box for a picture of your own stays empty.
function TPO.InLibrary(v)
    local n = tonumber(v)
    if n then return Options.TEXTURE_NAMES ~= nil and Options.TEXTURE_NAMES[n] ~= nil end
    if TPO.IsAtlas(v) then return true end
    return TPO.MediaNames()[tostring(v or "")] ~= nil
end

-- A picture on a texture: an atlas as the atlas, anything else as a file,
-- in the blend it is shown with (glow art on black loses its black).
function TPO.SetArt(tex, v, spellID, blend)
    if TPO.IsAtlas(v) and tex.SetAtlas then
        tex:SetAtlas(v, false)
    else
        tex:SetTexture(TPO.ArtOf(v, spellID))
        tex:SetTexCoord(0, 1, 0, 1)
    end
    tex:SetBlendMode(blend == "ADD" and "ADD" or "BLEND")
end

-- The blend a picked picture is made for: Glow for the library's glow art and
-- the game's additive sheets, Normal for the rest it knows; nil for a picture
-- of your own (its blend stays yours).
function TPO.BlendFor(v)
    v = tostring(v or "")
    if v == "" then return "BLEND" end
    local n = tonumber(v)
    if n then
        if Options.TEXTURE_NAMES and Options.TEXTURE_NAMES[n] then
            return (Options.TEXTURE_GLOW and Options.TEXTURE_GLOW[n]) and "ADD" or "BLEND"
        end
        return nil
    end
    local s = Options.TEXTURE_SHEET_OF and Options.TEXTURE_SHEET_OF[v]
    if s then return s.glow and "ADD" or "BLEND" end
    if TPO.IsAtlas(v) or TPO.MediaNames()[v] then return "BLEND" end
    return nil
end

-- A picked main picture brings its look: its blend, and for an animated
-- sheet the whole picture played as its grid (anything else: no sheet).
function TPO.ApplyPick(rec, v)
    local Store = NS.Store
    if not (rec and Store) then return end
    local blend = TPO.BlendFor(v)
    if blend then Store.SetOverride(rec, "texlook", "blend", blend) end
    local s = Options.TEXTURE_SHEET_OF and Options.TEXTURE_SHEET_OF[tostring(v or "")]
    if s then
        Store.SetOverride(rec, "texlook", "mode", "show")
        Store.SetOverride(rec, "texlook", "flipOn", true)
        Store.SetOverride(rec, "texlook", "flipRows", s.rows)
        Store.SetOverride(rec, "texlook", "flipCols", s.cols)
        Store.SetOverride(rec, "texlook", "flipFrames", s.frames)
        Store.SetOverride(rec, "texlook", "flipTime", s.time)
    elseif Store.Resolve(rec, "texlook", "flipOn") == true then
        Store.SetOverride(rec, "texlook", "flipOn", false)
    end
end

-- What a picture value is called: the spell's icon (empty), a library name, or
-- a picture of your own.
function TPO.PictureName(v)
    v = tostring(v or "")
    if v == "" then return "The spell's icon" end
    local n = tonumber(v)
    local nm = n and Options.TEXTURE_NAMES and Options.TEXTURE_NAMES[n]
    if nm then return nm end
    local s = Options.TEXTURE_SHEET_OF and Options.TEXTURE_SHEET_OF[v]
    if s then return s.name .. " (animated)" end
    local m = TPO.MediaNames()[v]
    if m then return m end
    if TPO.IsAtlas(v) then return "Atlas: " .. v end
    return "Your own: " .. v
end

-- What SetTexture takes for a value: the spell's icon when it is empty.
function TPO.ArtOf(v, spellID)
    v = tostring(v or "")
    if v ~= "" then return tonumber(v) or v end
    local icon = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) -- raw-id: the picker's preview of a typed spell
    if icon ~= nil and not (issecretvalue and issecretvalue(icon)) then return icon end
    return 134400
end

function TPO.DefaultName(source, spellID)
    local nm = SpellName(spellID)
    if source == "rules" then return "Custom texture" end
    if source == "power" then return "Power texture" end
    if source == "health" then return "Health texture" end
    if nm ~= "" then return nm end
    return (source == "spellCd") and "Cooldown texture" or "Aura texture"
end

-- The sidebar's and cards' one line.
function Options.TextureWhat(rec)
    local T = TPO.Runtime()
    return T and T.Describe(rec) or "texture"
end

-- The editor tabs: Triggers only for a picture with custom triggers.
function Options.TextureTabs(rec)
    local tabs = { "Tracking" }
    if rec.driver and rec.driver.source == "rules" then tabs[#tabs + 1] = "Triggers" end
    -- a value's picture has no stack count or time left to write
    local valued = NS.Schema.TexValue and NS.Schema.TexValue(rec)
    for _, t in ipairs({ "Appearance", "Conditions", "Text", "Position", "Load Conditions" }) do
        if not (t == "Text" and valued) then tabs[#tabs + 1] = t end
    end
    return tabs
end

-- The picture picker: every library picture as a thumbnail, by group, with a
-- search over names and IDs. A click uses one at once and the window stays
-- open to try others. It edits the one thing it was opened for and closes
-- with the window that opened it, or when its row goes away.
TPO.CELL, TPO.GAP, TPO.HEAD = 64, 6, 26

function TPO.BuildPicker()
    if TPO.win then return TPO.win end
    local AT, COL = NS.AT, NS.AT.COL
    local win = AT.CreateWindow("ArcAurasPicturePicker", {
        w = 600, h = 560, minW = 420, minH = 360, maxW = 1400, maxH = 1200,
        title = NS.AT.Brand("Choose", " a Picture"),
    })
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", 8, -38)
    body:SetPoint("BOTTOMRIGHT", -8, 8)
    local search = CreateFrame("EditBox", nil, body, "BackdropTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", 0, 0)
    AT.Skin(search, COL.well)
    search:SetFont(NS.AT.FONT, 11, "")
    search:SetTextInsets(6, 6, 0, 0)
    search:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    search:SetAutoFocus(false)
    local hint = search:CreateFontString(nil, "OVERLAY")
    hint:SetFont(NS.AT.FONT, 11, "")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(COL.faint[1], COL.faint[2], COL.faint[3])
    hint:SetText("Search by name or ID")
    search:SetScript("OnTextChanged", function(self)
        hint:SetShown((self:GetText() or "") == "")
        TPO.LayoutPicker()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    local done = AT.MakeSmallButton(body, "Done", 70)
    done:SetPoint("TOPRIGHT", 0, 0)
    done:SetHeight(20)
    done.fs:SetTextColor(COL.lead[1], COL.lead[2], COL.lead[3])
    done:SetScript("OnClick", function() win:Hide() end)
    local count = body:CreateFontString(nil, "OVERLAY")
    count:SetFont(NS.AT.FONT, 11, "")
    count:SetPoint("LEFT", search, "RIGHT", 12, 0)
    count:SetPoint("RIGHT", done, "LEFT", -12, 0)
    count:SetJustifyH("LEFT")
    count:SetWordWrap(false)
    count:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    local host, content = AT.MakeScroll(body)
    host:SetPoint("TOPLEFT", 0, -30)
    host:SetPoint("BOTTOMRIGHT", -6, 0)
    -- the width decides how many fit a line: lay out again whenever it moves
    host:HookScript("OnSizeChanged", function() TPO.LayoutPicker() end)
    local empty = body:CreateFontString(nil, "OVERLAY")
    empty:SetFont(NS.AT.FONT, 12, "")
    empty:SetPoint("CENTER", host, "CENTER", 0, 0)
    empty:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    empty:SetText("No picture matches.")
    empty:Hide()
    win:HookScript("OnHide", function() TPO.pick = nil end)
    TPO.win, TPO.searchBox, TPO.countFS, TPO.scroll, TPO.content, TPO.emptyFS = win, search, count, host, content, empty
    TPO.tiles, TPO.heads = {}, {}
    return win
end

-- One thumbnail: the picture in a box, its name and ID on hover, a click uses it.
function TPO.Tile(i)
    local t = TPO.tiles[i]
    if t then return t end
    local AT, COL = NS.AT, NS.AT.COL
    t = CreateFrame("Button", nil, TPO.content, "BackdropTemplate")
    t:SetSize(TPO.CELL, TPO.CELL)
    AT.Skin(t, COL.box, COL.line)
    t.art = t:CreateTexture(nil, "ARTWORK")
    t.art:SetPoint("TOPLEFT", 6, -6)
    t.art:SetPoint("BOTTOMRIGHT", -6, 6)
    t:SetScript("OnEnter", function(self)
        if not self.sel then self:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end
    end)
    t:SetScript("OnLeave", function(self) TPO.PaintTile(self) end)
    AT.Tooltip(t, function() return t.name end, function() return t.sub end)
    t:SetScript("OnClick", function(self) TPO.Use(self.value) end)
    -- an animated sheet plays in its tile while the picker is open
    t.flip = t.art:CreateAnimationGroup()
    t.flip:SetLooping("REPEAT")
    t.flip.fb = t.flip:CreateAnimation("FlipBook")
    t.flip.fb:SetFlipBookFrameWidth(0)
    t.flip.fb:SetFlipBookFrameHeight(0)
    TPO.tiles[i] = t
    return t
end

-- The picked one stands out in the accent colour.
function TPO.PaintTile(t)
    local COL = NS.AT.COL
    local p = TPO.pick
    t.sel = p ~= nil and t.value == tostring(p.get() or "")
    local bg, line = t.sel and COL.panel or COL.box, t.sel and COL.arc or COL.line
    t:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    t:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

-- A group's title line over its pictures, in the panels' section style.
function TPO.Head(i)
    local h = TPO.heads[i]
    if h then return h end
    local AT, COL = NS.AT, NS.AT.COL
    h = CreateFrame("Frame", nil, TPO.content)
    h:SetHeight(TPO.HEAD)
    h.fs = h:CreateFontString(nil, "OVERLAY")
    h.fs:SetFont(NS.AT.FONT, 11, "")
    h.fs:SetPoint("BOTTOMLEFT", 2, 8)
    h.fs:SetTextColor(COL.title[1], COL.title[2], COL.title[3])
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetTexture(AT.WHITE)
    h.line:SetVertexColor(COL.line[1], COL.line[2], COL.line[3], 1)
    h.line:SetPoint("BOTTOMLEFT", 0, 4)
    h.line:SetPoint("BOTTOMRIGHT", 0, 4)
    h.line:SetHeight(AT.Hairline and AT.Hairline(h) or 1)
    TPO.heads[i] = h
    return h
end

-- The client's atlas names holding q (3 letters or more), at most
-- TPO.ATLAS_CAP; the names are read once, on the first search.
TPO.ATLAS_CAP = 150
function TPO.AtlasMatches(q)
    if #q < 3 or not (C_Texture and C_Texture.GetAtlasElements) then return {}, false end
    if not TPO.atlasLower then
        TPO.atlasNames, TPO.atlasLower = {}, {}
        for _, name in ipairs(C_Texture.GetAtlasElements() or {}) do
            if type(name) == "string" then
                TPO.atlasNames[#TPO.atlasNames + 1] = name
                TPO.atlasLower[#TPO.atlasLower + 1] = name:lower()
            end
        end
    end
    local out, more = {}, false
    for i, low in ipairs(TPO.atlasLower) do
        if low:find(q, 1, true) then
            if #out >= TPO.ATLAS_CAP then
                more = true
                break
            end
            out[#out + 1] = TPO.atlasNames[i]
        end
    end
    return out, more
end

-- The groups the picker shows: the spell's icon and your own picture (when
-- one is set) first, then the library, the game's animated sheets, shared
-- media, and the client's atlases once a search is typed.
function TPO.PickerGroups(p, q)
    local cur = tostring(p.get() or "")
    local basics = { { value = "", name = "The spell's icon", art = p.spellArt(), sub = "Follows the spell it tracks." } }
    if cur ~= "" and not TPO.InLibrary(cur) then
        -- your own picture, in the blend you gave it
        basics[#basics + 1] = { value = cur, name = "Your own", art = tonumber(cur) or cur, sub = cur,
            glow = p.blend ~= nil and p.blend() == "ADD" }
    end
    local out = { { name = "Basics", list = basics } }
    for _, g in ipairs(Options.TEXTURE_LIBRARY or {}) do
        local list = {}
        for _, pic in ipairs(g.pictures) do
            list[#list + 1] = { value = tostring(pic.id), name = pic.name, art = pic.id,
                sub = g.name .. ", ID " .. pic.id, glow = g.glow }
        end
        out[#out + 1] = { name = g.name, list = list }
    end
    local sheets = {}
    for _, s in ipairs(Options.TEXTURE_SHEETS or {}) do
        if TPO.IsAtlas(s.atlas) then
            sheets[#sheets + 1] = { value = s.atlas, name = s.name, atlas = s.atlas, sheet = s,
                sub = "Animated, " .. s.frames .. " frames", glow = s.glow }
        end
    end
    if #sheets > 0 then out[#out + 1] = { name = "Animated", list = sheets } end
    local media = {}
    for path, name in pairs(TPO.MediaNames()) do
        media[#media + 1] = { value = path, name = name, art = tonumber(path) or path, sub = "Shared media" }
    end
    table.sort(media, function(a, b) return a.name < b.name end)
    if #media > 0 then out[#out + 1] = { name = "Shared Media", list = media } end
    local atl, more = TPO.AtlasMatches(q or "")
    if #atl > 0 then
        local list = {}
        for _, name in ipairs(atl) do
            list[#list + 1] = { value = name, name = name, atlas = name, sub = "Atlas" }
        end
        out[#out + 1] = { name = more and ("Atlases (first " .. TPO.ATLAS_CAP .. ")") or "Atlases",
            list = list, atlases = true }
    end
    return out
end

-- Lays the pictures out for the window's width: a title line per group with
-- a match, then its thumbnails, wrapping. The search keeps names or IDs that
-- hold what is typed.
function TPO.LayoutPicker()
    local p, win = TPO.pick, TPO.win
    if not (p and win and win:IsShown()) then return end
    local q = Trim(TPO.searchBox:GetText()):lower()
    local width = (TPO.scroll:GetWidth() or 0) - NS.AT.ScrollExtra()
    local step = TPO.CELL + TPO.GAP
    local per = math.max(1, math.floor((width + TPO.GAP) / step))
    TPO.content:SetWidth(math.max(1, width))
    local y, ti, hi, found, total, selY = 0, 0, 0, 0, 0, nil
    for _, g in ipairs(TPO.PickerGroups(p, q)) do
        local shown = {}
        for _, it in ipairs(g.list) do
            if g.name ~= "Basics" and not g.atlases then total = total + 1 end
            if q == "" or it.name:lower():find(q, 1, true) or it.value:find(q, 1, true) then
                shown[#shown + 1] = it
            end
        end
        if #shown > 0 then
            hi = hi + 1
            local h = TPO.Head(hi)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", TPO.content, "TOPLEFT", 0, -y)
            h:SetPoint("RIGHT", TPO.content, "RIGHT", 0, 0)
            h.fs:SetText(g.name:upper())
            h:Show()
            y = y + TPO.HEAD
            for i, it in ipairs(shown) do
                ti = ti + 1
                local t = TPO.Tile(ti)
                t.value, t.name, t.sub = it.value, it.name, it.sub
                if it.atlas and t.art.SetAtlas then
                    t.art:SetAtlas(it.atlas, false)
                else
                    t.art:SetTexture(it.art)
                    t.art:SetTexCoord(0, 1, 0, 1)
                end
                -- glow art in the blend it is made for: no black square
                t.art:SetBlendMode(it.glow and "ADD" or "BLEND")
                local s = it.sheet
                if s then
                    t.flip:Stop()
                    t.flip.fb:SetFlipBookRows(s.rows)
                    t.flip.fb:SetFlipBookColumns(s.cols)
                    t.flip.fb:SetFlipBookFrames(s.frames)
                    t.flip.fb:SetDuration(s.time)
                    t.flip:Play()
                elseif t.flip:IsPlaying() then
                    t.flip:Stop()
                end
                local ty = y + math.floor((i - 1) / per) * step
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", TPO.content, "TOPLEFT", ((i - 1) % per) * step, -ty)
                TPO.PaintTile(t)
                if t.sel then selY = ty end
                t:Show()
            end
            y = y + math.ceil(#shown / per) * step + 4
            found = found + #shown
        end
    end
    for i = ti + 1, #TPO.tiles do
        TPO.tiles[i]:Hide()
        TPO.tiles[i].flip:Stop()
    end
    for i = hi + 1, #TPO.heads do TPO.heads[i]:Hide() end
    TPO.content:SetHeight(math.max(1, y))
    TPO.scroll:UpdateScroll()
    TPO.emptyFS:SetShown(found == 0)
    local what = (q == "") and (total .. " pictures") or (found == 1 and "1 match" or (found .. " matches"))
    TPO.countFS:SetText((p.what and p.what ~= "" and (p.what .. ": ") or "") .. what)
    p.laidFor = tostring(p.get() or "")
    return selY
end

-- Brings the picked picture into view.
function TPO.ScrollToPick(selY)
    local host = TPO.scroll
    if not (selY and host) then return end
    local viewH = host:GetHeight() or 0
    local cur = host:GetVerticalScroll() or 0
    if selY >= cur and selY + TPO.CELL <= cur + viewH then return end
    local over = (TPO.content:GetHeight() or 0) - viewH
    local want = math.max(0, math.min(over, selY - TPO.HEAD))
    host:SetVerticalScroll(want)
    host:UpdateScroll()
end

function TPO.Use(v)
    local p = TPO.pick
    if not p then return end
    p.set(v)
    if p.rec and p.sheets then TPO.ApplyPick(p.rec, v) end
    TPO.LayoutPicker()
end

-- p: get() the value, set(v) a pick, spellArt() the spell's icon tile's art,
-- what (the name in the window's line), owner (the window that opened it, it
-- closes with it), row (the chooser row that opened it), rec (the record).
function TPO.OpenPicker(p)
    TPO.BuildPicker()
    local owner = p.owner
    if owner and owner.HookScript and not owner._adPickerHooked then
        owner._adPickerHooked = true
        owner:HookScript("OnHide", function() TPO.ClosePicker() end)
    end
    TPO.pick = p
    TPO.searchBox:SetText("")
    TPO.win:Show()
    TPO.win:Raise()
    TPO.ScrollToPick(TPO.LayoutPicker())
end

function TPO.ClosePicker()
    if TPO.win and TPO.win:IsShown() then TPO.win:Hide() end
    TPO.pick = nil
end

-- The chooser: a preview of what shows now and its name, and a button (or a
-- click on the preview) that opens the picker. c = { get, set, spellID, what,
-- rec, visible }; set receives the picked value.
function TPO.ChooserRow(pg, owner, label, c)
    local AT, COL = NS.AT, NS.AT.COL
    local row = AT.AddRow(pg, 48, c.visible)
    local lbl = AT.RowLabel(row, label)
    local box = CreateFrame("Button", nil, row, "BackdropTemplate")
    box:SetSize(44, 44)
    box:SetPoint("LEFT", row._ctrlX, 0)
    AT.Skin(box, COL.well, COL.line)
    local art = box:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 3, -3)
    art:SetPoint("BOTTOMRIGHT", -3, 3)
    local nameFS = row:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(NS.AT.FONT, 12, "")
    nameFS:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, -2)
    nameFS:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    local btn = AT.MakeSmallButton(row, "Choose picture", 120)
    btn:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 10, 1)
    local function Open()
        AT.CloseDropdown()
        TPO.OpenPicker({
            get = c.get,
            set = function(v)
                c.set(v)
                AT.LayoutPage(pg)
            end,
            spellArt = function() return TPO.ArtOf("", c.spellID and c.spellID()) end,
            what = c.what and c.what() or nil,
            owner = owner, row = row, rec = c.rec and c.rec() or nil, sheets = c.sheets, blend = c.blend,
        })
    end
    box:SetScript("OnClick", Open)
    btn:SetScript("OnClick", Open)
    box:SetScript("OnEnter", function() box:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1) end)
    box:SetScript("OnLeave", function() box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1) end)
    AT.Tooltip(box, label, "Click to choose from every picture.")
    -- a hidden section's rows are not synced: the row's own hide (its section,
    -- tab or window going away) closes the picker it opened
    row:HookScript("OnHide", function()
        local p = TPO.pick
        if p and p.row == row then TPO.ClosePicker() end
    end)
    -- the preview leads: the page pins it to the label column, and the name
    -- and the button ride on its right
    row._colLabel, row._colCtrl, row._colTrail = lbl, box, 10 + btn:GetWidth()
    row.button = btn
    row._sync = function()
        local v = c.get()
        TPO.SetArt(art, v, c.spellID and c.spellID(), (c.blend and c.blend()) or TPO.BlendFor(v))
        nameFS:SetText(TPO.PictureName(v))
        -- the picker follows its row: gone or on another record, it closes
        local p = TPO.pick
        if p and p.row == row then
            local vis = (not c.visible) or c.visible()
            if not vis or (c.rec and p.rec ~= c.rec()) then
                TPO.ClosePicker()
            elseif p.laidFor ~= tostring(v or "") then
                TPO.LayoutPicker()
            end
        end
    end
    return row
end

-- The picture field (SectionRows draws it for `picture`): the chooser, and a
-- box under it for a picture of your own (a FileDataID or a file path).
function Options.PictureRow(pg, owner, label, section, field, ctx, visible)
    local AT, Store = NS.AT, NS.Store
    local function Cur()
        local r = ctx()
        local v = r and Store.Resolve(r, section, field)
        return (v ~= nil) and tostring(v) or ""
    end
    local row = TPO.ChooserRow(pg, owner, label, {
        get = Cur,
        set = function(v)
            local r = ctx()
            if r then Store.SetOverride(r, section, field, tostring(v or "")) end
        end,
        -- the spell the live picture wears: a cooldown's rank and override,
        -- an aura's first aura (each question's own entry)
        spellID = function()
            local r = ctx()
            if not (r and r.driver) then return nil end
            local TP = NS.TextureElements
            if TP and TP.Source(r) == "spellCd" then return TP.EffSpell(r) end
            return Store.TrackedAuraIDs(r.driver)[1]
        end,
        what = function()
            local r = ctx()
            return r and r.name or nil
        end,
        rec = ctx,
        visible = visible,
        -- the main picture may be one of the game's animated sheets, and
        -- brings its blend
        sheets = section == "texlook" and field == "image",
        blend = function()
            local r = ctx()
            return r and Store.Resolve(r, "texlook", "blend") or nil
        end,
    })
    AT.RowInput(pg, "Picture ID or path",
        function()
            local v = Cur()
            return (v ~= "" and not TPO.InLibrary(v)) and v or ""
        end,
        function(v)
            local r = ctx()
            if not r then return end
            Store.SetOverride(r, section, field, Trim(v))
            AT.LayoutPage(pg)
        end,
        visible, "A picture of your own: its FileDataID, or its path such as Interface/AddOns/MyMedia/glow. Enter applies it; empty = pick one above.",
        "e.g. 450917")
    return row
end

-- The Add window's tab: what drives it, the aura or spell, the picture and a
-- name; the rest is set in the editor once it exists.
function Options.TextureAddRows(pg, owner, addState)
    local AT = NS.AT
    local vis = function() return addState.cat == "Texture" end
    local function Src() return addState.texSource or "aura" end
    local function Is(...)
        local want = { ... }
        return function()
            if not vis() then return false end
            for _, s in ipairs(want) do if Src() == s then return true end end
            return false
        end
    end
    local S = NS.Schema
    local function Items(values, labels)
        local out = {}
        for _, v in ipairs(values) do out[#out + 1] = { value = v, text = labels[v] or v } end
        return out
    end
    local function Mode() return addState.texMode or "show" end
    -- the aura as the editor's Tracking rows would hold it
    local function AuraDriver()
        return { source = "aura", spellID = ParseSpell(addState.texSpell or ""), auraType = addState.texAuraType,
            unit = addState.texUnit }
    end
    local function AuraUnit()
        return addState.texUnit or ((addState.texAuraType == "debuff") and "target" or "player")
    end
    AT.RowDesc(pg, "A picture that follows an aura, a cooldown, your power, health or triggers.", 20, vis)
    AT.RowDropdown(pg, owner, "Picture driven by",
        Src,
        function(v) addState.texSource = v end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    AT.RowInput(pg, "Aura or spell",
        function() return addState.texSpell or "" end,
        function(v)
            addState.texSpell = v
            -- the page again, so Create is judged with it
            AT.LayoutPage(pg)
        end,
        Is("aura", "spellCd"),
        "The aura's spell ID, or the spell whose cooldown it follows: an ID, a link or the name of a spell you know. Enter applies it.",
        "e.g. 1459")
    -- an aura: buff or debuff, and on whom (the aura icons' shape)
    AT.RowDropdown(pg, owner, "Buff or debuff",
        function() return addState.texAuraType or "buff" end,
        function(v)
            addState.texAuraType = (v == "debuff") and "debuff" or nil
            if not Options.AuraUnitAllowed(AuraDriver(), AuraUnit(), v) then
                addState.texUnit = (v == "debuff") and "target" or nil
            end
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        Is("aura"), function() AT.LayoutPage(pg) end)
    AT.RowDropdown(pg, owner, "Aura on whom",
        AuraUnit,
        function(v) addState.texUnit = v end,
        function() return Options.AuraUnitItems(AuraDriver(), addState.texAuraType or "buff", AuraUnit()) end,
        Is("aura"))
    AT.RowDropdown(pg, owner, "Picture shows",
        function() return addState.texCdActive or "ready" end,
        function(v) addState.texCdActive = (v ~= "ready") and v or nil end,
        function() return Items(S.TEXTURE_CD_ACTIVE, S.TEXTURE_CD_ACTIVE_LABELS) end,
        Is("spellCd"))
    AT.RowDropdown(pg, owner, "Power",
        function() return addState.texPowerType or -1 end,
        function(v) addState.texPowerType = (tonumber(v) and tonumber(v) >= 0) and tonumber(v) or nil end,
        function()
            if Options.PowerItems then return Options.PowerItems(addState.texPowerType, true) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        Is("power"))
    AT.RowDropdown(pg, owner, "Health of",
        function() return addState.texHealthUnit or "player" end,
        function(v) addState.texHealthUnit = (v ~= "player") and v or nil end,
        function()
            local TO = Options.TextElement
            return (TO and TO.UnitItems) and TO.UnitItems() or { { value = "player", text = "You" } }
        end,
        Is("health"))
    TPO.ChooserRow(pg, owner, "Picture to show", {
        get = function() return addState.texImage or "" end,
        -- a picked picture brings the blend it is made for
        set = function(v)
            addState.texImage = v
            local b = TPO.BlendFor(v)
            if b then addState.texBlend = (b ~= "BLEND") and b or nil end
        end,
        spellID = function()
            return (Src() == "aura" or Src() == "spellCd") and ParseSpell(addState.texSpell or "") or nil
        end,
        blend = function() return addState.texBlend or "BLEND" end,
        what = function() return "New texture" end,
        visible = vis,
    })
    local look = S.bar and S.bar.texlook and S.bar.texlook.fields or {}
    AT.RowDropdown(pg, owner, "Picture blend",
        function() return addState.texBlend or "BLEND" end,
        function(v) addState.texBlend = (v ~= "BLEND") and v or nil end,
        function() return Items(look.blend.values, look.blend.labels) end,
        vis, function() AT.LayoutPage(pg) end)
    AT.RowDropdown(pg, owner, "Shows as",
        Mode,
        function(v) addState.texMode = (v ~= "show") and v or nil end,
        function() return Items(look.mode.values, look.mode.labels) end,
        vis, function() AT.LayoutPage(pg) end)
    AT.RowDropdown(pg, owner, "Fill follows",
        function() return addState.texFillBy or "time" end,
        function(v) addState.texFillBy = (v ~= "time") and v or nil end,
        function() return Items({ "time", "stacks" }, look.fillBy.labels) end,
        function() return Is("aura")() and Mode() ~= "show" end)
    AT.RowInput(pg, "Texture name",
        function() return addState.texName or "" end,
        function(v) addState.texName = v end,
        vis, "What the sidebar calls it.",
        function() return TPO.DefaultName(Src(), ParseSpell(addState.texSpell or "")) end, true)
end

-- An aura or a cooldown needs its spell; custom triggers, the power and the
-- health are set afterwards.
function Options.TextureCanCreate(addState)
    local s = addState.texSource or "aura"
    if s ~= "aura" and s ~= "spellCd" then return true end
    return ParseSpell(addState.texSpell or "") ~= nil
end

function Options.TextureCreate(addState, layoutId)
    local Store = NS.Store
    local s = addState.texSource or "aura"
    local driver = { source = s }
    local sid
    if s == "rules" then
        driver.rules = {}
    elseif s == "aura" or s == "spellCd" then
        sid = ParseSpell(addState.texSpell or "")
        driver.spellID = sid
    end
    local name = Trim(addState.texName)
    if name == "" then name = TPO.DefaultName(s, sid) end
    if s == "aura" then
        driver.auraType = addState.texAuraType
        driver.unit = addState.texUnit
    elseif s == "spellCd" then
        driver.cdActive = addState.texCdActive
    elseif s == "power" then
        driver.powerType = addState.texPowerType
    elseif s == "health" then
        driver.unit = addState.texHealthUnit
    end
    local rec = Store.NewBar(layoutId, "texture", driver, name)
    if not rec then return rec end
    local img = Trim(addState.texImage)
    if img ~= "" then
        Store.SetOverride(rec, "texlook", "image", img)
        TPO.ApplyPick(rec, img)
    end
    -- a charge count starts at "at least 1" (Tracking, When it shows)
    if driver.cdActive == "charges" then
        Store.SetOverride(rec, "texstate", "stackShow", "from")
        Store.SetOverride(rec, "texstate", "stackLo", 1)
    end
    -- what the page set wins over what the pick brought
    if addState.texBlend then Store.SetOverride(rec, "texlook", "blend", addState.texBlend) end
    local mode = addState.texMode
    if mode and not (Options.TEXTURE_SHEET_OF and Options.TEXTURE_SHEET_OF[img]) then
        Store.SetOverride(rec, "texlook", "mode", mode)
        if s == "aura" and addState.texFillBy then Store.SetOverride(rec, "texlook", "fillBy", addState.texFillBy) end
    end
    return rec
end

-- The Tracking rows. ctx(): the open bar; trackVis: the Tracking tab.
function Options.TextureTrackRows(pg, ctx, trackVis, owner)
    local AT, Store, S = NS.AT, NS.Store, NS.Schema
    local function Rec()
        local r = ctx()
        return (r and r.type == "bar" and r.barKind == "texture" and not r._adMulti) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    local function Source(r)
        local T = TPO.Runtime()
        return (r and T) and T.Source(r) or "aura"
    end
    local function Is(want)
        return function()
            local r = Rec()
            return vis() and r ~= nil and Source(r) == want
        end
    end
    -- a driver edit: the record in place, then the page again at once
    local function Set(field, value)
        local r = Rec()
        if not r then return end
        if r.driver[field] == value then return end
        r.driver[field] = value
        Store.Dirty("style", r.id)
        AT.LayoutPage(pg)
    end

    AT.Section(pg, "What drives it", { visibleFn = vis })
    local srcRow = AT.RowDropdown(pg, owner, "Driven by",
        function() return Source(Rec()) end,
        function(v)
            local r = Rec()
            if not r or Source(r) == v then return end
            r.driver.source = v
            if v == "rules" and type(r.driver.rules) ~= "table" then r.driver.rules = {} end
            Store.Dirty("tree", r.id)
        end,
        TPO.SourceItems, vis, function() AT.LayoutPage(pg) end)
    -- the search finds the row on every texture (its own field name)
    srcRow._adMeta = { family = "bar", section = "texlook", field = "textureSource",
        def = { label = "Driven by" }, baseVis = vis }

    -- an aura on a unit: the aura icons' shape
    local auraVis = Is("aura")
    AT.RowInput(pg, "Aura to watch",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            local ids = (r and DA) and DA.SpellIDList(r.driver) or {}
            return table.concat(ids, ", ")
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local ids = Options.ParseSpellIDs(v)
            local old = NS.DriverAura and table.concat(NS.DriverAura.SpellIDList(r.driver), ",") or ""
            if table.concat(ids, ",") == old then return end
            Options.SetAuraSpellIDs(r.driver, ids)
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        auraVis, "The aura's spell IDs, separated by commas or spaces; any of them shows the picture.", "e.g. 1459, 10157")
    AT.RowDropdown(pg, owner, "Buff or debuff to watch",
        function()
            local r = Rec()
            return (r and r.driver.auraType == "debuff") and "debuff" or "buff"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            local DA = NS.DriverAura
            local unit = DA and DA.ShapeOf(r.driver) or "player"
            r.driver.auraType = v
            if not Options.AuraUnitAllowed(r.driver, unit, v) then unit = "target" end
            r.driver.unit = unit
            Store.Dirty("style", r.id)
            AT.LayoutPage(pg)
        end,
        function() return { { value = "buff", text = "Buff" }, { value = "debuff", text = "Debuff" } } end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura on whom",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            return (r and DA) and (DA.ShapeOf(r.driver)) or "player"
        end,
        function(v) Set("unit", v) end,
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return {} end
            return Options.AuraUnitItems(r.driver, nil, (DA.ShapeOf(r.driver)))
        end,
        auraVis)
    AT.RowDropdown(pg, owner, "Aura put there by",
        function()
            local r = Rec()
            local DA = NS.DriverAura
            if not (r and DA) then return "any" end
            local _, _, caster = DA.ShapeOf(r.driver)
            return caster or "any"
        end,
        function(v) Set("caster", (v ~= "any") and v or nil) end,
        function() return Options.AURA_CASTER_ITEMS end,
        auraVis)
    AT.RowDesc(pg, "The game draws it with the aura, in combat too. Buffs work on you, your pet and friendly units; debuffs on a hostile target or focus.", 20, auraVis)

    -- a spell's cooldown
    local cdVis = Is("spellCd")
    local spellRow = AT.RowInput(pg, "Spell to watch",
        function()
            local r = Rec()
            return (r and r.driver.spellID) and tostring(r.driver.spellID) or ""
        end,
        function(v)
            local id = ParseSpell(v)
            if Trim(v) ~= "" and not id then return end
            Set("spellID", id)
        end,
        cdVis, "A spell ID, a link, or the name of a spell you know. Enter applies it.", "e.g. 17364")
    local nameFS = spellRow:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(NS.AT.FONT, 11, "")
    if spellRow._colCtrl then nameFS:SetPoint("LEFT", spellRow._colCtrl, "RIGHT", 8, 0) end
    nameFS:SetPoint("RIGHT", spellRow, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    local sync = spellRow._sync
    spellRow._sync = function()
        if sync then sync() end
        local r = Rec()
        nameFS:SetText(r and SpellName(r.driver.spellID) or "")
    end
    AT.RowToggle(pg, "Use my current rank",
        function()
            local r = Rec()
            return r ~= nil and NS.Store.AutoRankOn(r.driver)
        end,
        -- on by default: only off is stored
        function(v) if v then Set("autoRank", nil) else Set("autoRank", false) end end,
        function() return cdVis() and NS.IsForever == true end,
        "On ranked realms, follow whichever rank of this spell you know now.")

    -- custom triggers: the rows live on the Triggers tab
    AT.RowDesc(pg, "Its triggers are on the Triggers tab: they decide when the picture shows, and a fill runs with their timer.", 20,
        Is("rules"))

    -- your power, a unit's health: a fill or a ring takes the value; a value
    -- to show at is on Conditions > By Value
    AT.RowDropdown(pg, owner, "Power",
        function()
            local r = Rec()
            local pt = r and r.driver.powerType
            return (pt == nil or pt < 0) and -1 or pt
        end,
        function(v) Set("powerType", (tonumber(v) and tonumber(v) >= 0) and tonumber(v) or nil) end,
        function()
            local r = Rec()
            if Options.PowerItems then return Options.PowerItems(r and r.driver.powerType, true) end
            return { { value = -1, text = "Automatic (current power)" } }
        end,
        Is("power"))
    AT.RowDropdown(pg, owner, "Health of",
        function()
            local r = Rec()
            return (r and r.driver.unit) or "player"
        end,
        function(v) Set("unit", (v ~= "player") and v or nil) end,
        function()
            local TO = Options.TextElement
            return (TO and TO.UnitItems) and TO.UnitItems() or { { value = "player", text = "You" } }
        end,
        Is("health"))

    -- WHEN IT SHOWS, the trigger's gate: an aura while it is up or at a stack
    -- count, a cooldown while ready, on cooldown or at a charge count. The
    -- count is one row: a comparison and typed counts, never a slider.
    local function Gated(r)
        if Source(r) == "aura" then return (Store.Resolve(r, "texstate", "stackShow") or "any") ~= "any" end
        return Source(r) == "spellCd" and r.driver.cdActive == "charges"
    end
    local whenVis = function()
        local r = Rec()
        local s = r and Source(r)
        return vis() and (s == "aura" or s == "spellCd")
    end
    AT.Section(pg, "When it shows", { visibleFn = whenVis })
    local showRow = AT.RowDropdown(pg, owner, "Picture shows",
        function()
            local r = Rec()
            if not r then return "up" end
            if Source(r) == "spellCd" then return r.driver.cdActive or "ready" end
            return Gated(r) and "count" or "up"
        end,
        function(v)
            local r = Rec()
            if not r then return end
            if Source(r) == "spellCd" then
                -- a charge count starts at "at least 1"
                if v == "charges" and (Store.Resolve(r, "texstate", "stackShow") or "any") == "any" then
                    Store.SetOverride(r, "texstate", "stackShow", "from")
                    Store.SetOverride(r, "texstate", "stackLo", 1)
                end
                r.driver.cdActive = (v ~= "ready") and v or nil
                Store.Dirty("style", r.id)
            else
                Store.SetOverride(r, "texstate", "stackShow", (v == "count") and "from" or "any")
            end
        end,
        function()
            local r = Rec()
            local out = {}
            if r and Source(r) == "spellCd" then
                for _, k in ipairs(S.TEXTURE_CD_ACTIVE) do
                    -- a charge count for a spell with charges
                    if k ~= "charges" or S.TexChargeSpell(r) or r.driver.cdActive == "charges" then
                        out[#out + 1] = { value = k, text = S.TEXTURE_CD_ACTIVE_LABELS[k] or k }
                    end
                end
                return out
            end
            out[1] = { value = "up", text = "While the aura is up" }
            if r and (S.TexStackGate(r) or Gated(r)) then out[2] = { value = "count", text = "At a stack count" } end
            return out
        end,
        whenVis, function() AT.LayoutPage(pg) end)
    showRow._adMeta = { family = "bar", section = "texstate", field = "stackShow",
        def = { label = "Picture shows" }, baseVis = whenVis }
    local countVis = function()
        local r = Rec()
        return whenVis() and r ~= nil and Gated(r)
    end
    local count = AT.AddRow(pg, 32, countVis)
    do
        local COL = AT.COL
        local lbl = AT.RowLabel(count, "Stack count")
        local function Op()
            local r = Rec()
            local v = r and Store.Resolve(r, "texstate", "stackShow") or "from"
            return (v == "any") and "from" or v
        end
        local function Put(field, n)
            local r = Rec()
            if r then Store.SetOverride(r, "texstate", field, n) end
            AT.LayoutPage(pg)
        end
        local dd = AT.MakeDropdown(owner, count, 120,
            function()
                local r = Rec()
                -- a stack fill keeps "at least" alone: the engine's own window
                local only = r ~= nil and S.TexByStacks(r)
                local out = {}
                for _, k in ipairs(S.TEXTURE_COUNT_OPS) do
                    if not only or k == "from" then
                        out[#out + 1] = { value = k, text = S.TEXTURE_COUNT_OP_LABELS[k] or k }
                    end
                end
                return out
            end,
            Op,
            function(v) Put("stackShow", v) end)
        dd:SetPoint("LEFT", count._ctrlX, 0)
        local lo = TPO.NumBox(count, function()
            local r = Rec()
            return r and Store.Resolve(r, "texstate", "stackLo")
        end, function(n) Put("stackLo", n) end)
        lo:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        local andFS = count:CreateFontString(nil, "OVERLAY")
        andFS:SetFont(AT.FONT, 12, "")
        andFS:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        andFS:SetText("and")
        andFS:SetPoint("LEFT", lo, "RIGHT", 8, 0)
        local hi = TPO.NumBox(count, function()
            local r = Rec()
            return r and Store.Resolve(r, "texstate", "stackHi")
        end, function(n) Put("stackHi", n) end)
        hi:SetPoint("LEFT", andFS, "RIGHT", 8, 0)
        AT.Tooltip(lo, "Count", "A whole number; Enter applies it.")
        AT.Tooltip(hi, "Count", "A whole number; Enter applies it.")
        count._colLabel, count._colCtrl = lbl, dd
        count._colTrail = 8 + 52 + 8 + 28 + 8 + 52
        count._sync = function()
            local r = Rec()
            lbl:SetText((r and Source(r) == "spellCd") and "Charge count" or "Stack count")
            dd.Refresh()
            lo.Sync()
            hi.Sync()
            local between = Op() == "between"
            andFS:SetShown(between)
            hi:SetShown(between)
        end
        count._adMeta = { family = "bar", section = "texstate", field = "stackLo",
            def = { label = "Stack count" }, baseVis = whenVis }
    end

    -- HOW IT SHOWS: the whole picture (solid while it shows), or a fill or a
    -- ring, and what that follows; its look (direction, ring start) stays on
    -- Appearance
    AT.Section(pg, "How it shows", { visibleFn = vis })
    if Options.SectionRows then
        Options.SectionRows(pg, "bar", "texlook", Rec, vis, { "mode", "fillBy", "fillMax" })
    end
    AT.Section(pg, nil)
end

-- A small typed count box, never a slider: Enter or leaving it stores a whole
-- number from 0 to 99, Escape puts the stored one back.
function TPO.NumBox(parent, get, set)
    local AT, COL = NS.AT, NS.AT.COL
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(52, 18)
    AT.Skin(box, COL.well)
    box:SetFont(AT.FONT, 11, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    local function Show() AT.BoxText(box, tostring(math.floor(tonumber(get()) or 0))) end
    box:SetScript("OnEnterPressed", function() box:ClearFocus() end)
    box:SetScript("OnEscapePressed", function()
        Show()
        box:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(COL.focus[1], COL.focus[2], COL.focus[3], 1) end)
    box:SetScript("OnEditFocusLost", function()
        local n = tonumber(box:GetText() or "")
        box:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        if n then
            n = math.max(0, math.min(99, math.floor(n)))
            if n ~= math.floor(tonumber(get()) or -1) then set(n) end
        end
        Show()
    end)
    box.Sync = function() if not box:HasFocus() then Show() end end
    Show()
    return box
end
