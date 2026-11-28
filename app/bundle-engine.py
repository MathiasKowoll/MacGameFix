# Copies the built Wine modules (engine/modules/<build>/<dir>/<file>) into the
# bundle flat, as engine-<build>-<dir>-<file>, since a catalog holds no folders;
# writes engine-modules.json, which says which CrossOver builds there are and which
# Wine each was built from; and prints the names. Each module is checked against
# the SHA-256 its built-for.json recorded.
#
# Each build also says whether it is maintained: the stable CrossOver and the
# latest Preview are, and an older Preview's modules stay as they were last built
# ("kept": installable, with nothing new built or checked for them). The builds
# kept are named in engine/support.json with the day they stopped; two Previews
# maintained at once is refused, so a new Preview cannot come in without the one
# before it being named there.
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
support = os.path.join(os.path.dirname(os.path.abspath(mods)), "support.json")
kept = json.load(open(support)).get("kept", {}) if os.path.isfile(support) else {}
for b in kept:
    if not os.path.isfile(os.path.join(mods, b, "built-for.json")):
        sys.exit(f"error: engine/support.json keeps {b}, which has no modules")
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
                   "wine": d["wine"].replace("Wine version ", ""), "files": d["files"],
                   "support": "kept" if b in kept else "maintained"})
previews = [b["build"] for b in builds if b["support"] == "maintained" and "Preview" in b["crossover"]]
if len(previews) > 1:
    sys.exit("error: more than one Preview is maintained (" + ", ".join(previews)
             + "): name the older ones under \"kept\" in engine/support.json")
# A build whose CrossOver app gets newer modules than its NotProton runner (engine/modules-app,
# 1.6.7's catalog for the latest Preview): bundled as engine-<build>-app-<dir>-<file>, which
# engine-modules.sh takes for a CrossOver app of that build.
extra = os.path.join(os.path.dirname(os.path.abspath(mods)), "modules-app")
for b in sorted(os.listdir(extra)) if os.path.isdir(extra) else []:
    meta = os.path.join(extra, b, "built-for.json")
    if not os.path.isfile(meta):
        continue
    d = json.load(open(meta))
    if d["build"] != b or b not in [x["build"] for x in builds]:
        sys.exit(f"error: engine/modules-app/{b} is not a build of engine/modules")
    for rel, want in sorted(d["files"].items()):
        src = os.path.join(extra, b, rel)
        if hashlib.sha256(open(src, "rb").read()).hexdigest() != want:
            sys.exit(f"error: engine/modules-app/{b}/{rel} is not what its built-for.json recorded")
        name = f"engine-{b}-app-{rel.replace('/', '-')}"
        shutil.copy2(src, os.path.join(res, name))
        print(name)
json.dump({"builds": builds}, open(os.path.join(res, "engine-modules.json"), "w"), indent=2)
