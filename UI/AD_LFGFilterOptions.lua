-- AD_LFGFilterOptions: the LFG Filter card on the Modules page and its page (WoW Forever only). Reads NS.LFGFilter
-- at call time.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local MOD = Options.Modules

local function LF() return NS.LFGFilter end
local function Avail() local f = LF() return f ~= nil and f.Available() end

local function Build(pg, m)
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Use the LFG Filter", m.isOn, m.setOn, Avail,
        "Adds a filter button and panel to the Looking For Group window.")
    MOD.Stamp(row, m, m.switch, "bool", Avail, true)
    AT.RowDesc(pg, "Arc LFG Filter is installed: set it up there (/arclfg).", 20,
        function() local f = LF() return f ~= nil and f.Standalone() end)
    AT.RowDesc(pg, "Takes effect after a reload.", 20,
        function() local f = LF() return f ~= nil and f.NeedsReload() end)
    AT.RowDesc(pg, "The filter button sits beside Refresh in the Looking For Group window.", 20,
        function() local f = LF() return Avail() and f.IsOn() end)
    AT.RowButton(pg, "Open", function() local f = LF() if f then f.OpenSettings() end end,
        function() local f = LF() return Avail() and f.IsOn() and f.Running() end, 92, "Invite and whisper settings")
    local f = LF()
    if f then
        f.notify = function()
            if pg:IsVisible() then AT.LayoutPage(pg) end
        end
    end
end

local spec
spec = {
    key = "lfgFilter",
    switch = "on",
    name = "LFG Filter",
    desc = "Filter the Looking For Group list by role, class and level, and whisper the players you invite.",
    foreverOnly = true,
    -- a funnel
    glyph = {
        { 3, 4, 14, 2, "arc" }, { 5, 7, 10, 2, "arc" }, { 7, 10, 6, 2, "arc" }, { 9, 13, 2, 4, "arc" },
    },
    available = function()
        local ok = Avail()
        spec.unavailable = (not ok) and "Arc LFG Filter is installed: set it up there (/arclfg)." or nil
        return ok
    end,
    isOn = function() local f = LF() return f ~= nil and f.IsOn() end,
    setOn = function(v)
        local f = LF()
        if f then f.SetOn(v) end
    end,
    build = function(pg, m) Build(pg, m) end,
}
MOD.Register(spec)
