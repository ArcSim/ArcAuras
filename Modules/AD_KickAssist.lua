-- AD_KickAssist: the Kick Assist module (your kick marker, its macros, the interrupt alert), retail, off until switched on.
-- Settings: ArcAurasDB.kick holds the switch (on), the account-wide flag and
-- the shared setup; ArcAurasDB.kick.chars[charKey] holds each character's own.
-- Missing keys read as the defaults, so only changes are saved. The marking
-- itself is the game's secure /tm inside the player's macro: this only
-- rewrites the marker number in the macro text, out of combat.
local ADDON, NS = ...
local Events = NS.Events

local KA = {}
NS.KickAssist = KA

local KEY = "kickassist"
KA.KEY = KEY

-- Macro bodies. {interrupt} = the spec's kick, {marker} = the picked marker.
-- The ~ marks the focus only while it has no marker, so a re-press never moves it.
local DEFAULT_MACRO = "#showtooltip {interrupt}\n/cast [@focus,harm,nodead] {interrupt}\n/focus [@focus,noexists] target\n/tm [@focus] ~{marker}"
local SET_FOCUS_MACRO = "/focus target\n/tm [@focus] ~{marker}"
local AUTOTAB_MACRO = "#showtooltip {interrupt}\n/cleartarget\n/targetenemy\n/cast {interrupt}\n/targetlasttarget"
local AUTOTAB_FOCUS_MACRO = "#showtooltip {interrupt}\n/cast [@focus,exists,nodead,harm] {interrupt}\n/stopmacro [@focus,exists,nodead,harm]\n/focus target\n/cleartarget\n/targetenemy\n/cast {interrupt}\n/target focus\n/clearfocus\n/startattack"
local AUTOTAB_MOUSEOVER_MACRO = "#showtooltip\n/cast [@mouseover,harm,nodead][@focus,harm,nodead,exists] {interrupt}\n/stopmacro [@mouseover,harm,nodead][@focus,harm,nodead,exists]\n/focus target\n/cleartarget\n/targetenemy\n/cast {interrupt}\n/target focus\n/clearfocus"

KA.TEMPLATES = {
    kick = {
        { name = "Focus + Kick (default, re-press to kick)", body = DEFAULT_MACRO },
        { name = "Focus + Kick (Ctrl to kick your target)",
          body = "#showtooltip {interrupt}\n/cast [nomod:ctrl,@focus,harm,nodead][] {interrupt}\n/focus [@focus,noexists] target\n/tm [@focus] ~{marker}" },
        { name = "Focus + Kick (mouseover)",
          body = "#showtooltip {interrupt}\n/cast [@focus,harm,nodead] {interrupt}\n/focus [@mouseover,harm,nodead,exists] mouseover\n/tm [@focus] ~{marker}" },
    },
    focus = {
        { name = "Set focus (target)", body = SET_FOCUS_MACRO },
        { name = "Set focus (mouseover)", body = "/focus [@mouseover,exists] mouseover\n/tm [@focus] ~{marker}" },
    },
    autotab = {
        { name = "Tab Kick (tab to nearest)", body = AUTOTAB_MACRO },
        { name = "Tab Kick (focus first, else tab)", body = AUTOTAB_FOCUS_MACRO },
        { name = "Tab Kick (mouseover or focus, else tab)", body = AUTOTAB_MOUSEOVER_MACRO },
    },
}

local QUESTION_ICON = "INV_Misc_QuestionMark"
KA.FOCUS_ICON = 132212

-- onKey: a slot's macro is left alone until the player saves or drags it once,
-- so a macro of their own that shares the name is never rewritten.
KA.SLOT_CFG = {
    kick    = { label = "Focus + Kick", nameKey = "macroName", tmplKey = "macroTemplate", onKey = "macroEnabled",
                defName = "FocusKick", icon = QUESTION_ICON },
    focus   = { label = "Set Focus", nameKey = "setFocusName", tmplKey = "setFocusTemplate", onKey = "setFocusEnabled",
                defName = "SetFocus", icon = KA.FOCUS_ICON },
    autotab = { label = "Tab Kick", nameKey = "autoTabName", tmplKey = "autoTabTemplate", onKey = "autoTabEnabled",
                defName = "AutoTabKick", icon = QUESTION_ICON },
}
KA.SLOT_ORDER = { "kick", "focus", "autotab" }

