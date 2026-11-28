#!/usr/bin/env bash
# The automation, offline: the Wine modules put into a runner and taken out, a
# signed catalog taken or refused, and the agent
# keeping a marked fix applied across game updates, while Steam writes the game,
# while the game runs, and when the installer fails, waiting for a recipe for a
# macOS game's new build until a catalog brings one, and left alone where that
# game's installer refuses; and a fix's report, with the two forms Games opens
# with it; and a newer MacGameFix found, refused when it is not signed as this
# one is, and put in a copy of this app's place. Nothing here touches the
# real Steam libraries or GitHub: MACGAMEFIX_HOME points everything at a
# throwaway home, and the fixes catalog is a fake one signed with a test key.
#
# Usage: app/test-automation.sh  (after app/build-app.sh)
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/MacGameFix.app/Contents/MacOS/MacGameFix"
[ -x "$BIN" ] || { echo "build MacGameFix.app first (build-app.sh)" >&2; exit 1; }
T="${KEEP_T:-$(mktemp -d)}"
trap '[ "${GAME_PID:-0}" -gt 0 ] && kill "$GAME_PID" 2>/dev/null; [ "${STUB_PID:-0}" -gt 0 ] && kill "$STUB_PID" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
export MACGAMEFIX_HOME="$T/home"
# What the Steam store says of each app, saved: no test asks the network.
export MACGAMEFIX_STORE_DIR="$T/store"
# Where macOS keeps each game's compiled shaders: a folder of the test's, never the real one.
export MACGAMEFIX_CACHE_DIR="$T/cache"
mkdir -p "$MACGAMEFIX_STORE_DIR"
# Every pass of the agent asks whether there is a newer MacGameFix: a release of this
# very version answers, so none of them asks the site or GitHub.
APPV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HERE/MacGameFix.app/Contents/Info.plist")"
export MACGAMEFIX_APP_SOURCE="$T/app-none"
mkdir -p "$MACGAMEFIX_APP_SOURCE"
printf '{"tag_name":"v%s","assets":[]}' "$APPV" > "$MACGAMEFIX_APP_SOURCE/release.json"
printf '{"4242":{"success":true,"data":{"categories":[{"id":28,"description":"Full controller support"}]}}}' > "$MACGAMEFIX_STORE_DIR/4242.json"
SUPPORT="$MACGAMEFIX_HOME/Library/Application Support"
GAME="$SUPPORT/Steam/steamapps/common/Fake Game"
MANIFEST="$SUPPORT/Steam/steamapps/appmanifest_4242.acf"
mkdir -p "$GAME" "$SUPPORT/MacGameFix"
touch "$GAME/FakeGame.exe"
fail=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }
steam() { # buildid, StateFlags
  printf '"AppState"\n{\n\t"appid"\t\t"4242"\n\t"name"\t\t"Fake Game"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"Fake Game"\n\t"buildid"\t\t"%s"\n}\n' "$2" "$1" > "$MANIFEST"
}
agent() { "$BIN" --agent-once 2>&1; }
menu() { "$BIN" --menu-report 2>&1; }
# A refusal exits 1; what is checked is what it says.
update() { "$BIN" --update-from "$@" 2>&1 || true; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# The Wine modules, from the bundle's own catalog (no catalog is downloaded yet):
# a fake NotProton runner of a build the catalog carries, with both sides, and
# one of a build it does not.
echo "== the Wine modules"
RUNNER="$SUPPORT/notproton/runners/crossover-27.0.0.41069-fex/CrossOver"
OTHER="$SUPPORT/notproton/runners/crossover-27.0.0.1-fex/CrossOver"
for side in x86_64 aarch64; do mkdir -p "$RUNNER/lib/wine/$side-unix" "$RUNNER/lib/wine/$side-windows"; done
mkdir -p "$OTHER/lib/wine/x86_64-unix"
printf 'x wine-11.17-8909 x' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
printf 'x wine-11.17-8909 x' > "$OTHER/lib/wine/x86_64-unix/ntdll.so"
mkdir -p "$RUNNER/etc" "$OTHER/etc"
printf '"BuildTag" = "cxpreview-20261006-rc2"\n' > "$RUNNER/etc/CrossOver.conf"
printf '"BuildTag" = "cxpreview-20261099-rc1"\n' > "$OTHER/etc/CrossOver.conf"
ENGINE_FILES="x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-windows/hidclass.sys x86_64-unix/winecoreaudio.so
  x86_64-unix/winebus.so aarch64-windows/winebus.sys aarch64-windows/mmdevapi.dll aarch64-windows/hidclass.sys
  aarch64-unix/winecoreaudio.so aarch64-unix/winebus.so
  x86_64-windows/xinput1_1.dll x86_64-windows/xinput1_2.dll x86_64-windows/xinput1_3.dll x86_64-windows/xinput1_4.dll
  x86_64-windows/xinput9_1_0.dll x86_64-windows/xinputuap.dll aarch64-windows/xinput1_1.dll aarch64-windows/xinput1_2.dll
  aarch64-windows/xinput1_3.dll aarch64-windows/xinput1_4.dll aarch64-windows/xinput9_1_0.dll aarch64-windows/xinputuap.dll"
for f in $ENGINE_FILES; do echo "CodeWeavers' $f" > "$RUNNER/lib/wine/$f"; done
engine() { "$BIN" --engine-report 2>&1 | grep -F "runner · CrossOver Preview $1 |" || true; }
check 'has "$(engine 20261006)" "| fex | absent"' "a runner of a carried build, both sides, is absent, named by its Preview's date"
check 'has "$(engine 20261099)" "noModules"' "a runner of a build with no modules says so"
# 20261006 is an older Preview: its modules are kept (engine/support.json), not maintained.
check 'has "$(engine 20261006)" "| kept" && ! has "$(engine 20261099)" "| kept"' "a runner of a Preview that is only kept says so, and one with no modules does not"
# 20261111 (41303): NotProton's runner and the CrossOver Preview app are both maintained
# (2026-11-28: the latest Preview's app is maintained like the stable one's; it was only
# kept, under engine/support.json's appsKept, from 2026-11-26).
KR="$SUPPORT/notproton/runners/crossover-27.0.0.41303-fex/CrossOver"
KA="$MACGAMEFIX_HOME/Applications/CrossOver Preview Latest.app"; KX="$KA/Contents/SharedSupport/CrossOver"
for root in "$KR" "$KX"; do
  mkdir -p "$root/lib/wine/x86_64-unix" "$root/etc"
  printf 'x wine-11.21-1 x' > "$root/lib/wine/x86_64-unix/ntdll.so"
  printf '"BuildTag" = "cxpreview-20261111-rc1"\n' > "$root/etc/CrossOver.conf"
done
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 27.0.0.41303' "$KA/Contents/Info.plist" >/dev/null
KREP="$("$BIN" --engine-report 2>&1)"
krunner="$(printf '%s\n' "$KREP" | grep -F "runner · CrossOver Preview 20261111 |" || true)"
kapp="$(printf '%s\n' "$KREP" | grep -F "CrossOver Preview 20261111" | grep -v -F "runner ·" || true)"
check '[ -n "$krunner" ] && ! has "$krunner" "| kept" && [ -n "$kapp" ] && ! has "$kapp" "| kept"' "41303: NotProton's runner and the CrossOver Preview app are both maintained"
rm -rf "$KA" "$SUPPORT/notproton/runners/crossover-27.0.0.41303-fex"
"$BIN" --engine-install "$RUNNER" >/dev/null 2>&1 || true
same=1
for f in $ENGINE_FILES; do
  cmp -s "$RUNNER/lib/wine/$f" "$HERE/MacGameFix.app/Contents/Resources/engine-27.0.0.41069-$(printf '%s' "$f" | tr / -)" || same=0
done
check '[ "$same" = 1 ] && has "$(engine 20261006)" "installed"' "installing puts both sides' modules in"
check '[ "$(cat "$SUPPORT/MacGameFix/engine-backup/crossover-27.0.0.41069-fex/x86_64-windows/winebus.sys")" = "CodeWeavers'"'"' x86_64-windows/winebus.sys" ]' "and keeps CrossOver's own"
printf 'x wine-11.0-1 x' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
check 'has "$(engine 20261006)" "noModules"' "a runner whose Wine is not the build's is refused"
printf 'x wine-11.17-8909 x' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
# A development build left in a runner is neither CrossOver's nor ours: installing
# again replaces it and keeps CrossOver's own as it was.
echo "a development build" > "$RUNNER/lib/wine/x86_64-unix/winebus.so"
"$BIN" --engine-install "$RUNNER" >/dev/null 2>&1 || true
check '[ "$(cat "$SUPPORT/MacGameFix/engine-backup/crossover-27.0.0.41069-fex/x86_64-unix/winebus.so")" = "CodeWeavers'"'"' x86_64-unix/winebus.so" ] && has "$(engine 20261006)" "installed"' "a development build in a module's place does not replace CrossOver's own kept file"
"$BIN" --engine-remove "$RUNNER" >/dev/null 2>&1 || true
check '[ "$(cat "$RUNNER/lib/wine/aarch64-unix/winecoreaudio.so")" = "CodeWeavers'"'"' aarch64-unix/winecoreaudio.so" ] && [ "$(cat "$RUNNER/lib/wine/x86_64-unix/winebus.so")" = "CodeWeavers'"'"' x86_64-unix/winebus.so" ] && has "$(engine 20261006)" "absent"' "removing puts CrossOver's own back"
# A CrossOver without one of the files: removing takes ours out again.
rm -f "$RUNNER/lib/wine/aarch64-unix/winebus.so"
"$BIN" --engine-install "$RUNNER" >/dev/null 2>&1 || true
"$BIN" --engine-remove "$RUNNER" >/dev/null 2>&1 || true
check '[ ! -e "$RUNNER/lib/wine/aarch64-unix/winebus.so" ] && has "$(engine 20261006)" "absent"' "a file CrossOver did not have is taken out again"
rm -rf "$SUPPORT/notproton"

# A catalog with one fake fix: a marker in the game folder, or a failure when
# the folder holds FAIL.
RES="$T/res"
mkdir -p "$RES"
cat > "$RES/install-fake.sh" <<'SH'
#!/bin/bash
# Build 2 of the fake fix; a marker holding anything else is an older build.
dir="$1"
case "${2:-}" in
  --status)
    if [ ! -f "$dir/fixed.marker" ]; then echo absent
    elif [ "$(cat "$dir/fixed.marker")" = 2 ]; then echo installed
    else echo outdated; fi
    exit 0 ;;
  --restore) rm -f "$dir/fixed.marker"; exit 0 ;;
esac
echo "installing into $dir"
# As an installer that takes minutes says how far it is, when it is asked to.
if [ "${MGVF_PROGRESS:-0}" = 1 ]; then echo "MGVF-PROGRESS 1 2"; fi
if [ -f "$dir/FAIL" ]; then echo "cannot write $dir/fake.dll"; exit 1; fi
echo 2 > "$dir/fixed.marker"
SH
# A fix that also writes a key into the prefix it is given, as the Kingdom
# Hearts and NieR installers do.
cat > "$RES/install-fakekeys.sh" <<'SH'
#!/bin/bash
dir="$1"; pfx="${MGVF_BOTTLE:?no prefix given}"
case "${2:-}" in
  --status)
    if [ -f "$dir/keys.marker" ] && [ -f "$pfx/fake.key" ]; then echo installed
    elif [ -f "$dir/keys.marker" ] || [ -f "$pfx/fake.key" ]; then echo half
    else echo absent; fi
    exit 0 ;;
  --restore) rm -f "$dir/keys.marker" "$pfx/fake.key"; exit 0 ;;
esac
echo "installing into $dir and $pfx"
echo 1 > "$dir/keys.marker"; touch "$pfx/fake.key"
SH
# A fix made for each build of a macOS game, as Cyberpunk 2077's is: the game's
# build is in its app, and the catalog's fakeapp.recipes lists the builds it has
# a recipe for. Every install it is asked for is written down in "runs". A file
# "blocked" or "half" in the game folder holds the reason it gives on a "Why:"
# line, as Cyberpunk 2077's does for an executable changed outside MacGameFix
# or a Mac the fix is not for, and it then refuses to install.
cat > "$RES/install-fakeapp.sh" <<'SH'
#!/bin/bash
dir="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
build="$(cat "$dir/FakeNative.app/Contents/build")"
echo "Game build: $build"
case "${2:-}" in --status|--restore) ;; *) echo "$build" >> "$dir/runs" ;; esac
for word in blocked half; do
  [ -f "$dir/$word" ] || continue
  case "${2:-}" in --status) echo "Why: $(cat "$dir/$word")"; echo "$word"; exit 0 ;; esac
  echo "error: $(cat "$dir/$word")"; exit 1
done
if ! /usr/bin/grep -qx "$build" "$HERE/fakeapp.recipes"; then
  case "${2:-}" in --status) echo norecipe; exit 0 ;; --restore) exit 0 ;; esac
  echo "no recipe for build $build"; exit 1
fi
case "${2:-}" in
  --status) [ -f "$dir/fixed.marker" ] && echo installed || echo absent; exit 0 ;;
  --restore) rm -f "$dir/fixed.marker"; exit 0 ;;
esac
touch "$dir/fixed.marker"
SH
printf '1\n' > "$RES/fakeapp.recipes"
# A fix with a DLL of its own, in its carrier's folder Bin, and a log it writes there
# (games.json's logs, an installer's MGVF-LOG line): what a fix's report reads.
cat > "$RES/install-fakedll.sh" <<'SH'
#!/bin/bash
dir="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
case "${2:-}" in
  --status)
    echo "looking at $dir/Bin/fake.dll"
    if [ ! -f "$dir/Bin/fake.dll" ]; then echo absent
    elif cmp -s "$dir/Bin/fake.dll" "$HERE/fakefix.dll"; then echo installed
    else echo outdated; fi
    exit 0 ;;
  --restore) rm -f "$dir/Bin/fake.dll"; exit 0 ;;
esac
cp "$HERE/fakefix.dll" "$dir/Bin/fake.dll"
SH
printf 'MZ the fake fix, build 1\n' > "$RES/fakefix.dll"
# Made for DXMT, with a codec only CrossOver Preview 27 ships; a second game
# whose fix writes registry keys; a third whose DLLs go into the prefix, as
# NINJA GAIDEN 3's do; a macOS game whose app its fix changes; and the fix above
# with a DLL and a log of its own.
cat > "$RES/games.json" <<'JSON'
{"games": [{"name": "Fake Game", "exe": "FakeGame.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "dxmt", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "CrossOver Preview 27", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Keys", "exe": "FakeKeys.exe", "carrierDir": "", "script": "install-fakekeys.sh",
  "needsPrefix": true, "symptom": "test", "backend": "d3dmetal", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Prefix", "exe": "FakePrefix.exe", "carrierDir": "", "script": "install-fakekeys.sh",
  "needsPrefix": true, "scope": "prefix", "symptom": "test", "backend": "dxvk", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Native", "exe": "FakeNative", "carrierDir": "FakeNative.app/Contents/MacOS", "script": "install-fakeapp.sh",
  "needsPrefix": false, "scope": "app", "symptom": "test", "backend": "", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Fixed", "exe": "FakeFixed.exe", "alsoRuns": [], "logs": ["fake-fix.log"], "carrierDir": "Bin",
  "script": "install-fakedll.sh", "needsPrefix": false, "scope": "folder", "symptom": "test", "backend": "d3dmetal",
  "gptk": "", "gptkAlso": "", "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""}],
 "testing": [{"name": "Fake Trial", "exe": "FakeGame.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "d3dmetal", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": "", "testing": "a friend",
  "credits": ["A Friend | https://example.invalid/fix"]}],
 "byHand": [{"name": "Fake Hand", "exe": "FakeHand.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "d3dmetal", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": "", "byHand": "It works for minutes."}]}
JSON
/usr/bin/python3 - "$RES" <<'PY'
import hashlib, json, pathlib, sys
res = pathlib.Path(sys.argv[1])
files = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in ("install-fake.sh", "install-fakekeys.sh", "install-fakeapp.sh", "fakeapp.recipes", "install-fakedll.sh", "fakefix.dll", "games.json")}
json.dump({"version": 4000000000, "minimumApp": "1.4.0", "files": files}, open(res / "catalog.json", "w"))
PY
PUB="$("$BIN" --new-signing-key "$T/test.key")"
"$BIN" --make-catalog "$T/release" --key "$T/test.key" --from "$RES" >/dev/null

echo "== a signed catalog"
cp -R "$T/release" "$T/zip-changed"; printf 'x' >> "$T/zip-changed/catalog.zip"
check 'has "$(update "$T/zip-changed" --pubkey "$PUB")" "catalog.zip does not match"' "a changed catalog.zip is refused"
cp -R "$T/release" "$T/json-changed"; sed -i '' 's/4000000000/4000000001/' "$T/json-changed/catalog.json"
check 'has "$(update "$T/json-changed" --pubkey "$PUB")" "not signed"' "a changed catalog.json is refused"
check 'has "$(update "$T/release")" "not signed"' "a catalog signed with another key is refused"
check '[ ! -e "$SUPPORT/MacGameFix/catalog/current" ]' "nothing refused was put in place"
check 'has "$(update "$T/release" --pubkey "$PUB")" "catalog 4000000000"' "a signed catalog is taken"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000000 ] && [ -x "$SUPPORT/MacGameFix/catalog/current/install-fake.sh" ]' "and switched to, its installer executable"
check 'has "$(update "$T/release" --pubkey "$PUB")" "up to date"' "the same catalog again is up to date"

echo "== what each fix requires"
steam 1 4
games() { "$BIN" --games-report 2>&1; }
check 'has "$(games)" "Fake Game | runs on DXMT, its videos need CrossOver Preview 27, which ships their codec"' "a fix's requirements are said beside the game, and nothing is asked"
check '! has "$(games)" "Fake Trial"' "a fix being tested is not listed while the testing switch is off"
touch "$GAME/FakeHand.exe"
check 'has "$(games)" "Fake Hand | runs on D3DMetal | installed from the window only"' "a fix installed from the window only is listed, and says so"
rm -f "$GAME/FakeHand.exe"
printf '{"testingFixes":true,"updates":false}' > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$(games)" "Fake Trial | runs on D3DMetal" && has "$(games)" "Fake Game |"' "with it on, the fix being tested is listed beside the others"
rm -f "$SUPPORT/MacGameFix/automatic.json"

echo "== the agent"
printf '{"kept":[{"name":"Fake Hand","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
steam 1 4; rm -f "$GAME/fixed.marker"; touch "$GAME/FakeHand.exe"
check '[ -z "$(agent)" ] && [ ! -f "$GAME/fixed.marker" ]' "a fix installed from the window only is never run by the agent, even marked Keep"
rm -f "$GAME/FakeHand.exe"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
steam 1 4
check 'has "$(agent)" "ok Fake Game: The fix was missing" && [ -f "$GAME/fixed.marker" ]' "a marked fix that is missing is installed"
check '[ -z "$(agent)" ]' "nothing changed, nothing done"
rm -f "$GAME/fixed.marker"; steam 2 4
check 'has "$(agent)" "Steam changed the game" && [ -f "$GAME/fixed.marker" ]' "after a game update the fix is put back"
rm -f "$GAME/fixed.marker"; steam 3 1026
check '[ -z "$(agent)" ] && [ ! -f "$GAME/fixed.marker" ]' "not while Steam is still writing the game"
steam 3 4
check 'has "$(agent)" "back in place" && [ -f "$GAME/fixed.marker" ]' "once Steam is done"
# A process whose command line names the game's executable, as Wine's does.
mkdir -p "$T/run"; printf '#!/bin/bash\nsleep 60\n' > "$T/run/FakeGame.exe"; chmod +x "$T/run/FakeGame.exe"
"$T/run/FakeGame.exe" 60 & GAME_PID=$!
rm -f "$GAME/fixed.marker"; steam 4 4
check '[ -z "$(agent)" ] && [ ! -f "$GAME/fixed.marker" ]' "not while the game runs"
kill "$GAME_PID"; wait "$GAME_PID" 2>/dev/null || true; GAME_PID=0
check 'has "$(agent)" "back in place" && [ -f "$GAME/fixed.marker" ]' "once the game is closed"
rm -f "$GAME/fixed.marker"; touch "$GAME/FAIL"; steam 5 4
OUT="$(agent)"
check 'has "$OUT" "FAILED Fake Game: The installer failed (status 1)."' "a failing installer is reported"
REPORT="$(echo "$OUT" | sed -n 's/^report //p' | /usr/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))')"
check 'has "$REPORT" "issues/new" && has "$REPORT" "cannot write ~/Library"' "with a filled-in issue holding the installer output"
check 'has "$REPORT" "installing into" && ! has "$REPORT" "MGVF-PROGRESS"' "and none of the lines the installer says its progress with"
check '! has "$REPORT" "$MACGAMEFIX_HOME"' "and the home folder replaced by ~"
check '[ "$(/usr/bin/python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))[\"events\"]))" "$SUPPORT/MacGameFix/agent-state.json")" = 5 ]' "the agent's events are kept for the window"
OUT="$(menu)"
check 'has "$OUT" "summary | 1 to review" && has "$OUT" "Fake Game | Failed | The installer failed (status 1). | report"' "the menu bar counts the failure, and the window has it with its report"
check 'has "$OUT" "news | yes"' "and the menu bar shows its dot"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false,"seen":9999999999}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$(menu)" "news | no"' "until the window has been opened"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"

echo "== the agent, whatever runs the game"
# A settings file an older version wrote, with what the user said the game runs
# on: nothing of it is read any more, and the rest of the file still is.
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false,"runtimes":{"%s|Fake Game":{"source":"your choice","build":"26.3.0.39832","backend":"d3dmetal","noD3DMetal":false,"setUpHere":false}}}' "$GAME" "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
rm -f "$GAME/FAIL" "$GAME/fixed.marker"; steam 6 4
check 'has "$(agent)" "back in place" && [ -f "$GAME/fixed.marker" ]' "the fix goes back into the game folder whatever runs the game"
check 'has "$(menu)" "summary | 1 in place"' "and the menu bar counts it in place"
printf '{"kept":[{"name":"Fake Game","folder":"%s"},{"name":"Gone Game","folder":"%s"}],"updates":false}' "$GAME" "$T/gone" > "$SUPPORT/MacGameFix/automatic.json"
OUT="$(menu)"
check 'has "$OUT" "summary | 1 to review" && has "$OUT" "Gone Game | Folder not found"' "a marked game whose folder is gone is to review"

echo "== an older build of a fix"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
echo 1 > "$GAME/fixed.marker"; steam 7 4
check 'has "$(agent)" "ok Fake Game: The fix is updated to the newer build." && [ "$(cat "$GAME/fixed.marker")" = 2 ]' "an older build in the game folder is replaced with the catalog's"

echo "== a fix that writes registry keys, into more than one prefix"
KEYS="$SUPPORT/Steam/steamapps/common/Fake Keys"; KEYS2="$T/elsewhere/Fake Keys"
PA="$T/prefix-a"; PB="$T/prefix-b"; PC="$T/prefix-c"
mkdir -p "$KEYS" "$KEYS2" "$PA" "$PB" "$PC"; touch "$KEYS/FakeKeys.exe" "$KEYS2/FakeKeys.exe"
# As a version before 1.5.1 wrote it: one prefix.
printf '{"kept":[{"name":"Fake Keys","folder":"%s","prefix":"%s"}],"updates":false}' "$KEYS" "$PA" \
  > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$(agent)" "ok Fake Keys: The fix was missing" && [ -f "$PA/fake.key" ] && [ ! -f "$PB/fake.key" ]' "a game kept with the one prefix an older version saved still gets it"
printf '{"kept":[{"name":"Fake Keys","folder":"%s","prefix":"%s"},{"name":"Fake Keys","folder":"%s","prefixes":["%s","%s"]}],"updates":false}' \
  "$KEYS" "$PA" "$KEYS2" "$PB" "$PC" > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$(agent)" "ok Fake Keys: The fix was missing" && [ -f "$KEYS2/keys.marker" ] && [ -f "$PB/fake.key" ] && [ -f "$PC/fake.key" ]' "with two prefixes chosen, the keys go into both"
