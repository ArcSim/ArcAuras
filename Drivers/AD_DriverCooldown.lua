-- Cooldown driver and the attach point for every icon kind; aura icons go on
-- to NS.DriverAura. Spell state is read off two hidden shadow Cooldowns with
-- IsShown(), never from cooldown numbers, which are secret in combat.

local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events
local Factory = NS.Factory
local AMMO_SLOT = NS.AMMO_SLOT or INVSLOT_AMMO or 0

local Driver = {}
NS.DriverCooldown = Driver

local attached = {}      -- [iconId] = { rec, frame, sCD, sCharge, isCharge }
local shadowCache = {}   -- [iconId] = { sCD, sCharge } kept across detach
local rangeTicker        -- fallback 0.25s range pulse, alive only while attached
local rangeIcons = {}    -- [sid] = { [iconId] = a }: icons whose range tint rides that spell's check

local function MakeShadow()
    local w = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    w:SetSize(1, 1)
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    w:SetAlpha(0)
    w:EnableMouse(false)
    w:SetHideCountdownNumbers(true)
    w:SetDrawEdge(false)
    w:SetDrawBling(false)
    w:Show()
    return w
end
Driver.MakeShadow = MakeShadow

-- A wand shot locks every spell for about a second and the game does not flag
-- it as the GCD: isOnGCD stays false and the ignoreGCD read is live. Casting
-- anything else stops the wand, so while a wand shot is the latest cast, a new
-- cooldown can only be that lock.
local WAND_SHOTS = { [5019] = true }
local WAND_LOCK_MAX = 3      -- seconds; longer than any wand's lock
local WAND_CAST_GAP = 0.25   -- a cast this close before the shot may still be landing its cooldown
local wandShotAt, otherCastAt = 0, 0

function Driver.IsWandShot(spellID)
    if issecretvalue and issecretvalue(spellID) then return false end
    return WAND_SHOTS[spellID] == true
end

-- Every player cast is noted here; the cooldown bars call it too. A secret
-- spell ID counts as another cast, so a real cooldown is never ignored.
function Driver.NoteCast(spellID)
    if Driver.IsWandShot(spellID) then
        wandShotAt = GetTime()
    else
        otherCastAt = GetTime()
    end
end

function Driver.WandLocked()
    return wandShotAt - otherCastAt > WAND_CAST_GAP
        and GetTime() - wandShotAt < WAND_LOCK_MAX
end

-- Forward declarations, above every user: a closure compiled before its local
-- is declared reads the (nil) global of that name instead.
local Feed
local PlayReadyAlert
local FeedUsability

-- Every alert plays through here. Callers fire it on verified shadow edges
-- only, since a sound cannot be taken back.
local function PlayAlert(rec, enKey, soundKey)
    if Store.Resolve(rec, "alerts", enKey) ~= true then return end
    -- An inert record is silent too, not just hidden.
    if NS.Conditions and NS.Conditions.IsInert(rec) then return end
    local name = Store.Resolve(rec, "alerts", soundKey)
    if type(name) == "string" and name ~= "" and NS.Sounds then
        NS.Sounds.Play(name, Store.Resolve(rec, "alerts", "soundChannel"))
    end
end
Driver.PlayAlert = PlayAlert

-- Usability pass state: a pass reads the target once and IsSpellUsable once
-- per spell. An icon's settings are re-read only after a change (AD_DIRTY).
local cfgGen = 0
local inPass, passTarget = false, false

-- Is there a target: false only on a plain no. UnitExists can answer a secret
-- boolean in combat on Forever, and testing one throws; unknown lets the range
-- read run, which answers nil with no target. Only the fallback range read asks.
local function MaybeTarget()
    local e = UnitExists("target")
    if issecretvalue and issecretvalue(e) then return true end
    return e == true
end
local passU, passM = {}, {}   -- [sid] = this pass's usable / no-mana keys
Events.OnMessage("AD_DIRTY", "adcd_cfg", function() cfgGen = cfgGen + 1 end)

-- Range rides SPELL_RANGE_CHECK_UPDATE through NS.DriverRange (loaded after
-- this file). A client without C_Spell.EnableSpellRangeCheck sends no such
-- event: there the fallback pulse reads IsSpellInRange instead.
local function RangeByEvent()
    return NS.DriverRange ~= nil and C_Spell.EnableSpellRangeCheck ~= nil
end

-- The range engine counts wants per spell, so releasing an icon's check never
-- turns off a range bar's check on the same spell.
local function SetRangeWant(a, want)
    local old = a.rangeSid
    if old == want then return end
    local id = a.rec.id
    a.rangeKey = a.rangeKey or ("adcd:" .. id)
    a.rangeSid = want
    if old then
        local set = rangeIcons[old]
        if set then
            set[id] = nil
            if next(set) == nil then rangeIcons[old] = nil end
        end
        NS.DriverRange.WantSpellRange(a.rangeKey, old, false)
    end
    if want then
        local set = rangeIcons[want]
        if not set then
            set = {}
            rangeIcons[want] = set
        end
        set[id] = a
        NS.DriverRange.WantSpellRange(a.rangeKey, want, true)
    end
end

-- The settings the feeds read per icon, cached until the next change. A
-- refresh also drops the frame's skip signatures, so the setters rerun.
local function UsabCfg(a)
    if a.cfgGen == cfgGen then return end
    a.cfgGen = cfgGen
    local rec = a.rec
    a.rangeOn = Store.Resolve(rec, "states", "rangeTint") ~= false
    a.edgeOn = Store.Resolve(rec, "alerts", "usableSoundEnabled") == true
    a.kbOn = Factory.KeybindEnabled(rec)
    a.kbByName = Store.Resolve(rec, "keybind", "keybindByName") == true
    a.frame._adUsabSig = nil
    a.frame._adStateSig = nil
end

-- IsSpellUsable's answers as plain keys: 1 true, 2 false, 3 secret, 0 other.
-- A secret is only tested, never compared.
local function Key(v)
    if issecretvalue and issecretvalue(v) then return 3 end
    return (v == true and 1) or (v == false and 2) or 0
end

local function UsableKeys(sid)
    if inPass and passU[sid] then return passU[sid], passM[sid] end
    local u, m = C_Spell.IsSpellUsable(sid)
    u, m = Key(u), Key(m)
    if inPass then passU[sid], passM[sid] = u, m end
    return u, m
end

-- Can it be pressed now: usable (IsSpellUsable is plain on Forever) and off
-- its real cooldown (the GCD is ignored). nil when the read is secret.
local function UsableNow(a)
    local sid = a.effSid or (a.rec.driver and a.rec.driver.spellID)
    if not (sid and C_Spell.IsSpellUsable) then return nil end
    local u = UsableKeys(sid)
    if u == 3 then return nil end
    return u == 1 and not a.frame._adOnCooldown
