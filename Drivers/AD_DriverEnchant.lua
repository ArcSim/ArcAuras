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

-- The enchant IDs a record counts, in order, once each: enchantID first, then
-- enchantIDs, which is set only for two or more. None = any enchant.
function DE.IDs(d)
    local out, seen = {}, {}
    local function add(v)
        v = tonumber(v)
        if v and v > 0 and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    d = d or {}
    add(d.enchantID)
    if type(d.enchantIDs) == "table" then
        for _, v in ipairs(d.enchantIDs) do add(v) end
    end
    return out
end

-- Templates: every rank of the shaman's weapon imbues, and of the two totems
-- that put an enchant on a group member's weapon, as Forever's game data
-- numbers them. An addon cannot list a spell's enchants in game (it only sees
-- the enchant on a weapon), so they ship here. Forever only: retail numbers
-- its enchants apart.
-- spell = the rank 1 spell, whose icon the picker shows.
DE.TEMPLATE_LIST = {
    { key = "rockbiter", name = "Rockbiter Weapon", spell = 8017, ids = { 29, 6, 1, 503, 1663, 683, 1664, 7568 } },
    { key = "flametongue", name = "Flametongue Weapon", spell = 8024, ids = { 5, 4, 3, 523, 1665, 1666, 7567 } },
    { key = "frostbrand", name = "Frostbrand Weapon", spell = 8033, ids = { 2, 12, 524, 1667, 1668, 7566 } },
    { key = "windfury", name = "Windfury Weapon", spell = 8232, ids = { 283, 284, 525, 1669, 7569 } },
    { key = "windfuryTotem", name = "Windfury Totem", spell = 8512, ids = { 1783, 563, 564 } },
    { key = "flametongueTotem", name = "Flametongue Totem", spell = 8227, ids = { 124, 285, 543, 1683 } },
}
DE.IMBUES = { rockbiter = true, flametongue = true, frostbrand = true, windfury = true }

-- The templates this client offers, each { key, name, label, ids }: any shaman
-- imbue first (the four imbues' ranks together), then each one.
function DE.Templates()
    if NS.IsForever ~= true then return {} end
    local all = {}
    for _, t in ipairs(DE.TEMPLATE_LIST) do
        if DE.IMBUES[t.key] then
            for _, id in ipairs(t.ids) do all[#all + 1] = id end
        end
    end
    local out = { { key = "imbues", name = "Shaman Imbue", label = "Any shaman imbue, every rank", ids = all,
        class = "SHAMAN" } }
    for _, t in ipairs(DE.TEMPLATE_LIST) do
        out[#out + 1] = { key = t.key, name = t.name, label = t.name .. ", every rank", ids = t.ids, spell = t.spell }
    end
    return out
end

function DE.Template(key)
    for _, t in ipairs(DE.Templates()) do
        if t.key == key then return t end
    end
    return nil
end

-- The enchant this icon tracks: an entry while it is on, false while it is
-- not, nil while the answer is secret. A weapon can carry two enchants, so
-- the first ID listed that is on it wins.
function DE.Read(rec)
    local list = DE.ReadHand(rec.driver and rec.driver.hand)
    if list == nil then return nil end
    local ids = DE.IDs(rec.driver)
    if #ids == 0 then return list[1] or false end
    for _, want in ipairs(ids) do
        for _, e in ipairs(list) do
            if e.id == want then return e end
        end
    end
    return false
end

-- An entry's time left in words: "50 min", or "40 s" under a minute.
function DE.LeftText(e)
    local left = e.left or 0
    if left >= 60 then return math.floor(left / 60 + 0.5) .. " min" end
    return math.floor(left + 0.5) .. " s"
end

-- An entry as the options and the tooltip IDs name it: "29 (50 min)", with
-- its charges when it has some ("29 (24 min, 5 charges)").
function DE.Describe(e)
    local ch = (e.charges or 0) > 0 and (", " .. e.charges .. " charges") or ""
    return tostring(e.id or 0) .. " (" .. DE.LeftText(e) .. ch .. ")"
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
