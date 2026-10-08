-- AD_Wheel: the Wheel item, a ring of spells and items that opens at the cursor on its key.
-- Owns the dial drawing (the options editor draws with it too), the secure frames behind each
-- wheel and the "wheel" bar kind on the bars registry; the layout engine keeps its holder hidden.
-- Casting is protected: contents, spots and the key change out of combat only, while the press,
-- the point and the release run in the game's secure snippets and work in combat.
local ADDON, NS = ...

local WH = {}
NS.Wheels = WH

WH.MIN, WH.MAX, WH.COUNT = 3, 10, 6
WH.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- |cos| past this puts a name beside its icon, not above or below it (sin 22.5)
WH.SIDE = 0.38
WH.KEY = "adwheel"
WH.units = {}       -- [record id] = the wheel's frames, kept: a frame cannot be destroyed
WH.live = {}        -- [record id] = the record while it loads
WH.pending = false  -- a change waiting for combat to end
-- a key on a mouse button, as the click that reaches the screen catcher names it
WH.MOUSE = { BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }

local function InCombat() return InCombatLockdown ~= nil and InCombatLockdown() == true end
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Geometry

-- a spot's angle (radians) on a wheel of n spots: 1 at the top, then clockwise
function WH.Angle(spot, n) return math.rad(90 - (spot - 1) * 360 / n) end

-- the slice (1..n) a direction falls in, measured from the wheel's centre; the
-- secure snippets below do the same sum
function WH.Slice(dx, dy, n)
    local fromTop = (90 - math.deg(math.atan2(dy, dx))) % 360
    return math.floor(fromTop / (360 / n) + 0.5) % n + 1
end

-- a dial's sizes at size k, in whole physical pixels
function WH.Geo(k)
    local g = { px = NS.AT.Px(UIParent) }
    local function S(v) return math.floor(v / g.px + 0.5) * g.px end
    g.S = S
    g.r = S(96 * k)                       -- the icons' circle
    g.icon, g.iconRest = S(42 * k), S(38 * k)
    g.sel = S(62 * k)
    g.gap = S(6 * k)
    g.half = S(g.r + 52 * k)              -- the dark disc reaches past the icons
    g.dead = 22 * k
    g.inner, g.outer = 30 * k, g.half - 10 * k
    g.font = math.floor(14 * k + 0.5)
    g.k = k
    return g
end

-- The record

function WH.IsWheel(rec)
    return type(rec) == "table" and rec.type == "bar" and rec.barKind == "wheel"
end

-- spots on the wheel, 3 to 10
function WH.Count(rec)
    local d = rec and rec.driver
    local n = tonumber(d and d.count)
    n = n and math.floor(n) or WH.COUNT
    if n < WH.MIN then n = WH.MIN elseif n > WH.MAX then n = WH.MAX end
    return n
end

-- [spot] = { t = "spell" | "item", id }; spots past the count stay saved
function WH.Spots(rec)
    local d = rec and rec.driver
    return (d and type(d.spots) == "table") and d.spots or {}
end

function WH.KeyOf(rec)
    local k = rec and rec.wheelKey
    if type(k) ~= "string" or k == "" then return nil end
    return k
end

function WH.Look(rec)
    local Store = NS.Store
    local size = tonumber(Store.Resolve(rec, "wheel", "size")) or 100
    return {
        k = math.max(0.6, math.min(1.6, size / 100)),
        names = Store.Resolve(rec, "wheel", "names") ~= false,
        cooldowns = Store.Resolve(rec, "wheel", "cooldowns") ~= false,
        counts = Store.Resolve(rec, "wheel", "counts") ~= false,
    }
end

