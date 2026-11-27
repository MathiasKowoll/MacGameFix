#!/bin/bash
# engine-modules.sh by improvement, offline: a fake runner and a fake catalog carrying
# both improvements (the controls' modules and ntdll.so).
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
E --restore --part=controls >/dev/null
check 'cw x86_64-unix/winebus.so && cw x86_64-windows/mmdevapi.dll && ours x86_64-unix/ntdll.so' "taking the controls out leaves Rosetta's in"
check '[ "$(st --part=controls)" = absent ] && [ "$(st --part=rosetta)" = installed ]' "controls absent, Rosetta's installed"
E --restore --part=rosetta >/dev/null
check 'cw x86_64-unix/ntdll.so && ! [ -d "$MGVF_ENGINE_BACKUP/crossover-$B-fex" ] && [ "$(st)" = absent ]' "the last one out removes the backup folder: all CrossOver's own"
# One improvement alone, never the other (issue #50): the other is absent, not outdated,
# and nothing is said to have replaced it.
E --part=controls >/dev/null
check '[ "$(st --part=controls)" = installed ] && [ "$(st --part=rosetta)" = absent ] && cw x86_64-unix/ntdll.so' "the controls alone: Rosetta's, never installed, is absent"
check '[ "$(E --status --part=rosetta | wc -l)" -eq 1 ]' "and nothing is said to have replaced it"
check '[ "$(st)" = half ]' "both together read half: one of the two is in"
E --restore --part=controls >/dev/null
E --part=rosetta >/dev/null
check '[ "$(st --part=rosetta)" = installed ] && [ "$(st --part=controls)" = absent ] && cw x86_64-unix/winebus.so' "Rosetta's alone: the controls, never installed, are absent"
E --restore --part=rosetta >/dev/null
# Newer modules add a file to an improvement that is in: that one has an update, the
# other is still absent.
mv "$CAT/engine-$B-x86_64-unix-winebus.so" "$T/held"
E --part=controls >/dev/null
mv "$T/held" "$CAT/engine-$B-x86_64-unix-winebus.so"
check '[ "$(st --part=controls)" = outdated ] && [ "$(st --part=rosetta)" = absent ]' "a module added to the controls is an update of the controls alone"
E --part=controls >/dev/null
check '[ "$(st --part=controls)" = installed ] && ours x86_64-unix/winebus.so' "which installing again brings in"
# CrossOver's own files back over an improvement that is in: absent, and said so.
for f in $FILES; do [ "$f" = x86_64-unix/ntdll.so ] || printf "CodeWeavers' %s wine-11.17-1\n" "$f" >"$R/lib/wine/$f"; done
check '[ "$(st --part=controls)" = absent ] && E --status --part=controls | grep -q "Something replaced"' "the controls replaced from outside: absent, and it says something replaced them"
check '[ "$(E --status --part=rosetta | wc -l)" -eq 1 ]' "while nothing is said about Rosetta's"
E --part=controls >/dev/null
# The note an older script left when an improvement was taken out is not needed and goes.
echo rosetta >"$MGVF_ENGINE_BACKUP/crossover-$B-fex/off.list"
check '[ "$(st --part=rosetta)" = absent ]' "an older script's note changes nothing"
E --part=rosetta >/dev/null
check '! [ -f "$MGVF_ENGINE_BACKUP/crossover-$B-fex/off.list" ]' "and the next install removes it"
E --restore >/dev/null
check 'cw x86_64-unix/ntdll.so && cw x86_64-unix/winebus.so && ! [ -d "$MGVF_ENGINE_BACKUP/crossover-$B-fex" ]' "a plain restore takes everything out"
check '[ "$(E --part=nothing | tail -1)" = "Unknown improvement: nothing" ]' "an unknown improvement is refused"