-- The standalone addon's defaults.
KA.DEFAULTS = {
    marker = 8,
    showOnReadyCheck = true,
    announceOnReadyCheck = true,
    smartOpen = false,
    message = "My Focus Kick is %MARKER%",
    interruptAlert = false,
    interruptAlertTTS = false,
    interruptAlertText = "Kick",
    interruptAlertSound = "kit:8960",
    interruptAlertChannel = "Master",
    macroEnabled = false,
    setFocusEnabled = false,
    autoTabEnabled = false,
    macroName = "FocusKick",
    macroTemplate = DEFAULT_MACRO,
    setFocusName = "SetFocus",
    setFocusTemplate = SET_FOCUS_MACRO,
    autoTabName = "AutoTabKick",
    autoTabTemplate = AUTOTAB_MACRO,
}
-- What an account-wide setup shares, copied once from the first character.
-- The kick spell is never shared: it belongs to one class.
local SHARED_KEYS = { "contexts", "specs", "point" }
for k in pairs(KA.DEFAULTS) do SHARED_KEYS[#SHARED_KEYS + 1] = k end

-- Difficulty IDs: 1 Normal, 2 Heroic, 23 Mythic, 8 Mythic Keystone.
KA.CONTEXT_DEFAULTS = { mplus = true, mythic = true, heroic = false, normal = false, raid = false }
KA.CONTEXT_ORDER = { "mplus", "mythic", "heroic", "normal", "raid" }
KA.CONTEXT_LABELS = {
    mplus = "Mythic+ (keystone)",
    mythic = "Mythic dungeons",
    heroic = "Heroic dungeons",
    normal = "Normal dungeons",
    raid = "Raid instances",
}

-- Kick spell per class, spec overrides by specialization ID; missing = no kick.
-- Demonology's Felguard stops casts with Axe Toss, not Spell Lock.
local INTERRUPTS = {
    DEATHKNIGHT = { default = 47528 },
    DEMONHUNTER = { default = 183752 },
    DRUID       = { default = 106839, [102] = 78675 },
    EVOKER      = { default = 351338 },
    HUNTER      = { default = 147362, [255] = 187707 },
    MAGE        = { default = 2139 },
    MONK        = { default = 116705 },
    PALADIN     = { default = 96231 },
    PRIEST      = { [258] = 15487 },
    ROGUE       = { default = 1766 },
    SHAMAN      = { default = 57994 },
    WARLOCK     = { default = 19647, [266] = 89766 },
    WARRIOR     = { default = 6552 },
}
KA.INTERRUPTS = INTERRUPTS

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

-- Settings

-- ArcAurasDB.kick, made on the first write; nil before the saved variables load.
function KA.Root(create)
    local db = ArcAurasDB
    if type(db) ~= "table" then return nil end
    local k = db.kick
    if type(k) ~= "table" then
        if not create then return nil end
        k = {}
        db.kick = k
    end
    return k
end

-- Writes made while the character's name is unreadable wait here and move
-- into its own table once the name reads, so nothing lands under "?".
local pendingChar
local function CharKeyNow()
    local Store = NS.Store
    local key = Store and Store.CharKey and Store.CharKey()
    if type(key) ~= "string" or key == "?" or key:find("-?", 1, true) then return nil end
    return key
end

function KA.Char(create)
    local key = CharKeyNow()
    if not key then
        if create and not pendingChar then pendingChar = {} end
        return pendingChar
    end
    local want = create or pendingChar ~= nil
    local root = KA.Root(want)
    if not root then return nil end
    local chars = root.chars
    if type(chars) ~= "table" then
        if not want then return nil end
        chars = {}
        root.chars = chars
    end
    local c = chars[key]
    if type(c) ~= "table" then
        if not want then return nil end
        c = {}
        chars[key] = c
    end
    if pendingChar then
        for k, v in pairs(pendingChar) do c[k] = v end
        pendingChar = nil
    end
    return c
end

function KA.AccountWide()
    local r = KA.Root()
    return r ~= nil and r.accountWide == true
end

-- The store the setup reads: the shared one while account-wide, else this character's.
function KA.Active(create)
    if KA.AccountWide() then return KA.Root(create) end
    return KA.Char(create)
end

function KA.Get(k)
    local s = KA.Active()
    local v = s and s[k]
    if v == nil then v = KA.DEFAULTS[k] end
    return v
end

-- A default is stored as nil, so the save holds only changes.
function KA.Set(k, v)
    if v == KA.DEFAULTS[k] then v = nil end
    local s = KA.Active(v ~= nil)
    if s then s[k] = v end
end

-- An if, not an and-chain: a missing table must read nil (the default), never false.
function KA.ContextOn(key)
    local s = KA.Active()
    local t = s and s.contexts
    local v
    if type(t) == "table" then v = t[key] end
    if v == nil then v = KA.CONTEXT_DEFAULTS[key] end
    return v == true
end

function KA.SetContext(key, on)
    on = on and true or false
    local s = KA.Active(true)
    if not s then return end
    if on == (KA.CONTEXT_DEFAULTS[key] == true) then
        if type(s.contexts) == "table" then
            s.contexts[key] = nil
            if next(s.contexts) == nil then s.contexts = nil end
        end
        return
    end
    if type(s.contexts) ~= "table" then s.contexts = {} end
    s.contexts[key] = on
end

-- A spec is on unless switched off; off is stored as false.
function KA.SpecOn(specID)
    local s = KA.Active()
    return not (s and type(s.specs) == "table" and s.specs[specID] == false)
end

function KA.SetSpec(specID, on)
    if not specID then return end
    local s = KA.Active(not on)
    if not s then return end
    if on then
        if type(s.specs) == "table" then
            s.specs[specID] = nil
            if next(s.specs) == nil then s.specs = nil end
        end
    else
        if type(s.specs) ~= "table" then s.specs = {} end
        s.specs[specID] = false
    end
    KA.SyncAlert()
end

function KA.CurSpecID()
    local Store = NS.Store
    return Store and Store.CurSpecID and Store.CurSpecID() or nil
end

-- Unknown spec (early login) counts as on.
function KA.SpecEnabled()
    local id = KA.CurSpecID()
    if not id then return true end
    return KA.SpecOn(id)
end

function KA.GetPoint()
    local s = KA.Active()
    local p = s and s.point
    if type(p) == "table" and type(p[1]) == "string" then return p end
    return nil
end

function KA.SetPoint(p, rp, x, y)
    local s = KA.Active(true)
    if s then s.point = { p, rp, x, y } end
end

-- The kick spell typed in, per character only: blank = the class default.
function KA.CustomKick()
    local c = KA.Char()
    local raw = c and c.customKick
    if type(raw) ~= "string" then return nil end
    raw = raw:match("^%s*(.-)%s*$") or ""
    if raw == "" then return nil end
    return raw
end

function KA.SetCustomKick(s)
    s = tostring(s or ""):match("^%s*(.-)%s*$") or ""
    local c = KA.Char(s ~= "")
    if c then c.customKick = (s ~= "") and s or nil end
    KA.SyncMacros()
    KA.Changed()
end

-- The switch, a public contract: ArcUI reads ArcAurasDB.kick.on to step its own copy aside.
function KA.IsOn()
    local r = KA.Root()
    return r ~= nil and r.on == true
end

function KA.StandaloneLoaded()
    local A = C_AddOns
    if not (A and A.IsAddOnLoaded) then return false end
    if A.IsAddOnLoaded("KickAssist") or A.IsAddOnLoaded("SetMyKick") then return true end
    return false
end

-- The UI file sets KA.onChange to redraw what is open.
function KA.Changed()
    if KA.onChange then KA.onChange() end
end

-- The kick

function KA.InterruptID()
    local custom = KA.CustomKick()
    if custom then
        local id = tonumber(custom)
        if id then return id end
        local S = C_Spell
        return (S and S.GetSpellIDForSpellIdentifier and S.GetSpellIDForSpellIdentifier(custom)) or nil -- raw-id: a name the player typed
    end
    local _, classToken = UnitClass("player")
    local data = classToken and INTERRUPTS[classToken]
    if not data then return nil end
    local specID = KA.CurSpecID()
    return (specID and data[specID]) or data.default
end

-- A typed name goes into the macro as typed; an ID reads its real name.
function KA.InterruptName()
    local custom = KA.CustomKick()
    local S = C_Spell
    if custom then
        local id = tonumber(custom)
        if id then return (S and S.GetSpellName and S.GetSpellName(id)) or custom end -- raw-id: macro text; /cast follows overrides itself
        return custom
    end
    local id = KA.InterruptID()
    return id and S and S.GetSpellName and S.GetSpellName(id) or nil -- raw-id: macro text; /cast follows overrides itself
end

-- The class default, for the kick spell box's hint.
function KA.DefaultInterruptName()
    local _, classToken = UnitClass("player")
    local data = classToken and INTERRUPTS[classToken]
    if not data then return nil end
    local specID = KA.CurSpecID()
    local id = (specID and data[specID]) or data.default
    local S = C_Spell
    return id and S and S.GetSpellName and S.GetSpellName(id) or nil
end

-- Group chat

local function ChatToken(index)
    if index and index >= 1 and index <= 8 then return "{rt" .. index .. "}" end
    return "no marker"
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- The game locks addon chat once a keystone starts.
function KA.ChatAllowed()
    local C = C_RestrictedActions
    if C and C.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
        return not C.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat)
    end
    return true
