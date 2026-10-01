# Arc Auras

## 1.9.0

Cooldown Manager layouts, totem bar icons, mana regen sparks and a picture picker for textures.

### New Features

- **From my Cooldown Manager** - Copy your Cooldown Manager into a layout in one click.
- **Totem bar icons** - Show your totem bar's pick and drop it with a click or a key.
- **Totem out of range** - Grey out, tint or glow a totem icon while its buff is not on you.
- **Shaman in my group** - A new Show When rule.
- **Five-second rule and mana ticks** - Sparks on mana bars for both.
- **Picture picker** - Pick a texture's picture from thumbnails, with a search.
- **Copy and duplicate** - Copy, duplicate or delete several items at once.
- **Imbue damage** - Optional tooltip line: what an imbue or weapon stone adds to your weapon.

### Improvements

- **You, then your target** - Aura icons can show your buff, then your target's.
- **Textures** - Crop, pulse and a tinted dim copy.
- **Weapon enchants** - Several enchant IDs per icon or bar, and enchant IDs in weapon tooltips.
- **Pick Frame** - Works on every anchor and can pick your Arc Auras items.
- **Color bands** - Start with one band. Add more as you need them.
- **Custom text** - One Show choice in each icon's own words.
- **Cost & Regen** - A new tab on resource bars.
- **Group load conditions** - Match the group fixes icons that leave out the group's classes.

### Bug Fixes

- **Dynamic aura groups** - Icons sit one Spacing apart, as in the edit grid.
- **Match width** - Bars matched to a group span exactly its icons.
- **Anchored bars** - No more thin background line along a bar's edge.
- **Aura icon texts** - Stay bright when you lower the active opacity.
- **Ammo icons** - Custom text for in stock or out of stock now works.

## 1.8.0

Missing-only aura icons and glows, textures, group buff counts, texts for spells and auras, updates for shared setups and known spells.

### New Features

- **Missing-only aura icons** - Set an aura icon's Active opacity to 0% and it shows only while the aura is missing.
- **Missing glows** - Aura glows can show only while the aura is missing.
- **Aura reminders** - Reminder groups can remind you of a missing buff or debuff.
- **Group Buff icons** - Count who in your party or raid has a buff, show it while anyone lacks it, and hover to see who is missing.
- **Textures** - Show a picture with an aura or a cooldown, or let it fill and drain like a bar. Pick from 170 pictures or use your own.
- **Update shared setups** - Import a newer version of a string you already have and update your copy instead of adding a second one. Works with strings made with 1.8.0 or later.
- **Known spells** - Spell icons and cooldown bars can wait until you learn their spell, and anything can load only while you know a spell.

### Improvements

- **Texts for spells and auras** - A text can follow a spell or an aura: its cooldown, charges, time left or stacks, or your own words for its state.
- **Text editing** - Texts take their spell's or aura's name, have their own Appearance page, and show a sample while you edit.
- **Custom text** - Labels are now Custom text. On aura icons each one shows always, while the aura is up, or while it is missing.
- **Aura icon opacity** - Active and Missing opacity are fully separate, and a dimmed icon fades instead of turning dark.
- **Glow cards** - Glow when sits at the top of each card.
- **Option folds** - More options folds open and close freely, even when they hold a changed setting.
- **While editing** - Combat-only aura glows and faint aura icons stay visible while the options window is open.
- **Ammo icons** - The count has its own Count tab and the preview shows your real count. The Duration tab is gone.
- **Version check** - A string from a newer Arc Auras tells you to update.
- **First imports** - Strings made with 1.8.0 or later keep their name and place. Only a second copy gets (import).

### Bug Fixes

- **New items** - Appear in the middle of the screen instead of further down each time.
- **Combo points** - The first point on a new target always shows.
- **Aura sounds** - No longer play twice after a reload.
- **Aura sounds in combat** - Changing one mid-fight no longer risks a blocked-action error.
- **Shared looks** - Items from a setup that uses Save as Default look the same for everyone who imports them.
- **Character-only items** - An item set to load only on its maker's character now loads for whoever imports it.

## 1.7.0

Aura groups for any aura or nameplate, text elements, clickable party bars, aura sounds, over-shields and less CPU.

### New Features

