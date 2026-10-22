#!/usr/bin/env bash
#
# Turn on the MetalFX denoiser that Cyberpunk 2077 for Mac ships and leaves off.
#
#     install-cp2077-denoiser.sh <game folder>            install
#     install-cp2077-denoiser.sh <game folder> --status   report
#     install-cp2077-denoiser.sh <game folder> --restore  undo
#
# The folder is the one Steam installed, holding Cyberpunk2077.app. This is the
# one fix here for a macOS game: no Wine is involved, and what it changes is the
# game's own app.
#
# WHAT IT CHANGES. The game carries Apple's MetalFX denoiser
# (MTLFXTemporalDenoisedScaler), but its renderer answers "not supported" from a
# method of two instructions, mov w0,#0; ret, and the game then neither offers
# the denoiser nor turns it on. The fix writes mov w0,#1 over the first: four
# bytes of the executable, at the offset the recipe names. Nothing else in the
# executable changes.
#
# THE RECIPE IS DATA. cp2077-denoiser.recipes, beside this script, has a row for
# each executable of each game build: its CFBundleVersion, the executable's
# sha256, the offset, the four bytes there and the four written, and the sha256
# after. A build with no row answers "norecipe" and nothing is written; a new
# build gets a new row in a catalog update, with no new app. The README's
# Cyberpunk 2077 section says how a row is made.
#
# SIGNING. Changing the executable breaks CD PROJEKT's signature, so the app is
# signed again, ad hoc, with the hardened runtime and the two entitlements of
# theirs an ad hoc signature may carry: allow-dyld-environment-variables, and
# disable-library-validation, without which the executable cannot load CD
# PROJEKT's frameworks. Never --deep: the four frameworks keep CD PROJEKT's
# signatures, and the bundle's seal of its resources comes out byte for byte
# the same. Their restricted entitlements, sustained-execution among them, are
# lost: an ad hoc signature that carries them is killed at launch. Stopped
# between the write and a signature that verifies, by an error or a signal, it
# puts the original back.
#
# THE ORIGINAL IS KEPT outside the app, in MacGameFix's app-backup folder
# ($MGVF_APP_BACKUP), under the bundle id and the build: the executable, the
# seal (_CodeSignature/CodeResources), and in "apps" the app or apps it is kept
# for. --restore puts both back and drops the copy once no app is left in it. A
# copy kept for another build of the same app is stale, since that executable
# is gone, and the next install or restore removes it.
#
# --status prints the game's build on a "Game build:" line and, when there is
# one, the reason for the word on a "Why:" line, then one word: absent,
# installed, broken (patched and its signature does not verify; installing
# again starts from the original), half (patched outside MacGameFix), norecipe
# (no row for this build), or blocked (nothing can be installed here: an
# executable no row was made from, or a Mac below an M3).
#
# Apple lists MetalFX denoised upscaling for Apple9 GPUs and later, M3 on. The
# game does not ask MetalFX whether the Mac can do it, so this refuses on an M1
# or an M2. It refuses while the game runs, too.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MGVF-SCOPE: app
# MGVF-GAME: Cyberpunk 2077 | Cyberpunk2077 | Cyberpunk2077.app/Contents/MacOS
# MGVF-WHY: Writes the one instruction that makes the game offer the MetalFX denoiser it ships, and signs its app again ad hoc. M3 or later.

set -euo pipefail

