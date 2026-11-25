# WARNING: AT YOUR OWN RISK

**MacGameFix takes no responsibility for failures in the game.**

This starts F1 25 without EA AntiCheat, through Swofty Launcher, a third-party mod launcher that changes the game's files while it runs. MacGameFix did not make Swofty Launcher, its offline play or any mod, and does not maintain them. If the game stops starting, crashes, behaves wrongly, or a save or a career is lost or damaged, that is not something MacGameFix can answer for or promises to fix. What EA's and Steam's terms say about running the game this way is yours to read.

It is a fix being tested, played on one Mac. If that is not acceptable to you, do not install it. Removing it gives Steam's Play back as it was.

# Before you install

- Download Swofty Launcher yourself, from [Swofty's site](https://f1.swofty.net): its Windows release, a .zip. It is not part of MacGameFix, and MacGameFix does not download it. You can leave it as it came, or unpacked if your browser unpacked it.
- Start F1 25 once from Steam, so NotProton makes the game's prefix. The game's own launcher does not open on a Mac; close it and go on.
- The game must be on NotProton's runner for CrossOver Preview 41303, on Rosetta. NotProton must be up to date: the fix loads a library through NotProton's plugin host.
- Quit Steam before you install: it writes the launch options when it quits.

The first install asks where your Swofty download is: choose the .zip, or, if your browser unpacked it, `swofty.exe` in its `bin` folder. MacGameFix copies it and keeps it; Swofty updates itself from then on, so installing again later asks nothing.

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

The fix adds no row of its own. It uses three of MacGameFix's rows, in the group **MacGameFix** on the game's Compatibility page in NotProton, which every game with a MacGameFix fix shares, each with its own settings:

| Row | What it does |
|---|---|
| **Engine fixes** | Loads one MacGameFix library that, for F1 25, keeps the game's memory where Windows would put it. Off, the game closes about half a minute after it starts. The install switches it on; leave it on. |
| **Start through the mod tool** | On: Play starts the game through Swofty Launcher. Off: Play starts the game's own launcher, which does not open on a Mac. The first install switches it on. |
| **Play opens** | **The game**, with Swofty's active profile; **The game without mods**, Swofty's vanilla profile; **The game, with exception notes for a report**; or **The mod tool's window**, Swofty Launcher's. |

Choose **The mod tool's window** to turn addons on or off, install mods, edit the game database or change the profile. Its own Play starts the game from there. Set the row back to **The game** to go straight into the game again.

The window needs the Wine modules with the fonts and window fixes for CrossOver Preview 41303 (engine patches 0039 and 0040). Without them it closes as it opens, and `f125-swofty-window.log` beside the play script says "failed to resolve font" or "initializing Direct Manipulation". Touchpad pinch and inertia do not work in it; the wheel and two-finger scrolling do.

# Profiles

Play uses Swofty's active profile. Swofty has two to begin with:

| Profile | What it is |
|---|---|
| `default` | The one your addons and mods go into. |
| `vanilla` | The game with no addons and no mod loader. |

To play without mods, set the row **Play opens** to **The game without mods** on the game's Compatibility page in NotProton, and back to **The game** afterwards. It is the quick way to tell whether a problem comes from a mod or from the game. Which profile is the active one is chosen in Swofty Launcher's window.

# Graphics

Leave ray tracing off: with it on the game closed when a session started (2026-11-23, not looked into). If the game closes right after you turn it on, set every `rt_` line to `enabled="false"` in `Documents/My Games/F1 25/hardwaresettings/hardware_settings_config.xml` in the game's prefix.

# If something goes wrong

Swofty's output for the last start is in `~/Library/Application Support/MacGameFix/swofty/f125-swofty-play.log`, and the window's in `f125-swofty-window.log` beside it.

| What you see | What to do |
|---|---|
| The game closes about half a minute in, at the main menu | The row **Engine fixes** is off: switch it on. If it is on, update NotProton (the row needs its plugin host) and install the fix again. |
| "Steam isn't running" or "not signed in" in the log | Install the fix again, with Steam closed. |
| Play opens the game's own launcher, which closes | The row **Start through the mod tool** is off. Switch it on in the game's Compatibility page. |
| The fix reads partial after a NotProton or prefix update | Install it again, with Steam closed. |

# Removing it

Remove gives the launch options and the prefix back as they were and takes the game out of MacGameFix's rows in NotProton. Swofty Launcher stays in `~/Library/Application Support/MacGameFix/swofty`, and its data and saves stay in the prefix.
