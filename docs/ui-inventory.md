<!-- Working reference for writing the user guide, read at the merge-follow-ups branch, based on 35db64c (MacGameFix 1.5.5): the app's source with that branch's own edits. Strings are quoted from the code; file:line refer to app/, and every line reference was read at that one state. Regenerate it when the UI changes; it is not the guide itself. -->

# MacGameFix 1.5.5: everything a user can see and do

Read from all nine Swift files, the README and the GitHub issue forms the app opens, at the merge-follow-ups branch, based on 35db64c (version 1.5.5, `build-app.sh:40`).

Files read (line references below use these short names):
- `app/MacGameFix.swift`, `MenuBar.swift`, `PadTester.swift`, `Pad.swift`, `Probe.swift`, `Engine.swift`, `GameMode.swift`, `Core.swift`, `Automation.swift`
- `README.md`
- `.github/ISSUE_TEMPLATE/` (`controller.yml`, `game-report.yml`, `game-feel-settings.yml`, `vibration-works.yml`, `game-fix.yml`)
- `app/build-app.sh` and `app/pad-presets.json`

Wherever a quoted string is built from a value, `<…>` stands for that value.

---

## 1. The main window

**The window itself**
- It is a `WindowGroup("MacGameFix")`: default size 1080×760, minimum 720×460 (MacGameFix.swift:2194-2197, 856).
- It starts a game scan when it opens (859).
- When that scan finishes, it looks at the CrossOver installs if it has not yet (348).
- Opening the window removes the dot from the menu bar icon (90-96). If the agent is on, opening it also restarts or re-registers the agent (100-106).
- Closing the last window quits this process (2181). If an install is running, the quit waits for it to finish (2183-2187).

**Tabs, in order** (834-847)

| # | Tab | Shown when | Purpose |
|---|---|---|---|
| 1 | "Games" | always | Install or remove the game fixes |
| 2 | "Wine Modules" | always | The patched Wine modules that go into CrossOver apps and NotProton runners, and their updates |
| 3 | "Game Feel" | only while `padAvailable` | DualSense options for every game and for each game |
| 4 | "Report" | always | Every Steam game on the Mac, to make a report about one that doesn't work |
| 5 | "Settings" | always | Background agent, Game Mode, game-fix updates, recent agent events, folders searched, the log |

- **When Game Feel appears:** at least one CrossOver row must be "Installed" or "Older modules: install again", and that build's modules must include `unix/winebus.so` (577-582).
  - The CrossOver rows are only filled in after the first game scan. So on a Mac that has the modules, the Game Feel tab shows up a few seconds after launch.

**Status line under the tabs, on every tab** (848-851): a small spinner while busy, then `model.status`. The possible texts:
- Scanning games: "Looking for games…", then "No supported game found in these folders." or "<n> game(s) found." (330, 346)
- Install/Remove with nothing to do: "Nothing selected needs installing." / "Nothing selected is installed." (377)
- Installing or removing fixes:
  - "Installing <game> (<i> of <n>)…" / "Removing <game> (<i> of <n>)…" (386)
  - then "Done: <n> game(s)." or "Done, <f> of <n> need attention." (408)
- Scanning CrossOver: "Looking at CrossOver and the NotProton runners…", then "No CrossOver or NotProton runner found." or "<n> CrossOver install(s) found." (768, 775)
- Installing or removing Wine modules:
  - "Installing the modules into <name>…" / "Removing the modules from <name>…", with " (<i> of <n>)…" when there are several (551-552)
  - then "Done." or "<f> of <n> need attention — see the log in Settings." (568)
  - If App Management blocked some installs, this is appended: " <names> needs App Management: see Wine Modules." ("need" for several) (543-545)
- Updates:
  - "Looking for new fixes…" / "Looking for new Wine modules…" (282, 261)
  - then "New fixes installed: catalog <n>." / "New Wine modules installed: catalog <n>." (Automation.swift:533-534)
  - or "The fixes are up to date (catalog <n>)." / "The Wine modules are up to date (catalog <n>)." (Automation.swift:481)
  - or "Could not update: <error>" (270, 291). The error texts are at Automation.swift:430-434: "the release has no <file>", "catalog.json is not signed with MacGameFix's key", "<file> does not match the signed catalog", "the catalog names a file it may not: <file>", "the new fixes need MacGameFix <v> or later".
- Export: "Exported the controller settings of <n> game(s)." / "Could not export: <error>" (753, 755)

---

## 2. Each tab

### 2.1 Games (`GamesView`, MacGameFix.swift:864-1011)

**Header** (917-921)
- Title "MacGameFix".
- Subtitle: "Fixes go into each game's own folder, a few also into its prefix or bottle, one into a macOS game's app, and never change CrossOver. Quit a game before changing its fix." (918)
- Tooltip on the subtitle: "The Windows games' fixes work with CrossOver as it ships, CrossOver Preview, and Steam Play tools such as NotProton."

