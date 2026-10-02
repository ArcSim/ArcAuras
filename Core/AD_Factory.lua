-- Icon factory: builds and styles every icon frame, the aura engine's buttons
-- included. Drivers never style anything; they report state (Factory.SetState)
-- or feed the swipe (frame.cooldown). ApplyStyle is the only style writer.

local ADDON, NS = ...
local Store = NS.Store

local Factory = {}
NS.Factory = Factory

local QUESTION_MARK = 134400
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BORDER_KEYS = { "top", "bottom", "left", "right" }
-- Ammo inventory slot (INVSLOT_AMMO on Forever and retail; 0 as a fallback).
local AMMO_SLOT = INVSLOT_AMMO or 0
NS.AMMO_SLOT = AMMO_SLOT

-- Glow frame level above the icon. The glow library's default +1 is under the
-- swipe (+2), which then paints over the glow whatever the draw layer.
-- Passed to every Start; unlike strata, it can't leak via the pool.
local GLOW_LEVEL = 7
NS.GLOW_LEVEL = GLOW_LEVEL

local frames = {}    -- [iconId] = frame
Factory.frames = frames

-- Live art of a toggle: on Forever GetSpellTexture never changes for toggles
-- such as Stealth, but the action button holding the spell swaps texture while
-- it is on, and so does its stance-bar entry. Secret textures paint fine; the
-- form count and IDs are checked before any loop or compare.
-- FindSpellActionButtons returns every filled slot on Forever, so the bars
-- (slots 1-180; gamepad storage lies above) are walked main bar first, keying
-- each spell slot by ID, base spell and name, as Forever ranks are separate
-- IDs sharing a name. The swap is rank-specific, so the rank the name resolves
-- to is tried first. A secret read keeps the old map and retries after combat.
local ART_BARS = { 1, 61, 49, 25, 37, 145, 157, 169, 13, 73, 85, 97, 109, 121, 133 }
local artSlots, artDirty, artRetry = {}, true, false
-- [sid] = its slot, or false for none; kept until the map is rebuilt, and
-- only answers read with no secret in them are kept
local slotOf = {}
local sawSecretRead = false

local function Plain(v)
    if issecretvalue and issecretvalue(v) then
        sawSecretRead = true
        return nil
    end
    return v
end

local function ArtRebuild()
    artDirty = false
    wipe(slotOf)
    local fresh, sawSecret = {}, false
    local function remember(key, slot)
        if key ~= nil and fresh[key] == nil then fresh[key] = slot end
    end
    for _, start in ipairs(ART_BARS) do
        for slot = start, start + 11 do
            local atype, id = GetActionInfo(slot)
            if issecretvalue and (issecretvalue(atype) or issecretvalue(id)) then
                sawSecret = true
            elseif atype == "spell" and type(id) == "number" then
                remember(id, slot)
                if C_Spell.GetBaseSpell then remember(Plain(C_Spell.GetBaseSpell(id)), slot) end
                if NS.IsForever == true and C_Spell.GetSpellName then
                    local nm = Plain(C_Spell.GetSpellName(id))
                    if type(nm) == "string" and nm ~= "" then remember("n:" .. nm, slot) end
                end
            end
        end
    end
    if sawSecret then
        for k, v in pairs(artSlots) do
            if fresh[k] == nil then fresh[k] = v end
        end
        artRetry = true
    end
    artSlots = fresh
end

local function ArtSlotFor(sid)
    if artDirty then ArtRebuild() end
    local hit = slotOf[sid]
    if hit ~= nil then return hit or nil end
    sawSecretRead = false
    local slot
    local nm = NS.IsForever == true and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(sid)) or nil
    if type(nm) ~= "string" or nm == "" then nm = nil end
    if nm and C_Spell.GetSpellIDForSpellIdentifier then
        local cur = Plain(C_Spell.GetSpellIDForSpellIdentifier(nm))
        if cur ~= nil then slot = artSlots[cur] end
    end
    if slot == nil then slot = artSlots[sid] end
    if slot == nil and C_Spell.GetBaseSpell then
        local base = Plain(C_Spell.GetBaseSpell(sid))
        if base ~= nil then slot = artSlots[base] end
    end
    if slot == nil and nm then slot = artSlots["n:" .. nm] end
    if not sawSecretRead then slotOf[sid] = slot or false end
    return slot
end

do
    local function dirty() artDirty = true end
    local function valid(e)
        return (not (C_EventUtils and C_EventUtils.IsEventValid)) or C_EventUtils.IsEventValid(e)
    end
    for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        if valid(e) then NS.Events.On(e, "adart_slots", dirty) end
    end
    if valid("PLAYER_REGEN_ENABLED") then
        NS.Events.On("PLAYER_REGEN_ENABLED", "adart_slots", function()
            if artRetry then artRetry = false; artDirty = true end
        end)
    end
end

local function LiveSpellArt(sid)
    local a = ArtSlotFor(sid)
    if a then
        local tex = GetActionTexture(a)
        if tex then return tex end
    end
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local n = GetNumShapeshiftForms()
        if not (issecretvalue and issecretvalue(n)) and type(n) == "number" then
            for i = 1, n do
                local icon, _, _, fsid = GetShapeshiftFormInfo(i)
                if not (issecretvalue and issecretvalue(fsid)) and fsid == sid and icon then
                    return icon
                end
            end
        end
    end
    return nil
end
Factory.LiveSpellArt = LiveSpellArt

local ammoEmptyTex
function Factory.AmmoEmptyTexture()
    if ammoEmptyTex == nil then
        local tex
        if NS.IsForever == true and GetInventorySlotInfo then
            local _, t = GetInventorySlotInfo("AmmoSlot")
            if type(t) == "string" and t ~= "" then tex = t end
        end
        ammoEmptyTex = tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo"
    end
    return ammoEmptyTex
end

-- An icon override, read the way its `<x>IconFrom` pick says (the kind can't be
-- guessed): "icon" = a file ID as is, "spell" = the spell's art, "item" = the
-- item's icon if it exists, since an unknown item gets the question mark.
local function OverrideTexture(ov, from)
    if type(ov) ~= "number" or ov <= 0 then return nil end
    if from == "spell" then
        local tex = C_Spell.GetSpellTexture(ov)
        return tex
    elseif from == "item" then
        if not (C_Item and C_Item.GetItemIconByID) then return nil end
        if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(ov) then return nil end
        return C_Item.GetItemIconByID(ov)
    end
    return ov
end

local function OverrideFor(rec, section, field)
    return OverrideTexture(Store.Resolve(rec, section, field),
        Store.Resolve(rec, section, field .. "From"))
end

-- Art override for the live aura button: Aura Active's icon, else the Custom
-- icon. A spell icon's aura overlay wears the spell's art unless "Icon while
-- the aura is up" picks the aura's (nil = the aura's own art).
function Factory.AuraActiveTexture(rec)
    local ov = OverrideFor(rec, "auraActive", "activeIcon")
    if ov then return ov end
    if rec.kind ~= "aura" then
        if Store.Resolve(rec, "auraActive", "overlayArt") == "aura" then return nil end
        return Factory.GetTexture(rec)
    end
    return OverrideFor(rec, "appearance", "customIcon")
end

-- A spell icon's own art. It follows the override spell unless the icon pins
-- the base spell. GetSpellTexture gives (icon, originalIcon); on Forever
-- neither moves for a toggle, so active art comes from the action bar.
local function SpellArt(d, activeArt)
    local sid = d.spellID
    if sid and not d.ignoreSpellOverride and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if ov and ov ~= 0 then sid = ov end
    end
    if not sid then return QUESTION_MARK end
    if activeArt then
        local live = LiveSpellArt(sid)
        if live then return live end
        return C_Spell.GetSpellTexture(sid) or QUESTION_MARK
    end
    local tex, orig = C_Spell.GetSpellTexture(sid)
    return orig or tex or QUESTION_MARK
end

-- The kind's own art, ignoring overrides: what the game itself would show.
local function KindTexture(rec)
    local d = rec.driver or {}
    local kind = rec.kind
    if kind == "spell" then
        return SpellArt(d, Store.Resolve(rec, "appearance", "activeArt") ~= false)
    elseif kind == "aura" or kind == "timer" or kind == "groupbuff" then
        local tex = d.spellID and C_Spell.GetSpellTexture(d.spellID)
        return tex or QUESTION_MARK
    elseif kind == "trinket" then
        local tex = d.slotID and GetInventoryItemTexture("player", d.slotID)
        return tex or QUESTION_MARK
    elseif kind == "item" then
        -- an icon with several items wears the one it shows
        local DC = NS.DriverCooldown
        local iid = (DC and DC.LiveItem and DC.LiveItem(rec)) or d.itemID
        local tex = iid and C_Item.GetItemIconByID and C_Item.GetItemIconByID(iid)
        return tex or QUESTION_MARK
    elseif kind == "ammo" then
        -- Current ammo art, so swapping arrows re-arts the icon; an empty slot
        -- shows the character sheet's empty-ammo art, not the question mark.
        return GetInventoryItemTexture("player", AMMO_SLOT) or Factory.AmmoEmptyTexture()
    elseif kind == "totem" then
        -- an icon following the totem bar shows the totem it would drop while
        -- its slot is empty (NS.DriverTotem)
        local DT = NS.DriverTotem
        if DT and DT.BarShows then
            local _, barTex = DT.BarShows(rec)
            if barTex then return barTex end
        end
        -- haveTotem is a secret boolean, so it is never tested. The icon is
        -- only painted, and SetTexture takes a secret. A totem followed by
        -- spell shows its spell's art while it is not down.
        local slot = d.slot or 1
        if NS.DriverTotem then slot = NS.DriverTotem.SlotFor(rec) end
        if slot and GetTotemInfo then
            local _, _, _, _, icon = GetTotemInfo(slot)
            if icon then return icon end
        end
        local tex = d.spellID and C_Spell.GetSpellTexture(d.spellID)
        return tex or QUESTION_MARK
    elseif kind == "enchant" then
        -- the enchant's own art while it is on, else the weapon's
        local E = NS.DriverEnchant
        local e = E and E.Read(rec)
        if e and e.icon then return e.icon end
        return GetInventoryItemTexture("player", E and E.InvSlot(rec) or 16) or QUESTION_MARK
    elseif kind == "special" then
        -- the tracker's own art (Core\AD_SpecialIcon.lua; nil without the hub)
        return NS.SpecialIcon and NS.SpecialIcon.Texture(rec) or QUESTION_MARK
    end
    return QUESTION_MARK
end

-- A record's art. A custom icon override wins on every kind. An aura icon's
-- holder is its missing look, so Aura Missing's own icon comes first there.
function Factory.GetTexture(rec)
    local ovTex = rec.kind == "aura"
        and OverrideFor(rec, "auraMissing", "missingIcon") or nil
    ovTex = ovTex or OverrideFor(rec, "appearance", "customIcon")
    if ovTex then return ovTex end
    return KindTexture(rec)
end

-- The art pass runs on busy events (ACTIONBAR_UPDATE_STATE, UNIT_AURA), so a
-- spell icon re-reads there only what can move, its override spell and live
-- button art, with its settings kept until the next change, and paints only
-- a new texture. ApplyStyle records what it painted in f._adArt.
local artGen = 0
NS.Events.OnMessage("AD_DIRTY", "adart_cfg", function() artGen = artGen + 1 end)

local function PaintArt(f, tex)
    -- a secret texture paints fine but is never compared
    if issecretvalue and issecretvalue(tex) then
        f._adArt = nil
    elseif tex == f._adArt then
        return
    else
        f._adArt = tex
    end
    f.icon:SetTexture(tex)
end

-- GetTexture's answer for a spell icon, from the cached settings.
function Factory.RefreshArt(f, rec)
    if f._adArtGen ~= artGen or f._adArtRec ~= rec then
        f._adArtGen, f._adArtRec = artGen, rec
        f._adArtOv = Store.Resolve(rec, "appearance", "customIcon")
        f._adArtOvFrom = Store.Resolve(rec, "appearance", "customIconFrom")
        f._adArtActive = Store.Resolve(rec, "appearance", "activeArt") ~= false
    end
    PaintArt(f, OverrideTexture(f._adArtOv, f._adArtOvFrom)
        or SpellArt(rec.driver or {}, f._adArtActive))
end

