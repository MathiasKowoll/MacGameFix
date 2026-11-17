#!/usr/bin/env python3
"""Read what tools/capture-performance.sh recorded.

    python3 -I tools/read-performance.py <the zip, or its folder> [seconds a row]

Prints, in this order: the Mac and what runs the game; the frames as Metal recorded them, whole and in
rows of ten seconds; the game's threads; the processor's speed; memory; the other busy programs and the
program that was in front; what macOS logged; and the logs MacGameFix's fixes wrote.

It prints numbers and says what each one is. It does not say why a game is slow: that is read from the
numbers side by side, and from a second capture after one thing was changed.

A zip is unpacked into a temporary folder and only the files a capture is made of are read from it.

Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
SPDX-License-Identifier: GPL-3.0-or-later
"""
import collections
import datetime
import json
import os
import re
import statistics
import sys
import tempfile
import zipfile


def find(arg):
    """The capture's folder, from a zip or a folder that holds capture.txt at any depth."""
    if os.path.isfile(arg):
        out = tempfile.mkdtemp(prefix="mgf-performance-")
        with zipfile.ZipFile(arg) as z:
            for m in z.infolist():
                name = m.filename
                # No path out of the folder, and nothing that is not a capture's own kind of file.
                if name.startswith("/") or ".." in name.split("/") or m.is_dir():
                    continue
                if not re.search(r"\.(txt|json|log)$", name) or m.file_size > 200 << 20:
                    continue
                z.extract(m, out)
        arg = out
    for root, _, files in os.walk(arg):
        if "capture.txt" in files:
            return root
    sys.exit("no capture.txt in " + arg)


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def stats(values):
    """(median, lowest, highest) of a list, or None."""
    return (statistics.median(values), min(values), max(values)) if values else None