end

-- "Play a sound when usable" on the edge into pressable, from either side (a
-- dodge lighting Mongoose Bite, its cooldown ending after one). Never on the
-- first read; re-checked after 0.15s, as the GCD filter can fake an edge.
local function EdgeFrom(a, now)
    if now == nil then return end
    if a.usableLast == false and now then
        local id = a.rec.id
        C_Timer.After(0.15, function()
            local live = attached[id]
            if live and UsableNow(live) == true then
                PlayAlert(live.rec, "usableSoundEnabled", "usableSound")
            end
        end)
    end
    a.usableLast = now
end

local function UsableEdge(a)
    UsabCfg(a)
    if not a.edgeOn then
        a.usableLast = nil
        return
    end
    EdgeFrom(a, UsableNow(a))
end

-- Keybinds (spells and custom timers)
-- The bars are walked in a fixed order instead of FindSpellActionButtons: its
-- order is undefined (a spell on two bars can report the side bar's key), and
-- it misses macro slots, other ranks and override forms.
local KB_BARS = {
    { start = 1,   binding = "ACTIONBUTTON",          button = "ActionButton" },            -- main bar wins ties
    { start = 61,  binding = "MULTIACTIONBAR1BUTTON", button = "MultiBarBottomLeftButton" },
    { start = 49,  binding = "MULTIACTIONBAR2BUTTON", button = "MultiBarBottomRightButton" },
    { start = 25,  binding = "MULTIACTIONBAR3BUTTON", button = "MultiBarRightButton" },
    { start = 37,  binding = "MULTIACTIONBAR4BUTTON", button = "MultiBarLeftButton" },
    { start = 145, binding = "MULTIACTIONBAR5BUTTON", button = "MultiBar5Button" },
    { start = 157, binding = "MULTIACTIONBAR6BUTTON", button = "MultiBar6Button" },
    { start = 169, binding = "MULTIACTIONBAR7BUTTON", button = "MultiBar7Button" },
}

local kbCache, kbDirty = {}, true
local kbExtraEvents = {}   -- the optional events that were registered

local function KBShort(key)
    if not key or key == "" then return nil end
    key = key:gsub("ALT%-", "a"):gsub("CTRL%-", "c"):gsub("SHIFT%-", "s")
        :gsub("MOUSEWHEELUP", "mwu"):gsub("MOUSEWHEELDOWN", "mwd")
        :gsub("BUTTON", "m"):gsub("NUMPAD", "n"):gsub("SPACE", "sp")
    if key == "" then return nil end
    return #key > 4 and key:sub(1, 4) or key
end

-- First write wins, so the walk order breaks ties.
local function KBRemember(id, txt)
    if id == nil then return end
    if issecretvalue and issecretvalue(id) then return end
    if kbCache[id] == nil then kbCache[id] = txt end
end

-- One button: the slot it shows (`.action` is the paged slot), its key and
-- whether it is visible. Fields are read with rawget: an action bar addon's
-- proxies throw on a plain index. No button means an addon owns the bar.
local function KBSlot(bar, i)
    local name = bar.button .. i
    local btn = _G[name]
    if btn and btn.IsForbidden and btn:IsForbidden() then btn = nil end
    local slot = bar.start + i - 1
    local bindingAction = bar.binding .. i
    if btn then
        local paged = rawget(btn, "action")
        if type(paged) == "number" and paged > 0 then slot = paged end
        local ba = rawget(btn, "bindingAction")
        if type(ba) == "string" and ba ~= "" then bindingAction = ba end
    end
    local key = GetBindingKey(bindingAction)
    if not key and btn then key = GetBindingKey("CLICK " .. name .. ":LeftButton") end
    local visible = (btn == nil) or (btn:IsVisible() == true)
    return slot, key, visible
end

local function KBRememberSlot(slot, txt)
    local atype, id, sub = GetActionInfo(slot)
    -- Macro slots count as the spell they cast, or macros would get no key.
    -- The client hands back that spell as the id with "spell" as the third
    -- return; only an older one returns the macro index.
    if atype == "macro" and id then
        if not (issecretvalue and issecretvalue(sub)) and sub == "spell" then
            atype = "spell"
        elseif GetMacroSpell then
            id, atype = GetMacroSpell(id), "spell"
        end
    end
    if atype == "spell" and id
        and not (issecretvalue and issecretvalue(id)) then
        KBRemember(id, txt)
        -- The bar may hold an override form: index the base too.
        if C_Spell and C_Spell.GetBaseSpell then
            local base = C_Spell.GetBaseSpell(id)
            if base and base ~= id then KBRemember(base, txt) end
        end
        -- Ranked realms: other ranks are unrelated IDs that share a name
        -- (GetBaseSpell links override forms only), so index the name too.
        if NS.IsForever and C_Spell and C_Spell.GetSpellName then
            local nm = C_Spell.GetSpellName(id)
            if nm and nm ~= "" then KBRemember("n:" .. nm, txt) end
        end
    end
end

local function KBWalk(wantVisible)
    local has = HasAction or (C_ActionBar and C_ActionBar.HasAction)
    for _, bar in ipairs(KB_BARS) do
        for i = 1, 12 do
            local slot, key, visible = KBSlot(bar, i)
            if visible == wantVisible and ((not has) or has(slot)) then
                local txt = KBShort(key)
                if txt then KBRememberSlot(slot, txt) end
            end
        end
    end
end

-- Action buttons from other bar layouts, found by global name: EnumerateFrames
-- returns half-built button objects. `.action` is read with rawget, since their
-- proxies throw on a plain index.
local ADDON_BUTTONS = {
    { prefix = "ElvUI_Bar", bars = 15, buttons = 12 },
    { prefix = "BT4Button", bars = 1, buttons = 180 },
    { prefix = "DominosActionButton", bars = 1, buttons = 180 },
}
local addonButtons, addonButtonsBuilt = {}, false

local function ForbiddenFrame(f)
    return f.IsForbidden and f:IsForbidden() == true
end

local function BuildAddonButtons()
    addonButtonsBuilt = true
    wipe(addonButtons)
    for _, info in ipairs(ADDON_BUTTONS) do
        for bar = 1, info.bars do
            for i = 1, info.buttons do
                local name = (info.bars > 1) and (info.prefix .. bar .. "Button" .. i)
                    or (info.prefix .. i)
                local btn = _G[name]
                if type(btn) == "table" and btn.IsVisible and not ForbiddenFrame(btn) then
                    addonButtons[#addonButtons + 1] = { btn = btn, name = name }
                end
            end
        end
    end
end

local function AddonButtonKey(btn, name)
    local hk = rawget(btn, "HotKey")
    if hk and hk.GetText then
        local t = hk:GetText()
        if issecretvalue and issecretvalue(t) then t = nil end
        if type(t) == "string" then
            t = t:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            local up = t:upper()
            if t ~= "" and up ~= "UNBOUND" and up ~= "RANGE"
                and not t:match("^[%.…]+$") and not t:find("%.%.") then
                return t
            end
        end
    end
    local gh = rawget(btn, "GetHotkey")
    if type(gh) == "function" then
        local k = gh(btn)
        if type(k) == "string" and k ~= "" and not k:match("^[%.…]+$") then return k end
    end
    local ba = rawget(btn, "bindingAction")
    if type(ba) == "string" and ba ~= "" then
        local k = GetBindingKey(ba)
        if k then return k end
    end
    local cn = rawget(btn, "commandName")
    if type(cn) == "string" and cn ~= "" then
        local k = GetBindingKey(cn)
        if k then return k end
    end
    return GetBindingKey("CLICK " .. name .. ":LeftButton")
end

local function KBWalkAddons()
    if not addonButtonsBuilt or #addonButtons == 0 then BuildAddonButtons() end
    for _, e in ipairs(addonButtons) do
        local btn = e.btn
        if not ForbiddenFrame(btn) and btn:IsVisible() == true then
            local slot = tonumber(rawget(btn, "action"))
            if slot and slot > 0 and HasAction and HasAction(slot) then
                local txt = KBShort(AddonButtonKey(btn, e.name))
                if txt then KBRememberSlot(slot, txt) end
            end
        end
    end
end

local function KBRebuild()
    kbDirty = false
    wipe(kbCache)
    if not (GetActionInfo and GetBindingKey) then return end
    -- Visible buttons first, so a copy the client auto-placed in a hidden
    -- main-bar slot cannot outrank the key in use. Hidden Blizzard buttons come
    -- last; their keys still work.
    KBWalk(true)
    KBWalkAddons()
    KBWalk(false)
end

-- Lookup order: the id, its base, its override, then (byName, ranked realms)
-- the spell's name, which matches whichever rank the bar holds.
local function KeybindFor(sid, byName)
    if not sid then return nil end
    if kbDirty then KBRebuild() end
    local txt = kbCache[sid]
    if txt then return txt end
    if C_Spell then
        if C_Spell.GetBaseSpell then
            local base = C_Spell.GetBaseSpell(sid)
            if base and base ~= sid and kbCache[base] then return kbCache[base] end
        end
        if C_Spell.GetOverrideSpell then
            local ov = C_Spell.GetOverrideSpell(sid)
            if ov and ov ~= sid and kbCache[ov] then return kbCache[ov] end
        end
        if byName and NS.IsForever and C_Spell.GetSpellName then
            local nm = C_Spell.GetSpellName(sid)
            if nm and nm ~= "" then return kbCache["n:" .. nm] end
        end
    end
end

local function ApplyKeybind(a)
    local rec = a.rec
    if rec.kind ~= "spell" and rec.kind ~= "timer" then return end
    UsabCfg(a)
    local txt
    if a.kbOn then
        local byName = a.kbByName
        -- the rank / override the feed resolved first (that is what the bar
        -- most likely holds), then the stored id
        local sid = rec.driver and rec.driver.spellID
        if a.effSid and a.effSid ~= sid then txt = KeybindFor(a.effSid, byName) end
        if not txt and sid then txt = KeybindFor(sid, byName) end
    end
    Factory.SetKeybindText(a.frame, txt)
end

-- The key an icon shows, for the options preview; nil when keybinds are off
-- for it or no bar holds the spell.
function Driver.KeybindTextFor(rec)
    if not (rec and rec.driver and Factory.KeybindEnabled(rec)) then return nil end
    local sid = rec.driver.spellID
    if not sid then return nil end
    local byName = Store.Resolve(rec, "keybind", "keybindByName") == true
    local live = attached[rec.id]
    local eff = live and live.effSid
    local txt
    if eff and eff ~= sid then txt = KeybindFor(eff, byName) end
    if not txt then txt = KeybindFor(sid, byName) end
    return txt
end

-- /adkeys <spell id or name>: every bar button that holds the spell (any
-- rank), with its key and whether it is visible.
SLASH_ADKEYS1 = "/adkeys"
SlashCmdList.ADKEYS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        print("|cff3fc9f2Arc Auras keys:|r /adkeys <spell id or name> - list the bar buttons that hold it")
        return
    end
    local wantID = tonumber(msg)
    local wantName = (not wantID) and msg:lower() or nil
    if wantID and C_Spell.GetSpellName then
        local nm = C_Spell.GetSpellName(wantID)
        if nm and nm ~= "" then wantName = nm:lower() end
    end
    print(("|cff3fc9f2Arc Auras keys|r for %s (cache %s, by-name index %s)"):format(
        msg, kbDirty and "stale" or "built", NS.IsForever and "on" or "off"))
    local n = 0
    for _, bar in ipairs(KB_BARS) do
        for i = 1, 12 do
            local slot, key, visible = KBSlot(bar, i)
            local atype, id, sub = GetActionInfo(slot)
            if atype == "macro" and id then
                if not (issecretvalue and issecretvalue(sub)) and sub == "spell" then atype = "spell"
                elseif GetMacroSpell then id, atype = GetMacroSpell(id), "spell" end
            end
            if atype == "spell" and id and not (issecretvalue and issecretvalue(id)) then
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                if id == wantID or (wantName and nm and nm:lower() == wantName) then
                    n = n + 1
                    print(("  %s%d (slot %d): %s [%d], key %s, %s"):format(
                        bar.button, i, slot, nm or "?", id, key or "none",
                        visible and "visible" or "HIDDEN"))
                end
            end
        end
    end
    if not addonButtonsBuilt or #addonButtons == 0 then BuildAddonButtons() end
    for _, e in ipairs(addonButtons) do
        local btn = e.btn
        if not ForbiddenFrame(btn) then
            local slot = tonumber(rawget(btn, "action"))
            if slot and slot > 0 and HasAction and HasAction(slot) then
                local atype, id, sub = GetActionInfo(slot)
                if atype == "macro" and id then
                    if not (issecretvalue and issecretvalue(sub)) and sub == "spell" then atype = "spell"
                    elseif GetMacroSpell then id, atype = GetMacroSpell(id), "spell" end
                end
                if atype == "spell" and id and not (issecretvalue and issecretvalue(id)) then
                    local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    if id == wantID or (wantName and nm and nm:lower() == wantName) then
                        n = n + 1
                        print(("  %s (addon, slot %d): %s [%d], key %s, %s"):format(
                            e.name, slot, nm or "?", id, tostring(AddonButtonKey(btn, e.name) or "none"),
                            btn:IsVisible() and "visible" or "HIDDEN"))
                    end
                end
            end
        end
    end
    if n == 0 then print("  not on any action bar button (Blizzard or addon)") end
end

local function PushState(a)
    local m = a.sCD:IsShown() == true
    local c = a.isCharge and a.sCharge:IsShown() == true or false
    -- m: the main cooldown runs (for a charge spell, every charge is spent).
    -- c: a charge is recharging. Dim on m, or on c unless waitForNoCharges.
    -- Desaturation follows m alone: a charge spell desaturates only when spent.
    local wait = Store.Resolve(a.rec, "states", "waitForNoCharges") == true
    local dim = m or (c and not wait)
    -- Ready sound on the dim-to-ready edge, re-checked after 0.15s because the
    -- GCD filter can report a transient edge. A first push never fires.
    if a.lastDim == true and dim == false then
        local id = a.rec.id
        C_Timer.After(0.15, function()
            local live = attached[id]
            if live and live.sCD:IsShown() ~= true then
                PlayReadyAlert(live.rec)
            end
        end)
    end
    a.lastDim = dim
    -- Other alerts come from shadow edges, not secret numbers: cooldown start,
    -- recharge start, and a charge back while the spell stays castable.
    if a.lastM ~= nil then
        if m and a.lastM == false then
            PlayAlert(a.rec, "cooldownSoundEnabled", "cooldownSound")
        end
        if a.isCharge then
            if c and a.lastC == false then
                PlayAlert(a.rec, "rechargeSoundEnabled", "rechargeSound")
            end
            if c == false and a.lastC == true and m == false then
                PlayAlert(a.rec, "chargeGainedSoundEnabled", "chargeGainedSound")
            end
        end
    end
    a.lastM, a.lastC = m, c
    -- Every GCD feeds every icon: SetState repaints only when a plain input
    -- it reads moved. ApplyStyle, a settings change and a re-attach drop
    -- f._adStateSig; a proc, a usability code or a combat edge is in it.
    local f = a.frame
    UsabCfg(a)
    local sig = (dim and "d" or "-") .. (m and "m" or "-") .. (f._adProcOn and "p" or "-")
        .. (InCombatLockdown() and "c" or "-") .. (f._adUsability or "") .. "|" .. (f._adGlowLaneOnly or "")
    if f._adStateSig ~= sig then
        f._adStateSig = sig
        Factory.SetState(f, a.rec, dim, m)
    end
    -- a state write moves what the usability skip froze: its next feed paints
    f._adUsabSig = nil
    UsableEdge(a)
end

local function QueueState(a)
    Events.Coalesce("adcd_state_" .. a.rec.id, function()
        local live = attached[a.rec.id]
        if live then PushState(live) end
    end)
end

-- One re-feed at the GCD's end. 61304 is the GCD; its numbers read plain in
-- normal play but are guarded, with a 0.3s fallback. Chained GCDs re-arm.
local function SchedulePostGCDRepush(a)
    if a.postGCDQueued then return end
    a.postGCDQueued = true
    local delay = 0.3
    local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(61304)
    if cd then
        local s, d = cd.startTime, cd.duration
        if not (issecretvalue and (issecretvalue(s) or issecretvalue(d)))
            and type(s) == "number" and type(d) == "number" and d > 0 then
            local rem = (s + d) - GetTime()
            if rem > 0 and rem < 2 then delay = rem + 0.05 end
        end
    end
    C_Timer.After(delay, function()
        a.postGCDQueued = nil
        local live = attached[a.rec.id]
        if live then Feed(live) end
    end)
end

Feed = function(a)
    local sid = a.rec.driver and a.rec.driver.spellID
    if not sid or not C_Spell.GetSpellCooldownDuration then return end
    -- Auto rank (ranked realms): GetSpellIDForSpellIdentifier(name) gives the
    -- rank the player knows, and SPELLS_CHANGED re-feeds when one is learned.
    -- The spell's own name is used (cached per id), not the record's.
    if a.rec.driver.autoRank and C_Spell.GetSpellIDForSpellIdentifier then
        if a.nameForSid ~= sid and C_Spell.GetSpellName then
            local nm = C_Spell.GetSpellName(sid)
            if nm and nm ~= "" then a.nameForSid, a.spellName = sid, nm end
        end
        if a.nameForSid == sid then
            local rid = C_Spell.GetSpellIDForSpellIdentifier(a.spellName)
            if rid then sid = rid end
        end
    end
    -- A replaced spell's cooldown (Stormstrike to Windstrike) lives on the
    -- override id; GetOverrideSpell is plain. ignoreSpellOverride opts out.
    if not a.rec.driver.ignoreSpellOverride and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if ov and ov ~= 0 and ov ~= sid then sid = ov end
    end
    -- a new rank / override takes over the range check at the end of this feed
    local rangeMoved = a.rangeSid ~= nil and a.rangeSid ~= sid
    a.effSid = sid
    -- the tooltip shows this rank / override too (our own frame field)
    a.frame._adEffSid = sid

    -- isOnGCD (never secret) backs up ignoreGCD, which is unproven on Forever:
    -- a spell waiting only on the GCD skips the main shadow and, with the GCD
    -- swipe hidden, the swipe.
    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = cdInfo and cdInfo.isOnGCD
    if issecretvalue and issecretvalue(onGcd) then onGcd = nil end
    onGcd = (onGcd == true)
    -- isEnabled false is a toggle that is on (Stealth's cooldown starts when
    -- you leave it). Like Blizzard's button, that counts as ready.
    local en = cdInfo and cdInfo.isEnabled
    if issecretvalue and issecretvalue(en) then en = nil end
    local disabled = (en == false)

    -- The wand's lock is ignored like the GCD. A cooldown already running keeps
    -- its own timing (the lock could only stretch its tail): nothing is re-pushed.
    -- Running means the last pushed state says so: a new shadow shows before
    -- its first feed. On the wand's own icon the lock is its real cooldown.
    local wandLock = Driver.WandLocked() and not Driver.IsWandShot(sid)
    local hold = wandLock and a.lastM == true and a.sCD:IsShown() == true
    local wandGCD = wandLock and not hold
    if wandGCD then onGcd = true end

    -- Shadows always ignore the GCD: state must not see it.
    if not hold then
        local mainDur = C_Spell.GetSpellCooldownDuration(sid, true)
        if mainDur and not onGcd and not disabled then
            a.sCD:SetCooldownFromDurationObject(mainDur, true)
        else
            a.sCD:Clear()
        end
    end
    if a.isCharge and C_Spell.GetSpellChargeDuration then
        local chargeDur = C_Spell.GetSpellChargeDuration(sid, true)
        if chargeDur then
            a.sCharge:SetCooldownFromDurationObject(chargeDur, true)
        else
            a.sCharge:Clear()
        end
    end

    local m = a.sCD:IsShown() == true
    local c = a.isCharge and a.sCharge:IsShown() == true or false
    -- How this GCD spin draws; the wand's lock has its own look.
    local look = Store.Resolve(a.rec, "swipe", wandGCD and "wandSwipe" or "gcdSwipe")
    local noGCD = (look or "hidden") == "hidden"

    -- Visible swipe. The shadows ignore the GCD, so a duration that lands while
    -- both are clear is the GCD (or a GCD-length blip): pureGCD draws it as an
    -- edge only, not the dark fill.
    local cooldown = a.frame.cooldown
    local pureGCD = false
    if hold then
        -- the running cooldown keeps the swipe it was given
    elseif a.isCharge then
        if c and not m then
            local dur = C_Spell.GetSpellChargeDuration(sid, true)
            if dur then cooldown:SetCooldownFromDurationObject(dur, true)
            else cooldown:Clear() end
        elseif m then
            local dur = C_Spell.GetSpellCooldownDuration(sid, true)
            if dur then cooldown:SetCooldownFromDurationObject(dur, true)
            else cooldown:Clear() end
        else
            local dur = C_Spell.GetSpellCooldownDuration(sid, noGCD and true or nil)
            if dur and not (noGCD and onGcd) and not disabled then
                cooldown:SetCooldownFromDurationObject(dur, true)
                pureGCD = true
            else cooldown:Clear() end
        end
    else
        local dur = C_Spell.GetSpellCooldownDuration(sid, noGCD and true or nil)
        if dur and not (noGCD and onGcd) and not disabled then
            cooldown:SetCooldownFromDurationObject(dur, true)
            pureGCD = not m
        else cooldown:Clear() end
    end
    -- hidden GCD: one settled re-feed at its end picks up whatever real
    -- cooldown started underneath it (none can start under the wand's lock)
    if noGCD and onGcd and not wandGCD then SchedulePostGCDRepush(a) end
    -- Recharging (a charge left, another on its way): the wait-for-no-charges
    -- options can suppress the dark fill and edge there.
    Factory.SetGCDPresentation(a.frame, a.rec, pureGCD, a.isCharge and c and not m, wandGCD)

    Factory.SetChargeText(a.frame, a.rec, sid, a.isCharge)
    -- charges-available flag for hide-duration-with-charges (shadow-derived)
    a.frame._adChargesAvail = (a.isCharge and c and not m) or nil
    Factory.ApplyDurationVis(a.frame, a.rec)
    ApplyKeybind(a)

    PushState(a)
    if rangeMoved then FeedUsability(a) end
end

local function FeedAll()
    for _, a in pairs(attached) do Feed(a) end
end

local function FeedCharges()
    for _, a in pairs(attached) do
        if a.isCharge then Feed(a) end
    end
end

-- A wand shot's own update: only the icons tracking the wand itself (the update
-- carries their cooldown) or drawing its lock re-read.
local function FeedWandLooks()
    for _, a in pairs(attached) do
        local sid = a.effSid or (a.rec.driver and a.rec.driver.spellID)
        if Driver.IsWandShot(sid)
            or (Store.Resolve(a.rec, "swipe", "wandSwipe") or "hidden") ~= "hidden" then
            Feed(a)
        end
    end
end

-- Items and trinkets
-- Item cooldowns are plain on retail 12.x, the one place SetCooldown is
-- allowed. They are unproven on Forever, so the plain path sits behind a
-- secrecy check: tonumber, compares and SetCooldown all throw on a secret.

local attachedItems = {}   -- [iconId] = { rec, frame }

-- A trinket with no use spell. Item data not loaded yet reads as on-use, so a
-- real one is never hidden: the game is asked for it, and its arrival
-- re-feeds the trinket icons (GET_ITEM_INFO_RECEIVED in EnsureEvents).
Driver.itemDataWanted = false
function Driver.IsPassiveItem(itemID)
    if not (C_Item and C_Item.GetItemSpell) then return false end
    if C_Item.GetItemSpell(itemID) ~= nil then return false end
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        Driver.itemDataWanted = true
        return false
    end
    return true
end

-- onCd is always plain here: from plain numbers or the widget's IsShown.
local function FinishItemState(a, onCd)
    local rec = a.rec
    if a.lastOn == true and onCd == false then
        PlayReadyAlert(rec)
    end
    if a.lastOn == false and onCd == true then
        PlayAlert(rec, "cooldownSoundEnabled", "cooldownSound")
    end
    a.lastOn = onCd
    Factory.SetState(a.frame, rec, onCd, onCd)
end

local function FeedItem(a)
    local rec = a.rec
    local d = rec.driver or {}
    local start, duration, enable
    if rec.kind == "trinket" then
        start, duration, enable = GetInventoryItemCooldown("player", d.slotID or 13)
    elseif C_Container and C_Container.GetItemCooldown and d.itemID then
        start, duration, enable = C_Container.GetItemCooldown(d.itemID)
    end
    -- Count first, whatever the cooldown secrecy: SetText takes it raw (a
    -- secret-safe sink); the empty flag changes only on a plain count.
    if rec.kind == "item" and d.itemID and C_Item and C_Item.GetItemCount then
        local cnt = C_Item.GetItemCount(d.itemID, false, true)
        if Store.Resolve(rec, "text", "stackText") ~= false then
            a.frame.stackText:SetText(cnt)
        end
        if cnt ~= nil and not (issecretvalue and issecretvalue(cnt)) then
            a.frame._adItemEmpty = (cnt == 0)
        end
    end
    if rec.kind == "trinket" then
        -- The item id is plain, and a secret compared with nil still gives a
        -- plain false, so this is legal either way.
        local iid = GetInventoryItemID("player", d.slotID or 13)
        a.frame._adItemEmpty = (iid == nil) or nil
        a.frame._adPassive = (iid ~= nil and Store.Resolve(rec, "trinket", "onlyOnUse") == true
            and Driver.IsPassiveItem(iid)) or nil
    end
    -- Ammo: the equipped stack. GetInventoryItemCount has no secrecy annotation
    -- and Blizzard's item buttons compare it; it still goes to SetText raw.
    if rec.kind == "ammo" then
        local cnt = GetInventoryItemCount("player", AMMO_SLOT)
        if Store.Resolve(rec, "text", "stackText") ~= false then
            a.frame.stackText:SetText(cnt or "")
            Factory.AmmoCountColor(a.frame.stackText, rec, "stackColor")
        end
        a.frame._adItemEmpty = (GetInventoryItemID("player", AMMO_SLOT) == nil) or nil
    end
    -- Secret item cooldowns (spell ones are secret on Forever) go through a
    -- duration object, which accepts secrets; the state is read back off the
    -- widget and OnCooldownDone re-feeds at expiry. No arithmetic on a secret.
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)
        or issecretvalue(enable)) then
        if C_DurationUtil and C_DurationUtil.CreateDuration then
            local durObj = a.durObj
            if not durObj then
                durObj = C_DurationUtil.CreateDuration()
                a.durObj = durObj
            end
            durObj:SetTimeFromStart(start, duration)
            a.frame.cooldown:SetCooldownFromDurationObject(durObj)
            local id = rec.id
            a.frame.cooldown:SetScript("OnCooldownDone", function(w)
                w:SetScript("OnCooldownDone", nil)
                local live = attachedItems[id]
                if live then FeedItem(live) end
            end)
            FinishItemState(a, a.frame.cooldown:IsShown() == true)
        end
        return
    end
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    -- >1.5s filters the item-GCD blip, the standard item-cooldown rule
    local onCd = (enable == 1 or enable == true) and duration > 1.5
        and (start + duration - GetTime()) > 0
    if onCd then
        a.frame.cooldown:SetCooldown(start, duration)
        -- item events do not reliably fire at expiry: one settle re-check
        if not a.expiryQueued then
            a.expiryQueued = true
            local rem = start + duration - GetTime()
            C_Timer.After(math.max(rem, 0) + 0.05, function()
                a.expiryQueued = nil
                local live = attachedItems[rec.id]
                if live then FeedItem(live) end
            end)
        end
    else
        a.frame.cooldown:Clear()
    end
    FinishItemState(a, onCd)
