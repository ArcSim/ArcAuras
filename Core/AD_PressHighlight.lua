-- Button Press Highlight: when you press an action button, every icon for that
-- ability flashes, or stays lit while the button is held.
-- Hooks are post-hooks, so the hooked calls stay untainted. A slot that reads
-- secret in combat is answered from a cache filled while it read plain.
local ADDON, NS = ...
local Store = NS.Store

local PH = {}
NS.PressHighlight = PH

-- Looks: a colour fill or one of the game's own button frames.
PH.LOOKS = {
    { value = "fill",  text = "Color fill" },
    { value = "quest", text = "Quest border" },
    { value = "down",  text = "Action button pressed" },
    { value = "hover", text = "Action button hover" },
    { value = "flash", text = "Action button flash" },
}
local LOOK_ART = {
    quest = { file = "Interface\\ContainerFrame\\UI-Icon-QuestBorder" },
    down = { atlas = "UI-HUD-ActionBar-IconFrame-Down" },
    hover = { atlas = "UI-HUD-ActionBar-IconFrame-Mouseover" },
    flash = { atlas = "UI-HUD-ActionBar-IconFrame-Flash" },
}
PH.DEFAULT_COLOR = { 0.95, 0.95, 0.32 }
PH.DEFAULT_ALPHA = 0.45
PH.DEFAULT_DURATION = 0.1

local function Setting(k, d)
    local v = Store.GetSetting and Store.GetSetting(k)
    if v == nil then return d end
    return v
end

-- Asked on every button press, so read once per settings change: every
-- settings write fires AD_DIRTY.
local enabled
function PH.Enabled()
    if enabled == nil then enabled = Setting("pressHighlight", false) == true end
    return enabled
end
if NS.Events and NS.Events.OnMessage then
    NS.Events.OnMessage("AD_DIRTY", "adpress_on", function() enabled = nil end)
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- What an action slot holds. A secret read is answered from the cache.
local slotCache = {}          -- [slot] = { kind, id } from the last plain read
local slotDirty = true

local function ReadSlot(slot)
    local kind, id, sub = GetActionInfo(slot)
    if Secret(kind) or Secret(id) or Secret(sub) then return nil end
    -- A macro: the client reports what it would cast or use as the id, with
    -- the third return naming the kind; an older one gives the macro index.
    if kind == "macro" and type(id) == "number" then
        if sub == "spell" or sub == "item" then return sub, id end
        local sid = GetMacroSpell and GetMacroSpell(id)
        if sid and not Secret(sid) then return "spell", sid end
        local _, link = nil, nil
        if GetMacroItem then _, link = GetMacroItem(id) end
        if type(link) == "string" and not Secret(link) then
            local iid = tonumber(link:match("item:(%d+)"))
            if iid then return "item", iid end
        end
        return nil
    end
    if (kind == "spell" or kind == "item") and type(id) == "number" then return kind, id end
    return nil
end

local function RebuildSlots()
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if not (Secret(kind) or Secret(id)) then
            local k, v = ReadSlot(slot)
            slotCache[slot] = k and { k, v } or nil
        end
    end
    slotDirty = false
end

local function SlotHolds(slot)
    if type(slot) ~= "number" then return nil end
    local k, v = ReadSlot(slot)
    if k then
        slotCache[slot] = { k, v }
        return k, v
    end
    local kind = GetActionInfo(slot)
    if not Secret(kind) and kind == nil then return nil end     -- empty slot
    local c = slotCache[slot]
    if c then return c[1], c[2] end
    return nil
end

-- Which icons a press lights
local function Plain(v)
    if Secret(v) then return nil end
    return v
end

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    return Plain(C_Spell.GetSpellName(id))
end