-- What a spot holds, ready to draw and to cast; nil for an empty spot. A spell
-- casts the highest rank you know, found by its name; one you do not know yet
-- shows grey and casts nothing (act nil). An item is used as /use would.
function WH.Entry(spot)
    if type(spot) ~= "table" then return nil end
    local id = tonumber(spot.id)
    if not id or id <= 0 then return nil end
    id = math.floor(id)
    if spot.t == "item" then
        local CI = C_Item
        local icon = CI and CI.GetItemIconByID and CI.GetItemIconByID(id)
        local name = CI and CI.GetItemNameByID and CI.GetItemNameByID(id)
        if not name then WH.WaitItem(id) end
        return { t = "item", id = id, icon = icon or 134400, name = name or ("Item " .. id),
            act = "item", value = "item:" .. id }
    end
    -- What it shows (art, name, cooldown): the one resolve, the rank you know
    -- by name and its override, as an icon reads it. What it casts: that rank
    -- itself (the game applies the override), never one the book dropped.
    local St, CS = NS.Store, C_Spell
    local eff = St.TrackedSpellID(id, true, false) or id
    local cast = St.TrackedSpellID(id, true, true) or id
    local name = CS and CS.GetSpellName and Plain(CS.GetSpellName(eff))
    local icon = CS and CS.GetSpellTexture and CS.GetSpellTexture(eff)
    local known = St.KnowsSpell(id) ~= false
    return { t = "spell", id = id, eff = eff, cast = cast, icon = icon or 134400,
        name = (type(name) == "string" and name ~= "") and name or ("Spell " .. id),
        act = known and "spell" or nil, value = cast }
end

-- every spot of the wheel, resolved: [spot] = entry
function WH.Entries(rec)
    local out, spots = {}, WH.Spots(rec)
    for spot = 1, WH.Count(rec) do out[spot] = WH.Entry(spots[spot]) end
    return out
end

-- an item the client has not cached yet: its name and icon come with
-- GET_ITEM_INFO_RECEIVED, then every wheel is drawn again
function WH.WaitItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    if WH.waiting then return end
    WH.waiting = true
    NS.Events.On("GET_ITEM_INFO_RECEIVED", WH.KEY, function()
        WH.waiting = false
        NS.Events.Off("GET_ITEM_INFO_RECEIVED", WH.KEY)
        WH.SyncAll()
    end)
end

-- The dial: the disc, the X, the pointer, a slot per spot, the dividers. One
-- drawing serves the wheel you cast from and the editor on the Wheel tab.

function WH.NewDial(parent)
    local d = { slots = {}, lines = {}, shown = {}, n = 0 }
    local ring = CreateFrame("Frame", nil, parent)
    d.ring = ring
    d.bg = ring:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAtlas("Radial_Wheel_BG")
    d.bg:SetPoint("CENTER")
    -- the middle: the X, ringed in gold while nothing is pointed at
    d.closeRing = ring:CreateTexture(nil, "ARTWORK")
    d.closeRing:SetAtlas("Radial_Wheel_Select_Close")
    d.closeRing:SetPoint("CENTER")
    d.closeIcon = ring:CreateTexture(nil, "OVERLAY")
    d.closeIcon:SetAtlas("Radial_Wheel_Icon_Close")
    d.closeIcon:SetPoint("CENTER")
    d.pointer = ring:CreateTexture(nil, "OVERLAY", nil, 1)
    d.pointer:SetAtlas("Radial_Wheel_Select_Pointer")
    d.pointer:SetPoint("CENTER")
    d.pointer:Hide()
    d.emptyText = ring:CreateFontString(nil, "OVERLAY")
    d.emptyText:SetFont(STANDARD_TEXT_FONT, 14, "")
    d.emptyText:SetShadowOffset(1, -1)
    d.emptyText:SetShadowColor(0, 0, 0, 1)
    return d
end

