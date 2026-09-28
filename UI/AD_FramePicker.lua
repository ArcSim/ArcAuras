-- AD_FramePicker: Pick Frame for the anchor rows: hover any frame on screen, click it, and its name fills Frame name.
-- Owns pick mode (a click catcher, a readout on the cursor, a box on the frame) and the common-frames list;
-- Options.AnchorPickRows calls FramePickRows. Pick mode runs out of combat only and offers what Anchor.FrameProblem passes.
local ADDON, NS = ...

local FP = {}
NS.FramePicker = FP

-- Global name prefixes of Arc Auras' own windows and layout containers.
FP.OWN_PREFIX = { "ArcUIv2", "ArcAuras" }
-- Seconds between two looks at what is under the cursor.
FP.RESOLVE_EVERY = 0.05
-- How far up a parent chain a pick looks before giving up.
FP.MAX_DEPTH = 40

-- Frames players anchor to, each checked in the Forever UI source; a frame the
-- running client lacks is left out of the list.
FP.COMMON = {
    { name = "PlayerFrame", text = "Player frame" },
    { name = "TargetFrame", text = "Target frame" },
    { name = "TargetFrameToT", text = "Target of target" },
    { name = "FocusFrame", text = "Focus frame" },
    { name = "PetFrame", text = "Pet frame" },
    { name = "PartyFrame", text = "Party frames" },
    { name = "PlayerCastingBarFrame", text = "Player cast bar" },
    { name = "TargetFrameSpellBar", text = "Target cast bar" },
    { name = "MainActionBar", text = "Action bar 1" },
    { name = "MultiBarBottomLeft", text = "Action bar 2" },
    { name = "MultiBarBottomRight", text = "Action bar 3" },
    { name = "MultiBarRight", text = "Action bar 4" },
    { name = "MultiBarLeft", text = "Action bar 5" },
    { name = "StanceBar", text = "Stance bar" },
    { name = "PetActionBar", text = "Pet action bar" },
    { name = "MinimapCluster", text = "Minimap" },
    { name = "BuffFrame", text = "Buffs" },
    { name = "DebuffFrame", text = "Debuffs" },
    { name = "ChatFrame1", text = "Chat window" },
}

-- What the readout says when nothing under the cursor can be picked.
FP.WHY_TEXT = {
    ownItem = "An Arc Auras item: pick it in Anchor to",
    own = "Arc Auras' own window: not offered",
    plate = "A nameplate: not offered",
    protected = "Protected by the game: not offered",
    none = "No named frame here",
}
FP.HINT = "Click to pick   Right-click or Esc: cancel"

function FP.IsCommon(name)
    for _, c in ipairs(FP.COMMON) do
        if c.name == name then return true end
    end
    return false
end

