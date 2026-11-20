#!/usr/bin/env python3
"""steam-launch-options.pl against disposable Steam settings; the Steam check reads a file."""
import os, pathlib, subprocess, tempfile, json
source = pathlib.Path(__file__).with_name('steam-launch-options.pl').read_text()
APP = '4115450'
with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td); journal = root / 'journal.json'
    cfg = root / 'Library/Application Support/Steam/userdata/123/config/localconfig.vdf'; cfg.parent.mkdir(parents=True)
    ps = root / 'processes'; ps.write_text(''); helper = root / 'options.pl'
    helper.write_text(source.replace('/bin/ps -axo comm=', f'/bin/cat {ps}'))

    def vdf(options, field=True):
        lo = ' "LaunchOptions" ' + json.dumps(options) if field else ''
        return ('// kept comment\n"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "' + APP + '" {'
                + lo + ' "Other" "{literal}" } "999" { "LaunchOptions" "KEEP=1 %command%" } } } } } }\n')

    def run(mode, *pairs, ok=True):
        pairs = pairs or ('NOTPROTON_ROSETTA_PIPELINE_CACHE=1',)
        r = subprocess.run(['/usr/bin/perl', str(helper), mode, APP, str(journal), *pairs],
                           env=dict(os.environ, HOME=str(root)), text=True, capture_output=True)
        assert (r.returncode == 0) == ok, (mode, r.stdout, r.stderr)
        return r

    def opts():
        t = cfg.read_text(); i = t.index('"' + APP + '"'); j = t.index('"999"', i)
        return t[i:j]

    # The user's own options are kept as they are, the variable goes in front.
    original = vdf('MGF_FANS=max D3DM_SUPPORT_DXR=0  PERSONAL="a b" %command% --arg "keep me"'); cfg.write_text(original)
    run('status', ok=False); assert cfg.read_text() == original
    ps.write_text('/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx\n')
    run('preflight', ok=False); run('install', ok=False); assert cfg.read_text() == original
    ps.write_text('')
    run('install'); installed = cfg.read_text(); run('status')
    assert 'NOTPROTON_ROSETTA_PIPELINE_CACHE=1 MGF_FANS=max D3DM_SUPPORT_DXR=0  PERSONAL=\\"a b\\" %command% --arg \\"keep me\\"' in opts(), opts()
    assert '"999" { "LaunchOptions" "KEEP=1 %command%" }' in installed and installed.startswith('// kept comment')
    run('install'); assert cfg.read_text() == installed  # twice is once
    ps.write_text('/Applications/Steam.app/Contents/MacOS/steam\n'); run('install')  # nothing to write: Steam may run
    run('status'); ps.write_text('')
    run('restore'); assert cfg.read_text() == original and not journal.exists()

    # A value the user had is given back; one they set themselves is theirs.
    cfg.write_text(vdf('NOTPROTON_ROSETTA_PIPELINE_CACHE=0 %command%')); before = cfg.read_text()
    run('install'); assert '"NOTPROTON_ROSETTA_PIPELINE_CACHE=1 %command%"' in opts(), opts()
    run('restore'); assert cfg.read_text() == before
    cfg.write_text(vdf('NOTPROTON_ROSETTA_PIPELINE_CACHE=1 X=2 %command%')); before = cfg.read_text()
    run('install'); assert cfg.read_text() == before and not journal.exists()
    run('restore'); assert cfg.read_text() == before

    # Changed by the user after the install: left alone by restore.
    cfg.write_text(vdf('X=2 %command%')); run('install')
    cfg.write_text(cfg.read_text().replace('NOTPROTON_ROSETTA_PIPELINE_CACHE=1', 'NOTPROTON_ROSETTA_PIPELINE_CACHE=7'))
    changed = cfg.read_text(); run('restore'); assert cfg.read_text() == changed

    # No options, and no field at all: both come back as they were.
    journal.unlink(missing_ok=True)
    cfg.write_text(vdf('')); before = cfg.read_text()
    run('install'); assert '"NOTPROTON_ROSETTA_PIPELINE_CACHE=1 %command%"' in opts(), opts()
    run('restore'); assert '"LaunchOptions" ""' in opts(), opts()
    cfg.write_text(vdf('', field=False))
    run('install'); assert '"LaunchOptions" "NOTPROTON_ROSETTA_PIPELINE_CACHE=1 %command%"' in opts(), opts(); run('status')
    run('restore')

    # Refused: a wrapper, and a game Steam has never started.
    cfg.write_text(vdf('wrapper %command%')); before = cfg.read_text()
    run('install', ok=False); assert cfg.read_text() == before
    cfg.write_text(vdf('A=1 %command%').replace('"' + APP + '"', '"1"'))
    run('install', ok=False); run('status', ok=False)
    run('install', 'BAD', ok=False)
    print('PASS: status reads only; Steam refusal only when writing; quoting kept; other apps untouched; '
          'idempotent; exact restore; earlier value given back; user values kept; empty and absent field; '
          'wrapper and unknown game refused')