# NotProton's Game Mode copies the runner for each game and copies it again when this
# stamp changes: runner_stamp, as NotProton's main has it in dylib/feats/compat_run.sh
# (e67dd9b). Every change of the modules must change it, on a runner whose loader is in a
# wine.app (Preview 27) and on one whose loader is not (26.3).
runner_stamp() {
  if [ -d "$wine_unix/wine.app" ]; then
    set -- "$wine_unix/wine.app/Contents" "$wine_unix/wine.app/Contents/MacOS" \
      "$wine_unix/wine.app/Contents/MacOS/wine"
  else
    set -- "$wine_unix/wine" "$wine_unix/ntdll.so"
  fi
  stat -f '%N %i %Fm' "$CX_ROOT/lib/wine" "$CX_ROOT/lib/wine"/* "$@"
}
stamp() { CX_ROOT="$R" wine_unix="$R/lib/wine/x86_64-unix" runner_stamp 2>/dev/null | shasum; }
changes() { local a; a="$(stamp)"; "$@" >/dev/null; [ "$(stamp)" != "$a" ]; }
mkdir -p "$R/lib/wine/x86_64-unix/wine.app/Contents/MacOS"
: >"$R/lib/wine/x86_64-unix/wine.app/Contents/MacOS/wine"
check 'changes E' "an install changes NotProton's stamp (a loader in a wine.app)"
for f in $FILES; do printf 'newer %s wine-11.17-1\n' "$f" >"$CAT/engine-$B-$(printf '%s' "$f" | tr / -)"; done
check 'changes E && ours x86_64-windows/winebus.sys' "so does an update of the modules"
check 'changes E --restore --part=controls && cw x86_64-windows/winebus.sys' "and taking the controls out"
check 'changes E --restore --part=rosetta && cw x86_64-unix/ntdll.so' "and taking Rosetta's out"
rm -rf "$R/lib/wine/x86_64-unix/wine.app"; : >"$R/lib/wine/x86_64-unix/wine"
check 'changes E --part=controls' "a controls install changes it on a runner whose loader is not in a wine.app"
check 'changes E --restore' "and so does a restore"
chmod 755 "$R/lib/wine/x86_64-unix/ntdll.so"
E >/dev/null
check '[ "$(stat -f %Lp "$R/lib/wine/x86_64-unix/ntdll.so")" = 755 ] && [ -z "$(find "$R/lib/wine" -name "*.mgvf-new")" ]' "a module keeps the mode of the file it replaces, and nothing is left beside it"
E --restore >/dev/null

# A runner with a FEX side, and a catalog whose ntdll.so (the timer fix) is on both sides:
# Rosetta's improvement puts both in and takes both out.
A="aarch64-windows/winebus.sys aarch64-windows/mmdevapi.dll aarch64-unix/winecoreaudio.so aarch64-unix/ntdll.so"
mkdir -p "$R/lib/wine/aarch64-unix" "$R/lib/wine/aarch64-windows"
for f in $A; do
  printf 'ours %s wine-11.17-1\n' "$f" >"$CAT/engine-$B-$(printf '%s' "$f" | tr / -)"
  printf "CodeWeavers' %s wine-11.17-1\n" "$f" >"$R/lib/wine/$f"
done
E --part=rosetta >/dev/null
check 'ours x86_64-unix/ntdll.so && ours aarch64-unix/ntdll.so && cw aarch64-unix/winecoreaudio.so' "Rosetta's improvement installs ntdll.so on both sides and nothing else"
E --restore --part=rosetta >/dev/null
check 'cw x86_64-unix/ntdll.so && cw aarch64-unix/ntdll.so && [ "$(st --part=rosetta)" = absent ]' "and taking it out puts CrossOver's ntdll.so back on both"
E >/dev/null; E --restore >/dev/null
check 'cw aarch64-unix/ntdll.so && cw aarch64-windows/winebus.sys && ! [ -d "$MGVF_ENGINE_BACKUP/crossover-$B-fex" ]' "a plain restore takes the FEX side's out too"
# 26.3 (CrossOver stable): the app gets the whole engine; NotProton's runner for 26.3 leaves
# Rosetta's modules to CodeWeavers, and the ntdll.so earlier modules put in it goes back.
B5=26.3.0.39832
F5="x86_64-unix/ntdll.so x86_64-unix/win32u.so x86_64-windows/kernelbase.dll x86_64-windows/user32.dll x86_64-unix/winebus.so x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll"
for f in $F5 x86_64-unix/winecoreaudio.so; do printf 'ours %s wine-11.0-1\n' "$f" >"$CAT/engine-$B5-$(printf '%s' "$f" | tr / -)"; done
printf '{"builds": [{"build": "%s", "crossover": "CrossOver 26.3", "wine": "11.0", "files": {}}]}\n' "$B5" >"$CAT/engine-modules.json"
R5="$T/notproton/runners/crossover-$B5/CrossOver"; A5="$T/CrossOver.app"; X5="$A5/Contents/SharedSupport/CrossOver"
for root in "$R5" "$X5"; do
  mkdir -p "$root/lib/wine/x86_64-unix" "$root/lib/wine/x86_64-windows"
  for f in $F5 x86_64-unix/winecoreaudio.so; do printf "CodeWeavers' %s wine-11.0-1\n" "$f" >"$root/lib/wine/$f"; done
done
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $B5" "$A5/Contents/Info.plist" >/dev/null
E5() { /bin/bash "$CAT/engine-modules.sh" "$1" "${@:2}" 2>&1; }
st5() { E5 "$@" --status | tail -1; }
ours5() { cmp -s "$1/lib/wine/$2" "$CAT/engine-$B5-$(printf '%s' "$2" | tr / -)"; }
cw5() { [ "$(cat "$1/lib/wine/$2")" = "CodeWeavers' $2 wine-11.0-1" ]; }
E5 "$X5" >/dev/null
check 'ours5 "$X5" x86_64-unix/ntdll.so && ours5 "$X5" x86_64-unix/win32u.so && ours5 "$X5" x86_64-windows/kernelbase.dll && ours5 "$X5" x86_64-windows/user32.dll && ours5 "$X5" x86_64-unix/winebus.so && [ "$(st5 "$X5")" = installed ]' "26.3, the CrossOver app: the whole engine goes in"
S5="$MGVF_ENGINE_BACKUP/crossover-$B5"; mkdir -p "$S5/x86_64-unix"
cp "$R5/lib/wine/x86_64-unix/ntdll.so" "$S5/x86_64-unix/ntdll.so"
printf 'earlier x86_64-unix/ntdll.so wine-11.0-1\n' >"$R5/lib/wine/x86_64-unix/ntdll.so"
printf '%s  %s\n' "$(shasum -a 256 "$R5/lib/wine/x86_64-unix/ntdll.so" | cut -d' ' -f1)" x86_64-unix/ntdll.so >"$S5/installed.list"
check '[ "$(st5 "$R5" --part=rosetta)" = outdated ]' "26.3, NotProton's runner with an earlier ntdll.so of ours: outdated"
E5 "$R5" >/dev/null
check 'cw5 "$R5" x86_64-unix/ntdll.so && cw5 "$R5" x86_64-unix/win32u.so && cw5 "$R5" x86_64-windows/kernelbase.dll && cw5 "$R5" x86_64-windows/user32.dll && ours5 "$R5" x86_64-unix/winebus.so' "an install puts CodeWeavers' ntdll.so back in the runner, leaves its win32u.so, kernelbase.dll and user32.dll, and puts the controls in"
check '[ "$(st5 "$R5" --part=rosetta)" = nomodules ] && [ "$(st5 "$R5" --part=controls)" = installed ] && ! grep -q ntdll "$S5/installed.list"' "then the runner has nothing of Rosetta's improvement and the controls installed"
echo "==> $fails failed"
exit $((fails > 0))
