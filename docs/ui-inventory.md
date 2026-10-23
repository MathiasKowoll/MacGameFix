<!-- Working reference for writing the user guide, read at the fix-works-report branch, based on 2a83427 (MacGameFix 1.5.6): the app's source with that branch's own edits. Strings are quoted from the code; file:line refer to app/. The line references of what was here before were carried to this state through each file's diff and spot-checked, and the new ones read at it. Regenerate it when the UI changes; it is not the guide itself. -->

# MacGameFix 1.5.6: everything a user can see and do

Read from all nine Swift files, the README and the GitHub issue forms the app opens, at the fix-works-report branch, based on 2a83427 (version 1.5.6, `build-app.sh:55`).

Files read (line references below use these short names):
- `app/MacGameFix.swift`, `MenuBar.swift`, `PadTester.swift`, `Pad.swift`, `Probe.swift`, `Engine.swift`, `GameMode.swift`, `Core.swift`, `Automation.swift`
- `README.md`
- `.github/ISSUE_TEMPLATE/` (`controller.yml`, `game-report.yml`, `game-feel-settings.yml`, `vibration-works.yml`, `game-fix.yml`, `fix-works.yml`, `works-without-fix.yml`)
- `app/build-app.sh` and `app/pad-presets.json`, and the installers' `MGVF-LOG` lines in `fixes/`

Wherever a quoted string is built from a value, `<…>` stands for that value.

---

## 1. The main window

**The window itself**
- It is a `WindowGroup("MacGameFix")`: default size 1080×760, minimum 720×460 (MacGameFix.swift:2250-2253, 893).
- It starts a game scan when it opens (896).
- When that scan finishes, it looks at the CrossOver installs if it has not yet (348).
- Opening the window removes the dot from the menu bar icon (90-96). If the agent is on, opening it also restarts or re-registers the agent (100-106).
- Closing the last window quits this process (2237). If an install is running, the quit waits for it to finish (2239-2243).

**Tabs, in order** (871-884)

| # | Tab | Shown when | Purpose |
|---|---|---|---|
| 1 | "Games" | always | Install or remove the game fixes, and report one that works, or a game that works without its fix |
| 2 | "Wine Modules" | always | The patched Wine modules that go into CrossOver apps and NotProton runners, and their updates |
| 3 | "Game Feel" | only while `padAvailable` | DualSense options for every game and for each game |
| 4 | "Report" | always | Every Steam game on the Mac, to make a report about one that doesn't work |
| 5 | "Settings" | always | Background agent, Game Mode, game-fix updates, recent agent events, folders searched, the log |

- **When Game Feel appears:** at least one CrossOver row must be "Installed" or "Older modules: install again", and that build's modules must include `unix/winebus.so` (577-582).
  - The CrossOver rows are only filled in after the first game scan. So on a Mac that has the modules, the Game Feel tab shows up a few seconds after launch.

**Status line under the tabs, on every tab** (885-888): a small spinner while busy, then `model.status`. The possible texts:
- Scanning games: "Looking for games…", then "No supported game found in these folders." or "<n> game(s) found." (330, 346)
- Install/Remove with nothing to do: "Nothing selected needs installing." / "Nothing selected is installed." (377)
- Installing or removing fixes:
  - "Installing <game> (<i> of <n>)…" / "Removing <game> (<i> of <n>)…" (386)
  - then "Done: <n> game(s)." or "Done, <f> of <n> need attention." (408)
- Scanning CrossOver: "Looking at CrossOver and the NotProton runners…", then "No CrossOver or NotProton runner found." or "<n> CrossOver install(s) found." (805, 812)
- Installing or removing Wine modules:
  - "Installing the modules into <name>…" / "Removing the modules from <name>…", with " (<i> of <n>)…" when there are several (551-552)
  - then "Done." or "<f> of <n> need attention — see the log in Settings." (568)
  - If App Management blocked some installs, this is appended: " <names> needs App Management: see Wine Modules." ("need" for several) (543-545)
- Updates:
  - "Looking for new fixes…" / "Looking for new Wine modules…" (282, 261)
  - then "New fixes installed: catalog <n>." / "New Wine modules installed: catalog <n>." (Automation.swift:533-534)
  - or "The fixes are up to date (catalog <n>)." / "The Wine modules are up to date (catalog <n>)." (Automation.swift:481)
  - or "Could not update: <error>" (270, 291). The error texts are at Automation.swift:430-434: "the release has no <file>", "catalog.json is not signed with MacGameFix's key", "<file> does not match the signed catalog", "the catalog names a file it may not: <file>", "the new fixes need MacGameFix <v> or later".
- Export: "Exported the controller settings of <n> game(s)." / "Could not export: <error>" (790, 792)
- A fix's report, from It Works… or Works Without the Fix…: "Making <game>'s fix report…" while it is made, cleared as the Save panel opens (752, 759); or, when the installer now gives the game another state than the row showed, "<game>: <state>; <It Works…|Works Without the Fix…> needs <Installed|Not installed>", with no Save panel (760-767).

---

## 2. Each tab

### 2.1 Games (`GamesView`, MacGameFix.swift:901-1067)

**Header** (954-958)
- Title "MacGameFix".
- Subtitle: "Fixes go into each game's own folder, a few also into its prefix or bottle, one into a macOS game's app, and never change CrossOver. Quit a game before changing its fix." (955)
- Tooltip on the subtitle: "The Windows games' fixes work with CrossOver as it ships, CrossOver Preview, and Steam Play tools such as NotProton."

**Button row** (962-971). All buttons are disabled while busy.
- **"Scan"**: looks through the libraries again and asks each game's installer for its state.
- **"Add Folder…"**: opens a folder picker (multiple folders allowed). Its message is "Choose a Steam library, its steamapps/common folder, or a game folder." (309-320). The chosen folders are saved and a scan runs.
- **"Select All"**: selects every row the current filter shows.
- **"Install Selected"**: installs on the selected rows that are not already "Installed", and skips a selected row waiting for a recipe (375). Its keyboard shortcut is Return (968).
  - When a selected row's fix changes a macOS game's app (Cyberpunk 2077), the "Change <game>'s app?" alert asks first (section 3, L; 380, 415-433). Cancel installs nothing, on any row.
- **"Remove Selected"**: runs the installer with `--restore` on the selected rows that are not "Not installed" (375, 390).
  - A row waiting for a recipe can be selected for this alone (Core.swift:336): Cyberpunk 2077's installer then deletes the copies it kept for the game's earlier builds, and the row stays "No recipe for this build yet", which counts as done (397-398).
- After each run the app asks the installer again, and that answer decides the result. The selection is then cleared (394-404).

**Filter row**
- A segmented picker with hidden label "Show", options **"All" / "Fixed" / "Not fixed" / "All fixes"** (907-909, 975-980). It resets to "All" every time the window opens (904).
  - "Fixed" shows Installed, Older build, Half installed and Needs repair.
  - "Not fixed" shows Not installed, Cannot be fixed here, No recipe for this build yet and Cannot be installed here (925).
  - "All fixes" adds the catalog's games that are not on this Mac (933-937).
- A toggle **"Only the marked games to review (<n>)"** (981-984).
  - It only appears when some kept game needs the user: the agent reported "Failed", "Folder not found" or "Cannot be installed here" (MenuBar.swift:31).
  - When on, only those games are listed.
  - It is already on when the window was opened from the menu bar's "<n> to review…" item (`--review`, MacGameFix.swift:56).
  - A game whose folder is gone has no row, so in practice only "Failed" games show here. This is my inference from the code.
- A count on the right: "<n> fix(es), <m> of their games on this Mac" under All fixes, otherwise "<shown> of <total> game(s)" (986-991).

**Empty state** (993-1006)
- One of these lines:
  - "Looking…" while busy
  - "No supported game found yet." when no games were found
  - "No game is fixed yet. Not fixed shows the supported games found." under Fixed
  - "No game here." otherwise
- Below it: "Supported: <every game name>".

**Table columns** (1008-1043). The table allows several rows to be selected. A row that is blocked can never be selected, except one waiting for a recipe (946; Core.swift:336).

| Column | Content | Tooltip |
|---|---|---|
| "Game" | Name in bold, symptom below | The folder path, a blank line, then the game's "why" text (1015) |
| "Requires" | The requirement note, or "—" | The same note |
| "Status" | The status cell below, or "Not on this Mac" for catalog-only rows | — |
| "Keep" | A checkbox | "Keep it applied: put it back after a game update." (1034) |
| "Goes into" | The place cell below, or "—" | See below |

