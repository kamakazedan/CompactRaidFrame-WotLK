# Compact Raid Frames (3.3.5a) - changelog

## 1.21

- Separate Groups: the "Party" title is only shown when you are in a party.
  Solo (raid frames kept on screen by Always show), your frame moves up into
  its place. If you join a party in combat, the title appears when combat ends.

## 1.20

- The raid frames no longer end up under the side menu. Frames placed within
  reach of the open menu are anchored to its edge, so opening it slides them
  over (in combat too), and frames dropped onto the menu or its tab land right
  beside it. Frames placed further right, or below the menu, stay where they
  are.
- Side bar: **Frame Height** and **Frame Width** sliders with the percentage,
  between Groups and the preview. Like Groups, they apply and save straight
  away (in combat the frames resize when combat ends).
- The Groups dropdowns show a short name when closed, e.g. "Separate
  (Horizontal)": the full name was cut off in the side bar. Their lists still
  show the full names.

## 1.19

### New options
- Display tab: **Display Incoming Heals** (incoming heals and absorb shields on
  the health bars; on, as before, for new and existing profiles) and **Display
  Only Healer Power Bars** (under Display Power Bars). Healers are recognised
  from their Dungeon Finder role or, in other groups, from their talents, which
  are read a few seconds after someone joins.
- General tab: **Hide player frame when raid frames are shown** (on by
  default). Hides Blizzard's player frame while the raid frames are on screen,
  including when you join or leave a group in combat. It stays visible in
  vehicles, and totem timers and Death Knight runes stay on screen. The pet
  frame is part of the player frame and hides with it (tick Display Pets to see
  your pet in the raid frames).

### Layout
- New **Layout** tab: Groups, Sort By, Display Border, frame height / width,
  Raid Size Preview and Reset Position (moved here from General and Display).
- **Groups** replaces Keep Groups Together / Horizontal Groups, as in the
  newer Edit Mode: Combine Groups (Vertical), Combine Groups (Horizontal),
  Separate Groups (Vertical) and Separate Groups (Horizontal). Existing
  profiles keep their setting. Combine Groups (Horizontal) is new (rows of 5),
  and Separate Groups (Vertical) now places the groups side by side instead of
  stacking them in one tall column.
- Raid manager side bar: **Groups** and **Raid Size Preview** dropdowns under
  the profile dropdown. Changes made there are saved straight away.
- **Raid Size Preview**: fills the raid frames with 10, 25 or 40 placeholder
  frames (all showing you) in the current layout, so the frames can be sized
  and placed while solo. It shows the raid frames even when they would
  otherwise be hidden, ends when combat starts and can't be started in combat.

### Fixes
- Blizzard's party frames now come back straight away after switching from
  raid-style party frames to them (they stayed hidden until the next change
  in the party).

## 1.18

- "Always show (even when solo)" is now off by default: when you are not in a
  group, the raid frames and the raid manager stay hidden unless you tick it
  (General tab). If you have already ticked or unticked it yourself, your
  choice is kept.

## 1.17

- Raid manager: a **Reset Position** button under Lock / Hide. It does the same
  as Reset Position on the options' General tab (and likewise says "You can't
  do that while in combat" in combat).
- Raid manager tab: while the manager is collapsed, the tab at the left edge of
  the screen stays hidden until you move the mouse over it. It fades in under
  the mouse and fades out half a second after the mouse leaves; it also works
  in combat. Only the tab fades, never the raid frames. On by default; turn it
  off with "Show raid manager tab only on mouseover" on the General tab (saved
  account-wide).
- Display tab: Frame Height and Frame Width show a percentage under the slider
  (0% = smallest size, 100% = largest) that follows the slider as you drag.

## 1.16

### Options panel (Interface > AddOns > Raid Profiles)
- Rebuilt to fit the 3.3.5a options window (about 413 x 428). The old Blizzard
  layout was sized for a larger window, so the Auto-Activate column, the health
  text dropdown and the size sliders were drawn outside it.
- Profile dropdown, Save and Delete now sit on one row, with three tabs below:
  - **General**: Use Raid-Style Party Frames, Always show (even when solo),
    Keep Groups Together / Horizontal Groups / Sort By, Display Pets,
    Display Main Tank and Assist, Reset Position.
  - **Display**: power bars, aggro highlight, class colours, border, debuffs,
    health text, frame height / width.
  - **Auto-Activate**: group sizes, PvP / PvE, and the "will never
    auto-activate" warning.
- "Always show (even when solo)" moved here from the raid manager side panel.

### Bug fixes
- "Always show (even when solo)" was never saved (it lived in a variable that
  was not a SavedVariable), so it switched itself back on at every login. It is
  now stored account-wide in CompactRaidFrameAccountDB.
- Turning "Use Raid-Style Party Frames" off did not survive a /reload (the
  "off" value was stored as nothing, which the loader treats as "default on").
- After switching profiles, edits to the newly selected profile were not
  detected as unsaved: Save stayed greyed out, Cancel did not revert them and
  no "unsaved changes" prompt appeared.
- Sort By "Role" looked up the wrong raid member's Main Tank / Main Assist flag
  (UnitInRaid is 0-based on 3.3.5a).
- Keep Groups Together: the container height was still snapped to frame rows
  (the setting was compared with "1" but is stored as true/false).
- Dragging the container resize handle re-laid out every frame on every screen
  refresh after the first half second (timer never reset).
- Changing Raid Profiles options, the raid-style setting or using Reset
  Position in combat touched protected frames ("Interface action failed
  because of an AddOn"). Option changes are now saved immediately and applied
  when combat ends; Reset Position says "You can't do that while in combat".
  The raid manager's buttons now use InCombatLockdown() (the check the secure
  code itself uses) instead of the player's combat flag.
- After a roster change in combat only part of the manager update was replayed
  (the Raid/Party Members label and the container lock state stayed stale), and
  the alive/total counts froze until combat ended.
- Heal prediction ignored healing debuffs and buffs (Mortal Strike, Wound
  Poison, ...) and every heal anywhere in the raid refreshed every frame; now
  only the frames of the healed units are refreshed.
- Pressing Enter in the "New Profile" box could create a profile even when
  Create was disabled (empty or duplicate name).
- Moving the frame-size sliders programmatically (every panel refresh) wrote
  the value back and re-applied the whole profile.
- Auto-activation activated every matching profile in turn (one full re-layout
  each); it now activates the same final profile once.
- "Make Everyone Assistant" showed a stale state until the leader changed.
- Disabled-button checks now work on every 3.3.5a build (IsEnabled returns
  1/0 or 1/nil depending on the client).

### Clean-up / compatibility
- Locale files no longer overwrite the client's own global strings (doing so
  taints them for the secure UI); they only fill in strings the client lacks.
- Uses the client's built-in UI sounds instead of bundled copies, and no longer
  modifies the global SOUNDKIT table other addons may use.
- Shared templates renamed with a CRF_ prefix so they cannot replace
  ClassicAPI's templates of the same name (or be replaced by them).
- C_Timer shim fills in only missing functions if another addon created a
  partial C_Timer.
- Roster events (PARTY_MEMBERS_CHANGED + RAID_ROSTER_UPDATE fire together in a
  raid) are coalesced into one refresh per frame.
- Fixed an invalid draw layer name (ATWORK) on the raid manager border and a
  wrong-case include path in Libs\Load.xml.
- Removed unused files (bundled sounds, unused textures, an unused cast-bar
  template).
