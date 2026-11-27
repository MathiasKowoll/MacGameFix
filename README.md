# MacGameFix

Preview 1.6.1-pre.1: **Forza Horizon 5 complete and gameplay validated; Forza Horizon 6 WIP with sign-in and driving advances.** [Release notes and validation limits](docs/releases/1.6.1-pre.1.md). The FH6 runtime belongs to the existing Rosetta improvement; diagnostics are optional.

Fixes for Windows games on a Mac that go into the game's own folder, and the
small macOS application that installs, checks and removes them. One more is
for a macOS game: it turns on the MetalFX denoiser that Cyberpunk 2077 ships
and leaves off, by changing the game's own app.

Most game-folder fixes do not replace a CrossOver module. FH6 additionally uses the paired ntdll from the existing Rosetta improvement. The other Windows game fixes work with
CrossOver as CodeWeavers ships it, with CrossOver Preview, and with Steam Play
tools for macOS such as [NotProton](https://github.com/NotProtonNot/NotProton):
a proxy DLL beside the game, and for a few titles registry keys in the game's
own prefix. Forza Horizon 5 and Forza Horizon 6 also add a private alias of the
selected runner's own D3DMetal module; the alias is made locally and the module
is not shipped.
NINJA GAIDEN 3: Razor's Edge puts its DLLs in the prefix instead.

This repository is where the fixes live now. They started in
[MacGameVideoFix](https://github.com/MathiasKowoll/MacGameVideoFix), which also
patched CrossOver itself: staged GStreamer codecs, its own `winegstreamer`, a
controller bus. That project is archived. The current game fixes and their installers moved
here. The history of every fix, and the engine work, stays in the
archived repository.

## What is in this repository

| Folder | What it holds |
| --- | --- |
| `app/` | The application: `Core.swift` (installers, games, libraries), `Engine.swift` (the Wine modules), `Pad.swift` (the Game Feel tab's options and what it writes for the modules), `Probe.swift` (the Report tab: what a game is made of, and its report; and a fix's report, which Games saves), `pad-presets.json` (options measured per title), `Automation.swift` (the background agent, signed catalog updates, reports), `AppUpdate.swift` (a newer MacGameFix found, checked and put in this one's place), `MenuBar.swift` (the agent's menu bar item), `MacGameFix.swift` (the window), `AppIcon.icon` (the icon); `build-app.sh`, `test-automation.sh`, `notarize.sh` (Apple's notarisation and the release's app zip) and `test-notarize.sh`. |
| `fixes/` | One installer per fix (`install-*.sh`), the DLLs they put in place, Cyberpunk 2077's recipe for each build of the game (`cp2077-denoiser.recipes`), the C source of each DLL and the scripts that build them (`build-proxy.sh`, `build-asf-reader.sh`, `check-builds.sh`), and the third-party notices. |
| `process-features.json` | The table: per game executable, its symptom, backend, toolkit, codec and engine needs. The app is built from it. |
| `tools/` | The probes and capture scripts the fixes were found with: video and Media Foundation observers, HID traces, a game survey; `capture-performance.sh`, which records two minutes of a game that runs slowly from outside it, and `read-performance.py`, which reads what it recorded ([how a player uses it](docs/performance-capture.md)); `vibration-md.py`, which writes the list of games played for vibration from its JSON; and `sign-payload.sh` and `check-signatures.sh`, which sign the Mach-O files the app carries with its Developer ID and check them. |
| `docs/` | The [list of games played for vibration](docs/vibration.md): `vibration.json`, its source, and `vibration.md`, made from it by `tools/vibration-md.py`. Also [how to record a game that runs slowly](docs/performance-capture.md), the inventory of what the app shows (`ui-inventory.md`) and the documentation's screenshots (`images/`). |
| `engine/` | Not a game fix: patched Wine modules that go into CrossOver itself, for a DualSense or DualSense Edge: its haptics on a cable and over Bluetooth, the pad on Bluetooth as the same pad on a cable, XInput (its rumble on the motors, or the pad as an XInput controller), trigger effects for a game that sets none, the pad's audio output for games that find it through SetupAPI and XAudio2, and the Edge shown as a standard DualSense or the pad as a DualShock 4. The built modules per CrossOver build, their installer (`engine-modules.sh`), the patches and `build.sh`; see [`engine/README.md`](engine/README.md). The app's Wine Modules tab installs them. |
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
*Fixed*, *Not fixed*, or *All fixes*, which adds the fixes for games that are not on this Mac; under
the table, **It Works…** and **Works Without the Fix…** report a game you played, one selected at a
time (see [Reporting a problem](#reporting-a-problem));
**Improvements**, the one part that changes CrossOver
itself, one section each: *DualSense controllers* (patched Wine modules for a DualSense's haptics on a
cable and over Bluetooth, the pad on Bluetooth as if on a cable, XInput, trigger effects for a game
that sets none, the pad's audio output through SetupAPI and XAudio2, and the Edge or the pad shown to a
game as another pad) and *Copy protection under Rosetta* (the Intel side's `ntdll.so`, for
Denuvo-protected games such as Phantom Blade Zero, Persona 4 Golden and
STAR WARS: Galactic Racer; the games played, reported or in progress are in
[`docs/improvements`](docs/improvements); in NotProton's runner for CrossOver Preview 41303 the
Intel side keeps CodeWeavers' and NotProton's files, and those games get the same from the
**Engine fixes** row on their Compatibility page), see
[`engine/README.md`](engine/README.md), each with a switch and an Update button for every CrossOver
app and NotProton runner (the stable CrossOver and the latest Preview are maintained; an older
Preview's modules are kept as they were last built, without support, and the tab says "No longer
maintained" under it); then *Game Mode*, *Fans* and *Shaders* (see
[Each game's compiled shaders, kept whole](#each-games-compiled-shaders-kept-whole)), which change
nothing in CrossOver, and the modules' own updates; **Game Feel**, the DualSense's options for every game
and, in a table of the Steam games on this Mac, for each one, with what the
modules saw each game do; **Report**, for a game that does not work (see
[Reporting a problem](#reporting-a-problem)); and **Settings**, with the background agent, the game
fixes' updates, the folders searched and the log.

## What each fix requires

A fix goes into the game's own folder, and the same folder serves every
place that runs the game: a NotProton runner, a CrossOver bottle, or both.
Where you run it is yours to check. The app says beside each game what its fix
requires: the graphics backend it was made for (D3DMetal or DXMT; God of War's
works on both and names neither), and for some games a CrossOver or D3DMetal
version.

Some fixes are not needed from a D3DMetal version on (CONTROL Resonant,
Mortal Shell 2, Resonance: A Plague Tale Legacy and both Life is Strange titles
from 4.0b3). The game says so. It is only a notice: the fix still installs.

The exception is a fix that also writes registry keys: Forza Horizon 5, Forza
Horizon 6, the Kingdom Hearts titles and NieR Replicant; NINJA GAIDEN 3:
Razor's Edge, whose
DLLs go there too and nothing into its folder; and Phantom Blade Zero, whose
H.264 decoder goes there with its registry values. Those keys go into the game's prefix, a
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

Forza Horizon 5's fix is made from source in this repository. It puts the
D3D12 proxy in the game folder, makes `apd12.dll` from the runner's own
D3DMetal DLL, adds that private alias to the runner and prefix, and applies the
override only to `ForzaHorizon5.exe`. It also installs the Xbox UDP proxy used
for Horizon Life, and the two prefix values the Xbox sign-in window needs. The
GPU identity cannot go into the prefix, because D3DMetal reads it from the
native environment, so NotProton still needs these variables in the game's
Steam launch options:

```text
NOTPROTON_ENV_D3DM_VENDOR_ID=4318 NOTPROTON_ENV_D3DM_DEVICE_ID=10118 NOTPROTON_ENV_D3DM_DEVICE_DESCRIPTION="NVIDIA GeForce RTX 4070"
```

The first successful run may spend several minutes at **Optimizing for your
PC**. The exact diagnosis, the files and the reversible layout are in
[Forza Horizon 5](legacy/wiki/Forza-Horizon-5.md).

Forza Horizon 6 uses a separate build from the same audited GPL source. Its
profile keeps the general D3DMetal compatibility fixes, the shader-model and
input-layout fallbacks, the `SV_ShadingRate` rewrite, and the real-memory
report. It deliberately leaves out FH5's descriptor-handle translation,
unwind guard and Xbox UDP proxy. The installer makes the same private
`apd12.dll` alias from the selected runner and applies the override only to
`forzahorizon6.exe`. NotProton's native Visual C++ runtime override remains
responsible for the concurrent-vector crash fixed by Highball's FH6 recipe.
The measured result and remaining validation are in
[Forza Horizon 6](legacy/wiki/Forza-Horizon-6.md).

## Keeping fixes applied, and new fixes

From version 1.4.0 the app can look after the fixes by itself. All of it is off
until you turn it on, and the fixes stay in the games' own folders as before.

- **Keep it applied.** Ori and the Will of the Wisps' fix cannot be kept: it
  compiles for minutes with the Mac working hard, so it runs only when you
  press Install. Every other game can be.

  Mark a game with *Keep it applied*, and turn on *Run in
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
- **Updates: one for everything.** A release brings three things: MacGameFix
  itself, the game fixes (the installers and every file they use) and the Wine
  modules. The fixes and the modules are two catalogs, each signed and
  versioned on its own, so new modules for a new CrossOver build come without
  touching the fixes and neither needs a new app. To you they are one update,
  with one choice in Settings, *Updates*, and one *Check Now*:
  - *Automatic*: the agent looks once an hour and takes the fixes and the
    modules as they come. A new MacGameFix is downloaded and checked while the
    window is open, and starts when you choose *Relaunch*.
  - *Ask first*: the agent checks what is new and tells you, and takes
    nothing. *Update*, above the tabs, or *Install the Update* in the menu bar
    takes it.
  - *Off*: nothing is looked for.

  What waits shows above the tabs as one notice with one button, and the menu
  bar has one line and one command for it. The notice and the agent's
  notification say what the update brings, in a few short lines: a catalog
  carries them under its signature (`fixes/WHATS-NEW.txt` and
  `engine/WHATS-NEW.txt` when it was built), and a new MacGameFix's come from
  its release notes.

  Improvements lists, under each improvement, every CrossOver app and NotProton
  runner by its release ("CrossOver Preview 20261015"), with a switch, and *All*
  and *None*. The switch is the action: on installs that improvement there, off
  puts CrossOver's own files back, and the other improvement is left as it is.
  *Copy protection under Rosetta* is on wherever the controllers are, unless it
  is turned off there. A game whose fix needs an improvement that is in no
  CrossOver says so in Games, beside the fix, with an *Install…* button. Only a CrossOver of a build and Wine the modules were built for can be
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
  - A newer build of a fix in a game that is not marked is not installed by
    itself. The agent names the game in a notification, and the window shows
    *A newer fix is ready for: …* above the tabs, with *Install*. A game on
    this Mac that gets its first fix is named in a notification too.
- **A new MacGameFix.** A new tab, an option or a fix an older app cannot
  install needs a new app, and it comes with the same update. The agent says so
  in a notification, the menu bar carries *Update to MacGameFix …*, and the
  window shows it above the tabs:
  - *What's New* opens the release's page.
  - *Update* downloads the new app and checks it; nothing is replaced yet.
    *Relaunch* then puts it where this one is and opens it, and the menu bar
    item starts again from the new one. On *Automatic* it is downloaded
    already, and only *Relaunch* is left.
  - The download is taken only when it is signed with the same Developer ID
    and identifier as the MacGameFix asking, every file in it is what the
    signature sealed, and its version is the one offered and newer than this
    one. Anything else is refused and the app stays as it was.
  - A copy that cannot replace itself says why and sends you to the release's
    page: one macOS runs from a read-only place (move it to Applications), one
    in a folder your account cannot change, and a build signed ad hoc.
  - The question goes to MacGameFix's service, which keeps a table of the
    versions and where each one's zip is on GitHub, and to GitHub's own API when
    the service does not answer. The app sends its version and nothing about
    you or your Mac. A build of your own asks GitHub only.
- **Reporting.** When a fix fails to install, the agent says so in a
  notification with a *Report on GitHub* button. It opens a new issue, already
  filled in with the game, the versions and the installer's last lines. Your
  home folder, account name and the Mac's serial number are taken out. Nothing
  is sent until you read it and press *Submit*. The window lists what the
  agent did, with the same button.

Turning the option off removes the agent. Its settings and what it did are in
`~/Library/Application Support/MacGameFix`, and its log is in
`~/Library/Logs/MacGameFix-agent.log`.

## Fans at full speed for the games that ask

macOS raises the fans about a minute after a game starts to load its world. By
then the chip is at 73-78 °C, and the kernel's power manager sets a thermal power
budget for the processor and the graphics together: it falls from about 48 W to
15-20 W in a minute, and the performance cores are held at 1.8 GHz of 4.5 for
some three minutes, then near 2 GHz for as long as the game runs. The kernel
logs it once a second
(`log show --predicate 'process == "kernel" AND eventMessage CONTAINS "Thermal Budget"'`).

With **Improvements › Fans** on, MacGameFix installs a small helper that turns
both fans to their maximum when a game that asks for it starts, and hands them
back to macOS when it closes. Measured on 2026-11-14 with Forza Horizon 6 on a MacBook
Pro M4 Max, under NotProton:

| | Fans as macOS runs them | Fans at full speed from launch |
| --- | --- | --- |
| Chip, a minute into the world | 73-78 °C | 64 °C |
| Chip, later | 60-65 °C, with the processor cut | 66-69 °C |
| Performance cores | 1.8-2.3 GHz | 4.5 GHz throughout |
| Thermal power budget | 15-20 W, then about 44 W | never set |
| Frame rate, capped at 60 | 27-50 | 59-60 |
| Seconds with a frame over 60 ms, a minute | 27-59 | 0-1 |

Both columns had the game's upscaler on and the game shown 8 processors; one
run each, standing still. The fans are loud at their maximum.

The helper is a LaunchDaemon, `/Library/PrivilegedHelperTools/io.github.macgamefix.fans`,
because only root can set the fans; macOS asks for your password when the switch
installs or removes it. It can only raise the fans, and puts them back to
automatic when no such game is running, when it is stopped, and when it is
removed. Apple silicon only.

A game asks for the fans with `MGF_FANS=max` in its launch options in Steam,
before `%command%`; this is for the games NotProton runs. The fans start within
a few seconds of the game's launch. MacGameFix also puts a row, **Fans at full
speed**, into NotProton's plugins folder (`mgf-fans.conf`); switched on for a
game it writes `NOTPROTON_MGF_FANS=1` into that game's launch options, which the
helper (version 2 or later) takes as it takes `MGF_FANS=max`. The row shows only
in a NotProton whose panel lists such rows, and the variable works without it.

Either works for any game NotProton starts, also when the launch options put a
script of their own before `%command%` and that script starts something else in
the game's place, as a mod launcher's does. That takes the helper at version 3:
an earlier one looked for the program being run in the line NotProton logged,
found another name there, and left the fans alone. **Improvements › Fans**
offers the update when the installed helper is older.

The fans raise what the Mac can shed; they do not lower what a game draws. A
game that drew about 96 W uncapped was cut all the same after 2 min 40 s. With
it, cap the frame rate (NotProton's **Frame rate cap** row, below), turn the
game's upscaler to a performance mode, and show the game 8 processors
(**Processors the game sees**, which needs no helper).
**Improvements › Fans** shows the two variables to copy.

Every game sees all of the Mac's processors unless it is given a count.
MacGameFix keeps a row, **Processors the game sees**, in NotProton's plugins
folder (`mgf-ncpu.conf`), written for the Mac it runs on: All by default, and
only counts below the Mac's own (with its performance cores named), so a game
is never shown processors that are not there. Picking a count for one game in
its NotProton options sets `NOTPROTON_ENV_WINENCPU` for that game alone.

Three more rows MacGameFix keeps for every game, each off until it is picked
for one:

- **Frame rate cap** (`mgf-fps.conf`, the Preview tools only: `D3DM_MAX_FPS`
  exists in D3DMetal 4 alone). D3DMetal 4 presents each frame no sooner than
  1/cap after the one before, and a Mac's display shows frames only at its own
  steps (240/n on a 120 Hz MacBook Pro: 120, 80, 60, 48, 40...). A cap of
  exactly 60 then ends at 48 fps: any cap from 48 to 60 held 48, and 70 held
  60.00 (measured on 2026-09-26 with the Metal HUD). So the row is made from
  the Mac's display, offers the rates it can hold, and each writes the cap
  halfway to the next faster step: **60 fps** writes 70. Only 60 was measured;
  the other rates follow the same rule.
- **Ray tracing off** (`mgf-dxr.conf`): `D3DM_SUPPORT_DXR=0`, so D3DMetal says
  it has no ray tracing. For a game that closes as a level loads where D3DMetal
  offers ray tracing it cannot do, as Phantom Blade Zero does with DLSS on.
- **NVIDIA driver version** (`mgf-nvidia-driver.conf`, the Rosetta tools):
  D3DMetal tells a game its NVIDIA driver is 576.02 (561.09 in D3DMetal 3), and
  a game that wants a newer one asks for a driver update at every start. The
  row patches that version to 999.99 in memory. EA SPORTS FC 27 1.0.143, which
  wants 610.62, started with no dialog (2026-11-26).

MacGameFix also carries four of its fixes as NotProton plugins, which
NotProton's creator ported and NotProton has not released yet
(`app/notproton-plugins/ORIGIN.md`). They go into NotProton's plugins folder
under NotProton's own file names, each off until it is switched on for a game:

- **Unreal video fix** (`40-unreal-video.conf`): patches `winegstreamer.dll`
  in memory to offer the NV12 output Unreal's video player asks for, where its
  videos stay black. Not for every game: Town to City crashes on a menu video
  with it.
- **D3DMetal freeze fix** (`50-d3dmetal-freeze.conf`, `d3dmetal-freeze.dylib`):
  D3DMetal 3.0 and 4.0b2 froze on a video memory question about a second GPU
  node (Town to City, Life is Strange, FATAL FURY).
- **D3DMetal video crash fix** (`55-d3dmetal-notifier.conf`,
  `d3dmetal-notifier.dylib`): the `ID3DDestructionNotifier` older D3DMetal
  lacked, where some games crashed playing a video.
- **Red Dead Online fix** (`60-red-dead-online.conf`, `tcp-noopt.dylib`), on
  Red Dead Redemption 2 and Red Dead Online's pages only: `TCP_NOOPT` on the
  game's sockets. Red Dead Redemption 2's fix switches it on for the game.

One more is MacGameFix's own:

- **DualSense controllers** (`mgf-controls.conf`, `mgf-controls.dylib`, the
  Rosetta tools): the DualSense in a game whose runner keeps CodeWeavers' own
  `winebus.so` and `winecoreaudio.so`. The library takes those two files' calls
  to macOS and does what the Wine modules do inside their own: the Bluetooth
  pad as a wired one, haptics, XInput, trigger effects and DualShock 4 mode,
  by the game's settings in Game Feel. Where the two files are MacGameFix's
  own it leaves them alone. The Windows side is moving into the library too,
  one module at a time: `setupapi.dll`'s change (a device's base container id
  as WCHAR from the ANSI function, which Nioh 3 needs) is made in memory on
  CodeWeavers' own file, a USB pad's container is made from where it is
  plugged in, as its audio output's is, when `winebus.sys` is CodeWeavers',
  CodeWeavers' `mmdevapi.dll` gives an audio output's container, which it
  never asked the driver for, the audio outputs are listed in SetupAPI, and
  an XAudio2 mastering voice opens the device the game names (the five
  changes are checked, not played yet). Played on 2026-11-26 with
  Marvel's Spider-Man 2 (Bluetooth and a cable), Crysis 3 Remastered and
  Crash Bandicoot 4.

The four libraries need NotProton's plugin host, which NotProton's own Update
installs, and the Unreal row a NotProton that reads `patch`. Where one cannot
work its row is taken out again. A row another plugin file already declares is
left alone, with its library, so a NotProton that ships the same plugins keeps
its own.

There is nothing to install by hand: the menu bar item puts them in place, and
so does the window each time it looks for games. The Improvements tab shows
whether each one is in place, or why it is not offered, and its **Put in Place**
button does now what the menu bar item would do on its next pass.

## Each game's compiled shaders, kept whole

A game compiles each shader the first time it draws with it, and Metal keeps the
result so that the next start does not compile it again. It keeps it under the
identifier of the app the game runs from, in one of four files
(`functions.data`, `functions1.data`, `functions2.data`, `functions3.data` in
`<user cache>/<bundle id>/com.apple.metal/<GPU and macOS>/`): a process takes
one that no other process holds, reads that one alone and adds to it. NotProton
starts each game from an app of its own (`com.notproton.launcher.<app id>`), and
Steam's launcher for the game runs from the same one, so two processes take a
file each, and which of them the game gets changes from one start to the next.
When it gets an empty one it compiles everything again. Metal makes a fifth file
(`functions4.data`), and more, when more processes use the app at once: Phantom
Blade Zero's had five on 2026-11-20, held by Wine's `explorer.exe`, Steam, the
game's launcher, the game and its crash handler, and the game had an empty one
while Steam held the full one. Every numbered file there is is copied over.
The copy is made on the agent's next look, within two minutes of the game
closing: a game started again sooner may still be handed an empty file.

Measured on 2026-11-18 with Ori and the Blind Forest: Definitive Edition on a
MacBook Pro M4 Max, under NotProton (CrossOver Preview's Wine, D3DMetal 4). The
game draws with every shader it has before it shows its menu:

| Start | Compiled | Taken from the cache | Before the first frame |
| --- | --- | --- | --- |
| First, nothing kept yet | all of them | 0 | about three minutes |
| Second, as macOS left the files | 3,650 | 1 | about half a minute |
| Third, the fullest file copied over the other three | 0 | 3,510 | under a second |

With **Improvements › Shaders** on, which it is unless you turn it off,
MacGameFix's agent does that copy for every game NotProton runs, once the game
and its launcher are closed: Metal keeps a lock on the file a process took, and
nothing is copied while any of the four is held. A copy is an APFS clone and
takes no space of its own until a game writes to it. What only a smaller file
held is compiled once more the next time the game draws it. Nothing is compiled
by MacGameFix, and no game file is changed.

CrossOver's own games are left alone: every game in every bottle shares one
folder (`com.codeweavers.CrossOver.wineloader`), each of its four files holds a
different mix of games, and copying one over the others would throw away what
the others hold.

This does nothing for the first time a game draws something; that compilation
still happens once. A game that compiles as it goes, such as Ori and the Will of
the Wisps, gets the other half of it: places already seen stop hitching again.

## A mod installer in a game's prefix

A mod installer or a mod manager made for Windows has to run inside the game's
prefix, with the same Wine the game runs on, to put its files where the game
looks. In the Games tab, select a game NotProton runs and open **Prefix** under
the table (or right-click its row): **Run a Program in This Game's Prefix…**
picks an exe, msi, bat or cmd file, starting in the game's folder, and runs it
with the game's own runner: the CrossOver build and FEX or Rosetta that the
game's Steam Play tool names, as NotProton's Prefixes › Run Program… does.
MacGameFix remembers the program for the game, so **Run <name> Again** starts
it next time in one click.

Quit the game first: nothing starts while the game, or anything else, runs in
its prefix, or while NotProton is setting the prefix up. What the program
printed is in `~/Library/Application Support/MacGameFix/prefix-runs/`. A mod
manager that starts the game itself starts it outside Steam, so the game then
runs without its launch options and NotProton's plugins; start the game from
Steam instead. CrossOver bottles are not offered: there, CrossOver's own Run
Command does this.

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

The links are made for the exes MacGameFix finds in the libraries of each
bottle's Steam and in each bottle's Program Files; a game elsewhere is not
covered. A library only the Mac's own Steam lists is NotProton's, and is left
out: NotProton runs its games from a bundle of its own. Game Feel's
options are read when the bottle starts, so in CrossOver change them before you
open Steam there (engine/README.md, "The options").

## The games

| Game | What the fix is for | Needs |
| --- | --- | --- |
| Beast of Reincarnation | Startup video plays with sound, no picture | D3DMetal, CrossOver Preview 27 |
| CONTROL Resonant | Lit rooms behind windows drawn in flat colours | D3DMetal |
| Cyberpunk 2077 | The MetalFX denoiser it ships is left off | The macOS version 2.5.0, an M3 or later |
| Devil May Cry 5 | Crashes when a skill preview plays | D3DMetal |
| FATAL FURY: City of the Wolves | Startup video plays with sound, no picture, and the game closes | D3DMetal, NotProton |
| DYNASTY WARRIORS: ORIGINS | Cutscenes with sound and no picture | D3DMetal, CrossOver Preview 27 |
| Forza Horizon 5 | Never leaves the loading screen after Xbox sign-in | D3DMetal 4, a prefix |
| Forza Horizon 6 | Sign-in, online, open world and races played at 60 fps; needs the launch options in its instructions | D3DMetal 4, Preview 41073 Rosetta improvement, a prefix |
| God of War | White specks on characters in dim light | D3DMetal or DXMT |
| God of War Ragnarök | Adaptive triggers never reach the pad | A DualSense or DualSense Edge, Bluetooth as a cable over Bluetooth |
| KINGDOM HEARTS Dream Drop Distance | Cutscenes with a solid green picture; a crash dialog on exit | D3DMetal, a prefix |
| KINGDOM HEARTS HD 1.5+2.5 ReMIX | The same, for the six titles of the package | D3DMetal, a prefix |
| Life is Strange: Double Exposure | Freezes after a while | D3DMetal 4 |
| Life is Strange: Reunion | Freezes after a while | D3DMetal 4 |
| Marvel's Spider-Man 2 | T-pose, a broken symbiote, black blocks in the sandstorm | D3DMetal |
| Mortal Kombat 11 | Dark smeared patches on bare faces once they animate; movies grey with purple and green bands, and choppy | D3DMetal (DirectX 12) or DXMT (DirectX 11) |
| Mortal Shell 2 | Crash on the first cutscene | D3DMetal |
| NieR Replicant ver.1.22474487139 | Crashes when the first video starts | D3DMetal, a prefix |
| NINJA GAIDEN 3: Razor's Edge | Will not start: "Insufficient VRAM" | DXVK, a prefix |
| NINJA GAIDEN 4 | Says the VP9 codec is missing, then exits; on D3DMetal 4, nothing is ever drawn | D3DMetal 3 or 4.0b3, CrossOver Preview 27 |
| Nioh | "Failure to play movie", then a crash | DXMT |
| Nioh 2 | Cutscene refuses to play, then a crash | DXMT |
| Nioh 3 | "Failed to play movie" | D3DMetal |
| Ori and the Will of the Wisps | Hitches whenever something new comes on screen | NotProton with a Rosetta runner, D3DMetal |
| Persona 5 Strikers | Video never starts; sound only | DXMT |
| Phantom Blade Zero | Never opens a window under Rosetta (Denuvo); black menu video | D3DMetal 4, the Wine modules on, a prefix |
| RESIDENT EVIL 2 | Crashes when a video plays | D3DMetal |
| RESIDENT EVIL 3 | Crashes when a video plays | D3DMetal |
| RESONANCE: A Plague Tale Legacy | "Shader Model 6.7 is not supported" | D3DMetal |
| TMNT: Splintered Fate | Opens a window, then closes | D3DMetal |
| The Witcher 3: Wild Hunt | Black screen at start; DLSS said to be unsupported | D3DMetal |
| Tormented Souls 2 | Fatal error before the first frame | D3DMetal |
| Wo Long: Fallen Dynasty | Cutscene with sound and a black picture | D3DMetal |

**Being tested.** These are listed only with **Show fixes being tested** on (see
[Fixes being tested](#fixes-being-tested)), since nobody here has played them yet:

| Game | What the fix is for | Needs |
| --- | --- | --- |
| Need for Speed Unbound | Black screen at start | D3DMetal, Steam build 16690907 |
| The Wolf Among Us Remastered | Anything that moves leaves faded copies behind | D3DMetal, a prefix |

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

### Switching away from a game: play in Borderless

A Windows game in exclusive fullscreen can stop drawing when you switch away with Cmd-Tab
and come back: the window is there and the game keeps running, but the picture no longer
changes. In fullscreen the game owns the display and has to set up its output again on its
way back, and under Wine and D3DMetal that step can fail. In a borderless window (the game's
**Borderless** or **Windowed Fullscreen** display mode) it is an ordinary window the size of
the screen, and Cmd-Tab only moves the focus.

So set every game you play this way to Borderless when it offers one. Seen on F1 25 under
NotProton (CrossOver Preview 41303 on Rosetta, 2026-11-25): in Fullscreen it stopped drawing
after a Cmd-Tab, in Borderless it switched back and forth without a problem. Steam's overlay
was off for the game at the time, so which of the two made the difference was not separated.

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

### Phantom Blade Zero needs the Wine modules

Under Rosetta its Denuvo spins one core and never opens a window: it checks the
CPU for CLFLUSHOPT, CLWB and RDPID, which Rosetta does not have. The Wine modules'
`ntdll.so` (engine patches `0017`, `0018` and `0020`, see
[engine/README.md](engine/README.md#rosettas-cpu-for-copy-protection)) shows them
to every process and emulates the two instructions. Modules from before `0020`
showed them only to a process that asked with `WINE_ROSETTA_CPUID7_OR`, so the fix
still asks for `PBZ.exe` alone, in the prefix's registry
(`AppDefaults\PBZ.exe\Environment`), where a game started by a Steam client that
was already running still finds it. It also loads Microsoft's Visual C++ runtime
before Wine's for it, which the game checks. Nothing goes into its folder, and no
launch option is needed.

Its menu video is H.264 played by Unreal's Electra, which takes NV12 frames and
nothing else. CrossOver's H.264 decoder does not offer NV12 on macOS (its CW HACK
26265) and says it is D3D aware, so the menu stays black. The fix puts
`msmpeg2vdec.dll` (built from `fixes/h264-software-decoder.c`) into the prefix's
`system32` and loads it for `PBZ.exe` alone: it serves the same decoder over
CrossOver's own and answers as winevideo's patch `0006` makes Wine answer, NV12
offered and no D3D awareness, so Electra decodes into system memory. The engine
is not changed, and the one file serves CrossOver 26.3 and Preview 27, whose
decoder code is the same there. CrossOver's file stays beside it as
`msmpeg2vdec.dll.mgvf-stock`.

TSR is the recommended upscaler: played on an M4 Max, it ran better than DLSS
(as felt in play, not measured). Either way one D3DMetal variable is needed.
With DLSS available (D3DMetal's default) PBZ turns on NVIDIA's opacity
micromaps, because D3DMetal's NVAPI says it supports them; D3DMetal then cannot
build them (`Unknown geometry type 2`) and the game closes as it loads a level,
whatever upscaler its menu has, TSR included. So:

- For TSR, turn DLSS off for the game (`D3DM_ENABLE_METALFX=0`) and choose TSR
  in its graphics settings.
- For DLSS, set `D3DM_SUPPORT_DXR=0`: with D3DMetal's ray tracing off the game
  does not ask for the micromaps, and DLSS works.

D3DMetal reads these from the macOS environment, which the prefix's registry
does not reach, so they go where the CrossOver that runs the game takes
variables:

- NotProton (a Steam Play prefix): the game's launch options in Steam,
  `D3DM_ENABLE_METALFX=0 %command%` for TSR, or `D3DM_SUPPORT_DXR=0 %command%`
  for DLSS.
- A CrossOver bottle: for TSR, CrossOver's own DLSS switch in the bottle's
  settings, off (it is `D3DM_ENABLE_METALFX`). For DLSS, the bottle's
  `cxbottle.conf`, under `[EnvironmentVariables]`, as
  `"D3DM_SUPPORT_DXR" = "0"`, with CrossOver closed. The Windows Steam inside a
  bottle does not read `VAR=value %command%` launch options, and every game of
  the bottle gets the variable, so a bottle of its own keeps ray tracing for the
  others.

In a CrossOver Preview 27 bottle, everything but DLSS's variable is in the
bottle's settings:

1. Turn the Wine modules on for CrossOver Preview in MacGameFix, and install
   this fix for the bottle.
2. In the bottle's settings: graphics D3DMetal, AVX on (every run played had it
   on), MSync on.
3. For TSR (recommended): turn DLSS off there, and choose TSR in the game.
4. For DLSS: leave DLSS on, quit CrossOver, add `"D3DM_SUPPORT_DXR" = "0"`
   under `[EnvironmentVariables]` in the bottle's `cxbottle.conf`, and open
   CrossOver again.

NotProton's pipeline cache (`NOTPROTON_ROSETTA_PIPELINE_CACHE`), on in every run
played, does not exist in a bottle. These steps have not been played yet.

It needs the Wine modules on for the CrossOver that runs it (CrossOver's own
`ntdll.so` ignores the value), the Intel side, and D3DMetal 4: CrossOver Preview
27 carries it, 26.3 carries 3.0, so PBZ is for Preview 27. Played on 2026-11-01
on Preview 41073's NotProton runner, first with the values as launch options for
32 minutes, then through this installer with CrossOver's own winegstreamer: the
menu video played from our decoder, the pad vibrated, and with
`D3DM_SUPPORT_DXR=0` a level loaded with DLSS on. The decoder DLL was measured
with a probe on all four CrossOvers: NV12 offered and the clip decoded (30 of 30
frames, 29 on the 26.3 runner), where CrossOver's own offers no NV12. In a
CrossOver bottle the game has not been played.

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

On CrossOver 26.3 with D3DMetal 3, D3DMetal keeps its D3D12 tables in memory
Wine cannot change, so the fix gives the device a copy of its table and hooks
that ([#28](https://github.com/MathiasKowoll/MacGameFix/issues/28)). The command
lists cannot take a copy, because the game crashed within a minute when they did.
So there the fix corrects the T-pose but adds no fog barrier, and the black blocks
in volumetric fog remain; `sm2-tpose-fix.log` says so. Played on 2026-10-25: four
minutes, characters right, no crash. With D3DMetal 4 the fix works as before.

### Ori and the Will of the Wisps downloads one thing too

Its installer compiles the game's shaders ahead of time with
[Ori Shader Warmer](https://github.com/macprotips/ori-shader-warmer) by
macprotips: a program that reads the shaders out of your own copy of the game,
one that draws them, and the list of about 90,000 combinations they recorded
from the game. Their release is downloaded once from their repository, checked
against a pinned sha256 and kept in `~/Library/Caches/MacGameFix`; MacGameFix
ships none of it.

It is for a game NotProton starts, with a Rosetta runner and D3DMetal. The
drawing runs with the runner NotProton made for the game, for 5 to 30 minutes
with the game closed, and the result goes under the game's own bundle
(`com.notproton.launcher.1057090`) and executable, where the running game was
seen to read it. Nothing another game uses is replaced. Under CrossOver every
bottle shares one Metal cache and a build for Ori replaces it, so the installer
refuses there; macprotips' own app does that.

Measured on 2026-11-18 on an M4 Max, from Metal's own record of the game:
1,123 shaders compiled in 222 seconds of play before, 70 of those seconds with
a frame more than 50 ms late; 6 compiled and 1,092 taken from the cache in 158
seconds after, 21 seconds with a frame that late. Compiling took 272 seconds.
The games row reads **Needs repair** once macOS, the runner or the game is
not what the shaders were compiled with: install again. It cannot be marked
Keep, so the agent never starts those minutes of compiling by itself while you
may be about to play. While it compiles, the
window shows a bar with the percentage, and a notification says when the game
is ready (see [A fix that takes minutes](#a-fix-that-takes-minutes)).

### God of War: the specks without the solid grass

God of War's white specks are fixed by loosening one depth test, and loosening it
for every draw also drew nearby grass and branches as solid shapes (reported
2026-10-22). The game writes a stencil reference per kind of object in that pass,
so the fix now loosens it only for references 0x01 and 0x03: characters and small
objects such as the axe on Kratos' back. Played on 2026-11-16 with DXMT and
`d3d11.defuseFma` on CrossOver Preview 27 (through Heroic, Epic edition): no
specks, grass and leaves drawn right, the axe steady. Played again on 2026-11-15
with D3DMetal under Rosetta, on NotProton's runner for CrossOver Preview 41303
(Steam edition): the same three references, no specks, grass and leaves drawn
right. `stencil_refs = all` in `gow-depth-fix.ini` brings back the earlier
behaviour. See [God of War](legacy/wiki/God-of-War.md).

### God of War Ragnarök sends its trigger effects to the pad

Under Wine, Steam tells Ragnarök it runs on a Steam Deck, and on a Steam Deck the
game never loads Sony's library: the adaptive-trigger effects it builds go to
its own `scePadSetTriggerEffect` wrapper, which drops them. A probe counted 979
in eight minutes on 2026-10-23, every one dropped. The fix puts a jump at that
wrapper and writes each effect to the pad as the DualSense's own trigger effect,
in an output report that carries only the trigger fields, so the rumble the
game sends through XInput, or Steam through Steam Input, is left alone. It
answers the game what the wrapper always answered, and on the game's exit it
releases the triggers.

- **Where it finds the code.** By the name the wrapper hands on: the one
  function that loads the address of the string `scePadSetTriggerEffect` and
  starts as the wrapper does. A game update that changed that code finds
  nothing, and the game runs as it does without the fix; `gowr-triggers.log`
  says so.
- **Which pad.** A DualSense or an Edge shown with the wired output report,
  which is what the Wine modules show on a cable and over Bluetooth with
  *Bluetooth as a cable*. Over Bluetooth without it, nothing is written. The
  Wine modules see the effect as the game's own, so a trigger effect chosen in
  Game Feel gives way on that trigger.
- **Played** on 2026-10-23 with Steam Input on and a DualSense Edge shown as a
  DualSense over Bluetooth: L2's vibration near the end of its travel came
  through. The effects seen in that play were all L2 vibration; R2 and the
  other modes are converted the way Sony documents them and were not seen.
  Not played on a cable, nor with a standard DualSense.
- **Steam Input on** is this game's configuration: the game then takes its
  controller and PlayStation buttons from Steam (see the vibration list).

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

## Fixes being tested

A fix someone else made, for a game MacGameFix has not played, comes first as a
fix being tested. **Settings > Testing > Show fixes being tested** lists those in
Games beside the others, marked *Testing*, with who is testing them in the game's
help. They install and remove like any fix. Say how one went with **It Works…** or
**Report**. Once it has been played, it loses the mark and is listed for everyone.

The switch is off by default, so a fix nobody has validated reaches only someone
who turned it on. In the repository, an installer marks it with
`# MGVF-TESTING: <who is testing it>`, and `build-app.sh` puts its game into
`games.json`'s `testing` table, which apps before 1.6.0 never read. Its
`# MGVF-CREDIT: <name> | <url>` lines name whose work it is, in the app and in
[Credits](#credits).

### A fix that takes minutes

An installer that works for minutes says how far it is. The app runs every
installer with `MGVF_PROGRESS=1`, and one that prints lines of
`MGVF-PROGRESS <done> <total>` then gets a bar in the window's status line,
with the percentage, instead of those lines in the log. An install that took
30 seconds or more ends with a notification: the fix is installed and the game
is ready, or it did not finish. Closing the window does not stop it: the app
quits once the install is done. Ori and the Will of the Wisps' is the first.

Such a fix is installed from the window only. Its installer says so with
`# MGVF-BY-HAND: <why>`; `build-app.sh` puts it into `games.json`'s `byHand`
table, which apps before this field never read, so no app that could keep it
lists it. Its Keep box is off and cannot be checked, its tooltip gives the
reason, and the agent skips it even if an older setting kept it.
Without `MGVF_PROGRESS`, as from a terminal, the installer prints its progress
in words.

## Reporting a problem

[Open an issue](https://github.com/MathiasKowoll/MacGameFix/issues/new/choose) with the form that fits:

- **A game that does not work**, with a fix of ours or without one. In the **Report** tab, click the game and
  choose what goes wrong. MacGameFix reads the game's folder, without changing anything in it, and says what
  it is made of: its executable and the DLLs it imports, the graphics API, the engine, how it reads a
  controller, its videos by container and codec, its middleware and any anti-cheat. Follow the steps it gives
  for what goes wrong, then click **Save the Report and Open an Issue…** and attach the file to the form
  that opens. The report adds the game's own log when it writes one (Unreal's `Saved/Logs`, Unity's
  `Player.log`) and what the Wine modules saw of it. It names that game alone, writes your home folder as
  `~` and leaves your Mac's name out: of the CrossOver bottles whose Steam lists the game's library, it
  names only one that holds the game, and counts the others.
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
  controller, the connection and what the pad was shown to the game as (a DualShock 4 or a DualSense), as
  the Wine modules saw them in its latest session, what they saw it do, and the library it reaches the pad
  through, guessed from its folder; say what you felt and attach the file. One report is one controller on
  one connection: played on a cable and over Bluetooth, send two. Reports like this make the
  [list of games played for vibration](docs/vibration.md).
- **A game fix does not work.** Copy the lines about the game from **Settings › Log** into the form.
- **A game fix works**, for the list of verified games. Play the moment the fix is for with the fix
  installed and close the game. In **Games**, select the game (its state *Installed*) and click **It
  Works…**, under the table. It saves the game's fix report and opens the form with the game, the
  versions and the fix's own log filled in, where it runs when the game's folder shows it (a Steam Play
  prefix of its own with a NotProton runner on the Mac, CrossOver bottles alone, or a macOS game), and the
  game's build when it is known. Choose the graphics backend the game ran on, which MacGameFix does not
  read, say what you played and whether it was tried without the fix, and attach the file. The fix's own
  log and the **Settings › Log** lines each go into the form when they fit in the link; what does not fit
  is in the report, and the form says so. The report is the **Report** tab's for the game with a section
  on the fix: what its installer's `--status` says, the files where it goes that are the catalog's by
  their SHA-256, the CrossOver apps or NotProton runners of the kind the game runs in with the D3DMetal
  builds each carries, this Mac's model, chip and macOS, the last 200 lines of the log the fix writes
  beside its DLL (Mortal Kombat 11's, Marvel's Spider-Man 2's and God of War's write one), and the
  window's **Settings › Log** lines for the game, which it keeps only while it is open. It writes your
  home folder as `~`, leaves your Mac's name out, and names no CrossOver bottle but one that holds the
  game or that the fix went into. A game is verified from what was played, not from what should work.
- **A game works without its fix**, on a newer Game Porting Toolkit or CrossOver. Remove the fix first
  (**Remove Selected** in **Games**), play the moment it was for, close the game, then select it (now
  *Not installed*) and click **Works Without the Fix…**. It saves the same report and opens the form with
  the game and the versions filled in, and the Game Porting Toolkit when the places it runs from carry one
  D3DMetal only. Reports like this are what mark a fix as no longer needed from a toolkit on.

## Opening it the first time

A download that Apple has notarised is expected to open as any app from the
internet does: macOS asks once, and *Open* opens it. That is not measured yet:
no MacGameFix build has been notarised so far. One that is not notarised is
blocked on its first launch: the releases signed ad hoc, before the Developer
ID, and an app built without one (see below). For those, on macOS 14, **Right
click > Open** once, and confirm. On macOS 15 and later Apple's notes say that
no longer opens it: open it once, then click **Open Anyway** in System Settings
› Privacy & Security, and confirm. That is Apple's word; it has not been tried
with MacGameFix.

## Building it

```
app/build-app.sh
```

It compiles the app, chooses the games as described above, copies the
installers and every file they name from `fixes/` unchanged, and fails if the
bundle differs from `fixes/` in a single byte.

**Signing.**
- **The identity:** `MACGAMEFIX_CODESIGN_IDENTITY` (a Developer ID Application
  identity's name or SHA-1), else the keychain's first "Developer ID
  Application" identity (`security find-identity -v -p codesigning`), else ad
  hoc, which the build says. `MACGAMEFIX_CODESIGN_IDENTITY=-` asks for ad hoc.
  With an identity the app is signed with the hardened runtime and a secure
  timestamp, and the build checks that every Mach-O in the bundle carries the
  same team's Developer ID, a timestamp and the runtime
  (`tools/check-signatures.sh`). The app has no entitlements: read from the
  code, it does nothing the hardened runtime asks one for (`build-app.sh` says
  what it does), and the agent's paths in `app/test-automation.sh` run under
  it; the window and the pad test have not been run under it yet.
- **The Mach-O files it carries:** `fixes/sm2-shadertool` and each
  `engine/modules/<build>/<arch>-unix/*.so` are signed in the repository, not
  in the app, since the bundle's copies must stay byte for byte what `fixes/`
  and each `built-for.json` hold. `tools/sign-payload.sh` signs them with the
  same identity, keeps each file's identifier and code (`otool -t` the same
  before and after) and writes the new hashes into `built-for.json`. Run it
  after `engine/build.sh` writes modules without `MACGAMEFIX_CODESIGN_IDENTITY`,
  or after `sm2-shadertool` is built again, and before committing them. A file
  already signed with this team's Developer ID, a secure timestamp and the
  runtime is left alone, so running it again changes nothing.
  `fixes/check-builds.sh` checks those signatures on any Mac, with an identity
  or without, so a file signed ad hoc again does not pass unseen where the
  build signs ad hoc.

**Notarising it.** `app/notarize.sh` sends the built app to Apple's notary
service and waits for the answer. Its credentials are an App Store Connect API
key named in `~/.config/macgamefix/notary.conf` (`$MACGAMEFIX_NOTARY_CONF`),
outside the repository and readable by its owner alone (`chmod 600`, the
`.p8` too):

```
KEY=~/.config/macgamefix/AuthKey_<key id>.p8
KEY_ID=<key id>
ISSUER=<issuer id>
```

Without that file, they are the notarytool keychain profile
`$MACGAMEFIX_NOTARY_PROFILE` (`itsomax-desktop-notary` unless set, made with
`xcrun notarytool store-credentials`). The file came after the profile vanished
from the build Mac four times, with nothing in this repository deleting it.
- **Accepted:** it staples the ticket to the app, checks it with `xcrun stapler
  validate` and `spctl`, and writes `app/dist/MacGameFix-<version>.zip` and its
  `.sha256`, the app assets of the release. Run it after `build-app.sh`, which
  empties `app/dist` when it writes the catalogs there.
- **Refused:** it saves Apple's log in `app/dist` and fails. When Apple answers
  that a required agreement is missing, the team's account holder has to accept
  it at developer.apple.com first, and it says so.
- **Before sending:** it refuses an app signed ad hoc, or one with a Mach-O
  that lacks the Developer ID or the secure timestamp, which Apple asks of every
  Mach-O, or the runtime, which Apple asks of the executables and MacGameFix
  puts on every Mach-O so that all are signed one way. `--dry-run` checks and
  zips the app and sends nothing. `app/test-notarize.sh` takes it through every
  answer with a fake `xcrun`, `spctl` and `ditto`, offline.
- **The assets:** they are written and checked in a temporary folder first,
  and replace the ones in `app/dist` only once the copy in the zip validates;
  any failure leaves `app/dist` as it was.

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

**The service that says whether there is a newer app.**
- **What the build needs:** `~/.config/macgamefix/updates.conf` (or
  `$MACGAMEFIX_UPDATES_CONF`) with two lines, `BASE=https://…` for where the
  service is and `SECRET=…` for the key of the app's OAuth client there. The
  build writes both into the app's `Info.plist` and says which service it
  named.
- **Without it:** the build says so, and the app asks GitHub's latest release
  instead. Nothing else changes.
- **The key is not a secret once it ships:** it is in every copy of the app.
  It names the app to the service, which lets that client read the table of
  versions and nothing more. It never enters the repository.
- **The tests never reach it:** with `MACGAMEFIX_APP_SOURCE` set, as
  `test-automation.sh` sets it, the app leaves the address it was built with
  alone and asks only a service the test names (`MACGAMEFIX_UPDATES_BASE`).

**What an update brings.** `fixes/WHATS-NEW.txt` and `engine/WHATS-NEW.txt` hold,
a line for each thing, what the catalog being built brings since the one
before it, in words for whoever plays. The build puts them into `catalog.json`
and `modules.json` as `notes`, under the signature. Rewrite them with every
change, before building: what stays there is said again with the next catalog.
A new app's come from its release notes: the bold lead of each item is what the
notice and the notification show.

**A change to the fixes or the Wine modules alone needs no new app.** Installed
apps take each catalog from the latest release on their own, so the release
stays and only that catalog's three files are replaced. A new version is for a
change to the app itself.
1. Merge the change into main and build from main. The build writes both
   catalogs in `app/dist`, each with a new version.
2. Run `fixes/test-installers.sh` and `fixes/check-builds.sh`, and compare the
   new `catalog.json` (or `modules.json`) with the one on the release: only the
   files of the change differ, and `minimumApp` is the same.
3. Replace only that catalog's files on the latest release:
   `gh release upload <tag> --repo MathiasKowoll/MacGameFix --clobber
   app/dist/catalog.json app/dist/catalog.json.sig app/dist/catalog.zip`
   (or the three `modules.*` files).
4. Download them again and compare them with `app/dist`, then let an installed
   app take them in a throwaway home:
   `MACGAMEFIX_HOME=$(mktemp -d) MacGameFix --update-from <folder>` must say it
   installed the new catalog, which proves the signature.
5. Add a dated section to the release notes, *Fixes updated, <date>* or *Wine
   modules updated, <date>*, naming the commit and the pull request, what
   changed and what was not played yet. The tag does not move: the app did not
   change.

Apps then take it within a day, or at once with *Check for New Fixes* in the
menu bar or *Check Now* in Improvements. First done on 2026-10-22, for Mortal
Kombat 11's movies (#14) in 1.5.6.

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
the MGVF-GAME lines with `process-features.json`, the MGVF-LOG lines with the
DLLs, and a built app's copies with `fixes/`. It also checks that `sm2-shadertool` and the Wine modules' unix
halves carry MacGameFix's Developer ID, a secure timestamp and the hardened
runtime.

Forza Horizon has dedicated builders because the D3D12 proxies have an unusual
forwarding layout: `build-fh5-d3d12.sh` and `build-fh6-d3d12.sh` build separate
profiles from the GPL sources under `fh5-d3d12/` and the retained FH6 instrumentation baseline under `fh6-d3d12/`. The FH6 profile omits FH5's
descriptor translation and FH5-only guards. `build-fh5-netfix.sh` generates the
exact `ws2_32` export table of its target runner before building FH5's separate
`ws2_32-fh5.dll`.

## How each fix is made

Every fix is one installer in `fixes/` and the files it puts in the game
folder; Cyberpunk 2077's puts none there, and changes four bytes of the game's
executable instead, from a recipe. A proxy DLL takes the name of a DLL the
game already loads, keeps the game's own as `<name>_real.dll`, and forwards
every export to it; the source named below is the code that runs inside it.
The source of each shipped DLL is the one that writes the log name the DLL
carries, which is how `fixes/check-builds.sh` finds it. A DLL that writes its log
beside itself, in the game folder, has it named on its installer's MGVF-LOG line,
so that a fix's report carries it. What was found, and
how, is in the game's page under `legacy/wiki/`.

| Installer | Games | What goes in the game folder | Built from | Findings |
| --- | --- | --- | --- | --- |
| `install-runtime-fix.sh` | Beast of Reincarnation, FATAL FURY: City of the Wolves, Life is Strange: Double Exposure, Life is Strange: Reunion, Mortal Shell 2 | `libogg_64.dll` under `Engine/Binaries/ThirdParty/Ogg/Win64` | `ue5-media-fix.c` | [Beast](legacy/wiki/Beast-of-Reincarnation.md), [Double Exposure](legacy/wiki/Life-is-Strange-Double-Exposure.md), [Reunion](legacy/wiki/Life-is-Strange-Reunion.md), [Mortal Shell 2](legacy/wiki/Mortal-Shell-2.md) |
| `install-ctl-fix.sh` | CONTROL Resonant | `PxFoundation_x64.dll` (from `PxFoundation_x64-ctl.dll`) | `ctl-window-fix.c` | [CONTROL Resonant](legacy/wiki/Control-Resonant.md) |
| `install-cp2077-denoiser.sh` | Cyberpunk 2077 | Nothing beside the game: four bytes of `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`, at the offset its build's row in `cp2077-denoiser.recipes` names, and the app signed again ad hoc; the original kept in MacGameFix's `app-backup` folder | Not built: a recipe for each game build, and none of CD PROJEKT's code ships | [Its section](#cyberpunk-2077-changes-four-bytes-of-its-app) |
| `install-re-vc1-fix.sh` | Devil May Cry 5, RESIDENT EVIL 2, RESIDENT EVIL 3 | `amd_ags_x64.dll` (from `amd_ags_x64-dmc5.dll`, or `amd_ags_x64-re2.dll` for both RE titles), and the reader | `mf-reader-fallback.c` | [RE Engine VC-1](legacy/wiki/RE-Engine-VC1.md) |
| `install-dwo-bridge.sh` | DYNASTY WARRIORS: ORIGINS, Wo Long: Fallen Dynasty | `libxess.dll` | `dwo-video-bridge.c` | [DYNASTY WARRIORS: ORIGINS](legacy/wiki/Dynasty-Warriors-Origins.md), [Wo Long](legacy/wiki/Wo-Long-Fallen-Dynasty.md) |
| `install-fh5-fix.sh` | Forza Horizon 5 | `d3d12.dll` (from `d3d12-fh5.dll`); the runner and prefix receive a private `apd12` alias made from their own D3DMetal, and the prefix receives the source-built Xbox UDP proxy | `fh5-d3d12/`; `fh5-netfix.c` | [Forza Horizon 5](legacy/wiki/Forza-Horizon-5.md) |
| `install-fh6-fix.sh` | Forza Horizon 6 | `d3d12.dll` (from `d3d12-fh6.dll`); the runner and prefix receive a private `apd12` alias made from their own D3DMetal | `fh5-d3d12/`, built with its FH6 profile | [Forza Horizon 6](legacy/wiki/Forza-Horizon-6.md) |
| `install-gow-fix.sh` | God of War | `libSceJobManager.dll` (from `libSceJobManager-gow.dll`) and `gow-depth-fix.ini` | `gow-depth-fix.c` | [God of War](legacy/wiki/God-of-War.md) |
| `install-gowr-triggers.sh` | God of War Ragnarök | `bink2w64.dll` (from `bink2w64-gowr.dll`) | `gowr-triggers.c` | [Its section](#god-of-war-ragnarök-sends-its-trigger-effects-to-the-pad) |
| `install-kh-bridge.sh` | KINGDOM HEARTS Dream Drop Distance, KINGDOM HEARTS HD 1.5+2.5 ReMIX | `dinput8.dll` (from `dinput8-kh.dll`); the original is the bottle's or prefix's own `dinput8`, copied beside it | `dwo-video-bridge.c` | [KINGDOM HEARTS](legacy/wiki/Kingdom-Hearts.md) |
| `install-sm2-fix.sh` | Marvel's Spider-Man 2 | `amd_ags_x64.dll` (from `amd_ags_x64-sm2.dll`), and shaders rewritten from the game's own executable by `sm2-shadertool` | `sm2-tpose-fix.c` with `sm2fix_core.c`; the tool from `sm2-shadertool.c` and `sm2-shaderfix.c` | [Spider-Man 2](legacy/wiki/Spider-Man-2.md) |
| `install-mk11-fix.sh` | Mortal Kombat 11 | `amd_ags_x64.dll` under `Binaries/Retail` (from `amd_ags_x64-mk11.dll`) | `mk11-face-fix.c` with `sm2fix_core.c`, `mk11-morph-shaders.h` (from `mk11-morph/`) and `mk11-movie.c` | [Mortal Kombat 11](legacy/wiki/Mortal-Kombat-11.md) |
| `install-nier-bridge.sh` | NieR Replicant ver.1.22474487139 | `dinput8.dll` (from `dinput8-nier.dll`), the original copied from the bottle or prefix, and the reader | `dwo-video-bridge.c` | [NieR Replicant](legacy/wiki/NieR-Replicant.md) |
| `install-ng3-fix.sh` | NINJA GAIDEN 3: Razor's Edge | Nothing: `d3d9.dll`, `qasf.dll`, `quartz.dll` and `winegstreamer.dll` (from `ng3-*.dll`) go into the prefix's `system32`, the prefix's own kept aside, with overrides for the game's executable | Not built here: d9vk v1.10.3-20250511 and winevideo 0.5's Wine builds, checked by their hashes in `ng3-THIRD-PARTY-LICENCES.md` | [NINJA GAIDEN 3](legacy/wiki/Ninja-Gaiden-3-Razors-Edge.md) |
| `install-ng4-fix.sh` | NINJA GAIDEN 4 | `dstorage.dll` (from `dstorage-ng4.dll`); `dstoragecore.dll` renamed aside | `tools/ng4-observe.c`, built with `-DNG4_FIX` | [NINJA GAIDEN 4](legacy/wiki/Ninja-Gaiden-4.md) |
| `install-nioh-bridge.sh` | Nioh, Nioh 2 | `GfeSDK.dll`, and the reader | `p5s-video-bridge.c` | [Nioh](legacy/wiki/Nioh.md), [Nioh 2](legacy/wiki/Nioh-2.md) |
| `install-nioh3-bridge.sh` | Nioh 3 | `amd_ags_x64.dll` (from `amd_ags_x64-nioh3.dll`), and the reader | `dwo-video-bridge.c` | [Nioh 3](legacy/wiki/Nioh-3.md) |
| `install-pbz-fix.sh` | Phantom Blade Zero | Nothing: ten registry values for `PBZ.exe` in the prefix (the CPUID bits the Wine modules' `ntdll.so` adds, native-first overrides for its Visual C++ runtime and for the decoder) and `msmpeg2vdec.dll` in its `system32` (from `msmpeg2vdec-sw.dll`) | `h264-software-decoder.c`; the engine's `ntdll.so` does the rest (`engine/patches/*/0017`, `0018`) | [Its section](#phantom-blade-zero-needs-the-wine-modules) |
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

- **`fh5-d3dmetal-fix` by xvferxedd** (GPL-3.0), originally at
  `github.com/xvferxedd/fh5-d3dmetal-fix`, a repository that is no longer
  online: the Forza Horizon 5 descriptor translation, D3D12 compatibility work
  and Xbox UDP diagnosis from which both source-built proxies derive.
- **[fh5-crossover-steam-fix](https://github.com/Andytizer/fh5-crossover-steam-fix)
  by Andytizer**, whose v1.0.1 preserved that source
  ([`upstream/source`](https://github.com/Andytizer/fh5-crossover-steam-fix/tree/main/upstream/source)),
  so it could be built here at all.
- **[Highball](https://github.com/gauthierpiarrette/highball) by Gauthier
  Piarrette** (GPL-3.0): the `tsshim` base, FH6 recipe and D3DMetal measurements
  behind the Forza Horizon proxies.
- **MACxus**, credited by xvferxedd for the FH5 profile: the NVIDIA identity
  the launch options still carry.
- **[witcher3-crossover-fix](https://github.com/tholtman1-del/witcher3-crossover-fix)
  by tholtman1-del** (MIT): the diagnosis of The Witcher 3's black screen and
  the rule that refuses the pipeline.
- **sbhaleraoopen** ([issue 26](https://github.com/MathiasKowoll/MacGameFix/issues/26)):
  the check that kept The Witcher 3's frame generation off under Wine, and the
  bytes it is found by; **maple-quartz18** confirmed them on 5.01c.
- **[SpiderMan2Fix](https://github.com/macprotips/SpiderMan2Fix) by macprotips.**
  The Spider-Man 2 fix is theirs; this adds a carrier that needs no DLL override,
  and a barrier after the volumetric fog copy.
- **[NFSUnboundFix](https://github.com/macprotips/NFSUnboundFix) by macprotips.**
  Need for Speed Unbound's fix is theirs: the cause in the shader pre-build and
  the six changes, which the recipe carries byte for byte. It improves on the
  first fix, by Ariel O in CodeWeavers' compatibility database, spread on Reddit
  by u/ales_sandr.
- **[Ori Shader Warmer](https://github.com/macprotips/ori-shader-warmer) by macprotips.**
  Ori and the Will of the Wisps' fix is theirs: the cause, the recorded list of
  combinations and the two programs. The installer downloads their release and
  runs it for a game NotProton starts.
- **[WolfAmongUsFix](https://github.com/macprotips/WolfAmongUsFix) by macprotips**
  (public domain): The Wolf Among Us Remastered's diagnosis and the `d3d11.dll`
  it installs, shipped as published with its source.
- **The God of War fix** comes from a r/macgaming post, "God Of War 2018 White
  Dot Fix (through Crossover)", whose author found the depth test behind the
  white specks.
- **[tombirdQAQ](https://github.com/tombirdQAQ)** found that God of War writes
  a stencil reference per kind of object in that pass, and made the fix loosen
  the test only for the characters' and small objects', so the grass is no
  longer drawn as solid shapes (#82).
- **[winevideo](https://github.com/Jfishin/winevideo)'s author** found why
  NINJA GAIDEN 3's movies never start (Wine's ASF Reader blocks its audio
  behind the video) and built the patched `qasf`, `quartz` and `winegstreamer`
  its fix installs (LGPL-2.1-or-later).
- **[d9vk](https://github.com/Sikarugir-App/d9vk) by Sikarugir-App** (zlib):
  the Direct3D 9 that NINJA GAIDEN 3 runs on.
- **Hrava** wrote the ntdll patch that makes Rosetta's CPU look like the one
  Phantom Blade Zero's Denuvo checks for (engine patch `0017`), which reached us
  in a package for that game with the D3DMetal fallback (`0018`).
- **[prsloan](https://github.com/prsloan)** found why Forza Horizon 6 never
  joined an online session on a Mac (two IPv4 options that macOS refuses on the
  game's dual-stack UDP socket) and wrote the ntdll patch that answers them
  (engine patch `0026`, #73), with its probes.
- **[NotProtonNot](https://github.com/NotProtonNot)**, NotProton's creator,
  wrote the four patches that let 2XKO through its copy protection under Rosetta
  (engine patches `0032` to `0035`: writecopy page-file views, drawing into
  another process's top-level window, device paths from GetMappedFileNameW and
  a GetPointerDevice stub), and handed them to us (#117, #119).
  They also found what Red Dead Online needs to connect on a Mac (TCP connections
  without TCP options) and handed us that fix too (engine patch `0037`, #129).
  They found that FATAL FURY: City of the Wolves needs the Unreal fix with all
  three halves on, and handed us the change that adds it.
  They ported four of MacGameFix's fixes to NotProton plugins, which MacGameFix
  carries as they wrote them (`app/notproton-plugins/`).
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
