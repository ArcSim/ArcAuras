# Arc Auras

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
