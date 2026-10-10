# Arc Auras

## 2.6.0

Copy your Cooldown Manager into a layout, icon shapes and Masque skins, frames that move with a group, and an options window that opens without a freeze.

### New Features

- **From Cooldown Manager** - New Layout copies the game's Cooldown Manager into a layout: its bars, spells, auras, totems and items, in its own look or ours.
- **Cooldown Manager look** - Any icon or group can wear the Cooldown Manager's icon look.
- **Icon shapes** - Wide, Tall, Column and Cropped sizes with the picture cropped to fit, and icons cut to a rounded square, circle, diamond or hexagon.
- **Masque skins** - Skin your icons with any Masque skin (Modules > Masque Skins).
- **Frames that move with a group** - Pin up to four game frames, like your player frame, beside a group and they move with it (Position > Anchor).
- **Anchor list** - An icon or group can list up to four frames to anchor to and sits on the first one shown.
- **Several spells on one icon** - One cooldown icon for spells that replace each other: it shows the one you cast or know.
- **Custom Bars show stacks** - As pips, icons or a segmented bar, with an Arcane Blast template for Mages.
- **Glow while suggested** - A spell icon glows while the game's Assisted Highlight suggests it next.
- **Items you can't use yet** - An item icon can take its own look while the game says you can't use it (Conditions > By State).
- **Spoken alerts** - Icon alerts can say words you type, with or without a sound.
- **Glow styles** - A pandemic border with the Cooldown Manager's art, and two styles that match the action bar's queued and toggled-on looks.
- **Skyriding** - A condition to show or fade anything while skyriding.
- **Shield equipped** - A condition that loads or shows anything only with a shield on.
- **Fold the options window** - Fold it to its title bar and keep editing with the Edit buttons on screen.

### Improvements

- **Totems and guardians** - An icon can show its totem or guardian first, then its aura, as the Cooldown Manager does.
- **Dynamic aura groups** - Totems line up in a row above the group.
- **When states overlap** - Pick which state a proc lifts and which one keeps texts bright, and show usability colors on a cooling spell (Conditions > By State).
- **Glows** - The game's own glow color, a dark line behind pixel glows, Glow size on button and proc glows, and bigger offsets.
- **Duration and stack texts** - Left and right anchors, Show under, more color bands, bands in percent, and shadow color and offset.
- **Keybinds** - An upper-case short style, your own replacements, an outline, and keybinds on items, trinkets and totems.
- **Borders** - Class color, grey with the icon, the game's debuff border art, an out-of-range shadow and a thickness for group borders.
- **Swipe** - Thicker edges, and insets for the aura swipe.
- **On this icon** - Items and trinkets can show an aura, a totem or a set duration over their cooldown.
- **Textures** - Follow a Custom trigger's stacks, and the dim copy hides with the picture unless you keep it.
- **Custom timers** - Up to two hours, keep running through a reload, several spells per rule, each stack on its own clock, a count at 0, and new triggers like "You cast any spell but these".
- **Stack bars** - A mark between each stack.
- **Fade when** - Can wait until all of its conditions hold.
- **Cooldown Manager switch** - Turn the game's Cooldown Manager off in Settings, or copy it and turn it off in one click.
- **New Layout** - The import cards show each addon's icon, and long titles wrap.
- **Options window** - Opens without a freeze, loads the rest without frame drops, and scales down to 20%.

### Bug Fixes

- **Totem time** - Shows on icons whose totem is a guardian or carries another name than its spell.
- **Dynamic groups** - A bigger icon in a one-row or one-column group no longer overlaps its neighbours or shifts when the options open.

## 2.5.0

A Defaults page, resource bar states, a texture update and icons that wait for the end of a cooldown or aura.

### New Features

- **Defaults page** - Every kind of item's defaults in one place (sidebar > Defaults).
- **Resource bar states** - Color the bar, mark costs and glow by spell, aura or power under Conditions > By State.
- **Opacity near the end** - Hide or fade a cooldown until its last seconds, or an aura until its pandemic window.
- **Textures** - Stack pictures, ring fills, time left looks and texts, animations, tiling and a full art search.
- **Item level on tooltips** - Modules > Tooltip IDs.

### Improvements

- **Arc Procs** - Special Auras are now Arc Procs everywhere.
- **Import / Export** - Two clear tabs: what you share, and what an import holds and where it goes.
- **Recharging** - Its own look on charge spells, with its own preview loop.
- **Weapon enchants** - A No weapon state and an option to load only with a weapon in hand.
- **Resource bars** - Fold in half on any power, and druid form conditions.
- **Pet autocast** - Counts as toggled on.
- **Options window** - A loading bar, draggable scroll bars and clearer tabs.

### Bug Fixes

- **Centred groups** - No longer shift by a pixel.
- **Aura icons** - Max stacks color, dispel borders and target swaps fixed.
- **Comparison tooltips** - The IDs show every time.
- **Save as Default** - No longer copies an icon's own picture onto its whole kind.

## 2.4.0

Themes, glows on every bar and talents for any class and spec.

