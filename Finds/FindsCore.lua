local ADDON, ns = ...
-- The item finder Arc Auras carries on Forever: the finder's own files (the ones beside this one are copies, never
-- edited here) in their own save. It only shares, unless the player picked the full finder on the Item Finds page,
-- which adds the finder's window, map marks and pop-ups. Arc Auras loads it at login unless the player switched it
-- off or the full finder addon is installed, which then runs instead. Loads right after Core.lua.

local opt = type(ArcAurasDB) == "table" and ArcAurasDB.itemFinds
ns.full = type(opt) == "table" and opt.full == true
ns.shareOnly = not ns.full
ns.SAVE = "ArcAurasFindsDB"
-- finds go out without the player's name unless the player changes it in the finder's settings
ns.DEFAULTS.credit = "anon"

-- the engine skips the finder window's own tooltips; without the window there are none
if ns.shareOnly then
    ns.Theme = { IsOwnTip = function() return false end }
end

-- loaded on demand after login: the login and entering-world work runs now (login runs once either way)
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON or not (IsLoggedIn and IsLoggedIn()) then return end
    ns.Login()
    local onEvent = ns.eventFrame:GetScript("OnEvent")
    onEvent(ns.eventFrame, "PLAYER_ENTERING_WORLD", false, false)
end)

-- what Arc Auras' Item Finds page reads and does
ArcAurasFinds = {
    Count = function()
        local n = 0
        for _ in pairs(ns.db and ns.db.finds or {}) do n = n + 1 end
        return n
    end,
    State = function() return ns.stopped and "stopped" or (ns.Sync and ns.Sync.state) end,
    Full = function() return ns.full end,
    Open = function()
        if ns.full and not ns.stopped then ns.Signal("OpenWindow") end
    end,
    -- switched off mid-session: out of the channel, deaf, and everything the window put on screen goes
    Stop = function()
        if ns.stopped then return end
        if ns.Sync and ns.Sync.Leave then ns.Sync.Leave() end
        ns.stopped = true
        if not ns.full then return end
        if ns.Popup then ns.Popup.Hide() end
        for _, name in ipairs({ "ForeverItemFinderFrame", "ForeverItemFinderPopup", "ForeverItemFinderMinimapButton" }) do
            local f = _G[name]
            if f then f:Hide() end
        end
        if ns.FavPins then ns.FavPins.Refresh() end
    end,
}
