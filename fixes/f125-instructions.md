# Before you install

- Start F1 25 once from Steam, so NotProton makes the game's prefix. The game's own launcher does not open on a Mac; close it and go on.
- The game must be on NotProton's runner for CrossOver Preview 41303, on Rosetta, with MacGameFix's **Rosetta** improvement installed in it. Without it the game closes about half a minute after it starts.
- Quit Steam before you install: it writes the launch options when it quits.

Installing downloads Swofty Launcher, about 90 MB, from Swofty's own site. It is not part of MacGameFix.

# The first start

Press Play in Steam. The first time, a console window opens and asks three things of you, once:

1. Swofty shows its offline play terms and waits for your answer. Read them; the answer is yours to give.
2. Swofty downloads its offline play extension.
3. Swofty does its one-time setup: it records the game's original files. If you ever put mods in the game folder by hand, close the window, verify the game files in Steam and press Play again.

After that Play builds the profile and starts the game. The first build takes longer.

# What you get, and what you do not

The game runs offline and without EA AntiCheat: no multiplayer, no online services. A message about online services at the main menu is expected.

Swofty changes the game folder while the game runs and puts it back when the game exits. Quit the game from its menu and wait a moment before you start it again.

# Profiles

Play uses Swofty's active profile. Swofty has two to begin with:

| Profile | What it is |
|---|---|
| `default` | The one your addons and mods go into. |
| `vanilla` | The game with no addons and no mod loader. |

To play one start without mods, put `F1_PROFILE=vanilla` in front of the launch options, before the script MacGameFix wrote:

```
F1_PROFILE=vanilla "…/f125-swofty-play.sh" %command%
```

Take it out again to go back to the active profile. It is the quick way to tell whether a problem comes from a mod or from the game.

# Graphics

Leave ray tracing off: with it on the game closed when a session started (2026-11-23, not looked into). If the game closes right after you turn it on, set every `rt_` line to `enabled="false"` in `Documents/My Games/F1 25/hardwaresettings/hardware_settings_config.xml` in the game's prefix.

# If something goes wrong

Swofty's output for the last start is in `~/Library/Application Support/MacGameFix/swofty/f125-swofty-play.log`.

| What you see | What to do |
|---|---|
| The game closes about half a minute in, at the main menu | The runner lost the Rosetta improvement. Install it again in **Improvements**. |
| "Steam isn't running" or "not signed in" in the log | Install the fix again, with Steam closed. |
| The fix reads partial after a NotProton or prefix update | Install it again, with Steam closed. |

# Removing it

Remove gives the launch options and the prefix back as they were. Swofty Launcher stays in `~/Library/Application Support/MacGameFix/swofty`, and its data and saves stay in the prefix.