usage() { sed -n '3,54p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

GAME="$1"
MODE="${2:---install}"
if [ "${MGVF_STATUS_ONLY:-0}" = 1 ]; then MODE=--status; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
# One spelling of the folder, however it was typed: a trailing slash, a
# relative path or a symbolic link all name the same app in what follows.
if [ -d "$GAME" ]; then GAME="$(CDPATH='' cd -- "$GAME" && pwd -P)"; fi

APP="$GAME/Cyberpunk2077.app"
EXE="$APP/Contents/MacOS/Cyberpunk2077"
SEAL="$APP/Contents/_CodeSignature/CodeResources"
RECIPES="$HERE/cp2077-denoiser.recipes"
BACKUPS="${MGVF_APP_BACKUP:-$HOME/Library/Application Support/MacGameFix/app-backup}"

[ -f "$EXE" ] || {
  echo "error: no 'Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077' in $GAME" >&2
  echo "       Pick the folder Cyberpunk 2077 is installed in." >&2
  exit 1
}

# A key of the app's Info.plist, or nothing. PlistBuddy says a missing file on
# stdout, so its output counts only when it succeeds.
plist() { local v; v="$(/usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null)" || v=""; printf '%s' "$v"; }
BUILD="$(plist CFBundleVersion)"
SHORT="$(plist CFBundleShortVersionString)"
BUNDLE="$(plist CFBundleIdentifier)"
SAVE="$BACKUPS/$BUNDLE-$BUILD"
# The app reads the build off this line for the row's note; it is never a state word.
if [ -n "$SHORT" ] && [ -n "$BUILD" ]; then echo "Game build: $SHORT ($BUILD)"
elif [ -n "$BUILD" ]; then echo "Game build: $BUILD"; fi

STEAM="In Steam, Properties > Installed Files > Verify integrity of game files should put CD PROJEKT's back"

sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
# The four bytes at an offset, as lower-case hex in file order.
wordat() { dd if="$1" bs=4 skip=$(($2 / 4)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
word() { wordat "$1" "$OFF"; }
hex() { case "$1" in *[!0123456789abcdef]*) return 1 ;; esac; [ ${#1} = "$2" ]; }

# This executable's row. A build may have several, one for each executable
# shipped under that CFBundleVersion: the one whose original is the executable
# here, or else the copy MacGameFix kept, or else whose patch is in it.
ROWS=0; ORIG=""; OFF=""; OLD=""; NEW=""; PATCHED=""; BY=""
if [ -n "$BUILD" ] && [ -n "$BUNDLE" ] && [ -f "$RECIPES" ]; then
  LIVE="$(sha "$EXE")"
  KEPT=""; [ ! -f "$SAVE/Cyberpunk2077" ] || KEPT="$(sha "$SAVE/Cyberpunk2077")"
  live=""; kept=""; hand=""
  while read -r r_b r_orig r_off r_old r_new r_patched _ || [ -n "${r_b:-}" ]; do
    case "$r_b" in ''|'#'*) continue ;; esac
    [ "$r_b" = "$BUILD" ] || continue
    # Lower-case hex throughout. An instruction is four bytes on a four-byte
    # boundary, and it is read and written as one block.
    o="${r_off#0x}"
    if ! hex "$r_orig" 64 || ! hex "$r_patched" 64 || ! hex "$r_old" 8 || ! hex "$r_new" 8 \
       || [ "$o" = "$r_off" ] || [ -z "$o" ] || ! hex "$o" "${#o}" || [ $((r_off % 4)) != 0 ]; then
      echo "error: a row for build $BUILD in cp2077-denoiser.recipes is not a recipe" >&2
      exit 1
    fi
    ROWS=$((ROWS + 1))
    row="$r_orig $r_off $r_old $r_new $r_patched"
    if [ -z "$live" ] && [ "$LIVE" = "$r_orig" ]; then live="$row"; fi
    if [ -z "$kept" ] && [ -n "$KEPT" ] && [ "$KEPT" = "$r_orig" ]; then kept="$row"; fi
    if [ -z "$hand" ] && [ "$(wordat "$EXE" "$r_off")" = "$r_new" ]; then hand="$row"; fi
  done < "$RECIPES"
  if [ -n "$live" ]; then BY=live; set -- $live
  elif [ -n "$kept" ]; then BY=kept; set -- $kept
  elif [ -n "$hand" ]; then BY=hand; set -- $hand
  fi
  if [ -n "$BY" ]; then ORIG="$1"; OFF="$2"; OLD="$3"; NEW="$4"; PATCHED="$5"; fi
fi

# What is there, in STATE, and in WHY the reason, when it needs one.
# "modified" is said as blocked.
decide() {
  STATE=norecipe; WHY="There is no recipe for this build of the game yet."
  if [ "$ROWS" = 0 ]; then
    :
  elif [ "$BY" = live ]; then
    STATE=absent; WHY=""
  elif [ "$BY" = kept ] && [ "$(word "$EXE")" = "$NEW" ]; then
    if codesign --verify --strict "$APP" >/dev/null 2>&1; then
      STATE=installed; WHY=""
    else
      STATE=broken
      WHY="The executable is patched and its signature does not verify; installing again starts from the original MacGameFix kept."
    fi
  elif [ "$BY" = hand ]; then
    STATE=half
    if [ -e "$SAVE/Cyberpunk2077" ]; then
      WHY="The executable is patched, and the copy MacGameFix kept for this build is not its original. $STEAM, then install here."
    else
      WHY="The executable is patched, but not by MacGameFix: no copy of its original is kept. $STEAM, then install here."
    fi
  else
    STATE=modified
    WHY="This executable is not one the recipes for build $BUILD were made from. $STEAM, then install here."
  fi
}
decide

# Apple lists MetalFX denoised upscaling for M3 and later. A Mac below that can
# still have the fix removed, but nothing installed.
chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
case "$chip" in
  "Apple M1"|"Apple M1 "*|"Apple M2"|"Apple M2 "*)
    UNDER="This Mac has an $chip. Apple lists MetalFX denoised upscaling for M3 and later, and the game does not ask, so it would offer an option this Mac cannot run." ;;
  *) UNDER="" ;;
esac

case "$MODE" in
--status)
  answer="$STATE"
  if [ "$STATE" = modified ]; then answer=blocked; fi
  if [ -n "$UNDER" ]; then
    case "$STATE" in absent|norecipe) answer=blocked; WHY="$UNDER" ;; esac
  fi
  # The app shows the reason beside a row it cannot install; never a state word.
  [ -z "$WHY" ] || echo "Why: $WHY"
  echo "$answer"
  exit 0
  ;;
