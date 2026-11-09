-- AD_AutoLog: asks, or just starts, the combat log in the instance types the player picks and stops it after they
-- leave, but only a log this module started. Settings: "autoLog" (off until switched on), "autoLogWhen" ("start" or
-- nil for asking first) and one per instance type; both games.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("AutoLog") or C_Timer   -- /arcperf times what they run
local hooksecurefunc = NS.Perf and NS.Perf.Hooks("AutoLog") or hooksecurefunc
local Store, Events, AT = NS.Store, NS.Events, NS.AT
local AL = {}
NS.AutoLog = AL

local KEY = "adautolog"
-- Long enough for a walk between dungeon wings or a corpse run, so those stay one log and one answer.
local STOP_AFTER = 120
-- The first reading after a loading screen can be out of date.
local LOOK_AGAIN = 3
-- The game shuts every Esc-closable window as a loading screen ends, so the question opens just after.
local ASK_DELAY = 1
local ZONE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "UPDATE_INSTANCE_INFO" }
local KEY_START = "CHALLENGE_MODE_START"
local KEY_DIFFICULTY = 8

local ASK_NAME = "ArcAurasAutoLogAsk"
local ASK_PAD, ASK_GAP, ASK_H, ASK_TOP = 12, 6, 84, 160
local ANSWERS = {
    { "This run", "run" },
    { "Always here", "always" },
    { "Not this run", "no" },
    { "Never here", "never" },
}

-- The instance types that can count; any other type the game reports stays out.
AL.KINDS = {
    party = { field = "autoLogParty", on = true },
    raid = { field = "autoLogRaid", on = true },
    pvp = { field = "autoLogPvp" },
    arena = { field = "autoLogArena" },
    scenario = { field = "autoLogScenario" },
}
-- Garrisons report as instances.
local NOT_INSTANCES = { [1152] = true, [1153] = true, [1158] = true, [1160] = true, [1330] = true, [1331] = true }

local seen             -- the instance last decided; a stop the player typed holds until they leave it
local busy             -- our own LoggingCombat call is running
local armed, hooked
local stopGen, stopQueued = 0, false
local ask, askId, askName   -- the question's frame, and the instance it is open for

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function Tell() if AL.notify then AL.notify() end end

-- Saved, because a reload keeps the log running and the next session has to know whose it is.
local function Owned() return Store.UI().autoLogOwned == true end
local function SetOwned(v) Store.UI().autoLogOwned = v and true or nil end

-- nil when the answer cannot be read. The game can answer false while a log is being written, so only true means much.
local function Logging()
    local on = LoggingCombat()
    if Secret(on) then return nil end
    return on and true or false
end

-- Saved like Owned: another caller's start counts as a running log even if the game's answer says otherwise.
local function Running() return Store.UI().autoLogTheirs == true or Logging() == true end

-- The instance type, its id, its name and whether a key is running; nil when the answer cannot be read.
local function Where()
    local name, kind, difficulty, _, _, _, _, id = GetInstanceInfo()
    if Secret(kind) or Secret(id) or kind == nil then return nil end
    if NOT_INSTANCES[id] then return "none" end
    return kind, id, name, not Secret(difficulty) and difficulty == KEY_DIFFICULTY
end

local function Counts(kind)
    local k = AL.KINDS[kind]
    if not k then return false end
    local v = Store.GetSetting(k.field)
    if v == nil then return k.on == true end
    return v == true
end

local function Drive(on)
    busy = true
    LoggingCombat(on)
    busy = false
end

local function CancelStop()
    stopGen = stopGen + 1
    stopQueued = false
end

-- The run is over: our log stops and a "not this run" answer ends with it.
local function StopNow()
    CancelStop()
    if Owned() then Drive(false) end
    SetOwned(false)
    Store.UI().autoLogNo = nil
    Tell()
end

local function StopSoon()
    if stopQueued then return end
    stopQueued = true
    local gen = stopGen
    C_Timer.After(STOP_AFTER, function()
        if gen ~= stopGen then return end
        stopQueued = false
        local kind = Where()
        if kind ~= nil and not Counts(kind) then StopNow() end
    end)
end

local function Start()
    Drive(true)
    SetOwned(true)
end

-- True logs, false does not, nil asks. A remembered answer only matters while the module asks.
local function Decide(here)
    if AL.Mode() == "start" then return true end
    local ui = Store.UI()
    if ui.autoLogNo == here then return false end
    return ui.autoLogAnswers and ui.autoLogAnswers[here]
end

local function CloseAsk()
    askId = nil
    if ask then ask:Hide() end
end

-- One width for all four, wide enough for the longest word in any language; everything lands on whole pixels.
local function LayAsk()
    local widest = 0
    for _, b in ipairs(ask.btns) do widest = math.max(widest, b:GetWidth()) end
    local w, h = AT.PixelSize(ask, widest), AT.PixelSize(ask, 22)
    local pad, gap = AT.PixelSize(ask, ASK_PAD), AT.PixelSize(ask, ASK_GAP)
    for i, b in ipairs(ask.btns) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", ask, "BOTTOMLEFT", pad + (i - 1) * (w + gap), pad)
    end
    local boxW = #ask.btns * w + (#ask.btns - 1) * gap + pad * 2
    ask:SetSize(boxW, AT.PixelSize(ask, ASK_H))
    local px = AT.Px(ask)
    local x = (UIParent:GetWidth() - boxW) / 2
    if px > 0 then x = math.floor(x / px + 0.5) * px end
    ask:ClearAllPoints()
    ask:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -AT.PixelSize(ask, ASK_TOP))