- **Requires** notes are built from these parts (Core.swift:209-232): "runs on DXMT/D3DMetal/DXVK", "needs D3DMetal <v>" or "needs D3DMetal <v> or <v2>", "its videos need <CrossOver>, which ships their codec", "not needed on D3DMetal <v> or later; kept for earlier ones", "needs <CrossOver>; stable CrossOver 26.3 needed MacGameVideoFix's engine, now archived", and for a fix that changes a macOS game's app, first, "macOS app; changes its executable" (Core.swift:211).
- **Keep** checkbox:
  - Checking it saves the game, its folder and its chosen prefixes for the agent (147-158).
  - It is disabled when the row is blocked or the app is busy, except for a row waiting for a recipe: that one can be kept, and the agent installs its fix when a recipe arrives (1033; Core.swift:331). A row already kept can always be unchecked, blocked or not.
  - Checking it on a fix that changes a macOS game's app (Cyberpunk 2077) asks first, with the Keep form of alert L; Cancel leaves it unchecked (147-150).
  - Nothing in the window warns that it does nothing while the agent is off.

**Status cell** (`GameStatusCell`, 1071-1095), top to bottom:
1. The state, in colour (Core.swift:254-276):

   | State | Colour |
   |---|---|
   | "…" | grey |
   | "Installed" | green |
   | "Older build: install to update" | blue |
   | "Not installed" | grey |
   | "Half installed" | orange |
   | "Needs repair" | orange |
   | "Cannot be fixed here" | red |
   | "No recipe for this build yet" | grey (Cyberpunk 2077 on a game build its catalog has no recipe for) |
   | "Cannot be installed here" | red (Cyberpunk 2077: an executable changed outside MacGameFix that no recipe row was made from, or an M1 or M2 Mac) |

2. In orange, the last run's outcome: "Failed — see the log" or "Did not take — see the log" (399-400).
3. In red, why the row is blocked (Core.swift:302-326):
   - "The installer found nothing in this folder for the fix to ride on."
   - "No prefix for this game was found. Run it once with NotProton or CrossOver, then Scan again."
   - "Choose at least one place for its DLLs." (NINJA GAIDEN 3) or "Choose at least one place for its registry keys."
   - "MacGameFix waits for a recipe for the game's build <version> (<build>); a catalog update brings it.", or "… for the game's new build; …" when the installer named no build (Core.swift:306-309). This one is grey, not red (1083), leaves Keep available, and the row can still be selected for Remove. The installer answers this only when its catalog has no row for the game's build.
   - For "Cannot be installed here", and for "Half installed" on a fix that changes a macOS game's app, the installer's own reason, from the "Why:" line of its `--status` (Core.swift:313-318). Cyberpunk 2077's are, with `<build>`, `<chip>` and the Steam sentence filled in: "This executable is not one the recipes for build <build> were made from. In Steam, Properties > Installed Files > Verify integrity of game files should put CD PROJEKT's back, then install here.", "The executable is patched, but not by MacGameFix: no copy of its original is kept. In Steam, … then install here.", "The executable is patched, and the copy MacGameFix kept for this build is not its original. In Steam, … then install here.", and "This Mac has an <chip>. Apple lists MetalFX denoised upscaling for M3 and later, and the game does not ask, so it would offer an option this Mac cannot run." Without a "Why:" line the app says "The installer cannot install the fix here." or "The executable was patched outside MacGameFix; nothing can be installed or removed here."
4. If the agent failed on a kept game: "In the background: <detail, or 'the fix did not take.'>" in orange. When there is a report link, a **"Report on GitHub…"** button follows, which opens the pre-filled issue (1085-1091).

**"Goes into" cell** (`GamePrefixCell`, 1100-1133)
- Fix that changes a macOS game's app (Cyberpunk 2077): "Its app", with the tooltip "Changes the game's executable and signs it again ad hoc; the original is kept in MacGameFix's app-backup folder." (1111-1113).
- Fix that needs no prefix: "Its folder".
  - The code also has an "Its prefix" branch for a game that is in-prefix but needs no prefix. It is probably unreachable, since NG3 needs a prefix. I can't confirm that without games.json.
- Zero or one prefix: plain text with the prefix name or "—".
  - Tooltip: "Registry keys go into <place or 'no prefix found'>." For NG3 it starts "Its DLLs and overrides go into" (Core.swift:186).
- Several prefixes: a **menu** with one checkable item per prefix (1120-1132).
  - Label: "Choose…", the single chosen name, or "<n> places".
  - Tooltip: "<Registry keys go into / Its DLLs and overrides go into>: <names or 'none chosen'>."
  - Checking or unchecking a prefix asks the installer again. If the game is kept, the new set is saved for the agent (164-178).
- Prefix names (Core.swift:243-248): "Steam Play prefix (<appid>)" and "CrossOver bottle “<name>”". Two bottles with the same name get " (<parent>/<root>)" appended (1104-1108).

**Under the table: It Works… and Works Without the Fix…** (1047-1064)
- On the left, in small grey text: "Played a game? Select it to report that its fix works, or that it works without it."
- **"It Works…"**: enabled when exactly one row is selected, its state is "Installed", and the app is not busy (740-742, 1054-1055). The rule is `FixReport.target` (Probe.swift:702-712), which the command-line flags below apply too.
  - Tooltip: "For one selected game whose fix is installed: saves its fix report and opens a new issue on GitHub that says the fix works, for the list of verified games, with the game, the versions and the fix's own log filled in, and where it runs when its folder shows it."
- **"Works Without the Fix…"**: enabled when exactly one row is selected, its state is "Not installed", and the app is not busy (1059-1060). A row under All fixes that is "Not on this Mac" cannot be selected, so it never enables either button.
  - Tooltip: "For one selected game whose fix is not installed: saves its fix report and opens a new issue on GitHub that says the game works without the fix, with the game and the versions filled in. Remove the fix and play the moment it was for first."
