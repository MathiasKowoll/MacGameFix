# Engine modules: DualSense haptics on a cable

Unlike the game fixes, these files go into CrossOver itself: three patched Wine
modules that replace CrossOver's own in `lib/wine`, in a CrossOver app or a
NotProton runner.

## What they fix

On a USB cable, macOS shows a DualSense as a 4-channel audio output. Games with
DualSense haptics play them as audio on that output, and find it by matching the
endpoint's `DEVPKEY_Device_ContainerId` with the pad's HID device, as Windows
gives both one container. Under Wine on macOS neither side has a stable
container, so these games never open the pad's output: the adaptive triggers
work, the haptics don't.

The patches give both sides the same container, derived from the USB location ID
they share. With a DualSense Edge on a cable, the HID device reports
`LocationID = 0x02100000` and CoreAudio names its output
`AppleUSBAudioEngine:Sony Interactive Entertainment:DualSense Edge Wireless Controller:2100000:1`.

| Patch | Module | Change |
|---|---|---|
| `0001-winebus.patch` | `winebus.sys` | A USB device with a location ID (`desc.uid`, set by the IOHID and Xbox 360 buses) gets a container built from it instead of a random one. |
| `0002-winecoreaudio.patch` | `winecoreaudio.so` | `get_prop_value` answers `DEVPKEY_Device_ContainerId` for an `AppleUSBAudioEngine:` endpoint with the same container. The wow64 thunk passes `VT_CLSID` through. |
| `0003-mmdevapi.patch` | `mmdevapi.dll` | The property store asks the driver for an active endpoint's container instead of reading the registry, which cannot hold a GUID and would keep it after the device is gone. |

Both derivations use one namespace, `{<location>-27F2-4948-9654-152804AF6378}`.
Keep them in sync.

Upstream, Wine MR !360 does the same for PulseAudio on Linux. It has been a
draft since July 2022, and its author notes it needs MR !359 (mmdevapi) and a
winebus counterpart.

## Measured

Measured on 2026-10-18 on CrossOver Preview 27.0.0.41069, in a NotProton runner,
with PR #203's wrapper taken out:

- Six games played their haptics on a cable with a DualSense Edge and with a
  standard DualSense: Marvel's Spider-Man 2, CONTROL Resonant, F1 23, Beast of
  Reincarnation, Ghost of Tsushima and Returnal.
- Mortal Shell II, which drives the motors and trigger effects itself, kept
  working.
- The pad's HID got `ContainerId = {02100000-27F2-4948-9654-152804AF6378}`.
- The pad's output was in use while playing.
- The game process mapped the patched `mmdevapi.dll` and `winecoreaudio.so`.

That round ran on an earlier build of the same patches: its unix half was built
with llvm-mingw's clang and macOS 27 as the minimum. The `modules/27.0.0.41069`
shipped here comes from `build.sh` as it is now: CONTROL Resonant played its
haptics on a cable with it, on the Intel side, installed by the app.

## Modules

CrossOver 27 runs a bottle either on the Intel side, under Rosetta (x86_64), or
on the FEX side, where Wine runs natively on arm64 and FEX translates only the
game's code. Each side has its own copy of these modules, so both are built.
CrossOver 26.3 has only the Intel side.

| CrossOver | Sources | Wine | Intel (x86_64) | FEX (arm64) |
|---|---|---|---|---|
| Preview 27.0.0.41069 (20261006) | `crossover-sources-20261006.tar.gz` | 11.17 | played; see "Measured" | built, not played |
| Preview (20261015) | `crossover-sources-20261015.tar.gz` | 11.17 | built, not played | built, not played |
| 26.3.0.39832 | `crossover-sources-26.3.0.tar.gz` | 11.0 | built, not played: our PE imports differ from CodeWeavers' (toolchain), and our `mmdevapi.dll` also lists `winmm.dll` | no FEX side |

`modules/<id>/` holds the files laid out as in `lib/wine` (`x86_64-windows`,
`x86_64-unix`, `aarch64-windows`, `aarch64-unix`), plus `built-for.json` with the
Wine version, the patch series and each file's SHA-256. The two Previews' Wine
trees differ only in `ntdll/loader.c`. On the FEX side the PE files are ARM64X
(arm64 and arm64ec in one file), as CrossOver ships them. Built unpatched, the
20261006 modules match CodeWeavers' on both sides in exports, imports, linked
libraries, rpaths and minimum macOS.

The DirectX 12 games that use the haptics need D3DMetal, which the FEX side does
not have, so the FEX modules cannot be played with them. There is no i386 PE
half for 32-bit games yet.