--restore|--install) ;;
*) usage ;;
esac

# The game, started from this app under any spelling of its path: by the file
# it runs, and by the path it was started with.
running() {
  local pat
  [ -z "$(/usr/sbin/lsof -t -a -d txt -- "$EXE" 2>/dev/null)" ] || return 0
  pat="$(printf '%s' "$APP/Contents/MacOS/" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  pgrep -f -- "$pat" >/dev/null 2>&1
}

# What to tell the user about a write into the app that failed. macOS refuses
# one with "Operation not permitted" when the app doing it is not allowed under
# App Management, and that is said as such.
advice() {
  case "$1" in
    *"Operation not permitted"*)
      echo "macOS did not let MacGameFix change $APP."
      if [ "${MGVF_FRONTEND:-}" = app ]; then
        echo "Allow MacGameFix in System Settings > Privacy & Security > App Management, then try again."
      else
        echo "Allow the app you ran this from in System Settings > Privacy & Security > App Management, then try again."
      fi ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Which apps a kept copy is kept for: the same build of the game, installed
# twice, shares one copy, and it goes only when neither is left.
holds() { /usr/bin/grep -qxF -- "$APP" "$1/apps" 2>/dev/null; }
claim() { holds "$1" || printf '%s\n' "$APP" >> "$1/apps"; }
# Takes this app off a copy's list; true when no app is left in it.
release() {
  local rest
  rest="$(/usr/bin/grep -vxF -- "$APP" "$1/apps" 2>/dev/null || true)"
  if [ -n "$rest" ]; then printf '%s\n' "$rest" > "$1/apps"; return 1; fi
  return 0
}

