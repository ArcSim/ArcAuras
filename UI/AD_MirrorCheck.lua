-- AD_MirrorCheck: "/arcauras mirror", a read-only window that pairs every icon on
-- the Cooldown Manager's bars with the Arc Auras icon its mirror built (the newest
-- layout named "Cooldown Manager", by spell) and compares, live, what matters: shown,
-- and the phase the icon is in (ready, cooldown, an aura on you or your target, a
-- totem and its slot) with its time left. A mismatch that holds is logged with its time in a box
-- that copies. Looks are not compared.
-- The Cooldown Manager is read through its fields and plain widget getters only,
-- never a method of its own. Our engine aura buttons are never read (forbidden in
-- combat): our aura phase is what the game's aura list says our icon's spells and
-- units hold, "?" while auras are secret. It runs only while its window is open:
-- events, one pass a beat later.
local ADDON, NS = ...
local Store = NS.Store

local MC = {}
NS.MirrorCheck = MC

MC.KEY = "admirror"
MC.DELAY = 0.15       -- after an event, both sides have refreshed
MC.HOLD = 0.4         -- a mismatch shorter than this is the two sides updating apart
MC.SLACK = 0.3        -- seconds two times left may differ
MC.LOG_MAX = 300
MC.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "UNIT_AURA", "PLAYER_TARGET_CHANGED",
    "PLAYER_TOTEM_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED" }
MC.log = {}
MC.open = {}          -- [pair key .. field] = { since, logged, text }
MC.rows = {}

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v) if type(v) == "number" and Plain(v) then return v end return nil end
local function Bool(v) if type(v) == "boolean" and Plain(v) then return v end return nil end
local function Str(v) if type(v) == "string" and Plain(v) then return v end return nil end

function MC.AurasSecret()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local v = C_Secrets.ShouldAurasBeSecret()
    if not Plain(v) then return true end
    return v == true
end

-- Our side

-- the newest layout named "Cooldown Manager": the mirror's
function MC.Layout()
    local best
    if not (Store and Store.EachRecord) then return nil end
    Store.EachRecord(function(id, rec)
        if rec.type == "layout" and rec.name == "Cooldown Manager" and (not best or id > best.id) then best = rec end
    end)
    return best
end

-- its icons by bar name (a group per bar) and its aura bars
function MC.Ours(lay)
    local out, groups = {}, {}
    Store.EachRecord(function(id, rec)
        if rec.type == "group" and rec.layoutId == lay.id then groups[id] = rec.name end
    end)
    Store.EachRecord(function(_, rec)
        local name = (rec.type == "icon" and rec.groupId and groups[rec.groupId])
            or (rec.type == "bar" and rec.layoutId == lay.id and rec.barKind == "aura" and "Tracked Bars")
        if name then
            out[name] = out[name] or {}
            table.insert(out[name], rec)
        end
    end)
    return out
end