-- A spell icon lights for its own ID, its override, the base of what was
-- pressed and, on ranked realms, any rank with the same name.
local function SpellMatches(d, sid, pressedName)
    local mine = d.spellID
    if type(mine) ~= "number" then return false end
    if mine == sid then return true end
    if C_Spell and C_Spell.GetOverrideSpell and Plain(C_Spell.GetOverrideSpell(mine)) == sid then return true end
    if C_Spell and C_Spell.GetBaseSpell and Plain(C_Spell.GetBaseSpell(sid)) == mine then return true end
    if NS.IsForever == true and pressedName and SpellName(mine) == pressedName then return true end
    return false
end

local function Matches(rec, kind, id, pressedName)
    local d = rec.driver or {}
    if rec.kind == "spell" then
        return kind == "spell" and SpellMatches(d, id, pressedName)
    elseif rec.kind == "item" then
        return kind == "item" and d.itemID == id
    elseif rec.kind == "trinket" then
        if kind == "invslot" then return d.slotID == id end
        if kind == "item" and GetInventoryItemID and d.slotID then
            return Plain(GetInventoryItemID("player", d.slotID)) == id
        end
    end
    return false
end

-- Overlay
local held = {}               -- [frame] = true while a hold shows on it
local holdTicker

local function Overlay(f)
    local o = f._adPress
    if not o then
        local host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host:Hide()
        o = { host = host, tex = host:CreateTexture(nil, "OVERLAY", nil, 7) }
        f._adPress = o
    end
    -- Above the art and swipe, below the border host (+6) and texts (+7).
    -- If the level reads secret, the last one stays.
    local lvl = f:GetFrameLevel()
    if not Secret(lvl) and type(lvl) == "number" then o.host:SetFrameLevel(lvl + 5) end
    return o
end

local atlasOK = {}
local function HasAtlas(name)
    if atlasOK[name] == nil then
        atlasOK[name] = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil
            and C_Texture.GetAtlasInfo(name) ~= nil
    end
    return atlasOK[name]
end

local function Paint(o, f)
    local t = o.tex
    t:ClearAllPoints()
    t:SetAllPoints(f.icon or f)          -- the art's own rect (padding included)
    local look = Setting("pressLook", "fill")
    local c = Setting("pressColor", PH.DEFAULT_COLOR)
    local a = Setting("pressAlpha", PH.DEFAULT_ALPHA)
    local art = LOOK_ART[look]
    if art and art.atlas and not HasAtlas(art.atlas) then art = nil end
    if not art then
        -- Colour fill: the vertex colour carries both colour and opacity.
        t:SetColorTexture(1, 1, 1, 1)
        t:SetDesaturated(false)
        t:SetVertexColor(c[1], c[2], c[3], a)
        return
    end
    if art.atlas then t:SetAtlas(art.atlas) else t:SetTexture(art.file) end
    if Setting("pressTint", false) == true then
        t:SetDesaturated(true)
        t:SetVertexColor(c[1], c[2], c[3], a)
    else
        t:SetDesaturated(false)
        t:SetVertexColor(1, 1, 1, a)
    end
end

local function Release(f)
    local o = f._adPress
    if o then o.host:Hide() end
    held[f] = nil
end

