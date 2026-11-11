#!/bin/bash
# The existing Rosetta section owns both ntdll halves, independently of controls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RES="$T/resources"; mkdir -p "$RES"
python3 "$ROOT/app/bundle-engine.py" "$ROOT/engine/modules" "$RES" >/dev/null
cp "$ROOT/engine/engine-modules.sh" "$RES/engine-modules.sh"
RUNNER="$T/runners/crossover-27.0.0.41073-fex/CrossOver"
mkdir -p "$RUNNER/lib/wine/x86_64-unix" "$RUNNER/lib/wine/x86_64-windows"
printf 'stock wine-11.17 marker\n' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
printf 'stock PE\n' > "$RUNNER/lib/wine/x86_64-windows/ntdll.dll"
export MGVF_ENGINE_BACKUP="$T/backups"
run() { /bin/bash "$RES/engine-modules.sh" "$RUNNER" "$@"; }
run --part=rosetta >/dev/null
cmp "$RES/engine-27.0.0.41073-x86_64-windows-ntdll.dll" "$RUNNER/lib/wine/x86_64-windows/ntdll.dll"
[ ! -f "$RUNNER/lib/wine/x86_64-windows/winebus.sys" ]
[ "$(run --part=rosetta --status | tail -1)" = installed ]
run --part=controls >/dev/null
cmp "$RES/engine-27.0.0.41073-x86_64-windows-ntdll.dll" "$RUNNER/lib/wine/x86_64-windows/ntdll.dll"
run --part=controls --restore >/dev/null
[ "$(run --part=rosetta --status | tail -1)" = installed ]
run --part=rosetta --restore >/dev/null
[ "$(cat "$RUNNER/lib/wine/x86_64-windows/ntdll.dll")" = 'stock PE' ]
[ "$(cat "$RUNNER/lib/wine/x86_64-unix/ntdll.so")" = 'stock wine-11.17 marker' ]
rm "$RUNNER/lib/wine/x86_64-windows/ntdll.dll"
run --part=rosetta >/dev/null
run --part=rosetta --restore >/dev/null
[ ! -e "$RUNNER/lib/wine/x86_64-windows/ntdll.dll" ]
echo 'PASS: paired Rosetta installation/status/removal; controls isolation; original and absent PE restoration'
