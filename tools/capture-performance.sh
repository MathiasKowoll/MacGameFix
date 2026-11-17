#!/bin/bash
#
# Record how a game runs for two minutes, to send with a report of a game that runs slowly.
#
#     bash capture-performance.sh [seconds [part of the game's exe name]]
#
# For a Windows game run through Wine: a NotProton runner, CrossOver, or anything else whose game is a
# process with an .exe in its name. With part of a name given and no .exe by it, any program by that name
# is taken, which is how a game made for macOS is recorded.
#
# Start the game, play to the part that runs slowly, then run the line above in Terminal and go back to the
# game: there are 20 seconds before the recording starts (DELAY=<s> before "bash" changes that), a sound
# when it starts and another when it ends. Keep playing in between. The zip it leaves in the home folder is
# what to drag into the issue (OUT=<folder> puts it elsewhere, does not show it in the Finder and makes no
# sound).
#
# WHAT IT READS, and it reads everything from outside: nothing is attached to the game, no thread of it is
# stopped, nothing is written into its folder or its prefix, and nothing needs a password.
#   - Metal's own record of the frames the game presented, a line a second: frames, the longest gap between
#     two frames on screen, the time a frame spent on the processor and on the graphics, shaders compiled,
#     the game's memory. macOS keeps that record always; metalperftrace, which macOS carries, reads it.
#   - The processor time of each thread of the game, a line a second (ps -M). It says whether one thread is
#     the limit or many are busy.
#   - Every five seconds: memory pressure and swap, the ten busiest programs by name, the program in front,
#     the game's own processor cycles (top), which give the speed the processor ran at.
#   - The Mac: model, chip, cores, memory, displays, power mode; the launch options NotProton handed the
#     game; the loader and the graphics modules the game has open (lsof); macOS's thermal level and Game Mode
#     lines for those minutes; and what MacGameFix's own fixes logged in C:\mgf since the game started.
# The home folder is written as ~ and the Mac's name is left out. The other programs are named because one
# of them is often the reason: a download, an index, a browser.
#
# WHY THE COUNTDOWN. A game that is not in front is not the game that runs slowly: macOS takes Game Mode
# away from it and many games pause. So the recording waits for the player to be back in the game, and says
# in front.txt which program was in front, for whoever reads it to see that it was.
#
# WHY NOT sample, spindump OR Instruments. They stop the game's threads to look at them. A game with copy
# protection that makes its own system calls can hang or close when that happens, and a stopped thread is a
# pause the capture would then be measuring.
#
# Read what comes out with tools/read-performance.py.
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later

set -u
export LC_ALL=C

SECS="${1:-120}"
WANT="${2:-}"
DELAY="${DELAY:-20}"
case "$SECS$DELAY" in *[!0-9]*|'') echo "usage: bash capture-performance.sh [seconds [part of the game's exe name]]" >&2; exit 2 ;; esac
[ "$SECS" -ge 10 ] || { echo "at least 10 seconds" >&2; exit 2; }

# Wine's own programs and the stores' launchers: never the game.
HELPERS='steam.exe steamwebhelper.exe steamservice.exe steamerrorreporter.exe steamerrorreporter64.exe
gameoverlayui.exe gameoverlayui64.exe services.exe winedevice.exe plugplay.exe svchost.exe explorer.exe
rpcss.exe conhost.exe wineboot.exe start.exe winemenubuilder.exe tabtip.exe cmd.exe winedbg.exe
epicgameslauncher.exe epicwebhelper.exe eosoverlayrenderer-win64-shipping.exe crashreportclient.exe
crashpad_handler.exe unitycrashhandler64.exe galaxyclient.exe eadesktop.exe
eabackgroundservice.exe ealauncher.exe upc.exe ubisoftconnect.exe battle.net.exe socialclubhelper.exe
cefsharp.browsersubprocess.exe msedgewebview2.exe'

