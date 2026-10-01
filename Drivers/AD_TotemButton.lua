-- Totem buttons: an icon following the totem bar (Drivers\AD_DriverTotem.lua)
-- drops the totem it shows on a click or a key. A secure action button on the
-- bar's action slot for its element does it, as Blizzard's totem bar button
-- does, so a new pick in the bar's flyout needs nothing from here, in combat
-- too. Protected calls (attributes, points, bindings, the state driver) run
-- out of combat only and wait for PLAYER_REGEN_ENABLED otherwise.
-- Called from AD_DriverCooldown's Attach / Detach and DT.BarChanged.

local ADDON, NS = ...
local Events = NS.Events

local TB = {}
NS.TotemButton = TB

TB.KEY = "adtotembtn"
-- binding and click-cast tools key on named frames
TB.NAME = "ArcAurasTotemButton"
-- over the icon's own layers (its texts and glows sit 7 or more over it)
TB.LEVEL_UP = 25
TB.buttons = {}   -- [iconId] = button, kept: a frame cannot be destroyed
TB.live = {}      -- [iconId] = { rec, frame } while its click or key is on
TB.pending = false

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function InCombat() return InCombatLockdown ~= nil and InCombatLockdown() == true end

-- An icon following the bar with its click or its key on.
function TB.Wanted(rec)
    local DT = NS.DriverTotem
    if not (DT and DT.IsBar and DT.IsBar(rec)) then return false end
    local d = rec.driver
    return d.click == true or (type(d.key) == "string" and d.key ~= "")
end

function TB.Action(rec)
    local DT = NS.DriverTotem
    return DT and DT.BarAction and DT.BarAction(rec.driver.slot or 1) or nil
end

-- The icon's tooltip, as if the mouse were on the icon.
local function OnEnter(self)
    local l = TB.live[self._adId]
    local fn = l and l.frame:GetScript("OnEnter")
    if fn then fn(l.frame) end
end

local function OnLeave(self)
    local l = TB.live[self._adId]
    local fn = l and l.frame:GetScript("OnLeave")
    if fn then fn(l.frame) end
end

-- Out of combat only. Hidden until its driver runs; key presses act on key
-- down or up as the game's own setting says, mouse clicks on the release.
local function Create(rec)
    local btn = CreateFrame("Button", TB.NAME .. rec.id, UIParent, "SecureActionButtonTemplate")
    btn:Hide()
    btn:EnableMouse(false)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn._adId = rec.id
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    TB.buttons[rec.id] = btn
    TB.Arm()
    return btn
end

-- Out of combat only: the icon's rect, strata and level onto the button.
function TB.Place(f, btn)
    local UB = NS.Bars and NS.Bars.ClickUnit
    local x, y, w, h
    if UB and UB.Rect then x, y, w, h = UB.Rect(f) end
    if x and (btn._adX ~= x or btn._adY ~= y or btn._adW ~= w or btn._adH ~= h) then
        btn._adX, btn._adY, btn._adW, btn._adH = x, y, w, h
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        btn:SetSize(w, h)
    end
    local strata, level = f:GetFrameStrata(), f:GetFrameLevel()
    if not IsSecret(strata) and type(strata) == "string" and btn._adStrata ~= strata then
        btn._adStrata = strata
        btn:SetFrameStrata(strata)
    end
    if not IsSecret(level) and type(level) == "number" and btn._adLevel ~= level + TB.LEVEL_UP then
        btn._adLevel = level + TB.LEVEL_UP
        btn:SetFrameLevel(btn._adLevel)
    end
end

-- Out of combat only: shown where the icon's conditions show it (the health
-- bars' translation, Bars\AD_ClickUnit.lua), hidden while the options are
-- open so the icon stays draggable, and hidden with no click.
function TB.Drive(rec, btn, click)
    local str = "hide"
    local LE = NS.LayoutEngine
    local editing = LE ~= nil and LE.IsEditMode ~= nil and LE.IsEditMode() == true
    if click and not editing then
        local UB = NS.Bars and NS.Bars.ClickUnit
        str = (UB and UB.Translate and UB.Translate(rec)) or "show"
    end
    if btn._adDriver ~= str then
        btn._adDriver = str
        RegisterStateDriver(btn, "visibility", str)
    end
end

-- Out of combat only: the whole protected state of one button. No action (no
-- totem bar) means no type and no key: a bare action button would use
-- action slot 1.
function TB.Apply(l)
    local rec, f = l.rec, l.frame
    local btn = TB.buttons[rec.id]
    if not btn then return end
    local action = TB.Action(rec)
    if btn._adAction ~= action then
        btn._adAction = action
        btn:SetAttribute("type", action and "action" or nil)
        btn:SetAttribute("action", action)
    end
    local key = action and rec.driver.key or nil
    if key == "" then key = nil end
    if btn._adKey ~= key then
        ClearOverrideBindings(btn)
        if key then SetOverrideBindingClick(btn, false, key, btn:GetName(), "LeftButton") end
        btn._adKey = key
    end
    local click = action ~= nil and rec.driver.click == true
    if click then TB.Place(f, btn) end
    btn:EnableMouse(click)
    TB.Drive(rec, btn, click)
end

-- Out of combat only: no key, no mouse, hidden.
local function Drop(btn)
    if btn._adKey then
        ClearOverrideBindings(btn)
        btn._adKey = nil
    end
    btn:EnableMouse(false)
    if btn._adDriver ~= nil then
        btn._adDriver = nil
        UnregisterStateDriver(btn, "visibility")
        btn:Hide()
    end
end

-- Every button against the live icons: what waited for combat to end, and a
-- new pick, page or bar (DT.BarChanged).
function TB.SyncAll()
    if InCombat() then
        TB.pending = true
        return
    end
    TB.pending = false
    for id, btn in pairs(TB.buttons) do
        local l = TB.live[id]
        if l and TB.Wanted(l.rec) then TB.Apply(l) else Drop(btn) end
    end
    for id, l in pairs(TB.live) do
        if not TB.buttons[id] and TB.Wanted(l.rec) then
            Create(l.rec)
            TB.Apply(l)
        end
    end
end

-- Combat end flushes what waited; a fade or a condition change moves the
-- click area out of combat.
function TB.Arm()
    if TB.armed then return end
    TB.armed = true
    Events.On("PLAYER_REGEN_ENABLED", TB.KEY, function()
        if TB.pending then TB.SyncAll() end
    end)
    Events.OnMessage("AD_VISIBILITY", TB.KEY, function()
        if next(TB.live) == nil then return end
        if InCombat() then
            TB.pending = true
        else
            TB.SyncAll()
        end
    end)
end

-- Every (re)style of a totem icon lands here.
function TB.Attach(rec, f)
    if TB.Wanted(rec) then
        TB.live[rec.id] = { rec = rec, frame = f }
    else
        TB.live[rec.id] = nil
    end
    if not (TB.live[rec.id] or TB.buttons[rec.id]) then return end
    if InCombat() then
        TB.pending = true
        TB.Arm()
        return
    end
    local l, btn = TB.live[rec.id], TB.buttons[rec.id]
    if l then
        if not btn then Create(rec) end
        TB.Apply(l)
    else
        Drop(btn)
    end
end

function TB.Detach(id)
    TB.live[id] = nil
    local btn = TB.buttons[id]
    if not btn then return end
    if InCombat() then
        TB.pending = true
        TB.Arm()
    else
        Drop(btn)
    end
end

