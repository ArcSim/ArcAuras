local _, ns = ...
if ns.shareOnly then return end

-- The item the Mark on Map button marked, until the button takes it off or another item is marked; kept in the save, so
-- a reload or a new session keeps it. FavPins.lua draws it with the favorites, on the World Map and its continents and
-- on the minimap; the player opens the map, the addon never does.
local W = {}
ns.WorldPins = W

function W.Marked()
    return ns.db and ns.db.marked
end

function W.Mark(id)
    if ns.db then ns.db.marked = id end
    if ns.FavPins then ns.FavPins.Refresh() end
end

function W.Clear()
    if ns.db then ns.db.marked = nil end
    if ns.FavPins then ns.FavPins.Refresh() end
end
