#!/usr/bin/env bash
#
# Install the MORTAL KOMBAT 11 face fix.
#
#     install-mk11-fix.sh <game folder>            install
#     install-mk11-fix.sh <game folder> --status   report
#     install-mk11-fix.sh <game folder> --restore  undo
#
# The folder is the one Steam installed, holding Binaries/Retail/MK11_DX12.exe.
#
# WHAT IT FIXES. The skin of every fighter whose face is uncovered -- forehead,
# brows, around the eyes -- turns into smeared dark patches with hard edges,
# which follow the light and change from frame to frame. A face is clean right
# after a screen loads and breaks once it animates; masked fighters never show
# it. Same on D3DMetal and on DXMT, at every graphics setting.
#
# After a face is deformed for its expression, two compute passes give it a
# fresh tangent frame, and on this Mac that frame comes out wrong where the face
# deforms. The fix skips those two passes, so a face keeps the tangent frame it
# was animated with: most of the patches go, faint ones remain. Why the
# recomputed frame is wrong is not known; legacy/wiki/Mortal-Kombat-11.md has
# what was ruled out. A game update that changes either shader makes the fix
# match nothing and do nothing, which is safe.
#
# DirectX 12 only: choose "DirectX 12" when Steam asks how to start the game.
# The DirectX 11 executable shows the same patches and is not covered.
#
# THE CARRIER IS THE GAME'S OWN. amd_ags_x64.dll is AMD's GPU services library,
# the game imports it statically, and its exports are forwarded straight back
# to the renamed original. Nothing is redistributed, no registry key is written
# and no CrossOver file is copied.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MGVF-SCOPE: folder
# MGVF-GAME: Mortal Kombat 11 | MK11_DX12.exe | Binaries/Retail
# MGVF-WHY: Skips the face tangent recompute whose result comes out as dark patches on this Mac. DirectX 12 only.

set -euo pipefail

usage() { sed -n '3,33p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
HERE="$(cd "$(dirname "$0")" && pwd)"

BIN="$GAME/Binaries/Retail"
LIVE="$BIN/amd_ags_x64.dll"
REAL="$BIN/amd_ags_x64_real.dll"
PROXY="$HERE/amd_ags_x64-mk11.dll"
EXPORTS="$HERE/pe.pl"
MARKER='mk11-face-fix.log'

is_ours() { [ -f "$1" ] && LC_ALL=C grep -qa "$MARKER" "$1"; }

# The same question asked a way that cannot go stale: our proxy forwards every
# export to amd_ags_x64_real, so the EXPORT table carries one
# "amd_ags_x64_real.<symbol>" string per forwarder. A genuine library never
# forwards to its own _real variant. Markers are for reporting; this is what the
# destructive step is allowed to rely on.
#
# The pattern is the prefix with its dot and NOT the ".dll" spelling, which
# never appears in the file: build-proxy.sh emits pure forwarders and no import
# descriptor, so the old test could not match, ever, and degenerated into the
# marker check it was written to outlive.
looks_like_ours() {
  [ -f "$1" ] || return 1
  is_ours "$1" && return 0
  LC_ALL=C grep -qaF "amd_ags_x64_real." "$1"
}

[ -f "$BIN/MK11_DX12.exe" ] || {
  echo "error: no 'Binaries/Retail/MK11_DX12.exe' in $GAME" >&2
  echo "       Pick the folder Mortal Kombat 11 is installed in." >&2
  exit 1
}

case "$MODE" in
--status)
  # An older build of ours is "outdated": it works, and installing again
  # replaces it with this one. The agent does that after a new catalog.
  if is_ours "$LIVE" && [ -f "$REAL" ]; then
    if cmp -s "$LIVE" "$PROXY"; then echo installed
    else echo "an older build of the fix is in place; installing again brings this one" >&2; echo outdated; fi
  elif is_ours "$LIVE"; then echo broken
  elif [ ! -f "$LIVE" ] && [ -f "$REAL" ]; then echo half
  else echo absent; fi
  exit 0
  ;;
--restore)
  # mv -f overwrites, so the original goes back in one step. Removing $LIVE
  # first would open a window where neither file is in place, and being
  # interrupted inside it left a state that neither --restore nor --install
  # would touch afterwards.
  if [ -f "$REAL" ] && ! looks_like_ours "$REAL" \
       && { looks_like_ours "$LIVE" || [ ! -e "$LIVE" ]; }; then
    mv -f "$REAL" "$LIVE"
    echo "restored — the game is back to its own amd_ags_x64"
  elif looks_like_ours "$LIVE"; then
    # Our proxy is here and the game's own DLL is not saved anywhere. There is
    # nothing to put back, and saying "nothing of ours is installed" about a
    # file that is plainly ours sends the reader looking in the wrong place.
    echo "our proxy is installed, but the game's own amd_ags_x64.dll is not saved here." >&2
    echo "  Verify the game files in Steam to get it back, then run --install." >&2
    exit 1
  else
    echo "nothing of ours is installed"
  fi
  exit 0
  ;;
