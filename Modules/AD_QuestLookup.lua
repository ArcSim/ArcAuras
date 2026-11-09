-- AD_QuestLookup: hold a key with a target and a box lists the quests it belongs to (WoW Forever only; retail keeps
-- just the key's name, since the bindings file loads there too). Nothing runs until the key goes down.
-- Setting: "questLookup", off until switched on.
local ADDON, NS = ...
local AT = NS.AT

BINDING_HEADER_ARCAURAS = "Arc Auras"
BINDING_NAME_ARCAURAS_QUESTLOOKUP = AT.Tr(NS.IsForever == true and "Quest Lookup (hold)" or "Quest Lookup (WoW Forever only)")

if NS.IsForever ~= true then return end

local COL, Tr, Store = AT.COL, AT.Tr, NS.Store
local QL = {}
NS.QuestLookup = QL

local BOX_NAME = "ArcAurasQuestLookupBox"
local MAX_ROWS = 14
local FONT_SIZE, ROW_H, PAD, WORD_GAP, INDENT = 12, 16, 8, 16, 10
local MIN_W, SECRET_W = 170, 320
local GREEN = { 0.35, 0.85, 0.45 }

local sources = {}
local box, titleFS
local rowPool = {}

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- UnitExists answers a secret boolean in combat; a secret counts as a target and the reads below settle it.
local function HasTarget()
    local there = UnitExists("target")
    if Secret(there) then return true end
    return there == true
end

local function NpcID(unit)
    local guid = UnitGUID(unit)
    if Secret(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- The game's own answer. Secret text still draws, so only the line's type has to be plain.
local function FromTooltip(unit, out, seen)
    local types = Enum and Enum.TooltipDataLineType
    local api = C_TooltipInfo
    if not (types and api and api.GetUnit) then return end
    local data = api.GetUnit(unit)
    if Secret(data) or type(data) ~= "table" then return end
    local lines = data.lines
    if Secret(lines) or type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        local kind, text = line.type, line.leftText
        local hasText = Secret(text) or (type(text) == "string" and text ~= "")
        if hasText and not Secret(kind) then
            if kind == types.QuestTitle then
                out[#out + 1] = { text = text, col = COL.ink }
                if not Secret(text) then seen[text] = true end
            elseif kind == types.QuestObjective then
                local done = line.completed
                if Secret(done) then done = false end
                out[#out + 1] = { text = text, col = (done == true) and GREEN or COL.dim, x = INDENT }
            end
        end
    end
end

-- Objective text reads "Young Wolf slain: 0/8" or "0/8 Young Wolf slain".
local function NamesMob(text, mob)
    local s = text:gsub("^%d+/%d+%s*", "")
    if s:sub(1, #mob) ~= mob then return false end
    local after = s:sub(#mob + 1, #mob + 1)
    return after == "" or not after:find("[%w\128-\255]")
end

-- For quests the tooltip left out: an objective that names this mob.
local function FromLog(mob, out, seen)
    if Secret(mob) or type(mob) ~= "string" or mob == "" then return end
    local api = C_QuestLog
    if not (api and api.GetNumQuestLogEntries and api.GetInfo and api.GetQuestObjectives) then return end
    local n = api.GetNumQuestLogEntries()
    if Secret(n) or type(n) ~= "number" then return end
    for i = 1, n do
        local info = api.GetInfo(i)
        if type(info) == "table" then
            local title, id, isHeader = info.title, info.questID, info.isHeader
            if not Secret(title) and type(title) == "string" and not seen[title]
                and not Secret(isHeader) and isHeader ~= true and not Secret(id) and id then
                local objectives = api.GetQuestObjectives(id)
                local named = false
                for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
                    local text, kind = o.text, o.type
                    if not Secret(text) and type(text) == "string" and not Secret(kind)
                        and kind == "monster" and NamesMob(text, mob) then
                        if not named then
                            named = true
                            seen[title] = true
                            out[#out + 1] = { text = title, col = COL.ink }
                        end
                        local done = o.finished
                        if Secret(done) then done = false end
                        out[#out + 1] = { text = text, col = (done == true) and GREEN or COL.dim, x = INDENT }
                    end
                end
            end
        end
    end
end

local function Related(unit)
    local api = C_QuestLog
    if not (api and api.UnitIsRelatedToActiveQuest) then return false end
    local r = api.UnitIsRelatedToActiveQuest(unit)
    if Secret(r) then return false end
    return r == true
end

local function Word(why)
    if why == "gives" then return Tr("Pick up") end
    if why == "ends" then return Tr("Turn in") end
    if why == "kill" then return Tr("Kill") end
    if why == "loot" then return Tr("Loot") end
end

-- A source's quests: the log's turn-ins join the quests above, and anything else in the log is the game's to answer.
local function FromSources(npc, mine, open)
    if not npc or #sources == 0 then return end
    local api = C_QuestLog
    local level = UnitLevel("player")
    if Secret(level) then level = nil end
    for _, source in ipairs(sources) do
        local list = source(npc)
        for _, q in ipairs(type(list) == "table" and list or {}) do
            local word = Word(q.why)
            local done = api.IsQuestFlaggedCompleted(q.id)
            if word and (Secret(done) or done ~= true) then
                local index = api.GetLogIndexForQuestID(q.id)
                local inLog = (not Secret(index)) and index ~= nil
                if inLog then
                    if q.why == "ends" then
                        mine[#mine + 1] = { text = q.name, col = GREEN, word = word, wordCol = GREEN }
                    end
                elseif q.why ~= "ends" then
                    local text = q.level and ("[%d] %s"):format(q.level, q.name) or q.name
                    local high = q.req and level and q.req > level
                    open[#open + 1] = { text = text, col = high and COL.faint or COL.ink, word = word, wordCol = COL.dim }
                end
            end
        end
    end
end

local function Caption(rows, words)
    rows[#rows + 1] = { text = Tr(words), col = COL.arc }
end

-- What the box shows for a unit: its name (may be secret) and the flat rows, capped so the box stays small.
function QL.Collect(unit)
    local name = UnitName(unit)
    local mine, open, seen = {}, {}, {}
    FromTooltip(unit, mine, seen)
    FromLog(name, mine, seen)
    if #mine == 0 and Related(unit) then
        mine[1] = { text = Tr("Part of a quest in your log"), col = COL.ink }
    end
    FromSources(NpcID(unit), mine, open)

    local rows = {}
    if #open > 0 and #mine > 0 then Caption(rows, "In your log") end
    for _, r in ipairs(mine) do rows[#rows + 1] = r end
    if #open > 0 then Caption(rows, "Not in your log") end
    for _, r in ipairs(open) do rows[#rows + 1] = r end
    if #rows == 0 then rows[1] = { text = Tr("No quests"), col = COL.dim } end

    if #rows > MAX_ROWS then
        local extra = #rows - MAX_ROWS + 1
        for i = #rows, MAX_ROWS, -1 do rows[i] = nil end
        rows[MAX_ROWS] = { text = Tr("and %d more"):format(extra), col = COL.faint }
    end
    return name, rows
end

-- The box

local function MakeFS()
    local fs = box:CreateFontString(nil, "OVERLAY")
    fs:SetFont(AT.FONT, FONT_SIZE, "")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Build()
    if box then return end
    box = CreateFrame("Frame", BOX_NAME, UIParent)
    box:Hide()
    box:SetFrameStrata("TOOLTIP")
    box:SetClampedToScreen(true)
    AT.Skin(box, COL.bg, COL.line2)
    tinsert(UISpecialFrames, BOX_NAME)
    titleFS = MakeFS()
    titleFS:SetPoint("TOPLEFT", PAD, -PAD)
    titleFS:SetTextColor(COL.arc[1], COL.arc[2], COL.arc[3])
    box:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    box:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" or event == "CINEMATIC_START" then
            box:Hide()
        else
            QL.Refresh()
        end
    end)
end

-- Secret text has no readable width, so it gets a fixed one.
local function TextW(fs, text)
    if Secret(text) then return SECRET_W end
    local w = fs:GetStringWidth()
    return type(w) == "number" and w or 0
end

local function Draw(name, rows)
    titleFS:SetText(name)
    local widest = math.max(MIN_W, TextW(titleFS, name))
    local y = PAD + ROW_H + 2
    for i, row in ipairs(rows) do
        local r = rowPool[i]
        if not r then
            r = { left = MakeFS(), right = MakeFS() }
            rowPool[i] = r
        end
        local col = row.col
        r.left:ClearAllPoints()
        r.left:SetPoint("TOPLEFT", PAD + (row.x or 0), -y)
        r.left:SetTextColor(col[1], col[2], col[3])
        r.left:SetText(row.text)
        r.left:Show()
        local need = (row.x or 0) + TextW(r.left, row.text)
        if row.word then
            local wc = row.wordCol
            r.right:ClearAllPoints()
            r.right:SetPoint("TOPRIGHT", -PAD, -y)
            r.right:SetTextColor(wc[1], wc[2], wc[3])
            r.right:SetText(row.word)
            r.right:Show()
            need = need + WORD_GAP + TextW(r.right, row.word)
        else
            r.right:Hide()
        end
        if need > widest then widest = need end
        y = y + ROW_H
    end
    for i = #rows + 1, #rowPool do
        rowPool[i].left:Hide()
        rowPool[i].right:Hide()
    end
    box:SetSize(AT.PixelSize(box, widest + PAD * 2), AT.PixelSize(box, y + PAD))
end

-- Beside the cursor, the corner on a whole pixel.
local function Place()
    local px = AT.Px(box)
    local scale = box:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local x, y = cx / scale + 16, cy / scale + 8
    if px > 0 then
        x = math.floor(x / px + 0.5) * px
        y = math.floor(y / px + 0.5) * px
    end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

-- False when there is nobody to describe.
local function Render()
    local name, rows = QL.Collect("target")
    if not Secret(name) and not name then return false end
    Draw(name, rows)
    return true
end

function QL.IsOn() return Store.GetSetting("questLookup") == true end

function QL.Close()
    if box then box:Hide() end
end

function QL.SetOn(v)
    Store.SetSetting("questLookup", v and true or nil)
    if not v then QL.Close() end
end

function QL.Refresh()
    if not (box and box:IsShown()) then return end
    if not (QL.IsOn() and HasTarget() and Render()) then box:Hide() end
end

function QL.Open()
    if box and box:IsShown() then
        QL.Refresh()
        return
    end
    if not (QL.IsOn() and HasTarget()) then return end
    Build()
    box:SetScale(AT.WinScale())
    if not Render() then return end
    Place()
    box:RegisterEvent("PLAYER_TARGET_CHANGED")
    box:RegisterEvent("QUEST_LOG_UPDATE")
    box:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    box:RegisterEvent("PLAYER_LEAVING_WORLD")
    box:RegisterEvent("CINEMATIC_START")
    box:Show()
end

-- The binding runs on the key's way down and on its way up.
function ArcAurasQuestLookup_Key(keystate)
    if keystate == "down" then QL.Open() else QL.Close() end
end

-- Another addon can add rows: fn(npcID) returns a list of
-- { id = questID, name = title, why = "gives" | "ends" | "kill" | "loot", level = number, req = number }.
function ArcAurasQuestLookup_AddSource(fn)
    if type(fn) == "function" then sources[#sources + 1] = fn end
end
