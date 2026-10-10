-- AD_ClickUnit: a health bar's click area, a secure unit button over the bar that targets its unit on a left click, opens the unit menu on a right click and takes click-cast bindings.
-- Owns one button per health bar with Clickable on; the bars runtime calls in through Bars.ClickUnit when it styles or releases a health bar, and the Tracking tab reads Note.
-- A protected call (attributes, points, size, show and hide, the state driver) runs out of combat only and waits for PLAYER_REGEN_ENABLED otherwise; in combat the state driver alone shows or hides the button.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (K and K.R and K.live and K.IsEditMode) then return end

local Store = NS.Store
local Events = NS.Events

local UB = {}
Bars.ClickUnit = UB

UB.KEY = "adclick"
-- click-cast addons key on named frames
UB.NAME = "ArcAurasUnit"
-- [bar id] = button; a frame cannot be destroyed, so a button is kept and reused
UB.buttons = {}
-- a protected change waited for combat to end
UB.pending = false
UB.armed = false
-- above the shell's overlay host, which sits 20 levels over the fill
UB.LEVEL_UP = 25

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function InCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local function Setting(k)
    return Store and Store.GetSetting and Store.GetSetting(k)
end

-- The macro conditionals the state driver can read, per condition key of the
-- conditions module: pos holds while the condition does, neg while it does
-- not, each an OR list of brackets. A condition on the player carries
-- @player, since a bare [dead] reads the target.
local function Word(on, off) return { pos = { on }, neg = { off } } end
local function Plain(w) return Word(w, "no" .. w) end
local function OnUnit(unit, w) return Word("@" .. unit .. "," .. w, "@" .. unit .. ",no" .. w) end
UB.MACRO = {
    inCombat = Plain("combat"), outOfCombat = Word("nocombat", "combat"),
    mounted = Plain("mounted"), stealthed = Plain("stealth"),
    flying = Plain("flying"), swimming = Plain("swimming"),
    indoors = Plain("indoors"), outdoors = Plain("outdoors"),
    resting = Plain("resting"), hasPet = Plain("pet"),
    dead = OnUnit("player", "dead"), alive = Word("@player,nodead", "@player,dead"),
    hasTarget = OnUnit("target", "exists"), noTarget = Word("@target,noexists", "@target,exists"),
    targetHostile = OnUnit("target", "harm"), targetFriendly = OnUnit("target", "help"),
    hasFocus = OnUnit("focus", "exists"),
    solo = Word("nogroup", "group"),
    -- a raid can read as a party too, so the raid is ruled out by hand
    party = { pos = { "group:party,nogroup:raid" }, neg = { "nogroup:party", "group:raid" } },
    raid = Plain("group:raid"),
    petBattle = Plain("petbattle"),
}
-- The forms read the stance bar: the slot whose spell names the form.
UB.FORM_KEYS = { formCaster = "none", formCat = "cat", formBear = "bear", formMoonkin = "moonkin",
    formTravel = "travel", formTree = "tree", stanceBattle = "battle", stanceDefensive = "defensive",
    stanceBerserker = "berserker", stanceNone = "none", shadowform = "shadowform",
    noShadowform = "shadowform" }

-- [form name] = its stance bar slots, "1" or "3/4", read plain and out of
-- combat (a respec moves the slots; every restyle reads them again).
function UB.FormSlots()
    local C = NS.Conditions
    local bySpell = C and C.FORM_BY_SPELL
    local out = {}
    if not (bySpell and GetNumShapeshiftForms and GetShapeshiftFormInfo) then return out end
    local n = GetNumShapeshiftForms()
    if IsSecret(n) or type(n) ~= "number" then return out end
    for i = 1, n do
        local _, _, _, sid = GetShapeshiftFormInfo(i)
        local name = (not IsSecret(sid)) and type(sid) == "number" and bySpell[sid] or nil
        if name then out[name] = out[name] and (out[name] .. "/" .. i) or tostring(i) end
    end
    return out
end

