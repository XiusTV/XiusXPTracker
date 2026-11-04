# Changelog

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