check 'has "$(menu)" "summary | 2 in place"' "and the menu bar counts both games in place"

echo "== a fix whose DLLs go into the prefix"
FP="$SUPPORT/Steam/steamapps/common/Fake Prefix"
mkdir -p "$FP" "$SUPPORT/Steam/steamapps/compatdata/4343/pfx"; touch "$FP/FakePrefix.exe" "$SUPPORT/Steam/steamapps/compatdata/4343/pfx/user.reg"
printf '"AppState"\n{\n\t"appid"\t\t"4343"\n\t"name"\t\t"Fake Prefix"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Fake Prefix"\n}\n' \
  > "$SUPPORT/Steam/steamapps/appmanifest_4343.acf"
check 'has "$(games)" "Fake Prefix | runs on DXVK | DLLs into the Steam Play prefix (4343)"' "its DLLs are said to go into the game's Steam Play prefix"
rm -rf "$FP" "$SUPPORT/Steam/steamapps/compatdata/4343" "$SUPPORT/Steam/steamapps/appmanifest_4343.acf"
check 'has "$(games)" "Fake Game |" && ! has "$(games)" "Fake Prefix"' "and a game that is not on disk is not listed"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"

echo "== a fix for a macOS game's app, made for each build of the game"
# The executable's name stays out of every command line here: the agent takes a
# process naming it for the game running.
FN="$SUPPORT/Steam/steamapps/common/Fake Native"
mkdir -p "$FN/FakeNative.app/Contents/MacOS"; touch "$FN/FakeNative.app/Contents/MacOS/FakeNative"
native() { # the build: Steam's buildid, and the app's own
  printf '"AppState"\n{\n\t"appid"\t\t"4545"\n\t"name"\t\t"Fake Native"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Fake Native"\n\t"buildid"\t\t"%s"\n}\n' "$1" \
    > "$SUPPORT/Steam/steamapps/appmanifest_4545.acf"
  echo "$1" > "$FN/FakeNative.app/Contents/build"
}
native 2
check 'has "$(games)" "Fake Native | macOS app; changes its executable"' "a fix that changes a macOS game's app says so beside the game"
printf '{"kept":[{"name":"Fake Native","folder":"%s"}],"updates":false,"modulesUpdates":false}' "$FN" > "$SUPPORT/MacGameFix/automatic.json"
OUT="$(agent)"
check 'has "$OUT" "ok Fake Native: No recipe for this build yet; MacGameFix puts it back when one arrives." && ! has "$OUT" "FAILED" && ! has "$OUT" "report " && [ ! -e "$FN/runs" ]' "with no recipe for the game's build the agent waits: no installer run, no failure, no report"
check '[ -z "$(agent)" ]' "and nothing more while nothing changes"
# A newer catalog, still with no recipe for build 2: the agent looks again, and
# does not say it again.
recatalog() { # recatalog <dir> <version>: <dir>'s files, signed as that catalog
  /usr/bin/python3 - "$1" "$2" <<'PY'
import hashlib, json, pathlib, sys
res = pathlib.Path(sys.argv[1])
m = json.load(open(res / "catalog.json"))
m["version"] = int(sys.argv[2])
m["files"] = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in m["files"]}
json.dump(m, open(res / "catalog.json", "w"))
PY
  "$BIN" --make-catalog "$1.release" --key "$T/test.key" --from "$1" >/dev/null
}
cp -R "$RES" "$T/res-norecipe"; recatalog "$T/res-norecipe" 4000000001
check 'has "$(update "$T/res-norecipe.release" --pubkey "$PUB")" "catalog 4000000001"' "a newer catalog with still no recipe for that build is taken"
check '[ -z "$(agent)" ] && [ ! -e "$FN/runs" ] && has "$(menu)" "Fake Native | Waiting for a recipe"' "and the agent, looking again, says nothing twice for the same build"
OUT="$(menu)"
check 'has "$OUT" "Fake Native | Waiting for a recipe" && has "$OUT" "summary | 1 waiting for a recipe" && ! has "$OUT" "to review"' "the menu bar counts it waiting for a recipe, not to review"
native 3
check 'has "$(agent)" "ok Fake Native: No recipe for this build yet" && [ ! -e "$FN/runs" ]' "a Steam update to another build with no recipe is said again, once for that build"
# The next catalog carries a recipe for build 3.
cp -R "$RES" "$T/res-recipe"; printf '1\n3\n' > "$T/res-recipe/fakeapp.recipes"; recatalog "$T/res-recipe" 4000000002
check 'has "$(update "$T/res-recipe.release" --pubkey "$PUB")" "catalog 4000000002"' "a newer catalog with a recipe for that build is taken"
OUT="$(agent)"
check 'has "$OUT" "ok Fake Native: A recipe for this build arrived; the fix is in place." && [ -f "$FN/fixed.marker" ] && [ "$(cat "$FN/runs")" = 3 ] && has "$(menu)" "Fake Native | In place"' "and the agent installs the fix at its next look"
# After a game update, the executable patched outside MacGameFix: its installer
# refuses, and running it would fail at every look.
WHY_HALF="The executable is patched, but not by MacGameFix. Verify the game in Steam, then install here."
echo "$WHY_HALF" > "$FN/half"; native 4
OUT="$(agent)"
check 'has "$OUT" "ok Fake Native: $WHY_HALF" && ! has "$OUT" "FAILED" && ! has "$OUT" "report " && [ "$(cat "$FN/runs")" = 3 ]' "patched outside MacGameFix: the installer's reason, and no installer run, no failure, no report"
OUT="$(menu)"
check 'has "$OUT" "Fake Native | Cannot be installed here | $WHY_HALF" && ! has "$OUT" "$WHY_HALF | report"' "the menu bar has it to review, with that reason and no report"
# Six hours on, nothing changed: looked at again, and not said again.
/usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for g in d["games"].values(): g["checked"] = g.get("checked", 0) - 7 * 3600
json.dump(d, open(sys.argv[1], "w"))
PY
check '[ -z "$(agent)" ] && [ "$(cat "$FN/runs")" = 3 ]' "and at the recheck hours later, nothing is run or said again"
WHY_CHIP="This Mac has an Apple M2 Pro. Apple lists MetalFX denoised upscaling for M3 and later."
rm -f "$FN/half"; echo "$WHY_CHIP" > "$FN/blocked"; native 5
OUT="$(agent)"
check 'has "$OUT" "ok Fake Native: $WHY_CHIP" && ! has "$OUT" "FAILED" && ! has "$OUT" "report " && [ "$(cat "$FN/runs")" = 3 ]' "blocked, on a Mac the fix is not for: the same, with that reason"
rm -rf "$FN" "$SUPPORT/Steam/steamapps/appmanifest_4545.acf"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"

echo "== the controllers' options"
export MACGAMEFIX_PAD_LOG="$T/pad.log"
P="$SUPPORT/MacGameFix"
padwrite() { "$BIN" --pad-write >/dev/null 2>&1; }
padreport() { "$BIN" --pad-report 2>&1; }
padwrite
check '[ -f "$P/pad.json" ] && has "$(cat "$P/pad.conf")" "bluetooth=wired" && has "$(cat "$P/pad.conf")" "motor_power=full" && has "$(cat "$P/pad.conf")" "edge_haptics_gain_cable=1.00" && has "$(cat "$P/pad.conf")" "edge_haptics_gain_bluetooth=1.00" && has "$(cat "$P/pad.conf")" "haptics_gain_bluetooth=1.00"' "every game's options start as measured, in pad.conf"
check 'has "$(cat "$P/pad.d/1593500.conf")" "edge=dualsense" && ! has "$(cat "$P/pad.d/1593500.conf")" "bluetooth="' "a game with a preset gets its own file, with only what differs"
/usr/bin/python3 - "$P/pad.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["games"] = {"1593500": {"name": "God of War", "options": {"edgeAsDualSense": False}}, "4242": {"name": "Fake Game", "options": {"hapticsGain": 2.5}}, "4243": {"name": "Other Game", "options": {"hapticsGainBluetooth": 2}}, "4244": {"name": "XInput Game", "options": {"xinput": "off", "triggerR2": "weapon@6", "triggerL2": "rumble", "triggerR2WithL2": "weapon@8", "triggerR2Replace": True}}}
json.dump(d, open(sys.argv[1], "w"))
PY2
padwrite
check '[ ! -f "$P/pad.d/1593500.conf" ]' "the user's own options win over a preset, and a game left as every game loses its file"
check 'has "$(cat "$P/pad.d/4242.conf")" "haptics_gain_cable=2.50" && has "$(cat "$P/pad.d/4242.conf")" "haptics_gain_bluetooth=2.50"' "a game's own gain, written with a point whatever the language; one gain from before counts for both connections"
check 'has "$(cat "$P/pad.d/4243.conf")" "haptics_gain_bluetooth=2.00" && ! has "$(cat "$P/pad.d/4243.conf")" "haptics_gain_cable="' "a gain over Bluetooth alone leaves the cable to every game's"
check 'has "$(cat "$P/pad.conf")" "xinput=rumble" && has "$(cat "$P/pad.conf")" "rumble=motors" && has "$(cat "$P/pad.conf")" "trigger_r2=off" && has "$(cat "$P/pad.d/4244.conf")" "xinput=off" && has "$(cat "$P/pad.d/4244.conf")" "trigger_r2=weapon@6" && has "$(cat "$P/pad.d/4244.conf")" "trigger_l2=rumble" && has "$(cat "$P/pad.d/4244.conf")" "trigger_r2_with_l2=weapon@8" && has "$(cat "$P/pad.conf")" "trigger_l2_with_r2=off" && has "$(cat "$P/pad.conf")" "trigger_r2_replace=off" && has "$(cat "$P/pad.d/4244.conf")" "trigger_r2_replace=on" && ! has "$(cat "$P/pad.d/4244.conf")" "trigger_l2_replace"' "XInput's rumble for every game, triggers free; a game's own written as the modules read them, a second effect and a replaced effect too"
check 'has "$(cat "$P/pad.d/4242.conf")" "xinput=pad" && has "$(cat "$(dirname "$P")/MacGameFix/pad.json")" "\"dualSense\" : false"' "a game the store does not list for the DualSense gets the pad as an XInput controller, and the answer is kept"
# A pad shown as a DualShock 4 is one game's alone, and is written as wired over
# Bluetooth whatever the game's Bluetooth row says; its XInput line is always
# written, off unless the game asks for XInput's rumble (ds4XInputRumble), never
# the pad as a controller.
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); d["defaults"]["asDualShock4"] = True; d["games"]["4245"] = {"name": "PS4 Game", "options": {"asDualShock4": True, "xinput": "pad", "bluetoothAsCable": False}}
json.dump(d, open(sys.argv[1], "w"))
PY4
padwrite
ds4every() { /usr/bin/python3 -c 'import json, sys; print("asDualShock4" in json.load(open(sys.argv[1]))["defaults"])' "$P/pad.json"; }
check 'has "$(cat "$P/pad.d/4245.conf")" "pad_as=dualshock4" && has "$(cat "$P/pad.d/4245.conf")" "bluetooth=wired" && ! has "$(cat "$P/pad.d/4245.conf")" "bluetooth=off" && has "$(cat "$P/pad.d/4245.conf")" "xinput=off" && ! has "$(cat "$P/pad.d/4245.conf")" "xinput=pad" && ! has "$(cat "$P/pad.conf")" "pad_as=" && [ "$(ds4every)" = False ]' "a game shown as a DualShock 4 gets pad_as=dualshock4, Bluetooth as a cable and XInput off; every game's never gets it"
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); d["games"]["4245"]["options"]["ds4XInputRumble"] = True
json.dump(d, open(sys.argv[1], "w"))
PY4
padwrite
check 'has "$(cat "$P/pad.d/4245.conf")" "xinput=rumble" && ! has "$(cat "$P/pad.d/4245.conf")" "xinput=off" && ! has "$(cat "$P/pad.d/4245.conf")" "xinput=pad"' "shown as a DualShock 4 with XInput's rumble asked for, the game's own file says xinput=rumble"
# Every game's Edge shown as a DualSense: winecoreaudio.so reads edge alone, so a game shown as a
# DualShock 4 says edge=edge in its own file, which the modules read first. The whole file, read back.
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); d["defaults"]["edgeAsDualSense"] = True
json.dump(d, open(sys.argv[1], "w"))
PY4
padwrite
check 'has "$(cat "$P/pad.conf")" "edge=dualsense" && [ "$(/usr/bin/grep -v "^#" "$P/pad.d/4245.conf" | tr "\n" " ")" = "bluetooth=wired edge=edge pad_as=dualshock4 xinput=rumble " ]' "every game's Edge shown as a DualSense, a game shown as a DualShock 4 gets edge=edge beside pad_as=dualshock4 in its own file, and nothing else changes there"
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); d["defaults"]["edgeAsDualSense"] = False
json.dump(d, open(sys.argv[1], "w"))
PY4
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); del d["games"]["4245"]["options"]["ds4XInputRumble"]
json.dump(d, open(sys.argv[1], "w"))
PY4
/usr/bin/python3 - "$P/pad.json" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); del d["games"]["4245"]["options"]["asDualShock4"]
json.dump(d, open(sys.argv[1], "w"))
PY4
padwrite
check 'has "$(cat "$P/pad.d/4245.conf")" "xinput=pad" && has "$(cat "$P/pad.d/4245.conf")" "bluetooth=off" && ! has "$(cat "$P/pad.d/4245.conf")" "pad_as=" && ! has "$(cat "$P/pad.d/4245.conf")" "bluetooth=wired"' "cleared, the line goes and the game's other options stay, its Bluetooth row again"
printf '10:00:00 [1] game=4242 observed: the game plays haptics on the Bluetooth DualSense Edge%ss output\n10:00:01 [2] game=4242 observed: the game sets trigger effects on the DualSense Edge\n10:00:02 [3] game=- the Bluetooth DualSense Edge at location 32c48ef2 is shown as wired\n10:00:03 [4] game=4242 observ' "'" > "$MACGAMEFIX_PAD_LOG"
padwrite
check 'has "$(padreport)" "4242 | Fake Game | " && has "$(padreport)" "seen haptics,triggers"' "what the modules logged is kept per game; a line with no game says nothing"
printf 'ed: the game rumbles the DualSense%ss motors\n' "'" >> "$MACGAMEFIX_PAD_LOG"
padwrite
check 'has "$(padreport)" "seen haptics,motors,triggers"' "a line the log had only half of is read once it is whole"
/usr/bin/python3 - "$P/pad.json" <<'PY3'
import json, sys
d = json.load(open(sys.argv[1])); d["games"].setdefault("4242", {"name": "Fake Game"})["diagnose"] = True
json.dump(d, open(sys.argv[1], "w"))
PY3
padwrite
check 'has "$(cat "$P/pad.d/4242.conf")" "diagnostics=on" && ! has "$(cat "$P/pad.conf")" "diagnostics=on"' "diagnosing one game turns the modules' diagnostics on for that game alone"
printf '10:00:05 [5] game=999 observed: the game rumbles the DualSense%ss motors\n10:00:06 [6] game=4242 the DualSense%ss Bluetooth writer is not listening at %s/x.sock\n' "'" "'" "$MACGAMEFIX_HOME" >> "$MACGAMEFIX_PAD_LOG"
"$BIN" --pad-game-report 4242 "$T/report.md" >/dev/null 2>&1
check 'has "$(cat "$T/report.md")" "Steam app 4242" && has "$(cat "$T/report.md")" "game=4242 observed: the game sets trigger effects" && has "$(cat "$T/report.md")" "xinput=pad" && ! has "$(cat "$T/report.md")" "game=999" && ! has "$(cat "$T/report.md")" "$MACGAMEFIX_HOME"' "a game's report has its log and settings, no other game, and no home folder"
"$BIN" --pad-export "$T/pad-export.json"
check 'has "$(cat "$T/pad-export.json")" "\"appid\" : \"4242\"" && ! has "$(cat "$T/pad-export.json")" "$MACGAMEFIX_HOME" && ! has "$(cat "$T/pad-export.json")" "/Users/"' "the export has the games and no paths"
# Which game an exe is, for the modules in a CrossOver bottle.
OX="$SUPPORT/Steam/steamapps/common/Other Exe"
mkdir -p "$OX/a/b/c/d"
printf '"AppState"\n{\n\t"appid"\t\t"4646"\n\t"name"\t\t"Other Exe"\n\t"installdir"\t\t"Other Exe"\n}\n' \
  > "$SUPPORT/Steam/steamapps/appmanifest_4646.acf"
touch "$OX/Other.EXE" "$OX/Shared.exe" "$GAME/Shared.exe" "$OX/a/b/c/Four.exe" "$OX/a/b/c/d/Deep.exe"
padwrite
check '[ "$(/usr/bin/grep -v "^#" "$P/pad-exes.conf" | sort | tr "\n" " ")" = "fakegame.exe=4242 four.exe=4646 other.exe=4646 " ]' "each exe one game alone has is named for it, in lower case, four folders deep; one two games share is not"
echo "# kept" >> "$P/pad-exes.conf"
padwrite
check 'has "$(cat "$P/pad-exes.conf")" "# kept"' "the same games are not looked through again"
printf '"AppState"\n{\n\t"appid"\t\t"4747"\n\t"name"\t\t"New Exe"\n\t"installdir"\t\t"New Exe"\n}\n' \
  > "$SUPPORT/Steam/steamapps/appmanifest_4747.acf"
mkdir -p "$SUPPORT/Steam/steamapps/common/New Exe" && touch "$SUPPORT/Steam/steamapps/common/New Exe/New.exe"
padwrite
check 'has "$(cat "$P/pad-exes.conf")" "new.exe=4747" && ! has "$(cat "$P/pad-exes.conf")" "# kept"' "a new game is"
rm -rf "$OX" "$SUPPORT/Steam/steamapps/common/New Exe" "$GAME/Shared.exe" \
  "$SUPPORT/Steam/steamapps/appmanifest_4646.acf" "$SUPPORT/Steam/steamapps/appmanifest_4747.acf"
# A game outside Steam the user added to it: listed by its shortcut, under the game id
# Steam starts it with, which is the id the modules log and read pad.d/ by.
SC="$SUPPORT/Steam/userdata/12345/config"
mkdir -p "$SC"
/usr/bin/python3 - "$SC/shortcuts.vdf" <<'PY3'
import struct, sys
def s(k, v): return b"\x01" + k.encode() + b"\x00" + v.encode() + b"\x00"
def i(k, v): return b"\x02" + k.encode() + b"\x00" + struct.pack("<I", v)
def m(k, body): return b"\x00" + k.encode() + b"\x00" + body + b"\x08"
one = i("appid", 4227251710) + s("AppName", "FC 27") + s("Exe", '"/x/FC27.app"') + m("tags", s("0", "Football"))
two = i("appid", 100) + s("appname", "Lower Game")
zero = i("appid", 0) + s("AppName", "No Id")
open(sys.argv[1], "wb").write(m("shortcuts", m("0", one) + m("1", two) + m("2", zero)) + b"\x08")
PY3
FC=18155907846443630592
/usr/bin/python3 - "$P/pad.json" "$FC" <<'PY4'
import json, sys
d = json.load(open(sys.argv[1])); d["games"][sys.argv[2]] = {"name": sys.argv[2], "options": {"hapticsGain": 2.5}}
json.dump(d, open(sys.argv[1], "w"))
PY4
printf '10:07:00 [13] game=%s observed: the game rumbles the DualSense%ss motors\n' "$FC" "'" >> "$MACGAMEFIX_PAD_LOG"
padwrite
check 'has "$(cat "$P/pad.d/$FC.conf")" "# FC 27" && has "$(cat "$P/pad.d/$FC.conf")" "haptics_gain_cable=2.50"' "a game added to Steam gets its own file under its game id, named by its shortcut"
check 'has "$(padreport)" "$FC | FC 27 | " && has "$(padreport)" "seen motors"' "what the modules saw of it is kept under its name"
check '! /usr/bin/python3 -c "import json,sys; g=json.load(open(sys.argv[1]))[\"games\"][sys.argv[2]]; sys.exit(0 if \"storeUnknown\" in g or \"dualSense\" in g else 1)" "$P/pad.json" "$FC"' "and the Steam store is not asked about it"
"$BIN" --pad-game-report "$FC" "$T/fc-report.md" >/dev/null 2>&1
check 'has "$(cat "$T/fc-report.md")" "FC 27, a non-Steam game added to Steam, game id $FC" && ! has "$(cat "$T/fc-report.md")" "Steam app $FC"' "its report says what it is, not a Steam app"
rm -rf "$SUPPORT/Steam/userdata" "$P/pad.d/$FC.conf"
/usr/bin/python3 - "$P/pad.json" "$FC" <<'PY5'
import json, sys
d = json.load(open(sys.argv[1])); d["games"].pop(sys.argv[2], None)
json.dump(d, open(sys.argv[1], "w"))
PY5
# The settings form's link, its fields read as GitHub reads them: a bare + is a space.
shareform() {
    /usr/bin/python3 - "$("$BIN" --pad-share-url "$1")" <<'PY3'
import sys, urllib.parse
for k, v in urllib.parse.parse_qsl(urllib.parse.urlsplit(sys.argv[1]).query):
    print(k + ": " + v.replace("\n", " | "))
PY3
}
check 'has "$(shareform 4242)" "template: game-feel-settings.yml" && has "$(shareform 4242)" "game: Fake Game (Steam app 4242)" && has "$(shareform 4242)" "settings: bluetooth=" && has "$(shareform 4242)" " | xinput=pad | " && has "$(shareform 4242)" " | trigger_l2_with_r2="' "sharing a game's settings opens the settings form with the game and every option it gets"
/usr/bin/python3 - "$P/pad.json" <<'PY3'
import json, sys
d = json.load(open(sys.argv[1])); d["games"]["4343"] = {"name": "Plus 1.5+2.5"}
json.dump(d, open(sys.argv[1], "w"))
PY3
check 'has "$(shareform 4343)" "title: [Settings] Plus 1.5+2.5"' "a plus in a game's name stays a plus"
# The form It Vibrates opens: the pad and the connection of the game's latest session, the last process that named it.
vibratesform() {
    /usr/bin/python3 - "$("$BIN" --pad-vibrates-url "$1")" <<'PY3'
import sys, urllib.parse
for k, v in urllib.parse.parse_qsl(urllib.parse.urlsplit(sys.argv[1]).query):
    print(k + ": " + v.replace("\n", " | "))
PY3
}
printf '10:01:00 [7] game=4242 the Bluetooth DualSense Edge at location 32c48ef2 is shown as wired\n10:01:01 [7] game=4242 observed: the game plays haptics on the Bluetooth DualSense Edge%ss output\n' "'" >> "$MACGAMEFIX_PAD_LOG"
check 'has "$(vibratesform 4242)" "template: vibration-works.yml" && has "$(vibratesform 4242)" "title: [Vibrates] Fake Game · DualSense Edge · Bluetooth" && has "$(vibratesform 4242)" "controller: DualSense Edge" && has "$(vibratesform 4242)" "connection: Bluetooth" && has "$(vibratesform 4242)" "game: Fake Game (Steam app 4242)" && has "$(vibratesform 4242)" "settings: bluetooth=" && ! has "$(vibratesform 4242)" "shown-as:"' "saying a game vibrates opens the vibration form with the pad and the connection of its latest session, and no identity for a pad shown as itself"
printf '10:02:00 [8] game=4242 the wired DualSense sent 2000 input reports in 2 s\n10:02:01 [8] game=4242 the Bluetooth DualSense Edge at location 32c48ef2 is shown as wired\n' >> "$MACGAMEFIX_PAD_LOG"
check '! has "$(vibratesform 4242)" "controller:" && ! has "$(vibratesform 4242)" "connection:" && has "$(vibratesform 4242)" "title: [Vibrates] Fake Game"' "a session with two pads and two connections leaves both to the player"
# A pad shown as a DualShock 4, as 0013 names it in the log: the identity goes into its field and the title.
printf '10:03:00 [9] game=4242 the Bluetooth DualSense Edge (shown as a DualShock 4) at location 32c48ef2 is shown as wired\n10:03:00 [9] game=4242 the DualSense Edge (shown as a DualShock 4) at location 32c48ef2 is shown to the game as a USB DualShock 4 (054C:05C4)\n10:03:05 [9] game=4242 observed: the game rumbles the DualSense Edge (shown as a DualShock 4)%ss motors\n' "'" >> "$MACGAMEFIX_PAD_LOG"
check 'has "$(vibratesform 4242)" "title: [Vibrates] Fake Game · DualSense Edge · Bluetooth · shown as a DualShock 4" && has "$(vibratesform 4242)" "controller: DualSense Edge" && has "$(vibratesform 4242)" "shown-as: DualShock 4" && [ "$(vibratesform 4242 | cut -d: -f1 | tr "\n" " ")" = "template title game controller connection shown-as seen settings " ]' "a pad shown as a DualShock 4 is reported as shown as one, in its own field and in the title, and no other field changes"
# The next session shows the pad as itself: the identity was the earlier session's alone.
printf '10:04:00 [10] game=4242 the Bluetooth DualSense Edge at location 32c48ef2 is shown as wired\n' >> "$MACGAMEFIX_PAD_LOG"
check '! has "$(vibratesform 4242)" "shown-as:" && has "$(vibratesform 4242)" "title: [Vibrates] Fake Game · DualSense Edge · Bluetooth" && ! has "$(vibratesform 4242)" "shown as a"' "an identity an earlier session of the game had is not reported for its latest, which showed the pad as itself"
# Two pads, an Edge shown as a DualSense (0004's wording) and a standard DualSense as itself: the identity is
# one pad's, so it is left to the player with the controller.
printf '10:05:00 [11] game=4242 the Bluetooth DualSense Edge (shown as a DualSense) at location 32c48ef2 is shown as wired\n10:05:01 [11] game=4242 the Bluetooth DualSense at location 1ac3b41b is shown as wired\n' >> "$MACGAMEFIX_PAD_LOG"
check '! has "$(vibratesform 4242)" "controller:" && ! has "$(vibratesform 4242)" "shown-as:" && has "$(vibratesform 4242)" "connection: Bluetooth" && ! has "$(vibratesform 4242)" "shown as a"' "a session with two pads, one of them shown as another, leaves the identity to the player with the controller"
printf '10:06:00 [12] game=4242 the Bluetooth DualSense Edge (shown as a DualShock 4) at location 32c48ef2 is shown as wired\n10:06:01 [12] game=4242 the Bluetooth DualSense Edge (shown as a DualSense) at location 32c48ef2 is shown as wired\n' >> "$MACGAMEFIX_PAD_LOG"
check '! has "$(vibratesform 4242)" "shown-as:" && has "$(vibratesform 4242)" "title: [Vibrates] Fake Game · DualSense Edge · Bluetooth" && ! has "$(vibratesform 4242)" "shown as a"' "a session that showed the pad as two pads leaves the identity to the player"
unset MACGAMEFIX_PAD_LOG

