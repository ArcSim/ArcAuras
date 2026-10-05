-- AD_SpecialIcon: the Special Aura icon kind, a tracker of the Special hub drawn as an ordinary icon (retail only).
-- Owns the attach to NS.Special, the templates on the stack text and labels, their state colours, the spent state and a timer's swipe; the cooldown driver hands it frames, the Factory asks it for art, tooltips and a repaint after a restyle.
-- Everything it paints is a plain number the tracker's Read() hands over; nothing here reads the game.
local ADDON, NS = ...
if NS.IsForever == true then return end

local SI = {}
NS.SpecialIcon = SI

SI.live = {}   -- [recId] = { rec, f, id, read, sure, cdKey }

-- the tokens that make a label the proc count, and the one that makes it the chance
local PROC_TOKENS = { procs = true, procsLeft = true, count = true }
-- custom texts 1 to 3, then the special icon's own slots 4 to 6 (proc count, chance, violations)
local SUFFIX = { "", "2", "3", "4", "5", "6" }

local function Hub() return NS.Special end

function SI.TrackerID(rec)
    local d = rec and rec.driver
    return d and (d.tracker or d.special) or nil
end

function SI.Def(rec)
    local SP = Hub()
    local id = SI.TrackerID(rec)
    return (SP and id) and SP.Get(id) or nil
end

-- The tracker's own art: a path, or a number tried as a spell first and then
-- as a file, as ProcTracker drew it.
function SI.ArtOf(def)
    if not def then return nil end
    local icon = def.icon
    if type(icon) == "string" then return icon end
    if type(icon) ~= "number" then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(icon) or icon
    end
    return icon
end

function SI.Texture(rec)
    return SI.ArtOf(SI.Def(rec))
end

function SI.Status(rec)
    local def = SI.Def(rec)
    if not def then return "unknown tracker" end
    if def.Status then return def.Status() or "" end
    return ""
end

-- Whether a label reads the proc count ("proc"), the chance ("chance") or neither.
function SI.LabelRole(template)
    if type(template) ~= "string" then return nil end
    for token in template:gmatch("{(%w+)}") do
        if PROC_TOKENS[token] then return "proc" end
    end
    if template:find("{chance}", 1, true) then return "chance" end
    return nil
end

-- A template with its tokens filled from a read; an unknown token reads empty.
-- A tracker that hands its own texts (text.pos, text.procs) is shown with them.
function SI.Expand(template, read, rec, def)
    if type(template) ~= "string" or template == "" or not read then return "" end
    local SP = Hub()
    local Store = NS.Store
    local txt = read.text
    local function Chance()
        if txt and txt.pos then return txt.pos end
        local pct = tonumber(read.chance)
        if not pct then return "" end
        local dec = Store and Store.Resolve(rec, "special", "chanceDecimals")
        return SP and SP.FormatChance(pct, dec ~= false) or tostring(pct)
    end
    local out = template:gsub("{(%w+)}", function(token)
        if token == "chance" then return Chance() end
        if token == "count" then
            if txt and txt.procs then return txt.procs end
            local v = read.count
            if v == nil then v = read.pos end
            return v ~= nil and tostring(v) or ""
        end
        local v = read[token]
        if v == nil then return "" end
        return tostring(v)
    end)
    return out
end

-- The tracker's stack text: the record's template, else the tracker's own.
function SI.StackTemplate(rec, def)
    local Store = NS.Store
    local t = Store and Store.Resolve(rec, "special", "stackTemplate")
    if type(t) == "string" and t ~= "" then return t end
    return def and def.stack or ""
end

-- The cooldown look: every proc of the deck used, or a timer's cooldown running.
function SI.Spent(read, def)
    if not read then return false end
    if def and def.isTimer then return read.active == true end
    local left = tonumber(read.procsLeft)
    return left ~= nil and left <= 0
end

-- "empty" (no proc used yet), "full" (every one used) or "half".
function SI.ProcState(read)
    local procs, left = tonumber(read.procs) or 0, tonumber(read.procsLeft)
    if left ~= nil and left <= 0 then return "full" end
    if procs <= 0 then return "empty" end
    return "half"
end

local function Color(c, fallback)
    c = c or fallback
    return { c[1], c[2], c[3], c[4] or 1 }
end

function SI.ProcColor(rec, read)
    local Store = NS.Store
    if Store.Resolve(rec, "special", "procColorMode") == "fixed" then return nil end
    local state = SI.ProcState(read)
    if state == "empty" then return Color(Store.Resolve(rec, "special", "procEmptyColor"), { 0, 1, 0 }) end
    if state == "full" then return Color(Store.Resolve(rec, "special", "procFullColor"), { 1, 0, 0 }) end
    return Color(Store.Resolve(rec, "special", "procHalfColor"), { 1, 0.82, 0 })