-- The art the live aura button shows (the preview's "aura up" phase draws it):
-- the Active override, else the aura's own art, approximated by its spell's.
function Factory.AuraLiveTexture(rec)
    return Factory.AuraActiveTexture(rec) or KindTexture(rec)
end
-- The preview's stand-in engine button takes this as the engine's art.
Factory.KindTexture = KindTexture

local function BuildFrame(rec)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:EnableMouse(false)

    -- Tooltip scripts are wired once; the record is looked up at hover time
    -- through f._adRecId, as frames are reused across records.
    f:SetScript("OnEnter", function(self)
        local editing = NS.LayoutEngine and NS.LayoutEngine.IsEditMode
            and NS.LayoutEngine.IsEditMode()
        -- Edit-only tooltips: on hover while the options window is open, never
        -- with a mouse button held (a drag is starting).
        if Store.GetSetting("tooltipsEditOnly") == true then
            if not editing or IsMouseButtonDown() then return end
            local er = Store.Get(self._adRecId)
            if not er then return end
            if Store.MouseFor and (Store.MouseFor(er)) == false then return end
            Factory.ShowTooltip(self, er)
            return
        end
        if editing then return end
        -- ApplyMouse's tier result; nil falls back to the addon setting.
        local tipsOn = self._adTipsOn
        if tipsOn == nil then tipsOn = Store.GetSetting("showTooltips") ~= false end
        if tipsOn == false then return end
        local r = Store.Get(self._adRecId)
        if r then Factory.ShowTooltip(self, r) end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()

    -- The border is four edge textures on their own host (ApplyBorder);
    -- backdrop edges render unreliably at 1px.

    -- Swipe: drivers feed it, ApplyStyle styles it, on the template's own art:
    -- the Cooldown Manager's textures have a shorter edge that stops partway
    -- across the icon and a pre-darkened swipe that shifts the cooldown color.
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawBling(true)
    f.cooldown:SetHideCountdownNumbers(false)
    -- Numbers draw only above this total duration; the default hides a 2 s
    -- cooldown. 1600 ms sits between Forever's 1.5 s GCD and a 2 s cooldown.
    if f.cooldown.SetMinimumCountdownDuration then f.cooldown:SetMinimumCountdownDuration(1600) end

    -- Texts live on a child frame so they draw above the swipe.
    f.textHost = CreateFrame("Frame", nil, f)
    f.textHost:SetAllPoints()
    f.textHost:SetFrameLevel(f.cooldown:GetFrameLevel() + 2)
    f.stackText = f.textHost:CreateFontString(nil, "OVERLAY")
    f.stackText:SetDrawLayer("OVERLAY", 7)
    f.stackText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    f.stackText:SetPoint("BOTTOMRIGHT", -2, 2)

    -- Own fontstring: a charge spell can show charges and arrows at once.
    f.ammoText = f.textHost:CreateFontString(nil, "OVERLAY")
    f.ammoText:SetDrawLayer("OVERLAY", 7)
    f.ammoText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    f.ammoText:SetPoint("BOTTOMLEFT", 2, 2)
    f.ammoText:Hide()

    f.labelText = f.textHost:CreateFontString(nil, "OVERLAY")
    f.labelText:SetDrawLayer("OVERLAY", 7)
    f.labelText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    f.labelText:SetPoint("CENTER", 0, 0)
    f.labelText:Hide()

    -- Keybind text: the cooldown driver fills it, ApplyStyle styles it.
    f.keybindText = f.textHost:CreateFontString(nil, "OVERLAY")
    f.keybindText:SetDrawLayer("OVERLAY", 7)
    f.keybindText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    f.keybindText:SetPoint("TOPLEFT", 2, -2)
    f.keybindText:Hide()

    -- Custom labels 2 and 3
    f.labelText2 = f.textHost:CreateFontString(nil, "OVERLAY")
    f.labelText2:SetDrawLayer("OVERLAY", 7)
    f.labelText2:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    f.labelText2:SetPoint("TOP", 0, -2)
    f.labelText2:Hide()
    f.labelText3 = f.textHost:CreateFontString(nil, "OVERLAY")
    f.labelText3:SetDrawLayer("OVERLAY", 7)
    f.labelText3:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    f.labelText3:SetPoint("BOTTOM", 0, 2)
    f.labelText3:Hide()

    f._adOnCooldown = false
    f._adDesatState = false
    return f
end

function Factory.Ensure(rec)
    local f = frames[rec.id]
    if not f then
        f = BuildFrame(rec)
        frames[rec.id] = f
    end
    f._adRecId = rec.id
    return f
end

-- Countdown formatters. SetCountdownFormatter with a NumericRuleFormatter
-- formats C-side from the real remaining time, so decimals and color bands
-- work on secret durations with no reads or ticks. The bars use them too.
local fmtCache = {}

-- Timer rounding: "up" (default) counts like Blizzard's cooldown numbers,
-- "down" like buff timers. The stock Cooldown text rounds up and the aura
-- engine's text down, so each needs a formatter only for the other way.
function Factory.TimerRounding()
    return (Store.GetSetting("timerRounding") == "down") and "down" or "up"
end

-- An icon's own rounding (Text > Duration Text > Round timer numbers), else
-- the Settings one. Bars resolve theirs in AD_Bars and pass it as roundMode.
function Factory.IconRounding(rec)
    local v = rec and Store.Resolve(rec, "text", "durationRounding")
    if v == "up" or v == "down" then return v end
    return Factory.TimerRounding()
end

local function ColorEscape(c)
    return string.format("|c%02x%02x%02x%02x", 255,
        math.floor((c[1] or 1) * 255 + 0.5),
        math.floor((c[2] or 1) * 255 + 0.5),
        math.floor((c[3] or 1) * 255 + 0.5))
end

-- decTo = decimal threshold in seconds (0 = none). bands = list of
-- { t = seconds, c = {r,g,b} }, baked in as color escapes since aura durations
-- can't be read; above the top band the fontstring's own color shows.
-- roundMode: "up" | "down" | nil (the Settings choice).
function Factory.GetCountdownFormatter(decTo, bands, abbrev, roundMode)
    decTo = tonumber(decTo) or 0
    if decTo > 60 then decTo = 60 end
    abbrev = tonumber(abbrev) or 0
    if abbrev <= 60 then abbrev = 0 end
    local nBands = (type(bands) == "table") and #bands or 0
    if decTo <= 0 and nBands == 0 and abbrev == 0 then return nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local CN = GetLocale and GetLocale() == "zhCN"
    if CN then decTo = 0 end   -- decimal refreshes can crash the zhCN client
    local mode = roundMode or Factory.TimerRounding()
    local parts = { tostring(decTo), tostring(abbrev), mode }
    for i = 1, nBands do
        local b = bands[i]
        parts[#parts + 1] = string.format("%g:%.2f,%.2f,%.2f",
            b.t, b.c[1] or 1, b.c[2] or 1, b.c[3] or 1)
    end
    local sig = table.concat(parts, "|")
    if fmtCache[sig] then return fmtCache[sig] end

    local sorted = {}
    for i = 1, nBands do sorted[i] = bands[i] end
    table.sort(sorted, function(a, b) return a.t < b.t end)

    -- Breakpoints: 0, 60, 3600, the decimal and M:SS thresholds, band edges.
    local edgeSet = { [0] = true, [60] = true, [3600] = true }
    if decTo > 0 and decTo < 60 then edgeSet[decTo] = true end
    if abbrev > 60 and abbrev < 3600 then edgeSet[abbrev] = true end
    for _, b in ipairs(sorted) do
        if b.t > 0 and b.t < 3600 then edgeSet[b.t] = true end
    end
    local edges = {}
    for v in pairs(edgeSet) do edges[#edges + 1] = v end
    table.sort(edges)

    local Up = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    -- whole seconds, minutes and hours all round the way the setting says
    local Round = Up
    if mode == "down" then
        Round = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
    end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    if not f then return nil end
    for _, lo in ipairs(edges) do
        -- band color for [lo, next): the first band whose edge is above lo
        local esc
        for _, b in ipairs(sorted) do
            if lo < b.t then esc = ColorEscape(b.c) break end
        end
        local Down = Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
        local fmt, comps, step
        if lo >= 3600 then
            fmt, comps, step = "%d h", { { div = 3600 } }, 3600
        elseif lo >= 60 then
            if abbrev > 60 and lo < abbrev then
                -- M:SS below the abbreviation threshold, both floored.
                fmt = "%d:%02d"
                comps = {
                    { div = 60, step = 1, rounding = Down },
                    { mod = 60, step = 1, rounding = Down },
                }
            else
                fmt, comps, step = "%d m", { { div = 60 } }, 60
            end
        elseif (not CN) and lo < decTo then
            fmt = "%.1f"
        else
            -- Stepped with the setting's rounding: "%.0f" rounds to nearest,
            -- so an icon with decimals or bands would read one off plain ones.
            fmt, step = "%d", 1
        end
        local bp = { threshold = lo, format = esc and (esc .. fmt .. "|r") or fmt }
        if comps then bp.components = comps end
        if step then
            bp.step = step
            if Round then bp.rounding = Round end
        end
        f:AddBreakpoint(bp)
    end
    fmtCache[sig] = f
    return f
end

-- A countdown with no options. aura = the aura engine's look ("13 s", seconds
-- up to 90 like its own text), else the Cooldown widget's ("13").
local function PlainTimerFormatter(mode, aura)
    local key = "plain|" .. mode .. (aura and "|aura" or "")
    if fmtCache[key] ~= nil then return fmtCache[key] or nil end
    local E = Enum.NumericRuleFormatRounding
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and E) then
        fmtCache[key] = false
        return nil
    end
    local Round = (mode == "down") and E.Down or E.Up
    local minAt, hourAt = 60, 3600
    local secF, minF, hourF = "%d", "%d m", "%d h"
    if aura then
        -- the client's own one-letter units, as the engine's text uses
        -- them, when each is a plain "%d" + unit; else the English ones
        local function Unit(g, fallback)
            if type(g) == "string" and g:find("%d", 1, true) and not g:find("|", 1, true)
                and select(2, g:gsub("%%", "")) == 1 then
                return g
            end
            return fallback
        end
        minAt, hourAt = 91, 5401
        secF = Unit(SECOND_ONELETTER_ABBR, "%d s")
        minF = Unit(MINUTE_ONELETTER_ABBR, "%d m")
        hourF = Unit(HOUR_ONELETTER_ABBR, "%d h")
    end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    if not f then
        fmtCache[key] = false
        return nil
    end
    f:AddBreakpoint({ threshold = 0, format = secF, step = 1, rounding = Round })
    f:AddBreakpoint({ threshold = minAt, format = minF, components = { { div = 60 } },
        step = 60, rounding = Round })
    f:AddBreakpoint({ threshold = hourAt, format = hourF, components = { { div = 3600 } },
        step = 3600, rounding = Round })
    fmtCache[key] = f
    return f
end

-- The formatter for any countdown text: the options one for decimals, colour
-- bands or M:SS, else a plain one when the stock text rounds the other way.
-- stock: "up" (a Cooldown widget) or "down" (aura engine). nil = keep stock.
function Factory.TimerFormatter(decTo, bands, abbrev, stock, roundMode)
    local fmt = Factory.GetCountdownFormatter(decTo, bands, abbrev, roundMode)
    if fmt then return fmt end
    local mode = roundMode or Factory.TimerRounding()
    stock = stock or "up"
    if mode == stock then return nil end
    return PlainTimerFormatter(mode, stock == "down")
end

-- The same rules in plain Lua, for countdowns our own GetTime math drives
-- (timer and swing bars): seconds, tenths under decTo, M:SS under abbrev,
-- then minutes and hours; whole units round the way roundDown says.
function Factory.FormatCountdown(t, decTo, abbrev, roundDown)
    local Rn = roundDown and math.floor or math.ceil
    if t >= 3600 then return string.format("%d h", Rn(t / 3600)) end
    if t >= 60 then
        if (abbrev or 0) > 60 and t < abbrev then
            local s = math.floor(t)
            return string.format("%d:%02d", math.floor(s / 60), s % 60)
        end
        return string.format("%d m", Rn(t / 60))
    end
    if (decTo or 0) > 0 and t < decTo then return string.format("%.1f", t) end
    return string.format("%d", Rn(t))
end

-- The icon's countdown formatter and signature (holder and aura button alike).
local function CountdownFormatterFor(rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local decTo, bands, abbrev = 0, nil, 0
    if R("text", "durationText") ~= false then
        abbrev = R("text", "durationAbbrev") or 0
        if R("text", "durationDecimals") == true then
            decTo = R("text", "durationDecimalThreshold") or 10
        end
        if R("text", "durationColorBands") == true then
            bands = {}
            -- only the bands in play ("+ Add band"); 0 seconds is still off
            local count = math.max(1, math.min(3, math.floor(tonumber(R("text", "durBandCount")) or 1)))
            for i = 1, count do
                local secs = R("text", "durBand" .. i .. "Sec") or 0
                if secs > 0 then
                    bands[#bands + 1] = {
                        t = secs,
                        c = R("text", "durBand" .. i .. "Color") or { 1, 1, 1, 1 },
                    }
                end
            end
            if #bands == 0 then bands = nil end
        end
    end
    -- Rounding is in the signature, so changing it re-pushes the formatter.
    local mode = Factory.IconRounding(rec)
    local sig = tostring(decTo) .. "/" .. tostring(abbrev) .. "/" .. mode
    if bands then
        for _, b in ipairs(bands) do
            sig = sig .. "|" .. b.t .. ":"
                .. (b.c[1] or 1) .. "," .. (b.c[2] or 1) .. "," .. (b.c[3] or 1)
        end
    end
    return Factory.TimerFormatter(decTo, bands, abbrev, nil, mode), sig
end

-- Aura stack formatter: the engine prints a count only above 1 unless handed a
-- NumericRuleFormatter, whose breakpoints carry show-at-1 and the color bands
-- so the secret count never reaches Lua. off = every count formats to "" (the
-- engine owns Shown). Returns formatter (nil = engine default), signature.
local stkFmtCache = {}
function Factory.GetStackFormatter(rec, off)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil, "none"
    end
    if off then
        if not stkFmtCache.off then
            local f = C_StringUtil.CreateNumericRuleFormatter()
            f:AddBreakpoint({ threshold = 0, format = "" })
            stkFmtCache.off = f
        end
        return stkFmtCache.off, "off"
    end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local single = R("text", "stackShowSingle") == true
    local bands
    if R("text", "stackColorBands") == true then
        bands = {}
        -- only the bands in play ("+ Add band")
        local count = math.max(1, math.min(3, math.floor(tonumber(R("text", "stkBandCount")) or 1)))
        for i = 1, count do
            local m = R("text", "stkBand" .. i .. "Min") or 0
            if m > 0 then
                bands[#bands + 1] = { m = m, c = R("text", "stkBand" .. i .. "Color") or { 1, 1, 1, 1 } }
            end
        end
        if #bands == 0 then bands = nil end
    end
    if not single and not bands then return nil, "default" end
    local showFrom = single and 1 or 2
    -- one format per threshold (a band starting at the show-from count
    -- simply colors it); sorted so the signature is stable
    local byThr = { [0] = "", [showFrom] = "%d" }
    if bands then
        for _, b in ipairs(bands) do
            byThr[math.max(b.m, showFrom)] = ColorEscape(b.c) .. "%d|r"
        end
    end
    local thr = {}
    for t in pairs(byThr) do thr[#thr + 1] = t end
    table.sort(thr)
    local parts = {}
    for _, t in ipairs(thr) do parts[#parts + 1] = t .. "=" .. byThr[t] end
    local sig = table.concat(parts, "|")
    if stkFmtCache[sig] then return stkFmtCache[sig], sig end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    for _, t in ipairs(thr) do
        f:AddBreakpoint({ threshold = t, format = byThr[t] })
    end
    stkFmtCache[sig] = f
    return f, sig
end

-- A style preview: a real factory frame, never attached to a driver or pooled
-- by record ID. The options panel drives it with a fake looping cooldown.
function Factory.CreatePreview(parent)
    local f = BuildFrame({})
    f:SetParent(parent)
    f:EnableMouse(false)
    f._adPreview = true
    return f
end

function Factory.Release(id)
    local f = frames[id]
    if f then
        -- an icon leaving the screen takes its Play on screen copy with it
        if NS.IconScreen and NS.IconScreen.On(id) then NS.IconScreen.Stop() end
        Factory.StopGlow(f)   -- ready + proc + aura lanes
        Factory.StopUsableGlow(f)
        f._adStateSig = nil   -- the lanes just stopped: the next feed repaints
        if NS.DriverWarn then NS.DriverWarn.Drop(f) end
        f._adPureGCD = nil   -- pooled frames must not carry GCD presentation
        f._adPureWand = nil
        f._adRecharging = nil
        f._adTipsOn = nil
        f:Hide()
        f:ClearAllPoints()
    end
end

-- State dim: it covers the whole icon but never uses f:SetAlpha, as the
-- frame's alpha belongs to ApplyFrameAlpha and child alpha multiplies (texts
-- could never stay bright), nor f.cooldown:SetAlpha, whose frame holds the
-- countdown fontstring. The swipe and edge dim by their colour instead.
local function ApplySwipeAlpha(f)
    -- The shown alpha (with the editing floor), not the raw state value.
    local a = f._adShownAlpha or f._adStateAlpha or 1
    local sc = f._adSwipeColor
    -- a GCD or wand spin draws in its own colour
    if f._adPureGCD then sc = (f._adPureWand and f._adWandSwipeColor or f._adGcdSwipeColor) or sc end
    if sc then f.cooldown:SetSwipeColor(sc[1], sc[2], sc[3], (sc[4] or 0.8) * a) end
    local ec = f._adEdgeColor
    if ec and f.cooldown.SetEdgeColor then
        f.cooldown:SetEdgeColor(ec[1], ec[2], ec[3], (ec[4] or 1) * a)
    end
end
Factory.ApplySwipeAlpha = ApplySwipeAlpha

-- The duration and stack texts' one colour writer. A fontstring's text colour
-- and its alpha are one channel, so a SetAlpha after SetTextColor wiped the
-- colour's own alpha: the colour (_adTextRGBA) and the dim (_adTextA) are kept
-- and always written together. ta: a new dim, nil keeps the last.
local function PaintText(fs, ta)
    if ta ~= nil then fs._adTextA = ta end
    local c = fs._adTextRGBA
    if c then
        fs:SetTextColor(c[1], c[2], c[3], (c[4] or 1) * (fs._adTextA or 1))
    else
        fs:SetAlpha(fs._adTextA or 1)
    end
end

-- With the options panel open, a dimmer look shows at the preview opacity so
-- it can be edited; closing rebuilds.
local function EditFloor(a)
    if NS.LayoutEngine and NS.LayoutEngine.IsEditMode and NS.LayoutEngine.IsEditMode() then
        local pv = Store.GetSetting("previewAlpha")
        if pv == nil then pv = 0.35 end
        if a < pv then return pv end
    end
    return a
end

-- The one writer for every dim (cooldown, aura missing, out of stock). Each
-- caller resolves preserveText from its own option.
local function ApplyStateAlpha(f, a, preserveText)
    -- f._adStateAlpha keeps the real value for the dynamic-group signature;
    -- the shown one has the editing floor. Later writers on the same art
    -- (tint, swipe) must use f._adShownAlpha; a raw 0 would undo the preview.
    f._adStateAlpha = a
    local shown = EditFloor(a)
    f._adShownAlpha = shown
    a = shown
    f.icon:SetAlpha(a)
    if f._adShadow then f._adShadow:SetAlpha(a) end
    ApplySwipeAlpha(f)
    if f._adBorderHost then f._adBorderHost:SetAlpha(a) end
    -- A fully hidden icon hides its texts too, whatever preserveText says.
    local ta = (a > 0 and preserveText) and 1 or a
    if f.textHost then f.textHost:SetAlpha(ta) end
    -- Labels kept to the aura's absence live under the button, not on the host.
    if f._adMissClip then f._adMissClip:SetAlpha(ta) end
    if f._adMissGlow then f._adMissGlow:SetAlpha(a) end
    -- The charge count's low host (aura overlay) dims like the text host.
    if f._adLowText then f._adLowText:SetAlpha(ta) end
    if f.stackText then PaintText(f.stackText, ta) end
    if f.cooldown.GetCountdownFontString then
        local cfs = f.cooldown:GetCountdownFontString()
        if cfs then PaintText(cfs, ta) end
    end
end

-- Border geometry: four strips on `edges` around `anchor`, shared by the
-- holder and the live aura button so an aura icon's two borders match. They
-- grow inward from the offset line (negative = outside); thickness snaps to
-- whole pixels with a 1px floor, the offset with none. A secret scale would
-- throw inside PixelUtil, so UIParent's stands in. A scaled preview snaps on
-- its _adPxRef's grid, as the live icon does, floored at one own pixel.
local function PaintBorderEdges(edges, anchor, rec, alpha, geometryOnly)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    local c = R("appearance", "borderColor") or { 0, 0, 0, 1 }
    local th = R("appearance", "borderThickness") or 2
    local off = R("appearance", "borderInset") or -3
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        local ref = anchor._adPxRef
        local es = (ref or anchor):GetEffectiveScale()
        if es == nil or (issecretvalue and issecretvalue(es)) then
            es = UIParent:GetEffectiveScale()
        end
        th = PixelUtil.GetNearestPixelSize(th, es, 1)
        off = PixelUtil.GetNearestPixelSize(off, es, 0)
        if ref then
            local own = PixelUtil.GetNearestPixelSize(0, anchor:GetEffectiveScale(), 1)
            if th < own then th = own end
        end
    end
    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", anchor, "TOPLEFT", off, -off)
    edges.top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -off, -off)
    edges.top:SetHeight(th)
    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", off, off)
    edges.bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -off, off)
    edges.bottom:SetHeight(th)
    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", anchor, "TOPLEFT", off, -off)
    edges.left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", off, off)
    edges.left:SetWidth(th)
    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -off, -off)
    edges.right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -off, off)
    edges.right:SetWidth(th)
    -- geometryOnly: the engine owns colour and visibility (dispel border).
    if geometryOnly then return off + th end
    local a = (c[4] or 1) * (alpha or 1)
    for _, k in ipairs(BORDER_KEYS) do
        edges[k]:SetVertexColor(c[1], c[2], c[3], a)
        edges[k]:Show()
    end
    return off + th   -- the strips' inside edge, where a swipe stops
end
-- Exported: a group buff's combat layers wear the icon's border.
Factory.PaintBorderEdges = PaintBorderEdges

-- The live aura button's own border, on the engine button so it shows and
-- hides with the aura and never carries the missing alpha (the button has no
-- border; CustomAuraButtonSharedMixin exposes only widget slots). OVERLAY 6
-- on its TextOverlay: above the swipe, under the texts. Accessible passes only.
local function ApplyAuraButtonBorder(b, rec, show, alpha)
    local edges = b._adBtnEdges
    if show then
        if not edges then
            local host = b.TextOverlay or b
            edges = {}
            for _, k in ipairs(BORDER_KEYS) do
                local t = host:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetColorTexture(1, 1, 1, 1)
                edges[k] = t
            end
            b._adBtnEdges = edges
        end
        PaintBorderEdges(edges, b, rec, alpha)
    elseif edges then
        for _, t in pairs(edges) do t:Hide() end
    end
end

