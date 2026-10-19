#!/usr/bin/env bash
# Build MacGameFix.app: the game-folder fixes, and nothing that patches CrossOver.
#
# It carries only the fixes that live entirely in a game's own folder -- a proxy
# DLL beside the game, plus registry keys in the game's own prefix for the titles
# that need them -- so it works with a CrossOver as CodeWeavers shipped it, with
# CrossOver Preview, and with a Steam Play tool such as NotProton. Nothing here
# touches an engine.
#
# WHICH GAMES, GATHERED AND NOT LISTED. A written-out list is the thing that went
# stale in the controller app twice. A title is in when all of this holds:
#
#   - an installer under fixes/ names it on an MGVF-GAME line, and declares
#     MGVF-SCOPE: folder
#   - process-features.json, generated from the wiki's own table, gives it no
#     codec -- a staged GStreamer plugin goes INTO the engine -- or names, in
#     codec_shipped_by, a CrossOver that already carries that codec as
#     CodeWeavers ships it; the app then says which one
#   - and no needs_engine -- the table's Motor column, which is what says a fix
#     depends on a winegstreamer of MacGameVideoFix's or winevideo's -- or names, in
#     engine_not_needed_on, a CrossOver where it was measured needing none
#
# So a fix that later stops needing the engine arrives here on its own, and one
# that starts needing it leaves.
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
APP="$HERE/MacGameFix.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
CACHE="${TMPDIR:-/tmp}/mgf-swift-cache"
VERSION="1.5.2"
# The oldest app that can use the catalog this build writes: the first with a
# catalog it can take from a release.
CATALOG_MIN_APP="1.4.0"
# The Wine modules' catalog came with 1.5.0.
MODULES_MIN_APP="1.5.0"
# The private half of the key whose public half Automation.swift carries. It
# never enters the repository; without it the build writes no release catalog.
SIGNING_KEY="${MACGAMEFIX_SIGNING_KEY:-$HOME/.config/macgamefix/catalog-signing.key}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> choosing the games"
# games.json is the app's whole table: one row per title, with the installer
# that serves it. Written by python3 from the two sources above; a title the
# rules keep out is named on the way, so the build says what it left behind.
/usr/bin/python3 - "$ROOT" "$STAGE/games.json" <<'PY'
import json, re, sys, pathlib
root, out = pathlib.Path(sys.argv[1]), sys.argv[2]
procs = json.loads((root / "process-features.json").read_text())["processes"]
games, left = [], []
for script in sorted((root / "fixes").glob("install-*.sh")):
    text = script.read_text()
    scope = re.search(r"^# MGVF-SCOPE: (\S+)", text, re.M)
    why = re.search(r"^# MGVF-WHY: (.*)$", text, re.M)
    for m in re.finditer(r"^# MGVF-GAME: (.*?) \| (.*?) \|(.*)$", text, re.M):
        # An optional fourth field names the other executables the title runs as
        # (MK11.exe beside MK11_DX12.exe), so the app knows it is running either way.
        rest = m.group(3).split("|")
        name, exe, carrier = m.group(1).strip(), m.group(2).strip(), rest[0].strip()
        also = [x.strip() for x in rest[1].split(",") if x.strip()] if len(rest) > 1 else []
        p = procs.get(exe)
        reason = None
        if not scope or scope.group(1) != "folder":
            reason = "not a game-folder fix"
        elif p is None:
            reason = "not in process-features.json"
        elif p.get("codec") and not p.get("codec_shipped_by"):
            reason = "needs " + p["codec"] + " inside the engine"
        elif p.get("needs_engine") and not p.get("engine_not_needed_on"):
            reason = "needs a winegstreamer carrying " + p["needs_engine"]
        if reason:
            left.append((name, reason)); continue
        games.append({
            "name": name,
            "exe": exe,
            "alsoRuns": also,
            "carrierDir": carrier,
            "script": script.name,
            # The one installer that writes registry keys sources bottles.sh to
            # find where; the app has to name that place for it.
            "needsPrefix": ". \"$HERE/bottles.sh\"" in text,
            "symptom": p.get("symptom", ""),
            "backend": p.get("backend", ""),
            "gptk": p.get("gptk", ""),
            "gptkAlso": p.get("gptk_also", ""),
            # Empty for a title that needs no codec. For one that does, the
            # CrossOver that ships it, which is then the only one it plays on.
            "codecShippedBy": p.get("codec_shipped_by", "") if p.get("codec") else "",
            # A title whose engine requirement holds on stable 26.3 and not on
            # the CrossOver named here, which then is the one it plays on.
            "engineFreeOn": p.get("engine_not_needed_on", "") if p.get("needs_engine") else "",
            # The toolkit from which this title plays without its fix at all.
            "notNeededFrom": p.get("not_needed_from_gptk", ""),
            "why": why.group(1).strip() if why else "",
        })
