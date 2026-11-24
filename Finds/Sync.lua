local ADDON, ns = ...

local P = ns.Proto

-- the engine: no WoW calls, everything through env, so tests can run many copies
-- env: now(), random(lo, hi), after(seconds, fn), send(dist, target, msg) -> "ok" / "wait" / "fail" / "gone" (offline),
--      canSend(), me, finds (Finds API), accept(info, sender, done(ok)), onRecorded(e, status, info),
--      stamp() (the clock finds are stamped with), bookmark() / setBookmark(t) (how far this server is caught up),
--      groups() (optional: the guild and group routes a live find also takes, e.g. { "GUILD", "PARTY" })
local Engine = {}
Engine.__index = Engine
ns.SyncEngine = Engine

local CHANNEL_GAP = 2.0       -- seconds between channel messages from one copy
local WHISPER_GAP = 0.3
local GROUP_GAP = 1.0         -- seconds between guild and group messages from one copy
local SERVE_LIMIT = 100       -- finds one catch-up page carries
local WHISPER_ROOM = SERVE_LIMIT * 2
local PAGE_GAP = 3            -- seconds before asking for the next page
local PAGE_WAIT = 40          -- seconds a next-page ask waits for an answer before the run counts as done
local OVERLAP = 3600          -- a catch-up reaches an hour back from the bookmark, for finds recorded around it
local SENDER_WINDOW = 300
local SENDER_MAX = 40         -- finds new to this copy heard from one sender per window; the rest of that window goes unheard
local SEND_MAX = 30           -- finds this copy sends per window, well under what the others hear (SENDER_MAX)
local BAD_MAX = 5             -- broken messages before a sender is muted
local ASK_MAX = 6             -- fresh catch-up asks answered for one sender per SENDER_WINDOW
local QUIET_GAP = 600         -- a find announced this long after the last word from another copy may have reached nobody
local RESEND_MAX = 20         -- such finds sent again per SENDER_WINDOW, live finds included, well under SENDER_MAX
local RESEND_WAIT = 30        -- seconds before they go, so a newcomer's catch-up comes first
local ANNOUNCE_SPREAD = 3     -- seconds a find may wait before this copy announces it
local PING_SPREAD = 20        -- seconds a ping's answer may wait, so a channel's answers spread out
local PING_GAP = 600
local PING_MAX = 3            -- pings answered per PING_GAP, whoever sends them
local WHERE_GAP = 60          -- seconds before one player's "where do you share" is answered again
local WHERE_MAX = 20          -- such asks answered per SENDER_WINDOW, whoever sends them
local NEWS_MAX = 3            -- channel events one answer carries

function Engine.New(env)
    local e = setmetatable({ env = env, chanQ = {}, whisQ = {}, grpQ = {}, pumping = false, nextChan = 0, nextWhis = 0, nextGrp = 0,
        senders = {}, muted = {}, serving = {}, announced = {}, helloSent = false, lastHeard = nil, helped = {}, unreachable = {},
        round = { claims = {}, bestCount = -1 }, pageAfter = 0, sent = {} }, Engine)
    return e
end

-- why: a line for the developer's channel report
function Engine:Mute(sender, why)
    if not self.muted[sender] and why and self.env.report then self.env.report("muted", sender, why) end
    self.muted[sender] = true
end

function Engine:IsMuted(sender)
    return self.muted[sender] == true
end

-- past SENDER_MAX finds in the current window: the rest of it goes unheard
function Engine:IsCapped(sender)
    local b = self.senders[sender]
    return b ~= nil and self.env.now() - b.start <= SENDER_WINDOW and b.finds > SENDER_MAX
end

local function Bucket(self, sender)
    local now = self.env.now()
    local b = self.senders[sender]
    if not b or now - b.start > SENDER_WINDOW then
        b = { start = now, finds = 0, bad = 0 }
        self.senders[sender] = b
    end
    return b
end

-- a message this copy cannot read; a sound one from another version of the addon is let go without counting, and so
-- is a chat line (anything typed into the channel, or a line a chat filter changed on its way)
local function Bad(self, b, sender, msg, via)
    if via == "line" or P.OtherVersion(msg) then return end
    b.bad = b.bad + 1
    if b.bad >= BAD_MAX then self:Mute(sender, b.bad .. " unreadable messages") end
end

function Engine:Pump()
    if self.pumping then return end
    local env = self.env
    local function Step()
        self.pumping = false
        if #self.chanQ == 0 and #self.whisQ == 0 and #self.grpQ == 0 then return end
        if not env.canSend() then
            self.pumping = true
            env.after(5, Step)
            return
        end
        local now = env.now()
        local wait = 60
        if #self.whisQ > 0 then
            if now >= self.nextWhis then
                local m = self.whisQ[1]
                local r = env.send("WHISPER", m.to, m.msg)
                self.whisperedAt = now
                if r == "gone" then
                    self:Unreachable(m.to)
                elseif r == "ok" or r == "fail" then
                    table.remove(self.whisQ, 1)
                end
                self.nextWhis = now + (r == "wait" and 2 or WHISPER_GAP)
            end
            wait = math.min(wait, math.max(0.05, self.nextWhis - now))
        end
        if #self.chanQ > 0 then
            if now >= self.nextChan then
                local r = env.send("CHANNEL", nil, self.chanQ[1])
                if r == "ok" or r == "fail" then table.remove(self.chanQ, 1) end
                self.nextChan = now + (r == "wait" and 5 or CHANNEL_GAP)
            end
            wait = math.min(wait, math.max(0.05, self.nextChan - now))
        end
        if #self.grpQ > 0 then
            if now >= self.nextGrp then
                local m = self.grpQ[1]
                local r = env.send(m.dist, nil, m.msg)
                if r ~= "wait" then table.remove(self.grpQ, 1) end
                self.nextGrp = now + (r == "wait" and 5 or GROUP_GAP)
            end
            wait = math.min(wait, math.max(0.05, self.nextGrp - now))
        end
        if #self.chanQ > 0 or #self.whisQ > 0 or #self.grpQ > 0 then
            self.pumping = true
            env.after(wait, Step)
        end
    end
    self.pumping = true
    env.after(0, Step)
end

function Engine:QueueChannel(msg)
    -- one copy never floods the channel: old queued lines give way
    if #self.chanQ >= 30 then table.remove(self.chanQ, 1) end
    table.insert(self.chanQ, msg)
    self:Pump()
end

function Engine:QueueGroup(dist, msg)
    if #self.grpQ >= 30 then table.remove(self.grpQ, 1) end
    table.insert(self.grpQ, { dist = dist, msg = msg })
    self:Pump()
end

function Engine:QueueWhisper(to, msg)
    if self.unreachable[to] or #self.whisQ >= WHISPER_ROOM then return end
    table.insert(self.whisQ, { to = to, msg = msg })
    self:Pump()
end

-- the server says this player is not online: the rest of their page is dropped and nothing more is whispered to them
-- this session, since each whisper into nothing prints a line in the player's chat
function Engine:Unreachable(to)
    self.unreachable[to] = true
    local q, n = self.whisQ, 0
    for i = 1, #q do
        if q[i].to ~= to then
            n = n + 1
            q[n] = q[i]
        end
    end
    for i = #q, n + 1, -1 do q[i] = nil end
end

-- this copy saw something worth telling: once per item per session. fresh: new to this copy or changed, so it goes ahead
-- of repeats when finds have to wait
function Engine:Announce(rec, fresh)
    if self.announced[rec.id] then return end
    self.announced[rec.id] = true
    -- no other copy has spoken lately, so maybe none is online: the find goes out again once one speaks (saved on the
    -- find, so a logout in between keeps it)
    local env = self.env
    if not self.heardAt or env.now() - self.heardAt > QUIET_GAP then
        rec.uh = true
        if self.unheard then self.unheard = self.unheard + 1 end
    end
    -- a raid sees the same loot on every copy at once: each waits a moment and stays quiet when two other players have
    -- reported the item meanwhile (everyone listening then holds it, confirmed), or when a catch-up said it is
    -- confirmed (an old item said to be changed still needs real reports)
    env.after(env.random(0, ANNOUNCE_SPREAD * 1000) / 1000, function()
        if (rec.cf and not rec.pend) or (env.finds.OthersReporting and env.finds.OthersReporting(rec, env.me) >= 2) then
            if rec.uh then
                rec.uh = nil
                if self.unheard then self.unheard = math.max(0, self.unheard - 1) end
            end
            return
        end
        self:SendFind(rec, true, fresh)
    end)
