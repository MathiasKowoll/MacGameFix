#!/bin/bash
# app/notarize.sh through every answer Apple gives, with nothing sent to Apple:
# a fake xcrun and a fake spctl go first on PATH. The fake xcrun answers
# notarytool submit, notarytool log, stapler staple and stapler validate as
# Apple's tools do, as FAKE_NOTARY tells it (accepted, accepted-text, invalid,
# agreement, noprofile), and refuses anything else without ever calling the real one.
# A fake ditto goes there too: /usr/bin/ditto itself, unless a case asks it to
# fail. The app is a copy of app/MacGameFix.app, which must be built with a
# Developer ID; the assets go into a throwaway folder.
#
#   app/test-notarize.sh  (after app/build-app.sh)
#
# What it checks:
#   - a dry run zips and stops: no notarytool call, no assets;
#   - an ad hoc app, and one whose nested Mach-O is ad hoc, are refused before
#     anything is sent;
#   - Apple's 403 for the agreement: the sentence for the account holder, exit 3,
#     nothing stapled, no assets;
#   - Invalid: Apple's log fetched into the folder and its issue printed, a
#     failure, no assets;
#   - no keychain profile: notarytool's own words, a failure, no assets;
#   - Accepted: the zip sent is the app at its top level with no AppleDouble
#     entries, the ticket stapled, spctl asked, and MacGameFix-<version>.zip and
#     its .sha256 written, the zip carrying the stapled app; the same from
#     notarytool's normal output, not its JSON;
#   - Accepted, and Gatekeeper still refusing: a failure, no assets;
#   - Accepted over an older pair of assets: the pair replaced, nothing else
#     left in the folder;
#   - Accepted, and the assets' zip failing halfway (a full disk), or the copy
#     in it not validating: a failure, and the older pair in the folder as it
#     was, with no new asset beside it.
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/MacGameFix.app"
[ -d "$SRC" ] || { echo "build MacGameFix.app first (build-app.sh)" >&2; exit 1; }
case "$(codesign -dv "$SRC" 2>&1 | sed -n 's/^TeamIdentifier=//p')" in
  ""|"not set")
    echo "  FAIL  app/MacGameFix.app is signed ad hoc, so nothing here can run: build it with a Developer ID (app/build-app.sh)"
    echo "FAILED"; exit 1 ;;
esac
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist")"
ASSET="MacGameFix-$VERSION.zip"
T="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] && echo "kept $T" || rm -rf "$T"' EXIT
fail=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

mkdir -p "$T/bin"
FAKE_LOG="$T/calls"; export FAKE_LOG
cat > "$T/bin/xcrun" <<'XCRUN'
#!/bin/bash
# A fake of xcrun for app/test-notarize.sh. It never calls the real one.
printf '%s\n' "$*" >> "$FAKE_LOG"
ID=2efe2717-52ef-43a5-96dc-0797e4ca1041
case "$1 $2" in
"notarytool submit")
  zip="$3"
  [ -f "$zip" ] || { echo "Error: no such file $zip" >&2; exit 1; }
  zipinfo -1 "$zip" > "$FAKE_LOG.zip" 2>&1
  case "${FAKE_NOTARY:-}" in
  accepted) printf '{"id":"%s","message":"Processing complete","status":"Accepted"}\n' "$ID" ;;
  # notarytool's normal output, should --output-format json ever be ignored.
  accepted-text)
    printf 'Conducting pre-submission checks for %s and initiating connection to the Apple notary service...\n' "$(basename "$zip")"
    printf 'Submission ID received\n  id: %s\nSuccessfully uploaded file\n  id: %s\n  path: %s\n' "$ID" "$ID" "$zip"
    printf 'Waiting for processing to complete.\nCurrent status: In Progress...\nCurrent status: Accepted....\n'
    printf 'Processing complete\n  id: %s\n  status: Accepted\n' "$ID" ;;
  invalid)  printf '{"id":"%s","message":"Processing complete","status":"Invalid"}\n' "$ID" ;;
  agreement)
    echo "Error: HTTP status code: 403. A required agreement is missing or has expired. This request requires an in-effect agreement that has not been signed or has expired. Ensure your team has signed the necessary legal agreements and that they are not expired." >&2
    exit 69 ;;
  noprofile)
    echo "Error: No Keychain password item found for profile: $5" >&2
    exit 69 ;;
  *) echo "fake xcrun: FAKE_NOTARY is not set" >&2; exit 99 ;;
  esac ;;
