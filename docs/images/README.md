# Screenshots

MacGameFix 1.6.3 (the build of 2026-11-14 at f74d86c, catalogs 1794704089), dark mode, at 2x. Each file name
is the tab, then the state or sheet; pages link to them by name, so a name stays when its image is retaken.

| File | What it shows |
|---|---|
| `games-all.png` | Games, the All filter: each supported game, what its fix requires, its state, Keep, and where it goes |
| `games-all-fixes.png` | Games, All fixes: adds the catalog's games that are not on this Mac |
| `games-selected.png` | Games with a row selected: Install Selected and Remove Selected |
| `games-instructions.png` | A game's special instructions (Forza Horizon 6): the line to play with, its Copy, and what each variable does |
| `games-instructions-heat.png` | The same sheet, scrolled: Frame rate, Heat, and the optional variables |
| `improvements.png` | Improvements: DualSense controllers and Copy protection under Rosetta, a switch per CrossOver app and NotProton runner |
| `improvements-rosetta.png` | The same tab, scrolled: Copy protection under Rosetta with its All and None, and Game Mode |
| `improvements-fans.png` | The same tab, scrolled to the end: Game Mode, Fans with the two variables to copy, and the modules' updates |
| `game-feel.png` | Game Feel: every game's options, and each game's own |
| `game-feel-every-game.png` | Every Game's Settings: the options and the haptics' strength |
| `game-feel-every-game-triggers.png` | The same sheet, scrolled: the tries and the trigger effects |
| `game-feel-effects.png` | What Each Effect Does |
| `game-feel-game.png` | One game's sheet (F1 23, with suggested settings) |
| `game-feel-game-about.png` | The same sheet, scrolled: About this game, Diagnose, Share These Settings, Make a Report |
| `report.png` | Report: every Steam game, where it runs, and whether MacGameFix has a fix |
| `report-sheet.png` | A game's report sheet: what MacGameFix found in the game's folder |
| `report-sheet-steps.png` | The same sheet, scrolled: the steps before a report, and Save the Report and Open an Issue |
| `settings.png` | Settings, as on a first launch: the agent is off until it is turned on |

The two of a game's instructions were taken later the same day, from the app as published at c3f1df6 (catalog
1794705165), after #77 put the whole line first.

Not pictured: the Not fixed filter, and the two questions asked before an improvement goes into every CrossOver
or into a CrossOver app. In `improvements-fans.png` the helper reads as older than the app's, which is how that
build told every new build apart; since #78 it compares versions, and that line shows only for a real update.

## How they are taken

From a copy of the app with its own bundle identifier, started with `MACGAMEFIX_HOME` set to a demo home,
so no screen shows anyone's real library:

- The demo home's Steam lists one library: APFS clones (`cp -c`) of eight chosen games and their prefixes,
  on the same volume as the originals, which the clones leave untouched.
- It has no `Steam/appcache`, so the app shows its own tile in place of each game's cover art.
- Its NotProton runners hold CrossOver's file names only, with the modules installed by
  `MacGameFix --engine-install`.
- Its `automatic.json` keeps the modules on in those runners and in CrossOver Preview, as a user who turned
  them on would have it.
- The agent stays off: turning it on in a copy would replace the real agent, whose label is shared.

Each window is sized to its content and taken alone, without its shadow, with `screencapture -x -o -l <window id>`.
A sheet or popover is taken by its own window id, which captures it over the window. An alert stays
unanswered until it is taken, then is cancelled.

`../ui-inventory.md` has every control with its exact text, read from the code, including what these images
leave out: the pop-up menus' choices, the menu bar agent, and the App Management notice.