function WH.DialSlot(d, spot)
    if d.slots[spot] then return d.slots[spot] end
    local s = CreateFrame("Frame", nil, d.ring)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- round, with the circle mask the game uses for its own round art
    s.mask = s:CreateMaskTexture()
    s.mask:SetTexture(WH.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    s.mask:SetAllPoints(s.icon)
    s.icon:AddMaskTexture(s.mask)
    -- a mask clips only its own frame's textures: the swipe is round by its own art
    s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
    s.cd:SetAllPoints(s.icon)
    s.cd:SetSwipeTexture(WH.CIRCLE)
    s.cd:SetSwipeColor(0, 0, 0, 0.7)
    s.cd:SetDrawEdge(false)
    s.cd:SetDrawBling(false)
    s.cd:SetHideCountdownNumbers(true)
    if s.cd.SetUseCircularEdge then s.cd:SetUseCircularEdge(true) end
    -- the count rides above the swipe
    s.top = CreateFrame("Frame", nil, s)
    s.top:SetAllPoints(s.icon)
    s.top:SetFrameLevel(s:GetFrameLevel() + 3)
    s.count = s.top:CreateFontString(nil, "OVERLAY")
    s.count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    s.count:SetPoint("BOTTOMRIGHT", s.icon, "BOTTOMRIGHT", 0, 1)
    -- the one pointed at wears the wheel's gold ring
    s.sel = s.top:CreateTexture(nil, "OVERLAY")
    s.sel:SetAtlas("Radial_Wheel_Select_Close")
    s.sel:SetPoint("CENTER", s, "CENTER")
    -- the tracking you are on now: a small cyan check. The wheel is on
    -- screen, so it keeps the classic colours whatever the panel's palette.
    local COL = NS.AT.PALETTES.classic.col
    s.check = s.top:CreateTexture(nil, "OVERLAY", nil, 2)
    s.check:SetAtlas("checkmark-minimal")
    s.check:SetDesaturated(true)
    s.check:SetVertexColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
    s.check:Hide()
    s.label = d.ring:CreateFontString(nil, "OVERLAY")
    s.label:SetFont(STANDARD_TEXT_FONT, 14, "")
    s.label:SetShadowOffset(1, -1)
    s.label:SetShadowColor(0, 0, 0, 1)
    d.slots[spot] = s
    return s
end

function WH.DialLine(d, i)
    if d.lines[i] then return d.lines[i] end
    local l = d.ring:CreateLine(nil, "BORDER")
    l:SetColorTexture(1, 1, 1, 1)
    l:SetVertexColor(0.8, 0.82, 0.86, 0.3)
    d.lines[i] = l
    return l
end

function WH.PlaceSlot(d, spot, on)
    local COL = NS.AT.PALETTES.classic.col
    local g, s, e = d.geo, d.slots[spot], d.shown[spot]
    local a = WH.Angle(spot, d.n)
    local x, y = g.S(g.r * math.cos(a)), g.S(g.r * math.sin(a))
    local size = on and g.icon or g.iconRest
    s:ClearAllPoints()
    s:SetSize(size, size)
    s:SetPoint("CENTER", d.ring, "CENTER", x, y)
    s.sel:SetShown(on)
    -- the name outside its icon, clear of the gold ring: beside it left and
    -- right, above it at the top, below it at the bottom
    local c, gap = math.cos(a), g.sel / 2 + g.gap
    s.label:ClearAllPoints()
    if c > WH.SIDE then
        s.label:SetPoint("LEFT", d.ring, "CENTER", x + gap, y)
    elseif c < -WH.SIDE then
        s.label:SetPoint("RIGHT", d.ring, "CENTER", x - gap, y)
    elseif y > 0 then
        s.label:SetPoint("BOTTOM", d.ring, "CENTER", x, y + gap)
    else
        s.label:SetPoint("TOP", d.ring, "CENTER", x, y - gap)
    end
    -- the pointed name lights; a spell not learned yet stays faint
    local lc = (not e.act) and COL.faint or (on and COL.ink or COL.dim)
    s.label:SetTextColor(lc[1], lc[2], lc[3])
end

function WH.PaintDial(d, pointed)
    for spot = 1, d.n do
        if d.shown[spot] then WH.PlaceSlot(d, spot, spot == pointed) end
    end
    d.closeRing:SetShown(pointed == nil and next(d.shown) ~= nil)
end

-- Size a dial and fill it: shown = [spot] = entry on a wheel of n spots, look =
-- WH.Look. names: overrides the look's Show names (the editor draws none).
function WH.FillDial(d, shown, n, look, names)
    local g = WH.Geo(look.k)
    d.geo, d.n, d.look = g, n, look
    wipe(d.shown)
    for spot, e in pairs(shown) do
        if spot <= n then d.shown[spot] = e end
    end
    local k = g.k
    d.ring:SetSize(g.half * 2, g.half * 2)
    d.bg:SetSize(g.half * 2, g.half * 2)
    d.closeRing:SetSize(g.S(48 * k), g.S(48 * k))
    d.closeIcon:SetSize(g.S(24 * k), g.S(24 * k))
    d.pointer:SetSize(g.S(84 * k), g.S(84 * k))
    d.pointer:Hide()
    if names == nil then names = look.names end
    -- slots are made per spot as needed, so the table can have holes
    for spot, sl in pairs(d.slots) do
        if not d.shown[spot] then
            sl:Hide()
            sl.label:Hide()
        end
    end
    for spot = 1, n do
        local e = d.shown[spot]
        if e then
            local sl = WH.DialSlot(d, spot)
            sl.icon:SetTexture(e.icon)
            sl.icon:SetDesaturated(not e.act)
            sl:SetAlpha(e.act and 1 or 0.55)
            sl.sel:SetSize(g.sel, g.sel)
            sl.label:SetFont(STANDARD_TEXT_FONT, g.font, "")
            sl.label:SetText(e.name)
            sl.count:SetFont(STANDARD_TEXT_FONT, math.max(8, g.font - 2), "OUTLINE")
            sl.count:SetText("")
            local cs = g.S(16 * k)
            sl.check:SetSize(cs, cs)
            sl.check:ClearAllPoints()
            sl.check:SetPoint("CENTER", sl, "BOTTOMRIGHT", -g.S(4 * k), g.S(4 * k))
            sl.check:Hide()
            sl.cd:Clear()
            sl:Show()
            sl.label:SetShown(names)
        end
    end

    -- equal slices: a divider halfway between every two spots
    local lineW = 2 * g.px
    for i = 1, n do
        local l, m = WH.DialLine(d, i), math.rad(90 - (i - 0.5) * 360 / n)
        l:SetStartPoint("CENTER", d.ring, g.inner * math.cos(m), g.inner * math.sin(m))
        l:SetEndPoint("CENTER", d.ring, g.outer * math.cos(m), g.outer * math.sin(m))
        l:SetThickness(lineW)
        l:Show()
    end
    for i = n + 1, #d.lines do d.lines[i]:Hide() end

    local COL = NS.AT.PALETTES.classic.col
    d.emptyText:SetFont(STANDARD_TEXT_FONT, g.font, "")
    d.emptyText:SetText("Nothing on this wheel yet")
    d.emptyText:ClearAllPoints()
    d.emptyText:SetPoint("TOP", d.ring, "CENTER", 0, -g.S(20 * k))
    d.emptyText:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    d.emptyText:SetShown(next(d.shown) == nil)
    WH.PaintDial(d, nil)
end

-- A slot's cooldown and count, while its wheel is up. Spell cooldowns are
-- secret on Forever and item ones can be: both go to the swipe as duration
-- objects and the count goes to SetText raw; only a plain count of 0 greys
-- the item.
function WH.Feed(d, spot)
    local s, e, look = d.slots[spot], d.shown[spot], d.look
    if not (s and e and look) then return end
    if not look.cooldowns then
        s.cd:Clear()
    elseif e.t == "spell" then
        local dur = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(e.eff, true)
        if dur then s.cd:SetCooldownFromDurationObject(dur, true) else s.cd:Clear() end
    else
        local CC, DU = C_Container, C_DurationUtil
        local start, duration
        if CC and CC.GetItemCooldown then start, duration = CC.GetItemCooldown(e.id) end
        if start ~= nil and duration ~= nil and DU and DU.CreateDuration then
            d.durs = d.durs or {}
            local dobj = d.durs[spot]
            if not dobj then
                dobj = DU.CreateDuration()
                d.durs[spot] = dobj
            end
            dobj:SetTimeFromStart(start, duration)
            s.cd:SetCooldownFromDurationObject(dobj, true)
        else
            s.cd:Clear()
        end
    end
    -- a tracking spell checked while it is the one you are on
    local tr = d.tracking
    s.check:SetShown(e.t == "spell" and tr ~= nil and (tr[e.eff] or tr[e.cast] or tr[e.id] or tr[e.name]) == true)
    if e.t == "item" then
        local CI = C_Item
        local stacks = CI and CI.GetItemMaxStackSizeByID and Plain(CI.GetItemMaxStackSizeByID(e.id))
        local cnt = CI and CI.GetItemCount and CI.GetItemCount(e.id, false, true)
        if look.counts and (type(stacks) ~= "number" or stacks > 1) then
            s.count:SetText(cnt)
            s.count:Show()
        else
            s.count:Hide()
        end
        local n = Plain(cnt)
        s.icon:SetDesaturated(type(n) == "number" and n == 0)
    else
        s.count:Hide()
    end
end

-- The tracking you are on now, by spell ID and by name: the game's own
-- tracking list, a plain answer in combat too. Empty when there is none.
function WH.ActiveTracking()
    local CM, set = C_Minimap, {}
    if not (CM and CM.GetNumTrackingTypes and CM.GetTrackingInfo) then return set end
    local n = Plain(CM.GetNumTrackingTypes())
    for i = 1, (type(n) == "number" and n or 0) do
        local info = CM.GetTrackingInfo(i)
        if type(info) == "table" and Plain(info.active) == true then
            local sid, nm = Plain(info.spellID), Plain(info.name)
            if type(sid) == "number" then set[sid] = true end
            if type(nm) == "string" and nm ~= "" then set[nm] = true end
        end
    end
    return set
end

function WH.FeedAll(d)
    d.tracking = WH.ActiveTracking()
    for spot = 1, d.n do
        if d.shown[spot] then WH.Feed(d, spot) end
    end
end

-- The live wheel: the insecure half

-- the spot the cursor points at, from where the wheel opened: the slice under
-- the pointer when something castable sits in it; nil in the middle
function WH.Pointed(d, dx, dy)
    local g = d.geo
    if dx * dx + dy * dy < g.dead * g.dead then return nil end
    local spot = WH.Slice(dx, dy, d.n)
    local e = d.shown[spot]
    return (e and e.act) and spot or nil
end

-- every frame while the wheel is up: the pointer turns to the cursor and the
-- slice it points at lights
function WH.Track(u)
    local d = u.dial
    local ox, oy = Plain(u.wheel:GetAttribute("adox")), Plain(u.wheel:GetAttribute("adoy"))
    if type(ox) ~= "number" or type(oy) ~= "number" or not d.geo then return end
    local s = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local dx, dy = cx / s - ox, cy / s - oy
    local g = d.geo
    if dx * dx + dy * dy >= g.dead * g.dead then
        d.pointer:SetRotation(math.atan2(dy, dx))
        d.pointer:Show()
    else
        d.pointer:Hide()
    end
    local p = WH.Pointed(d, dx, dy)
    if p ~= u.pointed then
        u.pointed = p
        WH.PaintDial(d, p)
    end
end

function WH.Opened(u)
    u.pointed = nil
    WH.PaintDial(u.dial, nil)
    WH.FeedAll(u.dial)
    -- the swipes, counts and the tracking check follow the game only while
    -- the wheel is up
    u.vis:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    u.vis:RegisterEvent("BAG_UPDATE_COOLDOWN")
    u.vis:RegisterEvent("BAG_UPDATE_DELAYED")
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("MINIMAP_UPDATE_TRACKING") then
        u.vis:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    end
    u.intro:Play()
end

function WH.Closed(u)
    u.vis:UnregisterAllEvents()
    u.pointed = nil
    u.dial.pointer:Hide()
end

-- The live wheel: the secure half. The snippets run in the game's restricted
-- environment against the one header (`owner`, the whole screen): no upvalues,
-- every number read from attributes. adphase: nil (shut), "held" (opened by
-- the key, waiting for its release), "sticky" (let go in the middle: up for a
-- click), "again" (the key pressed once more while sticky).

-- the slice under the cursor (spot) or the middle (middle)
WH.PICK = [[
    local spot, middle
    local fx, fy = owner:GetMousePosition()
    if fx then
        local dx = fx * owner:GetWidth() - (wheel:GetAttribute("adox") or 0)
        local dy = fy * owner:GetHeight() - (wheel:GetAttribute("adoy") or 0)
        local dead = wheel:GetAttribute("addead") or 0
        if dx * dx + dy * dy < dead * dead then
            middle = true
        else
            local n = wheel:GetAttribute("adn") or 0
            if n > 0 then
                local s = math.floor(((90 - math.deg(math.atan2(dy, dx))) % 360) / (360 / n) + 0.5) % n + 1
                if wheel:GetAttribute("adt" .. s) then spot = s end
            end
        end
    end
]]

-- a pointed spot: this button takes its action and the wheel shuts; the
-- button then acts on this release
WH.CAST = [[
    if spot then
        local t = wheel:GetAttribute("adt" .. spot)
        self:SetAttribute("type", t)
        self:SetAttribute(t, wheel:GetAttribute("adv" .. spot))
        wheel:Hide()
        return
    end
]]

-- the key: its press opens the wheel centred on the cursor, as the game's ping
-- wheel does (near an edge part of it runs off screen, so what is drawn is what
-- is picked); its release casts what it points at or, from the middle, leaves
-- the wheel up
WH.KEY_SNIPPET = [[
    local wheel = self:GetFrameRef("wheel")
    if not wheel then return false end
    local phase = wheel:GetAttribute("adphase")
    if down then
        if phase == "sticky" then
            wheel:SetAttribute("adphase", "again")
            return false
        end
        if phase then return false end
        local fx, fy = owner:GetMousePosition()
        if not fx then return false end
        local ox, oy = fx * owner:GetWidth(), fy * owner:GetHeight()
        wheel:SetAttribute("adox", ox)
        wheel:SetAttribute("adoy", oy)
        wheel:SetAttribute("adphase", "held")
        wheel:ClearAllPoints()
        wheel:SetPoint("CENTER", owner, "BOTTOMLEFT", ox, oy)
        wheel:Show()
        return false
    end
    if phase ~= "held" and phase ~= "again" then return false end
]] .. WH.PICK .. WH.CAST .. [[
    if middle and phase == "held" then
        wheel:SetAttribute("adphase", "sticky")
        return false
    end
    wheel:Hide()
    return false
]]

-- the screen catcher, up with the wheel: a click casts the slice it points at
-- and anything else shuts it; a right-click or Esc shuts it; a key on a mouse
-- button lands here once the wheel covers the screen
WH.CATCH_SNIPPET = [[
    local wheel = self:GetFrameRef("wheel")
    if not wheel then return false end
    local phase = wheel:GetAttribute("adphase")
    if not phase then return false end
    if button == "RightButton" then
        wheel:Hide()
        return false
    end
]] .. WH.PICK .. [[
    if middle and phase == "held" and button ~= "LeftButton" and button == wheel:GetAttribute("admouse") then
        wheel:SetAttribute("adphase", "sticky")
        return false
    end
]] .. WH.CAST .. [[
    wheel:Hide()
    return false
]]

-- while up, Esc shuts it; shut, it forgets its state
WH.ON_SHOW = [[ self:SetBindingClick(true, "ESCAPE", self:GetAttribute("adcatch"), "RightButton") ]]
WH.ON_HIDE = [[
    self:ClearBindings()
    self:SetAttribute("adphase", nil)
]]

-- the one header every wheel's snippets run against: the whole screen
function WH.Header()
    if WH.header then return WH.header end
    local h = CreateFrame("Frame", "ArcAurasWheelHeader", UIParent, "SecureHandlerBaseTemplate")
    h:SetAllPoints(UIParent)
    WH.header = h
    return h
end

-- Out of combat only. The key's button is shown but invisible and off screen,
-- so its binding always reaches it; it acts on the release only.
function WH.Create(id)
    local h = WH.Header()
    local name = "ArcAurasWheel" .. tostring(id)
    local u = { id = id, attrs = {} }
    local wheel = CreateFrame("Frame", name, UIParent, "SecureHandlerShowHideTemplate")
    wheel:SetFrameStrata("FULLSCREEN_DIALOG")
    wheel:SetFrameLevel(20)
    wheel:Hide()
    wheel:SetAttribute("adcatch", name .. "Catch")
    wheel:SetAttribute("_onshow", WH.ON_SHOW)
    wheel:SetAttribute("_onhide", WH.ON_HIDE)
    u.wheel = wheel

    local vis = CreateFrame("Frame", nil, wheel)
    vis:SetAllPoints(wheel)
    vis:SetFrameLevel(21)
    u.vis = vis
    u.dial = WH.NewDial(vis)
    u.dial.ring:SetPoint("CENTER", vis, "CENTER")
    u.intro = u.dial.ring:CreateAnimationGroup()
    u.intro:SetToFinalAlpha(true)
    local fade = u.intro:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.12)
    vis:SetScript("OnShow", function() WH.Opened(u) end)
    vis:SetScript("OnHide", function() WH.Closed(u) end)
    vis:SetScript("OnUpdate", function() WH.Track(u) end)
    vis:SetScript("OnEvent", function() WH.FeedAll(u.dial) end)

    local catcher = CreateFrame("Button", name .. "Catch", wheel, "SecureActionButtonTemplate")
    catcher:SetAllPoints(h)
    catcher:SetFrameLevel(40)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetAttribute("useOnKeyDown", false)
    SecureHandlerSetFrameRef(catcher, "wheel", wheel)
    SecureHandlerWrapScript(catcher, "OnClick", h, WH.CATCH_SNIPPET)
    u.catcher = catcher

    local opener = CreateFrame("Button", name .. "Key", UIParent, "SecureActionButtonTemplate")
    opener:SetSize(1, 1)
    opener:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    opener:SetAlpha(0)
    opener:EnableMouse(false)
    opener:RegisterForClicks("AnyDown", "AnyUp")
    opener:SetAttribute("useOnKeyDown", false)
    SecureHandlerSetFrameRef(opener, "wheel", wheel)
    SecureHandlerWrapScript(opener, "OnClick", h, WH.KEY_SNIPPET)
    u.opener = opener

    WH.units[id] = u
    return u