"notarytool log")
  # notarytool log [--keychain-profile <profile>] <id> <output path>
  out="${!#}"
  cat > "$out" <<LOG
{"jobId": "$ID", "status": "Invalid", "statusSummary": "Archive contains critical validation errors",
 "issues": [{"severity": "error", "code": null, "path": "MacGameFix-0.zip/MacGameFix.app/Contents/Resources/fake",
             "message": "The binary is not signed with a valid Developer ID certificate.", "docUrl": null, "architecture": "arm64"}]}
LOG
  ;;
"stapler staple")
  printf 'fake ticket\n' > "$3/Contents/CodeResources"
  echo "Processing: $3"; echo "The staple and validate action worked!" ;;
"stapler validate")
  echo "Processing: $3"
  # FAKE_VALIDATE=second-fails: the second validate, the copy unpacked from the
  # assets' zip, fails as one does with no network.
  n=$(( $(cat "$FAKE_LOG.validate" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_LOG.validate"
  if [ "${FAKE_VALIDATE:-}" = second-fails ] && [ "$n" = 2 ]; then
    echo "CloudKit query for $(basename "$3") failed due to \"Network is unreachable\"."; exit 68
  fi
  [ -f "$3/Contents/CodeResources" ] && { echo "The validate action worked!"; exit 0; }
  echo "$3 does not have a ticket stapled to it."; exit 65 ;;
*) echo "fake xcrun: not faked: $*" >&2; exit 99 ;;
esac
XCRUN
cat > "$T/bin/spctl" <<'SPCTL'
#!/bin/bash
# A fake of spctl -a -vv -t exec for app/test-notarize.sh.
printf 'spctl %s\n' "$*" >> "$FAKE_LOG"
app="${!#}"
if [ "${FAKE_SPCTL:-accepted}" = accepted ] && [ -f "$app/Contents/CodeResources" ]; then
  printf '%s: accepted\nsource=Notarized Developer ID\norigin=Developer ID Application: Fake (FAKE000000)\n' "$app" >&2; exit 0
fi
printf '%s: rejected\nsource=Unnotarized Developer ID\norigin=Developer ID Application: Fake (FAKE000000)\n' "$app" >&2; exit 3
SPCTL
cat > "$T/bin/ditto" <<'DITTO'
#!/bin/bash
# A fake of ditto for app/test-notarize.sh: /usr/bin/ditto itself, except that
# with FAKE_DITTO=second-zip-fails the second zip it is asked for, the assets',
# stops after 100000 bytes and fails, as it does on a full disk.
if [ "${FAKE_DITTO:-}" = second-zip-fails ] && [ "$1" = -c ]; then
  n=$(( $(cat "$FAKE_LOG.ditto" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_LOG.ditto"
  if [ "$n" = 2 ]; then
    dest="${!#}"
    /usr/bin/ditto "$@" && head -c 100000 "$dest" > "$dest.cut" && mv "$dest.cut" "$dest"
    echo "ditto: $dest: No space left on device" >&2; exit 1
  fi
fi
exec /usr/bin/ditto "$@"
DITTO
chmod +x "$T/bin/xcrun" "$T/bin/spctl" "$T/bin/ditto"

# One case: a fresh copy of the app, a fresh folder, the fakes first on PATH.
# With OLD=1 the folder already holds an older pair of assets.
n=0
case_run() { # <FAKE_NOTARY> [notarize.sh arguments before the app]
  n=$((n + 1)); C="$T/case$n"; mkdir -p "$C"
  /usr/bin/ditto "$SRC" "$C/MacGameFix.app"
  : > "$FAKE_LOG"; rm -f "$FAKE_LOG.zip" "$FAKE_LOG.ditto" "$FAKE_LOG.validate"
  if [ -n "${OLD:-}" ]; then
    mkdir -p "$C/out"; printf 'an older zip\n' > "$C/out/$ASSET"; printf 'an older sha256\n' > "$C/out/$ASSET.sha256"
  fi
  local mode="$1"; shift
  FAKE_NOTARY="$mode" PATH="$T/bin:$PATH" /bin/bash "$HERE/notarize.sh" "$@" "$C/MacGameFix.app" "$C/out" > "$C/log" 2>&1
  RC=$?
  cat "$FAKE_LOG" >> "$T/all-calls"
}
submitted() { /usr/bin/grep -q '^notarytool submit' "$FAKE_LOG"; }
no_assets() { [ ! -e "$C/out/$ASSET" ] && [ ! -e "$C/out/$ASSET.sha256" ]; }
# The folder holds the older pair, as it was, and nothing else.
old_kept() {
  [ "$(cat "$C/out/$ASSET" 2>/dev/null)" = "an older zip" ] \
    && [ "$(cat "$C/out/$ASSET.sha256" 2>/dev/null)" = "an older sha256" ] \
    && [ "$(ls -A "$C/out" | wc -l | tr -d ' ')" = 2 ]
}
stapled() { /usr/bin/grep -q '^stapler staple' "$FAKE_LOG"; }

echo "== a dry run"
case_run accepted --dry-run
[ "$RC" = 0 ] && ! submitted && ! stapled && no_assets && /usr/bin/grep -q '^dry run: would send it with' "$C/log" \
  && /usr/bin/grep -q 'nothing was sent' "$C/log" \
  && ok "it zips, says what it would send, and stops: no notarytool call, no assets" \
  || { bad "the dry run"; sed 's/^/        /' "$C/log"; }

echo "== refused before sending"
n=$((n + 1)); C="$T/case$n"; mkdir -p "$C"; /usr/bin/ditto "$SRC" "$C/MacGameFix.app"
codesign --force --sign - "$C/MacGameFix.app" 2>/dev/null; : > "$FAKE_LOG"
FAKE_NOTARY=accepted PATH="$T/bin:$PATH" /bin/bash "$HERE/notarize.sh" "$C/MacGameFix.app" "$C/out" > "$C/log" 2>&1; RC=$?
cat "$FAKE_LOG" >> "$T/all-calls"
[ "$RC" = 1 ] && ! submitted && no_assets && /usr/bin/grep -q 'is signed ad hoc' "$C/log" \
  && ok "an ad hoc app: refused, nothing sent" || { bad "an ad hoc app"; sed 's/^/        /' "$C/log"; }
n=$((n + 1)); C="$T/case$n"; mkdir -p "$C"; /usr/bin/ditto "$SRC" "$C/MacGameFix.app"
codesign --force --sign - "$C/MacGameFix.app/Contents/Resources/sm2-shadertool" 2>/dev/null
codesign --force --options runtime --timestamp=none --sign "$(codesign -dvv "$SRC" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p')" \
  "$C/MacGameFix.app" 2>/dev/null; : > "$FAKE_LOG"
FAKE_NOTARY=accepted PATH="$T/bin:$PATH" /bin/bash "$HERE/notarize.sh" "$C/MacGameFix.app" "$C/out" > "$C/log" 2>&1; RC=$?
cat "$FAKE_LOG" >> "$T/all-calls"
[ "$RC" = 1 ] && ! submitted && no_assets && /usr/bin/grep -q 'FAIL  MacGameFix.app/Contents/Resources/sm2-shadertool' "$C/log" \
  && /usr/bin/grep -q 'FAIL  MacGameFix.app/Contents/MacOS/MacGameFix: no secure timestamp' "$C/log" \
  && ok "an ad hoc sm2-shadertool inside, and an app with no secure timestamp: both named, refused, nothing sent" \
  || { bad "a nested ad hoc Mach-O"; sed 's/^/        /' "$C/log"; }

echo "== Apple's 403: the agreement"
case_run agreement
[ "$RC" = 3 ] && submitted && ! stapled && no_assets \
  && /usr/bin/grep -q "the team's account holder has not accepted Apple's current agreement" "$C/log" \
  && /usr/bin/grep -q 'must sign in at developer.apple.com/account and accept it' "$C/log" \
  && ok "the sentence for the account holder, exit 3, nothing stapled, no assets" \
  || { bad "the agreement (exit $RC)"; sed 's/^/        /' "$C/log"; }

echo "== Invalid"
case_run invalid
[ "$RC" = 1 ] && submitted && ! stapled && no_assets \
  && /usr/bin/grep -q '^notarytool log --keychain-profile itsomax-desktop-notary 2efe2717-52ef-43a5-96dc-0797e4ca1041 ' "$FAKE_LOG" \
  && [ -s "$C/out/notary-2efe2717-52ef-43a5-96dc-0797e4ca1041.json" ] \
  && /usr/bin/grep -q 'submission id: 2efe2717-52ef-43a5-96dc-0797e4ca1041' "$C/log" \
  && /usr/bin/grep -q 'error: .*not signed with a valid Developer ID certificate' "$C/log" \
  && /usr/bin/grep -q 'Apple did not notarise MacGameFix.app (Invalid)' "$C/log" \
  && ok "the id printed, Apple's log in the folder and its issue printed, a failure, no assets" \
  || { bad "Invalid (exit $RC)"; sed 's/^/        /' "$C/log"; }

echo "== no keychain profile"
MACGAMEFIX_NOTARY_PROFILE=nobody case_run noprofile
[ "$RC" = 1 ] && ! stapled && no_assets && /usr/bin/grep -q 'No Keychain password item found for profile: nobody' "$C/log" \
  && /usr/bin/grep -q -- '--keychain-profile nobody' "$FAKE_LOG" \
  && ok "MACGAMEFIX_NOTARY_PROFILE used; notarytool's own words, a failure, no assets" \
  || { bad "no profile (exit $RC)"; sed 's/^/        /' "$C/log"; }

echo "== Accepted, over an older pair of assets"
OLD=1 case_run accepted
if [ "$RC" = 0 ]; then
  /usr/bin/grep -q '^notarytool submit .* --keychain-profile itsomax-desktop-notary --wait --output-format json$' "$FAKE_LOG" \
    && ok "sent with the default profile, --wait" || bad "the submit line: $(/usr/bin/grep '^notarytool submit' "$FAKE_LOG")"
  first="$(head -1 "$FAKE_LOG.zip")"
  [ "$first" = "MacGameFix.app/" ] && ! /usr/bin/grep -qE '(^|/)\._|__MACOSX' "$FAKE_LOG.zip" \
    && ok "the zip sent: MacGameFix.app at its top, $(wc -l < "$FAKE_LOG.zip" | tr -d ' ') entries, no AppleDouble" \
    || bad "the zip sent starts with '$first' or carries AppleDouble entries"
  stapled && /usr/bin/grep -q '^stapler validate ' "$FAKE_LOG" && /usr/bin/grep -q '^spctl -a -vv -t exec ' "$FAKE_LOG" \
    && ok "stapled, validated, Gatekeeper asked" || bad "staple, validate and spctl: $(tr '\n' ';' < "$FAKE_LOG")"
  if [ -f "$C/out/$ASSET" ] && [ -f "$C/out/$ASSET.sha256" ]; then
    (cd "$C/out" && shasum -a 256 -c "$ASSET.sha256" > /dev/null 2>&1) \
      && [ "$(wc -c < "$C/out/$ASSET.sha256" | tr -d ' ')" = $((64 + 2 + ${#ASSET} + 1)) ] \
      && ok "$ASSET and $ASSET.sha256 written, in shasum's own format" || bad "the .sha256 does not check"
    [ "$(ls -A "$C/out" | wc -l | tr -d ' ')" = 2 ] && ! /usr/bin/grep -q 'an older' "$C/out/$ASSET.sha256" \
      && ok "the older pair replaced, and nothing else left in the folder" \
      || bad "the folder after Accepted: $(ls -A "$C/out" | tr '\n' ' ')"
    mkdir "$C/unz" && ditto -x -k "$C/out/$ASSET" "$C/unz"
    [ "$(cat "$C/unz/MacGameFix.app/Contents/CodeResources" 2>/dev/null)" = "fake ticket" ] \
      && codesign --verify --deep --strict "$C/unz/MacGameFix.app" 2>/dev/null \
      && ! zipinfo -1 "$C/out/$ASSET" | /usr/bin/grep -qE '(^|/)\._|__MACOSX' \
      && ok "the asset carries the stapled app, which still verifies, and no AppleDouble" \
      || bad "the asset's app is not the stapled one, or does not verify"
  else
    bad "no assets after Accepted"; sed 's/^/        /' "$C/log"
  fi
else
  bad "Accepted (exit $RC)"; sed 's/^/        /' "$C/log"
fi

echo "== Accepted, in notarytool's normal output"
case_run accepted-text
[ "$RC" = 0 ] && [ -f "$C/out/$ASSET" ] && /usr/bin/grep -q 'submission id: 2efe2717-52ef-43a5-96dc-0797e4ca1041' "$C/log" \
  && ok "read as Accepted too, the assets written" || { bad "Accepted as text (exit $RC)"; sed 's/^/        /' "$C/log"; }

echo "== Accepted, and Gatekeeper refusing"
FAKE_SPCTL=rejected case_run accepted
[ "$RC" = 1 ] && no_assets && /usr/bin/grep -q 'does not accept MacGameFix.app as a notarised Developer ID app' "$C/log" \
  && ok "a failure, no assets" || { bad "Gatekeeper refusing (exit $RC)"; sed 's/^/        /' "$C/log"; }

echo "== Accepted, and the assets' zip failing halfway"
OLD=1 FAKE_DITTO=second-zip-fails case_run accepted
[ "$RC" = 1 ] && stapled && old_kept && /usr/bin/grep -q 'No space left on device' "$C/log" \
  && /usr/bin/grep -q "error: could not zip $C/MacGameFix.app" "$C/log" \
  && ok "a failure, and the older pair in the folder as it was, nothing beside it" \
  || { bad "the assets' zip failing (exit $RC): $(ls -lA "$C/out" | tr '\n' ';')"; sed 's/^/        /' "$C/log"; }

echo "== Accepted, and the copy in the assets' zip not validating"
OLD=1 FAKE_VALIDATE=second-fails case_run accepted
[ "$RC" = 1 ] && stapled && old_kept && [ "$(/usr/bin/grep -c '^stapler validate ' "$FAKE_LOG")" = 2 ] \
  && /usr/bin/grep -q "the app in $ASSET does not verify or carries no ticket; nothing was written into" "$C/log" \
  && ok "a failure, and the older pair in the folder as it was, nothing beside it" \
  || { bad "the copy not validating (exit $RC): $(ls -lA "$C/out" | tr '\n' ';')"; sed 's/^/        /' "$C/log"; }

echo
# Every call the fakes took, across all the cases: only what they fake.
other="$(/usr/bin/grep -v -e '^notarytool submit ' -e '^notarytool log ' -e '^stapler staple ' -e '^stapler validate ' \
  -e '^spctl -a -vv -t exec ' "$T/all-calls" 2>/dev/null)"
[ -z "$other" ] && ok "the fakes took $(wc -l < "$T/all-calls" | tr -d ' ') calls, every one a notarytool, stapler or spctl call they answer" \
  || bad "the fakes were asked something else: $other"
[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
