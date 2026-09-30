-- Textures (barKind "texture"): a picture on the bars runtime's shell, driven
-- by an aura, a spell's cooldown or rules of its own. It shows the whole
-- picture while it is active, or fills and drains like a bar.
-- An aura's picture is drawn by the game's aura engine on the aura's own
-- button, so it follows the aura in combat with nothing read. A cooldown's
-- state is a hidden Cooldown's shown flag, a rule's the custom engine's plain
-- state; their fills are engine timers fed with duration objects.
local ADDON, NS = ...
local Bars = NS.Bars
local K = Bars and Bars.Kit
if not (Bars and K and Bars.RegisterKind) then return end
local R = K.R
local Schema = NS.Schema

local TP = {}
NS.TextureElements = TP
TP.KEY = "adbarstexture"
-- a cooldown the global cooldown hid is read again this long after
TP.GCD_RETRY = 0.3
-- the question mark, for a picture with nothing set and no spell to show
TP.QUESTION = 134400
TP.armed = {}      -- [event] = true while registered under TP.KEY

local SOURCES = {}
for _, s in ipairs(Schema.TEXTURE_SOURCES or {}) do SOURCES[s] = true end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

function TP.Source(rec)
    local d = rec and rec.driver
    local s = d and d.source
    return SOURCES[s] and s or "aura"
end

function TP.FillMode(rec)
    return R(rec, "texlook", "mode") == "fill"
end

-- The spell a cooldown picture follows: the rank you know, then its override.
function TP.EffSpell(rec)
    local d = rec.driver
    local sid = tonumber(d.spellID)
    if not (sid and sid > 0) then return nil end
    if d.autoRank and NS.DriverRange and NS.DriverRange.Resolve then
        sid = NS.DriverRange.Resolve(sid) or sid
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if not IsSecret(ov) and type(ov) == "number" and ov ~= 0 and ov ~= sid then sid = ov end
    end
    return sid
end

-- What SetTexture takes: the picture's FileDataID or path, else the tracked
-- spell's icon, else the question mark.
function TP.PictureOf(rec)
    local v = R(rec, "texlook", "image")
    if type(v) == "number" and v > 0 then return math.floor(v) end
    if type(v) == "string" and v ~= "" then
        local n = tonumber(v)
        if n then return math.floor(n) end
        return v
    end
    local sid = rec.driver and tonumber(rec.driver.spellID)
    local icon = sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
    if icon ~= nil and not IsSecret(icon) then return icon end
    return TP.QUESTION
end

-- The whole picture's look on a plain texture: the art, colour, blend and grey,
-- then the turn, flips and zoom (a fill keeps the picture upright). dim: the
-- dim copy behind, at its own opacity and grey.
function TP.Dress(tex, rec, dim)
    tex:SetTexture(TP.PictureOf(rec))
    local c = R(rec, "texlook", "color") or { 1, 1, 1, 1 }
    local a = c[4] or 1
    local grey = R(rec, "texlook", "desat") == true
    if dim then
        a = a * (R(rec, "texlook", "bgAlpha") or 0.3)
        if R(rec, "texlook", "bgDesat") == true then grey = true end
    end
    tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, a)
    tex:SetBlendMode(R(rec, "texlook", "blend") == "ADD" and "ADD" or "BLEND")
    tex:SetDesaturated(grey)
    if TP.FillMode(rec) then
        tex:SetTexCoord(0, 1, 0, 1)
        if tex.SetRotation then tex:SetRotation(0) end
        return
    end
    -- zoom crops the edges evenly: 45% keeps the middle 55%
    local z = (R(rec, "texlook", "zoom") or 0) / 200
    local l, r, t, b = z, 1 - z, z, 1 - z
    if R(rec, "texlook", "flipH") == true then l, r = r, l end
    if R(rec, "texlook", "flipV") == true then t, b = b, t end
    tex:SetTexCoord(l, r, t, b)
    if tex.SetRotation then tex:SetRotation(math.rad(R(rec, "texlook", "rotation") or 0)) end
end

