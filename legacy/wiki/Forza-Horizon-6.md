# Current status: WIP with validated progress

The retained 2026-11-11 Rosetta baseline passed sign-in, menu and actual driving. It is included in MacGameFix 1.6.1-pre.1, with timers and guarded exception acceleration under the existing Rosetta improvement. See [current release evidence and limits](../../docs/releases/1.6.1-pre.1.md). The notes below describe earlier investigation and do not supersede that baseline.

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

## Open

- Complete Xbox sign-in and reach gameplay with the FH6 profile installed.
- Decide whether to set the NVIDIA RTX 4070 identity from Highball's recipe or
  keep the measured **Ignore** path for the unsupported-GPU dialog.
- Test whether Wine's empty-Keychain `CredEnumerate` result prevents the Xbox
  account from being remembered on a later launch.
- Exercise install, reinstall and byte-for-byte restore in the offline
  installer test and then build the MacGameFix app.

## Sources and credits

- **Gauthier Piarrette**, [Highball](https://github.com/gauthierpiarrette/highball):
  `tsshim`, the FH6 recipe and the native-`concrt140` crash diagnosis.
- **xvferxedd**, `fh5-d3dmetal-fix` (GPL-3.0), originally at
  `github.com/xvferxedd/fh5-d3dmetal-fix`, now offline: the preserved D3D12
  proxy source and FH6 extensions.
- **Andytizer**,
  [fh5-crossover-steam-fix](https://github.com/Andytizer/fh5-crossover-steam-fix),
  whose v1.0.1 preserves the source tree.