echo "== the Report tab's probe"
PG="$SUPPORT/Steam/steamapps/common/Probe Game"
PFX="$SUPPORT/Steam/steamapps/compatdata/4949/pfx"
mkdir -p "$PG/ProbeGame/Binaries/Win64" "$PG/Content/Movies" "$PFX/drive_c/users/steamuser/AppData/Local/ProbeGame/Saved/Logs"
printf '"AppState"\n{\n\t"appid"\t\t"4949"\n\t"name"\t\t"Probe Game"\n\t"installdir"\t\t"Probe Game"\n}\n' \
  > "$SUPPORT/Steam/steamapps/appmanifest_4949.acf"
touch "$PFX/user.reg" "$PG/ProbeGame/Binaries/Win64/sl.interposer.dll" "$PG/ProbeGame/Binaries/Win64/libxess.dll" \
  "$PG/ProbeGame/Binaries/Win64/libScePad.dll" "$PG/ProbeGame/Binaries/Win64/CrashReportClient.exe"
# A Windows executable as small as one can be: one section holding its imports and the delay-loaded ones,
# each a list with commas, and the branch name Unreal builds into its executables.
pe() { # <file> <imports> [delay-loaded]
/usr/bin/python3 - "$@" <<'PY4'
import struct, sys
dlls = [d.encode() for d in sys.argv[2].split(",") if d]
delay = [d.encode() for d in (sys.argv[3] if len(sys.argv) > 3 else "").split(",") if d]
va, raw = 0x1000, 0x400
sec = bytearray(0x1000)
imp, dly = 0, 20 * (len(dlls) + 1)
at, rvas = dly + 32 * (len(delay) + 1), []
for d in dlls + delay:
    sec[at:at + len(d)] = d; rvas.append(va + at); at += len(d) + 1
for i in range(len(dlls)): struct.pack_into("<IIIII", sec, imp + 20 * i, 0, 0, 0, rvas[i], 0)
for j in range(len(delay)): struct.pack_into("<8I", sec, dly + 32 * j, 1, rvas[len(dlls) + j], 0, 0, 0, 0, 0, 0)
opt = bytearray(240)
struct.pack_into("<H", opt, 0, 0x20b); struct.pack_into("<Q", opt, 24, 0x140000000); struct.pack_into("<I", opt, 108, 16)
struct.pack_into("<II", opt, 112 + 8, va + imp, 20 * (len(dlls) + 1))
struct.pack_into("<II", opt, 112 + 8 * 13, va + dly, 32 * (len(delay) + 1))
dos = bytearray(64); dos[0:2] = b"MZ"; struct.pack_into("<I", dos, 0x3c, 0x40)
head = bytes(dos) + struct.pack("<4sHHIIIHH", b"PE\0\0", 0x8664, 1, 0, 0, 0, 240, 0x22) + bytes(opt) \
    + struct.pack("<8sIIIIIIHHI", b".idata\0\0", 0x1000, va, 0x1000, raw, 0, 0, 0, 0, 0xC0000040)
image = bytearray(raw); image[:len(head)] = head
open(sys.argv[1], "wb").write(bytes(image + sec) + "++UE5+Release-5.3".encode("utf-16-le"))
PY4
}
pe "$PG/ProbeGame/Binaries/Win64/ProbeGame-Win64-Shipping.exe" \
  d3d12.dll,dxgi.dll,XINPUT1_4.dll,mfplat.dll,api-ms-win-core-synch-l1-2-0.dll hid.dll
printf '\x1a\x45\xdf\xa3....webm....V_VP9....' > "$PG/Content/Movies/intro.webm"
printf '\x30\x26\xb2\x75\x8e\x66\xcf\x11....WMV3....' > "$PG/Content/Movies/old.wmv"
HOST_NAME="$(hostname -s)"
printf 'LogInit: Computer: %s\nLogInit: Base directory: Z:%s/Library\nPROBE LAST LINE\n' \
  "$(printf '%s' "$HOST_NAME" | tr '[:lower:]' '[:upper:]')" "$MACGAMEFIX_HOME" \
  > "$PFX/drive_c/users/steamuser/AppData/Local/ProbeGame/Saved/Logs/ProbeGame.log"
check 'has "$("$BIN" --probe-games)" "4949 | Probe Game | Steam Play prefix (4949)"' "every Steam game is listed, with the prefix it runs in"
"$BIN" --probe-report 4949 "$T/probe.md" video
PR="$(cat "$T/probe.md")"
check 'has "$PR" "Main executable: ProbeGame/Binaries/Win64/ProbeGame-Win64-Shipping.exe (x64)" && has "$PR" "Graphics: Direct3D 12" && has "$PR" "Engine: Unreal Engine 5.3" && has "$PR" "Controller: XInput, raw HID (reads controllers directly), Sony'"'"'s pad library (libScePad)"' "the main executable, its imports and the delay-loaded one, the engine and the controller libraries"
check 'has "$PR" "Video: Media Foundation, 1 WebM, VP9 (Content/Movies/intro.webm), 1 ASF, WMV3 (Content/Movies/old.wmv)" || has "$PR" "Video: Media Foundation, 1 ASF, WMV3 (Content/Movies/old.wmv), 1 WebM, VP9 (Content/Movies/intro.webm)"' "the videos by container and codec"
check 'has "$PR" "Middleware: NVIDIA Streamline, XeSS" && has "$PR" "(and 1 Windows API sets)" && ! has "$PR" "api-ms-win" && has "$PR" "What goes wrong: Videos or cutscenes"' "the middleware, the imports without the API sets, and what goes wrong"
check 'has "$PR" "ProbeGame.log, its last lines" && has "$PR" "PROBE LAST LINE" && has "$PR" "Z:~/Library" && ! has "$PR" "$MACGAMEFIX_HOME" && ! has "$PR" "$HOST_NAME" && ! has "$PR" "$(printf '%s' "$HOST_NAME" | tr '[:lower:]' '[:upper:]')" && ! has "$PR" "Fake Game"' "the game's own log, the home folder as ~, no Mac name and no other game"
# The library It Vibrates fills in, by the list's names: Sony's library whenever the game ships it, as for Mortal
# Kombat 11, which reads its input through DirectInput 8 and rumbles through libScePad, and for Crysis 2
# Remastered, which rumbles through XInput (the list keeps XInput); DirectInput for a game with no other way.
pe "$PG/ProbeGame/Binaries/Win64/ProbeGame-Win64-Shipping.exe" d3d11.dll,dxgi.dll,XINPUT1_3.dll
check 'has "$(MACGAMEFIX_PAD_LOG="$T/pad.log" vibratesform 4949)" "library: Sony libScePad"' "a game that imports XInput and ships Sony's library is reported as Sony libScePad, the folder's guess"
pe "$PG/ProbeGame/Binaries/Win64/ProbeGame-Win64-Shipping.exe" d3d11.dll,dinput8.dll
check 'has "$(MACGAMEFIX_PAD_LOG="$T/pad.log" vibratesform 4949)" "library: Sony libScePad"' "a game that imports DirectInput 8 and ships Sony's library is reported as Sony libScePad"
rm "$PG/ProbeGame/Binaries/Win64/libScePad.dll"
check 'has "$(MACGAMEFIX_PAD_LOG="$T/pad.log" vibratesform 4949)" "library: DirectInput"' "and one whose only way to the pad is DirectInput 8 as DirectInput"
rm -rf "$PG" "$SUPPORT/Steam/steamapps/compatdata/4949" "$SUPPORT/Steam/steamapps/appmanifest_4949.acf"

echo "== a fix's report: It Works… and Works Without the Fix…"
# Fake Fixed in a Steam Play prefix of its own, its fix installed: the catalog's DLL in Bin, beside the
# original it forwards to, a file of the same size that is not the catalog's, and the log the DLL writes.
# A NotProton runner carrying one D3DMetal, and the modules' log with a line for the game and one for another.
FX="$SUPPORT/Steam/steamapps/common/Fake Fixed"
mkdir -p "$FX/Bin" "$SUPPORT/Steam/steamapps/compatdata/5151/pfx"
touch "$FX/Bin/FakeFixed.exe" "$SUPPORT/Steam/steamapps/compatdata/5151/pfx/user.reg"
printf '"AppState"\n{\n\t"appid"\t\t"5151"\n\t"name"\t\t"Fake Fixed"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Fake Fixed"\n\t"buildid"\t\t"77"\n}\n' \
  > "$SUPPORT/Steam/steamapps/appmanifest_5151.acf"
cp "$SUPPORT/MacGameFix/catalog/current/fakefix.dll" "$FX/Bin/fake.dll"
printf 'MZ the game own library, b1\n' > "$FX/Bin/fake_real.dll"
printf 'MZ not the fix, build 1!\n' > "$FX/decoy.dll"
fixlog() { # fixlog <text before each number>: 250 lines, one naming the home folder and this Mac
  for n in $(seq 1 250); do
    if [ "$n" = 249 ]; then printf 'loaded from Z:%s/Library on %s\n' "$MACGAMEFIX_HOME" "$(printf '%s' "$HOST_NAME" | tr '[:lower:]' '[:upper:]')"
    else printf '%s %04d\n' "$1" "$n"; fi
  done > "$FX/Bin/fake-fix.log"
}
fixlog "fake fix line"
FR="$SUPPORT/notproton/runners/crossover-27.0.0.41069-fex/CrossOver"
mkdir -p "$FR/lib/wine/x86_64-unix" "$FR/etc" "$FR/lib/apple_gptk/external/D3DMetal.framework/Resources"
printf 'x wine-11.17-8909 x' > "$FR/lib/wine/x86_64-unix/ntdll.so"
printf '"BuildTag" = "cxpreview-20261006-rc2"\n' > "$FR/etc/CrossOver.conf"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 4.0b3' \
  "$FR/lib/apple_gptk/external/D3DMetal.framework/Resources/Info.plist" >/dev/null
export MACGAMEFIX_PAD_LOG="$T/pad-fix.log"
printf '10:00:00 [1] game=5151 observed: the game rumbles the DualSense%ss motors\n10:00:01 [2] game=999 observed: the game plays haptics\n' "'" \
  > "$MACGAMEFIX_PAD_LOG"
# The form's fields as GitHub reads them, and BAD for a field the form does not have, a dropdown value it does not
# offer, a field longer than an issue link carries (Report.longest), or a control character other than a line's end.
fixform() { # fixform <flag> <game>
  /usr/bin/python3 - "$("$BIN" "$1" "$2")" "$HERE/../.github/ISSUE_TEMPLATE" <<'PY5'
import re, sys, urllib.parse
fields = urllib.parse.parse_qsl(urllib.parse.urlsplit(sys.argv[1]).query)
form = dict(fields).get("template", "")
ids, options, cur, listing = set(), {}, None, False
for line in open(sys.argv[2] + "/" + form).read().split("\n") if form else []:
    m = re.match(r"^    id: (\S+)$", line)
    if m: cur = m.group(1); ids.add(cur)
    if re.match(r"^      options:$", line): options[cur] = []; listing = True; continue
    m = re.match(r"^        - (.+)$", line)
    if listing and m: options[cur].append(m.group(1)); continue
    listing = False
for k, v in fields:
    print(k + ": " + v.replace("\n", " | "))
    if k not in ids | {"template", "title"}: print("BAD field " + k)
    if k in options and v not in options[k]: print("BAD option " + k + ": " + v)
    if len(v.encode()) > 5000: print("BAD long " + k + ": " + str(len(v.encode())))
    if any(ord(c) < 32 and c not in "\t\n" for c in v): print("BAD control character in " + k)
PY5
}
# Everything under the home, by name, time and size: making a report or a form writes nothing there.
homestat() { find "$MACGAMEFIX_HOME" -exec stat -f '%N %m %z' {} + | sort; }
BEFORE="$(homestat)"
# A refusal exits 1, and what it says is what is checked: no call here stops the suite.
"$BIN" --fix-report "Fake Fixed" "$T/fix.md" works || true
FXR="$(cat "$T/fix.md" 2>/dev/null || true)"
check 'has "$FXR" "# MacGameFix fix report: Fake Fixed" && has "$FXR" "- Report: its fix works, played with the fix installed" && has "$FXR" "## What the game is made of" && ! has "$FXR" "What goes wrong"' "a fix report is the Report tab's report for the game, with no symptom"
check 'has "$FXR" "## The fix" && has "$FXR" "- State: Installed" && has "$FXR" "- Installer: install-fakedll.sh, of catalog 4000000002" && has "$FXR" "$(printf "\`\`\`\nlooking at ~/Library/Application Support/Steam/steamapps/common/Fake Fixed/Bin/fake.dll\ninstalled\n\`\`\`")" && has "$FXR" "- Steam'"'"'s build: 77"' "the fix's section: its state, its installer and catalog, the installer's whole --status, and Steam's build"
check '[ "$(wc -c < "$FX/decoy.dll")" = "$(wc -c < "$FX/Bin/fake.dll")" ] && has "$FXR" "- \`Bin/fake.dll\` is the catalog'"'"'s \`fakefix.dll\`" && ! has "$FXR" "decoy.dll" && ! has "$FXR" "fake_real.dll"' "the file that is the catalog's by its SHA-256, and not one of the same size that is not"
check 'has "$FXR" "- In: Steam Play prefix (5151)" && has "$FXR" "- NotProton runner · CrossOver Preview 20261006, build 27.0.0.41069: D3DMetal 4.0b3 (lib/apple_gptk)" && has "$FXR" "- Graphics backend: not read; the fix is made for D3DMetal" && has "$FXR" "- This Mac: " && has "$FXR" ", macOS "' "where it runs: the prefix, the runner with its D3DMetal, the backend the fix is made for, and this Mac"
check 'has "$FXR" "#### Bin/fake-fix.log, last written 20" && has "$FXR" "its last 200 of 250 lines" && has "$FXR" "fake fix line 0250" && ! has "$FXR" "fake fix line 0050"' "the fix's own log, with when it was written, its last 200 lines"
check 'has "$FXR" "game=5151 observed: the game rumbles" && ! has "$FXR" "game=999" && has "$FXR" "None. Settings › Log is kept in memory only"' "the modules' lines for the game alone, and Settings › Log said to have none"
check '! has "$FXR" "$MACGAMEFIX_HOME" && ! has "$FXR" "$HOST_NAME" && ! has "$FXR" "$(printf '"'"'%s'"'"' "$HOST_NAME" | tr "[:lower:]" "[:upper:]")" && has "$FXR" "loaded from Z:~/Library on <this Mac>"' "the report writes the home folder as ~ and leaves this Mac's name out"
OUT="$(fixform --fix-works-url "Fake Fixed")"
"$BIN" --works-without-url "Fake Fixed" >/dev/null 2>&1 || true
check '[ "$BEFORE" = "$(homestat)" ]' "making the report and the forms writes nothing under the home: not in the game folder, its prefix or MacGameFix's own"
check 'has "$OUT" "template: fix-works.yml" && has "$OUT" "title: [Works] Fake Fixed" && has "$OUT" "game: Fake Fixed (Steam app 5151)" && has "$OUT" "runs: A NotProton runner" && has "$OUT" "game-version: Steam build 77" && ! has "$OUT" "backend:"' "It Works… opens the form with the game, where it runs and the game's build, and leaves the backend, which is not read, to the player"
check 'has "$OUT" "versions: MacGameFix " && has "$OUT" ", catalog 4000000002; NotProton runner · CrossOver Preview 20261006 (27.0.0.41069, D3DMetal 4.0b3); macOS "' "and the versions: MacGameFix and its catalog, the runner and its D3DMetal, macOS"
check 'has "$OUT" "log: Bin/fake-fix.log, last written 20" && has "$OUT" " | fake fix line 0250 | " && ! has "$OUT" "fake fix line 0050" && has "$OUT" "Settings › Log: nothing this window ran for this game." && ! has "$OUT" "BAD" && ! has "$OUT" "$MACGAMEFIX_HOME" && ! has "$OUT" "$HOST_NAME"' "the fix's own log goes into the log field when it fits, and every field and option is the form's own"
# Settings › Log, which the window keeps in memory, from a file standing for it: the game's own block, and not another
# game's or the Wine modules', in the report and in the field.
SESSION="$T/session.log"
printf '\n▸ Fake Fixed — %s\n  installed fake.dll into %s/Bin\n\n▸ Fake Game — %s\n  another game%ss line\n\n▸ Wine modules — NotProton runner — %s\n  a modules line\n' \
  "$FX" "$FX" "$GAME" "'" "$FR" > "$SESSION"
MACGAMEFIX_SESSION_LOG="$SESSION" "$BIN" --fix-report "Fake Fixed" "$T/fix-session.md" works || true
FXS="$(cat "$T/fix-session.md" 2>/dev/null || true)"
OUT="$(MACGAMEFIX_SESSION_LOG="$SESSION" fixform --fix-works-url "Fake Fixed")"
FXDIR="~/Library/Application Support/Steam/steamapps/common/Fake Fixed"
check 'has "$FXS" "$(printf "### Settings › Log\n\n\`\`\`\n▸ Fake Fixed — %s\n  installed fake.dll into %s/Bin\n\`\`\`" "$FXDIR" "$FXDIR")" && ! has "$FXS" "another game" && ! has "$FXS" "a modules line"' "the report carries this window's Settings › Log block for the game, and not another game's or the Wine modules'"
check 'has "$OUT" " | fake fix line 0250 |  | ▸ Fake Fixed — $FXDIR |   installed fake.dll into $FXDIR/Bin" && ! has "$OUT" "another game" && ! has "$OUT" "a modules line" && ! has "$OUT" "BAD"' "and the log field, after the fix's own log, when both fit"
{ printf '▸ Fake Fixed — %s\n' "$FX"; for n in $(seq 1 40); do printf '  a line the installer wrote, number %04d, long enough to count\n' "$n"; done; } > "$SESSION"
MACGAMEFIX_SESSION_LOG="$SESSION" "$BIN" --fix-report "Fake Fixed" "$T/fix-session.md" works || true
OUT="$(MACGAMEFIX_SESSION_LOG="$SESSION" fixform --fix-works-url "Fake Fixed")"
check 'has "$OUT" " | fake fix line 0250 |  | Settings › Log'"'"'s lines for this game are in the attached report: more than this link carries." && ! has "$OUT" "number 0040" && ! has "$OUT" "BAD" && has "$(cat "$T/fix-session.md")" "  a line the installer wrote, number 0040"' "Settings › Log lines that do not fit beside the fix's own log are left to the report, and the field says so"
# An own log that fits the link alone, and not with the line that says Settings › Log has nothing: 4980 bytes in
# the field, its 53-byte heading, 200 lines of 23 and 24 characters and the line ends between them.
/usr/bin/python3 -c 'import sys; open(sys.argv[1], "w").write("".join(("edge line %04d" % n).ljust(24 if n > 122 else 23, ".") + "\n" for n in range(1, 251)))' "$FX/Bin/fake-fix.log"
OUT="$(fixform --fix-works-url "Fake Fixed")"
check 'has "$OUT" "log: The fix'"'"'s own log, fake-fix.log, is in the attached report: more than this link carries. |  | Settings › Log: nothing this window ran for this game." && ! has "$OUT" "Settings › Log'"'"'s lines" && ! has "$OUT" "BAD"' "with no Settings › Log lines, the field never says they are in the report, and stays within the link"
# A log that is there and cannot be read is said to be so, not missing.
chmod 000 "$FX/Bin/fake-fix.log"
"$BIN" --fix-report "Fake Fixed" "$T/fix-unread.md" works || true
OUT="$(fixform --fix-works-url "Fake Fixed")"
chmod 644 "$FX/Bin/fake-fix.log"
check 'has "$(cat "$T/fix-unread.md")" "Bin/fake-fix.log is there and could not be read (Permission denied)." && ! has "$(cat "$T/fix-unread.md")" "not in the game'"'"'s folder" && has "$OUT" "log: Bin/fake-fix.log is there and could not be read (Permission denied)."' "a log that cannot be read is said to be there and unreadable, in the report and the field"
# A log a fix let grow, with binary in it: only its end is read, a long line is cut, and no control character goes on.
/usr/bin/python3 -c 'import sys; open(sys.argv[1], "wb").write(b"x" * 290000 + b"\na line with a NUL \x00 and a \xff byte\n" + b"y" * 3000 + b"\nthe last line\n")' "$FX/Bin/fake-fix.log"
"$BIN" --fix-report "Fake Fixed" "$T/fix-big.md" works || true
BIG="$(cat "$T/fix-big.md" 2>/dev/null || true)"
OUT="$(fixform --fix-works-url "Fake Fixed")"
check '[ "$(wc -c < "$T/fix-big.md")" -lt 50000 ] && [ "$(tr -cd "\000" < "$T/fix-big.md" | wc -c | tr -d " ")" = 0 ] && has "$BIG" "lines, read from the end of its 293" && has "$BIG" "a line with a NUL � and a � byte" && has "$BIG" " [cut: 3000 characters]" && has "$BIG" "the last line" && ! has "$BIG" "xxxxxxxxxxxxxxxxxxxx"' "a large log is read from its end alone, its long line cut and its control characters replaced"
check 'has "$OUT" " | the last line |  | " && ! has "$OUT" "BAD"' "and the field carries no control character"
# A bottle whose Steam lists the game's library, named after another game: counted, never named, and it changes
# neither where the game runs nor the versions.
OB="$SUPPORT/CrossOver/Bottles/Other Title"
mkdir -p "$OB/drive_c/windows/system32" "$OB/drive_c/Program Files (x86)/Steam/config" "$OB/dosdevices"
touch "$OB/drive_c/windows/system32/dinput8.dll"
ln -s / "$OB/dosdevices/z:"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"Z:%s"\n\t}\n}\n' "$(printf '%s' "$SUPPORT/Steam" | sed 's#/#\\\\#g')" \
  > "$OB/drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf"
