-- AD_TextDrag: while the options window is open and "Drag on screen" is on,
-- the edited icon's or bar's texts each take a faint drag box. A drag writes
-- that text's own X / Y (whole numbers, kept in the field's range) through the
-- store, as its sliders do, so the normal style pass places the text and the
-- sliders follow. Every placement site notes its text here (TD.Note); nothing
-- here moves a text itself.
local ADDON, NS = ...

local TD = {}
NS.TextDrag = TD

-- [family][section][Y field] = X field: every text offset pair a drag writes
TD.PAIRS = {
    icon = {
        text = { durationY = "durationX", stackY = "stackX", ammoY = "ammoX" },
        label = { labelY = "labelX", labelY2 = "labelX2", labelY3 = "labelX3", labelY4 = "labelX4",
            labelY5 = "labelX5", labelY6 = "labelX6" },
        keybind = { keybindY = "keybindX" },
    },
    bar = {
        text = { durOffsetY = "durOffsetX", stkOffsetY = "stkOffsetX", nameOffsetY = "nameOffsetX",
            resOffsetY = "resOffsetX", res2OffsetY = "res2OffsetX", res3OffsetY = "res3OffsetX",
            hpOffsetY = "hpOffsetX", hp2OffsetY = "hp2OffsetX", hp3OffsetY = "hp3OffsetX",
            rcOffsetY = "rcOffsetX" },
        deck = { posOffsetY = "posOffsetX", procOffsetY = "procOffsetX" },
        pictext = { ptStkY = "ptStkX", ptTimeY = "ptTimeX" },
    },
}

TD.BOX_COLOR = { 0.2, 0.8, 1, 0.18 }
TD.MIN_W, TD.MIN_H = 16, 12

-- The X field a Y field pairs with, or nil: a Y row gets the switch beside it.
function TD.Pair(family, section, yField)
    local f = TD.PAIRS[family]
    local s = f and f[section]
    return s and s[yField] or nil
end

TD.on = false
TD.fight = false
-- [fontstring] = { id, family, section, x, y, k, owner }
TD.texts = setmetatable({}, { __mode = "k" })
-- [fontstring] = its box
TD.boxes = setmetatable({}, { __mode = "k" })

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The record whose texts take boxes: the item the editor has open, while the
-- switch is on and no fight runs (an aura button's texts cannot move then).
function TD.Target()
    if not TD.on or TD.fight then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local O = NS.Options
    return O and O.EditingId and O.EditingId() or nil
end

-- the editor's stage copy, or a frame under it (an aura button's texts)
local function OnStage(fr)
    for _ = 1, 8 do
        if not fr then return false end
        if fr._adOnStage == true then return true end
        fr = fr.GetParent and fr:GetParent()
    end
    return false
end

