#!/usr/bin/env bash
# Test the report's serialization without game installations or a GUI.
# Pass --integration after build-app.sh to test discovery in an isolated home.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
cat > "$TEMP/Test.swift" <<'SWIFT'
import Foundation
@main enum Test {
    static func main() throws {
        let name = "Game | \"quoted\"\nsecond line"
        let report = GamesReport(appVersion: "test", games: [.init(name: name,
            executable: "game.exe", requirement: "D3DMetal", manualInstall: false,
            needsPrefix: true, prefixCount: 2)])
        let data = try report.encoded()
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(root["schemaVersion"] as? Int == 1)
        precondition(root["appVersion"] as? String == "test")
        let game = (root["games"] as! [[String: Any]])[0]
        precondition(game["name"] as? String == name)
        precondition(game["prefixCount"] as? Int == 2)
        precondition(Set(game.keys) == Set(["name", "executable", "requirement", "manualInstall", "needsPrefix", "prefixCount"]))
        let empty = try GamesReport(appVersion: "test", games: []).encoded()
        let object = try JSONSerialization.jsonObject(with: empty) as! [String: Any]
        precondition((object["games"] as! [Any]).isEmpty)
        let secondEncoding = try report.encoded()
        precondition(data == secondEncoding)
        print("games-report-json serialization checks passed")
    }
}
SWIFT
swiftc "$HERE/GamesReport.swift" "$TEMP/Test.swift" -parse-as-library -o "$TEMP/test"
"$TEMP/test"

if [[ "${1:-}" == "--integration" ]]; then
    BIN="$HERE/MacGameFix.app/Contents/MacOS/MacGameFix"
    [[ -x "$BIN" ]] || { echo "build MacGameFix.app first (build-app.sh)" >&2; exit 1; }
    export MACGAMEFIX_HOME="$TEMP/home"
    mkdir -p "$MACGAMEFIX_HOME"
    "$BIN" --games-report-json > "$TEMP/empty.json"
    GAME="$MACGAMEFIX_HOME/Library/Application Support/Steam/steamapps/common/The Witcher 3/bin/x64_dx12"
    mkdir -p "$GAME"
    touch "$GAME/witcher3.exe"
    "$BIN" --games-report-json > "$TEMP/game.json"
    python3 - "$TEMP/empty.json" "$TEMP/game.json" "$MACGAMEFIX_HOME" <<'PY'
import json, pathlib, sys
empty = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert empty['schemaVersion'] == 1 and empty['games'] == []
text = pathlib.Path(sys.argv[2]).read_text()
report = json.loads(text)
assert report['schemaVersion'] == 1
assert any(g['executable'] == 'witcher3.exe' for g in report['games'])
assert sys.argv[3] not in text
assert all(set(g) == {'name', 'executable', 'requirement', 'manualInstall', 'needsPrefix', 'prefixCount'} for g in report['games'])
print('games-report-json isolated discovery checks passed')
PY
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :MacGameFixGamesReportSchemaVersion' "$HERE/MacGameFix.app/Contents/Info.plist")" == 1 ]]
fi