- **Every aura on a unit** - Aura groups can show every buff or debuff on a unit, no spell IDs needed.
- **Nameplate debuffs** - Aura groups can show your debuffs on enemy nameplates.
- **Text elements** - Put health, power, cooldowns, aura timers or your own words anywhere.
- **Clickable health bars** - Party health bars target on click and work with click casting.
- **Aura sounds** - Aura icons can play a sound when the aura appears, gains a stack or drops.
- **Over-shield** - Shields past full health now show inside the health bar.
- **Select several** - Ctrl or Shift click items to move, export or edit them together.
- **From your action bars** - Fill a group with icons from your action bars.
- **Cooldown glow** - Icons can glow while on cooldown.

### Improvements

- **Lighter on CPU** - Cooldown icons do much less work in combat.
- **Group + button** - Adds icons straight into that group.
- **Thinner bars** - Bars go down to 1 pixel.
- **Edit buttons** - Show them on icons only, bars only, or not at all.
- **Add texts** - Health and resource texts use a + Add button.
- **Text offsets** - Texts move up to 200 pixels, and offsets start at 0. Existing setups keep their look.
- **More sounds** - Eleven new alert sounds.

### Bug Fixes

- **Aura bars** - Draw right away after a reload in combat.
- **Macro keybinds** - Spells on your bars through a macro show their keybind and press highlight.
- **Aura group growth** - Groups grow from the corner you picked.
- **Friendly units** - Aura bars treat immune friendly units as friendly.
- **Tooltip IDs** - The aura ID line hides in combat instead of showing <secret>.
- **Range checks** - Fixed an error checking range to your target in dungeons.
- **Outside texts** - Text above or below a bar lines up with its edge.
- **Stack colors** - The Keep each stack's own color switch now shows.

## 1.6.0

Reminder groups, pet and ammo warnings, frame picking and a clearer editor.

### New Features

- **Reminder groups** - Spells, items and weapon enchants pulse in the middle of your screen when they're ready, with sounds, text to speech and animations.
- **Reminder triggers** - A reminder can fire the moment a spell becomes usable, even while it's on cooldown, and stay on screen until you cast it.
- **Warning glow** - An icon can glow while your ammo runs low, your pet's health is low or your pet isn't happy.
- **Ammo count colors** - The ammo count changes color at up to three thresholds you set.
- **Pet and ammo conditions** - Load conditions for your pet's happiness and for low ammo.
- **Sound when usable** - A spell icon can play a sound the moment it can be cast.
- **Pick a frame** - Anchor any bar, group or icon to a UI frame by clicking it on screen or choosing a common one from a list. Bars and groups can also anchor to a free icon.
- **Missing text** - An aura icon's label can show only while the aura is missing.

### Improvements

- **A clearer editor** - Tabs by what you want to happen (Show & Hide, Glows, Sounds), a table of how an icon looks in each state, and fine-tuning that folds away until you need it.
- **Modules page** - Button Press Highlight, Tooltip IDs and Auto-rank now live on their own page.
- **New Layout** - Pick a starting point from template cards, an empty layout or an import.
- **Color opacity** - Color pickers set opacity too, where it applies.
- **Thresholds** - Add or remove thresholds with a button instead of a slider.
- **Health bars** - Can pulse at their last threshold, for example your pet under 20%.
- **Tooltip IDs** - Choose which IDs show, or show them only while holding Shift.
- **Sound lists** - Each sound says where it comes from: Arc Auras, the game or another addon.
- **Talent picker** - Hovering a talent shows its full description, and every icon is fully visible.
- **Edit buttons** - A bar's Edit button sits small inside its corner, and whatever you're editing reads Editing in yellow.
- **Groups** - Choose the background behind a group while you edit it. The Add window's Icon Group tab is now just Group.

### Bug Fixes

- **Hide when ready** - Cooldown bars set to hide when ready now hide right after a reload.
- **Combo points** - The bar no longer misses a point until you gain the next one.
- **Tooltip IDs** - Spells with many Cooldown Manager entries no longer stretch the tooltip across the screen.
- **Shared sounds** - Sounds from your other addons now show in every sound list.
- **Talent picker** - The three trees fill the window evenly, and their backgrounds fill each panel.
- **Scrolling** - Making the window bigger no longer leaves a page scrolled down with no way back up.

## 1.5.0

Weapon enchants, totems by spell, a range bar, smarter swing bars, more aura glows and fewer tabs.

### New Features

