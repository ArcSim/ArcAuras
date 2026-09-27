-- Totem tracking: which of your totems sits in which slot, and the pulse bar.
-- The totem icon feed in AD_DriverCooldown asks SlotFor which slot to show and
-- hands every fed icon to Pulse; this file owns the pairing and the bars.
-- In combat a slot's totem info is secret, so a slot is named by your own cast
-- (its spell ID stays plain) landing with the slot's update, and every time is
-- our own GetTime stamp, never a totem number.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local DT = {}
NS.DriverTotem = DT

DT.SLOTS = 4
-- A cast and the slot update it causes land within this many seconds.
DT.PAIR_WINDOW = 0.5
-- Seconds between pulses, keyed by the rank 1 spell ID; other ranks match by
-- name, and a pulse setting on the icon wins.
DT.PULSE_EVERY = {
    [8143] = 3,    -- Tremor Totem
    [2484] = 3,    -- Earthbind Totem
    [16190] = 3,   -- Mana Tide Totem
    [8190] = 2,    -- Magma Totem
    [5675] = 2,    -- Mana Spring Totem
    [5394] = 2,    -- Healing Stream Totem
    [8166] = 5,    -- Poison Cleansing Totem
    [8170] = 5,    -- Disease Cleansing Totem
}
-- What a shaman's totem slots hold on Forever (FIRE_TOTEM_SLOT .. AIR_TOTEM_SLOT),
-- for hints only: a slot is a slot, whatever the game puts in it.
DT.ELEMENTS = { "Fire", "Earth", "Water", "Air" }

DT.slot = {}       -- [slot] = { name = totem name or nil, litAt = GetTime() }
DT.pending = {}    -- [slot] = when it lit with no cast to name it yet
DT.cast = nil      -- { name, at }: a totem cast still waiting for its slot
DT.shadow = {}     -- [slot] = hidden Cooldown whose IsShown() says a totem is down
DT.recs = {}       -- [iconId] = rec, the attached totem icons
DT.tracked = {}    -- [spell name] = true, the totems icons follow by spell

function DT.SlotName(slot) return "Slot " .. tostring(slot) end

-- "1 Fire, 2 Earth, 3 Water, 4 Air" on Forever, for a tooltip; nil elsewhere.
function DT.ElementHint()
    if not NS.IsForever then return nil end
    local parts = {}
    for i, el in ipairs(DT.ELEMENTS) do parts[i] = i .. " " .. el end
    return table.concat(parts, ", ")
end

function DT.SpellName(id)
    if not id or (issecretvalue and issecretvalue(id)) then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
end

-- Totem names seen in a plain read: they let a cast in combat count as a totem.
function DT.Known()
    local u = Store.UI()
    u.totemNames = u.totemNames or {}
    return u.totemNames
end

function DT.PulseByName()
    local map = DT.pulseNames
    if map and next(map) then return map end
    map = {}
    for id, every in pairs(DT.PULSE_EVERY) do
        local nm = DT.SpellName(id)
        if nm then map[nm] = every end
    end
    DT.pulseNames = map
    return map
end

function DT.IsTotemName(name)
    if not name then return false end
    return DT.Known()[name] == true or DT.tracked[name] == true or DT.PulseByName()[name] ~= nil
end

function DT.Shadow(slot)
    local w = DT.shadow[slot]
    local D = NS.DriverCooldown
    if not w and D and D.MakeShadow then
        w = D.MakeShadow()
        DT.shadow[slot] = w
    end
    return w
end

-- The duration object is the one totem read that stays usable in combat.
function DT.Active(slot)
    local w = DT.Shadow(slot)
    if not w then return false end
    local dur = GetTotemDuration and GetTotemDuration(slot)
    if dur and w.SetCooldownFromDurationObject then
        w:SetCooldownFromDurationObject(dur, true)
    else
        w:Clear()
    end
    return w:IsShown() == true
end

-- The slot's totem name when the game lets it be read, false for a plain empty
-- slot, nil when the answer is secret.
function DT.ReadSlot(slot)
    if not GetTotemInfo then return nil end
    local have, name = GetTotemInfo(slot)
    if issecretvalue and (issecretvalue(have) or issecretvalue(name)) then return nil end
    if have ~= true or type(name) ~= "string" or name == "" then return false end
    return name
end

function DT.Changed()
    local D = NS.DriverCooldown
    if D and D.FeedTotems then Events.Coalesce("adcd_feedtotems", D.FeedTotems) end
end

-- Every slot from scratch, from plain reads where the game allows them.
function DT.ReadAll()
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot] or {}
        DT.slot[slot] = s
        if not DT.Active(slot) then
            s.name, s.litAt = nil, nil
            DT.pending[slot] = nil
        else
            local name = DT.ReadSlot(slot)
            if name then
                s.name = name
                DT.Known()[name] = true
                DT.pending[slot] = nil
                local _, _, start = GetTotemInfo(slot)
                if not (issecretvalue and issecretvalue(start)) and type(start) == "number" then
                    s.litAt = start
                end
            end
            s.litAt = s.litAt or GetTime()
        end
    end
    DT.Changed()
end

