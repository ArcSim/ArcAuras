local _, ns = ...

-- Lines on the game's own item tooltips (bags, the auction house, chat links, loot): whether the item is new or changed
-- in Forever, and how to get it. Settings > Items picks which items get them.
local D, T = ns.Data, ns.Theme
local G = {}
ns.GameTips = G

local TAGS = { n = "New in Forever", x = "New in Forever", c = "Changed from Classic", h = "Changed by a hotfix" }
local ICON = "|T" .. ns.MEDIA .. "FIF_MapPin:0|t "

-- an item's lines, { tag, changed, how }, or false when the database does not list it; kept until its find changes
local cache = {}
function G.Lines(id)
    local l = cache[id]
    if l ~= nil then return l end
    local e, row = ns.Finds.Get(id), D.Seed(id)
    if not (e or row) then
        cache[id] = false
        return false
    end
    local kind = (e and e.k == "c" and "c") or (row and row.kind) or (e and e.k)
    local how, rate = ns.UI.HowToGet(id)
    if how and rate and rate ~= "Unknown" then how = how .. " (" .. rate .. ")" end
    l = { tag = TAGS[kind], changed = kind == "c" or kind == "h", how = how }
    cache[id] = l
    return l
end

ns.Listen("FindsChanged", function(e)
    if e and e.id then cache[e.id] = nil else wipe(cache) end
end)

local function Add(tip, data)
    local mode = ns.settings and ns.settings.itemTips
    if mode ~= "changes" and mode ~= "all" then return end
    -- a copy running without the window has no item words to show
    if not (ns.UI and ns.UI.HowToGet) then return end
    if T.IsOwnTip(tip) then return end
    -- the comparison tooltips beside it show equipped gear, not the item looked at
    local name = tip.GetName and tip:GetName()
    if type(name) == "string" and name:find("ShoppingTooltip", 1, true) then return end
    local id = data and data.id
    if not id or ns.Secret(id) then return end
    local l = G.Lines(id)
    if not l or (mode == "changes" and not l.tag) then return end
    if l.tag then tip:AddLine(ICON .. l.tag, T.RGB(l.changed and T.TAG.c.fg or T.TAG.n.fg)) end
    if l.how then tip:AddLine((l.tag and "" or ICON) .. l.how, T.RGB(T.C.ink)) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Add)
end
