# God of War

| | |
| --- | --- |
| Symptom | White specks all over the characters, Kratos first, in dim light |
| Cause | The G-buffer pass tests depth with EQUAL against a depth prepass, and the translated shaders do not reproduce the prepass depth to the last bit |
| Fix | That depth test is created as GREATER_EQUAL |
| Backend | **DXMT**, D3D11 |
| CrossOver | Preview 27, through NotProton, under Rosetta and under FEX |

## First, try DXMT's own setting

DXMT can remove the specks itself, with no fix installed. Its setting
`d3d11.defuseFma` keeps Metal from fusing a multiply and an add into one
instruction differently in the two passes, so both compute the same depth and the
game's EQUAL test passes as it does on Windows. In NotProton, put this in the
game's launch options in Steam:

    CX_GRAPHICS_BACKEND=dxmt DXMT_CONFIG="d3d11.defuseFma=True" %command%

Played on 2026-10-26, DXMT in CrossOver Preview 27 through NotProton: no specks,
and with no fix installed nothing else is drawn wrong. This is the recommended way.
DXMT already uses the same setting by default for Shadow of the Tomb Raider. For
D3DMetal, `D3DM_POSITION_INVARIANCE=1` should do the same job; that has not been
tried here.

The fix below stays for anyone who wants it, but it has a cost. On 2026-10-22 a
player reported grass, leaves and branches near the camera drawn as solid
triangles and rectangles with it installed, on D3DMetal and on DXMT. Those are
alpha-tested cards: the prepass writes depth only where their silhouette is,
and GREATER_EQUAL lets the second pass paint the rest of each card over the
background behind it.

## The specks

The game draws a depth-only prepass and then draws the same geometry again into
its G-buffer, with depth writes off, stencil on and the depth test set to EQUAL.
A pixel survives only if its depth matches the prepass exactly. On Windows the
GPU computes the same position bit for bit in both passes. Translated to Metal,
the two passes need not agree to the last bit, and the pixels that disagree are
discarded before any lighting runs. That is why the specks stay even with the
lighting forced to black.

The cause was found by a r/macgaming poster, "God Of War 2018 White Dot Fix
(through Crossover)", with a `d3d11.dll` proxy that bisected the game's shaders
and states live and showed that GREATER_EQUAL in place of EQUAL removes every
speck.

## The fix

A depth-stencil state whose test is EQUAL is created with GREATER_EQUAL
instead. Nothing else changes. Measured on DXMT in CrossOver Preview 27:

| | Without the fix | With the fix |
| --- | --- | --- |
| Rosetta (x86_64 DXMT) | specks | none |
| FEX (aarch64 DXMT) | specks | none |

The game creates the state about forty times, always the same kind (depth writes
off, stencil on), and the log counts them. D3DMetal is said to show the same
specks; that has not been measured here.

The risk, as the poster says: something drawn after the prepass that was not in
it would now draw through. It was seen on 2026-10-22: alpha-tested grass and
branches near the camera drawn as solid shapes (see above).

`gow-depth-fix.ini` beside the game sets what an EQUAL test becomes:
`greater_equal` (the default), `less_equal` or `off`.

## Where it hooks

The poster's fix is a `d3d11.dll` that needs a DLL override and a copy of DXMT's
own `d3d11.dll`, re-copied after every CrossOver update. This one rides on
`libSceJobManager.dll`, which the game imports and no runner ships, and copies
nothing. `GoW.exe` imports `d3d11.dll` directly, so its import table is pointed
at this DLL's `D3D11CreateDevice` and `D3D11CreateDeviceAndSwapChain`. The device
that comes back, DXMT's or D3DMetal's, has `CreateDepthStencilState` hooked. A
DXMT update needs nothing done.

## Install

    runtime/install-gow-fix.sh "<…>/steamapps/common/GodOfWar"
    runtime/install-gow-fix.sh "<…>/steamapps/common/GodOfWar" --status
    runtime/install-gow-fix.sh "<…>/steamapps/common/GodOfWar" --restore

Or pick the game in the app.
