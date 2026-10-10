-- Arc Auras, all rights reserved: do not copy or adapt this code into another addon without permission.
-- Icon factory: builds and styles every icon frame, the aura engine's buttons
-- included. Drivers never style anything; they report state (Factory.SetState)
-- or feed the swipe (frame.cooldown). ApplyStyle is the only style writer.
local ADDON, NS = ...
local Store = NS.Store

local Factory = {}
NS.Factory = Factory

local QUESTION_MARK = 134400
-- an empty totem slot's art, the totem glyph (retail's file)
Factory.TOTEM_GLYPH = 310731
-- the custom texts' slots; a special icon adds its own three
Factory.LABELS = { "", "2", "3" }
Factory.SPECIAL_LABELS = { "", "2", "3", "4", "5", "6" }
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
-- each spell slot by the one matcher's keys (ID, base spell and name, as
-- Forever ranks are separate IDs sharing a name). The swap is rank-specific,
-- so the rank the icon reads is tried first. A secret read keeps the old map
-- and retries after combat.
local ART_BARS = { 1, 61, 49, 25, 37, 145, 157, 169, 13, 73, 85, 97, 109, 121, 133 }
local artSlots, artDirty, artRetry = {}, true, false
-- [sid] = its slot, or false for none; kept until the map is rebuilt
local slotOf = {}

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
                -- filed under the forms the one matcher compares (Store.SeenKeys)
                for _, k in ipairs(Store.SeenKeys(id, NS.IsForever == true)) do remember(k, slot) end
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

-- `sid` is already the spell the icon reads (Store.RecordSpellID); its slot
-- is found by the one matcher's keys, the ID first, then its base form, then
-- on ranked realms its name. Hits and misses are kept until the map is
-- rebuilt; misses also go at combat's end, as a read in combat may have been
-- secret. The art pass runs every frame of combat, so the keys reuse a table.
local artKeys = {}
local function ArtSlotFor(sid)
    if artDirty then ArtRebuild() end
    local hit = slotOf[sid]
    if hit ~= nil then return hit or nil end
    wipe(artKeys)
    local slot
    for _, k in ipairs(Store.WantKeys(sid, sid, NS.IsForever == true, artKeys)) do
        slot = artSlots[k]
        if slot ~= nil then break end
    end
    slotOf[sid] = slot or false
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
            for k, v in pairs(slotOf) do
                if v == false then slotOf[k] = nil end
            end
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
        local tex = C_Spell.GetSpellTexture(ov) -- raw-id: an art pick, not a tracked spell
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

-- The Cooldown Manager's own picture for each item category it lists
-- (CooldownViewerItemData.lua spellCategoryMetadataLookup).
Factory.CATEGORY_ART = {
    [4] = "Interface/ICONS/INV_POTION_114",
    [30] = "Interface/ICONS/INV_POTION_54",
    [1711] = "Interface/ICONS/Warlock_ Healthstone",
    [2566] = "Interface/ICONS/Warlock_ Bloodstone",
}

-- A spell icon's own art: the spell its driver reads (Auto rank's rank, then
-- the override unless the icon pins the base spell). GetSpellTexture gives
-- (icon, originalIcon); on Forever neither moves for a toggle, so active art
-- comes from the action bar.
local function SpellArt(d, activeArt)
    local sid = Store.RecordSpellID(d)
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
    elseif kind == "aura" or kind == "groupbuff" then
        -- the first typed aura's art (the aura entry keeps it first)
        local id = Store.TrackedAuraIDs(d)[1]
        local tex = id and C_Spell.GetSpellTexture(id)
        return tex or QUESTION_MARK
    elseif kind == "timer" then
        local tex = d.spellID and C_Spell.GetSpellTexture(d.spellID) -- raw-id: the custom icon's art pick
        return tex or QUESTION_MARK
    elseif kind == "trinket" then
        local tex = d.slotID and GetInventoryItemTexture("player", d.slotID)
        return tex or QUESTION_MARK
    elseif kind == "item" then
        -- an item by its category wears the category's picture
        local cat = d.category and Factory.CATEGORY_ART[d.category]
        if cat then return cat end
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
        -- haveTotem is a secret boolean, so it is never tested: the feed's
        -- duration shadow says whether the slot is live (nil before its first
        -- feed). The icon is only painted, and SetTexture takes a secret. An
        -- empty slot's own art is blank: a totem followed by spell shows its
        -- spell's art, any other the totem glyph (retail; Forever lacks it).
        local slot = d.slot or 1
        if NS.DriverTotem then slot = NS.DriverTotem.SlotFor(rec) end
        local DC = NS.DriverCooldown
        local live = DC and DC.TotemLive and DC.TotemLive(rec)
        if live ~= false and slot and GetTotemInfo then
            local _, _, _, _, icon = GetTotemInfo(slot)
            if icon then return icon end
        end
        local sid = Store.RecordSpellID(d)
        local tex = sid and C_Spell.GetSpellTexture(sid)
        return tex or ((NS.IsForever ~= true) and Factory.TOTEM_GLYPH or QUESTION_MARK)
    elseif kind == "enchant" then
        -- the enchant's own art while it is on, else the weapon's
        local E = NS.DriverEnchant
        local e = E and E.Read(rec)
        if e and e.icon then return e.icon end
        return GetInventoryItemTexture("player", E and E.InvSlot(rec) or 16)
            or (E and E.SlotArt(rec)) or QUESTION_MARK
    elseif kind == "special" then
        -- the tracker's own art (Core\AD_SpecialIcon.lua; nil without the hub)
        return NS.SpecialIcon and NS.SpecialIcon.Texture(rec) or QUESTION_MARK
    elseif kind == "stance" then
        -- the stance bar's own art for the stance it shows (Drivers\AD_DriverStance.lua)
        return NS.DriverStance and NS.DriverStance.Texture(rec) or QUESTION_MARK
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
-- the stance driver repaints its art through it on every stance change
Factory.PaintArt = PaintArt

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

