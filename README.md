# Xius XP/Rep Tracker

A compact HUD card for **modern World of Warcraft** and **World of Warcraft Forever**. It replaces the default XP and reputation bars and adds faster loot, vendor helpers, Train All, and max-rank action bars.

**Folder name:** `XiusXPRepTracker`  
**Interfaces:** `120105` (modern) · `16001` (Forever)  
**Commands:** `/xt` · `/xiusxp` · `/xxp` · `/xrep` · `/xxr`  
**Version:** `1.5.2`

Loads on modern WoW and Forever. It does not load on Classic.

---

## What it does

Hides the stock XP / reputation tracking bars and shows a dark meter-style **HUD card**.

**Collapsed** shows level, XP (or watched reputation), percent, and thin progress bars.

**Stats** can appear in two ways:

1. **On the XP/rep card (default)** — hover or click to expand
2. **Separate stats box** — always-visible compact panel; the XP/rep card stays collapsed

Tracked metrics include session XP and time, time played this level, total time played, rested, time to level, XP per hour, kills to level, quests to level, gold, and reputation rates.

---

## Features

- Live XP bar with rested overlay
- Watched faction reputation (Friendship, Renown, and Paragon when those APIs exist)
- Session gold and gold per hour
- Kills to level and quests to level estimates
- Time played this level and total time played
- Optional separate movable stats box (`/xt panel`)
- Gear icon or right-click to open settings
- Shift + Left-drag to move when unlocked
- Faster loot: corpses loot immediately; hold Shift to open the loot window
- Auto-sell grey junk and auto-repair at vendors
- Train All button on class and profession trainers
- Action bars upgrade to the highest spell rank you know (login, level-up, and after training)
- Account-wide saved position and options

---

## Install

1. Download a release zip (or let CurseForge install it).
2. Put the **`XiusXPRepTracker`** folder in `Interface\AddOns`.
3. Enable the addon and `/reload`.

---

## Slash commands

| Command | Effect |
|---|---|
| `/xt` · `/xiusxp` · `/xxp` · `/xrep` · `/xxr` | Open settings |
| `/xt config` | Open settings |
| `/xt panel` | Toggle the separate stats box |
| `/xt lock` · `/xt unlock` | Lock / unlock the card and stats box |
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