-- Buttons a hold watches for the PUSHED state: Blizzard's bars first, then
-- action bar addons by global name. Gathered on the first hold.
local HOLD_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local holdButtons
local function HoldButtons()
    if holdButtons then return holdButtons end
    holdButtons = {}
    local function add(b)
        if type(b) == "table" and b.GetButtonState and not (b.IsForbidden and b:IsForbidden()) then
            holdButtons[#holdButtons + 1] = b
        end
    end
    for _, prefix in ipairs(HOLD_BARS) do
        for i = 1, 12 do add(_G[prefix .. i]) end
    end
    for bar = 1, 15 do
        for i = 1, 12 do add(_G["ElvUI_Bar" .. bar .. "Button" .. i]) end
    end
    for i = 1, 180 do add(_G["BT4Button" .. i]) add(_G["DominosActionButton" .. i]) end
    return holdButtons
end

local function AnyPushed()
    for _, b in ipairs(HoldButtons()) do
        local st = b:GetButtonState()
        if not Secret(st) and st == "PUSHED" then return true end
    end
    return false
end

-- A hold ends once no watched button is pushed, but not before the flash
-- length: a mouse click casts on release, when nothing is pushed any more.
local function HoldTick()
    local now = GetTime()
    local pushed = AnyPushed()
    local left = false
    for f in pairs(held) do
        local o = f._adPress
        if not pushed and o and now >= (o.minUntil or 0) then
            Release(f)
        else
            left = true
        end
    end
    if not left and holdTicker then
        holdTicker:Cancel()
        holdTicker = nil
    end
end

local function Light(f)
    local o = Overlay(f)
    Paint(o, f)
    o.tex:Show()
    o.host:Show()
    o.token = (o.token or 0) + 1
    local token = o.token
    local dur = Setting("pressDuration", PH.DEFAULT_DURATION)
    if Setting("pressMode", "flash") == "hold" then
        o.minUntil = GetTime() + dur
        held[f] = true
        if not holdTicker and C_Timer and C_Timer.NewTicker then
            holdTicker = C_Timer.NewTicker(0.03, HoldTick)
        end
    else
        held[f] = nil
        C_Timer.After(dur, function()
            -- a newer press on the same icon owns the overlay now
            if o.token == token then o.host:Hide() end
        end)
    end
end

-- One press: light every visible icon it belongs to.
local function Press(kind, id)
    if not PH.Enabled() then return end
    if id == nil or Secret(id) then return end
    local frames = NS.Factory and NS.Factory.frames
    if not frames then return end
    local pressedName = (kind == "spell") and SpellName(id) or nil
    for recId, f in pairs(frames) do
        -- only an icon you can see: a hidden frame, or art its state hides
        if f.IsVisible and f:IsVisible() and (f._adShownAlpha or 1) > 0 then
            local rec = Store.Get(recId)
            if rec and Matches(rec, kind, id, pressedName) then Light(f) end
        end
    end
end
PH.Press = Press   -- the harness and the options' preview reach it

-- Hooks
local function OnUseAction(slot)
    if not PH.Enabled() or Secret(slot) then return end
    if slotDirty and not InCombatLockdown() then RebuildSlots() end
    local kind, id = SlotHolds(slot)
    if kind then Press(kind, id) end
end

local function OnCastByID(spellID)
    if Secret(spellID) or type(spellID) ~= "number" then return end
    Press("spell", spellID)
end

local function OnCastByName(name)
    if not PH.Enabled() or Secret(name) or type(name) ~= "string" then return end
    local sid = C_Spell and C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(name)
    if sid and not Secret(sid) then Press("spell", sid) end
end

local function OnUseInventoryItem(slot)
    if Secret(slot) or type(slot) ~= "number" then return end
    Press("invslot", slot)
end

if hooksecurefunc then
    if type(UseAction) == "function" then hooksecurefunc("UseAction", OnUseAction) end
    if type(CastSpellByID) == "function" then hooksecurefunc("CastSpellByID", OnCastByID) end
    if type(CastSpellByName) == "function" then hooksecurefunc("CastSpellByName", OnCastByName) end
    if type(UseInventoryItem) == "function" then hooksecurefunc("UseInventoryItem", OnUseInventoryItem) end
end

-- the slot cache goes stale when a slot changes or a macro is edited
if NS.Events and NS.Events.On then
    local function dirty() slotDirty = true end
    for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD" }) do
        if (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(ev) then
            NS.Events.On(ev, "adpress", dirty)
        end
    end
end

-- Switched off: nothing may stay lit.
function PH.ReleaseAll()
    for f in pairs(held) do Release(f) end
    if holdTicker then holdTicker:Cancel() holdTicker = nil end
    local frames = NS.Factory and NS.Factory.frames
    if frames then
        for _, f in pairs(frames) do
            if f._adPress then f._adPress.host:Hide() end
        end
    end
end
