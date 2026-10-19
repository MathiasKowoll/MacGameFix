# Engine modules: the DualSense on a cable and over Bluetooth

Unlike the game fixes, these files go into CrossOver itself: patched Wine
modules that replace CrossOver's own in `lib/wine`, in a CrossOver app or a
NotProton runner. They give a DualSense or DualSense Edge its haptics on a
cable, the same pad on Bluetooth as if it were on a cable, XInput (its vibration
on the motors, or the pad as an XInput controller), trigger effects for a game
that sets none, and options per game that the app's **Game Feel** tab sets.

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

### Over Bluetooth

On Bluetooth a game gets less from the pad, or nothing: Sony's PC library plays
the haptics only on a cable, where it finds the 4-channel output by its
container. macOS gives a Bluetooth pad a location ID too, the low four bytes of
its address (an Edge at `50:EE:32:C4:8E:F2` is `0x32C48EF2`), so two more patches
show the Bluetooth pad as the same pad on a cable:

| Patch | Module | Change |
|---|---|---|
| `0004-winebus-bluetooth.patch` | `winebus.so` | A DualSense or Edge on Bluetooth gets the wired pad's bus type and report descriptor and keeps its location ID, so `0001` gives it the wired container. Input `0x31` becomes USB `0x01`; the game's USB `0x02` becomes Bluetooth `0x31` with its sequence and CRC. One thread per pad is the only writer to it: the game's output merged, at most every 16 ms, and the haptics, which arrive on a socket from `winecoreaudio.so` and go out 64 frames at a time in reports `0x32` (`0x33` first) every 21.3 ms. A Bluetooth link drains about 65 reports a second. |
| `0005-winecoreaudio-bluetooth.patch` | `winecoreaudio.so` | `dualsense_bt.h`, a CoreAudio facade `coreaudio.c` calls through: for each Bluetooth pad `winebus.so` serves, an output with the UID the wired pad's would have (`0002` gives it the pad's container). A thread pulls Wine's render callback at the device period, filters channels 3 and 4 to the pad's 3 kHz and sends them to the writer. The same file amplifies a wired pad's haptics in its real output's render callback when a gain is set. |

### XInput, and the triggers

A game that reads the pad itself but rumbles through XInput, such as Beast of
Reincarnation, gets no vibration: Wine's `xinput` drives a pad's motors through a
HID haptics collection, and no descriptor Sony ships has one. Replacing the
descriptor, as Wine's SDL bus does, costs the triggers, the haptics and Sony's
library. Three more patches, from MacGameVideoFix's `mgvf-0010`, `0011`, `0012`,
`0027`, `0028` and `0030`, add one instead:

| Patch | Module | Change |
|---|---|---|
| `0006-winebus-xinput-and-triggers.patch` | `winebus.so` | With `xinput=rumble`, the pad's descriptor is left as it is and one more top-level collection follows it: a multi-axis controller with no axis and no button, and two haptics collections, rumble and buzz (winebus's own template), on report ids the DualSense and the Edge do not use (output `0x03`, feature `0x04`, input `0x06`). What `xinput` writes there becomes the pad's `0x02` with the motors (flag0 `0x01`\|`0x02`), handled as the game's own output: the Edge's length, the motor power, the Bluetooth writer. With `trigger_r2=` or `trigger_l2=`, an effect on that trigger, written when the pad starts and kept when a game writes the trigger off; a game that writes an effect of its own owns that trigger from then on. Stopping releases them, and a marker in `/tmp/macgamefix-<uid>` lets the next start release what a torn-down Wine left set. It also changes `0004`'s Bluetooth writer: the haptics stream stays open through silences while the game sends and has no motor values, the queue is held near 32 ms, and with `rumble=haptics` the motor values play on the actuators. |
| `0008-xinput-sony-order.patch` | `xinput1_1` to `xinput1_4`, `xinput9_1_0`, `xinputuap` (one source) | A pad with Sony's vendor id and its own descriptor (an unsigned X axis; Wine's SDL descriptor has a signed one) is read in Sony's order: the right stick on Z and Rz, the triggers on Rx and Ry, the buttons as they sit on the face (Square, Cross, Circle, Triangle, ... PS as Guide), the hat counted from its own minimum (0..7, 8 centred), and Y turned over for both sticks, as winexinput turns it over for its own report. |
| `0007-hidclass-xinput.patch` | `hidclass.sys` | A gamepad, joystick or multi-axis collection with a haptics collection is also offered under the interface `xinput` enumerates. One that carries motors and nothing else is offered to `xinput` only, and to no raw input: it has the pad's vendor and product ids, and Sony's library, which finds its pad by walking the HID interface, would see two. |

