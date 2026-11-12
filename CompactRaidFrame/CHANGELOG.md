# Compact Raid Frames (3.3.5a) - changelog

## 1.26

- Separate Groups (Horizontal) with Display Pets: each group's pets now go in
  a row right under that group, before the next group (they were stacked in
  one column at the left under the last group). If a group and its pets don't
  fit at the bottom of the frames, they move to the next column together.
- Where pets go in each layout (Display Pets on):
  - Combine (Vertical): after the last player, down the column.
  - Combine (Horizontal): after the last player, five to a row.
  - Separate (Vertical): a column under each group (1.25).
  - Separate (Horizontal): a row under each group.

## 1.25

- Separate Groups (Vertical) with Display Pets: pets now sit under the players
  instead of off to the right.
  - In a party: a column of pets under the party (your pet first, then the
    party members' pets in order).
  - In a raid: each group's pets in a column under that group (your pet first
    in your group with Keep Me at the Top). When the groups take more than one
    line, each line has its pets right under it.
  - Lined up with the members, also with Display Border on.
- Other layouts are unchanged: in Combine Groups (Vertical) the pets already
  carry on under the last player; in the horizontal layouts they follow the
  groups as before.

## 1.24

- New Layout tab option **Keep Me at the Top** (next to Display Border, under
  Sort By), on by default and switched on for existing profiles. Your own
  frame comes first whatever the sort order:
  - Combine Groups, in a party or a raid: first with Role, Group or
    Alphabetical sorting (before, only Group sorting in a party did this).
  - Separate Groups in a raid: first in your own group (the groups stay in
    order 1-8). In a party your frame was already first.
  - Changed in combat, the new order applies when combat ends.

## 1.23

- The health text is centred in the frame's health bar ("the box"), with the
  name above it and buffs / debuffs in a strip below it, so they no longer
  cover each other.
  - The text's size follows the frame but is at most a third of the box's
    height, so at 50% / 50% with power bar text it is a little smaller than
    before.
  - Buffs and debuffs fill the strip under the text, up to their original
    size. A frame shows at most 3 buffs and 3 debuffs (plus up to 3 small
    dispel markers in the top right), so they always fit side by side.
  - The ready check and status icons (phase, resurrection) sit on the text.
  - With Display Health Text set to None, the auras keep their original size.
  - Frames too short for three rows (e.g. 36px tall) keep the old arrangement.
  - When a role change shows or hides a power bar in combat, everything
    re-fits straight away.

## 1.22

### New option
- Display tab: **Display Power Bar Text** (None / Power Remaining / Power
  Percentage), under Display Health Text. While it shows text the power bar is
  twice as tall (16px instead of 8px). It is greyed out until Display Power Bars
  is ticked, and the text is hidden for dead or offline players. On short
  frames the health text moves up so it stays clear of the taller bar.
  Existing profiles start with None.

### New profile defaults
- Frame Height and Frame Width 50% (66 x 129), Display Border off, and
  Auto-Activate on for 10, 15, 25 and 40 player groups, PvP and PvE.
- These apply to new profiles and to the panel's Defaults button (which
  replaces all profiles with one default profile). Existing profiles keep
  their settings.

### Fixes
- Frame Width could not be set to 50%: the sliders moved in 2px steps (128 =
  49%, 130 = 51%). Both size sliders, on the Layout tab and in the side bar,
  now move in 1px steps, so every width percentage can be picked.
- The power bar's maximum now also updates when a rage, energy or runic power
  maximum changes (only mana did), so the bar and its percentage stay right.

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