-- The Common frames dropdown: a placeholder, then the frames this client has.
function FP.CommonItems()
    local items = { { value = "", text = "Choose a frame" } }
    for _, c in ipairs(FP.COMMON) do
        local f = _G[c.name]
        if type(f) == "table" and f.GetObjectType then
            items[#items + 1] = { value = c.name, text = c.text }
        end
    end
    return items
end

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- "ownItem" for a layout container (its groups, bars and icons are unnamed
-- children), "own" for any other Arc Auras frame, else nil.
function FP.OwnKind(name)
    if type(name) ~= "string" then return nil end
    for _, p in ipairs(FP.OWN_PREFIX) do
        if name:sub(1, #p) == p then
            return name:match("^ArcUIv2Layout%d+$") and "ownItem" or "own"
        end
    end
    return nil
end

-- From one frame under the cursor up its parents: the first frame with a
-- global name that anchoring can use, as name, frame; else nil, nil, why the
-- walk stopped. A forbidden frame answers nothing but IsForbidden, so that is
-- asked first, and every other read can be secret.
function FP.Walk(f)
    local A = NS.Anchor
    local depth = 0
    while f ~= nil and depth < FP.MAX_DEPTH do
        depth = depth + 1
        if f == UIParent or f == WorldFrame then return nil end
        if f.IsForbidden then
            local fb = f:IsForbidden()
            if Secret(fb) or fb then return nil, nil, "protected" end
        end
        local name = f.GetName and f:GetName()
        if Secret(name) then name = nil end
        local own = FP.OwnKind(name)
        if own then return nil, nil, own end
        if type(name) == "string" and name ~= "" and _G[name] == f then
            local why = A and A.FrameProblem(f)
            if why == nil then return name, f end
            if why == "plate" or why == "forbidden" then
                return nil, nil, (why == "plate") and "plate" or "protected"
            end
            -- secret right now: a parent may still be fine
        end
        local p = f.GetParent and f:GetParent()
        if Secret(p) then return nil, nil, "protected" end
        f = p
    end
    return nil
end

-- The frames under the cursor, top first (the catcher lets motion through).
function FP.Foci()
    local foci
    if GetMouseFoci then
        foci = GetMouseFoci()
    elseif GetMouseFocus then
        foci = { GetMouseFocus() }
    end
    if type(foci) ~= "table" or Secret(foci) then return {} end
    return foci
end

-- The first pickable frame under the cursor: name, frame, or nil, nil, why.
-- The catcher is always the top one; being unnamed under UIParent, its walk
-- yields nothing.
function FP.Resolve(foci)
    local why
    for _, f in ipairs(foci or {}) do
        local name, frame, w = FP.Walk(f)
        if name then return name, frame end
        why = why or w
    end
    return nil, nil, why
end

function FP.IsActive()
    return FP.active == true
end

-- The picker's frames are unnamed UIParent children, so a walk never offers them.
local function Catcher()
    local c = FP.catcher
    if c then return c end
    c = CreateFrame("Frame", nil, UIParent)
    c:SetFrameStrata("TOOLTIP")
    c:SetFrameLevel(9990)
    c:SetAllPoints(UIParent)
    c:EnableMouse(true)
    -- Motion passes through, so GetMouseFoci still names the frames below;
    -- clicks stop here, so picking never clicks the frame.
    if c.SetPropagateMouseMotion then c:SetPropagateMouseMotion(true) end
    c:EnableKeyboard(true)
    c:SetScript("OnMouseUp", function(_, button) FP.Click(button) end)
    c:SetScript("OnKeyDown", function(self, key)
        -- Other keys go on to the game; Esc ends pick mode and nothing else.
        -- The propagation switch is restricted in combat, which ends pick mode.
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            FP.Stop()
        end
    end)
    c:SetScript("OnHide", function() FP.Stop() end)
    c:Hide()
    FP.catcher = c
    return c
end

local function Readout()
    local r = FP.readout
    if r then return r end
    local AT = NS.AT
    local COL = AT.COL
    r = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    r:SetFrameStrata("TOOLTIP")
    r:SetFrameLevel(9995)
    r:SetClampedToScreen(true)
    r:SetSize(200, 40)
    AT.Skin(r, COL.panel, COL.arc)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(STANDARD_TEXT_FONT, 12, "")
    r.name:SetPoint("TOPLEFT", 8, -7)
    r.name:SetJustifyH("LEFT")
    r.hint = r:CreateFontString(nil, "OVERLAY")
    r.hint:SetFont(STANDARD_TEXT_FONT, 10, "")
    r.hint:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.hint:SetJustifyH("LEFT")
    r.hint:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    r.hint:SetText(FP.HINT)
    r:Hide()
    FP.readout = r
    return r
end

local function Box()
    local b = FP.box
    if b then return b end
    local AT = NS.AT
    local COL = AT.COL
    b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    b:SetFrameStrata("TOOLTIP")
    b:SetFrameLevel(9993)
    AT.Skin(b, { COL.arc[1], COL.arc[2], COL.arc[3], 0.12 }, COL.arc)
    b:Hide()
    FP.box = b
    return b
end

-- Our own font strings' widths only: the readout fits its longer line.
local function TextW(fs)
    local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    if type(w) ~= "number" or w <= 0 then w = #(fs:GetText() or "") * 6 end
    return w
end

function FP.PlaceReadout(x, y)
    local r = FP.readout
    if not (r and x and y) then return end
    local s = UIParent:GetEffectiveScale()
    if type(s) ~= "number" or s <= 0 then s = 1 end
    r:ClearAllPoints()
    r:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 16, y / s + 14)
end

-- Looks under the cursor, then shows the name (or why not) and boxes the frame.
function FP.Refresh()
    local name, frame, why = FP.Resolve(FP.Foci())
    FP.name, FP.frame = name, frame
    local r, b = FP.readout, FP.box
    if r then
        local COL = NS.AT.COL
        if name then
            r.name:SetText(name)
            r.name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        else
            r.name:SetText(FP.WHY_TEXT[why or "none"] or FP.WHY_TEXT.none)
            r.name:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        end
        r:SetWidth(math.ceil(math.max(TextW(r.name), TextW(r.hint))) + 18)
    end
    if b then
        b:ClearAllPoints()
        if frame then
            b:SetAllPoints(frame)
            b:Show()
        else
            b:Hide()
        end
    end
end

function FP.Tick(_, elapsed)
    local x, y = GetCursorPosition()
    if x ~= FP.lastX or y ~= FP.lastY then
        FP.lastX, FP.lastY = x, y
        FP.PlaceReadout(x, y)
    end
    FP.acc = (FP.acc or 0) + (elapsed or 0)
    if FP.acc >= FP.RESOLVE_EVERY then
        FP.acc = 0
        FP.Refresh()
    end
end

-- Left-click takes the name under the cursor (nothing pickable: keep looking);
-- right-click cancels.
function FP.Click(button)
    if button == "RightButton" then
        FP.Stop()
        return
    end
    if button ~= "LeftButton" or not FP.active then return end
    FP.Refresh()
    local name, onPick = FP.name, FP.onPick
    if not name then return end
    FP.Stop()
    if onPick then onPick(name) end
end

-- Starts pick mode; onPick(name) runs on a pick. Refused in combat: a screen
-- covering click catcher would take the player's clicks.
function FP.Start(onPick)
    if InCombatLockdown() then return false end
    FP.Stop()
    local c = Catcher()
    Readout()
    Box()
    FP.onPick = onPick
    FP.active = true
    FP.acc, FP.lastX, FP.lastY = 0, nil, nil
    if c.SetPropagateKeyboardInput then c:SetPropagateKeyboardInput(true) end
    c:SetScript("OnUpdate", FP.Tick)
    c:Show()
    FP.readout:Show()
    FP.PlaceReadout(GetCursorPosition())
    FP.Refresh()
    if NS.Events then NS.Events.On("PLAYER_REGEN_DISABLED", "adpick", function() FP.Stop() end) end
    return true
end

-- Ends pick mode: no per-frame work, no event and no frame of it left showing.
function FP.Stop()
    if not FP.active then return end
    FP.active = false
    FP.onPick, FP.name, FP.frame = nil, nil, nil
    if NS.Events then NS.Events.Off("PLAYER_REGEN_DISABLED", "adpick") end
    local c = FP.catcher
    if c then
        c:SetScript("OnUpdate", nil)
        c:Hide()
    end
    if FP.readout then FP.readout:Hide() end
    if FP.box then
        FP.box:ClearAllPoints()
        FP.box:Hide()
    end
end

local Options = NS.Options
if not Options then return end

-- Two rows under Frame name: Common frames, then the Pick Frame button. vis:
-- when they show (a Named frame pick). owner: the window the dropdown opens on.
function Options.FramePickRows(pg, ctx, vis, owner)
    local AT, Store = NS.AT, NS.Store
    local function SetName(r, name)
        if r and type(name) == "string" and name ~= "" then
            Store.SetOverride(r, "anchor", "anchorTargetFrame", name)
        end
    end
    AT.RowDropdown(pg, owner, "Common frames",
        function()
            local r = ctx()
            local n = r and Store.Resolve(r, "anchor", "anchorTargetFrame") or ""
            return FP.IsCommon(n) and n or ""
        end,
        function(v) SetName(ctx(), v) end,
        FP.CommonItems, vis,
        function() AT.LayoutPage(pg) end)
    local row
    row = AT.RowButton(pg, "Pick Frame", function()
        local r = ctx()
        if not r then return end
        local id = r.id
        local ok = FP.Start(function(name)
            SetName(Store.Get(id), name)
            AT.LayoutPage(pg)
        end)
        if not ok then
            row.button.fs:SetText("Not in combat")
            C_Timer.After(2, function() row.button.fs:SetText("Pick Frame") end)
        end
    end, vis, 110, "Pick it on screen")
    AT.Tooltip(row.button, "Pick Frame",
        "Hover any frame on screen and left-click it to use its name. Right-click or Esc cancels.")
    -- pick mode ends with the page that started it
    pg:HookScript("OnHide", function() FP.Stop() end)
end