end

-- a find on the channel, counted: past SEND_MAX in a window it waits for room (Hold), so the copies hearing it never
-- cut this one off. A live find also goes to the player's guild and group, so they get it wherever the channel does
-- not reach
function Engine:SendFind(rec, live, fresh)
    local now, sent = self.env.now(), self.sent
    while sent[1] and now - sent[1] > SENDER_WINDOW do table.remove(sent, 1) end
    if #sent >= SEND_MAX then return self:Hold(rec, live, fresh) end
    sent[#sent + 1] = now
    local msg = P.EncodeFind(rec)
    self:QueueChannel(msg)
    if live and self.env.groups then
        for _, dist in ipairs(self.env.groups()) do self:QueueGroup(dist, msg) end
    end
end

-- a find waiting for room: new finds go ahead of repeats. A new one is also marked unheard (saved on the find), so a
-- logout before its turn sends it with the next session's resend
function Engine:Hold(rec, live, fresh)
    local h = self.held or { fresh = {}, again = {}, ids = {} }
    self.held = h
    if fresh and not rec.uh then
        rec.uh = true
        if self.unheard then self.unheard = self.unheard + 1 end
    end
    if not h.ids[rec.id] then
        h.ids[rec.id] = true
        table.insert(fresh and h.fresh or h.again, { rec = rec, live = live, fresh = fresh })
    end
    self:DrainSoon()
end

-- the held finds go once the oldest send leaves the window
function Engine:DrainSoon()
    if self.drainDue then return end
    local env, sent = self.env, self.sent
    self.drainDue = true
    env.after(math.max(1, sent[1] and (sent[1] + SENDER_WINDOW - env.now() + 1) or 1), function()
        self.drainDue = nil
        self:Drain()
    end)
end

function Engine:Drain()
    local h = self.held
    if not h then return end
    local now, sent = self.env.now(), self.sent
    while sent[1] and now - sent[1] > SENDER_WINDOW do table.remove(sent, 1) end
    local env = self.env
    while #sent < SEND_MAX do
        local m = table.remove(h.fresh, 1) or table.remove(h.again, 1)
        if not m then break end
        local rec = m.rec
        h.ids[rec.id] = nil
        if rec.uh then
            rec.uh = nil
            if self.unheard then self.unheard = math.max(0, self.unheard - 1) end
        end
        -- two other players reported it while it waited, or a catch-up called it confirmed: nobody needs it any more
        local done = (rec.cf and not rec.pend) or (env.finds.OthersReporting and env.finds.OthersReporting(rec, env.me) >= 2)
        if not done then self:SendFind(rec, m.live, m.fresh) end
    end
    if #h.fresh + #h.again > 0 then self:DrainSoon() end
end

-- another copy spoke. A hello comes from a copy that just logged in or pressed Refresh, and right after this copy's
-- own login any copy online may have come while it was away: either may lack the finds that went out to nobody
function Engine:Heard(hello)
    self.heardAt = self.env.now()
    if hello or self.justIn then
        self.justIn = nil
        if self.unheard ~= 0 then self:ResendSoon(RESEND_WAIT) end
    end
end

function Engine:ResendSoon(wait)
    if self.resendDue then return end
    self.resendDue = true
    self.env.after(wait, function()
        self.resendDue = nil
        self:Resend()
    end)
end

-- the unheard finds again on the channel, a window's worth at a time. It waits while this copy serves a catch-up (a
-- served find has reached its asker) and keeps room in the channel queue for live lines
function Engine:Resend()
    local env = self.env
    if self.resending or not env.finds.Unheard or not env.canSend() then return end
    local now, sent = env.now(), self.sent
    if #self.whisQ > 0 or next(self.serving) or (self.whisperedAt and now - self.whisperedAt < RESEND_WAIT) then
        self:ResendSoon(10)
        return
    end
    while sent[1] and now - sent[1] > SENDER_WINDOW do table.remove(sent, 1) end
    local room = math.min(RESEND_MAX - #sent, 30 - 5 - #self.chanQ)
    if room <= 0 then
        self:ResendSoon(60)
        return
    end
    local list, left = env.finds.Unheard(room)
    self.unheard = left
    if #list == 0 then return end
    self.resending = true
    for _, rec in ipairs(list) do
        rec.uh = nil
        self:SendFind(rec, false, true)
    end
    env.after(SENDER_WINDOW, function()
        self.resending = false
        if self.unheard ~= 0 and self.heardAt and env.now() - self.heardAt <= QUIET_GAP then self:Resend() end
    end)
end

-- asks this server's copies for the finds changed since its bookmark (a day's overlap), one page at a time
function Engine:SayHello()
    if self.helloSent then return end
    self.helloSent = true
    local env = self.env
    self.lastHello = env.now()
    -- a run of pages starts here: its time becomes the bookmark once the last page is in
    if self.pageAfter == 0 then self.runStamp = env.stamp and env.stamp() or 0 end
    local since = 0
    if not self.everything then
        local mark = env.bookmark and env.bookmark()
        since = mark and math.max(0, mark - OVERLAP) or 0
    end
    local count, sum = env.finds.Summary()
    -- each ask elects its own server: claims for an earlier ask no longer steer the pages
    self.round = { claims = {}, bestCount = -1 }
    self:QueueChannel(P.EncodeHello(count, sum, since, self.pageAfter))
    -- an ask for a next page nobody answers means the last page was the end
    if self.pageAfter > 0 then
        local token = {}
        self.waiting = token
        env.after(PAGE_WAIT, function()
            if self.waiting == token then self:RunDone() end
        end)
    end
end

-- the last page is in: this server is caught up to when the run began
function Engine:RunDone()
    self.pageAfter, self.everything, self.waiting = 0, nil, nil
    self.caughtUp = true
    if self.env.setBookmark then self.env.setBookmark(self.runStamp or 0) end
end

-- the developer's button: every find this server's copies hold, from the start, whatever the bookmark says
function Engine:CollectAll()
    self.everything, self.pageAfter, self.waiting = true, 0, nil
    self.helloSent = false
    self:SayHello()
end

-- a player's Refresh: hello again, so copies holding finds this one lacks send them; at most once a minute
function Engine:AskAgain()
    if self.lastHello and self.env.now() - self.lastHello < 60 then return false end
    self.helloSent = false
    self:SayHello()
    return true
end

function Engine:OnLogin()
    local env = self.env
    self.justIn = true
    env.after(env.random(15, 60), function() self:SayHello() end)
end

