#!/usr/bin/env bash
#
# Install the NEED FOR SPEED UNBOUND black-screen fix.
#
#     install-nfsu-fix.sh <game folder>            install
#     install-nfsu-fix.sh <game folder> --status   report
#     install-nfsu-fix.sh <game folder> --restore  undo
#
# The folder is the one Steam installed, named Excalibur, holding
# NeedForSpeedUnbound.exe.
#
# WHAT IT FIXES. On D3DMetal the game can stay on a black screen at start. As
# it starts it pre-builds the pipelines it saved from the last session; D3DMetal
# cannot create the root signature of a few of them, and the game crashes as it
# cleans up after those. The first fix shared for it turned the pre-build off,
# which starts the game but builds every pipeline the first time it is drawn,
# and stutters. This is macprotips' NFSUnboundFix 1.1.0: the pre-build skips the
# pipelines whose root signature failed, marks them failed so the game builds
# them when they are first drawn, and pre-builds everything else.
#
# WHAT IT CHANGES. Six places of Engine.Render.Core2.PlatformPcDx12.dll, the
# game's D3D12 renderer, listed with their bytes in nfsu-prebuild.recipes
# beside this script: two calls and a cleanup loop, two checks in the unused
# space at the end of the code section, and the code section's size in the
# header so those checks are code. Only for a DLL whose sha256 a row names
# (Steam build 16690907); any other build is left alone and the app says it
# waits for a recipe. The game's executable is not touched.
#
# THE ORIGINAL IS KEPT beside the DLL as <name>.mgvf-original, and --restore
# puts it back. Without that copy, --restore undoes the six changes and checks
# the result against the original's sha256. Steam's "Verify integrity of game
# files" puts the original back too. A DLL carrying the first fix (pre-build
# off) is reported as half: installing undoes it and puts this one in its
# place, and --restore undoes it.
#
# The game runs online through EA's servers, and changing a game file may go
# against EA's user agreement. macprotips' README says so too.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MGVF-SCOPE: folder
# MGVF-GAME: Need for Speed Unbound | NeedForSpeedUnbound.exe |
# MGVF-WHY: Lets the shader pre-build skip the few pipelines D3DMetal cannot create a root signature for, instead of crashing on a black screen. Steam build 16690907.
# MGVF-TESTING: macprotips
# MGVF-CREDIT: macprotips | https://github.com/macprotips/NFSUnboundFix
# MGVF-CREDIT: Ariel O, and u/ales_sandr for spreading it | https://www.codeweavers.com/compatibility

set -euo pipefail

usage() { sed -n '3,37p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
HERE="$(cd "$(dirname "$0")" && pwd)"

NAME="Engine.Render.Core2.PlatformPcDx12.dll"
RECIPES="$HERE/nfsu-prebuild.recipes"
EXE="NeedForSpeedUnbound.exe"

[ -f "$GAME/$EXE" ] || {
  echo "error: no '$EXE' in $GAME" >&2
  echo "       Pick the folder Need for Speed Unbound is installed in (Excalibur)." >&2
  exit 1
}

# The DLL sits beside the executable; a game update that moves it is found
# within two levels, and two copies are refused rather than guessed between.
DLL="$GAME/$NAME"
if [ ! -f "$DLL" ]; then
  found="$(find "$GAME" -maxdepth 3 -type f -iname "$NAME" 2>/dev/null)"
  if [ -n "$found" ] && [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = 1 ]; then DLL="$found"; fi
fi
SAVED="$DLL.mgvf-original"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
row() { /usr/bin/awk -v k="$1" -v h="$2" '$1 == k && $2 == h' "$RECIPES"; }

# What the DLL is, by its sha256: original (a row can patch it), patched (a
# row's result), older (a fix made elsewhere), or unknown.
what() {
  local h="$1"
  if [ -n "$(row result "$h")" ]; then echo original
  elif /usr/bin/awk -v h="$h" '$1 == "result" && $3 == h { f = 1 } END { exit !f }' "$RECIPES"; then echo patched
  elif [ -n "$(row older "$h")" ]; then echo older
  else echo unknown; fi
}

# Writes each edit of <rows> into a copy of <in> at <out>, the "from" bytes
# replaced by the "to" bytes (fields 4 and 5 of an edit row, or 5 and 6 of an
# older one, swapped when undoing), refusing if any "from" bytes are not there.
patch() { # <in> <out> <rows> <from field> <to field> <offset field>
  /usr/bin/perl -e '
    my ($in, $out, $rows, $fi, $ti, $oi) = @ARGV;
    open(my $f, "<:raw", $in) or die "cannot read $in\n"; local $/; my $d = <$f>; close $f;
    for my $r (split /\n/, $rows) {
      my @x = split " ", $r; my $o = hex $x[$oi];
      my ($from, $to) = (pack("H*", $x[$fi]), pack("H*", $x[$ti]));
      length($from) == length($to) or die "row at $x[$oi]: the two byte strings differ in length\n";
      substr($d, $o, length $from) eq $from or die "the bytes at $x[$oi] are not the expected ones\n";
      substr($d, $o, length $to) = $to;
    }
    open(my $g, ">:raw", $out) or die "cannot write $out\n"; print $g $d; close $g or die "cannot write $out\n";
  ' "$1" "$2" "$3" "$4" "$5" "$6"
}

# The bracket keeps grep's own command line from matching itself.
running() { /bin/ps -axo command= | /usr/bin/grep -qi '[n]eedforspeedunbound\.exe'; }

if [ ! -f "$DLL" ]; then
  [ "$MODE" = --status ] && { echo "Why: no $NAME in the game folder"; echo blocked; exit 0; }
  echo "error: no $NAME in $GAME" >&2; exit 1
fi

H="$(sha "$DLL")"
KIND="$(what "$H")"

case "$MODE" in
--status)
  echo "looking at $DLL"
  case "$KIND" in
  patched) echo installed ;;
  original) echo absent ;;
  older) echo "Why: the first fix shared for the game (shader pre-build off) is in place; installing replaces it"; echo half ;;
  *) echo "Why: this build of $NAME (sha256 $H) has no recipe yet"; echo norecipe ;;
  esac
  exit 0
  ;;