function DT.OnSlotUpdate(slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > DT.SLOTS then return end
    local now = GetTime()
    local s = DT.slot[slot] or {}
    DT.slot[slot] = s
    if not DT.Active(slot) then
        s.name, s.litAt = nil, nil
        DT.pending[slot] = nil
        DT.Changed()
        return
    end
    s.litAt = now
    local name = DT.ReadSlot(slot)
    if name then
        s.name = name
        DT.Known()[name] = true
        DT.pending[slot] = nil
    else
        -- secret: the cast that just landed names it, or the next one does
        local c = DT.cast
        if c and now - c.at <= DT.PAIR_WINDOW then
            s.name = c.name
            DT.cast = nil
            DT.pending[slot] = nil
        else
            s.name = nil
            DT.pending[slot] = now
        end
    end
    DT.Changed()
end

-- Only casts of known totems pair, so an unrelated spell landing in the same
-- half second can never name a slot.
function DT.OnCast(spellID)
    local name = DT.SpellName(spellID)
    if not DT.IsTotemName(name) then return end
    local now = GetTime()
    for slot, t in pairs(DT.pending) do
        DT.pending[slot] = nil
        if now - t <= DT.PAIR_WINDOW then
            local s = DT.slot[slot]
            if s then s.name = name end
            DT.cast = nil
            DT.Changed()
            return
        end
    end
    DT.cast = { name = name, at = now }
end

-- The slot an icon shows: a spell-tracked icon follows its totem into
-- whichever slot holds it (nil while it is not down), else its own slot.
function DT.SlotFor(rec)
    local d = (rec and rec.driver) or {}
    local want = d.spellID and DT.SpellName(d.spellID)
    if not want then return d.slot or 1, false end
    for slot = 1, DT.SLOTS do
        local s = DT.slot[slot]
        if s and s.name == want then return slot, true end
    end
    return nil, true
end

function DT.Track(rec)
    local d = rec.driver or {}
    local nm = d.spellID and DT.SpellName(d.spellID)
    if nm then DT.tracked[nm] = true end
end

function DT.Attach(rec)
    DT.recs[rec.id] = rec
    DT.Track(rec)
    if DT.live then return end
    DT.live = true
    Events.On("PLAYER_TOTEM_UPDATE", "adtotem", function(_, slot) DT.OnSlotUpdate(slot) end)
    Events.On("UNIT_SPELLCAST_SUCCEEDED", "adtotem", function(_, unit, _, spellID)
        if unit == "player" then DT.OnCast(spellID) end
    end)
    Events.On("PLAYER_REGEN_ENABLED", "adtotem", DT.ReadAll)
    Events.On("PLAYER_ENTERING_WORLD", "adtotem", DT.ReadAll)
    DT.ReadAll()
end

function DT.Detach(id, f)
    DT.recs[id] = nil
    if f then DT.StopPulse(f) end
    if next(DT.recs) or not DT.live then return end
    DT.live = false
    Events.Off("PLAYER_TOTEM_UPDATE", "adtotem")
    Events.Off("UNIT_SPELLCAST_SUCCEEDED", "adtotem")
    Events.Off("PLAYER_REGEN_ENABLED", "adtotem")
    Events.Off("PLAYER_ENTERING_WORLD", "adtotem")
    wipe(DT.tracked)
end

-- Pulse bar

-- Seconds between pulses for this icon: its own setting, else the totem's.
function DT.PulseEvery(rec, slot)
    local manual = tonumber(Store.Resolve(rec, "pulse", "pulseInterval"))
    if manual and manual > 0 then return manual end
    local d = rec.driver or {}
    local name = (d.spellID and DT.SpellName(d.spellID))
        or (slot and DT.slot[slot] and DT.slot[slot].name)
    return name and DT.PulseByName()[name]
end

function DT.StopPulse(f)
    f._adPulseToken = (f._adPulseToken or 0) + 1
    if f._adPulse then f._adPulse:Hide() end
end

function DT.PulseBar(f)
    local b = f._adPulse
    if b then return b end
    b = CreateFrame("StatusBar", nil, f)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.55)
    b:Hide()
    f._adPulse = b
    return b
end

-- One timer per bar per pulse, alive only while the bar shows: the widget
-- draws the fill, so nothing runs per frame.
function DT.RunPulse(f, litAt, every)
    local b = f._adPulse
    if not (b and b:IsShown()) then return end
    local now = GetTime()
    local k = math.max(0, math.floor((now - litAt) / every))
    local last = litAt + k * every
    local K = NS.Bars and NS.Bars.Kit
    local fed = false
    if C_DurationUtil and C_DurationUtil.CreateDuration and K and K.FeedStatusBarTimer then
        b._adDur = b._adDur or C_DurationUtil.CreateDuration()
        b._adDur:SetTimeFromStart(last, every)
        fed = K.FeedStatusBarTimer(b, b._adDur, false, false)
    end
    if not fed then b:SetValue(math.min(1, (now - last) / every)) end
    local token = (f._adPulseToken or 0) + 1
    f._adPulseToken = token
    C_Timer.After(math.max(0.05, last + every - now + 0.01), function()
        if f._adPulseToken ~= token then return end
        DT.RunPulse(f, litAt, every)
    end)
end

function DT.Pulse(f, rec, slot, active)
    if not (f and rec) then return end
    local R = function(k) return Store.Resolve(rec, "pulse", k) end
    local s = slot and DT.slot[slot]
    local every = active and R("pulseShow") == true and DT.PulseEvery(rec, slot)
    if not (every and s and s.litAt) then
        DT.StopPulse(f)
        return
    end
    local b = DT.PulseBar(f)
    local px = (NS.AT and NS.AT.Px and NS.AT.Px(f)) or 1
    local h = math.max(2, math.floor((tonumber(R("pulseHeight")) or 3) + 0.5)) * px
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(h)
    local c = R("pulseColor") or { 1, 0.82, 0.2, 1 }
    b:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if f.cooldown then b:SetFrameLevel(f.cooldown:GetFrameLevel() + 1) end
    b:Show()
    DT.RunPulse(f, s.litAt, every)
end
