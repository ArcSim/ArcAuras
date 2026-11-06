-- AD_CastSpellOptions: the castbar editor's Castbar > Per Spell sub-tab (a card per spell, "+ Add spell", the push bar).
-- AD_Options calls Options.CastSpellRows while it builds the bar pane; the runtime is Bars\AD_Castbar.lua (CB.SpellLook).
local ADDON, NS = ...
local Options = NS.Options
if not Options then return end

local CSO = {}
Options.CastSpellOptions = CSO

CSO.SUB = "Per Spell"
CSO.EMPTY_TEX = "Bar's own"
-- a card's rows in short words: the card names its spell
CSO.REST = { "castSpellID", "castSpellColorOn", "castSpellColor", "castSpellTex", "castSpellTicks",
    "castSpellTickCount", "castSpellTickPos" }

function CSO.Suf(k) return (k > 1) and tostring(k) or "" end

-- the card's line: the spell it styles, by name, with its ID
function CSO.When(r, suf)
    local Store = NS.Store
    if Store.Resolve(r, "cast", "castSpell" .. suf) ~= true then return "" end
    local id = tonumber(Store.Resolve(r, "cast", "castSpellID" .. suf))
    if not id or id <= 0 then return "" end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) -- raw-id: the ID typed, named as typed
    if type(name) ~= "string" or name == "" then return tostring(id) end
    return name .. " (" .. id .. ")"
end

function Options.CastSpellRows(pg, ctx, win, c)
    local Store, Schema = NS.Store, NS.Schema
    local slots = Schema.CAST_SPELL_SLOTS or 1
    local vis1
    for k = 1, slots do
        if Options.BuildYield then Options.BuildYield() end
        local suf = CSO.Suf(k)
        Options.MEDIA_EMPTY["castSpellTex" .. suf] = CSO.EMPTY_TEX
        local fields, rest = { "castSpell" .. suf }, {}
        for _, key in ipairs(CSO.REST) do
            fields[#fields + 1] = key .. suf
            rest[#rest + 1] = key .. suf
        end
        if k == 1 then fields[#fields + 1] = "castSpellCount" end
        -- per item: which spells a castbar styles is never a default look
        local vis = c.BarBlock("Spell " .. k, "cast", "Castbar", fields,
            function(r)
                return Schema.PlayerCast(r) and k <= (Store.Resolve(r, "cast", "castSpellCount") or 1)
            end,
            CSO.SUB, true, { card = {
                when = function(r) return CSO.When(r, suf) end,
                word = "Spell " .. k,
                rows = function(cardVis)
                    c.SectionRows(pg, "bar", "cast", ctx, cardVis, rest)
                end } })
        if k == 1 then vis1 = vis end
    end
    -- "+ Add spell" / "Remove last spell", then the push bar
    NS.AT.Section(pg, nil, { visibleFn = vis1 })
    c.SectionRows(pg, "bar", "cast", ctx, vis1, { "castSpellCount" })
    c.SubPush("Castbar", CSO.SUB)
end
