# FH6 runtime integration, sourced by install-fh6-fix.sh.
# ntdll is owned by the existing Rosetta improvement, never a new section.
# SPDX-License-Identifier: GPL-3.0-or-later
MODULES="${MGVF_MODULES:-$HERE}"
GAME_SHA=63791d0b686186c23ade10a1ae02efd785045bd818cc89816f472cad9a69fcb9
fh6sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
# The NotProton runners whose Wine modules carry FH6's ntdll pair (ntdll.so with ntdll.dll):
# Preview 41073's, the retained baseline, and 41303's, the same dispatcher built from
# engine/patches/wine-11.21's 0023. The pair is the one the modules catalog has for that
# build. On 41073 the installed baseline's ad hoc ntdll.so is accepted as well.
case "$RUNNER" in
  */runners/crossover-27.0.0.41073/CrossOver|*/runners/crossover-27.0.0.41073-fex/CrossOver) FH6_BUILD=27.0.0.41073 ;;
  */runners/crossover-27.0.0.41303/CrossOver|*/runners/crossover-27.0.0.41303-fex/CrossOver) FH6_BUILD=27.0.0.41303 ;;
  *) FH6_BUILD="" ;;
esac
NT_DLL="$MODULES/engine-${FH6_BUILD:-none}-x86_64-windows-ntdll.dll"
NT_UNIX="$MODULES/engine-${FH6_BUILD:-none}-x86_64-unix-ntdll.so"
BASELINE_PE="$(fh6sha "$NT_DLL")"
BASELINE_UNIX=""
[ "$FH6_BUILD" = 27.0.0.41073 ] && BASELINE_UNIX=dd6ef76ff8d51da5e2d246bdb7432a6c0b110668d742b1937e82ffcbb05d3ea0
fh6_pe_ok() { [ -f "$1" ] && [ -n "$BASELINE_PE" ] && [ "$(fh6sha "$1")" = "$BASELINE_PE" ]; }
fh6_unix_ok() {
  [ -f "$1" ] && { { [ -n "$BASELINE_UNIX" ] && [ "$(fh6sha "$1")" = "$BASELINE_UNIX" ]; } || { [ -f "$NT_UNIX" ] && cmp -s "$1" "$NT_UNIX"; }; }
}
fh6_runtime_ok() {
  local root="${CLONE:-$RUNNER}"
  fh6_pe_ok "$root/lib/wine/x86_64-windows/ntdll.dll" && fh6_unix_ok "$root/lib/wine/x86_64-unix/ntdll.so" && fh6_pe_ok "$SYS/ntdll.dll"
}
fh6_options() { /usr/bin/perl "$HERE/fh6-launch-options.pl" "$1" "$PFX"; }
fh6_preflight() {
  [ -n "$FH6_BUILD" ] || {
    echo 'error: FH6 WIP requires the standard NotProton runner for CrossOver Preview 27.0.0.41073 or 27.0.0.41303, using Rosetta.' >&2; return 1; }
  [ "$(fh6sha "$GAME/forzahorizon6.exe")" = "$GAME_SHA" ] || { echo 'error: this FH6 executable has not been validated for the WIP runtime. Nothing changed.' >&2; return 1; }
  fh6_pe_ok "$NT_DLL" && [ -f "$NT_UNIX" ] || { echo 'error: download this prerelease’s Wine modules in Improvements first.' >&2; return 1; }
  # All runtime copies must be backed up before an update. Unknown copies are not overwritten.
  local root f live stock
  for root in "$RUNNER" ${CLONE:+"$CLONE"}; do
    for f in x86_64-windows/ntdll.dll x86_64-unix/ntdll.so; do
      live="$root/lib/wine/$f"; stock="$live.mgf-fh6-original"
      [ -f "$live" ] || return 1
      if [ -f "$stock" ]; then
        case "$f" in *dll) fh6_pe_ok "$live" ;; *) fh6_unix_ok "$live" ;; esac || { echo "error: $live changed outside MacGameFix; it stays." >&2; return 1; }
      fi
    done
  done
  if [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_ok "$SYS/ntdll.dll" || return 1; fi
  fh6_options preflight
}
fh6_put() {
  local src="$1" dest="$2"
  cmp -s "$src" "$dest" && return 0
  # A validated ad-hoc library is already the same baseline. Signing the distribution copy
  # changes its file hash, not its code; leave the installed experiment intact.
  case "$dest" in */ntdll.so) fh6_unix_ok "$dest" && return 0 ;; esac
  [ -f "$dest.mgf-fh6-original" ] || cp -p "$dest" "$dest.mgf-fh6-original"
  cp -p "$src" "$dest.mgf-new" && mv -f "$dest.mgf-new" "$dest"
}
fh6_install_runtime() {
  # Stage the matching pair via the existing Rosetta installer; prefixes and per-game
  # launch clones are coordinated here because the generic installer does not own them.
  /bin/bash "$MODULES/engine-modules.sh" "$RUNNER" --part=rosetta
  if [ -n "$CLONE" ]; then
    fh6_put "$NT_DLL" "$CLONE/lib/wine/x86_64-windows/ntdll.dll"
    fh6_put "$NT_UNIX" "$CLONE/lib/wine/x86_64-unix/ntdll.so"
  fi
  fh6_put "$NT_DLL" "$SYS/ntdll.dll"
  local plugins="$HOME/Library/Application Support/notproton/plugins"
  mkdir -p "$plugins"
  # Keep an existing user plugin; our descriptor is only needed on a fresh installation.
  if [ ! -f "$plugins/rosetta-trap-boost.conf" ]; then
    cp -p "$HERE/notproton-rosetta-trap-boost.dylib" "$plugins/notproton-rosetta-trap-boost.dylib"
    cat > "$plugins/rosetta-trap-boost.conf" <<'CONF'
[NOTPROTON_ROSETTA_TRAP_BOOST]
label = Rosetta exception priority
description = Raises Rosetta exception delivery priority for the FH6 WIP profile
section = dev
on = 1
inject = 1
requires = Library/Application Support/notproton/plugins/notproton-rosetta-trap-boost.dylib
CONF
  fi
  fh6_options install
}
fh6_restore_runtime() {
  # Runtime improvement is shared by other games; removing a game fix never switches
  # it off globally. Only restore the prefix/clone copies actually backed up here.
  local root f live
  for root in ${CLONE:+"$CLONE"}; do
    for f in x86_64-windows/ntdll.dll x86_64-unix/ntdll.so; do
      live="$root/lib/wine/$f"
      if [ -f "$live.mgf-fh6-original" ]; then
        case "$f" in *dll) fh6_pe_ok "$live" ;; *) fh6_unix_ok "$live" ;; esac || return 1
        mv -f "$live.mgf-fh6-original" "$live"
      fi
    done
  done
  if [ -f "$SYS/ntdll.dll.mgf-fh6-original" ]; then fh6_pe_ok "$SYS/ntdll.dll" || return 1; mv -f "$SYS/ntdll.dll.mgf-fh6-original" "$SYS/ntdll.dll"; fi
}