--restore|--install) ;;
*) usage ;;
esac

if running; then
  echo "error: Need for Speed Unbound is running. Quit it, then try again. Nothing was changed." >&2
  exit 1
fi

TMP="$DLL.mgvf-new"
trap 'rm -f "$TMP"' EXIT

# The original, by whichever way is at hand: the saved copy when it is the
# original, else the edits undone.
original_into() { # <out>
  local orig
  if [ "$KIND" = patched ]; then
    orig="$(/usr/bin/awk -v h="$H" '$1 == "result" && $3 == h { print $2 }' "$RECIPES")"
    if [ -f "$SAVED" ] && [ "$(sha "$SAVED")" = "$orig" ]; then cp "$SAVED" "$1"; return; fi
    patch "$DLL" "$1" "$(row edit "$orig")" 4 3 2
  else # older
    orig="$(row older "$H" | /usr/bin/awk '{ print $3 }')"
    patch "$DLL" "$1" "$(row older "$H")" 5 4 3
  fi
  [ "$(sha "$1")" = "$orig" ] || { echo "error: undoing the changes did not give the original back" >&2; return 1; }
}

if [ "$MODE" = --restore ]; then
  case "$KIND" in
  original) rm -f "$SAVED"; echo "nothing of ours is installed"; exit 0 ;;
  unknown) echo "error: $NAME is a build this fix does not know (sha256 $H); nothing was changed" >&2; exit 1 ;;
  esac
  original_into "$TMP"
  mv -f "$TMP" "$DLL"
  rm -f "$SAVED"
  echo "restored: $NAME is the game's own again"
  exit 0
fi

case "$KIND" in
patched) echo "the fix is already installed, nothing to do"; exit 0 ;;
unknown)
  echo "error: this build of $NAME (sha256 $H) has no recipe; nothing was changed." >&2
  echo "       The fix is made for Steam build 16690907." >&2
  exit 1 ;;
esac

echo "[1/3] the original"
if [ "$KIND" = older ]; then
  echo "  the first fix (pre-build off) is in place: undoing it"
  original_into "$TMP"
  mv -f "$TMP" "$DLL"
  H="$(sha "$DLL")"; KIND=original
fi
cp -p "$DLL" "$SAVED"
[ "$(sha "$SAVED")" = "$H" ] || { rm -f "$SAVED"; echo "error: could not keep a copy of the original" >&2; exit 1; }

echo "[2/3] writing the changes"
want="$(row result "$H" | /usr/bin/awk '{ print $3 }')"
patch "$DLL" "$TMP" "$(row edit "$H")" 3 4 2
[ "$(sha "$TMP")" = "$want" ] || { echo "error: the patched DLL is not the one the recipe expects; nothing was changed" >&2; exit 1; }

echo "[3/3] installing"
chmod "$(stat -f %Lp "$DLL")" "$TMP"
mv -f "$TMP" "$DLL"
[ "$(sha "$DLL")" = "$want" ] || { cp -p "$SAVED" "$DLL"; echo "error: the DLL changed on the way; the original is back" >&2; exit 1; }
echo
echo "installed"
echo "  the original is kept as $(basename "$SAVED")"