fixlog "fake fix line"
"$BIN" --fix-report "Fake Fixed" "$T/fix-bottle.md" works || true
FXB="$(cat "$T/fix-bottle.md" 2>/dev/null || true)"
OUT="$(fixform --fix-works-url "Fake Fixed")"
check 'has "$FXB" "- Runs in: a Steam Play prefix (~/Library/Application Support/Steam/steamapps/compatdata/5151/pfx); another CrossOver bottle whose Steam lists its library, not named here" && has "$FXB" "- In: Steam Play prefix (5151), another CrossOver bottle whose Steam lists its library, not named here" && ! has "$FXB" "Other Title"' "a bottle whose Steam lists the game's library, and holds another game, is counted in the report and not named"
check '! has "$OUT" "Other Title" && has "$OUT" "runs: A NotProton runner" && has "$OUT" ", catalog 4000000002; NotProton runner · CrossOver Preview 20261006 (27.0.0.41069, D3DMetal 4.0b3); macOS "' "and it changes neither where the form says the game runs nor the versions"
rm -rf "$OB"
fixlog "a fix log line long enough that two hundred of them are more than an issue link carries"
OUT="$(fixform --fix-works-url "Fake Fixed")"
check 'has "$OUT" "log: The fix'"'"'s own log, fake-fix.log, is in the attached report: more than this link carries." && ! has "$OUT" "long enough"' "a log too long for the link is left to the report, and the field says so"
check 'has "$("$BIN" --works-without-url "Fake Fixed" 2>&1)" "Fake Fixed: Installed; Works Without the Fix… needs Not installed" && ! "$BIN" --works-without-url "Fake Fixed" >/dev/null 2>&1' "Works Without the Fix… is refused while the fix is installed"
rm "$FX/Bin/fake.dll"
OUT="$(fixform --works-without-url "Fake Fixed")"
check 'has "$OUT" "template: works-without-fix.yml" && has "$OUT" "title: [No longer needed] Fake Fixed" && has "$OUT" "game: Fake Fixed (Steam app 5151)" && has "$OUT" "toolkit: 4.0b3" && has "$OUT" "versions: MacGameFix " && [ "$(printf "%s\n" "$OUT" | cut -d: -f1 | tr "\n" " ")" = "template title game toolkit versions " ]' "with the fix removed, Works Without the Fix… opens its form with the game, the one D3DMetal there and the versions, and nothing else"
check 'has "$("$BIN" --fix-works-url "Fake Fixed" 2>&1)" "Fake Fixed: Not installed; It Works… needs Installed" && ! "$BIN" --fix-report "Fake Fixed" "$T/refused.md" >/dev/null 2>&1 && [ ! -e "$T/refused.md" ]' "and It Works… is refused, its report not written"
"$BIN" --fix-report "Fake Fixed" "$T/fix-without.md" without || true
check 'has "$(cat "$T/fix-without.md")" "- Report: it works without its fix, played with the fix removed" && has "$(cat "$T/fix-without.md")" "- State: Not installed" && has "$(cat "$T/fix-without.md")" "Written while the fix was in place: it is not installed now."' "the report without the fix says so, and that its log was written while the fix was in place"
rm "$FX/Bin/fake-fix.log"
"$BIN" --fix-report "Fake Fixed" "$T/fix-nolog.md" without || true
check 'has "$(cat "$T/fix-nolog.md")" "fake-fix.log: not in the game'"'"'s folder. The fix writes it beside its DLL while the game runs."' "a log the fix writes and is not there is said to be missing"
"$BIN" --fix-report "Fake Game" "$T/fix-game.md" || true
OUT="$(fixform --fix-works-url "Fake Game")"
check 'has "$(cat "$T/fix-game.md")" "The fix writes no log of its own beside its DLL." && has "$OUT" "log: The fix writes no log of its own. | " && ! has "$OUT" "backend:" && ! has "$OUT" "runs:" && ! has "$OUT" "BAD"' "a fix that writes no log says so, in the report and the form, and where it runs and the backend are left to the player"
# A macOS game, its fix in place: no Wine runs it, so where it runs and the backend are read from the folder.
mkdir -p "$FN/FakeNative.app/Contents/MacOS"; touch "$FN/FakeNative.app/Contents/MacOS/FakeNative" "$FN/fixed.marker"
native 1
OUT="$(fixform --fix-works-url "Fake Native")"
check 'has "$OUT" "runs: Native macOS (no Wine)" && has "$OUT" "backend: None (a macOS game)" && ! has "$OUT" "BAD"' "a macOS game's form says it runs natively, with no graphics backend"
unset MACGAMEFIX_PAD_LOG
rm -rf "$FX" "$FN" "$SUPPORT/Steam/steamapps/compatdata/5151" "$SUPPORT/Steam/steamapps/appmanifest_5151.acf" \
  "$SUPPORT/Steam/steamapps/appmanifest_4545.acf" "$SUPPORT/notproton"

echo "== new fixes, asked first"
# A newer release of the same fake catalog, and the agent pointed at it.
cp -R "$RES" "$T/res2"
/usr/bin/python3 - "$T/res2/catalog.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["version"] = 4000000005
# What the catalog says it brings, a line for each thing.
d["notes"] = "Fake Game runs its movies. And more words about it.\nA second thing"
json.dump(d, open(sys.argv[1], "w"))
PY
"$BIN" --make-catalog "$T/release2" --key "$T/test.key" --from "$T/res2" >/dev/null
check '/usr/bin/grep -q "Fake Game runs its movies" "$T/release2/catalog.json"' "a release's catalog carries what it brings, under its signature"
due() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lastUpdateCheck"] = -1e9; json.dump(d, open(sys.argv[1], "w"))
PY
}
waiting() { /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("available", 0))' "$SUPPORT/MacGameFix/agent-state.json"; }
newagent() { MACGAMEFIX_CATALOG_SOURCE="$T/release2" MACGAMEFIX_CATALOG_PUBKEY="$PUB" "$BIN" --agent-once 2>&1; }
before="$(readlink "$SUPPORT/MacGameFix/catalog/current")"
printf '{"kept":[],"updates":true,"askFirst":true}' > "$SUPPORT/MacGameFix/automatic.json"; due
check 'out="$(newagent)"; has "$out" "New fixes are ready (catalog 4000000005)" && has "$out" "Fake Game runs its movies. A second thing." && [ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ] && [ "$(waiting)" = 4000000005 ]' "asked first, a newer catalog is offered and nothing is installed"
check 'out="$("$BIN" --updates-report 2>&1)"; has "$out" "fixes | catalog $before, of " && has "$out" "notice | An update is available: new fixes." && has "$out" "button | Update" && ! has "$out" "Relaunch"' "the notice offers the new fixes with Update, and there is no Relaunch for a catalog"
due
check '! has "$(newagent)" "New fixes are ready" && [ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ]' "and offered once"
printf '{"kept":[],"updates":false,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"; due
newagent >/dev/null
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ]' "with updates off, the agent takes nothing"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"; due
out="$(newagent)"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000005 ] && [ "$(waiting)" = 0 ]' "automatic, it is installed and no longer waiting"
check 'has "$out" "The fixes were updated. Fake Game runs its movies. A second thing."' "and the agent says what it brings"

echo "== what Settings › Updates says"
# --updates-report prints the section's lines and the notice's, from the words the window uses.
upd() { "$BIN" --updates-report "$@" 2>&1 || true; }
every() { printf '{"kept":[],"updates":%s,"askFirst":false,"updateMinutes":%s}' "$1" "$2" > "$SUPPORT/MacGameFix/automatic.json"; upd; }
out="$(upd)"
check 'has "$out" "app | MacGameFix $APPV" && has "$out" "fixes | catalog 4000000005, of " && has "$out" "modules | catalog "' "the app's version and each catalog in use, by its number and its day"
check 'has "$out" "looks | every hour" && has "$out" "notice | none"' "updates are looked for every hour, and with nothing waiting there is no notice"
check 'has "$(every true 10)" "looks | every 10 minutes" && has "$(every true 1440)" "looks | once a day" && has "$(every true 120)" "looks | every 2 hours"' "another interval in the settings file is said as it is"
check 'has "$(every true 1)" "looks | every 10 minutes" && has "$(every false 60)" "looks | never"' "nothing under ten minutes, and never with updates off"
# When anything new was last looked for: the latest of the three questions, whoever asked.
looked() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" "$@" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for key, value in zip(("lastUpdateCheck", "lastModulesCheck", "lastAppCheck"), sys.argv[2:]): d[key] = float(value)
json.dump(d, open(sys.argv[1], "w"))
PY
}
cp "$SUPPORT/MacGameFix/agent-state.json" "$T/state.before-looked"
# Dates in the state file count from 2001: -1e9 is before any look, and 5e8 and 6e8 are days in 2016 and 2020.
looked -1e9 -1e9 -1e9
check 'has "$(upd)" "looked | Not yet"' "before the first look, Settings says it has not looked yet"
looked 5e8 -1e9 6e8
check 'out="$(upd)"; has "$out" "looked | " && has "$out" "2020" && ! has "$out" "2016" && ! has "$out" "Not yet"' "after it, the day and time of the latest of the three questions"
cp "$T/state.before-looked" "$SUPPORT/MacGameFix/agent-state.json"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"

echo "== the Wine modules, on their own"
# A Wine modules' catalog of fake modules for build 27.0.0.41069, signed with the test key.
RESM="$T/resm"; mkdir -p "$RESM"
cp "$HERE/MacGameFix.app/Contents/Resources/engine-modules.sh" "$RESM/"
MODS="x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so"
for f in $MODS; do echo "module $f" > "$RESM/engine-27.0.0.41069-$(printf '%s' "$f" | tr / -)"; done
/usr/bin/python3 - "$RESM" <<'PY'
import hashlib, json, os, sys
res = sys.argv[1]
mods = sorted(n for n in os.listdir(res) if n.startswith("engine-27"))
files = {n[len("engine-27.0.0.41069-"):].replace("-windows-", "-windows/").replace("-unix-", "-unix/"):
         hashlib.sha256(open(os.path.join(res, n), "rb").read()).hexdigest() for n in mods}
json.dump({"builds": [{"build": "27.0.0.41069", "crossover": "Test", "wine": "11.17", "files": files}]},
          open(os.path.join(res, "engine-modules.json"), "w"))
names = mods + ["engine-modules.sh", "engine-modules.json"]
json.dump({"version": 4000000010, "minimumApp": "1.5.0",
           "files": {n: hashlib.sha256(open(os.path.join(res, n), "rb").read()).hexdigest() for n in names}},
          open(os.path.join(res, "modules.json"), "w"))
PY
"$BIN" --make-catalog "$T/mrelease" --key "$T/test.key" --from "$RESM" >/dev/null
cp "$T/release2/"catalog.* "$T/mrelease/"
modagent() { MACGAMEFIX_CATALOG_SOURCE="$T/mrelease" MACGAMEFIX_CATALOG_PUBKEY="$PUB" "$BIN" --agent-once 2>&1; }
mdue() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lastModulesCheck"] = -1e9; d["lastUpdateCheck"] = 1e10; json.dump(d, open(sys.argv[1], "w"))
PY
}
runner() { # a fake runner with CodeWeavers' files: <folder name> <Preview date>
  local r="$SUPPORT/notproton/runners/$1/CrossOver"
  mkdir -p "$r/lib/wine/x86_64-unix" "$r/lib/wine/x86_64-windows" "$r/etc"
  printf '"BuildTag" = "cxpreview-%s-rc1"\n' "$2" > "$r/etc/CrossOver.conf"
  printf 'x wine-11.17-8909 x' > "$r/lib/wine/x86_64-unix/ntdll.so"
  for f in $MODS; do echo "CodeWeavers' $f" > "$r/lib/wine/$f"; done
  printf '%s' "$r"
}
ours() { [ "$(cat "$1/lib/wine/x86_64-windows/winebus.sys")" = "module x86_64-windows/winebus.sys" ]; }
settings() { # modulesAskFirst, kept list, declined list (JSON)
  printf '{"kept":[],"updates":false,"modulesUpdates":true,"modulesAskFirst":%s,"modulesKept":%s,"modulesDeclined":%s}' "$1" "$2" "$3" \
    > "$SUPPORT/MacGameFix/automatic.json"
}
R1="$(runner crossover-27.0.0.41069-fex 20261006)"
settings false "[\"$R1\"]" "[]"; mdue
OUT="$(modagent)"
check '[ "$(readlink "$SUPPORT/MacGameFix/modules/current")" = 4000000010 ] && has "$OUT" "DualSense controllers put back in NotProton runner · CrossOver Preview 20261006" && ours "$R1"' "automatic: the modules' own catalog is taken, and the modules go back into a runner they were kept in"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000005 ]' "without touching the fixes' catalog"
for f in $MODS; do echo "CodeWeavers' updated $f" > "$R1/lib/wine/$f"; done
check 'has "$(modagent)" "put back in" && ours "$R1"' "after a CrossOver update they are put back"
R2="$(runner crossover-27.0.0.41069 20261007)"
check 'has "$(modagent)" "installed in the new NotProton runner · CrossOver Preview 20261007" && ours "$R2"' "a runner for a new CrossOver build gets them, since a runner has them"
RV="$(runner 'crossover-27.0.0.41069-fex+mgf-test-window@0123456789ab' 20261006)"
OUT="$(modagent)"
check '! ours "$RV" && ! has "$OUT" "mgf-test-window" && ! has "$("$BIN" --engine-report 2>&1)" "mgf-test-window"' "a NotProton runner variant (a copy NotProton remakes) is neither listed nor given the modules"
rm -rf "$SUPPORT/notproton/runners/crossover-27.0.0.41069-fex+mgf-test-window@0123456789ab"
printf '{"kept":[],"updates":false,"modulesUpdates":true,"modulesAskFirst":false,"modulesKept":["%s"],"modulesDeclined":[],"modulesNewBuilds":false}' "$R1" \
  > "$SUPPORT/MacGameFix/automatic.json"
R3="$(runner crossover-27.0.0.41069-other 20261008)"
modagent >/dev/null
check '! ours "$R3"' "unless new CrossOver builds are turned off"
rm -rf "$SUPPORT/notproton/runners/crossover-27.0.0.41069-other"
settings false "[\"$R1\"]" "[\"$R2\"]"
for f in $MODS; do echo "CodeWeavers' $f" > "$R2/lib/wine/$f"; done
modagent >/dev/null
check '! ours "$R2"' "a runner the user took them out of is left alone"
APPDIR="$MACGAMEFIX_HOME/Applications/CrossOver Test.app"
mkdir -p "$APPDIR/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix" "$APPDIR/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 27.0.0.41069' "$APPDIR/Contents/Info.plist" >/dev/null
printf 'x wine-11.17-8909 x' > "$APPDIR/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so"
for f in $MODS; do echo "CodeWeavers' $f" > "$APPDIR/Contents/SharedSupport/CrossOver/lib/wine/$f"; done
settings false "[\"$R1\", \"$APPDIR/Contents/SharedSupport/CrossOver\"]" "[]"
OUT="$(modagent)"
check 'has "$OUT" "needs the DualSense controllers improvement again" && ! ours "$APPDIR/Contents/SharedSupport/CrossOver"' "a CrossOver app is only reported, even on automatic"
for f in $MODS; do echo "CodeWeavers' $f" > "$R1/lib/wine/$f"; done
settings true "[\"$R1\"]" "[]"
OUT="$(modagent)"
check 'has "$OUT" "needs the DualSense controllers improvement again" && ! ours "$R1"' "asked first, a runner is reported and left as it is"
settings false "[\"$R1\"]" "[]"
printf '{"kept":[],"updates":false,"modulesUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"
modagent >/dev/null
check '! ours "$R1"' "with the Wine modules off, nothing is done"

