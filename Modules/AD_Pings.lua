-- AD_Pings: the Arc Pings module: ping keys, the ping feed window and ping
-- alerts. Off until switched on, and asleep while the standalone Arc Pings
-- addon is loaded (that addon owns the feature then).
-- Settings: ArcAurasDB.pings, account-wide and sparse (only changes are kept);
-- its chars["Name-Realm"] holds what belongs to one character (the spell list,
-- Auto-Ping). ArcAurasDB.pings.on is the module switch other addons read.
-- The received ping is SECRET in combat: it only ever reaches SetText.
local ADDON, NS = ...
local C_Timer = NS.Perf and NS.Perf.Timers("Pings") or C_Timer   -- /arcperf times what they run
local CreateFrame = NS.Perf and NS.Perf.Frames("Pings") or function(...) return CreateFrame(...) end   -- /arcperf counts each file's frames

local P = {}
NS.Pings = P

local function Tr(s)
    local AT = NS.AT
    if AT and AT.Tr then return AT.Tr(s) end
    return s
end

-- Event subscriptions ride the shared dispatcher, so a stopped module holds none.
local KEY, BOOT, TEARDOWN = "adpings", "adpings_boot", "adpings_teardown"
local function On(ev, fn, key)
    local E = NS.Events
    if E and E.On then E.On(ev, key or KEY, fn) end
end
local function Off(ev, key)
    local E = NS.Events
    if E and E.Off then E.Off(ev, key or KEY) end
end
local function Valid(ev)
    local U = C_EventUtils
    if not (U and U.IsEventValid) then return true end
    return U.IsEventValid(ev) == true
end

-- Gates: on what the client has, never on a build number.
function P.HasAPI()
    local E = Enum and Enum.PingSubjectType
    return (C_Ping and E and E.ActionReady ~= nil) and true or false
end
function P.CanBind()
    return (SecureHandlerWrapScript and RegisterStateDriver and SetOverrideBindingClick
        and ClearOverrideBindings) and true or false
end
-- Asked at call time: the standalone loads after this addon.
function P.Standalone()
    local A = C_AddOns
    if not (A and A.IsAddOnLoaded) then return false end
    return (A.IsAddOnLoaded("ArcPings") or A.IsAddOnLoaded("ArcPingFeed")) and true or false
end
function P.Available() return P.HasAPI() and not P.Standalone() end

-- Settings

P.DEFAULTS = {
    enabled = true,          -- the feed window
    locked = true,
    panelDrag = true,        -- draggable while this page is open, locked or not
    width = 340,
    height = 0,              -- 0 hugs the entries; more keeps it at least that tall
    staticSize = false,      -- always sized for Max entries, on screen when empty
    windowScale = 1,
    showTitle = true,
    rowPadTop = 2, rowPadBottom = 2,
    maxEntries = 8,
    entrySeconds = 12,
    fontSize = 12,
    fontOutline = "OUTLINE",
    showBackground = false,
    showBorder = false,
    bgAlpha = 0.35,
    newestOnTop = true,
    showTimestamp = false,
    showSender = true,
    -- each piece sits left / center / right / top / bottom of the line, or of
    -- another piece it anchors to; the ping text fills what is left
    timePos = "left", timeX = 0, timeY = 0,
    senderPos = "left", senderX = 0, senderY = 0,
    timeAnchorTo = "row", senderAnchorTo = "text",
    timeSize = 0, senderSize = 0, textSize = 0,
    textPos = "center", textX = 0, textY = 0,
    colText = { 0.949, 0.941, 0.925 },
    colTime = { 0.75, 0.83, 0.92 },
    colSender = { 0.7, 0.9, 0.7 },
    colBg = { 0.043, 0.059, 0.102 },
    colBorder = { 0.114, 0.165, 0.247 },
    strata = "MEDIUM",
    animStyle = "pulse",
    animInSecs = 0.3,
    animOutStyle = "fade",
    animOutSecs = 0.4,
    showInWorld = true, showInDungeon = true, showInMythicPlus = true, showInRaid = true,
    showInBattleground = true, showInArena = true, showInScenario = true,
    alertsEnabled = false,
    alertSound = "",
    alertThrottle = 2,
    pkEnabled = true,
    pkOnlySelected = false,   -- by default the ping key works on every bound spell
    pkAutoOn = true,
    pkToggleKey = "",
    pkKey = "",
}
local DEFAULTS = P.DEFAULTS
-- per character: a spell list is one character's bars, and Auto-Ping is
-- flipped mid-fight by a key
local CHAR_ONLY = { pkSpells = true, pkAutoOn = true }

local function DB(create)
    local root = ArcAurasDB
    if type(root) ~= "table" then return nil end
    local t = root.pings
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        root.pings = t
    end
    return t
end

local function CharKey()
    local n = UnitName and UnitName("player") or "?"
    local r = GetRealmName and GetRealmName() or "?"
    return tostring(n) .. "-" .. tostring(r)
end

local function CharDB(create)
    local db = DB(create)
    if not db then return nil end
    local all = db.chars
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}
        db.chars = all
    end
    local k = CharKey()
    local c = all[k]
    if type(c) ~= "table" then
        if not create then return nil end
        c = {}
        all[k] = c
    end
    return c
end

local function Cfg(key)
    local t = CHAR_ONLY[key] and CharDB() or DB()
    if t and t[key] ~= nil then return t[key] end
    return DEFAULTS[key]
end
P.Get = Cfg

local function Same(a, b)
    if type(a) == "table" and type(b) == "table" then
        for i = 1, 4 do if a[i] ~= b[i] then return false end end
        return true
    end
    return a == b
end

function P.IsOn()
    local db = DB()
    return db ~= nil and db.on == true
end

local running = false
local panelOpen = false
function P.Running() return running end

local ApplyAll, PKApply   -- defined below

-- A value equal to its default is stored as nothing.
function P.Set(key, v)
    if CHAR_ONLY[key] then
        local c = CharDB(true)
        if not c then return end
        c[key] = v
    else
        local db = DB(true)
        if not db then return end
        if Same(v, DEFAULTS[key]) then v = nil end
        db[key] = v
    end
    if not running then return end
    ApplyAll()
    if type(key) == "string" and key:sub(1, 2) == "pk" then PKApply() end
end

-- The feed window and its rows

local win
local feedLive = false   -- the feed is on and allowed where the player is
local rows, entries = {}, {}
local entryToken = 0
local ROW_PAD = 2
local SenderDisplay   -- defined with the entries

local function CanDrag()
    return not Cfg("locked") or (panelOpen and Cfg("panelDrag") ~= false)
end

-- The game sends addons no pings while either of its own settings is off.
function P.BlizzOK()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return true end
    local a, b = get("enablePings"), get("showPingsInChat")
    -- a client without these settings has nothing to fix
    if a == nil and b == nil then return true end
    return a == "1" and b == "1"
end
function P.FixBlizz()
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return end
    set("enablePings", "1")
    set("showPingsInChat", "1")
end

local function PosStore() return DB(true) or {} end

-- Offsets from the screen centre. Y is kept on the edge the feed grows away
-- from, the edge that stays put as entries come and go.
function P.SetWindowPos(x, y)
    local cur = Cfg("pos")
    local top = Cfg("newestOnTop") ~= false
    local pos = { (cur and cur[1]) or 0, (cur and cur[2]) or 0,
        top = cur and cur.top, bottom = cur and cur.bottom }
    if x then pos[1] = x end
    if y then
        pos[2] = y
        if top then pos.top = y else pos.bottom = y end
    end
    local db = DB(true)
    if db then db.pos = pos end
    if running then ApplyAll() end
end
function P.WindowPos()
    local p = Cfg("pos")
    if not p then return 0, 0 end
    local top = Cfg("newestOnTop") ~= false
    return p[1] or 0, (top and p.top) or ((not top) and p.bottom) or p[2] or 0
end

-- Pieces: the timestamp, the sender and the ping text, each placed on its own.
local PK_Y = { icon = "iconY", time = "timeY", sender = "senderY", text = "textY" }
local PK_ANCHOR = { icon = "iconAnchorTo", time = "timeAnchorTo", sender = "senderAnchorTo" }
local PK_POS = { icon = "iconPos", time = "timePos", sender = "senderPos", text = "textPos" }
local PK_SIZE = { icon = "iconSize", time = "timeSize", sender = "senderSize", text = "textSize" }

P.PIECES = {
    time = { label = "Timestamp", showKey = "showTimestamp", posKey = "timePos", xKey = "timeX",
        yKey = "timeY", anchorKey = "timeAnchorTo", sizeKey = "timeSize", colorKey = "colTime" },
    sender = { label = "Sender", showKey = "showSender", posKey = "senderPos", xKey = "senderX",
        yKey = "senderY", anchorKey = "senderAnchorTo", sizeKey = "senderSize", colorKey = "colSender" },
    text = { label = "Ping text", posKey = "textPos", xKey = "textX", yKey = "textY",
        sizeKey = "textSize", colorKey = "colText" },
}
P.PIECE_ORDER = { "time", "sender", "text" }

local function PieceHeight(which)
    local v = Cfg(PK_SIZE[which])
    return ((v and v > 0) and v or Cfg("fontSize")) + 2
end

