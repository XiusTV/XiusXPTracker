# Xius XP/Rep Tracker

A HUD card for **modern World of Warcraft** and **World of Warcraft Forever**. It replaces the default XP and reputation bars with level, XP, rested XP, watched faction, session rates, gold, and time-to-level.

Settings and Unlock Frames live in **[Xius Core](https://www.curseforge.com/wow/addons/xius-core)**. Faster loot, selling gray items, repair, Train All, and max-rank action bars live there too, under Quality of Life.

**Folder name:** `XiusXPRepTracker`  
**Interfaces:** `120105` (modern) · `16001` (Forever)  
**Commands:** `/xt` · `/xiusxp` · `/xxp` · `/xrep` · `/xxr`  
**Version:** `1.5.3`

Loads on modern WoW and Forever. It does not load on Classic. Xius Core has to be installed and enabled.

## Features

### HUD card

- Replaces the stock XP and reputation tracking bars.
- Shows level, the XP or watched-faction bar, percent, and a rested overlay.
- Watched reputation includes Friendship, Renown, and Paragon when the client provides them.
- Bar style, height, and colors come from the Xius Core settings page.
- The card can be turned off. The normal Blizzard bars come back.

### Stats

Stats can sit in two places:

- **On the card (default).** Hover or click to expand.
- **Separate stats box.** A compact panel that stays visible. The card stays collapsed.

Tracked metrics include session XP and time, time played this level, total time played, rested XP, time to level, XP per hour, kills to level, quests to level, gold, and reputation rates. Each metric can be hidden.

### Moving

- **Unlock Frames** in `/xius`, or right-click the Xius Core minimap button, shows a drag handle on the card and the stats box.
- Locking saves the position and hides the handle.
- Shift-drag still moves the card while its own lock is off.

## Controls & Slash Commands

| Command / Input | Action |
| --- | --- |
| `/xt` · `/xiusxp` · `/xxp` · `/xrep` · `/xxr` | Open this page in Xius Core |
| `/xt config` | Open this page in Xius Core |
| `/xt panel` | Toggle the separate stats box |
| `/xt lock` | Lock the card, or the stats box when that box is showing |
| `/xt unlock` | Unlock the card and the stats box |
| `/xt reset` | Reset session baselines |
| `/xius xp` | Open this page in Xius Core |
| Unlock Frames, or right-click the minimap button | Drag the card and the stats box |

## Configuration

Open the page with `/xt` or `/xius xp`.

- **Card:** Enable, bar style, height, auto-track reputation, width, and lock.
- **Stats:** On the card or in a separate box, expand on hover or click, and which metrics show.
- **Loot, vendors, and training:** On the Quality of Life page in Xius Core.

Position and options are saved for the account.

## More From Xius

### Xius Core - [GitHub](https://github.com/XiusTV/XiusCore) · [CurseForge](https://www.curseforge.com/wow/addons/xius-core)

The settings and quality-of-life hub for the Xius addons. One window holds Quality of Life, General, and every other Xius addon you have installed.

### Xius Threat Meter - [GitHub](https://github.com/XiusTV/XiusThreatMeter) · [CurseForge](https://www.curseforge.com/wow/addons/xius-threat-meter)

A threat meter. Shows who is on the enemy's threat table, how much threat each player and pet has, and warns you before you pull aggro.

### Xius Marks Bar - [GitHub](https://github.com/XiusTV/XiusMarksBar) · [CurseForge](https://www.curseforge.com/wow/addons/xius-marks-bar)

A raid marking bar. Click the flag for world markers or the star for target markers. Includes 5 / 10 / 20 pull timers, ready check, and role check.

### Xius Max Graphics - [GitHub](https://github.com/XiusTV/XiusMaxGFX) · [CurseForge](https://www.curseforge.com/wow/addons/xius-max-graphics)

Graphics presets for Forever and retail. Ultimate, Balance, and Defaults raise view distance, grass, shadows, water, and image clarity, with optional loot and gathering sparkles.

### Xius Kill Streak - [GitHub](https://github.com/XiusTV/XiusKillStreak) · [CurseForge](https://www.curseforge.com/wow/addons/xius-kill-streak)

A ten-tier kill streak announcer for mobs and enemy players. Each tier shows a banner, plays a call, and keeps a counter for the streak and the time left.

Their settings open from Xius Core.

## License

Credit **Xius** if you fork or redistribute.

## Development & AI Disclosure

This addon was built and refactored with the assistance of AI development tools (Cursor / LLMs) for code generation, UI layout structure, and the settings window, with manual architecture, in-game verification, and maintenance by Xius.
