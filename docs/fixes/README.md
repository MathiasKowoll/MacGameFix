# The fixes, game by game

Every game MacGameFix fixes has a file in [`games/`](games), and
[`fixes.json`](fixes.json) puts them together with the code. This is the part
of the repository meant to be read: by someone who wants to know what went
wrong with a game and why, by someone from Wine who wants to check it, and by
anyone fixing another game the same way.

Each game answers the same five questions:

| | |
| --- | --- |
| **Symptom** | What you see: the crash, the black picture, the message |
| **Cause** | Why it happens, measured, not guessed |
| **Fix** | What changes, and where: the game folder, the prefix, the app |
| **Code** | The functions that do it, cut out of the source with a permalink to the commit |
| **Credits** | Whose work it stands on, with a link to theirs |

The long story, with the measurements and the wrong turns, is the game's page
under [`legacy/wiki`](../../legacy/wiki); its summary table is where the
symptom, the cause and the fix are read from.

## A game's file

```json
{
  "title": "Mortal Kombat 11",
  "installer": "install-mk11-fix.sh",
  "scope": "folder",
  "executable": "MK11_DX12.exe",
  "carrierDirectory": "Binaries/Retail",
  "alsoRuns": ["MK11.exe"],
  "summary": "The installer's MGVF-WHY line",
  "page": "legacy/wiki/Mortal-Kombat-11.md",
  "installs": ["amd_ags_x64-mk11.dll", "pe.pl"],
  "builtFrom": ["mk11-face-fix.c", "sm2fix_core.c", "mk11-morph-shaders.h", "mk11-movie.c"],
  "license": "GPL-3.0-or-later",
  "credits": [{ "name": "Anton Pavliuk", "url": "https://github.com/CyberDogFK/mk11-crossover-fix", "note": "What they did" }],
  "excerpts": [{ "file": "mk11-movie.c", "symbol": "hand_out", "note": "What these lines solve" }]
}
```

- `title`, `executable`, `carrierDirectory` and `alsoRuns` are the installer's
  `MGVF-GAME` line, and the export fails if they stop agreeing.
- `symptom`, `cause` and `fix` come from the page's table. Write them in the
  file only where the page has none, or says it for several games at once.
- An excerpt names a function (`symbol`), or a range between two patterns
  (`from`, `to`) for a script or a recipe. It is cut from the source on every
  export, so it follows the code; nothing is pasted by hand.
- `license` is the installer's SPDX line. The fixes are GPL-3.0-or-later; the
  Wine modules in `engine/` are LGPL-2.1-or-later, which is what makes them
  fit for Wine.
- A fix that came from someone else's work says so in `credits`, with a link to
  the original repository. A commit message is not credit.

## Adding a game

1. Write its installer in `fixes/`, with its `MGVF-GAME`, `MGVF-SCOPE` and
   `MGVF-WHY` lines.
2. Write its page under `legacy/wiki`, starting with the summary table.
3. Add `docs/fixes/games/<slug>.json` and run:

```bash
tools/export-fix-docs.py
```

`tools/export-fix-docs.py --check` says whether `fixes.json` is still what the
sources say. Commit the sources first: a permalink points at the last commit
that changed each file, so an uncommitted change would make it point at other
code.

## Where it goes

The [MacGameFix site](https://macgamefix.app) shows each game from this
file, through the database it is imported into. This repository stays the
source: what is edited is edited here.
