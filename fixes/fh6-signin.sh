# Forza Horizon 6's Xbox sign-in, sourced by install-fh6-fix.sh: on NotProton's FH6 runner
# with the rest of the improvement, and alone in any other bottle or prefix (CrossOver's).
# Needs HERE, PFX, SYS and KEY, and bottles.sh's user_reg_edit.
#
# XAL looks its device key up with CredEnumerateW("Xbl|DeviceKey*"). On macOS Wine's
# CredEnumerateW also asks the host keychain through mountmgr, which answers
# STATUS_NOT_FOUND when nothing there matches, and CredEnumerateW took that as the failure
# of the whole call although the registry held the key. XAL then made a new device at every
# start, and Xbox asked for sign-in again. advapi32-fh6-<build>.dll is that build's advapi32
# with the host's "not found" taken as no host credential (fh6-advapi32/), a native DLL.
#
# It replaces the prefix's system32\advapi32.dll, kept as advapi32.dll.mgf-fh6-original, and
# forzahorizon6.exe alone loads it, through advapi32=native,builtin under its AppDefaults.
# Every other program in the prefix keeps Wine's builtin, and no runner or CrossOver app is
# touched. advapi32 is a KnownDLL: Wine maps it from system32's copy before it looks in the
# game's folder, so a copy beside the game is never seen and the native override then fails
# every import with c0000135 (measured 2026-11-11). When an update of the prefix puts Wine's
# own copy back, native,builtin falls back to the builtin: FH6 starts, and asks for sign-in
# until the fix is installed again.
#
# The build is the one made against the advapi32.dll the prefix's system32 has (or had,
# before ours): its sha256 names the CrossOver it came from.
# Bundled: $HERE/advapi32-fh6-26.3.0.39832.dll $HERE/advapi32-fh6-27.0.0.41073.dll $HERE/advapi32-fh6-27.0.0.41303.dll
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-only

S_LIVE="$SYS/advapi32.dll"
S_KEPT="$S_LIVE.mgf-fh6-original"
S_VALUE=advapi32
S_ORDER=native,builtin
S_BUILDS="26.3.0.39832 27.0.0.41073 27.0.0.41303"

signin_sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
signin_build() {
  case "$(signin_sha "$1")" in
    0375c2ee0e61be9fc3064a07b52f65e73d8a74b06fd06b59ea9e958365a33940) echo 26.3.0.39832 ;;
    7c5e5f2f573e001eabfc39d252428dfcc79c773262b7d00b46301f53fb143dab) echo 27.0.0.41073 ;;
    8790c1b25ce4805c6f5fe1f5f103ea51c9439869c04297763652f2970b94febc) echo 27.0.0.41303 ;;
    *) return 1 ;;
  esac
}
signin_ours() {
  local b
  [ -f "$1" ] || return 1
  for b in $S_BUILDS; do cmp -s "$1" "${HERE}/advapi32-fh6-$b.dll" && return 0; done
  return 1
}
# The fix for this prefix, or nothing when its advapi32.dll is not one a fix was built for.
signin_source() {
  local b
  if signin_ours "$S_LIVE"; then b="$(signin_build "$S_KEPT")" || return 1
  else b="$(signin_build "$S_LIVE")" || return 1; fi
  [ -f "${HERE}/advapi32-fh6-$b.dll" ] || return 1
  printf '%s\n' "${HERE}/advapi32-fh6-$b.dll"
}
# The override's data, not only its presence: a plain "native" would leave FH6 unable to
# start once an update puts Wine's builtin back.
signin_order_ok() {
  MGVF_KEY="$KEY" MGVF_NAME="$S_VALUE" MGVF_DATA="$S_ORDER" LC_ALL=C /usr/bin/perl -ne '
    BEGIN { ($h = lc "[$ENV{MGVF_KEY}]") =~ s/\\/\\\\/g; $want = lc "\"$ENV{MGVF_NAME}\"=\"$ENV{MGVF_DATA}\"" }
    if (/^\[/) { $in = lc(substr($_, 0, length $h)) eq $h && substr($_, length $h, 1) =~ /^[ \n]$/; next }
    if ($in && lc($_) =~ /^\Q$want\E\s*$/) { $ok = 1 }
    END { exit($ok ? 0 : 1) }' "$PFX/user.reg"
}
# "<in place> <total>": 0 0 where no fix fits this prefix.
signin_parts() {
  local src p=0
  src="$(signin_source)" || { echo "0 0"; return 0; }
  cmp -s "$S_LIVE" "$src" && p=$((p + 1))
  signin_order_ok && p=$((p + 1))
  echo "$p 2"
}
signin_install() {
  local src p t
  src="$(signin_source)" || {
    echo "note: this prefix's advapi32.dll is not one the Xbox sign-in fix was built for; FH6 asks for sign-in at each start."
    return 0
  }
  if ! cmp -s "$S_LIVE" "$src"; then
    signin_ours "$S_LIVE" || cp -p "$S_LIVE" "$S_KEPT"
    cp -p "$src" "$S_LIVE.mgf-new" && mv -f "$S_LIVE.mgf-new" "$S_LIVE"
  fi
  user_reg_edit "$PFX" set "$KEY" "$S_VALUE" "$S_ORDER" || {
    echo "error: advapi32.dll is in place, but its FH6-only override could not be written" >&2
    return 1
  }
  read -r p t < <(signin_parts)
  [ "$p" = 2 ] && [ "$t" = 2 ] && signin_build "$S_KEPT" >/dev/null || {
    echo "error: the Xbox sign-in fix did not verify" >&2
    return 1
  }
  echo "installed the Xbox sign-in fix (advapi32 CredEnumerateW) for forzahorizon6.exe"
}
signin_restore() {
  if signin_ours "$S_LIVE" && [ -f "$S_KEPT" ] && ! signin_ours "$S_KEPT"; then
    mv -f "$S_KEPT" "$S_LIVE"
  fi
  user_reg_edit "$PFX" delete "$KEY" "$S_VALUE" || true
}
