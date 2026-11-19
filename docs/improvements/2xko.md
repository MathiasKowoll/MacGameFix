# 2XKO on a Mac

2XKO is Riot's free fighting game. It has run without Vanguard, Riot's kernel anti-cheat,
since patch 1.3.3b (2026-11-12). What is left is a copy protection in user space, which Wine
could not get past. With MacGameFix's **Copy protection under Rosetta** improvement on
CrossOver Preview 27.0.0.41303 it starts, signs in through the Riot Client and plays.

The patches that make it run are the work of NotProton's creator
(https://github.com/NotProtonNot/NotProton), who handed them to us. Thank you.

What was played (2026-11-19, M4 Max, macOS 27.2.1): sign-in with Apple, the title screen,
the menus and training mode, in a CrossOver bottle and as a non-Steam game in NotProton.
Online matches have not been tried yet.

## What you need

- A Mac with Apple silicon.
- **CrossOver Preview 27.0.0.41303** (CrossOver → About CrossOver). The modules are built
  for that build only; on another one MacGameFix does not install them.
- **MacGameFix** with the modules of that build (the release that carries PR #117).
- For the second way below, **NotProton** with its 41303 runner.

The game can stay on an external disk: nothing here moves it.

## 1. The improvement

1. Quit CrossOver and every game. MacGameFix changes nothing while a Wine of that
   CrossOver runs.
2. Open MacGameFix, tab **Improvements**, and turn on **Copy protection under Rosetta** for
   CrossOver Preview, and for NotProton's 41303 runner if you play there. If it is on
   already, it shows an update: apply it.

MacGameFix also tells Wine to refresh the copies of its modules that every bottle and
prefix keeps in `C:\windows\system32`. The game's protection reads `ntdll.dll` from there,
so the next start of each bottle takes a few seconds more, once.

## 2. Install the Riot Client and 2XKO (in CrossOver)

1. In CrossOver Preview, use a 64-bit bottle (Windows 10); any
   name works.
2. Download **Install 2XKO.exe** from Riot's site and run it in that bottle
   (**Run Command**, or drag it onto the bottle).
3. Choose where to install: the default `C:\Riot Games` or another drive, such as an
   external disk (it appears as `Z:\Volumes\<disk>\...`).
4. Let the Riot Client download 2XKO.

## 3. Play in CrossOver

1. Start **2XKO** from the bottle (the shortcut Riot creates runs
   `RiotClientServices.exe --launch-product=lion --launch-patchline=live`).
2. Sign in. With Apple, Google, Xbox or PlayStation, the sign-in finishes in the browser and
   comes back to the client.
3. Tick **Stay signed in**: the next start does not ask again.
4. Press **Play**.

## 4. Or play through NotProton (Steam)

1. In Steam: **Games → Add a Non-Steam Game to My Library → Browse**, and pick
   `RiotClientServices.exe` in the Riot Client's folder.
2. In the new shortcut's **Properties**:
   - **Start In**: the Riot Client's folder.
   - **Compatibility**: force **CrossOver 2026 11 11-ARM64 - Rosetta**. The **FEX** one
     does not run 2XKO: the Riot Client's window never draws there.
   - **Launch Options**: NotProton fills them in when the shortcut is added. Keep what it
     wrote and add at the end, after `%command%`:
     `--launch-product=lion --launch-patchline=live`
3. Start it once and quit. That makes its prefix:
   `~/Library/Application Support/Steam/steamapps/compatdata/<shortcut id>/pfx`.
4. Copy two folders from the CrossOver bottle into that prefix, with the Riot Client closed
   on both sides:
   - `drive_c/ProgramData/Riot Games`: where the client and the game are installed.
   - `drive_c/users/crossover/AppData/Local/Riot Games` and, in `AppData/Roaming`,
     `Riot Client` and `riot-client-ux` (into `drive_c/users/steamuser/...`): the client's
     settings and the session, so you need not sign in again.
5. Start it from Steam.

**Do not switch the shortcut's compatibility tool** afterwards. NotProton converts the
prefix at the next start, and that conversion deletes `drive_c/ProgramData/Riot Games`;
the client then no longer knows 2XKO is installed. If it happens, copy that folder in again.

## What to expect

- About 50-55 fps in training mode at 60 fps capped, with the graphics card far from busy.
- **It stutters**: pauses of 100-300 ms, in runs of a few seconds. The cause is measured
  and it is not something to set: the protection keeps the game's code encrypted, opens each
  page when the game first runs it and locks it again later. Under Rosetta every opening
  costs an exception and a new translation, 500-1000 times a second at times. Raising
  priorities does not help, and nothing here touches the protection. Details in
  [`../../engine/README.md`](../../engine/README.md#2xkos-copy-protection-and-an-ntdlldll-shaped-like-windows).
- Riot recommends fullscreen for performance (Settings → Video).

## If it does not start

- **The game closes a second after Play** (or nothing happens): the improvement is off or
  not updated, or the bottle has not refreshed `system32` yet. Check the improvement in
  MacGameFix, start the bottle once more and try again.
- **The Riot Client's window is blank or crashes**: the improvement is missing (it carries
  the fix for that window, `win32u.so`).
- **The client says 2XKO is not installed** (NotProton): see step 4.4.

League of Legends is not a candidate: on Windows it needs Vanguard. It has a version for
the Mac of its own. Valorant needs Vanguard and has none.