- **Weapon enchants** - Icons and bars for imbues, poisons, oils and stones, with time left and charges.
- **Totems by spell** - Track a totem by its spell, at any rank and in any slot, in combat too. Totem icons can also show a pulse timer.
- **Range Bar** - Shows how far away your target is, using hunter, melee or caster presets or your own bands. Melee range works on every class.
- **Show by range** - Any icon, group or bar can show only while your target is in or out of range of a spell.
- **Next-swing abilities** - Swing bars show when Heroic Strike, Raptor Strike or Maul come off cooldown, and which one is queued.
- **Ability colors** - A swing bar can change color while an ability is queued or after you cast it.
- **More aura glows** - Up to four glows on one aura icon, each for its own buff or debuff, and optionally only in combat.
- **On-use trinkets only** - Trinket icons can hide passive trinkets.
- **Starter Layout** - One click makes a layout with Cooldowns, Utility and Buffs groups placed under your character.

### Improvements

- **Fewer tabs** - Options are grouped into fewer tabs, and Thresholds is now called Color Changes.
- **Swing bars** - A fill that closes in from both ends, up to three ticks, a spark and an off-hand label.
- **Out of range on swing bars** - Dim when out of range now works on WoW Forever, for every class.
- **Reverse swipe** - New totem and weapon enchant icons start with a reverse swipe.
- **Spell picker** - The Add window shows your spellbook as a grid of icons.
- **Sidebar** - Icon groups open to show their icons, and anything that doesn't load on this character folds away under NOT LOADED.
- **Editing on screen** - The eye button hides an item while the options are open, and group names no longer cover what sits above them.
- **Import and export** - Export only what loads on this character, or import groups without their icons.
- **Match size** - A bar anchored to another bar or group can now match its height as well as its width.

### Bug Fixes

- **Background opacity** - 100 now gives a fully solid bar background.
- **Long countdowns** - Timers like 25 m no longer slip under the icon border.
- **Resource bar text** - Percent and value text no longer causes an error in combat.
- **Eye buttons** - The eye buttons no longer go blank after a click.

## 1.4.0

Arc UI Forever is now Arc Auras. Your setup moves over by itself, and this update brings an off-hand track for swing bars, labels that follow your auras, and a smoother options window.

### New Features

- **Arc UI Forever is now Arc Auras** - Same addon, new name and its own page. Your setup moves over by itself the first time Arc Auras loads. Type /arcauras to open it; the old commands still work.
- **Off-hand on swing bars** - A main-hand swing bar can show your off-hand's swing too: a thin line, a thick line, half of the bar or a moving mark, in its own color.
- **Labels while an aura is up** - An aura icon's labels can show only while the aura is up, in combat too.
- **Play on screen for icons** - Watch the icon preview play on the real icon, right where it sits on your screen.
- **GCD and wand looks** - Choose how the global cooldown shows on spell icons: hidden, an edge, a swipe or both, in your own color. Priests, mages and warlocks get the same choice for their wand.

### Improvements

- **Minutes and seconds** - Longer timers read 1:30 instead of 90 on icons and bars. Pick when that starts, from under 2 minutes to under 1 hour, or turn it off.
- **Smoother first open** - The options window no longer freezes the game the first time you open it; a small loading bar shows while it gets ready.
- **True-to-size icon preview** - The icon preview now matches the real icon, borders and crop included.
- **Preview background** - Previews sit on a softer slate color by default, or any color you pick.

### Bug Fixes

- **Wand shots** - Shooting your wand no longer makes cooldown icons and bars look like they are on a short cooldown.

## 1.3.0

Castbars, layout looks, anchors for free icons and your mouse, a button press highlight, and aura glows that hold steady in combat.

### New Features

- **Castbars** - Castbars for you, your target and your focus: the spell's name, icon and time, a spark, colors for interrupted and failed casts and for casts that can't be interrupted, your latency, and a tick mark for every tick of your channels. Your own castbar can hide Blizzard's. Works in combat.
- **Layout looks** - A layout can set the look of everything in it, from Icon Looks, Group Looks and Bar Looks on the layout. Its icons, groups and bars follow those settings and can still set their own, and Reset to layout makes them follow again.
- **Anchor free icons** - Icons that are not in a group get an Anchor tab: pin one to a group, a bar, a layout or a named frame, then drag it or use its offsets to place it.
- **Anchor to your mouse** - Groups, bars and free icons can follow your mouse cursor.
- **Button Press Highlight** - When you press an action button, cast through a macro or use a trinket, every icon of that ability lights up for a moment. Pick its look, color and how long it lasts in Settings.
- **Icon shadow, dispel borders and fonts** - Icons can wear the Cooldown Manager's soft shadow, aura icons can color their border by the aura's type (Magic, Curse, Disease or Poison), and every icon text can use any font, including fonts from other addons.
- **More glow styles** - Marching ants, the Cooldown Manager's flash and the proc glow without its opening burst join the glow styles, the Pixel glow gets a line length, and every glow can be moved with Move X and Y.
- **Play on screen** - The bar preview can play on the bar itself, in its real place and size.

