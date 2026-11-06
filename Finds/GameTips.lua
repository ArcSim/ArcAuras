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

-- a marked line's segments (Tooltip.lua T.MarkChanges) as one line of text: the new value in its direction's colour and
-- Classic's value after it in grey, in brackets, since a game tooltip line cannot strike words through
local function Render(segs)
    local look, out = T.CHANGE_LOOK, {}
    for _, sg in ipairs(segs) do
        local text, kind = sg[1], sg[2]
        if kind == "old" then
            out[#out + 1] = " |cff" .. look.old .. "(" .. (text:gsub("^%s+", ""):gsub("%s+$", "")) .. ")|r"
        elseif kind == "gone" then
            out[#out + 1] = "|cff" .. look.old .. text .. " (removed)|r"
        elseif kind and look[kind] then
            out[#out + 1] = "|cff" .. look[kind] .. text .. "|r"
        else
            out[#out + 1] = text
        end
    end
    return table.concat(out)
end

-- what changed from Classic, marked on the game's own lines as the item box marks them; a value Forever dropped, or a
-- change with no line of its own, goes under them. Nothing is marked when any line is secret
local function MarkTip(tip, id)
    local name = tip.GetName and tip:GetName()
    if type(name) ~= "string" or not tip.NumLines or not T.MarkChanges then return end
    local lines = {}
    for i = 1, tip:NumLines() or 0 do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local lt = left and left:GetText()
        if ns.Secret(lt) then return end
        local rt = right and right:IsShown() and right:GetText() or nil
        if ns.Secret(rt) then return end
        local r, g, b = 1, 1, 1
        if left then r, g, b = left:GetTextColor() end
        lines[#lines + 1] = { lt or "", rt or "", r, g, b, 1, 1, 1, fs = left, rfs = right }
    end
    if not T.MarkChanges(lines, id, D.Seed(id)) then return end
    -- what was there before, so the marks can be taken off again while the tooltip stays up
    local was = { text = {}, own = {} }
    for _, l in ipairs(lines) do
        if l.fs then
            if l.segs then
                was.text[l.fs] = l[1]
                l.fs:SetText(Render(l.segs))
            end
            if l.rsegs and l.rfs then
                was.text[l.rfs] = l[2]
                l.rfs:SetText(Render(l.rsegs))
            end
        elseif l.segs then
            tip:AddLine(Render(l.segs), l[3], l[4], l[5])
            was.own[#was.own + 1] = tip:NumLines()
        end
    end
    return was
end
G.MarkTip = MarkTip

-- the marks show always, or while the key the player picked is held (looked up when asked, so a key test sees it)
local HELD = { alt = "IsAltKeyDown", ctrl = "IsControlKeyDown", shift = "IsShiftKeyDown" }
local KEY = { alt = "Alt", ctrl = "Ctrl", shift = "Shift" }
local function MarksShown()
    local m = ns.settings and ns.settings.itemTipChanges
    if m == "always" then return true end
    local held = HELD[m] and _G[HELD[m]]
    return held ~= nil and held() == true
end

-- the tooltip showing a changed item: { tip, id, was = its marks' old text while marked }, so pressing or letting go
-- of the key marks it or takes the marks off without the game drawing it again
local current
local function ItemOf(tip)
    if not tip.GetItem then return end
    local _, link = tip:GetItem()
    if type(link) ~= "string" or ns.Secret(link) then return end
    return tonumber(link:match("|Hitem:(%d+)"))
end
ns.On("MODIFIER_STATE_CHANGED", function()
    local cur = current
    if not cur then return end
    if not (cur.tip.IsShown and cur.tip:IsShown()) or ItemOf(cur.tip) ~= cur.id then
        current = nil
        return
    end
    local want = MarksShown()
    if want and not cur.was then
        cur.was = MarkTip(cur.tip, cur.id)
    elseif not want and cur.was then
        for fs, text in pairs(cur.was.text) do fs:SetText(text) end
        local name = cur.tip:GetName()
        for _, i in ipairs(cur.was.own) do
            local fs = _G[name .. "TextLeft" .. i]
            if fs then fs:SetText("") end
        end
        cur.was = nil
    else
        return
    end
    cur.tip:Show()
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
    if current and current.tip == tip then current = nil end
    local l = G.Lines(id)
    if not l or (mode == "changes" and not l.tag) then return end
    local hint
    local marks = ns.settings.itemTipChanges
    if l.changed and marks ~= "off" and D.HasChanges(id) then
        current = { tip = tip, id = id }
        if MarksShown() then current.was = MarkTip(tip, id) end
        -- while the key is not held, the tag says which key shows the changes
        if KEY[marks] and not current.was then hint = KEY[marks] end
    end
    if l.tag then
        tip:AddLine(ICON .. l.tag .. (hint and ("  |cff" .. T.C.faint .. "(hold " .. hint .. ")|r") or ""),
            T.RGB(l.changed and T.TAG.c.fg or T.TAG.n.fg))
    end
    if l.how then tip:AddLine((l.tag and "" or ICON) .. l.how, T.RGB(T.C.ink)) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Add)
end
