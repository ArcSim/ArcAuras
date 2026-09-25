# Arc UI Forever

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
