# Pipeline cache for Phantom Blade Zero

Phantom Blade Zero compiles about 66,000 Metal pipelines while it loads. D3DMetal keeps its
own DXIL translation, but the GPU code Metal compiles from it goes to Metal's system cache,
`<user cache>/<bundle>/com.apple.metal/<GPU>/functionsN.data`, and each of those files stops
at about 1.11 GB. PBZ's pipelines need about 8 GB, so every start found the file full and
compiled roughly 40% of them again.

`rosetta_pipeline_cache.mm` and `pipeline_cache.mm` are a plugin NotProton loads into a
Rosetta game's processes when its switch, `NOTPROTON_ROSETTA_PIPELINE_CACHE=1`, is in the
game's launch options. It waits until D3DMetal asks Metal for a device, then keeps every
pipeline D3DMetal compiles as an archive of its own in
`<user cache>/notproton-rosetta/pipelines/<exe>/<GPU>-<OS build>/classic/`, and looks each
pipeline up there before Metal compiles it. What it writes stops at
`NOTPROTON_ROSETTA_PIPELINE_CACHE_MAX_MB` (10240). A new macOS build or another GPU gets a
folder of its own, since the GPU code is not valid across them.

## Measured

On 2026-11-20 with the NotProton runner for CrossOver Preview 41303, Rosetta side, M4 Max,
macOS 26B131:

| | Before (Metal's cache only) | First start with the plugin | Second start with the plugin |
|---|---|---|---|
| Pipelines compiled | ~40% again on every start | 65,685 (all) | 113 (0.17%), new to that session |
| Plugin cache | — | 7.9 GB in ~15 min | +11 MB |
| Game's memory | — | up to 14 GB | 13 GB |

Metal's five files stayed at their cap throughout; no `gpuarchiver` folders were left
behind, and no half-written archive.

## Where it comes from

NotProton's `experiments/fex-d3dmetal-bridge` at commit 4c8b173 (Mathias Kowoll, GPL-3.0),
the same author as this repository. The files are copied unchanged. `../build-pbz-pipeline-cache.sh`
builds them as that experiment's Makefile does and checks the hash it gave.

## Where it goes

`../install-pbz-fix.sh`, for a NotProton prefix only, copies the signed library to
`~/Library/Application Support/notproton/plugins/notproton-rosetta-pipeline-cache.dylib`,
writes the descriptor `rosetta-pipeline-cache.conf` beside it if there is none, and adds
`NOTPROTON_ROSETTA_PIPELINE_CACHE=1` to PBZ's Steam launch options (`../steam-launch-options.pl`).
A CrossOver bottle gets none of this: CrossOver has no way to load the plugin.
