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
        version = "1.10.0",
        intro = "Wheels, ready-made item icons, name texts and dispel type filters.",
        sections = {
            { header = "New Features", items = {
                { title = "Wheels",
                    desc = "A ring of your spells and items on a key: hold it, point, let go to cast. Start one from hunter Aspects or Trackings, or shaman imbues." },
                { title = "Ready-made item icons",
                    desc = "Healthstones, potions, bandages, food, drink and mana gems, one click each in the Add window." },
                { title = "Name text",
                    desc = "A text can show a name: yours, your target's, focus, pet or a party member's." },
                { title = "Dispel types",
                    desc = "Aura groups that show every aura on a unit can show only Magic, Curse, Disease or Poison." },
                { title = "Enchant templates",
                    desc = "Start an enchant icon or bar from a shaman imbue or totem, every rank filled in." },
            } },
            { header = "Improvements", items = {
                { title = "Item icons",
                    desc = "Follow several items and show the first one you carry and can use." },
                { title = "Party texts",
                    desc = "Health texts can follow party members 1 to 4." },
                { title = "Adding texts",
                    desc = "The Add window shows a text's own choices." },
                { title = "Dynamic aura groups",
                    desc = "A \"!\" explains why Aura Missing icons are off." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Health texts",
                    desc = "Hide with no target instead of showing 0." },
                { title = "Racial cooldowns",
                    desc = "Your race's cooldowns, like Will of the Forsaken, now show in the Add window's spell list." },
            } },
        },
    },
    {
        version = "1.9.0",
        intro = "Cooldown Manager layouts, totem bar icons, mana regen sparks and a picture picker for textures.",
        sections = {
            { header = "New Features", items = {
                { title = "From my Cooldown Manager",
                    desc = "Copy your Cooldown Manager into a layout in one click." },
                { title = "Totem bar icons",
                    desc = "Show your totem bar's pick and drop it with a click or a key." },
                { title = "Totem out of range",
                    desc = "Grey out, tint or glow a totem icon while its buff is not on you." },
                { title = "Shaman in my group",
                    desc = "A new Show When rule." },
                { title = "Five-second rule and mana ticks",
                    desc = "Sparks on mana bars for both." },
                { title = "Picture picker",
                    desc = "Pick a texture's picture from thumbnails, with a search." },
                { title = "Copy and duplicate",
                    desc = "Copy, duplicate or delete several items at once." },
                { title = "Imbue damage",
                    desc = "Optional tooltip line: what an imbue or weapon stone adds to your weapon." },
            } },
            { header = "Improvements", items = {
                { title = "You, then your target",
                    desc = "Aura icons can show your buff, then your target's." },
                { title = "Textures",
                    desc = "Crop, pulse and a tinted dim copy." },
                { title = "Weapon enchants",
                    desc = "Several enchant IDs per icon or bar, and enchant IDs in weapon tooltips." },
                { title = "Pick Frame",
                    desc = "Works on every anchor and can pick your Arc Auras items." },
                { title = "Color bands",
                    desc = "Start with one band. Add more as you need them." },
                { title = "Custom text",
                    desc = "One Show choice in each icon's own words." },
                { title = "Cost & Regen",
                    desc = "A new tab on resource bars." },
                { title = "Group load conditions",
                    desc = "Match the group fixes icons that leave out the group's classes." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Dynamic aura groups",
                    desc = "Icons sit one Spacing apart, as in the edit grid." },
                { title = "Match width",
                    desc = "Bars matched to a group span exactly its icons." },
                { title = "Anchored bars",
                    desc = "No more thin background line along a bar's edge." },
                { title = "Aura icon texts",
                    desc = "Stay bright when you lower the active opacity." },
                { title = "Ammo icons",
                    desc = "Custom text for in stock or out of stock now works." },
            } },
        },
    },
    {
        version = "1.8.0",
        intro = "Missing-only aura icons and glows, textures, group buff counts, texts for spells and auras, updates for shared setups and known spells.",
        sections = {
            { header = "New Features", items = {
                { title = "Missing-only aura icons",
                    desc = "Set an aura icon's Active opacity to 0% and it shows only while the aura is missing." },
                { title = "Missing glows",
                    desc = "Aura glows can show only while the aura is missing." },
                { title = "Aura reminders",
                    desc = "Reminder groups can remind you of a missing buff or debuff." },
                { title = "Group Buff icons",
                    desc = "Count who in your party or raid has a buff, show it while anyone lacks it, and hover to see who is missing." },
                { title = "Textures",
                    desc = "Show a picture with an aura or a cooldown, or let it fill and drain like a bar. Pick from 170 pictures or use your own." },
                { title = "Update shared setups",
                    desc = "Import a newer version of a string you already have and update your copy instead of adding a second one. Works with strings made with 1.8.0 or later." },
                { title = "Known spells",
                    desc = "Spell icons and cooldown bars can wait until you learn their spell, and anything can load only while you know a spell." },
            } },
            { header = "Improvements", items = {
                { title = "Texts for spells and auras",
                    desc = "A text can follow a spell or an aura: its cooldown, charges, time left or stacks, or your own words for its state." },
                { title = "Text editing",
                    desc = "Texts take their spell's or aura's name, have their own Appearance page, and show a sample while you edit." },
                { title = "Custom text",
                    desc = "Labels are now Custom text. On aura icons each one shows always, while the aura is up, or while it is missing." },
                { title = "Aura icon opacity",
                    desc = "Active and Missing opacity are fully separate, and a dimmed icon fades instead of turning dark." },
                { title = "Glow cards",
                    desc = "Glow when sits at the top of each card." },
                { title = "Option folds",
                    desc = "More options folds open and close freely, even when they hold a changed setting." },
                { title = "While editing",
                    desc = "Combat-only aura glows and faint aura icons stay visible while the options window is open." },
                { title = "Ammo icons",
                    desc = "The count has its own Count tab and the preview shows your real count. The Duration tab is gone." },
                { title = "Version check",
                    desc = "A string from a newer Arc Auras tells you to update." },
                { title = "First imports",
                    desc = "Strings made with 1.8.0 or later keep their name and place. Only a second copy gets (import)." },
            } },
            { header = "Bug Fixes", items = {
                { title = "New items",
                    desc = "Appear in the middle of the screen instead of further down each time." },
                { title = "Combo points",
                    desc = "The first point on a new target always shows." },
                { title = "Aura sounds",
                    desc = "No longer play twice after a reload." },
                { title = "Aura sounds in combat",
                    desc = "Changing one mid-fight no longer risks a blocked-action error." },
                { title = "Shared looks",
                    desc = "Items from a setup that uses Save as Default look the same for everyone who imports them." },
                { title = "Character-only items",
                    desc = "An item set to load only on its maker's character now loads for whoever imports it." },
            } },
        },
    },
    {
        version = "1.7.0",
        intro = "Aura groups for any aura or nameplate, text elements, clickable party bars, aura sounds, over-shields and less CPU.",
        sections = {
            { header = "New Features", items = {
                { title = "Every aura on a unit",
                    desc = "Aura groups can show every buff or debuff on a unit, no spell IDs needed." },
                { title = "Nameplate debuffs",
                    desc = "Aura groups can show your debuffs on enemy nameplates." },
                { title = "Text elements",
                    desc = "Put health, power, cooldowns, aura timers or your own words anywhere." },
                { title = "Clickable health bars",
                    desc = "Party health bars target on click and work with click casting." },
                { title = "Aura sounds",
                    desc = "Aura icons can play a sound when the aura appears, gains a stack or drops." },
                { title = "Over-shield",
                    desc = "Shields past full health now show inside the health bar." },
                { title = "Select several",
                    desc = "Ctrl or Shift click items to move, export or edit them together." },
                { title = "From your action bars",
                    desc = "Fill a group with icons from your action bars." },
                { title = "Cooldown glow",
                    desc = "Icons can glow while on cooldown." },
            } },
            { header = "Improvements", items = {
                { title = "Lighter on CPU",
                    desc = "Cooldown icons do much less work in combat." },
                { title = "Group + button",
                    desc = "Adds icons straight into that group." },
                { title = "Thinner bars",
                    desc = "Bars go down to 1 pixel." },
                { title = "Edit buttons",
                    desc = "Show them on icons only, bars only, or not at all." },
                { title = "Add texts",
                    desc = "Health and resource texts use a + Add button." },
                { title = "Text offsets",
                    desc = "Texts move up to 200 pixels, and offsets start at 0. Existing setups keep their look." },
                { title = "More sounds",
                    desc = "Eleven new alert sounds." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Aura bars",
                    desc = "Draw right away after a reload in combat." },
                { title = "Macro keybinds",
                    desc = "Spells on your bars through a macro show their keybind and press highlight." },
                { title = "Aura group growth",
                    desc = "Groups grow from the corner you picked." },
                { title = "Friendly units",
                    desc = "Aura bars treat immune friendly units as friendly." },
                { title = "Tooltip IDs",
                    desc = "The aura ID line hides in combat instead of showing <secret>." },
                { title = "Range checks",
                    desc = "Fixed an error checking range to your target in dungeons." },
                { title = "Outside texts",
                    desc = "Text above or below a bar lines up with its edge." },
                { title = "Stack colors",
                    desc = "The Keep each stack's own color switch now shows." },
            } },
        },
    },
    {
        version = "1.6.0",
        intro = "Reminder groups, pet and ammo warnings, frame picking and a clearer editor.",
        sections = {
            { header = "New Features", items = {
                { title = "Reminder groups",
                    desc = "Spells, items and weapon enchants pulse in the middle of your screen when they're ready, with sounds, text to speech and animations." },
                { title = "Reminder triggers",
                    desc = "A reminder can fire the moment a spell becomes usable, even while it's on cooldown, and stay on screen until you cast it." },
                { title = "Warning glow",
                    desc = "An icon can glow while your ammo runs low, your pet's health is low or your pet isn't happy." },
                { title = "Ammo count colors",
                    desc = "The ammo count changes color at up to three thresholds you set." },
                { title = "Pet and ammo conditions",
                    desc = "Load conditions for your pet's happiness and for low ammo." },
                { title = "Sound when usable",
                    desc = "A spell icon can play a sound the moment it can be cast." },
                { title = "Pick a frame",
                    desc = "Anchor any bar, group or icon to a UI frame by clicking it on screen or choosing a common one from a list. Bars and groups can also anchor to a free icon." },
                { title = "Missing text",
                    desc = "An aura icon's label can show only while the aura is missing." },
            } },
            { header = "Improvements", items = {
                { title = "A clearer editor",
                    desc = "Tabs by what you want to happen (Show & Hide, Glows, Sounds), a table of how an icon looks in each state, and fine-tuning that folds away until you need it." },
                { title = "Modules page",
                    desc = "Button Press Highlight, Tooltip IDs and Auto-rank now live on their own page." },
                { title = "New Layout",
                    desc = "Pick a starting point from template cards, an empty layout or an import." },
                { title = "Color opacity",
                    desc = "Color pickers set opacity too, where it applies." },
                { title = "Thresholds",
                    desc = "Add or remove thresholds with a button instead of a slider." },
                { title = "Health bars",
                    desc = "Can pulse at their last threshold, for example your pet under 20%." },
                { title = "Tooltip IDs",
                    desc = "Choose which IDs show, or show them only while holding Shift." },
                { title = "Sound lists",
                    desc = "Each sound says where it comes from: Arc Auras, the game or another addon." },
                { title = "Talent picker",
                    desc = "Hovering a talent shows its full description, and every icon is fully visible." },
                { title = "Edit buttons",
                    desc = "A bar's Edit button sits small inside its corner, and whatever you're editing reads Editing in yellow." },
                { title = "Groups",
                    desc = "Choose the background behind a group while you edit it. The Add window's Icon Group tab is now just Group." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Hide when ready",
                    desc = "Cooldown bars set to hide when ready now hide right after a reload." },
                { title = "Combo points",
                    desc = "The bar no longer misses a point until you gain the next one." },
                { title = "Tooltip IDs",
                    desc = "Spells with many Cooldown Manager entries no longer stretch the tooltip across the screen." },
                { title = "Shared sounds",
                    desc = "Sounds from your other addons now show in every sound list." },
                { title = "Talent picker",
                    desc = "The three trees fill the window evenly, and their backgrounds fill each panel." },
                { title = "Scrolling",
                    desc = "Making the window bigger no longer leaves a page scrolled down with no way back up." },
            } },
        },
    },
    {
        version = "1.5.0",
        intro = "Weapon enchants, totems by spell, a range bar, smarter swing bars, more aura glows and fewer tabs.",
        sections = {
            { header = "New Features", items = {
                { title = "Weapon enchants",
                    desc = "Icons and bars for imbues, poisons, oils and stones, with time left and charges." },
                { title = "Totems by spell",
                    desc = "Track a totem by its spell, at any rank and in any slot, in combat too. Totem icons can also show a pulse timer." },
                { title = "Range Bar",
                    desc = "Shows how far away your target is, using hunter, melee or caster presets or your own bands. Melee range works on every class." },
                { title = "Show by range",
                    desc = "Any icon, group or bar can show only while your target is in or out of range of a spell." },
                { title = "Next-swing abilities",
                    desc = "Swing bars show when Heroic Strike, Raptor Strike or Maul come off cooldown, and which one is queued." },
                { title = "Ability colors",
                    desc = "A swing bar can change color while an ability is queued or after you cast it." },
                { title = "More aura glows",
                    desc = "Up to four glows on one aura icon, each for its own buff or debuff, and optionally only in combat." },
                { title = "On-use trinkets only",
                    desc = "Trinket icons can hide passive trinkets." },
                { title = "Starter Layout",
                    desc = "One click makes a layout with Cooldowns, Utility and Buffs groups placed under your character." },
            } },
            { header = "Improvements", items = {
                { title = "Fewer tabs",
                    desc = "Options are grouped into fewer tabs, and Thresholds is now called Color Changes." },
                { title = "Swing bars",
                    desc = "A fill that closes in from both ends, up to three ticks, a spark and an off-hand label." },
                { title = "Out of range on swing bars",
                    desc = "Dim when out of range now works on WoW Forever, for every class." },
                { title = "Reverse swipe",
                    desc = "New totem and weapon enchant icons start with a reverse swipe." },
                { title = "Spell picker",
                    desc = "The Add window shows your spellbook as a grid of icons." },
                { title = "Sidebar",
                    desc = "Icon groups open to show their icons, and anything that doesn't load on this character folds away under NOT LOADED." },
                { title = "Editing on screen",
                    desc = "The eye button hides an item while the options are open, and group names no longer cover what sits above them." },
                { title = "Import and export",
                    desc = "Export only what loads on this character, or import groups without their icons." },
                { title = "Match size",
                    desc = "A bar anchored to another bar or group can now match its height as well as its width." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Background opacity",
                    desc = "100 now gives a fully solid bar background." },
                { title = "Long countdowns",
                    desc = "Timers like 25 m no longer slip under the icon border." },
                { title = "Resource bar text",
                    desc = "Percent and value text no longer causes an error in combat." },
                { title = "Eye buttons",
                    desc = "The eye buttons no longer go blank after a click." },
            } },
        },
    },
    {
        version = "1.4.0",
        intro = "Arc UI Forever is now Arc Auras. Your setup moves over by itself, and this update brings an off-hand track for swing bars, labels that follow your auras, and a smoother options window.",
        sections = {
            { header = "New Features", items = {
                { title = "Arc UI Forever is now Arc Auras",
                    desc = "Same addon, new name and its own page. Your setup moves over by itself the first time Arc Auras loads. Type /arcauras to open it; the old commands still work." },
                { title = "Off-hand on swing bars",
                    desc = "A main-hand swing bar can show your off-hand's swing too: a thin line, a thick line, half of the bar or a moving mark, in its own color." },
                { title = "Labels while an aura is up",
                    desc = "An aura icon's labels can show only while the aura is up, in combat too." },
                { title = "Play on screen for icons",
                    desc = "Watch the icon preview play on the real icon, right where it sits on your screen." },
                { title = "GCD and wand looks",
                    desc = "Choose how the global cooldown shows on spell icons: hidden, an edge, a swipe or both, in your own color. Priests, mages and warlocks get the same choice for their wand." },
            } },
            { header = "Improvements", items = {
                { title = "Minutes and seconds",
                    desc = "Longer timers read 1:30 instead of 90 on icons and bars. Pick when that starts, from under 2 minutes to under 1 hour, or turn it off." },
                { title = "Smoother first open",
                    desc = "The options window no longer freezes the game the first time you open it; a small loading bar shows while it gets ready." },
                { title = "True-to-size icon preview",
                    desc = "The icon preview now matches the real icon, borders and crop included." },
                { title = "Preview background",
                    desc = "Previews sit on a softer slate color by default, or any color you pick." },
            } },
            { header = "Bug Fixes", items = {
                { title = "Wand shots",
                    desc = "Shooting your wand no longer makes cooldown icons and bars look like they are on a short cooldown." },
            } },
        },
    },
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
        title = "|cff3fc9f2What's New|r|cffd5e2f2 in Arc Auras|r",
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
        "The first time you log in after Arc Auras updates, this window opens once with what changed. Settings has the same switch.")
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
