-- AD_Skins: Masque skins on Arc Auras icons. Masque picks, Arc Auras paints:
-- each icon group (and the free icons) is a Masque group, so its skin is
-- chosen in Masque's own options, but no frame of ours is ever handed to
-- Masque. Its skin data is read here into a plan and Core\AD_Factory.lua
-- draws it with every other look (PaintSkin), on our frames and on the
-- engine's aura buttons alike, pixel-snapped, on our own schedule.
-- Off by default (Settings > Masque).
-- The Cooldown Manager look (appearance / arrangement cdmLook) is a plan of
-- our own the same painter draws, with no Masque at all.
local ADDON, NS = ...
local Store = NS.Store
local Events = NS.Events

local SK = {}
NS.Skins = SK

-- the name Masque lists our groups under
SK.ADDON = "Arc Auras"
SK.FREE = "free"
SK.groups = {}   -- [static id] = Masque group
SK.names = {}    -- [static id] = the name it was given
SK.plans = {}    -- [static id] = plan, or false for no skin, until the next change
SK.gen = 0

function SK.Lib()
    return LibStub ~= nil and LibStub("Masque", true) or nil
end

function SK.On()
    return Store.GetSetting("masqueSkins") == true and SK.Lib() ~= nil
end

-- Any change Masque reports, a colour or a profile change it does not: every
-- plan is read again and every look repainted.
function SK.Changed()
    wipe(SK.plans)
    SK.gen = SK.gen + 1
    Store.Dirty("style")
end

-- Masque reports skin, scale and layer switches through the callback; colour
-- and profile changes only through these two group methods, hooked when they
-- exist (a renamed one leaves those two unseen until the next change).
local function Watch(g)
    if g.RegisterCallback then g:RegisterCallback(SK.Changed) end
    for _, m in ipairs({ "__SetColor", "__Update" }) do
        if type(g[m]) == "function" then hooksecurefunc(g, m, SK.Changed) end
    end
end

-- The Masque group under a static id, made the first time an icon asks.
function SK.Group(sid, name)
    local g = SK.groups[sid]
    if not g then
        local M = SK.Lib()
        g = M and M:Group(SK.ADDON, name, sid)
        if not g then return nil end
        SK.groups[sid] = g
        SK.names[sid] = name
        Watch(g)
    elseif SK.names[sid] ~= name and g.SetName then
        g:SetName(name)
        SK.names[sid] = name
    end
    return g
end

-- A group's name in Masque's list: its layout's and its own.
function SK.GroupName(g)
    local lay = g.layoutId and Store.Get(g.layoutId)
    local name = g.name or "Group"
    return (lay and lay.name) and (lay.name .. " / " .. name) or name
end

-- Where a record's skin comes from: an icon group's members share the
-- group's; free icons share one; a show-all group draws the unit's auras with
-- its own look and reminders are their own records, so neither has one.
function SK.SourceOf(rec)
    if not rec then return nil end
    if rec.type == "group" then
        if rec.groupKind == "reminder" or (Store.ShowsAll and Store.ShowsAll(rec)) then return nil end
        return "g" .. rec.id, SK.GroupName(rec)
    end
    -- an icon record; never a look proxy or a type's look
    if rec.type ~= "icon" then return nil end
    local g = rec.groupId and Store.Get(rec.groupId)
    if g then return SK.SourceOf(g) end
    if rec.groupId then return nil end
    return SK.FREE, "Free icons"
end

-- A layer's entry for a button like ours (Masque's Action type), or nil.
local function Entry(e)
    if type(e) ~= "table" then return nil end
    e = e.Action or e
    if type(e) ~= "table" or e.Hide then return nil end
    return e
end

