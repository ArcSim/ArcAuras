-- Auto-rank action bars (ranked realms, WoW Forever only): once a new rank is
-- learned, bar slots holding the previous top rank move up to it. Other lower
-- ranks stay, since they are usually deliberate (a low-mana heal, a rank 1
-- slow); AutoRank.UpgradeAll() is the explicit catch-up.
local ADDON, NS = ...

NS.AutoRank = {}
local AutoRank = NS.AutoRank

local MAX_SLOTS = 180
local top = {}          -- [spell name] = top known rank's spellID, last scan
local primed = false    -- first scan only records, never rewrites
local pendingScan = false
local wantRetry = false

-- Opt-in, and only an explicit true counts: this changes something outside
-- the addon, and an unloaded SavedVariables file must leave the bars alone.
function AutoRank.Enabled()
    if not NS.IsForever then return false end
    return NS.Store ~= nil and NS.Store.GetSetting ~= nil
        and NS.Store.GetSetting("autoRankBars") == true
end

function AutoRank.Supported()
    return NS.IsForever == true
        and C_Spell ~= nil and C_Spell.GetSpellIDForSpellIdentifier ~= nil
end

-- GetActionInfo does not throw for slots 1-180. Macros are skipped: a macro
-- casting by name already fires the top rank.
local function SlotSpell(slot)
    if not GetActionInfo then return nil end
    local kind, id = GetActionInfo(slot)
    if kind == "spell" and type(id) == "number"
        and not (issecretvalue and issecretvalue(id)) and id > 0 then
        return id
    end
end

local function Known(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end -- raw-id: a live bar slot's spell
    if IsSpellKnown and IsSpellKnown(spellID) then return true end -- raw-id: a live bar slot's spell
    return false
end

-- A lookup by name returns the top known rank; nil means leave the slot alone.
local function TopRankOf(spellID)
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) -- raw-id: a live bar slot's spell
    if not name or name == "" then return nil end
    local best = C_Spell.GetSpellIDForSpellIdentifier(name) -- raw-id: a live bar slot's spell
    if type(best) ~= "number" or best <= 0 then return nil, name end
    return best, name
end

local function Blocked()
    return (InCombatLockdown and InCombatLockdown()) or GetCursorInfo() ~= nil
end

-- Swaps one slot to `spellID`; the displaced rank lands on the cursor and is
-- dropped. Combat or a busy cursor blocks it: a drag in progress is the
-- player's. True when the slot really holds the new rank afterwards.
local function Place(slot, spellID)
    if Blocked() or not Known(spellID) then return false end
    if C_Spell.PickupSpell then C_Spell.PickupSpell(spellID) -- raw-id: a live bar slot's spell
    elseif PickupSpell then PickupSpell(spellID) end
    local kind, _, _, cursorID = GetCursorInfo()
    if kind ~= "spell" or (cursorID and cursorID ~= spellID) then
        ClearCursor()
        return false
    end
    PlaceAction(slot)
    ClearCursor()
    return SlotSpell(slot) == spellID
end

-- One pass over the bars. Normally only slots holding exactly the previous
-- top rank move; force (the catch-up) moves every slot below its top rank.
-- Returns upgraded, blocked.
local function Scan(force)
    if not AutoRank.Supported() then return 0, false end
    local upgraded, blocked = 0, false
    local moved = {}   -- [name] = old top, for this pass
    local seen = {}
    for slot = 1, MAX_SLOTS do
        local id = SlotSpell(slot)
        if id then
            local best, name = TopRankOf(id)
            if best and name then
                if not seen[name] then
                    seen[name] = true
                    local old = top[name]
                    if primed and old and old ~= best then moved[name] = old end
                    top[name] = best
                end
                local want = (force and id ~= best) or (moved[name] and id == moved[name])
                if want then
                    if Blocked() then
                        blocked = true
                        -- keep the old top on record so the retry still sees
                        -- this slot as "held the previous top"
                        if moved[name] then top[name] = moved[name] end
                    elseif Place(slot, best) then
                        upgraded = upgraded + 1
                    end
                end
            end
        end
    end
    primed = true
    return upgraded, blocked
end

local function RunScan()
    pendingScan = false
    if not AutoRank.Enabled() then
        -- Reset while off, so switching it on mid-session does not read
        -- stale tops as rank-ups.
        primed = false
        wipe(top)
        return
    end
    local _, blocked = Scan(false)
    wantRetry = blocked
end

local function QueueScan(delay)
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(delay or 0.5, RunScan)
end

-- The Auto-rank module page's button: brings every bar spell up to its top known rank.
-- Returns the upgraded count, or nil and a reason when it cannot run now.
function AutoRank.UpgradeAll()
    if not AutoRank.Supported() then return nil, "unsupported" end
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    if GetCursorInfo() ~= nil then return nil, "cursor" end
    local n = Scan(true)
    return n
end

if NS.IsForever then
    local ev = CreateFrame("Frame")
    -- RegisterEvent throws on an event this client does not know.
    for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
        "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
        "ACTIONBAR_SLOT_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        if (not (C_EventUtils and C_EventUtils.IsEventValid))
            or C_EventUtils.IsEventValid(name) then
            ev:RegisterEvent(name)
        end
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- spell data settles after the loading screen: prime late
            QueueScan(2)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if wantRetry then QueueScan(0.5) end
        else
            QueueScan(0.5)
        end
    end)
end