-- Dispel-type border: strips handed to the engine (AddDispelTypeTexture,
-- PreserveAsset), which shows them for auras of the icon's lane, tinted by
-- dispel type; untyped auras take the border colour ("None"). No Lua reads the
-- type, so it works in combat. Accessible passes only; returns true when on.
local function ApplyAuraButtonDispel(b, rec, on, alpha)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    local canEngine = b.AddDispelTypeTexture ~= nil and b.RemoveDispelTypeTexture ~= nil
        and styles ~= nil and styles.PreserveAsset ~= nil
    local edges = b._adDispelEdges
    if not (on and canEngine) then
        if edges and b._adDispelSig then
            for _, k in ipairs(BORDER_KEYS) do
                b:RemoveDispelTypeTexture(edges[k])
                edges[k]:Hide()
            end
            b._adDispelSig = nil
        end
        return false
    end
    if not edges then
        local host = b.TextOverlay or b
        edges = {}
        for _, k in ipairs(BORDER_KEYS) do
            local t = host:CreateTexture(nil, "OVERLAY", nil, 6)
            t:SetColorTexture(1, 1, 1, 1)
            edges[k] = t
        end
        b._adDispelEdges = edges
    end
    -- geometry only: the engine owns their colour and whether they show
    PaintBorderEdges(edges, b, rec, 1, true)
    for _, k in ipairs(BORDER_KEYS) do edges[k]:SetAlpha(alpha or 1) end
    local harmful = false
    if NS.DriverAura and NS.DriverAura.ShapeOf then
        local _, h = NS.DriverAura.ShapeOf(rec.driver)
        harmful = h == true
    end
    local borderOn = R("appearance", "borderEnabled") == true
    local c = R("appearance", "borderColor") or { 0, 0, 0, 1 }
    local sig = (harmful and "h" or "b") .. (borderOn and
        ("|" .. c[1] .. "," .. c[2] .. "," .. c[3] .. "," .. (c[4] or 1)) or "|none")
    if b._adDispelSig ~= sig then
        if b._adDispelSig then
            for _, k in ipairs(BORDER_KEYS) do b:RemoveDispelTypeTexture(edges[k]) end
        end
        local opts = {
            showWhenHarmful = harmful,
            showWhenHelpful = not harmful,
            showWithoutDispelType = borderOn,
            style = styles.PreserveAsset,
        }
        if borderOn and CreateColor then
            opts.customDispelColorMap = { None = CreateColor(c[1], c[2], c[3], c[4] or 1) }
        end
        for _, k in ipairs(BORDER_KEYS) do b:AddDispelTypeTexture(edges[k], opts) end
        b._adDispelSig = sig
    end
    return true
end

-- Icon shadow: the Cooldown Manager's shadow atlas around the art, grown by
-- 18% of the width and 16% of the height per unit of size. w, h = the art's
-- size from a plain source (engine rects read secret). No atlas, no shadow.
local SHADOW_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local shadowAtlasOK
local function ApplyShadow(host, key, art, rec, w, h, alpha, show)
    local t = host[key]
    if shadowAtlasOK == nil then
        shadowAtlasOK = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil
            and C_Texture.GetAtlasInfo(SHADOW_ATLAS) ~= nil
    end
    if not (show and art and shadowAtlasOK) then
        if t then t:Hide() end
        return
    end
    if not t then
        t = host:CreateTexture(nil, "OVERLAY", nil, 0)
        t:SetAtlas(SHADOW_ATLAS)
        host[key] = t
    end
    local size = Store.Resolve(rec, "appearance", "shadowSize") or 1
    local ox, oy = (w or 36) * 0.18 * size, (h or 36) * 0.16 * size
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        -- A secret scale falls back to UIParent's; a preview snaps like the
        -- live icon (PaintBorderEdges).
        local es = (host._adPxRef or host):GetEffectiveScale()
        if es == nil or (issecretvalue and issecretvalue(es)) then
            es = UIParent:GetEffectiveScale()
        end
        ox = PixelUtil.GetNearestPixelSize(ox, es, 1)
        oy = PixelUtil.GetNearestPixelSize(oy, es, 1)
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", art, "TOPLEFT", -ox, oy)
    t:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", ox, -oy)
    t:SetAlpha(alpha or 1)
    t:Show()
end
-- Exported: a group buff's combat layers wear the icon's shadow.
Factory.ApplyShadow = ApplyShadow

-- Icon fonts by name ("" = the default face) through the bars' resolver, which
-- loads after this file and is only reached at call time. A font an LSM addon
-- registers later shows the default until then; each later registration
-- restyles the icons (hooked the first time a named font is asked for).
local fontHooked = false
local function IconFont(key, default)
    local fallback = default or STANDARD_TEXT_FONT
    if key == nil or key == "" then return fallback end
    local B = NS.Bars
    if not (B and B.ResolveFont) then return fallback end
    if not fontHooked and B.GetLSM then
        local lsm = B.GetLSM()
        if lsm and lsm.RegisterCallback then
            fontHooked = true
            lsm.RegisterCallback(Factory, "LibSharedMedia_Registered", function(_, mediatype)
                if mediatype == "font" and NS.Events and NS.Events.Coalesce then
                    NS.Events.Coalesce("ad_icon_fonts", function() Store.Dirty("style") end)
                end
            end)
        end
    end
    return B.ResolveFont(key) or fallback
end
Factory.IconFont = IconFont

function Factory.ApplyBorder(f, rec, bump, forceHide)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    local edges = f.borderEdges
    -- how far in the swipe must stop (0: no border over the art)
    f._adBorderInner = 0
    if R("appearance", "borderEnabled") and not forceHide then
        if not edges then
            edges = {}
            local bias = 0.30000001192093
            local iconTex = f.icon or f._adIcon
            if iconTex and iconTex.GetTexelSnappingBias then
                local v = iconTex:GetTexelSnappingBias()
                -- The strips copy the icon's texel-snapping bias. In the
                -- create window, getters in a forbidden hierarchy return
                -- secrets that type() calls "number"; only issecretvalue
                -- tells, and setters reject them.
                if type(v) == "number"
                    and not (issecretvalue and issecretvalue(v)) then
                    bias = v
                end
            end
            -- on an aura icon's stage while the missing look is there
            local host = CreateFrame("Frame", nil, f._adStage or f)
            host:SetAllPoints(f)
            f._adBorderHost = host
            for _, k in ipairs(BORDER_KEYS) do
                local t = host:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(1, 1, 1, 1)
                if t.SetTexelSnappingBias then t:SetTexelSnappingBias(bias) end
                edges[k] = t
            end
            f.borderEdges = edges
        end
        -- bump: 1, under the swipe (+2) so its countdown number draws on
        -- top; 2 on an aura icon, under its engine button (+3). Set each
        -- pass (children don't follow a parent's SetFrameLevel); a secret
        -- level would throw on the addition, so it waits for a plain pass.
        local lvl = f:GetFrameLevel()
        if issecretvalue and issecretvalue(lvl) then lvl = nil end
        if type(lvl) == "number" then
            f._adBorderHost:SetFrameLevel(lvl + (bump or 1))
        end
        local inner = PaintBorderEdges(edges, f, rec, 1)
        if inner > 0 then f._adBorderInner = inner end
    elseif edges then
        for _, t in pairs(edges) do t:Hide() end
    end
end

-- The one writer of the cooldown draw flags (style and per-feed passes). Pure
-- GCD: the GCD's look, or the wand's for its lock (the driver clears a hidden
-- one). Recharging: the wait-for-no-charges options may drop the fill and the
-- edge. Otherwise the player's swipe settings.
local function ApplyCdPresentation(f, rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local ds, de, db
    if f._adPureGCD then
        local look = R("swipe", f._adPureWand and "wandSwipe" or "gcdSwipe")
        ds = look == "swipe" or look == "both"
        de = look == "edge" or look == "both"
        db = false
    else
        ds = R("swipe", "showSwipe") ~= false
        de = R("swipe", "showEdge") ~= false
        db = R("swipe", "showBling") ~= false
        if f._adRecharging then
            if ds and R("swipe", "swipeWaitForNoCharges") == true then ds = false end
            if de and R("swipe", "edgeWaitForNoCharges") == true then de = false end
        end
    end
    f.cooldown:SetDrawSwipe(ds)
    f.cooldown:SetDrawEdge(de)
    f.cooldown:SetDrawBling(db)
    -- the swipe colour follows the presentation
    ApplySwipeAlpha(f)
end

-- Texcoords: aspect crop first, then zoom, centered.
local function IconTexCoords(rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local zoom = R("appearance", "zoom") or 0.08
    local ar = R("appearance", "aspectRatio") or 1
    local L, Rt, T, B = 0, 1, 0, 1
    if ar > 1 then
        local off = (1 - 1 / ar) / 2
        T, B = off, 1 - off
    elseif ar < 1 then
        local off = (1 - ar) / 2
        L, Rt = off, 1 - off
    end
    if zoom > 0 then
        local w = (Rt - L) * (1 - zoom * 2)
        local h = (B - T) * (1 - zoom * 2)
        local mx = (L + Rt) / 2
        local my = (T + B) / 2
        L, Rt, T, B = mx - w / 2, mx + w / 2, my - h / 2, my + h / 2
    end
    return L, Rt, T, B
end
-- Exported: a group buff's combat layers crop their art the same way.
Factory.IconTexCoords = IconTexCoords

-- Countdown and stack text styling for the holder and the aura button. kS =
-- the base-36 scale factor from a plain size; anchorTo = the text's anchor.
local function StyleCountdownText(cfs, rec, kS, anchorTo, fontPath)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local outline = R("text", "durationOutline") or "OUTLINE"
    if outline == "NONE" then outline = "" end
    cfs:SetFont(IconFont(R("text", "durationFont"), fontPath),
        math.max(6, math.floor((R("text", "durationSize") or 14) * kS + 0.5)), outline)
    cfs._adTextRGBA = R("text", "durationColor") or { 1, 1, 1, 1 }
    PaintText(cfs)
    local dan = R("text", "durationAnchor") or "CENTER"
    cfs:ClearAllPoints()
    cfs:SetPoint(dan, anchorTo, dan,
        (R("text", "durationX") or 0) * kS, (R("text", "durationY") or 0) * kS)
    cfs:SetShadowColor(0, 0, 0, R("text", "durationShadow") == true and 1 or 0)
    cfs:SetShadowOffset(1, -1)
end

local function StyleStackText(fs, rec, kS, anchorTo)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local outline = R("text", "stackOutline") or "OUTLINE"
    if outline == "NONE" then outline = "" end
    fs:SetFont(IconFont(R("text", "stackFont")),
        math.max(6, math.floor((R("text", "stackSize") or 14) * kS + 0.5)), outline)
    fs._adTextRGBA = R("text", "stackColor") or { 1, 1, 1, 1 }
    PaintText(fs)
    local anch = R("text", "stackAnchor") or "BOTTOMRIGHT"
    fs:ClearAllPoints()
    fs:SetPoint(anch, anchorTo, anch,
        (R("text", "stackX") or 0) * kS, (R("text", "stackY") or 0) * kS)
    fs:SetShadowColor(0, 0, 0, R("text", "stackShadow") == true and 1 or 0)
    fs:SetShadowOffset(1, -1)
end

-- The equipped ammo count, or nil with the slot empty. It has no secrecy
-- annotation and Blizzard's item buttons compare it; a secret one reads nil.
function Factory.AmmoCount()
    if GetInventoryItemID("player", AMMO_SLOT) == nil then return nil end
    local n = GetInventoryItemCount("player", AMMO_SLOT)
    if issecretvalue and issecretvalue(n) then return nil end
    return type(n) == "number" and n or nil
end

-- An ammo count's colour: the lowest threshold it is at or below, else the
-- text's own (baseKey).
function Factory.AmmoCountColor(fs, rec, baseKey)
    local R = function(k) return Store.Resolve(rec, "text", k) end
    local c = R(baseKey) or { 1, 1, 1, 1 }
    local n = R("ammoCountColors") == true and Factory.AmmoCount() or nil
    if n then
        local best
        for k = 1, math.min(3, R("ammoCountSteps") or 1) do
            local v = R("ammoCount" .. k)
            if type(v) == "number" and n <= v and (best == nil or v < best) then
                best = v
                c = R("ammoCount" .. k .. "Color") or c
            end
        end
    end
    -- through the texts' writer, so an ammo icon's stack text keeps its dim
    -- when a count lands
    fs._adTextRGBA = c
    PaintText(fs)
end

-- Keybind on/off for the style pass and the cooldown driver: the icon's own
-- switch or its group's. Kinds without a binding are always false.
function Factory.KeybindEnabled(rec)
    if not NS.Schema.Applies(nil, NS.Schema.icon.keybind, rec.kind) then return false end
    if Store.Resolve(rec, "keybind", "keybindEnabled") == true then return true end
    local g = rec.groupId and Store.Get(rec.groupId)
    return g ~= nil and g.type == "group"
        and Store.Resolve(g, "keybind", "showKeybinds") == true
end

-- The one frame-alpha writer: the icon's opacity times the conditions module's
-- (0 while inert, else its fade), and 0 for an item hidden while missing,
-- except in edit mode so it stays grabbable.
function Factory.ApplyFrameAlpha(f, rec)
    local a = Store.Resolve(rec, "appearance", "alpha") or 1
    -- _adPassive: a passive trinket in a slot set to on-use trinkets only
    if (rec.kind == "item" or rec.kind == "trinket" or rec.kind == "ammo")
        and ((f._adItemEmpty and Store.Resolve(rec, "outOfStock", "hideWhenMissing") == true)
            or (rec.kind == "trinket" and f._adPassive))
        and not (NS.LayoutEngine and NS.LayoutEngine.IsEditMode
            and NS.LayoutEngine.IsEditMode()) then
        a = 0
    end
    if NS.Conditions then a = a * NS.Conditions.AlphaFor(rec) end
    f:SetAlpha(a)
end

-- One custom text's look (suf "", "2" or "3") on fs, anchored to anchorTo:
-- the holder's, and the copies a group buff's combat layers carry.
local function StyleLabel(fs, rec, suf, kS, anchorTo)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    fs:SetFont(IconFont(R("label", "labelFont")),
        math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), "OUTLINE")
    local lc = R("label", "labelColor" .. suf) or { 1, 1, 1, 1 }
    fs:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1)
    local an = R("label", "labelAnchor" .. suf) or "CENTER"
    fs:ClearAllPoints()
    fs:SetPoint(an, anchorTo, an,
        (R("label", "labelX" .. suf) or 0) * kS,
        (R("label", "labelY" .. suf) or 0) * kS)
    fs:SetText(R("label", "labelText" .. suf))
end
Factory.StyleLabel = StyleLabel

