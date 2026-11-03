# Games that run because of an improvement

[`games.json`](games.json) lists the games that run because of one of the
improvements in the app's **Improvements** tab: the Wine modules MacGameFix
installs into a CrossOver app or a NotProton runner. They are not fixes. A fix
goes into one game's folder or prefix and is listed in [`../fixes`](../fixes).
A game that needs both a fix and an improvement names its fix in `fix`.

The DualSense controllers improvement has a list of its own,
[`../vibration.json`](../vibration.json), because a controller is tested per
pad and per connection. That improvement appears here only when a game needs it
in order to run at all.

Each game has a `status`:

| | |
| --- | --- |
| `played` | We played it, on the CrossOver and Mac its test names |
| `reported` | Someone else reported it working, named in `by`; we have not played it |
| `in-progress` | Reported working, or expected to, but it does not run here yet; its last test says where it stops |

A reported game becomes `played` only after we play it, with a test of our own
added beside the report. One we tried that does not run yet becomes `in-progress`,
with that test, until it does. Nothing is added from what an improvement should do.

Each test records:

- what the game was played on: the Mac, the macOS, the CrossOver build or the
  Game Porting Toolkit, and the runner;
- who played it;
- what was seen.

Leave a field out when it is not known; do not guess it.

The site reads this file from `main`, as it reads `fixes.json` and
`vibration.json`.