**Button row** (925-934). All buttons are disabled while busy.
- **"Scan"**: looks through the libraries again and asks each game's installer for its state.
- **"Add Folder…"**: opens a folder picker (multiple folders allowed). Its message is "Choose a Steam library, its steamapps/common folder, or a game folder." (309-320). The chosen folders are saved and a scan runs.
- **"Select All"**: selects every row the current filter shows.
- **"Install Selected"**: installs on the selected rows that are not already "Installed", and skips a selected row waiting for a recipe (375). Its keyboard shortcut is Return (931).
  - When a selected row's fix changes a macOS game's app (Cyberpunk 2077), the "Change <game>'s app?" alert asks first (section 3, L; 380, 415-433). Cancel installs nothing, on any row.
- **"Remove Selected"**: runs the installer with `--restore` on the selected rows that are not "Not installed" (375, 390).
  - A row waiting for a recipe can be selected for this alone (Core.swift:301): Cyberpunk 2077's installer then deletes the copies it kept for the game's earlier builds, and the row stays "No recipe for this build yet", which counts as done (397-398).
- After each run the app asks the installer again, and that answer decides the result. The selection is then cleared (394-404).

**Filter row**
- A segmented picker with hidden label "Show", options **"All" / "Fixed" / "Not fixed" / "All fixes"** (870-872, 938-943). It resets to "All" every time the window opens (867).
  - "Fixed" shows Installed, Older build, Half installed and Needs repair.
  - "Not fixed" shows Not installed, Cannot be fixed here, No recipe for this build yet and Cannot be installed here (888).
  - "All fixes" adds the catalog's games that are not on this Mac (896-900).
- A toggle **"Only the marked games to review (<n>)"** (944-947).
  - It only appears when some kept game needs the user: the agent reported "Failed", "Folder not found" or "Cannot be installed here" (MenuBar.swift:31).
  - When on, only those games are listed.
  - It is already on when the window was opened from the menu bar's "<n> to review…" item (`--review`, MacGameFix.swift:56).
  - A game whose folder is gone has no row, so in practice only "Failed" games show here. This is my inference from the code.
- A count on the right: "<n> fix(es), <m> of their games on this Mac" under All fixes, otherwise "<shown> of <total> game(s)" (949-954).

**Empty state** (956-969)
- One of these lines:
  - "Looking…" while busy
  - "No supported game found yet." when no games were found
  - "No game is fixed yet. Not fixed shows the supported games found." under Fixed
  - "No game here." otherwise
- Below it: "Supported: <every game name>".

**Table columns** (971-1006). The table allows several rows to be selected. A row that is blocked can never be selected, except one waiting for a recipe (909; Core.swift:301).

| Column | Content | Tooltip |
|---|---|---|
| "Game" | Name in bold, symptom below | The folder path, a blank line, then the game's "why" text (978) |
| "Requires" | The requirement note, or "—" | The same note |
| "Status" | The status cell below, or "Not on this Mac" for catalog-only rows | — |
| "Keep" | A checkbox | "Keep it applied: put it back after a game update." (997) |
| "Goes into" | The place cell below, or "—" | See below |

- **Requires** notes are built from these parts (Core.swift:174-197): "runs on DXMT/D3DMetal/DXVK", "needs D3DMetal <v>" or "needs D3DMetal <v> or <v2>", "its videos need <CrossOver>, which ships their codec", "not needed on D3DMetal <v> or later; kept for earlier ones", "needs <CrossOver>; stable CrossOver 26.3 needed MacGameVideoFix's engine, now archived", and for a fix that changes a macOS game's app, first, "macOS app; changes its executable" (Core.swift:176).
- **Keep** checkbox:
  - Checking it saves the game, its folder and its chosen prefixes for the agent (147-158).
  - It is disabled when the row is blocked or the app is busy, except for a row waiting for a recipe: that one can be kept, and the agent installs its fix when a recipe arrives (996; Core.swift:296). A row already kept can always be unchecked, blocked or not.
  - Checking it on a fix that changes a macOS game's app (Cyberpunk 2077) asks first, with the Keep form of alert L; Cancel leaves it unchecked (147-150).
  - Nothing in the window warns that it does nothing while the agent is off.

**Status cell** (`GameStatusCell`, 1015-1039), top to bottom:
1. The state, in colour (Core.swift:219-241):

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
3. In red, why the row is blocked (Core.swift:267-291):
   - "The installer found nothing in this folder for the fix to ride on."
   - "No prefix for this game was found. Run it once with NotProton or CrossOver, then Scan again."
   - "Choose at least one place for its DLLs." (NINJA GAIDEN 3) or "Choose at least one place for its registry keys."
   - "MacGameFix waits for a recipe for the game's build <version> (<build>); a catalog update brings it.", or "… for the game's new build; …" when the installer named no build (Core.swift:271-274). This one is grey, not red (1027), leaves Keep available, and the row can still be selected for Remove. The installer answers this only when its catalog has no row for the game's build.
   - For "Cannot be installed here", and for "Half installed" on a fix that changes a macOS game's app, the installer's own reason, from the "Why:" line of its `--status` (Core.swift:278-283). Cyberpunk 2077's are, with `<build>`, `<chip>` and the Steam sentence filled in: "This executable is not one the recipes for build <build> were made from. In Steam, Properties > Installed Files > Verify integrity of game files should put CD PROJEKT's back, then install here.", "The executable is patched, but not by MacGameFix: no copy of its original is kept. In Steam, … then install here.", "The executable is patched, and the copy MacGameFix kept for this build is not its original. In Steam, … then install here.", and "This Mac has an <chip>. Apple lists MetalFX denoised upscaling for M3 and later, and the game does not ask, so it would offer an option this Mac cannot run." Without a "Why:" line the app says "The installer cannot install the fix here." or "The executable was patched outside MacGameFix; nothing can be installed or removed here."
