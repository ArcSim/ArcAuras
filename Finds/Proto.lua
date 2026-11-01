local _, ns = ...

-- the wire format: one short line per message, "~" between fields, a checksum last.
-- Checksums only drop junk; nothing in a message is trusted beyond what the game confirms.
local P = {}
ns.Proto = P

P.PREFIX = "FIF1"
P.VERSION = 1
P.MAX = 250

local function Checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum + s:byte(i) * (i % 13 + 1)) % 65536 end
    return ("%04x"):format(sum)
end
P.Checksum = Checksum

-- free text loses the separator and escape characters (and "^", which joins the lines of a share string) and is cut
-- short
local function Clean(s, n)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[~|%^\n\r]", " ")
    if #s > n then s = s:sub(1, n) end
    return s
end

local function Seal(body)
    return body .. "~" .. Checksum(body)
end

local function Split(msg)
    local out = {}
    for field in (msg .. "~"):gmatch("([^~]*)~") do out[#out + 1] = field end
    return out
end

local function Num(s, lo, hi)
    local n = tonumber(s)
    if not n or n ~= math.floor(n) or n < lo or n > hi then return end
    return n
end

local function Opened(msg)
    if type(msg) ~= "string" or #msg < 6 or #msg > P.MAX then return end
    local body, ck = msg:match("^(.*)~(%x%x%x%x)$")
    if not body or Checksum(body) ~= ck then return end
    local f = Split(body)
    if tonumber(f[2]) ~= P.VERSION then return end
    return f
end

-- e: a find record (Finds.lua keys)
function P.EncodeFind(e)
    local s = e.s and e.s[1] or {}
    local function Build(z, sz)
        return Seal(table.concat({
            "F", P.VERSION, e.id, e.k or "n", e.q or "", e.il or "", e.rq or "", e.cl or "", e.sc or "", e.iv or "",
            e.ac or "", Clean(e.fp, 40), s.t or "-", Clean(s.n, 40), s.npc or "", s.lv or "", Clean(z, 40),
            Clean(sz, 40), s.x or "", s.y or "", Clean(e.by, 24), e.at or "", s.m or "",
        }, "~"))
    end
    -- the place names are the only long fields: drop the subzone, then the zone
    local msg = Build(s.z, s.sz)
    if #msg > P.MAX then msg = Build(s.z, nil) end
    if #msg > P.MAX then msg = Build(nil, nil) end
    return msg
end

function P.DecodeFind(msg)
    local f = Opened(msg)
    if not f or f[1] ~= "F" or #f ~= 23 then return end
    local id = Num(f[3], 1, 9999999)
    local kind = f[4]
    if not id or (kind ~= "n" and kind ~= "c") then return end
    local info = {
        id = id, kind = kind,
        q = Num(f[5], 0, 8), ilvl = Num(f[6], 0, 2000), req = Num(f[7], 0, 200),
        cls = Num(f[8], -1, 30), sub = Num(f[9], -1, 40), inv = Num(f[10], -1, 40), ac = Num(f[11], -1, 2147483647),
        fp = f[12] ~= "" and f[12] or nil,
        by = f[21] ~= "" and f[21] or nil,
        at = Num(f[22], 1000000000, 4000000000),
    }
    local st = f[13]
    if st ~= "-" then
        if not ("lrvqcox"):find(st, 1, true) or #st ~= 1 then return end
        info.src = { t = st, n = f[14] ~= "" and f[14] or nil, npc = Num(f[15], 1, 9999999), lv = Num(f[16], -1, 200),
            z = f[17] ~= "" and f[17] or nil, sz = f[18] ~= "" and f[18] or nil, x = Num(f[19], 0, 1000), y = Num(f[20], 0, 1000),
            m = Num(f[23], 1, 999999) }
    end
    return info
end

-- a hello asks for finds changed after since (this server's bookmark) with an item id above after (the page cursor)
function P.EncodeHello(count, sum, since, after)
    return Seal(table.concat({ "H", P.VERSION, count, sum, since, after }, "~"))
end

function P.DecodeHello(msg)
    local f = Opened(msg)
    if not f or f[1] ~= "H" or #f ~= 6 then return end
    local count, sum = Num(f[3], 0, 1000000), Num(f[4], 0, 2147483647)
    local since, after = Num(f[5], 0, 4000000000), Num(f[6], 0, 99999999)
    if not count or not sum or not since or not after then return end
    return count, sum, since, after
end

-- the end of one catch-up page: how many finds it carried and the last item id
function P.EncodeEnd(n, last)
    return Seal(table.concat({ "E", P.VERSION, n, last }, "~"))
end

function P.DecodeEnd(msg)
    local f = Opened(msg)
    if not f or f[1] ~= "E" or #f ~= 4 then return end
    local n, last = Num(f[3], 0, 1000), Num(f[4], 0, 99999999)
    if not n or not last then return end
    return n, last
end

-- "I will serve target": count is how many of the asked-for finds this copy holds, so a bigger holder can take over
function P.EncodeServing(target, count)
    return Seal(table.concat({ "Y", P.VERSION, Clean(target, 60), count or 0 }, "~"))
end

function P.DecodeServing(msg)
    local f = Opened(msg)
    if not f or f[1] ~= "Y" or #f ~= 4 or f[3] == "" then return end
    local count = Num(f[4], 0, 1000000)
    if not count then return end
    return f[3], count
end

function P.Kind(msg)
    return type(msg) == "string" and msg:sub(1, 1) or nil
end

-- a sound message from another version of the addon: not junk, only not ours to read, so it never counts against the
-- sender
function P.OtherVersion(msg)
    if type(msg) ~= "string" or #msg < 6 or #msg > P.MAX then return false end
    local body, ck = msg:match("^(.*)~(%x%x%x%x)$")
    if not body or Checksum(body) ~= ck then return false end
    local v = tonumber(body:match("^[^~]*~([^~]*)"))
    return v ~= nil and v ~= P.VERSION
end

-- the string a player copies onto the website: a header (an anonymous id for this install and how many finds follow),
-- then one find message per find, all joined by "^". The count lets the website tell a paste that was cut short.
P.SHARE = "FIFS"
function P.EncodeShare(install, finds)
    local parts = { P.SHARE, P.VERSION, Clean(install, 16), #finds }
    for _, e in ipairs(finds) do parts[#parts + 1] = P.EncodeFind(e) end
    return table.concat(parts, "^")
end

-- install, finds (DecodeFind tables), expected count; nil for anything that is not a share string
function P.DecodeShare(s)
    if type(s) ~= "string" then return end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    local parts = {}
    for part in (s .. "^"):gmatch("([^%^]*)%^") do parts[#parts + 1] = part end
    if parts[1] ~= P.SHARE or tonumber(parts[2]) ~= P.VERSION then return end
    local count = Num(parts[4], 0, 100000)
    if not count or parts[3] == "" then return end
    local finds = {}
    for i = 5, #parts do
        local info = P.DecodeFind(parts[i])
        if info then finds[#finds + 1] = info end
    end
    return parts[3], finds, count
end