end

-- an attribute only when it changes
local function Attr(u, frame, name, v)
    local key = (frame == u.wheel) and name or ("o:" .. name)
    if u.attrs[key] == v and u.attrs[key .. "?"] then return end
    u.attrs[key], u.attrs[key .. "?"] = v, true
    frame:SetAttribute(name, v)
end

-- the click button a key on a mouse button arrives as, else nil
function WH.MouseButton(key)
    if type(key) ~= "string" then return nil end
    local b = key:match("(BUTTON%d+)$")
    return b and WH.MOUSE[b] or nil
end

-- Out of combat only: the whole protected state of one wheel from its record.
function WH.Apply(rec)
    local u = WH.units[rec.id] or WH.Create(rec.id)
    u.rec = rec
    local n, look = WH.Count(rec), WH.Look(rec)
    local shown = WH.Entries(rec)
    WH.FillDial(u.dial, shown, n, look)
    local g = u.dial.geo
    u.wheel:SetSize(g.half * 2, g.half * 2)
    Attr(u, u.wheel, "adn", n)
    Attr(u, u.wheel, "addead", g.dead)
    for spot = 1, WH.MAX do
        local e = (spot <= n) and shown[spot] or nil
        local act = e and e.act or nil
        Attr(u, u.wheel, "adt" .. spot, act)
        Attr(u, u.wheel, "adv" .. spot, act and e.value or nil)
    end
    local key = WH.KeyOf(rec)
    if u.key ~= key then
        ClearOverrideBindings(u.opener)
        if key then SetOverrideBindingClick(u.opener, false, key, u.opener:GetName(), "LeftButton") end
        u.key = key
    end
    Attr(u, u.wheel, "admouse", WH.MouseButton(key))
