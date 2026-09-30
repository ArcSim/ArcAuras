-- Group Buff icons: how many in your party or raid have a buff (any rank the
-- icon lists). Between pulls the count is read and shown as have / total; in
-- combat buffs read secret, so the count stops and the icon steps aside.
-- With "Show in combat while anyone lacks it" the game draws it instead. Nothing is read in combat.
-- Called through Driver.Attach / Detach / Refeed in AD_DriverCooldown.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local GB = {}
NS.DriverGroupBuff = GB

GB.EVENTS = { "UNIT_AURA", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "UNIT_HEALTH",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
-- A raid layer holds this many members, each owning every PER-th stripe of
-- its icon, so one member's lack shows the whole icon, faint.
GB.PER = 5
-- A stripe's height in UI units.
GB.STRIPE = 2
-- Secrecy can lift a moment after combat ends: the count is read again then.
GB.RETRY = { 0.5, 2 }
GB.attached = {}   -- [iconId] = { rec, frame, roster, state, have, total, sets, slotsSig }
GB.sets = {}       -- [iconId] = { party = set, raid = set }, kept: engine frames cannot go
GB.dirty = {}      -- units whose buffs changed since the last flush
GB.full = false    -- a whole recount is due
GB.dead = {}       -- [unit] = the last dead read, so only a death or a revive recounts
GB.inCombat = InCombatLockdown() and true or false

local UNIT_OK = { player = true }
for i = 1, 4 do UNIT_OK["party" .. i] = true end
for i = 1, 40 do UNIT_OK["raid" .. i] = true end

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function AurasSecret()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    if not Plain(v) then return true end
    return v == true
end

function GB.IDs(rec)
    local DA = NS.DriverAura
    return (DA and DA.SpellIDList) and DA.SpellIDList(rec.driver or {}) or {}
end

-- The group now: a raid's raid1..N (you among them), else you and party1-4;
-- nil while the roster reads secret. Second value: a raid.
function GB.Units()
    local raid = IsInRaid and IsInRaid() or false
    if not Plain(raid) then return nil end
    local out = {}
    if raid then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if not Plain(n) then return nil end
        for i = 1, math.min(40, n) do out[i] = "raid" .. i end
    else
        out[1] = "player"
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        if not Plain(n) then return nil end
        for i = 1, math.min(4, n) do out[#out + 1] = "party" .. i end
    end
    return out, raid == true
end

-- Counted: there, online and alive. nil while any of it reads secret.
function GB.Counted(unit)
    local ex = UnitExists(unit)
    if not Plain(ex) then return nil end
    if not ex then return false end
    local on, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
    if not (Plain(on) and Plain(dead)) then return nil end
    return on == true and not dead
end

-- Carries any of the ids: true or false, nil while the answer is secret.
function GB.Has(unit, ids)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not get then return nil end
    for _, id in ipairs(ids) do
        local a = get(unit, id)
        if a ~= nil then
            if not Plain(a) then return nil end
            return true
        end
    end
    return false
end

-- One member's state: "has", "lacks", "out" (not counted), or nil (secret).
local function Read(unit, ids)
    local c = GB.Counted(unit)
    if c == nil then return nil end
    if not c then return "out" end
    local h = GB.Has(unit, ids)
    if h == nil then return nil end
    return h and "has" or "lacks"
end

local function Tally(a)
    local have, total = 0, 0
    for _, u in ipairs(a.roster) do
        local s = a.state[u]
        if s == "has" then have, total = have + 1, total + 1
        elseif s == "lacks" then total = total + 1 end
    end
    a.have, a.total = have, total
end

-- The whole group read again; a secret answer keeps the last count.
function GB.Recount(a)
    if AurasSecret() then return end
    local ids = GB.IDs(a.rec)
    local units = GB.Units()
    if #ids == 0 or not units then return end
    local state = {}
    for _, u in ipairs(units) do
        local s = Read(u, ids)
        if s == nil then return end
        state[u] = s
    end
    a.roster, a.state = units, state
    Tally(a)
end

-- Only the members whose buffs changed.
function GB.Update(a, dirty)
    if AurasSecret() or not a.roster then return end
    local ids = GB.IDs(a.rec)
    local any = false
    for u in pairs(dirty) do
        if a.state[u] ~= nil then
            local s = Read(u, ids)
            if s == nil then return end
            if a.state[u] ~= s then
                a.state[u] = s
                any = true
            end
        end
    end
    if any then Tally(a) end
end

-- The count's words, as groupBuff.countShows picks: have / total, how many
-- lack it, or have.
function GB.CountText(rec, have, total)
    local shows = Store.Resolve(rec, "groupBuff", "countShows")
    if shows == "missing" then return tostring(total - have) end
    if shows == "have" then return tostring(have) end
    return have .. "/" .. total
end

-- The editor preview's stand-in count: four of five.
function GB.SampleText(rec) return GB.CountText(rec, 4, 5) end

-- The icon: its count between pulls, and its two states (someone lacks it,
-- everyone has it). In combat the holder steps aside for the layers.
function GB.Paint(a)
    local rec, f = a.rec, a.frame
    f._adGBHidden = GB.inCombat or nil
    local text = ""
    if not GB.inCombat and a.total and Store.Resolve(rec, "text", "stackText") ~= false then
        text = GB.CountText(rec, a.have, a.total)
    end
    f.stackText:SetText(text)
    local all = a.total ~= nil and a.have >= a.total
    Factory.SetState(f, rec, all, all)
    GB.SyncLayers(a)
end

function GB.Feed(a)
    GB.Recount(a)
    GB.Paint(a)
end

function GB.Flush()
    local full, dirty = GB.full, GB.dirty
    GB.full, GB.dirty = false, {}
    for _, a in pairs(GB.attached) do
        if full or not a.roster then GB.Recount(a) else GB.Update(a, dirty) end
        GB.Paint(a)
    end
end

function GB.Mark(unit)
    if unit then GB.dirty[unit] = true else GB.full = true end
    Events.Coalesce("adgb_flush", GB.Flush)
end

-- The combat layers
-- Built out of combat and kept for the icon's life; no one who is not there reads as missing.

local function Eraser(parent, drawLayer)
    local t = parent:CreateTexture(nil, drawLayer or "BACKGROUND", nil, drawLayer and 7 or -8)
    t:SetColorTexture(0, 0, 0, 0)
    t:SetBlendMode("DISABLE")
    return t
end

-- A member's share: the whole layer, or its stripes (every PER-th, from its
-- place k), laid on `anchor`. box: the layer's height, and how far its look
-- reaches past it (mx across, my up and down), all of which the share covers.
-- `pool` keeps the textures.
local BOX0 = { h = 36, mx = 0, my = 0 }
local function LayShare(pool, parent, anchor, kind, k, box, drawLayer)
    local mx, my = box.mx or 0, box.my or 0
    local n = 0
    if kind == "party" then
        n = 1
        local t = pool[1] or Eraser(parent, drawLayer)
        pool[1] = t
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -mx, my)
        t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", mx, -my)
        t:Show()
    else
        local s = GB.STRIPE
        local h = box.h + 2 * my
        local j = k - 1
        while j * s < h do
            n = n + 1
            local t = pool[n] or Eraser(parent, drawLayer)
            pool[n] = t
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -mx, my - j * s)
            t:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", mx, my - j * s)
            t:SetHeight(math.min(s, h - j * s))
            t:Show()
            j = j + GB.PER
        end
    end
    for i = n + 1, #pool do pool[i]:Hide() end