## Building them

We ship the built modules. Building them yourself is up to you; this is how we
do it.

1. **Get the CrossOver sources for your CrossOver build** from CodeWeavers:
   - stable: <https://www.codeweavers.com/crossover/source>;
   - Preview: <https://www.codeweavers.com/preview/download>, which needs a
     CodeWeavers account.

   Extract only the Wine tree: `tar -xzf crossover-sources-<id>.tar.gz sources/wine`.
2. **Install the tools:**
   - Xcode or its command line tools, for Apple's clang, which builds the unix
     half;
   - [llvm-mingw](https://github.com/mstorsjo/llvm-mingw), for the PE halves. Set
     `LLVM_MINGW` to the folder that holds its `bin/`;
   - Homebrew's `bison`.
3. **Build:**

   ```sh
   ./build.sh <build id> <path to sources/wine> <patch series> [x86_64|arm64]
   ./build.sh 20261006 ~/sources-cx-20261006/sources/wine wine-11.17
   ./build.sh 20261006 ~/sources-cx-20261006/sources/wine wine-11.17 arm64
   ./build.sh 26.3.0 ~/sources-cx-26.3.0/sources/wine wine-11.0
   ```

   `x86_64` (the default) builds the Intel side and `arm64` the FEX side. A series
   without a FEX side (`wine-11.0`) refuses `arm64`.

   Use `wine-11.17` for Wine 11.17 (CrossOver 27 Preview) and `wine-11.0` for
   Wine 11.0 (CrossOver 26.3). The two differ only in `0002`: Wine 11.0's
   `winecoreaudio` answers no property yet. `build.conf` in each series sets the
   minimum macOS version and the second rpath that CodeWeavers' own
   `winecoreaudio.so` has.

   `PATCHES=none ./build.sh …` builds the same modules unpatched, into `.build/`,
   to compare them with CodeWeavers' own. For 20261006 they match in exports,
   imports and linked libraries.

## A new CrossOver build

Every CrossOver build, Preview or stable (CrossOver 27 included), needs its own
modules:

1. Get its sources and read `sources/wine/VERSION`.
2. Pick the series for that Wine. If the patches no longer apply, make a new
   series next to the others, as `wine-11.0` was made for CrossOver 26.3.
3. Build both sides, if the build has a FEX side.
4. Play one haptics game on a cable with the new modules, then add the build to
   the table above.

## Installing them

The app's **Wine Modules** tab lists every CrossOver app (in `/Applications`
and `~/Applications`) and every NotProton runner by its release, says what is in
each, and installs or removes the modules with a switch. It runs `engine-modules.sh`, which the catalog
carries with the modules (flat, as `engine-<build>-<dir>-<file>`, with
`engine-modules.json`). They travel in their own signed catalog (`modules.zip`,
`modules.json`, `modules.json.sig` in a release), apart from the game fixes', so
modules for a new CrossOver build come without a new app and without touching
the fixes. The same tab decides, on its own, whether they are installed
automatically, asked about first, or not looked for; on automatic the agent keeps
them in the CrossOver installs that are on (the top-level README says how).

`engine-modules.sh`:

- installs a build's modules only into a CrossOver of that exact build
  (`CFBundleVersion`, or the runner folder's name) running that Wine;
- installs both sides where the CrossOver has the side and the build carries it;
- keeps CrossOver's own files under `~/Library/Application Support/MacGameFix/engine-backup/`,
  and takes them again if an update has put new ones in;
- refuses while a game or program of that CrossOver runs.

What else each kind of CrossOver needs:

- **NotProton runner:** nothing else. The PE files carry no macOS signature,
  and `winecoreaudio.so` is signed by `build.sh`.
- **CrossOver app:** macOS asks to allow MacGameFix under App Management.
  Changing files inside the app breaks CodeWeavers' signature, so the app is
  signed again ad hoc and its quarantine attribute cleared; this has not been
  tried on a CrossOver app yet. A CrossOver update puts its own files back.
- **NotProton:** "Update" or "Reinstall" may put the runner's own files back.
  NotProton builds that carry PR #203 replace `mmdevapi.dll` with its wrapper.

`tools/runner-swap.sh` is the developer tool the first tests used. It keeps its
backups under `.build/runner-backup/`, separate from the app's.

## Licence

Wine is LGPL-2.1-or-later, and so are these modules. Their source is
CodeWeavers' `crossover-sources-<id>.tar.gz` for the build they target, plus the
patches in `patches/`. `build.sh` is the whole recipe.
