-- The sound list behind every alert dropdown: sounds shipped in Sounds\, then
-- Blizzard kits ("kit:<id>"), then LibSharedMedia's when loaded. A stored value
-- is a plain string ("" = none): secret-free and readable in a share string.

local ADDON, NS = ...
local Sounds = {}
NS.Sounds = Sounds

-- ADDON is the folder name: "ArcAuras" on Forever, "ArcDisplay" on retail.
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\"

-- { stored name, file } in dropdown order. The names match the retail ArcUI
-- addon's LibSharedMedia keys, so profiles and LSM pickers agree.
local OWN = {
    -- Alerts
    { "ArcUI: Air Horn", "AirHorn.ogg" },
    { "ArcUI: Bike Horn", "BikeHorn.ogg" },
    { "ArcUI: Error Beep", "ErrorBeep.ogg" },
    { "ArcUI: Ringing Phone", "RingingPhone.ogg" },
    { "ArcUI: Robot Blip", "RobotBlip.ogg" },
    { "ArcUI: Warning Siren", "WarningSiren.ogg" },
    -- Effects
    { "ArcUI: Kaching", "Kaching.ogg" },
    { "ArcUI: Ultra Instinct", "UltraInstinct.mp3" },
    { "ArcUI: Ultra Instinct Theme", "UltraInstinctTheme.mp3" },
    { "ArcUI: Applause", "Applause.ogg" },
    { "ArcUI: Banana Peel Slip", "BananaPeelSlip.ogg" },
    { "ArcUI: Batman Punch", "BatmanPunch.ogg" },
    { "ArcUI: Blast", "Blast.ogg" },
    { "ArcUI: Boxing Arena", "BoxingArenaSound.ogg" },
    { "ArcUI: Double Whoosh", "DoubleWhoosh.ogg" },
    { "ArcUI: Heartbeat", "HeartbeatSingle.ogg" },
    { "ArcUI: Sharp Punch", "SharpPunch.ogg" },
    { "ArcUI: Shotgun", "Shotgun.ogg" },
    { "ArcUI: Squeaky Toy", "SqueakyToyShort.ogg" },
    { "ArcUI: Squish", "SquishFart.ogg" },
    { "ArcUI: Torch", "Torch.ogg" },
    { "ArcUI: Water Drop", "WaterDrop.ogg" },
    -- Musical
    { "ArcUI: Acoustic Guitar", "AcousticGuitar.ogg" },
    { "ArcUI: Brass", "Brass.mp3" },
    { "ArcUI: Drums", "Drums.ogg" },
    { "ArcUI: Glass", "Glass.mp3" },
    { "ArcUI: Synth Chord", "SynthChord.ogg" },
    { "ArcUI: Tada Fanfare", "TadaFanfare.ogg" },
    { "ArcUI: Temple Bell", "TempleBellHuge.ogg" },
    { "ArcUI: Xylophone", "Xylophone.ogg" },
    -- Animals
    { "ArcUI: Bleat", "Bleat.ogg" },
    { "ArcUI: Cat Meow", "CatMeow2.ogg" },
    { "ArcUI: Chicken Alarm", "ChickenAlarm.ogg" },
    { "ArcUI: Cow Mooing", "CowMooing.ogg" },
    { "ArcUI: Goat Bleating", "GoatBleating.ogg" },
    { "ArcUI: Kitten Meow", "KittenMeow.ogg" },
    { "ArcUI: Roaring Lion", "RoaringLion.ogg" },
    { "ArcUI: Rooster Chicken", "RoosterChickenCalls.ogg" },
    { "ArcUI: Sheep Bleat", "SheepBleat.ogg" },
    -- Voice
    { "ArcUI: Cartoon Voice", "CartoonVoiceBaritone.ogg" },
    { "ArcUI: Cartoon Walking", "CartoonWalking.ogg" },
    { "ArcUI: Oh No", "OhNo.ogg" },
}

-- Blizzard sound kits: { kit id, shown name }
local KITS = {
    { 567, "Snarl" },
    { 569, "Growl" },
    { 3081, "Direct Message" },
    { 5274, "Auction Window" },
    { 8959, "Raid Warning" },
    { 11466, "Not Prepared" },
    { 12867, "Drumroll Ding" },
    { 23404, "PvP Warning" },
    { 25477, "Countdown" },
}

