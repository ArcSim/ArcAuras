-- Minimap button.
-- Left-click toggles the options, right-click toggles move-layouts mode, and a
-- drag moves it around the rim. Settings: "minimapAngle" (degrees) and
-- "minimapHide" (bool); NS.MinimapButtonRefresh applies both.

local ADDON, NS = ...
local Events = NS.Events

local Minimap_ = Minimap
local btn

local function Angle()
    local a = NS.Store and NS.Store.GetSetting and NS.Store.GetSetting("minimapAngle")
    if type(a) == "number" then return a end
    -- retail ArcUI's button sits near 225
    return NS.IsForever and 220 or 195
end

local function Reposition(angle)
    local rad = math.rad(angle)
    local r = (Minimap_:GetWidth() or 140) / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap_, "CENTER",
        math.cos(rad) * r, math.sin(rad) * r)
end

local function Build()
    if btn then return end
    btn = CreateFrame("Button", "ArcUIv2MinimapButton", Minimap_)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 7, -6)
    -- ADDON is the folder name: ArcAuras on Forever, ArcDisplay on retail.
    icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Textures\\ArcAuras_Minimap_64")
    icon:SetTexCoord(0, 1, 0, 1)
    if icon.SetMask then
        icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    btn.icon = icon

    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff3fc9f2Arc|r Auras")
        GameTooltip:AddLine("Left-click: options", 0.8, 0.86, 0.94)
        GameTooltip:AddLine("Right-click: move layouts", 0.8, 0.86, 0.94)
        GameTooltip:AddLine("Drag: move this button", 0.55, 0.6, 0.68)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if NS.LayoutEngine and NS.LayoutEngine.SetMoveMode then
                NS.LayoutEngine.SetMoveMode(not NS.LayoutEngine.IsMoveMode())
            end
        elseif NS.Options and NS.Options.Toggle then
            NS.Options.Toggle()
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(s)
            local mx, my = Minimap_:GetCenter()
            if not mx then return end
            local cx, cy = GetCursorPosition()
            local scale = Minimap_:GetEffectiveScale()
            if not scale or scale <= 0 then return end
            local a = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            s._adAngle = a
            Reposition(a)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if self._adAngle and NS.Store and NS.Store.SetSetting then
            NS.Store.SetSetting("minimapAngle", math.floor(self._adAngle + 0.5))
        end
    end)

    Reposition(Angle())
end

function NS.MinimapButtonRefresh()
    if not btn then return end
    local hide = NS.Store and NS.Store.GetSetting
        and NS.Store.GetSetting("minimapHide") == true
    btn:SetShown(not hide)
    if not hide then Reposition(Angle()) end
end

-- Built at PLAYER_LOGIN, after the store's ADDON_LOADED init.
Events.On("PLAYER_LOGIN", "adminimap", function()
    Build()
    NS.MinimapButtonRefresh()
end)
