# Changelog

## 1.0.1

WoW Retail 12.1.5 compatibility update.

- Add Interface 120105 while retaining 120100 for Retail 12.1.0.
- Update addon version metadata to 1.0.1.
- No new features or changes to appearance, options, focus macros, or runtime logic.
- User reports 1.0.0 works on 12.1.5 without Lua errors; this update addresses the out-of-date declaration.

## 1.0.0

First public release.

- True interrupt highlighting on action bars and Blizzard Cooldown Manager.
- Target-only and all-visible enemy modes with optional range gating and live updates.
- Cooldown-ready gating that ignores the global cooldown.
- Classic WoW Glow, Modern WoW Glow, and Blizzard Assisted Highlight with color and size controls.
- Guaranteed startup discovery, cache recovery, and manual scanning.
- Focus macro generation with safe ownership, in-place refresh/update, and explicit restoration of modified macros.
- Spellbook-based targetable stun candidates for macro generation only.
- Secret Values-safe runtime handling and combat-deferred Cooldown Manager cache updates.
- Bounded scans and throttled cast-active updates without continuous global frame enumeration.
