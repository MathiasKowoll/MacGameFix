#!/bin/bash
# Has Apple notarise MacGameFix.app, staples the ticket to it, and writes the
# release's app assets.
#
#   app/notarize.sh [--dry-run] [<app>] [<folder>]
#
# <app> is app/MacGameFix.app, built by build-app.sh with a Developer ID, unless
# another is named. The assets, MacGameFix-<version>.zip and
# MacGameFix-<version>.zip.sha256, go into <folder>, app/dist by default, beside
# the catalogs build-app.sh writes there. The credentials are a notarytool
# keychain profile, made once with xcrun notarytool store-credentials:
# $MACGAMEFIX_NOTARY_PROFILE, itsomax-desktop-notary unless set.
#
#   1. The app is checked first: codesign --verify --deep --strict, and every
#      Mach-O in it signed with the app's own team's Developer ID, a secure
#      timestamp and the hardened runtime (tools/check-signatures.sh). Apple
#      asks the first two of every Mach-O and the runtime of the executables;
#      MacGameFix puts it on every Mach-O so that all are signed one way, and
#      sends nothing signed otherwise.
#   2. It is zipped as the release is, ditto -c -k --norsrc --noextattr
#      --keepParent, and sent with notarytool submit --wait. The submission's id
#      is printed as soon as Apple answers with one.
#   3. Accepted: the ticket is stapled to the app, xcrun stapler validate and
#      spctl -a -vv -t exec must accept it, and the app is zipped again, ticket
#      and all, into the assets; the zip is unpacked once more to check that the
#      copy in it validates too. Only then do the assets replace the ones in
#      <folder>: a failure anywhere leaves <folder> as it was.
#      Invalid or Rejected: Apple's log is fetched into <folder>/notary-<id>.json,
#      its issues are printed, and this fails.
#      Apple's 403 for an agreement the team has not accepted: it says so in a
#      sentence, and stops.
# --dry-run does step 1 and the zip, says what it would send, and stops there:
# nothing reaches Apple.
#
# xcrun and spctl are taken from PATH, so app/test-notarize.sh can put fakes of
# both first and walk every answer Apple gives without sending anything.
#
# Exit status: 0 notarised (or a dry run that would send), 1 refused or failed,
# 2 a wrong argument, 3 the agreement.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
PROFILE="${MACGAMEFIX_NOTARY_PROFILE:-itsomax-desktop-notary}"

DRY=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) sed -n '5p' "$0"; exit 2 ;;
    *) ARGS+=("$a") ;;
  esac
done
[ "${#ARGS[@]}" -le 2 ] || { sed -n '5p' "$0"; exit 2; }
APP="${ARGS[0]:-$HERE/MacGameFix.app}"
OUT="${ARGS[1]:-$HERE/dist}"
APP="${APP%/}"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -d "$APP/Contents" ] || die "$APP is not an app; build it first (app/build-app.sh)"
APP="$(cd "$APP" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP/Contents/Info.plist" 2>/dev/null)"
[ -n "$VERSION" ] && [ -n "$NAME" ] || die "$APP/Contents/Info.plist has no CFBundleName or CFBundleShortVersionString"
ASSET="$NAME-$VERSION.zip"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. An app not signed as step 1 above says is refused here.
say "==> checking $(basename "$APP") $VERSION"
codesign --verify --deep --strict "$APP" 2> "$WORK/verify" \
  || { sed 's/^/    /' "$WORK/verify" >&2; die "$(basename "$APP") does not verify"; }
TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
case "$TEAM" in
  ""|"not set") die "$(basename "$APP") is signed ad hoc; build it with a Developer ID (app/build-app.sh says how)" ;;
esac
"$ROOT/tools/check-signatures.sh" "$APP" "$TEAM" > "$WORK/signatures" \
  || { cat "$WORK/signatures" >&2; die "a Mach-O in $(basename "$APP") is not signed as MacGameFix signs its payload"; }
tail -1 "$WORK/signatures"

# 2. The zip, as the release's is made.
ZIP="$WORK/$ASSET"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP" || die "could not zip $APP"
say "==> zipped for Apple: $(du -h "$ZIP" | cut -f1 | tr -d ' ')"
if [ "$DRY" = 1 ]; then
  say "dry run: would send it with"
  say "    xcrun notarytool submit $ASSET --keychain-profile $PROFILE --wait --output-format json"
  say "and stops here; nothing was sent."
  exit 0
fi

say "==> sending it to Apple's notary service (profile $PROFILE); this waits for its answer"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json > "$WORK/submit" 2>&1
rc=$?
ID="$(/usr/bin/grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$WORK/submit" | tail -1 || true)"
STATUS="$(sed -nE 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p; s/^[[:space:]]*status:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p' "$WORK/submit" | tail -1)"

