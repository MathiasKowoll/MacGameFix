# Launch options

The line to play with, in the game's launch options in Steam:

```
MGF_FANS=max NOTPROTON_ENV_WINENCPU=8 D3DM_MAX_FPS=60 MGF_FH6_ROSETTA_PACER=60 NOTPROTON_ROSETTA_TRAP_BOOST=1 %command%
```

| Variable and value | What it does |
|---|---|
| `NOTPROTON_ROSETTA_TRAP_BOOST=1` | Needed. Turns on the priority plugin, which cuts scheduling waits while exceptions are handled under Rosetta. MacGameFix writes it itself when you install the improvement, and keeps the options you already had. Quit Steam first, or it cannot save them, and do not remove it afterwards. |
| `MGF_FANS=max` | Runs both fans at full speed while the game runs, so macOS does not cut the processor's speed (see Heat). Turn **Improvements › Fans** on in MacGameFix first: it installs the helper that does it. |
| `NOTPROTON_ENV_WINENCPU=8` | Shows the game 8 processors, so its engine starts fewer worker threads and the Mac runs cooler. |
| `D3DM_MAX_FPS=60` | Caps the frame rate (see Frame rate). |
| `MGF_FH6_ROSETTA_PACER=60` | Shortens the stop of 0.1 to 0.17 s the game makes every ten seconds or so (see Stutter). The number is not a setting to copy: it has to be tried on each Mac. `40` to `60` is the range that was played on this one. |

The first is needed and MacGameFix writes it. The other four are recommended: write them yourself, before `%command%`.

With that line, DLSS in a performance mode and the game's own frame rate setting on unlimited, it was played on a MacBook Pro M4 Max: on 2026-11-16 with `40`, in the open world and in races, and the player saw a steady 60 frames a second; on 2026-11-17 with `60`, 43 minutes in the open world and in races, and the player noticed no stop.

On NotProton's runner for CrossOver Preview 41303, FH6's exception handling is now built into the improvement's `ntdll`, so it needs no variables of its own. Installing the improvement again takes out what earlier versions wrote for it (`NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1`, `NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1`, `NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0` and `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0`), each only while it still has the value MacGameFix gave it. On the 41073 runner the first three are still needed, and MacGameFix keeps writing them there.

On that runner, on Rosetta, the improvement also adds FH6 to MacGameFix's shared row **Engine fixes (MacGameFix)**, on the game's Compatibility page in NotProton, and switches it on the first time: `NOTPROTON_MGF_ENGINE=1` goes in front of the launch options, so quit Steam before installing. The row's library arms three Wine fixes in FH6 alone, from outside `ntdll`: the threadpool's timer thread kept from spinning (without it, about 88,000 timer requests a second); the IPv4 options of the online sessions' socket, without which no session is joined; and the system calls and exceptions of the game's protection that Rosetta delivers on top of a thread being suspended, which otherwise hang or end that thread. The improvement's `ntdll` still carries all three, so for now the row changes nothing in the game; it is what lets that `ntdll`, and NotProton's own, go without them later. They were checked with test programs on a runner without them; FH6 has not been played with the row yet. Leave it on.

The exception handling built into the improvement's `ntdll` (the chain that hands the game's protection its next deliberate invalid instruction without a trip through macOS) is now also in the game's D3D12 proxy, which can hook it into the `ntdll.dll` CrossOver Preview 41303 and NotProton ship. Played A/B on 2026-11-25 on the same route, it is what makes the game playable: with it 58 frames a second and 2.4% of seconds holding a frame over 100 ms; without it (`NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=0`) 48 and 69%. While the improvement's own `ntdll.dll` is in place the proxy leaves it to that file and changes nothing; it is the step that lets FH6 stop replacing `ntdll.dll`.

# Frame rate

The steadiest play so far: set the frame rate to unlimited in the game's own video settings, and cap it with D3DMetal 4 instead, with one of these before `%command%` in the same launch options:

| Variable and value | What it does |
|---|---|
| `D3DM_MAX_FPS=48` | Caps the frame rate at 48. |
| `D3DM_MAX_FPS=60` | Caps the frame rate at 60. On a MacBook Pro's ProMotion display it may hold 48 all the same. |

Short stutters remain even so: with the car nearly still, a stop of 0.1 to 0.17 s every ten seconds or so. They are not shader compilation, the graphics settings or the online session. See Stutter.

# Stutter

The game's protection rewrites its own code all the time. Rosetta translates each rewritten piece again and keeps the translations in a store; when the store fills, Rosetta empties it in one go, and every thread that needs a translation waits meanwhile. That is the stop. Rosetta does the same with no game and no Wine: `tools/rosetta-store-stop/trapfreeze.c` in MacGameFix's source shows it. It is reported to Apple as FB25605182. Only a change in Rosetta takes the stop away; what follows makes it shorter. If you see the stop as well, a report of your own to Apple that names that number adds weight to it.

The FH6 `d3d12.dll` can make Rosetta empty the store more often, while it holds less, so each stop is shorter. It is off unless you ask for it, before `%command%`:

| Variable and value | What it does |
|---|---|
| `MGF_FH6_ROSETTA_PACER=60` | Runs a thread that keeps Rosetta's store small. The number is how much of the time it works, from 1 to 100. |
| `MGF_FH6_ROSETTA_PACER=60,4096` | The same, with the size in bytes of the code it runs each time (2048 to 65536; 4096 if left out). |

There is no value that is right everywhere. It depends on the processor and has to be tried case by case: start in the range of `40` to `60`, play, and move it if the stops stay (try higher) or a fine, constant stutter appears (try lower). The measurements below are one MacBook Pro M4 Max.

Played on a MacBook Pro M4 Max on 2026-11-16, standing in the world, 75 to 90 seconds a value, the frame rate the same in all of them:

| Value | Stops of 0.1 s or more | Longest |
|---|---|---|
| off | 2 to 4 | 0.13 to 0.17 s |
| `15` | 12 | 0.13 s |
| `25` | 1 | 0.10 s |
| `40` | 1 | 0.10 s |
| `50` | 0 | 0.09 s |
| `65` | 0 | 0.08 s |
| `100` | 1 | 0.11 s, with a pause of 0.09 s every second |

More is not better. The thread takes the translator from the game's own threads, and from about `65` up the game's usual short pause, about 0.055 s every second or so, grows instead: at `100` it is worse than off. `40` to `50` is where the long stops go and the short pause barely changes (0.06 s). Another processor may want another value, a faster one most likely a lower one.

`60` was then played for a whole session on 2026-11-17, 43 minutes in the world and in races. The thread's own log met no stop of 0.05 s in it (the longest 0.047 s), three minutes sampled from outside showed no stop, and the player noticed none. The gaps between frames were not measured in that session, so how `60` compares with `40` on the short pause is not known.

To try values without starting the game again: with the variable set, write a file `pacer.txt` in the `mgf` folder of the game's prefix (`drive_c/mgf`), holding just the number, or the number and the size. The game reads it twice a second and uses it in place of the variable while the file is there. `fh6-pacer-<number>.log` in the same folder gets a line every ten seconds whose last figure is the longest stop the thread itself met, in millionths of a second.

A later session at `40` had races in it. Which stretches were races was not noted: two three-minute stretches in a row had no gap of 0.1 s or more, and others had gaps of 0.3 to 2.7 s, which a loading screen gives as well.

Only on Rosetta, only one run a value so far, and only one Mac.

# Heat

Entering the world heats the Mac faster than macOS raises its fans. Near 75 °C macOS cuts the processor to less than half its speed for minutes, and the game stutters. `MGF_FANS=max`, `NOTPROTON_ENV_WINENCPU=8` and the frame-rate cap, all in the line above, keep FH6 under that.

In the game's video settings, turn the upscaler (DLSS) on in a performance mode as well. It takes load off the graphics, and under macOS's limit that goes to the processor.

Measured on a MacBook Pro M4 Max, one run each, standing still: with all of it the performance cores stayed at 4.5 GHz instead of 1.8-2.3, and a frame took over 60 ms in 0-1 seconds of a minute instead of 27-59.

# Online

On the 41303 runner the improvement's `ntdll` keeps the game's network socket open. Before, macOS refused two options the game sets on it, the game closed it, and no online session was ever joined. It comes with the Wine modules of 2026-11-15: once MacGameFix has taken them, install the improvement again.

If the open world still shows no other players, turn cross-play on in the game's settings. Played on 2026-11-15, Steam edition: with cross-play off the game held its session with Forza's server and showed nobody; with it on, it connected.

# Optional

Add these yourself if you want them; none is needed to play.

| Variable and value | What it does |
|---|---|
| `NOTPROTON_RAW_CONTROLLERS=0` | Keeps NotProton's usual controller handling instead of forcing direct access. Not an FPS improvement. |
| `NOTPROTON_GAME_MODE=0` | Starts the game without NotProton's Game Mode. Every measurement on this page was played with it; whether it changes anything here is not measured. |
| `NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0` | Turns the exception counters off. They are on by default, so `=1` changes nothing. Whether turning them off helps the stutter is not measured. |
| `NOTPROTON_ENV_WINE_DUALSTACK_IPV4_OPTIONS=0` | Turns the improvement's `ntdll` socket handling for Online off. With the Engine fixes row on, the row's own copy of it still applies, so this is how to play Online on the row alone; with the row off as well, Online is as it was before. Only to compare, or if the game does worse with it. |
| `NOTPROTON_ENV_WINE_DIRECT_SYSCALL_DEFERRAL=0` | Turns the improvement's `ntdll` handling of system calls and exceptions that come during a suspend off. With the Engine fixes row on, the row's own copy still applies, so this is how to play on the row alone. Only to compare. |
| `MTL_HUD_ENABLED=1` | Shows the Metal HUD. |
| `MTL_HUD_LOG_ENABLED=1` | Asks for the HUD's text log. That log can be missing; `metalperftrace` is used beside it for now. |

# After an update

If a CrossOver, NotProton or prefix update leaves the improvement partial, FH6 still starts but asks for Xbox sign-in again. Install the improvement again to put the fix back.