### Improvements

- **Better aura glows** - Aura glows are handled better: they show right away and keep going smoothly for as long as the aura is up.
- **Layouts list scrolls** - The layouts sidebar scrolls when it fills up, so everything stays in reach.

### Bug Fixes

- **Aura glows restarting** - Glows on buff and debuff icons restarted, sometimes several times, when combat started or ended. They now keep going.
- **Bar preview zoom** - Zooming the bar preview no longer moves the text on the bar.

## 1.2.0

A live preview for bars, bars on your target's nameplate, an aura shown on a cooldown icon, and a choice of when aura glows show.

### New Features

- **Live bar preview** - The bar editor shows the bar you are editing, drawn with your real settings, and can play it in a loop: filling, counting down, recharging and stacking up.
- **Zoom the bar preview** - Zoom in and out with the - and + buttons or the mouse wheel, click the percentage to fit the bar again, and drag a big bar to look around. Standing bars get a taller preview.
- **Bars on your target's nameplate** - Anchor a bar to your target's nameplate, for example your combo points. It follows your target and hides while your target has no nameplate. While this window is open, the bar's preview shows it on a stand-in nameplate so you can place it.
- **Icon type labels** - Every icon wears a colored label saying what it is, CD Icon, Aura Icon, Timer Icon, Item Icon, Trinket Icon, Totem Icon or Ammo Icon, in the sidebar, the layout view, the editor, import and export, and search.
- **An aura on a cooldown icon** - Switch on Show an aura on this icon on a spell icon's Tracking tab, and while the aura is up the icon shows the aura's time over its cooldown, like the Cooldown Manager does. It starts on the most likely aura for you, and the new Aura Active tab styles how it looks. Works in combat.
- **Glow timing** - Choose when an aura glow shows: the whole time the aura is up, only in the refresh (pandemic) window, or once little time is left, in percent or in seconds. For aura icons and the aura on a cooldown icon, in combat too.

### Improvements

- **Delete from the layout view** - Hover a tile to get an X in its corner that deletes it (it asks first), in place of the Edit and Delete buttons that covered the name. Click the tile to edit it.
- **Aura swipe colors** - The aura on a cooldown icon uses the Cooldown Manager's gold swipe by default. Change its color, direction and edge, and grey the icon while the aura is down. Aura icons can change their swipe's edge color and size too.
- **Timer rounding per bar and icon** - Round timer numbers can be set on each bar and icon, or left on the Settings choice.
- **New things appear in the middle** - New layouts, groups, icons and bars appear in the middle of your screen, one step lower when something already sits there.

### Bug Fixes

- **Short cooldowns count down** - A two second cooldown like Throw showed no countdown numbers on its icon or bar. It does now, and so do short auras on aura icons. The global cooldown still shows no numbers.
- **Tabs on first open** - Some tabs in the options window could sit in the wrong place or be missing until you clicked one. They now all show right away.
- **Empty option boxes** - Bar options no longer show a stray box, such as Health text 3 or Pips, holding only the Copy to, Save as Default and Reset buttons. Those buttons now sit at the bottom, below everything they cover.

## 1.1.0

Standing bars, up to three texts on resource and health bars, aura search by name, and a choice of how timers round.

### New Features

- **Stand a bar up** - Set a bar to Vertical and tick Stand the bar up: it turns a quarter so it is tall and thin, with its icon, texture and gradient turning along. Horizontal lays it down again.
- **More than one text** - Resource and health bars can show up to three texts, each with its own format, size, color and place, so a bar can show the value and the percent together.
- **Custom name text** - Give any bar's name text your own wording, or leave it empty for the normal name.
- **Find auras by name** - Type part of a buff or debuff's name when you add an aura icon or aura bar, or in an aura bar's settings, and pick it from the list to fill in its spell IDs. Every rank comes along, and spells you know are marked.
- **Aura bars: on whom, cast by whom** - Aura bars can watch you, your target, focus, pet or a party member, and count the aura from anyone, only you, or anyone but you, the same choices aura icons have.
- **Swing bar thresholds and ticks** - Color a swing bar in the last part of the swing, in tenths of a second, and add tick marks measured in seconds of the swing.
- **Timer rounding** - Choose in Settings whether countdowns round up, like action bar cooldowns (the default), or down, like buff timers.
- **What's New in game** - After each update a window shows what changed, once. Turn it off or open it again in Settings, or type /arccl.

### Improvements

