#!/usr/bin/env bash
# The automation, offline: the Wine modules put into a runner and taken out, a
# signed catalog taken or refused, and the agent
# keeping a marked fix applied across game updates, while Steam writes the game,
# while the game runs, and when the installer fails. Nothing here touches the
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
trap '[ "${GAME_PID:-0}" -gt 0 ] && kill "$GAME_PID" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
export MACGAMEFIX_HOME="$T/home"
# What the Steam store says of each app, saved: no test asks the network.
export MACGAMEFIX_STORE_DIR="$T/store"
mkdir -p "$MACGAMEFIX_STORE_DIR"
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
# Made for DXMT, with a codec only CrossOver Preview 27 ships; a second game
# whose fix writes registry keys; and a third whose DLLs go into the prefix, as
# NINJA GAIDEN 3's do.
cat > "$RES/games.json" <<'JSON'
{"games": [{"name": "Fake Game", "exe": "FakeGame.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "dxmt", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "CrossOver Preview 27", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Keys", "exe": "FakeKeys.exe", "carrierDir": "", "script": "install-fakekeys.sh",
  "needsPrefix": true, "symptom": "test", "backend": "d3dmetal", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Prefix", "exe": "FakePrefix.exe", "carrierDir": "", "script": "install-fakekeys.sh",
  "needsPrefix": true, "scope": "prefix", "symptom": "test", "backend": "dxvk", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "", "why": ""}]}
JSON
/usr/bin/python3 - "$RES" <<'PY'
import hashlib, json, pathlib, sys
res = pathlib.Path(sys.argv[1])
files = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in ("install-fake.sh", "install-fakekeys.sh", "games.json")}
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

echo "== the agent"
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

echo "== the controllers' options"
export MACGAMEFIX_PAD_LOG="$T/pad.log"
P="$SUPPORT/MacGameFix"
padwrite() { "$BIN" --pad-write >/dev/null 2>&1; }
padreport() { "$BIN" --pad-report 2>&1; }
padwrite
check '[ -f "$P/pad.json" ] && has "$(cat "$P/pad.conf")" "bluetooth=wired" && has "$(cat "$P/pad.conf")" "motor_power=full" && has "$(cat "$P/pad.conf")" "edge_haptics_gain_cable=2.00" && has "$(cat "$P/pad.conf")" "edge_haptics_gain_bluetooth=2.00" && has "$(cat "$P/pad.conf")" "haptics_gain_bluetooth=1.00"' "every game's options start as measured, in pad.conf"
check 'has "$(cat "$P/pad.d/1593500.conf")" "edge=dualsense" && ! has "$(cat "$P/pad.d/1593500.conf")" "bluetooth="' "a game with a preset gets its own file, with only what differs"
/usr/bin/python3 - "$P/pad.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); d["games"] = {"1593500": {"name": "God of War", "options": {"edgeAsDualSense": False}}, "4242": {"name": "Fake Game", "options": {"hapticsGain": 2.5}}, "4243": {"name": "Other Game", "options": {"hapticsGainBluetooth": 2}}, "4244": {"name": "XInput Game", "options": {"xinput": "off", "triggerR2": "weapon@6", "triggerL2": "rumble", "triggerR2WithL2": "weapon@8"}}}
json.dump(d, open(sys.argv[1], "w"))
PY2
padwrite
check '[ ! -f "$P/pad.d/1593500.conf" ]' "the user's own options win over a preset, and a game left as every game loses its file"
check 'has "$(cat "$P/pad.d/4242.conf")" "haptics_gain_cable=2.50" && has "$(cat "$P/pad.d/4242.conf")" "haptics_gain_bluetooth=2.50"' "a game's own gain, written with a point whatever the language; one gain from before counts for both connections"
check 'has "$(cat "$P/pad.d/4243.conf")" "haptics_gain_bluetooth=2.00" && ! has "$(cat "$P/pad.d/4243.conf")" "haptics_gain_cable="' "a gain over Bluetooth alone leaves the cable to every game's"
check 'has "$(cat "$P/pad.conf")" "xinput=rumble" && has "$(cat "$P/pad.conf")" "rumble=motors" && has "$(cat "$P/pad.conf")" "trigger_r2=off" && has "$(cat "$P/pad.d/4244.conf")" "xinput=off" && has "$(cat "$P/pad.d/4244.conf")" "trigger_r2=weapon@6" && has "$(cat "$P/pad.d/4244.conf")" "trigger_l2=rumble" && has "$(cat "$P/pad.d/4244.conf")" "trigger_r2_with_l2=weapon@8" && has "$(cat "$P/pad.conf")" "trigger_l2_with_r2=off"' "XInput's rumble for every game, triggers free; a game's own written as the modules read them, a second effect too"
check 'has "$(cat "$P/pad.d/4242.conf")" "xinput=pad" && has "$(cat "$(dirname "$P")/MacGameFix/pad.json")" "\"dualSense\" : false"' "a game the store does not list for the DualSense gets the pad as an XInput controller, and the answer is kept"
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
unset MACGAMEFIX_PAD_LOG