end

local function Reply(word)
    local id = askId
    CloseAsk()
    if id == nil then return end
    local ui = Store.UI()
    if word == "always" or word == "never" then
        ui.autoLogAnswers = ui.autoLogAnswers or {}
        ui.autoLogAnswers[id] = (word == "always")
    end
    if word == "no" then ui.autoLogNo = id end
    if word == "run" or word == "always" then
        if not Running() then Start() end
    elseif Owned() then
        -- Only a key's start can have begun a log while the question was open.
        Drive(false)
        SetOwned(false)
    end
    Tell()
end

local function BuildAsk()
    if ask then return end
    local COL = AT.COL
    ask = CreateFrame("Frame", ASK_NAME, UIParent)
    ask:Hide()
    ask:SetFrameStrata("DIALOG")
    ask:SetClampedToScreen(true)
    ask:EnableMouse(true)
    AT.Skin(ask, COL.bg, COL.line2)
    tinsert(UISpecialFrames, ASK_NAME)
    local q = ask:CreateFontString(nil, "OVERLAY")
    q:SetFont(AT.FONT, 13, "")
    q:SetPoint("TOP", 0, -ASK_PAD)
    q:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
    q:SetText(AT.Tr("Log combat here?"))
    ask.nameFS = ask:CreateFontString(nil, "OVERLAY")
    ask.nameFS:SetFont(AT.FONT, 12, "")
    ask.nameFS:SetPoint("TOP", q, "BOTTOM", 0, -4)
    ask.nameFS:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    ask.btns = {}
    for i, a in ipairs(ANSWERS) do
        local b = AT.MakeSmallButton(ask, a[1], 92)
        b:SetScript("OnClick", function() Reply(a[2]) end)
        ask.btns[i] = b
    end
end

local function ShowAsk()
    if askId == nil then return end
    BuildAsk()
    ask.nameFS:SetText(askName)
    LayAsk()
    ask:Show()
end

local function AskSoon(here, name)
    askId, askName = here, name
    C_Timer.After(ASK_DELAY, ShowAsk)
end

-- A key's first moments cannot be logged later, so a key started with the question open logs now.
local function OnKeyStart()
    if askId ~= nil and not Running() then
        Start()
        Tell()
    end
end

local function Check()
    if not AL.IsOn() then return end
    local kind, id, name, inKey = Where()
    if kind == nil then return end
    if Counts(kind) then
        CancelStop()
        local here = id or kind
        if here ~= seen then
            seen = here
            CloseAsk()
            local yes = Decide(here)
            if yes or Owned() then
                if not Running() then Start() end
            elseif yes == nil then
                AskSoon(here, name)
                if inKey then OnKeyStart() end
            end
        end
    else
        seen = nil
        CloseAsk()
        if Owned() or Store.UI().autoLogNo ~= nil then StopSoon() end
    end
    Tell()
end

-- Any other caller's say makes the log theirs, so it no longer stops with the instance. No arguments is only a read.
local function OnLoggingCall(...)
    if busy or not armed or select("#", ...) == 0 then return end
    SetOwned(false)
    Store.UI().autoLogTheirs = (...) and true or nil
    if ... then CloseAsk() end
    Tell()
end

local function Arm()
    if armed then return end
    armed = true
    if not hooked then
        hooked = true
        hooksecurefunc("LoggingCombat", OnLoggingCall)
    end
    for _, e in ipairs(ZONE_EVENTS) do Events.On(e, KEY, Check) end
    Events.On(KEY_START, KEY, OnKeyStart)
end

local function Disarm()
    armed = false
    for _, e in ipairs(ZONE_EVENTS) do Events.Off(e, KEY) end
    Events.Off(KEY_START, KEY)
end

function AL.IsOn() return Store.GetSetting("autoLog") == true end

function AL.SetOn(v)
    Store.SetSetting("autoLog", v and true or nil)
    seen = nil
    if v then
        Arm()
        Check()
    else
        Disarm()
        CloseAsk()
        StopNow()
        Store.UI().autoLogTheirs = nil
    end
    Tell()
end

-- "ask" or "start".
function AL.Mode() return Store.GetSetting("autoLogWhen") == "start" and "start" or "ask" end

function AL.SetMode(v)
    Store.SetSetting("autoLogWhen", v == "start" and "start" or nil)
    seen = nil
    Check()
end

function AL.AnswerCount()
    local n = 0
    for _ in pairs(Store.UI().autoLogAnswers or {}) do n = n + 1 end
    return n
end

function AL.Forget()
    Store.UI().autoLogAnswers = nil
    seen = nil
    Check()
    Tell()
end

function AL.Wants(kind) return Counts(kind) end

function AL.SetWants(kind, v)
    local k = AL.KINDS[kind]
    if not k then return end
    Store.SetSetting(k.field, v == true)
    if Where() == kind then seen = nil end
    Check()
end

-- "off", "ours" (stops after the instance) or "theirs" (keeps running). The calls seen come before the game's answer.
function AL.Status()
    if Owned() then return "ours" end
    return Running() and "theirs" or "off"
end

-- Every loading screen comes through here: login, reload, reconnect and each instance change.
Events.On("PLAYER_ENTERING_WORLD", KEY, function(_, isLogin)
    if not AL.IsOn() then return end
    -- The client ends every log at logout, and a log we started resumes through Check.
    if isLogin then Store.UI().autoLogTheirs = nil end
    Arm()
    Check()
    C_Timer.After(LOOK_AGAIN, Check)
    if askId ~= nil then C_Timer.After(ASK_DELAY, ShowAsk) end
end)
