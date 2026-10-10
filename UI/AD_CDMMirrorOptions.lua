-- AD_CDMMirrorOptions: the "From Cooldown Manager" card on the New Layout page.
-- Core\AD_CDMMirror.lua reads and builds; this file only offers it, through NL.AddOwnCard.
local ADDON, NS = ...

local MO = {}
NS.CDMMirrorOptions = MO

MO.TITLE = "From Cooldown Manager"
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

-- The card reads the Cooldown Manager as the window builds: its line says why
-- when there is nothing to build. The picture is fixed (a player's own bars,
-- often one or two icons, scaled up into blocks).
function MO.Draw(stage)
    local rows, why = MO.Rows()
    MO.entry.desc = rows and MO.DESC or MO.SAY[why] or MO.DESC
    MO.DrawGlyph(stage)
end

-- The Cooldown Manager's rows in grey, an arrow, and the same rows as our
-- coloured groups: two rows each, four large squares over five small.
MO.GLYPH_ROWS = { { n = 4, size = 12 }, { n = 5, size = 9 } }
MO.GLYPH_X = { from = 36, arrow = 80, to = 124 }

function MO.DrawGlyph(stage)
    local AT = NS.AT
    local COL = AT.COL
    local GC = NS.Options and NS.Options.GROUP_COLORS or {}
    local function Rows(cx, top, bottom)
        local y = 18
        for i, r in ipairs(MO.GLYPH_ROWS) do
            local c = (i == 1) and top or bottom
            local w = r.n * r.size + (r.n - 1) * 2
            local x0 = math.floor(cx - w / 2)
            for k = 1, r.n do
                local t = stage:CreateTexture(nil, "ARTWORK")
                t:SetColorTexture(c[1], c[2], c[3], 0.9)
                t:SetSize(r.size, r.size)
                t:SetPoint("TOPLEFT", stage, "TOPLEFT", x0 + (k - 1) * (r.size + 2), -y)
            end
            y = y + r.size + 3
        end
    end
    Rows(MO.GLYPH_X.from, COL.dim, COL.dim)
    Rows(MO.GLYPH_X.to, AT.Mute(GC.cooldown or COL.arc), AT.Mute(GC.aura or COL.arc))
    local head = AT.MakeChevron(stage)
    head:SetDir("right")
    head:SetColor(COL.arc)
    head:SetScale(2)
    -- its offsets are in its own scale
    head:SetPoint("CENTER", stage, "TOPLEFT", MO.GLYPH_X.arrow / 2, -30 / 2)
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
    local why = NS.CDMMirror.Check()
    if why then
        MO.Say(MO.SAY[why] or MO.SAY.read)
        return
    end
    MO.AskLook(function(look)
        local rec, why2 = NS.CDMMirror.Build(look)
        if rec then
            NS.Options.OpenLayout(rec)
            MO.OfferOff()
            return
        end
        MO.Say(MO.SAY[why2] or MO.SAY.read)
    end)
end

-- Before a build: the Cooldown Manager's look or ours, off unless picked. Two
-- buttons and no Escape: a popup's Escape answers as its second button.
MO.LOOK_POPUP = "ARCAURAS_CDM_LOOK"
MO.LOOK_TEXT = "Give the new icons the Cooldown Manager's look: its rounded corners, border and shadow?\n\n"
    .. "Any icon's Appearance > Look switches it later."
function MO.AskLook(onPick)
    if not (StaticPopupDialogs and StaticPopup_Show) then
        onPick(false)
        return
    end
    local d = StaticPopupDialogs[MO.LOOK_POPUP] or {
        button1 = "Its look", button2 = "Arc Auras look", timeout = 0, whileDead = true, hideOnEscape = false,
        preferredIndex = 3,
    }
    StaticPopupDialogs[MO.LOOK_POPUP] = d
    d.text = MO.LOOK_TEXT
    -- the next frame, so the next question can take a popup of its own
    d.OnAccept = function() C_Timer.After(0, function() onPick(true) end) end
    d.OnCancel = function(_, _, reason)
        if reason == "clicked" then C_Timer.After(0, function() onPick(false) end) end
    end
    StaticPopup_Show(MO.LOOK_POPUP)
end

-- After a build, while the game's own Cooldown Manager is on: one question,
-- turn it off now? Yes is Settings > Cooldown Manager's own switch.
MO.OFF_POPUP = "ARCAURAS_CDM_OFF"
MO.OFF_TEXT = "Your Cooldown Manager layout is ready. Turn off the game's own Cooldown Manager now?\n\n"
    .. "Settings > Cooldown Manager turns it back on."
function MO.CDMOn()
    local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("cooldownViewerEnabled")
    return v ~= nil and v ~= "0"
end
function MO.OfferOff()
    if not (MO.CDMOn() and StaticPopupDialogs and StaticPopup_Show) then return end
    local d = StaticPopupDialogs[MO.OFF_POPUP] or {
        button1 = "Turn it off", button2 = "Keep it", timeout = 0, whileDead = true, hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs[MO.OFF_POPUP] = d
    d.text = MO.OFF_TEXT
    d.OnAccept = function()
        C_CVar.SetCVar("cooldownViewerEnabled", "0")
        if NS.LayoutEngine and NS.LayoutEngine.QueueRebuild then NS.LayoutEngine.QueueRebuild() end
    end
    StaticPopup_Show(MO.OFF_POPUP)
end

MO.entry = {
    title = MO.TITLE,
    desc = MO.DESC,
    draw = function(stage) MO.Draw(stage) end,
    pick = function() MO.Pick() end,
    avail = function() return NS.CDMMirror ~= nil and NS.CDMMirror.Available() end,
    -- right after the templates, ahead of Empty and Import
    lead = true,
}
NS.NewLayout.AddOwnCard(MO.entry)
