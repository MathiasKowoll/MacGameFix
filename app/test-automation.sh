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
  printf '"AppState"\n{\n\t"appid"\t\t"4242"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"Fake Game"\n\t"buildid"\t\t"%s"\n}\n' "$2" "$1" > "$MANIFEST"
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
ENGINE_FILES="x86_64-windows/winebus.sys x86_64-windows/mmdevapi.dll x86_64-unix/winecoreaudio.so
  aarch64-windows/winebus.sys aarch64-windows/mmdevapi.dll aarch64-unix/winecoreaudio.so"
for f in $ENGINE_FILES; do echo "CodeWeavers' $f" > "$RUNNER/lib/wine/$f"; done
engine() { "$BIN" --engine-report 2>&1 | grep -F "runner $1 |" || true; }
check 'has "$(engine crossover-27.0.0.41069-fex)" "| fex | absent"' "a runner of a carried build, both sides, is absent"
check 'has "$(engine crossover-27.0.0.1-fex)" "noModules"' "a runner of a build with no modules says so"
"$BIN" --engine-install "$RUNNER" >/dev/null 2>&1 || true
same=1
for f in $ENGINE_FILES; do
  cmp -s "$RUNNER/lib/wine/$f" "$HERE/MacGameFix.app/Contents/Resources/engine-27.0.0.41069-$(printf '%s' "$f" | tr / -)" || same=0