-- Where a piece sits, as (center, height) from the line, following anchors as
-- the placement does, so the entry box always holds it.
local function PieceBand(which, depth)
    depth = (depth or 0) + 1
    local h = PieceHeight(which)
    local y = Cfg(PK_Y[which]) or 0
    if which == "text" or depth > 4 then return y, h end
    local a = Cfg(PK_ANCHOR[which]) or "row"
    if a == "row" or not PK_Y[a] then return y, h end
    local tc, th = PieceBand(a, depth)
    local pos = Cfg(PK_POS[which]) or "left"
    if pos == "top" then return tc + th / 2 + 2 + y + h / 2, h end
    if pos == "bottom" then return tc - th / 2 - 2 + y - h / 2, h end
    return tc + y, h
end

-- How far the shown pieces reach above and below the line.
local function RowExtents()
    local up, down = 0, 0
    local function ext(shown, which)
        if not shown then return end
        local c, h = PieceBand(which)
        if (c + h / 2) > up then up = c + h / 2 end
        if (h / 2 - c) > down then down = h / 2 - c end
    end
    ext(Cfg("showTimestamp"), "time")
    ext(Cfg("showSender"), "sender")
    ext(true, "text")
    return up, down
end

local function RowPads()
    local pt = tonumber(Cfg("rowPadTop")) or 2
    local pb = tonumber(Cfg("rowPadBottom")) or 2
    if pt < 0 then pt = 0 end
    if pb < 0 then pb = 0 end
    return pt, pb
end

local function LayoutRowHeight()
    local up, down = RowExtents()
    local pt, pb = RowPads()
    return math.ceil(up + pt + down + pb)
end

-- UIParent's centre in the window's units: they differ at a window scale.
local function UICenterForWin(w)
    local ux, uy = UIParent:GetCenter()
    if not (ux and uy) then return nil, nil end
    local s = (w:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if not s or s == 0 then s = 1 end
    return ux / s, uy / s
end

local function EnsureWindow()
    if win then return win end
    win = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(false)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if CanDrag() then self:StartMoving() end
    end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UICenterForWin(self)
        if cx and ux then
            -- the edges too: the window re-anchors by its stable edge
            local db = DB(true)
            if db then
                db.pos = { cx - ux, cy - uy,
                    top = (self:GetTop() or cy) - uy,
                    bottom = (self:GetBottom() or cy) - uy }
            end
            if P.notify then P.notify() end
        end
    end)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    -- nothing renders outside the box
    win:SetClipsChildren(true)
    -- the visible edge sits above the rows, so content never covers it
    win.edge = CreateFrame("Frame", nil, win, "BackdropTemplate")
    win.edge:SetAllPoints(win)
    win.edge:SetFrameLevel(win:GetFrameLevel() + 40)
    win.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win.edge:EnableMouse(false)
    -- the title floats above the window: inside, the clip would cut it
    win.titleHolder = CreateFrame("Frame", nil, UIParent)
    win.titleHolder:SetSize(140, 16)
    win.titleHolder:SetPoint("BOTTOM", win, "TOP", 0, 2)
    win.titleHolder:Hide()
    win.title = win.titleHolder:CreateFontString(nil, "OVERLAY")
    win.title:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    win.title:SetPoint("CENTER", 0, 0)
    win.title:SetAlpha(0.85)
    local AT = NS.AT
    win.title:SetText(AT and AT.Brand and AT.Brand("Arc", " Pings") or "Arc Pings")
    win:HookScript("OnShow", function(self) self.titleHolder:SetShown(self._titleWanted and true or false) end)
    win:HookScript("OnHide", function(self) self.titleHolder:Hide() end)
    return win
end

local function EnsureRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, EnsureWindow())
    -- the pieces' Y offsets are measured from this invisible line
    r.line = CreateFrame("Frame", nil, r)
    r.line:SetHeight(1)
    r.time = r:CreateFontString(nil, "OVERLAY")
    r.time:SetJustifyH("LEFT")
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.sender = r:CreateFontString(nil, "OVERLAY")
    r.sender:SetJustifyH("RIGHT")
    -- a font before the first SetText
    local size = Cfg("fontSize")
    r.time:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    r.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    r.sender:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    rows[i] = r
    return r
end

-- A width that may be secret (secret text measures secret): a guess then.
local function SafeWidth(fs, fallback)
    local w
    if fs.GetUnboundedStringWidth then w = fs:GetUnboundedStringWidth()
    elseif fs.GetStringWidth then w = fs:GetStringWidth() end
    if w == nil or (issecretvalue and issecretvalue(w)) then return fallback end
    return w
end

