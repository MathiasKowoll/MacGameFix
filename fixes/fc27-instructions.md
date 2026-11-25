# WARNING: AT YOUR OWN RISK

**MacGameFix takes no responsibility for failures in the game.**

This starts EA SPORTS FC 27 without EA AntiCheat, with FC 27 Live Editor inside it: a third-party mod tool that you download and provide, that changes the game while it runs. MacGameFix did not make Live Editor or its stand-in for EA AntiCheat's launcher, does not include or download them, and does not maintain them. If the game stops starting, crashes, behaves wrongly, or a save or a career is lost or damaged, or something happens to your EA account, that is not something MacGameFix can answer for or promises to fix. What EA's and Steam's terms say about running the game this way is yours to read.

**Offline only.** Do not use it in any online mode.

It is a fix being tested, played on one Mac. If that is not acceptable to you, do not install it. Removing it gives Steam's Play back as it was.

# Before you install

- Start EA SPORTS FC 27 once from Steam, so NotProton makes the game's prefix and the EA app installs in it. No game starts yet; stop it from Steam and go on.
- The game must be on NotProton's runner for CrossOver Preview 41303, on Rosetta. NotProton must be up to date: the fix loads its libraries through NotProton's plugin host.
- Download **FC 27 Live Editor** from its author (xAranaktu), the version made for your version of the game, and unpack it. MacGameFix does not download it or look for it: the install **asks you for that folder**, the one that holds `Launcher.exe` and `FCLiveEditor.DLL`, and copies it.
- Quit Steam before you install: it writes the launch options when it quits.

# The first start

Press Play in Steam. The first time, a console window says that Live Editor's launcher opens for a moment and closes again: it has to write its settings once. When the window says so, press a key and **press Play again**.

A version of Live Editor that is out for its patrons first asks you to **sign in to Patreon** once: at the first Play with it, your browser opens for the sign-in and that start ends without the game. Finish signing in; the console window waits for it and then says so. Press Play again. Live Editor keeps the sign-in in the game's prefix, and a version that is public does not ask.

From then on Play does all of it: Live Editor's launcher opens, the EA app checks your licence, the game starts and the launcher closes itself. In the game, **F9** (fn + F9 on a Mac keyboard) shows and hides Live Editor's window.

Do not close Live Editor's launcher window yourself while the game is starting, and do not switch to another app until the game is at its "press any key" screen.

# What you get, and what you do not

The game runs offline and without EA AntiCheat: no Ultimate Team, no online seasons, nothing that needs EA's servers to trust the game. A message about online services is expected.

The game does not start here without Live Editor: EA AntiCheat's own launcher starts nothing on a Mac. With the row **Start with Live Editor** off, Play starts nothing.

While a session starts, Live Editor's launcher replaces one file in the game folder (`EAAntiCheat.GameServiceLauncher.exe`, keeping the game's own as `.backup`) and gives it back when it closes. If Steam ever says the game's files need repair after a session that was cut short, let it verify them, or remove the fix: Remove puts the file back.

# The rows in NotProton

The fix adds two rows to the game's Compatibility page in NotProton, for this game only, in a group of their own, **MacGameFix · FC 27**, and switches on **Engine fixes**, in the group **MacGameFix**, for this game:

| Row | What it does |
|---|---|
| **Start with Live Editor** | On: Play starts the game with Live Editor, and NotProton loads the library that lets its window work on a Mac. Off: Play starts the game's own launcher, which starts nothing. The first install switches it on. |
| **Play opens** | **The game**; **The game, with exception notes for a report**, for one start when you report a game that closes; or **Live Editor's launcher window** alone. |
| **Engine fixes** | Shared by every game whose MacGameFix fix needs a Wine fix: it loads one library that, for FC 27, gives the game the Windows function its activation asks for. Off, the game says "There is a problem with your game's setup". The install switches it on; leave it on. |

Choose **Live Editor's launcher window** to look at the launcher's settings before a session. Its own "Run Game" button starts nothing here; close the window, set the row back to **The game** and press Play.

# A new version of Live Editor

Updating it is by hand, as installing it was. When the game updates, Live Editor needs its matching version:

1. Download the new version from its author and unpack it.
2. Quit the game and Steam, and install this fix again from MacGameFix. It asks for the folder again: choose the new one. Cancel keeps the Live Editor in use.

The copy that was in use is kept once, as `LiveEditor.previous` beside the new one, in `~/Library/Application Support/MacGameFix/fc27-live-editor`: Lua scripts or anything else you kept inside the old folder are there.

Because it asks you for a folder, MacGameFix never installs this fix again by itself after a game update, as it does with other fixes: it is yours to do.

Until Live Editor has a version for a new game update, the game does not start with it. Steam's game properties let you choose when the game updates.

# If something goes wrong

The play script's notes for the last start are in `~/Library/Application Support/MacGameFix/fc27-live-editor/fc27-le-run.log`, the library's in `fc27-le-hooks.log` beside it, and Live Editor's own in `LiveEditor/Logs`.

| What you see | What to do |
|---|---|
| "There is a problem with your game's setup. Please reinstall your game." | The row **Engine fixes** is off: switch it on. If it is on, update NotProton (the row needs its plugin host) and install the fix again. |
| The launcher stays at "Injecting" with "Starting EA Javelin Anticheat…" for more than half a minute | Stop the game from Steam and press Play again. |
| The browser opens for a Patreon sign-in and no game starts | Expected at the first Play with a Live Editor version that is out for its patrons first. Sign in, wait for the console window to say it was saved, and press Play again. |
| The game closes right after the EA SPORTS logo | The row **Start with Live Editor** lost its library, or Live Editor is not the version for this game. Install the fix again; check Live Editor's version. |
| Play starts nothing | The row **Start with Live Editor** is off. Switch it on in the game's Compatibility page. |
| The fix reads partial after a NotProton or prefix update | Install it again, with Steam closed. |

For a report of a game that closes, set the row **Play opens** to **The game, with exception notes for a report** for one start, and send NotProton's Wine log for the game with the three logs above. Set it back to **The game** afterwards: the log grows fast.

# Removing it

Remove gives the launch options back as they were and takes the two rows and the library out of NotProton, and the game out of **Engine fixes**. Your Live Editor folder stays in `~/Library/Application Support/MacGameFix/fc27-live-editor`, and its settings in the prefix (`C:\FC 27 Live Editor`).
