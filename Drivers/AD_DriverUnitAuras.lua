-- AD_DriverUnitAuras: aura groups that show every aura on one unit, drawn by the game in AuraContainers the group owns.
-- It places such a group for the layout engine (Engine.RegisterGroupClaim): one container follows the unit, or one per enemy nameplate; the member rows skip it.
-- The game reads the auras and draws the buttons, so it works in combat; nothing here reads an aura or a rect, and a unit answer is never compared unguarded.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local UA = {
    runtimes = {},   -- [groupId] = { cs, c, sent, buttons, engines, slotRecs, slotDims, cfg, mode, want, short, bound, hostile, pin, hasD }
    placed = {},     -- [groupId] = its group frame while the engine draws it
    looks = {},      -- [groupId] = the record its buttons are styled from
    looksD = {},     -- [groupId] = the same for its debuff half (Buffs and debuffs)
    blocked = {},    -- [groupId] = true while its first container waits to be made
    armed = {},      -- [unit] = true while its swap event listens
    platesArmed = false,
    pending = false, -- a build, a setting or a restyle waits for the settle edge
    loadWindowOver = false,
}
NS.DriverUnitAuras = UA

UA.KEY = "adUnitAuras"
-- Buffs and debuffs: the debuffs are a second aura group in the same container
UA.KEY_D = UA.KEY .. "D"
UA.KEYS = { UA.KEY }
UA.UNITS = { player = true, pet = true, target = true, focus = true, nameplate = true }
-- The unit token stays the same when it points at someone new, and the
-- container re-reads only on its own unit's aura events.
UA.SWAP = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED", pet = "UNIT_PET" }
UA.PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
UA.SORTS = { default = "Default", time = "ExpirationOnly" }
-- Blizzard_AuraContainerShared's values, for a client that has not loaded it
UA.SORT_IDS = { Default = 0, ExpirationOnly = 5 }
UA.MARK_ART = "Interface\\Icons\\INV_Misc_QuestionMark"
UA.MARK_ALPHA = 0.35

function UA.Available()
    local G = NS.DriverAuraGroups
    return G ~= nil and G.IsAvailable()
end

function UA.Claims(g)
    return Store.ShowsAll(g)
end

function UA.Token(i) return "nameplate" .. i end

-- Rows by the arrangement's Columns, and the cap they make per half, never
-- past Schema.UNIT_AURA_MAX.
function UA.Grid(g)
    local rows = math.floor(tonumber(Store.Resolve(g, "unitAuras", "rows")) or 1)
    local cols = math.floor(tonumber(Store.Resolve(g, "arrangement", "cols")) or 6)
    if rows < 1 then rows = 1 end
    if cols < 1 then cols = 1 end
    return rows, cols, math.min(rows * cols, NS.Schema.UNIT_AURA_MAX or 40)
end

function UA.Cap(g)
    local _, _, cap = UA.Grid(g)
    return cap
end

-- The arrangement's Alignment read on this group's grid shape, as the member
-- aura groups read theirs; the options window offers the same choices.
function UA.Alignment(g)
    local E = NS.LayoutEngine
    if not (E and E.EffectiveAlignment) then return "center", "horizontal" end
    local rows, cols = UA.Grid(g)
    return E.EffectiveAlignment(g, rows, cols)
end

-- "2825, 32182 80353" -> { [2825] = true, ... }, or nil when it names none
function UA.ParseIDs(text)
    local m
    for n in tostring(text or ""):gmatch("%d+") do
        local v = tonumber(n)
        if v and v > 0 then
            m = m or {}
            m[v] = true
        end
    end
    return m
end