The trigger effects are the layouts NotProton's controller bridge wrote: resist
from zone 3 (strength 4 unless given), weapon from zone 3 giving way at zone 6
(7), slope from zone 2 rising to the strength (8), vibrate at 25 Hz from zone 2
(3), and rumble at 40 Hz with the game's motor, R2 with the light one and L2 with
the heavy one, in eight steps and at most one change every 60 ms. A host test
compared all 2340 cases with the bridge's `Controls.h`: the same bytes. `recoil`
follows the motor the same way, the stronger of the two, with a resistance from
zone 2 instead.

With `xinput=pad`, `0006` puts the two haptics collections inside the pad's own
top-level collection instead, so `0007` offers the pad itself to `xinput`, which
reads it with `0008` and drives its motors through the same reports. The pad
keeps Sony's vendor and product ids, which `XInputGetCapabilitiesEx` hands a game,
so a game that chooses its button prompts from them can show PlayStation's. Its
own report lengths do not move: the feature report added is 17 bytes and the
output 5. A game that also reads the pad itself would get its input twice; that
is what `xinput=rumble` is for.

With `xinput=rumble` the pad is two HID devices to Wine, so its own gets an
`&Col01` in its device id; both keep its container.

By default the app chooses for each Steam game from its store page: a game listed
as supporting the DualSense (category 57) gets `xinput=rumble`, which every game
gets, and one that is not gets `xinput=pad`. An exception gets a preset once it is
measured: God of War Ragnarök, for one, lists the DualSense, but under Wine it does
not load Sony's library and reads XInput. For `xinput=pad` Steam Input must be off for the game,
or it sees Steam's controller beside the pad; Steam's own default turns Steam
Input on for a PlayStation pad in exactly the games the store does not list.

None of these patches touch a device that is not a DualSense. Without the Game
Feel options they behave as `0001`-`0003` alone.

### The options

The modules read their options from MacGameFix's support folder, written by its
Game Feel tab: `pad.d/<Steam app id>.conf` for the game, then `pad.conf` for
every game; the first line with a key wins. A game is known by the Steam app id
Steam and NotProton give it (`SteamAppId`, `SteamGameId`,
`STEAM_COMPAT_APP_ID`), else by its prefix's path (`compatdata/<id>/pfx`). A
CrossOver bottle gave neither on 2026-10-19 (`game=-` in the log), so in a bottle
only `pad.conf` applies.