--install) ;;
*) usage ;;
esac

if is_ours "$LIVE" && [ -f "$REAL" ]; then
  if cmp -s "$LIVE" "$PROXY"; then
    echo "the fix is already installed, nothing to do"
    exit 0
  fi
  # An older build of ours: the game's own DLL stays where it was saved, and
  # only our file is replaced, once this build forwards everything it exports.
  if looks_like_ours "$REAL"; then
    echo "error: $REAL is not the game's own DLL. Verify the game files in Steam, then run this again." >&2
    exit 1
  fi
  if ! real_exports="$(/usr/bin/perl "$EXPORTS" exports "$REAL" 2>&1)" \
     || ! proxy_exports="$(/usr/bin/perl "$EXPORTS" exports "$PROXY" 2>&1)"; then
    echo "error: cannot read the exports to compare; the older build stays in place" >&2; exit 1
  fi
  missing="$(comm -23 <(printf '%s\n' "$real_exports" | sort) \
                      <(printf '%s\n' "$proxy_exports" | sort))"
  if [ -n "$missing" ]; then
    echo "error: the game's own amd_ags_x64 exports symbols this build of the fix does not;" >&2
    echo "       the older build stays in place:" >&2
    echo "$missing" | head -8 | sed 's/^/       /' >&2
    exit 1
  fi
  cp "$PROXY" "$LIVE.new" && mv -f "$LIVE.new" "$LIVE" || {
    rm -f "$LIVE.new"; echo "error: could not replace the older build of the fix" >&2; exit 1; }
  echo "updated: an older build of the fix was in place; it is now this release's"
  exit 0
fi

echo "[1/3] checking amd_ags_x64.dll"
[ -f "$LIVE" ] || { echo "error: no amd_ags_x64.dll in $BIN" >&2; exit 1; }
if is_ours "$LIVE"; then
  echo "error: $LIVE is already a proxy but $REAL is gone." >&2
  echo "       Verify the game files in Steam, then run this again." >&2
  exit 1
fi

echo "[2/3] checking the proxy forwards everything the original exports"
if ! real_exports="$(/usr/bin/perl "$EXPORTS" exports "$LIVE" 2>&1)"; then
  echo "error: cannot read the exports of $LIVE" >&2; exit 1
fi
if ! proxy_exports="$(/usr/bin/perl "$EXPORTS" exports "$PROXY" 2>&1)"; then
  echo "error: cannot read the exports of $PROXY" >&2; exit 1
fi
missing="$(comm -23 <(printf '%s\n' "$real_exports" | sort) \
                    <(printf '%s\n' "$proxy_exports" | sort))"
if [ -n "$missing" ]; then
  echo "error: this build's amd_ags_x64 exports symbols the shipped proxy does not:" >&2
  echo "$missing" | head -8 | sed 's/^/       /' >&2
  echo "       The game has been updated; rebuild the proxy against it." >&2
  exit 1
fi

echo "[3/3] installing"
# What must never happen is moving a PROXY onto the saved original: that
# destroys the only copy of the game's own DLL. What is merely untidy is a
# leftover $REAL sitting beside a genuine $LIVE, which is exactly what a Steam
# file verification or a game patch leaves behind -- there the genuine library
# is the live one, and saving it over the stale copy is the right move.
#
# An earlier version of this refused on "$REAL exists" alone. That is the wrong
# question: it locked the ordinary post-verification state out of both install
# and restore, with no way back.
if looks_like_ours "$LIVE"; then
  echo "error: $LIVE is already a proxy, so the game's own DLL is not here to save." >&2
  echo "       Run --restore, or verify the game files in Steam, then try again." >&2
  exit 1
fi
if [ -e "$REAL" ]; then
  echo "  $REAL was left over from before; $LIVE is the game's own, so it replaces it"
fi
mv -f "$LIVE" "$REAL"
cp "$PROXY" "$LIVE" || { mv -f "$REAL" "$LIVE"; echo "error: could not install" >&2; exit 1; }
echo
echo "installed"
echo "  the game's own amd_ags_x64.dll is now amd_ags_x64_real.dll"
echo "  and every one of its exports reaches it"
