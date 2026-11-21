-- QOL\AD_GearTracker.lua: the gear tracker: inside a dungeon, the pieces you still want there boss by boss, the next
-- boss for you, the bosses killed, and a reminder to roll Need when a wanted piece drops.
-- Draws NS.GearList; on with the Gear Value page's tracker switch (setting gearTracker, off to start).
-- Boss kills, loot rolls and the loot window carry plain values; it reads nothing secret.
local ADDON, NS = ...
local CreateFrame = NS.Perf and NS.Perf.Frames("GearTracker") or function(...) return CreateFrame(...) end

local TR = {}
NS.GearTracker = TR

-- sizes from the picked boards (canvas row 6, JTrack and JTrackDrop)
TR.W, TR.PAD, TR.HEAD_H, TR.NEXT_H, TR.LUCK_H = 330, 12, 32, 30, 28
TR.NAME_H, TR.MORE_H, TR.ITEM_H, TR.ITEM_GAP, TR.ITEM_INDENT = 16, 14, 20, 4, 30
TR.MAX_ITEMS = 14
TR.ROLL_W, TR.ICON = 400, 42
TR.GOLD = { 0.949, 0.831, 0.608 }
TR.UP = { 0.357, 0.839, 0.541 }
TR.rules, TR.bosses, TR.items = {}, {}, {}

local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.AT.FONT, size, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Pulse(frame)
    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.55)
    a:SetDuration(0.8)
    return pulse
end

function TR.On()
    local S = NS.Store
    return S ~= nil and S.GetSetting ~= nil and S.GetSetting("gearTracker") == true
end

function TR.SetOn(on)
    local S = NS.Store
    if S and S.SetSetting then S.SetSetting("gearTracker", on and true or nil) end
    TR.Refresh()
end

-- The panel, moved by dragging, its spot kept for the account; the roll and won banners beside it.
function TR.Build()
    if TR.frame then return TR.frame end
    local AT = NS.AT
    local COL = AT.COL
    local f = CreateFrame("Frame", "ArcAurasGearTracker", UIParent, "BackdropTemplate")
    f:SetSize(TR.W, 100)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local ui = NS.Store and NS.Store.UI and NS.Store.UI()
        local _, _, _, x, y = self:GetPoint(1)
        if type(ui) == "table" then ui.gearTrackerPos = { x = x, y = y } end
    end)
    AT.Skin(f, { COL.well[1], COL.well[2], COL.well[3], 0.9 }, COL.line2)
    local ui = NS.Store and NS.Store.UI and NS.Store.UI()
    local pos = type(ui) == "table" and ui.gearTrackerPos
    if type(pos) == "table" and type(pos.x) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -22, -200)
    end
    f.title = Text(f, 15)
    f.title:SetPoint("TOPLEFT", TR.PAD, -10)
    Color(f.title, TR.GOLD)
    f.run = Text(f, 11, "RIGHT")
    f.run:SetPoint("TOPRIGHT", -TR.PAD, -12)
    Color(f.run, COL.faint)
    f.next = Text(f, 12)
    f.next:SetPoint("TOPLEFT", TR.PAD, -(TR.HEAD_H + 8))
    f.next:SetWidth(TR.W - 2 * TR.PAD)
    f.luck = Text(f, 11)
    f.luck:SetWidth(TR.W - 2 * TR.PAD)
    Color(f.luck, COL.faint)
    f:Hide()
    TR.frame = f

    -- the roll reminder: over the game's roll frame when there is one, else mid-screen
    local b = CreateFrame("Frame", "ArcAurasGearTrackerRoll", UIParent, "BackdropTemplate")
    b:SetSize(TR.ROLL_W, 14 + 12 + 10 + TR.ICON + 14)
    b:SetFrameStrata("HIGH")
    AT.Skin(b, COL.well, TR.GOLD)
    b.cap = Text(b, 11)
    b.cap:SetPoint("TOPLEFT", 16, -14)
    Color(b.cap, TR.GOLD)
    b.cap:SetText(Tr("ON YOUR LIST: ROLL NEED"))
    b.frame = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.frame:SetSize(TR.ICON, TR.ICON)
    b.frame:SetPoint("TOPLEFT", 16, -(14 + 12 + 10))
    AT.Skin(b.frame, COL.bg, COL.steel)
    b.icon = b.frame:CreateTexture(nil, "ARTWORK")
    local hair = AT.Hairline(b.frame)
    b.icon:SetPoint("TOPLEFT", hair, -hair)
    b.icon:SetPoint("BOTTOMRIGHT", -hair, hair)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.item = Text(b, 15)
    b.item:SetPoint("TOPLEFT", b.frame, "TOPRIGHT", 12, -4)
    b.item:SetPoint("RIGHT", -16, 0)
    b.gain = Text(b, 12)
    b.gain:SetPoint("TOPLEFT", b.item, "BOTTOMLEFT", 0, -4)
    b.gain:SetPoint("RIGHT", -16, 0)
    Color(b.gain, TR.UP)
    b.pulse = Pulse(b)
    b:Hide()
    TR.roll = b

    -- the piece reached the bags
    local won = CreateFrame("Frame", "ArcAurasGearTrackerWon", UIParent, "BackdropTemplate")
    won:SetSize(TR.ROLL_W, 14 + 16 + 14)
    won:SetFrameStrata("HIGH")
    AT.Skin(won, COL.well, TR.UP)
    won.text = Text(won, 14)
    won.text:SetPoint("LEFT", 16, 0)
    won.text:SetPoint("RIGHT", -16, 0)
    Color(won.text, COL.ink)
    won:Hide()
    TR.won = won
    return f
