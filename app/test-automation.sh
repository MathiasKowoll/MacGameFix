#!/usr/bin/env bash
# The automation, offline: a signed catalog taken or refused, and the agent
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
T="$(mktemp -d)"
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

# A catalog with one fake fix: a marker in the game folder, or a failure when
# the folder holds FAIL.
RES="$T/res"
mkdir -p "$RES"
cat > "$RES/install-fake.sh" <<'SH'
#!/bin/bash
dir="$1"
case "${2:-}" in
  --status) [ -f "$dir/fixed.marker" ] && echo installed || echo absent; exit 0 ;;
  --restore) rm -f "$dir/fixed.marker"; exit 0 ;;
esac
echo "installing into $dir"
if [ -f "$dir/FAIL" ]; then echo "cannot write $dir/fake.dll"; exit 1; fi
touch "$dir/fixed.marker"
SH
# Made for DXMT, with a codec only CrossOver Preview 27 ships.
cat > "$RES/games.json" <<'JSON'
{"games": [{"name": "Fake Game", "exe": "FakeGame.exe", "carrierDir": "", "script": "install-fake.sh",
  "needsPrefix": false, "symptom": "test", "backend": "dxmt", "gptk": "", "gptkAlso": "",
  "codecShippedBy": "CrossOver Preview 27", "engineFreeOn": "", "notNeededFrom": "", "why": ""}]}
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
printf '"InstallConfigStore"\n{\n "Software"\n {\n  "Valve"\n  {\n   "Steam"\n   {\n    "CompatToolMapping"\n    {\n     "4242"\n     {\n      "name" "notproton-test"\n     }\n    }\n   }\n  }\n }\n}\n' > "$STEAM/config/config.vdf"
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

[ "$fail" = 0 ] && echo "==> MacGameFix automation: signed catalogs, what each game runs on, the agent's updates, waits and reports, the menu bar's summary" || exit 1