| Line | Effect |
|---|---|
| `bluetooth=wired` | A Bluetooth pad shown as wired (`0004`). |
| `motor_power=full` | An Edge's motor power claimed at `0x00` in every report. Sony's library claims it so for a standard DualSense and never for an Edge, which then stays at the reduction it stores. |
| `edge=dualsense` | An Edge shown to the game as a standard DualSense, on a cable or over Bluetooth: for titles whose Sony library does not know the Edge. |
| `haptics_gain_cable=<1-4>`, `edge_haptics_gain_cable=<1-4>` | The haptics multiplied on a cable, a DualSense's and an Edge's, with a soft limit: linear to 0.8, then a curve that never passes 1.0. |
| `haptics_gain_bluetooth=<1-4>`, `edge_haptics_gain_bluetooth=<1-4>` | The same over Bluetooth. A pad does not feel every game alike on both: a standard DualSense felt the same at 1 in Spider-Man 2, and F1 23's light haptics needed 2 over Bluetooth to feel as steady as on a cable. An older file's `haptics_gain` or `edge_haptics_gain` counts for both connections. |
| `xinput=off\|rumble\|pad` | What XInput gets of the pad (`0006`-`0008`): nothing; its vibration on the motors (every game's default); the pad itself as an XInput controller (the default for a game the store does not list for the DualSense). |
| `trigger_r2=<effect>[@1-8]`, `trigger_l2=<effect>[@1-8]` | A trigger effect for a game that sets none: `off` (the default), `resist`, `weapon`, `slope`, `vibrate`, `rumble` or `recoil`, with an optional strength. `rumble` vibrates and `recoil` resists with the game's own motor values. |
| `rumble=haptics` | Over Bluetooth, the game's motor values played on the actuators while it plays no haptics of its own: the heavy motor a 65 Hz tone on the left, the light one 160 Hz on the right, ramped per 64-frame block; NotProton's bridge synthesizer, sample for sample in a host test. On a cable the pad's own rumble plays. Off (`motors`) by default. |
| `trigger_r2_with_l2=<effect>[@1-8]`, `trigger_l2_with_r2=<effect>[@1-8]` | A second effect for a trigger while the other is pressed (from 40 of 255, released under 20, read from the pad's input): a weapon on R2 while L2 aims. `off`, the default, keeps the first. |
| `diagnostics=on` | What a game writes to the pad and reads from it, and a level meter of its haptics, in the log. |

The modules log to `/tmp/macgamefix-<uid>/pad.log`, each line naming its game;
what a game was seen to do (haptics, motors, trigger effects, motor power,
Bluetooth) the app reads back into its table.

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
of MacGameFix 1.5.0 came from `build.sh` as it was then: CONTROL Resonant played
its haptics on a cable with it, on the Intel side, installed by the app.

Bluetooth and the options, measured on 2026-10-18 with Marvel's Spider-Man 2 on
the 41069 runner's Intel side, a DualSense Edge, with development builds of
`0004` and `0005`:

- Over Bluetooth the Edge was the wired pad: `Enum\USB\VID_054C&PID_0DF2` with
  `ContainerId = {32C48EF2-27F2-4948-9654-152804AF6378}`; the adaptive triggers
  worked, and the haptics, "the same as on a cable".
- The game claims the motor power at `0x00` in every report when it sees a
  standard DualSense, and never when it sees an Edge. It sends the same haptic
  signal to both (a level meter: same peaks and RMS for the same moments, peaks to
  1.1). With the power claimed and the Edge's haptics at 2x, the Edge felt like a
  standard DualSense, over Bluetooth and on a cable.
- It reads feature reports `0x09`, `0x20` and `0x05` only, never the Edge's
  profile reports (`0x70`-`0x7b`).

Measured on 2026-10-19 with the modules as built here, installed by the app, on
the Intel side, Steam Input off for the game unless said:

- Marvel's Spider-Man 2, 41069 runner: an Edge and a standard DualSense, on a
  cable and over Bluetooth: triggers and haptics. Its own gain in `pad.d/` was
  read before `pad.conf`, and felt.
- F1 23, 41069 runner: an Edge shown as a DualSense (`edge=dualsense` from its
  `pad.d/`) and a standard DualSense, on a cable and over Bluetooth, and both pads
  over Bluetooth at once. A standard DualSense over Bluetooth felt jerky at 1x and
  steady at 2x, where on a cable 1x was steady. With Steam Input on, its haptics
  over Bluetooth started and stopped, in two runs; off, they were steady. The
  level meter showed the same continuous signal leaving the module either way.
- CONTROL Resonant, 41073 runner: an Edge over Bluetooth and a standard
  DualSense on a cable: haptics and triggers.
- In a CrossOver Preview 27.0.0.41073 bottle: F1 23 with an Edge on a cable,
  seen as an Edge (buttons, haptics, triggers), and Beast of Reincarnation with an
  Edge over Bluetooth: haptics and triggers, and motor rumble only once Steam
  Input was on.
- A pad switched on after the game started got its triggers and not its
  haptics: Wine's `mmdevapi` lists the audio outputs once, when the game starts.

Measured later on 2026-10-19, `0006`-`0008`, an Edge over Bluetooth, Steam Input off:

- Onimusha: Way of the Sword, 41069 runner, `xinput=pad` by the store's rule: the
  game was controlled through XInput and rumbled on the motors, and R2's recoil while
  L2 was pressed worked. R2's slope on its own was left free: a launch starts and
  stops Wine more than once, and a Wine that stopped released the triggers after the
  next one had set them. A fixed effect is now written again as its trigger starts to
  be pressed (not played yet).
- Uncharted: Legacy of Thieves Collection, 41073 runner, with diagnostics: the game
  asked 32 ms of buffer on a cable and 30 ms over Bluetooth, and kept 21 ms and
  10-30 ms waiting there. Over Bluetooth the haptics stream restarted 54 times in two
  minutes, each restart a mode switch, 30 ms and the pad's audio set up again; kept
  open, the writer's queue then sat at its 170 ms, the link carrying a little less
  than the haptics need. A block now takes up to 12 frames more past 32 ms of queue,
  by interpolation; in a simulation the queue stays at 15-40 ms with the link up to
  10 % short (not played yet).
- MacGameFix's thirty-second tries: the haptics test and every trigger effect,
  with the bytes the modules write, felt over Bluetooth; no macOS permission asked.

Not played yet: the FEX (arm64) side, `xinput=pad` with God of War Ragnarök, `rumble=haptics`,
and the tries on a cable.

## Modules

CrossOver 27 runs a bottle either on the Intel side, under Rosetta (x86_64), or
on the FEX side, where Wine runs natively on arm64 and FEX translates only the
game's code. Each side has its own copy of these modules, so both are built.
CrossOver 26.3 has only the Intel side.

| CrossOver | Sources | Wine | Intel (x86_64) | FEX (arm64) |
|---|---|---|---|---|
| Preview 27.0.0.41069 (20261006) | `crossover-sources-20261006.tar.gz` | 11.17 | played; see "Measured" | built, not played |
| Preview 27.0.0.41073 (20261015) | `crossover-sources-20261015.tar.gz` | 11.17 | played; see "Measured" | built, not played |
| 26.3.0.39832 | `crossover-sources-26.3.0.tar.gz` | 11.0 | `0001`-`0003` only, built, not played: our PE imports differ from CodeWeavers' (toolchain), and our `mmdevapi.dll` also lists `winmm.dll` | no FEX side |

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
   - Homebrew's `bison`, and `sdl2` for its headers: CodeWeavers build
     `winebus.so` with SDL, which it opens when it runs, and so does `build.sh`.
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
   Wine 11.0 (CrossOver 26.3). They differ in `0002` (Wine 11.0's
   `winecoreaudio` answers no property yet), and `wine-11.0` has no `0004` or
   `0005` yet. A rebuild gives different bytes even with no source change, so
   compare builds by what they import and export, not by hash. `build.conf` in each series sets the
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
- installs both sides where the CrossOver has the side and the build carries it,
  `winebus.so` too where the build has it;
- keeps CrossOver's own files under `~/Library/Application Support/MacGameFix/engine-backup/`,
  and takes them again if an update has put new ones in; a file CrossOver does not
  have is noted, and removing the modules takes ours out again;
- refuses while a game or program of that CrossOver runs.

What else each kind of CrossOver needs:

- **NotProton runner:** nothing else. The PE files carry no macOS signature,
  and `winebus.so` and `winecoreaudio.so` are signed by `build.sh`.
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
