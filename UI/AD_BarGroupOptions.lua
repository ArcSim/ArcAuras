-- AD_BarGroupOptions: the Bar Group's editor rows and the bar's way into one.
-- It owns Appearance > Stack and Bars for a Bar Group; the group editor in UI\AD_Options.lua
-- calls Options.BarGroupRows, and the bar editor's Move to lists Bar Groups through it.
local ADDON, NS = ...
local Options = NS.Options

local BGO = {}
Options.BarGroupOptions = BGO

BGO.SECS = { "Stack", "Bars", "Container", "Visibility" }
BGO.STACK = { "grow", "spacing", "padding" }
BGO.DYNAMIC = { "closeGaps", "align", "collapse", "order", "shrink", "slide", "slideTime" }
BGO.BARS = { "barDir", "barW", "barH" }

-- a Bar Group's Appearance sub-tabs; every other kind keeps its own
local prevSecs = Options.GroupSecsFor
function Options.GroupSecsFor(g, secs)
    if g and g.groupKind == "bar" then return BGO.SECS end
    if prevSecs then return prevSecs(g, secs) end
    return secs
end

function Options.BarGroupRows(pg, ctx, tabFn, kit)
    local AT = NS.AT
    local function G()
        local g = ctx()
        return (g and g.groupKind == "bar") and g or nil
    end
    local function Sub(name)
        return function()
            return tabFn() == "Appearance" and G() ~= nil and kit.subFn() == name
        end
    end
    local stackVis, barsVis = Sub("Stack"), Sub("Bars")
    AT.Section(pg, "Stack", { visibleFn = stackVis })
    kit.SectionRows(pg, "iconGroup", "barStack", ctx, stackVis, BGO.STACK)
    Options.LookBlock("iconGroup", "Appearance", "Stack", "barStack", BGO.STACK, "Stack")
    Options.BuildYield()
    AT.Section(pg, "Dynamic", { visibleFn = stackVis })
    kit.SectionRows(pg, "iconGroup", "barStack", ctx, stackVis, BGO.DYNAMIC)
    Options.LookBlock("iconGroup", "Appearance", "Dynamic", "barStack", BGO.DYNAMIC, "Stack")
    kit.PushBar(pg, ctx, "barStack", stackVis, function()
        local out = {}
        for _, f in ipairs(BGO.STACK) do out[#out + 1] = f end
        for _, f in ipairs(BGO.DYNAMIC) do out[#out + 1] = f end
        return out
    end)
    Options.BuildYield()
    AT.Section(pg, "Bars", { visibleFn = barsVis })
    kit.SectionRows(pg, "iconGroup", "barStack", ctx, barsVis, BGO.BARS)
    Options.LookBlock("iconGroup", "Appearance", "Bars", "barStack", BGO.BARS, "Bars")
    kit.PushBar(pg, ctx, "barStack", barsVis, BGO.BARS)
end

-- The Bar Groups a bar can go into: its own layout's, for the bar editor's Move to.
function BGO.Targets(bar)
    local Store = NS.Store
    local out = {}
    local lay = bar and Store.Get(bar.layoutId)
    if not lay then return out end
    for _, mid in ipairs(lay.members or {}) do
        local g = Store.Get(mid)
        if g and g.type == "group" and g.groupKind == "bar" then out[#out + 1] = g end
    end
    return out
end