-- Bands in percent of the duration: a bound copy of the countdown (the Pct
-- functions below StyleCountdownText).
local Pct = {}

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
    -- Bands in percent: the bound copy follows every duration this cooldown
    -- takes; only an icon with them holds a binding.
    if hooksecurefunc then
        hooksecurefunc(f.cooldown, "SetCooldownFromDurationObject", function(_, d)
            if f._adPctBind and d then f._adPctBind:SetDuration(d) end
        end)
        hooksecurefunc(f.cooldown, "SetCooldown", function(_, start, dur) Pct.Plain(f, start, dur) end)
        hooksecurefunc(f.cooldown, "Clear", function() Pct.Plain(f, 0, 0) end)
    end

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
-- roundMode: "up" | "down" | nil (the Settings choice). below =
-- seconds from which the text prints a blank (0 = always shown).
function Factory.GetCountdownFormatter(decTo, bands, abbrev, roundMode, below)
    decTo = tonumber(decTo) or 0
    if decTo > 60 then decTo = 60 end
    abbrev = tonumber(abbrev) or 0
    if abbrev <= 60 then abbrev = 0 end
    below = tonumber(below) or 0
    if below < 0 then below = 0 end
    local nBands = (type(bands) == "table") and #bands or 0
    if decTo <= 0 and nBands == 0 and abbrev == 0 and below == 0 then return nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local CN = GetLocale and GetLocale() == "zhCN"
    if CN then decTo = 0 end   -- decimal refreshes can crash the zhCN client
    local mode = roundMode or Factory.TimerRounding()
    local parts = { tostring(decTo), tostring(abbrev), mode, tostring(below) }
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
    if below > 0 then edgeSet[below] = true end
    if decTo > 0 and decTo < 60 then edgeSet[decTo] = true end
    if abbrev > 60 and abbrev < 3600 then edgeSet[abbrev] = true end
    for _, b in ipairs(sorted) do
        if b.t > 0 and b.t < 3600 then edgeSet[b.t] = true end
    end
    local edges = {}
    for v in pairs(edgeSet) do
        -- nothing above the Show under line needs a rule of its own
        if below == 0 or v <= below then edges[#edges + 1] = v end
    end
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
        if below > 0 and lo >= below then
            -- a space keeps the font string's height while it waits
            fmt, esc = " ", nil
        elseif lo >= 3600 then
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
function Factory.TimerFormatter(decTo, bands, abbrev, stock, roundMode, below)
    local fmt = Factory.GetCountdownFormatter(decTo, bands, abbrev, roundMode, below)
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

-- A countdown that prints nothing, for a switched-off duration text; nil
-- where the client has no formatters.
local function BlankTimerFormatter()
    if fmtCache.blank ~= nil then return fmtCache.blank or nil end
    local f = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and C_StringUtil.CreateNumericRuleFormatter()
    if f then f:AddBreakpoint({ threshold = 0, format = "" }) end
    fmtCache.blank = f or false
    return f
end

-- The icon's countdown formatter and signature (holder and aura button alike).
local function CountdownFormatterFor(rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    -- switched off: nothing to print, whatever shows the numbers
    if R("text", "durationText") == false then return BlankTimerFormatter(), "off" end
    local decTo, bands = 0, nil
    local abbrev = R("text", "durationAbbrev") or 0
    if R("text", "durationDecimals") == true then
        decTo = R("text", "durationDecimalThreshold") or 10
    end
    -- bands in percent colour a bound copy instead (Pct)
    if R("text", "durationColorBands") == true and R("text", "durationBandsPercent") ~= true then
        bands = {}
        -- only the bands in play ("+ Add band"); 0 seconds is still off
        local count = math.max(1, math.min(5, math.floor(tonumber(R("text", "durBandCount")) or 1)))
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
    -- Rounding is in the signature, so changing it re-pushes the formatter.
    local mode = Factory.IconRounding(rec)
    local below = R("text", "durationShowBelow") or 0
    local sig = tostring(decTo) .. "/" .. tostring(abbrev) .. "/" .. mode .. "/" .. tostring(below)
    if bands then
        for _, b in ipairs(bands) do
            sig = sig .. "|" .. b.t .. ":"
                .. (b.c[1] or 1) .. "," .. (b.c[2] or 1) .. "," .. (b.c[3] or 1)
        end
    end
    return Factory.TimerFormatter(decTo, bands, abbrev, nil, mode, below), sig
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
        local count = math.max(1, math.min(6, math.floor(tonumber(R("text", "stkBandCount")) or 1)))
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
        Factory.StopRangeGlow(f)
        Factory.StopRechargeGlow(f)
        f._adStateSig = nil   -- the lanes just stopped: the next feed repaints
        if NS.DriverWarn then NS.DriverWarn.Drop(f) end
        if NS.DriverToggle then NS.DriverToggle.Drop(f) end
        if NS.DriverAssist then NS.DriverAssist.Drop(f) end
        -- pinned texts come home, their carriers hidden with the icon
        if NS.TextAnchor then NS.TextAnchor.Release(f) end
        f._adPureGCD = nil   -- pooled frames must not carry GCD presentation
        f._adNoWeapon = nil
        Factory.SetTimed(f, nil)
        f._adTimedDur = nil
        f._adPureWand = nil
        f._adRecharging = nil
        f._adTipsOn = nil
        f._adProcLit = nil   -- nor the game's proc on the spell it showed
        f:Hide()
        f:ClearAllPoints()
    end
end

-- State dim: it covers the whole icon but never uses f:SetAlpha, as the
-- frame's alpha belongs to ApplyFrameAlpha and child alpha multiplies (texts
-- could never stay bright), nor f.cooldown:SetAlpha, whose frame holds the
-- countdown fontstring. The swipe and edge dim by their colour instead.
-- On cooldown's opacity with N seconds left (states.cooldownAlphaTimed): the
-- cooldown's duration object maps its time left through a step curve, so the
-- answer (secret in combat) only ever reaches the setters. One curve per
-- seconds / late / before triple.
local stepCurves = {}
local function StepCurve(sec, late, before)
    local key = sec .. "/" .. late .. "/" .. before
    local c = stepCurves[key]
    if c == nil then
        c = C_CurveUtil.CreateCurve()
        if c.SetType and Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
        c:AddPoint(0, late)
        c:AddPoint(sec, late)
        c:AddPoint(sec + 0.001, before)
        c:AddPoint(1e6, before)
        stepCurves[key] = c
    end
    return c
end

-- The value for now: late with sec or less left, else before (plain when they match).
local function TimedValue(f, late, before)
    local T, dur = f._adTimed, f._adTimedDur
    if late == before or not (T and dur) then return late end
    return dur:EvaluateRemainingDuration(StepCurve(T.sec, late, before))
end

local function ApplySwipeAlpha(f)
    -- The shown alpha (with the editing floor), not the raw state value.
    local a = f._adShownAlpha or f._adStateAlpha or 1
    local T = f._adTimed
    local function A(own)
        if T then return TimedValue(f, own * T.late, own * T.before) end
        return own * a
    end
    local sc = f._adSwipeColor
    -- a GCD or wand spin draws in its own colour
    if f._adPureGCD then sc = (f._adPureWand and f._adWandSwipeColor or f._adGcdSwipeColor) or sc end
    if sc then f.cooldown:SetSwipeColor(sc[1], sc[2], sc[3], A(sc[4] or 0.8)) end
    local ec = f._adEdgeColor
    if ec and f.cooldown.SetEdgeColor then
        f.cooldown:SetEdgeColor(ec[1], ec[2], ec[3], A(ec[4] or 1))
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
-- a skin's pictures on the art's own frame (Factory.SkinLayers' back side)
local SKIN_BACK_KEYS = { "_adSkinBackdrop", "_adSkinShadow", "_adSkinNormal", "_adSkinGloss" }
-- and on its top frame; each picture dims itself, as the art does
local function DimSkin(f, a)
    for _, host in ipairs({ f.icon and f.icon:GetParent(), f._adSkinTop }) do
        for _, k in ipairs(SKIN_BACK_KEYS) do
            if host[k] then host[k]:SetAlpha(a) end
        end
    end
end

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
    DimSkin(f, a)
    -- A fully hidden icon hides its texts too, whatever preserveText says.
    local ta = (a > 0 and preserveText) and 1 or a
    if f.textHost then f.textHost:SetAlpha(ta) end
    if f._adLabelHost then f._adLabelHost:SetAlpha(f._adLabelsBright and (a > 0 and 1 or 0) or ta) end
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

-- A text's colour with the timed dim, as PaintText does with a plain one.
local function TimedText(f, fs, T)
    local c = fs._adTextRGBA
    if c then
        local k = c[4] or 1
        fs:SetTextColor(c[1], c[2], c[3], TimedValue(f, k * T.tLate, k * T.tBefore))
    else
        fs:SetAlpha(TimedValue(f, T.tLate, T.tBefore))
    end
end

-- The timed look on everything ApplyStateAlpha dims; the tint SetState
-- picked rides the art's alpha.
local function TimedPaint(f)
    local T = f._adTimed
    if not (T and f._adTimedDur) then return end
    local a = TimedValue(f, T.late, T.before)
    local tc = T.tint or { 1, 1, 1 }
    f.icon:SetVertexColor(tc[1], tc[2], tc[3], a)
    if f._adShadow then f._adShadow:SetAlpha(a) end
    if f._adBorderHost then f._adBorderHost:SetAlpha(a) end
    DimSkin(f, a)
    if f._adMissGlow then f._adMissGlow:SetAlpha(a) end
    ApplySwipeAlpha(f)
    local ta = TimedValue(f, T.tLate, T.tBefore)
    if f.textHost then f.textHost:SetAlpha(ta) end
    if f._adLabelHost then
        f._adLabelHost:SetAlpha(f._adLabelsBright and TimedValue(f, T.late > 0 and 1 or 0, T.before > 0 and 1 or 0) or ta)
    end
    if f._adMissClip then f._adMissClip:SetAlpha(ta) end
    if f._adLowText then f._adLowText:SetAlpha(ta) end
    if f.stackText then TimedText(f, f.stackText, T) end
    if f.cooldown.GetCountdownFontString then
        local cfs = f.cooldown:GetCountdownFontString()
        if cfs then TimedText(f, cfs, T) end
    end
end
Factory.TimedPaint = TimedPaint

-- The curve answers for one moment, so a frame on a timed look is repainted
-- while it is on (20 a second); the driver's next state write ends it. A
-- preview frame out of sight drops out, as no state write may follow.
local timedOn, timedAcc = {}, 0
local timedTick = CreateFrame("Frame")
local function TimedOnUpdate(_, el)
    timedAcc = timedAcc + el
    if timedAcc < 0.05 then return end
    timedAcc = 0
    for f in pairs(timedOn) do
        if f._adRecId == nil and not f:IsVisible() then
            timedOn[f] = nil
            f._adTimed = nil
        else
            TimedPaint(f)
        end
    end
    if next(timedOn) == nil then timedTick:SetScript("OnUpdate", nil) end
end

local function SetTimed(f, T)
    f._adTimed = T
    if T then
        timedOn[f] = true
        if not timedTick:GetScript("OnUpdate") then
            timedAcc = 0
            timedTick:SetScript("OnUpdate", TimedOnUpdate)
        end
    elseif timedOn[f] then
        timedOn[f] = nil
        if next(timedOn) == nil then timedTick:SetScript("OnUpdate", nil) end
    end
end
Factory.SetTimed = SetTimed

-- Shapes an icon can be cut to (appearance.iconMask, or its group's
-- arrangement.iconMask), each three pictures in Textures\Shapes: its
-- silhouette (the art's mask, a shaped swipe, a border ring's outside), its
-- hole (white outside the shape: the ring's inside edge) and its halo (a soft
-- rim outside it: shaped glows and shadow), the shape in the halo's middle
-- 1 / SHAPE_HALO.
Factory.SHAPES = { rounded = true, circle = true, diamond = true, hexagon = true }
Factory.SHAPE_HALO = 1.6
-- shapes whose swipe keeps its edge line: it runs round a circle the size of
-- the icon, which a diamond's or hexagon's sides cut inside of
Factory.SHAPE_EDGE = { rounded = true, circle = true }
-- a ring's inset per unit of thickness, so a slanted side reads as thick as a straight one
Factory.SHAPE_RING = { rounded = 1, circle = 1, diamond = 1.41, hexagon = 1 }
local SHAPE_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Shapes\\AD_Shape"

function Factory.ShapeFile(key, part)
    return SHAPE_DIR .. part .. "_" .. key
end

-- The Masque skin plan a record wears (Core\AD_Skins.lua), or nil.
function Factory.SkinPlan(rec)
    local S = NS.Skins
    return (S ~= nil and S.PlanFor ~= nil) and S.PlanFor(rec) or nil
end

-- The icon's shape key, or nil for square: its own, else its group's. A
-- Masque skin draws its own shape, so ours stands aside under one.
function Factory.MaskOf(rec)
    if not rec then return nil end
    if Factory.SkinPlan(rec) then return nil end
    local k = Store.Resolve(rec, "appearance", "iconMask")
    if Factory.SHAPES[k] then return k end
    local g = rec.groupId and Store.Get(rec.groupId)
    k = g and Store.Resolve(g, "arrangement", "iconMask")
    return Factory.SHAPES[k] and k or nil
end

-- Cuts `tex` to the shape over `box` (default its own rect); nil uncuts it.
-- The mask is made on the texture's frame: a mask clips only its own frame's
-- textures.
local function ShapeTex(tex, key, box)
    if not tex then return end
    local m = tex._adShapeM
    if not key then
        if m and tex._adShapeOn then
            tex:RemoveMaskTexture(m)
            tex._adShapeOn = nil
        end
        return
    end
    if not m then
        m = tex:GetParent():CreateMaskTexture()
        tex._adShapeM = m
    end
    if m._adKey ~= key then
        m:SetTexture(Factory.ShapeFile(key, "Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m._adKey = key
    end
    m:ClearAllPoints()
    m:SetAllPoints(box or tex)
    if not tex._adShapeOn then
        tex:AddMaskTexture(m)
        tex._adShapeOn = true
    end
end
Factory.ShapeTex = ShapeTex

-- Masque skins, painted by us (no frame of ours is handed to Masque): sizes
-- are the skin's units of a 36px button times the box and the group's scale,
-- offsets as the skin gives them (Masque's own rule); both snap to whole pixels.
local MASQUE_TEX = "Interface\\AddOns\\Masque\\Textures\\"
local SKIN_SWIPE = MASQUE_TEX .. "Square\\Mask"
local SKIN_SWIPE_ROUND = MASQUE_TEX .. "Circle\\Mask"
local SKIN_BACKDROP = MASQUE_TEX .. "Backdrop\\Action"
local SKIN_NORMAL = "Interface\\Buttons\\UI-Quickslot2"
local SKIN_WRAP = "CLAMPTOBLACKADDITIVE"
-- each layer's place in Masque's stack when the skin names none, and which
-- side of the picture (Masque's sits at BACKGROUND 0) a stack place puts it
Factory.SKIN_LAYERS = { { "Backdrop", "BACKGROUND", -1 }, { "Shadow", "ARTWORK", -1 },
    { "Normal", "ARTWORK", 0 }, { "Gloss", "OVERLAY", 1 } }
local DRAW_RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local SKIN_ICON_RANK = 16

local skinAtlas = {}
local function SkinAtlasOK(name)
    local v = skinAtlas[name]
    if v == nil then
        v = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
        skinAtlas[name] = v
    end
    return v
end

-- whole pixels on `frame`'s grid; a secret scale falls back to UIParent's
local function SkinSnap(frame, v, floor)
    if not (PixelUtil and PixelUtil.GetNearestPixelSize) then return v end
    local es = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if es == nil or (issecretvalue and issecretvalue(es)) then es = UIParent:GetEffectiveScale() end
    return PixelUtil.GetNearestPixelSize(v, es, floor)
end

local function SkinCoords(c)
    if type(c) == "table" then return c[1] or 0, c[2] or 1, c[3] or 0, c[4] or 1 end
    return 0, 1, 0, 1
end

-- A region's size and place from a skin entry, on `anchor` (a frame, w x h,
-- whose pixel grid it snaps to); an entry anchored to "Icon" sits on `art`,
-- and `on` places it on another region (a mask on its picture).
local function SkinPlace(region, e, plan, anchor, art, w, h, on)
    local to = on or (e and e.Anchor == "Icon" and art) or anchor
    region:ClearAllPoints()
    if e and e.SetAllPoints then
        region:SetAllPoints(to)
        return
    end
    local k = (plan.scale or 1) / 36
    if not (e and e.Atlas and e.UseAtlasSize) then
        region:SetSize(SkinSnap(anchor, ((e and e.Width) or 36) * (w or 36) * k, 1),
            SkinSnap(anchor, ((e and e.Height) or 36) * (h or 36) * k, 1))
    end
    region:SetPoint((e and e.Point) or "CENTER", to, (e and e.RelPoint) or "CENTER",
        SkinSnap(anchor, (e and e.OffsetX) or 0, 0), SkinSnap(anchor, (e and e.OffsetY) or 0, 0))
end
Factory.SkinPlace = SkinPlace

-- The picture's box in a skin on a w x h button.
local function SkinBox(plan, w, h)
    local e = plan.icon
    if e.SetAllPoints then return w, h end
    local k = (plan.scale or 1) / 36
    return (e.Width or 36) * w * k, (e.Height or 36) * h * k
end

-- The skin's crop; a box that is not square crops further at the icon's part
-- (its crop to shape, else a hand aspect ratio), so the picture never stretches.
function Factory.SkinTexCoords(rec, plan, bw, bh)
    local L, Rt, T, B = SkinCoords(plan.icon.TexCoords)
    local target
    if Factory.CropsToShape(rec) and type(bw) == "number" and type(bh) == "number" and bw > 0 and bh > 0 then
        target = bw / bh
    else
        local ar = Store.Resolve(rec, "appearance", "aspectRatio") or 1
        if ar ~= 1 and ar > 0 then target = ar end
    end
    local ww, wh = Rt - L, B - T
    if target and ww > 0 and wh > 0 then
        local focus = Factory.CropFocus(rec)
        if ww / wh > target then
            local keep = wh * target
            L = L + ww * Factory.FocusStart(focus, keep / ww)
            Rt = L + keep
        elseif ww / wh < target then
            local keep = ww / target
            T = T + wh * Factory.FocusStart(focus, keep / wh)
            B = T + keep
        end
    end
    return L, Rt, T, B
end

-- The skin's mask on the picture: the icon entry's own, else the button's
-- when the entry uses it. Made on the picture's frame; nil plan takes it off.
local function SkinMask(tex, plan, owner, w, h)
    local ie = plan and plan.icon
    local def, rel
    if ie and ie.Mask then
        def, rel = ie.Mask, tex
    elseif ie and ie.UseMask and plan.mask then
        def, rel = plan.mask, owner
    end
    local m = tex._adSkinM
    -- an atlas this client lacks would blank the picture: its file, else no mask
    if type(def) == "table" and not ((def.Atlas and SkinAtlasOK(def.Atlas)) or def.Texture) then def = nil end
    if not def then
        if m and tex._adSkinMOn then
            tex:RemoveMaskTexture(m)
            tex._adSkinMOn = nil
        end
        return
    end
    if not m then
        m = tex:GetParent():CreateMaskTexture()
        tex._adSkinM = m
    end
    if type(def) == "string" then
        m:SetTexture(def, SKIN_WRAP, SKIN_WRAP)
        m:ClearAllPoints()
        m:SetAllPoints(tex)
    else
        if def.Atlas and SkinAtlasOK(def.Atlas) then
            m:SetAtlas(def.Atlas, def.UseAtlasSize)
        else
            m:SetTexture(def.Texture, def.WrapH or SKIN_WRAP, def.WrapV or SKIN_WRAP)
        end
        -- a picture's own mask sits on the picture, the button's on the button
        SkinPlace(m, def, plan, owner, tex, w, h, rel)
    end
    if not tex._adSkinMOn then
        tex:AddMaskTexture(m)
        tex._adSkinMOn = true
    end
end

-- A piece drawn over a holder's art box (the checkmark, the press look, a
-- warning tint) takes the skin's mask the art wears (ApplyStyle keeps the plan).
function Factory.SkinMaskOver(tex, f)
    if not (tex and f) then return end
    local w, h = f:GetSize()
    if type(w) ~= "number" or type(h) ~= "number" or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then
        w, h = 36, 36
    end
    SkinMask(tex, f._adSkinPlan, f, w, h)
end

-- The skin's picture on `owner` (the frame it is on, w x h): its box, crop
-- and mask, in place of our padding, zoom and shape. No plan: its mask off
-- (the caller places the picture its own way).
function Factory.SkinArt(tex, rec, plan, owner, w, h)
    if not tex then return end
    if not plan then
        SkinMask(tex, nil)
        return
    end
    w, h = w or 36, h or 36
    SkinPlace(tex, plan.icon, plan, owner, nil, w, h)
    tex:SetTexCoord(Factory.SkinTexCoords(rec, plan, SkinBox(plan, w, h)))
    SkinMask(tex, plan, owner, w, h)
end

-- One layer's picture, colour and blend.
local function SkinPaint(t, e, color, defTex)
    local c = color or e.Color
    if e.UseColor then
        t:SetTexture(nil)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetColorTexture(c and c[1] or 0, c and c[2] or 0, c and c[3] or 0, c and c[4] or 0.5)
    else
        if e.Atlas and SkinAtlasOK(e.Atlas) then
            t:SetAtlas(e.Atlas, e.UseAtlasSize)
        else
            t:SetTexture(e.Texture or defTex)
            t:SetTexCoord(SkinCoords(e.TexCoords))
        end
        t:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1)
    end
    t:SetBlendMode(e.BlendMode or "BLEND")
end

-- The skin's layers round the picture: the ones its stack puts under the
-- picture on `back` (the picture's own frame), the rest on `top` (a frame over
-- it), each side in the skin's order. No plan or hide: all hidden. alpha: each
-- picture's own (a host that dims as a whole passes 1). Returns the pictures shown.
function Factory.SkinLayers(plan, back, top, anchor, art, w, h, alpha, hide)
    local shown = {}
    local sides = { back = {}, top = {} }
    if plan and not hide then
        for _, L in ipairs(Factory.SKIN_LAYERS) do
            local name = L[1]
            local e = plan[name:lower()]
            if e then
                local rank = (DRAW_RANK[e.DrawLayer or L[2]] or 3) * 16 + (e.DrawLevel or L[3])
                local side = (name == "Backdrop" or rank < SKIN_ICON_RANK) and "back" or "top"
                local list = sides[side]
                list[#list + 1] = { name = name, e = e, rank = rank }
            end
        end
    end
    -- one pass per side; a host's pictures the skin does not draw now hide
    -- after both (the two sides may share a frame)
    local on = {}
    local function Side(host, list, layer, base)
        table.sort(list, function(x, y) return x.rank < y.rank end)
        for i, it in ipairs(list) do
            local key = "_adSkin" .. it.name
            local t = host[key]
            if not t then
                t = host:CreateTexture(nil, layer, nil, 0)
                host[key] = t
            end
            local def = (it.name == "Backdrop" and SKIN_BACKDROP) or (it.name == "Normal" and SKIN_NORMAL) or nil
            SkinPaint(t, it.e, plan.colors[it.name], def)
            t:SetDrawLayer(layer, base + i - 1)
            SkinPlace(t, it.e, plan, anchor, art, w, h)
            t:SetAlpha(alpha or 1)
            t:Show()
            on[t] = true
            shown[#shown + 1] = t
        end
    end
    -- under the picture as deep as the back allows; over it under the texts
    Side(back, sides.back, "BACKGROUND", -1 - math.max(0, #sides.back - 1))
    Side(top, sides.top, "OVERLAY", 0)
    for _, host in ipairs({ back, top }) do
        for _, L in ipairs(Factory.SKIN_LAYERS) do
            local t = host["_adSkin" .. L[1]]
            if t and not on[t] then t:Hide() end
        end
    end
    return shown
end

-- The skin's shape as one of our glow outlines, or nil (a square skin keeps
-- the picked glow).
function Factory.SkinGlowShape(rec)
    local plan = Factory.SkinPlan(rec)
    local sh = plan and plan.shape
    if sh == "Circle" then return "circle" end
    if sh == "Hexagon" or sh == "Hexagon-Rotated" then return "hexagon" end
    return nil
end

-- The swipe's picture: a Masque skin's (plan), a shape's silhouette (key),
-- else back to the flat white one Lua-made cooldowns need; a round picture
-- runs a round edge (drawn only on SHAPE_EDGE shapes, where the draw flags
-- are set).
local function ShapeSwipe(cd, key, plan)
    if not cd then return end
    local tex, round
    if plan then
        tex = plan.cooldown.Texture or (plan.round and SKIN_SWIPE_ROUND or SKIN_SWIPE)
        round = plan.round == true
    elseif key then
        tex, round = Factory.ShapeFile(key, "Mask"), true
    end
    if tex then
        if cd._adSwipeTex ~= tex then
            cd:SetSwipeTexture(tex, 1, 1, 1, 1)
            cd._adSwipeTex = tex
        end
        if cd._adRoundEdge ~= round then
            if cd.SetUseCircularEdge then cd:SetUseCircularEdge(round) end
            cd._adRoundEdge = round
        end
    elseif cd._adSwipeTex then
        cd:SetSwipeTexture(WHITE, 1, 1, 1, 1)
        cd._adSwipeTex = nil
        if cd.SetUseCircularEdge then cd:SetUseCircularEdge(false) end
        cd._adRoundEdge = nil
    end
end
Factory.ShapeSwipe = ShapeSwipe

-- A shaped border's ring on the strips' frame: the silhouette from the offset
-- line, its inside cut by the hole mask one thickness in. Geometry only; the
-- caller colours it.
local function ShapeRing(edges, anchor, key, off, th)
    local ring = edges._adRing
    if not ring then
        local host = edges.top:GetParent()
        local layer, sub = edges.top:GetDrawLayer()
        ring = host:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
        ring._adHole = host:CreateMaskTexture()
        ring:AddMaskTexture(ring._adHole)
        edges._adRing = ring
    end
    if ring._adKey ~= key then
        ring:SetTexture(Factory.ShapeFile(key, "Mask"))
        ring._adHole:SetTexture(Factory.ShapeFile(key, "Hole"), "CLAMPTOWHITE", "CLAMPTOWHITE")
        ring._adKey = key
    end
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", anchor, "TOPLEFT", off, -off)
    ring:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -off, off)
    local inner = off + th * (Factory.SHAPE_RING[key] or 1)
    local hole = ring._adHole
    hole:ClearAllPoints()
    hole:SetPoint("TOPLEFT", anchor, "TOPLEFT", inner, -inner)
    hole:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inner, inner)
    return ring
end

-- Border geometry: four strips on `edges` around `anchor`, shared by the
-- holder and the live aura button so an aura icon's two borders match. They
-- grow inward from the offset line (negative = outside); thickness snaps to
-- whole pixels with a 1px floor, the offset with none. A secret scale would
-- throw inside PixelUtil, so UIParent's stands in. A scaled preview snaps on
-- its _adPxRef's grid, as the live icon does, floored at one own pixel.
local function PaintBorderEdges(edges, anchor, rec, alpha, geometryOnly, grey)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    local c = Factory.BorderColor(rec, grey)
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
    -- a Masque skin's border replaces ours: the caller paints its layers
    if not geometryOnly and Factory.SkinPlan(rec) then
        for _, k in ipairs(BORDER_KEYS) do edges[k]:Hide() end
        if edges._adRing then edges._adRing:Hide() end
        return 0
    end
    -- a shaped icon's border is one ring of the same reach in the strips' place
    local key = Factory.MaskOf(rec)
    if key then
        local ring = ShapeRing(edges, anchor, key, off, th)
        if geometryOnly then return off + th end
        local a = (c[4] or 1) * (alpha or 1)
        for _, k in ipairs(BORDER_KEYS) do edges[k]:Hide() end
        ring:SetVertexColor(c[1], c[2], c[3], a)
        ring:Show()
        return off + th
    end
    if edges._adRing then edges._adRing:Hide() end
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

-- The border's colour: its own or the player's class colour (the alpha its
-- own), turned grey while the art is (grey) when it follows the art.
function Factory.BorderColor(rec, grey)
    local c = Store.Resolve(rec, "appearance", "borderColor") or { 0, 0, 0, 1 }
    if Store.Resolve(rec, "appearance", "borderClassColor") == true and UnitClass then
        local _, tag = UnitClass("player")
        local cc = tag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[tag]
        if cc then c = { cc.r, cc.g, cc.b, c[4] or 1 } end
    end
    if grey and Store.Resolve(rec, "appearance", "borderFollowsGrey") == true then
        local l = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
        c = { l, l, l, c[4] or 1 }
    end
    return c
end

-- A border that follows the art: repainted to the art's grey (the strips'
-- geometry stays). f.borderEdges: the holder's own.
function Factory.BorderGrey(f, rec, grey)
    grey = grey and true or false
    if (f._adBorderGrey or false) == grey then return end
    f._adBorderGrey = grey
    local edges = f.borderEdges
    if not (edges and Store.Resolve(rec, "appearance", "borderFollowsGrey") == true) then return end
    local c = Factory.BorderColor(rec, grey)
    for _, k in ipairs(BORDER_KEYS) do edges[k]:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    if edges._adRing then edges._adRing:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

-- The live aura button's own border, on the engine button so it shows and
-- hides with the aura and never carries the missing alpha (the button has no
-- border; CustomAuraButtonSharedMixin exposes only widget slots). OVERLAY 6
-- on its edge layer (BUTTON_STACK.edge): above the swipe, under the button's
-- glows and texts. Accessible passes only.
local function ApplyAuraButtonBorder(b, rec, show, alpha)
    local edges = b._adBtnEdges
    if show then
        if not edges then
            local host = b._adEdgeHost or b.TextOverlay or b
            edges = {}
            for _, k in ipairs(BORDER_KEYS) do
                local t = host:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetColorTexture(1, 1, 1, 1)
                edges[k] = t
            end
            b._adBtnEdges = edges
        end
        PaintBorderEdges(edges, b, rec, alpha, nil, Store.Resolve(rec, "auraActive", "activeDesaturate") == true)
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
    -- they come off through NS.RemoveDispelTexture: 12.1.0 removes by index
    local canEngine = not NS.OldAuraEngine and b.AddDispelTypeTexture ~= nil and b.RemoveDispelTypeTexture ~= nil
        and styles ~= nil and styles.PreserveAsset ~= nil
    local edges = b._adDispelEdges
    -- the textures the engine holds now: the four strips, or a shaped icon's ring
    local held = b._adDispelHeld
    if not (on and canEngine) then
        if held and b._adDispelSig then
            for _, t in ipairs(held) do
                NS.RemoveDispelTexture(b, t)
                t:Hide()
            end
            b._adDispelSig = nil
            b._adDispelHeld = nil
        end
        return false
    end
    -- the game's own debuff border art, one texture on a sixth of the short
    -- side round the button; the engine picks the art by the aura's type
    if R("appearance", "dispelBorderStyle") == "game" and styles.Border ~= nil then
        local art = b._adDispelArt
        if not art then
            local host = b._adEdgeHost or b.TextOverlay or b
            art = host:CreateTexture(nil, "OVERLAY", nil, 6)
            b._adDispelArt = art
        end
        local bw, bh = b:GetSize()
        if type(bw) ~= "number" or (issecretvalue and issecretvalue(bw)) then bw = 36 end
        if type(bh) ~= "number" or (issecretvalue and issecretvalue(bh)) then bh = bw end
        local grow = math.min(bw, bh) * Factory.PANDEMIC_GROW
        if PixelUtil and PixelUtil.GetNearestPixelSize then
            grow = PixelUtil.GetNearestPixelSize(grow, UIParent:GetEffectiveScale(), 0)
        end
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", b, "TOPLEFT", -grow, grow)
        art:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", grow, -grow)
        art:SetAlpha(alpha or 1)
        local h = false
        if NS.DriverAura and NS.DriverAura.ShapeOf then
            local _, hh = NS.DriverAura.ShapeOf(rec.driver)
            h = hh == true
        end
        local gsig = "game|" .. (h and "h" or "b") .. "|" .. grow
        if b._adDispelSig ~= gsig then
            if held then
                for _, t in ipairs(held) do
                    NS.RemoveDispelTexture(b, t)
                    if t ~= art then t:Hide() end
                end
            end
            b:AddDispelTypeTexture(art, { showWhenHarmful = h, showWhenHelpful = not h,
                showWithoutDispelType = false, style = styles.Border })
            b._adDispelSig = gsig
            b._adDispelHeld = { art }
        end
        return true
    end
    if not edges then
        -- the border's layer: under the button's glows like the plain border
        local host = b._adEdgeHost or b.TextOverlay or b
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
    local key = Factory.MaskOf(rec)
    local list = key and { edges._adRing }
        or { edges.top, edges.bottom, edges.left, edges.right }
    for _, t in ipairs(list) do t:SetAlpha(alpha or 1) end
    local harmful = false
    if NS.DriverAura and NS.DriverAura.ShapeOf then
        local _, h = NS.DriverAura.ShapeOf(rec.driver)
        harmful = h == true
    end
    local borderOn = R("appearance", "borderEnabled") == true
    local c = R("appearance", "borderColor") or { 0, 0, 0, 1 }
    local sig = (harmful and "h" or "b") .. (key or "") .. (borderOn and
        ("|" .. c[1] .. "," .. c[2] .. "," .. c[3] .. "," .. (c[4] or 1)) or "|none")
    if b._adDispelSig ~= sig then
        if b._adDispelSig and held then
            -- a texture leaving the engine's hands stays hidden; one handed back keeps its look
            local keep = {}
            for _, t in ipairs(list) do keep[t] = true end
            for _, t in ipairs(held) do
                NS.RemoveDispelTexture(b, t)
                if not keep[t] then t:Hide() end
            end
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
        for _, t in ipairs(list) do b:AddDispelTypeTexture(t, opts) end
        b._adDispelSig = sig
        b._adDispelHeld = list
    end
    return true
end

-- The out-of-range shadow: the Cooldown Manager's overlay on the art at half
-- opacity (times the art's), grown iconW * (size - 1) / 2 per side on whole
-- pixels; shown while the spell's target is out of range.
local OOR_ATLAS = "UI-CooldownManager-OORshadow"
local oorAtlasOK
function Factory.RangeShadow(f, rec, out, va)
    local t = f._adRangeShadow
    if oorAtlasOK == nil then
        oorAtlasOK = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(OOR_ATLAS) ~= nil
    end
    local on = out and rec.kind == "spell" and Store.Resolve(rec, "states", "rangeShadow") == true
        and oorAtlasOK and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
    if not on then
        if t then t:Hide() end
        return
    end
    if not t then
        t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetAtlas(OOR_ATLAS)
        f._adRangeShadow = t
    end
    local art = f.icon
    local w = art:GetWidth()
    if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) then w = 36 end
    local grow = w * ((Store.Resolve(rec, "states", "rangeShadowSize") or 1) - 1) / 2
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        local es = f:GetEffectiveScale()
        if type(es) ~= "number" or (issecretvalue and issecretvalue(es)) then es = UIParent:GetEffectiveScale() end
        grow = PixelUtil.GetNearestPixelSize(grow, es, 0)
    end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", art, "TOPLEFT", -grow, grow)
    t:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", grow, -grow)
    t:SetVertexColor(1, 1, 1, 0.5 * (va or 1))
    t:Show()
end

-- Icon shadow: the Cooldown Manager's shadow atlas around the art, grown by
-- 18% of the width and 16% of the height per unit of size. w, h = the art's
-- size from a plain source (engine rects read secret). No atlas, no shadow.
local SHADOW_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local shadowAtlasOK
local function ApplyShadow(host, key, art, rec, w, h, alpha, show)
    local t = host[key]
    if show and Factory.SkinPlan(rec) then show = false end
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
    -- a shaped icon's shadow is its halo in black, fixed to the shape: size
    -- under 1 fades it (vertex alpha, under the dims' SetAlpha) rather than
    -- shrink it off the outline
    local shape = Factory.MaskOf(rec)
    if t._adShape ~= shape then
        if shape then
            t:SetTexture(Factory.ShapeFile(shape, "Halo"))
        else
            t:SetAtlas(SHADOW_ATLAS)
            t:SetVertexColor(1, 1, 1, 1)
        end
        t._adShape = shape
    end
    if shape then
        local k = (Factory.SHAPE_HALO - 1) / 2
        ox, oy = (w or 36) * k, (h or 36) * k
        t:SetVertexColor(0, 0, 0, math.min(1, size))
    end
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
        local inner = PaintBorderEdges(edges, f, rec, 1, nil, f._adBorderGrey)
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
    -- a diamond or hexagon draws no edge line: it would cross their sides
    if de and f._adMaskKey and not Factory.SHAPE_EDGE[f._adMaskKey] then de = false end
    f.cooldown:SetDrawSwipe(ds)
    f.cooldown:SetDrawEdge(de)
    f.cooldown:SetDrawBling(db)
    -- the swipe colour follows the presentation
    ApplySwipeAlpha(f)
end

-- Texcoords: aspect crop first, then zoom, centered.
-- The picture keeps its shape: its own switch, or its group's while it uses
-- the group's size.
function Factory.CropsToShape(rec)
    if not rec then return false end
    if Store.Resolve(rec, "appearance", "cropToShape") == true then return true end
    local g = rec.groupId and Store.Get(rec.groupId)
    return g ~= nil and Store.Resolve(rec, "position", "useGroupScale") ~= false
        and Store.Resolve(g, "arrangement", "cropIcons") == true
end

-- The part a crop keeps ("start", "middle", "end"): the icon's own, or its
-- group's while it crops with the group.
function Factory.CropFocus(rec)
    if Store.Resolve(rec, "appearance", "cropToShape") == true or not Factory.CropsToShape(rec) then
        return Store.Resolve(rec, "appearance", "cropFocus") or "middle"
    end
    local g = rec.groupId and Store.Get(rec.groupId)
    return (g and Store.Resolve(g, "arrangement", "cropFocus")) or "middle"
end

-- the start of a kept span of length `keep` along 0..1
local function FocusStart(focus, keep)
    if focus == "start" then return 0 end
    if focus == "end" then return 1 - keep end
    return (1 - keep) / 2
end
Factory.FocusStart = FocusStart

-- w, h: the box the picture fills; with the crop on, its shape is the crop,
-- else the hand-set aspect ratio is.
local function IconTexCoords(rec, w, h)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local zoom = R("appearance", "zoom") or 0.08
    local ar = R("appearance", "aspectRatio") or 1
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0
        and not (issecretvalue and (issecretvalue(w) or issecretvalue(h))) and Factory.CropsToShape(rec) then
        ar = w / h
    end
    local L, Rt, T, B = 0, 1, 0, 1
    if ar > 1 then
        local keep = 1 / ar
        T = FocusStart(Factory.CropFocus(rec), keep)
        B = T + keep
    elseif ar < 1 then
        L = FocusStart(Factory.CropFocus(rec), ar)
        Rt = L + ar
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

-- The crop for art filling `frame` inset by `pad`, read off the frame's plain size.
function Factory.BoxTexCoords(rec, frame, pad)
    local w, h = frame:GetSize()
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w, h = nil, nil end
    if type(w) ~= "number" or type(h) ~= "number" then return IconTexCoords(rec) end
    return IconTexCoords(rec, w - 2 * (pad or 0), h - 2 * (pad or 0))
end

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
    local dsc = R("text", "durationShadowColor") or { 0, 0, 0, 1 }
    cfs:SetShadowColor(dsc[1], dsc[2], dsc[3], R("text", "durationShadow") == true and (dsc[4] or 1) or 0)
    cfs:SetShadowOffset(R("text", "durationShadowX") or 1, R("text", "durationShadowY") or -1)
end

-- The bands in percent: a step curve over the time left's share (0 = done,
-- 1 = full), each band colouring the shares under its own and the text's
-- colour above the top one; steps carry epsilon gaps, as curves interpolate.
local pctCurves = {}
function Pct.Curve(rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    if R("text", "durationText") == false or R("text", "durationColorBands") ~= true
        or R("text", "durationBandsPercent") ~= true then
        return nil
    end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and C_DurationUtil
        and C_DurationUtil.CreateDurationTextBinding and Enum.DurationTextBindingProperty) then
        return nil
    end
    local count = math.max(1, math.min(5, math.floor(tonumber(R("text", "durBandCount")) or 1)))
    local bands = {}
    for i = 1, count do
        local p = R("text", "durBand" .. i .. "Pct") or 0
        if p > 0 then bands[#bands + 1] = { p = p, c = R("text", "durBand" .. i .. "Color") or { 1, 1, 1, 1 } } end
    end
    if #bands == 0 then return nil end
    table.sort(bands, function(a, b) return a.p < b.p end)
    local base = R("text", "durationColor") or { 1, 1, 1, 1 }
    local parts = {}
    for _, b in ipairs(bands) do
        parts[#parts + 1] = string.format("%g:%.3f,%.3f,%.3f,%.3f", b.p, b.c[1] or 1, b.c[2] or 1, b.c[3] or 1, b.c[4] or 1)
    end
    parts[#parts + 1] = string.format("%.3f,%.3f,%.3f,%.3f", base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1)
    local sig = table.concat(parts, "|")
    local curve = pctCurves[sig]
    if curve then return curve, sig end
    local function Col(c) return CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) end
    local EPS = 0.0001
    curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(0, Col(bands[1].c))
    for i, b in ipairs(bands) do
        local x = b.p / 100
        local nextC = bands[i + 1] and bands[i + 1].c or base
        if x > EPS then curve:AddPoint(x - EPS, Col(b.c)) end
        curve:AddPoint(x, Col(nextC))
    end
    curve:AddPoint(1, Col(base))
    pctCurves[sig] = curve
    return curve, sig
end

-- A plain start and length (or none) into the bound copy's duration.
function Pct.Plain(f, start, dur)
    local bnd = f._adPctBind
    if not bnd then return end
    if issecretvalue and (issecretvalue(start) or issecretvalue(dur)) then return end
    local d = f._adPctDur
    if not d then
        d = C_DurationUtil.CreateDuration()
        f._adPctDur = d
    end
    if type(start) == "number" and type(dur) == "number" and dur > 0 then
        d:SetTimeFromStart(start, dur)
    else
        d:Reset()
    end
    bnd:SetDuration(d)
end

-- Shown while the bands are on, the duration text shows, and no GCD-only spin
-- runs (the cooldown's own numbers skip those under its minimum).
function Pct.Show(f)
    local fs = f._adPctText
    if fs then fs:SetShown(f._adPctOn == true and not f._adDurHidden and not f._adPureGCD) end
end

-- The holder's bound copy: our binding on a text of the text host, styled as
-- the countdown; the cooldown's own numbers step aside (ApplyDurationVis).
function Pct.Apply(f, rec, kS)
    local curve = Pct.Curve(rec)
    if not curve then
        if f._adPctBind then f._adPctBind:SetEnabled(false) end
        f._adPctOn = nil
        Pct.Show(f)
        return
    end
    local fs = f._adPctText
    if not fs then
        fs = f.textHost:CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 7)
        f._adPctText = fs
    end
    local bnd = f._adPctBind
    if not bnd then
        bnd = C_DurationUtil.CreateDurationTextBinding()
        bnd:SetFontString(fs)
        if bnd.SetZeroDurationText then bnd:SetZeroDurationText("") end
        if bnd.SetExpiredText then bnd:SetExpiredText("") end
        f._adPctBind = bnd
    end
    local fmt = CountdownFormatterFor(rec)
    fmt = fmt or PlainTimerFormatter(Factory.IconRounding(rec), false)
    if fmt then bnd:SetFormatter(fmt) end
    bnd:SetTextColorCurve(curve, Enum.DurationTextBindingProperty.RemainingPercent)
    bnd:SetEnabled(true)
    f._adPctOn = true
    StyleCountdownText(fs, rec, kS, f, STANDARD_TEXT_FONT)
end

-- An aura button's bound copy: the engine's own binding (SetDurationText) with
-- the curve; the swipe's numbers step aside. Accessible passes only.
function Pct.Button(b, rec, kS, sw, textA)
    local curve = b.SetDurationText and Pct.Curve(rec)
    if not curve then
        if b._adPctSig then
            if b.ClearDurationText then b:ClearDurationText() end
            b._adPctSig = nil
        end
        if b._adPctText then b._adPctText:Hide() end
        return false
    end
    local fs = b._adPctText
    if not fs then
        fs = (b.TextOverlay or b):CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 7)
        b._adPctText = fs
    end
    local fmt, fsig = CountdownFormatterFor(rec)
    fmt = fmt or PlainTimerFormatter(Factory.IconRounding(rec), true)
    local _, csig = Pct.Curve(rec)
    local sig = tostring(fsig) .. "|" .. tostring(csig)
    if b._adPctSig ~= sig then
        b._adPctSig = sig
        b:SetDurationText(fs, { textFormatter = fmt, textColor = { curve = curve,
            property = Enum.DurationTextBindingProperty.RemainingPercent } })
    end
    sw:SetHideCountdownNumbers(true)
    StyleCountdownText(fs, rec, kS, b, STANDARD_TEXT_FONT)
    fs:SetAlpha(textA or 1)
    fs:Show()
    return true
end

-- pinOwner: the holder, whose own texts may ride another frame (Core\AD_TextAnchor.lua);
-- nil for a copy on the game's aura button, which cannot move in combat.
local function StyleStackText(fs, rec, kS, anchorTo, pinOwner)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local outline = R("text", "stackOutline") or "OUTLINE"
    if outline == "NONE" then outline = "" end
    fs:SetFont(IconFont(R("text", "stackFont")),
        math.max(6, math.floor((R("text", "stackSize") or 14) * kS + 0.5)), outline)
    fs._adTextRGBA = R("text", "stackColor") or { 1, 1, 1, 1 }
    PaintText(fs)
    local anch = R("text", "stackAnchor") or "BOTTOMRIGHT"
    local x, y = (R("text", "stackX") or 0) * kS, (R("text", "stackY") or 0) * kS
    local TA = pinOwner and NS.TextAnchor
    if TA then
        TA.Place(fs, pinOwner, "stack", R("text", "stackPinTo"), R("text", "stackPinTarget"), anch, anch, x, y)
    else
        fs:ClearAllPoints()
        fs:SetPoint(anch, anchorTo, anch, x, y)
    end
    local ssc = R("text", "stackShadowColor") or { 0, 0, 0, 1 }
    fs:SetShadowColor(ssc[1], ssc[2], ssc[3], R("text", "stackShadow") == true and (ssc[4] or 1) or 0)
    fs:SetShadowOffset(R("text", "stackShadowX") or 1, R("text", "stackShadowY") or -1)
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
    -- an item, trinket or totem: its own switch only
    if rec.kind == "item" or rec.kind == "trinket" or rec.kind == "totem" then return false end
    local g = rec.groupId and Store.Get(rec.groupId)
    return g ~= nil and g.type == "group"
        and Store.Resolve(g, "keybind", "showKeybinds") == true
end

-- An item its stock hides: out while it shows only in stock, or in stock while
-- it shows only when out (a trinket is out while its slot is empty).
function Factory.StockHidden(f, rec)
    if not (rec.kind == "item" or rec.kind == "trinket" or rec.kind == "ammo") then return false end
    if f._adItemEmpty then return Store.Resolve(rec, "outOfStock", "hideWhenMissing") == true end
    return rec.kind ~= "trinket" and Store.Resolve(rec, "outOfStock", "showOnlyWhenOut") == true
end

-- The one frame-alpha writer: the icon's opacity times the conditions module's
-- (0 while inert, else its fade), and 0 for an item its stock hides, except in
-- edit mode so it stays grabbable.
function Factory.ApplyFrameAlpha(f, rec)
    local a = Store.Resolve(rec, "appearance", "alpha") or 1
    -- _adPassive: a passive trinket in a slot set to on-use trinkets only
    if (Factory.StockHidden(f, rec) or (rec.kind == "trinket" and f._adPassive))
        and not (NS.LayoutEngine and NS.LayoutEngine.IsEditMode
            and NS.LayoutEngine.IsEditMode()) then
        a = 0
    end
    if NS.Conditions then a = a * NS.Conditions.AlphaFor(rec) end
    f:SetAlpha(a)
end

-- Every custom text's outline ("" for none).
function Factory.LabelOutline(rec)
    local o = Store.Resolve(rec, "label", "labelOutline") or "OUTLINE"
    if o == "NONE" then return "" end
    return o
end

-- A custom text's font: its own, else custom text 1's.
function Factory.LabelFont(rec, suf)
    local f = (suf ~= "") and Store.Resolve(rec, "label", "labelFont" .. suf) or nil
    if f == nil or f == "" then f = Store.Resolve(rec, "label", "labelFont") end
    return f
end

-- One custom text's look (suf "", "2" or "3") on fs, anchored to anchorTo:
-- the holder's, and the copies a group buff's combat layers carry. pinOwner:
-- the holder, whose own texts may ride another frame (the copies never do).
local function StyleLabel(fs, rec, suf, kS, anchorTo, pinOwner)
    local R = function(section, field) return Store.Resolve(rec, section, field) end
    fs:SetFont(IconFont(Factory.LabelFont(rec, suf)),
        math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), Factory.LabelOutline(rec))
    local lc = R("label", "labelColor" .. suf) or { 1, 1, 1, 1 }
    fs:SetTextColor(lc[1], lc[2], lc[3], lc[4] or 1)
    local an = R("label", "labelAnchor" .. suf) or "CENTER"
    local x, y = (R("label", "labelX" .. suf) or 0) * kS, (R("label", "labelY" .. suf) or 0) * kS
    local TA = pinOwner and NS.TextAnchor
    if TA then
        TA.Place(fs, pinOwner, "label" .. suf, R("label", "labelPinTo" .. suf),
            R("label", "labelPinTarget" .. suf), an, an, x, y)
    else
        fs:ClearAllPoints()
        fs:SetPoint(an, anchorTo, an, x, y)
    end
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
    -- other icon's border sits at +1, under the swipe (+2); a spell icon's
    -- aura overlay (the button at +5) covers both.
    local overlay = NS.DriverAura ~= nil and NS.DriverAura.OverlayOn ~= nil
        and NS.DriverAura.OverlayOn(rec) == true
    Factory.ApplyBorder(f, rec, rec.kind == "aura" and Factory.AURA_LADDER.border or 1, forceHide)
    -- Texts are the top of an icon: the text host sits over every glow at its
    -- default level and any anchored engine button's stack. Set each pass
    -- (children don't follow SetFrameLevel), skipped when the level reads secret.
    local hostLvl = f:GetFrameLevel()
    local plainLvl = not (issecretvalue and issecretvalue(hostLvl)) and type(hostLvl) == "number"
    if plainLvl then
        f.textHost:SetFrameLevel(hostLvl + Factory.TEXT_LEVEL + Factory.Rise(rec))
        if rec.kind ~= "aura" then f.cooldown:SetFrameLevel(hostLvl + 2) end
    end
    -- The countdown number moves onto a child of its swipe one under the text
    -- host: the swipe keeps driving it and hides it with itself, and it draws
    -- over the glows. With an aura overlay it stays on the swipe, under the
    -- button that covers the spell's look.
    local cfs = f.cooldown.GetCountdownFontString and f.cooldown:GetCountdownFontString()
    if cfs then
        local home = f.cooldown
        if not overlay then
            home = f._adCdText
            if not home then
                home = CreateFrame("Frame", nil, f.cooldown)
                home:SetAllPoints()
                home:EnableMouse(false)
                f._adCdText = home
            end
            if plainLvl then home:SetFrameLevel(hostLvl + Factory.TEXT_LEVEL - 1 + Factory.Rise(rec)) end
        end
        if cfs:GetParent() ~= home then cfs:SetParent(home) end
    end
    -- With an aura overlay the button shows the aura's count in that corner,
    -- so the charges move to a low host at +3, between the swipe (+2) and the
    -- button (+5), and show while the aura is down.
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
    -- cropped to the icon's shape: the art's box is known from here
    if fwS and fhS and Factory.CropsToShape(rec) then
        f.icon:SetTexCoord(IconTexCoords(rec, fwS - 2 * padPx, fhS - 2 * padPx))
    end
    -- cut to its shape: the art here, and what draws over the art's box reads
    -- f._adMaskKey (the swipe below, the glows, the checkmark, the press look)
    local mask = Factory.MaskOf(rec)
    f._adMaskKey = mask
    ShapeTex(f.icon, mask)
    -- a Masque skin: the picture in its box with its crop and mask, its
    -- layers round it (the top ones on a frame at the border's level, under
    -- the swipe), and below, the swipe in its box
    local plan = Factory.SkinPlan(rec)
    f._adSkinPlan = plan
    local top = f._adSkinTop
    if plan and not top then
        top = CreateFrame("Frame", nil, f._adStage or f)
        top:SetAllPoints(f)
        top:EnableMouse(false)
        f._adSkinTop = top
    end
    if top and plainLvl then
        top:SetFrameLevel(hostLvl + (rec.kind == "aura" and Factory.AURA_LADDER.border or 1))
    end
    if plan then
        Factory.SkinArt(f.icon, rec, plan, f, fwS or 36, fhS or 36)
    else
        Factory.SkinArt(f.icon, rec, nil)
    end
    local back = f.icon:GetParent()
    Factory.SkinLayers(plan, back, top or back, f, f.icon, fwS or 36, fhS or 36,
        f._adShownAlpha or f._adStateAlpha or 1, forceHide)

    local hasSwipe = NS.Schema.Applies(nil, NS.Schema.icon.swipe, rec.kind)
    if hasSwipe then
        ApplyCdPresentation(f, rec)
        f.cooldown:SetReverse(R("swipe", "reverse") == true)
        ShapeSwipe(f.cooldown, mask, plan)
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
        -- a skin's swipe box instead of the insets
        if plan then SkinPlace(f.cooldown, plan.cooldown, plan, f, f.icon, fwS or 36, fhS or 36) end
    end
    -- Pushed only when the recipe changes; nil restores the stock format.
    if f.cooldown.SetCountdownFormatter then
        local fmt, sig = CountdownFormatterFor(rec)
        if f._adFmtSig ~= sig then
            f._adFmtSig = sig
            f.cooldown:SetCountdownFormatter(fmt)
        end
    end
    -- the hide after the formatter: handing one over shows the numbers
    Pct.Apply(f, rec, kS)
    Factory.ApplyDurationVis(f, rec)
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
        StyleStackText(f.stackText, rec, kS, f, rec.kind ~= "aura" and f or nil)
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
    -- a special icon's own texts ride slots 4 to 6 (Schema.SPECIAL_TEXTS),
    -- made the first time a special icon wears the frame
    local special = rec.kind == "special"
    if special and not f.labelText4 then
        for n = 4, 6 do
            local fs = f.textHost:CreateFontString(nil, "OVERLAY")
            fs:SetDrawLayer("OVERLAY", 7)
            fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            fs:Hide()
            f["labelText" .. n] = fs
        end
    end
    local labelFS = { f.labelText, f.labelText2, f.labelText3, f.labelText4, f.labelText5, f.labelText6 }
    local sufs = special and Factory.SPECIAL_LABELS or Factory.LABELS
    -- a pooled frame a special icon wore: its slots 4 to 6 stand down
    for i = #sufs + 1, 6 do
        local st = f._adLabels[i]
        if st then
            f._adLabels[i] = nil
            if st.fs then
                st.fs:SetText("")
                st.fs:Hide()
                if NS.TextAnchor and NS.TextAnchor.live[st.fs] then NS.TextAnchor.Place(st.fs, f, "label" .. i, "own") end
            end
        end
    end
    -- under the time gate the button and the missing look carry every label
    local split = rec.kind == "aura" and Factory.TimeGateFrac(rec) ~= nil
    -- custom texts out of the state dim ride a host of their own at the text
    -- host's level, which SetState keeps bright (states.labelsFullOpacity)
    local bright = rec.kind ~= "aura" and R("states", "labelsFullOpacity") == true
    if bright and not f._adLabelHost then
        f._adLabelHost = CreateFrame("Frame", nil, f)
        f._adLabelHost:SetAllPoints()
        f._adLabelHost:EnableMouse(false)
    end
    if f._adLabelHost then
        local tl = f.textHost:GetFrameLevel()
        if type(tl) == "number" and not (issecretvalue and issecretvalue(tl)) then f._adLabelHost:SetFrameLevel(tl) end
    end
    local labelParent = bright and f._adLabelHost or f.textHost
    for i, suf in ipairs(sufs) do
        local fs = labelFS[i]
        local st = f._adLabels[i] or {}
        f._adLabels[i] = st
        st.fs = fs
        -- a pinned text rides its carrier; the rest move between the two hosts
        if fs and fs:GetParent() ~= labelParent and not (NS.TextAnchor and NS.TextAnchor.live[fs]) then
            fs:SetParent(labelParent)
        end
        st.ready = R("label", "labelShowReady" .. suf) ~= false
        st.cd = R("label", "labelShowCooldown" .. suf) ~= false
        st.activeOnly = rec.kind == "aura" and R("label", "labelActiveOnly" .. suf) == true
        st.missingOnly = rec.kind == "aura" and R("label", "labelMissingOnly" .. suf) == true
        st.split = split
        local ltext = R("label", "labelText" .. suf)
        if fs and ltext and ltext ~= "" then
            StyleLabel(fs, rec, suf, kS, f, f)
            st.has = true
        elseif fs then
            fs:SetText("")
            st.has = false
            fs:Hide()
            -- an emptied text leaves any pin, so its carrier does not linger
            if NS.TextAnchor and NS.TextAnchor.live[fs] then NS.TextAnchor.Place(fs, f, "label" .. suf, "own") end
        end
    end
    f._adHasLabel = f._adLabels[1].has
    Factory.ApplyMissingLabels(f, rec, kS)

    -- Keybind text style; the cooldown driver sets the text.
    local kbOn = Factory.KeybindEnabled(rec)
    if kbOn then
        local kol = R("keybind", "keybindOutline") or "OUTLINE"
        if kol == "NONE" then kol = "" end
        f.keybindText:SetFont(IconFont(R("keybind", "keybindFont")),
            math.max(6, math.floor((R("keybind", "keybindSize") or 12) * kS + 0.5)), kol)
        local kc = R("keybind", "keybindColor") or { 1, 1, 1, 1 }
        f.keybindText:SetTextColor(kc[1], kc[2], kc[3], kc[4] or 1)
        local kan = R("keybind", "keybindAnchor") or "TOPLEFT"
        local kx, ky = (R("keybind", "keybindX") or 0) * kS, (R("keybind", "keybindY") or 0) * kS
        if NS.TextAnchor then
            NS.TextAnchor.Place(f.keybindText, f, "keybind", R("keybind", "keybindPinTo"),
                R("keybind", "keybindPinTarget"), kan, kan, kx, ky)
        else
            f.keybindText:ClearAllPoints()
            f.keybindText:SetPoint(kan, f, kan, kx, ky)
        end
        f.keybindText:Show()
    else
        f.keybindText:Hide()
    end

    -- Glows restart only when their signature changes: a restart is visible.
    Factory.SetState(f, rec, f._adOnCooldown, f._adDesatState)
    -- the warning glow follows the ammo and the pet, not the icon's state
    if NS.DriverWarn then NS.DriverWarn.Sync(f, rec) end
    -- the toggle glow follows Shoot, Auto Shot or Attack being on
    if NS.DriverToggle then NS.DriverToggle.Sync(f, rec) end
    -- the suggested glow follows the game's Assisted Highlight
    if NS.DriverAssist then NS.DriverAssist.Sync(f, rec) end
    -- a special icon's texts are its templates expanded, so it paints again
    if rec.kind == "special" and NS.SpecialIcon then NS.SpecialIcon.Restyle(f, rec) end
end

-- Show only when little time is left (DriverAura): the share of the aura's
-- time left the live look shows under, or nil.
function Factory.TimeGateFrac(rec)
    local D = NS.DriverAura
    if not (D and D.TimeGateFrac) then return nil end
    return D.TimeGateFrac(rec)
end

-- Where an aura icon's custom text `suf` shows: on the live button, with the
-- missing look, or else on the holder in both states. Under the time gate a
-- text shown in both states takes the first two, so its live half waits too.
function Factory.LabelOnButton(rec, suf)
    if not (rec and rec.kind == "aura") then return false end
    if Store.Resolve(rec, "label", "labelActiveOnly" .. suf) == true then return true end
    return Factory.TimeGateFrac(rec) ~= nil
        and Store.Resolve(rec, "label", "labelMissingOnly" .. suf) ~= true
end

function Factory.LabelWithMissing(rec, suf)
    if not (rec and rec.kind == "aura") then return false end
    if Store.Resolve(rec, "label", "labelMissingOnly" .. suf) == true then return true end
    return Factory.TimeGateFrac(rec) ~= nil
        and Store.Resolve(rec, "label", "labelActiveOnly" .. suf) ~= true
end

-- A label kept to the aura's absence needs solid live art over it, or a stage (NeedsEraser).
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
        local want = ok and Factory.LabelWithMissing(rec, suf)
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
            fs:SetFont(IconFont(Factory.LabelFont(rec, suf)),
                math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), Factory.LabelOutline(rec))
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

-- Aura icon ladder over the holder: glows above borders, texts above glows,
-- the live button above every missing piece.
Factory.AURA_LADDER = { border = 1, missGlow = 2, missLabels = 3, button = 4 }

-- A live engine button's stack over its own level: the swipe, its border, its
-- glows at their frame level (GLOW_LEVEL unless set, a style frame one over),
-- its texts over those, then the time-left bar that hides them all.
Factory.BUTTON_STACK = { swipe = 1, edge = 2, text = GLOW_LEVEL + 2, gate = GLOW_LEVEL + 3 }

-- The holder's texts: over a spell overlay's button (one rung up) and its stack.
Factory.TEXT_LEVEL = Factory.AURA_LADDER.button + 1 + Factory.BUTTON_STACK.gate + 1

-- The level a live button's stack and glows count from: the single-icon
-- driver's stamp, else the button's own while it reads plain (it can read
-- secret in the create window).
local function ButtonBase(b)
    if type(b._adLevel) == "number" then return b._adLevel end
    local v = b:GetFrameLevel()
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end
    return nil
end

-- A button no holder anchors (aura group rows, a unit's auras) lays its stack
-- from its own level, the one its glows count from: texts over the glows.
local function StackOwnLevel(b)
    if type(b._adLevel) == "number" then return end
    local base = ButtonBase(b)
    if not base then return end
    local S = Factory.ButtonStack(b)
    if b._adSwipe then b._adSwipe:SetFrameLevel(base + S.swipe) end
    if b._adEdgeHost then b._adEdgeHost:SetFrameLevel(base + S.edge) end
    if b.TextOverlay then b.TextOverlay:SetFrameLevel(base + S.text) end
    if b._adTimeGate then b._adTimeGate:SetFrameLevel(base + S.gate) end
end

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

-- Before that: an aura icon's opacity while the aura is up until Active's
-- starts (auraActive.activeTimeBefore), 0 off the time gate.
function Factory.TimeGateBefore(rec)
    if Factory.TimeGateFrac(rec) == nil then return 0 end
    local v = Store.Resolve(rec, "auraActive", "activeTimeBefore") or 0
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

-- A Before that above 0 puts the gate under the swipe and texts, which then
-- show the whole time the aura is up, and a copy of the art, border and
-- shadow over the gate at that opacity, cut to the gate's fill.
Factory.BUTTON_STACK_LOW = { edge = 2, gate = 3, copy = 4, swipe = 5, text = GLOW_LEVEL + 2 }

function Factory.ButtonStack(b)
    return (b and b._adLowStack) and Factory.BUTTON_STACK_LOW or Factory.BUTTON_STACK
end

-- The button's stack from its own plain level, every piece it has.
local function LayStack(b)
    local base = ButtonBase(b)
    if not base then return end
    local S = Factory.ButtonStack(b)
    if b._adSwipe then b._adSwipe:SetFrameLevel(base + S.swipe) end
    if b._adEdgeHost then b._adEdgeHost:SetFrameLevel(base + S.edge) end
    if b.TextOverlay then b.TextOverlay:SetFrameLevel(base + S.text) end
    if b._adTimeGate then b._adTimeGate:SetFrameLevel(base + S.gate) end
    if b._adBeforeCopy then b._adBeforeCopy:SetFrameLevel(base + Factory.BUTTON_STACK_LOW.copy) end
end

-- The Before that copy: the art (the Active override or the aura's own, the
-- holder's stand-in), its border and shadow at `alpha`, shown only while the
-- gate's fill spans it. Accessible passes only, like the button.
local function ApplyBeforeCopy(b, rec, on, alpha, w, h, padPx)
    local c = b._adBeforeCopy
    local gb = b._adTimeGate
    if not (on and gb) then
        if c then c:Hide() end
        return
    end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    if not c then
        c = CreateFrame("Frame", nil, b)
        c:SetAllPoints(b)
        c:EnableMouse(false)
        c._adArt = c:CreateTexture(nil, "ARTWORK")
        c._adEdges = {}
        for _, k in ipairs(BORDER_KEYS) do
            local t = c:CreateTexture(nil, "OVERLAY", nil, 6)
            t:SetColorTexture(1, 1, 1, 1)
            c._adEdges[k] = t
        end
        b._adBeforeCopy = c
    end
    local base = ButtonBase(b)
    if base then c:SetFrameLevel(base + Factory.BUTTON_STACK_LOW.copy) end
    local art = c._adArt
    art:SetTexture(Factory.AuraLiveTexture(rec))
    art:SetTexCoord(IconTexCoords(rec, (w or 0) - 2 * padPx, (h or 0) - 2 * padPx))
    art:ClearAllPoints()
    if padPx > 0 then
        art:SetPoint("TOPLEFT", b, "TOPLEFT", padPx, -padPx)
        art:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -padPx, padPx)
    else
        art:SetAllPoints(b)
    end
    ShapeTex(art, Factory.MaskOf(rec))
    -- a Masque skin's picture and layers, cut to the gate's fill with the rest
    local plan = Factory.SkinPlan(rec)
    Factory.SkinArt(art, rec, plan, c, w or 36, h or 36)
    local skinned = Factory.SkinLayers(plan, c, c, c, art, w or 36, h or 36, alpha)
    art:SetDesaturated(R("auraActive", "activeDesaturate") == true)
    local tint = R("auraActive", "activeTintEnabled") == true and (R("auraActive", "activeTintColor") or { 1, 1, 1, 1 })
        or { 1, 1, 1, 1 }
    art:SetVertexColor(tint[1], tint[2], tint[3], alpha)
    if R("appearance", "borderEnabled") then
        PaintBorderEdges(c._adEdges, b, rec, alpha)
    else
        for _, t in pairs(c._adEdges) do t:Hide() end
    end
    ApplyShadow(c, "_adShadow", art, rec, w, h, alpha, R("appearance", "shadowEnabled") == true)
    local m = GateMask(c, gb:GetStatusBarTexture())
    SetGated(art, m)
    for _, t in pairs(c._adEdges) do SetGated(t, m) end
    if c._adShadow then SetGated(c._adShadow, m) end
    for _, t in ipairs(skinned) do SetGated(t, m) end
    c:Show()
end

-- The editor's stand-in before Active starts (its Aura loop): the art, border
-- and shadow at Before that's opacity, with the editing floor; the next
-- restyle puts the Active look back.
function Factory.PaintBeforeLook(b, rec)
    if not (b and rec) then return end
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local a = EditFloor(Factory.TimeGateBefore(rec))
    local ic = (b._adIconOv and b._adIconOv:IsShown()) and b._adIconOv or b._adIcon
    if ic then
        local c = R("auraActive", "activeTintEnabled") == true and (R("auraActive", "activeTintColor") or { 1, 1, 1, 1 })
            or { 1, 1, 1, 1 }
        ic:SetVertexColor(c[1], c[2], c[3], a)
    end
    if b._adBtnEdges and R("appearance", "borderEnabled") then PaintBorderEdges(b._adBtnEdges, b, rec, a) end
    if b._adShadow then b._adShadow:SetAlpha(a) end
end

-- Show only when little time is left: a hidden bar the engine fills with the
-- time left, over the live look. frac = the share it shows under (nil = off);
-- w, h = the button; reach = how far its texts go. A button binds one
-- duration bar (b._adBarOn), so glow 1 leaves it meanwhile (DriverAura).
-- True while the gate is on.
local function ApplyShowGate(b, frac, w, h, reach)
    local gb = b._adTimeGate
    local E = NS.LayoutEngine
    local on = frac ~= nil and b.SetDurationBar ~= nil and Enum ~= nil
        and Enum.StatusBarInterpolation ~= nil and Enum.StatusBarTimerDirection ~= nil
        and Enum.StatusBarTimerDirection.RemainingTime ~= nil
        and not (E ~= nil and E.IsEditMode ~= nil and E.IsEditMode() == true)
    if not on then
        if gb then gb:Hide() end
        return false
    end
    if not gb then
        gb = CreateFrame("StatusBar", nil, b)
        gb:SetStatusBarTexture(WHITE)
        gb:SetMinMaxValues(0, 1)
        gb:EnableMouse(false)
        local fill = gb:GetStatusBarTexture()
        fill:SetColorTexture(0, 0, 0, 0)
        fill:SetBlendMode("DISABLE")
        b._adTimeGate = gb
    end
    if b._adBarOn ~= gb then
        b._adBarOn = gb
        b:SetDurationBar(gb, {
            interpolation = Enum.StatusBarInterpolation.Immediate,
            direction = Enum.StatusBarTimerDirection.RemainingTime,
        })
    end
    -- The fill spans the look and a margin while more than frac is left; the
    -- look shows within gw / L of the aura's life once less is.
    local m = math.max(w, h, reach or 0)
    local gw, gh = w + 2 * m, h + 2 * m
    local L = math.min(120000, gw / 0.0005)
    gb:ClearAllPoints()
    gb:SetSize(L, gh)
    gb:SetPoint("LEFT", b, "CENTER", math.min(-gw / 2, gw / 2 - frac * L), 0)
    local base = ButtonBase(b)
    if base then gb:SetFrameLevel(base + Factory.ButtonStack(b).gate) end
    gb:Show()
    return true
end

-- The live engine button shows exactly while the aura is up: no presence read, nothing read off it.
function Factory.StyleAuraButton(b, rec, px, opts)
    if not (b and rec) then return end
    opts = opts or {}
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    -- show only when little time is left (aura icons)
    local timed = Factory.TimeGateFrac(rec)
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
    -- custom texts out of the active dim (a hidden active look still hides them)
    local lb = (rec.kind == "aura") and R("auraActive", "activeLabelsBright") or R("states", "labelsFullOpacity")
    local labelA = (aA > 0 and lb == true) and 1 or textA
    -- Active alpha goes on the pieces, so the button stays at 1.
    b:SetAlpha(1)
    -- a Before that above 0 lays the low stack (the gate under the swipe and texts)
    local before = Factory.TimeGateBefore(rec)
    local low = timed ~= nil and before > 0 and not forceHide
    if (b._adLowStack or false) ~= low then
        b._adLowStack = low
        LayStack(b)
    end
    StackOwnLevel(b)
    local padPx = (R("appearance", "padding") or 0) * kS
    -- the icon's shape: its art, plate and swipe here; border and glows read it too
    local mask = Factory.MaskOf(rec)
    -- a Masque skin: the same, from the skin's boxes on the button
    local plan = Factory.SkinPlan(rec)
    local bw0, bh0 = opts.w or px or 36, opts.h or px or 36
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
        local bw, bh = (opts.w or px or 0) - 2 * padPx, (opts.h or px or 0) - 2 * padPx
        local L, Rt, T, B = IconTexCoords(rec, bw, bh)
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
    ShapeTex(b._adIcon, mask)
    ShapeTex(b._adIconOv, mask)
    if plan and ic then
        Factory.SkinArt(ic, rec, plan, b, bw0, bh0)
    else
        Factory.SkinArt(b._adIcon, rec, nil)
        Factory.SkinArt(b._adIconOv, rec, nil)
    end
    -- Shown with opts.erase, as far as the missing look reaches.
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
    -- The plate keeps a dimmed active icon from showing the missing look (not with opts.erase).
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
        ShapeTex(plate, mask)
        -- under a skin the plate is the picture's box and mask
        if plan and ic then
            plate:ClearAllPoints()
            plate:SetAllPoints(ic)
        end
        SkinMask(plate, plan, b, bw0, bh0)
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
        ShapeSwipe(sw, mask, plan)
        -- a skin's swipe box; back to the whole button without one
        if plan then
            SkinPlace(sw, plan.cooldown, plan, b, ic, bw0, bh0)
            sw._adSkinBox = true
        else
            -- the aura swipe's own insets (positive shrinks), on whole pixels
            local ix, iy
            if R("auraSwipe", "separateInsets") == true then
                ix, iy = R("auraSwipe", "swipeInsetX") or 0, R("auraSwipe", "swipeInsetY") or 0
            else
                ix = R("auraSwipe", "swipeInset") or 0
                iy = ix
            end
            ix, iy = ix * kS, iy * kS
            if PixelUtil and PixelUtil.GetNearestPixelSize then
                local es = UIParent:GetEffectiveScale()
                ix, iy = PixelUtil.GetNearestPixelSize(ix, es, 0), PixelUtil.GetNearestPixelSize(iy, es, 0)
            end
            if ix ~= 0 or iy ~= 0 then
                sw:ClearAllPoints()
                sw:SetPoint("TOPLEFT", b, "TOPLEFT", ix, -iy)
                sw:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -ix, iy)
                sw._adInsetBox = true
            elseif sw._adSkinBox or sw._adInsetBox then
                sw:ClearAllPoints()
                sw:SetAllPoints(b)
                sw._adInsetBox = nil
            end
            sw._adSkinBox = nil
        end
        sw:SetDrawEdge(R("auraSwipe", "swipeEdge") == true and not forceHide
            and (mask == nil or Factory.SHAPE_EDGE[mask] == true))
        sw:SetDrawBling(R("auraSwipe", "swipeBling") == true and not forceHide)
        sw:SetSwipeColor(sc[1], sc[2], sc[3], (sc[4] or 0.8) * aA)
        -- Edge colour and length as on the cooldown swipe (template art, no
        -- SetEdgeTexture); its alpha follows Active alpha.
        if sw.SetEdgeScale then sw:SetEdgeScale(R("auraSwipe", "edgeScale") or 1.8) end
        if sw.SetEdgeColor then
            local ec = R("auraSwipe", "edgeColor") or { 1, 1, 1, 1 }
            sw:SetEdgeColor(ec[1], ec[2], ec[3], (ec[4] or 1) * aA)
        end
        -- The hide goes last: handing over a formatter shows the numbers, and
        -- an aura button gets no per-feed hide after it.
        if sw.SetCountdownFormatter then
            local fmt, sig = CountdownFormatterFor(rec)
            if b._adFmtSig ~= sig then
                b._adFmtSig = sig
                sw:SetCountdownFormatter(fmt)
            end
        end
        sw:SetHideCountdownNumbers(R("text", "durationText") == false)
        Pct.Button(b, rec, kS, sw, textA)
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
    -- a skin's layers: the back ones on the button under the art, the rest on its border's layer
    Factory.SkinLayers(plan, b, b._adEdgeHost or b, b, ic or b, bw0, bh0, artA, forceHide)
    -- Labels kept to the aura's time ride the button, which the game shows
    -- exactly while the aura is up; the holder's copies stand down (SetState).
    b._adLabelFS = b._adLabelFS or {}
    local lhost = b.TextOverlay or b
    for i, suf in ipairs({ "", "2", "3" }) do
        local fs = b._adLabelFS[i]
        local ltext = R("label", "labelText" .. suf)
        if Factory.LabelOnButton(rec, suf) and ltext and ltext ~= "" then
            if not fs then
                fs = lhost:CreateFontString(nil, "OVERLAY")
                fs:SetDrawLayer("OVERLAY", 7)
                b._adLabelFS[i] = fs
            end
            fs:SetFont(IconFont(R("label", "labelFont")),
                math.max(6, math.floor((R("label", "labelSize" .. suf) or 12) * kS + 0.5)), Factory.LabelOutline(rec))
            local lc = R("label", "labelColor" .. suf) or { 1, 1, 1, 1 }
            fs:SetTextColor(lc[1], lc[2], lc[3], (lc[4] or 1) * labelA)
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
    -- opts.rowGlows: a Dynamic row's button, which has no holder, so it draws
    -- every glow but a Missing one (Always ones too) and those on its row's
    -- lanes (opts.rowLanes, by slot)
    local row = opts.rowGlows == true
    local function Elsewhere(k)
        if row then return Factory.MissingGlowOn(rec, k) or (opts.rowLanes ~= nil and opts.rowLanes[k] == true) end
        -- under the time gate the editor's stand-in draws an Always glow too
        if timed and opts.previewGlows == true then
            return R("auraActive", "activeGlowWhen" .. ((k > 1) and k or "")) == "missing"
        end
        return Factory.HolderGlowOn(rec, k)
    end
    -- opts.glowElsewhere: a glow gate moved the glow onto its own button, as
    -- the time gate always does but on the editor's stand-in
    Factory.SetAuraButtonGlow(b, rec, (not forceHide) and not opts.glowElsewhere
        and not (timed and opts.previewGlows ~= true)
        and R("auraActive", "activeGlow") == true and not Elsewhere(1),
        opts.w or px, opts.h or px, aA)
    -- Glows 2-4 ride their own buttons in play; the editor preview's one
    -- stand-in draws them all (opts.previewGlows) and drops them otherwise,
    -- as it also serves spell icons.
    for k = 2, (NS.Schema and NS.Schema.AURA_GLOW_SLOTS) or 1 do
        Factory.SetAuraButtonGlow(b, rec, (opts.previewGlows == true or row) and (not forceHide)
            and R("auraActive", "activeGlow" .. k) == true and not Elsewhere(k),
            opts.w or px, opts.h or px, aA, k)
    end
    -- Show only when little time is left (opts.erase), at Before that's
    -- opacity until then
    local gated = false
    if timed and opts.erase == true then
        gated = ApplyShowGate(b, timed, opts.w or px, opts.h or px, Factory.LiveTextReach(rec, kS))
    else
        ApplyShowGate(b, nil)
    end
    ApplyBeforeCopy(b, rec, gated and low, before, opts.w or px, opts.h or px, padPx)
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
-- The action bar's attack flash as it shipped: retail's atlas, the old full red
-- file elsewhere. Forever's bars draw the atlas frames (barattack below).
local RED_FLASH_ATLAS = "UI-HUD-ActionBar-IconFrame-Flash"
local RED_FLASH_FILE = "Interface\\Buttons\\UI-QuickslotRed"
-- The bars' checked look and attack blink as the client draws them (Forever
-- runs these bars too): the gold frame added over a 45 px button at 46 x 45,
-- the red frame shown and hidden every 0.4 s (ATTACK_BUTTON_FLASH_TIME); the
-- old files where a client lacks the atlas.
local BAR_CHECK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local BAR_CHECK_FILE = "Interface\\Buttons\\CheckButtonHilight"
local BAR_W = 46 / 45
local BAR_BLINK = 0.4
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
    procloop = true, ants = true, flash = true, redflash = true, barcheck = true, barattack = true, pandemic = true }
local PANDEMIC_BORDER = "UI-CooldownManager-PandemicBorder"
local PANDEMIC_MASK = "UI-CooldownManager-PandemicBorder-Mask"
local PANDEMIC_FX = { "UI-CooldownManager-PandemicFX-Icon01", "UI-CooldownManager-PandemicFX-Icon02",
    "UI-CooldownManager-PandemicFX-Icon03" }
-- the pandemic box: the icon plus a sixth of its short side all round
Factory.PANDEMIC_GROW = 6 / 36
-- On a shaped icon (rec) every style draws the shape's soft outline, "shape:<key>",
-- and the red flash, which covers the icon itself, its filled silhouette:
-- rectangle styles would stand off the outline.
local function DrawnGlowStyle(gtype, rec)
    local key = rec and (Factory.MaskOf(rec) or Factory.SkinGlowShape(rec))
    if key then
        return ((gtype == "redflash" or gtype == "barattack") and "shapefill:" or "shape:") .. key
    end
    if not GLOW_STYLES_KNOWN[gtype] then return "button" end
    if gtype == "ants" and not AtlasOK(ANTS_ATLAS) then return "button" end
    if gtype == "flash" and not AtlasOK(FLASH_ATLAS) then return "button" end
    if gtype == "pandemic" and not AtlasOK(PANDEMIC_BORDER) then return "button" end
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
    for _, k in ipairs({ "_adBtn", "_adProc", "_adAnts", "_adFlash", "_adRedFlash", "_adShape", "_adShapeFill",
        "_adBarCheck", "_adBarRed", "_adPand" }) do
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
    if keep ~= "pixel" and host._adPixBack then
        for _, t in ipairs(host._adPixBack) do t:Hide() end
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
    if keep ~= "redflash" and host._adRedFlash then
        host._adRedFlash.ag:Stop()
        host._adRedFlash:Hide()
    end
    if keep ~= "shape" and host._adShape then
        host._adShape.ag:Stop()
        host._adShape:Hide()
    end
    if keep ~= "barcheck" and keep ~= "barattack" and host._adBarCheck then
        host._adBarCheck:Hide()
    end
    if keep ~= "barattack" and host._adBarRed then
        host._adBarRed.ag:Stop()
        host._adBarRed:Hide()
    end
    if keep ~= "pandemic" and host._adPand then
        host._adPand.ag:Stop()
        host._adPand:Hide()
    end
    if keep ~= "shapefill" and host._adShapeFill then
        host._adShapeFill.ag:Stop()
        host._adShapeFill:Hide()
    end
end

-- "shape:circle" -> "shape", "circle"; any other style alone
local function ShapeStyle(gtype)
    local st, key = string.match(gtype or "", "^(%a+):(%a+)$")
    if st then return st, key end
    return gtype, nil
end
Factory.ShapeStyle = ShapeStyle

-- Pixel: n dashes around a W x H rect, th thick, a lap per period seconds;
-- len = dash length in pixels (0 or nil = automatic), met by the nearest band.
-- back = { w, a }: a dark backing ring w wide under the dashes, or nil.
local function GlowPixel(host, W, H, n, th, period, r, g, bl, a, len, back)
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
    -- top and bottom span the width and the sides fill between, so no corner
    -- is darkened twice
    local bk = host._adPixBack
    if back then
        if not bk then
            bk = {}
            for i = 1, 4 do
                local t = host:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetColorTexture(0.1, 0.1, 0.1, 1)
                bk[i] = t
            end
            host._adPixBack = bk
        end
        local b = math.min(back.w, W / 2, H / 2)
        local side = math.max(0, H - 2 * b)
        for i, t in ipairs(bk) do
            t:ClearAllPoints()
            if i == 1 then
                t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
                t:SetSize(W, b)
            elseif i == 2 then
                t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
                t:SetSize(W, b)
            elseif i == 3 then
                t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -b)
                t:SetSize(b, side)
            else
                t:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -b)
                t:SetSize(b, side)
            end
            t:SetAlpha(back.a or 0.8)
            if side > 0 or i < 3 then t:Show() else t:Hide() end
        end
    elseif bk then
        for _, t in ipairs(bk) do t:Hide() end
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

