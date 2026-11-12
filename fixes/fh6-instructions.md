# Launch options

FH6's improvement needs these four in the game's Steam launch options. MacGameFix writes them there itself when you install the improvement, and keeps the options you already had. Quit Steam first, or it cannot save them, and do not remove them afterwards.

| Variable and value | What it does |
|---|---|
| `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1` | Turns on accelerated handling of supported exception chains in FH6. Needs MacGameFix's `ntdll`. |
| `NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1` | Turns on the operations the fast path supports, including LEA, INC, XOR, TEST and MUL. Result and flag checks are kept. |
| `NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0` | Keeps the extended resume into normal code off. This is the conservative setting that was validated. |
| `NOTPROTON_ROSETTA_TRAP_BOOST=1` | Turns on the priority plugin, which cuts scheduling waits while exceptions are handled under Rosetta. Independent of Game Mode. |

The same four as one line, for Steam's Launch Options field:

```
NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1 NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1 NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0 NOTPROTON_ROSETTA_TRAP_BOOST=1 %command%
```

# Frame rate

The steadiest play so far: set the frame rate to unlimited in the game's own video settings, and cap it with D3DMetal 4 instead, by adding one of these before `%command%` in the same launch options:

| Variable and value | What it does |
|---|---|
| `D3DM_MAX_FPS=48` | Caps the frame rate at 48. |
| `D3DM_MAX_FPS=60` | Caps the frame rate at 60. On a MacBook Pro's ProMotion display it may hold 48 all the same. |

Short stutters remain even so: with the car nearly still, about eight a minute, the longest under 0.1 s. They are not shader compilation, and their cause is still under investigation.

# Optional

Add these yourself if you want them; none is needed to play.

| Variable and value | What it does |
|---|---|
| `NOTPROTON_RAW_CONTROLLERS=0` | Keeps NotProton's usual controller handling instead of forcing direct access. Not an FPS improvement. |
| `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0` | Turns the exception counters off. They are on by default, so `=1` changes nothing. Whether turning them off helps the stutter is not measured. |
| `MTL_HUD_ENABLED=1` | Shows the Metal HUD. |
| `MTL_HUD_LOG_ENABLED=1` | Asks for the HUD's text log. That log can be missing; `metalperftrace` is used beside it for now. |

# After an update

If a CrossOver, NotProton or prefix update leaves the improvement partial, FH6 still starts but asks for Xbox sign-in again. Install the improvement again to put the fix back.