end

-- Posts the marker to group chat: "sent", "solo" or "locked" (nothing sent).
function KA.Announce()
    local msg = tostring(KA.Get("message") or KA.DEFAULTS.message)
    msg = msg:gsub("%%MARKER%%", function() return ChatToken(KA.Get("marker")) end)
    local channel = GroupChannel()
    if not channel then return "solo" end
    if not KA.ChatAllowed() then return "locked" end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return "locked" end
    send(msg, channel)
    return "sent"
end

-- Macros (text only; the game's /tm does the marking)

local MacroConsts = Constants and Constants.MacroConsts
local ACCT_MACRO_CAP = (MacroConsts and MacroConsts.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120
local CHAR_MACRO_CAP = (MacroConsts and MacroConsts.MAX_CHARACTER_MACROS) or MAX_CHARACTER_MACROS or 30
KA.ACCT_MACRO_CAP = ACCT_MACRO_CAP

-- Account-wide makes them account macros. A search in one bucket only, so the
-- same name in the other bucket is never touched.
local function FindMacroInBucket(name, perChar)
    local numAccount, numChar = GetNumMacros()
    if perChar then
        for i = 1, (numChar or 0) do
            local gi = ACCT_MACRO_CAP + i
            if GetMacroInfo(gi) == name then return gi end
        end
    else
        for i = 1, (numAccount or 0) do
            if GetMacroInfo(i) == name then return i end
        end
    end
    return nil
end

function KA.FindMacro(name)
    return FindMacroInBucket(name, not KA.AccountWide())
end

local function CreateManagedMacro(name, icon, body)
    local perChar = not KA.AccountWide()
    local numAccount, numChar = GetNumMacros()
    local used = perChar and numChar or numAccount
    local cap = perChar and CHAR_MACRO_CAP or ACCT_MACRO_CAP
    if used and used >= cap then return "full" end
    CreateMacro(name, icon, body, perChar)
    return "created"
end

-- Swaps the marker numbers that are /tm arguments, never digits inside [ ].
function KA.ReplaceTmMarkers(s, replacement)
    local out, depth, count = {}, 0, 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "[" then
            depth = depth + 1
            out[#out + 1] = c
        elseif c == "]" then
            if depth > 0 then depth = depth - 1 end
            out[#out + 1] = c
        elseif depth == 0 and c >= "0" and c <= "8" then
            out[#out + 1] = replacement
            count = count + 1
        else
            out[#out + 1] = c
        end
    end
    return table.concat(out), count
end

-- The first /tm line follows the marker; a body with none gets one.
-- Everything else stays as the player wrote it.
function KA.ManageMarkerInBody(body)
    body = tostring(body or ""):gsub("[\r\n]+$", "")
    if body == "" then return "/tm [@focus] ~{marker}" end
    local lines, handled = {}, false
    for line in (body .. "\n"):gmatch("(.-)\n") do
        if not handled then
            local prefix, rest = line:match("^(%s*/[tT][mM])(.*)$")
            if prefix and (rest == "" or rest:match("^[%s%[~!0-8]")) then
                local newRest, n = KA.ReplaceTmMarkers(rest, "{marker}")
                line = prefix .. newRest
                if n == 0 then line = line .. " ~{marker}" end
                handled = true
            end
        end
        lines[#lines + 1] = line
    end
    if not handled then lines[#lines + 1] = "/tm [@focus] ~{marker}" end
    return table.concat(lines, "\n")
end

-- Function replacements: a spell name with % in it stays as written.
function KA.BuildBody(template)
    local kick = KA.InterruptName() or ""
    local marker = tostring(KA.Get("marker"))
    local body = tostring(template or "")
    body = body:gsub("{interrupt}", function() return kick end)
    body = body:gsub("{marker}", function() return marker end)
    body = body:gsub("{kick}", function() return marker end)
    return body
end

function KA.SlotName(slot)
    local cfg = KA.SLOT_CFG[slot]
    local n = KA.Get(cfg.nameKey)
    if type(n) ~= "string" or n == "" then n = cfg.defName end
    return n
end

function KA.SlotBody(slot)
    local cfg = KA.SLOT_CFG[slot]
    local b = KA.Get(cfg.tmplKey)
    if type(b) ~= "string" then b = KA.DEFAULTS[cfg.tmplKey] end
    return b
end

-- Macro edits wait for the end of combat: EditMacro and CreateMacro are blocked in it.
local pendingSync, pendingCreate = false, {}
local OnRegenEnabled

local function Defer(slot)
    pendingSync = true
    if slot then pendingCreate[slot] = true end
    Events.On("PLAYER_REGEN_ENABLED", KEY, OnRegenEnabled)
end

function KA.MacroPending() return pendingSync end

-- One slot's macro: "edited", "created", "full", "combat" (queued), "none"
-- (no macro of that name and none asked for) or "off" (not set up here).
function KA.UpdateSlot(slot, create)
    local cfg = KA.SLOT_CFG[slot]
    if not (cfg and KA.active) then return "off" end
    if not KA.Get(cfg.onKey) then return "off" end
    if InCombatLockdown() then
        Defer(create and slot or nil)
        return "combat"
    end
    local name = KA.SlotName(slot)
    local body = KA.BuildBody(KA.SlotBody(slot))
    if body == "" then return "none" end
    local idx = KA.FindMacro(name)
    if idx then
        EditMacro(idx, name, cfg.icon, body)
        return "edited"
    end
    if slot == "kick" or create then return CreateManagedMacro(name, cfg.icon, body) end
    return "none"
end

-- Every macro set up here follows the marker.
function KA.SyncMacros(creates)
    if not KA.active then return "off" end
    if InCombatLockdown() then
        Defer()
        return "combat"
    end
    for _, slot in ipairs(KA.SLOT_ORDER) do
        KA.UpdateSlot(slot, creates and creates[slot])
    end
    return "done"
end

function OnRegenEnabled()
    Events.Off("PLAYER_REGEN_ENABLED", KEY)
    local creates = pendingCreate
    pendingSync, pendingCreate = false, {}
    if not KA.active then return end
    KA.SyncMacros(creates)
end

-- Saves a slot's name and text, then writes its macro (made if missing).
function KA.ApplySlot(slot, name, body)
    local cfg = KA.SLOT_CFG[slot]
    if not cfg then return "off" end
    name = tostring(name or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then name = KA.SlotName(slot) end
    KA.Set(cfg.nameKey, name)
    KA.Set(cfg.tmplKey, tostring(body or ""))
    KA.Set(cfg.onKey, true)
    return KA.UpdateSlot(slot, true)
end

-- Puts a slot's macro on the cursor for an action bar, making it first.
function KA.PickupSlot(slot)
    local cfg = KA.SLOT_CFG[slot]
    if not (cfg and KA.active) then return "off" end
    if InCombatLockdown() then return "combat" end
    KA.Set(cfg.onKey, true)
    local st = KA.UpdateSlot(slot, true)
    local idx = KA.FindMacro(KA.SlotName(slot))
    if idx then
        PickupMacro(idx)
        return "picked"
    end
    return st
end

function KA.SetMarker(i)
    i = tonumber(i)
    if not i or i < 0 or i > 8 then return end
    KA.Set("marker", math.floor(i))
    KA.SyncMacros()
    KA.Changed()
end

-- First time on, the shared setup is seeded from this character, so nothing is lost.
function KA.SetAccountWide(on)
    on = on and true or false
    local root = KA.Root(true)
    if not root then return end
    if on and not root.seeded then
        local c = KA.Char()
        if c then
            for _, k in ipairs(SHARED_KEYS) do
                if c[k] ~= nil then root[k] = Copy(c[k]) end
            end
        end
        root.seeded = true
    end
    root.accountWide = on or nil
    KA.SyncAlert()
    KA.SyncMacros()
    KA.Changed()
end

-- Ready check

local myName
-- The player's name is secret inside instances: kept while it reads.
local function RememberMyName()
    local n = UnitName("player")
    if issecretvalue(n) then return end
    if n then myName = n end
end

function KA.CurrentContext()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return nil end
    if instanceType == "raid" then return "raid" end
    if instanceType == "party" then
        local diff = select(3, GetInstanceInfo())
        if diff == 8 then return "mplus" end
        if diff == 23 then return "mythic" end
        if diff == 2 then return "heroic" end
        if diff == 1 then return "normal" end
    end
    return nil
end

local function ShouldTriggerHere()
    local key = KA.CurrentContext()
    return key ~= nil and KA.ContextOn(key)
end

local MARKER_TOKENS = {
    [1] = { "star" }, [2] = { "circle", "coin" }, [3] = { "diamond" }, [4] = { "triangle" },
    [5] = { "moon" }, [6] = { "square" }, [7] = { "cross", "x" }, [8] = { "skull" },
}

-- Does a chat line call out your marker ({rt8}, {skull} or the drawn icon)?
function KA.CallsMyMarker(text)
    if issecretvalue(text) then return false end
    local m = KA.Get("marker")
    if type(text) ~= "string" or type(m) ~= "number" or m < 1 or m > 8 then return false end
    text = text:lower()
    if text:find("{rt" .. m .. "}", 1, true) then return true end
    if text:find("raidtargetingicon_" .. m, 1, true) then return true end
    for _, name in ipairs(MARKER_TOKENS[m]) do
        if text:find("{" .. name .. "}", 1, true) then return true end
    end
    return false
end

-- Smart open: a few seconds after a ready check, group chat is watched and the
-- picker opens only if another player calls your marker.
local SMART_OPEN_WINDOW = 4
local SMART_CHAT_EVENTS = {
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}
local smartOpenExpire = 0

local function DisarmSmartOpen()
    smartOpenExpire = 0
    for _, e in ipairs(SMART_CHAT_EVENTS) do Events.Off(e, KEY) end
end

local function OpenPickerFromEvent()
    if KA.OpenPicker then KA.OpenPicker(true) end
end

local function OnSmartChat(_, text, sender)
    if GetTime() > smartOpenExpire then
        DisarmSmartOpen()
        return
    end
    if issecretvalue(sender) or issecretvalue(text) then return end
    if not (myName and type(sender) == "string") then return end
    if sender:match("^[^-]+") ~= myName and KA.CallsMyMarker(text) then
        DisarmSmartOpen()
        OpenPickerFromEvent()
    end
end

local function ArmSmartOpen()
    smartOpenExpire = GetTime() + SMART_OPEN_WINDOW
    for _, e in ipairs(SMART_CHAT_EVENTS) do Events.On(e, KEY, OnSmartChat) end
    C_Timer.After(SMART_OPEN_WINDOW + 0.1, function()
        if GetTime() >= smartOpenExpire then DisarmSmartOpen() end
    end)
end

local function OnReadyCheck()
    if not KA.active then return end
    if not (KA.SpecEnabled() and ShouldTriggerHere()) then return end
    if KA.Get("showOnReadyCheck") then
        if KA.Get("smartOpen") then ArmSmartOpen() else OpenPickerFromEvent() end
    end
    if KA.Get("announceOnReadyCheck") then KA.Announce() end
end

-- Interrupt alert: a sound or spoken words when your focus starts casting
-- while your kick is off cooldown. Whether the cast can be interrupted is
-- secret, so any focus cast counts. Nothing here reads a secret.

-- A hidden Cooldown takes the kick's duration object; IsShown() is the
-- plain answer to "on cooldown".
local interruptCD
local function ShadowCD()
    if interruptCD then return interruptCD end
    local cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    cd:SetSize(1, 1)
    cd:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    cd:SetAlpha(0)
    cd:EnableMouse(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:Show()
    interruptCD = cd
    return cd
end

-- The kick's live state through the one entry point, so an override is followed.
function KA.LiveInterruptID()
    return NS.Store.TrackedSpellID(KA.InterruptID())
end

function KA.InterruptReady()
    local id = KA.LiveInterruptID()
    local S = C_Spell
    if not (id and S and S.GetSpellCooldownDuration) then return false end
    local dur = S.GetSpellCooldownDuration(id, true)
    if not dur then return false end
    local cd = ShadowCD()
    cd:SetCooldownFromDurationObject(dur, true)
    return not cd:IsShown()
end

function KA.PlayAlertSound()
    local Sounds = NS.Sounds
    if not Sounds then return nil end
    return Sounds.Play(KA.Get("interruptAlertSound"), KA.Get("interruptAlertChannel"))
end

-- The shared voice and rate of every spoken line in Arc Auras.
function KA.Speak()
    local text = KA.Get("interruptAlertText")
    if type(text) ~= "string" or text == "" then text = KA.DEFAULTS.interruptAlertText end
    local CU = NS.DriverCustom
    if CU and CU.Speak then return CU.Speak(text) end
    local V = C_VoiceChat
    if not (V and V.SpeakText) then return false end
    V.SpeakText(0, text, 0, 100, false)
    return true
end

KA.ALERT_GAP = 1.5
local lastAlert
function KA.FireAlert()
    local now = GetTime()
    if lastAlert and now - lastAlert < KA.ALERT_GAP then return false end
    lastAlert = now
    if KA.Get("interruptAlertTTS") then KA.Speak() else KA.PlayAlertSound() end
    return true
end

-- The event's arguments (a secret spell ID in instances) are never read.
local function OnFocusCast()
    if KA.active and KA.Get("interruptAlert") and KA.InterruptReady() then KA.FireAlert() end
end

local FOCUS = { "focus" }
-- The focus cast events are heard only while the alert is on for this spec.
function KA.SyncAlert()
    if KA.active and KA.Get("interruptAlert") and KA.SpecEnabled() then
        Events.On("UNIT_SPELLCAST_START", KEY, OnFocusCast, FOCUS)
        Events.On("UNIT_SPELLCAST_CHANNEL_START", KEY, OnFocusCast, FOCUS)
    else
        Events.Off("UNIT_SPELLCAST_START", KEY)
        Events.Off("UNIT_SPELLCAST_CHANNEL_START", KEY)
        if interruptCD then interruptCD:Clear() end
    end
end

-- On and off

local function OnSpecChanged()
    KA.SyncMacros()
    KA.SyncAlert()
    KA.Changed()
end

local function OnEnteringWorld()
    RememberMyName()
    KA.SyncMacros()
    KA.SyncAlert()
end

local RUNTIME_EVENTS = {
    "READY_CHECK", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
}

function KA.Activate()
    if KA.StandaloneLoaded() then return false end
    if not KA.active then
        KA.active = true
        Events.On("READY_CHECK", KEY, OnReadyCheck)
        Events.On("PLAYER_SPECIALIZATION_CHANGED", KEY, OnSpecChanged, { "player" })
        Events.On("PLAYER_ENTERING_WORLD", KEY, OnEnteringWorld)
        RememberMyName()
        KA.SyncMacros()
    end
    KA.SyncAlert()
    return true
end

-- Everything it put on screen goes, every event stops and queued macro edits drop.
function KA.Deactivate()
    KA.active = false
    for _, e in ipairs(RUNTIME_EVENTS) do Events.Off(e, KEY) end
    DisarmSmartOpen()
    pendingSync, pendingCreate = false, {}
    if interruptCD then interruptCD:Clear() end
    if KA.ClosePicker then KA.ClosePicker() end
end

function KA.SetOn(v)
    v = v and true or nil
    local r = KA.Root(v)
    if r then r.on = v end
    if v then KA.Activate() else KA.Deactivate() end
    KA.Changed()
end

-- At login every addon has loaded, so the standalone check is final. A
-- one-time check on the shared dispatcher; nothing stays registered while off.
if Events then
    Events.On("PLAYER_LOGIN", KEY, function()
        Events.Off("PLAYER_LOGIN", KEY)
        if KA.IsOn() then KA.Activate() end
    end)
end
