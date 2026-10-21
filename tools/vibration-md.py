#!/usr/bin/env python3
# Writes docs/vibration.md from docs/vibration.json, the list of games played for
# vibration. The JSON is the source: the website reads it too, so edit it and run
#   python3 tools/vibration-md.py
#
# SPDX-License-Identifier: GPL-3.0-or-later
import json
import pathlib

docs = pathlib.Path(__file__).resolve().parent.parent / "docs"
data = json.loads((docs / "vibration.json").read_text())
results = data["results"]


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def controller(test):
    name = test["controller"]
    if name == "not recorded":
        return "Controller not recorded"
    return f"{name} shown as a {test['shownAs']}" if test.get("shownAs") else name


def connection(game, name):
    """A table cell: each controller tested on this connection, and its result."""
    tests = [x for x in game["tests"] if x["connection"] in (name, "not recorded")]
    if not tests:
        return results["not-played"]
    def one(x):
        when = [x["date"]] if x.get("date") else []
        if x["connection"] == "not recorded":
            when.append("connection not recorded")
        return f"{controller(x)}: {results[x['result']]}" + (f" ({', '.join(when)})" if when else "")
    return "; ".join(one(x) for x in tests)


def test_line(test):
    where = data["connections"].get(test["connection"], "connection not recorded")
    text = f"{controller(test)}, {where}: {results[test['result']]}"
    if test.get("date"):
        text += f" ({test['date']})"
    if test.get("notes"):
        text += f". {test['notes']}"
    return text


lines = [
    "# Games played for vibration",
    "",
    "<!-- Made from vibration.json by tools/vibration-md.py: edit the JSON, then run the script. -->",
    "",
    data["about"].split(" docs/vibration.md")[0],
    "",
    f"Played with {data['stack']} Updated {data['updated']}.",
    "",
    "**How a game vibrates** decides what Game Feel needs to give it:",
    "",
    "- **Haptics**: the game plays its vibration as audio on the pad's haptic actuators, as on a PS5, and",
    "  usually sets trigger effects too. It needs the Wine modules for the pad's audio output.",
    "- **Motors**: the game writes the pad's rumble itself, and the pad plays it on its actuators the way it",
    "  emulates motors.",
    "- **XInput**: the game rumbles an Xbox-style controller. Game Feel's XInput option gives it the pad as an",
    "  XInput controller, or puts its rumble on the motors.",
    "",
    "| Game | Vibration | Library | Cable | Bluetooth |",
    "|---|---|---|---|---|",
]
for g in data["games"]:
    lines.append(f"| [{cell(g['name'])}](#{g['steamAppId']}) | {cell(g['vibration'])} | {cell(g.get('library', ''))} | "
                 f"{cell(connection(g, 'cable'))} | {cell(connection(g, 'bluetooth'))} |")

for g in data["games"]:
    lines += ["", f"<a id=\"{g['steamAppId']}\"></a>", f"## {g['name']}", "", g["description"], ""]
    lines.append(f"- **Status:** {results[g['status']]}")
    if g.get("library"):
        lines.append(f"- **Library:** {g['library']}")
    lines.append(f"- **Technology:** {g['technology']}")
    lines.append(f"- **Features:** {', '.join(g['features'])}")
    if g.get("settings"):
        lines.append(f"- **Settings:** {g['settings']}")
    lines.append(f"- **Steam app:** {g['steamAppId']}")
    lines += ["", "Tested:", ""] + [f"- {test_line(x)}" for x in g["tests"]]
    if g.get("details"):
        lines += ["", "What was measured:", ""] + [f"- {d}" for d in g["details"]]

lines += [
    "",
    "## Adding a game",
    "",
    "After a session, add the game to `vibration.json` with what was felt and what the modules logged (Game",
    "Feel's **Seen** column, or Diagnose this game), one test per controller and connection, then run",
    "`tools/vibration-md.py`. A game that needed a setting says which one; if many players need the same one, it",
    "becomes the game's suggested setting in `app/pad-presets.json`.",
    "",
]
(docs / "vibration.md").write_text("\n".join(lines))