- Either button runs the game's installer with `--status` (once per chosen prefix for a fix that needs one), reads the game folder as the Report tab does, then opens the Save panel (section 3, E) and, once the file is saved, the form in the browser (749-771). Cancel in the Save panel opens no form. When that `--status` gives another state than the one the button needs (a game update took the fix away, or the agent put it back, since the row was last read), nothing is saved and no form opens: the row takes the new state, which turns the button off, and the status line says why (760-767).
- They sit under the table rather than in the button row: the comment at 1047-1049 gives the measured widths (seven buttons about 790 pt against the 688 pt the window's least width leaves).
- The table has no context menu, so neither button is offered on a right click.

**The fix report** (`FixReport`, Probe.swift:569-1049)
- It is the Report tab's report for the game (section 3, D) titled "MacGameFix fix report: <game>", with no "What goes wrong" line, and after its first lines "- Report: its fix works, played with the fix installed" or "- Report: it works without its fix, played with the fix removed" (Probe.swift:976-1048). It writes the home folder as ~ and leaves the Mac's name out, as that report does.
- Its "- Runs in:" line, as the Report tab's report's, names the game's own Steam Play prefix, a CrossOver bottle that holds the game folder, and, for a fix that needs a prefix, the ones chosen in Games; any other bottle whose Steam lists the game's library is counted, "another CrossOver bottle whose Steam lists its library, not named here" or "<n> other CrossOver bottles …", since a bottle is often named after another game (`Probe.places`, Probe.swift:477-496).
- "## The fix": the state, as its installer says now; the installer and the catalog's version; the game's build when its installer names one (Cyberpunk 2077's), and Steam's build id from the appmanifest.
- "### What its installer says (--status)": every line `--status` printed, run as the window runs it (`Fixer.statusRun`, Core.swift:637-643); for a fix that needs a prefix, once for each chosen one, under "Into the <prefix>: <state>".
- "### Files that match the catalog": the files in the game folder itself and in its carrier's folder, and for a fix whose DLLs go into the prefix, in each chosen prefix's `windows/system32`, none looked into further, whose SHA-256 is that of a file of the catalog in use: "`<file>` is the catalog's `<name>`". Only a file the size of one of the catalog's is hashed (Probe.swift:728-764). Otherwise "None: no file in the game folder or in <carrier> matches a file of catalog <n>."
- "### Where it runs": "In: <prefixes and bottles>", named and counted as on the "Runs in" line (the chosen ones for a fix that needs one); each CrossOver app (for a game in bottles alone), NotProton runner (in Steam Play prefixes alone), or both, with the D3DMetal builds it carries and where, read from `lib*/apple_gptk*/external/D3DMetal.framework/Resources/Info.plist` (Engine.swift:251-268); "Which of these ran the game is not read" when there are several; "Graphics backend: not read; the fix is made for <backend>", from games.json; "This Mac: <model>, <chip>, macOS <version>" (sysctl's `hw.model` and `machdep.cpu.brand_string`; no serial number).
- "### The fix's own log": for each name in the game's `logs` (games.json, from its installer's `# MGVF-LOG:` line, `build-app.sh:100`), the file in the carrier's folder or the game folder, when it was last written, and its last 200 lines ("its last <n> of <total> lines"). Only the last 256 KB of a log is read; a larger one says "its last <n> lines, read from the end of its <size> bytes". A line over 1000 characters is cut, with " [cut: <n> characters]", and a control character other than the tab is shown as U+FFFD (Probe.swift:788-823). "<path> is there and could not be read (<reason>)." for one that cannot be read ("Permission denied", or "it is not a file" for a folder of that name); "<name>: not in the game's folder. The fix writes it beside its DLL while the game runs." when it is not there, and "The fix writes no log of its own beside its DLL." for a fix that names none. From Works Without the Fix…, a log found adds "Written while the fix was in place: it is not installed now." The names today: `mk11-face-fix.log` (Mortal Kombat 11), `sm2-tpose-fix.log` (Marvel's Spider-Man 2) and `gow-depth-fix.log` (God of War). Every other DLL of ours names its log under `C:\`, in the prefix, which the report does not read (the DLLs' strings, read 2026-10-23); NINJA GAIDEN 3's third-party DLLs declare none.
- "### Settings › Log": this window's in-memory lines for the game, each block from "▸ <game> — <folder>" through the indented lines under it, the folder compared as `gameKey` compares it (Probe.swift:825-842), or "None. Settings › Log is kept in memory only and holds what this window ran since it opened; it ran nothing for <game>."
- Then the Report tab's own sections: what the game is made of, the Wine modules in each CrossOver, the modules' log lines that name the game's app id (none without one), and the game's own log.

### 2.2 Wine Modules (`EngineView`, 1139-1223)

**1. App Management notice.** This section only appears while macOS has refused a write to a CrossOver app (1144-1161).
- A lock-shield label: "macOS does not let MacGameFix change <app names>."
- Caption: "Turn MacGameFix on in System Settings › Privacy & Security › App Management, then check again. Releases signed with MacGameFix's Developer ID are expected to keep this permission across updates; the first update from a release made before the Developer ID, or a build not signed with it, may need it turned on again." Expected, not measured: macOS keeps the permission for the app's designated requirement, which with the Developer ID is the bundle identifier and the team, the same in every release; signed ad hoc, it is the build's own hash, so the first update from an ad hoc release to a Developer ID one changes it.
- **"Check Again"**: tries the write again on each CrossOver app that is on or was refused (526-530).
- **"Open App Management…"** (Return): opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles` (532-536).
- How the refusal happens: the app creates and deletes `lib/wine/.macgamefix-access` inside the app (507-513). This runs once per launch for CrossOver apps that are on (824-828), and before every install or removal in a CrossOver app (541).

**2. Main section**
- Header: "The DualSense's haptics and triggers, on a cable and over Bluetooth".
- Caption: "On installs the Wine modules into that CrossOver; off puts CrossOver's own back."
- Header tooltip: "Unlike the game fixes, these go into CrossOver itself. Quit that CrossOver's games first. In a CrossOver app, macOS asks to allow MacGameFix under App Management, and the app is signed again ad hoc." (1184-1192)
- Footer: "Only a CrossOver of a build and Wine the modules were built for can be turned on." (1194)

One row per CrossOver app (in /Applications and ~/Applications) and per NotProton runner (`EngineSwitch`, 2062-2091):
- **Name**, for example "CrossOver Preview 20261006", "CrossOver 26.3", or "NotProton runner · CrossOver Preview 20261015". Copies with the same name get " (<app or runner folder>)" (Engine.swift:122, 134, 139-144).
- **Caption**: "<build> · <state>", or "<build> · no modules for this build" when no modules exist (2071-2072).
  - States (Engine.swift:41-57): "…", "Installed" (green), "Older modules: install again" (orange), "Partly installed" (orange), "Not installed", "No modules for this build yet".
  - After a failed run, an orange "Failed — see the log in Settings" is added (563).
- **"Update"** (state Older modules) or **"Install Again"** (Not installed or Partly installed). These only appear when the switch is on but the modules are behind (797-799, 2080-2083).
- **Switch**: on installs the modules, off removes them (470-474).
  - Turning on a CrossOver app first shows the "Change CrossOver itself?" alert (section 3). Turning on a runner, or turning anything off, shows no question.
  - The switch is disabled while the state is "…", when there are no modules, or while busy (465, 2087).
  - Row tooltip: the install's root path (2089).

Below the rows:
- Empty state: "Looking…" or "No CrossOver or NotProton runner found." (1164-1166)
- Toggle **"New CrossOver builds too"** (default on). Tooltip: "With updates on Automatic: when NotProton adds a runner for a new CrossOver build and there are modules for it, they go there too, once a runner that is on has them." (1167-1171)
- Buttons, all disabled while busy (1172-1183):
  - **"All"** / **"None"**: each shows a confirmation alert, then installs into or removes from every row that has modules and is not already in that state.
  - **"Update All"**: only appears when some row is behind. Tooltip: "Brings the modules up to date in every CrossOver that is on and behind."
  - **"Look Again"**: scans the CrossOver installs again.

**3. "Updates" section** (1198-1218)
- Picker **"New Wine modules"**: **"Automatic" / "Ask first" / "Off"** (224-229). The default is Automatic (Automation.swift:66-67).
  - Tooltip: "New Wine modules from GitHub, on their own, once a day. On Automatic they also go back into the runners that are on after a CrossOver or NotProton update. “Ask first” checks the signature and tells you. A CrossOver app is only ever reported."
- **"New Wine modules ready (<n>)"** with an **"Install"** button, in orange. It only appears after the agent, in Ask first mode, found and verified a newer catalog.
- **"Catalog"**: the version number, with tooltip "Modules for: <CrossOver list>", and a **"Check Now"** button.
- Important: "Check Now" and "Install" both call `checkForModules` (258-277). That downloads and installs a newer modules catalog right away. It is not just a check.
  - Getting a new catalog does not change any CrossOver. The rows then show "Older modules: install again", along with "Update" and "Update All".

### 2.3 Game Feel (`ControllersView`, 1411-1505)

**Top area** (1429-1439)
- "Every game" (headline), with a summary of the global options below, joined by " · ".
  - On first run this starts "Bluetooth as a cable · full motor power · Edge shown as an Edge · DualSense haptics 1× on a cable · …" and is cut to two lines (Pad.swift:155-180, 60-64).
- **"Every Game's Settings…"** opens the global sheet.
  - Tooltip: "What every game gets unless it has settings of its own: the connection, XInput, the haptics' strength and the trigger effects, each with a thirty-second try."

**"Per game" area** (1446-1451)
- A **"Search"** field: matches part of a name (any case) or an exact app ID (1422).
- **"Look Again"**: reads the Steam games and the modules' log again, and asks the Steam store about games it hasn't asked about yet (585-613).
- **"Export…"**: tooltip "The settings and what was seen of each game, to share. No paths or accounts."

**Table** (1453-1463). A single click on a row opens that game's sheet (1464-1466).
- **"Game"**: Steam cover and name. The name is in the accent colour when the game has options of its own.
- **"Settings"**: "As every game", or the differences joined by ", ".
  - " (suggested)" is added when the difference comes from a preset, or from the Steam-store rule ("an XInput controller"), rather than from the user (1496-1500).
- **"Seen"**: what the modules logged the game doing: "haptics as audio", "rumble motors", "rumble through XInput", "trigger effects", "sets the motor power", "played over Bluetooth" (Pad.swift:282-291).
- Covers come from Steam's `appcache/librarycache/<appid>/library_600x900.jpg` or `header.jpg`. A grey tile with a gamepad stands in where Steam has none (1804-1849).

**Footer** (1467-1482)
- "No Steam game found." / "No game matches." / "<n> game(s)".
- A **"Show"** picker with 15/25/50/100, tooltip "How many games a page shows.", saved in UserDefaults under `gameFeelPerPage`.
- Back and forward chevrons, and "Page <x> of <y>".

### 2.4 Report (`ReportView`, 1227-1302)

- Header (1245-1248): "A game that does not work", with this caption: "Click it. MacGameFix looks at what the game is made of, without changing anything in it, and walks you through a report for an issue on GitHub, which is where it gets fixed. The report names that game alone."
- A **"Search"** field (name or app ID) and **"Look Again"**, which reads the Steam games and the catalog again (1256-1258).
- Table (1260-1274). A single click opens the Report sheet (1275-1277).
  - **"Game"**: cover and name.
  - **"Runs in"**: the prefix and bottle names, or "—".
  - **"MacGameFix"**: "Has a fix" or "—".
- Footer: the same count texts as Game Feel, plus the "Show" picker (15/25/50/100, no tooltip, saved under `reportPerPage`), chevrons and "Page x of y" (1278-1292).
- The list is every Steam appmanifest whose install folder exists, except app 228980 (Probe.swift:23-43).

### 2.5 Settings (`SettingsView`, 2095-2219)

**"Background"** (2100-2125)
- **"Run from the menu bar"**: installs or removes the LaunchAgent (211-218).
  - Tooltip: "MacGameFix starts when you log in and stays in the menu bar. Every two minutes it puts back the fix of a game marked “Keep it applied” after Steam updates or verifies it, once the game is closed."
  - If the agent can't be started, the error goes to the Log, not to an alert: "Could not start the agent: …" (213).
- **"Show the controller's battery"**: default on. Disabled while the agent is off.
  - Tooltip: "Beside the raccoon in the menu bar: a gamepad and the battery left in a connected controller, the lowest if there are several. The menu lists each one."
- **"Icon"** picker: **"Raccoon and gamepad" / "Gamepad" / "Battery only"**. Disabled unless the agent is on and the battery option is on.
  - Tooltip: "What stands beside the battery in the menu bar. With no controller connected, the gamepad stays if it is chosen; otherwise the raccoon shows."
- For each kept game whose folder is gone: "<name>: folder gone" in orange, with a **"Stop Keeping It"** button that removes the game from the kept list (2118-2124).

**"Game Mode"** (2127-2143)
- Toggle **"Game Mode for CrossOver's games"** (default off).
  - Tooltip: "macOS turns Game Mode on for a game in full screen whose app says it is a game. A game in CrossOver runs from a copy of Wine that does not say so; with this on, it runs from one that does, kept in MacGameFix's folder. CrossOver itself is not changed, and turning this off takes it all away."
- When on, a coverage line follows (GameMode.swift:266-277): "For <CrossOver name> (Intel and FEX), …." or "No CrossOver of a release this was checked with: 26.1, 26.3, Preview 20261006 or 20261015."
  - The line only fills in after the toggle is flipped, or after a CrossOver scan with Game Mode on (195-199, 814-819).
- Footer: "Play in full screen: the green button, or Control-Command-F. Game Mode also doubles what a wireless controller's Bluetooth link carries, which a DualSense's haptics need."

**"Game fix updates"** (2145-2167)
- Picker **"Game fixes"**: "Automatic" / "Ask first" / "Off" (default Automatic).
  - Tooltip: "New fixes from GitHub, looked for once a day. “Ask first” checks the signature and tells you; nothing is installed until you say so."
- **"New fixes ready (<n>)"** with **"Install"**, in orange, when one is waiting.
- **"Catalog"**: the version and **"Check Now"**. As in Wine Modules, this downloads and installs a newer catalog, then scans the games again (279-298).
- Footer: "The Wine modules have their own, in Wine Modules."

**"Recent"**. Only shown when the agent has recorded events (2169-2185).
- Up to 5 of the newest events, as "<game>: <message>" (orange if it failed), with the abbreviated date.
- A **"Report…"** button when the event has a report link.

**"Games"** (2187-2202)
- A disclosure group **"Folders searched (<n>)"** listing every library path. The ones the user added have a **"Remove"** button.
- **"Add Folder…"**, the same as on the Games tab.

**"Log"**, a disclosure group (2204-2214)
- Monospaced, selectable text, 160 pt tall.
- Lines include "▸ <game> — <folder>", "  into the <prefix>", the installer's output indented, "▸ Wine modules — <name> — <root>", "The report could not be saved: …", and "Could not start the agent: …".
- **The log is kept in memory only** (37, 307). It holds what this window ran and is lost when the window closes. The README and `game-fix.yml` both tell users to copy lines from Settings › Log, so the guide should say to copy them before closing the window.

---

## 3. Sheets, popovers, dialogs and alerts

**A. Folder picker.** Opened by "Add Folder…" on Games or Settings. Described in 2.1.

**B. Alert "Change CrossOver itself?"** (492-501)
- Opened by turning on a switch for a CrossOver *app* (not a runner), or by "All" when the list includes an app.
- Text: "MacGameFix puts its Wine modules into <names>. macOS asks you to allow MacGameFix under App Management, and the app is signed again ad hoc, so CodeWeavers' signature no longer covers it. Turning it off puts CrossOver's own files back."
- **"Install"** goes ahead. **"Cancel"** leaves the switch off.

**C. Alert from "All" or "None"** (477-490)
- Title: "Install the Wine modules into <n> CrossOver install(s)?" or "Remove the Wine modules from <n> CrossOver install(s)?"
- Body: the install names, one per line.
- Buttons: **"Install"** or **"Remove"**, and **"Cancel"**. If no row would change, nothing appears at all.

**D. Report sheet.** Opened by clicking a game in the Report tab (`ReportSheet`, 1306-1406).
- **Header**: a large cover and the name, then:
  - "Steam app <id>. Runs in: <places>." or "Steam app <id>. No prefix or bottle found beside its library."
  - "MacGameFix has a fix for it in Games: <fix>." or "MacGameFix has no fix for it yet."
- **Picker "What goes wrong"** (Probe.swift:527-534):
  - "It does not start, or closes at once"
  - "It crashes while playing"
  - "Videos or cutscenes are black, frozen or missing"
  - "Something looks wrong on screen"
  - "It runs slowly"
  - "The controller, its haptics or its triggers"
  - "Sound"
  - "Something else"
- **"1. What MacGameFix found in the game"**
  - While the folder is read: a spinner and "Looking through the game's folder…".
  - Then these rows: "Main executable", "Graphics", "Engine", "Controller", "Video", "Middleware", "Anti-cheat". Values can be "none found" or "not recognised" (Probe.swift:171-180).
  - Footer: "Read from the game's folder alone; nothing in it was changed."
- **"2. Before you make the report"**: numbered steps that depend on the symptom. The full text is at Probe.swift:539-566.
  - For "The controller, …" there is also a **"Diagnose this game"** toggle, with tooltip "The Wine modules log what this game writes to the pad, from its next start. Turn it off again afterwards."
  - If Game Feel isn't available, that toggle is replaced by "The Wine modules are in no CrossOver yet: turn them on in Wine Modules first." (1361-1372)
- **"3. The report"**
  - Text: "Saves the report and opens a new issue on GitHub. Attach the report there, with any screenshot, and say what happens in your own words."
  - Button **"Save the Report and Open an Issue…"**, disabled until the folder has been read.
  - Footer: "The report names this game alone, writes your home folder as ~ and leaves your Mac's name out. It adds the game's own log when the game writes one."
- **"Done"** (Return) closes the sheet.

**E. Saving a report, then opening a GitHub issue** (`saveReport`, 684-697)
- A Save panel opens in **~/Downloads** with a suggested name:
  - "MacGameFix game report - <game> - <YYYY-MM-DD>.md" from the Report sheet
  - "MacGameFix report - …" from Make a Report…
  - "MacGameFix settings - …" from Share These Settings…
  - "MacGameFix vibration report - …" from It Vibrates…
  - "MacGameFix fix report - …" from It Works…, and "MacGameFix report without the fix - …" from Works Without the Fix…
- After saving, the file is shown in Finder and the browser opens a GitHub issue form, pre-filled (Pad.swift:676-725, MacGameFix.swift:639-642, 648-673, 728-732, 749-771):

  | Button | Form | Pre-filled fields |
  |---|---|---|
  | Save the Report and Open an Issue… | `game-report.yml` | title "[Game] <name>", game "<name> (Steam app <id>)", what "<symptom>. " |
  | Make a Report… | `controller.yml` | title "[Controller] <name>", game |
  | Share These Settings… | `game-feel-settings.yml` | title "[Settings] <name>", game, settings = the key=value lines |
  | It Vibrates… | `vibration-works.yml` | title "[Vibrates] <name> · <controller> · <connection> · shown as a <identity>", each part after the name only when the modules' log has a single one for the game's latest session, the identity only with a single controller too (`PadSession`, Pad.swift:728-757); game; controller ("DualSense" or "DualSense Edge"); connection ("Cable" or "Bluetooth"); shown-as ("DualShock 4" or "DualSense", when the pad was shown as another); seen; library ("Sony libScePad", "SDL", "Raw HID", "XInput" or "DirectInput", guessed from the game's folder: "Sony libScePad" whenever it ships Sony's library, Probe.swift:139-151); settings |
  | It Works… | `fix-works.yml` | title "[Works] <name>"; game "<name> (Steam app <id>)", the name alone without an app id; runs "A NotProton runner" (Steam Play prefixes alone, with a NotProton runner on the Mac), "A CrossOver bottle" (bottles alone, or, with none named, bottles that are only counted) or "Native macOS (no Wine)" (a macOS game), else unset; backend "None (a macOS game)" for a macOS game, else unset: which backend ran a Windows game is not read, and games.json's backend is what the fix was made for (Mortal Kombat 11's says D3DMetal, and its fix works on DXMT too), which the report gives instead; versions "MacGameFix <v>, catalog <n>; <CrossOver app or runner> (<build>, D3DMetal <v> and <v>) or …; macOS <v>; <chip>"; game-version, the build the installer names or "Steam build <id>", when either is known; log, the fix's own log lines (as "<path>, last written <time>:"), or "The fix writes no log of its own." or "No <names> in the game's folder.", or "<path> is there and could not be read (<reason>).", then this window's Settings › Log lines for the game, or "Settings › Log: nothing this window ran for this game." when it has none. The field stays within 5000 bytes (`Report.longest`, Automation.swift:609, the limit of the agent's failure link): the own log is kept when it fits beside the shortest Settings › Log part, else it is "The fix's own log, <names>, is in the attached report: more than this link carries."; Settings › Log's lines are kept when they fit after it, else "Settings › Log's lines for this game are in the attached report: more than this link carries.", which is never said when there are none (Probe.swift:858-968) |
  | Works Without the Fix… | `works-without-fix.yml` | title "[No longer needed] <name>"; game; toolkit, the D3DMetal version when the CrossOver apps or runners of the kind the game runs in carry exactly one, else unset; versions, as above |

- For those two, a field the app cannot read is left out of the link, not sent empty (`Issue.new(template:fields:)`, Pad.swift:683-691), and every dropdown value is one of the form's options exactly. Each value is written with the home folder as ~ and without the Mac's name, as the report is.

- If the user cancels the Save panel, no issue opens.

**F. "Every Game's Settings…" sheet** (`PadGlobalSheet`, 1876-1932)
- Section header "Every game", with this caption: "The Wine modules read these when a game starts; in CrossOver, when Steam or the game opens the bottle, so make a change before you open it there, or quit and open it again. The haptics' strength is read each time a game starts its haptics. A game's own settings win, and so do its suggested ones."
- Option rows. Each has a caption that is always visible (1546-1608):
  - Toggle **"Bluetooth as a cable"**
  - Toggle **"Full motor power on the Edge"**
  - Toggle **"Show the Edge as a standard DualSense"**
  - Picker **"XInput"**: "Off" / "Its rumble on the motors" / "The pad as an XInput controller". Its caption changes with the choice (1546-1563).
  - Toggle **"Rumble on the haptic actuators"**
- Toggle **"Diagnostics in the modules' log"**. Tooltip: "What a game writes to the pad and reads from it, and a level meter of its haptics, in /tmp/macgamefix-<uid>/pad.log."
- **"Haptics strength"**: a grid with columns "DualSense" and "DualSense Edge" and rows "Cable" and "Bluetooth". Each cell is a picker with 1×, 1.5×, 2×, 2.5×, 3×. Each cell has its own tooltip, for example "A standard DualSense on a cable." (1775-1801). A haptics try row follows.
- **"Trigger effects"**
  - Caption: "For a game that sets none of its own, such as an XInput title. A game that sets one takes that trigger over."
  - Grid columns "Effect" and "Strength". Rows "R2", "  while L2 is pressed", "L2", "  while R2 is pressed".
  - Effect choices: "Off", "Resist", "Weapon", "Slope", "Vibrate", "Rumble with the motor", "Recoil with the motor". In the second rows, "Off" reads "The same as R2" or "The same as L2".
  - Strength choices: "Default", 1–8. Disabled when the effect is off.
  - Lines below, such as "R2, weapon: <feel>".
  - Button **"What Each Effect Does…"** opens popover G.
  - Footer: a triggers try row, and "Measured with NOTPROTON_RAW_CONTROLLERS=1 in the game's launch options and Steam Input off."
- Every change writes `pad.json`, `pad.conf` and `pad.d/` right away (617-623). There is no Save button.
- **"Done"** (Return) closes the sheet. Closing it stops any running try.

**G. Popover "What each effect does"** (1633-1666)
- A table with columns "Effect", "How it feels", "Suits", "Default strength". The row texts are at 1617-1630.
- Two notes under it:
  - "While the other is pressed: a second effect that replaces a trigger's own while the other trigger is held, a weapon on R2 while L2 aims, say. The other counts as pressed from about a sixth of its travel."
  - "Strength runs from 1, light, to 8, the pad's strongest; Default is each effect's own. The pad keeps an effect until something else is written: the Wine modules release the triggers when the game's Wine stops, or when the next game starts."

**H. Per-game Game Feel sheet.** Opened by clicking a game in Game Feel (`PadGameSheet`, 1936-2058).
- **Header**: a cover and the name, then:
  - "In blue, or marked with a dot, what is this game's own; the rest follows every game's." If the game has a preset, the end reads "the suggested settings, then every game's."
  - "They apply under NotProton, from the game's next start. A CrossOver bottle does not tell the modules which game runs, so there every game's settings apply."
- **Options**: the same option rows, haptics grid, trigger grid and both try rows as sheet F.
  - One row is here alone, after "Show the Edge as a standard DualSense": toggle **"Show the pad as a DualShock 4"**, with the caption "For a game whose controller code knows only the PS4 pad, such as Mortal Kombat 11, which vibrates through it (played on 2026-10-22). The pad is shown to the game as a DualShock 4 on a cable, over Bluetooth too." (1588-1595). It writes `pad_as=dualshock4`, `bluetooth=wired`, `edge=edge` and an XInput line to the game's `pad.d/<appid>.conf`, whatever the Bluetooth and Edge rows held: `edge=edge` so that every game's `edge=dualsense` does not name the pad's audio device a DualSense's, and `xinput=off`, or `xinput=rumble` when the picker below says so (PadOptions.ds4XInputRumble); turned off again, the `pad_as` line goes and the Bluetooth and Edge rows' values come back (Pad.swift:107-148). Sheet F never shows it, and every game's settings never carry it (Pad.swift:471-473).
  - While it is on, "Bluetooth as a cable" shows on and "Show the Edge as a standard DualSense" shows off, both greyed out (1523, 1566-1587); the Bluetooth caption reads "On while the pad is shown as a DualShock 4: the game sees a DualShock 4 on a cable." and the Edge caption "Off while the pad is shown as a DualShock 4: the game sees a DualShock 4, whichever pad it is." The "XInput" picker offers "Off" and "Its rumble on the motors" only, the game's own choice (Off unless asked; 1537-1544, 1596-1600), with the captions "XInput gets nothing. A game that rumbles through the DualShock 4, as Mortal Kombat 11 does, needs nothing more." and "For a game that shows PlayStation buttons through the DualShock 4 but rumbles only through XInput: its rumble goes to the motors. No game played has vibrated through it: Crysis 2 Remastered, played with it on 2026-10-22, sent XInput no rumble." (1546-1554). The "Full motor power on the Edge" caption reads "Shown as a DualShock 4, the game cannot set the motor power: a DualShock 4 has none. This claims it at full for either pad." (1575-1576). The table's "Settings" column says "shown as a DualShock 4", drops the Bluetooth and Edge words, and gives XInput as "XInput's rumble" or "no XInput" (Pad.swift:155-180).
  - The game's own values show as accent-coloured titles, or with a small dot.
  - Setting a value back to what the game would get anyway stops it being the game's own (1948-1961).
  - There is no Diagnostics toggle and no "Measured with" line here.
- **"About this game"** (1999-2041)
  - Toggle **"Diagnose this game"**. Tooltip: "The Wine modules log what this game writes to the pad, the haptics' levels and delays, for this game alone, from its next start."
  - **"It Vibrates…"** (2006-2009). Tooltip: "Saves this game's report and opens a new issue on GitHub that says it vibrates, with the controller, the connection and what the pad was shown to the game as, as the Wine modules saw them, for the list of games played for vibration." It opens the `vibration-works.yml` form (section 3, E).
  - **"Share These Settings…"**. Tooltip: "Saves this game's report and opens a new issue on GitHub with these settings in it, to attach it to."
  - **"Make a Report…"**. Tooltip: "Saves this game's report and opens a new issue on GitHub to attach it to."
  - Three captions (2016-2025): "To report a problem: turn on Diagnose, play the moment that goes wrong, close the game, then make a report and attach it to the issue that opens. …", "If these settings feel right, share them the same way: shared settings that a report backs become this game's suggested ones for everyone." and "If it vibrates, say so the same way, once for each controller and connection you played: a game's report that it vibrates adds it to the list of games played for vibration."
  - Info lines:
    - "Suggested: <summary>. <measured note>" when a preset exists. Presets exist for God of War 1593500, F1 23 2108330, Nioh 3 3681010 and Marvel's Spider-Man 2 2651280 (pad-presets.json).
    - One of: "The Steam store lists it as supporting the DualSense.", "The Steam store does not list it as supporting the DualSense, so it gets the pad as an XInput controller.", or "Not asked of the Steam store yet."
    - "Seen: …." when something was seen.
    - "Steam app <id>".
- **Bottom bar**
  - When the game has options of its own: **"Use Every Game's"** (no preset) or **"Use the Suggested"** (preset). Either one clears the game's own options (2045-2049).
  - **"Done"** (Return). Closing the sheet stops any running try.

**I. Export Save panel.** From "Export…" in Game Feel.
- Suggested name "MacGameFix controllers.json", JSON only, no default folder set (783-794).
- Contents: the global options and, for each game, the app ID, name, options that differ, what was seen, and the preset note (Pad.swift:588-615).

**J. Try rows.** These are inline in sheets F and H, not separate windows (`PadTryRow`, 1853-1873; PadTester.swift).
- Idle text for haptics: "Plays a rumble soft, medium and strong, then hits left and right, at the strength above for the pad connected and how it is connected."
- Idle text for triggers: "Sets the effects above on the pad connected; rumble and recoil follow a stand-in for a game's rumble."
- Button **"Try for 30 Seconds"**, which becomes **"Stop"** while running. Tooltip: "Close any game first: the try writes to the pad as the Wine modules do."
- Messages while trying:
  - "Haptics on the <DualSense|DualSense Edge> <over Bluetooth|on a cable> at <n>×, <s> s"
  - "Trigger effects on the <pad>, <s> s"
- Error messages:
  - "No DualSense or DualSense Edge is connected."
  - "The <pad>'s audio output was not found."
  - "The <pad>'s audio output did not start: <error>"
  - "No trigger effect is chosen."
- Only the first DualSense or DualSense Edge found is used (PadTester.swift:90, 235). The try stops by itself after 30 s.

**K. Agent notifications.** These come from the menu-bar agent, not the window (Automation.swift:668-700).
- Title is the game name or "MacGameFix". Body is the event message (all messages are in section 5).
- A failure has the action **"Report on GitHub…"**. It opens `issues/new` with the title "<game>: <problem>" and a body containing Game, What happened, the MacGameFix version and catalog, the macOS version, and the installer's last 60 lines with home, user name and serial number removed.
- That link uses no template, so it opens GitHub's blank issue form (Automation.swift:613-641).

**L. Alert "Change <game>'s app?"** (MacGameFix.swift:415-433)
- Opened by "Install Selected" when a selected row's fix changes a macOS game's app; today only Cyberpunk 2077's. With several such rows the title is "Change <n> games' apps?". Also opened, for that one row, by checking its Keep box.
- Text, one row: "MacGameFix writes the recipe's bytes into its executable and signs it again ad hoc, so the developer's signature no longer covers the executable. macOS may ask you to allow MacGameFix under App Management. Remove puts the original back from the copy MacGameFix keeps."
- Text, several rows: "MacGameFix writes the recipe's bytes into the executables of <names> and signs each again ad hoc, so the developers' signatures no longer cover them. macOS may ask you to allow MacGameFix under App Management. Remove puts the original back from the copy MacGameFix keeps." The names are joined by the system's list format ("A and B", "A, B, and C").
- From the Keep box, the text ends with " With Keep on, the agent does this in the background whenever the fix is missing, after a game update too, without asking again." and the first button is **"Keep"**.
- **"Install"** goes ahead with every selected row. **"Cancel"** installs nothing. Removing asks nothing.

---

## 4. The menu bar item (`MenuBar.swift`)

It only exists while the agent runs: "Run from the menu bar" is on.

**Icon** (165-185)
- A raccoon, drawn as a template image, with a dot by the ear when something new happened since the window was last opened. "Something new" means a failure, or a catalog or module event (Automation.swift:126, 211).
- With "Show the controller's battery" on and a controller connected, the lowest battery is shown:
  - "Raccoon and gamepad": raccoon, gamepad, then " NN%"
  - "Gamepad": gamepad (with a dot when there is news), then " NN%"
  - "Battery only": no image, just "• NN%" or "NN%"
  - With no controller, every choice except Gamepad falls back to the raccoon.
- Accessibility label: "MacGameFix: something new to look at" or "MacGameFix", plus ", <pad> battery <n> percent".

**Menu**, rebuilt each time it opens (192-249):
1. **"MacGameFix"** in bold (not clickable).
2. Either "No game is marked “Keep it applied”." or "Keeping 1 fix applied" / "Keeping <n> fixes applied".
3. Indented counts, each with an icon:
   - "<n> in place" (checkmark)
   - **"<n> to review…"** (eye). This is the only clickable count: it opens the window with only those games shown (`--review`). It counts the kept games the agent reported "Failed", "Folder not found" or "Cannot be installed here" (MenuBar.swift:31).
   - "<n> waiting for a recipe" (hourglass): a kept game whose fix is made for each game build, after an update its catalog has no recipe for yet (MenuBar.swift:81). Not clickable, and not counted to review.
   - "<n> not looked at yet" (clock)
4. If controllers are connected, between separators: "<name>: NN%", plus ", charging" or ", charged", with a battery icon (211-221, 452-462).
5. "Looking at the games…" while a pass runs, otherwise "Last look: <time>".
6. Separator, then "Fixes catalog <n>" or the agent's last update line, and the last modules update line if there is one.
7. **"Look at the Games Now"**: checks every kept game even if Steam didn't change it. Disabled while a pass runs or when no game is kept.
8. **"Check for New Fixes"**, which reads **"Install New Fixes (catalog <n>)"** when a verified catalog is waiting.
   - It forces an update that installs a newer fixes catalog, even in "Ask first" or "Off" mode, because the forced path skips the ask branch (Automation.swift:229-235).
   - Afterwards it posts a notification with the update line (153).
9. **"Install New Wine Modules (catalog <n>)"**: only shown when a modules catalog is waiting. It forces the modules update and posts a notification (154-156).
10. **"Open MacGameFix…"**: brings an open window forward, or launches the window (286-297).
11. Separator, then **"Quit MacGameFix"**: asks any open window to quit (a window that is installing finishes first), then quits the agent (274-281).
    - The LaunchAgent only restarts after a crash. It comes back at the next login, or when the window is opened.

---

## 5. App menus, Settings window, shortcuts, command line, background agent

**Menus.** No custom commands are defined: there is no `.commands`, no `Settings {}` scene, and no SwiftUI MenuBarExtra.
- The menu bar shows only SwiftUI's standard menus for a window app. The app menu has no "Settings…" item; settings are the Settings *tab*.
- Unclear from the code: File › New Window (⌘N) probably opens a second, independent window with its own scan and its own log, since each window creates its own model (866).

**Keyboard shortcuts.** Only Return, as the default button:
- "Install Selected" (Games, 968)
- "Open App Management…" (1157)
- "Done" in the Report sheet, the Every Game's Settings sheet and the per-game sheet (1396, 1925, 2051)

The "Control-Command-F" in the Game Mode footer is advice for full screen in games, not an app shortcut.

**Command-line flags**, all in one binary (2264-2514):
- `--agent`: the menu bar agent
- `--review`: opens the window with only the games to review
- One-off commands that print or write and then exit: `--agent-once`, `--menu-report`, `--pad-write`, `--pad-export <file>`, `--pad-report`, `--games-report` (named in the README), `--game-mode-keep|--game-mode-remove|--game-mode-report`, `--engine-report`, `--pad-game-report <appid> <path>`, `--probe-report <appid> <path> [symptom]`, `--probe-games`, `--pad-share-url <appid>`, `--pad-vibrates-url <appid>`, `--fix-report <game name> <path> [works|without]`, `--fix-works-url <game name>`, `--works-without-url <game name>`, `--engine-install|--engine-remove <root>`, `--update-from <dir> [--pubkey --kind modules]`, `--new-signing-key <file>`, `--make-catalog <out> --key <file> [--from]`
  - `--fix-report`, `--fix-works-url` and `--works-without-url` (2404-2433) find the game in Games by its catalog name and ask its installer, as the window does. Each refuses as its button would, printing "<game>: <state>; <It Works…|Works Without the Fix…> needs <Installed|Not installed>" and exiting 1, and writes the report or prints the form's link otherwise. The rule is the buttons' own (`FixReport.target`). They have no window: `MACGAMEFIX_SESSION_LOG`, a file standing for Settings › Log, gives the game's blocks to the report and the log field as the window's log would (2400-2403); without it, the report's Settings › Log section says none. The tests use it.

**Background agent** (`--agent`)
- It is a LaunchAgent with label `io.github.macgamefix.agent`. It starts at login and restarts only after a crash (Automation.swift:705-725).
- It does a pass at start and every 120 s (MenuBar.swift:114-118). Battery readings refresh every 60 s and when a controller connects or disconnects.
- Each pass (Automation.swift:279-397) does the following.

*Fixes catalog.* At most once every 24 h, if updates are on.
- In "Ask first" mode it only verifies the signature. Once per version it notes: "New fixes are ready (catalog <n>). Install them from the menu bar or MacGameFix's Settings."
- In "Automatic" mode it installs, then notes "New fixes: <names>" or "The fixes were updated."

*Wine modules catalog.* The same, with "New Wine modules are ready (catalog <n>). Install them from the menu bar or MacGameFix's Settings." and "The Wine modules were updated."
- That message says "Settings", but the window's install button for modules is in the Wine Modules tab.

*Wine modules in each CrossOver*, when modules updates are on (Engine.swift:198-249).
- For each install that is on, or a new runner covered by "New CrossOver builds too", that is behind:
  - **CrossOver apps, and everything in "Ask first" mode**, are only reported, once: "<name> needs <newer Wine modules | the Wine modules again: something replaced them, such as a CrossOver or NotProton update | the Wine modules: it is a new CrossOver build>. Install them from MacGameFix's Wine Modules tab."
  - **Runners in "Automatic" mode** get the modules installed once that CrossOver's games are closed: "Wine modules updated in / put back in / installed in the new <name>."
  - A failed install gives "The Wine modules could not go into <name>: <last line>."

*Game Mode.* If it is on, the links are put back.

*Game Feel.* If `pad.json` exists:
- It refreshes `pad-exes.conf`, reads new lines from the modules' log, and asks the Steam store about new games.
- If the store taught it anything, it rewrites `pad.conf` and `pad.d/`.

*Each kept game*
- It skips a game that is not in the catalog, whose folder no longer matches, that Steam is still writing (StateFlags ≠ 4), or that is running.
- It checks a game when its build or the catalog changed, when "everything" was asked for, or after 6 h.
- Messages:
  - "The fix is in place." (only after an earlier state that was not installed)
  - "The fix is updated to the newer build."
  - "Steam changed the game; the fix is back in place."
  - "The fix was missing and is back in place."
  - "A recipe for this build arrived; the fix is in place." (after waiting for one)
- Waiting, not a failure, with no report link and no dot: "No recipe for this build yet; MacGameFix puts it back when one arrives." It runs the installer only to ask its state, never to install, and says this once for each Steam build, however many catalogs or rechecks come before a recipe (Automation.swift:351-360). The menu bar shows the game as "Waiting for a recipe".
- Refused by the installer, not a failure, with no report link and no dot: for "Cannot be installed here", and for "Half installed" on a fix that changes a macOS game's app, the message is the installer's reason (see the blockers in 2.1), or "The installer cannot install the fix here." without one. It runs the installer only to ask its state, and says this once for each Steam build (Automation.swift:334-350). The menu bar shows the game as "Cannot be installed here", with that reason, and counts it to review.
- Failures, which carry a report link:
  - "The installer found nothing in the game folder for the fix to ride on."
  - "The installer failed (status <n>)."
  - "The fix did not take."

*Notifications.* Every event from the pass becomes a notification. The newest 50 events are kept for Settings › Recent (Automation.swift:213-216, 395).

---

## 6. Files and permissions

**`~/Library/Application Support/MacGameFix/`** (Core.swift:19-25 and the other files)

| Path | Contents |
|---|---|
| `automatic.json` | Settings: kept games, update modes, which CrossOvers are on or off, battery and icon choice, Game Mode, last-seen date |
| `agent-state.json` | The agent's memory and its events |
| `installer.lock` | Lock so the window and the agent never run an installer at once |
| `catalog/<version>/`, `catalog/current` | Downloaded fixes catalogs; two versions are kept |
| `modules/…` | The same, for the Wine modules |
| `engine-backup/` | CrossOver's own files, kept while the modules are in (Engine.swift:71) |
| `app-backup/<bundle id>-<build>/` | The original executable and `_CodeSignature/CodeResources` of a macOS game whose app a fix changed (Cyberpunk 2077), and `apps`, the app or apps it is kept for, one path a line. Kept until the fix is removed from every app listed; a copy kept for another build of the same app is deleted at the next install or removal that works (Core.swift:27; `fixes/install-cp2077-denoiser.sh`) |
| `pad.json` | Everything Game Feel keeps |
| `pad.conf` | Every game's options. First line: "# Written by MacGameFix (Game Feel); read by its Wine modules. Edit it there.". Keys: `bluetooth`, `motor_power`, `edge`, `haptics_gain_cable`, `edge_haptics_gain_cable`, `haptics_gain_bluetooth`, `edge_haptics_gain_bluetooth`, `xinput`, `rumble`, `trigger_r2`, `trigger_l2`, `trigger_r2_with_l2`, `trigger_l2_with_r2`, `diagnostics=on` (Pad.swift:119-148, 528-548) |
| `pad.d/<appid>.conf` | One game's differing lines and its Diagnose setting, headed "# <name>"; for a game shown as a DualShock 4 also `pad_as=dualshock4`, `bluetooth=wired`, `edge=edge` and its XInput line (Pad.swift:107-148). Removed when no longer needed |
| `pad-exes.conf` | Exe name to app ID, for CrossOver bottles (Pad.swift:768-834) |
| `GameMode/<app> <build> <arch>/CrossOver Game.app` and `GameMode/scan.json` | Game Mode's helper apps (GameMode.swift:37, 61-64, 212) |

**Other locations**
- `~/Library/LaunchAgents/io.github.macgamefix.agent.plist`: the agent's job (Automation.swift:707).
- `~/Library/Logs/MacGameFix-agent.log`: the agent's output (Automation.swift:713).
- `/tmp/macgamefix-<uid>/pad.log`: the Wine modules' log. The modules write it; the app reads it. It can be moved with `MACGAMEFIX_PAD_LOG`, and it is emptied on restart (Pad.swift:459-462, 561).
- `$TMPDIR/winetemp-*/<exe>`: Game Mode's links, which turning Game Mode off removes (GameMode.swift:78-83, 280-291).
- Inside each game folder and prefix: whatever that game's installer puts there. Spider-Man 2's tools are cached in `~/Library/Caches/MacGameVideoFix` (README:373-379).
- Reports: wherever the user saves them, ~/Downloads by default. The export goes wherever the user saves it.
- `games.json`, in the app's Resources or a downloaded catalog: one row per game. Its `logs` (optional, decoded as `Game.logs`, Core.swift:150-152) names the logs the fix writes beside its DLL, from the installer's `# MGVF-LOG:` line; `fixes/check-builds.sh` checks that a source in `fixes/` or `tools/` writes each name, that a DLL of the installer carries it, that no DLL of ours writes another log beside itself undeclared, as a narrow or a wide (UTF-16) string, and that a built app's games.json carries each installer's names.
- App preferences (domain `io.github.macgamefix`): `extraFolders`, `reportPerPage`, `gameFeelPerPage`.

**Network.** Users may want to know about these:
- The GitHub API at `releases/latest`, for catalog checks.
- Steam's public store API, once per installed game, to learn whether it lists the DualSense: `https://store.steampowered.com/api/appdetails?appids=<id>&filters=categories` (Pad.swift:389). It runs from Game Feel and from the agent.

**Permission prompts**
- **App Management**
  - Triggered by any install or removal of modules in a CrossOver *app*, by the once-per-launch check, and by "Check Again".
  - macOS shows its own notification; its text is not in the code. The comment at 821-823 says the app deliberately shows no alert of its own.
  - The app's own texts about it are the "Change CrossOver itself?" alert (B) and the Wine Modules notice (2.2).
  - NotProton runners need no App Management (508).
  - Installing or removing Cyberpunk 2077's fix writes into the game's app and may meet the same refusal. The app does not probe for it; the installer says "macOS did not let MacGameFix change <app>." and points to App Management, in Settings › Log.
- **Notifications**: the agent asks for alert permission when it starts (Automation.swift:678). The prompt is macOS's standard one.
- **Game Mode helper apps**: they declare microphone and camera usage texts, which a game running from them could trigger: "This game would like to access your microphone." and "This game would like to access your camera." (GameMode.swift:110-111).
- **First launch**: a notarised download is expected to open after macOS's usual question for an app from the internet; not measured, since no MacGameFix build has been notarised so far. One that is not notarised (the releases signed ad hoc, before the Developer ID, or a build without one) is blocked by Gatekeeper. The README says "Right click > Open" once on macOS 14 and, from Apple's notes, "Open Anyway" in System Settings › Privacy & Security on macOS 15 and later, which has not been tried with MacGameFix (README:544-554).
- Not requested in the code: Input Monitoring, Bluetooth, or folder access. The pad tries use IOHID and CoreAudio directly. I can't tell from the code whether macOS asks for anything for those, so check it on a real Mac.

---

## 7. Suggested screenshots (clicks from launch)

**Games**
1. Games tab, normal: launch, wait until the status line says "<n> game(s) found."
2. All fixes: click the "All fixes" segment. The "Not on this Mac" rows and the "<n> fix(es), …" count show.
3. Fixed, nothing fixed: click "Fixed" on a Mac with no fix installed. Shows "No game is fixed yet. …" and the "Supported: …" list.
4. Installing: select a row, click "Install Selected" (or press Return). The spinner and "Installing <game> (1 of 1)…" show.
5. Goes into menu: on KINGDOM HEARTS, NieR or NINJA GAIDEN 3 with two or more prefixes, click the "Goes into" menu. A row with no prefix shows the red blocker text instead.
6. Tooltips: hover the Game column (folder and why), the Requires note, and the Keep checkbox.
7. Add Folder: click "Add Folder…" to show the folder picker and its message.
8. Review mode: this needs a kept game that failed in the background. Menu bar icon › "<n> to review…" opens the Games tab with "Only the marked games to review (<n>)" on, and the orange "In the background: …" line with "Report on GitHub…".
9. It Works… and Works Without the Fix…: select one game whose fix is installed and hover the two buttons under the table for their tooltips; click It Works… for the Save panel, then the `fix-works.yml` form filled in. Remove a fix, select that game and click Works Without the Fix… for `works-without-fix.yml`. Then, with a row Installed, move the fix's DLL out of the game folder in the Finder and click It Works… without scanning again: no Save panel, the status line says "<game>: Not installed; It Works… needs Installed", and the row shows Not installed (not tried in the window; the command-line flags refuse the same way).

**Wine Modules**

10. Normal: click the Wine Modules tab and wait for "<n> CrossOver install(s) found."
11. Change CrossOver alert: turn on the switch of a CrossOver *app*, take the picture, then Cancel.
12. All alert: click "All", take the picture, then Cancel.
13. App Management notice: after macOS refused a change, the lock notice shows at the top. Click "Open App Management…" for the System Settings pane.
14. Behind: a row that is on but behind shows "Update" or "Install Again", and "Update All" appears.
15. Module update waiting: set "New Wine modules" to "Ask first" and wait for the agent's daily check. "New Wine modules ready (<n>)" with "Install" appears.

**Game Feel** (needs modules installed in at least one CrossOver)

16. Tab: click the "Game Feel" tab.
17. Every Game's Settings: click "Every Game's Settings…" and take the top, then scroll for "Haptics strength" and "Trigger effects".
18. Effects popover: in that sheet, click "What Each Effect Does…".
19. Try running: connect a DualSense and click "Try for 30 Seconds" under Haptics strength. Without a pad you get "No DualSense or DualSense Edge is connected."
20. Per-game sheet with a preset: click Marvel's Spider-Man 2, F1 23, Nioh 3 or God of War. Change one option to show the blue title or dot and the "Use the Suggested" button, then scroll to "About this game".
21. Make a Report: in a per-game sheet click "Make a Report…" for the Save panel, then the `controller.yml` form in the browser. "Share These Settings…" gives the same with the settings form.
22. It Vibrates: in a per-game sheet click "It Vibrates…" for the Save panel, then the `vibration-works.yml` form, its title and fields filled in from the modules' log of the game's latest session. For the identity's field, play the game once with "Show the pad as a DualShock 4" on.
23. Export: in the Game Feel tab, click "Export…" for the Save panel.

**Report**

24. Tab: click the "Report" tab.
25. Report sheet: click a game. Capture "Looking through the game's folder…", then the findings rows.
26. Symptom picker: open "What goes wrong". Choose "The controller, its haptics or its triggers" to show the Diagnose toggle, or its "turn them on in Wine Modules first" text when there are no modules.
27. Save and open: click "Save the Report and Open an Issue…" for the Save panel, then the `game-report.yml` form.

**Settings**

28. Default: click the "Settings" tab.
29. Agent on: turn on "Run from the menu bar". The battery and Icon options become available.
30. Game Mode: turn on "Game Mode for CrossOver's games" to show its coverage line.
31. Folders and log: expand "Folders searched (<n>)" and expand "Log" after an install.
32. When present: the "Recent" section, "New fixes ready (<n>)", and "<game>: folder gone" with "Stop Keeping It".

**Menu bar, notifications, first launch**

33. Icons: the plain raccoon; the raccoon with its dot; each of "Raccoon and gamepad", "Gamepad" and "Battery only" with a pad connected.
34. Menu: click the menu bar icon with kept games and a pad connected.
35. Notifications: the permission prompt the first time the agent starts, and a failure notification with "Report on GitHub…".
36. First launch: a notarised download's question ("downloaded from the Internet"); for an app that is not notarised, the Gatekeeper dialog, "Right click > Open" on macOS 14, and "Open Anyway" in System Settings › Privacy & Security on macOS 15 and later.

---

## README text that differs from the app

These matter for the guide. The quoted on-screen labels in the code are what users will see.

- The README calls the agent option *Run in the background, from the menu bar*; the label is "Run from the menu bar" (2101).
- The README calls the update choices *Install them automatically / Ask before installing them / Do not look for them*; the picker says "Automatic" / "Ask first" / "Off" (224-229).
- The README's icon choices are "raccoon and a gamepad, a gamepad, or nothing"; the picker says "Raccoon and gamepad" / "Gamepad" / "Battery only".
- The README says *Keep it applied*; the column is titled "Keep", and that phrase only appears in its tooltip and in the menu bar.
- The README says *Install New Wine Modules … in Settings*. In the window, that button ("New Wine modules ready" › "Install") is in the Wine Modules tab, and the agent's own notification also says "Settings".
- The README describes an Update button "for every CrossOver app and NotProton runner". It only appears when a row that is on is behind.
- "Check Now" in the window and "Check for New Fixes" in the menu bar both install a newer catalog right away, whatever the update mode. The README presents them as looking for updates.