end

function SI.ChanceColor(rec, read)
    local Store, SP = NS.Store, Hub()
    local mode = Store.Resolve(rec, "special", "chanceColorMode")
    if mode == "procs" then
        local left = tonumber(read.procsLeft) or 0
        if Store.Resolve(rec, "special", "chanceLeftCustom") == true then
            local slot = math.max(0, math.min(5, math.floor(left)))
            return Color(Store.Resolve(rec, "special", "chanceLeft" .. slot .. "Color"), { 1, 1, 1 })
        end
        local r, g, b = 1, 1, 1
        if SP then r, g, b = SP.ProcCountTint(left, tonumber(read.max) or 1) end
        return { r, g, b, 1 }
    elseif mode == "chance" then
        local pct = tonumber(read.chance) or 0
        local low = tonumber(Store.Resolve(rec, "special", "chanceLowPct")) or 3
        local high = tonumber(Store.Resolve(rec, "special", "chanceHighPct")) or 10
        -- the hot cut first, as ProcTracker reads them, so crossed cuts agree too
        if pct >= high then return Color(Store.Resolve(rec, "special", "chanceHotColor"), { 0, 1, 0 }) end
        if pct < low then return Color(Store.Resolve(rec, "special", "chanceColdColor"), { 0.6, 0.6, 0.6 }) end
        return Color(Store.Resolve(rec, "special", "chanceMidColor"), { 1, 0.82, 0 })
    end
    return nil
end

-- One label: its template expanded, shown per state by the Factory, coloured
-- by its role or its own colour.
local function PaintLabel(f, i, rec, read, def)
    local Store = NS.Store
    local suf = SUFFIX[i]
    local fs = f["labelText" .. suf]
    local st = f._adLabels and f._adLabels[i]
    if not (fs and st) then return end
    local template = Store.Resolve(rec, "label", "labelText" .. suf)
    local text = SI.Expand(template, read, rec, def)
    fs:SetText(text)
    st.has = text ~= ""
    if not st.has then
        fs:Hide()
        return
    end
    local role = SI.LabelRole(template)
    local c
    if role == "proc" then c = SI.ProcColor(rec, read)
    elseif role == "chance" then c = SI.ChanceColor(rec, read) end
    c = c or Color(Store.Resolve(rec, "label", "labelColor" .. suf), { 1, 1, 1 })
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- A timer's swipe: our own GetTime numbers, pushed once per cooldown.
local function PaintSwipe(e, read, def)
    local f = e.f
    if not (def and def.isTimer and f.cooldown) then return end
    if read.active == true and tonumber(read.expiry) and tonumber(read.duration) then
        local key = read.expiry .. "/" .. read.duration
        if e.cdKey ~= key then
            e.cdKey = key
            f.cooldown:SetCooldown(read.expiry - read.duration, read.duration)
        end
    elseif e.cdKey ~= nil then
        e.cdKey = nil
        f.cooldown:Clear()
    end
end

-- A tracker that cannot read what it counts says so on the icon, as
-- ProcTracker did: a yellow tint and "!" over the art (never on text only).
local function PaintWarn(f, rec, on)
    on = on and NS.Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
    local w = f._adSpecialWarn
    if not on then
        if w then w:Hide() end
        return
    end
    if not w then
        w = CreateFrame("Frame", nil, f)
        w:EnableMouse(false)
        local tint = w:CreateTexture(nil, "OVERLAY")
        tint:SetAllPoints()
        tint:SetColorTexture(1, 0.85, 0, 0.25)
        local mark = w:CreateFontString(nil, "OVERLAY")
        mark:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
        mark:SetPoint("CENTER")
        mark:SetTextColor(1, 0.85, 0, 1)
        mark:SetText("!")
        f._adSpecialWarn = w
    end
    w:ClearAllPoints()
    w:SetAllPoints(f.icon or f)
    -- over the art and the swipe, under the glows and texts
    local lvl = f:GetFrameLevel()
    if type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl)) then w:SetFrameLevel(lvl + 3) end
    w:Show()
end

local function PlayAlert(rec, enKey, soundKey)
    local D = NS.DriverCooldown
    if D and D.PlayAlert then D.PlayAlert(rec, enKey, soundKey) end
end