echo "== the games on this Mac that new fixes touch"
# The next catalog carries build 3 of the fake fix and a first fix for a game that is on this
# Mac, Fake New; Fake Game has build 2 in its folder and is not marked Keep.
mkdir -p "$T/res3"; cp "$T/res2"/* "$T/res3/"
sed -i '' -e 's/Build 2 of the fake fix/Build 3 of the fake fix/' -e 's/= 2 \]; then echo installed/= 3 ]; then echo installed/' \
  -e 's/^echo 2 > /echo 3 > /' "$T/res3/install-fake.sh"
/usr/bin/python3 - "$T/res3" <<'PY'
import hashlib, json, pathlib, sys
res = pathlib.Path(sys.argv[1])
table = json.load(open(res / "games.json"))
new = dict(table["games"][0]); new.update(name="Fake New", exe="FakeNew.exe")
table["games"].append(new)
json.dump(table, open(res / "games.json", "w"))
d = json.load(open(res / "catalog.json")); d["version"] = 4000000007; d["notes"] = "Fake Game's fix, build 3"
d["files"] = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in d["files"]}
json.dump(d, open(res / "catalog.json", "w"))
PY
"$BIN" --make-catalog "$T/release3" --key "$T/test.key" --from "$T/res3" >/dev/null
NEWGAME="$SUPPORT/Steam/steamapps/common/Fake New"
mkdir -p "$NEWGAME"; touch "$NEWGAME/FakeNew.exe"
echo 2 > "$GAME/fixed.marker"; steam 7 4
thirdagent() { MACGAMEFIX_CATALOG_SOURCE="$T/release3" MACGAMEFIX_CATALOG_PUBKEY="$PUB" "$BIN" --agent-once 2>&1; }
learned() { /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("gamesCatalog", 0), len(d.get("fixesKnown") or []))' "$SUPPORT/MacGameFix/agent-state.json"; }
check '[ "$(learned)" = "4000000005 6" ]' "the agent has learned the fixes of the catalog in use, and said nothing of them"
printf '{"kept":[],"updates":true,"askFirst":true}' > "$SUPPORT/MacGameFix/automatic.json"; due
out="$(thirdagent)"
check 'has "$out" "New fixes are ready (catalog 4000000007)" && ! has "$out" "A newer fix is ready" && ! has "$out" "now has a fix"' "asked first, the catalog that waits is not looked into: no game is named yet"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"; due
out="$(thirdagent)"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000007 ] && has "$out" "ok : A newer fix is ready for: Fake Game. Install it from MacGameFix'"'"'s Games tab; a game marked Keep gets it by itself."' "once the catalog is taken, a game here whose fix has a newer build is named"
check 'has "$out" "ok : MacGameFix now has a fix for: Fake New, on this Mac."' "and so is a game here that got its first fix"
check '[ "$(cat "$GAME/fixed.marker")" = 2 ] && [ ! -e "$NEWGAME/fixed.marker" ]' "nothing is installed in a game that is not marked Keep"
check 'has "$(menu)" "news | yes"' "and the menu bar shows its dot"
check 'has "$("$BIN" --updates-report 2>&1)" "games | A newer fix is ready for: Fake Game."' "the window's second notice names the game"
due
check '[ -z "$(thirdagent)" ]' "said once for a catalog"
# A fix being tested is named only while the testing switch is on: Fake Trial is the same folder's.
printf '{"kept":[],"updates":false,"testingFixes":true}' > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$("$BIN" --updates-report 2>&1)" "games | A newer fix is ready for: Fake Game, Fake Trial."' "with the testing switch on, a fix being tested that is behind is named too"
printf '{"kept":[],"updates":false,"testingFixes":false}' > "$SUPPORT/MacGameFix/automatic.json"
check 'out="$("$BIN" --updates-report 2>&1)"; has "$out" "games | A newer fix is ready for: Fake Game." && ! has "$out" "Fake Trial"' "and with it off again, it is not"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"
echo 3 > "$GAME/fixed.marker"
check 'has "$("$BIN" --updates-report 2>&1)" "games | none"' "with the newer build installed, the window's notice is gone"
# The same catalog arriving for a game marked Keep: the agent installs the newer build and says that alone.
/usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["gamesCatalog"] = 4000000005; json.dump(d, open(sys.argv[1], "w"))
PY
echo 2 > "$GAME/fixed.marker"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":true,"askFirst":false}' "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
out="$(thirdagent)"
check 'has "$out" "ok Fake Game: The fix is updated to the newer build." && ! has "$out" "A newer fix is ready" && [ "$(cat "$GAME/fixed.marker")" = 3 ]' "a game marked Keep gets the newer build by itself, and is not named as waiting"
# A MacGameFix that has never looked: it learns what is there and says nothing.
/usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("gamesCatalog", None); d.pop("fixesKnown", None); json.dump(d, open(sys.argv[1], "w"))
PY
echo 2 > "$GAME/fixed.marker"
printf '{"kept":[],"updates":false}' > "$SUPPORT/MacGameFix/automatic.json"
check '[ -z "$(thirdagent)" ] && [ "$(learned)" = "4000000007 7" ]' "the first look only learns: a fix that was already behind is not announced"
echo 3 > "$GAME/fixed.marker"; rm -rf "$NEWGAME"

echo "== each game's compiled shaders, kept whole"
# Metal's cache of one NotProton game: four files a process takes one of, with a list beside each.
# Here one is full, two hold less and one is missing; and CrossOver's own folder, which every bottle
# game shares, with files that differ.
export MACGAMEFIX_CACHE_DIR="$T/cache"
MC="$MACGAMEFIX_CACHE_DIR/com.notproton.launcher.4242/com.apple.metal/16777235_467"
CXC="$MACGAMEFIX_CACHE_DIR/com.codeweavers.CrossOver.wineloader/com.apple.metal/16777235_467"
mkdir -p "$MC" "$CXC"
fill() { /usr/bin/python3 -c 'import sys; open(sys.argv[1], "w").write(sys.argv[2] * int(sys.argv[3]))' "$1" "$2" "$3"; }
fill "$MC/functions.data" a 10; fill "$MC/functions.list" a 4
fill "$MC/functions1.data" full 200; fill "$MC/functions1.list" full 20
fill "$MC/functions2.data" b 100; fill "$MC/functions2.list" b 8
# A fifth, as Metal makes when five processes use the bundle at once (Phantom Blade Zero's).
fill "$MC/functions4.data" c 20; fill "$MC/functions4.list" c 2
fill "$CXC/functions.data" one 50; fill "$CXC/functions.list" one 5
fill "$CXC/functions1.data" other 500; fill "$CXC/functions1.list" other 9
cp "$MC/functions1.data" "$T/full.data"; cp "$MC/functions1.list" "$T/full.list"
shaders() { "$BIN" --shader-cache-keep 2>&1; }
allfull() { for n in functions functions1 functions2 functions3 functions4; do cmp -s "$MC/$n.data" "$T/full.data" && cmp -s "$MC/$n.list" "$T/full.list" || return 1; done; }
out="$(shaders)"
check 'has "$out" "com.notproton.launcher.4242: the fullest shader cache copied over 4 others" && allfull' "the fullest of a game's cache files is copied over the others, a fifth one too, lists and all"
check 'has "$out" "1 game with compiled shaders, 1 kept whole"' "and the game counts as whole"
check 'out="$(shaders)"; ! has "$out" "copied" && allfull' "four files that are the same are left alone"
check '[ "$(cat "$CXC/functions.data")" != "$(cat "$CXC/functions1.data")" ] && [ ! -e "$CXC/functions2.data" ]' "CrossOver's own folder, which every bottle game shares, is not touched"
# The game ran and added to the file it took: that one is the fullest now. While a process still holds
# any of the four, nothing is copied.
fill "$MC/functions2.data" fullmore 300; fill "$MC/functions2.list" fullmore 30
cp "$MC/functions2.data" "$T/full.data"; cp "$MC/functions2.list" "$T/full.list"
# perl, not python3: /usr/bin/python3 is a launcher, and killing it can leave the python it started holding the lock.
/usr/bin/perl -e 'use Fcntl ":flock"; $| = 1; open(my $f, "<", $ARGV[0]) or die; flock($f, LOCK_EX) or die; print "held\n"; sleep 60' "$MC/functions3.data" > "$T/held" &
HOLD_PID=$!
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/held" ] && break; /usr/bin/python3 -c 'import time; time.sleep(0.2)'; done
check 'out="$(shaders)"; ! has "$out" "copied" && ! allfull' "while a process holds one of the four, nothing is copied"
kill "$HOLD_PID" 2>/dev/null; wait "$HOLD_PID" 2>/dev/null || true
agent >/dev/null || true
check 'allfull' "once it is free, the agent's next look copies the fullest over the others"
fill "$MC/functions.data" fullest 400; fill "$MC/functions.list" fullest 40
printf '{"kept":[],"updates":false,"shaderCache":false}' > "$SUPPORT/MacGameFix/automatic.json"
agent >/dev/null || true
check '[ "$(cat "$MC/functions.data")" != "$(cat "$MC/functions1.data")" ]' "with the option off, the agent leaves the files as they are"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"

echo "== The App Management notice"
check '[ "$("$BIN" --blocked-names "" "CrossOver A;CrossOver A;CrossOver B;CrossOver B" "CrossOver A;CrossOver A;CrossOver B;CrossOver B")" = "CrossOver A;CrossOver B" ]' "a CrossOver refused for two improvements is named once"
check '[ "$("$BIN" --blocked-names "CrossOver A;CrossOver C" "CrossOver A;CrossOver B" "CrossOver B")" = "CrossOver C;CrossOver B" ]' "one allowed now leaves the notice, one not looked at stays"

echo "== Fans at full speed for the games that ask"
FH="$HERE/MacGameFix.app/Contents/Resources/fans/io.github.macgamefix.fans"
FR="$T/fansroot"; mkdir -p "$FR/Library/PrivilegedHelperTools" "$FR/Library/LaunchDaemons" "$SUPPORT/notproton/plugins"
export MACGAMEFIX_FANS_PREFIX="$FR"
check '[ -x "$FH" ] && [ "$("$BIN" --fans-state)" = absent ]' "the app carries the helper, and nothing is installed before"
"$BIN" --fans-install >/dev/null 2>&1
check 'cmp -s "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans" "$FH" && plutil -lint "$FR/Library/LaunchDaemons/io.github.macgamefix.fans.plist" >/dev/null && [ "$("$BIN" --fans-state)" = installed ]' "installing puts the helper and its LaunchDaemon in place"
check 'has "$(cat "$SUPPORT/notproton/plugins/mgf-fans.conf")" "[NOTPROTON_MGF_FANS]" && has "$(cat "$SUPPORT/notproton/plugins/mgf-fans.conf")" "on = 1" && ! has "$(cat "$SUPPORT/notproton/plugins/mgf-fans.conf")" "[MGF_FANS]"' "and the row for NotProton's panel, with an id NotProton takes (NOTPROTON_)"
printf '#!/bin/sh\necho 0\n' > "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans"
check '[ "$("$BIN" --fans-state)" = outdated ]' "a helper of an older version reads as outdated"
printf '#!/bin/sh\necho this needs root >&2; exit 1\n' > "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans"
check '[ "$("$BIN" --fans-state)" = outdated ]' "and so does one from before it said its version"
printf '#!/bin/sh\n# another build of the same helper\n"%s" "$@"\n' "$FH" > "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans"
check '[ "$("$BIN" --fans-state)" = installed ] && ! cmp -s "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans" "$FH"' "another build of the same version is not asked to be replaced"
"$BIN" --fans-install >/dev/null 2>&1
FG="$T/Fans Library/steamapps/common/FanGame"
NL="$T/np.log"
printf '2026-11-14 10:00:00 [notproton] info [launch] handed to /bin/sh -c: MGF_FANS=max D3DM_MAX_FPS=60 %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/a.exe'" > "$NL"
printf '2026-11-14 10:05:00 [notproton] info [launch] handed to /bin/sh -c: XMGF_FANS=max MGF_FANS=maximum %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/b.exe'" >> "$NL"
check '[ "$("$FH" --asked "$NL" "$FG/a.exe")" = yes ] && [ "$("$FH" --asked "$NL" "$FG/b.exe")" = no ] && [ "$("$FH" --asked "$NL" "$FG/c.exe")" = no ]' "a NotProton game asks with MGF_FANS=max in its launch options, as a word of its own"
printf '2026-11-14 10:09:00 [notproton] info [launch] handed to /bin/sh -c: D3DM_MAX_FPS=60 %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/a.exe'" >> "$NL"
check '[ "$("$FH" --asked "$NL" "$FG/a.exe")" = no ]' "its last launch decides"
printf '2026-11-23 10:00:00 [notproton] info [launch] handed to /bin/sh -c: NOTPROTON_MGF_FANS=1 %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/d.exe'" >> "$NL"
printf '2026-11-23 10:01:00 [notproton] info [launch] handed to /bin/sh -c: NOTPROTON_MGF_FANS=0 XNOTPROTON_MGF_FANS=1 %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/e.exe'" >> "$NL"
printf '2026-11-23 10:02:00 [notproton] info [launch] handed to /bin/sh -c: XMGF_FANS=max MGF_FANS=max %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/f.exe'" >> "$NL"
check '[ "$("$FH" --asked "$NL" "$FG/d.exe")" = yes ] && [ "$("$FH" --asked "$NL" "$FG/e.exe")" = no ] && [ "$("$FH" --asked "$NL" "$FG/f.exe")" = yes ]' "the panel row's NOTPROTON_MGF_FANS=1 asks too, as a word of its own, and a word anywhere on the line counts"
check '[ "$("$FH" --version)" -ge 2 ]' "a helper that reads the panel row says version 2, so an installed older one is offered the update"
# A launch option with a script of its own before %command%: Steam's command names the game, the
# script has the tool run cmd.exe, and the helper sees only the latter. The line is found by its time.
printf '2026-11-23 20:41:01 [notproton] info [launch] handed to /bin/sh -c: "/w/play.sh" %s/run waitforexitandrun %s\n' "'/tool'" "'steam2ea://launchgame/1?a=b&c=d'" >> "$NL"
printf '2026-11-23 20:56:05 [notproton] info [launch] handed to /bin/sh -c: NOTPROTON_MGF_FANS=1 "/w/play.sh" %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/g.exe'" >> "$NL"
check '[ "$("$FH" --asked "$NL" cmd.exe)" = no ] && [ "$("$FH" --asked "$NL" cmd.exe "2026-11-23 20:56:05")" = yes ] && [ "$("$FH" --asked "$NL" cmd.exe "2026-11-23 20:56:07")" = yes ]' "a game started through a launch option's own script asks too: its line is the one written when the script started"
check '[ "$("$FH" --asked "$NL" cmd.exe "2026-11-23 20:41:01")" = no ] && [ "$("$FH" --asked "$NL" cmd.exe "2026-11-23 20:41:30")" = no ]' "and one started that way without the variable does not, whatever a later launch asks"
printf '2026-11-23 21:10:00 [notproton] info [launch] handed to /bin/sh -c: MGF_FANS=max NOTE=cmd.exe %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/h.exe'" >> "$NL"
printf '2026-11-23 21:20:00 [notproton] info [launch] handed to /bin/sh -c: "/w/play.sh" %s/run waitforexitandrun %s\n' "'/tool'" "'$FG/i.exe'" >> "$NL"
check '[ "$("$FH" --asked "$NL" cmd.exe)" = yes ] && [ "$("$FH" --asked "$NL" cmd.exe "2026-11-23 21:20:01")" = no ]' "the line of its own time decides over an earlier one that happens to name the program"
check '[ "$("$FH" --asked "$NL" "$FG/d.exe" "2026-11-23 23:00:00")" = yes ] && [ "$("$FH" --asked "$NL" "$FG/e.exe" "2026-11-23 23:00:00")" = no ]' "with no line near the start, the last line naming the program decides, as before"
check '! "$FH" --asked "$NL" cmd.exe "yesterday" >/dev/null 2>&1 && [ "$("$FH" --version)" -ge 3 ]' "a start that is no time is refused, and this helper says version 3"
printf '[MGF_FANS]\nlabel = Fans at full speed\non = max\n' > "$SUPPORT/notproton/plugins/mgf-fans.conf"
check '[ "$("$BIN" --fans-row-keep)" = "fans row: written" ] && has "$(cat "$SUPPORT/notproton/plugins/mgf-fans.conf")" "[NOTPROTON_MGF_FANS]" && [ "$("$BIN" --fans-row-keep)" = "fans row: nothing to do" ]' "the row an earlier MacGameFix wrote is rewritten once while the helper is in place"
"$BIN" --fans-remove >/dev/null 2>&1
check '[ ! -e "$FR/Library/PrivilegedHelperTools/io.github.macgamefix.fans" ] && [ ! -e "$FR/Library/LaunchDaemons/io.github.macgamefix.fans.plist" ] && [ ! -e "$SUPPORT/notproton/plugins/mgf-fans.conf" ] && [ "$("$BIN" --fans-state)" = absent ]' "removing takes the helper, its LaunchDaemon and the row away"
unset MACGAMEFIX_FANS_PREFIX

echo "== A program run in a game's NotProton prefix"
PL="$T/prefixlib/steamapps"; PAPP=4242; PROOT="$PL/compatdata/$PAPP"; PPFX="$PROOT/pfx"
mkdir -p "$PPFX/drive_c/windows/system32" "$PL/common/ModGame/Mods"
# A PE ntdll.dll of the machine given (8664 x86_64, aa64 arm64): MZ, e_lfanew = 0x40, PE\0\0 and the machine.
mkpe() { { printf 'MZ'; head -c 58 /dev/zero; printf '\x40\x00\x00\x00PE\x00\x00'; printf "\\x${1#??}\\x${1%??}"; } > "$2"; }
mkpe 8664 "$PPFX/drive_c/windows/system32/ntdll.dll"
PSTEAM="$MACGAMEFIX_HOME/Library/Application Support/Steam"
mkdir -p "$PSTEAM/config"
PRUN="$SUPPORT/notproton/runners"
PREC="$T/prefix-ran.txt"
# A runner whose loader only writes down what it was given, for each flavour.
mkrunner() {
  local cx="$PRUN/crossover-$1/CrossOver"
  mkdir -p "$cx/bin" "$cx/lib/wine/x86_64-unix" "$cx/lib/wine/aarch64-unix/wine.app/Contents/MacOS"
  for l in "$cx/lib/wine/x86_64-unix/wine" "$cx/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine"; do
    printf '#!/bin/sh\nprintf "%%s\\n" "loader=$0" "pwd=$(pwd -P)" "args=$*" "WINEPREFIX=$WINEPREFIX" "WINESERVER=$WINESERVER" "WINEMSYNC=$WINEMSYNC" "CX_ROOT=$CX_ROOT" > "%s"\n' "$PREC" > "$l"
    chmod +x "$l"
  done
  printf '#!/bin/sh\n' > "$cx/bin/wineserver"; printf '#!/bin/sh\n' > "$cx/bin/wineserver-arm64"
  chmod +x "$cx/bin/wineserver" "$cx/bin/wineserver-arm64"
}
mkrunner 26.3.0.39832; mkrunner 27.0.0.41303-fex
mktool() { mkdir -p "$PSTEAM/compatibilitytools.d/$1"; printf '%s\n' "$2" > "$PSTEAM/compatibilitytools.d/$1/build"; printf '%s\n' "$3" > "$PSTEAM/compatibilitytools.d/$1/flavor"; }
mktool notproton-26.3 26.3.0.39832 rosetta; mktool notproton-fex-41303 27.0.0.41303-fex fex
mkmap() { printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n%s\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' "$1" > "$PSTEAM/config/config.vdf"; }
maprow() { printf '\t\t\t\t\t"%s"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}\n' "$1" "$2"; }
PEXE="$PL/common/ModGame/Mods/Mod Setup.exe"; printf 'MZ' > "$PEXE"
waitrec() { for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$PREC" ] && return 0; sleep 0.25; done; return 1; }

mkmap "$(maprow 0 notproton-26.3; maprow $PAPP notproton-fex-41303)"
check 'has "$("$BIN" --prefix-target "$PPFX")" "27.0.0.41303-fex | fex | $PRUN/crossover-27.0.0.41303-fex/CrossOver/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine | $PRUN/crossover-27.0.0.41303-fex/CrossOver/bin/wineserver-arm64 | notproton-fex-41303"' "the game's own Steam tool names the runner and the flavour: FEX's loader and wineserver"
mkmap "$(maprow 0 notproton-26.3)"
check 'has "$("$BIN" --prefix-target "$PPFX")" "26.3.0.39832 | rosetta | $PRUN/crossover-26.3.0.39832/CrossOver/lib/wine/x86_64-unix/wine | $PRUN/crossover-26.3.0.39832/CrossOver/bin/wineserver | notproton-26.3"' "a game with no tool of its own gets Steam's default one, with Rosetta's loader"
mkmap ""
check 'has "$("$BIN" --prefix-target "$PPFX")" "refused | MacGameFix cannot tell which NotProton runner"' "with no tool and no record of the prefix's build, it refuses"
printf '27.0.0.41303-fex\nCrossOver 2026 - Rosetta\n' > "$PROOT/notproton-build"
check 'has "$("$BIN" --prefix-target "$PPFX")" "27.0.0.41303-fex | rosetta | $PRUN/crossover-27.0.0.41303-fex/CrossOver/lib/wine/x86_64-unix/wine" && has "$("$BIN" --prefix-target "$PPFX")" "| record"' "else the build NotProton recorded in the prefix, in the flavour of the prefix's ntdll (x86_64: Rosetta)"
mkpe aa64 "$PPFX/drive_c/windows/system32/ntdll.dll"
check 'has "$("$BIN" --prefix-target "$PPFX")" "27.0.0.41303-fex | fex |"' "an arm64 ntdll is FEX's"
mkpe 8664 "$PPFX/drive_c/windows/system32/ntdll.dll"
printf '27.0.0.40000-fex\n' > "$PROOT/notproton-build"
check 'has "$("$BIN" --prefix-target "$PPFX")" "refused | The game'"'"'s runner (CrossOver build 27.0.0.40000-fex) is not in NotProton'"'"'s runners"' "a runner NotProton no longer has is named, and nothing runs"

mkmap "$(maprow $PAPP notproton-26.3)"
printf '1\n' > "$PROOT/notproton-msync"
rm -f "$PREC"
OUT="$("$BIN" --prefix-run "$PPFX" "$PEXE" --remember "key-modgame" || true)"
waitrec || true
R="$(cat "$PREC" 2>/dev/null)"
check 'has "$OUT" "Started Mod Setup.exe in the game'"'"'s prefix, with CrossOver 26.3.0.39832 (Rosetta)" && has "$R" "args=$PEXE" && has "$R" "pwd=$(cd "$PL/common/ModGame/Mods" && pwd -P)" && has "$R" "WINEPREFIX=$PPFX"' "the program starts with the game's loader, in its own folder and the game's prefix"
check 'has "$R" "WINESERVER=$PRUN/crossover-26.3.0.39832/CrossOver/bin/wineserver" && has "$R" "WINEMSYNC=1" && has "$R" "CX_ROOT=$PRUN/crossover-26.3.0.39832/CrossOver"' "with NotProton's environment: its wineserver, CX_ROOT, and the prefix's msync choice"
check '[ "$("$BIN" --prefix-last key-modgame)" = "$PEXE" ] && has "$(cat "$SUPPORT/MacGameFix/prefix-runs/$PAPP.log")" "$PEXE"' "the program is remembered for the game, and the run has a log of its own"
PMSI="$PL/common/ModGame/Mods/pack.msi"; printf 'x' > "$PMSI"; rm -f "$PREC"
"$BIN" --prefix-run "$PPFX" "$PMSI" >/dev/null || true; waitrec || true
check 'has "$(cat "$PREC")" "args=msiexec /i $PMSI"' "an msi goes through msiexec /i, as NotProton runs it"
PTXT="$PL/common/ModGame/Mods/readme.txt"; printf 'x' > "$PTXT"
check 'has "$("$BIN" --prefix-run "$PPFX" "$PTXT")" "refused | readme.txt is not a Windows program"' "a file that is not a program is refused"

# In use: NotProton's lock held, then a wineserver of this prefix with its socket folder open.
rm -f "$PREC"
/usr/bin/python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"w"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(30)' "$PROOT/.notproton-prefix.lock" "$T/locked" &
LOCK_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$T/locked" ] && break; sleep 0.25; done
check 'has "$("$BIN" --prefix-run "$PPFX" "$PEXE")" "refused | NotProton is setting the game'"'"'s prefix up" && [ ! -e "$PREC" ]' "while NotProton holds the prefix's lock, nothing starts"
kill "$LOCK_PID" 2>/dev/null; wait "$LOCK_PID" 2>/dev/null || true
export MACGAMEFIX_WINE_SERVER_ROOT="$T/wineservers"
read -r PDEV PINO <<<"$(stat -f '%d %i' "$PPFX")"
PSRV="$MACGAMEFIX_WINE_SERVER_ROOT/server-$(printf '%x' "$PDEV")-$(printf '%x' "$PINO")"
mkdir -p "$PSRV"; : > "$PSRV/socket"
sleep 30 < "$PSRV/socket" &
SRV_PID=$!
sleep 0.5
check 'has "$("$BIN" --prefix-run "$PPFX" "$PEXE")" "refused | The game, or another program, is running in this prefix" && [ ! -e "$PREC" ]' "while anything runs in the prefix (its wineserver's folder is open), nothing starts"
kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null || true
"$BIN" --prefix-run "$PPFX" "$PEXE" >/dev/null || true; waitrec || true
check '[ -s "$PREC" ]' "once the game has quit and its wineserver has gone, it runs"
unset MACGAMEFIX_WINE_SERVER_ROOT
rm -f "$PSTEAM/config/config.vdf"; rmdir "$PSTEAM/config" 2>/dev/null || true
rm -rf "$PSTEAM/compatibilitytools.d" "$PRUN/crossover-26.3.0.39832" "$PRUN/crossover-27.0.0.41303-fex"
echo "== NotProton's processors row, made for this Mac"
NPP="$SUPPORT/notproton/plugins"; NPR="$NPP/mgf-ncpu.conf"; CT="$MACGAMEFIX_HOME/Library/Application Support/Steam/compatibilitytools.d"
rm -f "$NPR"
check '[ "$(MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep)" = "processors row: written for 16 processors" ]' "the row is written where NotProton is"
R=$(cat "$NPR")
check 'has "$R" "[NOTPROTON_ENV_WINENCPU]" && has "$R" "type = choice" && has "$R" "default = 0" && has "$R" "choice = 0 = All (16)"' "every game sees All by default, and picking All clears a game's option"
check 'has "$R" "choice = 12 = 12 (performance cores)" && has "$R" "choice = 14" && ! /usr/bin/grep -Eq "^choice = (1[6-9]|[2-9][0-9])" "$NPR"' "it offers only counts below this Mac's, and names the performance cores"
check '! has "$R" "group = " && has "$R" "label = Processors the game sees (MacGameFix)"' "without a NotProton that knows groups, no group line (an older one refuses the row), and the label says whose row it is"
check '[ "$(MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep)" = "processors row: nothing to do" ]' "a row already right is left as it is"
mkdir -p "$CT/notproton-a" "$CT/notproton-b"
printf '      split("label description section on off type choice default apps patch variants group improves needed_for", f, " ")\n' > "$CT/notproton-a/run"
printf '      split("label description section on off type choice default apps patch variants", f, " ")\n' > "$CT/notproton-b/run"
MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep >/dev/null
check '! has "$(cat "$NPR")" "group = "' "one NotProton in Steam that does not know groups keeps the group out"
rm -rf "$CT/notproton-b"
MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep >/dev/null
check 'has "$(cat "$NPR")" "group = MacGameFix / Performance" && [ "$(/usr/bin/grep -c MacGameFix "$NPR")" = 1 ]' "with every NotProton knowing groups, the row goes in MacGameFix / Performance and names MacGameFix there alone"
mkdir -p "$CT/notproton-gone"; : > "$CT/notproton-gone/run.backup"
MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep >/dev/null
check 'has "$(cat "$NPR")" "group = MacGameFix / Performance"' "a notproton folder with no run script (a tool NotProton emptied) has no say"
rm -rf "$CT/notproton-gone"
MACGAMEFIX_CPUS=10,4 "$BIN" --cpu-row-keep >/dev/null
check 'has "$(cat "$NPR")" "choice = 0 = All (10)" && has "$(cat "$NPR")" "choice = 4 = 4 (performance cores)" && has "$(cat "$NPR")" "choice = 8" && ! /usr/bin/grep -Eq "^choice = (1[0-9])" "$NPR"' "a Mac with 10 is offered All, 4, 6 and 8"
MACGAMEFIX_CPUS=32,24 "$BIN" --cpu-row-keep >/dev/null
check '[ "$(/usr/bin/grep -c "^choice = " "$NPR")" -le 16 ] && has "$(cat "$NPR")" "choice = 24 = 24 (performance cores)" && ! has "$(cat "$NPR")" "choice = 32"' "a Mac with 32 stays within NotProton's 16 values"
cp "$NPR" "$T/ncpu-before"
printf '[NOTPROTON_ENV_WINENCPU]\nlabel = Theirs\ntype = choice\nchoice = 4\n' > "$NPP/someone-else.conf"
check 'has "$(MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep)" "another plugin file has NOTPROTON_ENV_WINENCPU" && cmp -s "$NPR" "$T/ncpu-before"' "an id another file declares is left alone (NotProton would show neither)"
rm -f "$NPP/someone-else.conf" "$NPR"
for i in $(seq 1 32); do printf '[NOTPROTON_FULL_%s]\nlabel = Row %s\n' "$i" "$i"; done > "$NPP/full.conf"
check 'has "$(MACGAMEFIX_CPUS=16,12 "$BIN" --cpu-row-keep)" "32 rows are taken" && [ ! -e "$NPR" ]' "with NotProton's 32 rows taken, it adds none"
rm -f "$NPP/full.conf"
echo "== NotProton's frame rate cap, ray tracing and NVIDIA driver rows"
NPF="$NPP/mgf-fps.conf"; NPD="$NPP/mgf-dxr.conf"; NPV="$NPP/mgf-nvidia-driver.conf"
rm -f "$NPF" "$NPD" "$NPV"
OUT=$(MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep)
check 'has "$OUT" "frame rate cap row: written for a 120 Hz display" && has "$OUT" "ray tracing row: written"' "the agent's rows for every game are written beside the processors row"
F=$(cat "$NPF")
check 'has "$F" "[NOTPROTON_ENV_D3DM_MAX_FPS]" && has "$F" "default = 0" && has "$F" "choice = 0 = No limit (120 Hz)" && has "$F" "group = MacGameFix / Performance"' "every game is unlimited by default, and picking No limit clears a game's cap"
check 'has "$F" "choice = 70 = 60 fps" && has "$F" "choice = 100 = 80 fps" && has "$F" "choice = 54 = 48 fps" && has "$F" "choice = 44 = 40 fps" && has "$F" "choice = 32 = 30 fps"' "each rate writes the cap halfway to the next faster step: 60 fps writes 70, as measured"
check '! has "$F" "120 fps" && ! has "$F" "34 fps" && ! has "$F" "27 fps"' "no rate the display's fastest, and no step that is not a whole rate"
check 'has "$F" "tools = notproton-fex*" && has "$F" "tools = notproton-preview*" && ! has "$F" "notproton-2"' "only for the Preview tools, which run D3DMetal 4 (D3DMetal 3 has no cap)"
MACGAMEFIX_DISPLAY=60,0 "$BIN" --rows-keep >/dev/null
check 'has "$(cat "$NPF")" "choice = 0 = No limit (60 Hz)" && has "$(cat "$NPF")" "choice = 45 = 30 fps" && [ "$(/usr/bin/grep -c "^choice = " "$NPF")" = 2 ]' "a 60 Hz display with fixed steps is offered No limit and 30"
check 'has "$(MACGAMEFIX_DISPLAY=0,0 "$BIN" --rows-keep)" "frame rate cap row: this Mac'"'"'s display could not be read"' "with no display read, the cap row is not touched"
D=$(cat "$NPD")
check 'has "$D" "[NOTPROTON_MGF_DXR_OFF]" && has "$D" "on = 1" && has "$D" "env = D3DM_SUPPORT_DXR=0" && has "$D" "group = MacGameFix / D3DMetal"' "the ray tracing row, switched on, gives the game D3DM_SUPPORT_DXR=0"
V=$(cat "$NPV")
check 'has "$OUT" "NVIDIA driver row: written" && has "$V" "[NOTPROTON_MGF_NVIDIA_DRIVER]" && has "$V" "on = 1" && has "$V" "group = MacGameFix / D3DMetal" && has "$V" "tools = notproton-fex-rosetta*"' "the NVIDIA driver row is written for every game, for the Rosetta tools it was played on"
check '[ "$(/usr/bin/grep -c "^patch = D3DMetal/x86_64: " "$NPV")" = 2 ] && [ "$(/usr/bin/grep -o "=9f [a-f0-9]*=86 00=01 00 48 b8" "$NPV" | /usr/bin/grep -c .)" = 4 ] && [ "$(/usr/bin/grep -c "72 36 31 36 5f 34 31 | .* 72 35 36 30 5f 38 38$" "$NPV")" = 2 ]' "its two patches write 99999 over D3DMetal's driver version, one form for D3DMetal 4 and one for D3DMetal 3"
check 'has "$D" "improves = 4115450 With DLSS on, the game no longer closes as a level loads." && has "$V" "improves = 4080220 The game stops asking for a driver update at every start." && ! has "$D$V" "needed_for"' "a NotProton that reads improves is told the game each row is for: ray tracing off for Phantom Blade Zero, the driver version for EA SPORTS FC 27"
check '! /usr/bin/grep -Eq "^(improves|needed_for)" "$NPF" "$NPR"' "the rows with a type name no game: NotProton refuses the fields there"
MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep >/dev/null
check '[ "$(MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep)" = "rows: nothing to do" ]' "rows already right are left as they are"
cp "$CT/notproton-a/run" "$T/run-with-patch"
# A NotProton from before needed_for and improves refuses a row that carries them: it gets the
# rows as they were before the fields.
DXR0="$(printf '%s\n' '[NOTPROTON_MGF_DXR_OFF]' 'label = Ray tracing off' 'group = MacGameFix / D3DMetal' \
  'description = The game sees no ray tracing. For a game that closes as a level loads: Phantom Blade Zero with DLSS on' 'section = dev' 'on = 1' 'env = D3DM_SUPPORT_DXR=0')"
NVD0="$(printf '%s\n' '[NOTPROTON_MGF_NVIDIA_DRIVER]' 'label = NVIDIA driver version' 'group = MacGameFix / D3DMetal' \
  'description = The game sees a newer NVIDIA driver and stops asking for a driver update. Played with EA SPORTS FC 27' 'on = 1' 'tools = notproton-fex-rosetta*' \
  'patch = D3DMetal/x86_64: 48 c7 42 04 02=9f e1=86 00=01 00 48 b8 72 36 31 36 5f 34 31 | 48 c7 42 04 2d=9f db=86 00=01 00 48 b8 72 35 36 30 5f 38 38' \
  'patch = D3DMetal/x86_64: c7 01 02=9f e1=86 00=01 00 48 b8 72 36 31 36 5f 34 31 | c7 01 2d=9f db=86 00=01 00 48 b8 72 35 36 30 5f 38 38')"
check '[ "$(/usr/bin/grep -v "^improves = " "$NPD")" = "$DXR0" ] && [ "$(/usr/bin/grep -v "^improves = " "$NPV")" = "$NVD0" ]' "the line is all that the fields add to a row"
printf '      split("label description section on off type choice default apps patch variants group", f, " ")\n' > "$CT/notproton-a/run"
OUT=$(MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep)
check 'has "$OUT" "ray tracing row: written" && has "$OUT" "NVIDIA driver row: written" && [ "$(cat "$NPD")" = "$DXR0" ] && [ "$(cat "$NPV")" = "$NVD0" ]' "a NotProton that reads neither field gets the rows as they were before the fields"
printf '      split("label description section on off type choice default apps patch variants group improves", f, " ")\n' > "$CT/notproton-a/run"
mkdir -p "$CT/notproton-b"; printf '      split("label description section on off type choice default apps patch variants group", f, " ")\n' > "$CT/notproton-b/run"
MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep >/dev/null
check '[ "$(cat "$NPD")" = "$DXR0" ] && [ "$(cat "$NPV")" = "$NVD0" ]' "one NotProton in Steam that does not read improves keeps the line out"
rm -rf "$CT/notproton-b"
MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep >/dev/null
check 'has "$(cat "$NPD")" "improves = 4115450 " && has "$(cat "$NPV")" "improves = 4080220 "' "with every NotProton reading improves, the rows name their games again"
cp "$T/run-with-patch" "$CT/notproton-a/run"
MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep >/dev/null
printf '      split("label description section on off type choice default apps group", f, " ")\n' > "$CT/notproton-a/run"
check 'has "$(MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep)" "NVIDIA driver row: taken out, the NotProton in Steam does not read patch" && [ ! -e "$NPV" ]' "a NotProton that does not read patch loses the NVIDIA driver row"
check '[ "$(MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240 "$BIN" --rows-keep)" = "rows: nothing to do" ]' "and is not given it again"
cp "$T/run-with-patch" "$CT/notproton-a/run"
rm -f "$NPF" "$NPD" "$NPV" "$NPR"
rm -rf "$CT"
echo "== The NotProton plugins MacGameFix carries"
NPU="$NPP/40-unreal-video.conf"; NPZ="$NPP/50-d3dmetal-freeze.conf"; NPN="$NPP/55-d3dmetal-notifier.conf"; NPT="$NPP/60-red-dead-online.conf"; NPC="$NPP/mgf-controls.conf"; NPH="$NPP/mgf-shaders.conf"
NPLIB="$HERE/MacGameFix.app/Contents/Resources/notproton-plugins"; NPHOST="$SUPPORT/notproton/plugin-host.dylib"
export MACGAMEFIX_CPUS=16,12 MACGAMEFIX_DISPLAY=120,240
rm -f "$NPU" "$NPZ" "$NPN" "$NPT" "$NPC" "$NPH" "$NPP"/d3dmetal-freeze.dylib "$NPP"/d3dmetal-notifier.dylib "$NPP"/tcp-noopt.dylib "$NPP"/mgf-controls.dylib "$NPP"/mgf-shaders.dylib
mkdir -p "$CT/notproton-a"
printf '      split("label description description_on section on off depends requires inject env overrides stage tools type choice min max step default suffix hide_crossover apps patch variants group improves needed_for", f, " ")\n' > "$CT/notproton-a/run"
check '[ -f "$NPLIB/d3dmetal-freeze.dylib" ] && [ -f "$NPLIB/d3dmetal-notifier.dylib" ] && [ -f "$NPLIB/tcp-noopt.dylib" ] && has "$(lipo -archs "$NPLIB/tcp-noopt.dylib")" arm64 && has "$(lipo -archs "$NPLIB/tcp-noopt.dylib")" x86_64 && has "$(lipo -archs "$NPLIB/mgf-controls.dylib")" arm64 && has "$(lipo -archs "$NPLIB/mgf-controls.dylib")" x86_64 && has "$(lipo -archs "$NPLIB/mgf-shaders.dylib")" arm64 && has "$(lipo -archs "$NPLIB/mgf-shaders.dylib")" x86_64' "the app carries the five libraries, for both architectures"
# Nothing goes into NotProton until the player installs, and an install wants Steam and NotProton
# closed. MGVF_STEAM_RUNNING and MGVF_NOTPROTON_RUNNING answer for the Steam of the Mac the tests run on.
export MGVF_STEAM_RUNNING=0 MGVF_NOTPROTON_RUNNING=0 MGVF_NOTPROTON_VERSION=1.2.8
NPNOTE="$SUPPORT/MacGameFix/notproton-plugins.installed"; rm -f "$NPNOTE"
"$BIN" --rows-keep >/dev/null
check '[ ! -e "$NPU" ] && [ ! -e "$NPC" ] && has "$("$BIN" --plugins-report)" "Unreal video fix: not installed"' "the agent's pass puts no plugin in that the player has not installed"
OUT=$(MGVF_STEAM_RUNNING=1 "$BIN" --plugins-install) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Steam is open. Quit it, then install. Nothing was changed." && [ ! -e "$NPU" ]' "with Steam open the install is refused, and nothing is written"
OUT=$(MGVF_NOTPROTON_RUNNING=1 "$BIN" --plugins-install) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "NotProton is open. Quit it, then install." && [ ! -e "$NPU" ]' "and with NotProton's app open"
check 'has "$(MGVF_STEAM_RUNNING=1 MGVF_NOTPROTON_RUNNING=1 "$BIN" --plugins-install || true)" "Steam and NotProton are open. Quit them, then install."' "both open are both named"
OUT=$("$BIN" --plugins-install)
check 'has "$OUT" "Unreal video row: written" && [ -f "$NPU" ] && [ ! -e "$NPZ" ] && [ ! -e "$NPN" ] && [ ! -e "$NPT" ] && [ ! -e "$NPC" ] && [ ! -e "$NPP/tcp-noopt.dylib" ] && [ ! -e "$NPP/mgf-controls.dylib" ] && [ ! -e "$NPH" ] && [ ! -e "$NPP/mgf-shaders.dylib" ]' "without NotProton's plugin host, only the Unreal row: a library would load and do nothing"
OUT=$("$BIN" --plugins-report)
check 'has "$OUT" "Unreal video fix: in place" && has "$OUT" "D3DMetal freeze fix: not offered, NotProton'"'"'s plugin host is not installed"' "the window says which plugins are in place and why one is not offered"
U=$(cat "$NPU")
check 'has "$U" "[NOTPROTON_UNREAL_VIDEO]" && has "$U" "group = MacGameFix / Video" && has "$U" "on = 1" && [ "$(/usr/bin/grep -c "^patch = winegstreamer.dll: " "$NPU")" = 2 ] && has "$U" "label = Unreal video fix" && [ "$(/usr/bin/grep -c MacGameFix "$NPU")" = 1 ]' "the Unreal row is NotProton's own, with its two patches, in MacGameFix / Video, and names MacGameFix there alone"
: > "$NPHOST"
OUT=$("$BIN" --rows-keep)
check 'has "$OUT" "D3DMetal freeze library: put in place" && has "$OUT" "D3DMetal freeze row: written" && has "$OUT" "D3DMetal video crash row: written" && has "$OUT" "Red Dead Online row: written" && has "$OUT" "DualSense controllers library: put in place" && has "$OUT" "DualSense controllers row: written"' "with the plugin host, the four rows and their libraries go in"
check 'cmp -s "$NPLIB/d3dmetal-freeze.dylib" "$NPP/d3dmetal-freeze.dylib" && cmp -s "$NPLIB/d3dmetal-notifier.dylib" "$NPP/d3dmetal-notifier.dylib" && cmp -s "$NPLIB/tcp-noopt.dylib" "$NPP/tcp-noopt.dylib" && [ -x "$NPP/tcp-noopt.dylib" ]' "each library is the one the app carries"
check 'has "$(cat "$NPZ")" "requires = Library/Application Support/notproton/plugins/d3dmetal-freeze.dylib" && has "$(cat "$NPZ")" "inject = 1" && has "$(cat "$NPZ")" "group = MacGameFix / D3DMetal"' "a library's row injects it and requires it where it was put"
T6=$(cat "$NPT")
check 'has "$T6" "[NOTPROTON_TCP_NOOPT]" && has "$T6" "apps = 1174180" && has "$T6" "apps = 1404210" && has "$T6" "group = MacGameFix / Game fixes"' "the Red Dead Online row shows for Red Dead Redemption 2 and Red Dead Online only"
C6=$(cat "$NPC")
check 'has "$C6" "[NOTPROTON_MGF_CONTROLS]" && has "$C6" "label = DualSense controllers" && has "$C6" "group = MacGameFix / Controllers" && has "$C6" "inject = 1" && has "$C6" "tools = notproton-fex-rosetta*" && has "$C6" "requires = Library/Application Support/notproton/plugins/mgf-controls.dylib" && ! /usr/bin/grep -q "^apps" "$NPC" && cmp -s "$NPLIB/mgf-controls.dylib" "$NPP/mgf-controls.dylib"' "the DualSense controllers row is on every game's page, for the Rosetta tools, and loads the library the app carries"
S6=$(cat "$NPH")
check 'has "$S6" "[NOTPROTON_MGF_SHADERS]" && has "$S6" "label = Shaders kept whole" && has "$S6" "group = MacGameFix / Performance" && has "$S6" "inject = 1" && has "$S6" "requires = Library/Application Support/notproton/plugins/mgf-shaders.dylib" && has "$S6" "improves = 387290 " && has "$S6" "improves = 1057090 " && has "$S6" "improves = 4115450 " && ! /usr/bin/grep -q "^apps" "$NPH" && cmp -s "$NPLIB/mgf-shaders.dylib" "$NPP/mgf-shaders.dylib"' "the shaders row is on every game's page, names Ori and Phantom Blade Zero to NotProton, and loads the library the app carries"
# The library itself, loaded by a stand-in process on a stand-in cache (MGF_SHADERS_CACHE_DIR and
# MGF_SHADERS_BUNDLE, honoured only together; HOME too, so it finds no real plugin host to log to): the
# fullest file over the others, nothing while one is held.
printf '#include <dlfcn.h>\nint main(int c, char **v) { (void)c; return dlopen(v[1], RTLD_NOW) ? 0 : 1; }\n' > "$T/load.c" && clang -o "$T/load" "$T/load.c"
SB=com.notproton.launcher.387290; SC="$T/metal-cache"; SD="$SC/$SB/com.apple.metal/gpu"; mkdir -p "$SD"
printf 1234567890 > "$SD/functions.data"; printf ab > "$SD/functions.list"; printf 123 > "$SD/functions1.data"; printf a > "$SD/functions1.list"
/usr/bin/perl -e 'use Fcntl ":flock"; open my $f, "<", $ARGV[0]; flock($f, LOCK_EX); sleep 2' "$SD/functions1.data" & SHELD=$!; sleep 0.5
HOME="$T" MGF_SHADERS_CACHE_DIR="$SC" MGF_SHADERS_BUNDLE=$SB "$T/load" "$NPLIB/mgf-shaders.dylib" 2>/dev/null
check '[ "$(cat "$SD/functions1.data")" = 123 ] && [ ! -e "$SD/functions2.data" ]' "the shaders library leaves the files alone while a process holds one"
wait "$SHELD"
HOME="$T" MGF_SHADERS_CACHE_DIR="$SC" "$T/load" "$NPLIB/mgf-shaders.dylib" 2>/dev/null
check '[ "$(cat "$SD/functions1.data")" = 123 ]' "and, outside a game's bundle, without the stand-in bundle too"
HOME="$T" MGF_SHADERS_CACHE_DIR="$SC" MGF_SHADERS_BUNDLE=$SB "$T/load" "$NPLIB/mgf-shaders.dylib" 2>/dev/null
check '( for k in 1 2 3; do cmp -s "$SD/functions.data" "$SD/functions$k.data" && cmp -s "$SD/functions.list" "$SD/functions$k.list" || exit 1; done ) && [ ! -e "$SD/functions1.data.mgf-new" ]' "with none held, the fullest file and its list are cloned over the other three"
check '[ "$("$BIN" --plugins-report | /usr/bin/grep -c ": in place$")" = 6 ]' "with the plugin host, the window shows all six in place"
check '[ "$("$BIN" --rows-keep)" = "rows: nothing to do" ]' "plugins already right are left as they are"
check 'has "$T6" "improves = 1174180 Red Dead Online connects to its servers." && has "$T6" "improves = 1404210 Red Dead Online connects to its servers." && ! has "$T6" "needed_for"' "a NotProton that reads improves is told the Red Dead Online row is for Red Dead Redemption 2 and Red Dead Online"
check '! /usr/bin/grep -Eq "^(improves|needed_for)" "$NPU" "$NPZ" "$NPN" "$NPC"' "the rows whose games this repository does not name by Steam app name none"
RDO0="$(printf '%s\n' '[NOTPROTON_TCP_NOOPT]' 'label = Red Dead Online fix' 'group = MacGameFix / Game fixes' 'description = Lets Red Dead Online connect. Played online on NotProton 41303' \
  'on = 1' 'inject = 1' 'apps = 1174180' 'apps = 1404210' 'requires = Library/Application Support/notproton/plugins/tcp-noopt.dylib')"
cp "$CT/notproton-a/run" "$T/run-with-fields"
printf '      split("label description description_on section on off depends requires inject env overrides stage tools type choice min max step default suffix hide_crossover apps patch variants group", f, " ")\n' > "$CT/notproton-a/run"
OUT=$("$BIN" --rows-keep)
check 'has "$OUT" "Red Dead Online row: written" && ! has "$OUT" "Unreal" && ! has "$OUT" "D3DMetal freeze" && ! has "$OUT" "video crash" && has "$OUT" "Shaders kept whole row: written" && ! /usr/bin/grep -q "^improves" "$NPH" && ! has "$OUT" "DualSense" && ! has "$OUT" "library" && [ "$(cat "$NPT")" = "$RDO0" ] && [ "$("$BIN" --plugins-report | /usr/bin/grep -c ": in place$")" = 6 ]' "a NotProton that does not read improves gets the Red Dead Online and shaders rows without the field, and no other carried plugin changes"
cp "$T/run-with-fields" "$CT/notproton-a/run"
OUT=$("$BIN" --rows-keep)
check 'has "$OUT" "Red Dead Online row: written" && [ "$(/usr/bin/grep -v "^improves = " "$NPT")" = "$RDO0" ] && [ "$(/usr/bin/grep -c "^improves = " "$NPT")" = 2 ] && [ "$(/usr/bin/grep -c "^improves = " "$NPH")" = 3 ] && [ "$("$BIN" --rows-keep)" = "rows: nothing to do" ]' "and one that reads it again gets the two lines back, and nothing else"
printf 'an older build' > "$NPP/tcp-noopt.dylib"
check 'has "$("$BIN" --plugins-report)" "Red Dead Online fix: not in place yet"' "a library that differs shows as not in place yet"
check '[ "$("$BIN" --rows-keep)" = "Red Dead Online library: put in place" ] && cmp -s "$NPLIB/tcp-noopt.dylib" "$NPP/tcp-noopt.dylib" && [ ! -e "$NPP/.tcp-noopt.dylib.mgf-new" ]' "a library that differs is replaced, through a rename, and nothing is left beside it"
rm -f "$NPN"; printf 'theirs' > "$NPP/d3dmetal-notifier.dylib"
printf '[NOTPROTON_D3DMETAL_NOTIFIER]\nlabel = Theirs\non = 1\n' > "$NPP/someone-else.conf"
check 'has "$("$BIN" --plugins-report)" "D3DMetal video crash fix: another plugin file has it"' "an id another file declares shows as theirs"
check 'has "$("$BIN" --rows-keep)" "another plugin file has NOTPROTON_D3DMETAL_NOTIFIER, left alone" && [ ! -e "$NPN" ] && [ "$(cat "$NPP/d3dmetal-notifier.dylib")" = theirs ]' "an id another file declares is left alone, and so is its library"
rm -f "$NPP/someone-else.conf" "$NPP/d3dmetal-notifier.dylib"
# NotProton's Plugins page deletes a plugin by moving its row and its library to the Trash.
OUT=$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)
check 'has "$OUT" "D3DMetal video crash row: deleted from NotProton'"'"'s plugins, left out until it is installed again" && [ ! -e "$NPN" ] && [ ! -e "$NPP/d3dmetal-notifier.dylib" ] && [ "$("$BIN" --rows-keep)" = "rows: nothing to do" ] && has "$("$BIN" --plugins-report)" "D3DMetal video crash fix: not installed"' "a plugin deleted in NotProton is not put back by the agent's pass"
check '! MGVF_STEAM_RUNNING=1 "$BIN" --plugins-install >/dev/null && [ ! -e "$NPN" ]' "nor by an install while Steam is open"
OUT=$("$BIN" --plugins-install)
check 'has "$OUT" "D3DMetal video crash library: put in place" && has "$OUT" "D3DMetal video crash row: written" && [ -f "$NPN" ] && cmp -s "$NPLIB/d3dmetal-notifier.dylib" "$NPP/d3dmetal-notifier.dylib" && ! has "$OUT" "Unreal" && ! has "$OUT" "DualSense"' "installing again brings it back, and touches no other plugin"
# One plugin at a time: removed, it is out of NotProton and of the note, and stays out; installed by
# its id, it alone comes back. Both want Steam and NotProton closed.
check 'has "$("$BIN" --plugins-report | tail -1)" "rows: $(cat "$NPP"/*.conf | /usr/bin/grep -c "^\[") of 32"' "the report counts the rows in NotProton's folder, of the 32 it reads"
OUT=$(MGVF_STEAM_RUNNING=1 "$BIN" --plugins-remove NOTPROTON_MGF_CONTROLS) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Steam is open. Quit it, then remove it. Nothing was changed." && [ -f "$NPC" ] && [ -f "$NPP/mgf-controls.dylib" ]' "with Steam open a plugin is not removed"
OUT=$("$BIN" --plugins-remove NOTPROTON_MGF_CONTROLS)
check 'has "$OUT" "DualSense controllers row: removed" && has "$OUT" "DualSense controllers library: removed" && [ ! -e "$NPC" ] && [ ! -e "$NPP/mgf-controls.dylib" ] && ! /usr/bin/grep -q NOTPROTON_MGF_CONTROLS "$NPNOTE" && [ -f "$NPT" ] && [ -f "$NPP/tcp-noopt.dylib" ] && [ -f "$NPU" ]' "removed with both closed: its row, its library and its place in the note, and no other plugin"
check '[ "$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)" = "rows: nothing to do" ] && [ ! -e "$NPC" ] && has "$("$BIN" --plugins-report)" "DualSense controllers: not installed"' "a removed plugin is not put back by the agent's pass"
"$BIN" --plugins-remove NOTPROTON_TCP_NOOPT >/dev/null
OUT=$("$BIN" --plugins-install NOTPROTON_MGF_CONTROLS)
check 'has "$OUT" "DualSense controllers row: written" && [ -f "$NPC" ] && cmp -s "$NPLIB/mgf-controls.dylib" "$NPP/mgf-controls.dylib" && [ ! -e "$NPT" ] && has "$("$BIN" --plugins-report)" "Red Dead Online fix: not installed"' "installed by its id, that plugin alone comes back: another one removed stays out"
check '! MGVF_NOTPROTON_RUNNING=1 "$BIN" --plugins-install NOTPROTON_TCP_NOOPT >/dev/null && [ ! -e "$NPT" ] && "$BIN" --plugins-install NOTPROTON_TCP_NOOPT >/dev/null && [ -f "$NPT" ] && [ "$("$BIN" --plugins-report | /usr/bin/grep -c ": in place$")" = 6 ]' "one plugin's install waits for NotProton to close too, and with it back all six are in place"
OUT=$("$BIN" --plugins-remove NOTPROTON_NO_SUCH_PLUGIN) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "is no plugin of MacGameFix"' "an id that is no plugin of MacGameFix's is refused"
cp "$NPZ" "$T/freeze-row"; printf '[NOTPROTON_D3DMETAL_NODEGUARD]\nlabel = Written by hand\non = 1\n' > "$NPZ"
OUT=$("$BIN" --plugins-remove NOTPROTON_D3DMETAL_NODEGUARD) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "is not one MacGameFix wrote, left alone" && has "$(cat "$NPZ")" "Written by hand"' "a row under a plugin's file name that MacGameFix did not write is not removed"
cp "$T/freeze-row" "$NPZ"
# Game Feel switches "DualSense controllers" on for one game: the row's variable in the game's Steam
# launch options, with what the account had kept so that turning it off gives it back. Only with
# Steam closed, for a game on a tool the row is for, with the plugin installed.
# With the app's own catalog: the downloaded one of the tests above is put back after.
mv "$SUPPORT/MacGameFix/catalog" "$T/catalog-aside"
GFV="$PSTEAM/userdata/1/config/localconfig.vdf"; mkdir -p "$(dirname "$GFV")" "$PSTEAM/config"
printf '"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"apps"\n\t\t\t\t{\n\t\t\t\t\t"4242"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LaunchOptions"\t\t"MTL_HUD_ENABLED=0 %%command%%"\n\t\t\t\t\t}\n\t\t\t\t\t"4343"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LastPlayed"\t\t"1"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' > "$GFV"
cp "$GFV" "$T/localconfig.before"
mkmap "$(maprow 4242 notproton-fex-rosetta-41303; maprow 4343 notproton-fex-rosetta-41303; maprow 4444 notproton-fex-41303; maprow 4545 notproton-fex-rosetta-41303)"
GFJ="$SUPPORT/MacGameFix/notproton-rows/4242-NOTPROTON_MGF_CONTROLS.json"
gfrow() { "$BIN" --controls-row "$@"; }
check '[ "$(gfrow status 4242)" = off ] && [ ! -e "$GFJ" ]' "Game Feel reads the DualSense controllers row as off for a game whose launch options do not carry it"
OUT=$(MGVF_STEAM_RUNNING=1 gfrow on 4242) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Steam is open. Quit it, then turn it on. Nothing was changed." && cmp -s "$GFV" "$T/localconfig.before" && [ ! -e "$GFJ" ]' "with Steam open it is not switched on, and the settings of Steam are untouched"
check '[ "$(gfrow on 4242)" = "on, switched on here" ] && /usr/bin/grep -q "\"NOTPROTON_MGF_CONTROLS=1 MTL_HUD_ENABLED=0 %command%\"" "$GFV" && [ -f "$GFJ" ] && [ "$(gfrow status 4242)" = "on, switched on here" ]' "switched on with Steam closed, the variable goes in front of what the options of the game had, and what they had is kept"
OUT=$(MGVF_STEAM_RUNNING=1 gfrow off 4242) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Quit it, then turn it off" && [ "$(gfrow status 4242)" = "on, switched on here" ]' "nor switched off with Steam open"
check '[ "$(gfrow off 4242)" = off ] && cmp -s "$GFV" "$T/localconfig.before" && [ ! -e "$GFJ" ]' "switched off, the settings of Steam are byte for byte what they were"
check '/usr/bin/grep -qx "4242 NOTPROTON_MGF_CONTROLS off" "$SUPPORT/MacGameFix/notproton-rows.applied"' "and it is noted as switched off, where the agent reads which rows it may switch on"
check '[ "$(gfrow on 4343)" = "on, switched on here" ] && /usr/bin/grep -q "\"NOTPROTON_MGF_CONTROLS=1 %command%\"" "$GFV" && [ "$(gfrow off 4343)" = off ] && /usr/bin/grep -q "\"LaunchOptions\" \"\"" "$GFV" && [ "$(/usr/bin/grep -v "\"LaunchOptions\" \"\"" "$GFV")" = "$(cat "$T/localconfig.before")" ]' "a game with no launch options gets them, and switched off is left with empty ones, as Steam writes them, and nothing else changed"
sed -i '' 's|"MTL_HUD_ENABLED=0 %command%"|"NOTPROTON_MGF_CONTROLS=1 MTL_HUD_ENABLED=0 %command%"|' "$GFV"
OUT=$(gfrow off 4242) && RC=0 || RC=$?
check '[ "$(gfrow status 4242)" = on ] && [ "$RC" = 1 ] && has "$OUT" "Game Feel did not switch it on" && /usr/bin/grep -q "NOTPROTON_MGF_CONTROLS=1 MTL_HUD_ENABLED=0" "$GFV"' "a row the player switched on in Steam reads on, and is theirs to switch off there"
# A game whose options run a program of another fix before the game (a mod tool's play script):
# the row in front of it is read, and where it is not there Game Feel does not write past a program.
cp "$T/localconfig.before" "$GFV"
sed -i '' 's|"MTL_HUD_ENABLED=0 %command%"|"NOTPROTON_MGF_CONTROLS=1 MTL_HUD_ENABLED=0 \\"/x/play.sh\\" %command%"|' "$GFV"
check '[ "$(gfrow status 4242)" = on ]' "a row in front of another program in the launch options reads on"
sed -i '' 's|"NOTPROTON_MGF_CONTROLS=1 MTL_HUD_ENABLED=0 |"MTL_HUD_ENABLED=0 |' "$GFV"
OUT=$(gfrow on 4242) && RC=0 || RC=$?
check '[ "$(gfrow status 4242)" = off ] && [ "$RC" = 1 ] && has "$OUT" "start with a program" && /usr/bin/grep -q "\"MTL_HUD_ENABLED=0 .*play.sh.* %command%\"" "$GFV"' "without it the game reads off, and Game Feel does not write options that run a program: it says to set them by hand"
cp "$T/localconfig.before" "$GFV"
OUT=$(gfrow on 4545) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Start it once in Steam first" && cmp -s "$GFV" "$T/localconfig.before"' "a game Steam has no settings for yet is not switched on, and says to start it once"
check '[ "$(gfrow status 4444)" = "not for notproton-fex-41303" ] && has "$(gfrow status 4646)" "not for this game"' "a game on a tool the row is not for, or on none, is told so"
check '[ "$(gfrow status 18155907846443630592)" = "a game added to Steam" ]' "a game added to Steam keeps its options elsewhere: it is pointed to Steam"
"$BIN" --plugins-remove NOTPROTON_MGF_CONTROLS >/dev/null
check '[ "$(gfrow status 4242)" = "not installed" ]' "with the plugin removed from NotProton, the row is not offered for a game"
"$BIN" --plugins-install NOTPROTON_MGF_CONTROLS >/dev/null
rm -rf "$PSTEAM/userdata" "$PSTEAM/config" "$SUPPORT/MacGameFix/notproton-rows" "$SUPPORT/MacGameFix/notproton-rows.applied"
mv "$T/catalog-aside" "$SUPPORT/MacGameFix/catalog"
# Engine fixes, the row for every game: the catalog's script writes it, into the file the games' installers share.
NPS="$NPP/mgf-shared.conf"; NPE="$NPP/mgf-engine.dylib"; NPRES="$HERE/MacGameFix.app/Contents/Resources"
check 'has "$("$BIN" --plugins-report)" "Engine fixes: not offered, this catalog of fixes has no installer for it"' "a downloaded catalog from before the installer existed does not offer Engine fixes"
# The app's own catalog from here: the downloaded one of the tests above is put back after.
mv "$SUPPORT/MacGameFix/catalog" "$T/catalog-aside"
check '[ -x "$NPRES/notproton-every-game.sh" ] && [ -f "$NPRES/mgf-engine.dylib" ] && has "$("$BIN" --plugins-report)" "Engine fixes: not installed" && [ ! -e "$NPS" ]' "the app carries the installer of the rows for every game, and nothing of them is there before an install"
check 'has "$(MGVF_STEAM_RUNNING=1 "$BIN" --plugins-install || true)" "Steam is open" && [ ! -e "$NPS" ] && [ ! -e "$NPE" ]' "with every other plugin installed, Engine fixes alone still waits for Steam to close"
OUT=$("$BIN" --plugins-install)
check 'has "$OUT" "Engine fixes: NotProton: 1 row(s) for every game" && has "$(cat "$NPS")" "[NOTPROTON_MGF_ENGINE]" && ! /usr/bin/grep -q "^apps" "$NPS" && has "$(cat "$NPS")" "requires = Library/Application Support/notproton/plugins/mgf-engine.dylib" && cmp -s "$NPRES/mgf-engine.dylib" "$NPE" && has "$("$BIN" --plugins-report)" "Engine fixes: in place" && [ "$("$BIN" --plugins-install)" = "plugins: nothing to do" ]' "the install puts Engine fixes on every game's page, with no game's fix installed, and its library beside it"
# Removed as any other plugin; where a game's fix uses the row it stays, and the removal says so.
OUT=$(MGVF_STEAM_RUNNING=1 "$BIN" --plugins-remove NOTPROTON_MGF_ENGINE) && RC=0 || RC=$?
check '[ "$RC" = 1 ] && has "$OUT" "Steam is open" && [ -f "$NPS" ]' "Engine fixes is not removed with Steam open"
check '[ "$("$BIN" --plugins-remove NOTPROTON_MGF_ENGINE)" = "Engine fixes: removed" ] && [ ! -e "$NPS" ] && [ ! -e "$NPE" ] && [ ! -e "$NPP/mgf-every-game.uses" ] && has "$("$BIN" --plugins-report)" "Engine fixes: not installed" && [ "$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)" = "rows: nothing to do" ] && [ ! -e "$NPS" ]' "removed with both closed, its file, its library and its note are gone, and no pass puts it back"
"$BIN" --plugins-install NOTPROTON_MGF_ENGINE >/dev/null
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE\n' > "$NPP/mgf-4080220.uses"
check 'has "$("$BIN" --plugins-report)" "Engine fixes: in place" && has "$("$BIN" --plugins-remove NOTPROTON_MGF_ENGINE)" "Engine fixes: NotProton: the row stays, the fix of 1 game(s) uses it" && has "$(cat "$NPS")" "[NOTPROTON_MGF_ENGINE]" && [ -f "$NPE" ]' "installed by its id; and removed while a game's fix uses it, the row and the library stay for that game, and the removal says so"
rm -f "$NPP/mgf-4080220.uses"; "$BIN" --plugins-install NOTPROTON_MGF_ENGINE >/dev/null
echo "description = edited by hand" >> "$NPS"
check 'has "$("$BIN" --plugins-report)" "Engine fixes: not in place yet" && has "$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)" "Engine fixes: " && ! /usr/bin/grep -q "edited by hand" "$NPS" && has "$("$BIN" --plugins-report)" "Engine fixes: in place"' "once installed it is kept current by the agent's pass, with Steam open too"
printf 'not a build of ours' > "$NPE"
check 'has "$("$BIN" --rows-keep)" "Engine fixes: error: mgf-engine.dylib in NotProton'"'"'s plugins folder is not one MacGameFix shipped; nothing was changed." && [ "$(cat "$NPE")" = "not a build of ours" ]' "a library there that MacGameFix never shipped is left as it is, and the pass says so"
rm -f "$NPS" "$NPE"
check 'has "$("$BIN" --plugins-report)" "Engine fixes: not installed" && [ "$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)" = "rows: nothing to do" ] && [ ! -e "$NPS" ]' "deleted in NotProton, it stays out as well"
rm -f "$NPP/mgf-every-game.uses"
# A Mac from before the notes, where a game's fix put Engine fixes in: the first pass takes it as
# installed, as it does the plugins whose rows are there.
rm -f "$NPNOTE"
printf '# MacGameFix writes this file for app 4080220 and removes it with the fix; edits do not last.\n# shared rows: NOTPROTON_MGF_ENGINE\n' > "$NPP/mgf-4080220.uses"
( HOME="$MACGAMEFIX_HOME"; . "$NPRES/notproton-plugins.sh"; NP_SHARED_TEMPLATE="$NPRES/np-plugin-shared.conf"; NP_SHARED_GROUP=""; np_shared_write ); cp "$NPRES/mgf-engine.dylib" "$NPE"
check 'has "$("$BIN" --plugins-report)" "Engine fixes: not installed" && [ "$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-keep)" = "rows: nothing to do" ] && [ -f "$NPP/mgf-every-game.uses" ] && [ "$("$BIN" --plugins-report | /usr/bin/grep -c ": in place$")" = 7 ]' "on a Mac from before the notes, what is already there is taken as installed: Engine fixes a game's fix put in, and the six plugins"
rm -f "$NPP/mgf-4080220.uses" "$NPP/mgf-every-game.uses" "$NPS" "$NPE"
mv "$T/catalog-aside" "$SUPPORT/MacGameFix/catalog"
rm -f "$NPHOST"
OUT=$("$BIN" --rows-keep)
check 'has "$OUT" "D3DMetal freeze row: taken out, NotProton'"'"'s plugin host is not installed" && [ ! -e "$NPZ" ] && [ ! -e "$NPN" ] && [ ! -e "$NPT" ] && [ ! -e "$NPC" ] && [ -f "$NPU" ]' "with the plugin host gone, the library rows come out and the Unreal row stays"
printf '      split("label description section on off depends requires inject env type choice default apps", f, " ")\n' > "$CT/notproton-a/run"
printf '[NOTPROTON_D3DMETAL_NODEGUARD]\nlabel = Written by hand\non = 1\n' > "$NPZ"
OUT=$("$BIN" --rows-keep)
check 'has "$OUT" "Unreal video row: taken out, the NotProton in Steam does not read patch" && [ ! -e "$NPU" ] && [ -f "$NPZ" ]' "a NotProton that does not read patch loses the Unreal row; a file MacGameFix did not write stays"
rm -f "$NPZ" "$NPP"/*.dylib "$NPF" "$NPD" "$NPV" "$NPR" "$NPNOTE"
rm -rf "$CT"
unset MACGAMEFIX_CPUS MACGAMEFIX_DISPLAY MGVF_STEAM_RUNNING MGVF_NOTPROTON_RUNNING MGVF_NOTPROTON_VERSION

echo "== NotProton rows switched on per game"
# The catalog's table and Game Feel name rows for games (RowsByGame.swift); each one goes into the
# game's launch options once, where its plugin is in place, the game is in a Steam library and
# Steam is closed. MACGAMEFIX_LAUNCH_OPTIONS is a copy of the writer that does not look for the
# Mac's own Steam; MACGAMEFIX_ROWS_TABLE is the table this build carries.
export MGVF_STEAM_RUNNING=0 MGVF_NOTPROTON_RUNNING=0 MGVF_NOTPROTON_VERSION=1.2.8
mkdir -p "$CT/notproton-a"
printf '      split("label description description_on section on off depends requires inject env overrides stage tools type choice min max step default suffix hide_crossover apps patch variants group improves needed_for", f, " ")\n' > "$CT/notproton-a/run"
: > "$NPHOST"
RG="$MACGAMEFIX_HOME/Library/Application Support/Steam"; RGVDF="$RG/userdata/1/config/localconfig.vdf"
mkdir -p "$RG/steamapps" "$(dirname "$RGVDF")"
for a in 387290 4115450 1174180; do printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"installdir"\t\t"G%s"\n}\n' "$a" "$a" > "$RG/steamapps/appmanifest_$a.acf"; done
printf '"UserLocalConfigStore"\n{\n\t"Software" { "Valve" { "Steam" { "apps" {\n\t\t"387290" { "LaunchOptions" "MINE=1 %%command%%" }\n\t\t"4115450" { "LaunchOptions" "\\"/x/wrap.sh\\" %%command%%" }\n\t\t"1174180" { "LaunchOptions" "" }\n\t} } } }\n}\n' > "$RGVDF"
RGVDF0="$(cat "$RGVDF")"
# Each game's tool: NotProton's Rosetta one, but 2222 on FEX's, where the controls row is not offered.
mkdir -p "$RG/config"
mkmap "$(for a in 387290 4115450 1174180 1057090 3333; do maprow $a notproton-fex-rosetta-41303; done; maprow 2222 notproton-fex-41303)"
for a in 2222 3333; do printf '"AppState"\n{\n\t"appid"\t\t"%s"\n}\n' "$a" > "$RG/steamapps/appmanifest_$a.acf"; done
/usr/bin/perl -pi -e 's/(\t\t"1174180")/\t\t"2222" { "LaunchOptions" "" }\n\t\t"3333" { "LaunchOptions" "" }\n$1/' "$RGVDF"
RGVDF0="$(cat "$RGVDF")"
cp "$NPRES/steam-launch-options.pl" "$T/slo.pl" && sed -i '' 's|/bin/ps -axo comm=|/usr/bin/true|' "$T/slo.pl"
export MACGAMEFIX_LAUNCH_OPTIONS="$T/slo.pl" MACGAMEFIX_ROWS_TABLE="$NPRES/notproton-rows.json"
/usr/bin/python3 - "$P/pad.json" <<'PYRG'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except OSError:
    d = {}
d.setdefault("games", {})["1174180"] = {"name": "Red Dead Redemption 2", "options": {"xinput": "pad"}}
d["games"]["2222"] = {"name": "A game on the FEX tool", "options": {"xinput": "pad"}}
d["games"]["3333"] = {"name": "A game switched off in Game Feel", "options": {"xinput": "pad"}}
json.dump(d, open(sys.argv[1], "w"))
PYRG
opts() { /usr/bin/perl -ne 'print "$1\n" if /"'"$1"'" \{ "LaunchOptions" "((?:\\.|[^"\\])*)"/' "$RGVDF"; }
check '[ "$(/usr/libexec/PlistBuddy -c "Print :MacGameFixRowsSchemaVersion" "$HERE/MacGameFix.app/Contents/Info.plist")" = 1 ] && [ -f "$NPRES/notproton-rows.json" ] && [ -f "$NPRES/steam-launch-options.pl" ]' "the app says which table it reads, and carries the table and the writer"
check 'has "$("$BIN" --rows-by-game-report)" "387290 NOTPROTON_MGF_SHADERS (catalog): waits for its plugin"' "a row waits for its plugin to be installed"
OUT=$("$BIN" --plugins-install 2>&1 || true)
check 'has "$OUT" "387290 NOTPROTON_MGF_SHADERS: switched on (catalog)" && [ "$(opts 387290)" = "NOTPROTON_MGF_SHADERS=1 MINE=1 %command%" ]' "installing the plugin with Steam closed puts the catalog's row in front of the game's own options"
check 'has "$OUT" "1174180 NOTPROTON_MGF_CONTROLS: switched on (Game Feel)" && [ "$(opts 1174180)" = "NOTPROTON_MGF_CONTROLS=1 %command%" ]' "a game set up in Game Feel gets the DualSense controllers row"
check 'has "$OUT" "4115450 NOTPROTON_MGF_SHADERS: not switched on, the game'"'"'s launch options start with a program" && has "$(opts 4115450)" "wrap.sh"' "options that start with a program are left as they are, and that is said"
check '[ "$(opts 2222)" = "" ] && ! has "$OUT" "2222" && has "$("$BIN" --rows-by-game-report)" "2222 NOTPROTON_MGF_CONTROLS (Game Feel): the game does not run on a NotProton tool the row is for"' "a game set up in Game Feel that runs on a tool the row is not for is left alone, and the report says why"
# Game Feel's own switch writes through the same journal and record: turned off there, the pass leaves it off.
check '[ "$(opts 3333)" = "NOTPROTON_MGF_CONTROLS=1 %command%" ] && [ "$("$BIN" --controls-row status 3333)" = "on, switched on here" ] && [ "$("$BIN" --controls-row off 3333)" = off ] && [ "$(opts 3333)" = "" ] && [ -z "$("$BIN" --rows-by-game | /usr/bin/grep ": switched on (")" ] && [ "$(opts 3333)" = "" ] && has "$("$BIN" --rows-by-game-report)" "3333 NOTPROTON_MGF_CONTROLS (Game Feel): switched off in Game Feel"' "a row the pass switched on reads in Game Feel as switched on here; turned off there, the pass does not switch it on again"
check 'has "$("$BIN" --rows-by-game-report)" "1057090 NOTPROTON_MGF_SHADERS (catalog): the game is not installed" && ! has "$(cat "$RGVDF")" "1057090"' "a game no library has is left out"
# Installed later, while Steam is open: it waits for Steam to close.
printf '"AppState"\n{\n\t"appid"\t\t"1057090"\n}\n' > "$RG/steamapps/appmanifest_1057090.acf"
/usr/bin/perl -pi -e 's/(\t\t"1174180")/\t\t"1057090" { "LaunchOptions" "" }\n$1/' "$RGVDF"
RGVDF1="$(cat "$RGVDF")"
OUT=$(MGVF_STEAM_RUNNING=1 "$BIN" --rows-by-game)
check '[ "$(cat "$RGVDF")" = "$RGVDF1" ] && has "$OUT" "1057090 NOTPROTON_MGF_SHADERS (catalog): to switch on while Steam is closed"' "with Steam open nothing is written, and the report says what waits"
OUT=$("$BIN" --rows-by-game)
check 'has "$OUT" "1057090 NOTPROTON_MGF_SHADERS: switched on (catalog)" && [ "$(opts 1057090)" = "NOTPROTON_MGF_SHADERS=1 %command%" ]' "and goes in at the next pass with Steam closed"
/usr/bin/perl -pi -e 's/NOTPROTON_MGF_SHADERS=1 //' "$RGVDF"
OUT=$("$BIN" --rows-by-game)
check '[ "$(opts 387290)" = "MINE=1 %command%" ] && has "$OUT" "387290 NOTPROTON_MGF_SHADERS (catalog): switched on" && ! has "$OUT" ": switched on (catalog)"' "a row the player switched off in Steam is not switched on again"
check 'has "$(cat "$SUPPORT/MacGameFix/notproton-rows.applied")" "4115450 NOTPROTON_MGF_SHADERS refused" && [ -z "$("$BIN" --rows-by-game | /usr/bin/grep -v "^[0-9]* NOTPROTON_[A-Z_]* (")" ]' "nor is one refused tried again"
OUT=$("$BIN" --plugins-remove NOTPROTON_MGF_CONTROLS)
check 'has "$OUT" "1174180 NOTPROTON_MGF_CONTROLS: launch options given back" && [ "$(opts 1174180)" = "" ] && [ ! -e "$SUPPORT/MacGameFix/notproton-rows/1174180-NOTPROTON_MGF_CONTROLS.json" ] && ! /usr/bin/grep -q "1174180" "$SUPPORT/MacGameFix/notproton-rows.applied"' "removing the plugin gives each game its launch options back as they were"
printf '{"schema": 2, "games": [{"appid": "387290", "title": "x", "rows": ["NOTPROTON_MGF_SHADERS"]}]}\n' > "$T/rows-2.json"
check '! has "$(MACGAMEFIX_ROWS_TABLE="$T/rows-2.json" "$BIN" --rows-by-game-report)" "(catalog)"' "a table of a newer schema than the app reads is not applied"
"$BIN" --plugins-remove NOTPROTON_MGF_SHADERS >/dev/null
rm -rf "$RG/steamapps/appmanifest_"* "$RG/userdata" "$RG/config" "$SUPPORT/MacGameFix/notproton-rows" "$SUPPORT/MacGameFix/notproton-rows.applied" "$NPHOST"
rm -f "$NPP"/*.conf "$NPP"/*.dylib "$NPNOTE"
rm -rf "$CT"
unset MACGAMEFIX_LAUNCH_OPTIONS MACGAMEFIX_ROWS_TABLE MGVF_STEAM_RUNNING MGVF_NOTPROTON_RUNNING MGVF_NOTPROTON_VERSION

echo "== Game Mode for CrossOver's games"
GM="$MACGAMEFIX_HOME/Applications/CrossOver GM.app"
GW="$GM/Contents/SharedSupport/CrossOver/lib/wine"
mkdir -p "$GW/x86_64-unix" "$GW/x86_64-windows" "$GW/aarch64-unix/wine.app/Contents/MacOS" "$GW/aarch64-windows"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 27.0.0.41073' "$GM/Contents/Info.plist" >/dev/null
printf 'intel ntdll' > "$GW/x86_64-unix/ntdll.so"; printf 'arm ntdll' > "$GW/aarch64-unix/ntdll.so"
printf '#!/bin/sh\n# intel loader\n' > "$GW/x86_64-unix/wine"; printf '#!/bin/sh\n# arm loader\n' > "$GW/aarch64-unix/wine.app/Contents/MacOS/wine"
chmod +x "$GW/x86_64-unix/wine" "$GW/aarch64-unix/wine.app/Contents/MacOS/wine"
: > "$GW/x86_64-windows/explorer.exe"; : > "$GW/aarch64-windows/explorer.exe"
touch -d 2026-01-02T03:04:05.012345678 "$GW/x86_64-unix/wine"
OLD="$MACGAMEFIX_HOME/Applications/CrossOver Old.app"
mkdir -p "$OLD/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 25.0.0.1' "$OLD/Contents/Info.plist" >/dev/null
: > "$OLD/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/ntdll.so"
cp "$GW/x86_64-unix/wine" "$OLD/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine"
# The game is in a library of a bottle's Steam; one in the Mac's own Steam is NotProton's and gets nothing.
GB="$SUPPORT/CrossOver/Bottles/GM Steam"
mkdir -p "$GB/drive_c/Program Files (x86)/Steam/config" "$GB/dosdevices"
ln -s / "$GB/dosdevices/z:"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"Z:%s"\n\t}\n}\n' "$(printf '%s' "$T/GM Library" | sed 's#/#\\\\#g')" \
  > "$GB/drive_c/Program Files (x86)/Steam/config/libraryfolders.vdf"
MG="$T/GM Library/steamapps/common/Mode Game"
mkdir -p "$MG/Binaries/Win64" "$T/tmp" "$SUPPORT/Steam/steamapps/common/NP Game"
: > "$MG/ModeGame.exe"; : > "$MG/Binaries/Win64/ModeGame-Win64-Shipping.exe"; : > "$MG/Other.exe"; : > "$MG/explorer.exe"
: > "$SUPPORT/Steam/steamapps/common/NP Game/NPGame.exe"
export MACGAMEFIX_TEMP_DIR="$T/tmp"
WT="$T/tmp/winetemp-$(stat -f '%i-%z-%m' "$GW/x86_64-unix/wine")-12345678"
mkdir -p "$WT"
ln "$GW/x86_64-unix/wine" "$WT/ModeGame.exe"
ln -s "$T/elsewhere/wine" "$WT/Other.exe"
COPY="$SUPPORT/MacGameFix/GameMode/CrossOver GM 27.0.0.41073 x86_64/CrossOver Game.app"
ARMCOPY="$SUPPORT/MacGameFix/GameMode/CrossOver GM 27.0.0.41073 arm64/CrossOver Game.app"
OUT="$("$BIN" --game-mode-keep 2>&1)"
check '[ "$(readlink "$WT/ModeGame.exe")" = "$COPY/Contents/MacOS/ModeGame.exe" ] && [ "$(readlink "$WT/ModeGame-Win64-Shipping.exe")" = "$COPY/Contents/MacOS/ModeGame-Win64-Shipping.exe" ]' "each exe of a game gets a link in ntdll's folder for the loader, into the bundle"
check '[ "$COPY/Contents/MacOS/ModeGame.exe" -ef "$COPY/Contents/MacOS/wine" ]' "under the exe's name, the bundle's copy of the loader, so the Dock names the game"
check '[ -L "$WT/ModeGame.exe" ]' "ntdll's own link, in no bundle, is replaced"
check '[ "$(readlink "$WT/Other.exe")" = "$T/elsewhere/wine" ]' "a link of somebody else's is left alone"
check '[ ! -e "$WT/explorer.exe" ]' "Wine's own programs get none"
check '[ "$(plutil -extract CFBundleExecutable raw "$COPY/Contents/Info.plist")" = launcher ] && [ -x "$COPY/Contents/MacOS/launcher" ]' "the bundle's executable is a script, so the loader's own signature is not checked against the bundle"
check '[ "$(plutil -extract LSApplicationCategoryType raw "$COPY/Contents/Info.plist")" = public.app-category.games ] && cmp -s "$COPY/Contents/MacOS/wine" "$GW/x86_64-unix/wine" && [ "$COPY/Contents/MacOS/ntdll.so" -ef "$GW/x86_64-unix/ntdll.so" ]' "the bundle says it is a game and holds a copy of the loader beside a link to its ntdll.so"
WA="$T/tmp/winetemp-$(stat -f '%i-%z-%m' "$GW/aarch64-unix/wine.app/Contents/MacOS/wine")-$(stat -f '%.9Fm' "$GW/aarch64-unix/wine.app/Contents/MacOS/wine" | sed 's/.*\.//; s/^0*//; s/^$/0/')"
check '[ "$(readlink "$WA/ModeGame.exe")" = "$ARMCOPY/Contents/MacOS/ModeGame.exe" ] && cmp -s "$ARMCOPY/Contents/MacOS/wine" "$GW/aarch64-unix/wine.app/Contents/MacOS/wine"' "the FEX side's loader, in its wine.app, gets its own"
check '[ ! -e "$WT/NPGame.exe" ] && [ ! -e "$WA/NPGame.exe" ] && [ ! -e "$COPY/Contents/MacOS/NPGame.exe" ]' "a game in the Mac's own Steam is left to NotProton"
check '[ ! -d "$SUPPORT/MacGameFix/GameMode/CrossOver Old 25.0.0.1 x86_64" ] && ! has "$("$BIN" --game-mode-report 2>&1)" "25.0.0.1"' "a CrossOver of a release not checked gets nothing"
LINKED=$(for f in "$WT"/*; do to=$(readlink "$f" || true); if [ "${to#"$COPY/Contents/MacOS/"}" != "$to" ]; then echo; fi; done | wc -l | tr -d ' ')
check '[ "$LINKED" -ge 2 ] && has "$("$BIN" --game-mode-report 2>&1)" "| x86_64 | ${WT##*/} | $LINKED linked"' "the report counts the links on disk"
"$BIN" --game-mode-remove >/dev/null 2>&1
check '[ ! -e "$WT/ModeGame.exe" ] && [ ! -e "$WA/ModeGame.exe" ] && [ -L "$WT/Other.exe" ] && [ ! -d "$SUPPORT/MacGameFix/GameMode" ]' "turning it off takes every link of ours and the bundles away, and nothing else"
printf '{"kept":[],"updates":false,"modulesUpdates":false,"gameMode":true}' > "$SUPPORT/MacGameFix/automatic.json"
"$BIN" --agent-once >/dev/null 2>&1
check '[ "$(readlink "$WT/ModeGame.exe")" = "$COPY/Contents/MacOS/ModeGame.exe" ]' "with it on, the agent puts the links back"
"$BIN" --game-mode-remove >/dev/null 2>&1
printf '{"kept":[],"updates":false,"modulesUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"
"$BIN" --agent-once >/dev/null 2>&1
check '[ ! -e "$WT/ModeGame.exe" ]' "with it off, the agent does nothing"
unset MACGAMEFIX_TEMP_DIR
rm -rf "$GB" "$SUPPORT/Steam/steamapps/common/NP Game"