-- The two perimeter styles, for the bar glows (Bars\AD_BarGlow.lua): the same
-- builders on another host, so both draw alike.
Factory.GlowArt = { pixel = GlowPixel, autocast = GlowSparkle, hide = HideGlowParts }

-- Button: the button glow at rest, its outer ring and ants on a
-- (1.4 w + 2 xo) x (1.4 h + 2 yo) frame, as the cooldown lanes lay it.
-- Desaturated so the colour tints the gold art.
local function GlowButton(host, fw, fh, r, g, bl, a, speed, native)
    local bt = host._adBtn
    if not bt then
        bt = CreateFrame("Frame", nil, host, host._adOptIn)
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
    -- the game's own colour keeps the gold art as it is
    if bt.outer.SetDesaturated then bt.outer:SetDesaturated(not native) end
    if bt.ants.SetDesaturated then bt.ants:SetDesaturated(not native) end
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
local function GlowProc(host, fw, fh, r, g, bl, a, native)
    local pr = host._adProc
    if not pr then
        pr = CreateFrame("Frame", nil, host, host._adOptIn)
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
    if pr.loop.SetDesaturated then pr.loop:SetDesaturated(not native) end
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
        at = CreateFrame("Frame", nil, host, host._adOptIn)
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
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
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

-- The action bar's red flash over the icon itself, on and off every
-- 0.1 / speed seconds: 0.4 at the default speed, the bars' own pace.
local function GlowRedFlash(host, fw, fh, r, g, bl, a, speed)
    local fl = host._adRedFlash
    if not fl then
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 7)
        if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and AtlasOK(RED_FLASH_ATLAS) then
            fl.tex:SetAtlas(RED_FLASH_ATLAS)
        else
            fl.tex:SetTexture(RED_FLASH_FILE)
        end
        fl.tex:SetAllPoints(fl)
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        fl.on = ag:CreateAnimation("Alpha")
        fl.on:SetFromAlpha(1)
        fl.on:SetToAlpha(1)
        fl.on:SetOrder(1)
        fl.off = ag:CreateAnimation("Alpha")
        fl.off:SetFromAlpha(0)
        fl.off:SetToAlpha(0)
        fl.off:SetOrder(2)
        fl.ag = ag
        host._adRedFlash = fl
    end
    fl.ag:Stop()
    fl:SetSize(fw, fh)
    fl.tex:SetVertexColor(r, g, bl, a)
    local t = 0.1 / math.max(0.05, speed or 0.25)
    if t < 0.05 then t = 0.05 elseif t > 5 then t = 5 end
    fl.on:SetDuration(t)
    fl.off:SetDuration(t)
    fl:Show()
    fl.ag:Play()