end

-- Out of combat only: no key, shut.
function WH.Drop(id)
    local u = WH.units[id]
    if not u then return end
    if u.key then
        ClearOverrideBindings(u.opener)
        u.key = nil
    end
    u.wheel:Hide()
end

-- one wheel against its record: built and bound while it loads, else dropped;
-- in combat it waits for PLAYER_REGEN_ENABLED
function WH.Sync(id)
    if InCombat() then
        WH.pending = true
        WH.Arm()
        return
    end
    local rec = WH.live[id]
    if rec then WH.Apply(rec) else WH.Drop(id) end
end

function WH.SyncAll()
    if InCombat() then
        WH.pending = true
        WH.Arm()
        return
    end
    WH.pending = false
    for id in pairs(WH.units) do
        if not WH.live[id] then WH.Drop(id) end
    end
    for _, rec in pairs(WH.live) do WH.Apply(rec) end
end

-- Combat end applies what waited; a new spell or rank re-resolves every wheel.
function WH.Arm()
    if WH.armed then return end
    WH.armed = true
    NS.Events.On("PLAYER_REGEN_ENABLED", WH.KEY, function()
        if WH.pending then WH.SyncAll() end
    end)
    NS.Events.On("SPELLS_CHANGED", WH.KEY, function()
        if next(WH.live) ~= nil then WH.SyncAll() end
    end)
end

-- The bar kind: the bars runtime hands every (re)style of a wheel record here.
-- Its holder never shows (noHolder): the wheel opens at the cursor.

function WH.Ensure(e)
    local rec = e.rec
    e.stateHidden = true
    WH.live[rec.id] = NS.Store.IsLoaded(rec) and rec or nil
    WH.Arm()
    WH.Sync(rec.id)
end

function WH.Release(e)
    local id = e.rec and e.rec.id
    if id == nil then return end
    WH.live[id] = nil
    WH.Sync(id)
end

function WH.Diag(e)
    local rec = e.rec
    local u = WH.units[rec.id]
    return ("wheel %d spots, key %s, %s"):format(WH.Count(rec), tostring(WH.KeyOf(rec) or "none"),
        (u and u.key) and "bound" or "not bound")
end

local Bars = NS.Bars
if Bars and Bars.RegisterKind then
    Bars.RegisterKind("wheel", { Ensure = WH.Ensure, Release = WH.Release, Diag = WH.Diag, noHolder = true })
end