def head(title):
    print("\n" + title + "\n" + "-" * len(title))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = find(sys.argv[1])
    step = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    # ------------------------------------------------------------------ the Mac and the game
    text = read(os.path.join(d, "capture.txt"))
    top, _, rest = text.partition("\n## ")
    meta = dict(l.split(": ", 1) for l in top.splitlines() if ": " in l)
    sections = {}
    for block in ("## " + rest).split("\n## ") if rest else []:
        title, _, body = block.lstrip("# ").partition("\n")
        sections[title.strip()] = [l for l in body.splitlines() if l.strip()]
    start, end = int(meta.get("from", 0)), int(meta.get("to", 0))
    ram = float(meta.get("memory GB", 0) or 0)
    pcores, ecores = int(meta.get("performance cores") or 0), int(meta.get("efficiency cores") or 0)

    head("The capture")
    when = datetime.datetime.fromtimestamp(start).strftime("%Y-%m-%d %H:%M:%S") if start else "?"
    print(f"{meta.get('game', '?')}, {end - start} s from {when} (this Mac's clock), asked {meta.get('asked seconds', '?')}")
    if "ended" in meta:
        print("NOTE: " + meta["ended"])
    print(f"{meta.get('model', '?')}, {meta.get('chip', '?')}: {pcores} performance + {ecores} efficiency cores, "
          f"{ram:.0f} GB; macOS {meta.get('macOS', '?')}; {meta.get('power', '')}")
    for l in sections.get("displays", []):
        if re.match(r"(Display Type|Resolution|UI Looks like|Refresh Rate)", l):
            print("  " + l)
    print(f"process: {meta.get('process', '?')}, running for {meta.get('running for seconds', '?')} s before the capture")
    print(f"prefix: {meta.get('prefix', '?')}")
    launch = sections.get("the launch NotProton made last", [])
    if launch:
        game = meta.get("game", "").lower()
        mine = game and game in launch[0].lower()
        print("launch (NotProton's last" + ("" if mine else ", WHICH DOES NOT NAME THIS GAME: it may be another's") + "):")
        print("  " + re.sub(r"^.*handed to /bin/sh -c: ", "", launch[0]))
    mods = sections.get("the loader and the graphics, upscaler and controller modules the game has open", [])
    if mods:
        print("modules open:")
        folders = collections.OrderedDict()
        for m in mods:
            folders.setdefault(os.path.dirname(m), []).append(os.path.basename(m))
        for folder, names in folders.items():
            print(f"  {folder}: {', '.join(names)}")
    others = sections.get("other programs with an .exe", [])
    if others:
        print("other .exe programs: " + ", ".join(sorted(set(o.split(" ", 1)[-1] for o in others))))

    # ------------------------------------------------------------------ frames
    head("Frames (Metal's own record)")
    entries = []
    for name in sorted(os.listdir(d)):
        if re.fullmatch(r"metal-\d+\.json", name):
            try:
                loaded = json.loads(read(os.path.join(d, name)))
            except ValueError:
                loaded = []
            entries += [e for e in loaded if isinstance(e, dict)] if isinstance(loaded, list) else []
    layers = [(e, L) for e in entries for L in e.get("Layers", [])]
    footprint = None
    if not layers:
        print("none: " + meta.get("metal", "no metal file in the capture"))
    for e, L in layers:
        cfg = (L.get("Configuration Timeline") or [{}])[-1]
        tot = L.get("Total Session Stats", {})
        p = tot.get("Presented Frame Stats", {})
        gap = tot.get("Frame-On-Glass Interval Stats", {})
        print(f"layer {cfg.get('Name', '?')}: {cfg.get('Width (pixels)', '?')} x {cfg.get('Height (pixels)', '?')} "
              f"{cfg.get('MTL Pixel Format Name', '')}" + (f" ({len(L['Configuration Timeline'])} configurations)" if len(L.get("Configuration Timeline", [])) > 1 else ""))
        if not p.get("Frame Count"):
            print("  no frame presented")
            continue
        print(f"  {p['Frame Count']} frames in {tot.get('Total Duration (sec)', 0):.0f} s: {p.get('FPS', 0):.1f} a second; "
              f"between two frames on screen {gap.get('Average (ms)', 0):.1f} ms on average, {gap.get('Max (ms)', 0):.0f} ms the longest")

        def ms(key):
            return p.get(key, {}).get("Average (ms)", 0)
        frame = gap.get("Average (ms)", 0) or 1
        # Metal times a frame by its command buffers. A game whose frames reach it with hardly any (seen:
        # 156 for 7311 frames) leaves those times covering none of the work, and they are not printed.
        timed = p.get("Command Buffer Count", 0) >= p["Frame Count"] / 2
        if timed:
            print(f"  a frame, on average: {ms('End-to-end Walltime Stats (CPU)'):.1f} ms from its first command to commit, "
                  f"{ms('On-GPU Walltime Stats'):.1f} ms on the graphics ({100 * ms('On-GPU Walltime Stats') / frame:.0f}% of the gap between frames), "
                  f"{ms('Next Drawable Wait Walltime Stats'):.1f} ms waiting for a drawable")
        else:
            print(f"  a frame, on average: {ms('Next Drawable Wait Walltime Stats'):.1f} ms waiting for a drawable. Metal counted "
                  f"{p.get('Command Buffer Count', 0)} command buffers for these frames, so its times on the processor and on the graphics say nothing here")
        fx = [k for k in ("Metal FX Temporal Scaling Frames", "Metal FX Spatial Scaling Frames", "Metal FX Denoising Scaling Frames",
                          "MetalFX Frame Interpolator Enabled Frames") if p.get(k)]
        if fx:
            ratio = p.get("Metal FX Scaling Ratio Stats", {})
            print("  MetalFX: " + ", ".join(k.replace("Metal FX ", "").replace("MetalFX ", "").replace(" Frames", "").lower() for k in fx)
                  + (f"; scaling ratio {ratio.get('Average', 0):.2f}" if ratio.get("Count") else ""))
        rows = collections.OrderedDict()
        persec, longest = [], []
        for w in L.get("Stats Timeline", []):
            wp = w.get("Presented Frame Stats", {})
            dur = w.get("Total Duration (sec)", 0)
            t = datetime.datetime.fromisoformat(w["Start Date"].replace("Z", "+00:00")).astimezone()
            key = t.replace(second=t.second // step * step, microsecond=0) if step < 60 else t.replace(second=0, microsecond=0)
            r = rows.setdefault(key, dict(n=0, dur=0.0, gap=0.0, gpu=0.0, cpu=0.0, wait=0.0, shaders=0, sh_time=0.0))
            n = wp.get("Frame Count", 0)
            g = w.get("Frame-On-Glass Interval Stats", {}).get("Max (ms)", 0)
            r["n"] += n; r["dur"] += dur; r["gap"] = max(r["gap"], g)
            r["gpu"] += wp.get("On-GPU Walltime Stats", {}).get("Total (ms)", 0)
            r["cpu"] += wp.get("End-to-end Walltime Stats (CPU)", {}).get("Total (ms)", 0)
            r["wait"] += wp.get("Next Drawable Wait Walltime Stats", {}).get("Total (ms)", 0)
            sc = wp.get("Shader Compiler", {})
            r["shaders"] += sc.get("Shader Compilations", 0); r["sh_time"] += sc.get("Shader Compilation Time", 0)
            if dur:
                persec.append(n / dur); longest.append(g)
        if persec:
            med = statistics.median(persec)
            print(f"  a second at a time: {med:.1f} frames the median, {min(persec):.1f} the slowest second, {max(persec):.1f} the fastest; "
                  f"seconds with a gap over 50 ms: {sum(g > 50 for g in longest)} of {len(longest)}, over 100 ms: {sum(g > 100 for g in longest)}")
        print(f"  {'from':8} {'frames/s':>8} {'longest gap':>12} {'graphics':>9} {'cpu':>7} {'drawable':>9} {'new shaders':>12}")
        for key, r in rows.items():
            n = r["n"] or 1
            work = f"{r['gpu'] / n:6.1f} ms {r['cpu'] / n:4.1f} ms" if timed else f"{'-':>9} {'-':>7}"
            print(f"  {key.strftime('%H:%M:%S')} {r['n'] / r['dur'] if r['dur'] else 0:8.1f} {r['gap']:9.0f} ms {work} "
                  f"{r['wait'] / n:6.1f} ms {r['shaders']:6d}" + (f" ({r['sh_time']:.1f} s)" if r["sh_time"] else ""))
        use = e.get("Resource Usage", {})
        if use:
            footprint = use.get("Physical Footprint (MiB)")
            print(f"  the game's memory: {use.get('Physical Footprint (MiB)', 0) / 1024:.1f} GB ({use.get('Peak Physical Footprint (MiB)', 0) / 1024:.1f} at its peak), "
                  f"of which Metal holds {use.get('Metal Device Allocated Size (MiB)', 0) / 1024:.1f} GB" + (f"; this Mac has {ram:.0f} GB" if ram else ""))

    # ------------------------------------------------------------------ threads
    head("The game's threads (ps -M, a reading a second)")
    samples = []
    for block in read(os.path.join(d, "threads.txt")).split("== ")[1:]:
        lines = block.splitlines()
        rows = []
        for l in lines[1:]:
            f = l.split()
            if len(f) >= 5:
                try:
                    rows.append((float(f[0]), f[1], f[3], f[4]))
                except ValueError:
                    pass
        samples.append((int(lines[0]), rows))

    def secs(clock):
        """ps's minutes:seconds.hundredths, or hours:minutes:seconds, as seconds."""
        s = 0.0
        for part in clock.split(":"):
            s = s * 60 + float(part)
        return s
    if not samples:
        print("none")
    else:
        totals = [sum(r[0] for r in rows) / 100 for _, rows in samples]
        counts = [len(rows) for _, rows in samples]
        print(f"{len(samples)} readings, {min(counts)}-{max(counts)} threads; the whole game: {statistics.mean(totals):.1f} cores on average, "
              f"{min(totals):.1f} to {max(totals):.1f}" + (f", of {pcores} + {ecores}" if pcores else ""))
        ranked = [sorted((r[0] for r in rows), reverse=True) for _, rows in samples]
        print("the busiest threads, each reading sorted (% of one core):")
        for k in range(min(8, max(counts))):
            v = [r[k] for r in ranked if len(r) > k]
            print(f"  #{k + 1}: {statistics.mean(v):5.1f} on average, {statistics.median(v):5.1f} the median, {max(v):5.1f} the most; at 90 or more in {sum(x >= 90 for x in v)} of {len(v)} readings")
        busy = [sum(x >= 50 for x in r) for r in ranked]
        print(f"threads over 50% of a core in a reading: {statistics.mean(busy):.1f} on average, {max(busy)} the most")
        first, last = samples[0][1], samples[-1][1]
        if len(first) == len(last) and len(samples) > 1:
            sy = sum(secs(b[2]) - secs(a[2]) for a, b in zip(first, last))
            us = sum(secs(b[3]) - secs(a[3]) for a, b in zip(first, last))
            if sy + us >= 1:
                print(f"processor time over the capture: {us:.0f} s in the game's own code, {sy:.0f} s in the system ({100 * sy / (sy + us):.0f}%)")
        else:
            print("(threads came and went, so the split between the game's own code and the system is not added up)")

    # ------------------------------------------------------------------ the whole Mac, and the processor's speed
    head("The processor")
    idle = []
    for l in read(os.path.join(d, "system.txt")).splitlines():
        f = l.split()
        # iostat: per disk "KB/t tps MB/s", then "us sy id", then three load averages. Its first line is since boot.
        if len(f) >= 6 and re.fullmatch(r"[\d.]+", f[0]):
            idle.append(tuple(int(x) for x in f[-6:-3]))
    idle = idle[1:]
    if idle:
        print(f"the whole Mac, a second at a time: {statistics.mean(u for u, _, _ in idle):.0f}% in programs, {statistics.mean(s for _, s, _ in idle):.0f}% in the system, "
              f"{statistics.mean(i for _, _, i in idle):.0f}% idle ({min(i for _, _, i in idle)}% the least idle)")
    ghz, ipc = [], []
    for block in read(os.path.join(d, "top.txt")).split("\nPID ")[2:]:      # the first reading has nothing to compare with
        f = block.splitlines()[1].split() if len(block.splitlines()) > 1 else []
        if len(f) >= 10:
            cpu = float(f[1]); instrs, cycles = (float(x.rstrip("+-")) for x in f[8:10])
            if cpu >= 20 and cycles:
                ghz.append(cycles / (cpu / 100 * 5) / 1e9); ipc.append(instrs / cycles)
    if ghz:
        print(f"the speed the game's threads ran at (cycles for each second of processor time, every 5 s): {statistics.median(ghz):.2f} GHz the median, "
              f"{min(ghz):.2f} to {max(ghz):.2f}; {statistics.median(ipc):.2f} instructions a cycle")
        print("  (a mean over performance and efficiency cores: it falls when macOS slows the processor and when work moves to efficiency cores)")

    # ------------------------------------------------------------------ memory
    head("Memory")
    mem = []
    for l in read(os.path.join(d, "memory.txt")).splitlines():
        f = l.split()
        if len(f) > 6:
            row = {"t": int(f[0]), "level": f[2], "swap": f[4]}
            row.update({f[i]: int(f[i + 1]) for i in range(5, len(f) - 1, 2) if f[i + 1].isdigit()})
            mem.append(row)
    if mem:
        a, b = mem[0], mem[-1]
        names = {"1": "normal", "2": "warning", "4": "critical"}
        levels = collections.Counter(names.get(m["level"], m["level"]) for m in mem)
        print("pressure: " + ", ".join(f"{k} in {v} of {len(mem)} readings" for k, v in levels.items()))
        page = 16384 / 2**30
        print(f"swap in use: {a['swap']} at the start, {b['swap']} at the end; swapped out during the capture: {(b.get('Swapouts', 0) - a.get('Swapouts', 0)) * page:.2f} GB, "
              f"swapped in: {(b.get('Swapins', 0) - a.get('Swapins', 0)) * page:.2f} GB, read from disk: {(b.get('Pageins', 0) - a.get('Pageins', 0)) * page:.2f} GB")
        print(f"compressed: {a.get('Pages_occupied_by_compressor', 0) * page:.1f} GB at the start, {b.get('Pages_occupied_by_compressor', 0) * page:.1f} GB at the end; "
              f"free: {min(m.get('Pages_free', 0) for m in mem) * page:.2f} GB at the least")
        if footprint and ram:
            print(f"the game alone is {footprint / 1024:.1f} of this Mac's {ram:.0f} GB")

    # ------------------------------------------------------------------ the other programs
    head("The busiest programs (every 5 s, % of one core, averaged over the readings)")
    blocks = read(os.path.join(d, "busiest.txt")).split("== ")[1:]
    use, big = collections.Counter(), {}
    for block in blocks:
        for l in block.splitlines()[1:]:
            f = l.split(None, 2)
            if len(f) == 3:
                try:
                    use[f[2]] += float(f[0]); big[f[2]] = max(big.get(f[2], 0), int(f[1]))
                except ValueError:
                    pass
    for name, total in use.most_common(8):
        print(f"  {total / max(len(blocks), 1):6.1f}  {big[name]:6d} MB  {name}")
    front = collections.Counter(l.split(" ", 1)[1] if " " in l else "(not read)" for l in read(os.path.join(d, "front.txt")).splitlines())
    if front:
        print("in front: " + ", ".join(f"{k or '(not read)'} in {v} of {sum(front.values())} readings" for k, v in front.most_common()))

    # ------------------------------------------------------------------ what macOS said
    head("macOS's log for those minutes")
    log = [l for l in read(os.path.join(d, "system-log.txt")).splitlines() if not l.startswith("Timestamp")]
    thermal = [l for l in log if "mTPL" in l]
    mode = [l for l in log if re.search("game mode", l, re.I)]
    print(f"{len(thermal)} thermal level lines" + (", the last: " + thermal[-1][:200] if thermal else ""))
    print(f"{len(mode)} Game Mode lines" + ("".join("\n  " + l[:200] for l in mode[-4:]) if mode else ""))
    for l in log:
        if l.startswith("("):
            print(l)
    for l in read(os.path.join(d, "thermal.txt")).splitlines():
        if l.strip() and "No " not in l:
            print("pmset: " + l.strip())

    # ------------------------------------------------------------------ the fixes' own logs
    mgf = os.path.join(d, "mgf")
    if os.path.isdir(mgf):
        head("What MacGameFix's fixes logged in C:\\mgf")
        for name in sorted(os.listdir(mgf)):
            lines = read(os.path.join(mgf, name)).splitlines()
            print(f"{name}: {len(lines)} lines, the last:")
            for l in lines[-3:]:
                print("  " + l[:200])


if __name__ == "__main__":
    main()
