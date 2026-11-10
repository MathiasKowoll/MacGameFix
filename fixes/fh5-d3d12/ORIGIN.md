# Origin and MacGameFix adaptation

This directory is the GPL-3.0 D3D12 proxy source bundled by
[`Andytizer/fh5-crossover-steam-fix` v1.0.1](https://github.com/Andytizer/fh5-crossover-steam-fix/releases/tag/v1.0.1),
commit `8ab0b746e77cb765547f0f8f0d59411b13cab51b`. That release preserved the
source after xvferxedd's original repository, `github.com/xvferxedd/fh5-d3dmetal-fix`
(its tree at commit `ebd20dbe6572751ff94f6c7e90e5cebf7d96a0ce`, 2026-11-05),
went offline together with its author's account.

The proxy is based on Gauthier Piarrette's Highball `tsshim` and retains its
GPL-3.0 license. The repository root's `LICENSE` contains the full terms.

MacGameFix changes only the default path used to find the real D3DMetal module:
instead of the reference setup's bare `d3d12_d3dmetal.dll`, it loads
`C:\windows\system32\apd12.dll`. `install-fh5-fix.sh` constructs that private
alias from the selected NotProton/CrossOver runner's own D3DMetal module and
changes its PE export name. No D3DMetal binary is distributed by MacGameFix.

`build-fh5-d3d12.sh` builds the shipped `d3d12-fh5.dll` from these files.
