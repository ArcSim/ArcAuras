-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- Totem out of range: a totem icon set to one totem wears its Out of range
-- look (grey, tint, a glow, custom texts) while the totem is out and its buff
-- is not on you. Buffs read secret in combat, so nothing is read: the look
-- sits in layers over the holder. Whether the totem is out is plain (the
-- totem feed).
-- Called from AD_DriverCooldown's totem feed, Driver.Attach and Driver.Detach.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local TR = {}
NS.TotemRange = TR

-- Rungs over a layer's own level: the glow's frames, the texts, then the
-- slot's button, which must sit over every piece it clears.
TR.GLOW, TR.TEXT, TR.BUTTON = 1, 3, 5
-- The layers over the holder: the art between the holder's art and its swipe
-- (+2), so the countdown stays on top; the glow and texts over the swipe and
-- under the holder's own texts (+7).
TR.ART_AT, TR.TOP_AT = 1, 6
-- A search that never answered (another search replaced it) frees the queue
-- after this many seconds.
TR.STALE = 30
TR.attached = {}   -- [iconId] = { rec, frame, active, painted }
TR.layers = {}     -- [iconId] = { art = layer, top = layer }, kept: engine frames cannot go
TR.queue = {}      -- icon ids waiting for their buff's IDs, one search at a time
TR.inCombat = InCombatLockdown() and true or false

local PARTS = { "art", "top" }
local SUFFIXES = { "", "2", "3" }
local WHITE = { 1, 1, 1, 1 }
local GLOW_KEY = "adtrg"

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function AurasSecret()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    if not Plain(v) then return true end
    return v == true
end

-- The buff

-- The buff is named after its totem ("Stoneskin Totem" gives "Stoneskin").
function TR.AutoName(rec)
    local DT = NS.DriverTotem
    local nm = DT and rec and type(rec.driver) == "table" and DT.SpellName(Store.RecordSpellID(rec.driver))
    if type(nm) ~= "string" or not Plain(nm) then return nil end
    nm = nm:gsub("%s+[Tt]otem$", "")
    return nm ~= "" and nm or nil
end

-- A typed name wins.
function TR.BuffName(rec)
    local typed = rec and type(rec.driver) == "table" and rec.driver.rangeBuff
    if type(typed) == "string" and typed ~= "" then return typed end
    return TR.AutoName(rec)
end

-- The buff's IDs when they were found for its current name, else nil.
function TR.IDs(rec)
    local name = TR.BuffName(rec)
    local d = rec and rec.driver
    if not name or d.rangeBuffFor ~= name or type(d.rangeBuffIDs) ~= "table" then return nil end
    if #d.rangeBuffIDs == 0 then return nil end
    return d.rangeBuffIDs
end

-- Every ID a slot shows, as the engine's filter map; none gets the
-- never-matching id 0 (an empty set shows any buff).
local function IDMap(ids)
    return Store.AuraIncludeMap({ spellIDs = ids })
end