end

-- The bars' gold frame while a button is on, steady; fw x fh = the icon's box.
local function GlowBarCheck(host, fw, fh, r, g, bl, a)
    local fl = host._adBarCheck
    if not fl then
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 6)
        if AtlasOK(BAR_CHECK_ATLAS) then
            fl.tex:SetAtlas(BAR_CHECK_ATLAS)
        else
            fl.tex:SetTexture(BAR_CHECK_FILE)
        end
        fl.tex:SetBlendMode("ADD")
        fl.tex:SetAllPoints(fl)
        host._adBarCheck = fl
    end
    fl:SetSize(fw * BAR_W, fh)
    fl.tex:SetVertexColor(r, g, bl, a)
    fl:Show()
end

-- Attack and Auto Shot on the bars: the gold frame, and the red frame over it
-- shown and hidden every 0.4 s (the bars' fixed pace).
local function GlowBarAttack(host, fw, fh, r, g, bl, a)
    GlowBarCheck(host, fw, fh, r, g, bl, a)
    local fl = host._adBarRed
    if not fl then
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 7)
        if AtlasOK(RED_FLASH_ATLAS) then
            fl.tex:SetAtlas(RED_FLASH_ATLAS)
        else
            fl.tex:SetTexture(RED_FLASH_FILE)
        end
        fl.tex:SetAllPoints(fl)
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        fl.on = ag:CreateAnimation("Alpha")
        fl.on:SetFromAlpha(1)
        fl.on:SetToAlpha(1)
        fl.on:SetDuration(BAR_BLINK)
        fl.on:SetOrder(1)
        fl.off = ag:CreateAnimation("Alpha")
        fl.off:SetFromAlpha(0)
        fl.off:SetToAlpha(0)
        fl.off:SetDuration(BAR_BLINK)
        fl.off:SetOrder(2)
        fl.ag = ag
        host._adBarRed = fl
    end
    fl.ag:Stop()
    fl:SetSize(fw * BAR_W, fh)
    fl.tex:SetVertexColor(r, g, bl, a)
    fl:Show()
    fl.ag:Play()
