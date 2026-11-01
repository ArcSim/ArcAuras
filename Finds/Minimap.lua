local _, ns = ...
if ns.shareOnly then return end

local T = ns.Theme
local U = T.U

-- the map button: opens the window, and a round red "!" says an update added datamined items (the tooltip says
-- how many)
local button, badge

local function Place()
    local angle = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + U(10)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function UpdateBadge()
    if not button then return end
    local n = ns.UI and ns.UI.NewDatamined() or 0
    badge:SetShown(n > 0)
end

-- a texture cut round by the game's circle mask
local function Round(parent, sub, inset, hex)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    t:SetColorTexture(T.RGB(hex))
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t
end

local function Build()
    button = CreateFrame("Button", "ForeverItemFinderMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.MEDIA .. "FIF_Minimap")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    -- cut round, so no corner of the art shows past the button's ring
    local iconMask = button:CreateMaskTexture()
    iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    iconMask:SetAllPoints(icon)
    icon:AddMaskTexture(iconMask)
    button.icon, button.iconMask = icon, iconMask
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    badge = CreateFrame("Frame", nil, button)
    badge:SetSize(U(14), U(14))
    badge:SetPoint("CENTER", button, "TOPRIGHT", -U(5), -U(5))
    badge:SetFrameLevel(button:GetFrameLevel() + 3)
    badge.ring = Round(badge, 1, 0, T.C.black)
    badge.fill = Round(badge, 2, 1, T.C.badge)
    badge.mark = T.Text(badge, 11, "FFFFFF", "OVERLAY")
    badge.mark:SetPoint("CENTER", 0, 0)
    badge.mark:SetText("!")
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then ns.UI.Show("options") else ns.UI.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg((math.atan2 or math.atan)(cy / scale - my, cx / scale - mx))
            Place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever Item Finder", 1, 0.82, 0)
        local n = ns.UI.NewDatamined()
        if n > 0 then
            GameTooltip:AddLine(n .. " new items in the database", 1, 1, 1)
            if ns.db.minedAt then GameTooltip:AddLine("Added " .. date("%b %d", ns.db.minedAt), 0.62, 0.62, 0.62) end
        else
            GameTooltip:AddLine(ns.Finds.Count() .. " finds", 1, 1, 1)
        end
        local new = ns.UI.FeedNew()
        if new > 0 then GameTooltip:AddLine(new .. " new in the Live Feed", 1, 1, 1) end
        GameTooltip:AddLine("Click: open", 0.12, 1, 0)
        GameTooltip:AddLine("Right-click: options", 0.12, 1, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
    UpdateBadge()
end

ns.Listen("Login", function()
    if not Minimap then return end
    Build()
end)
ns.Listen("DatabaseSeen", UpdateBadge)
ns.Listen("FindsChanged", UpdateBadge)