-- A fill's bar: the picture as its fill texture (the bar reveals it, never
-- squeezes it), its direction, colour, blend and grey.
function TP.DressBar(bar, rec)
    local dir = R(rec, "texlook", "fillDir") or "RIGHT"
    bar:SetOrientation((dir == "UP" or dir == "DOWN") and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(dir == "LEFT" or dir == "DOWN")
    bar:SetRotatesTexture(false)
    local want = TP.PictureOf(rec)
    if bar._adPic ~= want then
        bar._adPic = want
        bar:SetStatusBarTexture(want)
    end
    local c = R(rec, "texlook", "color") or { 1, 1, 1, 1 }
    bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    local t = bar:GetStatusBarTexture()
    if t then
        t:SetBlendMode(R(rec, "texlook", "blend") == "ADD" and "ADD" or "BLEND")
        t:SetDesaturated(R(rec, "texlook", "desat") == true)
    end
end

-- Aura pictures: one slot on a container of our own, the aura icons' shape.
-- The engine shows the button with the aura and hides it without; the picture
-- or the fill on it goes with it.

-- A debuff lane on your target or focus waits while that unit is friendly:
-- the engine skips spell-ID filters there and would show any debuff. nil =
-- unknown (the answers can be secret in combat).
function TP.Hostile(unit)
    if not UnitExists then return false end
    local exists = UnitExists(unit)
    if IsSecret(exists) then return nil end
    if exists ~= true then return false end
    if not UnitCanAssist then return true end
    local assist = UnitCanAssist("player", unit, true, true)
    if IsSecret(assist) then return nil end
    return assist ~= true
end

function TP.AuraSig(e)
    local DA = NS.DriverAura
    local rec = e.rec
    local d = rec.driver
    local unit, harmful = DA.ShapeOf(d)
    local filter = DA.FilterForLane(d, { harmful = harmful })
    local fill = TP.FillMode(rec)
    local drain = (R(rec, "texlook", "fillMode") or "drain") == "drain"
    -- the ids stay out (an edit re-sends them); the direction is baked into
    -- the engine's binding, so it is in
    local sig = table.concat({ unit, tostring(harmful), filter, tostring(fill), tostring(drain) }, "|")
    return sig, unit, harmful, filter, fill, drain
end

-- The candidate filters: the ids, or the never-matching 0 while parked. An
-- unknown answer keeps the last one (a swap to a new enemy mid-fight keeps
-- its debuff showing); a slot with no answer yet waits; combat end asks again.
function TP.AuraFilters(e)
    local DA = NS.DriverAura
    local sub = e.tpAura
    local parked = false
    if sub.harmful and (sub.unit == "target" or sub.unit == "focus") then
        local hostile = TP.Hostile(sub.unit)
        if hostile == nil then parked = sub.parked ~= false else parked = not hostile end
    end
    sub.parked = parked
    local ids = parked and { [0] = true } or DA.IncludeMap(e.rec.driver)
    return ids, parked
end

-- Sends the filters when they changed: every send restarts the slot.
function TP.PushAuraFilters(e)
    local sub = e.tpAura
    if not (sub and sub.container.SetAuraSlotCandidateFilters) then return end
    local ids = TP.AuraFilters(e)
    local fsig = NS.DriverAura.FilterSig(ids)
    if sub.filterSig == fsig then return end
    sub.filterSig = fsig
    sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = ids })
end

function TP.ParkAura(sub)
    if sub.container.SetAuraSlotCandidateFilters then
        sub.container:SetAuraSlotCandidateFilters(sub.key, { includeSpellIDs = { [0] = true } })
    end
    sub.container:Hide()
end

