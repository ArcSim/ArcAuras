-- AD_IconScreen: Play on screen for icons, the editor preview drawn over the live icon.
-- Owns the copy and which icon it covers; the options pane paints it (IS.painter),
-- the engine keeps the live frame hidden under it, the aura driver its container at 0.
-- It touches only our own frames and the aura container's alpha, all legal in combat.
local ADDON, NS = ...

local IS = {}
NS.IconScreen = IS

-- The live frame the engine places for this icon now, or nil: a released
-- frame has no points, and a hidden container hides the icon with it.
function IS.Live(rec)
    local f = rec and NS.Factory.frames[rec.id]
    if not f or f:GetNumPoints() == 0 then return nil end
    local p = f:GetParent()
    if not (p and p:IsVisible()) then return nil end
    return f
end

-- Offered while the icon shows on screen; kept while it plays, when its live
-- frame is the hidden one.
function IS.OK(rec)
    local f = IS.Live(rec)
    return f ~= nil and (f:IsShown() == true or IS.On(rec.id))
end

-- With an id: whether that icon is playing.
function IS.On(id)
    return IS.recId ~= nil and (id == nil or IS.recId == id)
end

-- The copy takes the live frame's parent, size, place, strata and level, so
-- everything the style pass derives from them matches the live icon.
function IS.Place(f)
    local c = IS.copy
    if not c then
        c = NS.Factory.CreatePreview(f:GetParent())
        IS.copy = c
    end
    if c:GetParent() ~= f:GetParent() then c:SetParent(f:GetParent()) end
    c:SetSize(f:GetSize())
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    c:SetFrameStrata(f:GetFrameStrata())
    c:SetFrameLevel(f:GetFrameLevel())
    c:Show()
end

function IS.Paint(rec)
    if IS.painter and IS.copy then IS.painter(rec, IS.copy) end
end

-- Starts the copy on this icon, or re-places and repaints it after a change.
function IS.Start(rec)
    local f = IS.Live(rec)
    if not f then return false end
    if IS.recId ~= rec.id then IS.Stop() end
    IS.recId = rec.id
    IS.Place(f)
    f:Hide()
    if NS.DriverAura and NS.DriverAura.SyncAlpha then NS.DriverAura.SyncAlpha(rec.id) end
    IS.Paint(rec)
    return true
end

-- The engine just placed this icon's live frame. True keeps it hidden; the
-- copy follows it (a new size, place or group) and repaints.
function IS.Follow(rec, f)
    if IS.recId ~= rec.id then return false end
    IS.Place(f)
    IS.Paint(rec)
    return true
end

function IS.Stop()
    local id = IS.recId
    if not id then return end
    IS.recId = nil
    local c = IS.copy
    if c then
        NS.Factory.StopGlow(c)
        NS.Factory.StopUsableGlow(c)
        c.cooldown:Clear()
        local ab = c._adAuraBtn
        if ab then
            if ab._adSwipe.Resume then ab._adSwipe:Resume() end
            ab._adSwipe:Clear()
            ab._adLoopUntil = nil
            ab:Hide()
        end
        c:Hide()
    end
    -- a frame the engine still places comes back; a released one stays down
    local f = NS.Factory.frames[id]
    if f and f:GetNumPoints() > 0 then f:Show() end
    if NS.DriverAura and NS.DriverAura.SyncAlpha then NS.DriverAura.SyncAlpha(id) end
    if IS.onStop then IS.onStop() end
end
