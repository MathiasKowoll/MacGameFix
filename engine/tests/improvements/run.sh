#!/bin/bash
# engine-modules.sh by improvement, offline: a fake runner and a fake catalog carrying
# both improvements (the controls' modules and the Intel side's ntdll.so).
#
#   /bin/bash engine/tests/improvements/run.sh
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$1"; then printf '  ok    %s\n' "$2"; else printf '  FAIL  %s\n' "$2"; fails=$((fails + 1)); fi; }

B=27.0.0.41073
CAT="$T/catalog"; mkdir -p "$CAT"
cp "$HERE/../../engine-modules.sh" "$CAT/"
FILES="x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so x86_64-unix/winebus.so x86_64-unix/ntdll.so"
for f in $FILES; do printf 'ours %s wine-11.17-1\n' "$f" >"$CAT/engine-$B-$(printf '%s' "$f" | tr / -)"; done
printf '{"builds": [{"build": "%s", "crossover": "Preview", "wine": "11.17", "files": {}}]}\n' "$B" >"$CAT/engine-modules.json"

R="$T/notproton/runners/crossover-$B-fex/CrossOver"
mkdir -p "$R/lib/wine/x86_64-unix" "$R/lib/wine/x86_64-windows"
for f in $FILES; do printf "CodeWeavers' %s wine-11.17-1\n" "$f" >"$R/lib/wine/$f"; done
export MGVF_ENGINE_BACKUP="$T/backup"
E() { /bin/bash "$CAT/engine-modules.sh" "$R" "$@" 2>&1; }
st() { E --status "$@" | tail -1; }
cw() { [ "$(cat "$R/lib/wine/$1")" = "CodeWeavers' $1 wine-11.17-1" ]; }
ours() { cmp -s "$R/lib/wine/$1" "$CAT/engine-$B-$(printf '%s' "$1" | tr / -)"; }

check '[ "$(st)" = absent ] && [ "$(st --part=controls)" = absent ] && [ "$(st --part=rosetta)" = absent ]' "nothing in: every improvement absent"
E >/dev/null
check '[ "$(st)" = installed ] && ours x86_64-unix/ntdll.so && ours x86_64-unix/winebus.so' "a plain install puts both in"
E --restore --part=rosetta >/dev/null
check 'cw x86_64-unix/ntdll.so && ours x86_64-windows/winebus.sys && ours x86_64-unix/winebus.so' "taking Rosetta's out puts CrossOver's ntdll.so back and leaves the controls"
check '[ "$(st --part=rosetta)" = absent ] && [ "$(st --part=controls)" = installed ]' "then Rosetta's is absent, not outdated, and the controls installed"
E --part=rosetta >/dev/null
check '[ "$(st --part=rosetta)" = installed ] && [ "$(st --part=controls)" = installed ] && ours x86_64-unix/ntdll.so' "putting Rosetta's back in keeps the controls on the list"
check '! [ -f "$MGVF_ENGINE_BACKUP/crossover-$B-fex/off.list" ]' "and it is no longer noted as off"
E --restore --part=controls >/dev/null
check 'cw x86_64-unix/winebus.so && cw x86_64-windows/mmdevapi.dll && ours x86_64-unix/ntdll.so' "taking the controls out leaves Rosetta's in"
check '[ "$(st --part=controls)" = absent ] && [ "$(st --part=rosetta)" = installed ]' "controls absent, Rosetta's installed"
E --restore --part=rosetta >/dev/null
check 'cw x86_64-unix/ntdll.so && ! [ -d "$MGVF_ENGINE_BACKUP/crossover-$B-fex" ] && [ "$(st)" = absent ]' "the last one out removes the backup folder: all CrossOver's own"
# An install made before the improvements were split (controls only), then a
# catalog with ntdll.so: the new improvement reads as an update, as before.
E --part=controls >/dev/null
check '[ "$(st --part=rosetta)" = outdated ]' "an install without Rosetta's, beside a catalog with it, says outdated for it"
E --part=rosetta >/dev/null
E --restore >/dev/null
check 'cw x86_64-unix/ntdll.so && cw x86_64-unix/winebus.so && ! [ -d "$MGVF_ENGINE_BACKUP/crossover-$B-fex" ]' "a plain restore takes everything out"
check '[ "$(E --part=nothing | tail -1)" = "Unknown improvement: nothing" ]' "an unknown improvement is refused"
echo "==> $fails failed"
exit $((fails > 0))