function Engine:Serve(requester, since, after, holding)
    local env = self.env
    self.serving[requester] = nil
    local page = env.finds.Since(since, after, SERVE_LIMIT)
    -- a copy too busy to whisper the whole page leaves the asker to another copy, so no page arrives in part
    if #page == 0 or #self.whisQ + #page + 4 > WHISPER_ROOM then return end
    -- "I have it" goes out at once, ahead of anything queued, so the other copies stand down in time
    local claim = P.EncodeServing(requester, holding)
    if not env.canSend() or env.send("CHANNEL", nil, claim) ~= "ok" then
        table.insert(self.chanQ, 1, claim)
        self:Pump()
    end
    local known = {}
    for _, rec in ipairs(page) do
        -- an unheard find reaches this asker now
        if rec.uh then
            rec.uh = nil
            if self.unheard then self.unheard = math.max(0, self.unheard - 1) end
        end
        self:QueueWhisper(requester, P.EncodeFind(rec))
        -- a page carries no reporters, so the asker would report these again on seeing them: it is told which are confirmed
        if not rec.pend and (rec.cf or (env.finds.Confirmed and env.finds.Confirmed(rec))) then known[#known + 1] = rec.id end
    end
    for _, m in ipairs(P.EncodeKnown(known)) do self:QueueWhisper(requester, m) end
    self:QueueWhisper(requester, P.EncodeEnd(#page, page[#page].id))
end

-- the same find sent as an addon message and as a chat line: the two routes may name the sender differently, so a
-- report is also known by its exact text and route for a window (two windows kept, so none slips through at the turn).
-- The same text by the other route is that copy again; by the same route it is another player's report
local function SeenText(self, msg, via)
    local now, route = self.env.now(), via or "message"
    if not self.textNow or now - self.textAt > SENDER_WINDOW then
        self.textOld, self.textNow, self.textAt = self.textNow or {}, {}, now
    end
    local was = self.textNow[msg] or self.textOld[msg]
    if was and was ~= route then return true end
    self.textNow[msg] = was or route
    return false
end

-- the developer's ping: each copy answers once, with its addon, its version and how the ping reached it (an addon
-- message, a chat line or both), on the channel and by whisper. The wait before answering lets both routes arrive
function Engine:Ping(sender, token, via)
    local env, how = self.env, via == "line" and "l" or "m"
    self.pings = self.pings or {}
    local p = self.pings[token]
    if p then
        p[how] = true
        return
    end
    local now, times = env.now(), self.pingTimes or {}
    self.pingTimes = times
    while times[1] and now - times[1] > PING_GAP do table.remove(times, 1) end
    if #times >= PING_MAX then return end
    times[#times + 1] = now
    p = { [how] = true }
    self.pings[token] = p
    env.after(2 + env.random(0, PING_SPREAD * 1000) / 1000, function()
        -- by whisper only: a ping on a busy channel would otherwise fill it with every copy's answer
        local answer = P.EncodeAnswer(token, (p.m and "m" or "") .. (p.l and "l" or ""), env.host or "?", env.version or "?")
        self:QueueWhisper(sender, answer)
    end)
end

-- a player whose copy spoke: one to ask where the copies share at a later login
function Engine:Peer(sender)
    if self.env.onPeer then self.env.onPeer(sender) end
end

-- a copy logging in asks where the copies share: the answer is this copy's channel name, then the channel events it saw
-- itself that the asker does not hold yet (newer than its newest), all by whisper
function Engine:Where(sender, newest)
    local env = self.env
    if not (env.here and env.here()) then return end
    local now = env.now()
    self.whereAt = self.whereAt or {}
    if self.whereAt[sender] and now - self.whereAt[sender] < WHERE_GAP then return end
    local times = self.whereTimes or {}
    self.whereTimes = times
    while times[1] and now - times[1] > SENDER_WINDOW do table.remove(times, 1) end
    if #times >= WHERE_MAX then return end
    times[#times + 1] = now
    self.whereAt[sender] = now
    env.after(env.random(200, 2000) / 1000, function()
        local slot = env.here()
        if not slot then return end
        self:QueueWhisper(sender, P.EncodeHere(slot))
        for _, ev in ipairs(env.news and env.news(newest, NEWS_MAX) or {}) do self:QueueWhisper(sender, P.EncodeEvent(ev)) end
    end)
end

-- via: "line" for a chat line on the channel, nil for an addon message
function Engine:Receive(msg, dist, sender, via)
    local env = self.env
    if not sender or sender == env.me or (env.isMe and env.isMe(sender)) or self.muted[sender] then return end
    -- a banned player is not heard at all
    if env.banned and env.banned(sender) then return end
    local kind = P.Kind(msg)
    -- the guild and the group carry live finds, the guild also the channel news; asks, claims and pages stay on the
    -- channel and whispers
    if dist ~= "CHANNEL" and dist ~= "WHISPER" and kind ~= "F" and not (dist == "GUILD" and (kind == "R" or kind == "W")) then return end
    local b = Bucket(self, sender)
    if kind == "F" then
        local info = P.DecodeFind(msg)
        if not info then return Bad(self, b, sender, msg, via) end
        self:Peer(sender)
        self:Heard()
        -- a find heard on the channel, the guild or the group is a first-hand report; a whispered one is a catch-up
        -- copy. The same report on two of them counts and records once
        local firstHand = dist ~= "WHISPER"
        if firstHand then
            b.heard = b.heard or {}
            if b.heard[msg] then return end
            b.heard[msg] = true
            if SeenText(self, msg, via) then return end
        end
        -- pages are expected from a copy that served this one lately, and from any copy soon after this one asked: a
        -- claim goes out as a chat line that waits for a key press, so several copies may serve one ask unheard
        local now, served, asked = env.now(), self.helped[sender], self.lastHello
        local expected = (served and now - served < SENDER_WINDOW) or (asked and now - asked < SENDER_WINDOW)
        -- only finds that teach this copy something count: a vendor list or a bag of items it already holds costs the
        -- sender nothing. Past the cap the rest of the window goes unheard and the sender is heard again in the next one;
        -- fakes are harmless anyway
        if not (dist == "WHISPER" and expected) then
            if b.finds > SENDER_MAX then return end
            if not env.finds.Adds or env.finds.Adds({ id = info.id, fp = info.fp, src = info.src, reporter = firstHand and sender or nil }) then
                b.finds = b.finds + 1
                if b.finds > SENDER_MAX then
                    if env.report then env.report("capped", sender, b.finds .. " finds this copy lacked, within 5 minutes") end
                    return
                end
            end
        end
        self.lastHeard = env.now()
        -- the server names the sender and nothing else in a message can be trusted: a credit stands only when it names
        -- the sender (a finder reporting or serving its own find). Forever names a sender "First Surname" while the
        -- credit carries the first name
        local base = sender:match("^[^-]+") or sender
        if info.by and info.by ~= base and info.by ~= base:match("^(%S+)%s") then info.by = nil end
        env.accept(info, sender, function(ok)
            if not ok then return end
            info.fromNet = true
            info.reporter = firstHand and sender or nil
            -- a catch-up copy is old news: it fills the feed and the database but never pops up
            info.quiet = not firstHand or nil
            local status, rec = env.finds.Record(info)
            if rec and self.knownSoon and self.knownSoon[info.id] then
                rec.cf = true
                self.knownSoon[info.id] = nil
            end
            if status and env.onRecorded then env.onRecorded(rec, status, info) end
        end)
    elseif kind == "H" then
        local count, sum, since, after = P.DecodeHello(msg)
        if not count then return Bad(self, b, sender, msg, via) end
        self:Peer(sender)
        -- a fresh ask comes at login and at most once a minute from Refresh; past ASK_MAX in a window more asks go
        -- unanswered, without a mute (a player reloading a lot is no troublemaker; a page run's next asks carry a cursor
        -- and are not counted)
        if (after or 0) == 0 then
            b.asks = (b.asks or 0) + 1
            if b.asks > ASK_MAX then return end
        end
        self:Heard(true)
        local myCount, mySum = env.finds.Summary()
        if myCount == count and mySum == sum then return end
        local holding = env.finds.CountSince(since, after)
        if holding == 0 or self.serving[sender] then return end
        -- many copies hear the same hello: each waits a random moment and stands down when a copy holding about as much
        -- answers first, so a much bigger holder still answers after a small one (the asker follows the biggest); the
        -- more copies around, the longer the spread, so two equal holders rarely answer at once
        local peers = 0
        for _ in pairs(self.senders) do peers = peers + 1 end
        local spread = math.min(20, 4 + math.floor(peers / 4))
        local token = {}
        self.serving[sender] = { token = token, holding = holding }
        env.after(1 + env.random(0, spread * 1000) / 1000, function()
            local mine = self.serving[sender]
            if not mine or mine.token ~= token then return end
            self:Serve(sender, since, after, holding)
        end)
    elseif kind == "Y" then
        local target, count = P.DecodeServing(msg)
        if not target then return Bad(self, b, sender, msg, via) end
        self:Heard()
        local mine = self.serving[target]
        -- a claim near this copy's own holding settles it; a much smaller one does not
        if mine and count >= mine.holding - math.max(5, math.floor(mine.holding / 10)) then self.serving[target] = nil end
        if target == env.me or (env.isMe and env.isMe(target)) then
            self.lastHeard = env.now()
            self.helped[sender] = env.now()
            self.waiting = nil
            local round = self.round
            round.claims[sender] = true
            if count > round.bestCount then round.best, round.bestCount = sender, count end
        end
    elseif kind == "E" then
        local n, last = P.DecodeEnd(msg)
        if not n or dist ~= "WHISPER" then return Bad(self, b, sender, msg, via) end
        self:Heard()
        -- only the biggest holder that claimed this ask steers the pages; late or smaller pages only add finds
        local round = self.round
        if not round.claims[sender] then return end
        round.claims[sender] = nil
        if round.best ~= sender then return end
        if n >= SERVE_LIMIT then
            -- a full page: the next one starts after its last item
            self.pageAfter = last
            env.after(PAGE_GAP, function()
                self.helloSent = false
                self:SayHello()
            end)
        else
            self:RunDone()
        end
    elseif kind == "Q" then
        local token = P.DecodePing(msg)
        if not token then return Bad(self, b, sender, msg, via) end
        if dist == "CHANNEL" then self:Ping(sender, token, via) end
    elseif kind == "A" then
        local token, heard, host, version = P.DecodeAnswer(msg)
        if not token then return Bad(self, b, sender, msg, via) end
        if env.onAnswer then env.onAnswer(sender, token, heard, host, version, dist, via) end
    elseif kind == "K" then
        local ids = P.DecodeKnown(msg)
        if not ids then return Bad(self, b, sender, msg, via) end
        -- taken like the pages it follows: by whisper, from a copy that served this one or soon after this one asked
        local now, served, asked = env.now(), self.helped[sender], self.lastHello
        if dist ~= "WHISPER" or not ((served and now - served < SENDER_WINDOW) or (asked and now - asked < SENDER_WINDOW)) then return end
        self.knownSoon = self.knownSoon or {}
        for _, id in ipairs(ids) do
            local rec = env.finds.Get and env.finds.Get(id)
            if rec then rec.cf = true else self.knownSoon[id] = true end
        end
    elseif kind == "R" then
        local newest = P.DecodeWhere(msg)
        if not newest then return Bad(self, b, sender, msg, via) end
        if dist == "CHANNEL" then return end
        self:Peer(sender)
        self:Where(sender, newest)
    elseif kind == "N" then
        local slot = P.DecodeHere(msg)
        if not slot then return Bad(self, b, sender, msg, via) end
        if dist ~= "WHISPER" then return end
        self:Peer(sender)
        if env.onHere then env.onHere(sender, slot) end
    elseif kind == "W" then
        local ev = P.DecodeEvent(msg)
        if not ev then return Bad(self, b, sender, msg, via) end
        if dist == "CHANNEL" then return end
        self:Peer(sender)
        if env.onEvent then env.onEvent(sender, ev) end
    else
        Bad(self, b, sender, msg, via)
    end
end

-- the WoW side: channel, prefix, lockdown, events
local S = {}
ns.Sync = S

local CHANNEL = "ForeverItemFinder"
local PASSWORD = "fif1"
S.CHANNEL = CHANNEL
-- the channel and its backups (ForeverItemFinder2 and on). Anyone can join with the password, so whoever owns a
-- channel can lock it: a copy refused at the door walks to the next name, and a takeover seen inside (a new password,
-- moderation, a kick or ban, a lost voice) moves every copy in it to the next name at once. Each login starts at the
-- first, so copies meet again on the lowest name that works
local NAMES = 9
local slot, hops, refused = 1, 0, false
-- toldSlot: the name the copies that answered at login share on
local toldSlot
local function NameOf(n) return n == 1 and CHANNEL or (CHANNEL .. n) end
local function Current() return NameOf(slot) end
S.NameOf = NameOf

-- the number of one of our names (1 the plain name), nil for any other channel
local function SlotOf(name)
    local n = name:lower()
    if n == CHANNEL:lower() then return 1 end
    local i = tonumber(n:match("^" .. CHANNEL:lower() .. "(%d)$"))
    if i and i >= 2 and i <= NAMES then return i end
end

-- this realm's part of a saved table (each realm has its own channels)
local function Realm(key)
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not ns.db or type(realm) ~= "string" or realm == "" or ns.Secret(realm) then return nil end
    ns.db[key] = ns.db[key] or {}
    local t = ns.db[key][realm] or {}
    ns.db[key][realm] = t
    return t
end

-- Knocking on a locked name makes the game show its own password box, which no chat filter stops. A name refused
-- once is kept per realm for a day and passed by without knocking, so a locked name costs a player one box a day
local LOCK_FOR = 24 * 3600
local function Locks() return Realm("locked") end
local function IsLocked(name)
    local t = Locks()
    local at = t and t[name:lower()]
    if not at then return false end
    if ns.Now() - at >= LOCK_FOR then
        t[name:lower()] = nil
        return false
    end
    return true
end
local function MarkLocked(name)
    local t = Locks()
    if t then t[name:lower()] = ns.Now() end
end

local engine
local joinTries = 0
S.state = "starting"     -- starting / on / nochannel / paused

local function Me()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm ~= "" and not ns.Secret(realm) then return name .. "-" .. realm end
    return name
end

-- Forever names a player's messages by first name and surname ("Name Surname"), not Name-Realm
local function IsMe(name)
    if type(name) ~= "string" or ns.Secret(name) or name == "" then return false end
    if name == Me() then return true end
    local full = NameUtil and NameUtil.GetUnmodifiedUnitFullName and NameUtil.GetUnmodifiedUnitFullName("player")
    if type(full) ~= "string" or ns.Secret(full) or full == "" then return false end
    if name == full then return true end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return type(realm) == "string" and not ns.Secret(realm) and name == full .. "-" .. realm
end

-- a player's name the way the ban list and the report write it, with the realm (the game leaves this player's own
-- realm off some names)
local function Full(name)
    if type(name) ~= "string" or ns.Secret(name) or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm ~= "" and not ns.Secret(realm) then return name .. "-" .. realm end
    return name
end
S.Full = Full

-- On Forever a player's messages carry the first name and surname, with a realm only now and then, so a ban written
-- with a surname matches that name with or without a realm. A first name alone stays exact: it is shared by many
local SURNAME = Constants and Constants.CharacterNameSeparatorConsts and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
if type(SURNAME) ~= "string" or SURNAME == "" then SURNAME = " " end
local function Surnamed(name)
    local base = name:gsub("%-[^-]+$", "")
    if base:find(SURNAME, 1, true) then return base end
end
S.Surnamed = Surnamed

local function Banned(sender)
    if type(sender) ~= "string" or ns.Secret(sender) or not ns.BANS then return false end
    local full = Full(sender)
    if full ~= nil and ns.BANS[full] == true then return true end
    local base = ns.isForever and Surnamed(sender)
    if not base then return false end
    for name in pairs(ns.BANS) do
        if Surnamed(name) == base then return true end
    end
    return false
end
S.Banned = Banned

-- the developer's channel report: what this copy saw done to the channel and whom it muted, as facts with the names the
-- server gave; whether anyone is banned stays the developer's call
local REPORT_MAX = 200
local function Report(text)
    if not ns.DEV or not ns.db then return end
    local r = ns.db.report or {}
    ns.db.report = r
    r[#r + 1] = { t = ns.Now(), text = text }
    while #r > REPORT_MAX do table.remove(r, 1) end
    ns.Signal("ReportChanged")
end
S.Report = Report

local function ChannelNumber()
    local id = GetChannelName(Current())
    if type(id) == "number" and id > 0 then return id end
end

local function HideChannel()
    local name = Current()
    for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if frame.RemoveChannel then
                frame:RemoveChannel(name)
            elseif ChatFrame_RemoveChannel then
                ChatFrame_RemoveChannel(frame, name)
            end
        end
    end
end

-- the hidden channel sits after every other channel, so the game's own keep their numbers (/1 stays General). The
-- game saves each channel's number per character: one that once joined before the world channels pushes them up at
-- every login until it is moved. Each step swaps it with the next number, the way the chat settings' reorder does
local function ToEnd()
    if S.state ~= "on" or not (C_ChatInfo.SwapChatChannelsByChannelIndex and GetChannelList) then return end
    if InCombatLockdown and InCombatLockdown() then
        S.toEndAfterCombat = true
        return
    end
    local mine = ChannelNumber()
    if not mine then return end
    local last = mine
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id = list[i]
        if type(id) == "number" and not ns.Secret(id) and id > last then last = id end
    end
    if last == mine then return end
    for at = mine, last - 1 do C_ChatInfo.SwapChatChannelsByChannelIndex(at, at + 1) end
    HideChannel()
end
S.ToEnd = ToEnd

local toEndDue = false
local function ToEndSoon()
    if toEndDue then return end
    toEndDue = true
    C_Timer.After(2, function()
        toEndDue = false
        ToEnd()
    end)
end

-- nothing of the channel ever reaches a chat window, whatever someone types into it
local function Filter(_, _, _, _, _, _, _, _, _, _, channelName)
    if type(channelName) == "string" and not ns.Secret(channelName) and channelName:find(CHANNEL, 1, true) then
        return true
    end
end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
    addFilter("CHAT_MSG_CHANNEL", Filter)
    addFilter("CHAT_MSG_CHANNEL_NOTICE", Filter)
    addFilter("CHAT_MSG_CHANNEL_NOTICE_USER", Filter)
    addFilter("CHAT_MSG_CHANNEL_JOIN", Filter)
    addFilter("CHAT_MSG_CHANNEL_LEAVE", Filter)
end

local Hop
local function Join()
    if ChannelNumber() then
        HideChannel()
        S.state = "on"
        ToEndSoon()
        ns.Signal("SyncState")
        return true
    end
    -- a name found locked lately is passed by without knocking, unless the copies that answered share there now
    if IsLocked(Current()) and slot ~= toldSlot then return Hop() end
    joinTries = joinTries + 1
    refused = false
    local at = slot
    local join = JoinTemporaryChannel or JoinChannelByName
    if join then join(Current(), PASSWORD) end
    C_Timer.After(2, function()
        if slot ~= at then return end
        if ChannelNumber() then
            HideChannel()
            S.state = "on"
            ToEndSoon()
        elseif refused then
            return Hop()
        elseif joinTries < 3 then
            C_Timer.After(30, Join)
        else
            S.state = "nochannel"
        end
        ns.Signal("SyncState")
    end)
end

-- on to the next name, leaving the locked one; after every name has failed once this session, sharing pauses
function Hop()
    local old = Current()
    hops = hops + 1
    local id = GetChannelName(old)
    if type(id) == "number" and id > 0 and LeaveChannelByName then LeaveChannelByName(old) end
    if hops >= NAMES then
        S.state = "nochannel"
        Report("every channel name failed this session: sharing paused")
        ns.Signal("SyncState")
        return
    end
    slot = slot % NAMES + 1
    Report("moved from " .. old .. " to " .. Current())
    joinTries = 0
    S.state = "starting"
    ns.Signal("SyncState")
    C_Timer.After(1, function()
        Join()
        -- a copy not caught up yet asks again on the new channel; the others already hold what it holds
        if engine and not engine.caughtUp then
            C_Timer.After(math.random(5, 30), function()
                if S.state ~= "on" then return end
                engine.helloSent = false
                engine:SayHello()
            end)
        end
    end)
end

-- notices about the channel in use: only its owner or a moderator can do these, and copies never do
local TAKEOVER = { PASSWORD_CHANGED = true, MODERATION_ON = true, PLAYER_KICKED = true, PLAYER_BANNED = true,
    UNSET_VOICE = true, MUTED = true }

-- the report's words per notice. The game's notice strings put the acting player first when there is one name
-- ("Password changed by %s") and the player acted on first, the actor second, when there are two ("Player %s kicked by
-- %s"); a name the notice leaves out is never guessed
local NOBODY = "an unnamed player"
local SAID = {
    PASSWORD_CHANGED = function(first) return "password changed by " .. (first or NOBODY) end,
    MODERATION_ON = function(first) return "moderation turned on by " .. (first or NOBODY) end,
    PLAYER_KICKED = function(first, second) return (first or NOBODY) .. " kicked by " .. (second or NOBODY) end,
    PLAYER_BANNED = function(first, second) return (first or NOBODY) .. " banned by " .. (second or NOBODY) end,
    UNSET_VOICE = function(first, second) return (first or NOBODY) .. " lost chat permission" .. (second and (", by " .. second) or "") end,
    SET_MODERATOR = function(first, second) return (first or NOBODY) .. " made a moderator" .. (second and (", by " .. second) or "") end,
    MUTED = function() return "this copy may not speak there" end,
    WRONG_PASSWORD = function() return "our password was refused" end,
    BANNED = function() return "this character is banned there" end,
}
-- a notice names a player by first name and realm; the channel's member list holds the full name their messages carry,
-- the one a ban needs. Looked up by the notice's player id, and only when the first names agree
local function MemberName(guid, first, channel)
    if type(guid) ~= "string" or guid == "" or ns.Secret(guid) or type(first) ~= "string" or ns.Secret(first) then return end
    if not (C_ChatInfo.GetChannelRosterInfo and GetNumDisplayChannels and GetChannelDisplayInfo) then return end
    local want, short = channel:lower(), first:match("^[^-]+")
    if not short then return end
    for i = 1, GetNumDisplayChannels() or 0 do
        local name, header, _, _, count = GetChannelDisplayInfo(i)
        if not header and type(name) == "string" and not ns.Secret(name) and name:lower() == want
            and type(count) == "number" and not ns.Secret(count) then
            for r = 1, count do
                local n, _, _, g = C_ChatInfo.GetChannelRosterInfo(i, r)
                if type(g) == "string" and not ns.Secret(g) and g == guid and type(n) == "string" and not ns.Secret(n)
                    and n ~= short and n:sub(1, #short) == short then
                    return n
                end
            end
        end
    end
end

local function Ours(name) return SlotOf(name) ~= nil end

-- The name log: what players did to our channels, with the names the game gave, kept per realm so players can see who
-- locked one. A copy writes down what it saw and passes it on; what others passed on shows as told, by how many
local WHO_MAX = 30
local WHO_KEEP = 30 * 86400
local NEWS_FRESH = 7 * 86400  -- events younger than this go to copies logging in
local SAME_WINDOW = 300       -- two copies' times for one event differ by their clocks and the notice's way to each
local function Who()
    local t = Realm("who")
    if not t then return nil end
    local now = ns.Now()
    for i = #t, 1, -1 do
        if type(t[i]) ~= "table" or type(t[i].t) ~= "number" or now - t[i].t > WHO_KEEP then table.remove(t, i) end
    end
    return t
end
S.Who = Who

local function Newest()
    local t = Who()
    return t and t[#t] and t[#t].t or 0
end

-- a notice names a player by first name and realm, the member list by first name and surname: they agree on the first
local function FirstOf(name)
    if type(name) ~= "string" then return "" end
    local base = name:gsub("%-[^-]+$", "")
    local i = base:find(SURNAME, 1, true)
    return (i and base:sub(1, i - 1) or base):lower()
end

local function Same(a, b)
    return a.slot == b.slot and a.kind == b.kind and math.abs(a.t - b.t) <= SAME_WINDOW
        and FirstOf(a.by) == FirstOf(b.by) and FirstOf(a.on) == FirstOf(b.on)
end

-- a name with the surname tells players apart, one without does not
local function Fuller(old, new)
    if not new then return old end
    if not old then return new end
    local oldBase, newBase = old:gsub("%-[^-]+$", ""), new:gsub("%-[^-]+$", "")
    if newBase:find(SURNAME, 1, true) and not oldBase:find(SURNAME, 1, true) then return new end
    return old
end

-- teller: who passed it on, nil when this copy saw it. Returns the entry and whether it is new
local function AddEvent(ev, teller)
    local t = Who()
    if not t then return end
    for _, e in ipairs(t) do
        if Same(e, ev) then
            if teller then
                e.told = e.told or {}
                e.told[teller] = true
            else
                e.mine = true
            end
            e.by, e.on = Fuller(e.by, ev.by), Fuller(e.on, ev.on)
            ns.Signal("WhoChanged")
            return e, false
        end
    end
    local e = { t = ev.t, slot = ev.slot, kind = ev.kind, by = ev.by, on = ev.on, mine = not teller or nil,
        told = teller and { [teller] = true } or nil }
    t[#t + 1] = e
    table.sort(t, function(a, b) return a.t < b.t end)
    while #t > WHO_MAX do table.remove(t, 1) end
    ns.Signal("WhoChanged")
    return e, true
end
S.AddEvent = AddEvent

-- the events this copy saw itself after time since, newest first, at most n: what a copy logging in is told
local function News(since, n)
    local out, t = {}, Who()
    if not t then return out end
    local now = ns.Now()
    for i = #t, 1, -1 do
        local e = t[i]
        if #out >= n or e.t <= since then break end
        if e.mine and now - e.t <= NEWS_FRESH then out[#out + 1] = e end
    end
    return out
end

local NOBODY_SHORT = "an unnamed player"
local EVENT_WORDS = {
    PASSWORD_CHANGED = function(by) return "locked with a password by " .. by end,
    MODERATION_ON = function(by) return "moderation turned on by " .. by end,
    PLAYER_KICKED = function(by, on) return on .. " kicked by " .. by end,
    PLAYER_BANNED = function(by, on) return on .. " banned by " .. by end,
    UNSET_VOICE = function(by, on) return on .. " silenced by " .. by end,
    SET_MODERATOR = function(by, on) return on .. " made a moderator by " .. by end,
}
local function EventText(e)
    return NameOf(e.slot) .. ": " .. EVENT_WORDS[e.kind](e.by or NOBODY_SHORT, e.on or NOBODY_SHORT)
end
S.EventText = EventText

-- the window footer's list: the newest n events, newest first, with when and who saw them
function S.WhoLines(n)
    local out, t = {}, Who() or {}
    for i = #t, math.max(1, #t - n + 1), -1 do
        local e = t[i]
        local tellers = 0
        for _ in pairs(e.told or {}) do tellers = tellers + 1 end
        local seen = e.mine and "seen by you" or ("told by " .. tellers .. (tellers == 1 and " player" or " players"))
        out[#out + 1] = EventText(e) .. " (" .. date("%b %d, %H:%M", e.t) .. ", " .. seen .. ")"
    end
    return out
end

-- a copy that saw it tells its guild a moment later, unless a guildmate's copy told it first
local function SpreadSoon(e)
    if not engine or not (IsInGuild and IsInGuild()) then return end
    C_Timer.After(math.random(1000, 10000) / 1000, function()
        if e.told and next(e.told) then return end
        engine:QueueGroup("GUILD", P.EncodeEvent(e))
    end)
end

-- the one-name notices name the player who acted; the two-name ones the player acted on, then the one who acted
local ONE_NAME = { PASSWORD_CHANGED = true, MODERATION_ON = true }
local function Witness(kind, first, second, name, guid)
    local function Best(n) return MemberName(guid, n, name) or Full(n) end
    local by, on
    if ONE_NAME[kind] then by = Best(first) else on, by = Best(first), Best(second) end
    -- a new moderator with nobody named is the game handing the channel to its next owner, which happens all the time
    if (kind == "SET_MODERATOR" and not by) or (not by and not on) then return end
    local e, new = AddEvent({ t = ns.Now(), slot = SlotOf(name), kind = kind, by = by, on = on })
    if e and new then SpreadSoon(e) end
end

-- arg2 is a notice's first player, arg5 its second, arg9 the channel
local function Notice(kind, first, _, _, second, _, _, _, name, _, _, guid)
    if ns.Secret(kind) or ns.Secret(name) or type(kind) ~= "string" or type(name) ~= "string" then return end
    if SAID[kind] and Ours(name) then
        local function Named(n)
            local full, member = Full(n), MemberName(guid, n, name)
            return full and member and (full .. " (" .. member .. ")") or full
        end
        Report(name .. ": " .. SAID[kind](Named(first), Named(second)))
    end
    if P.EVENTS[kind] and Ours(name) then Witness(kind, first, second, name, guid) end
    if name:lower() ~= Current():lower() then return end
    if kind == "WRONG_PASSWORD" or kind == "BANNED" then
        if kind == "WRONG_PASSWORD" then MarkLocked(name) end
        refused = true
    elseif TAKEOVER[kind] and S.state == "on" then
        if kind == "PASSWORD_CHANGED" then MarkLocked(name) end
        Hop()
    elseif kind == "YOU_LEFT" and S.state == "on" then
        -- put out of the channel: back in, or on to the next name when the door stays shut
        S.state = "starting"
        joinTries = 0
        C_Timer.After(2, Join)
    end
end
ns.On("CHAT_MSG_CHANNEL_NOTICE", Notice)
ns.On("CHAT_MSG_CHANNEL_NOTICE_USER", Notice)
-- the game asks for a password (its own box is already up) when a name we knock on is locked: that name refused us
ns.On("CHANNEL_PASSWORD_REQUEST", function(name)
    if type(name) ~= "string" or ns.Secret(name) or not Ours(name) then return end
    MarkLocked(name)
    Report(name .. ": a password we do not know was asked for")
    if name:lower() == Current():lower() then refused = true end
end)

-- AreOutgoingAddonChatMessagesRestricted is no send gate: it reads true on ordinary realms (tournament realms clear it)
-- while addon messages still go out there
local function CanSend()
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
    return true
end

-- Chat lines: every channel message also goes out as an ordinary chat line on the channel, which every copy reads back
-- (Forever may not carry addon messages on a channel; chat lines always arrive). An addon may only chat while the
-- game handles a real key press or click, so lines wait here and one goes per press, LINE_GAP apart
local LINE = P.PREFIX .. " "
local LINE_GAP = 2
local LINE_ROOM = 30
-- the server sends a player's own lines back, and drops lines that come too fast: a line that is not back in
-- LINE_BACK seconds was dropped, so it goes again after a pause that doubles with each drop in a row
local LINE_BACK = 5
local LINE_PAUSE = 10
local LINE_PAUSE_MAX = 120
local LINE_TRIES = 4
local lines = {}
S.lines = { sent = 0, heard = 0, off = false, nextAt = 0, back = 0, dropped = 0, lost = 0, gap = LINE_GAP, tries = {} }

local function QueueLine(msg)
    if S.lines.off then return end
    if #lines >= LINE_ROOM then table.remove(lines, 1) end
    lines[#lines + 1] = msg
end

-- the line in flight was dropped: back to the front of the queue, unless it has had its tries
local function Dropped(now)
    local L = S.lines
    local text = L.out
    L.out = nil
    if not text then return end
    L.dropped = L.dropped + 1
    if (L.tries[text] or 0) >= LINE_TRIES then
        L.tries[text] = nil
        L.lost = L.lost + 1
    else
        table.insert(lines, 1, text)
    end
    L.gap = math.min(LINE_PAUSE_MAX, L.gap < LINE_PAUSE and LINE_PAUSE or L.gap * 2)
    L.nextAt = now + L.gap
    if S.OnDrop then S.OnDrop(text, L.tries[text] == nil, L.gap) end
end

-- this player's own line came back from the server
local function CameBack(msg)
    local L = S.lines
    L.back = L.back + 1
    if L.out == msg then
        L.out = nil
        L.tries[msg] = nil
        L.gap = math.max(LINE_GAP, L.gap / 2)
        L.nextAt = math.min(L.nextAt, L.outAt + L.gap)
    end
end

function S.LinesWaiting()
    return #lines
end

-- whisper names by sender (a player from another realm needs the realm), and the whispers sent lately by the name used
local route, whispered = {}, {}
local BOUNCE_WAIT = 30
local NOT_FOUND = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S:find("%s", 1, true)
    and ("^" .. (ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)")) .. "$") or nil

-- the server's "no player named" answer to a whisper this copy sent: the sender it was meant for, else nil
local function Bounce(msg)
    if not NOT_FOUND or type(msg) ~= "string" or ns.Secret(msg) then return end
    local name = msg:match(NOT_FOUND)
    name = name and name:lower()
    local w = name and (whispered[name] or whispered[name:match("^[^-]+")])
    if w and GetTime() - w.at < BOUNCE_WAIT then return w.to end
end
S.Bounce = Bounce

if addFilter then
    addFilter("CHAT_MSG_SYSTEM", function(_, _, msg) return Bounce(msg) ~= nil end)
end
ns.On("CHAT_MSG_SYSTEM", function(msg)
    local to = Bounce(msg)
    if not to or not engine or engine.unreachable[to] then return end
    engine:Unreachable(to)
    if S.OnBounce then S.OnBounce(to) end
end)

-- a chat line's sender from another realm is whispered with that realm, or the server looks for them on this one
local function ReplyName(name, sender, guid)
    if name:find("-", 1, true) or not GetPlayerInfoByGUID then return end
    local realm = select(7, GetPlayerInfoByGUID(guid))
    if type(realm) ~= "string" or ns.Secret(realm) or realm == "" then return end
    return name .. "-" .. (sender:match("%-(.+)$") or realm:gsub("%s", ""))
end

-- Before its first knock, a copy asks where the copies share: its guild, and the players whose copies it heard lately
-- (a whisper to one who is offline bounces quietly). It goes straight to the lowest name an answer gives, so a name
-- locked while it was away costs no password box
local PEER_MAX = 40
local PEER_FRESH = 14 * 86400
local ASK_PEERS = 5
local told = {}

local function RecordPeer(sender)
    if type(sender) ~= "string" or ns.Secret(sender) or sender == "" or IsMe(sender) or Banned(sender) then return end
    local t = Realm("peers")
    if not t then return end
    t[route[sender] or sender] = ns.Now()
    local n, oldest, at = 0, nil, nil
    for k, v in pairs(t) do
        n = n + 1
        if type(v) ~= "number" or not at or v < at then oldest, at = k, type(v) == "number" and v or -1 end
    end
    if n > PEER_MAX then t[oldest] = nil end
end

local function AskWhere()
    if not engine or not CanSend() then return end
    local msg = P.EncodeWhere(Newest())
    if IsInGuild and IsInGuild() then engine:QueueGroup("GUILD", msg) end
    local list, now = {}, ns.Now()
    for name, at in pairs(Realm("peers") or {}) do
        if type(at) == "number" and now - at <= PEER_FRESH then list[#list + 1] = { name = name, at = at } end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    for i = 1, math.min(ASK_PEERS, #list) do engine:QueueWhisper(list[i].name, msg) end
end

-- answers count until this copy first knocks; the lowest name wins, so one wrong answer cannot pull it away from where
-- the others are
local function OnHere(sender, n)
    if n > NAMES then return end
    if not told.slot or n < told.slot then told.slot = n end
    Report((Full(sender) or "?") .. " says the copies share on " .. NameOf(n))
end

local function OnEvent(sender, ev)
    local now = ns.Now()
    if ev.slot > NAMES or ev.t > now + SAME_WINDOW or now - ev.t > WHO_KEEP then return end
    local e, new = AddEvent(ev, sender)
    if e and new then Report("told by " .. (Full(sender) or "?") .. ": " .. EventText(e)) end
end

local function Here()
    if S.state == "on" and ChannelNumber() then return slot end
end

local RESULT = Enum and Enum.SendAddonMessageResult
local function Send(dist, target, msg)
    if dist == "CHANNEL" then
        local num = ChannelNumber()
        if not num then return "fail" end
        target = tostring(num)
    elseif dist == "WHISPER" then
        local to = target
        target = route[to] or to
        local w = { to = to, at = GetTime() }
        whispered[target:lower()] = w
        whispered[target:lower():match("^[^-]+")] = w
    end
    local r = C_ChatInfo.SendAddonMessage(P.PREFIX, msg, dist, target)
    local out = "fail"
    if r == nil or r == true or r == 0 or (RESULT and r == RESULT.Success) then
        out = "ok"
    elseif (RESULT and (r == RESULT.AddonMessageThrottle or r == RESULT.ChannelThrottle or r == RESULT.AddOnMessageLockdown))
        or r == 3 or r == 8 or r == 11 then
        out = "wait"
    elseif (RESULT and r == RESULT.TargetOffline) or r == 12 then
        out = "gone"
    end
    -- a message held back is sent again later: its line waits for that
    if dist == "CHANNEL" and out ~= "wait" then QueueLine(msg) end
    return out
end

-- called only from a key press or a click
local function SendLine()
    local L = S.lines
    if L.off or S.state ~= "on" or not CanSend() then return end
    local now = GetTime()
    if L.out then
        if now - L.outAt < LINE_BACK then return end
        Dropped(now)
    end
    if #lines == 0 or now < L.nextAt then return end
    local num = ChannelNumber()
    local chat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not num or not chat then return end
    local text = table.remove(lines, 1)
    L.out, L.outAt = text, now
    L.tries[text] = (L.tries[text] or 0) + 1
    L.nextAt = now + L.gap
    L.sent = L.sent + 1
    chat(LINE .. text, "CHANNEL", nil, num)
end

-- the developer build's ping, sent from a button click: its line goes ahead of any waiting and rides that click
function S.Ping(token)
    if not engine or S.state ~= "on" then return false end
    local before = #lines
    Send("CHANNEL", nil, P.EncodePing(token))
    if #lines > before then table.insert(lines, 1, table.remove(lines)) end
    SendLine()
    return true
end

-- the presses lines ride on: clicks in the world, and every key (passed on to the game's own bindings). Set up out of
-- combat, where keyboard input may be changed
local function WatchPresses()
    if S.keys then return end
    if InCombatLockdown and InCombatLockdown() then
        S.watchAfterCombat = true
        return
    end
    if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", SendLine) end
    local keys = CreateFrame("Frame", nil, UIParent)
    keys:SetPropagateKeyboardInput(true)
    keys:SetScript("OnKeyDown", SendLine)
    S.keys = keys
end
S.WatchPresses = WatchPresses

-- a chat line names its sender by first name and realm, an addon message on Forever by first name and surname: the
-- player's id gives the full name where the game has it, so both routes name a player alike (bans, reports)
local function LineSender(sender, guid)
    if not ns.isForever or type(guid) ~= "string" or guid == "" then return sender end
    if GetPlayerInfoByGUID then
        local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
        if type(name) == "string" and not ns.Secret(name) and name:find(SURNAME, 1, true) then return name end
    end
    return MemberName(guid, sender, Current()) or sender
end
S.LineSender = LineSender

-- arg9 is the channel's name without its number, arg12 the sender's player id
ns.On("CHAT_MSG_CHANNEL", function(text, sender, _, _, _, _, _, _, base, _, _, guid)
    if not engine or ns.Secret(text) or ns.Secret(sender) or ns.Secret(base) or ns.Secret(guid) then return end
    if type(text) ~= "string" or type(sender) ~= "string" or type(base) ~= "string" then return end
    if base:lower() ~= Current():lower() or text:sub(1, #LINE) ~= LINE then return end
    local msg = text:sub(#LINE + 1)
    local mine = UnitGUID and guid ~= nil and guid == UnitGUID("player")
    if mine then
        CameBack(msg)
        return engine:Receive(msg, "CHANNEL", engine.env.me, "line")
    end
    S.lines.heard = S.lines.heard + 1
    local name = LineSender(sender, guid)
    route[name] = ReplyName(name, sender, guid)
    engine:Receive(msg, "CHANNEL", name, "line")
end)

-- the channel's notices, hidden from the chat windows: a throttle notice means the line in flight was dropped
ns.On("CHAT_MSG_CHANNEL_NOTICE", function(kind, _, _, _, _, _, _, _, name)
    if ns.Secret(kind) or ns.Secret(name) or type(kind) ~= "string" or type(name) ~= "string" then return end
    if name:lower() ~= Current():lower() then return end
    if S.OnNotice then S.OnNotice(kind, name) end
    if kind == "THROTTLED" and S.lines.out then Dropped(GetTime()) end
end)

-- a line the game refused (no press behind it after all): no more lines this session, so the refusal never repeats
local function Refused(addon, fn)
    if addon == ADDON and type(fn) == "string" and fn:find("SendChatMessage", 1, true) then
        S.lines.off = true
        S.lines.out = nil
        for i = #lines, 1, -1 do lines[i] = nil end
    end
end
ns.On("ADDON_ACTION_BLOCKED", Refused)
ns.On("ADDON_ACTION_FORBIDDEN", Refused)

-- place names in a message are never shown as sent: a creature's name comes from the shipped data by its id, a zone's
-- from the game's map by its id, and anything without such an id is left out
local function TrustPlaces(s)
    if not s then return end
    local place = s.npc and ns.Data.Place("npcs", s.npc)
    s.n = place and place.name or nil
    local map = s.m and C_Map.GetMapInfo and C_Map.GetMapInfo(s.m)
    local zone = map and map.name
    -- inside a dungeon the game gives no map, only its name: kept only when it names a dungeon this copy's own data
    -- lists, and then in the data's words, so the entrance comes from that data
    local dungeon = not s.m and ns.Data.DungeonNamed(s.z)
    s.z = (type(zone) == "string" and zone ~= "" and not ns.Secret(zone)) and zone or (dungeon and dungeon.name) or nil
    -- a quest reward is named by its quest's id, from this copy's own data or game
    if s.t == "q" then
        s.qid = P.QuestOf(s)
        s.n = s.qid and ns.Data.QuestName(s.qid) or nil
    end
    s.sz = nil
end

-- a network find is accepted only if this copy's own data agrees it is new or changed,
-- and the game itself knows the item (its details always come from the game, never the message)
local function Accept(info, _, done)
    TrustPlaces(info.src)
    if ns.Detect.Judge(info.id, info) == false then return done(false) end
    -- the numbers that matter come from the game, never the message: wait for the item, then take them
    ns.Detect.WhenLoaded(info.id, function(ok)
        if not ok then return done(false) end
        local _, _, q, ilvl, req, _, _, _, _, _, _, cls, sub = C_Item.GetItemInfo(info.id)
        if q then
            info.q, info.ilvl, info.req = q, ilvl, req
            info.cls, info.sub = cls or info.cls, sub or info.sub
            info.inv = (C_Item.GetItemInventoryTypeByID and C_Item.GetItemInventoryTypeByID(info.id)) or info.inv
        end
        -- an old Classic item the client withholds counts only if the game shows it changed
        if ns.isForever and ns.Data.Classify(info.id) == "withheld" then
            local wq, wil, wrq = ns.Data.Withheld(info.id)
            if q == wq and ilvl == wil and req == wrq then return done(false) end
            info.kind = "c"
        end
        done(true)
    end)
end

-- a find goes out while sharing is on, even with no channel: the guild and group routes still carry it. fresh: new to
-- this copy or changed
function S.Announce(rec, fresh)
    if engine and S.state ~= "paused" then engine:Announce(rec, fresh) end
end

-- the routes a live find also takes: the player's guild and the group they are in
local function Groups()
    local out = {}
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        out[#out + 1] = "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        out[#out + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then
        out[#out + 1] = "PARTY"
    end
    return out
end

-- sharing stops for the rest of the session: out of the channel, nothing more sent (a copy switched off mid-session)
function S.Leave()
    local id = GetChannelName(Current())
    if type(id) == "number" and id > 0 and LeaveChannelByName then LeaveChannelByName(Current()) end
    S.state = "paused"
    S.joined = true
    ns.Signal("SyncState")
end

function S.LastHeard()
    return engine and engine.lastHeard
end

-- the feed's Refresh: false while sharing is off or the last hello is under a minute old
function S.AskAgain()
    if not engine or S.state ~= "on" then return false end
    return engine:AskAgain()
end

function S.Engine()
    return engine
end

-- the developer build's button: pull every find this server's copies hold
function S.CollectAll()
    if not engine or S.state ~= "on" then return false end
    engine:CollectAll()
    return true
end

-- how far this copy is caught up, per server (each server has its own channel and its own finds)
local function ServerKey()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
end

ns.Listen("DBReady", function()
    if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(P.PREFIX) end
    engine = Engine.New({
        now = GetTime,
        random = function(lo, hi) return math.random(lo, hi) end,
        after = function(s, fn) C_Timer.After(s, fn) end,
        send = Send,
        canSend = CanSend,
        groups = Groups,
        me = Me(),
        isMe = IsMe,
        finds = ns.Finds,
        accept = Accept,
        onRecorded = function(rec, status, info) ns.Signal("NetFind", rec, status, info) end,
        stamp = ns.Now,
        bookmark = function() return ns.db.sync and ns.db.sync[ServerKey()] end,
        setBookmark = function(t)
            ns.db.sync = ns.db.sync or {}
            ns.db.sync[ServerKey()] = t
        end,
        banned = Banned,
        report = function(kind, sender, why)
            if kind == "capped" then
                Report("skipped " .. (Full(sender) or "?") .. "'s finds for the rest of 5 minutes: " .. why)
            else
                Report("muted " .. (Full(sender) or "?") .. " for this session: " .. why)
            end
        end,
        host = ns.SAVE == "ArcAurasFindsDB" and "Arc Auras" or "Item Finder",
        version = ns.VERSION,
        onAnswer = function(...) if S.OnAnswer then S.OnAnswer(...) end end,
        onPeer = RecordPeer,
        here = Here,
        news = News,
        onHere = OnHere,
        onEvent = OnEvent,
    })
end)

-- a banned player's reports come off every find at login, and a find from the network only they reported goes. Their
-- reports were keyed by the sender name the game gave, which for this realm's players may lack the realm
local function PurgeBans()
    if not ns.BANS or not next(ns.BANS) or not ns.Finds.DropReporters then return end
    local realm = (Me() or ""):match("%-(.+)$")
    local keys = {}
    for name in pairs(ns.BANS) do
        keys[ns.Finds.ReporterKey(name)] = true
        local short, r = name:match("^([^-]+)%-(.+)$")
        if short and r == realm then keys[ns.Finds.ReporterKey(short)] = true end
        local base = ns.isForever and Surnamed(name)
        if base then keys[ns.Finds.ReporterKey(base)] = true end
    end
    ns.Finds.DropReporters(keys)
end
S.PurgeBans = PurgeBans
ns.Listen("Login", PurgeBans)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if S.joined then return end
    S.joined = true
    C_Timer.After(1, AskWhere)
    -- the game's own channels join first; ours waits so it never takes their numbers
    C_Timer.After(8, function()
        if told.slot then
            slot, toldSlot = told.slot, told.slot
            Report("going straight to " .. Current() .. ", where the copies that answered share")
        end
        Join()
        WatchPresses()
        if engine then
            engine.env.me = Me()
            engine:OnLogin()
        end
    end)
end)

local ROUTES = { CHANNEL = true, WHISPER = true, GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
ns.On("CHAT_MSG_ADDON", function(prefix, msg, dist, sender)
    if ns.Secret(prefix) or ns.Secret(msg) or ns.Secret(dist) or ns.Secret(sender) then return end
    if prefix ~= P.PREFIX or not engine then return end
    if not ROUTES[dist] then return end
    engine:Receive(msg, dist, sender)
end)

-- a chat window the player adds later must not show the channel either
ns.On("UPDATE_CHAT_WINDOWS", function()
    if S.state == "on" then HideChannel() end
end)

-- a world channel joining late (login, leaving an instance) lands after ours: ours moves on again
ns.On("CHANNEL_UI_UPDATE", function()
    if S.state == "on" then ToEndSoon() end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if S.watchAfterCombat then
        S.watchAfterCombat = nil
        WatchPresses()
    end
    if S.toEndAfterCombat then
        S.toEndAfterCombat = nil
        ToEndSoon()
    end
end)