end

local function IsAccessible(b)
    local DA = NS.DriverAura
    if DA and DA.IsAccessible then return DA.IsAccessible(b) end
    return b ~= nil
end

-- Its engine button's level is set outright: children keep theirs when the layer's level moves.
local function StyleButton(slot, layer, set)
    local b = slot.button
    if not (b and IsAccessible(b)) then return false end
    local st = layer.stage
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", st, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", 0, 0)
    b:SetFrameStrata(st:GetFrameStrata())
    b:SetFrameLevel(st:GetFrameLevel() + 2)
    slot.share = slot.share or {}
    LayShare(slot.share, b, b, set.kind, slot.k, set.box or BOX0)
    return true
end

function GB.BuildSet(a, kind)
    local DA = NS.DriverAura
    if not (DA and DA.CreateIconContainer and DA.IncludeMap and DA.EraserAvailable
        and DA.EraserAvailable()) then return nil end
    if GB.inCombat or InCombatLockdown() or AurasSecret() then return nil end
    local set = { kind = kind, layers = {}, parked = false }
    local units = {}
    if kind == "party" then
        units = { "player", "party1", "party2", "party3", "party4" }
    else
        for i = 1, 40 do units[i] = "raid" .. i end
    end
    local per = (kind == "party") and 1 or GB.PER
    local ids = DA.IncludeMap(a.rec.driver or {})
    set.sig = DA.FilterSig(ids)
    for li = 1, math.ceil(#units / per) do
        local st = CreateFrame("Frame", nil, UIParent)
        st:SetSize(1, 1)
        st:SetPoint("TOP", UIParent, "TOP", 0, -80)
        st:SetFlattensRenderLayers(true)
        -- Buffer on before any eraser can show.
        st:SetIsFrameBuffer(true)
        st:SetAlpha(0)
        local art = st:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints()
        local layer = { stage = st, art = art, slots = {} }
        for k = 1, per do
            local unit = units[(li - 1) * per + k]
            if unit then
                local slot = { unit = unit, k = k, pre = {} }
                local c = DA.CreateIconContainer(unit, st)
                if c then
                    slot.container = c
                    slot.key = "adgb" .. tostring(a.rec.id) .. "_" .. unit
                    c:AddAuraSlot(slot.key, "HELPFUL", {
                        maxFrameCount = 1,
                        initializeFrame = function(b)
                            b:EnableMouse(false)
                            slot.button = b
                            StyleButton(slot, layer, set)
                        end,
                        candidateFilters = { includeSpellIDs = ids },
                    })
                end
                layer.slots[#layer.slots + 1] = slot
            end
        end
        set.layers[#set.layers + 1] = layer
    end
    return set
end

-- Park or re-aim every slot of a set: the never-matching id while parked.
local function AimSet(set, rec, parked)
    local DA = NS.DriverAura
    local ids = parked and { [0] = true } or DA.IncludeMap(rec.driver or {})
    local sig = DA.FilterSig(ids)
    if set.sig == sig then return end
    set.sig = sig
    for _, layer in ipairs(set.layers) do
        for _, slot in ipairs(layer.slots) do
            if slot.container then
                slot.container:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = ids })
            end
        end
    end
end

-- The custom texts a layer carries: those shown while someone lacks it.
function GB.LayerTexts(rec)
    local out = {}
    for _, suf in ipairs({ "", "2", "3" }) do
        local t = Store.Resolve(rec, "label", "labelText" .. suf)
        if t ~= nil and t ~= "" and Store.Resolve(rec, "label", "labelWhen" .. suf) ~= "has" then
            out[#out + 1] = suf
        end
    end
    return out
end

-- How far a layer's look reaches past the icon (an outside border, the
-- shadow, the texts' offsets and words), with a unit to spare: mx across
-- (free, the stripes are full width), my up and down.
function GB.Reach(rec, w, h, kS, texts)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local art = R("appearance", "forceHideIcon") ~= true
    local mx, my = 1, 1
    if art and R("appearance", "borderEnabled") then
        local out = math.max(0, -(R("appearance", "borderInset") or 0)) + 1
        mx, my = math.max(mx, out), math.max(my, out)
    end
    if art and R("appearance", "shadowEnabled") == true then
        local size = R("appearance", "shadowSize") or 1
        mx = math.max(mx, math.ceil(w * 0.18 * size) + 1)
        my = math.max(my, math.ceil(h * 0.16 * size) + 1)
    end
    for _, suf in ipairs(texts) do
        local t = R("label", "labelText" .. suf) or ""
        local size = (R("label", "labelSize" .. suf) or 12) * kS
        mx = math.max(mx, math.ceil(math.abs(R("label", "labelX" .. suf) or 0) * kS + math.max(#t * size * 0.7, size)))
        my = math.max(my, math.ceil(math.abs(R("label", "labelY" .. suf) or 0) * kS + size * 1.5))
    end
    return mx, my
end

-- A layer wears the icon's look while someone lacks it, as the holder does (Factory.ApplyStyle).
local function PaintLook(layer, rec, w, h, kS, texts)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local st, art = layer.stage, layer.art
    local hideArt = R("appearance", "forceHideIcon") == true
    local alpha = R("states", "readyAlpha") or 1
    local textA = (alpha > 0 and R("states", "preserveDurationText") ~= false) and 1 or alpha
    art:SetTexture(Factory.GetTexture(rec))
    if Factory.IconTexCoords then art:SetTexCoord(Factory.IconTexCoords(rec)) end
    local pad = (R("appearance", "padding") or 0) * kS
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", st, "TOPLEFT", pad, -pad)
    art:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", -pad, pad)
    art:SetAlpha(alpha)
    art:SetShown(not hideArt)
    if Factory.ApplyShadow then
        Factory.ApplyShadow(st, "_adShadow", art, rec, math.max(1, w - 2 * pad), math.max(1, h - 2 * pad),
            alpha, R("appearance", "shadowEnabled") == true and not hideArt)
    end
    local edges = layer.edges
    if R("appearance", "borderEnabled") and not hideArt and Factory.PaintBorderEdges then
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
        Factory.PaintBorderEdges(edges, st, rec, alpha)
    elseif edges then
        for _, t in pairs(edges) do t:Hide() end
    end
    local want = {}
    for _, suf in ipairs(texts) do want[suf] = true end
    layer.texts = layer.texts or {}
    for i, suf in ipairs({ "", "2", "3" }) do
        local fs = layer.texts[i]
        if want[suf] and Factory.StyleLabel then
            if not fs then
                fs = st:CreateFontString(nil, "OVERLAY")
                fs:SetDrawLayer("OVERLAY", 6)
                layer.texts[i] = fs
            end
            Factory.StyleLabel(fs, rec, suf, kS, st)
            fs:SetAlpha(textA)
            fs:Show()
        elseif fs then
            fs:SetText("")
            fs:Hide()
        end
    end
end

-- Stands the set on the holder at its size and level, dresses each layer in
-- the icon's look, and lays the shares again, as far as the look reaches
-- (buttons only when reachable: out of combat).
local function PlaceSet(a, set)
    local f, rec = a.frame, a.rec
    local h = f:GetHeight()
    if type(h) ~= "number" or not Plain(h) or h <= 0 then h = 36 end
    local w = f:GetWidth()
    if type(w) ~= "number" or not Plain(w) or w <= 0 then w = h end
    local kS = h / 36
    local texts = GB.LayerTexts(rec)
    local mx, my = GB.Reach(rec, w, h, kS, texts)
    set.box = { h = h, mx = mx, my = my }
    local lvl = f:GetFrameLevel()
    if type(lvl) ~= "number" or not Plain(lvl) then lvl = 1 end
    for _, layer in ipairs(set.layers) do
        local st = layer.stage
        st:ClearAllPoints()
        st:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        st:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        st:SetFrameStrata(f:GetFrameStrata())
        st:SetFrameLevel(lvl)
        PaintLook(layer, rec, w, h, kS, texts)
        for _, slot in ipairs(layer.slots) do
            if set.kind == "raid" then LayShare(slot.pre, st, st, "raid", slot.k, set.box, "OVERLAY") end
            StyleButton(slot, layer, set)
        end
    end
end

-- Which slots hold a member now. Out of combat every read is plain; in combat
-- the group's size still is, and a unit's online flag when it reads plain.
local function Present(unit, raid, n)
    local idx = tonumber(unit:match("%d+$"))
    if unit == "player" then return true end
    if (raid and unit:sub(1, 4) ~= "raid") or (not raid and unit:sub(1, 5) ~= "party") then return false end
    if idx and n and idx > n then return false end
    local on = UnitIsConnected(unit)
    if on == nil or not Plain(on) then return true end
    return on == true
end

local function GroupSize(raid)
    local n
    if raid then n = GetNumGroupMembers and GetNumGroupMembers() else
        n = GetNumSubgroupMembers and GetNumSubgroupMembers() end
    if not Plain(n) then return nil end
    return tonumber(n)
end

-- The layers' alpha: the holder's fade in combat when switched on, for the set this group needs.
function GB.SyncLayers(a)
    local sets = GB.sets[a.rec.id]
    if not sets then return end
    local want = Store.Resolve(a.rec, "groupBuff", "combatShow") == true
    local raid = IsInRaid and IsInRaid() or false
    if not Plain(raid) then raid = a.raid or false end
    a.raid = raid
    local active = want and (raid and sets.raid or sets.party) or nil
    local ea = a.frame:GetEffectiveAlpha()
    if type(ea) ~= "number" or not Plain(ea) then ea = 1 end
    local shown = GB.inCombat and a.frame:IsVisible()
    local n = GroupSize(raid)
    for kind, set in pairs(sets) do
        local on = set == active
        for _, layer in ipairs(set.layers) do
            local any = false
            for _, slot in ipairs(layer.slots) do
                local here = on and Present(slot.unit, raid, n)
                if here then any = true end
                if set.kind == "raid" then
                    for _, t in ipairs(slot.pre) do t:SetShown(not here) end
                end
            end
            layer.stage:SetAlpha((on and shown and any) and ea or 0)
        end
    end
end

-- The sets this icon needs, built and aimed out of combat.
function GB.EnsureSets(a)
    if GB.inCombat or InCombatLockdown() then
        a.setsPending = true
        return
    end
    a.setsPending = nil
    local want = Store.Resolve(a.rec, "groupBuff", "combatShow") == true
    local sets = GB.sets[a.rec.id]
    if want then
        local raid = IsInRaid and IsInRaid() or false
        if not Plain(raid) then return end
        local kind = raid and "raid" or "party"
        sets = sets or {}
        GB.sets[a.rec.id] = sets
        if not sets[kind] then
            sets[kind] = GB.BuildSet(a, kind)
            if not sets[kind] then a.setsPending = true end
        end
    end
    for kind, set in pairs(sets or {}) do
        local raid = IsInRaid and IsInRaid() or false
        local live = want and Plain(raid) and ((raid and kind == "raid") or (not raid and kind == "party"))
        AimSet(set, a.rec, not live)
        if live then PlaceSet(a, set) end
    end
end

-- A roster change: unit tokens now point at other members.
function GB.RefreshContainers()
    for _, sets in pairs(GB.sets) do
        for _, set in pairs(sets) do
            for _, layer in ipairs(set.layers) do
                for _, slot in ipairs(layer.slots) do
                    local c = slot.container
                    if c and type(c.UpdateAllAuras) == "function" then c:UpdateAllAuras() end
                end
            end
        end
    end
end

-- Events

function GB.OnEvent(ev, unit)
    if ev == "PLAYER_REGEN_DISABLED" then
        GB.inCombat = true
        for _, a in pairs(GB.attached) do GB.Paint(a) end
        return
    end
    if ev == "PLAYER_REGEN_ENABLED" then
        GB.inCombat = false
        for _, a in pairs(GB.attached) do
            if a.setsPending then GB.EnsureSets(a) end
        end
        GB.Mark(nil)
        for _, t in ipairs(GB.RETRY) do C_Timer.After(t, function() GB.Mark(nil) end) end
        return
    end
    if ev == "GROUP_ROSTER_UPDATE" then
        GB.RefreshContainers()
        if not GB.inCombat then
            for _, a in pairs(GB.attached) do GB.EnsureSets(a) end
        end
        GB.Mark(nil)
        return
    end
    if ev == "PLAYER_ENTERING_WORLD" then
        GB.Mark(nil)
        return
    end
    if not UNIT_OK[unit] then return end
    if GB.inCombat then
        -- buffs are secret now; only an offline flag moves the layers
        if ev == "UNIT_CONNECTION" then
            for _, a in pairs(GB.attached) do GB.SyncLayers(a) end
        end
        return
    end
    if ev == "UNIT_HEALTH" then
        -- only a death or a revive changes the count
        local dead = UnitIsDeadOrGhost(unit)
        if not Plain(dead) or GB.dead[unit] == dead then return end
        GB.dead[unit] = dead
    end
    GB.Mark(unit)
end

-- Forever throws on registering an event it lacks, so each is probed.
function GB.EnsureEvents()
    if GB.live then return end
    GB.live = true
    for _, ev in ipairs(GB.EVENTS) do
        if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
            Events.On(ev, "adgroupbuff", GB.OnEvent)
        end
    end
    -- a group, layout or condition fade reaches the layers
    Events.OnMessage("AD_VISIBILITY", "adgroupbuff", function()
        for _, a in pairs(GB.attached) do GB.SyncLayers(a) end
    end)
end

-- A hidden holder hides its layers; shown again, they take its fade back.
local function HookHolder(f)
    if f._adGBHooked then return end
    f._adGBHooked = true
    f:HookScript("OnHide", function(self)
        local a = GB.attached[self._adRecId]
        if a and a.frame == self then GB.SyncLayers(a) end
    end)
    f:HookScript("OnShow", function(self)
        local a = GB.attached[self._adRecId]
        if a and a.frame == self then GB.SyncLayers(a) end
    end)
end

function GB.Attach(rec, f)
    local a = GB.attached[rec.id] or { state = {} }
    GB.attached[rec.id] = a
    a.rec, a.frame = rec, f
    GB.EnsureEvents()
    HookHolder(f)
    GB.EnsureSets(a)
    GB.Feed(a)
end

function GB.Detach(id)
    local a = GB.attached[id]
    if not a then return end
    GB.attached[id] = nil
    local sets = GB.sets[id]
    for _, set in pairs(sets or {}) do
        for _, layer in ipairs(set.layers) do layer.stage:SetAlpha(0) end
        if not InCombatLockdown() then AimSet(set, a.rec, true) end
    end
    if next(GB.attached) or not GB.live then return end
    GB.live = false
    for _, ev in ipairs(GB.EVENTS) do Events.Off(ev, "adgroupbuff") end
end

function GB.Refeed(id)
    local a = GB.attached[id]
    if a then GB.Feed(a) end
end

-- The tooltip's lines under the buff's name: the last count, and who lacks it
-- when names read plain (between pulls).
function GB.TooltipLines(rec)
    local a = GB.attached[rec.id]
    if not (a and a.total) then
        GameTooltip:AddLine("Counts your party or raid between pulls.", 1, 1, 1, true)
        return
    end
    GameTooltip:AddLine(("%d of %d have it"):format(a.have, a.total), 1, 1, 1)
    if GB.inCombat then
        GameTooltip:AddLine("In combat the count waits for the fight to end.", 0.7, 0.7, 0.7, true)
        return
    end
    local names = {}
    for _, u in ipairs(a.roster or {}) do
        if a.state[u] == "lacks" then
            local nm = UnitName(u)
            if type(nm) == "string" and Plain(nm) then names[#names + 1] = nm end
        end
    end
    if #names > 0 then
        GameTooltip:AddLine("Missing: " .. table.concat(names, ", "), 1, 0.82, 0, true)
    end
end
