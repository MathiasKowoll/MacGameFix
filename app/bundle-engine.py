# Copies the built Wine modules (engine/modules/<build>/<dir>/<file>) into the
# bundle flat, as engine-<build>-<dir>-<file>, since a catalog holds no folders;
# writes engine-modules.json, which says which CrossOver builds there are and which
# Wine each was built from; and prints the names. Each module is checked against
# the SHA-256 its built-for.json recorded.
#
#   python3 bundle-engine.py <engine/modules> <bundle Resources>
#
# Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import os
import shutil
import sys

mods, res = sys.argv[1:3]
builds = []
for b in sorted(os.listdir(mods)):
    meta = os.path.join(mods, b, "built-for.json")
    if not os.path.isfile(meta):
        continue
    d = json.load(open(meta))
    if d["build"] != b:
        sys.exit(f"error: engine/modules/{b}/built-for.json says build {d['build']}")
    for rel, want in sorted(d["files"].items()):
        src = os.path.join(mods, b, rel)
        if hashlib.sha256(open(src, "rb").read()).hexdigest() != want:
            sys.exit(f"error: engine/modules/{b}/{rel} is not what its built-for.json recorded")
        name = f"engine-{b}-{rel.replace('/', '-')}"
        shutil.copy2(src, os.path.join(res, name))
        print(name)
    builds.append({"build": b, "crossover": d.get("crossover", b),
                   "wine": d["wine"].replace("Wine version ", ""), "files": d["files"]})
json.dump({"builds": builds}, open(os.path.join(res, "engine-modules.json"), "w"), indent=2)
