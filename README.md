# Xius XP/Rep Tracker

A compact HUD card for **World of Warcraft Forever** that replaces the default XP and reputation bars with a movable panel: level, XP, rested, watched faction, session rates, gold, time-to-level, kills-to-level, and quests-to-level.

**Folder name:** `XiusXPRepTracker`  
**Interface:** `16001`  
**Commands:** `/xt` · `/xiusxp`  
**Version:** `1.3.4`

---

## What it does

Hides the stock XP / reputation tracking bars and shows a dark meter-style **HUD card**.

**Collapsed** shows level, XP (or watched reputation), percent, and thin progress bars.

**Stats** can appear in two ways:

1. **On the XP/rep card (default)** — hover or click to expand
2. **Separate stats box** — always-visible compact panel; the XP/rep card stays collapsed

Tracked metrics include session XP/time, rested, time to level, XP/hour, kills to level, **quests to level**, gold, and reputation rates.

---

## Features

- Live XP bar with rested overlay
- Watched faction reputation (Friendship / Renown / Paragon when available)
- Session gold and gold per hour
- Kills to level and quests to level estimates
- Optional separate movable stats box (`/xt panel`)
- Gear icon or right-click to open settings
- Shift + Left-drag to move when unlocked
- Account-wide saved position and options

---

## Install

1. Download a release zip (or clone this repository).
2. Put the **`XiusXPRepTracker`** folder in `Interface\AddOns`.
3. Enable the addon and `/reload`.

---

## Slash commands

| Command | Effect |
|---|---|
| `/xt` · `/xiusxp` | Help |
| `/xt config` | Options |
| `/xt panel` | Toggle separate stats box |
| `/xt lock` · `/xt unlock` | Lock / unlock |
| `/xt reset` | Reset session baselines |

---

## More From Xius

**Xius Marks Bar**: A compact raid marking bar. Click the flag for world markers or the star for target markers, with 5 / 10 / 20 pull timers, ready check, and role check built in.  
[GitHub](https://github.com/XiusTV/XiusMarksBar) · [CurseForge](https://www.curseforge.com/wow/addons/xius-marks-bar)

**Xius Threat Meter**: A clean, lightweight threat meter. Shows who is on the enemy's threat table, how much threat each player and pet has, and warns you before you pull aggro.  
[GitHub](https://github.com/XiusTV/XiusThreatMeter) · [CurseForge](https://www.curseforge.com/wow/addons/xius-threat-meter)

**Xius Max Graphics**: Pick-and-choose graphics upgrades for Forever and retail. Ultimate, Balance, and Defaults presets push view distance, grass, shadows, water, and image clarity past the normal graphics menu, with optional loot and gathering sparkles.  
[GitHub](https://github.com/XiusTV/XiusMaxGFX)

**Xius Kill Streak**: A ten-tier kill streak announcer for mobs and enemy players. Each new tier shows a banner and plays a call, with a small counter for the current streak and the time left to keep it going.  
[GitHub](https://github.com/XiusTV/XiusKillStreak)

All Xius addons share the same clean, dark gold style for a unified UI.

## License

Personal / public addon. Credit **Xius** if you fork or redistribute.