done
check '[ "$same" = 1 ] && has "$(engine crossover-27.0.0.41069-fex)" "installed"' "installing puts both sides' modules in"
check '[ "$(cat "$SUPPORT/MacGameFix/engine-backup/crossover-27.0.0.41069-fex/x86_64-windows/winebus.sys")" = "CodeWeavers'"'"' x86_64-windows/winebus.sys" ]' "and keeps CrossOver's own"
printf 'x wine-11.0-1 x' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
check 'has "$(engine crossover-27.0.0.41069-fex)" "noModules"' "a runner whose Wine is not the build's is refused"
printf 'x wine-11.17-8909 x' > "$RUNNER/lib/wine/x86_64-unix/ntdll.so"
"$BIN" --engine-remove "$RUNNER" >/dev/null 2>&1 || true
check '[ "$(cat "$RUNNER/lib/wine/aarch64-unix/winecoreaudio.so")" = "CodeWeavers'"'"' aarch64-unix/winecoreaudio.so" ] && has "$(engine crossover-27.0.0.41069-fex)" "absent"' "removing puts CrossOver's own back"
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
# Made for DXMT, with a codec only CrossOver Preview 27 ships; and a second
# game made for D3DMetal whose fix D3DMetal 4.0b3 makes unnecessary.
cat > "$RES/games.json" <<'JSON'
{"games": [{"name": "Fake Game", "exe": "FakeGame.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "dxmt", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "CrossOver Preview 27", "engineFreeOn": "", "notNeededFrom": "", "why": ""},
 {"name": "Fake Two", "exe": "FakeTwo.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "d3dmetal", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "", "engineFreeOn": "", "notNeededFrom": "4.0b3", "why": ""}]}
JSON
/usr/bin/python3 - "$RES" <<'PY'
import hashlib, json, pathlib, sys
res = pathlib.Path(sys.argv[1])
files = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in ("install-fake.sh", "games.json")}
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

# What the game runs on, as Steam and NotProton would leave it: Steam maps the
# game to a NotProton tool, the tool names its CrossOver build, the runner
# carries D3DMetal, NotProton has run the game, and its launch options pick
# the backend.
STEAM="$SUPPORT/Steam"
mkdir -p "$STEAM/config" "$STEAM/compatibilitytools.d/notproton-test" "$STEAM/steamapps/compatdata/4242" \
  "$STEAM/userdata/1/config"
printf '"InstallConfigStore"\n{\n "Software"\n {\n  "Valve"\n  {\n   "Steam"\n   {\n    "CompatToolMapping"\n    {\n     "4242"\n     {\n      "name" "notproton-test"\n     }\n     "4343"\n     {\n      "name" "notproton-test"\n     }\n    }\n   }\n  }\n }\n}\n' > "$STEAM/config/config.vdf"
mkdir -p "$STEAM/steamapps/common/Fake Two" "$STEAM/steamapps/compatdata/4343"
touch "$STEAM/steamapps/common/Fake Two/FakeTwo.exe" "$STEAM/steamapps/compatdata/4343/notproton-run.log"
printf '"AppState"\n{\n\t"appid"\t\t"4343"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Fake Two"\n\t"buildid"\t\t"1"\n}\n' > "$STEAM/steamapps/appmanifest_4343.acf"
echo 27.0.0.41069-fex > "$STEAM/compatibilitytools.d/notproton-test/build"
echo rosetta > "$STEAM/compatibilitytools.d/notproton-test/flavor"
touch "$STEAM/steamapps/compatdata/4242/notproton-run.log"
GPTK="$SUPPORT/notproton/runners/crossover-27.0.0.41069-fex/CrossOver/lib/apple_gptk/external/D3DMetal.framework/Versions/A/Resources"
mkdir -p "$GPTK"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 4.0b3' "$GPTK/Info.plist" >/dev/null
options() { # launch options for the game
  printf '"UserLocalConfigStore"\n{\n "Software"\n {\n  "Valve"\n  {\n   "Steam"\n   {\n    "Apps"\n    {\n    }\n    "apps"\n    {\n     "4242"\n     {\n      "LaunchOptions" "%s"\n     }\n    }\n   }\n  }\n }\n}\n' "$1" > "$STEAM/userdata/1/config/localconfig.vdf"
}
report() { "$BIN" --runtime-report 2>&1; }
line() { report | /usr/bin/grep "^$1 |" || true; }

echo "== what the game runs on"
options 'CX_GRAPHICS_BACKEND=dxmt %command%'
steam 1 4
R="$(report)"
check 'has "$R" "Fake Game | CrossOver Preview 27, D3DMetal 4.0b3, DXMT — NotProton, notproton-test" && has "$R" "| Fits what this game runs on"' "a NotProton game: its build, D3DMetal and backend, and the fix fits"
options 'CX_GRAPHICS_BACKEND=d3dmetal %command%'
check 'has "$(report)" "Does not fit: made for DXMT, and this game runs on D3DMetal"' "the wrong backend does not fit"
options '%command%'
check 'has "$(report)" "Does not fit: made for DXMT, and this game runs on D3DMetal, the automatic backend"' "an automatic backend is D3DMetal"
echo 26.3.0.39832 > "$STEAM/compatibilitytools.d/notproton-test/build"
options 'CX_GRAPHICS_BACKEND=dxmt %command%'
check 'has "$(report)" "Does not fit: needs CrossOver Preview 27; this is CrossOver 26.3"' "an older CrossOver does not fit a codec it lacks"
echo 27.0.0.41069-fex > "$STEAM/compatibilitytools.d/notproton-test/build"
check 'has "$(line "Fake Two")" "Not needed: the game plays without it on D3DMetal 4.0b3 and later"' "a fix this D3DMetal makes unnecessary says so"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 4.0b2' "$GPTK/Info.plist"
check 'has "$(line "Fake Two")" "Fits what this game runs on"' "and on an older D3DMetal it fits"
mv "$GPTK/Info.plist" "$GPTK/Info.plist.away"
check 'has "$(line "Fake Two")" "Cannot tell: not needed from D3DMetal 4.0b3 on, and which D3DMetal this is is not known"' "when the D3DMetal version cannot be read, the user is asked"
mv "$GPTK/Info.plist.away" "$GPTK/Info.plist"; /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 4.0b3' "$GPTK/Info.plist"

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

echo "== the agent and what the game runs on"
rm -f "$GAME/FAIL" "$GAME/fixed.marker"; options 'CX_GRAPHICS_BACKEND=d3dmetal %command%'; steam 6 4
OUT="$(agent)"
check 'has "$OUT" "ok Fake Game: Not applied. Does not fit" && [ ! -f "$GAME/fixed.marker" ]' "a fix that does not fit is not applied, and it is said"
check '[ -z "$(agent)" ]' "and said once"
check 'has "$(menu)" "summary | 1 left alone: the fix does not fit"' "the menu bar counts it as left alone"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false,"runtimes":{"%s|Fake Game":{"source":"your choice","build":"27.0.0.41069","backend":"dxmt","noD3DMetal":false,"setUpHere":false}}}' "$GAME" "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
check 'has "$(report)" "You said" || has "$(report)" "your choice"' "the user's word on what the game runs on wins over detection"
check 'has "$(agent)" "back in place" && [ -f "$GAME/fixed.marker" ]' "and once the user says it fits, the agent applies it"
check 'has "$(menu)" "summary | 1 in place"' "and the menu bar counts it in place"
printf '{"kept":[{"name":"Fake Game","folder":"%s"},{"name":"Gone Game","folder":"%s"}],"updates":false}' "$GAME" "$T/gone" > "$SUPPORT/MacGameFix/automatic.json"
OUT="$(menu)"
check 'has "$OUT" "summary | 1 to review" && has "$OUT" "Gone Game | Folder not found"' "a marked game whose folder is gone is to review"

echo "== an older build of a fix"
printf '{"kept":[{"name":"Fake Game","folder":"%s"}],"updates":false,"runtimes":{"%s|Fake Game":{"source":"your choice","build":"27.0.0.41069","backend":"dxmt","noD3DMetal":false,"setUpHere":false}}}' "$GAME" "$GAME" > "$SUPPORT/MacGameFix/automatic.json"
echo 1 > "$GAME/fixed.marker"; steam 7 4
check 'has "$(agent)" "ok Fake Game: The fix is updated to the newer build." && [ "$(cat "$GAME/fixed.marker")" = 2 ]' "an older build in the game folder is replaced with the catalog's"

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
runner() { # a fake runner with CodeWeavers' files: <folder name>
  local r="$SUPPORT/notproton/runners/$1/CrossOver"
  mkdir -p "$r/lib/wine/x86_64-unix" "$r/lib/wine/x86_64-windows"
  printf 'x wine-11.17-8909 x' > "$r/lib/wine/x86_64-unix/ntdll.so"
  for f in $MODS; do echo "CodeWeavers' $f" > "$r/lib/wine/$f"; done
  printf '%s' "$r"
}
ours() { [ "$(cat "$1/lib/wine/x86_64-windows/winebus.sys")" = "module x86_64-windows/winebus.sys" ]; }
settings() { # modulesAskFirst, kept list, declined list (JSON)
  printf '{"kept":[],"updates":false,"modulesUpdates":true,"modulesAskFirst":%s,"modulesKept":%s,"modulesDeclined":%s}' "$1" "$2" "$3" \
    > "$SUPPORT/MacGameFix/automatic.json"
}
R1="$(runner crossover-27.0.0.41069-fex)"
settings false "[\"$R1\"]" "[]"; mdue
OUT="$(modagent)"
check '[ "$(readlink "$SUPPORT/MacGameFix/modules/current")" = 4000000010 ] && has "$OUT" "Wine modules put back in NotProton runner crossover-27.0.0.41069-fex" && ours "$R1"' "automatic: the modules' own catalog is taken, and the modules go back into a runner they were kept in"
check '[ "$(readlink "$SUPPORT/MacGameFix/catalog/current")" = 4000000005 ]' "without touching the fixes' catalog"
for f in $MODS; do echo "CodeWeavers' updated $f" > "$R1/lib/wine/$f"; done
check 'has "$(modagent)" "put back in" && ours "$R1"' "after a CrossOver update they are put back"
R2="$(runner crossover-27.0.0.41069)"
check 'has "$(modagent)" "installed in the new NotProton runner crossover-27.0.0.41069" && ours "$R2"' "a runner for a new CrossOver build gets them, since a runner has them"
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

[ "$fail" = 0 ] && echo "==> MacGameFix automation: the Wine modules and their own updates, signed catalogs taken automatically or asked first, what each game runs on, the agent's updates, waits and reports, the menu bar's summary" || exit 1