# The copies kept for this app at other builds of the game: their executables
# are gone. Only a folder named for this bundle id and a build, with this app
# in its list, is one of them. Dropped after an install or a removal that
# worked, and by a removal on a build with no recipe, where it is all there is
# to do.
drop_stale() {
  local d b
  [ -n "$BUNDLE" ] && [ -n "$BUILD" ] || return 0
  for d in "$BACKUPS/$BUNDLE-"*; do
    [ -d "$d" ] && [ "$d" != "$SAVE" ] || continue
    b="${d#"$BACKUPS/$BUNDLE-"}"
    case "$b" in ''|*[!0-9.]*) continue ;; esac
    holds "$d" || continue
    if release "$d"; then
      rm -rf "$d"
      echo "  removed the copy kept for build $b, which is no longer installed"
    else
      echo "  the copy kept for build $b stays: another copy of the game uses it"
    fi
  done
}

# Set while the executable holds bytes that are not signed and checked: from the
# write to a signature that verifies. Any way out then puts the original back.
DIRTY=0; BACK=""; ENT=""
# The original back over a change that did not take, as new files (ditto writes
# a new one rather than over the old, whose signature the kernel may still hold
# from a run). Says nothing itself, since whoever reads the output may be gone:
# BACK holds what to say.
put_back() {
  local wrote=0
  DIRTY=0; BACK="  the original could not be put back; it is kept in $SAVE"
  rm -f "$EXE.cstemp" 2>/dev/null || true
  if [ "$(sha "$EXE")" != "$ORIG" ]; then
    ditto "$SAVE/Cyberpunk2077" "$EXE" 2>/dev/null || return 1
    wrote=1
  fi
  if ! cmp -s "$SAVE/CodeResources" "$SEAL"; then
    ditto "$SAVE/CodeResources" "$SEAL" 2>/dev/null || return 1
    wrote=1
  fi
  [ "$(sha "$EXE")" = "$ORIG" ] || return 1
  # Nothing to say when nothing had been written.
  if [ "$wrote" = 1 ]; then BACK="  the original executable is back in place"; else BACK=""; fi
}
# Stops: the original goes back first, then what went wrong is said.
die() {
  [ "$DIRTY" = 0 ] || put_back || true
  local line
  for line in "$@"; do [ -z "$line" ] || printf '%s\n' "$line" >&2; done
  [ -z "$BACK" ] || printf '%s\n' "$BACK" >&2
  exit 1
}
finish() {
  # A line a gone reader did not take stays in bash's buffer, and would be
  # flushed into the next command substitution: it goes nowhere first.
  echo >/dev/null 2>&1 || true
  [ -z "$ENT" ] || rm -f "$ENT"
  [ -z "$SAVE" ] || rm -f "$SAVE/Cyberpunk2077.partial" 2>/dev/null || true
  if [ "$DIRTY" = 1 ]; then put_back || true; [ -z "$BACK" ] || printf '%s\n' "$BACK" >&2 || true; fi
}
trap finish EXIT
# A signal ends the run through finish. A reader that went away makes a write
# fail, which ends it the same way, rather than killing it where it stands.
trap 'exit 1' HUP INT TERM
trap '' PIPE

SIGNED=""
sign() {
  ENT="$(mktemp -t cp2077-entitlements)"
  cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST
  # The bundle without --deep: its main executable and the seal of its
  # resources are signed again, and the frameworks are left as CD PROJEKT signed them.
  SIGNED="$(codesign --force --sign - --options runtime --entitlements "$ENT" "$APP" 2>&1)" || return 1
  SIGNED="$(codesign --verify --strict "$APP" 2>&1)" || return 1
}

if [ "$MODE" = --restore ]; then
  case "$STATE" in
    norecipe)
      drop_stale
      echo "nothing of MacGameFix's is in this build of the game"; exit 0 ;;
    absent) echo "nothing of ours is installed"; exit 0 ;;
    # An executable changed after MacGameFix installed can still have the
    # original it kept put back; with none kept, there is nothing to put back.
    half|modified)
      [ "$BY" = kept ] || die "error: there is no original of MacGameFix's here to put back." "       $WHY" ;;
  esac
  if running; then die "error: Cyberpunk 2077 is running. Quit it first; nothing was changed."; fi
  out="$(ditto "$SAVE/Cyberpunk2077" "$EXE" 2>&1)" || die "$(advice "$out")"
  out="$(ditto "$SAVE/CodeResources" "$SEAL" 2>&1)" || die "$(advice "$out")"
  if [ "$(sha "$EXE")" != "$ORIG" ] || ! codesign --verify --strict "$APP" >/dev/null 2>&1; then
    die "error: the original is back but does not verify as CD PROJEKT signed it; the copy stays in $SAVE." "       $STEAM."
  fi
  if release "$SAVE"; then
    rm -rf "$SAVE"
  else
    echo "  the copy kept for this build stays: another copy of the game uses it"
  fi
  drop_stale
  echo "restored — the game is back to CD PROJEKT's own executable and signature"
  exit 0