games.sort(key=lambda g: g["name"].lower())
json.dump({"games": games}, open(out, "w"), indent=2)
for g in games:
    print(f"    in   {g['name']}")
for name, reason in left:
    print(f"    out  {name}: {reason}")
if not games:
    sys.exit("error: no game qualified; the rules above found nothing to carry")
PY

# The payload is every file the chosen installers name as $HERE/<name>, plus the
# installers themselves. Read from the scripts, so a helper an installer starts
# to use is carried without anybody remembering to add it here.
SCRIPTS=()
while IFS= read -r s; do SCRIPTS+=("$s"); done < <(
  /usr/bin/python3 -c 'import json,sys; print("\n".join(sorted({g["script"] for g in json.load(open(sys.argv[1]))["games"]})))' "$STAGE/games.json")
PAYLOAD=()
for s in "${SCRIPTS[@]}"; do
  PAYLOAD+=("$s")
  while IFS= read -r want; do PAYLOAD+=("$want"); done < <(
    grep -oE '\$HERE/[A-Za-z0-9._-]+' "$ROOT/fixes/$s" | sed 's|\$HERE/||' | sort -u)
done
PAYLOAD=($(printf '%s\n' "${PAYLOAD[@]}" | sort -u))

missing=0
for f in "${PAYLOAD[@]}"; do
  [ -e "$ROOT/fixes/$f" ] || { echo "error: fixes/$f is missing, and an installer here names it" >&2; missing=1; }
done
[ "$missing" = 0 ] || exit 1

rm -rf "$APP"
mkdir -p "$MACOS" "$RES" "$CACHE"

echo "==> compiling"
swiftc "$HERE/Core.swift" "$HERE/Engine.swift" "$HERE/Pad.swift" "$HERE/PadTester.swift" "$HERE/Automation.swift" "$HERE/MenuBar.swift" "$HERE/MacGameFix.swift" -O -parse-as-library \
  -o "$MACOS/MacGameFix" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework UserNotifications -framework GameController \
  -framework AVFoundation -framework CoreAudio -framework AudioToolbox \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$CACHE"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacGameFix</string>
  <key>CFBundleDisplayName</key><string>MacGameFix</string>
  <key>CFBundleIdentifier</key><string>io.github.macgamefix</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>MacGameFix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST

# RaccoonBot's raccoon, the same one the menu bar draws. AppIcon.icon is the
# Icon Composer source; with Xcode's actool it becomes Assets.car (the icon
# macOS 26 and later show) and AppIcon.icns. Without Xcode, the committed
# AppIcon.icns, which actool made from the same source.
echo "==> icon"
if ACTOOL="$(xcrun --find actool 2>/dev/null)" && [ -d "$HERE/AppIcon.icon" ]; then
  "$ACTOOL" "$HERE/AppIcon.icon" --compile "$RES" --app-icon AppIcon \
    --output-partial-info-plist "$CACHE/icon-partial.plist" --platform macosx \
    --minimum-deployment-target 14.0 --development-region en > /dev/null
