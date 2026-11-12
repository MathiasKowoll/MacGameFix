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

# Optional

Add these yourself if you want them; none is needed to play.

| Variable and value | What it does |
|---|---|
| `NOTPROTON_RAW_CONTROLLERS=0` | Keeps NotProton's usual controller handling instead of forcing direct access. Not an FPS improvement. |
| `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=1` | Keeps diagnostic counters. Not needed for the instructions to run correctly. |
| `MTL_HUD_ENABLED=1` | Shows the Metal HUD. |
| `MTL_HUD_LOG_ENABLED=1` | Asks for the HUD's text log. That log can be missing; `metalperftrace` is used beside it for now. |
| `D3DM_MAX_FPS=48` or `60` | Asks D3DMetal for that frame cap. A frame-pacing preference, not part of the `ntdll` patch. |

# After an update

If a CrossOver, NotProton or prefix update leaves the improvement partial, FH6 still starts but asks for Xbox sign-in again. Install the improvement again to put the fix back.