-- A placement site notes its text once it is placed: the record, the X / Y
-- fields it reads and k (an icon's offsets are times its scale). The editor's
-- own preview copies never take a box (bars pass none for their preview).
function TD.Note(fs, rec, family, section, xKey, yKey, k, owner)
    if not (fs and rec and rec.id) or rec._adMulti then return end
    if OnStage(owner) then return end
    local t = TD.texts[fs]
    if not t then
        t = {}
        TD.texts[fs] = t
    end
    t.id, t.family, t.section, t.x, t.y, t.k, t.owner = rec.id, family, section, xKey, yKey, k or 1, owner
    if TD.on or TD.boxes[fs] then TD.Sync(fs, t) end
end

local function Shown(region, visible)
    local v
    if visible then v = region:IsVisible() else v = region:IsShown() end
    return not Secret(v) and v == true
end

-- One text's box: shown on the edited item's texts that are on screen.
function TD.Sync(fs, t)
    local b = TD.boxes[fs]
    -- a box being dragged stays until the button comes up
    if b and b._drag then return end
    local id = TD.Target()
    local want = id ~= nil and t.id == id and Shown(fs) and (t.owner == nil or Shown(t.owner, true))
    if not want then
        if b then b:Hide() end
        return
    end
    b = b or TD.Box(fs)
    TD.Size(b, fs)
    b:Show()
end

-- The box covers the text, at least a small square where an empty one sits.
function TD.Size(b, fs)
    local w = fs.GetStringWidth and fs:GetStringWidth()
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if Secret(w) or type(w) ~= "number" then w = 0 end
    if Secret(h) or type(h) ~= "number" then h = 0 end
    local p = fs:GetParent()
    local ps = p and p:GetEffectiveScale()
    local us = UIParent:GetEffectiveScale()
    local r = 1
    if type(ps) == "number" and not Secret(ps) and type(us) == "number" and us > 0 then r = ps / us end
    b:SetSize(math.max(TD.MIN_W, w * r) + 6, math.max(TD.MIN_H, h * r) + 4)
end

function TD.Box(fs)
    local b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:EnableMouse(true)
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(b)
    local c = TD.BOX_COLOR
    tex:SetColorTexture(c[1], c[2], c[3], c[4])
    b.tex = tex
    b:SetPoint("CENTER", fs, "CENTER", 0, 0)
    b._fs = fs
    b:SetScript("OnMouseDown", TD.Down)
    b:SetScript("OnMouseUp", function(self) TD.Up(self) end)
    b:SetScript("OnHide", function(self) TD.Up(self) end)
    TD.boxes[fs] = b
    return b
end

-- A whole number in the field's own range.
function TD.Clamp(t, key, v)
    local fam = NS.Schema and NS.Schema[t.family]
    local sec = fam and fam[t.section]
    local d = sec and sec.fields and sec.fields[key]
    v = math.floor(v + 0.5)
    if d and type(d.min) == "number" and v < d.min then v = d.min end
    if d and type(d.max) == "number" and v > d.max then v = d.max end
    return v
end

function TD.Down(b, button)
    if button ~= "LeftButton" then return end
    local t = TD.texts[b._fs]
    local Store = NS.Store
    local rec = t and Store.Get(t.id)
    if not rec then return end
    local p = b._fs:GetParent()
    local sc = p and p:GetEffectiveScale()
    if type(sc) ~= "number" or Secret(sc) or sc <= 0 then return end
    local cx, cy = GetCursorPosition()
    b._drag = { rec = rec, t = t, cx = cx, cy = cy, sc = sc * (t.k or 1),
        x0 = tonumber(Store.Resolve(rec, t.section, t.x)) or 0, y0 = tonumber(Store.Resolve(rec, t.section, t.y)) or 0 }
    b:SetScript("OnUpdate", TD.Move)
end

-- Each frame of a drag: the total move since the press, so nothing drifts;
-- a write only when the whole number changes.
function TD.Move(b)
    local d = b._drag
    if not d then
        b:SetScript("OnUpdate", nil)
        return
    end
    -- a release away from the box never reaches its OnMouseUp
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        TD.Up(b)
        return
    end
    local cx, cy = GetCursorPosition()
    TD.Write(d, TD.Clamp(d.t, d.t.x, d.x0 + (cx - d.cx) / d.sc), TD.Clamp(d.t, d.t.y, d.y0 + (cy - d.cy) / d.sc))
end

function TD.Write(d, nx, ny)
    local Store, t, rec = NS.Store, d.t, d.rec
    if (tonumber(Store.Resolve(rec, t.section, t.x)) or 0) ~= nx then Store.SetOverride(rec, t.section, t.x, nx) end
    if (tonumber(Store.Resolve(rec, t.section, t.y)) or 0) ~= ny then Store.SetOverride(rec, t.section, t.y, ny) end
end

function TD.Up(b)
    if not b._drag then return end
    b._drag = nil
    b:SetScript("OnUpdate", nil)
    local t = TD.texts[b._fs]
    if t then TD.Sync(b._fs, t) end
end

-- Every noted text looks again: the switch, the selection, a rebuild, a fight.
function TD.Refresh()
    for fs, t in pairs(TD.texts) do TD.Sync(fs, t) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, e)
    TD.fight = (e == "PLAYER_REGEN_DISABLED")
    TD.Refresh()
end)

function TD.SetOn(v)
    TD.on = (v == true)
    if TD.on then
        TD.fight = InCombatLockdown ~= nil and InCombatLockdown() == true
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterAllEvents()
    end
    TD.Refresh()
end

-- The window closed: the switch goes off and every box goes away.
function TD.Stop()
    for _, b in pairs(TD.boxes) do
        b._drag = nil
        b:SetScript("OnUpdate", nil)
        b:Hide()
    end
    TD.SetOn(false)
end
