-- AD_LayoutFollow: a layout's changes offered to the items inside it, each
-- after asking. Its class, spec and talent checks are offered when you leave
-- its Load Conditions; a look it sets is offered once the change settles.
-- UI\AD_Options.lua calls LF.Sync on every tab, pick and window change and
-- LF.Rows on the Load Conditions page; the Store does the writes.
local ADDON, NS = ...

local LF = {}
NS.LayoutFollow = LF
NS.Options.LayoutFollow = LF

-- seconds a layout look must stay put before the offer (a slider drag sends
-- one change per step)
LF.SETTLE = 0.8

LF.snap = nil      -- { id, who }: the layout whose Load Conditions are open, as it was
LF.pending = {}    -- look changes waiting to settle, by layout / family / section / field
LF.gen = 0

-- One Yes / No popup per kind of offer; a newer offer replaces an open one.
function LF.Ask(key, text, onYes)
    StaticPopupDialogs[key] = StaticPopupDialogs[key] or {
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
        preferredIndex = 3,
    }
    local d = StaticPopupDialogs[key]
    d.text = text
    d.OnAccept = onYes
    if StaticPopup_Hide then StaticPopup_Hide(key) end
    StaticPopup_Show(key)
end

function LF.Refresh()
    if NS.Options.RefreshAll then NS.Options.RefreshAll() end
end

-- Called with the layout whose Load Conditions are open now (nil when none):
-- the one that was open before is checked against how it was, then this one
-- is remembered.
function LF.Sync(layoutId)
    local S = NS.Store
    local s = LF.snap
    LF.snap = nil
    if s then
        local rec = S.Get(s.id)
        if rec and rec.type == "layout" then LF.OfferWho(rec, s.who) end
    end
    local l = layoutId and S.Get(layoutId)
    if l and l.type == "layout" then LF.snap = { id = l.id, who = S.WhoOf(l) } end
end

function LF.OfferWho(layout, old)
    local S = NS.Store
    local list = S.WhoFollowers(layout, old)
    local n = #list
    if n == 0 then return end
    local cls, tal = false, false
    for _, e in ipairs(list) do
        cls = cls or e.cls
        tal = tal or e.tal
    end
    local what = (cls and tal) and "class, spec and talent checks" or tal and "talent checks"
        or "class and spec checks"
    local one = n == 1
    LF.Ask("ARCUIV2_LAYOUT_WHO",
        ("%d %s in '%s' %s this layout's old %s. Give %s its new ones? %s own Load When rules stay.")
            :format(n, one and "item" or "items", layout.name or "?", one and "has" or "have", what,
                one and "it" or "them", one and "Its" or "Their"),
        function()
            S.ApplyWho(layout, list)
            LF.Refresh()
        end)
end

-- Store.SetLayoutValue's message: wait for the change to settle, then offer
-- every row changed meanwhile at once.
function LF.OnLook(_, layoutId, family, section, field)
    LF.pending[layoutId .. "|" .. family .. "|" .. section .. "|" .. field] =
        { id = layoutId, family = family, section = section, field = field }
    LF.gen = LF.gen + 1
    local gen = LF.gen
    C_Timer.After(LF.SETTLE, function()
        if gen == LF.gen then LF.OfferLooks() end
    end)
end

function LF.FieldLabel(family, section, field)
    local fam = NS.Schema[family]
    local def = fam and fam[section] and fam[section].fields[field]
    return (def and def.label) or field
end

function LF.OfferLooks()
    local S = NS.Store
    local todo, items, labels, nouns = {}, {}, {}, {}
    local layout
    for key, p in pairs(LF.pending) do
        LF.pending[key] = nil
        local l = S.Get(p.id)
        if l and l.type == "layout" then
            local owners = S.LayoutOwners(l, p.family, p.section, p.field)
            if #owners > 0 then
                layout = layout or l
                if l == layout then
                    todo[#todo + 1] = p
                    labels[#labels + 1] = LF.FieldLabel(p.family, p.section, p.field)
                    nouns[p.family] = true
                    for _, it in ipairs(owners) do items[it] = true end
                end
            end
        end
    end
    if #todo == 0 then return end
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    local one = n == 1
    -- one family named by its own word (icon, group, bar), a mix as items
    local fams = {}
    for f in pairs(nouns) do fams[#fams + 1] = f end
    local noun = "item"
    for _, lt in ipairs(NS.Options.LOOK_TABS or {}) do
        if #fams == 1 and lt.family == fams[1] then noun = lt.one end
    end
    table.sort(labels)
    LF.Ask("ARCUIV2_LAYOUT_LOOK",
        ("%d %s%s in '%s' %s %s own %s. Make %s follow the layout?")
            :format(n, noun, one and "" or "s", layout.name or "?", one and "keeps" or "keep",
                one and "its" or "their", table.concat(labels, ", "), one and "it" or "them"),
        function()
            for _, p in ipairs(todo) do
                local l = S.Get(p.id)
                if l then S.FollowLayout(l, p.family, p.section, { p.field }) end
            end
            LF.Refresh()
        end)
end

NS.Events.OnMessage("AD_LAYOUT_LOOK", "layoutfollow", LF.OnLook)

-- The layout's Load Conditions page: how many items inside have class or
-- spec boxes that leave out some of the layout's, and Match the layout.
function LF.Rows(pg, ctx, tabVisible, anySpecs)
    local AT, S = NS.AT, NS.Store
    local what = anySpecs and "class and spec checks" or "class checks"
    local function Strays()
        local r = ctx()
        return (r and r.type == "layout") and S.LayoutClassStrays(r) or {}
    end
    local vis = function() return tabVisible() and #Strays() > 0 end
    local note = AT.RowDesc(pg, "", 20, vis)
    local fs = note:GetRegions()
    local sync = note._sync
    note._sync = function()
        local n = #Strays()
        if fs then
            fs:SetText(("%d %s in this layout %s %s that leave out some of the layout's %s.")
                :format(n, n == 1 and "item" or "items", n == 1 and "has" or "have", what,
                    anySpecs and "specs" or "classes"))
        end
        if sync then sync() end
    end
    local row = AT.RowButton(pg, "Match the layout", function()
        local r = ctx()
        if not (r and r.type == "layout") then return end
        S.MatchLayout(r, S.LayoutClassStrays(r))
        AT.LayoutPage(pg)
        LF.Refresh()
    end, vis, 150, "Their own " .. what)
    AT.Tooltip(row.button, "Match the layout", "Copies this layout's " .. what
        .. " onto those items (and its talent checks when it has any), so they load wherever the layout does. Their Load When rules stay.")
end
