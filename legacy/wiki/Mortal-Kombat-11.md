# Mortal Kombat 11

One fault, worked around rather than fixed. Most of the damage goes with the fix;
faint patches remain, and what makes the faces wrong in the first place was not
found.

| | |
| --- | --- |
| Symptom | Bare faces -- forehead, brows, around the eyes -- turn into smeared dark patches with hard edges that follow the light and change from frame to frame. Clean right after a screen loads, broken once the face animates, the character select included. Masked fighters never show it |
| Cause | The tangent frame the game recomputes for a face after deforming it comes out wrong on this Mac. Why is not known |
| Fix | The two compute passes of that recompute are skipped, so the face keeps the tangent frame it was animated with |
| Backend | **D3DMetal**, D3D12 (`MK11_DX12.exe`). DXMT with the DirectX 11 executable shows the same patches, and the fix does not cover it |
| CrossOver | Preview 27 through NotProton, Game Porting Toolkit 4.0b3 (2026-10-16 and 17) |

## Where it comes from

After a face is deformed for its expression, two compute shaders give it a fresh
tangent frame. `cs_cb994f68` takes each triangle of the deformed face, computes
its tangent and normal, weights them by the angle at each corner, scales them by
32767 and adds them into an integer accumulator per vertex with
`InterlockedAdd`. `cs_6f7a24b6` normalises the sums, makes the tangent
orthogonal to the normal and packs both as 10:10:10:2. The hashes are
vkd3d-proton's.

It was found the way the CONTROL Resonant shader was: the pipelines bound on
the character-select screen were logged per ten-second window, and groups of them
were kept from running. Skipping the two passes above removed the patches around
the eyes and most of the rest; faint ones stayed on the forehead and a cheek.
Skipping their neighbours as well -- the copy of the base mesh and the clear of the
accumulator -- removed the skin itself, so those are needed.

## What it is not

Each of these was one variable against the same screen, and none changed the
patches:

- the graphics settings: shadow quality at every level including Soft and Ultra,
  texture quality, anti-aliasing, ambient occlusion, anisotropic filtering and
  lighting quality, all at their lowest at once;
- the shadows themselves: the moment-shadow resolve skipped entirely (the frame
  went darker and the patches stayed), and the capsule shadows, which this game
  never runs;
- the battle damage painted on the faces, skipped;
- the depth test: the EQUAL test after the prepass created as GREATER_EQUAL, as
  for God of War;
- D3DMetal's switches: Metal 4 off, `D3DM_POSITION_INVARIANCE`,
  `D3DM_BOUNDS_CHECK`, `D3DM_SAMPLE_NAN_TO_ZERO` and `D3DM_FLUSH_POS_INF_TO_NAN`;
- the identity D3DMetal reports (AMD without MetalFX, NVIDIA with it);
- synchronisation: a UAV barrier after every compute dispatch, one after the last
  morph dispatch, one in front of every transition out of UAV state, and the CPU
  waiting for the GPU after every submission;
- the maths of the accumulation: `cs_cb994f68` replaced by a rewrite with robust
  corner weights and strict IEEE arithmetic, compiled with the DXC that ships
  inside D3DMetal;
- typed buffer views past element 2^28: none reaches 2^26;
- the CPU translation: AVX advertised or not. FEX would not start the game.

Measured natively on the M4 Max with Metal kernels: a float-to-int conversion of
NaN gives 0 and saturates infinities, as D3D does, and 16-byte loads and stores
at a 28-byte stride read and write the right bytes.

So the recompute's own maths and its ordering are cleared. What feeds it is the
suspect: the face's deformed positions, which come from a compressed geometry
cache decoded per frame, and whose small errors only a recomputed normal would
show. That is not measured.

## The fix

`install-mk11-fix.sh` puts `amd_ags_x64.dll`, built from `mk11-face-fix.c`, in
`Binaries/Retail`, with the game's own kept as `amd_ags_x64_real.dll`. The game
imports `D3D12CreateDevice` by ordinal, so the executable's import slot is
pointed at the fix, and a device of its own reaches the same class if the game's
is not seen in time. The dispatches of the two shaders, direct and through
`ExecuteIndirect`, are skipped. A game update that changes either shader makes
the fix match nothing and do nothing.

Start the game with **DirectX 12** when Steam asks. The log is
`mk11-face-fix.log` beside the DLL; after the first minute it says how many
dispatches were skipped.