-- The one style writer; drivers never call widget style methods.
function Factory.ApplyStyle(f, rec)
    local R = function(section, field) return Store.Resolve(rec, section, field) end

    -- Always painted here. The art pass and the driver's skips then re-read
    -- their settings, as a restyle follows every change.
    local tex = Factory.GetTexture(rec)
    f.icon:SetTexture(tex)
    f._adArt = not (issecretvalue and issecretvalue(tex)) and tex or nil
    f._adArtRec = nil
    f._adUsabSig = nil
    f._adStateSig = nil
    local forceHide = R("appearance", "forceHideIcon") == true
    f.icon:SetShown(not forceHide)
    local L, Rt, T, B = IconTexCoords(rec)
    f.icon:SetTexCoord(L, Rt, T, B)
    Factory.ApplyFrameAlpha(f, rec)

    -- An aura icon's holder border is the missing look's: on its ladder
    -- (AURA_LADDER) it sits under the missing look's glows and the engine
    -- button, which covers it while the aura is up and draws its own. Above
    -- the button it would show at the missing alpha over the live icon. Any
    -- other icon's border sits at +1, under the swipe (+2), so the swipe's own
    -- countdown number draws above it; a spell icon's aura overlay (the button
    -- at +4) covers both.
    local overlay = NS.DriverAura ~= nil and NS.DriverAura.OverlayOn ~= nil
        and NS.DriverAura.OverlayOn(rec) == true
    Factory.ApplyBorder(f, rec, rec.kind == "aura" and Factory.AURA_LADDER.border or 1, forceHide)
    -- The text host sits above the border and any anchored engine button,
    -- which would otherwise hide the labels. Set each pass (children don't
    -- follow SetFrameLevel), skipped when the level reads secret.
    local hostLvl = f:GetFrameLevel()
    local plainLvl = not (issecretvalue and issecretvalue(hostLvl)) and type(hostLvl) == "number"
    if plainLvl then
        f.textHost:SetFrameLevel(hostLvl + 7 + Factory.Rise(rec))
        if rec.kind ~= "aura" then f.cooldown:SetFrameLevel(hostLvl + 2) end
    end
    -- With an aura overlay the button shows the aura's count in that corner,
    -- so the charges move to a low host at +3, between the swipe (+2) and the
    -- button (+4), and show while the aura is down.
    if overlay then
        local low = f._adLowText
        if not low then
            low = CreateFrame("Frame", nil, f)
            low:SetAllPoints()
            f._adLowText = low
        end
        if plainLvl then low:SetFrameLevel(hostLvl + 3) end
        if f.stackText:GetParent() ~= low then f.stackText:SetParent(low) end
    elseif f._adLowText and f.stackText:GetParent() ~= f.textHost then
        f.stackText:SetParent(f.textHost)
    end

    -- Frames are sized, not scaled (pixel-exact edges), so values given for a
    -- 36px icon scale here by the real height; the border stays in pixels.
    local fwS, fhS = f:GetSize()
    local kS = (fhS and fhS > 0) and (fhS / 36) or 1
    -- Holder shadow, but not on an aura icon, whose live button draws one: two
    -- shadows would stack darker while the aura is up.
    do
        local pad = (R("appearance", "padding") or 0) * kS
        ApplyShadow(f, "_adShadow", f.icon, rec,
            math.max(1, (fwS or 36) - 2 * pad), math.max(1, (fhS or 36) - 2 * pad),
            f._adShownAlpha or f._adStateAlpha or 1,
            R("appearance", "shadowEnabled") == true and not forceHide and rec.kind ~= "aura")
    end
    -- Missing glows ride the missing look, Always glows the holder; a preview
    -- and the options window show those that wait for combat
    if rec.kind == "aura" or f._adMissGlow or f._adAlwaysGlow then
        local D = NS.DriverAura
        local combat = (D ~= nil and D.InCombat ~= nil and D.InCombat()) or f._adPreview == true
            or (NS.LayoutEngine ~= nil and NS.LayoutEngine.IsEditMode ~= nil and NS.LayoutEngine.IsEditMode())
        Factory.ApplyMissingGlows(f, rec, fwS, fhS, combat)
        Factory.ApplyAlwaysGlows(f, rec, fwS, fhS, combat)
    end

    -- Padding insets the art; the border stays at the frame edge.
    local padBase = R("appearance", "padding") or 0
    local padPx = padBase * kS
    f.icon:ClearAllPoints()
    if padPx > 0 then
        f.icon:SetPoint("TOPLEFT", padPx, -padPx)
        f.icon:SetPoint("BOTTOMRIGHT", -padPx, padPx)
    else
        f.icon:SetAllPoints()
    end

    local hasSwipe = NS.Schema.Applies(nil, NS.Schema.icon.swipe, rec.kind)
    if hasSwipe then
        ApplyCdPresentation(f, rec)
        f.cooldown:SetReverse(R("swipe", "reverse") == true)
        -- Cached for the state dim; ApplySwipeAlpha writes them scaled.
        local sc = R("swipe", "swipeColor") or { 0, 0, 0, 0.8 }
        f._adSwipeColor = sc
        f._adGcdSwipeColor = R("swipe", "gcdSwipeColor") or { 0, 0, 0, 0.5 }
        f._adWandSwipeColor = R("swipe", "wandSwipeColor") or { 0, 0, 0, 0.5 }
        if f.cooldown.SetEdgeScale then
            -- 1.8 = the Cooldown Manager's edge length; the template's is 1.0.
            f.cooldown:SetEdgeScale(R("swipe", "edgeScale") or 1.8)
        end
        if f.cooldown.SetEdgeColor then
            f._adEdgeColor = R("swipe", "edgeColor") or { 1, 1, 1, 1 }
        end
        ApplySwipeAlpha(f)
        -- No SetEdgeTexture: any file, the classic one included, washes the
        -- line out. With separateInsets off, stale X/Y insets are ignored.
        local ix, iy
        if R("swipe", "separateInsets") == true then
            ix = R("swipe", "swipeInsetX") or 0
            iy = R("swipe", "swipeInsetY") or 0
        else
            ix = R("swipe", "swipeInset") or 0
            iy = ix
        end
        ix, iy = (ix + padBase) * kS, (iy + padBase) * kS
        -- the swipe draws over the border now, so it stops at the border's
        -- inside edge; a deeper inset of its own still wins
        local bi = f._adBorderInner or 0
        if ix < bi then ix = bi end
        if iy < bi then iy = bi end
        f.cooldown:ClearAllPoints()
        f.cooldown:SetPoint("TOPLEFT", f, "TOPLEFT", ix, -iy)
        f.cooldown:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ix, iy)
    end
    Factory.ApplyDurationVis(f, rec)
    -- Pushed only when the recipe changes; nil restores the stock format.
    if f.cooldown.SetCountdownFormatter then
        local fmt, sig = CountdownFormatterFor(rec)
        if f._adFmtSig ~= sig then
            f._adFmtSig = sig
            f.cooldown:SetCountdownFormatter(fmt)
        end
    end
    if f.cooldown.GetCountdownFontString then
        local cfs = f.cooldown:GetCountdownFontString()
        if cfs then
            local fp = select(1, cfs:GetFont()) or STANDARD_TEXT_FONT
            StyleCountdownText(cfs, rec, kS, f, fp)
        end
    end

    local stacks = NS.Schema.Applies(NS.Schema.icon.text.fields.stackText, NS.Schema.icon.text, rec.kind)
        and R("text", "stackText") ~= false
    if stacks then
        StyleStackText(f.stackText, rec, kS, f)
        if rec.kind == "ammo" then Factory.AmmoCountColor(f.stackText, rec, "stackColor") end
        f.stackText:Show()
    else
        f.stackText:Hide()
    end

    -- Ammo text: styled and shown here, filled by the driver.
    local ammo = NS.Schema.Applies(NS.Schema.icon.text.fields.ammoText, NS.Schema.icon.text, rec.kind)
        and R("text", "ammoText") == true
    if ammo then
        local aout = R("text", "ammoOutline") or "OUTLINE"
        if aout == "NONE" then aout = "" end
        f.ammoText:SetFont(IconFont(R("text", "ammoFont")),
            math.max(6, math.floor((R("text", "ammoSize") or 14) * kS + 0.5)), aout)
        Factory.AmmoCountColor(f.ammoText, rec, "ammoColor")
        local aanch = R("text", "ammoAnchor") or "BOTTOMLEFT"
        f.ammoText:ClearAllPoints()
        f.ammoText:SetPoint(aanch, f, aanch,
            (R("text", "ammoX") or 0) * kS, (R("text", "ammoY") or 0) * kS)
        f.ammoText:SetShadowColor(0, 0, 0, R("text", "ammoShadow") == true and 1 or 0)
        f.ammoText:SetShadowOffset(1, -1)
        f.ammoText:Show()
    else
        f.ammoText:SetText("")
        f.ammoText:Hide()
    end

    -- Custom labels: styled here, shown per state in SetState.
    f._adLabels = f._adLabels or {}
    local labelFS = { f.labelText, f.labelText2, f.labelText3 }
    for i, suf in ipairs({ "", "2", "3" }) do
        local fs = labelFS[i]
        local st = f._adLabels[i] or {}
        f._adLabels[i] = st
        st.fs = fs
        st.ready = R("label", "labelShowReady" .. suf) ~= false
        st.cd = R("label", "labelShowCooldown" .. suf) ~= false
        st.activeOnly = rec.kind == "aura" and R("label", "labelActiveOnly" .. suf) == true
        st.missingOnly = rec.kind == "aura" and R("label", "labelMissingOnly" .. suf) == true
        local ltext = R("label", "labelText" .. suf)
        if fs and ltext and ltext ~= "" then
            StyleLabel(fs, rec, suf, kS, f)
            st.has = true
        elseif fs then
            fs:SetText("")
            st.has = false
            fs:Hide()
        end
    end
    f._adHasLabel = f._adLabels[1].has
    Factory.ApplyMissingLabels(f, rec, kS)

    -- Keybind text style; the cooldown driver sets the text.
    local kbOn = Factory.KeybindEnabled(rec)
    if kbOn then
        f.keybindText:SetFont(IconFont(R("keybind", "keybindFont")),
            math.max(6, math.floor((R("keybind", "keybindSize") or 12) * kS + 0.5)), "OUTLINE")
        local kc = R("keybind", "keybindColor") or { 1, 1, 1, 1 }
        f.keybindText:SetTextColor(kc[1], kc[2], kc[3], kc[4] or 1)
        local kan = R("keybind", "keybindAnchor") or "TOPLEFT"
        f.keybindText:ClearAllPoints()
        f.keybindText:SetPoint(kan, f, kan,
            (R("keybind", "keybindX") or 0) * kS, (R("keybind", "keybindY") or 0) * kS)
        f.keybindText:Show()
    else
        f.keybindText:Hide()
    end

    -- Glows restart only when their signature changes: a restart is visible.
    Factory.SetState(f, rec, f._adOnCooldown, f._adDesatState)
    -- the warning glow follows the ammo and the pet, not the icon's state
    if NS.DriverWarn then NS.DriverWarn.Sync(f, rec) end
    -- a special icon's texts are its templates expanded, so it paints again
    if rec.kind == "special" and NS.SpecialIcon then NS.SpecialIcon.Restyle(f, rec) end
end

-- A label kept to the aura's absence needs solid live art over it, or the eraser (NeedsEraser).
function Factory.MissingLabelsOK(rec)
    if not (rec ~= nil and rec.kind == "aura") then return false end
    local D = NS.DriverAura
    if D and D.EraserAvailable and D.EraserAvailable() then return true end
    return Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
        and (Store.Resolve(rec, "auraActive", "activeAlpha") or 1) > 0
end

-- Those labels sit under the engine button, which hides them while the aura is up, in combat too.
function Factory.ApplyMissingLabels(f, rec, kS)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local ok = Factory.MissingLabelsOK(rec)
    local clip = f._adMissClip
    local any = false
    for i, suf in ipairs({ "", "2", "3" }) do
        local ltext = R("label", "labelText" .. suf)
        local want = ok and R("label", "labelMissingOnly" .. suf) == true
            and ltext ~= nil and ltext ~= ""
        if want and not clip then
            clip = CreateFrame("Frame", nil, f._adStage or f)
            clip:SetClipsChildren(true)
            clip._fs = {}
            f._adMissClip = clip
        end
        local fs = clip and clip._fs[i]
        if want then
            if not fs then
                fs = clip:CreateFontString(nil, "OVERLAY")
                fs:SetDrawLayer("OVERLAY", 7)
                clip._fs[i] = fs
            end
            fs:SetFont(IconFont(R("label", "labelFont")),
                math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), "OUTLINE")
            local lc = R("label", "labelColor" .. suf) or { 1, 1, 1, 1 }
            fs:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1)
            local an = R("label", "labelAnchor" .. suf) or "CENTER"
            fs:ClearAllPoints()
            fs:SetPoint(an, f, an, (R("label", "labelX" .. suf) or 0) * kS,
                (R("label", "labelY" .. suf) or 0) * kS)
            fs:SetText(ltext)
            fs:Show()
            any = true
        elseif fs then
            fs:SetText("")
            fs:Hide()
        end
    end
    if not clip then return end
    if any then
        local D = NS.DriverAura
        local erasing = D ~= nil and D.EraserAvailable ~= nil and D.EraserAvailable()
        local padPx = erasing and 0 or ((R("appearance", "padding") or 0) * kS)
        clip:SetClipsChildren(not erasing)
        clip:ClearAllPoints()
        clip:SetPoint("TOPLEFT", f, "TOPLEFT", padPx, -padPx)
        clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -padPx, padPx)
        clip:SetFrameStrata(f:GetFrameStrata())
        clip:SetFrameLevel(f:GetFrameLevel() + Factory.AURA_LADDER.missLabels)
        clip:Show()
    else
        clip:Hide()
    end
end

-- Aura icon ladder over the holder: glows above borders, the live button above every missing piece.
Factory.AURA_LADDER = { border = 1, missLabels = 1, missGlow = 2, button = 3 }

-- An aura watching you, then your target, has a second button above the
-- first: the holder's texts and glows go up by as much to stay on top.
function Factory.Rise(rec)
    local D = NS.DriverAura
    return (D and D.Rise and D.Rise(rec)) or 0
end

-- Moves the missing look onto the stage, each piece keeping its level; nil brings it home.
function Factory.StageMissingLook(f, stage)
    local p = stage or f
    f._adStage = stage
    f.icon:SetParent(p)
    if f._adShadow then f._adShadow:SetParent(p) end
    for _, k in ipairs({ "_adBorderHost", "_adMissClip", "_adMissGlow" }) do
        local fr = f[k]
        if fr then
            local lvl = fr:GetFrameLevel()
            fr:SetParent(p)
            if type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl)) then
                fr:SetFrameLevel(lvl)
            end
        end
    end
end

-- The editor preview hides the missing look itself while its stand-in shows the aura up.
function Factory.HideMissingLook(f)
    f.icon:SetAlpha(0)
    if f._adShadow then f._adShadow:SetAlpha(0) end
    if f._adBorderHost then f._adBorderHost:SetAlpha(0) end
    if f._adMissClip then f._adMissClip:SetAlpha(0) end
    if f._adMissGlow then f._adMissGlow:SetAlpha(0) end
end

-- The Active look's alpha, with the editing floor the Missing look gets too
-- (the engine button restyles on an accessible pass, so closing the window
-- mid-fight keeps the floor until the fight ends).
function Factory.AuraActiveAlpha(rec)
    local aA = Store.Resolve(rec, "auraActive", "activeAlpha") or 1
    if aA < 0 then aA = 0 elseif aA > 1 then aA = 1 end
    return EditFloor(aA)
end

-- The live engine button shows exactly while the aura is up: no presence read, nothing read off it.
function Factory.StyleAuraButton(b, rec, px, opts)
    if not (b and rec) then return end
    opts = opts or {}
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local kS = (px and px > 0) and (px / 36) or 1
    local forceHide = R("appearance", "forceHideIcon") == true
    local aA = Factory.AuraActiveAlpha(rec)
    -- "Hide icon art": art, swipe, border and glow go; texts keep full alpha.
    -- A dimmed active look keeps them bright too, as the missing look and a
    -- spell's states do; a hidden one (alpha 0) hides them with it.
    local artA = forceHide and 0 or aA
    local keep
    if rec.kind == "aura" then
        keep = R("auraActive", "activePreserveText") ~= false
    else
        keep = R("states", "preserveDurationText") ~= false
    end
    local textA = (forceHide or (aA > 0 and keep)) and 1 or aA
    -- Active alpha goes on the pieces, so the button stays at 1.
    b:SetAlpha(1)
    local padPx = (R("appearance", "padding") or 0) * kS
    -- Art override: the engine only ever calls SetTexture on b._adIcon, so an
    -- override is our own texture drawn in its place. Being on the button, it
    -- shows exactly while the aura is up, in combat too.
    local ic = b._adIcon
    local ovTex = Factory.AuraActiveTexture(rec)
    if ovTex then
        local ovArt = b._adIconOv
        if not ovArt then
            ovArt = b:CreateTexture(nil, "ARTWORK", nil, 1)
            b._adIconOv = ovArt
        end
        ovArt:SetTexture(ovTex)
        ovArt:Show()
        if ic then ic:Hide() end
        ic = ovArt
    else
        if b._adIconOv then b._adIconOv:Hide() end
        if ic then ic:Show() end
    end
    if ic then
        local L, Rt, T, B = IconTexCoords(rec)
        ic:SetTexCoord(L, Rt, T, B)
        ic:ClearAllPoints()
        if padPx > 0 then
            ic:SetPoint("TOPLEFT", b, "TOPLEFT", padPx, -padPx)
            ic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -padPx, padPx)
        else
            ic:SetAllPoints(b)
        end
        -- The engine owns this texture's file; alpha, desaturation and vertex
        -- colour are ours. The tint carries artA, or it would undo SetAlpha.
        ic:SetAlpha(artA)
        ic:SetDesaturated(R("auraActive", "activeDesaturate") == true)
        if R("auraActive", "activeTintEnabled") == true then
            local c = R("auraActive", "activeTintColor") or { 1, 1, 1, 1 }
            ic:SetVertexColor(c[1], c[2], c[3], artA)
        else
            ic:SetVertexColor(1, 1, 1, artA)
        end
    end
    -- Shown only while the stage buffers (opts.erase), sized to the missing look's reach.
    local er = b._adEraser
    if er then
        if opts.erase == true then
            local m = math.max((px and px > 0) and px or 36, Factory.MissingTextReach(rec, kS))
            er:ClearAllPoints()
            er:SetPoint("TOPLEFT", b, "TOPLEFT", -m, m)
            er:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", m, -m)
            er:Show()
        else
            er:Hide()
        end
    end
    -- The plate keeps a dimmed active icon from showing the missing look; the eraser replaces it.
    local plate = b._adPlate
    if plate then
        if plate.SetIgnoreParentAlpha then plate:SetIgnoreParentAlpha(false) end
        plate:ClearAllPoints()
        if padPx > 0 then
            plate:SetPoint("TOPLEFT", b, "TOPLEFT", padPx, -padPx)
            plate:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -padPx, padPx)
        else
            plate:SetAllPoints(b)
        end
        plate:SetShown(artA > 0 and opts.ghost == true and opts.erase ~= true)
    end
    local sw = b._adSwipe
    if sw then
        -- A spell icon's aura phase keeps its own colour and direction (the
        -- Cooldown Manager's gold); an aura icon gets the reversed dark swipe.
        local overlay = rec.kind ~= "aura"
        local rev, sc
        if overlay then
            rev = R("auraSwipe", "overlaySwipeReverse") == true
            sc = R("auraSwipe", "overlaySwipeColor") or { 1, 0.95, 0.57, 0.7 }
        else
            rev = R("auraSwipe", "swipeReverse") ~= false
            sc = R("auraSwipe", "swipeColor") or { 0, 0, 0, 0.8 }
        end
        sw:SetDrawSwipe(R("auraSwipe", "swipeShow") ~= false and not forceHide)
        sw:SetReverse(rev)
        sw:SetDrawEdge(R("auraSwipe", "swipeEdge") == true and not forceHide)
        sw:SetDrawBling(R("auraSwipe", "swipeBling") == true and not forceHide)
        sw:SetSwipeColor(sc[1], sc[2], sc[3], (sc[4] or 0.8) * aA)
        -- Edge colour and length as on the cooldown swipe (template art, no
        -- SetEdgeTexture); its alpha follows Active alpha.
        if sw.SetEdgeScale then sw:SetEdgeScale(R("auraSwipe", "edgeScale") or 1.8) end
        if sw.SetEdgeColor then
            local ec = R("auraSwipe", "edgeColor") or { 1, 1, 1, 1 }
            sw:SetEdgeColor(ec[1], ec[2], ec[3], (ec[4] or 1) * aA)
        end
        sw:SetHideCountdownNumbers(R("text", "durationText") == false)
        if sw.SetCountdownFormatter then
            local fmt, sig = CountdownFormatterFor(rec)
            if b._adFmtSig ~= sig then
                b._adFmtSig = sig
                sw:SetCountdownFormatter(fmt)
            end
        end
        local cfs = sw.GetCountdownFontString and sw:GetCountdownFontString()
        if cfs then
            StyleCountdownText(cfs, rec, kS, b, STANDARD_TEXT_FONT)
            PaintText(cfs, textA)
        end
    end
    local st = b._adStacks
    if st then
        local on = NS.Schema.Applies(NS.Schema.icon.text.fields.stackText, NS.Schema.icon.text, rec.kind)
            and R("text", "stackText") ~= false
        StyleStackText(st, rec, kS, b)
        st:SetShown(on)
        PaintText(st, textA)
        -- The engine writes the count; it gets the fontstring and a formatter
        -- with the show-at-1 and color-band rules, empty when the text is off
        -- (the engine owns Shown). Re-handed only when the rules change.
        if b.SetApplicationCount then
            local fmt, sig = Factory.GetStackFormatter(rec, not on)
            if b._adStkSig ~= sig then
                b._adStkSig = sig
                b:SetApplicationCount(st, { formatter = fmt })
            end
        end
    end
    -- Aura icons only; a spell icon's overlay keeps the spell's shadow.
    ApplyShadow(b, "_adShadow", ic, rec, opts.w or px, opts.h or px, artA,
        rec.kind == "aura" and R("appearance", "shadowEnabled") == true and not forceHide)
    -- the dispel-type border replaces the plain one while it is on
    local dispelOn = ApplyAuraButtonDispel(b, rec,
        rec.kind == "aura" and not forceHide and R("appearance", "dispelBorder") == true, aA)
    -- The live icon's own border; the holder carries the ghost copy.
    ApplyAuraButtonBorder(b, rec, R("appearance", "borderEnabled") and not forceHide and not dispelOn, aA)
    -- Labels kept to the aura's time ride the button, which the game shows
    -- exactly while the aura is up; the holder's copies stand down (SetState).
    b._adLabelFS = b._adLabelFS or {}
    local lhost = b.TextOverlay or b
    for i, suf in ipairs({ "", "2", "3" }) do
        local fs = b._adLabelFS[i]
        local ltext = R("label", "labelText" .. suf)
        if rec.kind == "aura" and R("label", "labelActiveOnly" .. suf) == true
            and ltext and ltext ~= "" then
            if not fs then
                fs = lhost:CreateFontString(nil, "OVERLAY")
                fs:SetDrawLayer("OVERLAY", 7)
                b._adLabelFS[i] = fs
            end
            fs:SetFont(IconFont(R("label", "labelFont")),
                math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), "OUTLINE")
            local lc = R("label", "labelColor" .. suf) or { 1, 1, 1, 1 }
            fs:SetTextColor(lc[1], lc[2], lc[3], (lc[4] or 1) * textA)
            local an = R("label", "labelAnchor" .. suf) or "CENTER"
            fs:ClearAllPoints()
            fs:SetPoint(an, b, an, (R("label", "labelX" .. suf) or 0) * kS,
                (R("label", "labelY" .. suf) or 0) * kS)
            fs:SetText(ltext)
            fs:Show()
        elseif fs then
            fs:SetText("")
            fs:Hide()
        end
    end
    -- opts.glowElsewhere: a glow gate moved the glow onto its own button
    Factory.SetAuraButtonGlow(b, rec, (not forceHide) and not opts.glowElsewhere
        and R("auraActive", "activeGlow") == true and not Factory.HolderGlowOn(rec, 1),
        opts.w or px, opts.h or px, aA)
    -- Glows 2-4 ride their own buttons in play; the editor preview's one
    -- stand-in draws them all (opts.previewGlows) and drops them otherwise,
    -- as it also serves spell icons.
    for k = 2, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        Factory.SetAuraButtonGlow(b, rec, opts.previewGlows == true and (not forceHide)
            and R("auraActive", "activeGlow" .. k) == true and not Factory.HolderGlowOn(rec, k),
            opts.w or px, opts.h or px, aA, k)
    end