end

function TR.Rule(i)
    local t = TR.rules[i]
    if t then return t end
    local f = TR.frame
    t = f:CreateTexture(nil, "BORDER")
    t:SetHeight(NS.AT.Hairline(f))
    TR.rules[i] = t
    return t
end

function TR.Boss(i)
    local r = TR.bosses[i]
    if r then return r end
    local f = TR.frame
    r = { name = Text(f, 13), more = Text(f, 10), state = Text(f, 11, "RIGHT") }
    r.name:SetWidth(TR.W - 2 * TR.PAD - 60)
    r.more:SetWidth(TR.W - 2 * TR.PAD)
    Color(r.more, NS.AT.COL.faint)
    TR.bosses[i] = r
    return r
end

function TR.Item(i)
    local r = TR.items[i]
    if r then return r end
    local AT = NS.AT
    r = CreateFrame("Frame", nil, TR.frame, "BackdropTemplate")
    r:SetHeight(TR.ITEM_H)
    AT.Skin(r, { 0, 0, 0, 0 }, TR.GOLD)
    r.name = Text(r, 12)
    r.name:SetPoint("LEFT", 6, 0)
    r.chance = Text(r, 11, "RIGHT")
    r.chance:SetPoint("RIGHT", -6, 0)
    r.chance:SetWidth(40)
    Color(r.chance, AT.COL.dim)
    r.gain = Text(r, 11, "RIGHT")
    r.gain:SetPoint("RIGHT", r.chance, "LEFT", -8, 0)
    Color(r.gain, TR.UP)
    r.pulse = Pulse(r)
    TR.items[i] = r
    return r
end

-- The other bosses of one loot table, their titles left off: "Any one of them: Theolen Krastinov, Alexei Barov".
function TR.ShortName(name)
    return (tostring(name):gsub("^Instructor ", ""):gsub("^Doctor ", ""):gsub("^Lorekeeper ", ""):gsub("^Lord ", "")
        :gsub("^Lady ", ""))
end