4. If the agent failed on a kept game: "In the background: <detail, or 'the fix did not take.'>" in orange. When there is a report link, a **"Report on GitHub…"** button follows, which opens the pre-filled issue (1029-1035).

**"Goes into" cell** (`GamePrefixCell`, 1044-1077)
- Fix that changes a macOS game's app (Cyberpunk 2077): "Its app", with the tooltip "Changes the game's executable and signs it again ad hoc; the original is kept in MacGameFix's app-backup folder." (1055-1057).
- Fix that needs no prefix: "Its folder".
  - The code also has an "Its prefix" branch for a game that is in-prefix but needs no prefix. It is probably unreachable, since NG3 needs a prefix. I can't confirm that without games.json.
- Zero or one prefix: plain text with the prefix name or "—".
  - Tooltip: "Registry keys go into <place or 'no prefix found'>." For NG3 it starts "Its DLLs and overrides go into" (Core.swift:151).
- Several prefixes: a **menu** with one checkable item per prefix (1064-1076).
  - Label: "Choose…", the single chosen name, or "<n> places".
  - Tooltip: "<Registry keys go into / Its DLLs and overrides go into>: <names or 'none chosen'>."
  - Checking or unchecking a prefix asks the installer again. If the game is kept, the new set is saved for the agent (164-178).
- Prefix names (Core.swift:208-213): "Steam Play prefix (<appid>)" and "CrossOver bottle “<name>”". Two bottles with the same name get " (<parent>/<root>)" appended (1048-1052).

### 2.2 Wine Modules (`EngineView`, 1083-1167)