end

-- Aura button glow: drawn on the live engine button, so it shows exactly while
-- the aura is up with no presence read. The button is forbidden in combat (all
-- the time in instances), so a style can't run Lua per frame, chain scripts or
-- read the button: each is textures and looping animation groups set up on an
-- accessible pass, sized from plain sources. That rules out the glow
-- library, which reads the rect, animates in OnUpdate and chains in OnFinished.
-- We play the loops ourselves and never hand one to the button: its container
-- rebuilds on UNIT_FLAGS, which fires at every pull, and a group the button
-- owns restarts on each rebuild. Hiding and showing the button leaves our
-- loops running, so they come through untouched. For the same reason there
-- is no opening burst: nothing could play it only when the aura appears.
local GLOW_DASH_H = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_GlowDashH"
local GLOW_DASH_V = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\AD_GlowDashV"
-- Each dash texture has 8 bands (8 texels each) across its short side; band k
-- lights DASH_BANDS[k] of 64 texels; texcoords pick it. DASH_AUTO = automatic.
local DASH_BANDS = { 6, 13, 19, 26, 32, 39, 45, 52 }
local DASH_AUTO = 4
-- Ants art from ActionBarButtonAssistedCombatHighlightTemplate (66 px around a
-- 45 px button: BLIZZ_RATIO), flash art from Blizzard_VisualAlerts; both exist
-- on Forever. A client missing one draws the button style (DrawnGlowStyle).
local ANTS_ATLAS = "rotationhelper_ants_flipbook"
local FLASH_ATLAS = "UI-CooldownManager-VisualAlert-Glow"
local BLIZZ_RATIO = 66 / 45
local atlasOK = {}
local function AtlasOK(name)
    local v = atlasOK[name]
    if v == nil then
        v = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil
            and C_Texture.GetAtlasInfo(name) ~= nil
        atlasOK[name] = v
    end
    return v
end
-- the style a glow really draws: a known style, else button; ants / flash
-- fall back to button where the client lacks their art
local GLOW_STYLES_KNOWN = { pixel = true, autocast = true, button = true, proc = true,
    procloop = true, ants = true, flash = true }
local function DrawnGlowStyle(gtype)
    if not GLOW_STYLES_KNOWN[gtype] then return "button" end
    if gtype == "ants" and not AtlasOK(ANTS_ATLAS) then return "button" end
    if gtype == "flash" and not AtlasOK(FLASH_ATLAS) then return "button" end
    return gtype
end
Factory.DrawnGlowStyle = DrawnGlowStyle
Factory._glowAtlasOK = atlasOK   -- test harness handle
local ICON_ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local ICON_ALERT_ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local PROC_LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
-- the IconAlert sheet's outer ring
local ALERT_GLOW = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }
-- Sparkle art: the Artifacts sheet exists on retail only; other clients,
-- Forever included, get the item-socket sparkle.
local SPARKLE, SPARKLE_TC
if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
    SPARKLE = "Interface\\Artifacts\\Artifacts"
    SPARKLE_TC = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
else
    SPARKLE = "Interface\\ItemSocketingFrame\\UI-ItemSockets"
    SPARKLE_TC = { 0.3984375, 0.4453125, 0.40234375, 0.44921875 }
end
local SPARKLE_SIZES = { 7, 6, 5, 4 }

-- A flipbook texture shows its whole sheet until its loop has played. So
-- flipbook art rests at alpha 0, and this Alpha animation, created with the
-- loop, holds it at the build's intensity while the loop plays: a stopped
-- loop draws nothing. A texture's alpha is its vertex alpha.
local function LoopLit(ag)
    local lit = ag:CreateAnimation("Alpha")
    lit:SetDuration(0.001)
    lit:SetOrder(1)
    return lit
end

-- Set every build: whether children follow a parent's level is undocumented.
local function LevelStyleFrames(host, L)
    for _, k in ipairs({ "_adBtn", "_adProc", "_adAnts", "_adFlash" }) do
        local fr = host[k]
        if fr then fr:SetFrameLevel(L + 1) end
    end
end

-- stop and hide every style's pieces but the one being drawn
local function HideGlowParts(host, keep)
    if keep ~= "pixel" and host._adPix then
        for _, e in ipairs(host._adPix) do
            e.ag:Stop()
            e.strip:Hide()
        end
    end
    if keep ~= "autocast" and host._adSpk then
        for _, it in ipairs(host._adSpk) do
            it.ag:Stop()
            it.tex:Hide()
        end
    end
    if keep ~= "button" and host._adBtn then
        host._adBtn.antsAG:Stop()
        host._adBtn:Hide()
    end
    -- proc and procloop draw the same loop here: no burst on an aura button
    if keep ~= "proc" and keep ~= "procloop" and host._adProc then
        host._adProc.loopAG:Stop()
        host._adProc:Hide()
    end
    if keep ~= "ants" and host._adAnts then
        host._adAnts.ag:Stop()
        host._adAnts:Hide()
    end
    if keep ~= "flash" and host._adFlash then
        host._adFlash.ag:Stop()
        host._adFlash:Hide()
    end
end

-- Pixel: n dashes around a W x H rect, th thick, a lap per period seconds;
-- len = dash length in pixels (0 or nil = automatic), met by the nearest band.
local function GlowPixel(host, W, H, n, th, period, r, g, bl, a, len)
    local list = host._adPix
    if not list then
        list = {}
        host._adPix = list
    end
    local cycle = 2 * (W + H) / n
    local dur = math.max(0.01, period / n)
    local band = DASH_AUTO
    if type(len) == "number" and len > 0 then
        local best
        for k, lit in ipairs(DASH_BANDS) do
            local d = math.abs(lit / 64 * cycle - len)
            if best == nil or d < best then best, band = d, k end
        end
    end
    -- the band's texcoords across the strip, half a texel in from each edge
    -- so filtering never reaches a neighbouring band
    local b0 = (band - 1) / 8 + 1 / 128
    local b1 = band / 8 - 1 / 128
    for i = 1, 4 do
        local e = list[i]
        if not e then
            e = {}
            e.mask = host:CreateMaskTexture()
            -- NEAREST: a bilinear mask fades its outer half texel over the strip
            e.mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
            e.strip = host:CreateTexture(nil, "OVERLAY", nil, 7)
            e.strip:AddMaskTexture(e.mask)
            e.ag = e.strip:CreateAnimationGroup()
            e.ag:SetLooping("REPEAT")
            e.tr = e.ag:CreateAnimation("Translation")
            if e.tr.SetSmoothing then e.tr:SetSmoothing("NONE") end
            list[i] = e
        end
        e.ag:Stop()
        e.mask:ClearAllPoints()
        e.strip:ClearAllPoints()
        -- texture first, texcoords after: the tiling rides the texcoords
        if i == 1 then          -- top, running right
            e.strip:SetTexture(GLOW_DASH_H, "REPEAT", "REPEAT")
            e.mask:SetSize(W, th)
            e.mask:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            e.strip:SetSize(W + cycle, th)
            e.strip:SetPoint("TOPLEFT", host, "TOPLEFT", -cycle, 0)
            e.strip:SetTexCoord(0, (W + cycle) / cycle, b0, b1)
            e.tr:SetOffset(cycle, 0)
        elseif i == 2 then      -- right, running down
            local base = W / cycle
            e.strip:SetTexture(GLOW_DASH_V, "REPEAT", "REPEAT")
            e.mask:SetSize(th, H)
            e.mask:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
            e.strip:SetSize(th, H + cycle)
            e.strip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, cycle)
            e.strip:SetTexCoord(b0, b1, base, base + (H + cycle) / cycle)
            e.tr:SetOffset(0, -cycle)
        elseif i == 3 then      -- bottom, running left
            local base = (W + H) / cycle
            e.strip:SetTexture(GLOW_DASH_H, "REPEAT", "REPEAT")
            e.mask:SetSize(W, th)
            e.mask:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
            e.strip:SetSize(W + cycle, th)
            e.strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
            e.strip:SetTexCoord(base, base + (W + cycle) / cycle, b0, b1)
            e.tr:SetOffset(-cycle, 0)
        else                    -- left, running up
            local base = (2 * W + H) / cycle
            e.strip:SetTexture(GLOW_DASH_V, "REPEAT", "REPEAT")
            e.mask:SetSize(th, H)
            e.mask:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
            e.strip:SetSize(th, H + cycle)
            e.strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, -cycle)
            e.strip:SetTexCoord(b0, b1, base, base + (H + cycle) / cycle)
            e.tr:SetOffset(0, cycle)
        end
        e.strip:SetVertexColor(r, g, bl, a)
        e.tr:SetDuration(dur)
        e.strip:Show()
        e.ag:Play()
    end
end

-- a point on the rect's edge, `pos` along the perimeter clockwise from the
-- bottom-left corner (up the left side first); offsets from BOTTOMLEFT
local function PerimPoint(pos, W, H)
    local P = 2 * (W + H)
    pos = pos % P
    if pos <= H then return 0, pos end
    pos = pos - H
    if pos <= W then return pos, H end
    pos = pos - W
    if pos <= H then return W, H - pos end
    return W - (pos - H), 0
end

