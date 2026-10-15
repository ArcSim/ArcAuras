-- AD_LayoutFollow: a layout's changes offered to the items inside it, each
-- after asking. Its class, spec and talent checks are offered when you leave
-- its Load Conditions; a look it sets is offered once the change settles.
-- UI\AD_Options.lua calls LF.Sync on every tab, pick and window change and
-- LF.Rows on the Load Conditions page; the Store does the writes.
local ADDON, NS = ...

local LF = {}
NS.LayoutFollow = LF

-- the client's words; English while the theme is not loaded
local function Tr(s)
    local AT = NS.AT
    return AT and AT.Tr and AT.Tr(s) or s
end
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
    local what = (cls and tal) and Tr("class, spec and talent checks") or tal and Tr("talent checks")
        or Tr("class and spec checks")
    -- one whole sentence per count, so each language words it as a whole
    local ask = n == 1
        and Tr("%d item in '%s' has this layout's old %s. Give it its new ones? Its own Load When rules stay.")
        or Tr("%d items in '%s' have this layout's old %s. Give them its new ones? Their own Load When rules stay.")
    LF.Ask("ARCUIV2_LAYOUT_WHO", ask:format(n, layout.name or "?", what),
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
    local noun = one and Tr("item") or Tr("items")
    for _, lt in ipairs(NS.Options.LOOK_TABS or {}) do
        if #fams == 1 and lt.family == fams[1] then noun = Tr(one and lt.one or lt.many) end
    end
    table.sort(labels)
    for i, l in ipairs(labels) do labels[i] = Tr(l) end
    local ask = one and Tr("%d %s in '%s' keeps its own %s. Make it follow the layout?")
        or Tr("%d %s in '%s' keep their own %s. Make them follow the layout?")
    LF.Ask("ARCUIV2_LAYOUT_LOOK", ask:format(n, noun, layout.name or "?", table.concat(labels, ", ")),
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
            local line = n == 1 and Tr("%d item in this layout has %s that leave out some of the layout's %s.")
                or Tr("%d items in this layout have %s that leave out some of the layout's %s.")
            fs:SetText(line:format(n, anySpecs and Tr("class and spec checks") or Tr("class checks"),
                anySpecs and Tr("specs") or Tr("classes")))
        end
        if sync then sync() end
    end
    local row = AT.RowButton(pg, "Match the layout", function()
        local r = ctx()
        if not (r and r.type == "layout") then return end
        S.MatchLayout(r, S.LayoutClassStrays(r))
        AT.LayoutPage(pg)
        LF.Refresh()
    end, vis, 150, anySpecs and "Their own class and spec checks" or "Their own class checks")
    AT.Tooltip(row.button, "Match the layout", anySpecs
        and "Copies this layout's class and spec checks onto those items (and its talent checks when it has any), so they load wherever the layout does. Their Load When rules stay."
        or "Copies this layout's class checks onto those items (and its talent checks when it has any), so they load wherever the layout does. Their Load When rules stay.")
end
