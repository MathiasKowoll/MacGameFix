# Screenshots

MacGameFix 1.5.5 (Wine modules catalog 1792547610), dark mode, at 2x. Each file name is the tab, then the
state or sheet; pages link to them by name, so a name stays when its image is retaken.

| File | What it shows |
|---|---|
| `games-all.png` | Games, the All filter: each supported game, what its fix requires, its state, Keep, and where it goes |
| `games-all-fixes.png` | Games, All fixes: adds the catalog's games that are not on this Mac |
| `games-not-fixed.png` | Games, Not fixed |
| `games-selected.png` | Games with a row selected: Install Selected and Remove Selected |
| `wine-modules.png` | Wine Modules: a switch per CrossOver app and NotProton runner, and the modules' updates |
| `wine-modules-all-alert.png` | The question All asks before installing into every CrossOver |
| `wine-modules-crossover-alert.png` | "Change CrossOver itself?", asked before the modules go into a CrossOver app |
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
