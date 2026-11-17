# A game that runs slowly: record it

A report of a game that runs slowly says little without numbers. This records two minutes of the game
while you play, from outside it, and leaves one zip to attach to your issue.

## What to do

1. Start the game and play to the part that runs slowly.
2. Open Terminal and paste these two lines, one after the other:

   ```bash
   curl -fsSL -o ~/capture-performance.sh https://raw.githubusercontent.com/MathiasKowoll/MacGameFix/main/tools/capture-performance.sh
   ```

   ```bash
   bash ~/capture-performance.sh
   ```

3. It names the game it found and counts down from 20. Go back to the game in that time and keep playing
   the slow part. A sound says the recording has started, and another, two minutes later, that it has ended.
4. A zip named `MacGameFix-performance-<game>-<date>.zip` is in your home folder, shown in the Finder. Drag
   it into your issue, with the report the app's **Report** tab saves.

If it names the wrong program, press Control-C and give part of the game's name. That is also how a game
made for macOS, which has no `.exe`, is recorded:

```bash
bash ~/capture-performance.sh 120 forza
```

The first number is the seconds to record. `DELAY=40 bash ~/capture-performance.sh` gives 40 seconds to get
back to the game instead of 20.

A second capture after you change one thing (a graphics setting, the upscaler, a launch option) is worth
more than a long one: the two are read side by side.

## What it records

Everything is read from outside the game. Nothing is attached to it, nothing is installed or changed, no
password is asked, and nothing is sent anywhere: the zip stays on your Mac until you attach it.

| File | What is in it |
|---|---|
| `capture.txt` | The Mac's model, chip, cores, memory, displays and power mode; the game's process; the launch options NotProton handed it; the Wine loader and the graphics, upscaler and controller modules the game has open, with their folders. |
| `metal-1.json` | macOS's own record of the frames the game presented, a line a second: frames, the longest gap between two frames, time on the processor and on the graphics, shaders compiled, the game's memory. |
| `threads.txt` | The processor time of each thread of the game, every second. |
| `system.txt`, `top.txt` | The whole Mac's processor and disks every second; the game's processor cycles every five. |
| `memory.txt` | Memory pressure, swap and compression every five seconds. |
| `busiest.txt`, `front.txt` | The names of the ten busiest programs and of the program in front, every five seconds. |
| `system-log.txt`, `thermal.txt` | macOS's thermal level and Game Mode lines for those minutes. |
| `mgf/` | What MacGameFix's own fixes logged for the game, if they log. |

Your home folder is written as `~` and your Mac's name is left out. The names of the other busy programs
are kept because one of them is often the reason a game slows down: a download, an index, a browser. Open
the zip before you attach it if you want to see them.

## Reading one

```bash
python3 -I tools/read-performance.py ~/MacGameFix-performance-<game>-<date>.zip
```

It prints the frames whole and in rows of ten seconds, the game's busiest threads, the speed the processor
ran at, memory, the other programs and macOS's log lines. It prints numbers; it does not say why.
