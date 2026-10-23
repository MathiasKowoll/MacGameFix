#!/bin/bash
# Signs the Mach-O files this repository ships with MacGameFix's Developer ID.
#
#   tools/sign-payload.sh
#   MACGAMEFIX_CODESIGN_IDENTITY="Developer ID Application: <name> (<team>)" tools/sign-payload.sh
#
# Notarisation refuses an app in which one Mach-O lacks a Developer ID signature
# with a secure timestamp. The app carries Mach-O files it does not build: the
# Wine modules' unix halves (engine/modules/<build>/<arch>-unix/*.so, written by
# engine/build.sh) and fixes/sm2-shadertool. build-app.sh copies them unchanged
# and checks that the copies are byte for byte what the repository holds, and
# each module's sha256 is pinned in its built-for.json, which the catalogs carry.
# So they are signed here, in the repository, and never inside the app: signing
# them in the bundle would make its copies differ from what the hashes say.
#
# When to run it: after engine/build.sh writes modules without
# MACGAMEFIX_CODESIGN_IDENTITY, or after sm2-shadertool is built again (its
# source's header says how), and before committing either.
#
# The identity is $MACGAMEFIX_CODESIGN_IDENTITY, or else the keychain's first
# "Developer ID Application" identity; without one it refuses, since an ad hoc
# signature is what this replaces.
#
# The files are found by what they are, every Mach-O at the top of fixes/ and
# under engine/modules/, not by name. For each one:
#   - a module must be what its built-for.json recorded before anything is
#     signed; one that is not is refused;
#   - one already signed with this identity's team, a secure timestamp and the
#     hardened runtime is left alone, so running this again changes nothing;
#   - the others are signed with --timestamp and --options runtime, keeping the
#     identifier they had (a module's is the one its ad hoc signature gave);
#   - otool -t before and after must be the same (the code did not change, only
#     the signature), or the file is put back as it was and this fails;
#   - a module's new sha256 is written into its built-for.json.
# The hardened runtime is not needed on a library; it is set on the modules as
# well so that every Mach-O the app carries is signed one way, which
# tools/check-signatures.sh then checks for all of them.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

ID="${MACGAMEFIX_CODESIGN_IDENTITY:-}"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [ -z "$ID" ]; then
  ID="$(printf '%s\n' "$IDENTITIES" | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Developer ID Application: .*"$/\1/p')"
  ID="${ID%%$'\n'*}"
fi
if [ -z "$ID" ] || [ "$ID" = - ]; then
  echo "error: no Developer ID Application identity: set MACGAMEFIX_CODESIGN_IDENTITY, or add one to the keychain." >&2
  echo "       An ad hoc signature is what this replaces, so it signs nothing without one." >&2
  exit 1
fi
LINE="$(printf '%s\n' "$IDENTITIES" | /usr/bin/grep -F -- "$ID" || true)"
LINE="${LINE%%$'\n'*}"
NAME="$(printf '%s\n' "$LINE" | sed -n 's/^.*"\(.*\)"$/\1/p')"
TEAM="$(printf '%s\n' "$NAME" | sed -n 's/^Developer ID Application: .*(\([A-Z0-9]\{10\}\))$/\1/p')"
[ -n "$TEAM" ] || { echo "error: '$ID' is not a valid Developer ID Application identity in the keychain" >&2; exit 1; }
echo "==> signing with $NAME"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# What built-for.json says of a module: <built-for.json> <path in it> [<new sha256>].
recorded() {
  /usr/bin/python3 -I - "$@" <<'PY'
import json, sys
path, rel = sys.argv[1], sys.argv[2]
d = json.load(open(path))
if len(sys.argv) == 3:
    print(d["files"].get(rel, ""))
    sys.exit(0)
if rel not in d["files"]:
    sys.exit(f"error: {path} does not list {rel}")
d["files"][rel] = sys.argv[3]
with open(path, "w") as out:
    out.write(json.dumps(d, indent=2) + "\n")
PY
}

FILES=()
while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in Mach-O*) FILES+=("$f") ;; esac
done < <({ find "$ROOT/fixes" -maxdepth 1 -type f -print0; find "$ROOT/engine/modules" -type f -print0; } | sort -z)
[ "${#FILES[@]}" -gt 0 ] || { echo "error: no Mach-O file in fixes/ or engine/modules/" >&2; exit 1; }

# Every module first, before anything is signed.
for f in "${FILES[@]}"; do
  case "$f" in "$ROOT/engine/modules/"*) ;; *) continue ;; esac
  rel="${f#"$ROOT/engine/modules/"}"; build="${rel%%/*}"; rel="${rel#*/}"
  meta="$ROOT/engine/modules/$build/built-for.json"
  [ -f "$meta" ] || { echo "error: engine/modules/$build has no built-for.json" >&2; exit 1; }
  [ "$(recorded "$meta" "$rel")" = "$(sha "$f")" ] \
    || { echo "error: engine/modules/$build/$rel is not what its built-for.json recorded; nothing was signed" >&2; exit 1; }
done

signed=0; kept=0
for f in "${FILES[@]}"; do
  name="${f#"$ROOT/"}"
  d="$(codesign -dvv "$f" 2>&1 || true)"
  if codesign --verify --strict "$f" 2>/dev/null \
     && printf '%s\n' "$d" | /usr/bin/grep -qx "TeamIdentifier=$TEAM" \
     && printf '%s\n' "$d" | /usr/bin/grep -q '^Timestamp=' \
     && printf '%s\n' "$d" | /usr/bin/grep -q '^CodeDirectory .* flags=0x[0-9a-f]*([^)]*runtime'; then
    echo "  kept    $name (already signed by $TEAM)"
    kept=$((kept + 1)); continue
  fi
  ident="$(printf '%s\n' "$d" | sed -n 's/^Identifier=//p')"
  otool -t "$f" | tail -n +2 > "$TMP/before"
  cp -p "$f" "$TMP/original"
  old="$(sha "$f")"
  codesign --force --sign "$ID" --timestamp --options runtime ${ident:+--identifier "$ident"} "$f" 2> "$TMP/err" \
    || { cp -p "$TMP/original" "$f"; sed 's/^/       /' "$TMP/err" >&2; echo "error: $name could not be signed; it is as it was" >&2; exit 1; }
  otool -t "$f" | tail -n +2 > "$TMP/after"
  if ! cmp -s "$TMP/before" "$TMP/after" || ! codesign --verify --strict "$f" 2>/dev/null; then
    cp -p "$TMP/original" "$f"
    echo "error: $name changed more than its signature; it is as it was" >&2
    exit 1
  fi
  new="$(sha "$f")"
  case "$f" in
    "$ROOT/engine/modules/"*)
      rel="${f#"$ROOT/engine/modules/"}"; build="${rel%%/*}"; rel="${rel#*/}"
      recorded "$ROOT/engine/modules/$build/built-for.json" "$rel" "$new" ;;
  esac
  echo "  signed  $name ($ident): otool -t the same before and after ($(shasum -a 256 < "$TMP/after" | cut -c1-16)), sha256 ${old:0:16} -> ${new:0:16}"
  signed=$((signed + 1))
done
echo "==> $signed signed, $kept already signed"
for d in "$ROOT/fixes" "$ROOT/engine/modules"; do
  "$HERE/check-signatures.sh" "$d" "$TEAM" > "$TMP/check" || { cat "$TMP/check"; exit 1; }
  tail -1 "$TMP/check"
done
