# MacGameFix

Fixes for Windows games on a Mac that go into the game's own folder, and the
small macOS application that installs, checks and removes them. One more is
for a macOS game: it turns on the MetalFX denoiser that Cyberpunk 2077 ships
and leaves off, by changing the game's own app.

None of them changes CrossOver. The Windows games' fixes work with CrossOver as
CodeWeavers ships it, with CrossOver Preview, and with Steam Play tools for
macOS such as [NotProton](https://github.com/NotProtonNot/NotProton): a proxy
DLL beside the game, and for a few titles registry keys in the game's own
prefix. One, NINJA GAIDEN 3: Razor's Edge, puts its DLLs in that prefix instead.

This repository is where the fixes live now. They started in
[MacGameVideoFix](https://github.com/MathiasKowoll/MacGameVideoFix), which also
patched CrossOver itself: staged GStreamer codecs, its own `winegstreamer`, a
controller bus. That project is archived. On CrossOver Preview 27 none of the
games here needs anything in the engine (for three of them that is read off how
the fix works rather than run; see "Measured, and what was not"), so the work
that is still alive is the DLLs and their installers, and that is what moved
here. The history of every fix, and the engine work, stays in the
archived repository.

## What is in this repository

| Folder | What it holds |
| --- | --- |
| `app/` | The application: `Core.swift` (installers, games, libraries), `Engine.swift` (the Wine modules), `Pad.swift` (the Game Feel tab's options and what it writes for the modules), `Probe.swift` (the Report tab: what a game is made of, and its report), `pad-presets.json` (options measured per title), `Automation.swift` (the background agent, signed catalog updates, reports), `MenuBar.swift` (the agent's menu bar item), `MacGameFix.swift` (the window), `AppIcon.icon` (the icon); `build-app.sh` and `test-automation.sh`. |
| `fixes/` | One installer per fix (`install-*.sh`), the DLLs they put in place, Cyberpunk 2077's recipe for each build of the game (`cp2077-denoiser.recipes`), the C source of each DLL and the scripts that build them (`build-proxy.sh`, `build-asf-reader.sh`, `check-builds.sh`), and the third-party notices. |
| `process-features.json` | The table: per game executable, its symptom, backend, toolkit, codec and engine needs. The app is built from it. |
| `tools/` | The probes and capture scripts the fixes were found with: video and Media Foundation observers, HID traces, a game survey. |
| `engine/` | Not a game fix: four patched Wine modules that go into CrossOver itself, so that games find a DualSense's haptic output on a cable, and take the pad on Bluetooth as the same pad on a cable. The built modules per CrossOver build, their installer (`engine-modules.sh`), the patches and `build.sh`; see [`engine/README.md`](engine/README.md). The app's Wine Modules tab installs them. |
| `legacy/` | What MacGameVideoFix's wiki and notes found, per game and in general (`legacy/wiki/Findings.md`, `legacy/wiki/Diagnosing-a-new-game.md`). Kept as written; some pages describe the engine work that stayed behind. |

## What it does

- **Finds the games.** It reads the libraries of the native macOS Steam (where a
  Steam Play tool installs Windows games), the libraries of the Steam inside
  each CrossOver bottle, and any folder you add. Only the supported games below
  are ever shown; nothing else in your libraries is named.
- **Says what is installed**, for each game, by asking that game's installer.
- **Installs or removes** the fix for one game or several at once. Removing puts
  the game's own files back.

Quit a game before installing or removing its fix.

The window has four tabs, and a fifth once the Wine modules are in a CrossOver:
**Games**, the fixes above, in a table: each game's symptom, what its fix requires, its state, *Keep*
and where a fix that writes registry keys goes, shown *All* (every supported game on this Mac),
*Fixed*, *Not fixed*, or *All fixes*, which adds the fixes for games that are not on this Mac;
**Wine Modules**, the one part that changes CrossOver
itself (patched Wine modules for a DualSense's haptics on a cable, the pad on
Bluetooth as if on a cable, and XInput, see [`engine/README.md`](engine/README.md)), with a
switch and an Update button for every CrossOver app and NotProton runner, and
the modules' own updates; **Game Feel**, the DualSense's options for every game
and, in a table of the Steam games on this Mac, for each one, with what the
modules saw each game do; **Report**, for a game that does not work (see
[Reporting a problem](#reporting-a-problem)); and **Settings**, with the background agent, the game
fixes' updates, the folders searched and the log.

## What each fix requires

A fix goes into the game's own folder, and the same folder serves every
place that runs the game: a NotProton runner, a CrossOver bottle, or both.
Where you run it is yours to check. The app says beside each game what its fix
requires: the graphics backend it was made for (D3DMetal or DXMT; God of War's
needs `CX_GRAPHICS_BACKEND=dxmt`), and for some games a CrossOver or D3DMetal
version.

Some fixes are not needed from a D3DMetal version on (CONTROL Resonant,
Mortal Shell 2, Resonance: A Plague Tale Legacy and both Life is Strange titles
from 4.0b3). The game says so. It is only a notice: the fix still installs.

The exception is a fix that also writes registry keys: the Kingdom Hearts
titles and NieR Replicant, and NINJA GAIDEN 3: Razor's Edge, whose DLLs go
there too and nothing into its folder. Those keys go into the game's prefix, a
Steam Play prefix (`compatdata/<appid>/pfx`) or a CrossOver bottle, so the game
needs to have run there once. The prefix is shown in the game's *Goes into* column. When there is
more than one, that column is a menu where any number of them can be checked, and the fix goes into
every prefix checked: the installer runs once for each. Two bottles of the same name are told apart by
their folder. Unchecking a prefix does not take the fix out
of it; removing the fix with it checked does.

Cyberpunk 2077's is the one fix for a macOS game. No Wine runs the game, and
nothing goes into its folder: the fix changes the game's own app, and it needs
an M3 or later. Its *Requires* column says "macOS app; changes its executable",
and *Goes into* says "Its app". See
[its section](#cyberpunk-2077-changes-four-bytes-of-its-app).

`MacGameFix --games-report` prints the same in a terminal.

## Keeping fixes applied, and new fixes

From version 1.4.0 the app can look after the fixes by itself. All of it is off
until you turn it on, and the fixes stay in the games' own folders as before.

- **Keep it applied.** Mark a game with *Keep it applied*, and turn on *Run in
  the background, from the menu bar*. That starts a small agent (a LaunchAgent,
  `io.github.macgamefix.agent`) that starts when you log in and looks at the
  marked games every two minutes. When Steam updates or verifies a game and its
  fix is gone, the agent installs it again. It waits until the game is closed
  and Steam has finished writing it. A fix made for each build of the game,
  Cyberpunk 2077's, waits after an update for a catalog that carries a recipe
  for the new build, and is installed when one arrives. When its installer
  will not install it, on an app changed outside MacGameFix or a Mac it is not
  for, the agent says why once for that build, runs nothing, and reports no
  failure.
- **The menu bar.** The agent lives there as a raccoon. Its menu is a summary,
  however many games are marked: how many fixes are in place, to review,
  waiting for a recipe, or not looked at yet. A count you can act
  on opens the window on those games; the window has the detail. The menu also
  looks at every game or for new fixes on demand.
  - A dot by the raccoon's ear means something new to look at: new fixes or a
    fix that failed. It goes away when you open the window.
  - With a controller connected, its battery shows beside the raccoon (the
    lowest of several), and the menu lists each one. Settings chooses what
    stands beside it: the raccoon and a gamepad, a gamepad, or nothing.
  - *Quit MacGameFix* stops the agent, and closes the window if it is open,
    until you log in again or open the app. If it crashes, it starts again by
    itself.
- **New fixes and new Wine modules.** The agent looks at the latest release of
  this repository once a day. A release carries two catalogs, each signed and
  versioned on its own: the game fixes (the installers and every file they use)
  and the Wine modules. New modules for a new CrossOver build come without
  touching the fixes, and the other way round. Each has its own choice: *Game
  fixes* in Settings, *New Wine modules* in Wine Modules:
  - *Install them automatically*: the agent takes the catalog without a new app.
  - *Ask before installing them*: the agent checks the catalog's signature and
    tells you, and installs nothing. *Install New Fixes* or *Install New Wine
    Modules*, in the menu bar or in Settings, takes it.
  - *Do not look for them*: the agent does not ask the releases.

  Wine Modules lists every CrossOver app and NotProton runner, by its release
  ("CrossOver Preview 20261015"), with a switch, and *All* and *None*. The switch
  is the action: on installs the modules there, off puts CrossOver's own files
  back. Only a CrossOver of a build and Wine the modules were built for can be
  turned on; the others say so. Turning on a CrossOver app asks first. With the
  Wine modules on automatic, the agent keeps them in the CrossOver installs that
  are on: it puts them back after a CrossOver or NotProton update put CrossOver's
  own files back, and updates them when newer ones come. With *New CrossOver
  builds too*, it also installs them into a runner NotProton adds for a new
  CrossOver build, once a runner that is on has them. It waits until that
  CrossOver's games are closed. A CrossOver app is only ever reported, since
  changing one asks for App Management and signs the app again.
  - The catalog is signed. The app takes it only when the signature matches the
    key built into the app, and every file matches its hash. Anything else is
    refused and the catalog in use stays.
  - A new game in the catalog shows up as a notification, but nothing is
    installed for it until you mark it.
  - A newer build of a fix already in a marked game replaces the older one.
    The installers compare the files they put in place with the catalog's, and
    the window shows *Older build: install to update*; the agent installs it
    again once the game is closed. Spider-Man 2's says *Needs repair* instead,
    since its shaders are rebuilt for each game build as well.
- **Reporting.** When a fix fails to install, the agent says so in a
  notification with a *Report on GitHub* button. It opens a new issue, already
  filled in with the game, the versions and the installer's last lines. Your
  home folder, account name and the Mac's serial number are taken out. Nothing
  is sent until you read it and press *Submit*. The window lists what the
  agent did, with the same button.

Turning the option off removes the agent. Its settings and what it did are in
`~/Library/Application Support/MacGameFix`, and its log is in
`~/Library/Logs/MacGameFix-agent.log`.

## Game Mode for CrossOver's games

macOS turns Game Mode on for a game in front, in full screen, whose app says it
is a game. A game in CrossOver never is one: CrossOver's Wine starts each game
again from a link named after its exe, in a temporary folder and in no app. With
**Settings › Game Mode for CrossOver's games** on, MacGameFix keeps a small app
that says it is a game for each CrossOver it was checked with (26.1, 26.3,
Preview 20261006 and Preview 20261015, read in their sources), holding a copy of
that CrossOver's Wine loader, and points each game's link at it. CrossOver
itself is not changed, and turning the switch off takes it all away. NotProton
runners are left to NotProton.

Play in full screen: the green button, or Control-Command-F. Measured on
2026-10-19 and 20 with a DualSense Edge over Bluetooth:

- Game Mode doubles what the pad's Bluetooth link carries: 4.9 KB/s without it,
  9.5 KB/s with it, written back to back from a bench tool. The haptics need
  6.7 KB/s, and without Game Mode Spider-Man 2 (under NotProton) lost 27 % of them.
- In CrossOver Preview's Steam bottle, Spider-Man 2 and F1 23 in full screen
  turned Game Mode on by themselves, and their haptics lost none.

The links are made for the exes MacGameFix finds in the Steam libraries and in
each bottle's Program Files; a game elsewhere is not covered. Game Feel's
options are read when the bottle starts, so in CrossOver change them before you
open Steam there (engine/README.md, "The options").

## The games

| Game | What the fix is for | Needs |
| --- | --- | --- |
| Beast of Reincarnation | Startup video plays with sound, no picture | D3DMetal, CrossOver Preview 27 |
| CONTROL Resonant | Lit rooms behind windows drawn in flat colours | D3DMetal |
| Cyberpunk 2077 | The MetalFX denoiser it ships is left off | The macOS version 2.5.0, an M3 or later |
| Devil May Cry 5 | Crashes when a skill preview plays | D3DMetal |
| DYNASTY WARRIORS: ORIGINS | Cutscenes with sound and no picture | D3DMetal, CrossOver Preview 27 |
| God of War | White specks on characters in dim light | DXMT |
| KINGDOM HEARTS Dream Drop Distance | Cutscenes with a solid green picture; a crash dialog on exit | D3DMetal, a prefix |
| KINGDOM HEARTS HD 1.5+2.5 ReMIX | The same, for the six titles of the package | D3DMetal, a prefix |
| Life is Strange: Double Exposure | Freezes after a while | D3DMetal 4 |
| Life is Strange: Reunion | Freezes after a while | D3DMetal 4 |
| Marvel's Spider-Man 2 | T-pose, a broken symbiote, black blocks in the sandstorm | D3DMetal |
| Mortal Kombat 11 | Dark smeared patches on bare faces once they animate | D3DMetal (DirectX 12) or DXMT (DirectX 11) |
| Mortal Shell 2 | Crash on the first cutscene | D3DMetal |
| NieR Replicant ver.1.22474487139 | Crashes when the first video starts | D3DMetal, a prefix |
| NINJA GAIDEN 3: Razor's Edge | Will not start: "Insufficient VRAM" | DXVK, a prefix |
| NINJA GAIDEN 4 | Says the VP9 codec is missing, then exits; on D3DMetal 4, nothing is ever drawn | D3DMetal 3 or 4.0b3, CrossOver Preview 27 |
| Nioh | "Failure to play movie", then a crash | DXMT |
| Nioh 2 | Cutscene refuses to play, then a crash | DXMT |
| Nioh 3 | "Failed to play movie" | D3DMetal |
| Persona 5 Strikers | Video never starts; sound only | DXMT |
| RESIDENT EVIL 2 | Crashes when a video plays | D3DMetal |
| RESIDENT EVIL 3 | Crashes when a video plays | D3DMetal |
| RESONANCE: A Plague Tale Legacy | "Shader Model 6.7 is not supported" | D3DMetal |
| TMNT: Splintered Fate | Opens a window, then closes | D3DMetal |
| The Witcher 3: Wild Hunt | Black screen at start; DLSS said to be unsupported | D3DMetal |
| Tormented Souls 2 | Fatal error before the first frame | D3DMetal |
| Wo Long: Fallen Dynasty | Cutscene with sound and a black picture | D3DMetal |

The list is not written by hand. The build takes every installer in `fixes/`
that declares a game-folder, a prefix or an app fix, and keeps the games for which the table
records no engine requirement, and either no codec or a CrossOver that ships
that codec as CodeWeavers distributes it.

**Measured, and what was not.** Every Windows game's fix here was measured on a CrossOver 26.3
that carried MacGameVideoFix's engine patches, which do not touch these fixes;
Spider-Man 2, God of War and Mortal Kombat 11 on CrossOver Preview 27 through NotProton;
NINJA GAIDEN 3 in a bottle of a patched CrossOver Preview 27 (27.0.0.40921), on 2026-08-28.
For Wo Long, Nioh 3 and KINGDOM HEARTS Dream Drop Distance, that the fix needs
nothing of the engine is read off how it works, not established by a run on an
untouched CrossOver. Cyberpunk 2077's, which no Wine runs, has its own
measurements in its section.

**Game Porting Toolkit 4.0b3.** The app marks five titles as not needing their
fix from 4.0b3 on: the four below and Mortal Shell 2, which was also played
without its fix on 4.0b3, cutscenes included (2026-10-14). On 2026-10-13 and 14, with D3DMetal 4.0b3 and
every fix removed, CONTROL Resonant drew its windows correctly, RESONANCE
started and played, and both Life is Strange titles played without problems:
none of the four needs its fix there. (The Life is Strange freeze was never
reproduced on demand, even on 4.0b2, so for those two the sessions show that
nothing went wrong rather than a fault cured.) Spider-Man 2, The Witcher 3, Tormented Souls 2, TMNT and Wo Long still
needed theirs, Mortal Kombat 11's was made on 4.0b3, and God of War runs on DXMT, which the toolkit does not change. Every
fix stays, for anyone on 4.0b2 and earlier.

### Nioh and Nioh 2 decode their own video

Their cutscenes are WMV3, which no CrossOver decodes. Nioh plays them through
DirectShow, and its fix gives the video the Windows Media reader Windows would
give it, with a WMV3 decoder of its own behind it. Nioh 2 plays them through
Media Foundation and uses the same reader as Persona 5 Strikers. Both must run
on **DXMT**: with a Steam Play tool, set `CX_GRAPHICS_BACKEND=dxmt %command%`.
Measured on 2026-10-14 on CrossOver Preview 27 through NotProton, with nothing
else installed: the videos play.

### Nioh 3 decodes its own video too

Its cutscenes are VP9. CrossOver Preview 27 decodes them through VideoToolbox
with magenta blocks in the bright areas, so its fix decodes them itself, with
the same reader, and asks for it before CrossOver's decoder. Measured on
2026-10-14 on CrossOver Preview 27 through NotProton: the picture is clean and
smooth.

### NieR Replicant decodes its own video, and needs a prefix

Its video is WMV2 with WMA v2 audio, which no CrossOver decodes; its fix uses
the same reader as Persona 5 Strikers. Measured on 2026-10-14 on CrossOver
Preview 27 through NotProton, with nothing else installed: the intro plays
with its sound. Like KINGDOM HEARTS below, its fix also tells Wine, in the
game's prefix, to load the DLL beside it, so the app asks which prefix.

### KINGDOM HEARTS needs a prefix

Its fix adds a DLL beside the game and also tells Wine, in the registry of that
game's prefix, to load it. The app finds the prefix itself:

- for a Steam Play tool, `steamapps/compatdata/<appid>/pfx` beside the library;
- for CrossOver, a bottle whose Steam declares the library the game is in.

When both exist it lets you choose. A Steam Play prefix is edited only while
nothing runs in it, and the installer refuses otherwise. The CrossOver route is
the one measured with the game. The Steam Play route was tested on a prefix --
install, check, remove, and Wine reading the key back -- but not yet with
KINGDOM HEARTS itself running from one.

### NINJA GAIDEN 3: Razor's Edge goes into the prefix

It is the Master Collection's Direct3D 9 title, and under CrossOver's own DXVK
it does not start: it says "Insufficient VRAM", because that DXVK cannot create
a Vulkan device for it. Its fix puts four DLLs into the `system32` of the
game's prefix, d9vk for Direct3D 9 and winevideo's builds of `qasf`, `quartz`
and `winegstreamer` for its ASF movies, keeps the prefix's own copies aside, and
tells Wine to load them for this game's executable only. Every other game in
the same bottle or prefix is left as it was, and nothing goes into the game
folder.

Measured on 2026-08-28 in a CrossOver bottle: the game starts, runs at 60 fps
and its cutscenes play. The boot movie stops on its first frame; one click
skips it. A Steam Play prefix, as a NotProton runner keeps, is edited only while
nothing runs in it, as for the other prefix fixes. That route was tested on a
prefix (install, check, repair, remove) but not yet with the game running from
one.

A CrossOver update that updated the bottle was measured putting back Wine's
own copies of three of the four DLLs. The game then shows as needing repair,
and installing again puts them back; with "Keep it applied" on, the agent does
it.

### Beast of Reincarnation needs CrossOver Preview

On stable CrossOver 26.3 its video stalls after two frames unless the engine
carries a change from winevideo, which MacGameVideoFix installed. CrossOver
Preview 27 does not need it: its own video decoder already behaves that way.
Measured on 2026-10-14 on CrossOver Preview 27 through NotProton, D3DMetal,
with nothing else installed: the startup video plays.

### DYNASTY WARRIORS: ORIGINS needs CrossOver Preview

Its cutscenes are VP9 in WebM, like NINJA GAIDEN 4's, and the same holds:
stable CrossOver 26.3 cannot open them, while CrossOver Preview 27 can, by
itself. The fix is a bridge that carries each decoded frame from the game's
D3D11 video device to its D3D12 renderer. Measured on 2026-10-14 on CrossOver
Preview 27 through NotProton, D3DMetal, with nothing else installed: the
cutscene plays with its sound.

### NINJA GAIDEN 4 needs CrossOver Preview

Its videos are VP9 in WebM. Stable CrossOver 26.3 cannot open a WebM, so there
the game reaches its menu with every video missing; MacGameVideoFix staged the
codec for it, which this app does not do. CrossOver Preview 27 ships what it
needs: its own GStreamer opens the WebM and VideoToolbox decodes the VP9.

The fix itself does three things, all in the game folder. It answers the game's
question about a VP9 decoder, which a Windows install answers with a codec pack.
It renames `dstoragecore.dll`, so DirectStorage is off, and removing the fix
renames it back. And it repairs two faults in how D3DMetal 4 handles D3D12
fences, without which the game runs with sound and never draws a frame.

Measured on 2026-10-14: on CrossOver Preview 27 through NotProton, with D3DMetal
4.0b3 and Metal 4 on, the intro video played and the menu came up. The same
repair, in a diagnostic build, brought the game up on 4.0b3 with Metal 4 on and
off, on a CrossOver carrying MacGameVideoFix's engine. D3DMetal 4.0b2 with the
repair was not run.

### Devil May Cry 5 and RESIDENT EVIL 2 and 3 decode their own videos

Some of their videos are VC-1: Devil May Cry 5's skill previews on the
Customize screen, and the two RESIDENT EVIL games' cutscenes. That is the same
codec as Persona 5 Strikers' videos, and these games use the same reader.
Measured on 2026-10-14 on CrossOver Preview 27 through NotProton, with nothing
else installed: the previews and the videos play, with their sound.

### Persona 5 Strikers decodes its own video

Its cutscenes are VC-1 with WMA Pro audio, which no CrossOver decodes. The fix
adds `mgvf-asf-reader.dll` beside the game: a video reader built on FFmpeg
(LGPL; its notice is installed with it), used only when CrossOver cannot open
the video. The game must run on **DXMT**. With a Steam Play tool such as
NotProton, set the launch option `CX_GRAPHICS_BACKEND=dxmt %command%`.

Measured on 2026-10-14 on CrossOver Preview 27 through NotProton, with nothing
else installed: the intro videos play with sound in sync. Stable CrossOver 26.3
without MacGameVideoFix's codec was not run.

### Spider-Man 2 downloads one thing

Its installer rebuilds the fix's four shaders from your own `Spider-Man2.exe`,
with Microsoft's shader tools taken from the release of
[SpiderMan2Fix](https://github.com/macprotips/SpiderMan2Fix). They are downloaded
once, cached in `~/Library/Caches/MacGameVideoFix`, and checked against the
verified result before anything is installed.

### Cyberpunk 2077 changes four bytes of its app

Cyberpunk 2077 for Mac carries Apple's MetalFX denoiser
(`MTLFXTemporalDenoisedScaler`) and does not offer it: its renderer answers
"not supported" from a method of two instructions, `mov w0,#0; ret`. CD
PROJEKT's notes for 2.5 first said "Added support for MetalFX Frame
Interpolation and Denoising on Mac", published on 2026-10-21, and were edited
within a day to drop "Denoising". The fix writes `mov w0,#1` over the first
instruction, so that the method answers "supported" and the game offers the
denoiser. It is the one fix here for a macOS game: no Wine runs it, and
nothing goes beside the app.

- **What changes.** Four bytes of `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`,
  `20 00 80 52` at file offset `0x1494640` in 2.5.0 (build 5814786), and the
  app's signature. A community script that does the same also turns four
  branches after the call into no-ops. Each of them follows the same call
  directly, so once the method answers 1 they change nothing, and MacGameFix
  writes only the one word. That the four change nothing, and that the one
  word is enough for the game to offer the denoiser, is read off the code, and
  the game played on 2026-10-22 had that one word written by hand: the same
  executable, byte for byte, that this installer leaves.
- **The signature.** The changed executable is no longer covered by CD
  PROJEKT's signature, so the app is signed again ad hoc:
  `codesign --force --sign - --options runtime --entitlements <plist> <app>`,
  without `--deep` and without clearing extended attributes. The entitlements
  are two of CD PROJEKT's own, `com.apple.security.cs.allow-dyld-environment-variables`
  and `com.apple.security.cs.disable-library-validation`; without the second,
  the ad hoc executable cannot load CD PROJEKT's frameworks under the hardened
  runtime. Only the executable changes: the four dylibs in `Contents/Frameworks`
  keep CD PROJEKT's signatures, and `Contents/_CodeSignature/CodeResources` is
  written again byte for byte the same.
- **What is lost.** The entitlements only CD PROJEKT's provisioning profile
  allows: `com.apple.developer.sustained-execution`, the application identifier
  and the team identifier. An ad hoc signature that carries them is killed at
  launch. Apple describes sustained execution as holding a game at its steady
  level of performance from launch, rather than a burst first; what losing it
  does to this game was not measured.
- **The original is kept** in
  `~/Library/Application Support/MacGameFix/app-backup/<bundle id>-<build>/`:
  the executable and its `CodeResources`, copied before anything is written and
  never replaced, and in `apps` the app it is kept for. *Remove* puts both
  back, checks that CD PROJEKT's signature verifies again, and deletes the
  copy; two copies of the game at the same build share it, and it goes when
  both are removed. Steam's *Verify integrity of game files* should put the
  original back as well; that was not tried. A copy kept for an earlier build
  of the same app is deleted at the next install or removal that works, since
  that executable is gone, and by *Remove Selected* on a row waiting for a
  recipe, the one thing it does there.
- **Stopped half way.** From the four bytes written to a signature that
  verifies, the executable cannot start. Stopped there, by an error, by Ctrl-C,
  or by MacGameFix quitting while it runs, the installer puts the original
  back. Broken all the same (*Needs repair*), installing again starts from the
  kept original, so what is signed is always the recipe's executable.
- **M3 or later.** Apple lists MetalFX denoised upscaling for Apple9 GPUs and
  later: M3, M4 and M5. The game does not ask MetalFX whether the Mac can do
  it, so on an M1 or an M2 the option would appear with nothing behind it: the
  row shows *Cannot be installed here*, with the reason, and the installer
  refuses. A fix already in can still be removed there.
- **A game update waits for a recipe.** The recipe is data: a row for each
  executable of each game build in `fixes/cp2077-denoiser.recipes`. A build
  with no row shows *No recipe for this build yet*, and nothing is changed;
  with *Keep it applied* on, the agent says so once for that build, however
  often it looks, and waits. The row for a new build comes in a catalog update,
  with no new app, and the agent then installs the fix.
- **Changed outside MacGameFix.** An executable patched outside MacGameFix,
  with no copy of its original kept, shows *Half installed*; one changed any
  other way, signed again by another tool for instance, so that no row was
  made from it, shows *Cannot be installed here*. Either way MacGameFix
  installs and removes nothing there, and says why beside the game. With *Keep
  it applied* on, the agent says it once for that build, with no failure and
  no report, and the menu bar counts the game to review. Steam's verify should
  put CD PROJEKT's executable back (not tried), and the fix installs from there.
- **Asked first.** *Install Selected* asks before it changes the app, as
  turning on the Wine modules in a CrossOver app does, and so does turning on
  *Keep it applied*, since the agent then changes the app in the background. macOS may ask you to
  allow MacGameFix under System Settings › Privacy & Security › App
  Management, and a write it refuses changes nothing; the log says so. Whether
  it asks for a game in a Steam library on an external volume was not measured.

**How a row is made for a new build.** The anchors, as found in 2.5.0: the
setting's name, `MetalFX_Denoiser`, appears in the code as its 64-bit FNV-1a
hash, `0x78134c36793c27dc`; beside it the game asks the renderer, through slot
`0x388` of its virtual table (`ldr x8, [x8, #0x388]`, then `blr x8`), whether
the denoiser is supported; and the method in that slot is the two-instruction
override, `mov w0,#0; ret`, at `0x101494640`, which is file offset `0x1494640`.
For a new build, find the three again in the new executable, check that the
word at the method reads `00008052`, write `20008052` into a copy, and take the
copy's sha256 before signing it. Then sign the copy as above, check it with
`codesign --verify --strict`, and check in the game that the option appears.
Only then does the row go in:
`<CFBundleVersion> <sha256 before> <offset> 00008052 20008052 <sha256 after>`.
A build shipped with more than one executable under one CFBundleVersion gets a
row for each; the installer takes the row made from the executable it finds.

Measured on 2026-10-22 on an M4 Max. On copies of the game's app: the four
bytes, and the signing, after which only the executable differed from CD
PROJEKT's app, its four frameworks kept their signatures and `CodeResources`
came out the same. With test executables: an ad hoc one under the hardened
runtime without `disable-library-validation` could not load one of CD
PROJEKT's dylibs, and one carrying the restricted entitlements was killed at
launch. The game on that Mac, with the one word written by hand, was played
the same day and looked good to the player. The installer on the real game,
run from a terminal: it refused that hand-patched executable (*Half
installed*); after CD PROJEKT's executable was put back, it installed, removed
(CD PROJEKT's signature verified again and the kept copy was deleted) and
installed again, and what it left is the hand-patched executable byte for byte
(sha256 `2f7c3ca9…651d`). Not measured: frame times with the denoiser on or
off, any M3 Mac, what Steam's verify does to the changed app, and the install
run from MacGameFix, where macOS may ask for App Management.

## Reporting a problem

[Open an issue](https://github.com/MathiasKowoll/MacGameFix/issues/new/choose) with the form that fits:

- **A game that does not work**, with a fix of ours or without one. In the **Report** tab, click the game and
  choose what goes wrong. MacGameFix reads the game's folder, without changing anything in it, and says what
  it is made of: its executable and the DLLs it imports, the graphics API, the engine, how it reads a
  controller, its videos by container and codec, its middleware and any anti-cheat. Follow the steps it gives
  for what goes wrong, then click **Save the Report and Open an Issue…** and attach the file to the form
  that opens. The report adds the game's own log when it writes one (Unreal's `Saved/Logs`, Unity's
  `Player.log`) and what the Wine modules saw of it. It names that game alone, writes your home folder as
  `~` and leaves your Mac's name out.
- **Controller, haptics or triggers.** In **Game Feel**, click the game, turn on **Diagnose this game**,
  play the moment that goes wrong, close the game, and click **Make a Report…**. It saves a file and opens
  the form; attach the file there. The report has MacGameFix's and macOS's versions, the Wine modules in
  each CrossOver, the game's settings and what the modules logged for it. It names that game alone and
  writes your home folder as `~`. Turn Diagnose off afterwards.
- **Settings that felt right.** In **Game Feel**, click the game, set it up and play it; with **Diagnose
  this game** on, the report also holds the haptics' levels and delays. Then click **Share These
  Settings…**: it saves the same report and opens the form with the game and every option it gets filled
  in; attach the file there and say how it felt. Shared settings that a report backs become the game's
  suggested settings in Game Feel.
- **A game that vibrates.** In **Game Feel**, click the game, play it with **Diagnose this game** on if you
  can, close it, and click **It Vibrates…**. It saves the same report and opens the form with the game, the
  controller and the connection the Wine modules saw in its latest session, what they saw it do, and the
  library it talks to the pad through; say what you felt and attach the file. One report is one controller on
  one connection: played on a cable and over Bluetooth, send two. Reports like this make the
  [list of games played for vibration](docs/vibration.md).
- **A game fix does not work.** Copy the lines about the game from **Settings › Log** into the form.

## Opening it the first time

The application is signed ad hoc, so macOS blocks the first launch of a
downloaded copy. **Right click > Open** once, and confirm.

## Building it

```
app/build-app.sh
```

It compiles the app, chooses the games as described above, copies the
installers and every file they name from `fixes/` unchanged, and fails if the
bundle differs from `fixes/` in a single byte.

**The release's catalog.**
- **When it is written:** when the signing key is at
  `~/.config/macgamefix/catalog-signing.key` (or `$MACGAMEFIX_SIGNING_KEY`), the
  build also writes `app/dist/catalog.zip`, `app/dist/catalog.json` and
  `app/dist/catalog.json.sig`. Attach all three to the release so installed apps
  take the new fixes.
- **The key:** it never enters the repository, and only the public half is in
  `Automation.swift`. Losing it means a new key in a new app, since catalogs
  signed with another key are refused. `MacGameFix --new-signing-key <file>`
  makes one and prints the public half.

**Testing it.** `app/test-automation.sh` checks all of it offline, with a
throwaway home and a fake game and catalog:
- refused and accepted catalogs;
- the agent after a game update;
- what each fix requires, said beside the game;
- while Steam writes the game and while the game runs;
- an older build of a fix replaced with the catalog's;
- a failing installer's report;
- a macOS game's fix waiting for a recipe for the game's build, with no failure
  and no report, said once for that build through a newer catalog without one,
  until a catalog brings one;
- a macOS game's app changed outside MacGameFix, or on a Mac the fix is not
  for: the installer's reason, once for each build, never run, no failure and
  no report.

`fixes/test-installers.sh` takes every folder installer through its life on
throwaway folders, with no game needed: installed, an older build, updated,
restored to the game's own file, and an older or missing reader where a fix
has one. Cyberpunk 2077's goes through its life on a fake app built there with
`cc`: installed and signed, with every other file of the game folder as it
was; rebuilt from the original when broken; restored byte for byte; two copies
of a build sharing the kept original; the original put back after Ctrl-C while
signing and after its reader goes away. It is refused, with nothing changed,
on an M1 and an M2, while the game runs (started by another spelling of its
path), for a build with no recipe, for an executable no row was made from, for
one patched by hand, over a kept copy that is not the original, and when macOS
refuses the write. Copies kept for other builds go at an install and at a
removal, and another app's stay.

**Building a fix's DLL.** `fixes/build-proxy.sh` and
`fixes/build-asf-reader.sh` need llvm-mingw (or another x86_64-w64-mingw32
toolchain). Users never run them: the built DLLs are in `fixes/` and ship in the
app. `fixes/check-builds.sh` rebuilds each DLL from its source and compares the
two, checks the third-party ones against their recorded sha256, and compares
the MGVF-GAME lines with `process-features.json` and a built app's copies with
`fixes/`.

## How each fix is made

Every fix is one installer in `fixes/` and the files it puts in the game
folder; Cyberpunk 2077's puts none there, and changes four bytes of the game's
executable instead, from a recipe. A proxy DLL takes the name of a DLL the
game already loads, keeps the game's own as `<name>_real.dll`, and forwards
every export to it; the source named below is the code that runs inside it.
The source of each shipped DLL is the one that writes the log name the DLL
carries, which is how `fixes/check-builds.sh` finds it. What was found, and
how, is in the game's page under `legacy/wiki/`.

| Installer | Games | What goes in the game folder | Built from | Findings |
| --- | --- | --- | --- | --- |
| `install-runtime-fix.sh` | Beast of Reincarnation, Life is Strange: Double Exposure, Life is Strange: Reunion, Mortal Shell 2 | `libogg_64.dll` under `Engine/Binaries/ThirdParty/Ogg/Win64` | `ue5-media-fix.c` | [Beast](legacy/wiki/Beast-of-Reincarnation.md), [Double Exposure](legacy/wiki/Life-is-Strange-Double-Exposure.md), [Reunion](legacy/wiki/Life-is-Strange-Reunion.md), [Mortal Shell 2](legacy/wiki/Mortal-Shell-2.md) |
| `install-ctl-fix.sh` | CONTROL Resonant | `PxFoundation_x64.dll` (from `PxFoundation_x64-ctl.dll`) | `ctl-window-fix.c` | [CONTROL Resonant](legacy/wiki/Control-Resonant.md) |
| `install-cp2077-denoiser.sh` | Cyberpunk 2077 | Nothing beside the game: four bytes of `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`, at the offset its build's row in `cp2077-denoiser.recipes` names, and the app signed again ad hoc; the original kept in MacGameFix's `app-backup` folder | Not built: a recipe for each game build, and none of CD PROJEKT's code ships | [Its section](#cyberpunk-2077-changes-four-bytes-of-its-app) |
| `install-re-vc1-fix.sh` | Devil May Cry 5, RESIDENT EVIL 2, RESIDENT EVIL 3 | `amd_ags_x64.dll` (from `amd_ags_x64-dmc5.dll`, or `amd_ags_x64-re2.dll` for both RE titles), and the reader | `mf-reader-fallback.c` | [RE Engine VC-1](legacy/wiki/RE-Engine-VC1.md) |
| `install-dwo-bridge.sh` | DYNASTY WARRIORS: ORIGINS, Wo Long: Fallen Dynasty | `libxess.dll` | `dwo-video-bridge.c` | [DYNASTY WARRIORS: ORIGINS](legacy/wiki/Dynasty-Warriors-Origins.md), [Wo Long](legacy/wiki/Wo-Long-Fallen-Dynasty.md) |
| `install-gow-fix.sh` | God of War | `libSceJobManager.dll` (from `libSceJobManager-gow.dll`) and `gow-depth-fix.ini` | `gow-depth-fix.c` | [God of War](legacy/wiki/God-of-War.md) |
| `install-kh-bridge.sh` | KINGDOM HEARTS Dream Drop Distance, KINGDOM HEARTS HD 1.5+2.5 ReMIX | `dinput8.dll` (from `dinput8-kh.dll`); the original is the bottle's or prefix's own `dinput8`, copied beside it | `dwo-video-bridge.c` | [KINGDOM HEARTS](legacy/wiki/Kingdom-Hearts.md) |
| `install-sm2-fix.sh` | Marvel's Spider-Man 2 | `amd_ags_x64.dll` (from `amd_ags_x64-sm2.dll`), and shaders rewritten from the game's own executable by `sm2-shadertool` | `sm2-tpose-fix.c` with `sm2fix_core.c`; the tool from `sm2-shadertool.c` and `sm2-shaderfix.c` | [Spider-Man 2](legacy/wiki/Spider-Man-2.md) |
| `install-mk11-fix.sh` | Mortal Kombat 11 | `amd_ags_x64.dll` under `Binaries/Retail` (from `amd_ags_x64-mk11.dll`) | `mk11-face-fix.c` with `sm2fix_core.c` and `mk11-morph-shaders.h` (from `mk11-morph/`) | [Mortal Kombat 11](legacy/wiki/Mortal-Kombat-11.md) |
| `install-nier-bridge.sh` | NieR Replicant ver.1.22474487139 | `dinput8.dll` (from `dinput8-nier.dll`), the original copied from the bottle or prefix, and the reader | `dwo-video-bridge.c` | [NieR Replicant](legacy/wiki/NieR-Replicant.md) |
| `install-ng3-fix.sh` | NINJA GAIDEN 3: Razor's Edge | Nothing: `d3d9.dll`, `qasf.dll`, `quartz.dll` and `winegstreamer.dll` (from `ng3-*.dll`) go into the prefix's `system32`, the prefix's own kept aside, with overrides for the game's executable | Not built here: d9vk v1.10.3-20250511 and winevideo 0.5's Wine builds, checked by their hashes in `ng3-THIRD-PARTY-LICENCES.md` | [NINJA GAIDEN 3](legacy/wiki/Ninja-Gaiden-3-Razors-Edge.md) |
| `install-ng4-fix.sh` | NINJA GAIDEN 4 | `dstorage.dll` (from `dstorage-ng4.dll`); `dstoragecore.dll` renamed aside | `tools/ng4-observe.c`, built with `-DNG4_FIX` | [NINJA GAIDEN 4](legacy/wiki/Ninja-Gaiden-4.md) |
| `install-nioh-bridge.sh` | Nioh, Nioh 2 | `GfeSDK.dll`, and the reader | `p5s-video-bridge.c` | [Nioh](legacy/wiki/Nioh.md), [Nioh 2](legacy/wiki/Nioh-2.md) |
| `install-nioh3-bridge.sh` | Nioh 3 | `amd_ags_x64.dll` (from `amd_ags_x64-nioh3.dll`), and the reader | `dwo-video-bridge.c` | [Nioh 3](legacy/wiki/Nioh-3.md) |
| `install-p5s-bridge.sh` | Persona 5 Strikers | `amd_ags_x64.dll`, and the reader | `p5s-video-bridge.c` | [Persona 5 Strikers](legacy/wiki/Persona-5-Strikers.md) |
| `install-resonance-fix.sh` | RESONANCE: A Plague Tale Legacy | `NvCloth_x64.dll` (from `NvCloth_x64-resonance.dll`) | `shader-floor-fix.c` | [RESONANCE](legacy/wiki/Resonance-A-Plague-Tale-Legacy.md) |
| `install-tmnt-fix.sh` | TMNT: Splintered Fate | `fmod.dll` (from `fmod-tmnt.dll`) | `d3d12-guards.c` | [TMNT](legacy/wiki/TMNT-Splintered-Fate.md) |
| `install-tormented-fix.sh` | Tormented Souls 2 | `OpenColorIO_2_3.dll` under `TormentedSouls2/Binaries/Win64` (from `OpenColorIO_2_3-tormented.dll`) | `d3d12-guards.c` | [Tormented Souls 2](legacy/wiki/Tormented-Souls-2.md) |
| `install-w3-fix.sh` | The Witcher 3: Wild Hunt | `amd_fidelityfx_loader_dx12.dll` under `bin/x64_dx12` (from `amd_fidelityfx_loader_dx12-w3.dll`), and a `bin/x64` link | `w3-streamout-fix.c` | [The Witcher 3](legacy/wiki/The-Witcher-3.md) |

- **The reader** (`mgvf-asf-reader.dll`) is `asf-reader.c`, `wmv-dmo.c`,
  `wm-reader.c` and `dshow-graph.c` over a static FFmpeg 9.0.2 cut down to the
  demuxers and decoders these games need, built by `fixes/build-asf-reader.sh`.
  Its notices are in `fixes/mgvf-asf-reader-LICENCES.md`.
- **The proxies** are built by `fixes/build-proxy.sh <the game's DLL>
  <source.c>`, which reads the exports from the game's own DLL so the
  forwarders match it. NINJA GAIDEN 4's source is a probe that becomes the fix
  with `MGVF_CFLAGS="-DNG4_FIX"`, as the script's comments say.
- **`sm2-shadertool`** is a Mac program, built with clang as its source's header
  shows.
- **Work by others:** Spider-Man 2's diagnosis, raw views and rewritten
  shaders are macprotips', as `sm2-tpose-fix.c` says, and `sm2-shaderfix.c` is
  their rewriter ported to C; The Witcher 3's rule is tholtman1-del's; God of
  War's depth test was found in a r/macgaming post; NINJA GAIDEN 3's DirectShow
  diagnosis and builds are winevideo's, and its d3d9 is d9vk. See Credits.
- **Sources no shipped fix builds from:** `ue5-runtime-fix.c` and
  `electra-h264-fix.c` (earlier sources of the Unreal fix, whose builds
  `install-runtime-fix.sh` still recognises), `sleep-yield-fix.c`
  (METAL GEAR SOLID 4) and `hide-wine.c`.

## Credits

- **[witcher3-crossover-fix](https://github.com/tholtman1-del/witcher3-crossover-fix)
  by tholtman1-del** (MIT): the diagnosis of The Witcher 3's black screen and
  the rule that refuses the pipeline.
- **[SpiderMan2Fix](https://github.com/macprotips/SpiderMan2Fix) by macprotips.**
  The Spider-Man 2 fix is theirs; this adds a carrier that needs no DLL override,
  and a barrier after the volumetric fog copy.
- **The God of War fix** comes from a r/macgaming post, "God Of War 2018 White
  Dot Fix (through Crossover)", whose author found the depth test behind the
  white specks.
- **[winevideo](https://github.com/Jfishin/winevideo)'s author** found why
  NINJA GAIDEN 3's movies never start (Wine's ASF Reader blocks its audio
  behind the video) and built the patched `qasf`, `quartz` and `winegstreamer`
  its fix installs (LGPL-2.1-or-later).
- **[d9vk](https://github.com/Sikarugir-App/d9vk) by Sikarugir-App** (zlib):
  the Direct3D 9 that NINJA GAIDEN 3 runs on.
- **The Cyberpunk 2077 patch** comes from a community script published
  anonymously; its author is not known. MacGameFix writes one of its five
  words.
- Everything else, and the findings behind every fix, is in `legacy/` here and
  in the archived [MacGameVideoFix](https://github.com/MathiasKowoll/MacGameVideoFix)
  with its full history.

## License

[GPL-3.0-or-later](LICENSE), and the app carries the text. The reader built on
FFmpeg (LGPL-2.1-or-later) carries its own notice and the LGPL's text
(`fixes/mgvf-asf-reader-LICENCES.md`, installed beside the games that use it),
and every release attaches the FFmpeg source tarball it was built from. NINJA
GAIDEN 3's third-party DLLs, which the app carries for its fix, come with their
notices and the LGPL's text in `fixes/ng3-THIRD-PARTY-LICENCES.md`, which also
says where their source is.