local byName = {}
for _, e in ipairs(OWN) do byName[e[1]] = PATH .. e[2] end

-- Optional LibSharedMedia, looked up when needed: the addons that bring it
-- load after this one (addons load in alphabetical order), so a lookup at load
-- finds nothing. Its list feeds ours, and ours go to it the first time it is
-- there, for other addons' pickers. ArcUI or the ProcTracker may have
-- registered the same names (same clips) first, and LSM keeps the first, so
-- only the gaps are filled.
local shared
function Sounds.Lib()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true) or nil
    if lsm and lsm ~= shared then
        shared = lsm
        for _, e in ipairs(OWN) do
            if not lsm:IsValid("sound", e[1]) then
                lsm:Register("sound", e[1], PATH .. e[2])
            end
        end
    end
    return lsm
end
Sounds.Lib()
-- Every addon has loaded by login, so ours reach other pickers even when no
-- Arc Auras sound list is ever opened.
if NS.Events then
    NS.Events.On("PLAYER_LOGIN", "adsounds", function() Sounds.Lib() end)
end

-- "Master" ignores the SFX and music sliders, which suits an alert; the
-- other channels follow a volume slider the player already set.
Sounds.CHANNELS = { "Master", "SFX", "Music", "Ambience", "Dialog" }
Sounds.CHANNEL_LABELS = {
    Master = "Master (ignores the other sliders)",
    SFX = "Sound Effects",
    Music = "Music",
    Ambience = "Ambience",
    Dialog = "Dialog",
}
local VALID_CHANNEL = {}
for _, c in ipairs(Sounds.CHANNELS) do VALID_CHANNEL[c] = true end

-- File for a stored name: ours first, then LSM; nil when unknown.
function Sounds.PathFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    local own = byName[name]
    if own then return own end
    local lsm = Sounds.Lib()
    if lsm then return lsm:Fetch("sound", name, true) end
    return nil
end

-- { value = stored key, text = shown name }, "None" first; ours drop "ArcUI: ".
-- Each name says where it comes from: ours and the game's play for anyone a
-- profile is shared with, another addon's only for players who have it too.
function Sounds.Items()
    local items = { { value = "", text = "None" } }
    for _, e in ipairs(OWN) do
        items[#items + 1] = { value = e[1], text = e[1]:sub(8) .. " (Arc Auras)" }
    end
    for _, k in ipairs(KITS) do
        items[#items + 1] = { value = "kit:" .. k[1], text = k[2] .. " (Built-in)" }
    end
    local lsm = Sounds.Lib()
    if lsm then
        local extra = {}
        for _, n in ipairs(lsm:List("sound")) do
            if n ~= "None" and not byName[n] then extra[#extra + 1] = n end
        end
        table.sort(extra)
        for _, n in ipairs(extra) do items[#items + 1] = { value = n, text = n .. " (other addon)" } end
    end
    return items
end

-- Shown name for a stored key (summaries, tooltips). A sound no loaded addon
-- provides, as from an imported profile, says so instead of failing silently.
function Sounds.Label(name)
    if type(name) ~= "string" or name == "" then return "None" end
    local kit = name:match("^kit:(%d+)$")
    if kit then
        for _, k in ipairs(KITS) do
            if tostring(k[1]) == kit then return k[2] .. " (Built-in)" end
        end
        return name
    end
    if byName[name] then return name:sub(8) end
    local lsm = Sounds.Lib()
    if lsm and lsm:IsValid("sound", name) then return name .. " (other addon)" end
    return name .. " (not installed)"
end

-- Returns willPlay, soundHandle like PlaySound; nil for "" or an unknown key.
function Sounds.Play(name, channel)
    if type(name) ~= "string" or name == "" then return nil end
    if not VALID_CHANNEL[channel] then channel = "Master" end
    local kit = name:match("^kit:(%d+)$")
    if kit then return PlaySound(tonumber(kit), channel) end
    local path = Sounds.PathFor(name)
    if path then return PlaySoundFile(path, channel) end
    return nil
end

-- One preview at a time, so clicking through the list doesn't stack clips.
local previewHandle
function Sounds.StopPreview()
    if previewHandle then
        StopSound(previewHandle)
        previewHandle = nil
    end
end

function Sounds.Preview(name, channel)
    Sounds.StopPreview()
    local _, handle = Sounds.Play(name, channel)
    previewHandle = handle
end
