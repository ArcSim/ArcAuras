-- AD_QuestLookupOptions: the Quest Lookup card on the Modules page and its page (WoW Forever only). Reads
-- NS.QuestLookup at call time.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local MOD = Options.Modules

local ACTION = "ARCAURAS_QUESTLOOKUP"

local function QL() return NS.QuestLookup end

local function KeyWord()
    local key = GetBindingKey(ACTION)
    if type(key) ~= "string" or key == "" then return "Not set" end
    return GetBindingText(key)
end

-- The keybindings screen owns the key; this row names it and opens that screen.
local function KeyRow(pg, vis)
    local row = AT.AddRow(pg, 26, vis)
    row._colLabel = AT.RowLabel(row, "Key to hold")
    local b = AT.MakeSmallButton(row, "Not set", 150)
    row._colCtrl = b
    b:SetScript("OnClick", function()
        if InCombatLockdown() or not (Settings and Settings.OpenToCategory) then return end
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    end)
    AT.Tooltip(b, "Key to hold", "Opens the game's keybindings, where Quest Lookup is listed under Arc Auras.")
    row._sync = function() b:SetLabel(KeyWord()) end
    return row
end

local function Build(pg, m)
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Show quests for your target", m.isOn, m.setOn, MOD.Always,
        "While you hold the key, a box beside the cursor lists the quests your target belongs to.")
    MOD.Stamp(row, m, m.switch, "bool", MOD.Always, true)
    KeyRow(pg, function() return m.isOn() end)
end

MOD.Register({
    key = "questLookup",
    switch = "questLookup",
    name = "Quest Lookup",
    desc = "Hold a key to see which quests your target belongs to.",
    foreverOnly = true,
    -- a quest mark in a frame
    glyph = {
        { 2, 2, 16, 2, "arc" }, { 2, 16, 16, 2, "arc" }, { 2, 2, 2, 14, "arc" }, { 16, 2, 2, 14, "arc" },
        { 9, 5, 2, 7, "ink" }, { 9, 13, 2, 2, "ink" },
    },
    isOn = function() local q = QL() return q ~= nil and q.IsOn() end,
    setOn = function(v)
        local q = QL()
        if q then q.SetOn(v) end
        Options.RefreshAll()
    end,
    build = function(pg, m) Build(pg, m) end,
})