-- the spells a record follows
function MC.SpellsOf(rec)
    local d, out = rec.driver or {}, {}
    if type(d.spellID) == "number" then out[#out + 1] = d.spellID end
    if type(d.spellIDs) == "table" then
        for _, v in ipairs(d.spellIDs) do if type(v) == "number" then out[#out + 1] = v end end
    end
    return out
end

-- The aura our icon's lanes find on the game's list now: the unit and its end
-- time, false for none, "?" while auras are secret, nil when it tracks no aura.
function MC.AuraNow(rec)
    local DA = NS.DriverAura
    local d, lanes
    if rec.type == "bar" then
        d = rec.driver or {}
        lanes = { { unit = d.unit or "player", harmful = d.auraType == "debuff" } }
    else
        d = DA and DA.ShapeFor and DA.ShapeFor(rec)
        if not d then return nil end
        lanes = DA.LanesFor(d)
    end
    if MC.AurasSecret() then return "?" end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return "?" end
    local ids = Store.AuraIncludeMap(d)
    local mine = d.caster == nil or d.caster == "mine"
    for _, lane in ipairs(lanes) do
        if Bool(UnitExists(lane.unit)) then
            local filter = (lane.harmful and "HARMFUL" or "HELPFUL") .. (mine and "|PLAYER" or "")
            for i = 1, 40 do
                local a = get(lane.unit, i, filter)
                if not a then break end
                local sid = a.spellId
                if not Plain(sid) then return "?" end
                if ids[sid] then
                    local exp = Num(a.expirationTime)
                    return lane.unit, (exp and exp > 0) and exp or nil
                end
            end
        end
    end
    return false
end

-- a cooldown widget's end time when it reads plain
local function EndOf(cd)
    if not (cd and cd.GetCooldownTimes) then return nil end
    local s, d = cd:GetCooldownTimes()
    s, d = Num(s), Num(d)
    if not (s and d) or d <= 0 then return nil end
    return (s + d) / 1000
end

local function Shown(f)
    if not (f and f.IsVisible) then return nil end
    local v = Bool(f:IsVisible())
    if v == nil then return nil end
    if not v then return false end
    local a = f.GetEffectiveAlpha and Num(f:GetEffectiveAlpha())
    if a == nil then return true end
    return a > 0.01
end

-- Our icon's totem (Drivers\AD_DriverPhase.lua) when its button shows: the phase,
-- its end and the slot it follows go into s. Blizzard checks a totem first.
function MC.TotemNow(rec, s)
    local PH = NS.DriverPhase
    if not (PH and PH.Source and PH.Source(rec) == "totem") then return false end
    local b = PH.buttons and PH.buttons[rec.id]
    if not (b and Bool(b:IsShown())) then return false end
    local e = PH.entries and PH.entries[rec.id]
    local DT = NS.DriverTotem
    s.phase, s.ends = "totem", EndOf(b._adSwipe)
    s.slot = (e and e.pseudo and DT and DT.SlotFor and DT.SlotFor(e.pseudo)) or nil
    return true
end

-- what our record shows: { shown, phase, ends, slot }; phase "?" when unreadable
function MC.OurState(rec)
    local s = {}
    if rec.type == "bar" then
        local unit, ends = MC.AuraNow(rec)
        if unit == "?" then s.phase = "?" elseif unit then s.phase, s.ends = "aura:" .. unit, ends else s.phase = "off" end
        return s
    end
    local f = NS.Factory and NS.Factory.frames and NS.Factory.frames[rec.id]
    s.shown = Shown(f)
    if rec.kind == "totem" then
        local DC = NS.DriverCooldown
        local live = DC and DC.TotemLive and DC.TotemLive(rec)
        if live == nil then s.phase = "?" elseif live then s.phase, s.ends = "totem", EndOf(f and f.cooldown)
        else s.phase = "off" end
        return s
    end
    if rec.kind == "aura" then
        if MC.TotemNow(rec, s) then return s end
        local unit, ends = MC.AuraNow(rec)
        if unit == "?" then s.phase = "?" elseif unit then s.phase, s.ends = "aura:" .. unit, ends else s.phase = "off" end
        return s
    end
    -- a spell icon: its totem, else its aura, else its cooldown
    if MC.TotemNow(rec, s) then return s end
    local unit, ends = MC.AuraNow(rec)
    if unit == "?" then
        s.phase = "?"
        return s
    end
    if unit then
        s.phase, s.ends = "aura:" .. unit, ends
        return s
    end
    if f and (f._adOnCooldown == true or f._adRecharging == true) then
        s.phase, s.ends = "cooldown", EndOf(f.cooldown)
    else
        s.phase = f and "ready" or "?"
    end
    return s
end

-- The Cooldown Manager's side

-- a bar's item frames (a frame with a cooldownID), in the bar's order
function MC.Items(v)
    local out = {}
    local root = _G[v.frame]
    if type(root) ~= "table" or not root.GetChildren then return out end
    local function Walk(fr, depth)
        if depth > 2 then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            if type(c) == "table" and not (c.IsForbidden and c:IsForbidden()) then
                if Num(c.cooldownID) then
                    out[#out + 1] = c
                elseif c.GetChildren then
                    Walk(c, depth + 1)
                end
            end
        end
    end
    Walk(root, 1)
    table.sort(out, function(a, b) return (Num(a.layoutIndex) or 0) < (Num(b.layoutIndex) or 0) end)
    return out
end

-- what one item shows: { shown, phase, ends, slot }
function MC.CdmState(c, buffish)
    local s = { shown = Shown(c) }
    local unit = Str(c.auraDataUnit)
    local ends = EndOf(c.Cooldown)
    if c.auraDataUnit ~= nil and not unit then
        s.phase = "?"
    elseif c.totemData ~= nil then
        s.phase, s.ends = "totem", ends
        s.slot = type(c.totemData) == "table" and Num(c.totemData.slot) or nil
    elseif buffish then
        local active = Bool(c.isActive)
        if active == nil then s.phase = "?"
        elseif active then s.phase, s.ends = "aura:" .. (unit or "player"), ends
        else s.phase = "off" end
    elseif unit then
        s.phase, s.ends = "aura:" .. unit, ends
    else
        local cd = c.Cooldown and Bool(c.Cooldown:IsShown())
        local gcd = Bool(c.isOnGCD)
        if cd == nil then s.phase = "?"
        elseif cd and gcd ~= true then s.phase, s.ends = "cooldown", ends
        else s.phase = "ready" end
    end
    return s
end

-- the spells an entry answers to, from its info (a C call, plain on Forever)
function MC.EntryIDs(id, cache)
    if cache[id] ~= nil then return cache[id] end
    local CV = C_CooldownViewer
    local M = NS.CDMMirror
    local info = CV and CV.GetCooldownViewerCooldownInfo and CV.GetCooldownViewerCooldownInfo(id)
    local c = info and M and M.CopyInfo(info)
    local ids = false
    if c then
        ids = { list = {}, cdmSpell = c.spellID } -- raw-id: a Cooldown Manager entry's own spell
        for _, v in ipairs({ c.spellID, c.overrideSpellID, c.overrideTooltipSpellID }) do
            if type(v) == "number" then ids.list[#ids.list + 1] = v end
        end
        for _, v in ipairs(c.linkedSpellIDs or {}) do ids.list[#ids.list + 1] = v end
    end
    cache[id] = ids
    return ids
end

function MC.Pairs(ids, rec)
    for _, mine in ipairs(MC.SpellsOf(rec)) do
        for _, theirs in ipairs(ids.list) do
            if mine == theirs or Store.SpellMatch(mine, theirs) then return true end
        end
    end
    return false
end

-- Words

function MC.Phase(st)
    local p = st.phase
    local w = (p == "aura:player" and "aura on you") or (p == "aura:target" and "aura on target")
        or (p and p:match("^aura:") and "aura") or p or "?"
    if p == "totem" and st.slot then w = w .. " " .. st.slot end
    if st.ends and (p == "cooldown" or p == "totem" or (p and p:match("^aura"))) then
        local left = st.ends - GetTime()
        if left > 0 then w = w .. (" %.1fs"):format(left) end
    end
    if st.shown == false then w = "hidden, " .. w end
    return w
end

-- the fields that differ: shown, phase, slot, time (each only where both read plain)
function MC.Diff(a, b)
    local out = {}
    if a.shown ~= nil and b.shown ~= nil and a.shown ~= b.shown then out[#out + 1] = "shown" end
    if a.phase ~= "?" and b.phase ~= "?" and a.phase ~= b.phase then
        out[#out + 1] = "phase"
    else
        if a.phase == "totem" and b.phase == "totem" and a.slot and b.slot and a.slot ~= b.slot then
            out[#out + 1] = "slot"
        end
        if a.phase == b.phase and a.ends and b.ends and math.abs(a.ends - b.ends) > MC.SLACK then
            out[#out + 1] = "time"
        end
    end
    return out
end

-- The pass

function MC.Log(line)
    MC.log[#MC.log + 1] = date("%H:%M:%S") .. "  " .. line
    while #MC.log > MC.LOG_MAX do table.remove(MC.log, 1) end
end

-- One read of both sides. Returns the rows; logs what changed.
function MC.Pass()
    local M = NS.CDMMirror
    local now = GetTime()
    local rows, seen = {}, {}
    MC.why = nil
    if not (M and M.VIEWERS) then
        MC.why = "The mirror is not loaded."
        return rows
    end
    local lay = MC.Layout()
    if not lay then
        MC.why = "No layout named Cooldown Manager: build one from New Layout > From Cooldown Manager."
        return rows
    end
    local ours = MC.Ours(lay)
    local cache = {}
    MC.paired, MC.missing, MC.extra, MC.differ = 0, 0, 0, 0
    for _, v in ipairs(M.VIEWERS) do
        local list = ours[v.name] or {}
        local used = {}
        local buffish = v.cat ~= "Essential" and v.cat ~= "Utility"
        for _, c in ipairs(MC.Items(v)) do
            local id = Num(c.cooldownID)
            local ids = MC.EntryIDs(id, cache)
            local cdm = MC.CdmState(c, buffish)
            -- a spare frame has no cooldownID (Blizzard clears it on release)
            if ids then
                local rec
                for i, r in ipairs(list) do
                    if not used[i] and MC.Pairs(ids, r) then
                        rec = r
                        used[i] = true
                        break
                    end
                end
                local name = (M.NameOf and M.NameOf(ids.cdmSpell)) or ("cooldown " .. id)
                local row = { bar = v.name, name = name, key = v.name .. ":" .. id, cdm = cdm }
                if rec then
                    MC.paired = MC.paired + 1
                    row.ours = MC.OurState(rec)
                    row.diff = MC.Diff(cdm, row.ours)
                    if #row.diff > 0 then MC.differ = MC.differ + 1 end
                else
                    MC.missing = MC.missing + 1
                    row.diff = { "missing" }
                end
                rows[#rows + 1] = row
                seen[row.key] = row
            end
        end
        for i, r in ipairs(list) do
            if not used[i] then
                MC.extra = MC.extra + 1
                rows[#rows + 1] = { bar = v.name, name = r.name or "?", key = v.name .. ":arc" .. r.id,
                    ours = MC.OurState(r), diff = { "extra" } }
            end
        end
    end
    MC.Track(rows, now)
    MC.rows = rows
    return rows
end

-- A mismatch is logged once it has held MC.HOLD seconds, and again when it ends.
function MC.Track(rows, now)
    local live = {}
    local soonest
    for _, row in ipairs(rows) do
        for _, field in ipairs(row.diff or {}) do
            local k = row.key .. "|" .. field
            live[k] = true
            local o = MC.open[k]
            local text = row.bar .. "  " .. row.name .. ": " .. field
                .. (row.cdm and ("  CDM " .. MC.Phase(row.cdm)) or "")
                .. (row.ours and ("  /  Arc " .. MC.Phase(row.ours)) or "")
            if not o then
                MC.open[k] = { since = now, text = text }
                soonest = math.min(soonest or MC.HOLD, MC.HOLD)
            elseif not o.logged then
                if now - o.since >= MC.HOLD then
                    o.logged = true
                    MC.Log(text)
                else
                    soonest = math.min(soonest or MC.HOLD, MC.HOLD - (now - o.since))
                end
            end
        end
    end
    for k, o in pairs(MC.open) do
        if not live[k] then
            if o.logged then
                MC.Log((o.text:match("^(.-:%s*%S+)") or o.text) .. ": matches again (" .. ("%.1f"):format(now - o.since) .. "s)")
            end
            MC.open[k] = nil
        end
    end
    if soonest then MC.Queue(soonest + 0.05) end
end

-- Scheduling: a pass a beat after the last event, only while the window shows.

function MC.Queue(delay)
    if not (MC.win and MC.win:IsShown()) then return end
    local token = {}
    MC.token = token
    C_Timer.After(delay or MC.DELAY, function()
        if MC.token ~= token or not (MC.win and MC.win:IsShown()) then return end
        MC.Refresh()
    end)
end

function MC.OnEvent(event, unit)
    if event == "UNIT_AURA" and unit ~= "player" and unit ~= "target" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then MC.Log("-- combat starts") end
    if event == "PLAYER_REGEN_ENABLED" then MC.Log("-- combat ends") end
    MC.Queue(MC.DELAY)
end

function MC.Arm(on)
    local E = NS.Events
    if not E then return end
    for _, e in ipairs(MC.EVENTS) do
        if not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(e)) then
            if on then E.On(e, MC.KEY, MC.OnEvent) else E.Off(e, MC.KEY) end
        end
    end
end

-- The window

function MC.Text()
    local out = {}
    local lay = MC.Layout()
    out[#out + 1] = "Cooldown Manager  vs  Arc Auras layout \"Cooldown Manager\"   " .. date("%H:%M:%S")
    if MC.why then
        out[#out + 1] = MC.why
    else
        out[#out + 1] = ("%d paired, %d missing in Arc Auras, %d extra in Arc Auras.  %s"):format(MC.paired or 0,
            MC.missing or 0, MC.extra or 0, (MC.differ or 0) == 0 and "All paired icons match now."
            or ((MC.differ) .. " differ now."))
        if MC.AurasSecret() then out[#out + 1] = "Auras are secret here: our aura phase reads ?." end
    end
    local bar
    for _, row in ipairs(MC.rows) do
        if row.bar ~= bar then
            bar = row.bar
            out[#out + 1] = ""
            out[#out + 1] = bar:upper()
        end
        local mark = (#(row.diff or {}) == 0) and "ok    " or "DIFF  "
        local d = (#(row.diff or {}) > 0) and ("   (" .. table.concat(row.diff, ", ") .. ")") or ""
        out[#out + 1] = "  " .. mark .. row.name .. "   CDM " .. (row.cdm and MC.Phase(row.cdm) or "-")
            .. "   |   Arc " .. (row.ours and MC.Phase(row.ours) or "-") .. d
    end
    out[#out + 1] = ""
    out[#out + 1] = "LOG (a mismatch that held " .. MC.HOLD .. "s, then its end)"
    for _, l in ipairs(MC.log) do out[#out + 1] = l end
    if lay == nil and #MC.log == 0 then out[#out + 1] = "(nothing yet)" end
    return table.concat(out, "\n")
end

function MC.Refresh()
    MC.Pass()
    MC.text = MC.Text()
    local w = MC.win
    if not w then return end
    w.edit:SetText(MC.text)
    if w.scroll and w.scroll.UpdateScroll then w.scroll:UpdateScroll() end
    w.status:SetText(MC.why or ((MC.differ or 0) == 0 and "Watching: everything matches." or "Watching."))
end

function MC.Build()
    local AT = NS.AT
    if MC.win or not (AT and AT.CreateWindow) then return MC.win end
    local w = AT.CreateWindow("ArcAurasMirrorCheck", {
        w = 760, h = 520, minW = 520, minH = 320, maxW = 1400, maxH = 1100,
        title = "|cff3fc9f2Arc|r Auras mirror check",
    })
    w:SetFrameStrata("DIALOG")
    local edit = CreateFrame("EditBox", nil, w)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(700)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- read-only: a typed change puts the report back
    edit:SetScript("OnTextChanged", function(self, typed)
        if typed then self:SetText(MC.text or "") end
    end)
    local scroll = AT.MakeScroll(w, edit)
    scroll:SetPoint("TOPLEFT", 14, -42)
    scroll:SetPoint("BOTTOMRIGHT", -18, 50)
    scroll:HookScript("OnSizeChanged", function(_, sw) if sw and sw > 0 then edit:SetWidth(sw - 8) end end)
    w.edit, w.scroll = edit, scroll
    local function Btn(label, width, x, fn)
        local b = AT.MakeSmallButton(w, label, width)
        b:SetPoint("BOTTOMLEFT", x, 12)
        b:SetScript("OnClick", fn)
        return b
    end
    Btn("Select all", 90, 14, function() edit:SetFocus() edit:HighlightText() end)
    Btn("Check now", 90, 110, function() MC.Refresh() end)
    Btn("Clear log", 90, 206, function()
        wipe(MC.log)
        MC.Refresh()
    end)
    local status = w:CreateFontString(nil, "OVERLAY")
    status:SetFont(STANDARD_TEXT_FONT, 12, "")
    status:SetPoint("BOTTOMLEFT", 310, 18)
    status:SetTextColor(AT.COL.dim[1], AT.COL.dim[2], AT.COL.dim[3])
    w.status = status
    w:HookScript("OnShow", function()
        MC.Arm(true)
        MC.Refresh()
    end)
    w:HookScript("OnHide", function()
        MC.Arm(false)
        MC.token = nil
        wipe(MC.open)
    end)
    MC.win = w
    return w
end

function MC.Open()
    local w = MC.Build()
    if not w then return end
    if w:IsShown() then MC.Refresh() else w:Show() end
end
