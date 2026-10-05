-- AD_SpellAnchor: the frame a spell pin rides: the action bar button holding a spell, or the
-- Cooldown Manager icon showing it. Core\AD_Anchor.lua asks it for the "action" and "cdm" kinds.
-- Everything here is read (a button's slot, the slot's spell, a pooled Cooldown Manager frame's
-- cooldownID); nothing is written to the game's frames, so pins work in combat and taint nothing.
local ADDON, NS = ...

local SA = {}
NS.SpellAnchor = SA

SA.KEY = "adspellpin"
-- the Cooldown Manager's viewers, the cooldown rows first
SA.CDM_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer",
    "BuffBarCooldownViewer" }
-- the game's bar button names, for a client whose ActionButtonUtil does not list them
SA.BAR_NAMES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
SA.BUTTONS_PER_BAR = 12
-- A button shows another slot, or a slot another spell, after these; every
-- spell pin then looks again. An event this client lacks is skipped.
SA.EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_STEALTH", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
    "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }
-- the Cooldown Manager re-deals its pooled frames over a moment: one more look this long after
SA.SETTLE = 1
SA.cache = {}    -- [kind .. "|" .. spec] = the frame found last
SA.parsed = {}   -- [spec] = { list, set } or false
SA.armed = {}    -- [event] = true while registered
SA.hooked = {}   -- [viewer frame] = true once its layout pass is hooked

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function Plain(v)
    if v == nil or Secret(v) then return nil end
    return v
end

-- a spell's name while it reads plain, else nil
function SA.NameOf(id)
    local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if Secret(nm) or type(nm) ~= "string" or nm == "" then return nil end
    return nm
end

