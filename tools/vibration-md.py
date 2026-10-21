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


def connection(game, name):
    c = game["connections"][name]
    out = results[c["result"]]
    if c.get("pads"):
        out += f", {c['pads']}"
    if c.get("date"):
        out += f" ({c['date']})"
    return out


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
    for name, label in (("cable", "Cable"), ("bluetooth", "Bluetooth")):
        c = g["connections"][name]
        text = connection(g, name)
        if c.get("notes"):
            text += f". {c['notes']}"
        lines.append(f"- **{label}:** {text}")
    if g.get("settings"):
        lines.append(f"- **Settings:** {g['settings']}")
    lines.append(f"- **Steam app:** {g['steamAppId']}")
    if g.get("details"):
        lines += ["", "What was measured:", ""] + [f"- {d}" for d in g["details"]]

lines += [
    "",
    "## Adding a game",
    "",
    "After a session, add the game to `vibration.json` with what was felt and what the modules logged (Game",
    "Feel's **Seen** column, or Diagnose this game), one result per connection, then run",
    "`tools/vibration-md.py`. A game that needed a setting says which one; if many players need the same one, it",
    "becomes the game's suggested setting in `app/pad-presets.json`.",
    "",
]
(docs / "vibration.md").write_text("\n".join(lines))