# Every process Wine named after an .exe, the largest in memory first: "pid megabytes exe". Wine gives a
# process the Windows program's path as its name; a shell or a script that only mentions an .exe keeps its own.
candidates() {
    ps -axo pid=,rss=,comm= | awk -v helpers="$(printf '%s' "$HELPERS" | tr '\n' ' ')" -v want="$WANT" -v native="${1:-0}" '
        BEGIN { n = split(tolower(helpers), h, / +/); for (i = 1; i <= n; i++) skip[h[i]] = 1; want = tolower(want) }
        {
            pid = $1; rss = $2; $1 = $2 = ""; sub(/^ +/, ""); name = tolower($0)
            if (!native && name !~ /\.exe$/) next
            n = split(name, part, /[\\\/]/); exe = part[n]
            if (exe in skip) next
            if (want != "" && index(native ? exe : name, want) == 0) next
            printf "%d %d %s\n", pid, rss / 1024, exe
        }' | sort -k2,2 -n -r
}

FOUND="$(candidates)"
# A game made for macOS has no .exe: with a name given and no Wine program by it, any program by that name.
[ -z "$FOUND" ] && [ -n "$WANT" ] && FOUND="$(candidates 1)"
if [ -z "$FOUND" ]; then
    if [ -n "$WANT" ]; then echo "No game found: no running program has \"$WANT\" in its name." >&2
    else
        echo "No game found: no running program is a Windows .exe." >&2
        echo "For a game made for macOS, give part of its name: bash capture-performance.sh $SECS <name>" >&2
    fi
    echo "Start the game first, then run this again." >&2
    exit 1
fi
PID="$(printf '%s\n' "$FOUND" | head -1 | awk '{print $1}')"
MB="$(printf '%s\n' "$FOUND" | head -1 | awk '{print $2}')"
EXE="$(printf '%s\n' "$FOUND" | head -1 | cut -d' ' -f3-)"

NAME="$(printf '%s' "${EXE%.exe}" | tr -c 'a-z0-9._-' '-' | cut -c1-40)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mgf-performance.XXXXXX")" || exit 1
DIR="$WORK/performance-$NAME-$STAMP"
ZIP="${OUT:-$HOME}/MacGameFix-performance-$NAME-$STAMP.zip"
mkdir -p "$DIR" || exit 1
TOP_PID=""; IO_PID=""
cleanup() {
    [ -n "$TOP_PID" ] && kill "$TOP_PID" 2>/dev/null
    [ -n "$IO_PID" ] && kill "$IO_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
trap 'echo; echo "Stopped: nothing was saved."; exit 130' INT TERM

echo "MacGameFix performance capture"
echo
echo "  The game:   $EXE ($MB MB in memory)"
if [ "$(printf '%s\n' "$FOUND" | wc -l)" -gt 1 ]; then
    echo "  Not taken:  $(printf '%s\n' "$FOUND" | tail -n +2 | cut -d' ' -f3- | sort -u | head -6 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    echo "              If one of those is the game, press Control-C and name it:"
    echo "              bash capture-performance.sh $SECS <part of its name>"
fi
echo "  It records: $SECS seconds, from outside the game. Nothing is installed or changed."
echo "  It keeps:   frames and their times, the game's threads, memory, the busiest programs' names,"
echo "              this Mac's model and the game's launch options. No home folder name, no Mac name."
echo
echo "Go back to the game now and keep playing the part that runs slowly."
# With OUT set it is a test or a script that runs this: no sound.
sound() { [ -n "${OUT:-}" ] || ( afplay "/System/Library/Sounds/$1.aiff" >/dev/null 2>&1 & ); }

# ---------------------------------------------------------------- the Mac and the game, before
# Read while the player goes back to the game, so that none of it weighs on the seconds recorded.
# The files a process has open, "fd<TAB>type<TAB>path" a line. lsof asks the kernel; the process is not touched.
open_files() {
    lsof -p "$1" -F ftn 2>/dev/null | awk '
        /^f/ { fd = substr($0, 2) } /^t/ { type = substr($0, 2) } /^n/ { printf "%s\t%s\t%s\n", fd, type, substr($0, 2) }'
}
GAME_FILES="$(open_files "$PID")"
# The prefix: a Wine server keeps its prefix's folder open. With more than one server running, the one whose
# prefix the game has a file open in; a prefix that is only another game's is never written down.
# A game made for macOS has none, whatever Wine server happens to be running beside it.
SERVERS=""
case "$EXE" in *.exe) SERVERS="$(ps -axo pid=,comm= | awk '/wineserver/ { print $1 }')" ;; esac
PREFIX=""; nservers=0
for ws in $SERVERS; do
    nservers=$((nservers + 1))
    dir="$(open_files "$ws" | awk -F'\t' '$2 == "DIR" && $1 != "cwd" && $3 !~ /\/\.wine-[0-9]+\// { print $3; exit }')"
    [ -n "$dir" ] || continue
    if printf '%s\n' "$GAME_FILES" | awk -F'\t' -v d="$dir/" 'index($3, d) == 1 { found = 1 } END { exit !found }'; then PREFIX="$dir"; break; fi
    [ "$(printf '%s\n' "$SERVERS" | wc -l)" -eq 1 ] && PREFIX="$dir"
