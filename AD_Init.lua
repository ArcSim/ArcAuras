-- Startup: the store loads on ADDON_LOADED, the layout engine starts on
-- PLAYER_LOGIN, and the slash commands open the options.

local ADDON, NS = ...
local Events = NS.Events

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        NS.Store.Init()
        -- Aura slots are created parked here: the load window is the one
        -- time engine slot creation is legal, even in combat or an instance.
        if NS.DriverAura and NS.DriverAura.PreBuild then
            NS.DriverAura.PreBuild()
        end
        if NS.DriverUnitAuras and NS.DriverUnitAuras.PreBuild then
            NS.DriverUnitAuras.PreBuild()
        end
        if NS.DriverAuraRows and NS.DriverAuraRows.PreBuild then
            NS.DriverAuraRows.PreBuild()
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- On Forever the client can assign the saved variables global after
        -- ADDON_LOADED; point the store at the live table.
        NS.Store.AdoptLiveSV()
        NS.LayoutEngine.Init()
        -- Aura bars build here, inside the login window, as the aura slots
        -- did at ADDON_LOADED: the queued draw runs a frame later, outside it.
        if NS.Bars and NS.Bars.PreBuildAura then NS.Bars.PreBuildAura() end
        NS.LayoutEngine.QueueRebuild()
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The same check one event later: if the client re-pointed the global
        -- after PLAYER_LOGIN, follow it and draw the real layout.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if NS.Store.AdoptLiveSV() then
            NS.LayoutEngine.QueueRebuild()
        end
        -- Entering the world closes every Escape-closable window, so open it after.
        if NS.Migrate and NS.Migrate.OldEngineLoaded() then C_Timer.After(1, NS.Migrate.ShowNotice) end
    end
end)

-- Sample layout for "/arcui2 demo": a cooldown group (with a charge spell,
-- to exercise the dual-shadow path), an aura group and a free trinket.
local function SeedDemo()
    local Store = NS.Store
    local layout = Store.NewLayout("Demo HUD")
    local rotation = Store.NewGroup(layout.id, "Rotation", "cooldown")
    for _, sid in ipairs({ 17364, 60103, 188389, 51533 }) do
        local name = (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid)
        Store.NewIcon("spell", { spellID = sid }, rotation.id, nil, name)
    end
    local buffs = Store.NewGroup(layout.id, "Buffs", "aura")
    local aname = (C_Spell.GetSpellName and C_Spell.GetSpellName(344179)) or "Aura 344179"
    Store.NewIcon("aura", { spellID = 344179, auraType = "buff" }, buffs.id, nil, aname)
    Store.NewIcon("trinket", { slotID = 13 }, nil, layout.id, "Trinket 1")
    return layout
end

-- The old Arc UI Forever commands keep working. The numbers stay gapless: the
-- chat frame stops reading at the first missing one.
SLASH_ARCUIVTWO1 = "/arcauras"
SLASH_ARCUIVTWO2 = "/arcui2"
SLASH_ARCUIVTWO3 = "/aui2"
-- Forever has no retail ArcUI, so /arcui and /aui open this addon there too.
if NS.IsForever then
    SLASH_ARCUIVTWO4 = "/arcui"
    SLASH_ARCUIVTWO5 = "/aui"
end
SlashCmdList["ARCUIVTWO"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "demo" then
        local layout = SeedDemo()
        NS.Options.Open()
        NS.Options.Select("layout", layout.id)
        return
    end
    -- "/arcui2 plate" prints what the target-nameplate pin sees on this client.
    -- Chat output only ever answers a command the player typed.
    if msg == "plate" and NS.Anchor and NS.Anchor.PlateReport then
        for _, line in ipairs(NS.Anchor.PlateReport()) do
            print("|cff3fc9f2Arc Auras:|r " .. line)
        end
        return
    end
    -- "/arcauras special" prints every Special Aura tracker's state (retail only).
    if msg == "special" and NS.Special and NS.Special.Diag then
        for _, line in ipairs(NS.Special.Diag()) do
            print("|cff3fc9f2Arc Auras:|r " .. line)
        end
        return
    end
    NS.Options.Toggle()
end
