@echo off
rem EA SPORTS FC 27 with FC 27 Live Editor, inside the game's NotProton prefix. Started by
rem fc27-le-play.sh; install-fc27-live-editor.sh keeps both beside the Live Editor folder.
rem Its notes go to fc27-le-run.log beside it.
rem
rem What has to happen, and in which order (all of it seen on 2026-11-23):
rem   1. Live Editor's launcher first. It puts its stand-in for EA AntiCheat's launcher in the
rem      game folder (keeping the game's own as .exe.backup) and waits for FC27.exe. It has to
rem      be waiting BEFORE the game starts: a launcher that comes up late injects into a game
rem      that is already past its start, and the game freezes.
rem   2. Steam's own command, through NotProton's Steam stub. The EA app checks the licence
rem      and starts what it takes for EA AntiCheat's launcher; the stand-in starts FC27.exe,
rem      the launcher injects its DLL, closes itself and puts the game's own file back.
rem   3. Stay until FC27.exe is gone. The EA app's launcher ends right after the game has
rem      started, and NotProton closes the prefix, the game with it, when the program it
rem      started ends. That program is this batch file.
rem
rem cmd reads a batch file a line at a time from the file: do not edit this one while a start
rem is running, the run goes on in the middle of a line of the new text.
rem
rem Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
rem SPDX-License-Identifier: GPL-3.0-or-later
set "log=%~dp0fc27-le-run.log"
set "le=%~dp0LiveEditor"
set "config=C:\FC 27 Live Editor\le_config.json"
echo start %date% %time% > "%log%"

rem "Play opens: Live Editor's launcher window". The window alone, for as long as it is open;
rem closing it is what makes the launcher put the game's own file back and save its settings.
rem Its own "Run Game" asks the EA app through another link and starts nothing here.
if /i "%FC27_OPENS%"=="window" goto window

rem The launcher's log says how far it is, and it keeps that log open for writing, which find
rem cannot read: a copy is read. Earlier logs are set aside so that this start's is the one.
if not exist "%le%\Logs" mkdir "%le%\Logs"
if not exist "%le%\Logs\old" mkdir "%le%\Logs\old"
move /y "%le%\Logs\*.log" "%le%\Logs\old" > nul 2>&1
del "%le%\Logs\old\ready-check.txt" > nul 2>&1

rem The first start in this prefix: the launcher has no settings file yet, and it writes one
rem when it closes. fc27-le-play.sh needs the file to raise the launcher's injection delay,
rem without which the game hangs at "Injecting" in some starts. So the launcher is opened and
rem closed once, and the game is for the next Play.
if not exist "%config%" goto first

echo opening Live Editor's launcher at %time% >> "%log%"
start "" /d "%le%" "%le%\Launcher.exe"
set /a tries=0
:ready
set "ok=0"
for %%f in ("%le%\Logs\live_editor_launcher_*.log") do copy /y "%%f" "%le%\Logs\old\ready-check.txt" > nul 2>&1
find "STATUS_WAITING_FOR_GAME" "%le%\Logs\old\ready-check.txt" > nul 2>&1 && set "ok=1"
if "%ok%"=="1" goto isready
set /a tries=tries+1
if %tries% geq 75 goto notready
ping -n 3 127.0.0.1 > nul
goto ready
:notready
echo Live Editor's launcher was not waiting for the game after 150 s: the game is not started >> "%log%"
echo Live Editor's launcher did not get ready. Look at its window and at its Logs folder.
taskkill /im Launcher.exe >> "%log%" 2>&1
exit /b 1
:isready
echo Live Editor's launcher is waiting for the game at %time% (after %tries% checks) >> "%log%"

rem Steam's own command. Started without waiting: the stub does not return while the EA app's
rem background service lives, which is long after the game has closed. /b keeps the game's
rem Wine output in NotProton's log for the game. The link has an ampersand, so it is only
rem ever written inside quotes.
echo starting "%FC27_STEAM_COMMAND%" at %time% >> "%log%"
start "" /b "C:\Program Files (x86)\Steam\steam.exe" "%FC27_STEAM_COMMAND%"

rem The EA app checks the licence and syncs saves before it starts the game: FC27.exe gets
rem four minutes to show up.
set /a tries=0
:appear
tasklist | find /i "FC27.exe" > nul
if not errorlevel 1 goto running
set /a tries=tries+1
if %tries% geq 80 goto never
ping -n 4 127.0.0.1 > nul
goto appear
:never
echo FC27.exe never started (4 minutes) at %time% >> "%log%"
goto restore
:running
echo FC27.exe is running at %time% >> "%log%"

:wait
ping -n 4 127.0.0.1 > nul
tasklist | find /i "FC27.exe" > nul
if not errorlevel 1 goto wait
echo FC27.exe is gone at %time% >> "%log%"

:restore
rem The launcher closes itself once it has injected. If it is still there, closing it is what
rem makes it put the game's own EA AntiCheat launcher back.
taskkill /im Launcher.exe >> "%log%" 2>&1
ping -n 4 127.0.0.1 > nul
echo end %time% >> "%log%"
exit /b 0

:first
echo first start: opening Live Editor's launcher once so that it writes its settings >> "%log%"
echo First start with Live Editor in this prefix.
echo Its launcher opens for a moment and closes again, to write its settings.
start "" /d "%le%" "%le%\Launcher.exe"
set /a tries=0
:firstready
set "ok=0"
for %%f in ("%le%\Logs\live_editor_launcher_*.log") do copy /y "%%f" "%le%\Logs\old\ready-check.txt" > nul 2>&1
find "SetupImGUI] Done" "%le%\Logs\old\ready-check.txt" > nul 2>&1 && set "ok=1"
if "%ok%"=="1" goto firstclose
set /a tries=tries+1
if %tries% geq 75 goto firstclose
ping -n 3 127.0.0.1 > nul
goto firstready
:firstclose
taskkill /im Launcher.exe >> "%log%" 2>&1
set /a tries=0
:firstsaved
if exist "%config%" goto firstdone
set /a tries=tries+1
if %tries% geq 15 goto firstfailed
ping -n 3 127.0.0.1 > nul
goto firstsaved
:firstfailed
echo the launcher wrote no settings file (%config%) >> "%log%"
echo Live Editor's launcher did not write its settings. Look at its Logs folder,
echo and check that the Live Editor you installed is the one for this version of the game.
pause
exit /b 1
:firstdone
echo first start done at %time%: the settings file is there >> "%log%"
echo.
echo Done. Press Play again: from now on Play starts the game with Live Editor.
pause
exit /b 0

:window
echo opening Live Editor's launcher window at %time% >> "%log%"
start "" /wait /d "%le%" "%le%\Launcher.exe"
echo the launcher's window was closed at %time% >> "%log%"
exit /b 0
