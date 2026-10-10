-- AD_SoundOptions: the Sound item's rows: the Add window's Sound tab, and the editor's Tracking tab with where it plays and its rules.
-- AD_Options calls in behind nil checks (Options.SoundAddRows / SoundCreate / SoundRows / SoundWhat / SoundThumb); the rules are the Custom editor's (Options.Custom.RuleRows) with the sound and speak actions only.
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local SO = {}
Options.Sound = SO

-- a speaker both clients ship (the chat channel button's art)
SO.THUMB = "Interface\\Common\\VoiceChat-Speaker"
-- Play in: each switch on means the item plays there (the record stores the off ones)
SO.PLAY_IN = {
    { key = "skipSolo", label = "Play when solo", tip = "Off: silent while you are not in a group." },
    { key = "skipParty", label = "Play in a party", tip = "Off: silent while you are in a party." },
    { key = "skipRaid", label = "Play in a raid", tip = "Off: silent while you are in a raid group." },
}
SO.AURA = { aura_gain = true, aura_stack = true, aura_lost = true }

local function Trim(v) return (tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- The Add window

-- The first rule, set up here: what sets it off and what it plays (more rules,
-- and their guards, on the item's Tracking tab). addState.soundRule is the draft.
function SO.Draft(addState)
    addState.soundRule = addState.soundRule or { when = "cast", act = "sound" }
    return addState.soundRule
end

function SO.GroupOf(when)
    for _, g in ipairs(NS.Schema.SOUND_TRIGGER_GROUPS) do
        for _, t in ipairs(g.list) do
            if t == when then return g end
        end
    end
    return NS.Schema.SOUND_TRIGGER_GROUPS[1]
end

function Options.SoundAddRows(pg, owner, addState)
    local AT, S = NS.AT, NS.Schema
    local vis = function() return addState.cat == "Sound" and not addState.remGroupId end
    local function D() return SO.Draft(addState) end
    local function Is(...)
        local set = {}
        for _, k in ipairs({ ... }) do set[k] = true end
        return function() return vis() and set[D().when] == true end
    end
    local Relay = function() AT.LayoutPage(pg) end
    AT.RowDesc(pg, "Plays a sound or speaks when something happens. Nothing shows on screen.", 20, vis)
    AT.RowInput(pg, "Sound name",
        function() return addState.soundName or "" end,
        function(v) addState.soundName = v end,
        vis, "What the sidebar calls it.", "Sound", true)
    AT.RowDropdown(pg, owner, "Trigger type",
        function() return SO.GroupOf(D().when).key end,
        function(v)
            for _, g in ipairs(S.SOUND_TRIGGER_GROUPS) do
                if g.key == v and SO.GroupOf(D().when) ~= g then D().when = g.list[1] end
            end
        end,
        function()
            local out = {}
            for _, g in ipairs(S.SOUND_TRIGGER_GROUPS) do out[#out + 1] = { value = g.key, text = g.label } end
            return out
        end, vis, Relay)
    AT.RowDropdown(pg, owner, "When",
        function() return D().when end,
        function(v)
            local d = D()
            d.when = v
            -- an aura's moment is the game's to play: a sound file, no speech
            if SO.AURA[v] and d.act == "speak" then d.act = "sound" end
        end,
        function()
            local out = {}
            for _, t in ipairs(SO.GroupOf(D().when).list) do
                out[#out + 1] = { value = t, text = S.CUSTOM_TRIGGER_LABELS[t] or t }
            end
            return out
        end, vis, Relay)
    local CU = NS.DriverCustom
    AT.RowInput(pg, "Spell",
        function()
            local id = D().spellID
            local nm = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the typed spell, for the editor's words
            return (type(nm) == "string" and nm ~= "") and nm or (id and tostring(id) or "")
        end,
        function(v)
            local CO = Options.Custom
            D().spellID = CO and CO.ParseSpell and CO.ParseSpell(v) or tonumber(v)
        end,
        function() return vis() and CU ~= nil and CU.SPELL_TRIGGERS[D().when] == true end,
        "The spell's name or ID.", "e.g. 6572")
    AT.RowDropdown(pg, owner, "Condition",
        function() return D().cond or "" end,
        function(v) D().cond = (v ~= "") and v or nil end,
        function() return SO.CondItems(D()) end, Is("cond_on", "cond_off"), Relay)
    AT.RowDropdown(pg, owner, "Whose aura",
        function() return D().unit or "player" end,
        function(v) D().unit = (v ~= "player") and v or nil end,
        SO.UnitItems, Is("aura_gain", "aura_stack", "aura_lost"), Relay)
    AT.RowInput(pg, "Aura IDs",
        function() return table.concat(D().auraIDs or {}, ", ") end,
        function(v)
            local list = Options.ParseSpellIDs(v)
            while #list > 10 do table.remove(list) end
            D().auraIDs = (#list > 0) and list or nil
        end,
        Is("aura_gain", "aura_stack", "aura_lost"), "The aura's spell IDs, comma separated.", "e.g. 16870")
    AT.RowDropdown(pg, owner, "Play",
        function() return D().act end,
        function(v) D().act = v end,
        function() return SO.ActionItems(D()) end, vis, Relay)
    AT.RowDropdown(pg, owner, "Sound",
        function() return D().sound or "" end,
        function(v) D().sound = (v ~= "") and v or nil end,
        function() return SO.SoundItems(D()) end,
        function() return vis() and D().act == "sound" end, Relay)
    AT.RowInput(pg, "Say",
        function() return D().text or "" end,
        function(v) D().text = (Trim(v) ~= "") and v:sub(1, 200) or nil end,
        function() return vis() and D().act == "speak" end, "The line to speak.", nil, true)
end

-- The item with the drafted rule as its first one (the engine's own setters,
-- so the rule is tidied as an edit would be).
function Options.SoundCreate(addState, layoutId)
    local name = Trim(addState.soundName)
    local rec = NS.Store.NewBar(layoutId, "sound", { rules = {} }, name ~= "" and name or "Sound")
    local CU, d = NS.DriverCustom, addState.soundRule
    if rec and CU and CU.AddRule and CU.SetRule and d then
        CU.AddRule(rec)
        for _, k in ipairs({ "when", "spellID", "cond", "unit", "auraIDs", "act", "sound", "text" }) do
            if d[k] ~= nil then CU.SetRule(rec, 1, k, d[k]) end
        end
    end
    addState.soundName, addState.soundRule = nil, nil
    return rec
end

-- The words: the card's line and the thumbnail

-- a rule's trigger as the line reads it: "you cast a spell (Revenge)"
function SO.TriggerWords(r)
    local CU = NS.DriverCustom
    local w = (CU and CU.Words) and CU.Words(r) or tostring(r.when)
    w = w:match("^(.-) > ") or w
    return w:sub(1, 1):lower() .. w:sub(2)
end

function Options.SoundWhat(rec)
    local SN = NS.SoundItems
    local rules = SN and SN.Rules(rec) or {}
    local r = rules[1]
    if not r then return "no rules yet" end
    local out = ((r.act == "speak") and "speaks when " or "plays when ") .. SO.TriggerWords(r)
    if #rules == 2 then
        out = out .. ", and 1 more rule"
    elseif #rules > 2 then
        out = out .. (", and %d more rules"):format(#rules - 1)
    end
    return out
end

function Options.SoundThumb() return SO.THUMB end

-- The rule editor's own pieces

function SO.IsAura(r) return r ~= nil and SO.AURA[r.when] == true end

-- the conditions a rule can turn on (the Custom editor's list)
function SO.CondItems(r)
    return Options.Custom.CondItems(r)
end

function SO.UnitItems()
    local S = NS.Schema
    local out = {}
    for _, u in ipairs(S.SOUND_AURA_UNITS) do out[#out + 1] = { value = u, text = S.SOUND_AURA_UNIT_LABELS[u] or u } end
    return out
end

function SO.ActionItems(r)
    local S = NS.Schema
    local out = {}
    for _, a in ipairs(S.SOUND_ACTIONS) do
        if not (a == "speak" and SO.IsAura(r)) then out[#out + 1] = { value = a, text = S.CUSTOM_ACTION_LABELS[a] } end
    end
    return out
end

-- an aura's moment is played by the game from a file: no built-in kits there
function SO.SoundItems(r)
    if not NS.Sounds then return { { value = "", text = "None" } } end
    return NS.Sounds.Items(SO.IsAura(r))
end

-- under the trigger: the aura's unit and ids (the condition row is the shared editor's)
function SO.TriggerRows(pg, i, api, owner)
    local AT = NS.AT
    local auraVis = api.Is("when", "aura_gain", "aura_stack", "aura_lost")
    local unit = AT.RowDropdown(pg, owner, "Whose aura",
        function()
            local r = api.Rule()
            return (r and r.unit) or "player"
        end,
        function(v) api.Set("unit", (v ~= "player") and v or nil) end,
        SO.UnitItems, auraVis)
    local ids = AT.RowInput(pg, "Aura IDs",
        function()
            local r = api.Rule()
            local list = r and type(r.auraIDs) == "table" and r.auraIDs or {}
            local t = {}
            for _, v in ipairs(list) do t[#t + 1] = tostring(v) end
            return table.concat(t, ", ")
        end,
        function(v)
            local list = Options.ParseSpellIDs(v)
            -- words with no id in them change nothing; an empty box clears
            if #list == 0 and Trim(v) ~= "" then return end
            while #list > 10 do table.remove(list) end
            api.Set("auraIDs", (#list > 0) and list or nil)
        end,
        auraVis, "The aura's spell IDs, comma separated. Any caster's copy counts.", "e.g. 16870")
    AT.RowDesc(pg, "The game plays it, in combat too; Load When and the gap between cues don't apply.", 20, auraVis)
    if i == 1 then
        api.Stamp(unit, "ruleAuraUnit", "Whose aura")
        api.Stamp(ids, "ruleAuraIDs", "Aura IDs")
    end
end

-- under the action: how long the rule stays quiet after it plays
function SO.ActRows(pg, i, api)
    local AT = NS.AT
    local q = AT.RowInput(pg, "Quiet for (seconds)",
        function()
            local SN = NS.SoundItems
            local r = api.Rule()
            return ("%g"):format(SN and SN.QuietOf(r) or 4)
        end,
        function(v)
            local SN = NS.SoundItems
            if v == "" then api.Set("quiet", nil) return end
            local n = tonumber(v)
            if not (n and n >= 0 and SN) then return end
            n = math.min(3600, n)
            api.Set("quiet", (n ~= SN.QUIET) and n or nil)
        end,
        api.rv, "After it plays, the rule stays silent this long (aura rules: the game's limit, 5 at most). Enter applies it.")
    if i == 1 then api.Stamp(q, "ruleQuiet", "Quiet for (seconds)") end
end

function SO.RuleOpts(owner)
    local S = NS.Schema
    return {
        groups = S.SOUND_TRIGGER_GROUPS, actions = S.SOUND_ACTIONS, section = "sound",
        empty = "No rules yet: add one to say when it plays.",
        noTimer = true, noGuards = SO.IsAura, actionsFor = SO.ActionItems, soundItems = SO.SoundItems,
        triggerRows = function(pg, i, api) SO.TriggerRows(pg, i, api, owner) end,
        actRows = SO.ActRows,
    }
end

-- The editor's Tracking tab: where it plays, then its rules. One record only,
-- never over a multi-selection.
function Options.SoundRows(pg, ctx, trackVis, owner)
    local AT = NS.AT
    local CO = Options.Custom
    local function Rec()
        local r, SN = ctx(), NS.SoundItems
        return (r and not r._adMulti and SN and SN.Is(r)) and r or nil
    end
    local vis = function() return trackVis() and Rec() ~= nil end
    AT.Section(pg, "Sound", { visibleFn = vis })
    for _, p in ipairs(SO.PLAY_IN) do
        local row = AT.RowToggle(pg, p.label,
            function()
                local r = Rec()
                return r ~= nil and r.driver[p.key] ~= true
            end,
            function(v)
                local r, CU = Rec(), NS.DriverCustom
                if r and CU then CU.SetDriver(r, p.key, (not v) or nil) end
                AT.LayoutPage(pg)
            end,
            vis, p.tip)
        row._adMeta = { family = "bar", section = "sound", field = p.key, def = { label = p.label }, baseVis = vis }
    end
    -- the game channel it plays on, as an icon's sounds pick theirs
    local chDef = NS.Schema.icon.alerts.fields.soundChannel
    local ch = AT.RowDropdown(pg, owner, "Sound channel",
        function()
            local r, SN = Rec(), NS.SoundItems
            return (r and SN) and SN.Channel(r) or "Master"
        end,
        function(v)
            local r, CU = Rec(), NS.DriverCustom
            if r and CU then CU.SetDriver(r, "channel", (v ~= "Master") and v or nil) end
        end,
        function()
            local out = {}
            for _, v in ipairs(chDef.values) do out[#out + 1] = { value = v, text = (chDef.labels and chDef.labels[v]) or v } end
            return out
        end, vis, function() AT.LayoutPage(pg) end)
    AT.Tooltip(ch, "Sound channel", "Which of the game's volume sliders its sounds come out of.")
    if CO and CO.RuleRows then CO.RuleRows(pg, Rec, vis, owner, true, SO.RuleOpts(owner)) end
    SO.SpeechRows(pg, vis, Rec)
    AT.Section(pg, nil)
end

-- Speech, shared by every spoken line in Arc Auras (CU.Speak): the voice and
-- the rate are ours, the volume and the tick between lines are WoW's own text
-- to speech settings. Test voice speaks the item's first line.
SO.VOICES = { { value = "default", text = "WoW's voice" }, { value = "male", text = "A male voice" },
    { value = "female", text = "A female voice" } }
function SO.SpeechRows(pg, vis, Rec)
    local AT, Store = NS.AT, NS.Store
    local TS = C_TTSSettings
    local TICK = Enum and Enum.TtsBoolSetting and Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks
    AT.Section(pg, "Speech", { visibleFn = vis })
    AT.RowDesc(pg, "Shared by every spoken line in Arc Auras. The volume and the tick are WoW's own text to speech settings.", 20, vis)
    local voice = AT.RowDropdown(pg, pg, "Voice",
        function() return Store.GetSetting("ttsVoice") or "default" end,
        function(v) Store.SetSetting("ttsVoice", (v ~= "default") and v or nil) end,
        function() return SO.VOICES end, vis)
    AT.Tooltip(voice, "Voice", "WoW's voice is the one picked in WoW's own options. Male or female picks a matching voice from your system's list.")
    local rate = AT.RowSlider(pg, "Speech rate",
        function() return Store.GetSetting("ttsRate") or 0 end,
        function(v) Store.SetSetting("ttsRate", (v ~= 0) and v or nil) end,
        -10, 10, 1, false, vis)
    AT.Tooltip(rate, "Speech rate", "How fast a line is spoken. 0 follows WoW's own speech rate.")
    if TS and TS.GetSpeechVolume and TS.SetSpeechVolume then
        local vol = AT.RowSlider(pg, "Speech volume",
            function() return TS.GetSpeechVolume() or 100 end,
            function(v) TS.SetSpeechVolume(v) end,
            0, 100, 1, false, vis)
        AT.Tooltip(vol, "Speech volume", "WoW's own text to speech volume, so it also sets chat narration.")
    end
    if TS and TS.GetSetting and TS.SetSetting and TICK ~= nil then
        AT.RowToggle(pg, "Sound between messages",
            function() return TS.GetSetting(TICK) == true end,
            function(v) TS.SetSetting(TICK, v == true) end,
            vis, "WoW's own option: a short tick when a spoken line ends.")
    end
    AT.RowButton(pg, "Test voice", function()
        local CU, SN = NS.DriverCustom, NS.SoundItems
        if not CU then return end
        local line = "This is how Arc Auras speaks."
        for _, r in ipairs((SN and Rec()) and SN.Rules(Rec()) or {}) do
            if r.act == "speak" and type(r.text) == "string" and r.text ~= "" then
                line = r.text
                break
            end
        end
        CU.Speak(line)
    end, vis, 110, "Hear the voice")
end
