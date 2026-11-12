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
CodeWeavers' 26.3, 41073 and 41303 `advapi32` and succeeds, count 1, with these. With the
41303 one, FH6 started without asking for sign-in, and `Xbl|DeviceKey` and the device
token were not rewritten.

## Where it goes

`../fh6-signin.sh` puts the file in the prefix's `system32\advapi32.dll`, keeping Wine's
copy as `advapi32.dll.mgf-fh6-original`, and sets `advapi32=native,builtin` under
`AppDefaults\forzahorizon6.exe`. Only `forzahorizon6.exe` loads it; every other program in
the prefix, Wine's own services included, keeps the builtin. No runner and no CrossOver app
is changed, so the same fix works in a NotProton prefix and a CrossOver bottle.

`advapi32` is a KnownDLL. Wine's `wineboot` maps the KnownDLLs from `system32` at start, and
the loader takes them from there before it looks in the game's folder: a copy beside the
game is never seen, and `advapi32=native` then fails every import with `c0000135` (FH6
stopped before its first window). A builtin in `system32` does not help either: Wine loads
builtins from its own `lib` folder. When an update of the prefix puts Wine's copy back,
`native,builtin` falls back to the builtin, measured in a probe prefix: the game starts
and asks for sign-in until the fix is installed again.

## Files

`0001-advapi32-credenumerate-host-not-found.patch` takes the host's `ERROR_NOT_FOUND` as no
host credential, in both of `CredEnumerateW`'s passes. It applies with no fuzz to Wine 11.0
(`crossover-sources-26.3.0`, CrossOver 26.3.0.39832), 11.17 (`crossover-sources-20261015`,
Preview 27.0.0.41073) and 11.21 (`crossover-sources-20261111`, Preview 27.0.0.41303).
`../build-fh6-advapi32.sh <build> <source>` builds the x86_64 half and clears the 32-byte
Wine builtin signature at 0x40, since Wine refuses a native DLL that says it is a builtin.
A rebuild differs only by its PE timestamps.

| File | sha256 |
|---|---|
| `advapi32-fh6-26.3.0.39832.dll` | bc17c8e2e6732958ffa8cfa9600f38ca7138a527389ebde0e466b87120436cb2 |
| `advapi32-fh6-27.0.0.41073.dll` | c6099256afd011829c1ff7d2343bf9b318ed04221ee52046dd65834e52ded176 |
| `advapi32-fh6-27.0.0.41303.dll` | 7497a062cecd0c24591e9663d5b97d360add45715db53ec382849a411637aca5 |
| CrossOver 26.3's own `advapi32.dll`, which picks the 26.3.0.39832 file | 0375c2ee0e61be9fc3064a07b52f65e73d8a74b06fd06b59ea9e958365a33940 |
| CrossOver 41073's own `advapi32.dll`, which picks the 27.0.0.41073 file | 7c5e5f2f573e001eabfc39d252428dfcc79c773262b7d00b46301f53fb143dab |
| CrossOver 41303's own `advapi32.dll`, which picks the 27.0.0.41303 file | 8790c1b25ce4805c6f5fe1f5f103ea51c9439869c04297763652f2970b94febc |

Wine is LGPL-2.1-or-later, and so are these files.