-- Every piece anchors to the line's edge or to another piece; the ping text
-- spans what is left between the pieces on its line.
local function ApplyRowLayout(r)
    local size = Cfg("fontSize")
    local outline = Cfg("fontOutline")
    if outline == "NONE" then outline = "" end
    local font = STANDARD_TEXT_FONT
    local tsz = Cfg("timeSize"); tsz = (tsz and tsz > 0) and tsz or size
    local ssz = Cfg("senderSize"); ssz = (ssz and ssz > 0) and ssz or size
    local xsz = Cfg("textSize"); xsz = (xsz and xsz > 0) and xsz or size
    r.time:SetFont(font, tsz, outline)
    r.text:SetFont(font, xsz, outline)
    r.sender:SetFont(font, ssz, outline)
    local ct = Cfg("colText")
    r.text:SetTextColor(ct[1], ct[2], ct[3])
    local cti = Cfg("colTime")
    r.time:SetTextColor(cti[1], cti[2], cti[3])
    -- a readable sender is drawn again, so changes reach rows on screen
    if r._senderClean then r.sender:SetText(SenderDisplay(r._senderClean)) end
    local cs = Cfg("colSender")
    r.sender:SetTextColor(cs[1], cs[2], cs[3])

    local showTime, showSender = Cfg("showTimestamp"), Cfg("showSender")
    r.time:SetShown(showTime)
    r.sender:SetShown(showSender)
    r.time:ClearAllPoints()
    r.sender:ClearAllPoints()
    r.text:ClearAllPoints()

    -- a piece pushes the text only while it shares the text's line
    local textBandY = Cfg("textY") or 0
    local band = xsz + 4
    local leftExtent, rightExtent = 0, 0
    if r.line then
        local upExt = RowExtents()
        local padT = RowPads()
        r.line:ClearAllPoints()
        r.line:SetPoint("LEFT", r, "TOPLEFT", 0, -(upExt + padT))
        r.line:SetPoint("RIGHT", r, "TOPRIGHT", 0, -(upExt + padT))
    end
    local L = r.line or r

    local PC = {
        time = { el = r.time, shown = showTime, pos = Cfg("timePos"), x = Cfg("timeX") or 0,
            y = Cfg("timeY") or 0, w = SafeWidth(r.time, 44), anchor = Cfg("timeAnchorTo") or "row" },
        sender = { el = r.sender, shown = showSender, pos = Cfg("senderPos"), x = Cfg("senderX") or 0,
            y = Cfg("senderY") or 0, w = SafeWidth(r.sender, 60), anchor = Cfg("senderAnchorTo") or "row" },
    }
    -- each piece's side, reach and height, through its anchor chain (a cycle
    -- or a hidden target falls back to free placement)
    local eff = {}
    local function Resolve(key, visited)
        if eff[key] then return eff[key] end
        local pc = PC[key]
        visited = visited or {}
        local a = pc.anchor
        if visited[key] then a = "row" end
        visited[key] = true
        local sideExtent = (pc.pos == "left" or pc.pos == "right") and (pc.x + pc.w) or nil
        if a == "row" then
            eff[key] = { mode = "row", side = pc.pos, extent = sideExtent, y = pc.y }
        elseif a == "text" then
            eff[key] = { mode = "text", side = Cfg("textPos") or "left", extent = nil, y = (Cfg("textY") or 0) + pc.y }
        elseif PC[a] and PC[a].shown then
            local te = Resolve(a, visited)
            local grows = (pc.pos == "left" or pc.pos == "right")
                and ((te.side == "right") and (pc.pos == "left") or (te.side ~= "right") and (pc.pos == "right"))
            local extent = te.extent and (grows and (te.extent + 4 + pc.x + pc.w) or te.extent) or nil
            eff[key] = { mode = "piece", target = PC[a].el, side = te.side, extent = extent, y = te.y + pc.y }
        elseif PC[a] then
            -- a hidden target: the piece takes the target's side of the line
            local te = Resolve(a, visited)
            local side = te.side or pc.pos
            local ext = (side == "left" or side == "right") and (pc.x + pc.w) or nil
            eff[key] = { mode = "row", side = side, extent = ext, y = pc.y }
        else
            eff[key] = { mode = "row", side = pc.pos, extent = sideExtent, y = pc.y }
        end
        return eff[key]
    end

    local deferred = {}
    for _, key in ipairs({ "time", "sender" }) do
        local pc = PC[key]
        if pc.shown then
            local e = Resolve(key)
            local el = pc.el
            if e.mode == "text" then
                deferred[#deferred + 1] = { pc = pc, e = e }
            elseif e.mode == "row" then
                local sidePos = e.side or pc.pos
                if sidePos == "right" then
                    el:SetPoint("RIGHT", L, "RIGHT", -pc.x, pc.y)
                elseif sidePos == "center" then
                    el:SetPoint("CENTER", L, "CENTER", pc.x, pc.y)
                elseif sidePos == "top" then
                    el:SetPoint("TOP", r, "TOP", pc.x, math.min(0, pc.y))
                elseif sidePos == "bottom" then
                    el:SetPoint("BOTTOM", r, "BOTTOM", pc.x, math.max(0, pc.y))
                else
                    el:SetPoint("LEFT", L, "LEFT", pc.x, pc.y)
                end
            else
                local tel = e.target
                if pc.pos == "right" then
                    el:SetPoint("LEFT", tel, "RIGHT", 4 + pc.x, pc.y)
                elseif pc.pos == "center" then
                    el:SetPoint("CENTER", tel, "CENTER", pc.x, pc.y)
                elseif pc.pos == "top" then
                    el:SetPoint("BOTTOM", tel, "TOP", pc.x, 2 + pc.y)
                elseif pc.pos == "bottom" then
                    el:SetPoint("TOP", tel, "BOTTOM", pc.x, -2 + pc.y)
                else
                    el:SetPoint("RIGHT", tel, "LEFT", -(4 + pc.x), pc.y)
                end
            end
            local j = (e.mode == "row") and (e.side or pc.pos) or pc.pos
            el:SetJustifyH((j == "right") and "RIGHT" or (j == "left") and "LEFT" or "CENTER")
            if e.extent and math.abs((e.y or 0) - textBandY) < band then
                if e.side == "right" then
                    if e.extent > rightExtent then rightExtent = e.extent end
                elseif e.extent > leftExtent then
                    leftExtent = e.extent
                end
            end
        end
    end

    local ty = Cfg("textY") or 0
    local li = leftExtent + ((leftExtent > 0) and 5 or 0)
    local ri = rightExtent + ((rightExtent > 0) and 5 or 0)
    local tx = Cfg("textX") or 0
    local tpos = Cfg("textPos")
    local rightSide = tpos == "right"
    local centerText = tpos == "center"
    if rightSide then
        if tx > ri then ri = tx end
        r.text:SetJustifyH("RIGHT")
    elseif centerText then
        r.text:SetJustifyH("CENTER")
    else
        if tx > li then li = tx end
        r.text:SetJustifyH("LEFT")
    end
    -- a line too long for the span ends in "..." inside the box
    local needed = SafeWidth(r.text, nil)
    local avail = (r:GetWidth() or 0) - li - ri
    r._neededW = needed and (li + needed + ri) or nil
    if centerText and not (needed and needed > avail) then
        r.text:SetPoint("CENTER", L, "CENTER", tx, ty)
    else
        r.text:SetPoint("LEFT", L, "LEFT", li, ty)
        r.text:SetPoint("RIGHT", L, "RIGHT", -ri, ty)
    end

    -- pieces anchored to the text sit on its glyphs; secret text cannot be
    -- measured, so they sit on its span then, every side handled
    if #deferred > 0 then
        local rowW = r:GetWidth() or 0
        local tw = SafeWidth(r.text, nil)
        local gL, gR
        if tw then
            if rightSide then
                gR = rowW - ri; gL = gR - tw
            elseif centerText then
                local mid = rowW / 2 + tx
                gL, gR = mid - tw / 2, mid + tw / 2
            else
                gL = li; gR = gL + tw
            end
        end
        for _, d in ipairs(deferred) do
            local pc, e = d.pc, d.e
            local el = pc.el
            local ey = e.y or 0
            if not gL then
                if pc.pos == "right" then
                    el:SetPoint("LEFT", r.text, "RIGHT", 4 + pc.x, pc.y)
                elseif pc.pos == "top" then
                    el:SetPoint("BOTTOM", r.text, "TOP", pc.x, 2 + pc.y)
                elseif pc.pos == "bottom" then
                    el:SetPoint("TOP", r.text, "BOTTOM", pc.x, -2 + pc.y)
                elseif pc.pos == "center" then
                    el:SetPoint("CENTER", r.text, "CENTER", pc.x, pc.y)
                else
                    el:SetPoint("RIGHT", r.text, "LEFT", -(4 + pc.x), pc.y)
                end
            elseif pc.pos == "right" then
                el:SetPoint("LEFT", L, "LEFT", gR + 4 + pc.x, ey)
            elseif pc.pos == "center" then
                el:SetPoint("CENTER", L, "LEFT", (gL + gR) / 2 + pc.x, ey)
            elseif pc.pos == "top" then
                el:SetPoint("BOTTOM", L, "LEFT", (gL + gR) / 2 + pc.x, ty + xsz / 2 + 2 + pc.y)
            elseif pc.pos == "bottom" then
                el:SetPoint("TOP", L, "LEFT", (gL + gR) / 2 + pc.x, ty - xsz / 2 - 2 + pc.y)
            else
                el:SetPoint("RIGHT", L, "LEFT", gL - 4 - pc.x, ey)
            end
        end
    end
end

local function Render()
    if not win then return end
    local width = Cfg("width")
    local rowH = LayoutRowHeight()
    local top = Cfg("newestOnTop")
    local n = #entries
    local function LayoutRows(w)
        local maxNeed = w
        for _, e in ipairs(entries) do
            local r = e.row
            if r then
                r:SetSize(w - 12, rowH)
                ApplyRowLayout(r)
                if r._neededW and r._neededW + 12 > maxNeed then maxNeed = r._neededW + 12 end
            end
        end
        return maxNeed
    end
    -- a readable line never truncates: the window widens for it, then returns
    local need = LayoutRows(width)
    if need > width then
        width = math.ceil(need)
        LayoutRows(width)
    end
    -- keep the edge the feed grows away from where it is across the resize
    local ux, uy = UICenterForWin(win)
    local wcx = win:GetCenter()
    local edgeY = top and win:GetTop() or win:GetBottom()
    -- right after a re-anchor the live geometry is last frame's: trust the store
    if win._arcPosDirty then
        win._arcPosDirty = nil
        local sp = PosStore().pos
        if sp and ux and uy then
            wcx = (sp[1] or 0) + ux
            local se = top and sp.top or sp.bottom
            edgeY = se and (se + uy) or edgeY
        end
    end
    local padTop = 6
    local staticBox = Cfg("staticSize")
    local rowsFor = staticBox and (Cfg("maxEntries") or 8) or math.max(1, n)
    local autoH = rowsFor * (rowH + ROW_PAD) + padTop + 6
    local hBase = tonumber(Cfg("height")) or 0
    win:SetSize(width, (hBase > autoH) and hBase or autoH)
    if wcx and edgeY and ux then
        win:ClearAllPoints()
        if top then
            win:SetPoint("TOP", UIParent, "CENTER", wcx - ux, edgeY - uy)
        else
            win:SetPoint("BOTTOM", UIParent, "CENTER", wcx - ux, edgeY - uy)
        end
        local pos = PosStore().pos
        if pos then
            local t, b = win:GetTop(), win:GetBottom()
            if t then pos.top = t - uy end
            if b then pos.bottom = b - uy end
        end
    end
    -- an entry expiring after Show In hid the feed must not bring it back
    win:SetShown(feedLive and (n > 0 or not Cfg("locked") or panelOpen or staticBox) and true or false)
    -- rows hug the stable edge, so entries on screen never move
    for i, e in ipairs(entries) do
        local r = e.row
        if r then
            r:ClearAllPoints()
            if top then
                r:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -padTop - (i - 1) * (rowH + ROW_PAD))
            else
                r:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 6, 6 + (i - 1) * (rowH + ROW_PAD))
            end
            r:Show()
        end
    end
end

local function FreeRow(r)
    if not r then return end
    if r.fadeOutAG then r.fadeOutAG:Stop() end
    r._onFadeOutDone = nil
    r:Hide()
    r:SetAlpha(1)
    r.free = true
end

local function FinalizeRemove(token)
    for i, e in ipairs(entries) do
        if e.token == token then
            FreeRow(e.row)
            table.remove(entries, i)
            Render()
            return
        end
    end
end

