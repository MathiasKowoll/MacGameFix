# Launch options

The line to play with, in the game's launch options in Steam:

```
NOTPROTON_ROSETTA_PIPELINE_CACHE=1 D3DM_SUPPORT_DXR=0 %command%
```

| Variable and value | What it does |
|---|---|
| `NOTPROTON_ROSETTA_PIPELINE_CACHE=1` | Needed in NotProton. Turns the pipeline cache on (see Shaders). MacGameFix writes it itself when you install the fix and keeps the options you already had. Quit Steam first, or it cannot save them, and do not remove it afterwards: without it the game compiles its shaders again at every start. |
| `D3DM_SUPPORT_DXR=0` | Needed for DLSS. With DLSS available the game closes as it loads a level, whatever upscaler is chosen; this keeps DLSS and stops that. Write it yourself, before `%command%`. |

If you would rather not use DLSS, `D3DM_ENABLE_METALFX=0` in its place turns DLSS off, and you choose TSR in the game. TSR ran better than DLSS in play, but that was not measured.

# Shaders

The game compiles about 66,000 Metal pipelines while it loads, about 8 GB of GPU code. Metal's own cache stops at about 1.1 GB a file, so without the pipeline cache some 40% of them are compiled again at every start, and the loading bar slows down from about 60%.

With the cache, the first start compiles everything once and keeps it: on a MacBook Pro M4 Max that took about 15 minutes and wrote 7.9 GB. From the next start on, only the few pipelines the game has never asked for before are compiled (113 and 133 in the two starts measured, on 2026-11-20), and the game loads quickly.

- The cache is in your user cache folder, `notproton-rosetta/pipelines/PBZ_exe/`. It is limited to 10 GB.
- After a macOS update or on another GPU, the cache starts over in a folder of its own, because the compiled code is not valid there. The first start after an update is a slow one again.
- Removing the fix takes the launch option out, but leaves the cache folder where it is.

# CrossOver

The pipeline cache works in NotProton only: CrossOver has no way to load it. In a CrossOver bottle the rest of the fix is installed, and the game keeps compiling part of its shaders at every start.

# Optional

Add these yourself if you want them; none is needed to play.

| Variable and value | What it does |
|---|---|
| `MGF_FANS=max` | Runs both fans at full speed while the game runs. Turn **Improvements › Fans** on in MacGameFix first: it installs the helper that does it. |
| `MTL_HUD_ENABLED=1` | Shows the Metal HUD. |

# After an update

If a NotProton or prefix update leaves the fix partial, install it again, with Steam closed.
