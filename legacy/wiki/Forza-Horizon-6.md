# Current status: WIP with validated progress

Since MacGameFix 1.6.2 (2026-11-12) the improvement targets NotProton's CrossOver Preview 27.0.0.41303 runner under Rosetta, with D3DMetal 4: the paired `ntdll` (timers 0021, exception dispatcher 0023, register bridge 0024), the priority plugin, and an `advapi32` that keeps the Xbox sign-in across starts (held over four starts in a row). Sign-in, menu and driving are validated on NotProton only. Short stutters remain; see [Frame pacing](#frame-pacing-2026-11-12). The 41073 notes below describe earlier investigation. Earlier release evidence: [1.6.1-pre.1](../../docs/releases/1.6.1-pre.1.md).

# Forza Horizon 6

| | |
| --- | --- |
| Symptom | The game starts on D3DMetal 4, but shader conversion repeatedly reports unsupported shading-rate semantics |
| Cause | FH6 emits `SV_ShadingRate` paths and D3D12 input-layout and pipeline combinations not represented correctly by the unmodified D3DMetal path |
| Fix | A source-built FH6 profile of the Highball-derived D3D12 proxy rewrites those shaders and normalises the affected layouts and pipelines |
| Backend | **D3DMetal** 4, D3D12 |
| CrossOver | NotProton's `crossover-27.0.0.41073-fex` runner, Steam Play prefix |

## Current result

Tested on 2026-11-10 with native macOS Steam, NotProton's
`crossover-27.0.0.41073-fex` FEX runner, CrossOver 27 Preview's Wine 11.17 and
D3DMetal 4. Before the proxy, the game reached the title and Xbox device-login
screen, while the log repeatedly printed
`[metal-shaderconverter] Warning: Unsupported: shadingrate`. With the FH6
profile installed, it reaches the same Xbox login and the warning is absent.
The game process loaded the game-folder proxy, the private runner alias, Apple's
D3DMetal framework, and the native Microsoft Visual C++ runtime together.

Xbox sign-in and entry into gameplay are still being validated. The unsupported
GPU dialog was passed with **Ignore**; an NVIDIA identity was not added to the
Steam launch options for this measurement.

## Why this is not the FH5 fix copied whole

The proxy is built from the audited GPL source already carried for FH5, which
itself derives from Highball's `tsshim` and the source preserved by
`Andytizer/fh5-crossover-steam-fix`. FH6 gets a separate compile-time profile.
It keeps the general fixes relevant to both games:

- shader-model fallback and the `SV_ShadingRate` rewrite;
- explicit `APPEND_ALIGNED_ELEMENT` offsets;
- depth-resolve and unused dual-source blend handling; and
- the physical-memory report used instead of Wine's much larger virtual-size
  number.

It intentionally does not enable FH5's 24-to-32-byte descriptor translation,
unwind guard, dual-source workaround or Xbox UDP proxy. No DLL from an external
release is copied into the game.

## Native Visual C++ runtime

Highball's FH6 recipe installs native `concrt140`. Its investigation of the
November 3 startup crash identified a race in Wine's built-in
`concurrent_vector` implementation. NotProton already detects the Microsoft
runtime shipped with this game and sets native-first overrides for
`concrt140`, `msvcp140` and the related runtime DLLs. The MacGameFix installer
does not duplicate or replace that policy; it prints that dependency after a
successful install.

## Reproducible MacGameFix layout

`fixes/install-fh6-fix.sh` performs and reverses the installation:

1. validates that `d3d12-fh6.dll` exports exactly what the selected runner's
   D3DMetal module exports;
2. makes `apd12.dll` locally from that runner's own D3DMetal DLL by changing
   its PE export name;
3. places the Windows alias and Unix-half link in the base runner and FH6's
   existing NotProton runner clone;
4. puts the discovery copy in the prefix and the source-built proxy in the game
   folder;
5. writes the native override only for `forzahorizon6.exe`; and
6. keeps displaced files and restores them byte for byte.

The base-runner alias is shared safely with FH5 through separate ownership
records. Removing either fix leaves the alias while the other still owns it.

## Frame pacing (2026-11-12)

The steadiest play so far comes from unlocking the frame rate in the game's own
settings and capping it with D3DMetal 4's `D3DM_MAX_FPS` (48 or 60) in the
launch options. Short stutters remain.

Measured with the car nearly still (1 km/h), cap in effect, Game Mode on for
the whole minute, from Metal's presentation telemetry:

| | |
| --- | --- |
| Frames in 60 s | 2,848, 47.47 FPS on average |
| Longest presentation interval | 95.83 ms (about 4.6 frames at 48 FPS) |
| One-second windows with an interval over 50 ms | 8 (66.67 to 95.83 ms); none over 100 ms |
| New shader compilations | none recorded |

These are aggregated windows, not single frames: they place a stall, they do
not name it. GPU time in the affected windows was no higher than in the others
(median of the window maxima 31.41 ms against 33.06 ms), which points at
work submission or synchronisation rather than GPU load, without ruling the GPU
out. The intervals between affected windows vary; nothing supports a fixed
period. An earlier slow phase (29 to 35 FPS for the first half minute) is a
separate effect: it coincided with a cold Mac and with Game Mode being paused
and switched off and on, and is not explained by either alone.

`D3DM_MAX_FPS` is a no-sooner-than interval (`presentDrawable:afterMinimumDuration:`),
and the MacBook Pro's ProMotion panel shows frames only at 240/n Hz (120, 80,
60, 48, 40...). On this Mac in September, with another D3DMetal 4 title, every
cap from 48 to 60 held 48 and a cap of 70 held 60. That is why 48 and 60 can
behave alike here; a cap above the rate to hold has not been tried with FH6.

The exception statistics of the dispatcher (`WINE_SOFTWARE_EXCEPTION_STATS`)
are on by default: only `=0` turns them off, and `=1` changes nothing. Whether
turning them off changes the stutter has not been measured.

Not known yet: which thread or wait holds the frame back. Candidates are an
exception burst, the bridge's own cost, contention on its counters, a runnable
thread not getting a core, a synchronisation wait, file or memory activity,
and thermal or scheduler changes. A diagnostic that records the dispatcher's
timings in-process is prepared outside MacGameFix and has not run on FH6. It
ships with nothing here. A system trace attached to FH6 earlier preceded a
critical-section hang and the game's own watchdog crash, so profilers on the
live game are weighed against that.

## Open

- Find what holds the frame back in the stutters above, then fix that one
  thing, with one change at a time against the working baseline.
- CrossOver bottles: only the sign-in fix installs there, untested.
- FEX/Mullion and hardware beyond this Mac.

## Sources and credits

- **Gauthier Piarrette**, [Highball](https://github.com/gauthierpiarrette/highball):
  `tsshim`, the FH6 recipe and the native-`concrt140` crash diagnosis.
- **xvferxedd**, `fh5-d3dmetal-fix` (GPL-3.0), originally at
  `github.com/xvferxedd/fh5-d3dmetal-fix`, now offline: the preserved D3D12
  proxy source and FH6 extensions.
- **Andytizer**,
  [fh5-crossover-steam-fix](https://github.com/Andytizer/fh5-crossover-steam-fix),
  whose v1.0.1 preserves the source tree.
