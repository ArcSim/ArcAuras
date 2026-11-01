local _, ns = ...
if ns.shareOnly then return end

local T = ns.Theme
local D = ns.Data
local C = T.C
local U = T.U

local Popup = {}
ns.Popup = Popup

local GAP = 5               -- seconds between two pop-ups
local frame
local current               -- the find on screen
local waiting = 0           -- finds that arrived while one was showing: they stay in the feed
local lastShown = -100
local lastQ = 0             -- the quality of the last find shown
local hideAt
local held                  -- a find held back during combat
local moving = false

local function S() return ns.settings end

-- which finds may pop up: the Live Feed's filter while pop-ups follow it, else their own copy; both start at
-- discoveries only (D.IsDiscovery)
function Popup.Passes(e)
    local s = S()
    if not e or e.pend then return false end
    if not s.popOn then return false end
    local _, classFile = UnitClass("player")
    return D.FindPasses(s.popFollow and s.findFilter or s.popOwn, e, UnitLevel("player") or 1, classFile)
end

-- the sounds a pop-up can play: game sounds, so every client has them
Popup.SOUNDS = { { "loot", "Epic loot", 31578 }, { "legendary", "Legendary loot", 63971 }, { "raid", "Raid warning", 8959 },
    { "ready", "Ready check", 8960 }, { "whisper", "Boss whisper", 37666 }, { "quest", "Quest complete", 878 },
    { "alarm", "Alarm clock", 12889 }, { "tell", "Whisper", 3081 }, { "toast", "Friend online", 18019 } }
function Popup.PlaySound(key)
    local id = Popup.SOUNDS[1][3]
    for _, snd in ipairs(Popup.SOUNDS) do if snd[1] == key then id = snd[3] end end
    PlaySound(id, "Master")
end

-- the stat card: type line, stats, effects
-- an effect that is really a stat joins the stat line; the order matters (the first match wins)
local SHORT = {
    { "damage and healing done by magical spells and effects by up to (%d+)", "+%s Spell Power" },
    { "healing done by [%a ]-spells and effects by up to (%d+)", "+%s Healing" },
    { "damage done by (%a+) spells and effects by up to (%d+)", "+%2$s %1$s Damage" },
    { "critical strike with spells by ([%d%.]+)%%", "+%s%% Spell Crit" },
    { "chance to get a critical strike by ([%d%.]+)%%", "+%s%% Crit" },
    { "chance to hit with spells by ([%d%.]+)%%", "+%s%% Spell Hit" },
    { "chance to hit by ([%d%.]+)%%", "+%s%% Hit" },
    { "chance to dodge an attack by ([%d%.]+)%%", "+%s%% Dodge" },
    { "chance to parry an attack by ([%d%.]+)%%", "+%s%% Parry" },
    { "chance to block attacks with a shield by ([%d%.]+)%%", "+%s%% Block" },
    { "block value of your shield by (%d+)", "+%s Block Value" },
    { "[Rr]anged [Aa]ttack [Pp]ower by (%d+)", "+%s Ranged Attack Power" },
    { "^%+(%d+) [Rr]anged [Aa]ttack [Pp]ower", "+%s Ranged Attack Power" },
    { "[Aa]ttack [Pp]ower by (%d+)", "+%s Attack Power" },
    { "^%+(%d+) [Aa]ttack [Pp]ower", "+%s Attack Power" },
    { "attack speed and casting speed by ([%d%.]+)%%", "+%s%% Haste" },
    { "[Rr]estores (%d+) mana per 5 sec", "+%s Mana per 5 sec" },
    { "[Rr]estores (%d+) health per 5 sec", "+%s Health per 5 sec" },
    { "magical resistances of your spell targets by (%d+)", "+%s Spell Penetration" },
    { "^Increased Defense %+(%d+)", "+%s Defense" },
    { "^Increased ([%a%- ]+) %+(%d+)%.?$", "+%2$s %1$s" },
}
-- a Use or proc effect, shortened: "Increases attack power by 260 for 20 sec." -> "+260 Attack Power, 20 sec"
local USE = {
    { "^Increases your (%a[%a ]-) by (%d+) for (%d+) sec", "+%2$s %1$s, %3$s sec" },
    { "^Increases (%a[%a ]-) by (%d+) for (%d+) sec", "+%2$s %1$s, %3$s sec" },
    { "^Increases (%a[%a ]-) by up to (%d+) for (%d+) sec", "+%2$s %1$s, %3$s sec" },
}
local MAX_EFFECTS = 3
local LINE_CHARS = 64