-- Creates the slot once per recipe; false means retry on a later rebuild
-- (engine absent, or auras secret outside the login window).
function TP.EnsureAura(e)
    local DA = NS.DriverAura
    if not (DA and K.AuraEngineUp()) then return false end
    local rec = e.rec
    local sig, unit, harmful, filter, fill, drain = TP.AuraSig(e)
    local sub = e.tpAura
    if sub then
        if sub.sig == sig then
            TP.PushAuraFilters(e)
            return true
        end
        -- a new recipe cannot be made while auras are secret: the old slot
        -- keeps running (a stale look beats a dead picture)
        if K.AuraSecretNow() and not Bars.loadWindow then return true end
        TP.ParkAura(sub)
        e.tpAura = nil
    end
    if K.AuraSecretNow() and not Bars.loadWindow then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local shell = e.shell
    -- parented to the shell: the holder's opacity and conditions reach it
    local c = CreateFrame("AuraContainer", nil, shell, "CustomAuraContainerTemplate")
    if not c or type(c.AddAuraSlot) ~= "function" then return false end
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    c:SetUnit(unit)
    c:SetEnabled(true)
    c:Show()
    e.tpAuraGen = (e.tpAuraGen or 0) + 1
    local key = "adtexture" .. rec.id .. "_g" .. e.tpAuraGen
    sub = { container = c, key = key, sig = sig, unit = unit, harmful = harmful }
    e.tpAura = sub
    local ids = TP.AuraFilters(e)
    sub.filterSig = DA.FilterSig(ids)
    local dirEnum = Enum and Enum.StatusBarTimerDirection
    local dir = dirEnum and (drain and dirEnum.RemainingTime or dirEnum.ElapsedTime) or nil
    local id = rec.id
    c:AddAuraSlot(key, filter, {
        maxFrameCount = 1,
        -- The init window: everything built here descends from the button (the
        -- engine takes nothing else) and is anchored to our frames.
        initializeFrame = function(b)
            local cur = K.live[id]
            if not (cur and cur.tpAura == sub) then return end
            b:EnableMouse(false)
            b:SetAlpha(1)
            -- above the dim copy on our host
            b:SetFrameLevel(cur.tpHost:GetFrameLevel() + 2)
            b:ClearAllPoints()
            b:SetAllPoints(cur.shell)
            sub.button = b
            if fill then
                local bar = CreateFrame("StatusBar", nil, b)
                bar:SetAllPoints(b)
                -- the range before the binding: a later one drops the timer
                bar:SetMinMaxValues(0, 1)
                sub.bar = bar
                TP.DressBar(bar, cur.rec)
                b:SetDurationBar(bar, dir and { direction = dir } or {})
            else
                local pic = b:CreateTexture(nil, "ARTWORK")
                pic:SetAllPoints(b)
                sub.pic = pic
                TP.Dress(pic, cur.rec, false)
            end
        end,
        candidateFilters = { includeSpellIDs = ids },
    })
    if type(c.UpdateAllAuras) == "function" then c:UpdateAllAuras() end
    return true
end

-- A unit token keeps its name when it points at someone new, and a container
-- re-reads only on its own unit's aura events: re-park and nudge on a swap.
-- unit "party": every party slot (a roster change moves them all).
function TP.OnUnitSwap(unit)
    K.ForEach("texture", function(e)
        local sub = e.tpAura
        if sub and (unit == nil or sub.unit == unit or (unit == "party" and sub.unit:sub(1, 5) == "party")) then
            TP.PushAuraFilters(e)
            if type(sub.container.UpdateAllAuras) == "function" then sub.container:UpdateAllAuras() end
        end
    end)
end

-- Cooldown pictures: the main cooldown on one hidden Cooldown (state: on
-- cooldown or ready, the global cooldown kept out) and a charge spell's
-- recharge on another (what its fill runs with).

function TP.EnsureShadows(e)
    if e.tpCD then return end
    e.tpCD = K.MakeShadow()
    e.tpCharge = K.MakeShadow()
end

-- One re-read after the global cooldown: a real cooldown started under it
-- comes with no event of its own at its end.
function TP.RetryAfterGCD(e)
    if e.tpGcdQueued then return end
    e.tpGcdQueued = true
    local id = e.rec.id
    C_Timer.After(TP.GCD_RETRY, function()
        local cur = K.live[id]
        if not cur then return end
        cur.tpGcdQueued = nil
        if TP.Source(cur.rec) == "spellCd" then TP.Refresh(cur) end
    end)
end

