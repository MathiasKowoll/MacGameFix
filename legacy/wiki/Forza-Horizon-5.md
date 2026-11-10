# Forza Horizon 5

| | |
| --- | --- |
| Symptom | After Xbox sign-in, **Continue** stays in a blurred loading screen and returns to the menu or never ends |
| Cause | D3DMetal reports a 24-byte CBV/SRV/UAV descriptor where FH5 sizes its descriptor pool for NVIDIA's 32, among other D3D12 gaps |
| Fix | A source-built D3D12 proxy reports 32 and translates every handle to D3DMetal's 24; an Xbox UDP proxy keeps the online socket open |
| Backend | **D3DMetal** 4, D3D12 |
| CrossOver | NotProton's `crossover-27.0.0.41073-fex` runner, Steam Play prefix |

## Current result

Tested on 2026-11-10 with the native macOS Steam, NotProton's
`crossover-27.0.0.41073-fex` FEX runner, D3DMetal 4 and Steam build 688.109.
Xbox sign-in completes, **Continue** advances through **Please wait** and
**Optimizing for your PC**, and the game plays. Before the D3D12 proxy it stayed
in the blurred loading screen indefinitely. Validated that day with exactly the
layout `install-fh5-fix.sh` makes, with the game folder's own
`amd_ags_x64.dll` (no other carrier), and with the launch variables and the
WebView2 setting under "Xbox sign-in".

## Cause and fix

The embedded Xbox WebView was not waiting for another browser callback after
Continue. Network connections stayed healthy, the WebView made no new request
or script call during the old loop, and the stable waiting thread was a parked
startup thread rather than the game loop. The missing
`Windows.Internal.Security.WebAuthentication.AuthenticationManager` string
came from WebView2's SmartScreen library, not from Forza's authentication code.

The transition changed only when the GPL D3D12 proxy from the source preserved
in `Andytizer/fh5-crossover-steam-fix` v1.0.1 was placed in front of D3DMetal.
The proxy contains Highball's generic D3D12 compatibility work and FH5's
descriptor-stride translation. D3DMetal reports a 24-byte CBV/SRV/UAV
increment, while the NVIDIA-like device FH5 sizes its descriptor pool around
32 bytes. The proxy reports 32 to the game and translates the handles back to
D3DMetal's real 24-byte layout. It also supplies timestamp queries and guards
or translates the other D3D12 behaviours documented in `fixes/fh5-d3d12/`.

The successful run loaded all three layers at once:

- the source-built game-folder `d3d12.dll`;
- the private `apd12.dll` alias made from the selected runner's D3DMetal; and
- Apple's D3DMetal framework and `libd3dshared.dylib`.

The real module needs both its Windows and Unix halves. Wine also needs a
physical `apd12.dll` in the prefix's `system32` before an absolute
`C:\windows\system32\apd12.dll` load resolves the renamed builtin module. A
small loader test first proved that path and `D3D12CreateDevice`; the game run
then proved the proxy creates its D3D12 device and passes Continue.

## Xbox sign-in

The sign-in window is FH5's own WebView2 (Edge 91, in the game folder's
`webview2`). Two settings were needed on this runner before the session reached
`oauth20_desktop.srf?status=success`. Both were measured before the D3D12 proxy
existed, both were in the validated profile, and the installer writes both into
the prefix:

- WebView2 as Windows 7: `"Version"="win7"` under
  `HKCU\Software\Wine\AppDefaults\msedgewebview2.exe`. Without it a NULL
  `+0x30` read in a WebView2 window message ends the session right after login.
- `--disable-features=CalculateNativeWinOcclusion` as WebView2's extra browser
  arguments. `--disable-gpu` instead turns the login page black. Edge 91 reads
  these from `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` and also from the policy
  key `HKCU\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments`,
  by the host executable's name (both names are in its
  `EmbeddedBrowserWebView.dll`). The installer writes
  `"ForzaHorizon5.exe"` there, so the launch option is no longer needed.

A value found there before is kept in the prefix's `.mgf-fh5-signin` and put
back by `--restore`. Whether either is still needed once the account is signed
in is not measured. The reference setup used both only for a one-time sign-in
through DevTools and then removed them.

The GPU identity (`D3DM_VENDOR_ID`, `D3DM_DEVICE_ID`,
`D3DM_DEVICE_DESCRIPTION`) is a different case. D3DMetal reads it inside
`D3DMetal.framework`, with the native environment, so no registry value reaches
it and it stays a launch option.

## Online socket

FH5 opens Xbox Live's UDP socket as dual-stack IPv6 on port 3074. Wine does not
implement `SIO_UDP_NETRESET`, and macOS rejects the IPv4 option the game applies
to that IPv6 socket. The game closes the socket after either failure.
`fh5-netfix.c` makes the first operation succeed and applies the IPv6
equivalent of the second. Its log confirmed both translations and the open
socket. This is for Horizon Life and Horizon Open; it was not the cause of the
post-login loading loop.

## Reproducible MacGameFix layout

`fixes/install-fh5-fix.sh` performs and reverses the complete installation:

1. validates that the shipped proxy's exports match the selected D3DMetal;
2. builds `apd12.dll` from that runner's own DLL by changing its PE export name;
3. places the Windows alias and a Unix-half link in the base runner and the
   existing NotProton per-game clone;
4. places the discovery copy in the prefix and the source-built proxy in the
   game folder;
5. writes native overrides for `d3d12` and `ws2_32` only under
   `ForzaHorizon5.exe`; and
6. keeps displaced files and restores them byte for byte.

No DLL from the reference release is installed. `build-fh5-d3d12.sh` and
`build-fh5-netfix.sh` rebuild the two payloads from the GPL sources, and
`check-builds.sh` compares their exports and meaningful strings with those
sources. `test-installers.sh` exercises absent, install, reinstall and restore
on a throwaway runner and prefix.

NotProton still needs the NVIDIA identity variables printed by the installer.
They were present in the successful run. Whether all three remain necessary
after the descriptor proxy is a separate test; do not remove them from the
known-working profile yet.

## Open

- Verify Horizon Life or Horizon Open, not only that the UDP socket remains
  open.
- Test whether the NVIDIA identity variables can be reduced without bringing
  back FH302 or the loading failure.
- Sign in with the WebView2 launch option removed, to prove the policy key alone.

## Credits

- **xvferxedd**, `fh5-d3dmetal-fix` (GPL-3.0), originally at
  `github.com/xvferxedd/fh5-d3dmetal-fix`. The repository and its author's
  account are no longer online. The descriptor translation, the D3D12 work and
  the Xbox UDP diagnosis are theirs.
- **Andytizer**,
  [fh5-crossover-steam-fix](https://github.com/Andytizer/fh5-crossover-steam-fix),
  whose v1.0.1 keeps that tree under
  [`upstream/source`](https://github.com/Andytizer/fh5-crossover-steam-fix/tree/main/upstream/source).
- **Gauthier Piarrette**, [Highball](https://github.com/gauthierpiarrette/highball):
  the `tsshim` base of the D3D12 proxy.
- **MACxus**, credited upstream for the FH5 profile with the NVIDIA identity.
- **ADM1SH**, [Forza-Horizon-5-for-mac](https://github.com/ADM1SH/Forza-Horizon-5-for-mac):
  research notes on the same build that pointed at the memory counters and the
  WebView2 fatal at `exe+92df62`.