- **Icons keep their own size** - A bar's icon now has its own size, with Match the bar's size as an option.
- **Swing bars fill up** - Swing bars fill during the swing and sit empty between swings by default.
- **Taller and thinner bars** - Bar width and height both go from 4 to 600.
- **Text settings in one place** - What a resource bar's text shows is now on the Text tab with the rest of its text options; your choice carries over.
- **Search** - A group's Alignment is found even while Dynamic is off, and the result says to switch Dynamic on first.

### Bug Fixes

- **Icon and bar timers agree** - An icon and a bar showing the same timer could read one second apart; every timer now rounds the same way.
- **Spell icon art** - Spell icons no longer take another ability's art from your action bars (a Raptor Strike icon could show Mongoose Bite). Toggles like aspects and Stealth show the active art of the rank you actually cast.
- **Ranged swing bar error** - Fixed an error at the end of a ranged swing in combat.
- **Vertical aura bars** - Aura bars now redraw their color layers correctly after switching between horizontal and vertical.

## 1.0.0

The first release of Arc UI for WoW Forever. Type /arcui in game to open it. On retail, Arc UI keeps updating as before.

### New Features

- **Layouts** - Movable blocks that hold your icon groups, free icons and bars. Drag them into place or type an exact position, and anchor anything to anything.
- **Icon groups** - Cooldown groups on a grid you shape yourself, with dynamic layouts that close the gaps as icons drop out, and aura groups that keep a fixed grid or show only the buffs and debuffs that are up.
- **Icons** - Track spells, auras, items, trinkets, totems and your ammo. Ready, cooldown, proc and usable states each get their own glow, tint and opacity, with swipes, duration and charge text, keybinds and up to three custom labels.
- **Aura icons** - One icon can watch several auras: buffs on you, your target, focus, pet or party, and debuffs on your target or focus, from anyone, only you or anyone but you. Style how it looks while the aura is up and while it is missing, and light it up with a glow, Blizzard's own proc glow included, when the aura appears. All of it works in combat.
- **Custom icon art** - Give any icon other art by icon, spell or item ID, and give aura icons their own art for when the aura is up and when it is missing.
- **Toggle spells follow your bars** - Stealth, aspects and other toggles show the same active art your action bar shows.
- **Spell ranks** - Icons and bars can follow whichever rank of a spell you know. Switch on auto-rank under QOL and your action bars move up to each new rank you learn, leaving the lower ranks you placed on purpose and your macros alone.
- **Aura bars** - Buff and debuff bars with duration fill, stack fill, countdown and stack text that keep working in combat, and that can hide completely while the aura is down.
- **Stack colors** - Recolor an aura stack bar at the stack counts you choose, with a max-stacks color on top.
- **Cooldown, swing and resource bars** - Charge-aware cooldown bars, swing timers and bars for every power type, colored by time left or by power, with your own textures, backgrounds and borders.
- **Combo points** - As a bar with a tick mark for every point, or as pips in square, circle or diamond cells with their own point colors.
- **Health bars** - For you, your target, focus, pet or party members, with incoming heals, absorb shields and heal absorbs drawn on the bar, each with its own toggle and color. Color the bar by class, reaction or a health gradient, and change its color below the health you choose.
- **Cost icons** - A spell's icon at its cost on your mana or energy bar, dimmed while you cannot afford it.
- **Sound alerts** - Play a sound when a spell is ready, starts its cooldown or gains a charge. Pick from a built-in pack or the game's own sounds and preview them first.
- **Load conditions and fades** - Show anything only for some classes, characters or talents, and fade it by combat, mounting and more.
- **Sharing** - Export a whole layout or just the pieces you tick, import strings from friends, and rename, duplicate or move anything between layouts.
- **Copy settings in one click** - Copy any block of settings to another group, a whole layout or everything of its kind, or save it as the default for new ones.
- **Your shared media** - Textures, fonts, borders and sounds from your other addons appear in every list beside the built-in ones.
- **An options panel built for this** - Tiles or cards for your layout contents, a sidebar you can resize, a Position tab everywhere, a live preview that plays each icon's states, and an eye on anything not loaded for this character so you can still see and place it while you edit.
- **Search everything** - One box finds your layouts, groups, icons and bars by name or by spell, item or icon ID, and any option by its name. Click a result to jump straight to it, highlighted.
- **IDs in tooltips** - Spell, aura, item and other tooltips anywhere in the game show the ID and the icon ID, plus the Cooldown Manager's cooldown ID when there is one. Turn it off in Settings, where you can also have your icons show their tooltips only while this window is open.