function TP.FeedCooldown(e)
    TP.EnsureShadows(e)
    local rec = e.rec
    local sid = TP.EffSpell(rec)
    if not (sid and C_Spell and C_Spell.GetSpellCooldownDuration) then
        e.tpCD:Clear()
        e.tpCharge:Clear()
        e.tpMainDur, e.tpChargeDur, e.tpIsCharge = nil, nil, nil
        return
    end
    local DC = NS.DriverCooldown
    local wandLock = DC ~= nil and DC.WandLocked ~= nil and DC.WandLocked() and not DC.IsWandShot(sid)
    -- a running cooldown keeps its timing through the wand's lock
    if wandLock and e.tpCD:IsShown() == true then return end
    local main = (not wandLock) and C_Spell.GetSpellCooldownDuration(sid, true) or nil
    if main then e.tpCD:SetCooldownFromDurationObject(main, true) else e.tpCD:Clear() end
    local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
    local maxC = ch and ch.maxCharges
    local isCharge = type(maxC) == "number" and not IsSecret(maxC) and maxC > 1
    local chDur = isCharge and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(sid, true) or nil
    if chDur then e.tpCharge:SetCooldownFromDurationObject(chDur, true) else e.tpCharge:Clear() end
    e.tpMainDur, e.tpChargeDur, e.tpIsCharge = main, chDur, isCharge
    local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
    local onGcd = info and info.isOnGCD
    if not IsSecret(onGcd) and onGcd == true and not wandLock then TP.RetryAfterGCD(e) end
end

-- The state the picture shows, from the source: active, and a running
-- duration object for a fill (nil = nothing runs).
function TP.StateOf(e)
    local rec = e.rec
    local s = TP.Source(rec)
    if s == "spellCd" then
        local m = e.tpCD ~= nil and e.tpCD:IsShown() == true
        local c = e.tpIsCharge == true and e.tpCharge:IsShown() == true
        local active
        if rec.driver.cdActive == "cooldown" then active = m else active = not m end
        local run
        if c then run = e.tpChargeDur elseif m then run = e.tpMainDur end
        return active, run
    elseif s == "rules" then
        local CU = NS.DriverCustom
        local st = CU and CU.Get(rec.id)
        if not st then return false, nil end
        local run
        if CU.Running(st) and st.start and st.dur and C_DurationUtil and C_DurationUtil.CreateDuration then
            e.tpRuleDur = e.tpRuleDur or C_DurationUtil.CreateDuration()
            e.tpRuleDur:SetTimeFromStart(st.start, st.dur)
            run = e.tpRuleDur
        end
        return CU.Active(st), run
    end
    return true, nil
end

-- Paints a cooldown or rule picture: the whole picture while active, or the
-- fill running with its timer (full with nothing running but active, empty
-- when not). While you place it (edit mode) it always shows.
function TP.Paint(e)
    if e.isPreview then return end
    local rec = e.rec
    local s = TP.Source(rec)
    local edit = K.IsEditMode()
    if s == "aura" then
        -- the engine draws the live picture; ours stands in while you place it
        e.tpPic:SetShown(edit)
        e.tpBar:Hide()
        return
    end
    local active, run = TP.StateOf(e)
    if TP.FillMode(rec) then
        e.tpPic:Hide()
        e.tpBar:Show()
        local drain = (R(rec, "texlook", "fillMode") or "drain") == "drain"
        if run and not edit and K.FeedStatusBarTimer(e.tpBar, run, true, drain) then
            e.tpRunning = true
            return
        end
        e.tpRunning = nil
        e.tpBar:SetMinMaxValues(0, 1)
        e.tpBar:SetValue((active or edit) and 1 or 0)
    else
        e.tpBar:Hide()
        e.tpPic:SetShown(active or edit)
    end
end

-- The custom engine's paint told every picture that reads that state.
function TP.OnCustomPaint(st)
    K.ForEach("texture", function(e)
        if e.rec.id == st.id and TP.Source(e.rec) == "rules" then TP.Paint(e) end
    end)
end

-- Events: each source arms only what it needs, while a picture with that
-- source is live.

local function RefreshWhere(key, pred)
    NS.Events.Coalesce("adtexture_" .. key, function()
        K.ForEach("texture", function(e)
            if pred(e) then TP.Refresh(e) end
        end)
    end)
end

local function IsCd(e) return TP.Source(e.rec) == "spellCd" end

