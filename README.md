# Interrupt Highlight 1.0.0

Interrupt Highlight is a World of Warcraft Retail addon that highlights your ready true interrupt when a watched enemy casts an interruptible spell. It supports action bars and Blizzard's Cooldown Manager.

## Features

- **Target only** watches your current target. **All visible enemies** also watches enemies with active nameplates.
- Optional **Only in range** gating uses the casting enemy's unit token and updates during the cast.
- Cooldown-ready gating ignores the global cooldown.
- Three styles: Classic WoW Glow, Modern WoW Glow, and Blizzard Assisted Highlight.
- Adjustable glow color and size (0–150%), a five-second appearance preview, and a draggable minimap button.
- Automatic startup discovery, cache recovery, and a manual action-bar scan.
- A focus macro generator with Create, Refresh, Update, Modified, and Restore states.
- A macro-only catalog of known targetable stuns: Asphyxiate, Mighty Bash, Maim, Fel Eruption, Intimidation, Hammer of Justice, Cheap Shot, Kidney Shot, and Storm Bolt.

## Installation and setup

Extract `InterruptHighlight/` into `_retail_/Interface/AddOns/`. Keep the folder name unchanged, then restart WoW or reload the UI. Open settings with `/ih` or left-click the minimap icon. Right-click the icon to toggle highlighting.

For action bars, place your interrupt or its generated macro on a bar. If a custom bar loads late, use `/ih scan` outside combat. For Cooldown Manager, enable Blizzard's Cooldown Manager, display your interrupt there, and enable **Highlight Cooldown Manager** in Interrupt Highlight.

## Focus macros

Settings list detected interrupts and supported stuns known in your spellbook. These optional character-specific focus macros first cast the ability on a valid hostile Focus target without changing your current target. If no valid Focus exists, the macro temporarily uses Focus to remember your current target, selects an enemy, casts the interrupt or stun, restores your previous target, clears the temporary Focus, and resumes auto-attack.

The addon does not automatically execute macros or place them on an action bar. Explicitly choose **Create macro**, then drag the spell icon onto an action bar. Review the generated body before use; you must press the macro yourself.

**Refresh macro** reapplies the current body and icon to a ready macro in place. **Update macro** updates a recognized generated macro. A manually edited owned macro is marked **Modified** and requires an explicit **Restore generated macro** click to replace its contents. Unrelated macros are not overwritten; macros are not deleted automatically. Macro editing and dragging are unavailable in combat and remain subject to the game's macro slot and length limits.

Stun candidates are for macro generation only. Catalog membership never grants runtime interrupt highlighting, and a stun may not affect a particular enemy.

## Commands

- `/ih` or `/interrupthighlight` — open settings.
- `/ih scan` — run a bounded action-bar scan; combat requests wait until combat ends.
- `/ih on` / `/ih off` — enable or disable highlighting.
- `/ih status` — show current settings and discovery status.
- `/ih test` — preview the selected glow for five seconds; this is an appearance preview, not a readiness indicator.
- `/ih color R G B` — set RGB values from 0 to 1.
- `/ih reset` — restore default settings.

## Performance and compatibility

Global action-button discovery is bounded to 10,000 visited frames and runs on startup or explicit scans, including a preview's discovery fallback. Recovery and action-bar events refresh caches. There is no continuous global frame scanning. While watched casts are active, a throttled 0.20-second update refreshes range and cooldown gates; it stops while idle.

Cooldown Manager discovery uses active viewer item pools. Its cache rebuilds outside combat, defers combat requests, skips secret or inaccessible spell IDs, and clears when Blizzard's viewer is disabled. Cast interruptibility, cooldown readiness, and spell range use renderer alpha gates for restricted values. Unsupported or unavailable readiness/range data hides the glow.

Retail 12.1.0 (Interface 120100). Standalone, with no bundled addon libraries or EllesmereUI dependency. Blizzard UI components are provided by the game. Third-party action bars are discovered through standard action-slot metadata; unusual or late-created buttons may require a manual scan. All-visible mode depends on active nameplates and does not detect every enemy in the area. The addon highlights opportunities; it does not choose or interrupt a target automatically.

The supplied icon is used by the addon listing and minimap button. Blizzard texture paths and atlas names refer to resources already in the game client.

## License

MIT for the project's own code. See `LICENSE`.
