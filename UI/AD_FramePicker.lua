-- AD_FramePicker: Pick Frame for the anchor rows: hover any frame on screen, a game frame or an Arc Auras item, and click it to anchor to it.
-- Owns pick mode (a click catcher, a readout on the cursor, a box on the frame), the common-frames list and a spell pin's Spell row;
-- Options.AnchorPickRows calls FramePickRows. Pick mode runs out of combat only and offers what Anchor.FrameProblem
-- passes, the Arc Auras items Anchor.PickFrames maps for the record being edited, and for a bar the action buttons and
-- Cooldown Manager icons that hold a spell (Core\AD_SpellAnchor.lua PickMap).
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
    self = "This item itself: not offered",
    loop = "Anchored to this one: it would loop",
    ownItem = "An Arc Auras item: pick it in Anchor to",
    own = "Arc Auras' own window: not offered",
    plate = "A nameplate: not offered",
    protected = "Protected by the game: not offered",
    none = "No named frame here",
}
FP.HINT = "Click to pick   Right-click or Esc: cancel"
-- an action button: its spell wherever it moves, or this one button
FP.BUTTON_HINT = "Click: follow the spell   Shift-click: this button   Esc: cancel"
FP.ICON_HINT = "Click: follow this icon   Right-click or Esc: cancel"

