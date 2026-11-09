-- AD_AutoLogOptions: the Auto Combat Log card on the Modules page and its page. Reads NS.AutoLog at call time.
local ADDON, NS = ...
local Options = NS.Options
if not (Options and Options.Modules) then return end
local AT = NS.AT
local MOD = Options.Modules

local function AL() return NS.AutoLog end

local function StatusIs(word)
    return function()
        local a = AL()
        return a ~= nil and a.IsOn() and a.Status() == word
    end
end

local function Kinds()
    local list = {
        { "Dungeons", "party" },
        { "Raids", "raid" },
        { "Battlegrounds", "pvp" },
        { "Arenas", "arena" },
    }
    if NS.IsForever ~= true then list[#list + 1] = { "Scenarios and delves", "scenario" } end
    return list
end

local function KindRow(pg, m, on, label, kind)
    local a = AL()
    local row = AT.RowToggle(pg, label,
        function() local x = AL() return x ~= nil and x.Wants(kind) end,
        function(v) local x = AL() if x then x.SetWants(kind, v) end end, on)
    MOD.Stamp(row, m, a and a.KINDS[kind].field or kind, "bool", on)
end

local function Build(pg, m)
    local function On() return m.isOn() end
    AT.Section(pg, m.name)
    local row = AT.RowToggle(pg, "Log combat in instances", m.isOn, m.setOn, MOD.Always,
        "Starts the combat log when you enter an instance and stops it after you leave. A log you started yourself keeps running.")
    MOD.Stamp(row, m, m.switch, "bool", MOD.Always, true)
    row = AT.RowDropdown(pg, MOD.win, "When you enter",
        function() local a = AL() return a and a.Mode() or "ask" end,
        function(v) local a = AL() if a then a.SetMode(v) end end,
        function()
            return {
                { value = "ask", text = "Ask first" },
                { value = "start", text = "Start logging" },
            }
        end, On)
    AT.Tooltip(row, "When you enter", "Ask first shows a box with your choices. Start logging logs every time without asking.")
    MOD.Stamp(row, m, "autoLogWhen", "enum", On)
    AT.RowDesc(pg, "Logging now. It stops after you leave the instance.", 20, StatusIs("ours"))
    AT.RowDesc(pg, "Logging now. You started this log, so it keeps running.", 20, StatusIs("theirs"))
    AT.RowDesc(pg, "Arc Auras has not started a log.", 20, StatusIs("off"))
    AT.Section(pg, "Instances To Log", { visibleFn = On })
    for _, k in ipairs(Kinds()) do KindRow(pg, m, On, k[1], k[2]) end
    local function HasAnswers()
        local x = AL()
        return On() and x ~= nil and x.Mode() == "ask" and x.AnswerCount() > 0
    end
    row = AT.RowButton(pg, "Forget all", function()
        local x = AL()
        if x then x.Forget() end
        AT.LayoutPage(pg)
    end, HasAnswers, 92, "Saved answers")
    AT.Tooltip(row.button, "Saved answers", "Clears every Always here and Never here, so those instances ask again.")
    MOD.Stamp(row, m, "autoLogForget", nil, HasAnswers)
    local a = AL()
    if a then
        a.notify = function()
            if pg:IsVisible() then AT.LayoutPage(pg) end
        end
    end
end

MOD.Register({
    key = "autoLog",
    switch = "autoLog",
    name = "Auto Combat Log",
    desc = "Logs combat in dungeons and raids, and asks first if you want it to.",
    -- a page of lines
    glyph = {
        { 3, 2, 14, 2, "arc" }, { 3, 16, 14, 2, "arc" }, { 3, 2, 2, 16, "arc" }, { 15, 2, 2, 16, "arc" },
        { 7, 6, 6, 2, "ink" }, { 7, 9, 6, 2, "ink" }, { 7, 12, 4, 2, "ink" },
    },
    isOn = function() local a = AL() return a ~= nil and a.IsOn() end,
    setOn = function(v)
        local a = AL()
        if a then a.SetOn(v) end
        Options.RefreshAll()
    end,
    build = function(pg, m) Build(pg, m) end,
})
