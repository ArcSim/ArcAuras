-- AD_ItemFindsOptions: the Item Finds card on the Modules page and its page (WoW Forever only). Reads NS.ItemFinds
-- at call time.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local MOD = Options.Modules

local function IF() return NS.ItemFinds end
local function Avail() local f = IF() return f ~= nil and f.Available() end

local function Build(pg, m)
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Share item finds", m.isOn, m.setOn, Avail,
        "Shares the new Forever items you loot with other players, without your name, and keeps theirs.")
    MOD.Stamp(row, m, m.switch, "bool", Avail, true)
    AT.RowDesc(pg, "Forever Item Finder is installed: it shares your finds.", 20,
        function() local f = IF() return f ~= nil and f.Standalone() end)
    AT.RowDesc(pg, "Switched back on: sharing starts again after a reload.", 20,
        function() local f = IF() return f ~= nil and f.NeedsReload() end)
    local function Sharing() local f = IF() return Avail() and f.IsOn() end
    row = AT.RowToggle(pg, "Full Item Finder", function() local f = IF() return f ~= nil and f.IsFull() end,
        function(v) local f = IF() if f then f.SetFull(v) end end, Sharing,
        "Adds the finder's window: search every Forever item, see where it drops on your map, star favorites and get pop-ups for new finds.")
    MOD.Stamp(row, m, "full", "bool", Sharing)
    AT.RowDesc(pg, "Takes effect after a reload.", 20,
        function() local f = IF() return Sharing() and f.FullNeedsReload() end)
    AT.RowButton(pg, "Open", function() local f = IF() if f then f.Open() end end,
        function() local f = IF() return Sharing() and f.FullLoaded() end, 92, "The Item Finder window")
    AT.RowDesc(pg, "See every find and where it drops at forever-item-finder.pages.dev.", 20, Avail)
    local f = IF()
    if f then
        f.notify = function()
            if pg:IsVisible() then AT.LayoutPage(pg) end
        end
    end
end

local spec
spec = {
    key = "itemFinds",
    switch = "on",
    name = "Item Finds",
    desc = "Share the new Forever items you find with other players, and see everyone's on the finder website.",
    foreverOnly = true,
    -- a magnifying glass over a find
    glyph = {
        { 3, 3, 10, 2, "arc" }, { 3, 11, 10, 2, "arc" }, { 3, 3, 2, 10, "arc" }, { 11, 3, 2, 10, "arc" },
        { 12, 14, 7, 2, "arc", 45 },
        { 7, 7, 2, 2, "ink" },
    },
    available = function()
        local ok = Avail()
        spec.unavailable = (not ok) and "Forever Item Finder is installed and shares your finds." or nil
        return ok
    end,
    isOn = function() local f = IF() return f ~= nil and f.IsOn() end,
    setOn = function(v)
        local f = IF()
        if f then f.SetOn(v) end
    end,
    build = function(pg, m) Build(pg, m) end,
}
MOD.Register(spec)
