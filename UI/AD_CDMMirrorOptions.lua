-- AD_CDMMirrorOptions: the "From my Cooldown Manager" card on the New Layout page.
-- Core\AD_CDMMirror.lua reads and builds; this file only offers it, through NL.AddOwnCard.
local ADDON, NS = ...

local MO = {}
NS.CDMMirrorOptions = MO

MO.TITLE = "From my Cooldown Manager"
MO.DESC = "Your Cooldown Manager's bars as groups: same spells, sizes and places. Then hide its bars in Edit Mode."
MO.SAY = {
    empty = "Your Cooldown Manager shows no spells yet.",
    read = "Your Cooldown Manager could not be read just now. Try again in a moment.",
}

-- The bars the layout would get, each a row of its icons at its own height and
-- size (at most 12 drawn); nil and why when there is nothing to build.
function MO.Rows()
    local M = NS.CDMMirror
    local snap = M.Read()
    if not snap.complete then return nil, "read" end
    local plan = M.Plan(snap, M.Merge(snap))
    if #plan == 0 then return nil, "empty" end
    local h = M.Num(UIParent:GetHeight()) or 768
    if h <= 0 then h = 768 end
    local rows = {}
    for _, part in ipairs(plan) do
        local v = part.viewer
        local geo = M.Geometry(v, part.ids)
        rows[#rows + 1] = {
            kind = v.groupKind or "aura",
            y = geo.y or math.floor(v.y * h / 1080 + 0.5),
            size = geo.size or geo.height or 30,
            n = math.min(#part.pieces, 12),
        }
    end
    return rows
end

-- The card reads the Cooldown Manager as the window builds: its picture is the
-- player's own bars, and its line says why when there is nothing to build.
function MO.Draw(stage)
    local rows, why = MO.Rows()
    MO.entry.desc = rows and MO.DESC or MO.SAY[why] or MO.DESC
    if rows then
        NS.NewLayout.DrawRows(stage, rows)
    else
        NS.NewLayout.DrawEmpty(stage)
    end
end

-- A card's own line carries a failed click's reason: nothing prints to chat.
function MO.Say(text)
    local NL = NS.NewLayout
    local row = NL and NL.ownRow
    local COL = NS.AT.COL
    for _, c in ipairs(row and row._cards or {}) do
        if c.entry == MO.entry and c.desc then
            c.desc:SetText(text)
            c.desc:SetTextColor(COL.ink[1], COL.ink[2], COL.ink[3])
        end
    end
end

function MO.Pick()
    local rec, why = NS.CDMMirror.Build()
    if rec then
        NS.Options.OpenLayout(rec)
        return
    end
    MO.Say(MO.SAY[why] or MO.SAY.read)
end

MO.entry = {
    title = MO.TITLE,
    desc = MO.DESC,
    draw = function(stage) MO.Draw(stage) end,
    pick = function() MO.Pick() end,
    avail = function() return NS.CDMMirror ~= nil and NS.CDMMirror.Available() end,
}
NS.NewLayout.AddOwnCard(MO.entry)
