local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
ns.DISCORD = "https://discord.gg/yMZmnFjUTd"
ns.SITE = "https://forever-item-finder.pages.dev/#share"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
-- A host addon that carries a copy of these files names the copy's save in ns.SAVE, sets ns.shareOnly when it
-- runs without the window (the window's files then return at once), and sets ns.stopped to silence the copy.

-- Forever runs the 1.x interface; anything else is a test run on another client
ns.isForever = (select(4, GetBuildInfo()) or 0) < 20000

function ns.Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

function ns.Now()
    return (GetServerTime and GetServerTime()) or time()
end

local DEFAULTS = {
    popOn = true,           -- pop-ups at all; finds reach the feed either way
    -- which finds the Live Feed shows (Data.lua D.FindPasses): discoveries only (what the database lacked: D.IsDiscovery),
    -- a quality floor any / uncommon / rare / epic, a level choice any / mine / near / custom (levelMin .. levelMax,
    -- either may be nil), slots ticked (none = any), usable gear only, and the kinds; pop-ups show the same finds while
    -- popFollow is on, else their own popOwn, which starts at Rare and better so a busy server does not bury the
    -- player in cards
    findFilter = { discoveries = true, quality = "any", level = "any", slots = {}, usable = false, kinds = { n = true, c = true } },
    popFollow = false,
    popOwn = { discoveries = true, quality = "rare", level = "any", slots = {}, usable = false, kinds = { n = true, c = true } },
    popStyle = "card",      -- compact / card / full
    -- what the stat card shows: these are the card itself, so they start shown
    card = { type = true, stats = true, effects = true, found = true },
    popScale = 100,
    popStay = "5",          -- 5 / 10 / 20 / close
    popAnim = "basic",      -- basic (slide and fade) / full (adds a shine and a pulse) / off
    -- a find while one shows: wait (stays in the feed) / replace (takes over the pop-up) / rarer (takes over only when
    -- its quality is higher; the rarer find also passes the rate limit)
    popNext = "replace",
    -- seconds between two pop-ups: 5 / 10 / 20 / 30; as long as a card stays, so a find after it has gone still shows
    popGap = "5",
    popCombat = "hold",     -- hold until combat ends / show
    sound = false,
    soundKit = "loot",      -- a key of Popup.SOUNDS
    credit = "name",        -- name / anon
    winScale = 100,         -- the window's size, in percent
    -- favorites on the game's maps (FavPins.lua): both (World Map and minimap) / world / off; starring an item is
    -- already the player asking for it, so this starts on
    favPins = "both",
    favLook = "icon",       -- icon (the item's) / dot (the window's pin for its source)
}
ns.DEFAULTS = DEFAULTS

local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            Fill(dst[k], v)
        end
    end
end

-- internal signals: modules talk through these, never through each other
local listeners = {}
function ns.Listen(signal, fn)
    listeners[signal] = listeners[signal] or {}
    table.insert(listeners[signal], fn)
end
function ns.Signal(signal, ...)
    local list = listeners[signal]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

-- one event frame for the whole addon
local events = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = events
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        events:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if ns.stopped or not list then return end
    for i = 1, #list do list[i](...) end
end)

local Command

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    local save = ns.SAVE or "ForeverItemFinderDB"
    _G[save] = _G[save] or {}
    local db = _G[save]
    db.v = db.v or 1
    db.finds = db.finds or {}
    -- a test run outside Forever starts clean on every load, so the same items count as finds again
    if not ns.isForever then
        db.finds, db.popped, db.demoMined, db.demoOn = {}, {}, nil, nil
    end
    db.settings = db.settings or {}
    Fill(db.settings, DEFAULTS)
    -- an older save keeps "off" as its quality choice: that means pop-ups off; the old filter keys go
    if db.settings.popFor == "off" then db.settings.popOn = false end
    for _, k in ipairs({ "popFor", "popLevel", "popLevelMin", "popLevelMax", "popUsable", "kinds", "types", "popFilter" }) do db.settings[k] = nil end
    db.minimap = db.minimap or { angle = 200 }
    db.popup = db.popup or {}
    -- a per-install salt keeps the reporter counts from naming anyone
    db.salt = db.salt or tostring(math.random(100000, 999999))
    ns.db = db
    ns.settings = db.settings
    if not ns.shareOnly then
        SLASH_FOREVERITEMFINDER1 = "/fif"
        SLASH_FOREVERITEMFINDER2 = "/foreveritemfinder"
        SlashCmdList.FOREVERITEMFINDER = Command
    end
    ns.Signal("DBReady")
end)

-- once, also for a copy loaded on demand after login (its host calls ns.Login then)
local loggedIn = false
function ns.Login()
    if loggedIn then return end
    loggedIn = true
    ns.Signal("Login")
end
ns.On("PLAYER_LOGIN", ns.Login)

function Command(msg)
    if ns.stopped then return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "options" or msg == "config" then
        ns.Signal("OpenWindow", "options")
    elseif msg == "db" or msg == "database" then
        ns.Signal("OpenWindow", "db")
    -- sample finds for showing the addon, in the developer's copy only (Dev.lua)
    elseif msg == "demo" and ns.DEV then
        ns.Signal("Demo", false)
    elseif msg == "demo clear" and ns.DEV then
        ns.Signal("Demo", true)
    else
        ns.Signal("ToggleWindow")
    end
end