**1. App Management notice.** This section only appears while macOS has refused a write to a CrossOver app (1088-1105).
- A lock-shield label: "macOS does not let MacGameFix change <app names>."
- Caption: "Turn MacGameFix on in System Settings › Privacy & Security › App Management, then check again. Releases signed with MacGameFix's Developer ID are expected to keep this permission across updates; the first update from a release made before the Developer ID, or a build not signed with it, may need it turned on again." Expected, not measured: macOS keeps the permission for the app's designated requirement, which with the Developer ID is the bundle identifier and the team, the same in every release; signed ad hoc, it is the build's own hash, so the first update from an ad hoc release to a Developer ID one changes it.
- **"Check Again"**: tries the write again on each CrossOver app that is on or was refused (526-530).
- **"Open App Management…"** (Return): opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles` (532-536).
- How the refusal happens: the app creates and deletes `lib/wine/.macgamefix-access` inside the app (507-513). This runs once per launch for CrossOver apps that are on (787-791), and before every install or removal in a CrossOver app (541).

**2. Main section**
- Header: "The DualSense's haptics and triggers, on a cable and over Bluetooth".
- Caption: "On installs the Wine modules into that CrossOver; off puts CrossOver's own back."
- Header tooltip: "Unlike the game fixes, these go into CrossOver itself. Quit that CrossOver's games first. In a CrossOver app, macOS asks to allow MacGameFix under App Management, and the app is signed again ad hoc." (1128-1136)
- Footer: "Only a CrossOver of a build and Wine the modules were built for can be turned on." (1138)

One row per CrossOver app (in /Applications and ~/Applications) and per NotProton runner (`EngineSwitch`, 2006-2035):
- **Name**, for example "CrossOver Preview 20261006", "CrossOver 26.3", or "NotProton runner · CrossOver Preview 20261015". Copies with the same name get " (<app or runner folder>)" (Engine.swift:122, 134, 139-144).
- **Caption**: "<build> · <state>", or "<build> · no modules for this build" when no modules exist (2015-2016).
  - States (Engine.swift:41-57): "…", "Installed" (green), "Older modules: install again" (orange), "Partly installed" (orange), "Not installed", "No modules for this build yet".
  - After a failed run, an orange "Failed — see the log in Settings" is added (563).
- **"Update"** (state Older modules) or **"Install Again"** (Not installed or Partly installed). These only appear when the switch is on but the modules are behind (760-762, 2024-2027).
- **Switch**: on installs the modules, off removes them (470-474).
  - Turning on a CrossOver app first shows the "Change CrossOver itself?" alert (section 3). Turning on a runner, or turning anything off, shows no question.
  - The switch is disabled while the state is "…", when there are no modules, or while busy (465, 2031).
  - Row tooltip: the install's root path (2033).

Below the rows:
- Empty state: "Looking…" or "No CrossOver or NotProton runner found." (1108-1110)
- Toggle **"New CrossOver builds too"** (default on). Tooltip: "With updates on Automatic: when NotProton adds a runner for a new CrossOver build and there are modules for it, they go there too, once a runner that is on has them." (1111-1115)
- Buttons, all disabled while busy (1116-1127):
  - **"All"** / **"None"**: each shows a confirmation alert, then installs into or removes from every row that has modules and is not already in that state.
  - **"Update All"**: only appears when some row is behind. Tooltip: "Brings the modules up to date in every CrossOver that is on and behind."
  - **"Look Again"**: scans the CrossOver installs again.

**3. "Updates" section** (1142-1162)
- Picker **"New Wine modules"**: **"Automatic" / "Ask first" / "Off"** (224-229). The default is Automatic (Automation.swift:66-67).
  - Tooltip: "New Wine modules from GitHub, on their own, once a day. On Automatic they also go back into the runners that are on after a CrossOver or NotProton update. “Ask first” checks the signature and tells you. A CrossOver app is only ever reported."
- **"New Wine modules ready (<n>)"** with an **"Install"** button, in orange. It only appears after the agent, in Ask first mode, found and verified a newer catalog.
- **"Catalog"**: the version number, with tooltip "Modules for: <CrossOver list>", and a **"Check Now"** button.
- Important: "Check Now" and "Install" both call `checkForModules` (258-277). That downloads and installs a newer modules catalog right away. It is not just a check.
  - Getting a new catalog does not change any CrossOver. The rows then show "Older modules: install again", along with "Update" and "Update All".

### 2.3 Game Feel (`ControllersView`, 1355-1449)

**Top area** (1373-1383)
- "Every game" (headline), with a summary of the global options below, joined by " · ".
  - On first run this starts "Bluetooth as a cable · full motor power · Edge shown as an Edge · DualSense haptics 1× on a cable · …" and is cut to two lines (Pad.swift:155-180, 60-64).
- **"Every Game's Settings…"** opens the global sheet.
  - Tooltip: "What every game gets unless it has settings of its own: the connection, XInput, the haptics' strength and the trigger effects, each with a thirty-second try."

**"Per game" area** (1390-1395)
- A **"Search"** field: matches part of a name (any case) or an exact app ID (1366).
- **"Look Again"**: reads the Steam games and the modules' log again, and asks the Steam store about games it hasn't asked about yet (585-613).
- **"Export…"**: tooltip "The settings and what was seen of each game, to share. No paths or accounts."

**Table** (1397-1407). A single click on a row opens that game's sheet (1408-1410).
- **"Game"**: Steam cover and name. The name is in the accent colour when the game has options of its own.
- **"Settings"**: "As every game", or the differences joined by ", ".
  - " (suggested)" is added when the difference comes from a preset, or from the Steam-store rule ("an XInput controller"), rather than from the user (1440-1444).
- **"Seen"**: what the modules logged the game doing: "haptics as audio", "rumble motors", "rumble through XInput", "trigger effects", "sets the motor power", "played over Bluetooth" (Pad.swift:282-291).
- Covers come from Steam's `appcache/librarycache/<appid>/library_600x900.jpg` or `header.jpg`. A grey tile with a gamepad stands in where Steam has none (1748-1793).

**Footer** (1411-1426)
- "No Steam game found." / "No game matches." / "<n> game(s)".
- A **"Show"** picker with 15/25/50/100, tooltip "How many games a page shows.", saved in UserDefaults under `gameFeelPerPage`.
- Back and forward chevrons, and "Page <x> of <y>".

### 2.4 Report (`ReportView`, 1171-1246)

- Header (1189-1192): "A game that does not work", with this caption: "Click it. MacGameFix looks at what the game is made of, without changing anything in it, and walks you through a report for an issue on GitHub, which is where it gets fixed. The report names that game alone."
- A **"Search"** field (name or app ID) and **"Look Again"**, which reads the Steam games and the catalog again (1200-1202).
- Table (1204-1218). A single click opens the Report sheet (1219-1221).
  - **"Game"**: cover and name.
  - **"Runs in"**: the prefix and bottle names, or "—".
  - **"MacGameFix"**: "Has a fix" or "—".
- Footer: the same count texts as Game Feel, plus the "Show" picker (15/25/50/100, no tooltip, saved under `reportPerPage`), chevrons and "Page x of y" (1222-1236).
- The list is every Steam appmanifest whose install folder exists, except app 228980 (Probe.swift:21-41).

### 2.5 Settings (`SettingsView`, 2039-2163)

**"Background"** (2044-2069)
- **"Run from the menu bar"**: installs or removes the LaunchAgent (211-218).
  - Tooltip: "MacGameFix starts when you log in and stays in the menu bar. Every two minutes it puts back the fix of a game marked “Keep it applied” after Steam updates or verifies it, once the game is closed."
  - If the agent can't be started, the error goes to the Log, not to an alert: "Could not start the agent: …" (213).
- **"Show the controller's battery"**: default on. Disabled while the agent is off.
  - Tooltip: "Beside the raccoon in the menu bar: a gamepad and the battery left in a connected controller, the lowest if there are several. The menu lists each one."
- **"Icon"** picker: **"Raccoon and gamepad" / "Gamepad" / "Battery only"**. Disabled unless the agent is on and the battery option is on.
  - Tooltip: "What stands beside the battery in the menu bar. With no controller connected, the gamepad stays if it is chosen; otherwise the raccoon shows."
- For each kept game whose folder is gone: "<name>: folder gone" in orange, with a **"Stop Keeping It"** button that removes the game from the kept list (2062-2068).

**"Game Mode"** (2071-2087)
- Toggle **"Game Mode for CrossOver's games"** (default off).
  - Tooltip: "macOS turns Game Mode on for a game in full screen whose app says it is a game. A game in CrossOver runs from a copy of Wine that does not say so; with this on, it runs from one that does, kept in MacGameFix's folder. CrossOver itself is not changed, and turning this off takes it all away."
- When on, a coverage line follows (GameMode.swift:266-277): "For <CrossOver name> (Intel and FEX), …." or "No CrossOver of a release this was checked with: 26.1, 26.3, Preview 20261006 or 20261015."
  - The line only fills in after the toggle is flipped, or after a CrossOver scan with Game Mode on (195-199, 777-782).
- Footer: "Play in full screen: the green button, or Control-Command-F. Game Mode also doubles what a wireless controller's Bluetooth link carries, which a DualSense's haptics need."

**"Game fix updates"** (2089-2111)
- Picker **"Game fixes"**: "Automatic" / "Ask first" / "Off" (default Automatic).
  - Tooltip: "New fixes from GitHub, looked for once a day. “Ask first” checks the signature and tells you; nothing is installed until you say so."
- **"New fixes ready (<n>)"** with **"Install"**, in orange, when one is waiting.
- **"Catalog"**: the version and **"Check Now"**. As in Wine Modules, this downloads and installs a newer catalog, then scans the games again (279-298).
- Footer: "The Wine modules have their own, in Wine Modules."

**"Recent"**. Only shown when the agent has recorded events (2113-2129).
- Up to 5 of the newest events, as "<game>: <message>" (orange if it failed), with the abbreviated date.
- A **"Report…"** button when the event has a report link.

**"Games"** (2131-2146)
- A disclosure group **"Folders searched (<n>)"** listing every library path. The ones the user added have a **"Remove"** button.
- **"Add Folder…"**, the same as on the Games tab.

**"Log"**, a disclosure group (2148-2158)
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

**D. Report sheet.** Opened by clicking a game in the Report tab (`ReportSheet`, 1250-1350).
- **Header**: a large cover and the name, then:
  - "Steam app <id>. Runs in: <places>." or "Steam app <id>. No prefix or bottle found beside its library."
  - "MacGameFix has a fix for it in Games: <fix>." or "MacGameFix has no fix for it yet."
- **Picker "What goes wrong"** (Probe.swift:493-500):
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
  - Then these rows: "Main executable", "Graphics", "Engine", "Controller", "Video", "Middleware", "Anti-cheat". Values can be "none found" or "not recognised" (Probe.swift:169-178).
  - Footer: "Read from the game's folder alone; nothing in it was changed."
- **"2. Before you make the report"**: numbered steps that depend on the symptom. The full text is at Probe.swift:505-532.
  - For "The controller, …" there is also a **"Diagnose this game"** toggle, with tooltip "The Wine modules log what this game writes to the pad, from its next start. Turn it off again afterwards."
  - If Game Feel isn't available, that toggle is replaced by "The Wine modules are in no CrossOver yet: turn them on in Wine Modules first." (1305-1316)
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
- After saving, the file is shown in Finder and the browser opens a GitHub issue form, pre-filled (Pad.swift:676-720, MacGameFix.swift:639-642, 648-673, 728-732):

  | Button | Form | Pre-filled fields |
  |---|---|---|
  | Save the Report and Open an Issue… | `game-report.yml` | title "[Game] <name>", game "<name> (Steam app <id>)", what "<symptom>. " |
  | Make a Report… | `controller.yml` | title "[Controller] <name>", game |
  | Share These Settings… | `game-feel-settings.yml` | title "[Settings] <name>", game, settings = the key=value lines |
  | It Vibrates… | `vibration-works.yml` | title "[Vibrates] <name> · <controller> · <connection> · shown as a <identity>", each part after the name only when the modules' log has a single one for the game's latest session, the identity only with a single controller too (`PadSession`, Pad.swift:723-752); game; controller ("DualSense" or "DualSense Edge"); connection ("Cable" or "Bluetooth"); shown-as ("DualShock 4" or "DualSense", when the pad was shown as another); seen; library ("Sony libScePad", "SDL", "Raw HID", "XInput" or "DirectInput", guessed from the game's folder: "Sony libScePad" whenever it ships Sony's library, Probe.swift:137-149); settings |

- If the user cancels the Save panel, no issue opens.

**F. "Every Game's Settings…" sheet** (`PadGlobalSheet`, 1820-1876)
- Section header "Every game", with this caption: "The Wine modules read these when a game starts; in CrossOver, when Steam or the game opens the bottle, so make a change before you open it there, or quit and open it again. The haptics' strength is read each time a game starts its haptics. A game's own settings win, and so do its suggested ones."
- Option rows. Each has a caption that is always visible (1490-1552):
  - Toggle **"Bluetooth as a cable"**
  - Toggle **"Full motor power on the Edge"**
  - Toggle **"Show the Edge as a standard DualSense"**
  - Picker **"XInput"**: "Off" / "Its rumble on the motors" / "The pad as an XInput controller". Its caption changes with the choice (1490-1507).
  - Toggle **"Rumble on the haptic actuators"**
- Toggle **"Diagnostics in the modules' log"**. Tooltip: "What a game writes to the pad and reads from it, and a level meter of its haptics, in /tmp/macgamefix-<uid>/pad.log."
- **"Haptics strength"**: a grid with columns "DualSense" and "DualSense Edge" and rows "Cable" and "Bluetooth". Each cell is a picker with 1×, 1.5×, 2×, 2.5×, 3×. Each cell has its own tooltip, for example "A standard DualSense on a cable." (1719-1745). A haptics try row follows.
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

**G. Popover "What each effect does"** (1577-1610)
- A table with columns "Effect", "How it feels", "Suits", "Default strength". The row texts are at 1561-1574.
- Two notes under it:
  - "While the other is pressed: a second effect that replaces a trigger's own while the other trigger is held, a weapon on R2 while L2 aims, say. The other counts as pressed from about a sixth of its travel."
  - "Strength runs from 1, light, to 8, the pad's strongest; Default is each effect's own. The pad keeps an effect until something else is written: the Wine modules release the triggers when the game's Wine stops, or when the next game starts."

**H. Per-game Game Feel sheet.** Opened by clicking a game in Game Feel (`PadGameSheet`, 1880-2002).
- **Header**: a cover and the name, then:
  - "In blue, or marked with a dot, what is this game's own; the rest follows every game's." If the game has a preset, the end reads "the suggested settings, then every game's."
  - "They apply under NotProton, from the game's next start. A CrossOver bottle does not tell the modules which game runs, so there every game's settings apply."
- **Options**: the same option rows, haptics grid, trigger grid and both try rows as sheet F.
  - One row is here alone, after "Show the Edge as a standard DualSense": toggle **"Show the pad as a DualShock 4"**, with the caption "For a game whose controller code knows only the PS4 pad, such as Mortal Kombat 11, which vibrates through it (played on 2026-10-22). The pad is shown to the game as a DualShock 4 on a cable, over Bluetooth too." (1532-1539). It writes `pad_as=dualshock4`, `bluetooth=wired`, `edge=edge` and an XInput line to the game's `pad.d/<appid>.conf`, whatever the Bluetooth and Edge rows held: `edge=edge` so that every game's `edge=dualsense` does not name the pad's audio device a DualSense's, and `xinput=off`, or `xinput=rumble` when the picker below says so (PadOptions.ds4XInputRumble); turned off again, the `pad_as` line goes and the Bluetooth and Edge rows' values come back (Pad.swift:107-148). Sheet F never shows it, and every game's settings never carry it (Pad.swift:471-473).
  - While it is on, "Bluetooth as a cable" shows on and "Show the Edge as a standard DualSense" shows off, both greyed out (1467, 1510-1531); the Bluetooth caption reads "On while the pad is shown as a DualShock 4: the game sees a DualShock 4 on a cable." and the Edge caption "Off while the pad is shown as a DualShock 4: the game sees a DualShock 4, whichever pad it is." The "XInput" picker offers "Off" and "Its rumble on the motors" only, the game's own choice (Off unless asked; 1481-1488, 1540-1544), with the captions "XInput gets nothing. A game that rumbles through the DualShock 4, as Mortal Kombat 11 does, needs nothing more." and "For a game that shows PlayStation buttons through the DualShock 4 but rumbles only through XInput: its rumble goes to the motors. No game played has vibrated through it: Crysis 2 Remastered, played with it on 2026-10-22, sent XInput no rumble." (1490-1498). The "Full motor power on the Edge" caption reads "Shown as a DualShock 4, the game cannot set the motor power: a DualShock 4 has none. This claims it at full for either pad." (1519-1520). The table's "Settings" column says "shown as a DualShock 4", drops the Bluetooth and Edge words, and gives XInput as "XInput's rumble" or "no XInput" (Pad.swift:155-180).
  - The game's own values show as accent-coloured titles, or with a small dot.
  - Setting a value back to what the game would get anyway stops it being the game's own (1892-1905).
  - There is no Diagnostics toggle and no "Measured with" line here.
- **"About this game"** (1943-1985)
  - Toggle **"Diagnose this game"**. Tooltip: "The Wine modules log what this game writes to the pad, the haptics' levels and delays, for this game alone, from its next start."
  - **"It Vibrates…"** (1950-1953). Tooltip: "Saves this game's report and opens a new issue on GitHub that says it vibrates, with the controller, the connection and what the pad was shown to the game as, as the Wine modules saw them, for the list of games played for vibration." It opens the `vibration-works.yml` form (section 3, E).
  - **"Share These Settings…"**. Tooltip: "Saves this game's report and opens a new issue on GitHub with these settings in it, to attach it to."
  - **"Make a Report…"**. Tooltip: "Saves this game's report and opens a new issue on GitHub to attach it to."
  - Three captions (1960-1969): "To report a problem: turn on Diagnose, play the moment that goes wrong, close the game, then make a report and attach it to the issue that opens. …", "If these settings feel right, share them the same way: shared settings that a report backs become this game's suggested ones for everyone." and "If it vibrates, say so the same way, once for each controller and connection you played: a game's report that it vibrates adds it to the list of games played for vibration."
  - Info lines:
    - "Suggested: <summary>. <measured note>" when a preset exists. Presets exist for God of War 1593500, F1 23 2108330, Nioh 3 3681010 and Marvel's Spider-Man 2 2651280 (pad-presets.json).
    - One of: "The Steam store lists it as supporting the DualSense.", "The Steam store does not list it as supporting the DualSense, so it gets the pad as an XInput controller.", or "Not asked of the Steam store yet."
    - "Seen: …." when something was seen.
    - "Steam app <id>".
- **Bottom bar**
  - When the game has options of its own: **"Use Every Game's"** (no preset) or **"Use the Suggested"** (preset). Either one clears the game's own options (1989-1993).
  - **"Done"** (Return). Closing the sheet stops any running try.

**I. Export Save panel.** From "Export…" in Game Feel.
- Suggested name "MacGameFix controllers.json", JSON only, no default folder set (746-757).
- Contents: the global options and, for each game, the app ID, name, options that differ, what was seen, and the preset note (Pad.swift:588-615).

**J. Try rows.** These are inline in sheets F and H, not separate windows (`PadTryRow`, 1797-1817; PadTester.swift).
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

**K. Agent notifications.** These come from the menu-bar agent, not the window (Automation.swift:666-698).
- Title is the game name or "MacGameFix". Body is the event message (all messages are in section 5).
- A failure has the action **"Report on GitHub…"**. It opens `issues/new` with the title "<game>: <problem>" and a body containing Game, What happened, the MacGameFix version and catalog, the macOS version, and the installer's last 60 lines with home, user name and serial number removed.
- That link uses no template, so it opens GitHub's blank issue form (Automation.swift:611-639).

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
- Unclear from the code: File › New Window (⌘N) probably opens a second, independent window with its own scan and its own log, since each window creates its own model (829).

**Keyboard shortcuts.** Only Return, as the default button:
- "Install Selected" (Games, 931)
- "Open App Management…" (1101)
- "Done" in the Report sheet, the Every Game's Settings sheet and the per-game sheet (1340, 1869, 1995)

The "Control-Command-F" in the Game Mode footer is advice for full screen in games, not an app shortcut.

**Command-line flags**, all in one binary (2207-2423):
- `--agent`: the menu bar agent
- `--review`: opens the window with only the games to review
- One-off commands that print or write and then exit: `--agent-once`, `--menu-report`, `--pad-write`, `--pad-export <file>`, `--pad-report`, `--games-report` (named in the README), `--game-mode-keep|--game-mode-remove|--game-mode-report`, `--engine-report`, `--pad-game-report <appid> <path>`, `--probe-report <appid> <path> [symptom]`, `--probe-games`, `--pad-share-url <appid>`, `--pad-vibrates-url <appid>`, `--engine-install|--engine-remove <root>`, `--update-from <dir> [--pubkey --kind modules]`, `--new-signing-key <file>`, `--make-catalog <out> --key <file> [--from]`

**Background agent** (`--agent`)
- It is a LaunchAgent with label `io.github.macgamefix.agent`. It starts at login and restarts only after a crash (Automation.swift:703-723).
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
| `pad-exes.conf` | Exe name to app ID, for CrossOver bottles (Pad.swift:763-829) |
| `GameMode/<app> <build> <arch>/CrossOver Game.app` and `GameMode/scan.json` | Game Mode's helper apps (GameMode.swift:37, 61-64, 212) |

**Other locations**
- `~/Library/LaunchAgents/io.github.macgamefix.agent.plist`: the agent's job (Automation.swift:705).
- `~/Library/Logs/MacGameFix-agent.log`: the agent's output (Automation.swift:711).
- `/tmp/macgamefix-<uid>/pad.log`: the Wine modules' log. The modules write it; the app reads it. It can be moved with `MACGAMEFIX_PAD_LOG`, and it is emptied on restart (Pad.swift:459-462, 561).
- `$TMPDIR/winetemp-*/<exe>`: Game Mode's links, which turning Game Mode off removes (GameMode.swift:78-83, 280-291).
- Inside each game folder and prefix: whatever that game's installer puts there. Spider-Man 2's tools are cached in `~/Library/Caches/MacGameVideoFix` (README:371-377).
- Reports: wherever the user saves them, ~/Downloads by default. The export goes wherever the user saves it.
- App preferences (domain `io.github.macgamefix`): `extraFolders`, `reportPerPage`, `gameFeelPerPage`.

**Network.** Users may want to know about these:
- The GitHub API at `releases/latest`, for catalog checks.
- Steam's public store API, once per installed game, to learn whether it lists the DualSense: `https://store.steampowered.com/api/appdetails?appids=<id>&filters=categories` (Pad.swift:389). It runs from Game Feel and from the agent.