done
# How long the game has run, in seconds, from ps's [[days-]hours:]minutes:seconds.
RUNNING="$(ps -o etime= -p "$PID" | awk '{ n = split($1, t, /[-:]/); s = 0; for (i = 1; i <= n; i++) s = s * (n == 4 && i == 2 ? 24 : 60) + t[i]; print s }')"
{
    echo "MacGameFix performance capture 1"
    echo "made: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "game: $EXE"
    echo "pid: $PID"
    echo "process: $(ps -o comm= -p "$PID")"
    echo "running for seconds: $RUNNING"
    case "$EXE" in
        *.exe) echo "prefix: ${PREFIX:-not known ($nservers Wine servers running)}" ;;
        *) echo "prefix: none, not a Windows program" ;;
    esac
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "model: $(sysctl -n hw.model)"
    echo "chip: $(sysctl -n machdep.cpu.brand_string)"
    echo "performance cores: $(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)"
    echo "efficiency cores: $(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null)"
    echo "memory GB: $(( $(sysctl -n hw.memsize) / 1073741824 ))"
    echo "power: $(pmset -g 2>/dev/null | awk '/powermode|lowpowermode/ { printf "%s %s; ", $1, $2 }')$(pmset -g batt 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")"
    echo
    echo "## other programs with an .exe"
    printf '%s\n' "$FOUND" | tail -n +2 | awk '{ $1 = ""; print }' | sed 's/^ //'
    echo
    echo "## displays"
    system_profiler SPDisplaysDataType 2>/dev/null \
        | grep -E 'Chipset Model|Total Number of Cores|Display Type|Resolution|UI Looks like|Main Display|Refresh Rate|Mirror|Online' \
        | sed 's/^ *//'
    echo
    echo "## the launch NotProton made last"
    L="$HOME/Library/Application Support/notproton/notproton.log"
    if [ -r "$L" ]; then grep -a 'handed to' "$L" | tail -1 | sed "s/ sh -c '.*' sh / /"; else echo "(no NotProton log)"; fi
    echo
    # macOS does not show a Wine process's environment (Wine writes the program's name over it), so what
    # runs the game is read from the files it has mapped: the loader, and every graphics, upscaler and
    # controller module, with the folder each comes from.
    echo "## the loader and the graphics, upscaler and controller modules the game has open"
    printf '%s\n' "$GAME_FILES" | awk -F'\t' '$1 == "txt" { print $3 }' \
        | grep -iE '/(wine|wine64|wine-preloader|ntdll\.so|[^/]*(d3d|dxgi|dxmt|dxvk|vkd3d|metal|molten|nvngx|nvapi|dlss|xess|ffx|fsr|amd_|dstorage|gameinput|xinput|dinput|scepad|winemac|rosetta|fex|arm64ec)[^/]*)$' \
        | sort -u
} > "$DIR/meta.txt" 2>/dev/null

left="$DELAY"
while [ "$left" -gt 0 ]; do
    printf '\r  Recording starts in %2d seconds. ' "$left"
    sleep 1; left=$((left - 1))
