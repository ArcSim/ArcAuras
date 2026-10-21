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

-- The quarters a minimap addon's shape keeps round (GetMinimapShape), in the
-- order right-bottom, left-bottom, right-top, left-top; on a square quarter
-- the button runs along the edge instead of a circle.
local ROUND_QUARTERS = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function Reposition(angle)
    local rad = math.rad(angle)
    local c, s = math.cos(rad), math.sin(rad)
    local w = (Minimap_:GetWidth() or 140) / 2 + 5
    local h = (Minimap_:GetHeight() or (w * 2 - 10)) / 2 + 5
    local shape = GetMinimapShape and GetMinimapShape()
    local quarters = ROUND_QUARTERS[type(shape) == "string" and shape or "ROUND"] or ROUND_QUARTERS.ROUND
    local q = (c < 0 and 2 or 1) + (s > 0 and 2 or 0)
    local x, y
    if quarters[q] then
        x, y = c * w, s * h
    else
        -- where the ray from the centre meets the square's edge
        local t = math.min(c ~= 0 and w / math.abs(c) or math.huge, s ~= 0 and h / math.abs(s) or math.huge)
        x, y = c * t, s * t
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap_, "CENTER", x, y)
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
        local Tr = (NS.AT and NS.AT.Tr) or function(s) return s end
        GameTooltip:AddLine("|cff3fc9f2Arc|r Auras")
        GameTooltip:AddLine(Tr("Left-click: options"), 0.8, 0.86, 0.94)
        GameTooltip:AddLine(Tr("Right-click: move layouts"), 0.8, 0.86, 0.94)
        GameTooltip:AddLine(Tr("Drag: move this button"), 0.55, 0.6, 0.68)
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