**Permission prompts**
- **App Management**
  - Triggered by any install or removal of modules in a CrossOver *app*, by the once-per-launch check, and by "Check Again".
  - macOS shows its own notification; its text is not in the code. The comment at 784-786 says the app deliberately shows no alert of its own.
  - The app's own texts about it are the "Change CrossOver itself?" alert (B) and the Wine Modules notice (2.2).
  - NotProton runners need no App Management (508).
  - Installing or removing Cyberpunk 2077's fix writes into the game's app and may meet the same refusal. The app does not probe for it; the installer says "macOS did not let MacGameFix change <app>." and points to App Management, in Settings › Log.
- **Notifications**: the agent asks for alert permission when it starts (Automation.swift:676). The prompt is macOS's standard one.
- **Game Mode helper apps**: they declare microphone and camera usage texts, which a game running from them could trigger: "This game would like to access your microphone." and "This game would like to access your camera." (GameMode.swift:110-111).
- **First launch**: a notarised download is expected to open after macOS's usual question for an app from the internet; not measured, since no MacGameFix build has been notarised so far. One that is not notarised (the releases signed ad hoc, before the Developer ID, or a build without one) is blocked by Gatekeeper. The README says "Right click > Open" once on macOS 14 and, from Apple's notes, "Open Anyway" in System Settings › Privacy & Security on macOS 15 and later, which has not been tried with MacGameFix (README:520-530).
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