function SI.Paint(e)
    local rec, f, read = e.rec, e.f, e.read
    if not (rec and f and read) then return end
    local Store, Factory = NS.Store, NS.Factory
    local def = SI.Def(rec)
    if f.stackText and Store.Resolve(rec, "text", "stackText") ~= false then
        f.stackText:SetText(SI.Expand(SI.StackTemplate(rec, def), read, rec, def))
    end
    for i = 1, #SUFFIX do PaintLabel(f, i, rec, read, def) end
    PaintSwipe(e, read, def)
    PaintWarn(f, rec, read.cdmWarn == true)
    local spent = SI.Spent(read, def)
    if Factory and Factory.SetState then Factory.SetState(f, rec, spent, spent) end
    -- the "guaranteed next" edge: never on the first paint
    local sure = tonumber(read.chance) ~= nil and read.chance >= 99.95
    if e.sure == false and sure then PlayAlert(rec, "sureSoundEnabled", "sureSound") end
    e.sure = sure
end

function SI.OnUpdate(rec, read)
    local e = SI.live[rec.id]
    if not e then return end
    e.read = read
    SI.Paint(e)
end

function SI.OnProc(rec)
    if not SI.live[rec.id] then return end
    PlayAlert(rec, "procSoundEnabled", "procSound")
end

SI.SINK = { Update = SI.OnUpdate, Proc = SI.OnProc }

-- The cooldown driver's front door. An unknown tracker leaves a plain ready icon.
function SI.Attach(rec, f)
    local SP, Factory = Hub(), NS.Factory
    local e = SI.live[rec.id]
    if not e then
        e = { rec = rec, f = f, id = SI.TrackerID(rec) }
        SI.live[rec.id] = e
    else
        e.rec, e.f, e.id, e.cdKey = rec, f, SI.TrackerID(rec), nil
    end
    if not (SP and SP.Attach(rec, SI.SINK)) then
        if Factory and Factory.SetState then Factory.SetState(f, rec, false) end
        return false
    end
    return true
end

function SI.Detach(id)
    local e = SI.live[id]
    if not e then return end
    SI.live[id] = nil
    -- the frame may serve another icon next
    if e.f and e.f._adSpecialWarn then e.f._adSpecialWarn:Hide() end
    local SP = Hub()
    if SP then SP.Detach(id) end
end

function SI.Refeed(id)
    local e = SI.live[id]
    if not e then return end
    if e.read then SI.Paint(e) else
        local SP = Hub()
        if SP and e.id then SP.Update(e.id) end
    end
end

-- ApplyStyle writes the raw templates back onto the labels; paint them again.
function SI.Restyle(f, rec)
    local e = SI.live[rec.id]
    if e and e.f == f and e.read then SI.Paint(e) end
end

-- The Tracking tab's per-tracker settings live on the driver; the tracker
-- re-reads them on its next gate pass.
function SI.SetDriver(rec, key, value)
    if not (rec and rec.driver) then return end
    if rec.driver[key] == value then return end
    rec.driver[key] = value
    local Store, SP = NS.Store, Hub()
    if Store and Store.Dirty then Store.Dirty("style", rec.id) end
    local id = SI.TrackerID(rec)
    local def = (SP and id) and SP.Get(id) or nil
    if def and SP.Wanted(id) then
        if def.Sync then def.Sync() end
        SP.Update(id)
    end
end

function SI.Reset(rec)
    local SP = Hub()
    local id = SI.TrackerID(rec)
    if SP and id then SP.Reset(id) end
end

-- A readout line for tooltips: the deck, the procs, the chance or the timer.
function SI.Readout(rec)
    local e = SI.live[rec.id]
    local read = e and e.read
    local def = SI.Def(rec)
    if not (read and def) then return "" end
    if def.isTimer then
        if read.active then return ("Cooling down, %d s left"):format(math.floor((tonumber(read.remaining) or 0) + 0.5)) end
        return "Ready"
    end
    local parts = {}
    if tonumber(read.size) and tonumber(read.pos) then
        parts[#parts + 1] = ("Deck %d / %d"):format(read.pos, read.size)
    end
    if tonumber(read.max) and tonumber(read.procs) then
        parts[#parts + 1] = ("procs %d / %d"):format(read.procs, read.max)
    end
    local chance = SI.Expand("{chance}", read, rec, def)
    if chance ~= "" then parts[#parts + 1] = "chance " .. chance end
    return table.concat(parts, ", ")
end

function SI.Tooltip(rec)
    local def = SI.Def(rec)
    GameTooltip:SetText(def and def.name or rec.name or "Special Aura")
    local status = SI.Status(rec)
    if status ~= "" then GameTooltip:AddLine(status, 0.7, 0.7, 0.7) end
    local line = SI.Readout(rec)
    if line ~= "" then GameTooltip:AddLine(line, 1, 1, 1) end
end

-- The sidebar's and cards' one line for a special icon.
function SI.Words(rec)
    local def = SI.Def(rec)
    return "special: " .. (def and def.name or tostring(SI.TrackerID(rec) or "unknown"))
end