end

-- Pandemic border: the Cooldown Manager's pandemic art on the fw x fh box,
-- its three sparks swelling through the border's mask in turn, as the game's
-- loop runs them. Tinted like the others, or untinted (native).
local function GlowPandemic(host, fw, fh, r, g, bl, a, native)
    local pd = host._adPand
    if not pd then
        pd = CreateFrame("Frame", nil, host, host._adOptIn)
        pd:SetPoint("CENTER", host, "CENTER", 0, 0)
        pd.border = pd:CreateTexture(nil, "OVERLAY", nil, 6)
        pd.border:SetAtlas(PANDEMIC_BORDER)
        pd.border:SetAllPoints(pd)
        pd.fx = CreateFrame("Frame", nil, pd, host._adOptIn)
        pd.fx:SetAllPoints(pd)
        pd.mask = pd.fx:CreateMaskTexture()
        pd.mask:SetAtlas(PANDEMIC_MASK, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pd.mask:SetAllPoints(pd.fx)
        pd.sparks = {}
        local ag = pd.fx:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        for i, atlas in ipairs(PANDEMIC_FX) do
            local t = pd.fx:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetAtlas(atlas)
            t:SetAllPoints(pd.fx)
            t:AddMaskTexture(pd.mask)
            t:SetAlpha(0)
            pd.sparks[i] = t
            local d0 = (i - 1) * 1.5
            local sc = ag:CreateAnimation("Scale")
            sc:SetTarget(t)
            sc:SetScaleFrom(0.25, 0.25)
            sc:SetScaleTo(1.5, 1.5)
            sc:SetDuration(2)
            sc:SetStartDelay(d0)
            sc:SetSmoothing("IN_OUT")
            sc:SetOrder(1)
            for _, step in ipairs({ { 0, 1, 0.5, 0 }, { 1, 1, 1, 0.5 }, { 1, 0, 0.5, 1.5 } }) do
                local al = ag:CreateAnimation("Alpha")
                al:SetTarget(t)
                al:SetFromAlpha(step[1])
                al:SetToAlpha(step[2])
                al:SetDuration(step[3])
                al:SetStartDelay(d0 + step[4])
                al:SetSmoothing("IN_OUT")
                al:SetOrder(1)
            end
        end
        pd.ag = ag
        host._adPand = pd
    end
    pd.ag:Stop()
    pd:SetSize(fw, fh)
    local tint = not native
    local cr, cg, cb = r, g, bl
    if native then cr, cg, cb = 1, 1, 1 end
    pd.border:SetDesaturated(tint)
    pd.border:SetVertexColor(cr, cg, cb, a)
    for _, t in ipairs(pd.sparks) do
        t:SetDesaturated(tint)
        t:SetVertexColor(cr, cg, cb, 1)
    end
    -- the sparks' alpha is the loop's; the intensity rides their frame
    pd.fx:SetAlpha(a)
    pd:Show()
    pd.ag:Play()
end

-- A shaped icon's glow: the shape's halo, added light, pulsing 40% to 100% at
-- the flash's pace. fw, fh = the halo's box (the icon times SHAPE_HALO).
local function GlowShape(host, fw, fh, r, g, bl, a, speed, key)
    local fl = host._adShape
    if not fl then
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 7)
        fl.tex:SetBlendMode("ADD")
        fl.tex:SetAllPoints(fl)
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        fl.up = ag:CreateAnimation("Alpha")
        fl.up:SetFromAlpha(0.4)
        fl.up:SetToAlpha(1)
        fl.up:SetOrder(1)
        if fl.up.SetSmoothing then fl.up:SetSmoothing("IN_OUT") end
        fl.down = ag:CreateAnimation("Alpha")
        fl.down:SetFromAlpha(1)
        fl.down:SetToAlpha(0.4)
        fl.down:SetOrder(2)
        if fl.down.SetSmoothing then fl.down:SetSmoothing("IN_OUT") end
        fl.ag = ag
        host._adShape = fl
    end
    fl.ag:Stop()
    if fl._adKey ~= key then
        fl.tex:SetTexture(Factory.ShapeFile(key, "Halo"))
        fl._adKey = key
    end
    fl:SetSize(fw, fh)
    fl.tex:SetVertexColor(r, g, bl, a)
    local half = 0.125 / math.max(0.05, speed or 0.25)
    if half < 0.05 then half = 0.05 elseif half > 5 then half = 5 end
    fl.up:SetDuration(half)
    fl.down:SetDuration(half)
    fl:Show()
    fl.ag:Play()
