# Launch options

FH6's improvement needs one variable in the game's Steam launch options, `NOTPROTON_ROSETTA_TRAP_BOOST=1`. It turns on the priority plugin, which cuts scheduling waits while exceptions are handled under Rosetta. MacGameFix writes it itself when you install the improvement, and keeps the options you already had. Quit Steam first, or it cannot save them, and do not remove it afterwards.

```
NOTPROTON_ROSETTA_TRAP_BOOST=1 %command%
```

On NotProton's runner for CrossOver Preview 41303, FH6's exception handling is now built into the improvement's `ntdll`, so it needs no variables of its own. Installing the improvement again takes out what earlier versions wrote for it (`NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1`, `NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1`, `NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0` and `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0`), each only while it still has the value MacGameFix gave it. On the 41073 runner the first three are still needed, and MacGameFix keeps writing them there.

# CrossOver Preview 41303

In a bottle of CrossOver Preview 41303 itself, the improvement installs the same D3D12 and `ntdll` parts as on NotProton. It adds the renamed D3DMetal copy (`apd12.dll` and `apd12.so`) to the app, signs the app again ad hoc the way the Wine modules do, and puts the proxy, the alias and the `d3d12` override in the bottle. Install the Wine modules for CrossOver Preview first. CrossOver cannot load NotProton's priority plugin, so it needs no launch options. Quit Steam in the bottle before installing. Not yet validated in game.

# Frame rate

The steadiest play so far: set the frame rate to unlimited in the game's own video settings, and cap it with D3DMetal 4 instead, by adding one of these before `%command%` in the same launch options, for example `D3DM_MAX_FPS=48 NOTPROTON_ROSETTA_TRAP_BOOST=1 %command%`:

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
