-- AD_TypeLooks: a show-all aura group's debuff type looks, parts on each game button shown only for the dispel types given them.
-- The show-all runtime (Drivers\AD_DriverUnitAuras.lua) calls TL.Apply from its buttons' style pass; the settings are the group's typeLook section.
-- The game reads each aura's type and picks the art and colour itself, so it works in combat: nothing here reads an aura.
local ADDON, NS = ...
local Store = NS.Store

local TL = {}
NS.TypeLooks = TL

TL.WHITE = "Interface\\Buttons\\WHITE8X8"
-- the IconAlert sheet's outer ring, the soft glow the action bars use
TL.GLOW = "Interface\\SpellActivationOverlay\\IconAlert"
TL.GLOW_TC = { left = 0.00781250, right = 0.50781250, top = 0.27734375, bottom = 0.52734375 }
-- Blizzard's own type art, for a client whose AuraUtil lacks its display table
TL.ART = {
    Magic = { basicAtlas = "ui-debuff-border-magic-noicon", dispelAtlas = "ui-debuff-border-magic-icon",
        dispelIconAtlas = "RaidFrame-Icon-DebuffMagic" },
    Curse = { basicAtlas = "ui-debuff-border-curse-noicon", dispelAtlas = "ui-debuff-border-curse-icon",
        dispelIconAtlas = "RaidFrame-Icon-DebuffCurse" },
    Disease = { basicAtlas = "ui-debuff-border-disease-noicon", dispelAtlas = "ui-debuff-border-disease-icon",
        dispelIconAtlas = "RaidFrame-Icon-DebuffDisease" },
    Poison = { basicAtlas = "ui-debuff-border-poison-noicon", dispelAtlas = "ui-debuff-border-poison-icon",
        dispelIconAtlas = "RaidFrame-Icon-DebuffPoison" },
    None = { basicAtlas = "ui-debuff-border-default-noicon" },
}
-- Blizzard draws its debuff border 40 wide round a 30 icon (BuffFrameTemplates)
TL.BORDER_SCALE = 40 / 30
TL.BADGE_SCALE = 0.45
TL.LABEL_INSET = 2
TL.EDGES = { "top", "bottom", "left", "right" }

-- The button takes per-type art from the game (CustomAsset style).
function TL.Available(b)
    local S = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    return b ~= nil and b.AddDispelTypeTexture ~= nil and b.RemoveDispelTypeTexture ~= nil
        and S ~= nil and S.CustomAsset ~= nil and CreateColor ~= nil
end

function TL.On(g)
    return g ~= nil and Store.ShowsAll(g) == true and Store.Resolve(g, "typeLook", "looks") == "parts"
end

-- Blizzard's art for one type: the game's live table first.
function TL.Art(key)
    local info = AuraUtil and AuraUtil.GetDebuffDisplayInfoTable and AuraUtil.GetDebuffDisplayInfoTable()
    local i = type(info) == "table" and info[key]
    if type(i) == "table" and i.basicAtlas then return i end
    return TL.ART[key]
end

-- What the group asks for: per part, the types using it ({ [key] = true }),
-- each type's colour and label, the shared sizes, and a signature of all of it.
function TL.Plan(g)
    local R = function(f) return Store.Resolve(g, "typeLook", f) end
    local p = { color = {}, blizzard = {}, blizzardBadge = {}, badge = {}, wash = {}, glow = {},
        labels = {}, colors = {} }
    local sig = {}
    for _, t in ipairs(NS.Schema.TYPE_LOOKS) do
        local k = t.key
        local c = R("color" .. k) or t.color
        p.colors[k] = c
        local border = R("border" .. k) or "normal"
        if border ~= "normal" and p[border] then p[border][k] = true end
        if R("wash" .. k) == true then p.wash[k] = true end
        if R("glow" .. k) == true then p.glow[k] = true end
        local lb = R("label" .. k)
        if type(lb) == "string" and lb ~= "" then p.labels[k] = lb end
        sig[#sig + 1] = table.concat({ k, border, tostring(p.wash[k] or false), tostring(p.glow[k] or false),
            p.labels[k] or "", c[1], c[2], c[3] }, ",")
    end
    p.washAlpha = R("washAlpha") or 0.3
    p.labelSize = R("labelSize") or 12
    p.labelAnchor = R("labelAnchor") or "BOTTOMRIGHT"
    p.glowSize = R("glowSize") or 1.4
    p.sig = table.concat(sig, "|")
    return p
end

-- A type's label in its own colour, a | doubled so it prints as typed.
function TL.LabelText(text, c)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5), (text:gsub("|", "||")))
end

-- The textures and frames a button wears for its type looks, made once.
function TL.Parts(b)
    local st = b._adTL
    if st then return st end
    local host = b.TextOverlay or b
    st = { reg = {}, edges = {} }
    for _, e in ipairs(TL.EDGES) do st.edges[e] = host:CreateTexture(nil, "OVERLAY", nil, 7) end
    st.blz = host:CreateTexture(nil, "OVERLAY", nil, 7)
    st.blzBadge = host:CreateTexture(nil, "OVERLAY", nil, 7)
    st.badge = host:CreateTexture(nil, "OVERLAY", nil, 7)
    -- the wash and the glow sit in frames of their own: the game sets their
    -- textures' colour (and so their alpha), the frames carry the strength
    st.washF = CreateFrame("Frame", nil, b)
    st.washF:SetAllPoints(b)
    st.wash = st.washF:CreateTexture(nil, "ARTWORK")
    st.wash:SetAllPoints(st.washF)
    st.glowF = CreateFrame("Frame", nil, b)
    st.glowF:SetAllPoints(b)
    st.glow = st.glowF:CreateTexture(nil, "OVERLAY")
    st.glow:SetBlendMode("ADD")
    st.glow:SetDesaturated(true)
    st.label = host:CreateFontString(nil, "OVERLAY")
    st.label:SetDrawLayer("OVERLAY", 7)
    b._adTL = st
    return st