fi

case "$STATE" in
  installed) echo "the denoiser is already turned on, nothing to do"; exit 0 ;;
esac
[ -z "$UNDER" ] || die "error: $UNDER Nothing was changed."
case "$STATE" in
  norecipe) die "$WHY Nothing was changed; MacGameFix waits for one." ;;
  half|modified) die "error: $WHY" ;;
esac
if running; then die "error: Cyberpunk 2077 is running. Quit it first; nothing was changed."; fi

if [ "$STATE" = broken ]; then
  # Whatever is in the executable now, the result is the recipe's: the
  # original first, then the same steps as a first install, which check it.
  echo "the patch is in place and its signature does not verify: starting again from the original kept in $SAVE"
  DIRTY=1
  put_back || die "error: could not put the original back over the executable."
  [ -z "$BACK" ] || echo "$BACK"
fi

echo "[1/3] keeping the original in $SAVE"
[ "$(word "$EXE")" = "$OLD" ] \
  || die "error: the recipe for build $BUILD expects $OLD at $OFF; the executable has $(word "$EXE"). Nothing was changed."
mkdir -p "$SAVE"
if [ -e "$SAVE/Cyberpunk2077" ]; then
  # Kept before, and never replaced: a Steam verify puts the same original back.
  [ "$KEPT" = "$ORIG" ] \
    || die "error: $SAVE/Cyberpunk2077 is not this build's original. Move it away, then try again; nothing was changed."
  echo "  the copy kept before is the original, and stays"
else
  # Under another name until it is whole and checked, so an interrupted copy is
  # never taken for the original.
  rm -f "$SAVE/Cyberpunk2077.partial"
  if ! ditto "$EXE" "$SAVE/Cyberpunk2077.partial" || [ "$(sha "$SAVE/Cyberpunk2077.partial")" != "$ORIG" ]; then
    rm -f "$SAVE/Cyberpunk2077.partial"
    die "error: could not keep a copy of the executable in $SAVE; nothing was changed."
  fi
  mv -f "$SAVE/Cyberpunk2077.partial" "$SAVE/Cyberpunk2077"
fi
if [ ! -f "$SAVE/CodeResources" ]; then
  ditto "$SEAL" "$SAVE/CodeResources" || die "error: could not keep a copy of $SEAL; nothing was changed."
fi
claim "$SAVE"

echo "[2/3] writing the recipe's four bytes at $OFF"
octal=""; i=0
while [ $i -lt 8 ]; do octal="$octal$(printf '\\%03o' "0x${NEW:$i:2}")"; i=$((i + 2)); done
# dd into the file as it is: codesign then writes the signed executable as a new file.
DIRTY=1
out="$(printf "$octal" | dd of="$EXE" bs=4 seek=$((OFF / 4)) count=1 conv=notrunc 2>&1)" || die "$(advice "$out")"
[ "$(sha "$EXE")" = "$PATCHED" ] || die "error: the patched executable is not the one the recipe expects."

echo "[3/3] signing the app again (ad hoc): CD PROJEKT's signature no longer covers the executable"
sign || die "error: could not sign $APP" "$(advice "$SIGNED")"
DIRTY=0
# Only once the fix is in: a refusal or a failure leaves everything as it was.
drop_stale
echo
echo "installed"
echo "  the original is kept in $SAVE; --restore puts it back"
