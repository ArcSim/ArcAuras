-- Minimap button, made through the shared minimap button library so minimap
-- addons can list, place and fade it like every other addon's button.
-- Left-click toggles the options, right-click toggles move-layouts mode, and a
-- drag moves it around the rim. Settings: "minimapAngle" (degrees) and
-- "minimapHide" (bool); NS.MinimapButtonRefresh applies both.

local ADDON, NS = ...
local Events = NS.Events

local NAME = "ArcAuras"
local MM = {}
NS.MinimapButton = MM

local function Angle()
    local a = NS.Store and NS.Store.GetSetting and NS.Store.GetSetting("minimapAngle")
    if type(a) == "number" then return a end
    -- retail ArcUI's button sits near 225
    return NS.IsForever and 220 or 195
end

local function Hidden()
    return NS.Store and NS.Store.GetSetting and NS.Store.GetSetting("minimapHide") == true
end

-- The library reads and writes these fields; a drag writes every frame, so the
-- angle is held here and saved once when the drag ends (a save restyles).
local dragPos
MM.db = setmetatable({}, {
    __index = function(_, k)
        if k == "minimapPos" then return dragPos or Angle() end
        if k == "hide" then return Hidden() end
        return nil
    end,
    __newindex = function(_, k, v)
        if k == "minimapPos" and type(v) == "number" then dragPos = v end
    end,
})

local function Libs()
    local LS = LibStub
    if not LS then return nil, nil end
    return LS("LibDataBroker-1.1", true), LS("LibDBIcon-1.0", true)
end

local function Broker(ldb)
    local obj = ldb:GetDataObjectByName(NAME)
    if obj then return obj end
    return ldb:NewDataObject(NAME, {
        type = "launcher",
        text = "Arc Auras",
        -- ADDON is the folder name: ArcAuras on Forever, ArcDisplay on retail.
        icon = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\ArcAuras_Minimap_64",
        -- the library trims a twentieth off each edge while not pressed
        iconCoords = { -1 / 18, 19 / 18, -1 / 18, 19 / 18 },
        OnClick = function(_, mouse)
            if mouse == "RightButton" then
                if NS.LayoutEngine and NS.LayoutEngine.SetMoveMode then
                    NS.LayoutEngine.SetMoveMode(not NS.LayoutEngine.IsMoveMode())
                end
            elseif NS.Options and NS.Options.Toggle then
                NS.Options.Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            if not (tt and tt.AddLine) then return end
            local Tr = (NS.AT and NS.AT.Tr) or function(s) return s end
            tt:AddLine("|cff3fc9f2Arc|r Auras")
            tt:AddLine(Tr("Left-click: options"), 0.8, 0.86, 0.94)
            tt:AddLine(Tr("Right-click: move layouts"), 0.8, 0.86, 0.94)
            tt:AddLine(Tr("Drag: move this button"), 0.55, 0.6, 0.68)
        end,
    })
end

-- Our look on both games: the round icon inside the tracking ring.
local function Dress(dbi, btn)
    if dbi.SetButtonBorder then dbi:SetButtonBorder(NAME, 136430, 53, "TOPLEFT", 0, 0) end
    if dbi.RemoveButtonBackground then dbi:RemoveButtonBackground(NAME) end
    if dbi.SetButtonIcon then dbi:SetButtonIcon(NAME, nil, 19, "TOPLEFT", 7, -6) end
    if btn.icon and btn.icon.SetMask and not btn._adMasked then
        btn.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        btn._adMasked = true
    end
end

function MM.Build()
    local ldb, dbi = Libs()
    if not (ldb and dbi) then return nil end
    local btn = dbi:GetMinimapButton(NAME)
    if btn then return btn end
    local obj = Broker(ldb)
    if not obj then return nil end
    dbi:Register(NAME, obj, MM.db)
    btn = dbi:GetMinimapButton(NAME)
    if not btn then return nil end
    Dress(dbi, btn)
    btn:HookScript("OnDragStop", function()
        if dragPos and NS.Store and NS.Store.SetSetting then
            NS.Store.SetSetting("minimapAngle", math.floor(dragPos + 0.5) % 360)
        end
        dragPos = nil
    end)
    return btn
end

function NS.MinimapButtonRefresh()
    local _, dbi = Libs()
    if not (dbi and dbi:GetMinimapButton(NAME)) then return end
    if Hidden() then dbi:Hide(NAME) else dbi:Show(NAME) end
end

-- Built at PLAYER_LOGIN, after the store's ADDON_LOADED init.
Events.On("PLAYER_LOGIN", "adminimap", function()
    MM.Build()
    NS.MinimapButtonRefresh()
end)
