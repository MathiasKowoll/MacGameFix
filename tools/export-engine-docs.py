#!/usr/bin/env python3
"""Write docs/engine/engine.json: the Wine modules' patches and the code the site shows of them.

    tools/export-engine-docs.py            write it
    tools/export-engine-docs.py --check    fail if it is not what the sources say

The site's /wine page reads it from main. Two files in docs/engine/ hold what only a person can
say, and the rest is read from engine/patches/, so nothing is written twice:

  - patches.json, one line per patch, "<series>/<patch>": what it does. A patch without one fails,
    so a new patch cannot reach the site unnamed;
  - excerpts.json, "<key>": {"file", "symbol"} for a function the patch adds, cut from its
    definition (and the comment right above it) to its closing brace, the patch's "+" taken off;
    or {"file", "hunk"} for the one hunk whose lines match a pattern, shown as a diff.

Every series in engine/patches/ is listed with its patches by name, the modules each changes
(the dlls/ folders it touches) and a permalink pinned to the last commit that changed it, as
tools/export-fix-docs.py pins its excerpts.

Standard library only: it runs with the macOS /usr/bin/python3, like build-app.sh.
SPDX-License-Identifier: GPL-3.0-or-later
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCHES = os.path.join(ROOT, 'engine', 'patches')
DOCS = os.path.join(ROOT, 'docs', 'engine')
OUT = os.path.join(DOCS, 'engine.json')
REPOSITORY = 'MathiasKowoll/MacGameFix'
REPO = 'https://github.com/' + REPOSITORY


def fail(message):
    sys.exit('export-engine-docs: ' + message)


def git(*args):
    return subprocess.run(['git', '-C', ROOT] + list(args), check=True, capture_output=True, text=True).stdout.strip()


def pinned(rel):
    if git('status', '--porcelain', '--', rel):
        fail(f'{rel} has uncommitted changes; a permalink to it would point at other code')
    commit = git('log', '-1', '--format=%H', '--', rel)
    if not commit:
        fail(f'{rel} is not committed')
    return commit


def read_json(name):
    with open(os.path.join(DOCS, name), encoding='utf-8') as f:
        return json.load(f)


def modules(lines):
    """The dlls/ folders a patch changes, in the order it first touches them."""
    seen = []
    for line in lines:
        m = re.match(r'^\+\+\+ b/dlls/([^/\s]+)/', line)
        if m and m.group(1) not in seen:
            seen.append(m.group(1))
    return seen


def cut_symbol(rel, lines, symbol):
    """A function the patch adds: from the comment right above its definition to its closing brace."""
    name = re.escape(symbol)
    start = next((i for i, l in enumerate(lines)
                  if l.startswith('+') and re.search(rf'\b{name}\s*\(', l)
                  and not l[1:2].isspace() and not l.rstrip().endswith(';')), None)
    if start is None:
        fail(f'{rel}: no definition of {symbol} that the patch adds')
    # The closing brace can be a context line: a function added right before another's end.
    end = next((i for i in range(start, len(lines)) if lines[i] in ('+}', ' }')), None)
    if end is None:
        fail(f'{rel}: {symbol} has no closing brace in column 0')
    if lines[start - 1].rstrip().endswith('*/'):
        while start > 0 and not lines[start - 1][1:].lstrip().startswith('/*'):
            start -= 1
        start -= 1
    code = '\n'.join(l[1:] for l in lines[start:end + 1] if not l.startswith('-'))
    return start + 1, end + 1, code


def cut_hunk(rel, lines, pattern):
    """The one hunk with a line that matches, from its @@ line to the line before the next."""
    heads = [i for i, l in enumerate(lines) if l.startswith('@@ ')]
    found = []
    for n, start in enumerate(heads):
        end = (heads[n + 1] if n + 1 < len(heads) else len(lines)) - 1
        while lines[end].startswith(('--- ', '+++ ')) or lines[end] == '':
            end -= 1
        if any(re.search(pattern, l) for l in lines[start + 1:end + 1]):
            found.append((start, end))
    if len(found) != 1:
        fail(f'{rel}: {len(found)} hunks match {pattern!r}, not one')
    start, end = found[0]
    return start + 1, end + 1, '\n'.join(lines[start:end + 1])


def patch_lines(rel):
    with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
        return f.read().split('\n')


def builds(subjects):
    out, named = [], set()
    for series in sorted(os.listdir(PATCHES)):
        folder = os.path.join(PATCHES, series)
        if not os.path.isdir(folder) or not series.startswith('wine-'):
            continue
        patches = []
        for name in sorted(n for n in os.listdir(folder) if n.endswith('.patch')):
            rel = f'engine/patches/{series}/{name}'
            key = f'{series}/{name}'
            if key not in subjects:
                fail(f'docs/engine/patches.json has no line for {key}')
            named.add(key)
            commit = pinned(rel)
            patches.append({
                'name': name,
                'file': rel,
                'subject': subjects[key],
                'modules': modules(patch_lines(rel)),
                'commit': commit,
                'url': f'{REPO}/blob/{commit}/{rel}',
            })
        out.append({'wine': series[len('wine-'):], 'patches': patches})
    for key in sorted(set(subjects) - named):
        fail(f'docs/engine/patches.json names {key}, which is not in engine/patches')
    return out


def excerpts(wanted):
    out = {}
    for key, e in wanted.items():
        rel = e['file']
        lines = patch_lines(rel)
        if 'symbol' in e:
            first, last, code = cut_symbol(rel, lines, e['symbol'])
            language = 'c'
        else:
            first, last, code = cut_hunk(rel, lines, e['hunk'])
            language = 'diff'
        commit = pinned(rel)
        out[key] = {
            'file': rel,
            'symbol': e.get('symbol'),
            'language': language,
            'startLine': first,
            'endLine': last,
            'commit': commit,
            'url': f'{REPO}/blob/{commit}/{rel}#L{first}-L{last}',
            'code': code,
        }
    return out


def main():
    doc = {
        'schema': 1,
        'repository': REPOSITORY,
        'builds': builds(read_json('patches.json')),
        'excerpts': excerpts(read_json('excerpts.json')),
    }
    text = json.dumps(doc, ensure_ascii=False, indent=2) + '\n'
    count = sum(len(b['patches']) for b in doc['builds'])
    if '--check' in sys.argv:
        try:
            with open(OUT, encoding='utf-8') as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != text:
            fail('docs/engine/engine.json is out of date; run tools/export-engine-docs.py')
        print(f'docs/engine/engine.json is up to date ({count} patches, {len(doc["excerpts"])} excerpts)')
        return
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f'wrote docs/engine/engine.json: {len(doc["builds"])} series, {count} patches, {len(doc["excerpts"])} excerpts')


main()