end

-- Sizes and spots, every style pass: the button's size and the group's
-- border can change without the type looks changing.
function TL.Place(b, st, p, look, w, h)
    if NS.Factory and NS.Factory.PaintBorderEdges and look then
        NS.Factory.PaintBorderEdges(st.edges, b, look, 1, true)
    end
    for _, t in ipairs({ st.blz, st.blzBadge }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        t:SetSize(w * TL.BORDER_SCALE, h * TL.BORDER_SCALE)
    end
    local s = math.min(w, h) * TL.BADGE_SCALE
    st.badge:ClearAllPoints()
    st.badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    st.badge:SetSize(s, s)
    st.washF:SetAlpha(p.washAlpha)
    st.glow:ClearAllPoints()
    st.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    st.glow:SetSize(w * p.glowSize, h * p.glowSize)
    local fs = st.label
    fs:SetFont(STANDARD_TEXT_FONT, math.max(6, math.floor(p.labelSize * h / 36 + 0.5)), "OUTLINE")
    fs:ClearAllPoints()
    local an = p.labelAnchor
    local x = an:find("LEFT") and TL.LABEL_INSET or (an:find("RIGHT") and -TL.LABEL_INSET or 0)
    local y = an:find("TOP") and -TL.LABEL_INSET or (an:find("BOTTOM") and TL.LABEL_INSET or 0)
    fs:SetPoint(an, b, an, x, y)
end

-- Hands one texture to the game for the types in `types`: each gets its art
-- from asset(key) and, with colours, its colour. A type left out gets no art,
-- so the texture draws nothing for it. False when no type uses it.
function TL.Register(b, st, tex, types, asset, colors)
    local amap, cmap, any = {}, nil, false
    for k in pairs(types) do
        local a = asset(k)
        if a then
            amap[k] = a
            any = true
        end
    end
    if not any then
        tex:Hide()
        return false
    end
    if colors then
        cmap = {}
        for k in pairs(amap) do
            local c = colors[k]
            cmap[k] = CreateColor(c[1], c[2], c[3], 1)
        end
    end
    b:AddDispelTypeTexture(tex, { showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = true,
        style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset,
        customDispelAssetMap = amap, customDispelColorMap = cmap })
    st.reg[#st.reg + 1] = tex
    return true
end

function TL.Unregister(b, st)
    for i = #st.reg, 1, -1 do
        local t = st.reg[i]
        b:RemoveDispelTypeTexture(t)
        t:Hide()
        st.reg[i] = nil
    end
    if st.labelOn then
        if b.ClearDispelTypeText then b:ClearDispelTypeText() end
        st.label:SetText("")
        st.label:Hide()
        st.labelOn = nil
    end
    st.sig = nil
end

-- The button's type looks off (the group switched them off, or this client
-- has no per-type art).
function TL.Clear(b)
    local st = b and b._adTL
    if st and st.sig then TL.Unregister(b, st) end
end

-- One button's type looks for group g. look: the record its plain look comes
-- from (the border's thickness and offset); w, h: its size. Accessible
-- passes only (the caller's style pass checks).
function TL.Apply(b, g, look, w, h)
    if not (TL.On(g) and TL.Available(b)) then return TL.Clear(b) end
    local p = TL.Plan(g)
    local st = TL.Parts(b)
    TL.Place(b, st, p, look, w or 36, h or 36)
    if st.sig == p.sig then return end
    TL.Unregister(b, st)
    local white = function() return { asset = TL.WHITE } end
    for _, e in ipairs(TL.EDGES) do TL.Register(b, st, st.edges[e], p.color, white, p.colors) end
    TL.Register(b, st, st.blz, p.blizzard, function(k)
        local a = TL.Art(k)
        return a and a.basicAtlas and { asset = a.basicAtlas } or nil
    end)
    TL.Register(b, st, st.blzBadge, p.blizzardBadge, function(k)
        local a = TL.Art(k)
        local atlas = a and (a.dispelAtlas or a.basicAtlas)
        return atlas and { asset = atlas } or nil
    end)
    TL.Register(b, st, st.badge, p.badge, function(k)
        local a = TL.Art(k)
        return a and a.dispelIconAtlas and { asset = a.dispelIconAtlas } or nil
    end)
    TL.Register(b, st, st.wash, p.wash, white, p.colors)
    TL.Register(b, st, st.glow, p.glow, function() return { asset = TL.GLOW, texCoords = TL.GLOW_TC } end, p.colors)
    if next(p.labels) and b.SetDispelTypeText then
        local map = {}
        for _, t in ipairs(NS.Schema.TYPE_LOOKS) do
            local text = p.labels[t.key]
            map[t.key] = text and TL.LabelText(text, p.colors[t.key]) or ""
        end
        -- the docs name "" for an aura with no type; the button reads "None"
        map[""] = map.None
        b:SetDispelTypeText(st.label, { showWhenHarmful = true, showWhenHelpful = true,
            showWithoutDispelType = true, customDispelTextMap = map })
        st.labelOn = true
    end
    st.sig = p.sig
end
