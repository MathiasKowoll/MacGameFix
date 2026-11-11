# advapi32 for Forza Horizon 6's Xbox sign-in

FH6 asked for Xbox sign-in at every start under Wine on macOS. XAL looks its device
key up with `CredEnumerateW("Xbl|DeviceKey*")`. Wine's `CredEnumerateW` reads the
registry, where the key is, and then the host's keychain through mountmgr, whose
`search_credentials` answers `STATUS_NOT_FOUND` when nothing there matches. Only
`ERROR_NOT_SUPPORTED` was taken as "no host credential", so the whole call failed with
`ERROR_NOT_FOUND` (1168) although the registry held the key. XAL then generated a new
device key, Xbox saw a new device, and the sign-in was asked again.

Measured on 2026-11-11 with a Wine trace of FH6 on the Preview 41303 runner: 18
`CredEnumerateW` calls, each failing after its first pass, and `BCryptGenerateKeyPair`
right after the `Xbl|DeviceKey*` lookup, with no import of the stored key. A probe that
writes `MgfTest|DeviceKey` and enumerates `MgfTest|DeviceKey*` fails with 1168 on
CodeWeavers' 41073 and 41303 `advapi32` and succeeds, count 1, with these. With the
41303 one in place of the builtin `advapi32.dll` of FH6's runner clone, FH6 started without
asking for sign-in, and `Xbl|DeviceKey`, the device token and the account ticket were not
rewritten. The same file with its builtin signature cleared, beside the game as a native DLL
with `advapi32=native` for `forzahorizon6.exe`, does not load: every importer of `advapi32`
failed and FH6 stopped with `c0000135` before its first window.

`0001-advapi32-credenumerate-host-not-found.patch` takes the host's `ERROR_NOT_FOUND` as no
host credential, in both of `CredEnumerateW`'s passes. It applies with no fuzz to Wine 11.17
(`crossover-sources-20261015`, Preview 27.0.0.41073) and 11.21 (`crossover-sources-20261111`,
Preview 27.0.0.41303). `../build-fh6-advapi32.sh <build> <source>` builds the x86_64 half,
a Wine builtin like the file it replaces. A rebuild differs only by its PE timestamps.

| File | sha256 |
|---|---|
| `advapi32-fh6-27.0.0.41073.dll` | cdb0be388d43466ba9ae8f1bf23ffe2ad5856d48a68c063fab86c64de778b143 |
| `advapi32-fh6-27.0.0.41303.dll` | 649f1c770516685a89c8198dcaad5bdc3f062654ac8863b112fb391bc7aabe18 |
| CrossOver 41073's own `x86_64-windows/advapi32.dll`, which the installer requires | 7c5e5f2f573e001eabfc39d252428dfcc79c773262b7d00b46301f53fb143dab |
| CrossOver 41303's own `x86_64-windows/advapi32.dll`, which the installer requires | 8790c1b25ce4805c6f5fe1f5f103ea51c9439869c04297763652f2970b94febc |

Wine is LGPL-2.1-or-later, and so are these files.