-- What the tracker shows: the header, Next for you, each block of bosses with the pieces still wanted, the tries.
function TR.Model()
    local GL = NS.GearList
    if not (TR.On() and GL and GL.Available() and GL.here and GL.cands) then return nil end
    local scale = GL.Scale()
    if not scale then return nil end
    local group
    for _, g in ipairs(GL.Groups(scale)) do if g.here then group = g end end
    local order = NS.GearListOrder and NS.GearListOrder[GL.here.map] or {}
    local down = 0
    for _, name in ipairs(order) do if GL.Killed(name) then down = down + 1 end end
    local run = ""
    if #order > 0 then run = down == 0 and Tr("Just entered") or string.format(Tr("%d of %d bosses killed"), down, #order) end
    local m = { title = GL.here.name, run = run, blocks = {} }
    local mine = GL.Mine()
    local tries, next = 0, nil
    for _, b in ipairs(group and group.blocks or {}) do
        local want = {}
        for _, e in ipairs(b.entries) do if not GL.Has(e.id) then want[#want + 1] = e end end
        if #want > 0 then
            if not b.killed and not next then next = b end
            local others = {}
            for k = 2, #b.bosses do others[#others + 1] = TR.ShortName(b.bosses[k]) end
            local block = {
                name = b.bosses[1] .. (#b.bosses > 1 and string.format(Tr(" and %d more"), #b.bosses - 1) or ""),
                more = #others > 0 and string.format(Tr("Any one of them: %s"), table.concat(others, ", ")) or "",
                state = b.killed and Tr("killed") or (next == b and Tr("next") or ""),
                killed = b.killed, items = {},
            }
            for _, e in ipairs(want) do
                -- runs before this one: a boss killed in this run already counted its try
                local t = (mine and mine.tries[e.id] or 0) - (b.killed and 1 or 0)
                if t > tries then tries = t end
                block.items[#block.items + 1] = { id = e.id, q = e.q, name = e.name, chance = GL.ChanceText(b, e.id),
                    gain = NS.GearListUI.GainText(e.gain.d, scale), hot = GL.drop ~= nil and GL.drop.id == e.id }
            end
            m.blocks[#m.blocks + 1] = block
        end
    end
    m.next = next and string.format(Tr("Next for you: %s"), next.bosses[1]) or Tr("Nothing left for you here")
    m.done = next == nil
    m.luck = tries == 0 and Tr("First run here for these. Each kill of their boss is one more try.")
        or string.format(Tr("Run %d here for these. Each kill of their boss is one more try."), tries + 1)
    return m
end

local function HideBanners()
    if TR.roll then
        TR.roll.pulse:Stop()
        TR.roll:Hide()
    end
    if TR.won then TR.won:Hide() end
end

function TR.Refresh()
    local m = TR.Model()
    local f = TR.frame
    if not m then
        if f then f:Hide() end
        HideBanners()
        return
    end
    f = TR.Build()
    local AT = NS.AT
    local COL = AT.COL
    local QC = ITEM_QUALITY_COLORS or {}
    f.title:SetText(m.title)
    f.run:SetText(m.run)
    f.next:SetText(m.next)
    Color(f.next, m.done and TR.UP or TR.GOLD)
    local rules, bosses, items = 0, 0, 0
    local function Rule(y, c)
        rules = rules + 1
        local t = TR.Rule(rules)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:Show()
    end
    Rule(-TR.HEAD_H, COL.line)
    local y = -(TR.HEAD_H + TR.NEXT_H)
    Rule(y, COL.panel)
    for _, block in ipairs(m.blocks) do
        if items >= TR.MAX_ITEMS then break end
        bosses = bosses + 1
        local B = TR.Boss(bosses)
        y = y - 7
        B.name:ClearAllPoints()
        B.name:SetPoint("TOPLEFT", f, "TOPLEFT", TR.PAD, y)
        B.name:SetText(block.name)
        Color(B.name, block.killed and COL.faint or COL.ink)
        B.state:ClearAllPoints()
        B.state:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TR.PAD, y - 1)
        B.state:SetText(block.state)
        Color(B.state, block.killed and COL.faint or TR.GOLD)
        local alpha = block.killed and 0.5 or 1
        B.name:SetAlpha(alpha)
        B.state:SetAlpha(alpha)
        B.name:Show()
        B.state:Show()
        y = y - TR.NAME_H
        if block.more ~= "" then
            B.more:ClearAllPoints()
            B.more:SetPoint("TOPLEFT", f, "TOPLEFT", TR.PAD, y)
            B.more:SetText(block.more)
            B.more:SetAlpha(alpha)
            B.more:Show()
            y = y - TR.MORE_H
        else
            B.more:Hide()
        end
        for _, it in ipairs(block.items) do
            if items >= TR.MAX_ITEMS then break end
            items = items + 1
            local R = TR.Item(items)
            y = y - TR.ITEM_GAP
            R:ClearAllPoints()
            R:SetPoint("TOPLEFT", f, "TOPLEFT", TR.PAD + TR.ITEM_INDENT, y)
            R:SetPoint("TOPRIGHT", f, "TOPRIGHT", -TR.PAD, y)
            R.name:SetText(it.name)
            R.name:SetPoint("RIGHT", R.gain, "LEFT", -8, 0)
            local q = it.hot and { r = TR.GOLD[1], g = TR.GOLD[2], b = TR.GOLD[3] } or (QC[it.q or 1] or { r = 1, g = 1, b = 1 })
            R.name:SetTextColor(q.r, q.g, q.b)
            R.gain:SetText(it.gain)
            R.chance:SetText(it.chance)
            R:SetBackdropBorderColor(TR.GOLD[1], TR.GOLD[2], TR.GOLD[3], it.hot and 1 or 0)
            R:SetAlpha(alpha)
            R:Show()
            if it.hot then
                if not R.pulse:IsPlaying() then R.pulse:Play() end
            else
                R.pulse:Stop()
            end
            y = y - TR.ITEM_H
        end
        y = y - 6
        Rule(y, COL.panel)
    end
    f.luck:ClearAllPoints()
    f.luck:SetPoint("TOPLEFT", f, "TOPLEFT", TR.PAD, y - 8)
    f.luck:SetText(m.luck)
    y = y - TR.LUCK_H
    for i = rules + 1, #TR.rules do TR.rules[i]:Hide() end
    for i = bosses + 1, #TR.bosses do
        local B = TR.bosses[i]
        B.name:Hide()
        B.more:Hide()
        B.state:Hide()
    end
    for i = items + 1, #TR.items do
        TR.items[i].pulse:Stop()
        TR.items[i]:Hide()
    end
    f:SetHeight(-y)
    f:Show()
    TR.Banners()
end

-- A wanted piece in a roll or the loot window; then, once it is in the bags, that it was won.
function TR.Banners()
    local GL = NS.GearList
    local QC = ITEM_QUALITY_COLORS or {}
    local b, won = TR.roll, TR.won
    if GL.drop then
        local e = GL.drop.e
        local q = QC[e.q or 1] or { r = 1, g = 1, b = 1 }
        local scale = GL.Scale()
        b.item:SetText(e.name or "")
        b.item:SetTextColor(q.r, q.g, q.b)
        b.frame:SetBackdropBorderColor(q.r, q.g, q.b, 1)
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)
        b.icon:SetTexture(icon or 134400)
        local G = NS.GearValue
        local gain = NS.GearListUI.GainText(e.gain.d, scale)
        local pct = G and G.Pct and G.Pct(e.gain.d, e.gain.was)
        if pct then gain = gain .. " " .. string.format(Tr("(%s vs worn)"), G.PctText(pct)) end
        b.gain:SetText(scale and string.format(Tr("%s on %s"), gain, scale.name) or gain)
        b:ClearAllPoints()
        local host = GroupLootFrame1
        if GL.drop.roll and host and host:IsShown() then
            b:SetPoint("BOTTOM", host, "TOP", 0, 8)
        else
            b:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
        b:Show()
        if not b.pulse:IsPlaying() then b.pulse:Play() end
    else
        b.pulse:Stop()
        b:Hide()
    end
    if GL.won and not GL.drop then
        won.text:SetText(string.format(Tr("You won %s. Off your list, and your progress moves on."), GL.won.e.name or ""))
        won:ClearAllPoints()
        won:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        won:Show()
    else
        won:Hide()
    end
end