-- The brackets of one condition key, or nil when the game has no conditional
-- for it (or the form is not on this character's bar).
function UB.Rule(key, forms)
    local m = UB.MACRO[key]
    if m then return m end
    local name = UB.FORM_KEYS[key]
    if not name then return nil end
    if name == "none" then return Word("noform", "form") end
    local slots = forms[name]
    if not slots then return nil end
    local r = Word("form:" .. slots, "noform:" .. slots)
    if key == "noShadowform" then return { pos = r.neg, neg = r.pos } end
    return r
end

-- Two brackets as one AND. A unit goes first, where it covers the whole
-- bracket; two different units in one bracket are refused.
function UB.Join(a, b)
    local ua, ub = a:match("^@(%w+),"), b:match("^@(%w+),")
    if ua and ub then
        if ua ~= ub then return nil end
        return a .. "," .. b:gsub("^@%w+,", "")
    end
    if ub then return b .. "," .. a end
    return a .. "," .. b
end

-- The state driver for a bar's conditions: "[...] hide; ...; show". Returns the
-- string, the keys it follows and the keys in use it cannot (a key the module
-- ignores on this client counts as unused). A never or all-of list drops an
-- unreadable key alone, so the click area shows more than the bar; an any-of
-- list with one is dropped whole, since dropping the key alone could hide the
-- click area under a shown bar. The fade lists count only at a fade to nothing.
function UB.Translate(rec)
    local C = NS.Conditions
    local c = (rec and rec.c) or {}
    local unit = (rec and rec.driver and rec.driver.unit) or "player"
    local forms = UB.FormSlots()
    local hides, shows, followed, dropped = {}, nil, {}, {}
    local always = false
    local function Live(key)
        local d = C and C.ByKey and C.ByKey(key)
        if not d then return false end
        if d.avail and not d.avail() then return false end
        return true
    end
    local function Keys(set)
        local list = {}
        if type(set) == "table" then
            for k, v in pairs(set) do
                if v == true and Live(k) then list[#list + 1] = k end
            end
        end
        table.sort(list)
        return list
    end
    local function Never(set)
        for _, k in ipairs(Keys(set)) do
            if k == "always" then
                always = true
            else
                local r = UB.Rule(k, forms)
                if r then
                    for _, b in ipairs(r.pos) do hides[#hides + 1] = b end
                    followed[#followed + 1] = k
                else
                    dropped[#dropped + 1] = k
                end
            end
        end
    end
    -- every checked one at once: a hide per joint of their brackets. A key it
    -- cannot read drops the whole list (dropping it alone would hide the click
    -- area under a shown bar); Always holds anyway and joins nothing.
    local function NeverAll(set)
        local keys = Keys(set)
        if #keys == 0 then return end
        local list, rest = nil, {}
        for _, k in ipairs(keys) do
            if k ~= "always" then rest[#rest + 1] = k end
        end
        if #rest == 0 then
            always = true
            followed[#followed + 1] = "always"
            return
        end
        for _, k in ipairs(rest) do
            local r = UB.Rule(k, forms)
            if not r then
                list = false
                break
            end
            if not list then
                list = {}
                for _, b in ipairs(r.pos) do list[#list + 1] = b end
            else
                local joined = {}
                for _, a in ipairs(list) do
                    for _, b in ipairs(r.pos) do
                        local j = UB.Join(a, b)
                        if not j then
                            joined = nil
                            break
                        end
                        joined[#joined + 1] = j
                    end
                    if not joined then break end
                end
                list = joined or false
                if not list then break end
            end
        end
        if not list then
            for _, k in ipairs(keys) do dropped[#dropped + 1] = k end
            return
        end
        for _, b in ipairs(list) do hides[#hides + 1] = b end
        for _, k in ipairs(keys) do followed[#followed + 1] = k end
    end
    local function When(set, all)
        local keys = Keys(set)
        if #keys == 0 then return end
        if all then
            for _, k in ipairs(keys) do
                local r = UB.Rule(k, forms)
                if r then
                    for _, b in ipairs(r.neg) do hides[#hides + 1] = b end
                    followed[#followed + 1] = k
                else
                    dropped[#dropped + 1] = k
                end
            end
            return
        end
        local list = {}
        for _, k in ipairs(keys) do
            local r = UB.Rule(k, forms)
            if not r then
                list = nil
                break
            end
            for _, b in ipairs(r.pos) do list[#list + 1] = b end
        end
        if list and shows then
            -- a second any-of list: every pair of brackets, or nothing
            local joined = {}
            for _, a in ipairs(shows) do
                for _, b in ipairs(list) do
                    local j = UB.Join(a, b)
                    if not j then
                        joined = nil
                        break
                    end
                    joined[#joined + 1] = j
                end
                if not joined then break end
            end
            list = joined
        end
        if not list then
            for _, k in ipairs(keys) do dropped[#dropped + 1] = k end
            return
        end
        shows = list
        for _, k in ipairs(keys) do followed[#followed + 1] = k end
    end
    local fadeZero = not (C and C.GetFade) or C.GetFade(rec, "fadeAlpha") <= 0
    Never(c.loadNever)
    if fadeZero then
        if c.fadeWhenAll == true then NeverAll(c.fadeWhen) else Never(c.fadeWhen) end
    end
    When(c.loadWhen, c.loadWhenAll == true)
    if fadeZero then When(c.showWhen, c.showWhenAll == true) end
    -- the target range rule has no conditional
    if fadeZero and C and C.RangeRule and C.RangeRule(rec) then dropped[#dropped + 1] = "range" end
    if always then return "hide", followed, dropped end
    local parts = { "[@" .. unit .. ",noexists] hide" }
    for _, b in ipairs(hides) do parts[#parts + 1] = "[" .. b .. "] hide" end
    if shows then
        local ors = {}
        for _, b in ipairs(shows) do ors[#ors + 1] = "[" .. b .. "]" end
        parts[#parts + 1] = table.concat(ors) .. " show"
        parts[#parts + 1] = "hide"
    else
        parts[#parts + 1] = "show"
    end
    return table.concat(parts, "; "), followed, dropped
end

-- The Tracking tab's line under the switch.
function UB.Note(rec)
    local _, followed, dropped = UB.Translate(rec)
    local C = NS.Conditions
    local function Words(list)
        local out = {}
        for _, k in ipairs(list) do
            local d = C and C.ByKey and C.ByKey(k)
            out[#out + 1] = (k == "range" and "Target range rule") or (d and d.text) or k
        end
        return table.concat(out, ", ")
    end
    if #followed == 0 and #dropped == 0 then
        return "Left click targets the unit and right click opens its menu, in combat too; the click area shows while the unit exists."
    end
    local s = ""
    if #followed > 0 then s = "In combat the click area follows: " .. Words(followed) .. "." end
    if #dropped > 0 then
        s = s .. (s ~= "" and " " or "") .. Words(dropped) .. (#dropped == 1 and " hides" or " hide")
            .. " the bar but not its click area until combat ends."
    end
    return s
end

-- The button

local function Unit(e)
    local d = e.rec and e.rec.driver
    return (d and d.unit) or "player"
end

-- A live bar with the switch on; Styled keeps the preview out.
function UB.Wanted(e)
    return e ~= nil and e.kind == "health" and RegisterStateDriver ~= nil
        and K.R(e.rec, "behavior", "clickable") == true
end

-- the game's own unit tooltip, as its unit frames show it
local function OnEnter(self)
    if Setting("showTooltips") == false or Setting("tooltipsEditOnly") == true then return end
    if not (GameTooltip and self._adUnit) then return end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    if GameTooltip:SetUnit(self._adUnit) then GameTooltip:Show() end
end

local function OnLeave()
    if GameTooltip then GameTooltip:FadeOut() end
end

-- The bar's rect in UIParent's units. nil while the bar has no rect yet or a
-- secret one (a bar pinned to a nameplate); the button then keeps its last.
function UB.Rect(holder)
    if Bars.RectHidden(holder) then return nil end
    local l, b, w, h = holder:GetLeft(), holder:GetBottom(), holder:GetWidth(), holder:GetHeight()
    if IsSecret(l) or IsSecret(b) or IsSecret(w) or IsSecret(h) then return nil end
    if type(l) ~= "number" or type(b) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return nil
    end
    local s, us = holder:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if IsSecret(s) or IsSecret(us) or type(s) ~= "number" or type(us) ~= "number" or us == 0 then
        return l, b, w, h
    end
    local k = s / us
    return l * k, b * k, w * k, h * k
end

-- The module's own verdict: nothing to click while the bar is inert or faded
-- to nothing (its mouse is off then too).
function UB.Hidden(e)
    local C = NS.Conditions
    return C ~= nil and C.MouseBlocked ~= nil and C.MouseBlocked(e.rec) == true
end

-- Out of combat only: the bar's rect, strata and level onto the button, each
-- written only when it changed.
function UB.Place(e, btn)
    local holder = e.holder
    local x, y, w, h = UB.Rect(holder)
    if x and (btn._adX ~= x or btn._adY ~= y or btn._adW ~= w or btn._adH ~= h) then
        btn._adX, btn._adY, btn._adW, btn._adH = x, y, w, h
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        btn:SetSize(w, h)
    end
    local strata, level = holder:GetFrameStrata(), holder:GetFrameLevel()
    if not IsSecret(strata) and type(strata) == "string" and btn._adStrata ~= strata then
        btn._adStrata = strata
        btn:SetFrameStrata(strata)
    end
    if not IsSecret(level) and type(level) == "number" then
        level = level + UB.LEVEL_UP
        if btn._adLevel ~= level then
            btn._adLevel = level
            btn:SetFrameLevel(level)
        end
    end
end

-- Out of combat only: "hide" while the panel is open or the module has the bar
-- hidden, else the translated conditions; re-registered when the words change.
function UB.Drive(e, btn)
    local str
    if K.IsEditMode() or UB.Hidden(e) then
        str = "hide"
    else
        str = UB.Translate(e.rec)
    end
    if btn._adDriver ~= str then
        btn._adDriver = str
        RegisterStateDriver(btn, "visibility", str)
    end
end

-- The bar's effective alpha, in combat too: SetAlpha is not protected and
-- takes a secret.
function UB.Alpha(e, btn)
    local a = e.holder:GetEffectiveAlpha()
    if a == nil then return end
    if not IsSecret(a) and btn._adAlpha == a then return end
    btn._adAlpha = (not IsSecret(a)) and a or nil
    btn:SetAlpha(a)
end

-- Out of combat only: the whole protected state of one button.
function UB.Apply(e)
    local btn = UB.buttons[e.rec.id]
    if not btn then return end
    local unit = Unit(e)
    if btn._adUnit ~= unit then
        btn._adUnit = unit
        btn:SetAttribute("unit", unit)
    end
    if not btn._adListed then
        btn._adListed = true
        ClickCastFrames = ClickCastFrames or {}
        ClickCastFrames[btn] = true
    end
    UB.Place(e, btn)
    UB.Drive(e, btn)
    UB.Alpha(e, btn)
end

-- Out of combat only: off the click-cast list, no driver, hidden.
local function Drop(btn)
    if btn._adListed then
        btn._adListed = false
        if ClickCastFrames then ClickCastFrames[btn] = false end
    end
    if btn._adDriver ~= nil then
        btn._adDriver = nil
        UnregisterStateDriver(btn, "visibility")
        btn:Hide()
    end
end

function UB.OnVisibility()
    local combat = InCombat()
    for id, btn in pairs(UB.buttons) do
        local e = K.live[id]
        if e and btn._adDriver ~= nil and UB.Wanted(e) then
            UB.Alpha(e, btn)
            if not combat then
                UB.Place(e, btn)
                UB.Drive(e, btn)
            end
        end
    end
end

-- Combat end flushes what waited; the conditions pass and every fade tick
-- carry the alpha, and out of combat the rect and the driver.
local function Arm()
    if UB.armed then return end
    UB.armed = true
    Events.On("PLAYER_REGEN_ENABLED", UB.KEY, function()
        if UB.pending then UB.SyncAll() end
    end)
    Events.OnMessage("AD_VISIBILITY", UB.KEY, UB.OnVisibility)
end

-- Out of combat only. Hidden until its driver runs; the clicks and the two
-- types are the secure template's own defaults.
local function Create(e)
    local id = e.rec.id
    local btn = CreateFrame("Button", UB.NAME .. id, UIParent, "SecureUnitButtonTemplate")
    btn:Hide()
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    UB.buttons[id] = btn
    Arm()
    return btn
end

-- A bar that follows another's width resizes without a rebuild.
function UB.Hook(e)
    local holder = e.holder
    if holder._adClickHooked then return end
    holder._adClickHooked = true
    local id = e.rec.id
    holder:HookScript("OnSizeChanged", function()
        local cur, btn = K.live[id], UB.buttons[id]
        if not (cur and btn and btn._adDriver ~= nil and UB.Wanted(cur)) then return end
        if InCombat() then
            UB.pending = true
        else
            UB.Place(cur, btn)
        end
    end)
end

-- Every button against the live bars: what waited for combat to end.
function UB.SyncAll()
    if InCombat() then return end
    UB.pending = false
    for id, btn in pairs(UB.buttons) do
        local e = K.live[id]
        if e and UB.Wanted(e) then
            UB.Hook(e)
            UB.Apply(e)
        else
            Drop(btn)
        end
    end
    for id, e in pairs(K.live) do
        if not UB.buttons[id] and UB.Wanted(e) then
            Create(e)
            UB.Hook(e)
            UB.Apply(e)
        end
    end
end

-- At the end of every style pass (every rebuild): the switch, the unit and
-- the rect can all have changed.
function UB.Styled(e)
    if e.isPreview then return end
    local btn = UB.buttons[e.rec.id]
    if not UB.Wanted(e) then
        if btn then
            if InCombat() then UB.pending = true else Drop(btn) end
        end
        return
    end
    if InCombat() then
        UB.pending = true
        Arm()
        if btn then UB.Alpha(e, btn) end
        return
    end
    if not btn then btn = Create(e) end
    UB.Hook(e)
    UB.Apply(e)
end

-- The entry has already left the live table.
function UB.Release(e)
    local btn = UB.buttons[e.rec.id]
    if not btn then return end
    if InCombat() then UB.pending = true else Drop(btn) end
end

-- The /adbars diag line of a health bar with the switch on.
function UB.Diag(e)
    local btn = UB.buttons[e.rec.id]
    if not (btn or UB.Wanted(e)) then return nil end
    return ("%s [click] on=%s unit=%s shown=%s pending=%s driver=%s"):format(tostring(e.rec.name),
        tostring(UB.Wanted(e)), tostring(btn and btn._adUnit), tostring(btn and btn:IsShown()),
        tostring(UB.pending), tostring(btn and btn._adDriver))
end