end

-- The red flash on a shaped icon: its filled silhouette in the red art's
-- shade (times the glow colour, as the art is), on and off at its pace.
local SHAPE_FILL_TINT = { 1, 0.12, 0.12, 0.55 }
local function GlowShapeFill(host, fw, fh, r, g, bl, a, speed, key)
    local fl = host._adShapeFill
    if not fl then
        fl = CreateFrame("Frame", nil, host, host._adOptIn)
        fl:SetPoint("CENTER", host, "CENTER", 0, 0)
        fl.tex = fl:CreateTexture(nil, "OVERLAY", nil, 7)
        fl.tex:SetAllPoints(fl)
        local ag = fl:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        fl.on = ag:CreateAnimation("Alpha")
        fl.on:SetFromAlpha(1)
        fl.on:SetToAlpha(1)
        fl.on:SetOrder(1)
        fl.off = ag:CreateAnimation("Alpha")
        fl.off:SetFromAlpha(0)
        fl.off:SetToAlpha(0)
        fl.off:SetOrder(2)
        fl.ag = ag
        host._adShapeFill = fl
    end
    fl.ag:Stop()
    if fl._adKey ~= key then
        fl.tex:SetTexture(Factory.ShapeFile(key, "Mask"))
        fl._adKey = key
    end
    fl:SetSize(fw, fh)
    local k = SHAPE_FILL_TINT
    fl.tex:SetVertexColor(r * k[1], g * k[2], bl * k[3], a * k[4])
    local t = 0.1 / math.max(0.05, speed or 0.25)
    if t < 0.05 then t = 0.05 elseif t > 5 then t = 5 end
    fl.on:SetDuration(t)
    fl.off:SetDuration(t)
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
    for _, t in ipairs(host._adPixBack or {}) do out[#out + 1] = { t, host } end
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
    local rf = host._adRedFlash
    if rf then out[#out + 1] = { rf.tex, rf } end
    local sh = host._adShape
    if sh then out[#out + 1] = { sh.tex, sh } end
    local sf = host._adShapeFill
    if sf then out[#out + 1] = { sf.tex, sf } end
    local bc = host._adBarCheck
    if bc then out[#out + 1] = { bc.tex, bc } end
    local br = host._adBarRed
    if br then out[#out + 1] = { br.tex, br } end
    local pd = host._adPand
    if pd then
        out[#out + 1] = { pd.border, pd }
        for _, t in ipairs(pd.sparks) do out[#out + 1] = { t, pd.fx } end
    end
    return out
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
        end
        -- bound again after the show gate held the button's one duration bar
        if b._adBarOn ~= gb then
            b._adBarOn = gb
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
-- under the live button), else the glow's own level over b; cap = a lane's
-- icon shows only under this share of time left. Accessible passes only.
function Factory.SetAuraButtonGlow(b, rec, on, w, h, alphaMul, slot, levelTo, cap)
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
    local gtype = DrawnGlowStyle(R("auraActive", "activeGlowType") or "button", rec)
    local c = R("auraActive", "activeGlowColor") or { 0.95, 0.95, 0.32, 1 }
    -- the game's own colour: the gold art untinted, the intensity its alpha
    local Sch = NS.Schema
    local native = Sch ~= nil and Sch.GLOW_NATIVE_STYLES[gtype] == true and R("auraActive", "activeGlowNative") == true
    local backing = gtype == "pixel" and R("auraActive", "activeGlowBacking") == true
    local a = (native and 1 or (c[4] or 1)) * (R("auraActive", "activeGlowIntensity") or 1) * (alphaMul or 1)
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
    -- no sooner than the icon shows (the editor shows it the whole time)
    local LE = NS.LayoutEngine
    if cap and not (LE ~= nil and LE.IsEditMode ~= nil and LE.IsEditMode() == true) then
        frac = math.min(frac or 1, cap)
    end
    -- the level the button's stack counts from (ButtonBase)
    local base = ButtonBase(b)
    local sig = table.concat({ gtype, w, h, c[1], c[2], c[3], a, speed, xo, yo,
        lines, th, parts, scale, lvl, strata, base or -1,
        frac or -1, dash, mx, my, levelTo or -1, native and 1 or 0, backing and 1 or 0 }, ":")
    if not host then
        -- b._adOptIn: a template b was made with (a Dynamic row's stage), which
        -- every frame anchored to it needs too
        host = CreateFrame("Frame", nil, b, b._adOptIn)
        host._adOptIn = b._adOptIn
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
        -- template's 66/45 box, the red flash the icon itself, offsets
        -- expanding any
        host:SetPoint("CENTER", b, "CENTER", mx, my)
        host:SetSize(w, h)
        local k = (gtype == "ants" or gtype == "flash") and BLIZZ_RATIO or 1.4
        if gtype == "redflash" then k = 1 end
        -- a shaped icon's outline lays its halo box, its fill the icon itself
        local st = ShapeStyle(gtype)
        if st == "shape" then k = Factory.SHAPE_HALO elseif st == "shapefill" then k = 1 end
        -- the bars' frames sit on the icon's own box
        if gtype == "barcheck" or gtype == "barattack" then k = 1 end
        -- a button or proc glow's size grows its box
        if gtype == "button" or gtype == "proc" or gtype == "procloop" then
            k = k * math.min(2, math.max(0.5, tonumber(scale) or 1))
        end
        W, H = w * k + 2 * xo, h * k + 2 * yo
        if gtype == "pandemic" then
            local grow = math.min(w, h) * Factory.PANDEMIC_GROW
            W, H = w + 2 * grow + 2 * xo, h + 2 * grow + 2 * yo
        end
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
    local style, shape = ShapeStyle(gtype)
    HideGlowParts(host, style)
    local r, g, bl = c[1], c[2], c[3]
    if native then r, g, bl = 1, 1, 1 end
    if style == "shape" then
        GlowShape(host, W, H, r, g, bl, a, speed, shape)
    elseif style == "shapefill" then
        GlowShapeFill(host, W, H, r, g, bl, a, speed, shape)
    elseif gtype == "barcheck" then
        GlowBarCheck(host, W, H, r, g, bl, a)
    elseif gtype == "barattack" then
        GlowBarAttack(host, W, H, r, g, bl, a)
    elseif gtype == "pixel" then
        -- Whole physical pixels; the buttons scale with UIParent.
        local tpx, bpx = th, th + 1
        if PixelUtil and PixelUtil.GetNearestPixelSize then
            tpx = PixelUtil.GetNearestPixelSize(th, UIParent:GetEffectiveScale(), 1)
            bpx = tpx + PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
        end
        -- the backing dims with the aura's opacity, as the cooldown lanes' does with the icon
        GlowPixel(host, W, H, lines, tpx, 1 / speed, r, g, bl, a, dash,
            backing and { w = bpx, a = 0.8 * (alphaMul or 1) } or nil)
    elseif gtype == "autocast" then
        GlowSparkle(host, W, H, parts, scale, 1 / speed, r, g, bl, a)
    elseif gtype == "proc" or gtype == "procloop" then
        GlowProc(host, W, H, r, g, bl, a, native)
    elseif gtype == "ants" then
        GlowAnts(host, W, H, r, g, bl, a)
    elseif gtype == "flash" then
        GlowFlash(host, W, H, r, g, bl, a, speed)
    elseif gtype == "redflash" then
        GlowRedFlash(host, W, H, r, g, bl, a, speed)
    elseif gtype == "pandemic" then
        GlowPandemic(host, W, H, r, g, bl, a, native)
    else
        GlowButton(host, W, H, r, g, bl, a, speed, native)
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
    if Store.Resolve(rec, "auraActive", "activeGlow" .. suf) ~= true then return false end
    local when = Store.Resolve(rec, "auraActive", "activeGlowWhen" .. suf)
    -- under the time gate an Always glow is this half and a lane's
    return when == "missing" or (when == "both" and Factory.TimeGateFrac(rec) ~= nil)
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
        and Factory.TimeGateFrac(rec) == nil
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
        if Factory.LabelWithMissing(rec, suf) and t ~= nil and t ~= "" then
            return true
        end
    end
    return false
end

-- Pixels past the icon the texts `pick` takes can reach (offsets plus a generous width).
local function LabelReach(rec, kS, pick)
    local reach = 0
    for _, suf in ipairs({ "", "2", "3" }) do
        local t = Store.Resolve(rec, "label", "labelText" .. suf)
        if pick(rec, suf) and t ~= nil and t ~= "" then
            local size = (Store.Resolve(rec, "label", "labelSize" .. suf) or 12) * kS
            local x = math.abs(Store.Resolve(rec, "label", "labelX" .. suf) or 0) * kS
            local y = math.abs(Store.Resolve(rec, "label", "labelY" .. suf) or 0) * kS
            reach = math.max(reach, math.max(x, y) + math.max(#t * size * 0.7, size))
        end
    end
    return reach
end

-- Pixels past the icon those texts can reach.
function Factory.MissingTextReach(rec, kS)
    if not Factory.HasMissingText(rec) then return 0 end
    return math.ceil(LabelReach(rec, kS or 1, Factory.LabelWithMissing))
end

-- Pixels past the icon the live button's texts can reach: its labels, the
-- countdown and the stack count.
function Factory.LiveTextReach(rec, kS)
    kS = kS or 1
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local reach = LabelReach(rec, kS, Factory.LabelOnButton)
    for _, t in ipairs({ { "duration", 5 }, { "stack", 3 } }) do
        local p = t[1]
        local off = math.max(math.abs(R("text", p .. "X") or 0), math.abs(R("text", p .. "Y") or 0))
        reach = math.max(reach, (off + t[2] * (R("text", p .. "Size") or 14) * 0.7) * kS)
    end
    return math.ceil(reach)
end

-- Always glows: on the holder itself, never on the stage, so they show in both states.
function Factory.ApplyAlwaysGlows(f, rec, w, h, combat)
    local host = f._adAlwaysGlow
    local D = NS.DriverAura
    local ok = rec ~= nil and rec.kind == "aura" and D ~= nil and D.HolderGlowOK ~= nil
        and D.HolderGlowOK(rec) and Store.Resolve(rec, "appearance", "forceHideIcon") ~= true
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
            -- the live button's own glow level (your button's on a two-unit
            -- icon): over its art, under its texts and the holder's
            host._adLevel = lvl and (lvl + Factory.AURA_LADDER.button + Factory.Rise(rec))
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
        opts.w or px, opts.h or px, aA, slot, nil, opts.glowCap)
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
                    -- Under the time gate both copies carry every label.
                    st.fs:SetShown(not st.missingOnly and not (st.activeOnly and onCooldown)
                        and not st.split)
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
        Factory.BorderGrey(f, rec, desat)
        -- the missing look's own tint; the vertex alpha carries the dim
        local va = f._adShownAlpha or a
        local mt = onCooldown and R("auraMissing", "missingTintEnabled") == true
            and (R("auraMissing", "missingTintColor") or { 0.5, 0.5, 0.5, 1 }) or nil
        if mt then
            f.icon:SetVertexColor(mt[1], mt[2], mt[3], va)
        else
            f.icon:SetVertexColor(1, 1, 1, va)
        end
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
    -- Recharging: a charge spell with a charge left and another on its way
    -- (the driver's flag). Castable: ready, or recharging with that charge.
    local recharging = f._adRecharging == true
    local castable = not onCooldown or recharging
    -- the usability looks: while it can be cast, or only while ready when they wait for it
    local usabOK = castable
    if recharging and R("states", "usabilityReadyOnly") == true then usabOK = false end
    -- "always" / "ready" / "cooldown": which state a rule covers (recharging is on cooldown)
    local function StateWhen(v)
        if v == "ready" then return not onCooldown end
        if v == "cooldown" then return onCooldown and true or false end
        return true
    end
    local procLift = f._adProcLit and R("states", "procOverride") == true
        and StateWhen(R("states", "procOverrideWhen"))
    local keepText = R("states", "preserveDurationText") ~= false and StateWhen(R("states", "preserveTextWhen"))
    if keepBright then
        f._adStateAlpha = 1
    else
        if recharging then
            -- a look of its own, neither Ready's nor Depleted's
            f._adStateAlpha = R("states", "rechargeAlpha") or 1
        elseif onCooldown then
            f._adStateAlpha = R("states", "cooldownAlpha") or 1
        else
            f._adStateAlpha = R("states", "readyAlpha") or 1
        end
        -- Usability dim: an unusable, no-resource or out-of-range castable
        -- spell takes the lower of the two alphas (out of range at full by
        -- default), or can't use and no resource set it outright.
        local ucode = usabOK and f._adUsability or nil
        local replace = R("states", "usabilityAlphaReplaces") == true
        if ucode == "unusable" then
            local ua = R("states", "unusableAlpha") or 1
            f._adStateAlpha = replace and ua or math.min(f._adStateAlpha, ua)
        elseif ucode == "nomana" then
            local ra = R("states", "resourceAlpha") or 1
            f._adStateAlpha = replace and ra or math.min(f._adStateAlpha, ra)
        elseif ucode == "range" then
            f._adStateAlpha = math.min(f._adStateAlpha, R("states", "rangeAlpha") or 1)
        end
    end
    -- Toggled on (Shoot, Auto Shot, Attack, pet autocast: Drivers\AD_DriverToggle.lua) has its own alpha.
    if f._adToggled and not keepBright and R("states", "toggleAlphaEnabled") == true then
        f._adStateAlpha = R("states", "toggleAlpha") or 1
    end
    -- A group buff in combat: nobody's buffs can be read, so its count and
    -- icon step aside (its driver's layers show instead, when switched on).
    if rec.kind == "groupbuff" and f._adGBHidden then f._adStateAlpha = 0 end
    -- A weapon enchant whose hand holds no weapon: its No weapon state.
    if rec.kind == "enchant" and f._adNoWeapon then f._adStateAlpha = R("states", "noWeaponAlpha") or 0 end
    -- procOverride: a lit proc forces full opacity, over the usability dim too.
    if procLift then
        f._adStateAlpha = 1
    end
    -- usableOverride: full opacity while ready and usable (range is usable,
    -- unless out of range has a dim of its own).
    if not onCooldown and R("states", "usableOverride") == true
        and (f._adUsability == nil or (f._adUsability == "range"
            and (R("states", "rangeAlpha") or 1) >= 1)) then
        f._adStateAlpha = 1
    end
    -- On cooldown's opacity waiting for the last seconds: only On cooldown's
    -- own value (no toggle or proc took over), and only with the cooldown's
    -- duration object (the driver's, or the preview's fake one). The plain
    -- value is the brighter of the two, for packing and the glows.
    local T
    local cdA = R("states", "cooldownAlpha") or 1
    if rec.kind == "spell" and onCooldown and not recharging and not keepBright
        and f._adTimedDur ~= nil
        and not (f._adToggled and R("states", "toggleAlphaEnabled") == true)
        and not procLift
        and R("states", "cooldownAlphaTimed") == true
        and C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil then
        local before = R("states", "cooldownAlphaBefore") or 0
        if before < 0 then before = 0 elseif before > 1 then before = 1 end
        local late, early = EditFloor(cdA), EditFloor(before)
        T = { sec = R("states", "cooldownAlphaSec") or 3, late = late, before = early,
            tLate = (late > 0 and keepText) and 1 or late, tBefore = (early > 0 and keepText) and 1 or early }
        f._adStateAlpha = math.max(cdA, before)
    end
    SetTimed(f, T)
    -- preserveDurationText (on by default) keeps the texts out of the dim.
    f._adLabelsBright = R("states", "labelsFullOpacity") == true
    ApplyStateAlpha(f, f._adStateAlpha, keepText)
    local desatOK = not keepBright or R("appearance", "keepBrightAllowDesat") == true
    f.icon:SetDesaturated(desatOK and f._adDesatState
        and R("states", "cooldownDesaturate") == true or false)
    -- The ready look (a Custom Icon's Active) has its own grey out; a
    -- recharging spell has its own, below.
    if desatOK and not onCooldown and R("states", "readyDesaturate") == true
        and not (R("states", "readyGreyUsable") == true and f._adUsability ~= nil) then
        f.icon:SetDesaturated(true)
    end
    -- Grey only while usable holds Recharging's grey back the same way
    if desatOK and recharging and R("states", "rechargeDesaturate") == true
        and not (R("states", "readyGreyUsable") == true and f._adUsability ~= nil) then
        f.icon:SetDesaturated(true)
    end
    -- No-resource, unusable or out of range can grey a castable icon apart from the cooldown desat.
    if usabOK and desatOK then
        local ucode = f._adUsability
        if (ucode == "nomana" and R("states", "resourceDesaturate") == true)
            or (ucode == "unusable" and R("states", "unusableDesaturate") == true)
            or (ucode == "range" and R("states", "rangeDesaturate") == true) then
            f.icon:SetDesaturated(true)
        end
    end
    if desatOK and f._adToggled and R("states", "toggleDesaturate") == true then
        f.icon:SetDesaturated(true)
    end
    -- "Desaturate while the aura is down" with an aura overlay: the art stays
    -- grey under the aura's button, so it reads grey exactly while the aura is
    -- down, with no presence read. Wins over every other desaturation.
    if R("auraActive", "overlayDesatInactive") == true and NS.DriverAura
        and NS.DriverAura.OverlayOn and NS.DriverAura.OverlayOn(rec) then
        f.icon:SetDesaturated(true)
    end
    -- Tint priority, as Blizzard's: range red, usability, state tints, white.
    -- The usability tints show while it can be cast (a charge left counts),
    -- or on a cooling spell too as the game's buttons do.
    local tc
    local code = usabOK and f._adUsability or nil
    if code == nil and onCooldown and R("states", "usabilityOnCooldown") == true then code = f._adUsability end
    if code == "range" and R("states", "rangeTint") ~= false then
        tc = R("states", "rangeTintColor") or { 0.85, 0.2, 0.2, 1 }
    elseif code == "nomana" and f._adToggled and R("states", "queueShort") == true
        and NS.DriverToggle ~= nil and NS.DriverToggle.Kind(rec) == "queue" then
        -- queued without the cost: this swing lands plain
        tc = R("states", "queueShortColor") or { 1, 0.1, 0.1, 1 }
    elseif code == "nomana" and R("states", "resourceTintEnabled") ~= false then
        tc = R("states", "resourceTintColor") or { 0.35, 0.45, 1, 1 }
    elseif code == "unusable" and R("states", "unusableTintEnabled") ~= false then
        tc = R("states", "unusableTintColor") or { 0.45, 0.45, 0.45, 1 }
    elseif castable and f._adToggled and R("states", "toggleTintEnabled") == true then
        tc = R("states", "toggleTintColor") or { 1, 0.35, 0.35, 1 }
    elseif recharging then
        -- its own tint or none: never Ready's or Depleted's
        if R("states", "rechargeTintEnabled") == true then
            tc = R("states", "rechargeTintColor") or { 1, 0.85, 0.4, 1 }
        end
    elseif not onCooldown then
        if R("states", "readyTintEnabled") == true then tc = R("states", "readyTintColor") end
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
    Factory.RangeShadow(f, rec, f._adUsability == "range", va)
    if T then
        T.tint = tc
        TimedPaint(f)
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
            ApplyStateAlpha(f, R("outOfStock", "outAlpha") or 0.4, keepText)
        end
        if R("outOfStock", "outTintEnabled") == true then
            local oc = R("outOfStock", "outTintColor") or { 0.5, 0.5, 0.5, 1 }
            f.icon:SetVertexColor(oc[1], oc[2], oc[3], f._adShownAlpha or f._adStateAlpha or 1)
        end
    end
    -- Dynamic groups re-place from here, so every icon kind moves them. Fired
    -- when a drop-out input flips (busy, state alpha 0, hidden while missing),
    -- for recorded icons only: the preview's fake cooldown must not wake them.
    if f._adRecId then
        local sig = (f._adOnCooldown and 1 or 0)
            + (((f._adStateAlpha or 1) <= 0) and 2 or 0)
            + (Factory.StockHidden(f, rec) and 4 or 0)
            + (f._adPassive and 8 or 0)
        if f._adDynSig ~= sig then
            f._adDynSig = sig
            NS.Events.Fire("AD_DYNEDGE")
        end
    end
    Factory.UpdateGlow(f, rec, not onCooldown)
    Factory.UpdateUsableGlow(f, rec)
    Factory.UpdateCooldownGlow(f, rec)
    Factory.UpdateRangeGlow(f, rec)
    Factory.UpdateRechargeGlow(f, rec)
    if f._adProcLit ~= nil then Factory.SetProcGlow(f, rec, f._adProcLit) end
    -- the border follows the art's final grey (our own texture: a plain read)
    Factory.BorderGrey(f, rec, f.icon.IsDesaturated ~= nil and f.icon:IsDesaturated() == true)
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
-- flashes the icon size their box is baked from (library frames follow anchors).
local function LaneExt(f, gtype, len, mx, my)
    local s = (len or 0) .. ":" .. (mx or 0) .. ":" .. (my or 0)
    if gtype == "ants" or gtype == "flash" or gtype == "redflash" or gtype == "barcheck" or gtype == "barattack"
        or gtype == "pandemic" or ShapeStyle(gtype) ~= gtype then
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
-- StartLane so each offers every style. Ants and the flashes are our own
-- builders on a per-lane host (TexLaneStart), which every stop takes down too.
local function StopLane(f, key)
    local tg = f["_adTexGlow" .. key]
    if tg then
        HideGlowParts(tg, nil)
        tg:Hide()
    end
    local LCG = GetLCG()
    if not LCG then return end
    -- a sized button or proc glow goes back to the library's shared pool unscaled
    for _, fld in ipairs({ "_ButtonGlow", "_ProcGlow" }) do
        local g = f[fld .. key]
        if g and g.SetScale then g:SetScale(1) end
    end
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

-- A state at 0 opacity hides the icon, and its glows with it: they ride the
-- frame, which the state's dim never touches (SetState re-runs them after it).
function Factory.GlowHidden(f)
    return (f._adShownAlpha or f._adStateAlpha or 1) <= 0
end

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

-- Ants and the flashes on a cooldown lane: the aura-button builders on a
-- per-lane host at the lane's level and strata; the icon is ours, so groups
-- just play.
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
    local style, shape = ShapeStyle(gtype)
    HideGlowParts(host, style)
    -- the red flash covers the icon itself, the others their template's box;
    -- a shaped outline its halo's, a shaped fill the icon
    local k = (gtype == "redflash" or gtype == "barcheck" or gtype == "barattack") and 1 or BLIZZ_RATIO
    if style == "shape" then k = Factory.SHAPE_HALO elseif style == "shapefill" then k = 1 end
    local W = math.max(1, w * k + 2 * (p.xo or 0))
    local H = math.max(1, h * k + 2 * (p.yo or 0))
    if gtype == "pandemic" then
        local grow = math.min(w, h) * Factory.PANDEMIC_GROW
        W, H = math.max(1, w + 2 * grow + 2 * (p.xo or 0)), math.max(1, h + 2 * grow + 2 * (p.yo or 0))
    end
    local c = p.color
    if gtype == "pandemic" then
        GlowPandemic(host, W, H, c[1], c[2], c[3], p.native and (p.inten or 1) or (c[4] or 1), p.native)
    elseif style == "shape" then
        GlowShape(host, W, H, c[1], c[2], c[3], c[4] or 1, p.speed, shape)
    elseif style == "shapefill" then
        GlowShapeFill(host, W, H, c[1], c[2], c[3], c[4] or 1, p.speed, shape)
    elseif gtype == "barcheck" then
        GlowBarCheck(host, W, H, c[1], c[2], c[3], c[4] or 1)
    elseif gtype == "barattack" then
        GlowBarAttack(host, W, H, c[1], c[2], c[3], c[4] or 1)
    elseif gtype == "ants" then
        GlowAnts(host, W, H, c[1], c[2], c[3], c[4] or 1)
    elseif gtype == "redflash" then
        GlowRedFlash(host, W, H, c[1], c[2], c[3], c[4] or 1, p.speed)
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
    local style = ShapeStyle(gtype)
    if gtype == "ants" or gtype == "flash" or gtype == "redflash" or gtype == "barcheck" or gtype == "barattack"
        or gtype == "pandemic" or style == "shape" or style == "shapefill" then
        TexLaneStart(f, key, gtype, p)
        return
    end
    local LCG = GetLCG()
    if not LCG then return end
    local lvl = p.level or GLOW_LEVEL
    -- the game's own colour: no colour handed in, so the gold art stays untinted
    local color = p.color
    if p.native then color = nil end
    if gtype == "pixel" then
        -- the dash length: 0 = the library's automatic length
        local len = (type(p.length) == "number" and p.length > 0) and p.length or nil
        LCG.PixelGlow_Start(f, p.color, p.lines, p.speed, len, p.thickness,
            p.xo, p.yo, p.border == true, key, lvl)
    elseif gtype == "autocast" then
        LCG.AutoCastGlow_Start(f, p.color, p.particles, p.speed, p.scale,
            p.xo, p.yo, key, lvl)
    elseif (gtype == "proc" or gtype == "procloop") and LCG.ProcGlow_Start then
        -- procloop = the proc glow without its opening burst
        LCG.ProcGlow_Start(f, { color = color, key = key,
            frameLevel = lvl, xOffset = p.xo, yOffset = p.yo,
            startAnim = gtype == "proc" })
    else
        LCG.ButtonGlow_Start(f, color, p.speed, lvl, key, p.xo, p.yo)
        gtype = "button"
    end
    ApplyStrata(f, key, p.strata)
    local g = f[LCG_FIELD[gtype] .. key]
    -- untinted art has no colour alpha to carry the intensity, so it dims the
    -- frame; any other start returns a recycled frame to full
    if g and g.SetAlpha then g:SetAlpha(p.native and (p.inten or 1) or 1) end
    -- a button or proc glow's size scales it whole (set on every start: the
    -- library's frames are pooled); its move stays in the icon's units, as a
    -- scaled frame's offsets scale with it
    local sc = 1
    if g and g.SetScale and (gtype == "button" or gtype == "proc" or gtype == "procloop") then
        sc = tonumber(p.scale) or 1
        if sc < 0.5 then sc = 0.5 elseif sc > 2 then sc = 2 end
        g:SetScale(sc)
    end
    ShiftGlow(g, (p.mx or 0) / sc, (p.my or 0) / sc)
end
-- Any frame of ours can wear a lane under its own key (the Reminder group's
-- pulses: Drivers\AD_DriverReminders.lua), every style included.
Factory.StartGlowLane = StartLane
Factory.StopGlowLane = StopLane

-- A lane's look switches into its recipe p: the game's own colour on a button
-- or proc glow, and the pixel glow's dark backing line. inten = the lane's
-- intensity (the untinted art's frame alpha). Returns the signature part.
local function LaneLook(rec, sec, glowPrefix, gtype, p, inten)
    local Sch = NS.Schema
    p.native = Sch ~= nil and Sch.GLOW_NATIVE_STYLES[gtype] == true
        and Store.Resolve(rec, sec, glowPrefix .. "Native") == true
    p.border = gtype == "pixel" and Store.Resolve(rec, sec, glowPrefix .. "Backing") == true
    p.inten = inten or 1
    return (p.native and (":n" .. p.inten) or "") .. (p.border and ":b" or "")
end
Factory.LaneLook = LaneLook

-- Proc glow (SPELL_ACTIVATION_OVERLAY), with the other lanes' options.
function Factory.SetProcGlow(f, rec, on)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    on = on and true or false
    local changed = (f._adProcLit or false) ~= on
    f._adProcLit = on
    -- a proc that lifts the icon to full opacity restyles its state, which
    -- calls back here with the new opacity
    if changed and f._adOnCooldown ~= nil and R("states", "procOverride") == true then
        Factory.SetState(f, rec, f._adOnCooldown, f._adDesatState)
        return
    end
    local want = on and R("states", "procGlow") == true
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "proc") and not Factory.GlowHidden(f)
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
    local gtype = DrawnGlowStyle(R("states", "procGlowType") or "proc", rec)
    local sig = GlowSig(f, gtype, p.color, p.speed, p.lines, p.thickness,
        p.particles, p.scale, p.xo, p.yo, p.level, p.strata,
        LaneExt(f, gtype, p.length, p.mx, p.my) .. LaneLook(rec, "states", "procGlow", gtype, p, inten))
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
        and LaneAllowed(f, "ready") and not Factory.GlowHidden(f)
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
    local gtype = DrawnGlowStyle(R("states", "readyGlowType") or "button", rec)
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
    local p = { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my }
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my) .. LaneLook(rec, "states", "readyGlow", gtype, p, inten))
    if f._adGlowOn and f._adGlowSig == sig then return end
    Factory.StopReadyGlow(f)
    StartLane(f, "ad", gtype, p)
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
    -- castable: ready, or recharging with a charge left; an item in stock
    local want = (rec.kind == "spell" or (rec.kind == "item" and not f._adItemEmpty))
        and R("states", "usableGlow") == true
        and f._adUsability == nil
        and (not f._adOnCooldown or f._adRecharging == true)
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "usable") and not Factory.GlowHidden(f)
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
    local gtype = DrawnGlowStyle(R("states", "usableGlowType") or "button", rec)
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
    local p = { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my }
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my) .. LaneLook(rec, "states", "usableGlow", gtype, p, inten))
    if f._adUsableOn and f._adUsableSig == sig then return end
    Factory.StopUsableGlow(f)
    StartLane(f, "adu", gtype, p)
    f._adUsableOn = true
    f._adUsableSig = sig
end

-- The recharging glow, key "adrc": lit while a charge spell has a charge left
-- and another on its way (the driver's f._adRecharging). The options preview
-- sets the flag in its Recharging moments and shows it while it is the lane on.
function Factory.StopRechargeGlow(f)
    if not f._adRechargeOn then return end
    StopLane(f, "adrc")
    f._adRechargeOn = false
    f._adRechargeSig = nil
end

function Factory.UpdateRechargeGlow(f, rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local preview = f._adGlowLaneOnly == "recharge"
    local want = rec.kind == "spell"
        and R("states", "rechargeGlow") == true
        and f._adRecharging == true
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "recharge") and not Factory.GlowHidden(f)
    if want and not preview and R("states", "rechargeGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    if not want then
        Factory.StopRechargeGlow(f)
        return
    end
    local c = R("states", "rechargeGlowColor") or { 1, 0.85, 0.4, 1 }
    local inten = R("states", "rechargeGlowIntensity") or 1
    local color = { c[1], c[2], c[3], (c[4] or 1) * inten }
    local gtype = DrawnGlowStyle(R("states", "rechargeGlowType") or "button", rec)
    local speed = R("states", "rechargeGlowSpeed") or 0.25
    local xo = R("states", "rechargeGlowXOffset") or 0
    local yo = R("states", "rechargeGlowYOffset") or 0
    local lines = R("states", "rechargeGlowLines") or 8
    local th = R("states", "rechargeGlowThickness") or 2
    local parts = R("states", "rechargeGlowParticles") or 4
    local scale = R("states", "rechargeGlowScale") or 1
    local lvl = (R("states", "rechargeGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    local strata = R("states", "rechargeGlowStrata") or "inherit"
    local len = R("states", "rechargeGlowLength") or 0
    local mx = R("states", "rechargeGlowMoveX") or 0
    local my = R("states", "rechargeGlowMoveY") or 0
    local p = { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my }
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my) .. LaneLook(rec, "states", "rechargeGlow", gtype, p, inten))
    if f._adRechargeOn and f._adRechargeSig == sig then return end
    Factory.StopRechargeGlow(f)
    StartLane(f, "adrc", gtype, p)
    f._adRechargeOn = true
    f._adRechargeSig = sig
end

-- The out-of-range glow, key "adr": lit while a castable spell's target is
-- out of its range (a charge left counts), the state its alpha, grey and
-- tint follow. The options preview shows it while it is the lane on.
function Factory.StopRangeGlow(f)
    if not f._adRangeOn then return end
    StopLane(f, "adr")
    f._adRangeOn = false
    f._adRangeSig = nil
end

function Factory.UpdateRangeGlow(f, rec)
    local R = function(s, k) return Store.Resolve(rec, s, k) end
    local preview = f._adGlowLaneOnly == "range"
    local want = rec.kind == "spell"
        and R("states", "rangeGlow") == true
        and (preview or (f._adUsability == "range" and (not f._adOnCooldown or f._adRecharging == true)))
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "range") and not Factory.GlowHidden(f)
    if want and not preview and R("states", "rangeGlowCombatOnly") == true
        and not InCombatLockdown() then
        want = false
    end
    if not want then
        Factory.StopRangeGlow(f)
        return
    end
    local c = R("states", "rangeGlowColor") or { 0.85, 0.2, 0.2, 1 }
    local inten = R("states", "rangeGlowIntensity") or 1
    local color = { c[1], c[2], c[3], (c[4] or 1) * inten }
    local gtype = DrawnGlowStyle(R("states", "rangeGlowType") or "button", rec)
    local speed = R("states", "rangeGlowSpeed") or 0.25
    local xo = R("states", "rangeGlowXOffset") or 0
    local yo = R("states", "rangeGlowYOffset") or 0
    local lines = R("states", "rangeGlowLines") or 8
    local th = R("states", "rangeGlowThickness") or 2
    local parts = R("states", "rangeGlowParticles") or 4
    local scale = R("states", "rangeGlowScale") or 1
    local lvl = (R("states", "rangeGlowLevel") or GLOW_LEVEL) + Factory.Rise(rec)
    local strata = R("states", "rangeGlowStrata") or "inherit"
    local len = R("states", "rangeGlowLength") or 0
    local mx = R("states", "rangeGlowMoveX") or 0
    local my = R("states", "rangeGlowMoveY") or 0
    local p = { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my }
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my) .. LaneLook(rec, "states", "rangeGlow", gtype, p, inten))
    if f._adRangeOn and f._adRangeSig == sig then return end
    Factory.StopRangeGlow(f)
    StartLane(f, "adr", gtype, p)
    f._adRangeOn = true
    f._adRangeSig = sig
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
    -- Depleted's glow: a recharging charge spell has a glow of its own
    local want = f._adOnCooldown == true and f._adRecharging ~= true and rec.kind ~= "aura"
        and R("states", "cooldownGlow") == true
        and R("appearance", "forceHideIcon") ~= true
        and LaneAllowed(f, "cooldown") and not Factory.GlowHidden(f)
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
    local gtype = DrawnGlowStyle(R("states", "cooldownGlowType") or "button", rec)
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
    local p = { color = color, speed = speed, lines = lines,
        thickness = th, particles = parts, scale = scale, xo = xo, yo = yo,
        level = lvl, strata = strata, length = len, mx = mx, my = my }
    local sig = GlowSig(f, gtype, color, speed, lines, th, parts, scale, xo, yo, lvl, strata,
        LaneExt(f, gtype, len, mx, my) .. LaneLook(rec, "states", "cooldownGlow", gtype, p, inten))
    if f._adCdGlowOn and f._adCdGlowSig == sig then return end
    Factory.StopCooldownGlow(f)
    StartLane(f, "adcdg", gtype, p)
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
    if R("states", "rangeGlowCombatOnly") == true then Factory.UpdateRangeGlow(f, rec) end
    if R("states", "rechargeGlowCombatOnly") == true then Factory.UpdateRechargeGlow(f, rec) end
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
    f._adDurHidden = hide
    -- the bands in percent: the bound copy shows the numbers instead
    f.cooldown:SetHideCountdownNumbers(hide or f._adPctOn == true)
    Pct.Show(f)
end

-- A key's words as the icon writes them: its replacements (FIND=REPL, on the
-- key's own words), then lower case ("ALT-CTRL-SHIFT-1" -> "acs1", m4, mwu,
-- n1, sp) or upper case with S, C, A first (SCA1, M4, WU, N1, PU, SP); four
-- letters at most either way.
local function KeyReplace(raw, list)
    if type(list) ~= "string" or not list:find("=", 1, true) then return raw end
    local text = raw:upper()
    for pair in list:gmatch("[^,]+") do
        local from, to = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if from and from ~= "" then
            from = from:upper():gsub("(%W)", "%%%1")
            to = (to or ""):gsub("%%", "%%%%")
            text = text:gsub(from .. "[%-+]", to):gsub(from, to)
        end
    end
    return text
end

local function LowerKey(key)
    key = key:gsub("ALT%-", "a"):gsub("CTRL%-", "c"):gsub("SHIFT%-", "s")
        :gsub("MOUSEWHEELUP", "mwu"):gsub("MOUSEWHEELDOWN", "mwd")
        :gsub("BUTTON", "m"):gsub("NUMPAD", "n"):gsub("SPACE", "sp")
    if key == "" then return nil end
    return #key > 4 and key:sub(1, 4) or key
end

local UPPER_KEYS = {
    { "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" },
    { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" }, { "NUMPADMULTIPLY", "N*" }, { "NUMPADDIVIDE", "N/" },
    { "NUMPADPERIOD", "N." }, { "NUMPADENTER", "NE" }, { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" },
    { "INSERT", "INS" }, { "DELETE", "DEL" }, { "UPARROW", "UP" }, { "DOWNARROW", "DN" },
    { "LEFTARROW", "LT" }, { "RIGHTARROW", "RT" }, { "BACKSPACE", "BS" }, { "CAPSLOCK", "CAP" },
}
local UPPER_WHOLE = { HOME = "HM", END = "EN", SPACE = "SP", ESCAPE = "ESC", TAB = "TB", MIDDLEMOUSE = "M3",
    MINUS = "-", PLUS = "=", ["+"] = "=", EQUALS = "=" }

local function UpperKey(text)
    text = text:upper():gsub("[%c]", "")
    local mods = ""
    if text:find("SHIFT[%-+]") or text:find("^S[%-+]") then mods = mods .. "S" end
    if text:find("CTRL[%-+]") or text:find("^C[%-+]") then mods = mods .. "C" end
    if text:find("ALT[%-+]") or text:find("^A[%-+]") then mods = mods .. "A" end
    local key = text:gsub("SHIFT[%-+]", ""):gsub("CTRL[%-+]", ""):gsub("ALT[%-+]", "")
        :gsub("^S[%-+]", ""):gsub("^C[%-+]", ""):gsub("^A[%-+]", ""):gsub("%s+", "")
    key = key:gsub("^BUTTON(%d+)$", "M%1"):gsub("^MOUSEBUTTON(%d+)$", "M%1")
    for _, p in ipairs(UPPER_KEYS) do key = key:gsub(p[1], p[2]) end
    key = key:gsub("^NUMPAD(%d)", "N%1")
    key = UPPER_WHOLE[key] or key
    if key == "" then return nil end
    local out = (mods .. key):gsub("[^%w%-%+=%.%*/]", "")
    if out == "" or out:match("^%.+$") then return nil end
    return #out > 4 and out:sub(1, 4) or out
end

function Factory.KeyText(rec, raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local key = KeyReplace(raw, rec and Store.Resolve(rec, "keybind", "keybindReplace"))
    if rec and Store.Resolve(rec, "keybind", "keybindStyle") == "upper" then return UpperKey(key) end
    return LowerKey(key)
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
    Pct.Show(f)
    ApplyCdPresentation(f, rec)
end

-- Mouse and tooltips

-- Tooltip by kind. Inputs are plain configured numbers; no secret is compared.
function Factory.ShowTooltip(f, rec)
    local d = rec.driver or {}
    local kind = rec.kind
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    if (kind == "spell" or kind == "aura" or kind == "timer") and d.spellID then
        -- A spell: the rank or override the driver tracks (stamped on the frame
        -- each feed, else its own resolve). An aura or a custom icon: the
        -- typed spell, whose art it wears.
        local sid
        if kind == "spell" then sid = f._adEffSid or Store.RecordSpellID(d)
        elseif kind == "aura" then sid = Store.TrackedAuraIDs(d)[1]
        else sid = d.spellID end -- raw-id: a custom icon's art pick
        if sid and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(sid) then
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
            GameTooltip:SetSpellByID(barSid) -- raw-id: the totem bar slot's own spell
        elseif slot and GameTooltip.SetTotem then
            GameTooltip:SetTotem(slot)
        elseif d.spellID then
            GameTooltip:SetSpellByID(Store.RecordSpellID(d) or d.spellID)
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
    elseif kind == "stance" and NS.DriverStance then
        -- the stance it shows, or a line saying you are in none
        NS.DriverStance.Tooltip(rec)
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