end

-- Usability and range (spells)
-- A secret boolean (restricted content) throws on a test: check it first.
-- A feed whose plain inputs match the frame's last signature stops before the
-- setters; every other writer of these visuals drops f._adUsabSig.
local CODE_N = { range = 1, nomana = 2, unusable = 3 }

FeedUsability = function(a)
    -- the tracked rank / override: mana cost and range belong to it
    local sid = a.effSid or (a.rec.driver and a.rec.driver.spellID)
    if not sid then return end
    UsabCfg(a)
    local f = a.frame
    local code
    if RangeByEvent() then
        -- the engine's last plain answer: out only on checksRange true, isInRange false
        SetRangeWant(a, a.rangeOn and sid or nil)
        if a.rangeOn and NS.DriverRange.SpellOut(sid) then code = "range" end
    elseif a.rangeOn and C_Spell.IsSpellInRange then
        local target = passTarget
        if not inPass then target = MaybeTarget() end
        if target then
            local inRange = C_Spell.IsSpellInRange(sid, "target")
            if not (issecretvalue and issecretvalue(inRange)) and inRange == false then
                code = "range"
            end
        end
    end
    local u
    if C_Spell.IsSpellUsable and (not code or a.edgeOn) then
        local m
        u, m = UsableKeys(sid)
        -- a secret in either answer leaves the icon usable
        if not code and u ~= 3 and m ~= 3 then
            if m == 1 then
                code = "nomana"
            elseif u == 2 then
                code = "unusable"
            end
        end
    end
    -- the usable sound's input: pressable now, nil when unknown
    local now
    if a.edgeOn and u and u ~= 3 then now = u == 1 and not f._adOnCooldown end
    local sig = sid * 16 + (CODE_N[code] or 0) + (now == nil and 0 or (now and 4 or 8))
    if f._adUsabSig == sig then return end
    f._adUsabSig = sig
    Factory.SetUsability(f, a.rec, code)
    if a.edgeOn then EdgeFrom(a, now) else a.usableLast = nil end
