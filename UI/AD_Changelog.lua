-- What's New window. On Forever it opens by itself once per base version;
-- retail ArcUI shows its own. State lives in Store.UI(), so marking a version
-- seen doesn't dirty the store into a full rebuild.

local ADDON, NS = ...
local AT = NS.AT
local COL = AT.COL

local CL = {}
NS.Changelog = CL

-- @whatsnew-begin (generated from CHANGELOG.md by tools\whatsnew_sync.lua)
CL.versions = {
    {
        version = "1.3.0",
        intro = "Castbars, layout looks, anchors for free icons and your mouse, a button press highlight, and aura glows that hold steady in combat.",
        sections = {
            { header = "New Features", items = {
                { title = "Castbars",
                    desc = "Castbars for you, your target and your focus: the spell's name, icon and time, a spark, colors for interrupted and failed casts and for casts that can't be interrupted, your latency, and a tick mark for every tick of your channels. Your own castbar can hide Blizzard's. Works in combat." },
                { title = "Layout looks",
                    desc = "A layout can set the look of everything in it, from Icon Looks, Group Looks and Bar Looks on the layout. Its icons, groups and bars follow those settings and can still set their own, and Reset to layout makes them follow again." },
                { title = "Anchor free icons",
                    desc = "Icons that are not in a group get an Anchor tab: pin one to a group, a bar, a layout or a named frame, then drag it or use its offsets to place it." },
                { title = "Anchor to your mouse",
                    desc = "Groups, bars and free icons can follow your mouse cursor." },
                { title = "Button Press Highlight",
                    desc = "When you press an action button, cast through a macro or use a trinket, every icon of that ability lights up for a moment. Pick its look, color and how long it lasts in Settings." },
                { title = "Icon shadow, dispel borders and fonts",
                    desc = "Icons can wear the Cooldown Manager's soft shadow, aura icons can color their border by the aura's type (Magic, Curse, Disease or Poison), and every icon text can use any font, including fonts from other addons." },
                { title = "More glow styles",
                    desc = "Marching ants, the Cooldown Manager's flash and the proc glow without its opening burst join the glow styles, the Pixel glow gets a line length, and every glow can be moved with Move X and Y." },
                { title = "Play on screen",
                    desc = "The bar preview can play on the bar itself, in its real place and size." },
            } },
            { header = "Improvements", items = {
                { title = "Better aura glows",
                    desc = "Aura glows are handled better: they show right away and keep going smoothly for as long as the aura is up." },
                { title = "Layouts list scrolls",
                    desc = "The layouts sidebar scrolls when it fills up, so everything stays in reach." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Aura glows restarting",
                    desc = "Glows on buff and debuff icons restarted, sometimes several times, when combat started or ended. They now keep going." },
                { title = "Bar preview zoom",
                    desc = "Zooming the bar preview no longer moves the text on the bar." },
            } },
        },
    },
    {
        version = "1.2.0",
        intro = "A live preview for bars, bars on your target's nameplate, an aura shown on a cooldown icon, and a choice of when aura glows show.",
        sections = {
            { header = "New Features", items = {
                { title = "Live bar preview",
                    desc = "The bar editor shows the bar you are editing, drawn with your real settings, and can play it in a loop: filling, counting down, recharging and stacking up." },
                { title = "Zoom the bar preview",
                    desc = "Zoom in and out with the - and + buttons or the mouse wheel, click the percentage to fit the bar again, and drag a big bar to look around. Standing bars get a taller preview." },
                { title = "Bars on your target's nameplate",
                    desc = "Anchor a bar to your target's nameplate, for example your combo points. It follows your target and hides while your target has no nameplate. While this window is open, the bar's preview shows it on a stand-in nameplate so you can place it." },
                { title = "Icon type labels",
                    desc = "Every icon wears a colored label saying what it is, CD Icon, Aura Icon, Timer Icon, Item Icon, Trinket Icon, Totem Icon or Ammo Icon, in the sidebar, the layout view, the editor, import and export, and search." },
                { title = "An aura on a cooldown icon",
                    desc = "Switch on Show an aura on this icon on a spell icon's Tracking tab, and while the aura is up the icon shows the aura's time over its cooldown, like the Cooldown Manager does. It starts on the most likely aura for you, and the new Aura Active tab styles how it looks. Works in combat." },
                { title = "Glow timing",
                    desc = "Choose when an aura glow shows: the whole time the aura is up, only in the refresh (pandemic) window, or once little time is left, in percent or in seconds. For aura icons and the aura on a cooldown icon, in combat too." },
            } },
            { header = "Improvements", items = {
                { title = "Delete from the layout view",
                    desc = "Hover a tile to get an X in its corner that deletes it (it asks first), in place of the Edit and Delete buttons that covered the name. Click the tile to edit it." },
                { title = "Aura swipe colors",
                    desc = "The aura on a cooldown icon uses the Cooldown Manager's gold swipe by default. Change its color, direction and edge, and grey the icon while the aura is down. Aura icons can change their swipe's edge color and size too." },
                { title = "Timer rounding per bar and icon",
                    desc = "Round timer numbers can be set on each bar and icon, or left on the Settings choice." },
                { title = "New things appear in the middle",
                    desc = "New layouts, groups, icons and bars appear in the middle of your screen, one step lower when something already sits there." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Short cooldowns count down",
                    desc = "A two second cooldown like Throw showed no countdown numbers on its icon or bar. It does now, and so do short auras on aura icons. The global cooldown still shows no numbers." },
                { title = "Tabs on first open",
                    desc = "Some tabs in the options window could sit in the wrong place or be missing until you clicked one. They now all show right away." },
                { title = "Empty option boxes",
                    desc = "Bar options no longer show a stray box, such as Health text 3 or Pips, holding only the Copy to, Save as Default and Reset buttons. Those buttons now sit at the bottom, below everything they cover." },
            } },
        },
    },
    {
        version = "1.1.0",
        intro = "Standing bars, up to three texts on resource and health bars, aura search by name, and a choice of how timers round.",
        sections = {
            { header = "New Features", items = {
                { title = "Stand a bar up",
                    desc = "Set a bar to Vertical and tick Stand the bar up: it turns a quarter so it is tall and thin, with its icon, texture and gradient turning along. Horizontal lays it down again." },
                { title = "More than one text",
                    desc = "Resource and health bars can show up to three texts, each with its own format, size, color and place, so a bar can show the value and the percent together." },
                { title = "Custom name text",
                    desc = "Give any bar's name text your own wording, or leave it empty for the normal name." },
                { title = "Find auras by name",
                    desc = "Type part of a buff or debuff's name when you add an aura icon or aura bar, or in an aura bar's settings, and pick it from the list to fill in its spell IDs. Every rank comes along, and spells you know are marked." },
                { title = "Aura bars: on whom, cast by whom",
                    desc = "Aura bars can watch you, your target, focus, pet or a party member, and count the aura from anyone, only you, or anyone but you, the same choices aura icons have." },
                { title = "Swing bar thresholds and ticks",
                    desc = "Color a swing bar in the last part of the swing, in tenths of a second, and add tick marks measured in seconds of the swing." },
                { title = "Timer rounding",
                    desc = "Choose in Settings whether countdowns round up, like action bar cooldowns (the default), or down, like buff timers." },
                { title = "What's New in game",
                    desc = "After each update a window shows what changed, once. Turn it off or open it again in Settings, or type /arccl." },
            } },
            { header = "Improvements", items = {
                { title = "Icons keep their own size",
                    desc = "A bar's icon now has its own size, with Match the bar's size as an option." },
                { title = "Swing bars fill up",
                    desc = "Swing bars fill during the swing and sit empty between swings by default." },
                { title = "Taller and thinner bars",
                    desc = "Bar width and height both go from 4 to 600." },
                { title = "Text settings in one place",
                    desc = "What a resource bar's text shows is now on the Text tab with the rest of its text options; your choice carries over." },
                { title = "Search",
                    desc = "A group's Alignment is found even while Dynamic is off, and the result says to switch Dynamic on first." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Icon and bar timers agree",
                    desc = "An icon and a bar showing the same timer could read one second apart; every timer now rounds the same way." },
                { title = "Spell icon art",
                    desc = "Spell icons no longer take another ability's art from your action bars (a Raptor Strike icon could show Mongoose Bite). Toggles like aspects and Stealth show the active art of the rank you actually cast." },
                { title = "Ranged swing bar error",
                    desc = "Fixed an error at the end of a ranged swing in combat." },
                { title = "Vertical aura bars",
                    desc = "Aura bars now redraw their color layers correctly after switching between horizontal and vertical." },
            } },
        },
    },
    {
        version = "1.0.0",
        intro = "The first release of Arc UI for WoW Forever. Type /arcui in game to open it. On retail, Arc UI keeps updating as before.",
        sections = {
            { header = "New Features", items = {
                { title = "Layouts",
                    desc = "Movable blocks that hold your icon groups, free icons and bars. Drag them into place or type an exact position, and anchor anything to anything." },
                { title = "Icon groups",
                    desc = "Cooldown groups on a grid you shape yourself, with dynamic layouts that close the gaps as icons drop out, and aura groups that keep a fixed grid or show only the buffs and debuffs that are up." },
                { title = "Icons",
                    desc = "Track spells, auras, items, trinkets, totems and your ammo. Ready, cooldown, proc and usable states each get their own glow, tint and opacity, with swipes, duration and charge text, keybinds and up to three custom labels." },
                { title = "Aura icons",
                    desc = "One icon can watch several auras: buffs on you, your target, focus, pet or party, and debuffs on your target or focus, from anyone, only you or anyone but you. Style how it looks while the aura is up and while it is missing, and light it up with a glow, Blizzard's own proc glow included, when the aura appears. All of it works in combat." },
                { title = "Custom icon art",
                    desc = "Give any icon other art by icon, spell or item ID, and give aura icons their own art for when the aura is up and when it is missing." },
                { title = "Toggle spells follow your bars",
                    desc = "Stealth, aspects and other toggles show the same active art your action bar shows." },
                { title = "Spell ranks",
                    desc = "Icons and bars can follow whichever rank of a spell you know. Switch on auto-rank under QOL and your action bars move up to each new rank you learn, leaving the lower ranks you placed on purpose and your macros alone." },
                { title = "Aura bars",
                    desc = "Buff and debuff bars with duration fill, stack fill, countdown and stack text that keep working in combat, and that can hide completely while the aura is down." },
                { title = "Stack colors",
                    desc = "Recolor an aura stack bar at the stack counts you choose, with a max-stacks color on top." },
                { title = "Cooldown, swing and resource bars",
                    desc = "Charge-aware cooldown bars, swing timers and bars for every power type, colored by time left or by power, with your own textures, backgrounds and borders." },
                { title = "Combo points",
                    desc = "As a bar with a tick mark for every point, or as pips in square, circle or diamond cells with their own point colors." },
                { title = "Health bars",
                    desc = "For you, your target, focus, pet or party members, with incoming heals, absorb shields and heal absorbs drawn on the bar, each with its own toggle and color. Color the bar by class, reaction or a health gradient, and change its color below the health you choose." },
                { title = "Cost icons",
                    desc = "A spell's icon at its cost on your mana or energy bar, dimmed while you cannot afford it." },
                { title = "Sound alerts",
                    desc = "Play a sound when a spell is ready, starts its cooldown or gains a charge. Pick from a built-in pack or the game's own sounds and preview them first." },
                { title = "Load conditions and fades",
                    desc = "Show anything only for some classes, characters or talents, and fade it by combat, mounting and more." },
                { title = "Sharing",
                    desc = "Export a whole layout or just the pieces you tick, import strings from friends, and rename, duplicate or move anything between layouts." },
                { title = "Copy settings in one click",
                    desc = "Copy any block of settings to another group, a whole layout or everything of its kind, or save it as the default for new ones." },
                { title = "Your shared media",
                    desc = "Textures, fonts, borders and sounds from your other addons appear in every list beside the built-in ones." },
                { title = "An options panel built for this",
                    desc = "Tiles or cards for your layout contents, a sidebar you can resize, a Position tab everywhere, a live preview that plays each icon's states, and an eye on anything not loaded for this character so you can still see and place it while you edit." },
                { title = "Search everything",
                    desc = "One box finds your layouts, groups, icons and bars by name or by spell, item or icon ID, and any option by its name. Click a result to jump straight to it, highlighted." },
                { title = "IDs in tooltips",
                    desc = "Spell, aura, item and other tooltips anywhere in the game show the ID and the icon ID, plus the Cooldown Manager's cooldown ID when there is one. Turn it off in Settings, where you can also have your icons show their tooltips only while this window is open." },
            } },
        },
    },
}
-- @whatsnew-end