echo "== a newer MacGameFix"
# The app asked about is a copy of this build, so that what is replaced is the copy.
# The newer ones are this build too, with another version and signed again with the
# identity that signed it: without a Developer ID no copy replaces itself, and only
# that refusal is checked.
A="$T/app"
mkdir -p "$A/installed"
cp -R "$HERE/MacGameFix.app" "$A/installed/"
COPY="$A/installed/MacGameFix.app/Contents/MacOS/MacGameFix"
copyv() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$A/installed/MacGameFix.app/Contents/Info.plist"; }
AUTH="$(codesign -dvv "$HERE/MacGameFix.app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
variant() { # <name> <version> <identity>: a copy of the build under that version, signed
  mkdir -p "$A/$1"
  cp -R "$HERE/MacGameFix.app" "$A/$1/"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $2" -c "Set :CFBundleVersion $2" "$A/$1/MacGameFix.app/Contents/Info.plist"
  if [ "$3" = - ]; then codesign --force --deep --sign - "$A/$1/MacGameFix.app" >/dev/null 2>&1
  else codesign --force --options runtime --timestamp=none --sign "$3" "$A/$1/MacGameFix.app" >/dev/null 2>&1; fi
}
release() { # <name> <version GitHub names>: the folder's app as GitHub's latest release
  mkdir -p "$A/rel-$1"
  (cd "$A/$1" && ditto -c -k --norsrc --noextattr --keepParent MacGameFix.app "$A/rel-$1/MacGameFix-$2.zip")
  (cd "$A/rel-$1" && shasum -a 256 "MacGameFix-$2.zip" > "MacGameFix-$2.zip.sha256")
  /usr/bin/python3 - "$A/rel-$1" "$2" <<'PY'
import json, pathlib, sys
d, v = pathlib.Path(sys.argv[1]), sys.argv[2]
names = (f"MacGameFix-{v}.zip", f"MacGameFix-{v}.zip.sha256")
# The release's notes as they are written: a heading, items with a bold lead, nested ones.
body = f"## MacGameFix {v}\n\n### App\n\n- **One update for everything.** More words about it.\n  - A nested item.\n- A second thing. And more.\n"
json.dump({"tag_name": "v" + v, "html_url": f"https://example.invalid/releases/tag/v{v}", "body": body,
           "assets": [{"name": n, "browser_download_url": (d / n).as_uri()} for n in names]}, open(d / "release.json", "w"))
PY
}
appcheck() { MACGAMEFIX_APP_SOURCE="$A/rel-$1" "$COPY" --app-update-check 2>&1 || true; }
appupdate() { MACGAMEFIX_APP_SOURCE="$A/rel-$1" "$COPY" --app-update 2>&1 || true; }
appdue() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lastAppCheck"] = -1e9; json.dump(d, open(sys.argv[1], "w"))
PY
}
check 'has "$("$COPY" --app-update-check 2>&1)" "up to date ($APPV)"' "a release of this very version is nothing new"
if [ -z "$AUTH" ]; then
  variant new 9.9.9 -
  release new 9.9.9
  check 'has "$(appcheck new)" "available 9.9.9"' "a newer MacGameFix is found"
  check 'has "$(appupdate new)" "not signed with a Developer ID" && [ "$(copyv)" = "$APPV" ]' "a build signed ad hoc does not replace itself"
  check 'out="$(MACGAMEFIX_APP_SOURCE="$A/rel-new" "$COPY" --updates-report --downloaded 2>&1)"; has "$out" "notice | An update is available: MacGameFix 9.9.9." && has "$out" "button | none" && has "$out" "cannot | " && ! has "$out" "Relaunch"' "and its notice has no button: neither Update nor Relaunch"
  echo "  skip  this build has no Developer ID: the replacement itself is not checked"