-- The skin as one table the painter reads: each layer's entry (nil = not
-- drawn), the user's colours, the group's scale and the shape.
local function Plan(g)
    local M = SK.Lib()
    local db = g and g.db
    if not (M and db) or db.Disabled then return false end
    local skin = M:GetSkin(db.SkinID)
    if type(skin) ~= "table" and M.GetDefaultSkin then
        local _, s = M:GetDefaultSkin()
        skin = s
    end
    if type(skin) ~= "table" then return false end
    local mask = skin.Mask
    if type(mask) == "table" then mask = mask.Action or mask end
    local cd = Entry(skin.Cooldown) or {}
    local p = {
        id = db.SkinID,
        shape = skin.Shape,
        round = skin.Shape == "Circle" or cd.IsRound == true,
        scale = tonumber(db.Scale) or 1,
        colors = type(db.Colors) == "table" and db.Colors or {},
        icon = Entry(skin.Icon) or {},
        mask = (type(mask) == "table" or type(mask) == "string") and mask or nil,
        normal = Entry(skin.Normal),
        backdrop = db.Backdrop == true and Entry(skin.Backdrop) or nil,
        cooldown = cd,
    }
    -- a shadow and a gloss need a picture of their own
    local sh, gl = Entry(skin.Shadow), Entry(skin.Gloss)
    p.shadow = (db.Shadow == true and sh and sh.Texture) and sh or nil
    p.gloss = (db.Gloss == true and gl and gl.Texture) and gl or nil
    return p
end

-- The game's Cooldown Manager look, from the art on its bars (Forever 70058
-- CooldownViewer.xml): the picture under its mask, the overlay round it
-- (border and shadow, 9 x 8 out on a 50 icon and 6 x 5 on a 30: about 1.38 x
-- 1.33 of the icon) and its swipe picture. The mask keeps the art's margin, so
-- the icon's box is the bar's whole icon.
SK.CDM_PLAN = {
    id = "cdm", scale = 1, colors = {},
    icon = { Width = 36, Height = 36, UseMask = true },
    mask = { Atlas = "UI-HUD-CoolDownManager-Mask", Width = 36, Height = 36 },
    normal = { Atlas = "UI-HUD-CoolDownManager-IconOverlay", Width = 49.7, Height = 47.9, DrawLayer = "OVERLAY" },
    cooldown = { Texture = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe" },
}

-- In the Cooldown Manager look: an icon by its own switch, else its group's;
-- a group by its own. A group that shows every aura on a unit keeps its look.
function SK.CdmLook(rec)
    if type(rec) ~= "table" then return false end
    if rec.type == "group" then
        return not (Store.ShowsAll and Store.ShowsAll(rec)) and Store.Resolve(rec, "arrangement", "cdmLook") == true
    end
    if rec.type ~= "icon" then return false end
    if Store.Resolve(rec, "appearance", "cdmLook") == true then return true end
    local g = rec.groupId and Store.Get(rec.groupId)
    return g ~= nil and SK.CdmLook(g)
end

-- The skin a record wears now, or nil: the Cooldown Manager look first; else
-- Masque on, the switch on, a group for it that Masque has not disabled.
function SK.PlanFor(rec)
    if SK.CdmLook(rec) then return SK.CDM_PLAN end
    if not SK.On() then return nil end
    local sid, name = SK.SourceOf(rec)
    if not sid then return nil end
    local p = SK.plans[sid]
    if p == nil then
        p = Plan(SK.Group(sid, name))
        SK.plans[sid] = p
    end
    return p or nil
end

function SK.Skinned(rec)
    return SK.PlanFor(rec) ~= nil
end

-- Off: our groups leave Masque's list (Masque keeps their settings for the
-- next time) and every look goes back to its own.
function SK.SetOn(v)
    Store.SetSetting("masqueSkins", v and true or nil)
    if not v then
        for sid, g in pairs(SK.groups) do
            if g.Delete then g:Delete() end
            SK.groups[sid] = nil
            SK.names[sid] = nil
        end
    end
    SK.Changed()
end

-- Skins from other addons register as they load: read again once all are in.
Events.On("PLAYER_LOGIN", "adskins", function()
    if SK.Lib() then SK.Changed() end
end)
