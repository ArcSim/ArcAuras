-- Weapon enchant icons: what is on a weapon (an imbue, a poison, an oil, a
-- stone), with its time left, charges and the missing look.
-- Called through Driver.Attach / Detach / Refeed in AD_DriverCooldown.
-- C_Item.GetWeaponEnchantInfo carries no secret annotation on Forever and the
-- game's own buff frame does arithmetic on it, so it is read plain; a secret
-- answer anyway keeps the last look. The swipe runs on a duration object, so
-- nothing polls.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory

local DE = {}
NS.DriverEnchant = DE

-- slot = Enum.WeaponSlot, inv = the inventory slot for art and tooltips
DE.HANDS = {
    main = { slot = 0, inv = 16, text = "Main Hand" },
    off  = { slot = 1, inv = 17, text = "Off Hand" },
}
DE.EVENTS = { "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED" }
DE.attached = {}   -- [iconId] = { rec, frame, lastOn, token, dur }

function DE.Hand(rec)
    local h = rec and rec.driver and rec.driver.hand
    return DE.HANDS[h] or DE.HANDS.main
end

function DE.InvSlot(rec) return DE.Hand(rec).inv end

local function Plain(...)
    if not issecretvalue then return true end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return false end
    end
    return true
end

-- The enchants on a hand now: a list of { id, left (seconds), charges, icon },
-- empty when bare, nil when the game answers secret.
function DE.ReadHand(handKey)
    local hand = DE.HANDS[handKey] or DE.HANDS.main
    local out = {}
    if C_Item and C_Item.GetWeaponEnchantInfo then
        local list = C_Item.GetWeaponEnchantInfo(hand.slot)
        if list == nil then return out end
        if not Plain(list) then return nil end
        for _, e in ipairs(list) do
            if not Plain(e.hasEnchant, e.timeLeft, e.charges, e.enchantID, e.enchantIconID) then return nil end
            if e.hasEnchant == true then
                local icon = tonumber(e.enchantIconID)
                out[#out + 1] = {
                    id = tonumber(e.enchantID), left = (tonumber(e.timeLeft) or 0) / 1000,
                    charges = tonumber(e.charges) or 0, icon = (icon and icon > 0) and icon or nil,
                }
            end
        end
        return out
    end
    if GetWeaponEnchantInfo then
        local hasM, expM, chM, idM, hasO, expO, chO, idO = GetWeaponEnchantInfo()
        if not Plain(hasM, expM, chM, idM, hasO, expO, chO, idO) then return nil end
        local has, exp, ch, id
        if hand.slot == 0 then has, exp, ch, id = hasM, expM, chM, idM
        else has, exp, ch, id = hasO, expO, chO, idO end
        if has then
            out[1] = { id = tonumber(id), left = (tonumber(exp) or 0) / 1000, charges = tonumber(ch) or 0 }
        end
    end
    return out
end

-- The weapon in a hand, as its item ID, or nil: an empty hand, a shield or a
-- held item takes no enchant.
function DE.WeaponIn(handKey)
    local hand = DE.HANDS[handKey] or DE.HANDS.main
    local id = GetInventoryItemID("player", hand.inv)
    if not Plain(id) or not id then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
        local weapon = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
        if classID ~= nil and Plain(classID) and classID ~= weapon then return nil end
    end
    return id
end

-- The enchant this icon tracks: an entry while it is on, false while it is
-- not, nil while the answer is secret.
function DE.Read(rec)
    local list = DE.ReadHand(rec.driver and rec.driver.hand)
    if list == nil then return nil end
    local want = tonumber(rec.driver and rec.driver.enchantID)
    for _, e in ipairs(list) do
        if not want or want <= 0 or e.id == want then return e end
    end
    return false
end

-- The enchant's full length for the swipe: the longest time left seen, since
-- the game reports only what is left.
function DE.Full(e)
    local u = Store.UI()
    u.enchantMax = u.enchantMax or {}
    local key = e.id or 0
    local m = u.enchantMax[key]
    if not m or e.left > m then
        m = e.left
        u.enchantMax[key] = m
    end
    return m
end

-- One re-read when the enchant should run out, in case no event says so.
function DE.Expiry(a, left)
    a.token = (a.token or 0) + 1
    local token, id = a.token, a.rec.id
    C_Timer.After(math.max(0.1, left + 0.2), function()
        local live = DE.attached[id]
        if live and live.token == token then DE.Feed(live) end
    end)
end

function DE.Feed(a)
    local rec, f = a.rec, a.frame
    local e = DE.Read(rec)
    if e == nil then return end
    local on = e ~= false
    if on then
        if C_DurationUtil and C_DurationUtil.CreateDuration then
            a.dur = a.dur or C_DurationUtil.CreateDuration()
            a.dur:SetTimeFromEnd(GetTime() + e.left, DE.Full(e))
            f.cooldown:SetCooldownFromDurationObject(a.dur, true)
        end
        if Store.Resolve(rec, "text", "stackText") ~= false then
            f.stackText:SetText(e.charges > 0 and e.charges or "")
        end
        DE.Expiry(a, e.left)
    else
        a.token = (a.token or 0) + 1
        f.cooldown:Clear()
        f.stackText:SetText("")
    end
    f.icon:SetTexture(Factory.GetTexture(rec))
    -- a sound on a real change only, never on the first read
    local D = NS.DriverCooldown
    if D and D.PlayAlert and a.lastOn ~= nil and a.lastOn ~= on then
        if on then
            D.PlayAlert(rec, "readySoundEnabled", "readySound")
        else
            D.PlayAlert(rec, "cooldownSoundEnabled", "cooldownSound")
        end
    end
    a.lastOn = on
    Factory.SetState(f, rec, not on, not on)
end

function DE.FeedAll()
    for _, a in pairs(DE.attached) do DE.Feed(a) end
end

-- Forever throws on registering an event it lacks, so each is probed.
function DE.EnsureEvents()
    if DE.live then return end
    DE.live = true
    for _, ev in ipairs(DE.EVENTS) do
        if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) then
            Events.On(ev, "adenchant", function(_, unit)
                if ev == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
                Events.Coalesce("adenchant_feed", DE.FeedAll)
            end)
        end
    end
end

function DE.Attach(rec, f)
    local a = DE.attached[rec.id] or {}
    DE.attached[rec.id] = a
    a.rec, a.frame = rec, f
    DE.EnsureEvents()
    DE.Feed(a)
end

function DE.Detach(id)
    local a = DE.attached[id]
    if not a then return end
    a.token = (a.token or 0) + 1
    DE.attached[id] = nil
    if next(DE.attached) or not DE.live then return end
    DE.live = false
    for _, ev in ipairs(DE.EVENTS) do Events.Off(ev, "adenchant") end
end

function DE.Refeed(id)
    local a = DE.attached[id]
    if a then DE.Feed(a) end
end