else
  variant new 9.9.9 "$AUTH"
  release new 9.9.9
  check 'has "$(appcheck new)" "available 9.9.9"' "a newer MacGameFix is found"
  check 'has "$(appcheck new)" "brings One update for everything. A second thing."' "with what it brings, from the release's notes"
  # The agent says so once, the menu carries it, and with the setting off it does not look.
  printf '{"kept":[],"updates":false,"modulesUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"; appdue
  check 'has "$(MACGAMEFIX_APP_SOURCE="$A/rel-new" "$BIN" --agent-once 2>&1)" "MacGameFix 9.9.9 is available. Open MacGameFix to update. One update for everything. A second thing."' "the agent says so, and what it brings"
  check 'has "$(menu)" "app | Update to MacGameFix 9.9.9"' "and the menu offers it"
  appdue
  check '! has "$(MACGAMEFIX_APP_SOURCE="$A/rel-new" "$BIN" --agent-once 2>&1)" "is available"' "once for a version"
  appdue; "$BIN" --agent-once >/dev/null 2>&1
  check '! has "$(menu)" "app |"' "and no longer once the release is this version"
  printf '{"kept":[],"updates":false,"modulesUpdates":false,"appUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"; appdue
  check '! has "$(MACGAMEFIX_APP_SOURCE="$A/rel-new" "$BIN" --agent-once 2>&1)" "is available" && ! has "$(menu)" "app |"' "with the setting off, the agent does not look"
  printf '{"kept":[],"updates":false,"modulesUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"

  # The notice's one button. Relaunch is for a new MacGameFix alone, downloaded and
  # checked, with no catalog waiting; and then it is always there.
  notice() { MACGAMEFIX_APP_SOURCE="$A/rel-$1" "$COPY" --updates-report "${@:2}" 2>&1 || true; }
  fixeswait() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["available"] = int(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
PY
  }
  check 'out="$(notice new)"; has "$out" "notice | An update is available: MacGameFix 9.9.9." && has "$out" "button | Update" && ! has "$out" "Relaunch"' "a newer MacGameFix not yet downloaded is offered with Update"
  check 'out="$(notice new --downloaded)"; has "$out" "notice | MacGameFix 9.9.9 is ready. Relaunch to finish updating." && has "$out" "button | Relaunch"' "downloaded and checked, it has Relaunch"
  check '[ "$(copyv)" = "$APPV" ] && [ "$(ls "$A/installed")" = MacGameFix.app ]' "and nothing was put in the app's place before Relaunch"
  fixeswait 4999999999
  check 'out="$(notice new --downloaded)"; has "$out" "notice | An update is available: MacGameFix 9.9.9, new fixes." && has "$out" "button | Update" && ! has "$out" "Relaunch"' "with new fixes waiting beside it, Update comes first"
  check 'out="$("$COPY" --updates-report --downloaded 2>&1)"; has "$out" "notice | An update is available: new fixes." && has "$out" "button | Update" && ! has "$out" "Relaunch"' "new fixes alone never have Relaunch"
  fixeswait 0
  check 'has "$("$COPY" --updates-report --downloaded 2>&1)" "notice | none"' "and with nothing new there is no notice"

  # What is refused, and leaves the copy as it was.
  cp -R "$A/new" "$A/changed"; printf 'x' >> "$A/changed/MacGameFix.app/Contents/Resources/games.json"
  release changed 9.9.9
  check 'has "$(appupdate changed)" "not signed as MacGameFix is" && [ "$(copyv)" = "$APPV" ]' "an app changed after it was signed is refused"
  variant adhoc 9.9.9 -
  release adhoc 9.9.9
  check 'has "$(appupdate adhoc)" "not signed as MacGameFix is" && [ "$(copyv)" = "$APPV" ]' "one signed ad hoc is refused"
  check 'out="$(notice adhoc --downloaded)"; has "$out" "refused | " && has "$out" "button | Update" && ! has "$out" "Relaunch"' "and a download that was refused never has Relaunch"
  variant other 9.9.8 "$AUTH"
  release other 9.9.9
  mv "$A/rel-other/MacGameFix-9.9.9.zip" "$A/rel-other/x.zip"
  (cd "$A/other" && ditto -c -k --norsrc --noextattr --keepParent MacGameFix.app "$A/rel-other/MacGameFix-9.9.9.zip")
  (cd "$A/rel-other" && rm x.zip && shasum -a 256 MacGameFix-9.9.9.zip > MacGameFix-9.9.9.zip.sha256)
  check 'has "$(appupdate other)" "is MacGameFix 9.9.8, not 9.9.9" && [ "$(copyv)" = "$APPV" ]' "one of another version than the release names is refused"
  cp -R "$A/rel-new" "$A/rel-sum"
  /usr/bin/python3 - "$A/rel-sum" <<'PY'