done
printf '\r                                         \r'
kill -0 "$PID" 2>/dev/null || { echo "The game is no longer running. Nothing was recorded."; exit 1; }
sound Tink

# ---------------------------------------------------------------- the recording
START="$(date +%s)"
iostat -w 1 -c $((SECS + 1)) > "$DIR/system.txt" 2>/dev/null &
IO_PID=$!
top -l $((SECS / 5 + 2)) -s 5 -pid "$PID" -stats pid,cpu,threads,mem,cmprs,faults,pageins,csw,instrs,cycles > "$DIR/top.txt" 2>/dev/null &
TOP_PID=$!

ENDED=""
i=0
now="$START"
while [ $((now - START)) -lt "$SECS" ]; do
    kill -0 "$PID" 2>/dev/null || { ENDED=1; break; }
    # A thread a line: %CPU, state, priority, system time, user time.
    { echo "== $now"; ps -M -p "$PID" 2>/dev/null | awk 'NR == 2 { print $4, $5, $6, $7, $8 } NR > 2 { print $2, $3, $4, $5, $6 }'; } >> "$DIR/threads.txt"
    if [ $((i % 5)) -eq 0 ]; then
        {
            echo "== $now"
            ps -axo pcpu=,rss=,comm= | sort -n -r | head -10 \
                | awk '{ p = $1; r = $2; $1 = $2 = ""; sub(/^ +/, ""); n = split($0, a, "/"); printf "%s %d %s\n", p, r / 1024, a[n] }'
        } >> "$DIR/busiest.txt"
        {
            printf '%s level %s swap %s ' "$now" "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" \
                "$(sysctl -n vm.swapusage 2>/dev/null | sed 's/.*used = \([^ ]*\).*/\1/')"
            vm_stat | awk '/Pages free|occupied by compressor|Pageins|Pageouts|Swapins|Swapouts/ { gsub(/[".]/, ""); v = $NF; $NF = ""; gsub(/[ :]+$/, ""); gsub(/ /, "_"); printf "%s %s ", $0, v }'
            echo
        } >> "$DIR/memory.txt"
        echo "$now $(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed -e 's/"LSDisplayName"=//' | sed -n '1s/^"\([^"]*\)".*/\1/p')" >> "$DIR/front.txt"
        printf '\r  Recording: %3d of %d seconds. ' "$((now - START))" "$SECS"
    fi
    sleep 1; i=$((i + 1)); now="$(date +%s)"
done
END="$(date +%s)"
kill "$TOP_PID" "$IO_PID" 2>/dev/null; TOP_PID=""; IO_PID=""
printf '\r                                         \r'
sound Glass
{
    echo "from: $START"
    echo "to: $END"
    echo "asked seconds: $SECS"
    [ -n "$ENDED" ] && echo "ended: the game closed during the recording"
} >> "$DIR/meta.txt.times"
if [ -n "$ENDED" ]; then echo "The game closed after $((END - START)) seconds; what was recorded until then is kept."; fi
echo "Recorded. Collecting what macOS kept of those seconds..."

# ---------------------------------------------------------------- what macOS kept
METAL="none"
if command -v metalperftrace >/dev/null 2>&1; then
    # From a second before, since Metal's record is in whole seconds of its own, to now: an end that is not
    # yet past is refused, and with it the whole collection.
    metalperftrace collect --start "@$((START - 1))" --prefix capture "$WORK/metal" >/dev/null 2>&1
    n=0
    for a in "$WORK"/metal/*.atrc; do
        [ -f "$a" ] || continue
        n=$((n + 1))
        metalperftrace overview --json-include-timeline --include-state-transitions --predicate "pid == $PID" "$a" \
            > "$WORK/metal/all.json" 2>/dev/null
        # The predicate takes the other programs' frames out and leaves their names and memory in. Only the
        # game's own entry is kept: the record names every program that drew, in a game or out of one.
        k=0
        while other="$(plutil -extract "$k.PID" raw -o - "$WORK/metal/all.json" 2>/dev/null)"; do
            if [ "$other" = "$PID" ]; then
                { printf '['; plutil -extract "$k" json -o - "$WORK/metal/all.json"; printf ']\n'; } > "$DIR/metal-$n.json" 2>/dev/null
                break
            fi
            k=$((k + 1))
        done
    done
    rm -rf "$WORK/metal"
    METAL="no record for those seconds"
    [ "$n" -gt 0 ] && METAL="a record, with no frames of this game in it"
    FPS="$(plutil -extract '0.Layers.0.Total Session Stats.Presented Frame Stats.FPS' raw -o - "$DIR/metal-1.json" 2>/dev/null)"
    case "$FPS" in ''|*[!0-9.]*) ;; *) METAL="$(printf '%.1f' "$FPS") frames a second" ;; esac
else
    METAL="this macOS has no metalperftrace"
fi
echo "metal: $METAL" >> "$DIR/meta.txt.times"

W0="$(date -r $((START - 60)) '+%Y-%m-%d %H:%M:%S')"; W1="$(date -r $((END + 1)) '+%Y-%m-%d %H:%M:%S')"
/usr/bin/log show --start "$W0" --end "$W1" --style compact --predicate \
    '(process == "thermalmonitord" AND eventMessage CONTAINS "mTPL") OR (process == "gamepolicyd" AND eventMessage CONTAINS[c] "game mode")' \
    > "$DIR/system-log.txt" 2>&1 || echo "(the log could not be read: $(tail -1 "$DIR/system-log.txt"))" >> "$DIR/system-log.txt"
pmset -g therm > "$DIR/thermal.txt" 2>&1

# What MacGameFix's fixes wrote in C:\mgf since the game started, the end of each.
if [ -n "$PREFIX" ] && [ -d "$PREFIX/drive_c/mgf" ]; then
    mkdir -p "$DIR/mgf"
    find "$PREFIX/drive_c/mgf" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' \) -newermt "$(date -r $((START - ${RUNNING:-3600} - 120)) '+%Y-%m-%d %H:%M:%S')" 2>/dev/null \
        | head -20 | while IFS= read -r f; do tail -c 200000 "$f" > "$DIR/mgf/$(basename "$f")" 2>/dev/null; done
    rmdir "$DIR/mgf" 2>/dev/null
fi

cat "$DIR/meta.txt.times" "$DIR/meta.txt" > "$DIR/capture.txt" && rm -f "$DIR/meta.txt.times" "$DIR/meta.txt"

# ---------------------------------------------------------------- no home folder, no Mac name
esc() { printf '%s' "$1" | sed 's/[][\\.*^$|]/\\&/g'; }
SED=(-e "s|$(esc "$HOME")|~|g")
for name in "$(scutil --get ComputerName 2>/dev/null)" "$(scutil --get LocalHostName 2>/dev/null)" "$(hostname -s 2>/dev/null)"; do
    [ "${#name}" -ge 5 ] && SED+=(-e "s|$(esc "$name")|(this Mac)|g")
done
find "$DIR" -type f | while IFS= read -r f; do
    sed "${SED[@]}" "$f" > "$f.clean" 2>/dev/null && mv "$f.clean" "$f"
done

( cd "$WORK" && zip -q -r "$ZIP" "$(basename "$DIR")" ) || { echo "The zip could not be written to $ZIP." >&2; exit 1; }

echo
echo "Saved: ${OUT:-~}/$(basename "$ZIP") ($(( $(stat -f %z "$ZIP") / 1024 )) KB)"
echo "  Seconds recorded:  $((END - START))"
echo "  Metal's frames:    $METAL"
echo "  Threads sampled:   $(grep -c '^==' "$DIR/threads.txt" 2>/dev/null || echo 0) times"
case "$METAL" in
    *"frames a second") ;;
    *) echo "  Without Metal's frames the capture still says how busy the processor and the memory were." ;;
esac
echo
echo "Drag that zip into your issue at https://github.com/MathiasKowoll/MacGameFix/issues"
[ -n "${OUT:-}" ] || open -R "$ZIP" 2>/dev/null
exit 0