### New Features

- **Themes** - Settings > Theme: Classic, Midnight Ink, Dusk or Graphite, with an optional Soft light. Dusk is the new default.
- **Bar glows** - Every bar can glow while any aura is up or missing, or by any spell's cooldown. Find them under the bar's Conditions tab (was Show & Hide).
- **Talents for any class** - Each class under Class and Spec has a Talents button that opens its trees, with a tab per spec, whatever you play. Picks count only on their own class and spec.

### Improvements

- **Options look** - Folder tabs, boxed sections and a cleaner font.
- **Talent swaps** - Icons, bars and glows follow a spell a talent replaces, with its art, tooltip and keybind.
- **Talent window** - Matches your panel scale.
- **Combat** - The options window waits until combat ends to open, and closes when a fight starts.

### Bug Fixes

- **Unloaded items** - No longer show on screen while editing after a group's eye is clicked twice; class Views show only what they list.
- **Own settings** - Text, picture and reminder items and range bars now follow their Ignore Override.

## 2.3.0

Stance icons, a lock for layouts and groups, a sidebar View and pack updates you can undo.

### New Features

- **Stance icon** - Add > Icon > Stance shows the stance, form or aura you are in, or one stance that lights up while you are in it.
- **Lock in place** - A padlock beside a layout's or group's eye keeps it from being dragged on screen. It shows on hover and stays while locked, and Position has the same switch.
- **Sidebar View** - List everything, only what loads on this character, a section per class, or one class, with class marks.
- **Pack updates** - Undo the last update, keep your own version of any item, and pack items you deleted stay deleted.
- **Pack info** - A pack can carry its name, version, link and notes. You see them before you import, with any sounds, fonts or textures you don't have.
- **Order by time left** - Aura groups with Close gaps on can put the aura closest to running out first, in one shared look.
- **Conditions in aura groups** - Aura icons in a group with Close gaps off get their own Load When, Never Load When and Fade When.
- **New conditions** - Pet has no target, Auto Shot or Shoot, Melee attack is on and Not attacking.
- **Spell queue tick** - Your castbar can mark when you can queue your next spell.
- **Color each tick** - Each number in a custom tick list can have its own color.

### Improvements

- **Clearer group options** - Dynamic is now Close gaps, with plainer names for its other options.
- **Thin ticks** - Tick marks and dividers can be 1 pixel thick.
- **Home page** - Click a section's heading to fold it.
- **Performance** - Less CPU while your mana or energy refills.
- **Texts over glows** - Duration and stack texts always sit over the glows on aura group buttons.

### Bug Fixes

- **Duration text** - Turning it off on aura icons now sticks without a /reload.
- **Resource bar looks** - A look per form, spec or talent no longer forgets a switch you turned off when you log in.
- **Buffs and debuffs** - Aura groups showing both now add their debuffs reliably, and switching back to Buffs or to nameplates removes them at once.
- **Load When** - No longer promises silence on aura icons: the game still plays their sounds.

## 2.2.0

The first retail release of Arc Auras. Feedback is welcome on Discord.

### New Features

- **Arc Auras on retail** - Icons, icon groups and bars for your cooldowns, auras and resources, set up from one panel.
- **Import from ArcUI ProcTracker** - Bring your trackers over, switched-off ones too, with the same looks, sounds and counts. Each one you import is switched off in ArcUI ProcTracker, so nothing shows twice. Arc Auras offers it when it finds ProcTracker set up.
- **Special Auras** - Doom Winds, Tempest, Storm Unleashed, Elemental Tempest, Deeply Rooted Elements, Soulburst, Nature's Guardian and Power Infusion, as icons or deck bars. Talent decks load only with their talent.
- **Pin any text** - Stack counts, custom texts, keybinds and bar texts can sit on an action button, a Cooldown Manager icon or any named frame.
- **Cooldown ID pins** - Pin to one exact Cooldown Manager icon, even when two icons share a spell.
- **Resource bars** - Rune and Essence recharge countdowns, bar-style slots, charged combo points, fold in half, and an option to hide Blizzard's class bar.
- **A look per form, spec or talent** - A resource bar can keep its own colors, texts and ticks for each druid form, each spec, or with and without a talent.
- **Sound item** - A sound or spoken line with nothing on screen, on the same triggers as Custom Icons, a condition, or an aura gained, stacking or fading.
- **Conditions** - Load, fade or play a sound by combat, aggro, mounted, group, instance, raid encounter and more.
- **Charge spells** - Their states read Ready, Recharging and Depleted.
- **Totem slots** - An empty slot shows the totem icon.

### Bug Fixes

- **Glows over borders** - The glow on an aura icon draws over its border instead of hiding behind it.

### Known Issues

- **Waiting for patch 12.1.5** - Debuff-colored borders, stack colors on aura bars and debuff type looks are hidden until then.
- **Sound item aura rules** - Until patch 12.1.5, Quiet for does not limit them, so they play every time.
- **/arcauras** - With ArcUI installed, /arcauras opens ArcUI. Use /arcui2 instead.