elif [ -f "$HERE/AppIcon.icns" ]; then
  cp "$HERE/AppIcon.icns" "$RES/AppIcon.icns"
else
  echo "    note: app/AppIcon.icns is missing, so this build has no icon"
fi

# The app is GPL-3.0-or-later, and the licence travels with it.
cp "$ROOT/LICENSE" "$RES/LICENSE"

echo "==> bundling ${#PAYLOAD[@]} files"
for f in "${PAYLOAD[@]}"; do
  cp -a "$ROOT/fixes/$f" "$RES/$f"
done
for s in "${SCRIPTS[@]}"; do chmod +x "$RES/$s"; done
cp "$STAGE/games.json" "$RES/games.json"
# The Controllers tab's presets: options measured per title.
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$HERE/pad-presets.json" || { echo "pad-presets.json is not valid JSON"; exit 1; }
cp "$HERE/pad-presets.json" "$RES/pad-presets.json"

# The Wine modules (engine/): their installer, and every built module with
# engine-modules.json, as bundle-engine.py lays them out.
echo "==> Wine modules"
cp -a "$ROOT/engine/engine-modules.sh" "$RES/engine-modules.sh"
ENGINE=(engine-modules.sh engine-modules.json)
/usr/bin/python3 "$HERE/bundle-engine.py" "$ROOT/engine/modules" "$RES" > "$STAGE/engine-names"
while IFS= read -r n; do ENGINE+=("$n"); done < "$STAGE/engine-names"
[ -f "$RES/engine-modules.json" ] || { echo "error: the Wine modules could not be bundled" >&2; exit 1; }
echo "    ${#ENGINE[@]} files"

# catalog.json and modules.json: what each catalog is -- built now, so a newer
# build wins -- and every file with its hash. The agent compares a release's
# catalogs with them, each on its own: the game fixes, and the Wine modules.
manifest() { # <name> <minimum app> <files...>
  /usr/bin/python3 - "$RES" "$@" <<'PY'
import hashlib, json, pathlib, sys, time
res, out, minimum, names = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4:]
files = {n: hashlib.sha256((res / n).read_bytes()).hexdigest() for n in names}
json.dump({"version": int(time.time()), "minimumApp": minimum, "files": files},
          open(res / out, "w"), indent=2, sort_keys=True)
PY
}
manifest catalog.json "$CATALOG_MIN_APP" games.json "${PAYLOAD[@]}"
manifest modules.json "$MODULES_MIN_APP" "${ENGINE[@]}"

echo "==> signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "    note: ad-hoc signing failed; the app still runs after Right click > Open"

# The payload must be byte for byte what fixes/ holds, for the reason the other
# two apps check it: a copy taken from a build outlives the build it came from.
for f in "${PAYLOAD[@]}"; do
  cmp -s "$ROOT/fixes/$f" "$RES/$f" || { echo "error: $f in the bundle differs from fixes/$f" >&2; exit 1; }
done
cmp -s "$ROOT/engine/engine-modules.sh" "$RES/engine-modules.sh" \
  || { echo "error: engine-modules.sh in the bundle differs from engine/" >&2; exit 1; }
echo "==> the payload is byte-identical to fixes/ and engine/"

# The release's catalog: catalog.zip, catalog.json and its signature, for the
# agent of every installed MacGameFix to take without a new app.
if [ -f "$SIGNING_KEY" ]; then
  rm -rf "$HERE/dist"
  "$MACOS/MacGameFix" --make-catalog "$HERE/dist" --key "$SIGNING_KEY"
  echo "==> release catalogs in $HERE/dist: attach catalog.zip, catalog.json, catalog.json.sig, modules.zip,"
  echo "    modules.json and modules.json.sig to the release"
else
  echo "    note: no signing key at $SIGNING_KEY, so no release catalog; installed apps keep theirs"
fi
echo
echo "built: $APP"
