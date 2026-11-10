-- AD_BarTint: a bar's Fill color while its While conditions hold (Effects > While). A flat texture over
-- the fill, anchored to the fill's own edge, so it follows a value Lua may not read.
local ADDON, NS = ...
local Bars = NS.Bars
if not Bars then return end

local BT = {}
Bars.Tint = BT
BT.KEY = "adbartint"

-- An aura bar's fill is handed to the game's aura button, and nothing of ours
-- may hang on it there.
function BT.Allowed(rec) return rec ~= nil and rec.barKind ~= "aura" end

-- The colour to wear now, nil for none.
function BT.Color(rec, holds, edit)
    local c = rec and rec.c and rec.c.fadeTint
    if type(c) ~= "table" or edit == true or holds ~= true or not BT.Allowed(rec) then return nil end
    return c
end

function BT.Paint(e)
    local shell = e and e.shell
    if not shell then return end
    local C, E = NS.Conditions, NS.LayoutEngine
    local rec = e.rec
    local holds = C ~= nil and C.WhileHolds ~= nil and C.WhileHolds(rec) == true
    local edit = E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true
    local c = (not e.pipsOn) and BT.Color(rec, holds, edit) or nil
    local tex = shell._adTint
    if not c then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        tex = shell.fill:CreateTexture(nil, "ARTWORK", nil, 7)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        local edge = shell.fill:GetStatusBarTexture()
        tex:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 0)
        shell._adTint = tex
    end
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tex:Show()
end

function BT.PaintAll()
    if Bars.EachLive then Bars.EachLive(BT.Paint) end
end

local Events = NS.Events
if Events and Events.OnMessage then Events.OnMessage("AD_VISIBILITY", BT.KEY, BT.PaintAll) end