-- autocast: n sparkles per ring, four rings, the outer ones slower
local function GlowSparkle(host, W, H, n, scale, period, r, g, bl, a)
    local list = host._adSpk
    if not list then
        list = {}
        host._adSpk = list
    end
    local P = 2 * (W + H)
    local corners = { 0, H, H + W, 2 * H + W }
    local idx = 0
    for layer = 1, 4 do
        for s = 1, n do
            idx = idx + 1
            local start = (s - 1) * P / n
            -- the corners ahead of the start, clockwise, then the start one lap on
            local stops = {}
            for _, c in ipairs(corners) do
                if c > start then stops[#stops + 1] = c end
            end
            for _, c in ipairs(corners) do
                if c < start then stops[#stops + 1] = c + P end
            end
            stops[#stops + 1] = start + P
            local it = list[idx]
            -- control points cannot be removed: a new count needs a fresh sparkle
            if it and it.nStops ~= #stops then
                it.ag:Stop()
                it.tex:Hide()
                it = nil
            end
            if not it then
                it = {}
                it.tex = host:CreateTexture(nil, "OVERLAY", nil, 7)
                it.tex:SetTexture(SPARKLE)
                it.tex:SetTexCoord(SPARKLE_TC[1], SPARKLE_TC[2], SPARKLE_TC[3], SPARKLE_TC[4])
                it.tex:SetBlendMode("ADD")
                it.ag = it.tex:CreateAnimationGroup()
                it.ag:SetLooping("REPEAT")
                it.path = it.ag:CreateAnimation("Path")
                it.points = {}
                for i = 1, #stops do
                    it.points[i] = it.path:CreateControlPoint(nil, nil, i)
                end
                it.nStops = #stops
                list[idx] = it
            end
            it.ag:Stop()
            local sx, sy = PerimPoint(start, W, H)
            local sz = SPARKLE_SIZES[layer] * scale
            it.tex:SetSize(sz, sz)
            it.tex:ClearAllPoints()
            it.tex:SetPoint("CENTER", host, "BOTTOMLEFT", sx, sy)
            it.tex:SetVertexColor(r, g, bl, a)
            for i, pos in ipairs(stops) do
                local qx, qy = PerimPoint(pos, W, H)
                it.points[i]:SetOffset(qx - sx, qy - sy)
            end
            it.path:SetDuration(math.max(0.05, period * layer))
            it.tex:Show()
            it.ag:Play()
        end
    end
    for i = idx + 1, #list do
        list[i].ag:Stop()
        list[i].tex:Hide()
    end
end

-- Button: the button glow at rest, its outer ring and ants on a
-- (1.4 w + 2 xo) x (1.4 h + 2 yo) frame, as the cooldown lanes lay it.
-- Desaturated so the colour tints the gold art.
local function GlowButton(host, fw, fh, r, g, bl, a, speed)
    local bt = host._adBtn
    if not bt then
        bt = CreateFrame("Frame", nil, host)
        bt:SetPoint("CENTER", host, "CENTER", 0, 0)
        bt.outer = bt:CreateTexture(nil, "OVERLAY", nil, 6)
        bt.outer:SetTexture(ICON_ALERT)
        bt.outer:SetTexCoord(ALERT_GLOW[1], ALERT_GLOW[2], ALERT_GLOW[3], ALERT_GLOW[4])
        bt.outer:SetBlendMode("ADD")
        bt.outer:SetPoint("CENTER", bt, "CENTER", 0, 0)
        if bt.outer.SetDesaturated then bt.outer:SetDesaturated(true) end
        bt.ants = bt:CreateTexture(nil, "OVERLAY", nil, 7)
        bt.ants:SetTexture(ICON_ALERT_ANTS)
        bt.ants:SetBlendMode("ADD")
        bt.ants:SetPoint("CENTER", bt, "CENTER", 0, 0)
        if bt.ants.SetDesaturated then bt.ants:SetDesaturated(true) end
        bt.antsAG = bt.ants:CreateAnimationGroup()
        bt.antsAG:SetLooping("REPEAT")
        bt.antsLit = LoopLit(bt.antsAG)
        bt.antsFB = bt.antsAG:CreateAnimation("FlipBook")
        bt.antsFB:SetOrder(1)
        bt.antsFB:SetFlipBookRows(5)
        bt.antsFB:SetFlipBookColumns(5)
        bt.antsFB:SetFlipBookFrames(22)
        bt.antsFB:SetFlipBookFrameWidth(48)
        bt.antsFB:SetFlipBookFrameHeight(48)
        host._adBtn = bt
    end
    bt.antsAG:Stop()
    bt:SetSize(fw, fh)
    bt.outer:SetSize(fw, fh)
    bt.ants:SetSize(fw * 0.85, fh * 0.85)
    bt.outer:SetVertexColor(r, g, bl, a)
    bt.ants:SetVertexColor(r, g, bl, 0)
    bt.antsLit:SetFromAlpha(a)
    bt.antsLit:SetToAlpha(a)
    -- the cooldown lanes' pace at the same speed (one ants lap = 22 frames)
    local dur = 0.055 / math.max(0.05, speed)
    if dur < 0.05 then dur = 0.05 elseif dur > 5 then dur = 5 end
    bt.antsFB:SetDuration(dur)
    bt:Show()
    bt.antsAG:Play()
end

-- a flipbook over a 6 x 5 sheet of 30 frames (the proc loop, the ants)
local function FlipBook(ag, target, dur, order)
    local fb = ag:CreateAnimation("FlipBook")
    if target then fb:SetTarget(target) end
    fb:SetDuration(dur)
    fb:SetOrder(order)
    fb:SetFlipBookRows(6)
    fb:SetFlipBookColumns(5)
    fb:SetFlipBookFrames(30)
    fb:SetFlipBookFrameWidth(0)
    fb:SetFlipBookFrameHeight(0)
    return fb
end

-- Proc: Blizzard's proc loop on a (1.4 w + 2 xo) x (1.4 h + 2 yo) frame. With
-- no opening burst, proc and procloop draw the same loop on an aura button.
local function GlowProc(host, fw, fh, r, g, bl, a)
    local pr = host._adProc
    if not pr then
        pr = CreateFrame("Frame", nil, host)
        pr:SetPoint("CENTER", host, "CENTER", 0, 0)
        pr.loop = pr:CreateTexture(nil, "OVERLAY", nil, 6)
        pr.loop:SetAtlas(PROC_LOOP)
        pr.loop:SetAllPoints(pr)
        -- desaturated and tinted, as the cooldown lanes tint theirs
        if pr.loop.SetDesaturated then pr.loop:SetDesaturated(true) end
        local la = pr.loop:CreateAnimationGroup()
        la:SetLooping("REPEAT")
        pr.loopLit = LoopLit(la)
        FlipBook(la, nil, 1, 1)
        pr.loopAG = la
        host._adProc = pr
    end
    pr.loopAG:Stop()
    pr:SetSize(fw, fh)
    pr.loop:SetVertexColor(r, g, bl, 0)
    pr.loopLit:SetFromAlpha(a)
    pr.loopLit:SetToAlpha(a)
    pr:Show()
    pr.loopAG:Play()
end

-- Ants: the action bar's highlight flipbook (30 frames, a lap a second) on the
-- fw x fh box, 66/45 of the icon plus offsets. Desaturated so the colour tints
-- it.
local function GlowAnts(host, fw, fh, r, g, bl, a)
    local at = host._adAnts
    if not at then
        at = CreateFrame("Frame", nil, host)
        at:SetPoint("CENTER", host, "CENTER", 0, 0)
        at.tex = at:CreateTexture(nil, "OVERLAY", nil, 7)
        at.tex:SetAtlas(ANTS_ATLAS)
        at.tex:SetAllPoints(at)
        if at.tex.SetDesaturated then at.tex:SetDesaturated(true) end
        local ag = at.tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        at.lit = LoopLit(ag)
        FlipBook(ag, nil, 1, 1)
        at.ag = ag
        host._adAnts = at
    end
    at.ag:Stop()
    at:SetSize(fw, fh)
    at.tex:SetVertexColor(r, g, bl, 0)
    at.lit:SetFromAlpha(a)
    at.lit:SetToAlpha(a)
    at:Show()
    at.ag:Play()
end

-- Flash: the Cooldown Manager's glow art in the same box, the frame pulsing 25%
-- to 100% while the art's vertex alpha keeps the intensity. Speed 0.25 (the
-- default) matches the Cooldown Manager's 0.5 s each way.
local function GlowFlash(host, fw, fh, r, g, bl, a, speed)
    local fl = host._adFlash
    if not fl then
        fl = CreateFrame("Frame", nil, host)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 7)
        fl.tex:SetAtlas(FLASH_ATLAS)
        fl.tex:SetAllPoints(fl)
        if fl.tex.SetDesaturated then fl.tex:SetDesaturated(true) end
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        fl.up = ag:CreateAnimation("Alpha")
        fl.up:SetFromAlpha(0.25)
        fl.up:SetToAlpha(1)
        fl.up:SetOrder(1)
        if fl.up.SetSmoothing then fl.up:SetSmoothing("IN_OUT") end
        fl.down = ag:CreateAnimation("Alpha")
        fl.down:SetFromAlpha(1)
        fl.down:SetToAlpha(0.25)
        fl.down:SetOrder(2)
        if fl.down.SetSmoothing then fl.down:SetSmoothing("IN_OUT") end
        fl.ag = ag
        host._adFlash = fl
    end
    fl.ag:Stop()
    fl:SetSize(fw, fh)
    fl.tex:SetVertexColor(r, g, bl, a)
    local half = 0.125 / math.max(0.05, speed or 0.25)
    if half < 0.05 then half = 0.05 elseif half > 5 then half = 5 end
    fl.up:SetDuration(half)
    fl.down:SetDuration(half)
    fl:Show()
    fl.ag:Play()
end

-- Glow timing (auraActive.activeGlowWhen), all engine-driven:
--   always    while the aura is up: the host is the button's child
--   pandemic  the last 30%: Forever keeps no leftover time on a refresh, so
--             the engine never opens a pandemic window
--   time      under a time-left threshold: each texture is masked by the fill
--             of a hidden engine-driven duration bar (ApplyTimeGate). Seconds
--             need the aura's length set, as addons can't read its duration.
-- Buttons without a duration bar (the preview's stand-in) glow the whole time.

-- every glow texture with the frame that owns it (a mask clips only its
-- own frame's textures)
local function GlowTextures(host)
    local out = {}
    for _, e in ipairs(host._adPix or {}) do out[#out + 1] = { e.strip, host } end
    for _, it in ipairs(host._adSpk or {}) do out[#out + 1] = { it.tex, host } end
    local bt = host._adBtn
    if bt then
        out[#out + 1] = { bt.outer, bt }
        out[#out + 1] = { bt.ants, bt }
    end
    local pr = host._adProc
    if pr then out[#out + 1] = { pr.loop, pr } end
    local at = host._adAnts
    if at then out[#out + 1] = { at.tex, at } end
    local fl = host._adFlash
    if fl then out[#out + 1] = { fl.tex, fl } end
    return out
end

-- the gate mask on `frame`, anchored to the gate bar's fill
local function GateMask(frame, fill)
    local m = frame._adGateMask
    if not m then
        m = frame:CreateMaskTexture()
        -- NEAREST + CLAMPTOBLACKADDITIVE: clear outside the fill, no soft edge.
        m:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        frame._adGateMask = m
    end
    m:ClearAllPoints()
    m:SetAllPoints(fill)
    return m
end

local function SetGated(tex, mask)
    if tex._adGate == mask then return end
    if tex._adGate then tex:RemoveMaskTexture(tex._adGate) end
    if mask then tex:AddMaskTexture(mask) end
    tex._adGate = mask
end

-- The time-left gate: frac = the fraction of time left the glow shows under
-- (nil = no gate); W, H = the glow rect, centred on b and moved by mx, my.
local function ApplyTimeGate(b, host, frac, W, H, mx, my)
    local on = (frac ~= nil and b.SetDurationBar and Enum
        and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation) and true or false
    local fill
    if on then
        local gb = b._adGateBar
        if not gb then
            gb = CreateFrame("StatusBar", nil, b)
            gb:SetStatusBarTexture(WHITE)
            gb:SetStatusBarColor(1, 1, 1, 0)   -- never seen: its fill is only a rect
            gb:EnableMouse(false)
            b._adGateBar = gb
            b:SetDurationBar(gb, {
                interpolation = Enum.StatusBarInterpolation.Immediate,
                direction = Enum.StatusBarTimerDirection.ElapsedTime,
            })
        end
        -- Gate rect = glow rect plus a margin for overhanging art (the proc
        -- burst runs about 2.5x the icon). The range g .. g + 0.0002 flips the
        -- fill; with L = gw / 0.0005 and the -g * L shift, a range reset to
        -- 0 .. 1 would still cross the gate within 0.05% of the aura's life.
        local E = math.max(W, H)
        local gw, gh = W + 2 * E, H + 2 * E
        local L = math.min(120000, gw / 0.0005)
        local g = 1 - frac
        gb:ClearAllPoints()
        gb:SetSize(L, gh)
        gb:SetPoint("LEFT", b, "CENTER", -gw / 2 - g * L + (mx or 0), my or 0)
        gb:SetMinMaxValues(g, g + 0.0002)
        fill = gb:GetStatusBarTexture()
    end
    for _, pair in ipairs(GlowTextures(host)) do
        SetGated(pair[1], fill and GateMask(pair[2], fill) or nil)
    end
end

-- On/off plus the recipe from the Aura Active glow fields. w, h = the plain
-- button size; alphaMul = Active alpha; slot 2+ = a numbered glow (its own
-- fields and host); levelTo = an exact level (a Missing glow, which must stay
-- under the live button), else the glow's own level over b. Accessible
-- passes only.
function Factory.SetAuraButtonGlow(b, rec, on, w, h, alphaMul, slot, levelTo)
    if not b then return end
    local suf = (slot and slot > 1) and tostring(slot) or ""
    local hostKey, sigKey = "_adGlowHost" .. suf, "_adGlowSig" .. suf
    local host = b[hostKey]
    if not on then
        if host and host._adOn then
            HideGlowParts(host, nil)
            host:Hide()
            host._adOn = false
        end
        b[sigKey] = nil
        return
    end
    -- every field read here is a glow field, so the slot's suffix applies
    local R = function(s, k) return Store.Resolve(rec, s, k .. suf) end
    w = (w and w > 0) and w or 36
    h = (h and h > 0) and h or w
    local gtype = DrawnGlowStyle(R("auraActive", "activeGlowType") or "button")
    local c = R("auraActive", "activeGlowColor") or { 0.95, 0.95, 0.32, 1 }
    local a = (c[4] or 1) * (R("auraActive", "activeGlowIntensity") or 1) * (alphaMul or 1)
    local speed = math.max(0.05, R("auraActive", "activeGlowSpeed") or 0.25)
    local xo = R("auraActive", "activeGlowXOffset") or 0
    local yo = R("auraActive", "activeGlowYOffset") or 0
    local lines = math.max(1, math.floor(R("auraActive", "activeGlowLines") or 8))
    local th = R("auraActive", "activeGlowThickness") or 2
    local parts = math.max(1, math.floor(R("auraActive", "activeGlowParticles") or 4))
    local scale = R("auraActive", "activeGlowScale") or 1
    local lvl = R("auraActive", "activeGlowLevel") or GLOW_LEVEL
    local strata = R("auraActive", "activeGlowStrata") or "inherit"
    -- a Missing glow keeps the missing look's strata, under the button
    if levelTo then strata = "inherit" end
    -- Pixel dash length (0 = automatic) and the move.
    local dash = R("auraActive", "activeGlowLength") or 0
    local mx = R("auraActive", "activeGlowMoveX") or 0
    local my = R("auraActive", "activeGlowMoveY") or 0
    -- frac = the share of time left the glow shows under; nil = no gate.
    local when = R("auraActive", "activeGlowWhen") or "always"
    local frac
    if when == "pandemic" then
        frac = 0.3
    elseif when == "time" then
        if (R("auraActive", "activeGlowTimeUnit") or "pct") == "sec" then
            local len = R("auraActive", "activeGlowAuraLength") or 0
            if len > 0 then frac = math.min(1, (R("auraActive", "activeGlowTimeSec") or 5) / len) end
        else
            frac = (R("auraActive", "activeGlowTimePct") or 30) / 100
        end
    end
    -- A plain level: stamped by the single-icon driver when it anchors the
    -- button; group buttons read it, skipping a secret read (create window).
    local base = b._adLevel
    if type(base) ~= "number" then
        local v = b:GetFrameLevel()
        if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then base = v end
    end
    local sig = table.concat({ gtype, w, h, c[1], c[2], c[3], a, speed, xo, yo,
        lines, th, parts, scale, lvl, strata, base or -1,
        frac or -1, dash, mx, my, levelTo or -1 }, ":")
    if not host then
        host = CreateFrame("Frame", nil, b)
        host:EnableMouse(false)
        b[hostKey] = host
    end
    if host._adOn and b[sigKey] == sig then return end
    b[sigKey] = sig
    host:ClearAllPoints()
    local W, H
    if gtype == "pixel" or gtype == "autocast" then
        host:SetPoint("TOPLEFT", b, "TOPLEFT", -xo + mx, yo + my)
        host:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", xo + mx, -yo + my)
        W, H = w + 2 * xo, h + 2 * yo
    else
        -- button / proc lay their own 1.4x frame, ants / flash their
        -- template's 66/45 box, offsets expanding either
        host:SetPoint("CENTER", b, "CENTER", mx, my)
        host:SetSize(w, h)
        local k = (gtype == "ants" or gtype == "flash") and BLIZZ_RATIO or 1.4
        W, H = w * k + 2 * xo, h * k + 2 * yo
    end
    if W < 1 then W = 1 end
    if H < 1 then H = 1 end
    local glowLvl = levelTo or (base and (base + lvl))
    if glowLvl then host:SetFrameLevel(glowLvl) end
    if strata ~= "inherit" then
        host:SetFrameStrata(strata)
        host._adStrata = strata
    elseif host._adStrata then
        local s = b:GetFrameStrata()
        if type(s) == "string" and not (issecretvalue and issecretvalue(s)) then
            host:SetFrameStrata(s)
        end
        host._adStrata = nil
    end
    HideGlowParts(host, gtype)
    local r, g, bl = c[1], c[2], c[3]
    if gtype == "pixel" then
        -- Whole physical pixels; the buttons scale with UIParent.
        local tpx = th
        if PixelUtil and PixelUtil.GetNearestPixelSize then
            tpx = PixelUtil.GetNearestPixelSize(th, UIParent:GetEffectiveScale(), 1)
        end
        GlowPixel(host, W, H, lines, tpx, 1 / speed, r, g, bl, a, dash)
    elseif gtype == "autocast" then
        GlowSparkle(host, W, H, parts, scale, 1 / speed, r, g, bl, a)
    elseif gtype == "proc" or gtype == "procloop" then
        GlowProc(host, W, H, r, g, bl, a)
    elseif gtype == "ants" then
        GlowAnts(host, W, H, r, g, bl, a)
    elseif gtype == "flash" then
        GlowFlash(host, W, H, r, g, bl, a, speed)
    else
        GlowButton(host, W, H, r, g, bl, a, speed)
    end
    -- an exact level holds the style frames on it too, so nothing of the glow
    -- reaches the next rung; otherwise they sit one over the host
    if levelTo then
        LevelStyleFrames(host, levelTo - 1)
    elseif glowLvl then
        LevelStyleFrames(host, glowLvl)
    end
    ApplyTimeGate(b, host, frac, W, H, mx, my)
    host:Show()
    host._adOn = true
end

-- A glow set to "While the aura is missing" (an aura icon's glow `slot`).
function Factory.MissingGlowOn(rec, slot)
    if not (rec and rec.kind == "aura") then return false end
    local suf = (slot and slot > 1) and tostring(slot) or ""
    return Store.Resolve(rec, "auraActive", "activeGlow" .. suf) == true
        and Store.Resolve(rec, "auraActive", "activeGlowWhen" .. suf) == "missing"
end

function Factory.HasMissingGlow(rec)
    for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        if Factory.MissingGlowOn(rec, k) then return true end
    end
    return false
end

-- A glow set to "Always" (an aura icon's glow `slot`).
function Factory.AlwaysGlowOn(rec, slot)
    if not (rec and rec.kind == "aura") then return false end
    local suf = (slot and slot > 1) and tostring(slot) or ""
    return Store.Resolve(rec, "auraActive", "activeGlow" .. suf) == true
        and Store.Resolve(rec, "auraActive", "activeGlowWhen" .. suf) == "both"
end

-- A glow the holder draws (Missing or Always), never the live button.
function Factory.HolderGlowOn(rec, slot)
    return Factory.MissingGlowOn(rec, slot) or Factory.AlwaysGlowOn(rec, slot)
end

-- An aura icon's custom texts kept to the aura's absence.
function Factory.HasMissingText(rec)
    if not (rec and rec.kind == "aura") then return false end
    for _, suf in ipairs({ "", "2", "3" }) do
        local t = Store.Resolve(rec, "label", "labelText" .. suf)
        if Store.Resolve(rec, "label", "labelMissingOnly" .. suf) == true and t ~= nil and t ~= "" then
            return true
        end
    end
    return false
end

-- Pixels past the icon those texts can reach (offsets plus a generous width), for the eraser.
function Factory.MissingTextReach(rec, kS)
    if not Factory.HasMissingText(rec) then return 0 end
    kS = kS or 1
    local reach = 0
    for _, suf in ipairs({ "", "2", "3" }) do
        local t = Store.Resolve(rec, "label", "labelText" .. suf)
        if Store.Resolve(rec, "label", "labelMissingOnly" .. suf) == true and t ~= nil and t ~= "" then
            local size = (Store.Resolve(rec, "label", "labelSize" .. suf) or 12) * kS
            local x = math.abs(Store.Resolve(rec, "label", "labelX" .. suf) or 0) * kS
            local y = math.abs(Store.Resolve(rec, "label", "labelY" .. suf) or 0) * kS
            reach = math.max(reach, math.max(x, y) + math.max(#t * size * 0.7, size))
        end
    end
    return math.ceil(reach)
end

-- Always glows: on the holder itself, never on the stage, so they show in both states.
function Factory.ApplyAlwaysGlows(f, rec, w, h, combat)
    local host = f._adAlwaysGlow
    local D = NS.DriverAura
    local ok = rec ~= nil and rec.kind == "aura" and D ~= nil and D.GlowLaneOK ~= nil
        and D.GlowLaneOK(rec) and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
    if not ok and not host then return end
    local lvl = f:GetFrameLevel()
    if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then lvl = nil end
    for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        local suf = (k > 1) and tostring(k) or ""
        local want = ok and Factory.AlwaysGlowOn(rec, k)
            and (combat == true or Store.Resolve(rec, "auraActive", "activeGlowCombatOnly" .. suf) ~= true)
        if want and not host then
            host = CreateFrame("Frame", nil, f)
            host:SetAllPoints(f)
            host:EnableMouse(false)
            f._adAlwaysGlow = host
        end
        if host then
            -- the live button's own glow level: over the button and the holder's texts
            host._adLevel = lvl and (lvl + Factory.AURA_LADDER.button)
            Factory.SetAuraButtonGlow(host, rec, want, w, h, 1, k)
        end
    end
end

-- Missing glows ride the missing look: its parent frame, their rung of AURA_LADDER, its alpha.
function Factory.ApplyMissingGlows(f, rec, w, h, combat)
    local host = f._adMissGlow
    local D = NS.DriverAura
    local ok = rec ~= nil and rec.kind == "aura" and D ~= nil and D.MissingGlowOK ~= nil
        and D.MissingGlowOK(rec) and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
    if not ok and not host then return end
    local lvl = f:GetFrameLevel()
    if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then lvl = nil end
    local rung = lvl and (lvl + Factory.AURA_LADDER.missGlow)
    for k = 1, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        local suf = (k > 1) and tostring(k) or ""
        local want = ok and Factory.MissingGlowOn(rec, k)
            and (combat == true or Store.Resolve(rec, "auraActive", "activeGlowCombatOnly" .. suf) ~= true)
        if want and not host then
            host = CreateFrame("Frame", nil, f._adStage or f)
            host:SetAllPoints(f)
            host:EnableMouse(false)
            f._adMissGlow = host
        end
        if host then
            if rung then host:SetFrameLevel(rung) end
            host:SetAlpha(f._adShownAlpha or f._adStateAlpha or 1)
            Factory.SetAuraButtonGlow(host, rec, want, w, h, 1, k, rung)
        end
    end
end

-- A glow lane's button (DriverAura's glow lanes): it carries one glow alone,
-- opts.glowSlot (1-4), and only while opts.glowOn says its lane is live.
-- Accessible passes only, like SetAuraButtonGlow.
function Factory.StyleAuraGlowButton(b, rec, px, opts)
    if not (b and rec) then return end
    opts = opts or {}
    local slot = opts.glowSlot or 1
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local aA = Factory.AuraActiveAlpha(rec)
    b:SetAlpha(1)
    Factory.SetAuraButtonGlow(b, rec, opts.glowOn == true
        and R("appearance", "forceHideIcon") ~= true
        and R("auraActive", "activeGlow" .. ((slot > 1) and slot or "")) == true,
        opts.w or px, opts.h or px, aA, slot)
end

-- State writer: drivers report, this paints. onCooldown picks the alpha bucket
-- (missing, on an aura icon); desatState (nil = onCooldown) drives desaturation
-- alone, so a recharging charge spell dims but stays colored until depleted.
function Factory.SetState(f, rec, onCooldown, desatState)
    f._adOnCooldown = onCooldown and true or false
    if desatState == nil then desatState = onCooldown end
    f._adDesatState = desatState and true or false
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    if f._adLabels then
        for _, st in ipairs(f._adLabels) do
            if st.has and st.fs then
                if rec.kind == "aura" then
                    -- The live holder always wears the missing look, so a label
                    -- kept to the aura's time shows here only in the editor
                    -- preview's active phase; live, its copy rides the button.
                    -- A label kept to its absence has its copy under the button.
                    st.fs:SetShown(not st.missingOnly and not (st.activeOnly and onCooldown))
                else
                    -- the kind's second state: on cooldown, or ammo's none left
                    local second = onCooldown
                    if rec.kind == "ammo" then second = f._adItemEmpty == true end
                    st.fs:SetShown((second and st.cd) or ((not second) and st.ready))
                end
            end
        end
    end
    if rec.kind == "aura" then
        -- onCooldown here means the aura is missing: a whole-icon dim with its
        -- own text carve-out, as aura icons have no States tab.
        local a, desat = 1, false
        if onCooldown then
            a = (R("auraMissing", "showWhileMissing") == false) and 0
                or (R("auraMissing", "missingAlpha") or 1)
            desat = R("auraMissing", "missingDesaturate") ~= false
        end
        ApplyStateAlpha(f, a, R("auraMissing", "missingPreserveText") ~= false)
        f.icon:SetDesaturated(desat)
        -- The live holder only takes the missing art (the button carries the
        -- active); the editor preview flips both, so its Active icon shows too.
        if onCooldown then
            f.icon:SetTexture(Factory.GetTexture(rec))
        else
            f.icon:SetTexture(Factory.AuraLiveTexture(rec))
        end
        return
    end
    local keepBright = R("appearance", "keepBright") == true
    if keepBright then
        f._adStateAlpha = 1
    elseif onCooldown then
        f._adStateAlpha = R("states", "cooldownAlpha") or 1
    else
        f._adStateAlpha = R("states", "readyAlpha") or 1
        -- Usability dim: an unusable or no-resource ready spell takes the lower
        -- of the two alphas. Out of range never dims; its tint shows it.
        local ucode = f._adUsability
        if ucode == "unusable" then
            f._adStateAlpha = math.min(f._adStateAlpha, R("states", "unusableAlpha") or 1)
        elseif ucode == "nomana" then
            f._adStateAlpha = math.min(f._adStateAlpha, R("states", "resourceAlpha") or 1)
        end
    end
    -- A group buff in combat: nobody's buffs can be read, so its count and
    -- icon step aside (its driver's layers show instead, when switched on).
    if rec.kind == "groupbuff" and f._adGBHidden then f._adStateAlpha = 0 end
    -- procOverride: a lit proc forces full opacity, over the usability dim too.
    if f._adProcOn and R("states", "procOverride") == true then
        f._adStateAlpha = 1
    end
    -- usableOverride: full opacity while ready and usable (range is usable).
    if not onCooldown and R("states", "usableOverride") == true
        and (f._adUsability == nil or f._adUsability == "range") then
        f._adStateAlpha = 1
    end
    -- preserveDurationText (on by default) keeps the texts out of the dim.
    ApplyStateAlpha(f, f._adStateAlpha,
        R("states", "preserveDurationText") ~= false)
    local desatOK = not keepBright or R("appearance", "keepBrightAllowDesat") == true
    f.icon:SetDesaturated(desatOK and f._adDesatState
        and R("states", "cooldownDesaturate") == true or false)
    -- No-resource or unusable can grey the icon apart from the cooldown desat.
    if not onCooldown and desatOK then
        local ucode = f._adUsability
        if (ucode == "nomana" and R("states", "resourceDesaturate") == true)
            or (ucode == "unusable" and R("states", "unusableDesaturate") == true) then
            f.icon:SetDesaturated(true)
        end
    end
    -- "Desaturate while the aura is down" with an aura overlay: the art stays
    -- grey under the aura's button, so it reads grey exactly while the aura is
    -- down, with no presence read. Wins over every other desaturation.
    if R("auraActive", "overlayDesatInactive") == true and NS.DriverAura
        and NS.DriverAura.OverlayOn and NS.DriverAura.OverlayOn(rec) then
        f.icon:SetDesaturated(true)
    end
    -- Tint priority, as Blizzard's: range red, usability, state tints, white.
    local tc
    if not onCooldown then
        local code = f._adUsability
        if code == "range" and R("states", "rangeTint") ~= false then
            tc = R("states", "rangeTintColor") or { 0.85, 0.2, 0.2, 1 }
        elseif code == "nomana" and R("states", "usabilityTint") ~= false then
            tc = R("states", "resourceTintColor") or { 0.35, 0.45, 1, 1 }
        elseif code == "unusable" and R("states", "usabilityTint") ~= false then
            tc = R("states", "unusableTintColor") or { 0.45, 0.45, 0.45, 1 }
        elseif R("states", "readyTintEnabled") == true then
            tc = R("states", "readyTintColor")
        end
    elseif R("states", "cooldownTintEnabled") == true then
        tc = R("states", "cooldownTintColor")
    end
    -- Vertex alpha is the texture's alpha: a literal 1 would undo the state
    -- dim's SetAlpha on the art, so every tint carries the shown alpha.
    local va = f._adShownAlpha or f._adStateAlpha or 1
    if tc then
        f.icon:SetVertexColor(tc[1], tc[2], tc[3], va)
    else
        f.icon:SetVertexColor(1, 1, 1, va)
    end
    -- Hide-when-missing is frame alpha. Out of stock forces desat and alpha
    -- (the driver keeps the last known state while reads are secret).
    if rec.kind == "item" or rec.kind == "trinket" or rec.kind == "ammo" then
        Factory.ApplyFrameAlpha(f, rec)
    end
    if (rec.kind == "item" or rec.kind == "ammo") and f._adItemEmpty then
        if R("outOfStock", "outDesaturate") ~= false then
            f.icon:SetDesaturated(true)
        end
        if R("outOfStock", "outAlphaEnabled") == true then
            -- preserveDurationText applies: items and ammo have a States tab.
            ApplyStateAlpha(f, R("outOfStock", "outAlpha") or 0.4,
                R("states", "preserveDurationText") ~= false)
        end
    end
    -- Dynamic groups re-place from here, so every icon kind moves them. Fired
    -- when a drop-out input flips (busy, state alpha 0, hidden while missing),
    -- for recorded icons only: the preview's fake cooldown must not wake them.
    if f._adRecId then
        local sig = (f._adOnCooldown and 1 or 0)
            + (((f._adStateAlpha or 1) <= 0) and 2 or 0)
            + ((f._adItemEmpty and R("outOfStock", "hideWhenMissing") == true) and 4 or 0)
            + (f._adPassive and 8 or 0)
        if f._adDynSig ~= sig then
            f._adDynSig = sig
            NS.Events.Fire("AD_DYNEDGE")
        end
    end
    Factory.UpdateGlow(f, rec, not onCooldown)
    Factory.UpdateUsableGlow(f, rec)
    Factory.UpdateCooldownGlow(f, rec)
end

-- usability code from the driver: "range" | "nomana" | "unusable" | nil
function Factory.SetUsability(f, rec, code)
    if f._adUsability == code then return end
    f._adUsability = code
    Factory.SetState(f, rec, f._adOnCooldown, f._adDesatState)
end

-- Glow library accessor. Must stay above every glow user: a function defined
-- before this local compiles a global lookup instead of the upvalue.
local function GetLCG()
    if not LibStub then return nil end
    -- Always the bundled copy: a standard copy another addon loads may be an
    -- older one that errors on this client and can't key the button glow.
    return LibStub("ArcGlow-1.0", true)
end

-- Glow parameter signature: a lane restarts only when it changes, as a restart
-- is visible and ApplyStyle runs on every rebuild. Must stay above the lanes.
-- It includes the icon's frame level: the library sets the glow's level only
-- in Start and children don't follow a later SetFrameLevel, so after a level
-- change the glow would sink behind the border. ext = LaneExt's parts.
local function GlowSig(f, gtype, color, speed, a, b, c2, d, xo, yo, lvl, strata, ext)
    local host = f.GetFrameLevel and f:GetFrameLevel()
    if issecretvalue and issecretvalue(host) then host = -1 end
    if type(host) ~= "number" then host = -1 end
    return table.concat({ gtype, color[1], color[2], color[3], color[4] or 1,
        speed, a or 0, b or 0, c2 or 0, d or 0, xo or 0, yo or 0,
        lvl or GLOW_LEVEL, strata or "inherit", host, ext or "" }, ":")
end

-- Lane signature extras: dash length, Move X / Y, and for our own ants and
-- flash the icon size their box is baked from (library frames follow anchors).
local function LaneExt(f, gtype, len, mx, my)
    local s = (len or 0) .. ":" .. (mx or 0) .. ":" .. (my or 0)
    if gtype == "ants" or gtype == "flash" then
        local w, h = f:GetSize()
        if type(w) ~= "number" or type(h) ~= "number"
            or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then
            return s .. ":?"
        end
        s = s .. ":" .. string.format("%.2fx%.2f", w, h)
    end
    return s
end

-- Glow lanes: ready "ad", proc "adproc" and usable "adu", each under its own
-- glow key so they never stop each other, all through StopLane and
-- StartLane so each offers every style. Ants and flash are our own builders on
-- a per-lane host (TexLaneStart), which every stop takes down too.
local function StopLane(f, key)
    local tg = f["_adTexGlow" .. key]
    if tg then
        HideGlowParts(tg, nil)
        tg:Hide()
    end
    local LCG = GetLCG()
    if not LCG then return end
    LCG.PixelGlow_Stop(f, key)
    LCG.AutoCastGlow_Stop(f, key)
    LCG.ButtonGlow_Stop(f, key)
    if LCG.ProcGlow_Stop then LCG.ProcGlow_Stop(f, key) end
end

-- the frame the library parked on the icon for this key, so strata can be
-- applied after the start (it takes a level but never a strata)
local GLOW_FIELDS = { "_PixelGlow", "_AutoCastGlow", "_ButtonGlow", "_ProcGlow" }
local function GlowFrameFor(f, key)
    for _, pre in ipairs(GLOW_FIELDS) do
        local g = f[pre .. key]
        if g then return g end
    end
end

-- The glow library pools its frames and nothing resets strata, so a custom
-- strata would ride a recycled frame into its next user. The marker puts it
-- back once the setting returns to "inherit".
local function ApplyStrata(f, key, strata)
    local g = GlowFrameFor(f, key)
    if not (g and g.SetFrameStrata) then return end
    if strata and strata ~= "inherit" then
        g:SetFrameStrata(strata)
        g._adStrataOverride = strata
    elseif g._adStrataOverride then
        g:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
        g._adStrataOverride = nil
    end
end

-- Preview lane lock: f._adGlowLaneOnly limits the preview to the edited lane.
-- It filters before any start; stopping lanes afterwards would fight
-- ApplyStyle, which the preview re-runs several times a second, and flicker.
local function LaneAllowed(f, lane)
    local only = f._adGlowLaneOnly
    return only == nil or only == lane
end
Factory.LaneAllowed = LaneAllowed

-- Move X / Y on a library glow: the library re-anchors its frame on every
-- Start, so each point shifts once right after it. A secret read, unexpected
-- on our own frame, leaves the glow where the library put it.
local function ShiftGlow(g, mx, my)
    mx, my = mx or 0, my or 0
    if not g or (mx == 0 and my == 0) then return end
    local pts = {}
    for i = 1, (g:GetNumPoints() or 0) do
        local p, rel, rp, x, y = g:GetPoint(i)
        if issecretvalue and (issecretvalue(p) or issecretvalue(x) or issecretvalue(y)) then return end
        pts[i] = { p, rel, rp, x or 0, y or 0 }
    end
    g:ClearAllPoints()
    for _, q in ipairs(pts) do g:SetPoint(q[1], q[2], q[3], q[4] + mx, q[5] + my) end
end

-- Ants and flash on a cooldown lane: the aura-button builders on a per-lane
-- host at the lane's level and strata; the icon is ours, so groups just play.
local function TexLaneStart(f, key, gtype, p)
    local host = f["_adTexGlow" .. key]
    if not host then
        host = CreateFrame("Frame", nil, f)
        host:EnableMouse(false)
        f["_adTexGlow" .. key] = host
    end
    local w, h = f:GetSize()
    if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) or w <= 0 then w = 36 end
    if type(h) ~= "number" or (issecretvalue and issecretvalue(h)) or h <= 0 then h = w end
    host:ClearAllPoints()
    host:SetPoint("CENTER", f, "CENTER", p.mx or 0, p.my or 0)
    host:SetSize(w, h)
    local lvl = f:GetFrameLevel()
    local plainLvl = type(lvl) == "number" and not (issecretvalue and issecretvalue(lvl))
    if plainLvl then
        host:SetFrameLevel(lvl + (p.level or GLOW_LEVEL))
    end
    -- the same strata marker rule as the library frames (ApplyStrata)
    if p.strata and p.strata ~= "inherit" then
        host:SetFrameStrata(p.strata)
        host._adStrataOverride = p.strata
    elseif host._adStrataOverride then
        host:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
        host._adStrataOverride = nil
    end
    HideGlowParts(host, gtype)
    local W = math.max(1, w * BLIZZ_RATIO + 2 * (p.xo or 0))
    local H = math.max(1, h * BLIZZ_RATIO + 2 * (p.yo or 0))
    local c = p.color
    if gtype == "ants" then
        GlowAnts(host, W, H, c[1], c[2], c[3], c[4] or 1)
    else
        GlowFlash(host, W, H, c[1], c[2], c[3], c[4] or 1, p.speed)
    end
    if plainLvl then LevelStyleFrames(host, lvl + (p.level or GLOW_LEVEL)) end
    host:SetAlpha(1)
    host:Show()
end

-- the field the library parks each style's frame under (ShiftGlow's target)
local LCG_FIELD = { pixel = "_PixelGlow", autocast = "_AutoCastGlow",
    button = "_ButtonGlow", proc = "_ProcGlow", procloop = "_ProcGlow" }

local function StartLane(f, key, gtype, p)
    if gtype == "ants" or gtype == "flash" then
        TexLaneStart(f, key, gtype, p)
        return
    end
    local LCG = GetLCG()
    if not LCG then return end
    local lvl = p.level or GLOW_LEVEL
    if gtype == "pixel" then
        -- the dash length: 0 = the library's automatic length
        local len = (type(p.length) == "number" and p.length > 0) and p.length or nil
        LCG.PixelGlow_Start(f, p.color, p.lines, p.speed, len, p.thickness,
            p.xo, p.yo, false, key, lvl)
    elseif gtype == "autocast" then
        LCG.AutoCastGlow_Start(f, p.color, p.particles, p.speed, p.scale,
            p.xo, p.yo, key, lvl)
    elseif (gtype == "proc" or gtype == "procloop") and LCG.ProcGlow_Start then
        -- procloop = the proc glow without its opening burst
        LCG.ProcGlow_Start(f, { color = p.color, key = key,
            frameLevel = lvl, xOffset = p.xo, yOffset = p.yo,
            startAnim = gtype == "proc" })
    else
        LCG.ButtonGlow_Start(f, p.color, p.speed, lvl, key, p.xo, p.yo)
        gtype = "button"
    end
    ApplyStrata(f, key, p.strata)
    ShiftGlow(f[LCG_FIELD[gtype] .. key], p.mx, p.my)
end
-- Any frame of ours can wear a lane under its own key (the Reminder group's
-- pulses: Drivers\AD_DriverReminders.lua), every style included.
Factory.StartGlowLane = StartLane
Factory.StopGlowLane = StopLane

-- Proc glow (SPELL_ACTIVATION_OVERLAY), with the other lanes' options.
function Factory.SetProcGlow(f, rec, on)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local want = on and R("states", "procGlow") == true
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "proc")
    if not want then
        Factory.StopProcGlow(f)
        return
    end
    local c = R("states", "procGlowColor") or { 0.95, 0.95, 0.32, 1 }
    local inten = R("states", "procGlowIntensity") or 1
    local p = {
        color = { c[1], c[2], c[3], (c[4] or 1) * inten },
        speed = R("states", "procGlowSpeed") or 0.4,
        lines = R("states", "procGlowLines") or 10,
        thickness = R("states", "procGlowThickness") or 2,
        particles = R("states", "procGlowParticles") or 4,
        scale = R("states", "procGlowScale") or 1,
        xo = R("states", "procGlowXOffset") or 0,
        yo = R("states", "procGlowYOffset") or 0,
        length = R("states", "procGlowLength") or 0,
        mx = R("states", "procGlowMoveX") or 0,
        my = R("states", "procGlowMoveY") or 0,
    }
    p.level = (R("states", "procGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    p.strata = R("states", "procGlowStrata") or "inherit"
    local gtype = DrawnGlowStyle(R("states", "procGlowType") or "proc")
    local sig = GlowSig(f, gtype, p.color, p.speed, p.lines, p.thickness,
        p.particles, p.scale, p.xo, p.yo, p.level, p.strata,
        LaneExt(f, gtype, p.length, p.mx, p.my))
    if f._adProcOn and f._adProcSig == sig then return end
    Factory.StopProcGlow(f)
    StartLane(f, "adproc", gtype, p)
    f._adProcOn = true
    f._adProcSig = sig
end

function Factory.SetStack(f, count)
    if count and count > 1 then
        f.stackText:SetText(count)
    else
        f.stackText:SetText("")
    end
end

-- Charges can read secret: SetText only, never compared or zero-tested.
function Factory.SetChargeText(f, rec, sid, isCharge)
    if not isCharge then
        f.stackText:SetText("")
        return
    end
    if sid and C_Spell.GetSpellCharges then
        local ch = C_Spell.GetSpellCharges(sid)
        if ch then
            local count = ch.currentCharges
            -- Via TruncateWhenZero: comparing a secret count throws.
            if rec and Store.Resolve(rec, "text", "hideChargeAtZero") == true
                and C_StringUtil and C_StringUtil.TruncateWhenZero then
                count = C_StringUtil.TruncateWhenZero(count)
            end
            f.stackText:SetText(count)
        end
        -- nil charge info is transient (mid-GCD): keep the last text.
    end
end

-- Edit chip: a child button shown while the options panel is open. OnClick
-- looks the record up through f._adRecId, as frames are reused across records.
local function EnsureEditChip(f)
    if f._adEditBtn then return f._adEditBtn end
    local b = CreateFrame("Button", nil, f)
    b:SetSize(24, 12)
    b:SetPoint("BOTTOM", f, "BOTTOM", 0, -2)
    b:RegisterForClicks("LeftButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    b.fs = b:CreateFontString(nil, "OVERLAY")
    b.fs:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
    b.fs:SetPoint("CENTER", 0, 0)
    b.fs:SetText("Edit")
    b.fs:SetTextColor(1, 0.8, 0)
    b:SetScript("OnEnter", function(s) s.fs:SetTextColor(1, 1, 0.3) end)
    b:SetScript("OnLeave", function(s) s.fs:SetTextColor(1, 0.8, 0) end)
    b:SetScript("OnClick", function()
        local rec = Store.Get(f._adRecId)
        if rec and NS.Options and NS.Options.SelectIconHome then
            NS.Options.Open()
            NS.Options.SelectIconHome(rec)
        end
    end)
    b:Hide()
    f._adEditBtn = b
    return b
end

-- Settings "Edit buttons on screen": whether this kind ("icon" or "bar")
-- shows its Edit chip while the options window is open. The one reader of
-- the setting (the engine's bar chrome and the Settings row go through it):
-- nil is "all", the way the panel stores the default.
function Factory.EditChipsOn(kind)
    local v = Store.GetSetting("editButtons")
    if v == "none" then return false end
    -- anything but the other kind's "only" keeps a kind's chips (a value the
    -- panel never wrote reads as all)
    if kind == "bar" then return v ~= "icons" end
    return v ~= "bars"
end

-- The chip of the icon the editor has open reads Editing, widened to fit.
function Factory.SetEditing(f, on)
    local b = f._adEditBtn
    if not b or (b._adEditing or false) == on then return end
    b._adEditing = on
    b:SetSize(on and 32 or 24, 12)
    b.fs:SetText(on and "Editing" or "Edit")
end

-- Lane stops and the ready glow

-- Each lane stops only itself, so refreshing the ready glow never kills a
-- live proc glow. StopGlow stops every lane when a frame is released.
function Factory.StopReadyGlow(f)
    if not f._adGlowOn then return end
    StopLane(f, "ad")
    f._adGlowOn = false
    f._adGlowSig = nil
end

function Factory.StopProcGlow(f)
    if not f._adProcOn then return end
    StopLane(f, "adproc")
    f._adProcOn = false
    f._adProcSig = nil
end

function Factory.StopAuraGlow(f)
    if not f._adAuraOn then return end
    StopLane(f, "adaura")
    f._adAuraOn = false
    f._adAuraSig = nil
end

function Factory.StopGlow(f)
    Factory.StopProcGlow(f)
    Factory.StopReadyGlow(f)
    Factory.StopAuraGlow(f)
    Factory.StopCooldownGlow(f)
end

-- The Aura Active glow is drawn on the live engine button (SetAuraButtonGlow):
-- on the holder it would need a presence read, which fails closed in combat.
-- StopAuraGlow only clears a leftover "adaura" lane.

-- Glow while ready (the alpha bucket's ready state).
function Factory.UpdateGlow(f, rec, ready)
    local LCG = GetLCG()
    if not LCG then return end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local want = ready and rec.kind ~= "aura" and R("states", "readyGlow") == true
        and LaneAllowed(f, "ready")
    -- Combat-only is re-checked on every restyle and at each combat edge
    -- (Factory.CombatGlows).
    if want and R("states", "readyGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    if not want then
        Factory.StopReadyGlow(f)
        return
    end
    local c = R("states", "readyGlowColor") or { 0.95, 0.95, 0.32, 1 }
    -- Intensity rides the color's alpha.
    local inten = R("states", "readyGlowIntensity") or 1
    local color = { c[1], c[2], c[3], (c[4] or 1) * inten }
    local gtype = DrawnGlowStyle(R("states", "readyGlowType") or "button")
    local speed = R("states", "readyGlowSpeed") or 0.25
    local xo = R("states", "readyGlowXOffset") or 0
    local yo = R("states", "readyGlowYOffset") or 0
    local lines = R("states", "readyGlowLines") or 8
    local th = R("states", "readyGlowThickness") or 2
    local parts = R("states", "readyGlowParticles") or 4
    local scale = R("states", "readyGlowScale") or 1
    local lvl = (R("states", "readyGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    local strata = R("states", "readyGlowStrata") or "inherit"
    local len = R("states", "readyGlowLength") or 0
    local mx = R("states", "readyGlowMoveX") or 0
    local my = R("states", "readyGlowMoveY") or 0
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my))
    if f._adGlowOn and f._adGlowSig == sig then return end
    Factory.StopReadyGlow(f)
    StartLane(f, "ad", gtype, { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my })
    f._adGlowOn = true
    f._adGlowSig = sig
end

-- Usable glow, key "adu" so it never fights the ready or proc glow (the
-- bundled library keys ButtonGlow too). It glows while the
-- spell has its resources and no real cooldown runs: f._adOnCooldown ignores
-- the GCD, and f._adUsability is already secret-guarded (nil = usable).
function Factory.StopUsableGlow(f)
    if not f._adUsableOn then return end
    StopLane(f, "adu")
    f._adUsableOn = false
    f._adUsableSig = nil
end

function Factory.UpdateUsableGlow(f, rec)
    local LCG = GetLCG()
    if not LCG then return end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local want = rec.kind == "spell"
        and R("states", "usableGlow") == true
        and f._adUsability == nil
        and not f._adOnCooldown
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "usable")
    if want and R("states", "usableGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    if not want then
        Factory.StopUsableGlow(f)
        return
    end
    local c = R("states", "usableGlowColor") or { 0.48, 0.85, 0.56, 1 }
    local inten = R("states", "usableGlowIntensity") or 1
    local color = { c[1], c[2], c[3], (c[4] or 1) * inten }
    local gtype = DrawnGlowStyle(R("states", "usableGlowType") or "button")
    local speed = R("states", "usableGlowSpeed") or 0.25
    local xo = R("states", "usableGlowXOffset") or 0
    local yo = R("states", "usableGlowYOffset") or 0
    local lines = R("states", "usableGlowLines") or 8
    local th = R("states", "usableGlowThickness") or 2
    local parts = R("states", "usableGlowParticles") or 4
    local scale = R("states", "usableGlowScale") or 1
    local lvl = (R("states", "usableGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    local strata = R("states", "usableGlowStrata") or "inherit"
    local len = R("states", "usableGlowLength") or 0
    local mx = R("states", "usableGlowMoveX") or 0
    local my = R("states", "usableGlowMoveY") or 0
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my))
    if f._adUsableOn and f._adUsableSig == sig then return end
    Factory.StopUsableGlow(f)
    StartLane(f, "adu", gtype, { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my })
    f._adUsableOn = true
    f._adUsableSig = sig
end

-- The cooldown glow, key "adcdg": lit while the icon wears its cooldown look
-- (f._adOnCooldown, which the driver keeps clear of the GCD), on the kinds the
-- schema's cooldownGlow names.
function Factory.StopCooldownGlow(f)
    if not f._adCdGlowOn then return end
    StopLane(f, "adcdg")
    f._adCdGlowOn = false
    f._adCdGlowSig = nil
end

function Factory.UpdateCooldownGlow(f, rec)
    local LCG = GetLCG()
    if not LCG then return end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local want = f._adOnCooldown == true and rec.kind ~= "aura"
        and R("states", "cooldownGlow") == true
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "cooldown")
    if want and R("states", "cooldownGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    if not want then
        Factory.StopCooldownGlow(f)
        return
    end
    local c = R("states", "cooldownGlowColor") or { 0.95, 0.95, 0.32, 1 }
    local inten = R("states", "cooldownGlowIntensity") or 1
    local color = { c[1], c[2], c[3], (c[4] or 1) * inten }
    local gtype = DrawnGlowStyle(R("states", "cooldownGlowType") or "button")
    local speed = R("states", "cooldownGlowSpeed") or 0.25
    local xo = R("states", "cooldownGlowXOffset") or 0
    local yo = R("states", "cooldownGlowYOffset") or 0
    local lines = R("states", "cooldownGlowLines") or 8
    local th = R("states", "cooldownGlowThickness") or 2
    local parts = R("states", "cooldownGlowParticles") or 4
    local scale = R("states", "cooldownGlowScale") or 1
    local lvl = (R("states", "cooldownGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    local strata = R("states", "cooldownGlowStrata") or "inherit"
    local len = R("states", "cooldownGlowLength") or 0
    local mx = R("states", "cooldownGlowMoveX") or 0
    local my = R("states", "cooldownGlowMoveY") or 0
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my))
    if f._adCdGlowOn and f._adCdGlowSig == sig then return end
    Factory.StopCooldownGlow(f)
    StartLane(f, "adcdg", gtype, { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my })
    f._adCdGlowOn = true
    f._adCdGlowSig = sig
end

-- A combat edge re-checks only the lanes with a combat-only switch, with the
-- inputs SetState last gave them. Aura holders have none of these lanes.
function Factory.CombatGlows(f, rec)
    if rec.kind == "aura" then return end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    if R("states", "readyGlowCombatOnly") == true then
        Factory.UpdateGlow(f, rec, not f._adOnCooldown)
    end
    if R("states", "usableGlowCombatOnly") == true then Factory.UpdateUsableGlow(f, rec) end
    if R("states", "cooldownGlowCombatOnly") == true then Factory.UpdateCooldownGlow(f, rec) end
end

-- Duration text visibility, re-applied per feed. Hiding while charges remain
-- uses the shadow-derived f._adChargesAvail, never the secret charge count.
function Factory.ApplyDurationVis(f, rec)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    local hide = R("text", "durationText") == false
    if not hide and f._adChargesAvail
        and R("text", "hideDurWithCharges") == true then
        hide = true
    end
    f.cooldown:SetHideCountdownNumbers(hide)
end

-- Keybind text setter; the cooldown driver resolves the binding.
function Factory.SetKeybindText(f, txt)
    f.keybindText:SetText(txt or "")
end

-- GCD presentation, set by the cooldown driver per feed. pure = a GCD-only spin
-- (the shadows see no real cooldown), drawn in the GCD look; wand = that spin
-- is the wand's lock, drawn in the wand look. A real cooldown restores the
-- swipe settings.
function Factory.SetGCDPresentation(f, rec, pure, recharging, wand)
    pure = pure and true or false
    recharging = recharging and true or false
    wand = (pure and wand) and true or false
    if (f._adPureGCD or false) == pure
        and (f._adRecharging or false) == recharging
        and (f._adPureWand or false) == wand then
        return
    end
    f._adPureGCD = pure
    f._adRecharging = recharging
    f._adPureWand = wand
    ApplyCdPresentation(f, rec)
end

-- Mouse and tooltips

-- Tooltip by kind. Inputs are plain configured numbers; no secret is compared.
function Factory.ShowTooltip(f, rec)
    local d = rec.driver or {}
    local kind = rec.kind
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    if (kind == "spell" or kind == "aura" or kind == "timer") and d.spellID then
        -- The rank or override the driver is tracking (Auto rank on ranked
        -- realms), stamped on the frame each feed; else the stored ID.
        local sid = f._adEffSid or d.spellID
        if C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(sid) then
            GameTooltip:SetSpellByID(sid)
        else
            GameTooltip:SetText(rec.name or "Unknown spell")
        end
    elseif kind == "item" and d.itemID then
        local DC = NS.DriverCooldown
        GameTooltip:SetItemByID((DC and DC.LiveItem and DC.LiveItem(rec)) or d.itemID)
    elseif kind == "trinket" and d.slotID then
        GameTooltip:SetInventoryItem("player", d.slotID)
    elseif kind == "ammo" then
        GameTooltip:SetInventoryItem("player", AMMO_SLOT)
    elseif kind == "totem" then
        local slot = d.slot or 1
        if NS.DriverTotem then slot = NS.DriverTotem.SlotFor(rec) end
        -- an empty slot on an icon following the totem bar: the totem it would drop
        local barSid = NS.DriverTotem and NS.DriverTotem.BarShows and NS.DriverTotem.BarShows(rec)
        if barSid then
            GameTooltip:SetSpellByID(barSid)
        elseif slot and GameTooltip.SetTotem then
            GameTooltip:SetTotem(slot)
        elseif d.spellID then
            GameTooltip:SetSpellByID(d.spellID)
        else
            GameTooltip:SetText(rec.name or "Arc Auras")
        end
    elseif kind == "enchant" then
        -- the weapon's tooltip carries its enchant line and time
        GameTooltip:SetInventoryItem("player", NS.DriverEnchant and NS.DriverEnchant.InvSlot(rec) or 16)
    elseif kind == "special" and NS.SpecialIcon then
        NS.SpecialIcon.Tooltip(rec)
    elseif kind == "groupbuff" and NS.DriverGroupBuff then
        -- the buff, then who lacks it at the last count (read between pulls)
        GameTooltip:SetText(rec.name or "Group Buff")
        NS.DriverGroupBuff.TooltipLines(rec)
    else
        GameTooltip:SetText(rec.name or "Arc Auras")
    end
    GameTooltip:Show()
end

-- The one mouse-state writer. Edit mode gets the full mouse (dragging needs
-- clicks); otherwise Store.MouseFor's tiers set hover and click-through.
-- EnableMouse(true) re-enables both channels, so the split always follows it.
function Factory.ApplyMouse(f, editMode, rec)
    if editMode then
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(true) end
        if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(true) end
        f._adTipsOn = nil   -- edit hover falls back to the global setting
        f._adCondBlocked = false
        return
    end
    -- An inert or fully faded record (itself, its group or layout) must not
    -- catch the mouse; the conditions pass re-runs this when that flips.
    local blocked = NS.Conditions ~= nil and rec ~= nil
        and NS.Conditions.MouseBlocked(rec)
    f._adCondBlocked = blocked
    if blocked then
        f._adTipsOn = false
        f:EnableMouse(false)
        return
    end
    local tips, thru
    if rec and Store.MouseFor then
        tips, thru = Store.MouseFor(rec)
    else
        tips = Store.GetSetting("showTooltips") ~= false
        thru = Store.GetSetting("clickThrough") ~= false
    end
    -- Edit-only tooltips: no hover in play, so click-through passes the mouse.
    if Store.GetSetting("tooltipsEditOnly") == true then tips = false end
    f._adTipsOn = tips
    if not tips and thru then
        f:EnableMouse(false)   -- nothing wants the mouse: fully transparent
        return
    end
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(not thru) end
    if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(tips) end
end

function Factory.SetEditMode(f, rec, on)
    f._adRecId = rec.id
    if on and Factory.EditChipsOn("icon") then
        local b = EnsureEditChip(f)
        b:SetFrameLevel(f:GetFrameLevel() + 100)
        b:Show()
    elseif f._adEditBtn then
        f._adEditBtn:Hide()
    end
end

-- /adstate <icon name>: prints the live alpha ladder and every state input of
-- each icon with that name, only in answer to the typed command. Values go
-- through plain(): a secret would throw inside format, so it prints "secret".
local function plain(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "number" then return ("%.2f"):format(v) end
    return tostring(v)
end
SLASH_ADSTATE1 = "/adstate"
SlashCmdList.ADSTATE = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if msg == "" then
        print("|cff3fc9f2Arc Auras state:|r /adstate <icon name> - print that icon's live alpha ladder")
        return
    end
    local n = 0
    for id, f in pairs(frames) do
        local rec = Store.Get(id)
        if rec and rec.name and rec.name:lower() == msg then
            n = n + 1
            local R = function(s, k) return plain(Store.Resolve(rec, s, k)) end
            local bh = f._adBorderHost
            print(("|cff3fc9f2%s|r [%s id %s] shown=%s frame a=%s lvl=%s | art a=%s shown=%s | border a=%s lvl=%s | texts a=%s lvl=%s"):format(
                rec.name, tostring(rec.kind), tostring(id), plain(f:IsShown()), plain(f:GetAlpha()), plain(f:GetFrameLevel()),
                plain(f.icon:GetAlpha()), plain(f.icon:IsShown()),
                bh and plain(bh:GetAlpha()) or "none", bh and plain(bh:GetFrameLevel()) or "-",
                plain(f.textHost:GetAlpha()), plain(f.textHost:GetFrameLevel())))
            print(("  state a=%s onCd=%s desat=%s usability=%s proc=%s | ready=%s cd=%s unusable=%s res=%s keepBright=%s procOverride=%s usableOverride=%s"):format(
                plain(f._adStateAlpha), plain(f._adOnCooldown), plain(f._adDesatState),
                plain(f._adUsability), plain(f._adProcOn),
                R("states", "readyAlpha"), R("states", "cooldownAlpha"), R("states", "unusableAlpha"), R("states", "resourceAlpha"),
                R("appearance", "keepBright"), R("states", "procOverride"), R("states", "usableOverride")))
        end
    end
    if n == 0 then print("  no live icon with that name") end
end
