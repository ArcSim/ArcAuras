-- Arc UI Forever is now Arc Auras. This stand-in draws nothing: it keeps the old
-- saved setup loaded so Arc Auras can copy it, and points the player there.
local ADDON, NS = ...

local LINK = "https://www.curseforge.com/wow/addons/arc-auras"
local ICON = "Interface\\AddOns\\ArcUI\\ArcAuras_Icon"
local CYAN = { 0.25, 0.79, 0.95 }
local DEEP = { 0.10, 0.44, 0.62 }
local LINE = { 0.16, 0.24, 0.33 }

local notice

local function Skin(f, r, g, b, er, eg, eb)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(r, g, b, 1)
    f:SetBackdropBorderColor(er, eg, eb, 1)
end

local function BuildNotice()
    local f = CreateFrame("Frame", "ArcUIForeverBridgeNotice", UIParent, "BackdropTemplate")
    f:SetSize(460, 204)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    Skin(f, 0.06, 0.09, 0.15, CYAN[1], CYAN[2], CYAN[3])
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- Escape closes it like any other window.
    tinsert(UISpecialFrames, "ArcUIForeverBridgeNotice")

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture(ICON)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    title:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
    title:SetText("Arc UI Forever is now Arc Auras")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    body:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    body:SetJustifyH("LEFT")
    body:SetText("Same addon, new name. Install Arc Auras from CurseForge or Wago, and your setup moves over by itself the first time it loads. Until then, it is kept safe here.")

    local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    box:SetSize(320, 24)
    box:SetPoint("BOTTOMLEFT", 18, 50)
    Skin(box, 0.04, 0.06, 0.10, LINE[1], LINE[2], LINE[3])
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetText(LINK)
    box:SetCursorPosition(0)
    -- The box only holds the link for copying, so typing can't change it.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(LINK)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    hint:SetText("Click the link, then press Ctrl+C to copy it.")

    local close = CreateFrame("Button", nil, f, "BackdropTemplate")
    close:SetSize(96, 24)
    close:SetPoint("BOTTOMRIGHT", -18, 18)
    Skin(close, 0.10, 0.15, 0.22, DEEP[1], DEEP[2], DEEP[3])
    local label = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(CLOSE)
    close:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(CYAN[1], CYAN[2], CYAN[3], 1) end)
    close:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(DEEP[1], DEEP[2], DEEP[3], 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    return f
end

local function ShowNotice()
    notice = notice or BuildNotice()
    notice:Show()
end

local function OldSetting(key)
    local db = _G.ArcUIv2DB
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return db.settings[key]
end

-- The old minimap button stays where the player put it, and now opens the notice.
local function BuildMinimapButton()
    if not Minimap or OldSetting("minimapHide") == true then return end
    local b = CreateFrame("Button", "ArcUIForeverBridgeMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    if icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local angle = OldSetting("minimapAngle")
    local rad = math.rad(type(angle) == "number" and angle or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff3fc9f2Arc|r UI Forever is now Arc Auras")
        GameTooltip:AddLine("Click: where to get it", 0.8, 0.86, 0.94)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", ShowNotice)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- With Arc Auras installed the move is done, so stay out of the way.
    if C_AddOns.IsAddOnLoaded("ArcAuras") then return end
    BuildMinimapButton()
    -- The old commands open the notice, so typing them still leads somewhere.
    SLASH_ARCUIFOREVERBRIDGE1 = "/arcui"
    SLASH_ARCUIFOREVERBRIDGE2 = "/aui"
    SLASH_ARCUIFOREVERBRIDGE3 = "/arcui2"
    SLASH_ARCUIFOREVERBRIDGE4 = "/aui2"
    SlashCmdList.ARCUIFOREVERBRIDGE = ShowNotice
    -- Entering the world closes every Escape-closable window, so open it after.
    C_Timer.After(1, ShowNotice)
end)