TP.HANDLERS = {
    SPELL_UPDATE_COOLDOWN = function() RefreshWhere("cd", IsCd) end,
    SPELL_UPDATE_CHARGES = function() RefreshWhere("cd", IsCd) end,
    SPELLS_CHANGED = function() RefreshWhere("cd", IsCd) end,
    -- your cast lands its cooldown before SPELL_UPDATE_COOLDOWN inside a charge
    -- GCD: the pictures on that spell re-read now
    UNIT_SPELLCAST_SUCCEEDED = function(_, unit, _, spellID)
        if unit ~= "player" or IsSecret(spellID) then return end
        K.ForEach("texture", function(e)
            if IsCd(e) and (e.rec.driver.spellID == spellID or TP.EffSpell(e.rec) == spellID) then TP.Refresh(e) end
        end)
    end,
    PLAYER_TARGET_CHANGED = function() TP.OnUnitSwap("target") end,
    PLAYER_FOCUS_CHANGED = function() TP.OnUnitSwap("focus") end,
    UNIT_PET = function(_, unit)
        if unit ~= nil and unit ~= "player" and not IsSecret(unit) then return end
        TP.OnUnitSwap("pet")
    end,
    GROUP_ROSTER_UPDATE = function() TP.OnUnitSwap("party") end,
    -- a hostility answer that was secret in combat is plain again
    PLAYER_REGEN_ENABLED = function() TP.OnUnitSwap(nil) end,
}

function TP.Needs()
    local n = {}
    K.ForEach("texture", function(e)
        local s = TP.Source(e.rec)
        if s == "spellCd" then
            n.SPELL_UPDATE_COOLDOWN, n.SPELL_UPDATE_CHARGES, n.SPELLS_CHANGED = true, true, true
            n.UNIT_SPELLCAST_SUCCEEDED = true
        elseif s == "rules" then
            n.custom = true
        else
            local unit, harmful = NS.DriverAura.ShapeOf(e.rec.driver)
            if unit == "target" then n.PLAYER_TARGET_CHANGED = true
            elseif unit == "focus" then n.PLAYER_FOCUS_CHANGED = true
            elseif unit == "pet" then n.UNIT_PET = true
            elseif unit:sub(1, 5) == "party" then n.GROUP_ROSTER_UPDATE = true end
            if harmful and (unit == "target" or unit == "focus") then n.PLAYER_REGEN_ENABLED = true end
        end
    end)
    return n
end

-- Arms and disarms against what the live pictures need; run after every
-- ensure and release.
function TP.Sync()
    local n = TP.Needs()
    for ev, fn in pairs(TP.HANDLERS) do
        if n[ev] and not TP.armed[ev] then
            TP.armed[ev] = true
            K.SafeOn(ev, TP.KEY, fn)
        elseif not n[ev] and TP.armed[ev] then
            TP.armed[ev] = nil
            NS.Events.Off(ev, TP.KEY)
        end
    end
    local CU = NS.DriverCustom
    if CU and CU.Watch then
        if n.custom and not TP.watching then
            TP.watching = true
            CU.Watch(TP.KEY, TP.OnCustomPaint)
        elseif not n.custom and TP.watching then
            TP.watching = nil
            CU.Unwatch(TP.KEY)
        end
    end
end

-- Kind registry hooks

function TP.Build(e)
    if e.tpHost then return end
    local shell = e.shell
    local host = CreateFrame("Frame", nil, shell)
    host:SetAllPoints(shell)
    host:SetFrameLevel(shell.overlay:GetFrameLevel() + 1)
    host:EnableMouse(false)
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    bg:Hide()
    local pic = host:CreateTexture(nil, "ARTWORK")
    pic:SetAllPoints(host)
    pic:Hide()
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetAllPoints(host)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
    e.tpHost, e.tpBg, e.tpPic, e.tpBar = host, bg, pic, bar
end

-- What another source held: the aura slot, the rules sink.
function TP.DropOthers(e, keep)
    if keep ~= "rules" and NS.DriverCustom and NS.DriverCustom.DetachText then NS.DriverCustom.DetachText(e.rec.id) end
    if keep ~= "aura" and e.tpAura then
        TP.ParkAura(e.tpAura)
        e.tpAura = nil
    end
    if keep ~= "spellCd" and e.tpCD then
        e.tpCD:Clear()
        e.tpCharge:Clear()
        e.tpMainDur, e.tpChargeDur, e.tpIsCharge = nil, nil, nil
    end
