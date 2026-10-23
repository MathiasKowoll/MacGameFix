#!/usr/bin/env python3
"""Write docs/fixes/fixes.json: every game fix, what goes wrong, why, how it is fixed, and the code.

    tools/export-fix-docs.py            write it
    tools/export-fix-docs.py --check    fail if it is not what the sources say

Each game has a file in docs/fixes/games/. It holds what only a person can say: which page
tells the story, who the fix owes, and which functions show the fix. The rest is read from
where it already lives, so nothing is written twice:

  - the installer's MGVF lines (title, executable, scope, why), copied into the game's file by
    hand when the game is added and checked here against the installer;
  - the summary table at the top of the game's page under legacy/wiki (Symptom, Cause, Fix,
    Backend, CrossOver), unless the game's file says it otherwise;
  - process-features.json, the app's own table by executable: the graphics backend, the Game
    Porting Toolkit generation, and the one from which D3DMetal fixes the game by itself, so the
    fix is no longer needed there;
  - the excerpts, cut out of the source by the name of the function, so they follow the code.
    A permalink pins each one to the last commit that changed its file.

Standard library only: it runs with the macOS /usr/bin/python3, like build-app.sh.
SPDX-License-Identifier: GPL-3.0-or-later
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = os.path.join(ROOT, 'docs', 'fixes', 'games')
OUT = os.path.join(ROOT, 'docs', 'fixes', 'fixes.json')
FEATURES = os.path.join(ROOT, 'process-features.json')
REPO = 'https://github.com/MathiasKowoll/MacGameFix'
TABLE_KEYS = {'Symptom': 'symptom', 'Cause': 'cause', 'Fix': 'fix', 'Backend': 'backend', 'CrossOver': 'crossover'}
LANGUAGES = {'.c': 'c', '.h': 'c', '.sh': 'bash', '.py': 'python', '.pl': 'perl', '.hlsl': 'hlsl', '.recipes': 'text'}


def fail(message):
    sys.exit('export-fix-docs: ' + message)


def git(*args):
    return subprocess.run(['git', '-C', ROOT] + list(args), check=True, capture_output=True, text=True).stdout.strip()


def summary_table(page):
    """The two-column table at the top of a game's page, as {key: value}."""
    values = {}
    with open(os.path.join(ROOT, page), encoding='utf-8') as f:
        for line in f:
            if line.startswith('## '):
                break
            m = re.match(r'^\| ([A-Za-z]+) \| (.+) \|\s*$', line)
            if m and m.group(1) in TABLE_KEYS:
                values.setdefault(TABLE_KEYS[m.group(1)], m.group(2).strip())
    return values


def installer_line(installer, title):
    with open(os.path.join(ROOT, 'fixes', installer), encoding='utf-8') as f:
        text = f.read()
    for line in text.splitlines():
        if line.startswith('# MGVF-GAME:') and line.split(':', 1)[1].split('|')[0].strip() == title:
            return [p.strip() for p in line.split(':', 1)[1].split('|')]
    fail(f'{installer} has no MGVF-GAME line for "{title}"')


def cut(path, excerpt):
    """The lines of one function, from its definition to the closing brace in column 0."""
    with open(os.path.join(ROOT, source(path)), encoding='utf-8') as f:
        lines = f.read().split('\n')
    if 'symbol' in excerpt:
        name = re.escape(excerpt['symbol'])
        start = next((i for i, l in enumerate(lines)
                      if re.search(rf'\b{name}\s*\(', l) and not l.rstrip().endswith(';') and not l.startswith((' ', '\t'))), None)
        if start is None:
            fail(f'{path}: no definition of {excerpt["symbol"]}')
        end = next((i for i in range(start, len(lines)) if lines[i] == '}'), None)
    else:
        start = next((i for i, l in enumerate(lines) if re.search(excerpt['from'], l)), None)
        end = next((i for i in range(start or 0, len(lines)) if re.search(excerpt['to'], lines[i])), None) if start is not None else None
    if start is None or end is None:
        fail(f'{path}: the excerpt {excerpt} matches nothing')
    return start + 1, end + 1, '\n'.join(lines[start:end + 1])


def source(path):
    """The file's path in the repository; excerpts name it relative to fixes/."""
    return os.path.normpath(os.path.join('fixes', path))


def pinned(path):
    rel = source(path)
    if git('status', '--porcelain', '--', rel):
        fail(f'{rel} has uncommitted changes; a permalink to it would point at other code')
    return git('log', '-1', '--format=%H', '--', rel)


def process_features():
    with open(FEATURES, encoding='utf-8') as f:
        return json.load(f)['processes']


def game(file, features):
    with open(os.path.join(GAMES, file), encoding='utf-8') as f:
        d = json.load(f)
    parts = installer_line(d['installer'], d['title'])
    if (parts[1] if len(parts) > 1 else '') != (d.get('executable') or ''):
        fail(f'{file}: executable {d.get("executable")!r} differs from the installer\'s {parts[1]!r}')
    page = summary_table(d['page']) if d.get('page') else {}
    for key in TABLE_KEYS.values():
        d[key] = d.get(key) or page.get(key)
    if not d.get('symptom'):
        fail(f'{file}: no symptom, in the file or in its page\'s table')
    d['pageUrl'] = f'{REPO}/blob/main/{d["page"]}' if d.get('page') else None
    row = features.get(d.get('executable') or '', {})
    d['graphicsBackend'] = row.get('backend') or None
    d['gptk'] = row.get('gptk') or None
    d['notNeededFromGptk'] = row.get('not_needed_from_gptk') or None
    excerpts = []
    for e in d.get('excerpts', []):
        first, last, code = cut(e['file'], e)
        commit = pinned(e['file'])
        excerpts.append({
            'file': source(e['file']),
            'symbol': e.get('symbol'),
            'note': e['note'],
            'language': LANGUAGES.get(os.path.splitext(e['file'])[1], 'text'),
            'startLine': first,
            'endLine': last,
            'commit': commit,
            'url': f'{REPO}/blob/{commit}/{source(e["file"])}#L{first}-L{last}',
            'code': code,
        })
    d['excerpts'] = excerpts
    return d


def main():
    features = process_features()
    games = [game(f, features) for f in sorted(os.listdir(GAMES)) if f.endswith('.json')]
    text = json.dumps({'repository': REPO, 'games': games}, ensure_ascii=False, indent=2) + '\n'
    if '--check' in sys.argv:
        with open(OUT, encoding='utf-8') as f:
            if f.read() != text:
                fail('docs/fixes/fixes.json is out of date; run tools/export-fix-docs.py')
        print(f'docs/fixes/fixes.json is up to date ({len(games)} games)')
        return
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f'wrote docs/fixes/fixes.json: {len(games)} games, {sum(len(g["excerpts"]) for g in games)} excerpts')


main()
