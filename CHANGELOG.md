# Changelog

## 1.6.0
Everything new since the GitHub **1.5.3** release (2026-11-16).

### Added
- **Instance run timer** — `INSTANCE TIME` tracks each dungeon/raid entry separately from session time, with soft-reset / new-instance detection (`resetInstanceTimerOnEnter`)
- **Max-level reputation fallback** — at cap, auto-picks the watched faction or the highest non-Exalted reputation (Friendship / Renown / Paragon aware)
- **Standing badge + faction picker** — click the standing badge for AUTO (highest non-Exalted) or a manual faction; scrollable list with mousewheel on rows
- **Career pace / Overall TTL** — per-character career XP stats (`ForeverBarTrackerCharDB`) blend into a long-term time-to-level estimate
- **Card scale** slider and richer auto-track options (ignore Exalted, only switch out of combat)
- Dedicated **`XiusXPRepTracker_Forever.toc`** (Interface `16001`) plus modern interfaces `120100` / `120105` / `120107`
- Addon icon texture and Xius-styled TOC title

### Fixed / Hardened
- Max-level auto-rep no longer sticks on an Exalted watched faction when `SetWatchedFaction` is blocked (combat / API) — displays the scanned best faction directly
- Secret `IsInInstance` results no longer wipe a live instance timer on `/reload`
- Collapsed card ↔ expanded drawer seam stays gap-free when card height changes
- Faction / standing / GUID / unit reads use Forever secret-value guards throughout
- Strict **XiusCore** dependency (no deprecated `XiusUI` fallback)

### Changed
- Settings page regrouped (Card, Lock & Expansion, Separate Stats Box, Bars & Colors, Auto Faction Tracking, Instance Run Timer, Session Stats)
- Saved-variables schema bumped to **dbVersion 14**

## 1.5.3
- Requires Xius Core. If Xius Core is not loaded, the addon stays quiet instead of erroring
- Unlock Frames in Xius Core highlights the XP card and stats box so they can be dragged. Locking saves the position and hides the handle
- Faster loot, junk selling, repair, Train All, and max-rank bars stay in Xius Core Quality of Life, so this addon no longer runs a second copy
- The XP card now follows Enable, bar style, card height, bar colors, and auto-track reputation from the Xius Core settings page
- The separate stats box moves beside the settings window instead of sitting underneath it
- The one-second stats tick no longer allocates a timer, and height animation no longer rebuilds the stats grid

## 1.5.2
- Fixed EditMode, `PlayerFrame`, `BuffFrame`, and `DamageMeter` taint by suppressing default Blizzard status bars via `SetAlpha(0)` / `EnableMouse(false)` instead of calling `Hide()` or writing custom keys onto Blizzard frames
- Replaced protected `OpenSettingsPanel` / `Settings.OpenToCategory` calls with a movable standalone Settings dialog (while preserving Blizzard AddOns canvas integration)
- Fixed Kills to Level (`KTL`) in WoW Forever & Modern WoW when combat XP messages contain secret enemy names (`issecretvalue`), and excluded quest XP from `KTL`
- Fixed collapsed XP/rep card ignoring clicks, right-clicks, and Shift-dragging on the left side when stats buttons were hidden underneath
- Fixed level-up session XP calculation under all `PLAYER_XP_UPDATE` / `PLAYER_LEVEL_UP` event orderings
- Fixed `Train All` stopping after the first pass when server latency exceeds 50ms before subsequent ranks unlock
- Fixed `MaxRank` spell variant handling (shapeshift/polymorph subtexts) and added single-pass spellbook lookup with full passive spell detection
- Suppressed `/played` chat output cleanly by temporarily unregistering `TIME_PLAYED_MSG` on chat frames instead of hooking `ChatFrameUtil`
- Batched vendor junk selling (12 items per pass) so large sales never hit server item-lock errors, and delayed auto-repair until junk sale gold lands
- Eliminated per-slot and per-tick table allocations across `Core.lua`, `LootVendor.lua`, and `MaxRank.lua`

## 1.5.1
- Combat updates keep running when the client hides a number from addons
- Faster loot follows the checkbox, and Shift still opens the loot window
- Reputation, paragon, and renown reads no longer stop the tracker if an API call fails
- Max-rank skips passive spells and only counts a bar change that actually sticks
- Action bar, loot, repair, and trainer reads skip values the client will not let addons compare

## 1.5.0
- Loads on modern and Forever only
- Train All buys each skill once, from the bottom of the list, including ranks that unlock after a purchase
- Action bars scan every slot and replace a lower spell rank with the highest rank you know
- Dragging the card or stats box stops when the mouse button is released
- Loot, repair, and gold checks ignore values the client will not let addons read

## 1.3.4
- Fixed separate stats box breaking after `/reload` (stats no longer pile onto the XP bar while the box stays empty)
- Separate box stays correctly attached across login and world loading

## 1.3.3
- Removed the awkward **Opt** header button
- Settings now uses a damage-meter style gear icon next to Reset Session (and on the separate box)
- Softened chrome to a more transparent meter-style panel
- Clearer move hint: **Shift + Left-drag to move**
- Resize grip made smaller and less noticeable

## 1.3.2
- Separate stats box is much smaller by default (~340px wide, compact 3-column layout)
- Added Settings control and move instructions on the separate box
- Saved panel size resets to the new compact default

## 1.3.1
- Added Settings access from the HUD (button + right-click the bar)

## 1.3.0
- Optional **separate stats box** — keep the XP/rep bar collapsed and show all metrics in a movable panel (`/xt panel` or options)
- Default remains hover-to-expand on the XP/rep card
- Added **Quests to Level** estimate (average of the last 5 quest turn-in XP rewards)
- Session rep and Exalted / max timers wired into the stats grid
- Independent lock and position for the separate box

## 1.2.0
- Previous public release baseline