echo "== new fixes, asked first"
# A newer release of the same fake catalog, and the agent pointed at it.
cp -R "$RES" "$T/res2"
/usr/bin/python3 - "$T/res2/catalog.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["version"] = 4000000005; json.dump(d, open(sys.argv[1], "w"))
PY
"$BIN" --make-catalog "$T/release2" --key "$T/test.key" --from "$T/res2" >/dev/null
due() { /usr/bin/python3 - "$SUPPORT/MacGameFix/agent-state.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["lastUpdateCheck"] = -1e9; json.dump(d, open(sys.argv[1], "w"))
PY
}
waiting() { /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("available", 0))' "$SUPPORT/MacGameFix/agent-state.json"; }
newagent() { MACGAMEFIX_CATALOG_SOURCE="$T/release2" MACGAMEFIX_CATALOG_PUBKEY="$PUB" "$BIN" --agent-once 2>&1; }
before="$(readlink "$SUPPORT/MacGameFix/catalog/current")"
printf '{"kept":[],"updates":true,"askFirst":true}' > "$SUPPORT/MacGameFix/automatic.json"; due
check 'has "$(newagent)" "New fixes are ready (catalog 4000000005)" && [ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ] && [ "$(waiting)" = 4000000005 ]' "asked first, a newer catalog is offered and nothing is installed"
due
check '! has "$(newagent)" "New fixes are ready" && [ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ]' "and offered once"
printf '{"kept":[],"updates":false,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"; due
newagent >/dev/null
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = "$before" ]' "with updates off, the agent takes nothing"
printf '{"kept":[],"updates":true,"askFirst":false}' > "$SUPPORT/MacGameFix/automatic.json"; due
newagent >/dev/null
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000005 ] && [ "$(waiting)" = 0 ]' "automatic, it is installed and no longer waiting"

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
check '[ "$(readlink "$SUPPORT/MacGameFix/modules/current")" = 4000000010 ] && has "$OUT" "Wine modules put back in NotProton runner · CrossOver Preview 20261006" && ours "$R1"' "automatic: the modules' own catalog is taken, and the modules go back into a runner they were kept in"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000005 ]' "without touching the fixes' catalog"
for f in $MODS; do echo "CodeWeavers' updated $f" > "$R1/lib/wine/$f"; done
check 'has "$(modagent)" "put back in" && ours "$R1"' "after a CrossOver update they are put back"
R2="$(runner crossover-27.0.0.41069 20261007)"
check 'has "$(modagent)" "installed in the new NotProton runner · CrossOver Preview 20261007" && ours "$R2"' "a runner for a new CrossOver build gets them, since a runner has them"
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
check 'has "$OUT" "needs the Wine modules again" && ! ours "$APPDIR/Contents/SharedSupport/CrossOver"' "a CrossOver app is only reported, even on automatic"
for f in $MODS; do echo "CodeWeavers' $f" > "$R1/lib/wine/$f"; done
settings true "[\"$R1\"]" "[]"
OUT="$(modagent)"
check 'has "$OUT" "needs the Wine modules again" && ! ours "$R1"' "asked first, a runner is reported and left as it is"
settings false "[\"$R1\"]" "[]"
printf '{"kept":[],"updates":false,"modulesUpdates":false}' > "$SUPPORT/MacGameFix/automatic.json"
modagent >/dev/null
check '! ours "$R1"' "with the Wine modules off, nothing is done"

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
MG="$SUPPORT/Steam/steamapps/common/Mode Game"
mkdir -p "$MG/Binaries/Win64" "$T/tmp"
: > "$MG/ModeGame.exe"; : > "$MG/Binaries/Win64/ModeGame-Win64-Shipping.exe"; : > "$MG/Other.exe"; : > "$MG/explorer.exe"
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

[ "$fail" = 0 ] && echo "==> MacGameFix automation: the Wine modules and their own updates, signed catalogs taken automatically or asked first, what each game runs on, the agent's updates, waits and reports, the menu bar's summary" || exit 1