import json, pathlib, sys
d = pathlib.Path(sys.argv[1]); r = json.load(open(d / "release.json"))
for a in r["assets"]: a["browser_download_url"] = (d / a["name"]).as_uri()
json.dump(r, open(d / "release.json", "w"))
(d / "MacGameFix-9.9.9.zip.sha256").write_text("0" * 64 + "  MacGameFix-9.9.9.zip\n")
PY
  check 'has "$(appupdate sum)" "does not match the release" && [ "$(copyv)" = "$APPV" ]' "a download that does not match the checksum is refused"
  check '[ "$(ls "$A/installed")" = MacGameFix.app ] && codesign --verify --deep --strict "$A/installed/MacGameFix.app" 2>/dev/null' "and every refusal left the app whole, with nothing beside it"

  # The service answers first; GitHub only when the service gives nothing that can be read.
  SUM="$(cut -d' ' -f1 "$A/rel-new/MacGameFix-9.9.9.zip.sha256")"
  /usr/bin/python3 - "$A" "$SUM" "$APPV" <<'PY'
import json, pathlib, sys
a, s, v = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
row = {"version": "9.9.9", "tag": "v9.9.9", "prerelease": False, "releaseUrl": "https://example.invalid/releases/tag/v9.9.9",
       "downloadUrl": (a / "rel-new" / "MacGameFix-9.9.9.zip").as_uri(), "sha256": s.upper(), "sizeBytes": 1, "minimumSystem": "14.0",
       "notes": "- **Said by the service.** And more."}
json.dump(row, open(a / "site-new.json", "w"))
json.dump(dict(row, version=v), open(a / "site-same.json", "w"))
json.dump(dict(row, downloadUrl="ftp://example.invalid/MacGameFix-9.9.9.zip"), open(a / "site-ftp.json", "w"))
(a / "site-broken.json").write_text("<html>502</html>")
PY
  check 'out="$(MACGAMEFIX_APP_SITE="$A/site-new.json" "$COPY" --app-update-check 2>&1)"; has "$out" "available 9.9.9" && has "$out" "brings Said by the service."' "the service's answer is taken, with what it says the version brings"
  check 'has "$(MACGAMEFIX_APP_SITE="$A/site-same.json" appcheck new)" "up to date"' "and GitHub is not asked when the service answers"
  check 'has "$(MACGAMEFIX_APP_SITE="$A/site-broken.json" appcheck new)" "available 9.9.9" && has "$(MACGAMEFIX_APP_SITE="$A/none.json" appcheck new)" "available 9.9.9"' "a service that answers nothing readable, or not at all, leaves the question to GitHub"
  check 'has "$(MACGAMEFIX_APP_SITE="$A/site-ftp.json" "$COPY" --app-update-check 2>&1)" "up to date"' "a download the service names over anything but HTTPS is not taken"

  # The service itself, as a stand-in on this Mac: a token for the app's client, then
  # the table with it. GitHub's stand-in is the release of this very version, so
  # "available" can only be the service's word.
  mkdir -p "$A/stub"
  cat > "$A/stub.py" <<'PY'
import http.server, json, pathlib, sys, urllib.parse
d = pathlib.Path(sys.argv[1]); row = pathlib.Path(sys.argv[2]).read_bytes(); issued = []
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def answer(self, status, body):
        self.send_response(status); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def note(self, line):
        with open(d / "log", "a") as f: f.write(line + "\n")
    def do_POST(self):
        form = urllib.parse.parse_qs(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
        good = (self.path == "/connect/token" and form.get("grant_type") == ["client_credentials"]
                and form.get("client_id") == ["Itsomax_MacGameFix_Updates"] and form.get("client_secret") == ["key+with a space"]
                and form.get("scope") == ["Itsomax.MacGameFix.AppReleases"])
        self.note("token " + ("given" if good else "refused"))
        if not good: return self.answer(401, b'{"error":"invalid_client"}')
        issued.append("tok-%d" % (len(issued) + 1))
        self.answer(200, json.dumps({"access_token": issued[-1], "token_type": "Bearer", "expires_in": 3600}).encode())
    def do_GET(self):
        held = self.headers.get("Authorization", "")
        if self.path != "/api/macgamefix/app-releases/latest": return self.answer(404, b"{}")
        if (d / "down").exists(): self.note("latest 500"); return self.answer(500, b'{"error":{}}')
        if (d / "expire").exists():
            (d / "expire").unlink(); self.note("latest 401"); return self.answer(401, b"")
        if not issued or held != "Bearer " + issued[-1]: self.note("latest 401"); return self.answer(401, b"")
        self.note("latest 200 " + self.headers.get("User-Agent", "") + (" cookie" if self.headers.get("Cookie") else ""))
        self.answer(200, row)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
(d / "port").write_text(str(s.server_address[1]))
s.serve_forever()
PY
  /usr/bin/python3 "$A/stub.py" "$A/stub" "$A/site-new.json" & STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$A/stub/port" ] && break; /bin/sleep 0.3; done
  STUB="http://127.0.0.1:$(cat "$A/stub/port")"
  asked() { MACGAMEFIX_UPDATES_BASE="$STUB" MACGAMEFIX_UPDATES_SECRET="$1" "$COPY" --app-update-check 2>&1 || true; }
  stublog() { tr '\n' ';' < "$A/stub/log"; : > "$A/stub/log"; }
  : > "$A/stub/log"
  check 'has "$(asked "key+with a space")" "available 9.9.9" && [ "$(stublog)" = "token given;latest 200 MacGameFix/$APPV;" ]' "the service is asked with a token for the app's client, and no cookie"
  touch "$A/stub/expire"
  check 'has "$(asked "key+with a space")" "available 9.9.9" && [ "$(stublog)" = "token given;latest 401;token given;latest 200 MacGameFix/$APPV;" ]' "a token the service refuses is asked for once more"
  check 'has "$(asked "another key")" "up to date" && [ "$(stublog)" = "token refused;" ]' "a key the service does not know is tried once, and leaves the question to GitHub"
  touch "$A/stub/down"
  check 'has "$(asked "key+with a space")" "up to date" && [ "$(stublog)" = "token given;latest 500;" ]' "and so does a service that fails"
  rm -f "$A/stub/down"
  # The address and key the build was given (Info.plist): asked when nothing else is
  # named, and left alone by a test that names its own release, as every test here
  # does, so that none of them reaches the real service.
  mkdir -p "$A/given"
  cp -R "$HERE/MacGameFix.app" "$A/given/"
  plutil -replace MacGameFixUpdatesBase -string "$STUB" "$A/given/MacGameFix.app/Contents/Info.plist"
  plutil -replace MacGameFixUpdatesSecret -string "key+with a space" "$A/given/MacGameFix.app/Contents/Info.plist"
  codesign --force --deep --sign - "$A/given/MacGameFix.app" >/dev/null 2>&1
  GIVEN="$A/given/MacGameFix.app/Contents/MacOS/MacGameFix"
  check 'has "$("$GIVEN" --app-update-check 2>&1)" "up to date" && [ -z "$(stublog)" ]' "a test that names its own release does not reach the address the build was given"
  check 'has "$(env -u MACGAMEFIX_APP_SOURCE "$GIVEN" --app-update-check 2>&1)" "available 9.9.9" && [ "$(stublog)" = "token given;latest 200 MacGameFix/$APPV;" ]' "and with none named, the build's own address and key are asked"
  check 'out="$(MACGAMEFIX_APP_SOURCE="$A/rel-new" "$GIVEN" --updates-report --downloaded 2>&1)"; has "$out" "notice | An update is available: MacGameFix 9.9.9." && has "$out" "button | none" && has "$out" "cannot | " && ! has "$out" "Relaunch"' "a copy that cannot replace itself has no button for the new MacGameFix: neither Update nor Relaunch"
  kill "$STUB_PID" 2>/dev/null; STUB_PID=0
  check 'has "$(asked "key+with a space")" "up to date"' "and one that is not there"

  # And the one that is taken.
  check 'has "$(MACGAMEFIX_APP_SITE="$A/site-new.json" "$COPY" --app-update 2>&1)" "installed 9.9.9" && [ "$(copyv)" = 9.9.9 ]' "a newer MacGameFix signed as this one is put in its place"
  check '[ "$(ls "$A/installed")" = MacGameFix.app ] && codesign --verify --deep --strict "$A/installed/MacGameFix.app" 2>/dev/null' "whole, with nothing left beside it"
  check 'has "$(appcheck new)" "up to date (9.9.9)"' "and it finds nothing newer than itself"
fi

[ "$fail" = 0 ] && echo "==> MacGameFix automation: the Wine modules and their own updates, signed catalogs taken automatically or asked first, what each game runs on, the agent's updates, waits and reports, a macOS game waiting for a recipe or refused by its installer, the menu bar's summary, a fix's report and its forms" || exit 1