end

local function FeedUsabilityAll()
    wipe(passU)
    wipe(passM)
    -- one target read per pass, for the fallback's range reads only
    inPass, passTarget = true, (not RangeByEvent()) and MaybeTarget()
    for _, a in pairs(attached) do FeedUsability(a) end
    inPass = false
end

-- A range answer moved: repaint only the icons on that spell.
local function OnSpellRange(sid)
    local set = rangeIcons[sid]
    if not set then return end
    for _, a in pairs(set) do
        a.frame._adUsabSig = nil
        FeedUsability(a)
    end
end

PlayReadyAlert = function(rec)
    PlayAlert(rec, "readySoundEnabled", "readySound")
end

-- Totems
-- GetTotemDuration(slot) gives a duration object while the slot is live and
-- nothing when empty, so a shadow's IsShown() is the state. GetTotemInfo's
-- haveTotem is a secret boolean. A live totem shows as ready. An icon that
-- follows one totem by spell asks NS.DriverTotem which slot holds it.

local attachedTotems = {}     -- [iconId] = { rec, frame, shadow }
local totemShadowCache = {}   -- [iconId] = shadow, kept across detach

local function FeedTotem(a)
    local DT = NS.DriverTotem
    local slot
    if DT then slot = DT.SlotFor(a.rec) else slot = (a.rec.driver and a.rec.driver.slot) or 1 end
    local dur = slot and GetTotemDuration and GetTotemDuration(slot)
    if dur and a.shadow.SetCooldownFromDurationObject then
        a.shadow:SetCooldownFromDurationObject(dur, true)
        a.frame.cooldown:SetCooldownFromDurationObject(dur, true)
    else
        a.shadow:Clear()
        a.frame.cooldown:Clear()
    end
    -- totem art follows the live totem (display-only field, safe sink)
    a.frame.icon:SetTexture(Factory.GetTexture(a.rec))
    local active = a.shadow:IsShown() == true
    Factory.SetState(a.frame, a.rec, not active, not active)
    if DT then DT.Pulse(a.frame, a.rec, slot, active) end
