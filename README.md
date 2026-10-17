# MacGameFix

Fixes for Windows games on a Mac that go into the game's own folder, and the
small macOS application that installs, checks and removes them.

None of them changes CrossOver. They work with CrossOver as CodeWeavers ships
it, with CrossOver Preview, and with Steam Play tools for macOS such as
[NotProton](https://github.com/NotProtonNot/NotProton): a proxy DLL beside the
game, and for a few titles registry keys in the game's own prefix.

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
| `app/` | The application: `Core.swift` (installers, games, libraries), `Runtime.swift` (what each game runs on), `Automation.swift` (the background agent, signed catalog updates, reports), `MenuBar.swift` (the agent's menu bar item), `MacGameFix.swift` (the window), `AppIcon.icon` (the icon); `build-app.sh` and `test-automation.sh`. |
| `fixes/` | One installer per fix (`install-*.sh`), the DLLs they put in place, the C source of each DLL and the scripts that build them (`build-proxy.sh`, `build-asf-reader.sh`, `check-builds.sh`), and the third-party notices. |
| `process-features.json` | The table: per game executable, its symptom, backend, toolkit, codec and engine needs. The app is built from it. |
| `tools/` | The probes and capture scripts the fixes were found with: video and Media Foundation observers, HID traces, a game survey. |
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

## What each game runs on

A fix is made for one graphics backend (D3DMetal or DXMT) and, for some games,
one CrossOver or toolkit version. From 1.4.0 the app looks at what each game is
set to run on and compares it with the table:

- **With a Steam Play tool** (NotProton): the tool Steam is told to use for the
  game, the CrossOver build that tool runs, the D3DMetal version inside it, and
  `CX_GRAPHICS_BACKEND` in the game's launch options. Without that variable
  CrossOver runs Direct3D 11 and 12 games on D3DMetal. A tool that runs on FEX
  has no D3DMetal.
- **In a CrossOver bottle:** the bottle's CrossOver version, the matching
  CrossOver app's D3DMetal, and the bottle's own `CX_GRAPHICS_BACKEND`.

Each game then shows one line, *Runs on*, and one of:

- **Fits** what the game runs on.
- **Not needed:** the game plays without the fix on what it runs on.
- **Does not fit,** and what to change. For example, God of War's fix is made
  for DXMT, so a game set to D3DMetal says `CX_GRAPHICS_BACKEND=dxmt`.
- **Cannot tell,** when nothing on the Mac says it: a game more than one place
  could run, or a FEX tool with no backend set.

In the last two cases *Change…* lets you say what the game runs on, and your
word is kept over what the app finds. The app asks before installing a fix that
does not fit or is not needed. The background agent installs a fix by itself
only when it fits, and says once why it left any other alone. `MacGameFix --runtime-report` prints the same lines in a terminal.

## Keeping fixes applied, and new fixes

From version 1.4.0 the app can look after the fixes by itself. All of it is off
until you turn it on, and the fixes stay in the games' own folders as before.

- **Keep it applied.** Mark a game with *Keep it applied*, and turn on *Run in
  the background, from the menu bar*. That starts a small agent (a LaunchAgent,
  `io.github.macgamefix.agent`) that starts when you log in and looks at the
  marked games every two minutes. When Steam updates or verifies a game and its
  fix is gone, the agent installs it again. It waits until the game is closed
  and Steam has finished writing it.
- **The menu bar.** The agent lives there as a raccoon. Its menu is a summary,
  however many games are marked: how many fixes are in place, to review,
  left alone because they do not fit, or not looked at yet. A count you can act
  on opens the window on those games; the window has the detail. The menu also
  looks at every game or for new fixes on demand.
  - A dot by the raccoon's ear means something new to look at: new fixes, a fix
    that failed, or one left alone. It goes away when you open the window.
  - *Quit MacGameFix* stops the agent until you log in again or open the
    window. If it crashes, it starts again by itself.
- **New fixes.** With *Get new fixes from GitHub* on, the agent looks at the
  latest release of this repository once a day. When the release carries a newer
  catalog of fixes, the agent takes it without a new app: the installers and
  every file they use.
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

## The games

| Game | What the fix is for | Needs |
| --- | --- | --- |
| Beast of Reincarnation | Startup video plays with sound, no picture | D3DMetal, CrossOver Preview 27 |
| CONTROL Resonant | Lit rooms behind windows drawn in flat colours | D3DMetal |
| Devil May Cry 5 | Crashes when a skill preview plays | D3DMetal |
| DYNASTY WARRIORS: ORIGINS | Cutscenes with sound and no picture | D3DMetal, CrossOver Preview 27 |
| God of War | White specks on characters in dim light | DXMT |
| KINGDOM HEARTS Dream Drop Distance | Cutscenes with a solid green picture; a crash dialog on exit | D3DMetal, a prefix |
| KINGDOM HEARTS HD 1.5+2.5 ReMIX | The same, for the six titles of the package | D3DMetal, a prefix |
| Life is Strange: Double Exposure | Freezes after a while | D3DMetal 4 |
| Life is Strange: Reunion | Freezes after a while | D3DMetal 4 |
| Marvel's Spider-Man 2 | T-pose, a broken symbiote, black blocks in the sandstorm | D3DMetal |
| Mortal Kombat 11 | Dark smeared patches on bare faces once they animate; faint ones remain with the fix | D3DMetal, DirectX 12 |
| Mortal Shell 2 | Crash on the first cutscene | D3DMetal |
| NieR Replicant ver.1.22474487139 | Crashes when the first video starts | D3DMetal, a prefix |
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
that declares a game-folder fix, and keeps the games for which the table
records no engine requirement, and either no codec or a CrossOver that ships
that codec as CodeWeavers distributes it.

**Measured, and what was not.** Every fix here was measured on a CrossOver 26.3
that carried MacGameVideoFix's engine patches, which do not touch these fixes;
Spider-Man 2, God of War and Mortal Kombat 11 on CrossOver Preview 27 through NotProton.
For Wo Long, Nioh 3 and KINGDOM HEARTS Dream Drop Distance, that the fix needs
nothing of the engine is read off how it works, not established by a run on an
untouched CrossOver.

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
- what a game runs on, read from a fake Steam Play setup, and the user's choice
  over it;
- while Steam writes the game and while the game runs;
- an older build of a fix replaced with the catalog's;
- a failing installer's report.

`fixes/test-installers.sh` takes every folder installer through its life on
throwaway folders, with no game needed: installed, an older build, updated,
restored to the game's own file, and an older or missing reader where a fix
has one.

**Building a fix's DLL.** `fixes/build-proxy.sh` and
`fixes/build-asf-reader.sh` need llvm-mingw (or another x86_64-w64-mingw32
toolchain). Users never run them: the built DLLs are in `fixes/` and ship in the
app. `fixes/check-builds.sh` rebuilds each DLL from its source and compares the
two, checks the third-party ones against their recorded sha256, and compares
the MGVF-GAME lines with `process-features.json` and a built app's copies with
`fixes/`.

## How each fix is made

Every fix is one installer in `fixes/` and the files it puts in the game
folder. A proxy DLL takes the name of a DLL the game already loads, keeps the
game's own as `<name>_real.dll`, and forwards every export to it; the source
named below is the code that runs inside it. The source of each shipped DLL is
the one that writes the log name the DLL carries, which is how
`fixes/check-builds.sh` finds it. What was found, and how, is in the game's
page under `legacy/wiki/`.

| Installer | Games | What goes in the game folder | Built from | Findings |
| --- | --- | --- | --- | --- |
| `install-runtime-fix.sh` | Beast of Reincarnation, Life is Strange: Double Exposure, Life is Strange: Reunion, Mortal Shell 2 | `libogg_64.dll` under `Engine/Binaries/ThirdParty/Ogg/Win64` | `ue5-media-fix.c` | [Beast](legacy/wiki/Beast-of-Reincarnation.md), [Double Exposure](legacy/wiki/Life-is-Strange-Double-Exposure.md), [Reunion](legacy/wiki/Life-is-Strange-Reunion.md), [Mortal Shell 2](legacy/wiki/Mortal-Shell-2.md) |
| `install-ctl-fix.sh` | CONTROL Resonant | `PxFoundation_x64.dll` (from `PxFoundation_x64-ctl.dll`) | `ctl-window-fix.c` | [CONTROL Resonant](legacy/wiki/Control-Resonant.md) |
| `install-re-vc1-fix.sh` | Devil May Cry 5, RESIDENT EVIL 2, RESIDENT EVIL 3 | `amd_ags_x64.dll` (from `amd_ags_x64-dmc5.dll`, or `amd_ags_x64-re2.dll` for both RE titles), and the reader | `mf-reader-fallback.c` | [RE Engine VC-1](legacy/wiki/RE-Engine-VC1.md) |
| `install-dwo-bridge.sh` | DYNASTY WARRIORS: ORIGINS, Wo Long: Fallen Dynasty | `libxess.dll` | `dwo-video-bridge.c` | [DYNASTY WARRIORS: ORIGINS](legacy/wiki/Dynasty-Warriors-Origins.md), [Wo Long](legacy/wiki/Wo-Long-Fallen-Dynasty.md) |
| `install-gow-fix.sh` | God of War | `libSceJobManager.dll` (from `libSceJobManager-gow.dll`) and `gow-depth-fix.ini` | `gow-depth-fix.c` | [God of War](legacy/wiki/God-of-War.md) |
| `install-kh-bridge.sh` | KINGDOM HEARTS Dream Drop Distance, KINGDOM HEARTS HD 1.5+2.5 ReMIX | `dinput8.dll` (from `dinput8-kh.dll`); the original is the bottle's or prefix's own `dinput8`, copied beside it | `dwo-video-bridge.c` | [KINGDOM HEARTS](legacy/wiki/Kingdom-Hearts.md) |
| `install-sm2-fix.sh` | Marvel's Spider-Man 2 | `amd_ags_x64.dll` (from `amd_ags_x64-sm2.dll`), and shaders rewritten from the game's own executable by `sm2-shadertool` | `sm2-tpose-fix.c` with `sm2fix_core.c`; the tool from `sm2-shadertool.c` and `sm2-shaderfix.c` | [Spider-Man 2](legacy/wiki/Spider-Man-2.md) |
| `install-mk11-fix.sh` | Mortal Kombat 11 | `amd_ags_x64.dll` under `Binaries/Retail` (from `amd_ags_x64-mk11.dll`) | `mk11-face-fix.c` with `sm2fix_core.c` | [Mortal Kombat 11](legacy/wiki/Mortal-Kombat-11.md) |
| `install-nier-bridge.sh` | NieR Replicant ver.1.22474487139 | `dinput8.dll` (from `dinput8-nier.dll`), the original copied from the bottle or prefix, and the reader | `dwo-video-bridge.c` | [NieR Replicant](legacy/wiki/NieR-Replicant.md) |
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
  War's depth test was found in a r/macgaming post. See Credits.
- **Sources no shipped fix builds from:** `ue5-runtime-fix.c` and
  `electra-h264-fix.c` (earlier sources of the Unreal fix, whose builds
  `install-runtime-fix.sh` still recognises), `sleep-yield-fix.c`
  (METAL GEAR SOLID 4) and `hide-wine.c`. NINJA GAIDEN 3: Razor's Edge has an
  installer here (`install-ng3-fix.sh`, with its `ng3-*` files), but it changes
  a bottle rather than a game folder, so the app does not offer it.

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
- Everything else, and the findings behind every fix, is in `legacy/` here and
  in the archived [MacGameVideoFix](https://github.com/MathiasKowoll/MacGameVideoFix)
  with its full history.

## License

[GPL-3.0-or-later](LICENSE), and the app carries the text. The reader built on
FFmpeg (LGPL-2.1-or-later) carries its own notice and the LGPL's text
(`fixes/mgvf-asf-reader-LICENCES.md`, installed beside the games that use it),
and every release attaches the FFmpeg source tarball it was built from. NINJA
GAIDEN 3's third-party DLLs, which the app does not carry, say where their
source is in `fixes/ng3-THIRD-PARTY-LICENCES.md`.