if /usr/bin/grep -qiE 'required agreement|agreement (is )?(missing|expired)|status code:? *403' "$WORK/submit"; then
  sed 's/^/    /' "$WORK/submit" >&2
  say "Apple refused the submission because the team's account holder has not accepted Apple's current agreement."
  say "The account holder must sign in at developer.apple.com/account and accept it; then run app/notarize.sh again."
  exit 3
fi
[ -n "$ID" ] && say "    submission id: $ID"

case "$STATUS" in
Accepted) ;;
Invalid|Rejected)
  mkdir -p "$OUT" || die "could not make $OUT"
  LOG="$OUT/notary-$ID.json"
  if xcrun notarytool log --keychain-profile "$PROFILE" "$ID" "$LOG" > "$WORK/log" 2>&1 && [ -s "$LOG" ]; then
    say "Apple's log: $LOG"
    /usr/bin/python3 -I - "$LOG" <<'PY'
import json, sys
log = json.load(open(sys.argv[1]))
for i in log.get("issues") or []:
    print(f"    {i.get('severity', '')}: {i.get('path', '')}: {i.get('message', '')}")
PY
  else
    sed 's/^/    /' "$WORK/log" >&2
    say "Apple's log could not be fetched: xcrun notarytool log --keychain-profile $PROFILE $ID"
  fi
  die "Apple did not notarise $(basename "$APP") ($STATUS)" ;;
*)
  sed 's/^/    /' "$WORK/submit" >&2
  die "notarytool gave no answer this understands (exit $rc${STATUS:+, status $STATUS})" ;;
esac
say "==> notarised"

# 3. The ticket, in the app and in the zip that ships.
xcrun stapler staple "$APP" > "$WORK/staple" 2>&1 \
  || { sed 's/^/    /' "$WORK/staple" >&2; die "could not staple the ticket to $APP"; }
xcrun stapler validate "$APP" > "$WORK/validate" 2>&1 \
  || { sed 's/^/    /' "$WORK/validate" >&2; die "the stapled ticket does not validate"; }
say "==> ticket stapled and validated"
spctl -a -vv -t exec "$APP" > "$WORK/spctl" 2>&1; src=$?
sed 's/^/    /' "$WORK/spctl"
[ "$src" = 0 ] && /usr/bin/grep -q 'source=Notarized Developer ID' "$WORK/spctl" \
  || die "Gatekeeper does not accept $(basename "$APP") as a notarised Developer ID app"

# The assets are made and checked in $WORK, and reach <folder> only once the
# copy in the zip has passed: until then a failure leaves <folder> as it was,
# older assets and all, as every failure before this point does. They are
# copied in beside the old pair under names of their own and then renamed over
# it, the zip first; should the second rename fail, both are removed rather than
# leave a zip beside another zip's .sha256.
A="$WORK/assets"
mkdir "$A" || die "could not make $A"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$A/$ASSET" || die "could not zip $APP"
(cd "$A" && shasum -a 256 "$ASSET" > "$ASSET.sha256") || die "could not write $ASSET.sha256"
mkdir "$WORK/unpacked" && ditto -x -k "$A/$ASSET" "$WORK/unpacked" \
  && codesign --verify --deep --strict "$WORK/unpacked/$(basename "$APP")" 2>/dev/null \
  && xcrun stapler validate "$WORK/unpacked/$(basename "$APP")" > /dev/null 2>&1 \
  || die "the app in $ASSET does not verify or carries no ticket; nothing was written into $OUT"
mkdir -p "$OUT" || die "could not make $OUT"
NEW=".$ASSET.new.$$"
trap 'rm -rf "$WORK"; rm -f "$OUT/$NEW" "$OUT/$NEW.sha256"' EXIT
cp "$A/$ASSET" "$OUT/$NEW" && cp "$A/$ASSET.sha256" "$OUT/$NEW.sha256" \
  && cmp -s "$A/$ASSET" "$OUT/$NEW" && cmp -s "$A/$ASSET.sha256" "$OUT/$NEW.sha256" \
  || die "could not copy the assets into $OUT; what was there is as it was"
mv -f "$OUT/$NEW" "$OUT/$ASSET" || die "could not put $ASSET into $OUT; what was there is as it was"
mv -f "$OUT/$NEW.sha256" "$OUT/$ASSET.sha256" \
  || { rm -f "$OUT/$ASSET" "$OUT/$ASSET.sha256"; die "could not put $ASSET.sha256 into $OUT; both assets were removed from it"; }
say "==> release assets in $OUT:"
say "    $ASSET"
say "    $ASSET.sha256  $(cut -d' ' -f1 "$OUT/$ASSET.sha256")"