-- Typed words to the spell ids a spell pin keeps: numbers as they are, a link
-- or a spell's name through the spell parser. nil when nothing reads as a spell.
function FP.SpellSpec(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "" end
    local ids, seen = {}, {}
    if text:find("^[%d%s,]+$") then
        for n in text:gmatch("%d+") do
            local v = tonumber(n)
            if v and v > 0 and not seen[v] then
                seen[v] = true
                ids[#ids + 1] = v
            end
        end
    else
        local CO = NS.Options and NS.Options.Custom
        local id = CO and CO.ParseSpell and CO.ParseSpell(text)
        if id then ids[1] = id end
    end
    if #ids == 0 then return nil end
    return table.concat(ids, ", ")
end

-- A pin spec's cooldown ID ("cd:12821" -> 12821), or nil.
function FP.CooldownID(spec)
    if type(spec) ~= "string" then return nil end
    return tonumber(spec:match("^%s*[Cc][Dd]:%s*(%d+)%s*$") or "")
end

-- Typed digits to a cooldown ID spec; "" clears; nil when nothing reads.
function FP.CooldownSpec(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "" end
    local n = tonumber(text:match("^[Cc]?[Dd]?:?%s*(%d+)$") or "")
    if not n or n <= 0 then return nil end
    return "cd:" .. n
end

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
-- global name that anchoring can use, as name, frame; the first Arc Auras
-- item in `items` (Anchor.PickFrames) or action button / Cooldown Manager icon
-- in `spells`, as nil, frame, nil, item; else nil, nil, why the walk stopped.
-- A forbidden frame answers nothing but IsForbidden, so that is asked first,
-- and every other read can be secret.
function FP.Walk(f, items, spells)
    local A = NS.Anchor
    local depth = 0
    while f ~= nil and depth < FP.MAX_DEPTH do
        depth = depth + 1
        if f == UIParent or f == WorldFrame then return nil end
        if f.IsForbidden then
            local fb = f:IsForbidden()
            if Secret(fb) or fb then return nil, nil, "protected" end
        end
        local item = items and items[f]
        if item then
            if item.value then return nil, f, nil, item end
            return nil, nil, item.why
        end
        local sp = spells and spells[f]
        if sp then return nil, f, nil, sp end
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

-- The first pickable frame under the cursor: name, frame (a game frame), nil,
-- frame, nil, item (an Arc Auras item), or nil, nil, why. The catcher is
-- always the top one; being unnamed under UIParent, its walk yields nothing.
function FP.Resolve(foci, items, spells)
    local why
    for _, f in ipairs(foci or {}) do
        local name, frame, w, item = FP.Walk(f, items, spells)
        if name or item then return name, frame, nil, item end
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
    r.name:SetFont(NS.AT.FONT, 12, "")
    r.name:SetPoint("TOPLEFT", 8, -7)
    r.name:SetJustifyH("LEFT")
    r.hint = r:CreateFontString(nil, "OVERLAY")
    r.hint:SetFont(NS.AT.FONT, 10, "")
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
    local name, frame, why, item = FP.Resolve(FP.Foci(), FP.items, FP.spells)
    FP.name, FP.frame, FP.item = name, frame, item
    local r, b = FP.readout, FP.box
    if r then
        local COL = NS.AT.COL
        if name or item then
            r.name:SetText(name or item.text)
            r.name:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
        else
            r.name:SetText(FP.WHY_TEXT[why or "none"] or FP.WHY_TEXT.none)
            r.name:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
        end
        -- a spell pin says what a click and a Shift-click take
        local hint = FP.HINT
        if item and item.spec then
            hint = (item.value == "action" and item.frameName) and FP.BUTTON_HINT
                or (item.value == "cdm" and FP.ICON_HINT) or FP.HINT
        end
        r.hint:SetText(hint)
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

-- Left-click takes what is under the cursor (nothing pickable: keep looking);
-- right-click cancels. Shift on an action button takes that button by its
-- name instead of the spell it holds.
function FP.Click(button)
    if button == "RightButton" then
        FP.Stop()
        return
    end
    if button ~= "LeftButton" or not FP.active then return end
    FP.Refresh()
    local name, item, onPick = FP.name, FP.item, FP.onPick
    if not (name or item) then return end
    if item and item.spec and item.frameName and IsShiftKeyDown and IsShiftKeyDown() then
        name, item = item.frameName, nil
    end
    FP.Stop()
    if onPick then onPick(name, item) end
end

-- The action buttons and Cooldown Manager icons a pick may offer rec: the
-- spell kinds its family allows, each as a pick ({ value, spec, text,
-- frameName }); nil when it allows none.
function FP.SpellPicks(rec, all)
    local A, SA = NS.Anchor, NS.SpellAnchor
    if not (SA and SA.PickMap) then return nil end
    local action, cdm = all == true, all == true
    if not all then
        if not (rec and A) then return nil end
        action, cdm = A.Allows(rec, "action"), A.Allows(rec, "cdm")
    end
    if not (action or cdm) then return nil end
    local out = {}
    for f, it in pairs(SA.PickMap()) do
        if (it.kind == "action" and action) or (it.kind == "cdm" and cdm) then
            local spec = it.cid and ("cd:" .. it.cid) or tostring(it.id)
            out[f] = { value = it.kind, spec = spec, text = it.text, frameName = it.frameName }
        end
    end
    return out
end

-- Starts pick mode; onPick(name) runs on a game frame's pick, onPick(nil,
-- item) on an Arc Auras item's (item.value is an Anchor.PickSet value). rec:
-- the record being anchored, whose legal targets are offered; nil offers game
-- frames only. Refused in combat: a screen covering click catcher would take
-- the player's clicks.
function FP.Start(onPick, rec, textPick)
    if InCombatLockdown() then return false end
    FP.Stop()
    local c = Catcher()
    Readout()
    Box()
    FP.onPick = onPick
    -- the items are mapped once: pick mode is short, and a rebuild while it
    -- runs only leaves a stale frame that is no longer under the cursor. A
    -- text's pick offers game frames, buttons and icons, never Arc Auras items.
    FP.items = (rec and not textPick and NS.Anchor and NS.Anchor.PickFrames) and NS.Anchor.PickFrames(rec) or nil
    FP.spells = FP.SpellPicks(rec, textPick)
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
    FP.onPick, FP.name, FP.frame, FP.item, FP.items, FP.spells = nil, nil, nil, nil, nil, nil
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
-- when Common frames shows (a Named frame pick); pickVis: when Pick Frame
-- shows (every anchor pick; vis when nil). owner: the window the dropdown
-- opens on. A pick of a game frame makes the anchor a Named frame with that
-- name; a pick of an Arc Auras item anchors to that item, as Anchor to would.
function Options.FramePickRows(pg, ctx, vis, owner, pickVis)
    local AT, Store = NS.AT, NS.Store
    local function SetName(r, name)
        if r and type(name) == "string" and name ~= "" then
            Store.SetOverride(r, "anchor", "anchorTargetFrame", name)
        end
    end
    -- a spell pin (an action bar button or a Cooldown Manager icon): its
    -- spell, kept as ids in the anchor's frame field
    local spellVis = function()
        return (pickVis or vis)() and NS.Anchor ~= nil and NS.Anchor.IsSpellPick(ctx())
    end
    AT.RowInput(pg, "Anchor spell",
        function()
            local r = ctx()
            local v = r and (Store.Resolve(r, "anchor", "anchorTargetFrame") or "") or ""
            return FP.CooldownID(v) and "" or v
        end,
        function(v)
            local r, spec = ctx(), FP.SpellSpec(v)
            if r and spec then Store.SetOverride(r, "anchor", "anchorTargetFrame", spec) end
        end,
        spellVis,
        "The spell whose button or icon it rides: a spell ID, a link or the name of a spell you know. Several ranks' IDs may be listed. Enter applies it.",
        "e.g. 17364")
    -- a Cooldown Manager icon by its exact entry: a spell's cooldown icon and
    -- its buff icon share the spell, never the cooldown ID
    AT.RowInput(pg, "Cooldown ID",
        function()
            local r = ctx()
            return tostring(FP.CooldownID(r and Store.Resolve(r, "anchor", "anchorTargetFrame")) or "")
        end,
        function(v)
            local r, spec = ctx(), FP.CooldownSpec(v)
            if r and spec then Store.SetOverride(r, "anchor", "anchorTargetFrame", spec) end
        end,
        function()
            local r = ctx()
            return spellVis() and r ~= nil and Store.Resolve(r, "anchor", "anchorTargetKind") == "cdm"
        end,
        "The icon's cooldown ID, its exact entry in the Cooldown Manager: Pick Frame on an icon fills it. Empty uses the spell above.",
        "e.g. 12821")
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
        local ok = FP.Start(function(name, item)
            local A, rec = NS.Anchor, Store.Get(id)
            if not (A and rec) then return end
            if item then
                A.PickSet(rec, item.value)
                if item.spec then Store.SetOverride(rec, "anchor", "anchorTargetFrame", item.spec) end
            else
                A.PickSet(rec, "frame")
                SetName(rec, name)
            end
            AT.LayoutPage(pg)
        end, r)
        if not ok then
            row.button.fs:SetText("Not in combat")
            C_Timer.After(2, function() row.button.fs:SetText("Pick Frame") end)
        end
    end, pickVis or vis, 110, "Pick it on screen")
    AT.Tooltip(row.button, "Pick Frame",
        "Hover a game frame, one of your Arc Auras items, or for a bar an action button or Cooldown Manager icon, and left-click it. A button is followed by its spell, an icon by its cooldown ID; Shift-click keeps that one button. Right-click or Esc cancels.")
    -- pick mode ends with the page that started it
    pg:HookScript("OnHide", function() FP.Stop() end)
end