-- What the group's containers are set to. Cast by rides the filter string (the
-- aura icons' own reader); the hide list goes only to a half the game honours
-- it for. Buffs and debuffs: the first half HELPFUL, the second HARMFUL.
-- Enemy nameplates carry debuffs only, whatever Aura type says.
function UA.Config(g)
    local R = function(k) return Store.Resolve(g, "unitAuras", k) end
    local S, DA = NS.Schema, NS.DriverAura
    local unit, harmful, both = S.UnitAuraShape(g)
    if not UA.UNITS[unit] then unit, harmful, both = "player", R("auraType") == "debuff", R("auraType") == "both" end
    local plates = unit == "nameplate"
    local hide, hideD
    if S.UnitAuraHideOK(unit, harmful) then hide = UA.ParseIDs(R("hideSpells")) end
    if both and S.UnitAuraHideOK(unit, true) then hideD = UA.ParseIDs(R("hideSpells")) end
    local count = 1
    if plates then
        local max = S.UNIT_AURA_PLATES or 40
        count = math.floor(tonumber(R("plateCount")) or 20)
        if count < 1 then count = 1 elseif count > max then count = max end
    end
    local rows, cols, cap = UA.Grid(g)
    local caster = R("caster")
    -- the dispel types ticked (none = every aura), both halves alike
    local dispel, dispelSig
    for _, d in ipairs(UA.DISPEL) do
        if R(d.field) == true then
            dispel = dispel or {}
            dispel[d.name] = true
            dispelSig = (dispelSig and (dispelSig .. ",") or "") .. d.name
        end
    end
    return {
        dispel = dispel, dispelSig = dispelSig,
        unit = unit, plates = plates, harmful = harmful, both = both, hide = hide, hideD = hideD, count = count,
        rows = rows, cols = cols, cap = cap,
        filter = DA.FilterForLane({ caster = caster }, { harmful = harmful }),
        filterD = both and DA.FilterForLane({ caster = caster }, { harmful = true }) or nil,
        -- a plate row keeps filling across
        vertical = R("fill") == "down" and not plates,
        newLine = R("debuffLine") ~= false,
        order = (R("order") == "time") and "time" or "default",
        edge = (R("plateEdge") == "bottom") and "bottom" or "top",
        x = tonumber(R("plateX")) or 0, y = tonumber(R("plateY")) or 0,
    }
end

-- A half's candidate filters and their signature. No list means every aura
-- that passes the filter string shows. The dispel types reach every unit: the
-- game filters them itself (only spell IDs are refused on some units).
UA.DISPEL = { { field = "dispelMagic", name = "Magic" }, { field = "dispelCurse", name = "Curse" },
    { field = "dispelDisease", name = "Disease" }, { field = "dispelPoison", name = "Poison" } }
function UA.Filters(cfg, debuffs)
    local ids = cfg.hide
    if debuffs then ids = cfg.hideD end
    local filters, sig = {}, "none"
    if ids then
        filters.excludeSpellIDs = ids
        sig = "x:" .. NS.DriverAura.FilterSig(ids)
    end
    if cfg.dispel then
        filters.includeDispelTypes = cfg.dispel
        sig = sig .. "|d:" .. cfg.dispelSig
    end
    return filters, sig
end

function UA.Sort(order)
    local name = UA.SORTS[order] or "Default"
    local E, D = AuraContainerSortMethod, AuraContainerSortDirection
    return (E and E[name]) or UA.SORT_IDS[name], (D and D.Normal) or 0
end

