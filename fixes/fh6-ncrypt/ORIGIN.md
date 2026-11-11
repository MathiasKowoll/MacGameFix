# ncrypt with persisted keys, for Forza Horizon 6's Xbox sign-in

FH6 asked for Xbox sign-in at every start under Wine. XAL keeps its device key as
a named CNG key (`NCryptCreatePersistedKey`, then `NCryptOpenKey` by that name at
the next start) and stores only a reference to it in the Credential Manager
(`Xbl|DeviceKey`: a GUID and 21 bytes). Wine 11.17's `ncrypt` ignores the name
("Persistent keys are not supported") and `NCryptOpenKey` is a stub that returns
`NTE_NOT_SUPPORTED`, so XAL made a new key at every start, which is a new device to
Xbox. Seen on 2026-11-11: 54 s into a start, `Xbl|DeviceKey` was written again,
then a new device token, then the whole sign-in.

`0001-ncrypt-persisted-keys.patch` keeps a named key in the registry, under
`Software\Wine\NCrypt\Keys\<name>` in the user's hive (the machine's with
`NCRYPT_MACHINE_KEY_FLAG`): its algorithm and its private key blob, protected with
DPAPI. `NCryptFinalizeKey` writes it, `NCryptOpenKey` reads it (`NTE_BAD_KEYSET`
when there is none), `NCryptDeleteKey` removes it, and `NCryptCreatePersistedKey`
returns `NTE_EXISTS` for a kept name without `NCRYPT_OVERWRITE_KEY_FLAG`, as
Windows does. RSA and ECDSA P-256 keys, the two this `ncrypt` creates. A probe
created a P-256 key in one process and opened it in another (the same public key),
and after `NCryptDeleteKey` opening it gave `NTE_BAD_KEYSET`.

Source: `wine/` from CodeWeavers' `crossover-sources-20261015.tar.gz`, the sources
of CrossOver Preview 27.0.0.41073, with this patch. `../build-fh6-ncrypt.sh` builds
it (x86_64 only; FH6 runs on the Intel side). A rebuild differs from the shipped
file only by its PE timestamps; the code is the same.

| File | sha256 |
|---|---|
| `ncrypt-fh6.dll` | 9b5596636467b9f3f489eafdc6d9faea9de26328b1478046210ff0f9ee5a873b |
| CrossOver 41073's own `x86_64-windows/ncrypt.dll`, which the installer requires | ae9f0b9b3e90cbcb97892b5b884e63df95e323a28827dabe2ef04d64b6264abd |

`install-fh6-fix.sh` puts it beside the game as `ncrypt.dll` with an
`ncrypt=native` override for `forzahorizon6.exe` only, and only onto a runner whose
own `ncrypt.dll` is 41073's. A newer CrossOver needs it built from that release's
sources. Wine is LGPL-2.1-or-later, and so is this file.