end

local function FeedAllTotems()
    for _, a in pairs(attachedTotems) do FeedTotem(a) end
end
Driver.FeedTotems = FeedAllTotems

local function FeedAllItems()
    for _, a in pairs(attachedItems) do FeedItem(a) end
end

-- Ammo count on spell icons (arrows on Auto Shot). Factory.ApplyStyle owns
-- the look and Show/Hide; this sets only the number.
local function ApplyAmmoText(a)
    local f, rec = a.frame, a.rec
    if not (f and f.ammoText) then return end
    if Store.Resolve(rec, "text", "ammoText") ~= true then
        f.ammoText:SetText("")
        return
    end
    f.ammoText:SetText(GetInventoryItemCount("player", AMMO_SLOT) or "")
    Factory.AmmoCountColor(f.ammoText, rec, "ammoColor")
end

local function FeedAmmoAll()
    for _, a in pairs(attached) do ApplyAmmoText(a) end
    FeedAllItems()
end

local registered = false
local function EnsureEvents()
    if registered then return end
    registered = true
    Events.On("SPELL_UPDATE_COOLDOWN", "adcd", function(_, spellID, baseSpellID)
        -- a wand shot's own update carries only its lock
        if Driver.IsWandShot(spellID) or Driver.IsWandShot(baseSpellID) then
            Events.Coalesce("adcd_feedwand", FeedWandLooks)
            return
        end
        Events.Coalesce("adcd_feedall", FeedAll)
    end)
    Events.On("SPELL_UPDATE_CHARGES", "adcd", function()
        Events.Coalesce("adcd_feedcharges", FeedCharges)
    end)
    Events.On("UNIT_SPELLCAST_SUCCEEDED", "adcd", function(_, unit, _, spellID)
        if unit ~= "player" then return end
        Driver.NoteCast(spellID)
        for _, a in pairs(attached) do
            -- the cast carries the rank / override id (Auto rank)
            if a.rec.driver and (a.rec.driver.spellID == spellID
                or a.effSid == spellID) then Feed(a) end
        end
    end)
    Events.On("BAG_UPDATE_COOLDOWN", "adcd", function()
        Events.Coalesce("adcd_feeditems", FeedAllItems)
    end)
    Events.On("BAG_UPDATE_DELAYED", "adcd", function()
        -- item counts move without a cooldown event
        Events.Coalesce("adcd_feedammo", FeedAmmoAll)
    end)
    -- Ammo shrinks as you shoot; Blizzard's paper doll tracks it by this event.
    Events.On("UNIT_INVENTORY_CHANGED", "adcd_ammo", function(_, unit)
        if unit and unit ~= "player" then return end
        Events.Coalesce("adcd_feedammo", FeedAmmoAll)
    end)
    Events.On("SPELL_UPDATE_USABLE", "adcd", function()
        Events.Coalesce("adcd_usab", FeedUsabilityAll)
    end)
    Events.On("PLAYER_TARGET_CHANGED", "adcd_usab", function()
        Events.Coalesce("adcd_usab", FeedUsabilityAll)
    end)
    Events.On("PLAYER_TOTEM_UPDATE", "adcd_totem", function()
        Events.Coalesce("adcd_feedtotems", FeedAllTotems)
    end)
    -- Range answers arrive by event. The 0.25 s pulse is only the fallback for
    -- a client without C_Spell.EnableSpellRangeCheck, which has no such event.
    if RangeByEvent() then
        NS.DriverRange.OnSpellRange("adcd", OnSpellRange)
    elseif not rangeTicker and C_Timer and C_Timer.NewTicker then
        rangeTicker = C_Timer.NewTicker(0.25, function()
            if MaybeTarget() then FeedUsabilityAll() end
        end)
    end
    Events.On("PLAYER_EQUIPMENT_CHANGED", "adcd_items", function()
        Events.Coalesce("adcd_feedammo", FeedAmmoAll)
    end)
    -- a trinket read as on-use while its data loaded: settle it now
    Events.On("GET_ITEM_INFO_RECEIVED", "adcd_items", function()
        if not Driver.itemDataWanted then return end
        Driver.itemDataWanted = false
        Events.Coalesce("adcd_feeditems", FeedAllItems)
    end)
    Events.On("PLAYER_ENTERING_WORLD", "adcd", function()
        -- addon bars build at their own login step: re-discover them and
        -- re-read every key after each loading screen
        addonButtonsBuilt = false
        kbDirty = true
        Events.Coalesce("adcd_feedall", FeedAll)
        Events.Coalesce("adcd_feedammo", FeedAmmoAll)
    end)
    Events.On("SPELLS_CHANGED", "adcd", function()
        -- Charges can change with talents or spec. A charge spell has
        -- maxCharges > 1: single-charge spells return a charges table too.
        for _, a in pairs(attached) do
            local sid = a.effSid or (a.rec.driver and a.rec.driver.spellID)
            local info = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
            a.isCharge = (info and (info.maxCharges or 0) > 1) == true
        end
        Events.Coalesce("adcd_feedall", FeedAll)
    end)
    -- The cache must be stale before icons re-resolve; KeybindFor rebuilds it.
    Events.On("UPDATE_BINDINGS", "adcd_kb", function()
        kbDirty = true
        for _, a in pairs(attached) do ApplyKeybind(a) end
    end)
    Events.On("ACTIONBAR_SLOT_CHANGED", "adcd_kb", function()
        kbDirty = true
        Events.Coalesce("adcd_kb_all", function()
            for _, a in pairs(attached) do ApplyKeybind(a) end
        end)
    end)
    -- Paging and stance swaps change slots without a slot event for each. The
    -- events are probed, since Forever throws on registering one it lacks.
    local function KBRefresh()
        kbDirty = true
        Events.Coalesce("adcd_kb_all", function()
            for _, a in pairs(attached) do ApplyKeybind(a) end
        end)
    end
    for _, e in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
        if (not (C_EventUtils and C_EventUtils.IsEventValid))
            or C_EventUtils.IsEventValid(e) then
            kbExtraEvents[#kbExtraEvents + 1] = e
            Events.On(e, "adcd_kb", KBRefresh)
        end
    end
    -- Proc overlays. The payload can be the override id, so match the stored id
    -- and the last effective id.
    Events.On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "adcd", function(_, spellID)
        for _, a in pairs(attached) do
            if a.rec.driver and (a.rec.driver.spellID == spellID
                or a.effSid == spellID) then
                Factory.SetProcGlow(a.frame, a.rec, true)
            end
        end
    end)
    Events.On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "adcd", function(_, spellID)
        for _, a in pairs(attached) do
            if a.rec.driver and (a.rec.driver.spellID == spellID
                or a.effSid == spellID) then
                Factory.SetProcGlow(a.frame, a.rec, false)
            end
        end
    end)
