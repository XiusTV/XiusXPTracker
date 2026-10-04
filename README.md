# Xius XP/Rep Tracker

A compact HUD card for **World of Warcraft Forever** that replaces the default XP and reputation bars with a single movable panel: level, XP, rested, watched faction, session rates, gold, and time-to-level.

**Folder name:** `XiusXPRepTracker`  
**Interface:** `16001` (World of Warcraft Forever)  
**Commands:** `/xt` · `/xiusxp`

---

## About

> Sleek XP & reputation HUD card for World of Warcraft Forever. Replaces the default tracking bar with session stats, gold, time-to-level, and a card that expands up or down.

---

## What it does

Xius XP/Rep Tracker hides the stock XP / reputation tracking bars and puts a dark gold-bordered **HUD card** at the bottom of the screen (the same place as the default XP bar).

**Collapsed (~48px)** shows only the header:

- Gold double-ring **level badge**
- Label: `Experience current / max` (or the watched faction name)
- Gold **percentage**
- Thin purple XP bar with amber **rested** fill past current XP
- Optional 6px blue **reputation** bar under XP when a faction is watched

**Expanded (~165px)** smoothly grows the same frame (no separate popup) and reveals:

| Column | Stats |
|---|---|
| 1 | Session XP, Session Time |
| 2 | Rested XP, Time to Level |
| 3 | XP / Hour, Kills to Level |
| 4 | Gold / Hour, Session Gold |
| 5 | Rep / Hour, Next Rank |

A **Reset Session** button and a small footer hint sit in the expanded area.

---

## Features

### XP & leveling
- Live XP bar with current / max and percent
- Rested XP overlay on the bar and in the stats grid
- Session XP earned
- XP per hour
- Time to next level (from session rate)
- Kills to level (rolling average of the last 5 combat XP gains)

### Reputation
- Tracks the **watched** faction via `C_Reputation.GetWatchedFactionData()`
- Thin reputation bar under XP while leveling; switches to reputation at max level if XP is hidden
- Session reputation, rep / hour, time to next standing
- Friendship / Best Friend, Renown, and Paragon when those APIs exist

### Gold
- Net gold this session (green when up, red when down)
- Gold per hour, using standard coin textures

### HUD behavior
- **One frame** — height animates 48px → 165px instead of a detached drawer
- **Hover** or **click** to expand (configurable)
- **Growth direction:** Auto (by screen position), always up, or always down
- Auto: bottom half of the screen grows **up**; top half grows **down**
- Header stays on the anchored edge so the XP bar does not jump
- Shift-drag to move (when unlocked)
- Drag the right edge to resize (600–1200px, default 620px)
- Position and width saved per account
- Default XP / rep tracking bars are hidden and their events unregistered

---

## Install

1. Download or clone this repository.
2. Copy the **`XiusXPRepTracker`** folder into your World of Warcraft Forever `Interface\AddOns` directory.

   The folder must contain `XiusXPRepTracker.toc`, `Config.lua`, and `Core.lua`.

3. Restart the game (or log to character select).
4. Enable **Xius XP/Rep Tracker** on the AddOns list.
5. `/reload` once in-game.

This addon is built only for **World of Warcraft Forever** (interface `16001`).

---

## Usage

| Action | How |
|---|---|
| Expand stats | Hover the card (default) or left-click (if set to Click) |
| Move | Unlock, then **Shift + Left-drag** |
| Resize | Drag the thin grip on the right edge |
| Reset session | **Reset Session** on the expanded card, or `/xt reset` |
| Options | Escape → Options → AddOns → **Xius XP/Rep Tracker**, or `/xt config` |

Watch a faction in the Reputation window for the rep bar and rank timers.

---

## Slash commands

| Command | Effect |
|---|---|
| `/xt` or `/xiusxp` | Show help |
| `/xt config` · `/xt opt` | Open the options panel |
| `/xt lock` | Toggle frame lock |
| `/xt unlock` | Unlock the card |
| `/xt reset` | Reset session time, XP, gold, and reputation baselines |

---

## Settings

All options default **on**. Saved in `ForeverBarTrackerDB` (account-wide).

**Expansion**
- Hover to expand / Click to expand
- Direction: Auto (screen position) · Always Expand Up · Always Expand Down

**Bars & position**
- Lock card (blocks Shift-drag and resize)
- Show XP bar (hides at max level if reputation is shown)
- Show reputation bar
- Reset Session / Reset Position buttons

**Card stats (toggle each row)**
- Session duration, XP / Hour, Time to Level, Kills to Level
- Gold session, Gold / Hour, Rested XP
- Reputation session, Rep / Hour, Time until next rank, Time until Exalted / Best Friend / Max

---

## Compatibility

World of Warcraft Forever only. TOC interface: `16001`.

Uses Forever client APIs (`C_Reputation`, `C_Timer`, `Settings`). Lua 5.1. No external libraries.

---

## Files

```
XiusXPRepTracker/
├── XiusXPRepTracker.toc
├── Config.lua      # defaults, saved variables, options panel, slash commands
├── Core.lua        # HUD card, tracking engine, default bar replacement
└── README.md
```