**Wine Modules**

9. Normal: click the Wine Modules tab and wait for "<n> CrossOver install(s) found."
10. Change CrossOver alert: turn on the switch of a CrossOver *app*, take the picture, then Cancel.
11. All alert: click "All", take the picture, then Cancel.
12. App Management notice: after macOS refused a change, the lock notice shows at the top. Click "Open App Management…" for the System Settings pane.
13. Behind: a row that is on but behind shows "Update" or "Install Again", and "Update All" appears.
14. Module update waiting: set "New Wine modules" to "Ask first" and wait for the agent's daily check. "New Wine modules ready (<n>)" with "Install" appears.

**Game Feel** (needs modules installed in at least one CrossOver)

15. Tab: click the "Game Feel" tab.
16. Every Game's Settings: click "Every Game's Settings…" and take the top, then scroll for "Haptics strength" and "Trigger effects".
17. Effects popover: in that sheet, click "What Each Effect Does…".
18. Try running: connect a DualSense and click "Try for 30 Seconds" under Haptics strength. Without a pad you get "No DualSense or DualSense Edge is connected."
19. Per-game sheet with a preset: click Marvel's Spider-Man 2, F1 23, Nioh 3 or God of War. Change one option to show the blue title or dot and the "Use the Suggested" button, then scroll to "About this game".
20. Make a Report: in a per-game sheet click "Make a Report…" for the Save panel, then the `controller.yml` form in the browser. "Share These Settings…" gives the same with the settings form.
21. It Vibrates: in a per-game sheet click "It Vibrates…" for the Save panel, then the `vibration-works.yml` form, its title and fields filled in from the modules' log of the game's latest session. For the identity's field, play the game once with "Show the pad as a DualShock 4" on.
22. Export: in the Game Feel tab, click "Export…" for the Save panel.