end

function TP.Ensure(e)
    local s = TP.Source(e.rec)
    TP.DropOthers(e, s)
    if s == "aura" then
        TP.EnsureAura(e)
    elseif s == "spellCd" then
        TP.FeedCooldown(e)
    end
    TP.Sync()
    -- the sink attaches after the watcher is armed: its first paint reaches us
    if s == "rules" and NS.DriverCustom and NS.DriverCustom.AttachText then
        NS.DriverCustom.AttachText(e.rec, e)
    end
    TP.Paint(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

function TP.Refresh(e)
    if TP.Source(e.rec) == "spellCd" then TP.FeedCooldown(e) end
    TP.Paint(e)
    e.stateHidden = false
    K.ApplyVisibility(e)
end

function TP.Release(e)
    TP.DropOthers(e, nil)
    e.tpGcdQueued = nil
    TP.Sync()
end

-- ApplyStyle draws the bar's chrome: put it all away, then dress the
-- picture, the dim copy and the fill (and the aura button's while accessible).
function TP.Styled(e)
    local shell, rec = e.shell, e.rec
    shell.fill:Hide()
    shell.bg:Hide()
    for _, t in pairs(shell.edges) do t:Hide() end
    if shell.borderF then shell.borderF:Hide() end
    shell.sheen:Hide()
    TP.Dress(e.tpBg, rec, true)
    e.tpBg:SetShown(R(rec, "texlook", "bgShow") == true)
    TP.Dress(e.tpPic, rec, false)
    TP.DressBar(e.tpBar, rec)
    local sub = e.tpAura
    if sub and sub.button then
        local DA = NS.DriverAura
        if not (DA and DA.IsAccessible) or DA.IsAccessible(sub.button) then
            if sub.bar then TP.DressBar(sub.bar, rec) end
            if sub.pic then TP.Dress(sub.pic, rec, false) end
        end
    end
end

function TP.Diag(e)
    local active, run = false, nil
    if TP.Source(e.rec) ~= "aura" then active, run = TP.StateOf(e) end
    return ("%s [texture %s %s] active=%s running=%s aura=%s button=%s"):format(tostring(e.rec.name),
        TP.Source(e.rec), TP.FillMode(e.rec) and "fill" or "show", tostring(active == true),
        tostring(run ~= nil), tostring(e.tpAura ~= nil), tostring(e.tpAura ~= nil and e.tpAura.button ~= nil))
end

-- Editor preview: the picture as it looks while active (a fill at 60%).

function TP.PreviewModes()
    return { { key = "static", text = "Preview", tip = "The picture as it looks while active; a fill stands at 60%." } }
end

function TP.PreviewApply(e)
    local rec = e.rec
    if TP.FillMode(rec) then
        e.tpPic:Hide()
        e.tpBar:Show()
        e.tpBar:SetMinMaxValues(0, 1)
        e.tpBar:SetValue(0.6)
    else
        e.tpBar:Hide()
        e.tpPic:Show()
    end
end

-- What the sidebar and the layout cards say about a picture.
function TP.Describe(rec)
    local s = TP.Source(rec)
    local d = rec.driver or {}
    local L = Schema.TEXTURE_SOURCE_LABELS or {}
    local base = L[s] or s
    if s == "aura" then
        base = base .. ": " .. (d.spellID and tostring(d.spellID) or "no aura")
    elseif s == "spellCd" then
        local nm = d.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(d.spellID)
        if IsSecret(nm) then nm = nil end
        base = "Cooldown: " .. (nm or (d.spellID and ("spell " .. d.spellID)) or "no spell")
    else
        local n = type(d.rules) == "table" and #d.rules or 0
        base = base .. ", " .. n .. (n == 1 and " rule" or " rules")
    end
    return base .. (TP.FillMode(rec) and ", fill" or "")
end

Bars.RegisterKind("texture", {
    Build = TP.Build,
    Ensure = TP.Ensure,
    Refresh = TP.Refresh,
    Release = TP.Release,
    Styled = TP.Styled,
    Diag = TP.Diag,
    ownsName = true,
    PreviewModes = TP.PreviewModes,
    PreviewApply = TP.PreviewApply,
})
