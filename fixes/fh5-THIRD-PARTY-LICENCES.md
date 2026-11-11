# Forza Horizon 5 and 6 D3DMetal fixes, and the FH5 network fix

The files under `fh5-d3d12/` are derived from Highball's `tsshim` by Gauthier
Piarrette and from xvferxedd's Forza Horizon 5 work, `fh5-d3dmetal-fix`
(originally `github.com/xvferxedd/fh5-d3dmetal-fix`, no longer online), as
preserved in `Andytizer/fh5-crossover-steam-fix` v1.0.1. They are GPL-3.0. The precise
provenance and MacGameFix's path adaptation are in `fh5-d3d12/ORIGIN.md`.

`d3d12-fh5.dll` and `d3d12-fh6.dll` are built from those sources by their
respective builders. They are not published release DLLs. FH6 is a separate
compile-time profile that retains the general `tsshim` compatibility paths and
FH6 shader fixes while omitting FH5's descriptor translation and guards. Each
installer builds the private `apd12.dll` alias from the user's selected runner,
so MacGameFix does not redistribute Apple's D3DMetal module.

`fh5-netfix.c` is derived from the `ws2_32-netfix` component of
`xvferxedd/fh5-d3dmetal-fix`, commit
`ebd20dbe6572751ff94f6c7e90e5cebf7d96a0ce`, recovered in
[`Andytizer/fh5-crossover-steam-fix`](https://github.com/Andytizer/fh5-crossover-steam-fix)
version 1.0.1. Copyright belongs to its original contributors.

That component and this derivative are licensed under the GNU General Public
License, version 3. A copy of the licence is in the repository root as
`LICENSE`.

No prebuilt DLL from the recovered project is redistributed here. The
`ws2_32-fh5.dll` payload is built from `fh5-netfix.c` by
`build-fh5-netfix.sh` against the target Wine's own export table.