**Report**

23. Tab: click the "Report" tab.
24. Report sheet: click a game. Capture "Looking through the game's folder…", then the findings rows.
25. Symptom picker: open "What goes wrong". Choose "The controller, its haptics or its triggers" to show the Diagnose toggle, or its "turn them on in Wine Modules first" text when there are no modules.
26. Save and open: click "Save the Report and Open an Issue…" for the Save panel, then the `game-report.yml` form.

**Settings**

27. Default: click the "Settings" tab.
28. Agent on: turn on "Run from the menu bar". The battery and Icon options become available.
29. Game Mode: turn on "Game Mode for CrossOver's games" to show its coverage line.
30. Folders and log: expand "Folders searched (<n>)" and expand "Log" after an install.
31. When present: the "Recent" section, "New fixes ready (<n>)", and "<game>: folder gone" with "Stop Keeping It".

**Menu bar, notifications, first launch**

32. Icons: the plain raccoon; the raccoon with its dot; each of "Raccoon and gamepad", "Gamepad" and "Battery only" with a pad connected.
33. Menu: click the menu bar icon with kept games and a pad connected.
34. Notifications: the permission prompt the first time the agent starts, and a failure notification with "Report on GitHub…".
35. First launch: a notarised download's question ("downloaded from the Internet"); for an app that is not notarised, the Gatekeeper dialog, "Right click > Open" on macOS 14, and "Open Anyway" in System Settings › Privacy & Security on macOS 15 and later.

---

## README text that differs from the app

These matter for the guide. The quoted on-screen labels in the code are what users will see.

- The README calls the agent option *Run in the background, from the menu bar*; the label is "Run from the menu bar" (2045).
- The README calls the update choices *Install them automatically / Ask before installing them / Do not look for them*; the picker says "Automatic" / "Ask first" / "Off" (224-229).
- The README's icon choices are "raccoon and a gamepad, a gamepad, or nothing"; the picker says "Raccoon and gamepad" / "Gamepad" / "Battery only".
- The README says *Keep it applied*; the column is titled "Keep", and that phrase only appears in its tooltip and in the menu bar.
- The README says *Install New Wine Modules … in Settings*. In the window, that button ("New Wine modules ready" › "Install") is in the Wine Modules tab, and the agent's own notification also says "Settings".
- The README describes an Update button "for every CrossOver app and NotProton runner". It only appears when a row that is on is behind.
- "Check Now" in the window and "Check for New Fixes" in the menu bar both install a newer catalog right away, whatever the update mode. The README presents them as looking for updates.
