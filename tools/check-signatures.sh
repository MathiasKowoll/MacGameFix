#!/bin/bash
# Is every Mach-O under a path signed as MacGameFix signs what it ships?
#
#   tools/check-signatures.sh <app, folder or file> [<team id>]
#
# Apple's notary service refuses a submission in which one Mach-O is not signed
# with a Developer ID and a secure timestamp, or one executable lacks the
# hardened runtime. MacGameFix signs every Mach-O it ships with all three
# (tools/sign-payload.sh, engine/build.sh, app/build-app.sh), so this asks all
# three of each. The files are found by what they are (file(1) says Mach-O), not
# by name, so one that joins the payload is checked without anybody listing it.
# For each:
#   - codesign --verify --strict passes;
#   - the leaf certificate is a Developer ID Application one;
#   - its TeamIdentifier is <team id>, or, without one, the first file's;
#   - it carries a Timestamp, the secure one Apple's server gives (a signature
#     made without --timestamp shows "Signed Time" instead);
#   - its flags carry runtime, and not adhoc.
# One line per file, then a count. Exit 1 when any fails, 2 when there is no
# Mach-O at all.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
TARGET="${1:-}"; TEAM="${2:-}"
[ -n "$TARGET" ] && [ -e "$TARGET" ] || { sed -n '4p' "$0"; exit 2; }
TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
BASE="$(dirname "$TARGET")/"

n=0; bad=0
while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in Mach-O*) ;; *) continue ;; esac
  n=$((n + 1))
  d="$(codesign -dvv "$f" 2>&1)"
  team="$(printf '%s\n' "$d" | sed -n 's/^TeamIdentifier=//p')"
  flags="$(printf '%s\n' "$d" | sed -n 's/.* flags=\(0x[0-9a-f]*([^)]*)\).*/\1/p')"
  [ -n "$TEAM" ] || TEAM="$team"
  why=""
  codesign --verify --strict "$f" 2>/dev/null || why="$why, does not verify"
  printf '%s\n' "$d" | /usr/bin/grep -q '^Authority=Developer ID Application: ' || why="$why, not signed with a Developer ID"
  [ "$team" = "$TEAM" ] || why="$why, team ${team:-none} and not $TEAM"
  printf '%s\n' "$d" | /usr/bin/grep -q '^Timestamp=' || why="$why, no secure timestamp"
  case "$flags" in *adhoc*) why="$why, ad hoc" ;; esac
  case "$flags" in *runtime*) ;; *) why="$why, no hardened runtime" ;; esac
  if [ -z "$why" ]; then
    printf '  ok    %s  %s %s\n' "${f#"$BASE"}" "$team" "$flags"
  else
    printf '  FAIL  %s: %s\n' "${f#"$BASE"}" "${why#, }"
    bad=$((bad + 1))
  fi
done < <(find "$TARGET" -type f -print0 | sort -z)

if [ "$n" = 0 ]; then
  echo "  no Mach-O file in ${TARGET#"$BASE"}"
  exit 2
fi
files=files; [ "$n" = 1 ] && files=file
if [ "$bad" = 0 ]; then
  echo "  $n Mach-O $files in ${TARGET#"$BASE"}, every one signed with a Developer ID of $TEAM, a secure timestamp and the hardened runtime"
  exit 0
fi
are=are; [ "$bad" = 1 ] && are=is
echo "  $bad of the $n Mach-O $files in ${TARGET#"$BASE"} $are not signed with a Developer ID of $TEAM, a secure timestamp and the hardened runtime"
exit 1