end

local function MaybeReleaseEvents()
    if not registered or next(attached) or next(attachedItems)
        or next(attachedTotems) then return end
    registered = false
    Events.Off("PLAYER_TOTEM_UPDATE", "adcd_totem")
    Events.Off("SPELL_UPDATE_COOLDOWN", "adcd")
    Events.Off("SPELL_UPDATE_CHARGES", "adcd")
    Events.Off("UNIT_SPELLCAST_SUCCEEDED", "adcd")
    Events.Off("BAG_UPDATE_COOLDOWN", "adcd")
    Events.Off("BAG_UPDATE_DELAYED", "adcd")
    Events.Off("UNIT_INVENTORY_CHANGED", "adcd_ammo")
    Events.Off("SPELL_UPDATE_USABLE", "adcd")
    Events.Off("PLAYER_TARGET_CHANGED", "adcd_usab")
    if rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
    if NS.DriverRange then NS.DriverRange.OnSpellRange("adcd", nil) end
    Events.Off("PLAYER_EQUIPMENT_CHANGED", "adcd_items")
    Events.Off("GET_ITEM_INFO_RECEIVED", "adcd_items")
    Events.Off("PLAYER_ENTERING_WORLD", "adcd")
    Events.Off("SPELLS_CHANGED", "adcd")
    Events.Off("UPDATE_BINDINGS", "adcd_kb")
    Events.Off("ACTIONBAR_SLOT_CHANGED", "adcd_kb")
    for _, e in ipairs(kbExtraEvents) do Events.Off(e, "adcd_kb") end
    wipe(kbExtraEvents)
    Events.Off("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "adcd")
    Events.Off("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "adcd")
end

function Driver.Attach(rec, f)
    if rec.kind ~= "spell" then
        if rec.kind == "aura" and NS.DriverAura then
            -- aura icons ride the engine-owned AuraContainer backend
            NS.DriverAura.Attach(rec, f)
            if NS.AuraSounds then NS.AuraSounds.Attach(rec) end
        elseif rec.kind == "trinket" or rec.kind == "item" or rec.kind == "ammo" then
            local ai = attachedItems[rec.id]
            if not ai then
                ai = {}
                attachedItems[rec.id] = ai
            end
            ai.rec, ai.frame = rec, f
            EnsureEvents()
            FeedItem(ai)
        elseif rec.kind == "totem" then
            local at = attachedTotems[rec.id]
            if not at then
                local shadow = totemShadowCache[rec.id]
                if not shadow then
                    shadow = MakeShadow()
                    totemShadowCache[rec.id] = shadow
                end
                at = { shadow = shadow }
                attachedTotems[rec.id] = at
            end
            at.rec, at.frame = rec, f
            EnsureEvents()
            -- the slot pairing reads every slot first
            if NS.DriverTotem then NS.DriverTotem.Attach(rec) end
            FeedTotem(at)
        elseif rec.kind == "enchant" and NS.DriverEnchant then
            NS.DriverEnchant.Attach(rec, f)
        elseif rec.kind == "timer" and NS.DriverCustom then
            -- a Custom Icon: its rules feed it (Drivers\AD_DriverCustom.lua)
            NS.DriverCustom.Attach(rec, f)
        elseif rec.kind == "special" and NS.SpecialIcon then
            -- a Special Aura: its tracker feeds it (Core\AD_SpecialIcon.lua)
            NS.SpecialIcon.Attach(rec, f)
        elseif rec.kind == "groupbuff" and NS.DriverGroupBuff then
            -- a Group Buff: who in the group has it (Drivers\AD_DriverGroupBuff.lua)
            NS.DriverGroupBuff.Attach(rec, f)
        else
            Factory.SetState(f, rec, false)
        end
        return
    end
    local a = attached[rec.id]
    if not a then
        local cache = shadowCache[rec.id]
        if not cache then
            cache = { sCD = MakeShadow(), sCharge = MakeShadow() }
            shadowCache[rec.id] = cache
        end
        a = { rec = rec, frame = f, sCD = cache.sCD, sCharge = cache.sCharge }
        attached[rec.id] = a
        -- State flips ride the shadows' OnShow/OnHide, which fire because the
        -- shadows are shown under UIParent: a hidden parent freezes IsShown and
        -- swallows both. OnCooldownDone backs up the expiry.
        local function bump() QueueState(a) end
        a.sCD:SetScript("OnShow", bump)
        a.sCD:SetScript("OnHide", bump)
        a.sCD:SetScript("OnCooldownDone", bump)
        a.sCharge:SetScript("OnCooldownDone", function()
            local live = attached[rec.id]
            if live then Feed(live) end   -- next charge re-feeds or lands full
        end)
    else
        a.rec, a.frame = rec, f
    end
    -- a (re)attach re-reads the settings and paints the usability in full
    a.cfgGen = nil
    local sid = rec.driver and rec.driver.spellID
    local info = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    a.isCharge = (info and (info.maxCharges or 0) > 1) == true
    EnsureEvents()
    Feed(a)
    FeedUsability(a)
    ApplyAmmoText(a)
    -- Aura on this icon: the aura driver lays its engine button over the holder
    -- while the option is on, and parks it when off.
    if NS.DriverAura and NS.DriverAura.AttachOverlay then
        NS.DriverAura.AttachOverlay(rec, f)
    end
end

function Driver.Detach(id)
    -- Every kind is released here. The aura driver parks its slots: engine
    -- slots cannot be destroyed.
    if NS.DriverAura then NS.DriverAura.Detach(id) end
    if NS.AuraSounds then NS.AuraSounds.Detach(id) end
    attachedItems[id] = nil
    local at = attachedTotems[id]
    if at and NS.DriverTotem then NS.DriverTotem.Detach(id, at.frame) end
    attachedTotems[id] = nil
    if NS.DriverEnchant then NS.DriverEnchant.Detach(id) end
    if NS.DriverCustom then NS.DriverCustom.Detach(id) end
    if NS.SpecialIcon then NS.SpecialIcon.Detach(id) end
    if NS.DriverGroupBuff then NS.DriverGroupBuff.Detach(id) end
    local a = attached[id]
    if a then
        SetRangeWant(a, nil)
        if a.frame then
            a.frame._adEffSid = nil
            a.frame._adUsabSig = nil
            a.frame._adStateSig = nil
        end
        a.sCD:SetScript("OnShow", nil)
        a.sCD:SetScript("OnHide", nil)
        a.sCD:SetScript("OnCooldownDone", nil)
        a.sCharge:SetScript("OnCooldownDone", nil)
        a.sCD:Clear()
        a.sCharge:Clear()
        attached[id] = nil
    end
    MaybeReleaseEvents()
end

function Driver.Refeed(id)
    local a = attached[id]
    if a then Feed(a) end
    local ai = attachedItems[id]
    if ai then FeedItem(ai) end
    local at = attachedTotems[id]
    if at then FeedTotem(at) end
    if NS.DriverEnchant then NS.DriverEnchant.Refeed(id) end
    if NS.DriverCustom then NS.DriverCustom.Refeed(id) end
    if NS.SpecialIcon then NS.SpecialIcon.Refeed(id) end
    if NS.DriverGroupBuff then NS.DriverGroupBuff.Refeed(id) end
end
