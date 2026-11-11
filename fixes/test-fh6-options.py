#!/usr/bin/env python3
"""Lossless FH6 settings tests; all files and process discovery are disposable."""
import os, pathlib, subprocess, tempfile, json
source = pathlib.Path(__file__).with_name('fh6-launch-options.pl').read_text()
with tempfile.TemporaryDirectory() as td:
    root=pathlib.Path(td); pfx=root/'pfx';pfx.mkdir()
    cfg=root/'Library/Application Support/Steam/userdata/123/config/localconfig.vdf';cfg.parent.mkdir(parents=True)
    ps=root/'processes';ps.write_text('');helper=root/'options.pl'
    helper.write_text(source.replace('/bin/ps -axo comm=',f'/bin/cat {ps}'))
    def vdf(options):
        encoded=json.dumps(options)
        return '// retained comment\n"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "2483190" { "LaunchOptions" '+encoded+' "Other" "{literal}" } "999" { "LaunchOptions" "KEEP=1 %command%" } } } } } }\n'
    def run(mode,ok=True):
        r=subprocess.run(['/usr/bin/perl',str(helper),mode,str(pfx)],env=dict(os.environ,HOME=str(root)),text=True,capture_output=True)
        assert (r.returncode==0)==ok,(mode,r.stdout,r.stderr)
        return r
    original=vdf('PERSONAL="a b" %command% --argument "keep me"');cfg.write_text(original)
    run('status',False)
    ps.write_text('/Applications/Steam.app/Contents/MacOS/steam\n')
    run('preflight',False);run('install',False);assert cfg.read_text()==original
    ps.write_text('');run('preflight');assert cfg.read_text()==original
    run('install');installed=cfg.read_text();run('status');run('install');assert cfg.read_text()==installed
    assert 'NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0' in installed
    assert 'MTL_HUD_ENABLED' not in installed and 'PERSONAL=\\"a b\\"' in installed
    assert '"999" { "LaunchOptions" "KEEP=1 %command%" }' in installed
    run('diagnostics-on');assert 'MTL_HUD_LOG_ENABLED=1' in cfg.read_text()
    run('diagnostics-off');assert 'MTL_HUD_LOG_ENABLED=0' in cfg.read_text()
    run('restore');assert cfg.read_text()==original
    cfg.write_text(vdf('CUSTOM=1 NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1 NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0 NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1 NOTPROTON_ROSETTA_TRAP_BOOST=1 NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=1 MTL_HUD_ENABLED=1 %command%'))
    before=cfg.read_text();run('install');assert cfg.read_text()==before # retained baseline untouched
    cfg.write_text(vdf('wrapper %command%'));before=cfg.read_text();run('install',False);assert cfg.read_text()==before
    cfg.write_text(vdf('KEY=1 %command%').replace('"LaunchOptions" "KEY=1 %command%"',''))
    run('install');run('status')
    print('PASS: status is read-only; Steam refusal; quoted options; unrelated apps; idempotence; diagnostics; exact restore; baseline preservation; wrapper refusal; absent field insertion')