function CL.CurrentVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    return type(v) == "string" and v or "?"
end

-- "1.1.0.a" -> "1.1.0". The auto-open tracks the base version, so a
-- hotfix's notes go into its base version's entry.
function CL.BaseVersion()
    return (CL.CurrentVersion():gsub("%.%a+$", ""))
end

local function Hex(c)
    return string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function CL.Body(ver)
    local arc, ink, dim = Hex(COL.arc), Hex(COL.ink), Hex(COL.dim)
    local lines = {}
    if ver.intro then
        lines[#lines + 1] = "|c" .. dim .. ver.intro .. "|r"
        lines[#lines + 1] = " "
    end
    for _, sec in ipairs(ver.sections or {}) do
        lines[#lines + 1] = "|c" .. arc .. string.upper(sec.header or "") .. "|r"
        for _, it in ipairs(sec.items or {}) do
            lines[#lines + 1] = "|c" .. arc .. ">|r  |c" .. ink .. (it.title or "") .. "|r   |c"
                .. dim .. (it.desc or "") .. "|r"
        end
        lines[#lines + 1] = " "
    end
    return table.concat(lines, "\n")
end

-- Window

local win, scroll, content, blocks, check, switchBtn

function CL.Layout()
    if not win then return end
    local w = scroll:GetWidth()
    -- The scroll frame has no width until the client first lays it out.
    if not w or w < 50 then w = (win:GetWidth() or 560) - 30 end
    w = math.floor(w - 8)
    content:SetWidth(w)
    local y = 0
    for i, b in ipairs(blocks) do
        b.hdr:ClearAllPoints()
        b.hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        b.hdr:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        b.chev:SetDown(b.expanded)
        b.label:SetText("|c" .. Hex(COL.ink) .. "Version " .. b.ver.version .. "|r"
            .. ((i == 1) and ("   |c" .. Hex(COL.arc) .. "Latest|r") or ""))
        y = y + 26 + 6
        if b.expanded then
            b.body:SetWidth(w - 16)
            b.body:ClearAllPoints()
            b.body:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
            b.body:Show()
            y = y + math.ceil(b.body:GetStringHeight() or 0) + 14
        else
            b.body:Hide()
        end
    end
    content:SetHeight(math.max(y, 1))
    scroll:UpdateScroll()
end

local function SyncCheck()
    local ui = NS.Store and NS.Store.UI and NS.Store.UI()
    if check then check:SetOn(not (ui and ui.changelogOff)) end
end

local function Build()
    if win then return win end
    win = AT.CreateWindow("ArcUIv2WhatsNew", {
        w = 580, h = 620, minW = 460, minH = 420, maxW = 1000, maxH = 1200,
        title = "|cff3fc9f2What's New|r|cffd5e2f2 in Arc UI Forever|r",
        version = CL.CurrentVersion(),
        onResize = function() CL.Layout() end,
    })
    -- Above the options window (DIALOG), so opening it from Settings doesn't
    -- land behind the panel.
    win:SetFrameStrata("FULLSCREEN_DIALOG")

    scroll, content = AT.MakeScroll(win)
    scroll:SetPoint("TOPLEFT", 14, -42)
    scroll:SetPoint("BOTTOMRIGHT", -18, 50)

    blocks = {}
    for i, ver in ipairs(CL.versions) do
        local b = { ver = ver, expanded = (i == 1) }
        local hdr = CreateFrame("Button", nil, content, "BackdropTemplate")
        hdr:SetHeight(26)
        AT.Skin(hdr, COL.panel, COL.line)
        b.chev = AT.MakeChevron(hdr)
        b.chev:SetPoint("LEFT", 8, 0)
        b.label = hdr:CreateFontString(nil, "OVERLAY")
        b.label:SetFont(STANDARD_TEXT_FONT, 12, "")
        b.label:SetPoint("LEFT", b.chev, "RIGHT", 8, 0)
        hdr:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COL.arc[1], COL.arc[2], COL.arc[3], 1)
        end)
        hdr:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(COL.line[1], COL.line[2], COL.line[3], 1)
        end)
        hdr:SetScript("OnClick", function()
            b.expanded = not b.expanded
            CL.Layout()
        end)
        b.hdr = hdr
        local body = content:CreateFontString(nil, "OVERLAY")
        body:SetFont(STANDARD_TEXT_FONT, 12, "")
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(4)
        body:SetText(CL.Body(ver))
        b.body = body
        blocks[i] = b
    end

    -- Footer: a hairline, the auto-open switch (the whole label clicks) and
    -- Close, clear of the resize grip.
    local hr = win:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(COL.line[1], COL.line[2], COL.line[3], 1)
    hr:SetPoint("BOTTOMLEFT", 12, 42)
    hr:SetPoint("BOTTOMRIGHT", -12, 42)
    hr:SetHeight(AT.Hairline(win))

    local sw = CreateFrame("Button", nil, win)
    sw:SetSize(260, 22)
    sw:SetPoint("BOTTOMLEFT", 14, 12)
    check = AT.MakeCheckbox(sw)
    check:SetPoint("LEFT", 0, 0)
    check:EnableMouse(false)
    local lbl = sw:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(STANDARD_TEXT_FONT, 12, "")
    lbl:SetPoint("LEFT", check, "RIGHT", 8, 0)
    lbl:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
    lbl:SetText("Show after each update")
    sw:SetScript("OnEnter", function() check:SetHover(true) end)
    sw:SetScript("OnLeave", function() check:SetHover(false) end)
    sw:SetScript("OnClick", function()
        local ui = NS.Store and NS.Store.UI and NS.Store.UI()
        if not ui then return end
        ui.changelogOff = (not ui.changelogOff) or nil
        SyncCheck()
        PlaySound(ui.changelogOff and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    AT.Tooltip(sw, "Show after each update",
        "The first time you log in after Arc UI Forever updates, this window opens once with what changed. Settings has the same switch.")
    switchBtn = sw

    local close = AT.MakeSmallButton(win, "Close", 90)
    close:SetPoint("BOTTOMRIGHT", -28, 12)
    close:SetScript("OnClick", function() win:Hide() end)
    return win
end

function CL.Show()
    Build()
    for i, b in ipairs(blocks) do b.expanded = (i == 1) end
    SyncCheck()
    win:Show()
    win:Raise()
    scroll:SetVerticalScroll(0)
    CL.Layout()
    -- Widths resolve after the first frame, so lay out again then.
    C_Timer.After(0, CL.Layout)
end

function CL.Hide()
    if win then win:Hide() end
end

function CL.Toggle()
    if win and win:IsShown() then win:Hide() else CL.Show() end
end

function CL.IsShown()
    return win ~= nil and win:IsShown()
end

-- Read-only handles for the offline test harness.
function CL.Blocks() return blocks or {} end
function CL.SwitchButton() return switchBtn end

-- Once-per-update open

-- Returns true when it opened. The version is marked seen before opening,
-- so an error can't make it open on every login.
function CL.CheckOnLogin()
    local Store = NS.Store
    local ui = Store and Store.UI and Store.UI()
    if not ui then return false end
    if ui.changelogOff then return false end
    local cur = CL.BaseVersion()
    if cur == "?" or ui.changelogSeen == cur then return false end
    ui.changelogSeen = cur
    CL.Show()
    return true
end

if NS.IsForever then
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Wait for the store to settle on the live saved variables (AD_Init can
        -- re-point it on this event) and for the screen to clear.
        C_Timer.After(3, CL.CheckOnLogin)
    end)
end

-- Slash commands. The window is the answer, with no chat output.
SLASH_ARCUIVTWOCL1 = "/arccl2"
if NS.IsForever then
    SLASH_ARCUIVTWOCL2 = "/arccl"
    SLASH_ARCUIVTWOCL3 = "/arcchangelog"
end
SlashCmdList["ARCUIVTWOCL"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "reset" or msg == "test" then
        -- Forget the seen version and the off switch, so the next login or
        -- /reload opens it by itself again.
        local ui = NS.Store and NS.Store.UI and NS.Store.UI()
        if ui then
            ui.changelogSeen = nil
            ui.changelogOff = nil
        end
        CL.Show()
        return
    end
    CL.Toggle()
end
