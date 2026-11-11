# Retained FH6 ntdll source overlay

This is the exact source used for the 2026-11-11 driving baseline, not a new binary build. The matching binary pair is under `engine/modules/27.0.0.41073/`; the installed baseline hashes and subsequent distribution hashes are recorded in `docs/releases/fh6-baseline.json` and `built-for.json` respectively.

Only Wine 11.17 from CrossOver Preview 27.0.0.41073, x86_64/Rosetta, is supported for this overlay. Do not transplant it into Wine 10, ARM64 or an arbitrary upstream Wine. The GitHub prerelease includes the complete corresponding Wine source archive with these files already overlaid, its license and the build script. It includes the existing CPU fidelity fixes and timer patch 0021 in `native/sync.c`. Keep this pair when updating controller-only modules; the general `engine/build.sh` does not recreate this experimental PE dispatcher.

- `pe/`: Wine PE-side dispatcher, loader, declarations and authored semantic tests.
- `native/`: Wine Unix-side timing/observation and CPU compatibility sources. Detailed collection is opt-in.
- `rosetta-trap-boost.c`, `faultcount.h`: existing Rosetta priority plugin used by the baseline; it changes scheduling, not game instructions. Its periodic lightweight census is unchanged in this preview; the app's optional Diagnostics menu controls the Metal HUD/log and PE aggregate counters only. Fault tracing remains opt-in.

The dispatcher only enables for the checked FH6 executable headers and opt-in environment. The installer additionally verifies the full executable SHA-256. New D4/9A candidates and D5 without APX require the conservative readable window; unsafe boundaries keep the original path. SHL preserves the actual CL/immediate instruction form and full flags. Memory operations and other unsupported cases retain normal execution. No license/protection check is removed or replaced with a success result.

Wine source remains LGPL-2.1-or-later; retain its file headers and COPYING.LIB. The MacGameFix integration is GPL-3.0-or-later. The priority plugin was developed locally for this experiment; its exact source and header accompany the binary. The complete Forza D3D12 proxy source and upstream notices are in `fixes/fh6-d3d12/` and `fixes/fh5-THIRD-PARTY-LICENCES.md`.