-- Row animations play on our own frames, so they run in combat too.
local function EnsureRowAnims(r)
    if r.pulseAG then return end
    r.pulseAG = r:CreateAnimationGroup()
    local up = r.pulseAG:CreateAnimation("Scale")
    up:SetOrder(1); up:SetScale(1.12, 1.12); up:SetDuration(0.12)
    local down = r.pulseAG:CreateAnimation("Scale")
    down:SetOrder(2); down:SetScale(1 / 1.12, 1 / 1.12); down:SetDuration(0.18)
    r.pulseUp, r.pulseDown = up, down
    r.flashAG = r:CreateAnimationGroup()
    r.flashSteps = {}
    for i = 1, 2 do
        local dim = r.flashAG:CreateAnimation("Alpha")
        dim:SetOrder(i * 2 - 1); dim:SetFromAlpha(1); dim:SetToAlpha(0.25); dim:SetDuration(0.1)
        local bright = r.flashAG:CreateAnimation("Alpha")
        bright:SetOrder(i * 2); bright:SetFromAlpha(0.25); bright:SetToAlpha(1); bright:SetDuration(0.1)
        r.flashSteps[#r.flashSteps + 1] = dim
        r.flashSteps[#r.flashSteps + 1] = bright
    end
    r.fadeInAG = r:CreateAnimationGroup()
    r.fadeInA = r.fadeInAG:CreateAnimation("Alpha")
    r.fadeInA:SetFromAlpha(0); r.fadeInA:SetToAlpha(1)
    r.fadeInA:SetDuration(0.3); r.fadeInA:SetSmoothing("OUT")
    r.zoomAG = r:CreateAnimationGroup()
    local z1 = r.zoomAG:CreateAnimation("Scale")
    z1:SetOrder(1); z1:SetScaleFrom(0.7, 0.7); z1:SetScaleTo(1.15, 1.15)
    z1:SetDuration(0.12); z1:SetSmoothing("OUT")
    local z2 = r.zoomAG:CreateAnimation("Scale")
    z2:SetOrder(2); z2:SetScaleFrom(1.15, 1.15); z2:SetScaleTo(1.0, 1.0)
    z2:SetDuration(0.08); z2:SetSmoothing("IN")
    local zi = r.zoomAG:CreateAnimation("Alpha")
    zi:SetOrder(1); zi:SetFromAlpha(0); zi:SetToAlpha(1); zi:SetDuration(0.12)
    r.zoom1, r.zoom2, r.zoomIn = z1, z2, zi
    r.fadeOutAG = r:CreateAnimationGroup()
    r.fadeOutA = r.fadeOutAG:CreateAnimation("Alpha")
    r.fadeOutA:SetFromAlpha(1); r.fadeOutA:SetToAlpha(0)
    r.fadeOutA:SetDuration(0.4); r.fadeOutA:SetSmoothing("OUT")
    r.fadeOutAG:SetScript("OnFinished", function()
        local cb = r._onFadeOutDone
        r._onFadeOutDone = nil
        if cb then cb() end
    end)
end

local function RemoveEntry(token)
    for _, e in ipairs(entries) do
        if e.token == token then
            local r = e.row
            if r and r:IsShown() and Cfg("animOutStyle") == "fade" then
                EnsureRowAnims(r)
                if not r.fadeOutAG:IsPlaying() then
                    r.fadeOutA:SetDuration(math.max(0.05, tonumber(Cfg("animOutSecs")) or 0.4))
                    r._onFadeOutDone = function() FinalizeRemove(token) end
                    r.fadeOutAG:Play()
                end
            else
                FinalizeRemove(token)
            end
            return
        end
    end
end

local function ClaimRow()
    for i = 1, Cfg("maxEntries") do
        local r = EnsureRow(i)
        if r.free or not r.claimed then
            r.free, r.claimed = false, true
            return r
        end
    end
    local oldest = entries[#entries]
    if oldest then
        table.remove(entries, #entries)
        return oldest.row
    end
    return EnsureRow(1)
end

local function PlayNewPingAnim(r)
    EnsureRowAnims(r)
    -- a row taken mid-expiry comes back to full life
    r.fadeOutAG:Stop(); r._onFadeOutDone = nil; r:SetAlpha(1)
    local style = Cfg("animStyle")
    if style == "none" then return end
    r.pulseAG:Stop(); r.flashAG:Stop(); r.fadeInAG:Stop(); r.zoomAG:Stop()
    local D = math.max(0.05, tonumber(Cfg("animInSecs")) or 0.3)
    if style == "flash" then
        for _, a in ipairs(r.flashSteps) do a:SetDuration(D / #r.flashSteps) end
        r.flashAG:Play()
    elseif style == "fade" then
        r.fadeInA:SetDuration(D)
        r.fadeInAG:Play()
    elseif style == "zoom" then
        r.zoom1:SetDuration(D * 0.6)
        r.zoomIn:SetDuration(D * 0.6)
        r.zoom2:SetDuration(D * 0.4)
        r.zoomAG:Play()
    else
        r.pulseUp:SetDuration(D * 0.4)
        r.pulseDown:SetDuration(D * 0.6)
        r.pulseAG:Play()
    end
end

-- Alerts: the ping's arrival is never secret, so the sound plays in combat.
local lastAlertAt
local function FireAlerts()
    if not Cfg("alertsEnabled") then return end
    local now = GetTime()
    if lastAlertAt and (now - lastAlertAt) < (tonumber(Cfg("alertThrottle")) or 0) then return end
    lastAlertAt = now
    P.PlaySound(Cfg("alertSound"))
end

function P.PlaySound(name)
    local S = NS.Sounds
    if type(name) == "string" and name ~= "" and S and S.Play then S.Play(name, "Master") end
end

-- The sender arrives as a player link; only a readable one is cleaned.
local function CleanSenderName(sender)
    if sender == nil then return nil end
    if issecretvalue and issecretvalue(sender) then return nil end
    if type(sender) ~= "string" then return nil end
    return sender:match("|Hplayer:([^:|%]]+)") or sender
end

SenderDisplay = function(cleanName)
    if not cleanName then return "" end
    return Ambiguate and Ambiguate(cleanName, "short") or cleanName
end

local function RemovePreviewEntries()
    local removed = false
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e.preview then
            FreeRow(e.row)
            table.remove(entries, i)
            removed = true
        end
    end
    return removed
end

-- The payload is handed to SetText as it came and nothing else ever reads it:
-- in combat it is secret, and SetText is the one thing that takes it.
local function AddEntry(text, sender, isPreview)
    if not (running and feedLive and win) then return end
    if not isPreview then RemovePreviewEntries() end
    entryToken = entryToken + 1
    local token = entryToken
    local r = ClaimRow()
    r.time:SetText(date and date("%H:%M:%S") or "")
    if text ~= nil then r.text:SetText(text) else r.text:SetText("") end
    local cleanName = CleanSenderName(sender)
    r._senderClean = cleanName
    if not cleanName then
        if sender ~= nil then r.sender:SetText(sender) else r.sender:SetText("") end
    end
    table.insert(entries, 1, { token = token, row = r, preview = isPreview or nil })
    while #entries > Cfg("maxEntries") do
        local e = table.remove(entries, #entries)
        FreeRow(e.row)
    end
    Render()
    PlayNewPingAnim(r)
    if isPreview then return end
    FireAlerts()
    -- our own clock, never the payload, decides when a line goes
    local life = tonumber(Cfg("entrySeconds"))
    if life and life > 0 then
        C_Timer.After(life, function() RemoveEntry(token) end)
    end
end

-- The sample line: a spell the player has, in the longest callout the game sends.
local previewSpellID, previewSpec
local function PreviewSpellID()
    local csi = C_SpecializationInfo
    local spec = (csi and csi.GetSpecialization and csi.GetSpecialization())
        or (GetSpecialization and GetSpecialization()) or 0
    if previewSpellID and previewSpec == spec then return previewSpellID end
    previewSpec = spec
    local sb = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (sb and sb.GetNumSpellBookSkillLines and bank) then
        previewSpellID = nil
        return nil
    end
    local specPick, anyPick
    for line = 1, (sb.GetNumSpellBookSkillLines() or 0) do
        local info = sb.GetSpellBookSkillLineInfo(line)
        if info and not info.isGuild and not info.offSpecID then
            local first = (info.itemIndexOffset or 0) + 1
            local last = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
            for slot = first, last do
                local item = sb.GetSpellBookItemInfo(slot, bank)
                if item and item.spellID and not item.isPassive and not item.isOffSpec then
                    anyPick = item.spellID
                    if info.specID then specPick = item.spellID end
                end
            end
        end
    end
    previewSpellID = specPick or anyPick
    return previewSpellID
end

local function PreviewText()
    local id = PreviewSpellID()
    local name
    if id then
        local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id) -- raw-id: a spellbook sample line
        if type(link) == "string" then return Tr("%s will be ready in 0:12!"):format(link) end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id) -- raw-id: a spellbook sample line
        name = info and info.name
    end
    return Tr("%s will be ready in 0:12!"):format("|cff71d5ff[" .. (name or Tr("Your Cooldown")) .. "]|r")
end

local function ShowPreviewEntry()
    RemovePreviewEntries()
    if #entries > 0 then Render() return end
    AddEntry(PreviewText(), UnitName and UnitName("player"), true)
end

function P.TestPing()
    if not (running and feedLive and win) then return false end
    AddEntry(PreviewText(), UnitName and UnitName("player"))
    return true
end

-- Which Show In switch covers where the player stands.
local function CurrentContent()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        local cm = C_ChallengeMode
        if cm and cm.IsChallengeModeActive and cm.IsChallengeModeActive() then return "showInMythicPlus" end
        return "showInDungeon"
    elseif instanceType == "raid" then return "showInRaid"
    elseif instanceType == "pvp" then return "showInBattleground"
    elseif instanceType == "arena" then return "showInArena"
    elseif instanceType == "scenario" then return "showInScenario"
    end
    return "showInWorld"
end
P.CurrentContent = CurrentContent

local function OnPing(_, text, sender)
    AddEntry(text, sender)
end

ApplyAll = function()
    if not running then return end
    -- an off feed, or one this content type hides, does not listen either
    local live = (Cfg("enabled") and Cfg(CurrentContent()) ~= false and Valid("CHAT_MSG_PING")) and true or false
    feedLive = live
    if live then
        On("CHAT_MSG_PING", OnPing)
    else
        Off("CHAT_MSG_PING")
        if win then win:Hide() end
        return
    end
    local w = EnsureWindow()
    local pos = PosStore().pos
    -- a scale change keeps the window where it is on screen
    local newScale = tonumber(Cfg("windowScale")) or 1
    if newScale <= 0 then newScale = 1 end
    local oldScale = w._appliedScale or newScale
    if pos and oldScale ~= newScale then
        local f = oldScale / newScale
        pos[1] = (pos[1] or 0) * f
        pos[2] = (pos[2] or 0) * f
        if pos.top then pos.top = pos.top * f end
        if pos.bottom then pos.bottom = pos.bottom * f end
    end
    w._appliedScale = newScale
    w:SetScale(newScale)
    w:ClearAllPoints()
    if pos and Cfg("newestOnTop") and pos.top then
        w:SetPoint("TOP", UIParent, "CENTER", pos[1], pos.top)
    elseif pos and not Cfg("newestOnTop") and pos.bottom then
        w:SetPoint("BOTTOM", UIParent, "CENTER", pos[1], pos.bottom)
    elseif pos then
        w:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
    else
        w:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
    w:EnableMouse(CanDrag())
    w:SetFrameStrata(Cfg("strata"))
    local cbg = Cfg("colBg")
    w:SetBackdropColor(cbg[1], cbg[2], cbg[3], Cfg("showBackground") and Cfg("bgAlpha") or 0)
    w:SetBackdropBorderColor(0, 0, 0, 0)
    -- unlocked shows the accent edge as a placement aid
    if not Cfg("locked") then
        w.edge:SetBackdropBorderColor(0.247, 0.788, 0.949, 1)
    elseif Cfg("showBorder") then
        local cbo = Cfg("colBorder")
        w.edge:SetBackdropBorderColor(cbo[1], cbo[2], cbo[3], 1)
    else
        w.edge:SetBackdropBorderColor(0, 0, 0, 0)
    end
    w._titleWanted = (not Cfg("locked") or panelOpen) and Cfg("showTitle") ~= false
    w.titleHolder:SetFrameStrata(Cfg("strata"))
    w.titleHolder:SetScale(newScale)
    w._arcPosDirty = true
    Render()
    w.titleHolder:SetShown((w._titleWanted and w:IsShown()) and true or false)
end
P.ApplyAll = function() ApplyAll() end

-- While this module's page is open the window shows, with a sample line.
function P.SetPanelOpen(open)
    open = open and true or false
    if panelOpen == open then return end
    panelOpen = open
    if not running then return end
    if open then
        ApplyAll()
        ShowPreviewEntry()
    else
        RemovePreviewEntries()
        ApplyAll()
    end
end
function P.PanelOpen() return panelOpen end

-- The layout's pieces back to how they ship.
local LAYOUT_KEYS = { "showTimestamp", "showSender", "rowPadTop", "rowPadBottom",
    "timePos", "timeX", "timeY", "timeAnchorTo", "timeSize",
    "senderPos", "senderX", "senderY", "senderAnchorTo", "senderSize",
    "textPos", "textX", "textY", "textSize" }
function P.ResetLayout()
    local db = DB()
    if db then for _, k in ipairs(LAYOUT_KEYS) do db[k] = nil end end
    if running then ApplyAll() end
end
function P.ResetPiece(key)
    local pc = P.PIECES[key]
    local db = DB()
    if not (pc and db) then return end
    for _, f in ipairs({ "posKey", "xKey", "yKey", "anchorKey", "sizeKey", "colorKey" }) do
        if pc[f] then db[pc[f]] = nil end
    end
    if running then ApplyAll() end
end

-- PING KEYS: hold the ping key and press a spell's own key to ping it, or let
-- a spell ping each time its key is pressed, or give it a key that only pings.
-- /pingspell is a secure slash command: it runs only from a secure button's
-- macro, so every key goes to a relay button. In combat Lua may not write a
-- binding or a secure attribute, so the swap happens in secure snippets and
-- every Lua-side write waits for the end of combat.

local PK_MAX = 12        -- picked spells, and the first relays
local PK_ALL = 60        -- relays for "every bound spell"
local PK_MACRO = 120     -- account macros come first, character macros after
P.PK_MAX = PK_MAX

local pkBindOwner, pkAlwaysOwner, pkGateHeader, pkAutoHolder
local pkRelays, pkHolders, pkHolderN = {}, {}, 0
local pkDirty = false
local pkArmed, pkSkipped = 0, 0
local PK = {}
P.PK = PK

local NO_LIST = {}
-- Reading never creates the table; a write does.
local function PKList(create)
    local c = CharDB(create)
    if c and type(c.pkSpells) == "table" then return c.pkSpells end
    if not create then return NO_LIST end
    c.pkSpells = {}
    return c.pkSpells
end
PK.List = function() return PKList(false) end

local function PushCmd(t, seen, v)
    if type(v) ~= "string" or v == "" or seen[v] then return end
    seen[v] = true
    t[#t + 1] = v
end

-- Every binding command a bar button may answer to, the bar addon's own first.
local function ButtonCommands(btn)
    if not btn then return nil end
    local out, seen = {}, {}
    local cfg = type(btn.config) == "table" and btn.config or nil
    if cfg and type(btn.GetBindingAction) == "function" then PushCmd(out, seen, btn:GetBindingAction()) end
    PushCmd(out, seen, btn.bindingAction)
    PushCmd(out, seen, btn.commandName)
    PushCmd(out, seen, btn.keyBoundTarget)
    PushCmd(out, seen, cfg and cfg.keyBoundTarget)
    local name = btn.GetName and btn:GetName()
    if type(name) == "string" then
        local cb = (cfg and type(cfg.keyBoundClickButton) == "string") and cfg.keyBoundClickButton
        PushCmd(out, seen, "CLICK " .. name .. ":" .. (cb or "Keybind"))
        PushCmd(out, seen, "CLICK " .. name .. ":Keybind")
        PushCmd(out, seen, "CLICK " .. name .. ":LeftButton")
    end
    return out
end

-- key, command; the command even when unbound, to re-resolve later
local function PKKeyForButton(btn)
    local cmds = ButtonCommands(btn)
    if not cmds or #cmds == 0 then return nil, nil end
    for i = 1, #cmds do
        local k = GetBindingKey(cmds[i])
        if k and k ~= "" then return k, cmds[i] end
    end
    return nil, cmds[1]
end

-- A bar addon leaves the buttons it replaced with a frozen action: never theirs.
local function PKLiveButton(name)
    local btn = type(name) == "string" and _G[name]
    if type(btn) ~= "table" or type(btn.GetObjectType) ~= "function" then return nil end
    if btn.GetAttribute and btn:GetAttribute("statehidden") then return nil end
    return btn
end

local BTN_NAMES
local function ButtonNames()
    if BTN_NAMES then return BTN_NAMES end
    local list = {}
    for _, bar in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15 }) do
        for i = 1, 12 do list[#list + 1] = "ElvUI_Bar" .. bar .. "Button" .. i end
    end
    for i = 1, 180 do list[#list + 1] = "BT4Button" .. i end
    for i = 1, 180 do list[#list + 1] = "EABButton" .. i end
    for _, b in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
        for i = 1, 12 do list[#list + 1] = b .. i end
    end
    BTN_NAMES = list
    return list
end

-- Every action button we can find, from the button library's own registry and
-- by name, sorted so the scan is the same each time.
local function PKCollectButtons()
    local out, seen = {}, {}
    local function take(f)
        if type(f) ~= "table" or seen[f] or type(f.GetObjectType) ~= "function" then return end
        if f.GetAttribute and f:GetAttribute("statehidden") then return end
        seen[f] = true
        out[#out + 1] = f
    end
    if LibStub and type(LibStub.libs) == "table" then
        for major, lib in pairs(LibStub.libs) do
            if type(major) == "string" and major:find("^LibActionButton%-1%.0")
                and type(lib) == "table" and type(lib.GetAllButtons) == "function" then
                for b in pairs(lib:GetAllButtons()) do take(b) end
            end
        end
    end
    for _, n in ipairs(ButtonNames()) do take(_G[n]) end
    table.sort(out, function(a, b)
        local an = (a.GetName and a:GetName()) or ""
        local bn = (b.GetName and b:GetName()) or ""
        return tostring(an) < tostring(bn)
    end)
    return out
end
PK.CollectButtons = PKCollectButtons

-- What a bar button holds as a ping subject: id, command, "spell" | "item", name.
local function PKButtonSubject(btn)
    local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
    if type(slot) ~= "number" or not HasAction(slot) then return nil end
    local aType, id = GetActionInfo(slot)
    local kind, sid
    if aType == "spell" then
        kind, sid = "spell", id
    elseif aType == "item" then
        kind, sid = "item", id
    elseif aType == "macro" then
        if C_ActionBar and C_ActionBar.GetSpell then
            local s = C_ActionBar.GetSpell(slot)
            if type(s) == "number" and s > 0 then kind, sid = "spell", s end
        end
        if not sid and GetMacroSpell then
            local ms = GetMacroSpell(id)
            if ms then kind, sid = "spell", ms end
        end
        if not sid and GetMacroItem and C_Item and C_Item.GetItemInfoInstant then
            local _, mlink = GetMacroItem(id)
            local iid = mlink and C_Item.GetItemInfoInstant(mlink)
            if iid then kind, sid = "item", iid end
        end
    end
    if not sid and C_ActionBar and C_ActionBar.GetSpell then
        local s = C_ActionBar.GetSpell(slot)
        if type(s) == "number" and s > 0 then kind, sid = "spell", s end
    end
    if type(sid) ~= "number" then return nil end
    local _, cmd = PKKeyForButton(btn)
    return sid, cmd, kind, btn.GetName and btn:GetName() or nil
end

-- The half of an override pair that is live now, from either half.
local function PKLiveSpellID(id)
    if type(id) ~= "number" then return id end
    local sid = id
    if C_Spell and C_Spell.GetBaseSpell then
        local b = C_Spell.GetBaseSpell(sid) -- raw-id: a live bar slot's spell
        if type(b) == "number" and b > 0 then sid = b end
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        local o = C_Spell.GetOverrideSpell(sid) -- raw-id: a live bar slot's spell
        if type(o) == "number" and o > 0 then sid = o end
    end
    return sid
end

local function PKSubjectInfo(entry)
    if entry.kind == "item" then
        local nm = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id)
        local ic = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
        return nm or Tr("Item %d"):format(entry.id), ic or 134400
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(PKLiveSpellID(entry.id)) -- raw-id: a live bar slot's spell
    return (info and info.name) or Tr("Spell %d"):format(entry.id), (info and info.iconID) or 134400
end
PK.SubjectInfo = PKSubjectInfo

-- /pingspell takes a literal ID: the live half of an override pair.
local function PKPingLine(entry)
    if entry.kind == "item" then return "/pingitem " .. entry.id end
    return "/pingspell " .. PKLiveSpellID(entry.id)
end

-- Any button that holds the spell, for an entry with no button of its own.
local function PKAutoKey(spellID)
    for _, b in ipairs(PKCollectButtons()) do
        if PKButtonSubject(b) == spellID then
            local k = PKKeyForButton(b)
            if k then return k end
        end
    end
    return nil
end

-- A command survives a spec change, the spell in its slot does not: never arm
-- an entry whose bar slot holds something else now.
local function PKEntryMatchesBar(entry)
    if not entry then return false end
    local btn = PKLiveButton(entry.btn)
    if not btn then return true end
    local sid = PKButtonSubject(btn)
    if not sid then return false end
    if sid == entry.id then return true end
    if entry.kind == "item" then return false end
    return PKLiveSpellID(sid) == PKLiveSpellID(entry.id)
end
PK.MatchesBar = PKEntryMatchesBar

-- The live button first, then the stored command, then a scan of the bars.
local function PKKeyFor(entry)
    local btn = PKLiveButton(entry.btn)
    if btn then
        local k = PKKeyForButton(btn)
        if k then return k end
    end
    if entry.cmd then
        local k = GetBindingKey(entry.cmd)
        if k and k ~= "" then return k end
    end
    return PKAutoKey(entry.id)
end

local function PKPingKeyFor(entry)
    local k = entry and entry.pingKey
    if k and k ~= "" then return k end
    local g = Cfg("pkKey")
    return (g and g ~= "") and g or nil
end
PK.PingKeyFor = PKPingKeyFor

local function PKEntryOn(e) return e ~= nil and e.enabled ~= false end
PK.EntryOn = PKEntryOn

local function PKEntryMode(e)
    if e and e.mode == "always" then return "always" end
    if e and e.mode == "own" then return "own" end
    return "key"
end
PK.EntryMode = PKEntryMode

-- Whether an entry would arm right now; each mode needs a different key.
local function PKEntryArms(e)
    if not (e and e.id and PKEntryOn(e)) then return false end
    if e.mode == "own" then return e.ownKey ~= nil and e.ownKey ~= "" end
    if not PKKeyFor(e) then return false end
    if e.mode == "always" then return true end
    return PKPingKeyFor(e) ~= nil
end

function PK.ResolvedCount()
    local list, n = PKList(false), 0
    for i = 1, #list do
        if PKEntryArms(list[i]) then n = n + 1 end
    end
    return n
end
function PK.Armed() return pkArmed, pkSkipped end
function PK.Pending() return pkDirty end

-- A macro's index from its name, told apart by the spell or icon its slot shows.
local function PKMacroIndexForSlot(slot)
    if type(slot) ~= "number" then return nil end
    local name = GetActionText and GetActionText(slot)
    if not name or name == "" then return nil end
    if not (GetNumMacros and GetMacroInfo) then return nil end
    local _, wantSpell = GetActionInfo(slot)
    local wantTex = GetActionTexture and GetActionTexture(slot)
    local acct, char = GetNumMacros()
    local byName, bySpell, byTex
    local function scan(from, to)
        for i = from, to do
            local n, tex = GetMacroInfo(i)
            if n == name then
                byName = byName or i
                if wantSpell and GetMacroSpell and GetMacroSpell(i) == wantSpell then bySpell = bySpell or i end
                if wantTex and tex == wantTex then byTex = byTex or i end
            end
        end
    end
    scan(1, acct or 0)
    scan(PK_MACRO + 1, PK_MACRO + (char or 0))
    return bySpell or byTex or byName
end

-- The base spell's name: /cast follows an override both ways, so the line
-- never needs rewriting (which combat would forbid).
local function PKBaseSpellName(id)
    if type(id) ~= "number" then return nil end
    if not (C_Spell and C_Spell.GetBaseSpell) then return nil end
    local base = C_Spell.GetBaseSpell(id) -- raw-id: a live bar slot's spell
    if type(base) ~= "number" or base <= 0 or base == id then return nil end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(base) -- raw-id: a live bar slot's spell
    return info and info.name or nil
end

-- What an every-press relay runs to cast as the player would. A macro cannot
-- run another macro, so a macro's own body is inlined; everything else casts
-- by name, which no modifier on the bar button can intercept.
local function PKCastLines(e)
    local btn = type(e.btn) == "string" and _G[e.btn]
    if type(btn) == "table" and type(btn.GetObjectType) == "function" then
        local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
        if type(slot) == "number" and HasAction(slot) and GetActionInfo(slot) == "macro" then
            local idx = PKMacroIndexForSlot(slot)
            if idx and GetMacroInfo then
                local _, _, body = GetMacroInfo(idx)
                if type(body) == "string" and body ~= "" then return (body:gsub("%s+$", "")) end
            end
        end
    end
    local nm = PKSubjectInfo(e)
    if not nm or nm == "" then return nil end
    if e.kind == "item" then return "/use " .. nm end
    return "/cast " .. (PKBaseSpellName(e.id) or nm)
end

-- Counts presses (the secure side has no clock) and picks between the two
-- baked lines; the cast is in both, so a skipped ping never eats a press.
-- Relays are pooled: one with no pkFull is left alone.
local PK_PRESS_GATE = [=[
    local full = self:GetAttribute("pkFull")
    if not full then return end
    local castOnly = self:GetAttribute("pkCastOnly") or full
    local every = self:GetAttribute("pkEvery") or 1
    if every <= 1 then
        self:SetAttribute("macrotext", full)
        return
    end
    local n = (self:GetAttribute("pkPress") or 0) + 1
    if n >= every then n = 0 end
    self:SetAttribute("pkPress", n)
    if n == 0 then
        self:SetAttribute("macrotext", full)
    else
        self:SetAttribute("macrotext", castOnly)
    end
]=]

local function PKRelay(i)
    local r = pkRelays[i]
    if not r then
        r = CreateFrame("Button", "ArcAurasPingRelay" .. i, UIParent, "SecureActionButtonTemplate")
        r:SetSize(1, 1)
        r:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
        r:RegisterForClicks("AnyDown")
        r:SetAttribute("type", "macro")
        r:SetAttribute("macrotext", "")
        if not pkGateHeader then
            pkGateHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
        end
        SecureHandlerWrapScript(r, "OnClick", pkGateHeader, PK_PRESS_GATE)
        pkRelays[i] = r
    end
    -- a pooled relay forgets its last owner's gate
    r:SetAttribute("pkFull", nil)
    r:SetAttribute("pkCastOnly", nil)
    r:SetAttribute("pkEvery", 1)
    r:SetAttribute("pkPress", 0)
    return r
end

-- Binds the held key's spells on key-down and drops them on key-up. With the
-- guard on it binds nothing while the bar shows another page than the one
-- the relays were baked from: silent, never the wrong spell.
local PK_SNIPPET = [=[
    if down then
        if self:GetAttribute("pkGuard") then
            local baked = self:GetAttribute("pkBakedState")
            local live = self:GetAttribute("pkLiveState")
            if baked and live and baked ~= live then return end
        end
        local n = self:GetAttribute("pkCount") or 0
        for i = 1, n do
            local k = self:GetAttribute("pkKey" .. i)
            local r = self:GetAttribute("pkRelay" .. i)
            if k and r then self:SetBindingClick(true, k, r) end
        end
    else
        self:ClearBindings()
    end
]=]
local PK_DRIVER = "[overridebar]o;[vehicleui]v;[possessbar]p;[shapeshift]s;[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;1"
local PK_STATE_SNIPPET = [=[ self:SetAttribute("pkLiveState", newstate) ]=]

-- One holder per ping key; a spell may name its own ping key.
local function PKHolder(pingKey)
    local h = pkHolders[pingKey]
    if not h then
        pkHolderN = pkHolderN + 1
        h = CreateFrame("Button", "ArcAurasPingHolder" .. pkHolderN, UIParent,
            "SecureHandlerClickTemplate,SecureHandlerStateTemplate")
        h:SetSize(1, 1)
        h:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
        h:RegisterForClicks("AnyDown", "AnyUp")
        h:SetAttribute("_onclick", PK_SNIPPET)
        h:SetAttribute("_onstate-pkpage", PK_STATE_SNIPPET)
        pkHolders[pingKey] = h
    end
    if not h._adDriver then
        RegisterStateDriver(h, "pkpage", PK_DRIVER)
        h._adDriver = true
    end
    return h
end

local function PKBarState()
    if HasOverrideActionBar and HasOverrideActionBar() then return "o" end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return "v" end
    if IsPossessBarVisible and IsPossessBarVisible() then return "p" end
    local form = GetShapeshiftForm and GetShapeshiftForm()
    if type(form) == "number" and form > 0 then return "s" end
    local page = GetActionBarPage and GetActionBarPage() or 1
    return tostring(page)
end

-- Auto-Ping: every-press spells as a group, switched by a key even in combat.
-- Their bindings belong to the holder's snippet so that key can drop and
-- restore them where Lua cannot.
local PK_AUTO_APPLY = [=[
    self:ClearBindings()
    if not self:GetAttribute("pkAutoOn") then return end
    local n = self:GetAttribute("pkAutoCount") or 0
    for i = 1, n do
        local k = self:GetAttribute("pkAutoKey" .. i)
        local r = self:GetAttribute("pkAutoRelay" .. i)
        if k and r then self:SetBindingClick(true, k, r) end
    end
]=]
local PK_AUTO_TOGGLE = [=[
    if down then
        self:SetAttribute("pkAutoOn", not self:GetAttribute("pkAutoOn"))
        self:RunAttribute("pkAutoApply")
    end
]=]

local function PKAutoNotify(on)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        if on then UIErrorsFrame:AddMessage(Tr("Arc Pings: Auto-Ping on"), 0.2, 1.0, 0.6, 1, 3)
        else UIErrorsFrame:AddMessage(Tr("Arc Pings: Auto-Ping off"), 1.0, 0.35, 0.35, 1, 3) end
    end
    if PlaySound and SOUNDKIT then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
    end
end

local function PKAutoHolder()
    if pkAutoHolder then return pkAutoHolder end
    pkAutoHolder = CreateFrame("Button", "ArcAurasPingAutoHolder", UIParent,
        "SecureHandlerClickTemplate,SecureHandlerShowHideTemplate")
    pkAutoHolder:SetSize(1, 1)
    pkAutoHolder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
    pkAutoHolder:RegisterForClicks("AnyDown")
    pkAutoHolder:SetAttribute("pkAutoApply", PK_AUTO_APPLY)
    pkAutoHolder:SetAttribute("_onclick", PK_AUTO_TOGGLE)
    pkAutoHolder:SetAttribute("_onshow", "self:RunAttribute('pkAutoApply')")
    -- the toggle key flips the attribute in a snippet; this hears it, in
    -- combat too, so the next apply never pushes the old value back
    pkAutoHolder:SetScript("OnAttributeChanged", function(_, name, value)
        if name ~= "pkautoon" then return end
        local on = value and true or false
        if (Cfg("pkAutoOn") ~= false) == on then return end
        local c = CharDB(true)
        if c then c.pkAutoOn = on end
        PKAutoNotify(on)
        if P.notify then P.notify() end
    end)
    return pkAutoHolder
end

function PK.AutoOn() return Cfg("pkAutoOn") ~= false end
function PK.SetAutoOn(on)
    P.Set("pkAutoOn", on and true or false)
end

local function PKArmAlways(e, slotIndex, autoN)
    local k = PKKeyFor(e)
    local cast = PKCastLines(e)
    if not (k and cast) then return false end
    if not PKEntryMatchesBar(e) then return false end
    -- the ping last, so a macro's own /stopmacro still stops it
    local r = PKRelay(slotIndex)
    local full = cast .. "\n" .. PKPingLine(e)
    r:SetAttribute("macrotext", full)
    r:SetAttribute("pkFull", full)
    r:SetAttribute("pkCastOnly", cast)
    r:SetAttribute("pkEvery", tonumber(e.every) or 1)
    r:SetAttribute("pkPress", 0)
    local h = PKAutoHolder()
    h:SetAttribute("pkAutoKey" .. autoN, k)
    h:SetAttribute("pkAutoRelay" .. autoN, r:GetName())
    return true
end

local function PKArmKey(h, e, slotIndex, n)
    local k = PKKeyFor(e)
    if not k then return false end
    if not PKEntryMatchesBar(e) then return false end
    local r = PKRelay(slotIndex)
    r:SetAttribute("macrotext", PKPingLine(e))
    h:SetAttribute("pkKey" .. n, k)
    h:SetAttribute("pkRelay" .. n, r:GetName())
    return true
end

-- Every key on the bars pings what it holds; one relay per key.
local function PKArmAnySpell(h)
    local seen, n = {}, 0
    for _, b in ipairs(PKCollectButtons()) do
        if n >= PK_ALL then break end
        local sid, _, kind = PKButtonSubject(b)
        local k = PKKeyForButton(b)
        if sid and k and not seen[k] then
            seen[k] = true
            n = n + 1
            local r = PKRelay(PK_MAX + n)
            r:SetAttribute("macrotext", PKPingLine({ id = sid, kind = kind }))
            h:SetAttribute("pkKey" .. n, k)
            h:SetAttribute("pkRelay" .. n, r:GetName())
        end
    end
    return n
end

local function PKArmOwn(e, slotIndex)
    local k = e.ownKey
    if not k or k == "" then return false end
    local r = PKRelay(slotIndex)
    r:SetAttribute("macrotext", PKPingLine(e))
    SetOverrideBindingClick(pkAlwaysOwner, true, k, r:GetName())
    return true
end

-- Every binding and secure attribute this module set, dropped. Out of combat
-- only; in combat it waits for the end of combat.
local function PKDisarm()
    if InCombatLockdown() then
        pkDirty = true
        return false
    end
    if pkBindOwner then ClearOverrideBindings(pkBindOwner) end
    if pkAlwaysOwner then ClearOverrideBindings(pkAlwaysOwner) end
    for _, h in pairs(pkHolders) do
        h:SetAttribute("pkCount", 0)
        h:SetAttribute("pkGuard", false)
        ClearOverrideBindings(h)
        if h._adDriver then
            UnregisterStateDriver(h, "pkpage")
            h._adDriver = nil
        end
    end
    if pkAutoHolder then
        pkAutoHolder:SetAttribute("pkAutoCount", 0)
        ClearOverrideBindings(pkAutoHolder)
    end
    pkArmed, pkSkipped = 0, 0
    return true
end

PKApply = function()
    if not running then return end
    if InCombatLockdown() then pkDirty = true return end
    pkDirty = false
    if not (Cfg("pkEnabled") and P.CanBind()) then
        PKDisarm()
        return
    end
    pkBindOwner = pkBindOwner or CreateFrame("Frame")
    pkAlwaysOwner = pkAlwaysOwner or CreateFrame("Frame")
    ClearOverrideBindings(pkBindOwner)
    ClearOverrideBindings(pkAlwaysOwner)
    for _, h in pairs(pkHolders) do
        h:SetAttribute("pkCount", 0)
        h:SetAttribute("pkGuard", false)
    end
    pkArmed, pkSkipped = 0, 0
    local barState = PKBarState()
    local globalKey = Cfg("pkKey")
    local perKeyN = {}
    -- every bound spell on the ping key, unless narrowed to the picked list
    if Cfg("pkOnlySelected") ~= true and globalKey and globalKey ~= "" then
        local h = PKHolder(globalKey)
        -- this layer bakes from the bars, so it pauses while they page away
        h:SetAttribute("pkGuard", true)
        local n = PKArmAnySpell(h)
        perKeyN[globalKey] = n
        pkArmed = n
    end
    -- the picked list, each by its own mode; held entries come after the ones
    -- above on the same holder, so theirs wins for a shared key
    local list = PKList(false)
    local slot, autoN = 0, 0
    for i = 1, #list do
        local e = list[i]
        if e and e.id and PKEntryOn(e) and slot < PK_MAX then
            slot = slot + 1
            local mode, ok = PKEntryMode(e), false
            if mode == "always" then
                autoN = autoN + 1
                ok = PKArmAlways(e, slot, autoN)
                if not ok then autoN = autoN - 1 end
            elseif mode == "own" then
                ok = PKArmOwn(e, slot)
            else
                local pk = PKPingKeyFor(e)
                if pk then
                    local h = PKHolder(pk)
                    local n = (perKeyN[pk] or 0) + 1
                    ok = PKArmKey(h, e, slot, n)
                    if ok then perKeyN[pk] = n end
                end
            end
            if ok then pkArmed = pkArmed + 1 else pkSkipped = pkSkipped + 1 end
        end
    end
    for pk, n in pairs(perKeyN) do
        local h = PKHolder(pk)
        h:SetAttribute("pkCount", n)
        h:SetAttribute("pkBakedState", barState)
        h:SetAttribute("pkLiveState", barState)
        if n > 0 then SetOverrideBindingClick(pkBindOwner, true, pk, h:GetName()) end
    end
    -- a holder no key uses any more stops watching the bar
    for pk, h in pairs(pkHolders) do
        if not perKeyN[pk] and h._adDriver then
            UnregisterStateDriver(h, "pkpage")
            h._adDriver = nil
        end
    end
    -- hide then show runs the holder's apply snippet
    local ah = PKAutoHolder()
    ah:SetAttribute("pkAutoCount", autoN)
    ah:SetAttribute("pkAutoOn", Cfg("pkAutoOn") ~= false)
    ah:Hide()
    ah:Show()
    local tk = Cfg("pkToggleKey")
    if tk and tk ~= "" and autoN > 0 then
        SetOverrideBindingClick(pkBindOwner, true, tk, ah:GetName())
    end
    if P.notify then P.notify() end
end
PK.Apply = function() PKApply() end

-- The catalog: everything on the bars, plus picked spells that are not, built
-- on demand (a scan walks every bar button) and marked stale by bar events.
local pkCatalog, pkCatalogBuilt = {}, false
local pkSelID
local pkCatSearch, pkCatView = "", "all"

local function PKTracked(id)
    if not id then return nil end
    local list = PKList(false)
    for i = 1, #list do
        if list[i].id == id then return list[i] end
    end
    return nil
end
PK.Tracked = PKTracked

function PK.BuildCatalog()
    wipe(pkCatalog)
    local seen = {}
    for _, btn in ipairs(PKCollectButtons()) do
        local id, cmd, kind, bname = PKButtonSubject(btn)
        if id and not seen[id] then
            seen[id] = true
            local e = { id = id, kind = kind or "spell", cmd = cmd, btn = bname }
            e.name, e.icon = PKSubjectInfo(e)
            e.key = PKKeyForButton(btn)
            pkCatalog[#pkCatalog + 1] = e
        elseif id then
            -- the same spell on two bars: keep the copy that has a key
            for j = 1, #pkCatalog do
                local c = pkCatalog[j]
                if c.id == id and not c.key then
                    local k = PKKeyForButton(btn)
                    if k then c.key, c.cmd, c.btn = k, cmd, bname end
                    break
                end
            end
        end
    end
    -- a picked spell off the bars stays reachable
    local list = PKList(false)
    for i = 1, #list do
        local t = list[i]
        if t and t.id and not seen[t.id] then
            seen[t.id] = true
            local e = { id = t.id, kind = t.kind or "spell", cmd = t.cmd, btn = t.btn, offBar = true }
            e.name, e.icon = PKSubjectInfo(e)
            local live = PKLiveButton(t.btn)
            e.key = (live and PKKeyForButton(live)) or (t.cmd and GetBindingKey(t.cmd)) or t.ownKey or nil
            if e.key == "" then e.key = nil end
            pkCatalog[#pkCatalog + 1] = e
        end
    end
    -- keybound first, then by name
    table.sort(pkCatalog, function(a, b)
        local ak, bk = a.key ~= nil, b.key ~= nil
        if ak ~= bk then return ak end
        return (a.name or "") < (b.name or "")
    end)
    pkCatalogBuilt = true
    return #pkCatalog
end

function PK.Catalog()
    if not pkCatalogBuilt then PK.BuildCatalog() end
    return pkCatalog
end
function PK.CatalogDirty() pkCatalogBuilt = false end
function PK.SetCatSearch(s) pkCatSearch = s or "" end
function PK.CatSearch() return pkCatSearch end
function PK.SetCatView(v) pkCatView = v or "all" end
function PK.GetCatView() return pkCatView end

function PK.CatalogFiltered()
    local all = PK.Catalog()
    local q = (pkCatSearch ~= "") and pkCatSearch:lower() or nil
    if not q and pkCatView == "all" then return all end
    local out = {}
    for _, e in ipairs(all) do
        local ok = true
        if q then ok = type(e.name) == "string" and e.name:lower():find(q, 1, true) ~= nil end
        if ok and pkCatView ~= "all" then
            local t = PKTracked(e.id)
            ok = (pkCatView == "on") == (t ~= nil and PKEntryOn(t))
        end
        if ok then out[#out + 1] = e end
    end
    return out
end

-- Selection is by ID: the list reorders when an entry goes.
function PK.Select(id) pkSelID = id end
function PK.SelectedID() return pkSelID end
function PK.Selected()
    if not pkSelID then return nil end
    for _, c in ipairs(PK.Catalog()) do
        if c.id == pkSelID then return c end
    end
    local t = PKTracked(pkSelID)
    if t then
        local nm, icon = PKSubjectInfo(t)
        return { id = t.id, kind = t.kind, cmd = t.cmd, btn = t.btn, name = nm, icon = icon, offBar = true }
    end
    return nil
end

-- On adds the entry the first time and only flips it after, so a spell
-- switched off and on keeps its mode and keys. False, "full" when no slot is left.
function PK.SetSelectedEnabled(on)
    local sel = PK.Selected()
    if not sel then return false end
    local t = PKTracked(sel.id)
    if on then
        if not t then
            local list = PKList(true)
            if #list >= PK_MAX then return false, "full" end
            list[#list + 1] = { id = sel.id, kind = sel.kind, cmd = sel.cmd, btn = sel.btn }
        else
            t.enabled = nil
        end
    elseif t then
        t.enabled = false
    end
    PKApply()
    return true
end

function PK.RemoveSelected()
    local sel = PK.Selected()
    if not sel then return end
    local list = PKList(false)
    for i = #list, 1, -1 do
        if list[i].id == sel.id then table.remove(list, i) end
    end
    if sel.offBar then
        PK.CatalogDirty()
        pkSelID = nil
    end
    PKApply()
end

-- Adds a spell by ID (it need not be on a bar) and selects it.
function PK.AddSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 or spellID ~= math.floor(spellID) then return false end
    if C_Spell and C_Spell.GetSpellInfo and not C_Spell.GetSpellInfo(spellID) then return false end -- raw-id: a typed ID checked
    if PKTracked(spellID) then
        pkSelID = spellID
        return true
    end
    local list = PKList(true)
    if #list >= PK_MAX then return false, "full" end
    list[#list + 1] = { id = spellID }
    PK.CatalogDirty()
    pkSelID = spellID
    PKApply()
    return true
end

-- One field of the selected entry: mode, every, pingKey, ownKey.
function PK.SetField(field, v)
    local sel = PK.Selected()
    local t = sel and PKTracked(sel.id)
    if not t then return end
    if field == "mode" then t.mode = (v ~= "key") and v or nil
    elseif field == "every" then t.every = (tonumber(v) and tonumber(v) > 1) and tonumber(v) or nil
    elseif field == "pingKey" or field == "ownKey" then t[field] = (v ~= nil and v ~= "") and v or nil
    end
    PKApply()
end

-- Running

local EVENTS = {
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED",
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "TRAIT_CONFIG_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED", "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED", "PLAYER_DIFFICULTY_CHANGED",
}
-- where the player is decides the Show In switches
local CONTENT = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true, CHALLENGE_MODE_START = true,
    CHALLENGE_MODE_COMPLETED = true, PLAYER_DIFFICULTY_CHANGED = true }
-- bars and bindings changed: the catalog and the baked relays are stale
local STALE = { UPDATE_BINDINGS = true, ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true,
    PLAYER_ENTERING_WORLD = true, TRAIT_CONFIG_UPDATED = true, PLAYER_SPECIALIZATION_CHANGED = true,
    UPDATE_SHAPESHIFT_FORM = true }
local applyQueued = false

-- One re-arm a frame later, however many bar events came. Bar addons re-apply
-- their own bindings on the same events, so ours land after theirs.
local function QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        if running then PKApply() end
    end)
end

local function OnEvent(ev)
    if not running then return end
    if CONTENT[ev] then ApplyAll() end
    if ev == "PLAYER_REGEN_DISABLED" then
        if P.notify then P.notify() end
        return
    end
    if STALE[ev] then PK.CatalogDirty() end
    if ev == "PLAYER_REGEN_ENABLED" then
        if P.notify then P.notify() end
        if pkDirty then PKApply() end
        return
    end
    if STALE[ev] and Cfg("pkEnabled") then QueueApply() end
end

-- After combat: what a stop in combat could not undo.
local function FinishTeardown()
    Off("PLAYER_REGEN_ENABLED", TEARDOWN)
    if running then return end
    PKDisarm()
end

function P.Start()
    if running or not (P.IsOn() and P.Available()) then return false end
    running = true
    for _, ev in ipairs(EVENTS) do
        if Valid(ev) then On(ev, OnEvent) end
    end
    ApplyAll()
    if panelOpen then ShowPreviewEntry() end
    PKApply()
    return true
end

-- Off: everything on screen goes now; bindings now, or once combat ends.
function P.Stop()
    if not running then return end
    running = false
    feedLive = false
    for _, ev in ipairs(EVENTS) do Off(ev) end
    Off("CHAT_MSG_PING")
    for i = #entries, 1, -1 do
        FreeRow(entries[i].row)
        entries[i] = nil
    end
    if win then win:Hide(); win.titleHolder:Hide() end
    if not PKDisarm() then On("PLAYER_REGEN_ENABLED", FinishTeardown, TEARDOWN) end
    if P.notify then P.notify() end
end

function P.SetOn(v)
    local db = DB(true)
    if not db then return end
    db.on = v and true or nil
    if v then P.Start() else P.Stop() end
end

-- At login the saved settings are in; on WoW Forever the client can hand them
-- over a moment later, so the world's first entry looks again.
local function BootLogin()
    Off("PLAYER_LOGIN", BOOT)
    P.Start()
end
local function BootWorld()
    Off("PLAYER_ENTERING_WORLD", BOOT)
    Off("PLAYER_LOGIN", BOOT)
    -- not mid-dispatch: starting adds to the event being dispatched
    C_Timer.After(0, function() P.Start() end)
end
On("PLAYER_LOGIN", BootLogin, BOOT)
On("PLAYER_ENTERING_WORLD", BootWorld, BOOT)

-- The harness's view of what is on screen.
function P.Debug()
    return { win = win, rows = rows, entries = entries, holders = pkHolders, relays = pkRelays,
        autoHolder = pkAutoHolder, bindOwner = pkBindOwner, alwaysOwner = pkAlwaysOwner }
end