-- Every ID named exactly the buff, any rank, kept on the icon.
function TR.Keep(rec, name, results)
    local ids, low = {}, name:lower()
    for _, g in ipairs(results or {}) do
        if type(g.name) == "string" and g.name:lower() == low then
            for _, v in ipairs(g.ids or {}) do ids[#ids + 1] = v end
        end
    end
    table.sort(ids)
    rec.driver.rangeBuffFor = name
    rec.driver.rangeBuffIDs = ids
    Store.Dirty("style", rec.id)
    -- the Tracking tab's line follows the answer
    if NS.Options and NS.Options.RefreshAll then NS.Options.RefreshAll() end
end

function TR.Searching(rec)
    if not rec then return false end
    if TR.searching == rec.id then return true end
    for _, id in ipairs(TR.queue) do
        if id == rec.id then return true end
    end
    return false
end

-- One search at a time: NS.SpellNames runs one query, and a newer one
-- replaces it without a word.
function TR.NextSearch()
    local id = table.remove(TR.queue, 1)
    TR.searching, TR.searchAt = id, id and GetTime() or nil
    if not id then return end
    local rec = Store.Get(id)
    local name = rec and TR.BuffName(rec)
    if not name then return TR.NextSearch() end
    NS.SpellNames.Search(name, function(state, results)
        if state == "loading" or TR.searching ~= id then return end
        local live = Store.Get(id)
        if live and TR.BuffName(live) == name then TR.Keep(live, name, results) end
        TR.searching = nil
        TR.NextSearch()
    end)
end

-- Looks the buff up by name. The spell list's first search probes the whole
-- spell range, so it runs from the options only.
function TR.Find(rec)
    if not (rec and NS.SpellNames and TR.BuffName(rec)) then return end
    if TR.searching and GetTime() - (TR.searchAt or 0) > TR.STALE then TR.searching = nil end
    if not TR.Searching(rec) then TR.queue[#TR.queue + 1] = rec.id end
    if not TR.searching then TR.NextSearch() end
end

-- An icon whose look is on and whose buff was never looked up, while the
-- options are open.
local function MaybeFind(rec)
    local LE = NS.LayoutEngine
    if not (LE and LE.IsEditMode and LE.IsEditMode()) then return end
    local name = TR.BuffName(rec)
    if name and rec.driver.rangeBuffFor ~= name then TR.Find(rec) end
end

-- The Tracking tab's line under the buff's name.
function TR.StatusText(rec)
    local name = TR.BuffName(rec)
    if not name then return "Set the totem's spell ID first." end
    local ids = TR.IDs(rec)
    if ids then
        return ("Out of range shows while the totem is out and %s is not on you (%d spell IDs)."):format(name, #ids)
    end
    if TR.Searching(rec) then return ("Looking up %s in the spell list..."):format(name) end
    if rec.driver.rangeBuffFor == name then
        return ("No buff named %s was found. Type the buff's name as its tooltip shows it."):format(name)
    end
    return ("%s is looked up when you turn an Out of range look on."):format(name)
end

-- What the look holds

-- The custom texts shown while out of range.
function TR.RangeTexts(rec)
    local out = {}
    for _, suf in ipairs(SUFFIXES) do
        local t = Store.Resolve(rec, "label", "labelText" .. suf)
        if t ~= nil and t ~= "" and Store.Resolve(rec, "label", "labelShowRange" .. suf) == true then
            out[#out + 1] = suf
        end
    end
    return out
end

-- The art layer (grey or tint) and the top layer (a glow or texts).
function TR.Wants(rec)
    if not (NS.Schema.TotemBySpell and NS.Schema.TotemBySpell(rec)) then return false, false end
    local R = function(k) return Store.Resolve(rec, "states", k) == true end
    local art = R("totemRangeDesaturate") or R("totemRangeTint")
    local top = R("totemRangeGlow") or #TR.RangeTexts(rec) > 0
    return art, top
end

-- The layers

local function Eraser(b)
    local t = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetColorTexture(0, 0, 0, 0)
    t:SetBlendMode("DISABLE")
    return t
end

-- Its button covers the layer and as far as the layer's look reaches, over
-- every piece of it; written only while it can be (its birth, out of combat).
local function StyleButton(layer)
    local b = layer.button
    local DA = NS.DriverAura
    if not (b and DA and DA.IsAccessible and DA.IsAccessible(b)) then return false end
    local st = layer.stage
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", 0, 0)
    b:SetFrameStrata(st:GetFrameStrata())
    b:SetFrameLevel(st:GetFrameLevel() + TR.BUTTON)
    local e = layer.eraser or Eraser(b)
    layer.eraser = e
    local mx, my = layer.mx or 1, layer.my or 1
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", b, "TOPLEFT", -mx, my)
    e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", mx, -my)
    e:Show()
    return true
end

-- A layer: our frame over the holder, drawn as one picture, and a player aura
-- slot on the buff's IDs. Built out of combat, kept for the icon's life.
local function BuildLayer(rec, part, ids)
    local DA = NS.DriverAura
    if not (DA and DA.CreateIconContainer and DA.FilterSig and DA.EraserAvailable
        and DA.EraserAvailable()) then return nil end
    if TR.inCombat or InCombatLockdown() or AurasSecret() then return nil end
    local st = CreateFrame("Frame", nil, UIParent)
    st:SetSize(1, 1)
    st:SetPoint("TOP", UIParent, "TOP", 0, -80)
    st:SetFlattensRenderLayers(true)
    -- set before any button exists
    st:SetIsFrameBuffer(true)
    st:SetAlpha(0)
    local c = DA.CreateIconContainer("player", st)
    if not c then
        st:Hide()
        return nil
    end
    local layer = { stage = st, part = part, container = c,
        key = "adtr" .. tostring(rec.id) .. "_" .. part }
    local map = IDMap(ids)
    layer.sig = DA.FilterSig(map)
    c:AddAuraSlot(layer.key, "HELPFUL", {
        maxFrameCount = 1,
        initializeFrame = function(b)
            b:EnableMouse(false)
            layer.button = b
            StyleButton(layer)
        end,
        candidateFilters = { includeSpellIDs = map },
    })
    return layer
end

-- The slot on the buff's IDs, or on the never-matching id while parked. A
-- filter equal to the last one sent is never sent again: each send restarts
-- the slot.
local function AimLayer(layer, ids)
    local map = ids and IDMap(ids) or { [0] = true }
    local sig = NS.DriverAura.FilterSig(map)
    if layer.sig == sig then
        layer.aimPending = nil
        return
    end
    if TR.inCombat or InCombatLockdown() then
        layer.aimPending = true
        return
    end
    layer.sig, layer.aimPending = sig, nil
    layer.container:SetAuraSlotCandidateFilters(layer.key, { includeSpellIDs = map })
end

-- Stands a layer on the holder, at its strata, `at` rungs over it.
local function Stand(layer, f, at)
    local st = layer.stage
    st:ClearAllPoints()
    st:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    st:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    st:SetFrameStrata(f:GetFrameStrata())
    local lvl = f:GetFrameLevel()
    if type(lvl) ~= "number" or not Plain(lvl) then lvl = 1 end
    st:SetFrameLevel(lvl + at)
end

-- The holder's Active dim, which the layers wear as the holder's art does.
local function ShownAlpha(f)
    local a = f._adShownAlpha or f._adStateAlpha or 1
    if type(a) ~= "number" or not Plain(a) then a = 1 end
    return a
end

-- The art in its Out of range look, and the border over it (the holder's
-- border shares the layer's level, so either may draw last).
local function PaintArt(layer, rec, f, kS, a)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local st = layer.stage
    local art = layer.art
    if not art then
        art = st:CreateTexture(nil, "ARTWORK")
        layer.art = art
    end
    local hide = R("appearance", "forceHideIcon") == true
    art:SetTexture(Factory.GetTexture(rec))
    if Factory.BoxTexCoords then art:SetTexCoord(Factory.BoxTexCoords(rec, f, (R("appearance", "padding") or 0) * kS)) end
    local pad = (R("appearance", "padding") or 0) * kS
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", st, "TOPLEFT", pad, -pad)
    art:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", -pad, pad)
    if Factory.ShapeTex then Factory.ShapeTex(art, Factory.MaskOf(rec)) end
    -- a Masque skin's picture and layers on the icon's size (the border below stands aside)
    if Factory.SkinArt then
        local fw, fh = f:GetSize()
        if issecretvalue and (issecretvalue(fw) or issecretvalue(fh)) then fw, fh = nil, nil end
        local plan = Factory.SkinPlan(rec)
        Factory.SkinArt(art, rec, plan, st, fw or 36, fh or 36)
        Factory.SkinLayers(plan, st, st, st, art, fw or 36, fh or 36, a, hide)
    end
    -- the totem is out: Active's grey out and tint carry under this look
    art:SetDesaturated(R("states", "totemRangeDesaturate") == true or R("states", "readyDesaturate") == true)
    local tc
    if R("states", "totemRangeTint") == true then
        tc = R("states", "totemRangeTintColor")
    elseif R("states", "readyTintEnabled") == true then
        tc = R("states", "readyTintColor")
    end
    tc = tc or WHITE
    -- vertex alpha is the art's alpha, as on the holder
    art:SetVertexColor(tc[1], tc[2], tc[3], a)
    art:SetShown(not hide)
    local border = R("appearance", "borderEnabled") and not hide
    local edges = layer.edges
    if border and Factory.PaintBorderEdges then
        if not edges then
            edges = {}
            local bias = art.GetTexelSnappingBias and art:GetTexelSnappingBias()
            for _, k in ipairs({ "top", "bottom", "left", "right" }) do
                local t = st:CreateTexture(nil, "OVERLAY", nil, 5)
                t:SetColorTexture(1, 1, 1, 1)
                if type(bias) == "number" and Plain(bias) and t.SetTexelSnappingBias then
                    t:SetTexelSnappingBias(bias)
                end
                edges[k] = t
            end
            layer.edges = edges
        end
        Factory.PaintBorderEdges(edges, st, rec, a)
    elseif edges then
        for _, t in pairs(edges) do t:Hide() end
    end
    -- an outside border reaches past the icon; a unit to spare
    local out = 1
    if border then out = math.max(0, -(R("appearance", "borderInset") or 0)) + 1 end
    layer.mx, layer.my = out, out
end

-- The glow's recipe from the Out of range glow fields.
local function GlowRecipe(rec)
    local R = function(k) return Store.Resolve(rec, "states", "totemRangeGlow" .. k) end
    local c = R("Color") or { 1, 0.3, 0.3, 1 }
    local gtype = R("Type") or "pixel"
    if Factory.DrawnGlowStyle then gtype = Factory.DrawnGlowStyle(gtype, rec) end
    local inten = R("Intensity") or 1
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * inten },
        speed = R("Speed") or 0.25, lines = R("Lines") or 8, thickness = R("Thickness") or 2,
        particles = R("Particles") or 4, scale = R("Scale") or 1,
        xo = R("XOffset") or 0, yo = R("YOffset") or 0, length = R("Length") or 0,
        mx = R("MoveX") or 0, my = R("MoveY") or 0, level = TR.GLOW, strata = "inherit",
    }
    local look = Factory.LaneLook and Factory.LaneLook(rec, "states", "totemRangeGlow", gtype, p, inten) or ""
    local sig = table.concat({ gtype, p.color[1], p.color[2], p.color[3], p.color[4], p.speed,
        p.lines, p.thickness, p.particles, p.scale, p.xo, p.yo, p.length, p.mx, p.my }, ":") .. look
    return gtype, p, sig
end

-- The glow runs only while its layer shows: the library animates every frame.
local function SetGlow(layer, on)
    local g = layer.glow
    on = on and g ~= nil
    if on and layer.glowSig == g.sig .. ":" .. layer.size then return end
    if layer.glowSig then
        Factory.StopGlowLane(layer.stage, GLOW_KEY)
        layer.glowSig = nil
    end
    if on and Factory.StartGlowLane then
        Factory.StartGlowLane(layer.stage, GLOW_KEY, g.gtype, g.p)
        layer.glowSig = g.sig .. ":" .. layer.size
    end
end

-- The glow's recipe and the texts shown while out of range, on a host over
-- the glow.
local function PaintTop(layer, rec, f, w, h, kS, a)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local st = layer.stage
    local mx, my = 1, 1
    layer.glow = nil
    -- a moved layer restarts its glow: children keep their old level
    layer.size = w .. "x" .. h .. "@" .. tostring(st:GetFrameLevel())
    if R("states", "totemRangeGlow") == true and R("appearance", "forceHideIcon") ~= true then
        local gtype, p, sig = GlowRecipe(rec)
        layer.glow = { gtype = gtype, p = p, sig = sig }
        -- the proc glow's burst runs about 2.5x the icon
        local E = math.max(w, h) * 0.8
        mx = math.ceil(E + math.abs(p.xo) + math.abs(p.mx)) + 1
        my = math.ceil(E + math.abs(p.yo) + math.abs(p.my)) + 1
    end
    local texts = TR.RangeTexts(rec)
    local host = layer.textHost
    if #texts > 0 and not host then
        host = CreateFrame("Frame", nil, st)
        host:SetAllPoints(st)
        host:EnableMouse(false)
        layer.textHost = host
        layer.texts = {}
    end
    if host then
        host:SetFrameLevel(st:GetFrameLevel() + TR.TEXT)
        local textA = (a > 0 and R("states", "preserveDurationText") ~= false) and 1 or a
        local want = {}
        for _, suf in ipairs(texts) do want[suf] = true end
        for i, suf in ipairs(SUFFIXES) do
            local fs = layer.texts[i]
            if want[suf] and Factory.StyleLabel then
                if not fs then
                    fs = host:CreateFontString(nil, "OVERLAY")
                    fs:SetDrawLayer("OVERLAY", 6)
                    layer.texts[i] = fs
                end
                Factory.StyleLabel(fs, rec, suf, kS, st)
                fs:SetAlpha(textA)
                fs:Show()
                -- how far the words reach: offset plus a generous width
                local t = R("label", "labelText" .. suf) or ""
                local size = (R("label", "labelSize" .. suf) or 12) * kS
                mx = math.max(mx, math.ceil(math.abs(R("label", "labelX" .. suf) or 0) * kS
                    + math.max(#t * size * 0.7, size)))
                my = math.max(my, math.ceil(math.abs(R("label", "labelY" .. suf) or 0) * kS + size * 1.5))
            elseif fs then
                fs:SetText("")
                fs:Hide()
            end
        end
    end
    layer.mx, layer.my = mx, my
end

local function HolderSize(f)
    local h = f:GetHeight()
    if type(h) ~= "number" or not Plain(h) or h <= 0 then h = 36 end
    local w = f:GetWidth()
    if type(w) ~= "number" or not Plain(w) or w <= 0 then w = h end
    return w, h
end

-- Stands and dresses the live layers; their buttons follow when writable.
function TR.Paint(a)
    local L = TR.layers[a.rec.id]
    if not L then return end
    local rec, f = a.rec, a.frame
    local wantArt, wantTop = TR.Wants(rec)
    local w, h = HolderSize(f)
    local kS = h / 36
    local alpha = ShownAlpha(f)
    a.painted = alpha
    if L.art and wantArt then
        Stand(L.art, f, TR.ART_AT)
        PaintArt(L.art, rec, f, kS, alpha)
        StyleButton(L.art)
    end
    if L.top and wantTop then
        Stand(L.top, f, TR.TOP_AT + Factory.Rise(rec))
        PaintTop(L.top, rec, f, w, h, kS, alpha)
        StyleButton(L.top)
    end
end

-- The layers' alpha: the holder's while the totem is out, else none.
function TR.Sync(a)
    local L = TR.layers[a.rec.id]
    if not L then return end
    local f = a.frame
    local wantArt, wantTop = TR.Wants(a.rec)
    local ea = f:GetEffectiveAlpha()
    if type(ea) ~= "number" or not Plain(ea) then ea = 1 end
    local shown = a.active == true and TR.IDs(a.rec) ~= nil and f:IsVisible() == true
    if L.art then L.art.stage:SetAlpha((shown and wantArt) and ea or 0) end
    if L.top then
        local on = shown and wantTop
        L.top.stage:SetAlpha(on and ea or 0)
        SetGlow(L.top, on)
    end
end

-- The layers this icon needs, built and aimed out of combat.
function TR.Ensure(a)
    local rec = a.rec
    local wantArt, wantTop = TR.Wants(rec)
    local ids = TR.IDs(rec)
    local L = TR.layers[rec.id]
    if not L and ids and (wantArt or wantTop) then
        L = {}
        TR.layers[rec.id] = L
    end
    if not L then return end
    local want = { art = wantArt, top = wantTop }
    for _, part in ipairs(PARTS) do
        local layer = L[part]
        if want[part] and ids and not layer then
            layer = BuildLayer(rec, part, ids)
            L[part] = layer
        end
        if layer then AimLayer(layer, (want[part] and ids) or nil) end
    end
    TR.Paint(a)
    TR.Sync(a)
end

-- Every layer of an icon off: no alpha, no glow, the slot parked.
local function Park(id)
    local L = TR.layers[id]
    if not L then return end
    for _, part in ipairs(PARTS) do
        local layer = L[part]
        if layer then
            layer.stage:SetAlpha(0)
            SetGlow(layer, false)
            AimLayer(layer, nil)
        end
    end
end

-- Events

function TR.OnEvent(ev)
    if ev == "PLAYER_REGEN_DISABLED" then
        TR.inCombat = true
        return
    end
    TR.inCombat = false
    -- what waited on combat: builds, buttons, filters
    for id, L in pairs(TR.layers) do
        if not TR.attached[id] then
            for _, part in ipairs(PARTS) do
                if L[part] and L[part].aimPending then AimLayer(L[part], nil) end
            end
        end
    end
    for _, a in pairs(TR.attached) do TR.Ensure(a) end
end

function TR.EnsureEvents()
    if TR.live then return end
    TR.live = true
    Events.On("PLAYER_REGEN_DISABLED", "adtotemrange", TR.OnEvent)
    Events.On("PLAYER_REGEN_ENABLED", "adtotemrange", TR.OnEvent)
    if not TR.heard then
        TR.heard = true
        -- a group, layout or condition fade reaches the layers
        Events.OnMessage("AD_VISIBILITY", "adtotemrange", function()
            for _, a in pairs(TR.attached) do TR.Sync(a) end
        end)
    end
end

-- A hidden holder hides its layers; shown again, they take its fade back.
local function HookHolder(f)
    if f._adTRHooked then return end
    f._adTRHooked = true
    local function sync(self)
        local a = TR.attached[self._adRecId]
        if a and a.frame == self then TR.Sync(a) end
    end
    f:HookScript("OnHide", sync)
    f:HookScript("OnShow", sync)
end

-- Every (re)style of a totem icon lands here.
function TR.Attach(rec, f)
    local wantArt, wantTop = TR.Wants(rec)
    if not (wantArt or wantTop) then
        TR.attached[rec.id] = nil
        Park(rec.id)
        return
    end
    local a = TR.attached[rec.id] or {}
    TR.attached[rec.id] = a
    a.rec, a.frame = rec, f
    TR.EnsureEvents()
    HookHolder(f)
    if not TR.IDs(rec) then MaybeFind(rec) end
    TR.Ensure(a)
end

-- The totem feed: out or not, after the holder took its state.
function TR.Feed(rec, f, active)
    local a = TR.attached[rec.id]
    if not a then return end
    a.frame = f
    a.active = active == true
    local L = TR.layers[rec.id]
    if not L then return end
    if a.active and a.painted ~= ShownAlpha(f) then
        TR.Paint(a)
    elseif L.art and L.art.art then
        -- the art follows the live totem, as the holder's does
        L.art.art:SetTexture(Factory.GetTexture(rec))
    end
    TR.Sync(a)
end

function TR.Detach(id)
    TR.attached[id] = nil
    Park(id)
    if next(TR.attached) or not TR.live then return end
    TR.live = false
    Events.Off("PLAYER_REGEN_DISABLED", "adtotemrange")
    Events.Off("PLAYER_REGEN_ENABLED", "adtotemrange")
end