local function TooltipLines(id)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
    return data and data.lines or {}
end

-- Lua patterns have no positional captures: fill "%1$s" style targets by hand
local function FillCaps(fmt, ...)
    local caps = { ... }
    local out = fmt:gsub("%%(%d)%$s", function(i) return caps[tonumber(i)] or "" end)
    if out:find("%%s") then out = out:format(...) end
    return (out:gsub("%%%%", "%%"))
end

local function Match(list, text)
    for _, p in ipairs(list) do
        local caps = { text:match(p[1]) }
        if caps[1] then
            -- stat names read as the tooltip's stat lines do: "attack power" -> "Attack Power"
            for i, c in ipairs(caps) do
                if not tonumber(c) then caps[i] = c:gsub("(%a)(%a*)", function(first, rest) return first:upper() .. rest end) end
            end
            return FillCaps(p[2], caps[1], caps[2], caps[3]), true
        end
    end
end

local function Cut(text)
    if #text <= LINE_CHARS then return text end
    return text:sub(1, LINE_CHARS - 3):gsub("%s+%S*$", "") .. "..."
end

-- an effect line of the tooltip: its trigger (equip / use / proc) from the line type, or from the game's words
local TYPES = Enum and Enum.TooltipDataLineType or {}
local function Trigger(line, text)
    if line.type ~= nil and line.type == TYPES.ItemSpellTriggerOnEquip then return "equip" end
    if line.type ~= nil and line.type == TYPES.ItemSpellTriggerOnUse then return "use" end
    if line.type ~= nil and line.type == TYPES.ItemSpellTriggerOnProc then return "proc" end
    local function Word(g, fallback) return type(g) == "string" and g ~= "" and g or fallback end
    local words = { equip = Word(ITEM_SPELL_TRIGGER_ONEQUIP, "Equip:"), use = Word(ITEM_SPELL_TRIGGER_ONUSE, "Use:"),
        proc = Word(ITEM_SPELL_TRIGGER_ONPROC, "Chance on hit:") }
    for kind, w in pairs(words) do
        if text:sub(1, #w) == w then return kind end
    end
end

local PREFIX = { equip = "Equip: ", use = "Use: ", proc = "Proc: " }

-- the effects an item carries, as stats ("+1% Crit") or short lines ("Use: +260 Attack Power, 20 sec, 2 min CD")
function Popup.Effects(id)
    local stats, lines = {}, {}
    for _, line in ipairs(TooltipLines(id)) do
        local text = line.leftText
        if type(text) == "string" and not ns.Secret(text) then
            local trigger = Trigger(line, text)
            if trigger then
                local body = text:gsub("^[^:]+:%s*", "")
                local cd = body:match("%((%d+ %a+) [Cc]ooldown%)")
                body = body:gsub("%s*%([^%)]*[Cc]ooldown%)", ""):gsub("%s+$", "")
                local short = trigger == "equip" and Match(SHORT, body)
                if short then
                    stats[#stats + 1] = short
                else
                    local use = Match(USE, body) or body:gsub("%.$", "")
                    if cd then use = use .. ", " .. cd:lower() .. " CD" end
                    lines[#lines + 1] = Cut(PREFIX[trigger] .. use)
                end
            end
        end
    end
    return stats, lines
end

function Popup.CardLines(e)
    local parts = {}
    local kind = D.ItemKind(e.cl, e.sc, e.iv)
    if kind ~= "" then parts[#parts + 1] = kind end
    if e.il then parts[#parts + 1] = (#parts == 0 and "Item level " or "item level ") .. e.il end
    local only = D.OnlyClass(e.ac)
    if only then parts[#parts + 1] = only end
    local typeLine = table.concat(parts, ", ")
    local stats = {}
    local _, link = C_Item.GetItemInfo(e.id)
    local raw = link and C_Item.GetItemStats and C_Item.GetItemStats(link)
    if type(raw) == "table" then
        local list = {}
        for k, v in pairs(raw) do
            local name = _G[k]
            -- bonus stats only: the game lists a weapon's damage per second here too, as a long decimal
            if type(name) == "string" and type(v) == "number" and not k:find("ARMOR") and not k:find("DAMAGE_PER_SECOND") then
                list[#list + 1] = { v, name }
            end
        end
        table.sort(list, function(a, b) return a[1] > b[1] end)
        for i = 1, math.min(#list, 4) do stats[#stats + 1] = "+" .. list[i][1] .. " " .. list[i][2] end
    end
    local effectStats, effects = Popup.Effects(e.id)
    for _, st in ipairs(effectStats) do stats[#stats + 1] = st end
    return typeLine, table.concat(stats, "  "), effects
end

local function FoundLine(e)
    local s = e.s and e.s[1]
    if s and s.t == "x" then return s.n and ("Found inside " .. s.n) or "Found in a container" end
    if s and s.z then return "Found in " .. s.z end
    if s and s.n then return "Found on " .. s.n end
    return "New find"
end

-- the frame
local function Build()
    frame = CreateFrame("Button", "ForeverItemFinderPopup", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()
    T.Panel(frame, "1B1610", C.gold, 2)
    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetSize(U(44), U(44))
    iconFrame:SetPoint("TOPLEFT", U(12), -U(12))
    frame.iconBorder = T.Border(iconFrame, "A335EE", 1, "OVERLAY")
    frame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.iconFrame = iconFrame
    frame.name = T.Text(frame, 16, "A335EE")
    frame.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", U(12), 0)
    frame.name:SetPoint("RIGHT", -U(34), 0)
    frame.lines = {}
    for i = 1, 24 do
        local fs = T.Text(frame, 12, "FFFFFF")
        fs:SetWordWrap(true)
        frame.lines[i] = fs
    end
    frame.more = T.Text(frame, 12, C.title)
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(U(20), U(20))
    close:SetPoint("TOPRIGHT", -U(8), -U(8))
    T.Panel(close, C.red, C.gold)
    local x = T.Cross(close, U(8), C.title)
    x:SetPoint("CENTER")
    close:SetScript("OnClick", function() Popup.Hide() end)
    frame.close = close
    frame:SetScript("OnClick", function()
        if moving then return end
        local id = current and current.id
        Popup.Hide()
        if id and ns.UI then ns.UI.Select(id) end
    end)
    -- hovering shows the item and holds the pop-up open
    frame:SetScript("OnHide", function(self) T.HideItemTip(self) end)
    frame:SetScript("OnEnter", function(self)
        if not current or moving then return end
        hideAt = nil
        T.ItemTip(self, current.id)
    end)
    frame:SetScript("OnLeave", function()
        T.HideItemTip(frame)
        if current and not moving then Popup.ScheduleHide(3) end
    end)
    -- arriving: a short slide down while it fades in; it then sits exactly on its saved spot
    frame:SetClipsChildren(true)
    local arrive = frame:CreateAnimationGroup()
    local slide = arrive:CreateAnimation("Translation")
    slide:SetOffset(0, -U(10))
    slide:SetDuration(0.25)
    slide:SetSmoothing("OUT")
    local fadeIn = arrive:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.25)
    arrive:SetScript("OnFinished", function() Popup.Place() end)
    arrive:SetScript("OnStop", function() Popup.Place() end)
    frame.arrive = arrive
    -- leaving: a fade, then the frame hides
    local leave = frame:CreateAnimationGroup()
    local fadeOut = leave:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.3)
    leave:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)
    frame.leave = leave
    -- full animation: a gold shine crosses rare and better finds once, the waiting count pulses as it grows
    local shine = frame:CreateTexture(nil, "OVERLAY")
    shine:SetTexture("Interface\\Buttons\\WHITE8X8")
    shine:SetBlendMode("ADD")
    shine:SetGradient("HORIZONTAL", CreateColor(1, 0.82, 0, 0), CreateColor(1, 0.82, 0, 0.35))
    shine:SetWidth(U(60))
    shine:SetPoint("TOP")
    shine:SetPoint("BOTTOM")
    shine:SetPoint("RIGHT", frame, "LEFT")
    shine:Hide()
    local sweep = shine:CreateAnimationGroup()
    local cross = sweep:CreateAnimation("Translation")
    cross:SetDuration(0.7)
    cross:SetSmoothing("IN_OUT")
    sweep:SetScript("OnPlay", function() cross:SetOffset(frame:GetWidth() + U(60), 0) shine:Show() end)
    sweep:SetScript("OnFinished", function() shine:Hide() end)
    sweep:SetScript("OnStop", function() shine:Hide() end)
    frame.shine, frame.sweep = shine, sweep
    local pulse = frame.more:CreateAnimationGroup()
    local dim = pulse:CreateAnimation("Alpha")
    dim:SetFromAlpha(1)
    dim:SetToAlpha(0.35)
    dim:SetDuration(0.2)
    dim:SetOrder(1)
    local back = pulse:CreateAnimation("Alpha")
    back:SetFromAlpha(0.35)
    back:SetToAlpha(1)
    back:SetDuration(0.25)
    back:SetOrder(2)
    frame.pulse = pulse
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, px, py = self:GetPoint()
        ns.db.popup.pos = { point, rel, px, py }
    end)
    Popup.Place()
    Popup.ApplyScale()
end

-- lift: how far above its spot it starts (the arrival slide ends on the spot itself)
function Popup.Place(lift)
    if not frame then return end
    frame:ClearAllPoints()
    local pos = ns.db.popup.pos
    lift = lift or 0
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4] + lift) else frame:SetPoint("TOP", UIParent, "TOP", 0, -U(180) + lift) end
end

function Popup.ApplyScale()
    if frame then frame:SetScale((S().popScale or 100) / 100) end
end

local function Fill(e)
    local f = frame
    local style = S().popStyle
    -- an item the game has not loaded wears the shipped database's icon
    local known = C_Item.GetItemInfo(e.id) and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)
    f.icon:SetTexture(known or D.IconOf(e.id) or 134400)
    local hex = T.QualityHex(e.q)
    f.iconBorder:SetColor(hex)
    f.name:SetText(e.nm or C_Item.GetItemInfo(e.id) or ("Item " .. e.id))
    f.name:SetTextColor(T.RGB(hex))
    for _, fs in ipairs(f.lines) do fs:Hide() end
    local rows = {}
    if style == "card" then
        local typeLine, statLine, effects = Popup.CardLines(e)
        local show = S().card or {}
        if show.type and typeLine ~= "" then rows[#rows + 1] = { typeLine, "FFFFFF" } end
        if show.stats and statLine ~= "" then rows[#rows + 1] = { statLine, "1EFF00" } end
        if show.effects then
            for i, line in ipairs(effects) do
                if i > MAX_EFFECTS then
                    rows[#rows + 1] = { "+" .. (#effects - MAX_EFFECTS) .. " more, hover for the tooltip", C.dim }
                    break
                end
                rows[#rows + 1] = { line, "1EFF00" }
            end
        end
        if show.found then rows[#rows + 1] = { FoundLine(e), C.title } end
    elseif style == "full" then
        rows[#rows + 1] = { FoundLine(e), C.title }
        local lines = TooltipLines(e.id)
        for i = 2, #lines do
            local l = lines[i]
            local text = l.leftText
            if type(text) == "string" and not ns.Secret(text) and text ~= "" then
                local c = l.leftColor
                local hexc = c and ("%02X%02X%02X"):format(math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255)) or "FFFFFF"
                if l.rightText and l.rightText ~= "" and not ns.Secret(l.rightText) then text = text .. "   " .. l.rightText end
                rows[#rows + 1] = { text, hexc }
            end
            if #rows >= 22 then break end
        end
    else
        rows[#rows + 1] = { FoundLine(e), C.dim }
    end
    local width = style == "full" and U(320) or U(380)
    f:SetWidth(width)
    local textW = width - U(12) - U(44) - U(12) - U(12)
    local y = -U(12) - U(20)
    for i, r in ipairs(rows) do
        local fs = f.lines[i]
        fs:ClearAllPoints()
        if style == "full" and i > 1 then
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", U(12), y)
            fs:SetWidth(width - U(24))
        else
            fs:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", U(12), y + U(12))
            fs:SetWidth(textW)
        end
        fs:SetText(r[1])
        fs:SetTextColor(T.RGB(r[2]))
        fs:Show()
        y = y - math.max(U(15), fs:GetStringHeight() + U(2))
        if style == "full" and i == 1 then y = math.min(y, -U(12) - U(44) - U(6)) end
    end
    if waiting > 0 then
        f.more:ClearAllPoints()
        f.more:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", U(12), y + U(12))
        f.more:SetText("+" .. waiting .. " more waiting in the feed")
        f.more:Show()
        y = y - U(16)
    else
        f.more:Hide()
    end
    f:SetHeight(math.max(U(44) + U(24), -y + U(10)))
end

function Popup.ScheduleHide(seconds)
    local stay = S().popStay
    if stay == "close" and not seconds then hideAt = nil return end
    local s = seconds or tonumber(stay) or 5
    local token = {}
    hideAt = token
    C_Timer.After(s, function()
        if hideAt ~= token then return end
        if frame and frame:IsMouseOver() then return end
        Popup.Hide()
    end)
end

local function Animated() return S().popAnim ~= "off" end

function Popup.Hide()
    hideAt = nil
    current = nil
    waiting = 0
    T.HideItemTip(frame)
    if not frame or not frame:IsShown() then return end
    frame.arrive:Stop()
    frame.sweep:Stop()
    if Animated() and not moving then
        frame.leave:Play()
    else
        frame.leave:Stop()
        frame:Hide()
        frame:SetAlpha(1)
    end
end

-- puts a find on screen with the chosen animation
local function Present(e)
    if not frame then Build() end
    current = e
    Fill(e)
    frame.leave:Stop()
    frame:SetAlpha(1)
    frame.arrive:Stop()
    if Animated() then
        Popup.Place(U(10))
        frame:Show()
        frame.arrive:Play()
        if S().popAnim == "full" and (e.q or 0) >= 3 then frame.sweep:Play() end
    else
        Popup.Place()
        frame:Show()
    end
end

local function Show(e)
    lastShown, lastQ = GetTime(), e.q or 0
    ns.db.popped = ns.db.popped or {}
    ns.db.popped[e.id] = true
    Present(e)
    if S().sound then Popup.PlaySound(S().soundKit) end
    Popup.ScheduleHide()
end

-- a demo find pops up even with pop-ups off, but only when the Live Feed lists it (its filter and New / Changed chips)
local function DemoPasses(e)
    local _, classFile = UnitClass("player")
    return D.FindPasses(S().findFilter, e, UnitLevel("player") or 1, classFile)
end

-- a new or changed find arrived: one pop-up at a time, never in combat, each item once ever
function Popup.Offer(e)
    if not e or moving then return end
    ns.db.popped = ns.db.popped or {}
    -- a demo find carries its own name and icon
    local passes
    if e.demo then passes = DemoPasses(e) else passes = Popup.Passes(e) end
    if ns.db.popped[e.id] or not passes then return end
    -- a find from the network may not be loaded yet: the pop-up waits for the game's name and icon
    if not C_Item.GetItemInfo(e.id) and not e.demo then
        ns.Detect.WhenLoaded(e.id, function(ok)
            if not ok then return end
            e.nm = e.nm or C_Item.GetItemInfo(e.id)
            Popup.Offer(e)
        end)
        return
    end
    local s = S()
    -- "rarer": a find of a higher quality than the one showing takes over; the one it pushes out stays in the feed
    local rarer = s.popNext == "rarer"
    if InCombatLockdown() and s.popCombat ~= "show" then
        if not (rarer and held and (held.q or 0) > (e.q or 0)) then held = e end
        return
    end
    -- one showing: the new find waits in the feed, or takes over the pop-up
    if current and (s.popNext == "replace" or (rarer and (e.q or 0) > (current.q or 0))) then
        waiting = 0
        Show(e)
        return
    end
    -- the rate limit holds back a find, unless it is rarer than the last one shown while a rarer find takes over
    local early = GetTime() - lastShown < (tonumber(s.popGap) or GAP)
    if current or (early and not (rarer and (e.q or 0) > lastQ)) then
        if current then
            waiting = waiting + 1
            Fill(current)
            if s.popAnim == "full" then frame.pulse:Play() end
        end
        return
    end
    Show(e)
end

-- a catch-up copy (quiet) is old news: it reaches the feed, never a pop-up
ns.Listen("FindsChanged", function(e, status, info)
    if (status == "new" or status == "changed") and not (info and info.quiet) then Popup.Offer(e) end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if held then
        local e = held
        held = nil
        Popup.Offer(e)
    end
end)

-- options: show the chosen style on the latest find, or let the player drag it
function Popup.Preview()
    local e = ns.Finds.List()[1]
    if not e or moving then return end
    Present(e)
    Popup.ScheduleHide(5)
end

function Popup.ToggleMover()
    if not frame then Build() end
    if moving then
        moving = false
        frame:EnableMouse(true)
        Popup.Hide()
        return
    end
    moving = true
    current = ns.Finds.List()[1] or { id = 6948, nm = "Hearthstone", q = 1, s = {} }
    waiting = 0
    Fill(current)
    frame:Show()
    hideAt = nil
end

function Popup.ResetPosition()
    ns.db.popup.pos = nil
    Popup.Place()
end

-- the mover never outlives the window it was opened from
ns.Listen("WindowHidden", function()
    if moving then Popup.ToggleMover() end
end)
