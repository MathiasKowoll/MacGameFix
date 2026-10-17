# Mortal Kombat 11

One fault, fixed at its cause: D3DMetal reads a three-float buffer view as if it
held two floats, DXMT as if it held one, and the face morph reads its deltas
from one.

| | |
| --- | --- |
| Symptom | Bare faces -- forehead, brows, around the eyes -- turn into smeared dark patches with hard edges that follow the light and change from frame to frame. Clean right after a screen loads, broken once the face animates; barely visible in a fight, glaring in close views, the character select and the fatalities. Masked fighters never show it. It has been there since at least an M1 Pro |
| Cause | The face morph reads its per-vertex deltas from `DXGI_FORMAT_R32G32B32_FLOAT` buffer views, and D3DMetal serves those as two floats an element with z = 0 |
| Fix | Every such view is created as an `R32_FLOAT` view three times as long, and the two morph shaders read a delta's three floats one by one |
| Backend | **D3DMetal** with D3D12 (`MK11_DX12.exe`) and **DXMT** with D3D11 (`MK11.exe`): one install covers both, whichever Steam starts |
| CrossOver | Preview 27 through NotProton, Game Porting Toolkit 4.0b3 (2026-10-16 and 17) |

## Where it comes from

A face's expression is a set of morph targets. For each one, a compute pass --
`cs_9f038ca4`, or `cs_b947e8cb`, which has no mask -- adds
`PositionDeltas[i] * Weight` to the vertices the target moves, the first scaled
by the alpha of each vertex's colour. `PositionDeltas` is a `Buffer<float3>`, and
the game creates its views as `R32G32B32_FLOAT`. After the morph and the
skinning, two more compute passes recompute the face's tangent frame from the
deformed positions (`cs_cb994f68` sums each triangle's tangent and normal per
vertex, `cs_6f7a24b6` normalises them). The hashes are vkd3d-proton's.

Metal has no three-float texel format. Read on the game's own device, with a
test shader of the probe's over a buffer holding 0, 1, 2, ...:

| View | Element 0, 1, 2 | D3D12 gives |
| --- | --- | --- |
| `R32G32B32_FLOAT`, first element 0 | (0 1 0) (2 3 0) (4 5 0) | (0 1 2) (3 4 5) (6 7 8) |
| `R32G32B32_FLOAT`, first element 4 | (8 9 0) (10 11 0) (12 13 0) | (12 13 14) (15 16 17) (18 19 20) |
| `R32G32B32A32_FLOAT`, control | (0 1 2 3) (4 5 6 7) (8 9 10 11) | the same |
| `R32_FLOAT`, control | (0) (1) (2) | the same |

So D3DMetal 4.0b3 reads element *i* of a view starting at element *F* as the
floats 2F+2i and 2F+2i+1, and z as 0. Every expression then moves every vertex
it touches by a small, wrong amount. The face keeps roughly its shape, which is
why a fight at a distance hides it, but the recomputed tangent frame turns the
crumpled surface into the patches.

DXMT has its own form of it, read from its source: an `R32G32B32_FLOAT` buffer
view becomes a texture buffer of `R32Float`, and a typed load of element *i*
reads the single float at element *i + F*. That explains why the patches looked
the same on both translators, and the same fix cleared them under DXMT
(2026-10-17).

Of the 11,428 shaders the game created in the sessions measured, 19 declare a
three-float typed buffer: the two morph passes and 17 geometry-cache shaders
(`GeomCachePositions`). In the measured fight two of the geometry-cache shaders
ran; they are not rewritten. If their views are three-float ones they were wrong
before the fix as well (z = 0), and nothing visibly wrong was reported either
way.

## How it was found

Like the CONTROL Resonant shader, by elimination: the pipelines bound on the
character select were logged per ten-second window and groups of them were kept
from running. Skipping the tangent recompute removed most of the patches, and
MacGameFix 1.4.1 shipped that as a workaround; faint patches stayed.

The recompute's own maths was not at fault: a rewrite with robust weights and
strict IEEE arithmetic changed nothing. Its input positions come from the
dual-quaternion skinning, and before that from the morph. Reading the morph's
typed loads led to the formats of the game's buffer views (6,275
`R32G32B32_FLOAT` views in one session, none starting off a 16-byte boundary)
and to the self-test above. With the views converted and the morph rewritten,
the tangent recompute running as the game has it, the character select and a
fatality close-up were clean (2026-10-17), on D3DMetal and then on DXMT.

## What it is not

Each of these was one variable against the same screen, and none changed the
patches:

- the graphics settings: shadow quality at every level including Soft and Ultra,
  texture quality, anti-aliasing, ambient occlusion, anisotropic filtering and
  lighting quality, all at their lowest at once;
- the shadows themselves: the moment-shadow resolve skipped entirely, and the
  capsule shadows, which this game never runs;
- the battle damage painted on the faces, skipped;
- the depth test: the EQUAL test after the prepass created as GREATER_EQUAL, as
  for God of War;
- D3DMetal's switches: Metal 4 off, `D3DM_POSITION_INVARIANCE`,
  `D3DM_BOUNDS_CHECK`, `D3DM_SAMPLE_NAN_TO_ZERO` and `D3DM_FLUSH_POS_INF_TO_NAN`;
- the identity D3DMetal reports (AMD without MetalFX, NVIDIA with it);
- synchronisation: a UAV barrier after every compute dispatch, one after the last
  morph dispatch, one in front of every transition out of UAV state, and the CPU
  waiting for the GPU after every submission;
- typed buffer views past element 2^28, or starting off a 16-byte boundary
  (Metal rounds such a texture buffer down, measured): none in this game;
- the CPU translation: AVX advertised or not. FEX would not start the game.

## The fix

`install-mk11-fix.sh` puts `amd_ags_x64.dll`, built from `mk11-face-fix.c`, in
`Binaries/Retail`, with the game's own kept as `amd_ags_x64_real.dll`. Both
executables import it, and the fix sees which API the one running imports.

- **DirectX 12.** `MK11_DX12.exe` imports `D3D12CreateDevice` by ordinal, so the
  executable's import slot is pointed at the fix. The two morph shaders are
  replaced, by hash, with rewrites in `fixes/mk11-morph/`, compiled to DXIL with
  the DXC inside D3DMetal (`tools/hlslc.c`) into `mk11-morph-shaders.h`.
- **DirectX 11.** `MK11.exe` imports `D3D11CreateDevice` by name; AMD's library
  can also create the device, so a device of the fix's own reaches the same class
  if the game's is not seen in time. Here the game's own bytecode is edited as it
  is handed over (`rgb32-loads.c`): the one load from `PositionDeltas` becomes
  three one-float loads, with the container's checksum recomputed
  (`dxbc-checksum.c`, from vkd3d-shader). A morph shader is found by its
  resources, so nothing of the game's ships with the fix.

The rewrites' arithmetic is the game's. A game update that changes a morph
shader makes the DirectX 12 rewrite match nothing, and the log says no morph
pipeline was replaced.

The log is `mk11-face-fix.log` beside the DLL; after the first minute it says
how many morph pipelines were replaced and how many views were converted.
