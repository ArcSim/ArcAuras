-- Arc UI Forever became Arc Auras. Its setup stays in ArcUIv2DB, kept loaded by
-- the ArcUI stand-in (or the old addon itself), and moves in on the first start.
local ADDON, NS = ...

local Migrate = {}
NS.Migrate = Migrate

local function DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, x in pairs(v) do t[DeepCopy(k, seen)] = DeepCopy(x, seen) end
    return t
end

local function HasRecords(db)
    return type(db) == "table" and type(db.records) == "table" and next(db.records) ~= nil
end

-- Copies the old setup into an empty store, once. A copy, not the old table:
-- the old file keeps its data, so turning Arc Auras off loses nothing.
function Migrate.FromArcUI(db)
    if db.migratedFrom or HasRecords(db) then return false end
    local old = _G.ArcUIv2DB
    if not HasRecords(old) then return false end
    for k, v in pairs(DeepCopy(old)) do db[k] = v end
    db.migratedFrom = "ArcUI"
    return true
end

-- The full old addon still loaded (not the stand-in, which marks itself
-- X-Bridge) draws every display a second time.
function Migrate.OldEngineLoaded()
    if NS.IsForever ~= true then return false end
    if not C_AddOns.IsAddOnLoaded("ArcUI") then return false end
    return C_AddOns.GetAddOnMetadata("ArcUI", "X-Bridge") == nil
end

local notice

local function BuildNotice()
    local AT = NS.AT
    local COL = AT.COL
    local f = CreateFrame("Frame", "ArcAurasMoveNotice", UIParent, "BackdropTemplate")
    f:SetSize(430, 150)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    AT.Skin(f, COL.bg, COL.line2)
    tinsert(UISpecialFrames, "ArcAurasMoveNotice")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(STANDARD_TEXT_FONT, 14, "")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("|cff3fc9f2Arc|r|cffd5e2f2 Auras|r")

    local body = f:CreateFontString(nil, "OVERLAY")
    body:SetFont(STANDARD_TEXT_FONT, 12, "")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    body:SetJustifyH("LEFT")
    body:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    body:SetText("Arc UI Forever is still turned on. Arc Auras replaces it, so your displays are drawn twice right now. Your setup is already in Arc Auras: turn Arc UI Forever off to finish the move.")

    local later = AT.MakeQuietButton(f, "Not now", 90)
    later:SetPoint("BOTTOMRIGHT", -14, 14)
    later:SetScript("OnClick", function() f:Hide() end)

    local off = AT.MakeSmallButton(f, "Turn it off and reload", 170)
    off:SetPoint("RIGHT", later, "LEFT", -8, 0)
    off:SetScript("OnClick", function()
        C_AddOns.DisableAddOn("ArcUI")
        C_AddOns.SaveAddOns()
        ReloadUI()
    end)
    return f
end

function Migrate.ShowNotice()
    notice = notice or BuildNotice()
    notice:Show()
end
