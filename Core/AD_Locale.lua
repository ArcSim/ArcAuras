-- Translations. English text is the key: NS.L["Some words"] gives the
-- client's translation of those words, or the words themselves when there is
-- none, so a missing translation shows English and never an error. The theme
-- draws through the same lookup (AT.L), so its labels, tooltips, buttons and
-- tabs translate where they are drawn while every key stays English.

local _, NS = ...

local Locale = { strings = {}, base = {} }
NS.Locale = Locale

-- GAME_LOCALE lets a player force a language; British English is English.
local function ClientCode()
    local c = GAME_LOCALE
    if type(c) ~= "string" then c = (type(GetLocale) == "function") and GetLocale() or nil end
    if type(c) ~= "string" or c == "" then c = "enUS" end
    if c == "enGB" then c = "enUS" end
    return c
end
Locale.code = ClientCode()

-- The language files write into these: Locales\<code>.lua returns early on
-- any other client and fills LocaleStrings (L["English"] = "translation");
-- an enUS file fills LocaleBase with the English for a short key.
local strings, base = Locale.strings, Locale.base
NS.LocaleStrings = strings
NS.LocaleBase = base

-- A whole table at once: the client's language fills the translations, enUS
-- the English base on every client, any other language is ignored.
function Locale.Add(code, t)
    if type(t) ~= "table" then return false end
    local into
    if code == "enUS" then into = base
    elseif code == Locale.code then into = strings
    else return false end
    for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "string" and v ~= "" then into[k] = v end
    end
    return true
end

-- The player's Use English switch. It is kept only once logged in: the saved
-- settings arrive after the files load, so an earlier read can be stale.
local english
local function UseEnglish()
    if english ~= nil then return english end
    local S = NS.Store
    local on = S ~= nil and S.GetSetting ~= nil and S.GetSetting("useEnglish") == true
    local logged = IsLoggedIn
    if logged and logged() then english = on end
    return on
end

-- Re-reads the switch; the setting's row calls it after a change.
function Locale.Refresh()
    english = nil
    return UseEnglish()
end

local function Find(k)
    if not UseEnglish() then
        local v = strings[k]
        if type(v) == "string" and v ~= "" then return v end
    end
    local b = base[k]
    if type(b) == "string" and b ~= "" then return b end
    return nil
end

-- Words with numbers in them ("Glow 2 color") share one key per family
-- ("Glow %d color"): the key, and the numbers in order. Nil when there is no
-- number, the words are a format string already, or one %d could not give a
-- number back as written (a leading zero, a long run).
Locale.NUM_MAX = 8
function Locale.NumKey(s)
    if type(s) ~= "string" or not s:find("%d") then return nil end
    if s:find("%%[%-+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]") then return nil end
    local nums, ok = {}, true
    local key = s:gsub("%%", "%%%%"):gsub("%d+", function(d)
        if #d > 9 or (#d > 1 and d:sub(1, 1) == "0") then ok = false end
        nums[#nums + 1] = tonumber(d)
        return "%d"
    end)
    if not ok or #nums > Locale.NUM_MAX then return nil end
    return key, nums
end

-- A family's words with the numbers put back. A translation that asks for
-- another count of values than the key holds is no translation.
function Locale.Fill(fmt, nums)
    local want = 0
    for spec in fmt:gmatch("%%(.)") do
        if spec ~= "%" then want = want + 1 end
    end
    if want ~= #nums then return nil end
    local n = nums
    return fmt:format(n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8])
end

local function Lookup(k)
    if type(k) ~= "string" then return k end
    local v = Find(k)
    if v then return v end
    local key, nums = Locale.NumKey(k)
    local f = key and Find(key)
    if f then return Locale.Fill(f, nums) or k end
    return k
end
Locale.Lookup = Lookup

-- Reads look up and never store, so a miss is never cached; writes land in
-- the client's translations, as a language file's L["English"] = "..." would.
NS.L = setmetatable({}, {
    __index = function(_, k) return Lookup(k) end,
    __newindex = function(_, k, v)
        if type(k) == "string" and type(v) == "string" then strings[k] = v end
    end,
    __call = function(_, k) return Lookup(k) end,
})

if NS.AT then NS.AT.L = Lookup end
