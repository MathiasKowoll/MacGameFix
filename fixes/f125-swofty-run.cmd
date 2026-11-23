@echo off
rem F1 25 through Swofty Launcher, inside the game's NotProton prefix. Started by
rem f125-swofty-play.sh; install-f125-swofty.sh keeps both beside the launcher.
rem
rem NotProton gives a game STEAM_COMPAT_TOOL_PATHS, as Proton does. With it set, Swofty starts
rem the game as "<that folder>\proton run <its session launcher>", and NotProton's tool has
rem "run" but no "proton": the launch ended with "File not found (os error 2)" (2026-11-23,
rem seen with WINEDEBUG=+process). Without it Swofty starts its session launcher itself, as
rem it does in a CrossOver bottle. NotProton does not let a launch option change a
rem STEAM_COMPAT_ variable, so it is cleared here.
rem
rem Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
rem SPDX-License-Identifier: GPL-3.0-or-later
set "STEAM_COMPAT_TOOL_PATHS="
set "swofty=%~dp0launcher\bin\swofty.exe"
set "data=%LOCALAPPDATA%\Swofty"

rem Offline play is Swofty's own: its terms are the player's to read and accept, so the first
rem start shows them in this window and waits for the answer. Then Swofty downloads its
rem extension. Neither is done again once done.
if not exist "%data%\state\offline_consent.json" (
  echo Swofty asks you to read and accept its offline play terms before the first start.
  "%swofty%" offline accept
  if errorlevel 1 exit /b 1
)
if not exist "%data%\extensions\offline-play\f1op_hook.dll" (
  echo Swofty is downloading its offline play extension.
  "%swofty%" offline fetch
  if errorlevel 1 exit /b 1
)

rem Swofty's one-time setup before modded play: it puts the game folder back and starts its
rem record of the original game files. Swofty checks every game file against Steam's own list
rem at each start, so it asks for no verification in Steam.
"%swofty%" setup status | findstr /c:"setup: done" > nul
if errorlevel 1 (
  echo Swofty's one-time setup: it records the game's original files before the first modded start.
  echo If you ever put mods in the game folder by hand, close this window, verify the game files
  echo in Steam, and press Play again. Otherwise:
  pause
  "%swofty%" setup reset
  if errorlevel 1 exit /b 1
  "%swofty%" setup done
  if errorlevel 1 exit /b 1
)

rem An empty variable still counts as defined in Wine's cmd, so the value is compared.
set "args=run --apply --no-start-store"
if not "%F125_PROFILE%"=="" set "args=%args% --profile %F125_PROFILE%"
echo Swofty is building the profile and starting F1 25. Its output goes to f125-swofty-play.log.
"%swofty%" %args% -- "%F125_STEAM_COMMAND%" > "%~dp0f125-swofty-play.log" 2>&1
exit /b %errorlevel%