-- The box: Rows by Columns, a line filled across (Columns long) or down (Rows
-- long) first, the debuffs' block after the buffs' when both show. The unit's
-- container is pinned where Alignment says and reads away from that pin, as
-- the member rows do (Drivers\AD_DriverAuraGroups.lua ApplyEngineLayout); a
-- centred axis keeps its growth direction and grows both ways. A plate row
-- grows away from the plate's edge instead, from its corner.
function UA.Plan(g, cfg)
    cfg = cfg or UA.Config(g)
    local w, h, sx, sy, _, growthH, growthV = NS.DriverAuraGroups.GroupDims(g)
    local cap, vertical = cfg.cap, cfg.vertical == true
    local per = math.max(1, math.min(vertical and cfg.rows or cfg.cols, cap))
    local lines = math.ceil(cap / per)
    local blocks = cfg.both and 2 or 1
    local pad = Store.Resolve(g, "arrangement", "containerPadding") or 0
    if pad < 0 then pad = 0 end
    local right, down = growthH ~= "LEFT", growthV ~= "UP"
    local hPart, vPart
    if cfg.plates then
        down = cfg.edge == "bottom"
    else
        local align, shape = UA.Alignment(g)
        if align == "left" or align == "right" then
            hPart = align:upper()
        elseif align == "center_h" or (align == "center" and shape ~= "vertical") then
            hPart = ""
        else
            hPart = right and "LEFT" or "RIGHT"
        end
        if align == "top" or align == "bottom" then
            vPart = align:upper()
        elseif align == "center_v" or (align == "center" and shape == "vertical") then
            vPart = ""
        else
            vPart = down and "TOP" or "BOTTOM"
        end
        if hPart ~= "" then right = hPart == "LEFT" end
        if vPart ~= "" then down = vPart == "TOP" end
    end
    local pw, ps, cw, cs = w, sx, h, sy
    if vertical then pw, ps, cw, cs = h, sy, w, sx end
    local span = per * pw + (per - 1) * ps
    local n = lines * blocks
    local bw, bh = span, n * cw + (n - 1) * cs
    if vertical then bw, bh = bh, bw end
    bw, bh = math.max(4, bw + 2 * pad), math.max(4, bh + 2 * pad)
    local corner = (down and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT")
    local pin, ox, oy = corner, 0, 0
    if not cfg.plates then
        pin = vPart .. hPart
        if pin == "" then pin = "CENTER" end
        -- the flow's corner seen from the pin, on a full box
        local fx = (hPart == "LEFT" and 0) or (hPart == "RIGHT" and bw) or bw / 2
        local fy = (vPart == "TOP" and 0) or (vPart == "BOTTOM" and -bh) or -bh / 2
        ox, oy = (right and 0 or bw) - fx, (down and 0 or -bh) - fy
    end
    return {
        w = w, h = h, sx = sx, sy = sy, per = per, lines = lines, blocks = blocks, cap = cap, pad = pad,
        right = right, down = down, vertical = vertical, corner = corner, pin = pin, ox = ox, oy = oy,
        -- past one line's buttons and short of the next one's end, so exactly
        -- `per` fit, whatever the spacing
        lineSize = span + math.max(0.5, (pw + ps) / 2),
        boxW = bw, boxH = bh,
    }
end

-- Cell i's offset from the pin, where the flow puts its i-th button once the
-- container, pinned there, is full. Past the first cap cells the debuffs'
-- block starts a line on: a full buff grid ends its line either way.
function UA.CellXY(p, i)
    local k = (i - 1) % p.cap
    local line = math.floor(k / p.per) + math.floor((i - 1) / p.cap) * p.lines
    local a = p.pad + (k % p.per) * (p.vertical and (p.h + p.sy) or (p.w + p.sx))
    local b = p.pad + line * (p.vertical and (p.w + p.sx) or (p.h + p.sy))
    local x, y = a, b
    if p.vertical then x, y = b, a end
    return (p.right and x or -x) + p.ox, (p.down and -y or y) + p.oy
end

-- A plain aura icon of the group's unit and type in its layout, never saved:
-- a half's buttons wear what a new aura icon there would.
function UA.LookRec(g, cfg, debuffs)
    local looks = debuffs and UA.looksD or UA.looks
    local r = looks[g.id]
    if not r then
        r = { type = "icon", kind = "aura", o = {}, c = {}, driver = {} }
        looks[g.id] = r
    end
    r.groupId = g.id
    r.driver.unit = cfg.unit
    r.driver.auraType = (debuffs or cfg.harmful) and "debuff" or "buff"
    return r
end

-- Containers are made in the load window, else only out of combat with auras
-- plain: the game blocks creation otherwise.
function UA.CanMake()
    return not (UA.loadWindowOver and (InCombatLockdown() or NS.DriverAuraGroups.AurasSecretNow()))
end

-- One container with one aura group, following `unit`, its buttons dressed
-- as they are made (the always-legal write window). Every later edit is a
-- setter: a container is never re-slotted.
function UA.MakeContainer(g, rt, cfg, unit)
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraGroup) ~= "function" then
        if c then c:Hide() end
        return nil
    end
    c:SetSize(1, 1)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:EnableMouse(false)
    c:Hide()
    local filters, sig = UA.Filters(cfg)
    c:AddAuraGroup(UA.KEY, cfg.filter, UA.GroupOptions(rt, cfg, filters, 1))
    c._adSent = { unit = unit, filter = cfg.filter, cap = cfg.cap, order = cfg.order, hide = sig }
    rt.cs[#rt.cs + 1] = c
    rt.engines[#rt.engines + 1] = c
    return c
end

-- One half's aura group: slot 1 the first half, 2 the debuffs. Its buttons
-- are dressed from rt.slotRecs[slot] as they are made, every batch the game
-- makes later too.
function UA.GroupOptions(rt, cfg, filters, slot)
    local G, DA = NS.DriverAuraGroups, NS.DriverAura
    local method, dir = UA.Sort(cfg.order)
    return {
        maxFrameCount = cfg.cap,
        sortMethod = method, sortDirection = dir,
        candidateFilters = filters,
        initializeFrame = function(b)
            if DA and DA.WireButton then DA.WireButton(b) end
            b:SetSize(rt.cfg.iconW, rt.cfg.iconH)
            b._adAppliedW, b._adAppliedH = rt.cfg.iconW, rt.cfg.iconH
            b._adSlotIndex = slot
            b:EnableMouse(false)
            if not b._adCollected then
                b._adCollected = true
                rt.buttons[#rt.buttons + 1] = b
            end
            G.StyleSlotButton(b, rt)
        end,
        layout = UA.HalfLayout(rt.cfg.sx, rt.cfg.sy, slot == 2, cfg.newLine),
    }
end

-- A half's spacing: ex between buttons on a line, ly between lines. The
-- debuffs flow on after the buffs with no gap of their own, on a new line
-- when asked.
function UA.HalfLayout(ex, ly, debuffs, newLine)
    local t = { elementSpacing = ex, lineSpacing = ly, groupSpacing = ex, groupLineSpacing = ly }
    if debuffs then t.groupSpacing, t.forceNewLine, t.layoutIndex = 0, newLine == true, 2 end
    return t
end

-- Buffs and debuffs: the debuff half joins the unit's container the first
-- time a group needs it, under the creation rule, else at the settle edge. A
-- group is never removed, only switched off (UA.Push).
function UA.AddDebuffs(g, rt, cfg)
    if rt.hasD or not cfg.both then return end
    if not UA.CanMake() then
        UA.pending = true
        return
    end
    local c = rt.cs[1]
    rt.slotRecs[2] = UA.LookRec(g, cfg, true)
    local filters, sig = UA.Filters(cfg, true)
    c:AddAuraGroup(UA.KEY_D, cfg.filterD, UA.GroupOptions(rt, cfg, filters, 2))
    c._adSentD = { on = true, filter = cfg.filterD, cap = cfg.cap, order = cfg.order, hide = sig }
    rt.hasD = true
end

-- The group's runtime and its first container, built once.
function UA.Build(g)
    local rt = UA.runtimes[g.id]
    if rt then return rt end
    if not UA.Available() then return nil end
    if not UA.CanMake() then
        UA.blocked[g.id] = true
        UA.pending = true
        return nil
    end
    local cfg = UA.Config(g)
    local p = UA.Plan(g, cfg)
    rt = { cs = {}, buttons = {}, engines = {}, slotDims = {}, bound = {}, hostile = {},
        slotRecs = { UA.LookRec(g, cfg) }, cfg = { iconW = p.w, iconH = p.h, sx = p.sx, sy = p.sy },
        mode = cfg.plates and "plates" or "unit", want = 1 }
    local c = UA.MakeContainer(g, rt, cfg, cfg.plates and UA.Token(1) or cfg.unit)
    if not c then return nil end
    rt.c, rt.sent = c, c._adSent
    UA.runtimes[g.id] = rt
    UA.blocked[g.id] = nil
    return rt
end

-- The plate pool: container i follows "nameplate<i>", Nameplates covered
-- deep. It grows under the creation rule, so plates past it stay uncovered
-- until it can; a smaller count keeps the extra containers, unused.
function UA.Pool(g, rt, cfg)
    local want = cfg.plates and cfg.count or 1
    rt.want = want
    while #rt.cs < want do
        if not UA.CanMake() then
            UA.pending = true
            break
        end
        if not UA.MakeContainer(g, rt, cfg, UA.Token(#rt.cs + 1)) then break end
    end
    rt.short = #rt.cs < want
end

-- How many plate containers are in use: the pool, capped at Nameplates covered.
function UA.Covered(rt)
    return math.min(rt.want or 1, #rt.cs)
end

-- Sends what changed since the last send to each container in use: the one
-- following the unit, or every plate row. The setters are data only, yet
-- they wait out combat like the other aura drivers' edits; a client lacking
-- one keeps what the container was built with.
function UA.Push(g, rt)
    local cfg = UA.Config(g)
    rt.slotRecs[1] = UA.LookRec(g, cfg)
    local filters, sig = UA.Filters(cfg)
    local n = cfg.plates and UA.Covered(rt) or 1
    for i = 1, n do
        local c, s = rt.cs[i], rt.cs[i]._adSent
        local unit = cfg.plates and UA.Token(i) or cfg.unit
        if s.unit ~= unit then
            if InCombatLockdown() then
                UA.pending = true
                return
            end
            c:SetUnit(unit)
            s.unit = unit
        end
        if UA.SendHalf(c, UA.KEY, s, cfg.filter, filters, sig, cfg) then
            UA.pending = true
            return
        end
    end
    if not rt.hasD then return end
    -- the debuff half: on only while both show
    rt.slotRecs[2] = UA.LookRec(g, cfg, true)
    local c, s = rt.cs[1], rt.cs[1]._adSentD
    local on = cfg.both == true
    if s.on ~= on then
        if InCombatLockdown() then
            UA.pending = true
            return
        end
        if c.SetAuraGroupEnabled then
            c:SetAuraGroupEnabled(UA.KEY_D, on)
            s.on = on
        end
    end
    local fD, sigD = UA.Filters(cfg, true)
    if on and UA.SendHalf(c, UA.KEY_D, s, cfg.filterD, fD, sigD, cfg) then UA.pending = true end
end

-- One half's filter, hide list, order and cap, each sent only when changed:
-- every send rebuilds the container. True when combat holds the send.
function UA.SendHalf(c, key, s, filter, filters, sig, cfg)
    if s.filter == filter and s.hide == sig and s.order == cfg.order and s.cap == cfg.cap then return false end
    if InCombatLockdown() then return true end
    if s.filter ~= filter and c.SetAuraGroupFilterString then
        c:SetAuraGroupFilterString(key, filter)
        s.filter = filter
    end
    if s.hide ~= sig and c.SetAuraGroupCandidateFilters then
        c:SetAuraGroupCandidateFilters(key, filters)
        s.hide = sig
    end
    if s.order ~= cfg.order and c.SetAuraGroupSortMethod then
        local method, dir = UA.Sort(cfg.order)
        c:SetAuraGroupSortMethod(key, method, dir)
        s.order = cfg.order
    end
    if s.cap ~= cfg.cap and c.SetAuraGroupMaxFrameCount then
        c:SetAuraGroupMaxFrameCount(key, cfg.cap)
        s.cap = cfg.cap
    end
    return false
end

-- The flow the aura group rows use. The unit's container is pinned to the
-- group frame at the pin Alignment picks, so it grows away from it (both ways
-- when centred); a plate row is pinned to its plate when the plate comes up
-- (UA.Pin).
function UA.Layout(rt, gf, p, cfg)
    rt.cfg.iconW, rt.cfg.iconH, rt.cfg.sx, rt.cfg.sy = p.w, p.h, p.sx, p.sy
    local n = cfg.plates and UA.Covered(rt) or 1
    for i = 1, n do UA.Flow(rt, rt.cs[i], p, cfg) end
    if cfg.plates then return end
    local c = rt.cs[1]
    c:ClearAllPoints()
    c:SetPoint(p.pin, gf, p.pin, 0, 0)
end

-- Fill down first turns the flow's axis: a line runs down, so each spacing
-- goes to the gap it separates. The axis is set every time, as a container
-- can move between a unit and a plate.
function UA.Flow(rt, c, p, cfg)
    local ex, ly = p.sx, p.sy
    if p.vertical then ex, ly = p.sy, p.sx end
    NS.DriverAuraGroups.ApplyFlow(c, UA.KEYS, ex, ly, p.lineSize, p.pad, p.right, p.down)
    local AX = AnchorUtil and AnchorUtil.FlowLayoutAxis
    if AX and c.SetFlowLayoutAxis then c:SetFlowLayoutAxis(p.vertical and AX.Vertical or AX.Horizontal) end
    -- a layout send replaces the whole set, so the debuffs' own keys ride along
    if rt.hasD and c == rt.cs[1] and c.SetAuraGroupLayout then
        c:SetAuraGroupLayout(UA.KEY_D, UA.HalfLayout(ex, ly, true, cfg.newLine))
    end
end

-- A plate's row sits centred on the plate's top or bottom edge, plus the
-- offsets, and grows away from it. Anchoring our container to the plate is
-- legal; its points may be secret, and ours are never read.
function UA.Pin(c, plate, pin)
    c:ClearAllPoints()
    if pin.edge == "bottom" then
        c:SetPoint("TOP", plate, "BOTTOM", pin.x, pin.y)
    else
        c:SetPoint("BOTTOM", plate, "TOP", pin.x, pin.y)
    end
end

-- Dim cells where the auras will sit, while the options window is open, so the
-- group has a box to see and drag; the game's buttons draw over them.
function UA.Marks(gf, p, on)
    local host = gf._adUAMarks
    if not on then
        if host then host:Hide() end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, gf)
        host.cells = {}
        gf._adUAMarks = host
    end
    host:SetFrameLevel(gf:GetFrameLevel() + 1)
    local n = p.cap * p.blocks
    for i = 1, n do
        local t = host.cells[i]
        if not t then
            t = host:CreateTexture(nil, "ARTWORK")
            t:SetTexture(UA.MARK_ART)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t:SetAlpha(UA.MARK_ALPHA)
            host.cells[i] = t
        end
        local x, y = UA.CellXY(p, i)
        t:ClearAllPoints()
        t:SetPoint(p.corner, gf, p.pin, x, y)
        t:SetSize(p.w, p.h)
        t:Show()
    end
    for i = n + 1, #host.cells do host.cells[i]:Hide() end
    host:Show()
end

-- Plates

-- Only a plate you can attack shows a row: a plain false hides it, and a
-- secret answer (an instance) shows it, since HARMFUL alone would show a
-- friendly plate's debuffs.
function UA.Hostile(token)
    local can = UnitCanAttack("player", token)
    if issecretvalue and issecretvalue(can) then return true end
    return can == true
end

-- The plate a token points at, or nil: none up, or one the game keeps to itself.
function UA.PlateOf(token)
    local NP = C_NamePlate
    if not (NP and NP.GetNamePlateForUnit) then return nil end
    local plate = NP.GetNamePlateForUnit(token, false)
    if plate and plate.IsForbidden and plate:IsForbidden() then return nil end
    return plate
end

-- A group's rows may show while the engine draws it and it loads here (an
-- unloaded group its eye shows while editing gets its cells only).
function UA.Drawn(g)
    return UA.placed[g.id] ~= nil and Store.IsLoaded(g)
end

-- A plate row shows while the group is drawn, its plate is up and the plate
-- is one you can attack; the group frame's fade and level carry over.
function UA.MirrorPlate(g, rt, i, gf)
    local on = UA.Drawn(g) and rt.bound[i] == true and rt.hostile[i] == true
    NS.DriverAuraGroups.MirrorOnto(rt.cs[i], gf, on)
    return on
end

-- A plate came up for token i: its row takes the plate's edge and its
-- hostility, and reads its auras (the token points at a new unit, and the
-- container never re-reads on its own).
function UA.Bind(g, rt, i, plate, gf)
    local c = rt.cs[i]
    UA.Pin(c, plate, rt.pin)
    rt.bound[i] = true
    rt.hostile[i] = UA.Hostile(UA.Token(i))
    if UA.MirrorPlate(g, rt, i, gf) and c.UpdateAllAuras then c:UpdateAllAuras() end
end

function UA.Unbind(rt, i)
    local c = rt.cs[i]
    c:Hide()
    c:ClearAllPoints()
    rt.bound[i], rt.hostile[i] = nil, nil
end

-- The plates already up when the group is placed (a rebuild fires no ADDED):
-- every covered token asked once; a row with no plate hides (the first one
-- may have just followed a unit), and rows past the covered count let go.
function UA.BindAll(g, rt, gf)
    local n = UA.Covered(rt)
    for i = 1, #rt.cs do
        local plate = (i <= n) and UA.PlateOf(UA.Token(i)) or nil
        if plate then
            UA.Bind(g, rt, i, plate, gf)
        else
            UA.Unbind(rt, i)
        end
    end
end

function UA.UnbindAll(rt)
    for i = 1, #rt.cs do
        if rt.bound[i] then UA.Unbind(rt, i) end
    end
end

-- A plate added or removed: its token is "nameplate<i>". A secret token is
-- never read; a token past the pool has no row.
function UA.OnPlate(event, token)
    if (issecretvalue and issecretvalue(token)) or type(token) ~= "string" then return end
    local i = tonumber(token:match("^nameplate(%d+)$"))
    if not i then return end
    for gid, gf in pairs(UA.placed) do
        local rt, g = UA.runtimes[gid], Store.Get(gid)
        if rt and g and rt.mode == "plates" and i <= UA.Covered(rt) then
            local plate = (event == "NAME_PLATE_UNIT_ADDED") and UA.PlateOf(token) or nil
            if plate then
                UA.Bind(g, rt, i, plate, gf)
            elseif rt.bound[i] then
                UA.Unbind(rt, i)
            end
        end
    end
end

function UA.Valid(e)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
end

-- The plate events listen only while a drawn group follows the plates.
function UA.ArmPlates()
    local want = false
    for gid in pairs(UA.placed) do
        local rt = UA.runtimes[gid]
        if rt and rt.mode == "plates" then
            want = true
            break
        end
    end
    if want == UA.platesArmed then return end
    UA.platesArmed = want
    for _, e in ipairs(UA.PLATE_EVENTS) do
        if want then
            if UA.Valid(e) then Events.On(e, "adua_plates", UA.OnPlate) end
        else
            Events.Off(e, "adua_plates")
        end
    end
end

-- The engine's place: the box, the cells while editing, then the containers.
-- On enemy nameplates the box is the editor's stand-in (one plate's worth of
-- cells, so the group can be found, sized and given conditions); in play the
-- group frame hides and only the plates' rows show.
function UA.Place(g, gf, editMode)
    local cfg = UA.Config(g)
    local p = UA.Plan(g, cfg)
    gf:SetSize(p.boxW, p.boxH)
    UA.placed[g.id] = gf
    UA.Marks(gf, p, editMode)
    if cfg.plates then gf:SetShown(editMode) end
    local rt = UA.runtimes[g.id] or UA.Build(g)
    if rt then
        local G = NS.DriverAuraGroups
        rt.mode = cfg.plates and "plates" or "unit"
        rt.pin = { edge = cfg.edge, x = cfg.x, y = cfg.y }
        UA.Pool(g, rt, cfg)
        if not cfg.plates then UA.UnbindAll(rt) end
        UA.AddDebuffs(g, rt, cfg)
        UA.Layout(rt, gf, p, cfg)
        UA.Push(g, rt)
        if G.StyleButtons(rt) then UA.pending = true end
        if cfg.plates then
            UA.BindAll(g, rt, gf)
        else
            -- live with the window open too: the auras show over the cells
            G.MirrorOnto(rt.cs[1], gf, UA.Drawn(g))
            for i = 2, #rt.cs do rt.cs[i]:Hide() end
        end
    end
    UA.ArmSwaps()
    UA.ArmPlates()
end

function UA.Release(g)
    local gid = g.id
    UA.placed[gid] = nil
    local rt = UA.runtimes[gid]
    if rt then
        UA.UnbindAll(rt)
        for _, c in ipairs(rt.cs) do c:Hide() end
    end
    local E = NS.LayoutEngine
    local gf = E and E.GetGroupFrame and E.GetGroupFrame(gid)
    if gf and gf._adUAMarks then gf._adUAMarks:Hide() end
    UA.ArmSwaps()
    UA.ArmPlates()
end

-- True while the group's first container, or its debuff half, waits for
-- combat to end or auras to turn plain (the options window says so).
function UA.Waiting(g)
    if g == nil then return false end
    local rt = UA.runtimes[g.id]
    if rt == nil then return UA.blocked[g.id] == true end
    local _, _, both = NS.Schema.UnitAuraShape(g)
    return both == true and rt.hasD ~= true
end

-- True while the plate pool is smaller than Nameplates covered.
function UA.PoolShort(g)
    local rt = g and UA.runtimes[g.id]
    return rt ~= nil and rt.short == true
end

-- Unit swaps

-- A swap event listens only while a drawn group follows that unit.
function UA.ArmSwaps()
    local want = {}
    for gid in pairs(UA.placed) do
        local rt = UA.runtimes[gid]
        if rt and UA.SWAP[rt.sent.unit] then want[rt.sent.unit] = true end
    end
    for unit, event in pairs(UA.SWAP) do
        if want[unit] and not UA.armed[unit] and UA.Valid(event) then
            UA.armed[unit] = true
            Events.On(event, "adua_" .. unit, function(_, who) UA.OnSwap(unit, who) end)
        elseif UA.armed[unit] and not want[unit] then
            UA.armed[unit] = nil
            Events.Off(event, "adua_" .. unit)
        end
    end
end

-- UNIT_PET names whose pet changed: another unit's is ignored, and a secret
-- token is never compared, so it counts as yours.
function UA.OnSwap(unit, who)
    if unit == "pet" and who ~= nil and not (issecretvalue and issecretvalue(who)) and who ~= "player" then
        return
    end
    for gid in pairs(UA.placed) do
        local rt = UA.runtimes[gid]
        if rt and rt.sent.unit == unit and rt.c:IsShown() and rt.c.UpdateAllAuras then rt.c:UpdateAllAuras() end
    end
end

-- Settle edges

-- Every drawn plate group asks its plates again (hostility reads secret in
-- combat, so a friendly plate's row showed). A runtime its place has not
-- reached yet (no pin) waits for the rebuild UA.pending brings.
function UA.RebindPlates()
    for gid, gf in pairs(UA.placed) do
        local rt, g = UA.runtimes[gid], Store.Get(gid)
        if rt and g and rt.mode == "plates" and rt.pin then UA.BindAll(g, rt, gf) end
    end
end

-- Combat end and loading screens: the plates are asked again a frame later
-- (the engine no longer rebuilds at combat end), and a rebuild lands what
-- waited; secrecy can lift a beat after combat, so one more try a second later.
function UA.Settle()
    Events.Coalesce("adua_rebind", UA.RebindPlates)
    if not UA.pending then return end
    UA.pending = false
    local E = NS.LayoutEngine
    if not E then return end
    E.QueueRebuild()
    C_Timer.After(1, function()
        if UA.pending and not InCombatLockdown() then
            UA.pending = false
            E.QueueRebuild()
        end
    end)
end

-- A deleted group is never released by the engine, and its containers are not
-- the group frame's children.
function UA.Sweep()
    for gid in pairs(UA.runtimes) do
        local g = Store.Get(gid)
        if not (g and Store.ShowsAll(g)) then UA.Release(g or { id = gid }) end
    end
end

-- Load window: every saved group that shows all auras gets its containers
-- now, the one time creation is legal in combat or an instance.
function UA.PreBuild()
    if not UA.Available() then return end
    for _, layout in ipairs(Store.Layouts()) do
        for _, g in ipairs((Store.ChildrenOf(layout))) do
            if Store.ShowsAll(g) then
                local rt = UA.Build(g)
                if rt then
                    local cfg = UA.Config(g)
                    UA.Pool(g, rt, cfg)
                    UA.AddDebuffs(g, rt, cfg)
                end
            end
        end
    end
end

Events.On("PLAYER_LOGIN", "adua_lw", function() UA.loadWindowOver = true end)
Events.On("PLAYER_REGEN_ENABLED", "adua", UA.Settle)
Events.On("PLAYER_ENTERING_WORLD", "adua", UA.Settle)
Events.OnMessage("AD_DIRTY", "adua", function() Events.Coalesce("adua_sweep", UA.Sweep) end)
-- after every visibility pass: the containers follow their group frame's alpha
Events.OnMessage("AD_VISIBILITY", "adua", function()
    local G = NS.DriverAuraGroups
    for gid, gf in pairs(UA.placed) do
        local rt, g = UA.runtimes[gid], Store.Get(gid)
        if rt and g and G then
            if rt.mode == "plates" then
                for i = 1, #rt.cs do
                    if rt.bound[i] then UA.MirrorPlate(g, rt, i, gf) end
                end
            else
                G.MirrorOnto(rt.cs[1], gf, UA.Drawn(g))
            end
        end
    end
end)

if NS.LayoutEngine and NS.LayoutEngine.RegisterGroupClaim then
    NS.LayoutEngine.RegisterGroupClaim({ claims = UA.Claims, place = UA.Place, release = UA.Release })
end