-- "17364, 51533" -> { list = { 17364, 51533 }, set = { [17364] = true, ... } }, or nil.
-- "cd:12821" -> { cid = 12821, list = {}, set = {} }: one Cooldown Manager
-- entry exactly, as two icons of the same spell (a cooldown and its buff) differ.
function SA.Parse(spec)
    if type(spec) ~= "string" or spec == "" then return nil end
    local p = SA.parsed[spec]
    if p == nil then
        local cid = tonumber(spec:match("^%s*[Cc][Dd]:%s*(%d+)%s*$") or "")
        if cid and cid > 0 then
            p = { cid = cid, list = {}, set = {} }
        else
            local list, set = {}, {}
            for n in spec:gmatch("%d+") do
                local v = tonumber(n)
                if v and v > 0 and not set[v] then
                    set[v] = true
                    list[#list + 1] = v
                end
            end
            p = (#list > 0) and { list = list, set = set } or false
        end
        SA.parsed[spec] = p
    end
    return p or nil
end

-- A spell id the game reports stands for the pin's spell: one of its ids, or a
-- spell of the same name (another rank on a ranked realm). Names are read when
-- first needed: spell data can arrive after the pin is typed.
function SA.Matches(p, id)
    id = Plain(id)
    if type(id) ~= "number" then return false end
    if p.set[id] then return true end
    if not p.names then
        local names, any = {}, false
        for _, v in ipairs(p.list) do
            local nm = SA.NameOf(v)
            if nm then
                names[nm] = true
                any = true
            end
        end
        if not any then return false end
        p.names = names
    end
    local nm = SA.NameOf(id)
    return nm ~= nil and p.names[nm] == true
end

-- the slot a button shows now: the game's buttons keep a field, a bar
-- library's buttons the secure attribute
local function SlotOf(b)
    local slot = Plain(b.action)
    if type(slot) ~= "number" and b.GetAttribute then slot = Plain(b:GetAttribute("action")) end
    return (type(slot) == "number") and slot or nil
end

-- A button on screen that holds the pin's spell now (a macro counts by what it
-- casts). A button on a bar page that is put away still reports a slot, and a
-- hidden bar's buttons still say shown, so both are checked.
function SA.ButtonHolds(b, p)
    if type(b) ~= "table" or not b.GetObjectType then return false end
    if b.IsForbidden then
        local fb = b:IsForbidden()
        if Secret(fb) or fb then return false end
    end
    if b.GetAttribute then
        local hid = b:GetAttribute("statehidden")
        if Secret(hid) or hid then return false end
    end
    local vis = b.IsVisible and b:IsVisible()
    if Secret(vis) or not vis then return false end
    local slot = SlotOf(b)
    if not (slot and GetActionInfo) then return false end
    if HasAction then
        local has = HasAction(slot)
        if Secret(has) or not has then return false end
    end
    local kind, id = GetActionInfo(slot)
    if Secret(kind) or (kind ~= "spell" and kind ~= "macro") then return false end
    return SA.Matches(p, id)
end

-- Every button a bar library registered (each bar addon ships its own copy
-- under its own major, so every one in LibStub is asked), then the game's own.
function SA.EachButton(fn)
    local libs = LibStub and LibStub.libs
    if type(libs) == "table" then
        for major, lib in pairs(libs) do
            if type(major) == "string" and major:find("^LibActionButton%-1%.0") and type(lib) == "table"
                and type(lib.GetAllButtons) == "function" then
                for b in pairs(lib:GetAllButtons()) do
                    if fn(b) then return b end
                end
            end
        end
    end
    local util = ActionButtonUtil
    local names = (type(util) == "table" and type(util.ActionBarButtonNames) == "table")
        and util.ActionBarButtonNames or SA.BAR_NAMES
    for _, prefix in ipairs(names) do
        for i = 1, SA.BUTTONS_PER_BAR do
            local b = _G[prefix .. i]
            if b ~= nil and fn(b) then return b end
        end
    end
    return nil
end

function SA.FindButton(p)
    return SA.EachButton(function(b) return SA.ButtonHolds(b, p) end)
end

-- The spell ids a Cooldown Manager entry stands for: the manager's own data,
-- plain, read through its C API (no method of the manager is called).
function SA.EntryIDs(cooldownID)
    local out = {}
    local CV = C_CooldownViewer
    local info = CV and CV.GetCooldownViewerCooldownInfo and CV.GetCooldownViewerCooldownInfo(cooldownID)
    if type(info) ~= "table" then return out end
    for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID" }) do
        local v = Plain(info[k])
        if type(v) == "number" and v > 0 then out[#out + 1] = v end
    end
    if type(info.linkedSpellIDs) == "table" then
        for _, v in ipairs(info.linkedSpellIDs) do
            v = Plain(v)
            if type(v) == "number" and v > 0 then out[#out + 1] = v end
        end
    end
    return out
end

-- A Cooldown Manager icon on screen showing the pin's spell. Its cooldownID is
-- a field the manager writes; reading it taints nothing.
function SA.IconHolds(f, p)
    if type(f) ~= "table" then return false end
    local cid = Plain(f.cooldownID)
    if type(cid) ~= "number" then return false end
    local vis = f.IsVisible and f:IsVisible()
    if Secret(vis) or not vis then return false end
    if p.cid then return cid == p.cid end
    for _, id in ipairs(SA.EntryIDs(cid)) do
        if SA.Matches(p, id) then return true end
    end
    return false
end

-- Every active Cooldown Manager icon, through each viewer's frame pool (a
-- read-only walk of the pool's own list).
function SA.EachIcon(fn)
    for _, vn in ipairs(SA.CDM_VIEWERS) do
        local v = _G[vn]
        local pool = type(v) == "table" and v.itemFramePool
        if type(pool) == "table" and pool.EnumerateActive then
            for f in pool:EnumerateActive() do
                if fn(f) then return f end
            end
        end
    end
    return nil
end

function SA.FindIcon(p)
    return SA.EachIcon(function(f) return SA.IconHolds(f, p) end)
end

-- The frame a pin rides now, or nil. The last one found is asked first (does
-- it still hold the spell, on screen?), so most passes cost one look; a frame
-- anchoring could not use is never returned.
function SA.Resolve(kind, spec)
    local p = SA.Parse(spec)
    if not p or (kind ~= "action" and kind ~= "cdm") then return nil end
    -- a cooldown ID names a Cooldown Manager entry, never a button
    if p.cid and kind == "action" then return nil end
    local key = kind .. "|" .. spec
    local holds = (kind == "action") and SA.ButtonHolds or SA.IconHolds
    local c = SA.cache[key]
    if c and holds(c, p) then return c end
    local f
    if kind == "action" then f = SA.FindButton(p) else f = SA.FindIcon(p) end
    local A = NS.Anchor
    if f and A and A.FrameProblem and A.FrameProblem(f) then f = nil end
    SA.cache[key] = f
    return f
end

function SA.Forget()
    for k in pairs(SA.cache) do SA.cache[k] = nil end
end

-- Every spell pin looks again on the next frame (one pass however many
-- events arrive together).
function SA.Changed()
    if not (NS.Events and NS.Events.Coalesce) then return end
    NS.Events.Coalesce(SA.KEY, function()
        local A = NS.Anchor
        if A and A.ReapplySpellPins then A.ReapplySpellPins() end
        local TA = NS.TextAnchor
        if TA and TA.Reapply then TA.Reapply() end
    end)
end

-- The manager's settings changed or it laid out again: the pooled frames may
-- hold other cooldowns now. A settings change also drops what was found and
-- looks once more after the manager settles.
function SA.CDMChanged(full)
    if not SA.wantCDM then return end
    if full == true then
        SA.Forget()
        if not SA.settling and C_Timer then
            SA.settling = true
            C_Timer.After(SA.SETTLE, function()
                SA.settling = nil
                SA.Changed()
            end)
        end
    end
    SA.Changed()
end

local function Valid(ev)
    return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(ev) == true
end

-- The Cooldown Manager's signals, set once: its settings callback, and each
-- viewer's layout pass (hooked, which leaves the manager's own run untouched).
-- A viewer that was not built yet is hooked on a later sync.
function SA.HookCDM()
    if not SA.settingsHooked and EventRegistry and EventRegistry.RegisterCallback then
        SA.settingsHooked = true
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged",
            function() SA.CDMChanged(true) end, "ArcAurasSpellPin")
    end
    if not hooksecurefunc then return end
    for _, vn in ipairs(SA.CDM_VIEWERS) do
        local v = _G[vn]
        if type(v) == "table" and not SA.hooked[v] and type(v.RefreshLayout) == "function" then
            SA.hooked[v] = true
            hooksecurefunc(v, "RefreshLayout", function() SA.CDMChanged(false) end)
        end
    end
end

-- Arms exactly what the live pins need, after every rebuild: the bar events
-- while any spell pin exists, the manager's signals while one rides an icon.
-- A hook cannot be removed, so it stays but does nothing without an icon pin.
-- Bars and records report through Sync, pinned texts through SyncTexts.
SA.barWant = { action = false, cdm = false }
SA.textWant = { action = false, cdm = false }
function SA.Sync(wantAction, wantCDM)
    SA.barWant.action, SA.barWant.cdm = wantAction == true, wantCDM == true
    SA.Arm()
end
function SA.SyncTexts(wantAction, wantCDM)
    SA.textWant.action, SA.textWant.cdm = wantAction == true, wantCDM == true
    SA.Arm()
end
function SA.Arm()
    local wantAction = SA.barWant.action or SA.textWant.action
    local wantCDM = SA.barWant.cdm or SA.textWant.cdm
    local want = wantAction or wantCDM
    SA.wantCDM = wantCDM == true
    if NS.Events then
        for _, ev in ipairs(SA.EVENTS) do
            if want and not SA.armed[ev] and Valid(ev) then
                SA.armed[ev] = true
                NS.Events.On(ev, SA.KEY, SA.Changed)
            elseif not want and SA.armed[ev] then
                SA.armed[ev] = nil
                NS.Events.Off(ev, SA.KEY)
            end
        end
    end
    if SA.wantCDM then SA.HookCDM() end
    if not want then SA.Forget() end
end

-- The spell an action button or a Cooldown Manager icon holds now, for the
-- picker (UI\AD_FramePicker.lua); nil when it holds none.
function SA.ButtonSpell(b)
    if type(b) ~= "table" or not b.GetObjectType then return nil end
    local slot = SlotOf(b)
    if not (slot and GetActionInfo) then return nil end
    local kind, id = GetActionInfo(slot)
    if Secret(kind) or (kind ~= "spell" and kind ~= "macro") then return nil end
    id = Plain(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

function SA.IconSpell(f)
    local cid = type(f) == "table" and Plain(f.cooldownID)
    if type(cid) ~= "number" then return nil end
    return SA.EntryIDs(cid)[1]
end

-- The picker's map, made once per pick: every button and icon that holds a
-- spell now -> { kind, id, text, frameName }.
function SA.PickMap()
    local map = {}
    SA.EachButton(function(b)
        if map[b] then return false end
        local id = SA.ButtonSpell(b)
        if id then
            local nm = b.GetName and b:GetName()
            if Secret(nm) or type(nm) ~= "string" or _G[nm] ~= b then nm = nil end
            map[b] = { kind = "action", id = id, frameName = nm,
                text = "Action button:  " .. (SA.NameOf(id) or ("spell " .. id)) }
        end
        return false
    end)
    -- an icon is picked by its cooldown ID: the exact entry, never its twin
    -- of the same spell (a cooldown and its buff)
    SA.EachIcon(function(f)
        local cid = Plain(f.cooldownID)
        if type(cid) == "number" and cid > 0 then
            local id = SA.IconSpell(f)
            map[f] = { kind = "cdm", id = id, cid = cid,
                text = "Cooldown Manager:  " .. (id and (SA.NameOf(id) or ("spell " .. id)) or "an icon")
                    .. "  (cooldown ID " .. cid .. ")" }
        end
        return false
    end)
    return map
end
