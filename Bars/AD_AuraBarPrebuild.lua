-- AD_AuraBarPrebuild: aura bars built inside the login window, so a reload
-- while auras are secret (combat, a restricted instance) keeps them.
local ADDON, NS = ...
local Bars = NS.Bars
local Store = NS.Store

-- Aura bars draw through engine slots, which an addon may create only while
-- auras are not secret, except inside the login window. Aura icons and groups
-- build there (AD_Init, ADDON_LOADED); bars came from the queued draw a frame
-- later, outside it, and stayed empty until the restriction lifted. This runs
-- every aura bar that loads here through its real build inside PLAYER_LOGIN,
-- on a hidden stand-in holder, with Bars.loadWindow opening the creation
-- gates in AuraBarEnsure. The engine's draw then re-parents the shell to the
-- real holder and keeps the composition (same signature).
local holders = {}
local done = false

local function Loads(rec)
    if not Store.IsLoaded(rec) then return false end
    -- a bar in a layout that does not load here is never drawn
    local layout = rec.layoutId and Store.Get(rec.layoutId)
    return layout == nil or Store.IsLoaded(layout) == true
end

function Bars.PreBuildAura()
    if done then return end
    done = true
    if not (Store and Store.EachRecord and Store.IsLoaded and Bars.EnsureBar) then return end
    local DA = NS.DriverAura
    if not (DA and DA.IsAvailable and DA.IsAvailable() == true) then return end
    Bars.loadWindow = true
    Store.EachRecord(function(id, rec)
        -- a text element reading an aura's time or stacks draws through a slot
        -- too, and so does a texture driven by an aura, and a bar glow set to
        -- an aura (Bars\AD_BarGlow.lua)
        local T, TP, BG = NS.TextElements, NS.TextureElements, Bars.Glow
        if rec.type == "bar" and (rec.barKind == "aura"
            or (rec.barKind == "text" and T and (T.SlotSource or T.AuraSource)(rec))
            or (rec.barKind == "texture" and TP and TP.Source(rec) == "aura")
            or (BG and BG.WantsLanes(rec))) and Loads(rec) then
            local h = holders[id]
            if not h then
                h = CreateFrame("Frame", nil, UIParent)
                h:Hide()
                holders[id] = h
            end
            -- the engine's own size, so the layer windows are laid right once
            local w = Store.Resolve(rec, "size", "width") or 220
            local ht = Store.Resolve(rec, "size", "height") or 16
            local sc = Store.Resolve(rec, "size", "scale") or 1
            h:SetSize(math.max(1, math.floor(w * sc + 0.5)), math.max(1, math.floor(ht * sc + 0.5)))
            -- and its strata and level: buttons born now keep the rungs they get
            h:SetFrameStrata(Store.Resolve(rec, "frame", "strata") or "MEDIUM")
            h:SetFrameLevel(Store.Resolve(rec, "frame", "level") or 10)
            Bars.EnsureBar(rec, h)
        end
    end)
    Bars.loadWindow = nil
end
