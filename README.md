# CompactRaidFrame for WotLK 3.3.5a

Compact Raid Frames 1.15 for World of Warcraft 3.3.5a, with fixes and additions. It brings Blizzard's later compact raid and party frames to the stock 3.3.5a client (no ClassicAPI needed): resizable frames with health, power, buffs and debuffs, raid profiles that switch with the group size, and a raid manager in a side bar at the left edge of the screen.

## Installing

1. Download the repository (**Code → Download ZIP**) and extract it.
2. Copy the `CompactRaidFrame` folder into `World of Warcraft\Interface\AddOns\`, replacing any older copy. The folder must be named `CompactRaidFrame`.
3. Restart the game if it's running. A full restart is needed when an update adds files, because `/reload` won't load new ones.

The settings are under **Interface → AddOns → Raid Profiles**, and in the raid manager's side bar.

## Changes from 1.15

- The Raid Profiles options panel fits the 3.3.5a options window, with General, Layout, Display and Auto-Activate tabs.
- **Groups** layouts: Combine or Separate, Vertical or Horizontal. Sort By also works inside separate groups, and **Keep Me at the Top** keeps your own frame first whatever the order.
- **Raid Size Preview** fills the frames with 10, 25 or 40 placeholders, so you can size and place them while solo.
- The health text is centred in the health bar with the buffs and debuffs in a strip under it. **Display Power Bar Text** shows power remaining or as a percentage on a taller power bar.
- **Display Incoming Heals** and **Display Only Healer Power Bars**.
- **Hide player frame when raid frames are shown**. Your totems (or a Death Knight's runes) then show as small boxes right under your own raid frame while they're in use, and the frames below make room for them.
- Pets sit under their own group in every layout, group frames are only as long as the players they show, and there's no "Party" title when you're solo.
- Raid manager: Reset Position, the Groups and preview dropdowns and frame size sliders in the side bar. Its tab stays hidden until you mouse over it, and the frames keep clear of the side menu.
- New profiles start at 50% height and width, with no border and Auto-Activate on for every group size.
- Fixes, among them: "Always show" and the raid-style party frames setting are saved, unsaved changes are tracked after switching profiles, Sort By Role picks the right members, option changes in combat wait for it to end instead of causing "Interface action failed", and heal prediction counts healing debuffs and buffs.

`CompactRaidFrame/CHANGELOG.md` has the details of every version.

The first commit is the 1.15 build these changes started from, as uploaded. Each later commit is one version, so the history shows every change after that.

## Testing

`tests/` holds the harness these changes were tested with: a stand-in for the 3.3.5a client's UI that loads the addon and drives it through groups, raids, combat, totems and runes, the options panel and saved settings. Run `tests/run-all.sh` (it needs `texlua` from TeX Live, and Python 3). It isn't part of the addon: only the `CompactRaidFrame` folder goes into your AddOns.

## Credits

Compact Raid Frames is by Blizzard and Tsoukie; this stock 3.3.5a backport is by Jedborg. It includes LibStub, CallbackHandler, AceComm, AceEvent, AceSerializer, AceTimer, LibHealComm-4.0, LibGroupTalents-1.0, LibTalentQuery-1.0, LibResComm-1.0 and AbsorbsMonitor-1.0.
