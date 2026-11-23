# WARNING: AT YOUR OWN RISK

**MacGameFix takes no responsibility for failures in the game.**

This starts F1 25 without EA AntiCheat, through Swofty Launcher, a third-party mod launcher that changes the game's files while it runs. MacGameFix did not make Swofty Launcher, its offline play or any mod, and does not maintain them. If the game stops starting, crashes, behaves wrongly, or a save or a career is lost or damaged, that is not something MacGameFix can answer for or promises to fix. What EA's and Steam's terms say about running the game this way is yours to read.

It is a fix being tested, played on one Mac. If that is not acceptable to you, do not install it. Removing it gives Steam's Play back as it was.

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

# The rows in NotProton

The fix adds two rows to the game's Compatibility page in NotProton, for this game only, in a group of their own, **MacGameFix · F1 25**:

| Row | What it does |
|---|---|
| **Start through Swofty Launcher** | On: Play starts the game through Swofty. Off: Play starts the game's own launcher, which does not open on a Mac. The first install switches it on. |
| **Play opens** | **The game**, with Swofty's active profile, or **Swofty Launcher's window**. |

Choose **Swofty Launcher's window** to turn addons on or off, install mods, edit the game database or change the profile. Its own Play starts the game from there. Set the row back to **The game** to go straight into the game again.

The window needs the Wine modules with the fonts and window fixes for CrossOver Preview 41303 (engine patches 0039 and 0040). Without them it closes as it opens, and `f125-swofty-window.log` beside the play script says "failed to resolve font" or "initializing Direct Manipulation". Touchpad pinch and inertia do not work in it; the wheel and two-finger scrolling do.

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

Swofty's output for the last start is in `~/Library/Application Support/MacGameFix/swofty/f125-swofty-play.log`, and the window's in `f125-swofty-window.log` beside it.

| What you see | What to do |
|---|---|
| The game closes about half a minute in, at the main menu | The runner lost the Rosetta improvement. Install it again in **Improvements**. |
| "Steam isn't running" or "not signed in" in the log | Install the fix again, with Steam closed. |
| Play opens the game's own launcher, which closes | The row **Start through Swofty Launcher** is off. Switch it on in the game's Compatibility page. |
| The fix reads partial after a NotProton or prefix update | Install it again, with Steam closed. |

# Removing it

Remove gives the launch options and the prefix back as they were and takes the two rows out of NotProton. Swofty Launcher stays in `~/Library/Application Support/MacGameFix/swofty`, and its data and saves stay in the prefix.
