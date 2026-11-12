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
    def run(mode,ok=True,chain_in_ntdll=False):
        r=subprocess.run(['/usr/bin/perl',str(helper),mode,str(pfx)],env=dict(os.environ,HOME=str(root),MGF_FH6_CHAIN_IN_NTDLL='1' if chain_in_ntdll else '0'),text=True,capture_output=True)
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
    # 0025's ntdll: only the plugin switch is needed; what MacGameFix wrote is taken out again,
    # only with the exact value it wrote, and everything else stays where it was.
    (pfx/'.mgf-fh6-launch-options.json').unlink(missing_ok=True)
    cfg.write_text(vdf('D3DM_MAX_FPS=48 NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_CHAIN=1 NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0 NOTPROTON_ENV_WINE_SOFTWARE_BRIDGE_RESUME=0 NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=1 NOTPROTON_ROSETTA_TRAP_BOOST=1 MTL_HUD_ENABLED=1 %command% --arg'))
    old_text=cfg.read_text()
    run('status',chain_in_ntdll=True)  # the switch is there: installed, nothing removed by status
    assert cfg.read_text()==old_text
    run('install',chain_in_ntdll=True);t=cfg.read_text()
    assert '"LaunchOptions" "D3DM_MAX_FPS=48 NOTPROTON_ROSETTA_TRAP_BOOST=1 MTL_HUD_ENABLED=1 %command% --arg"' in t,t
    run('install',chain_in_ntdll=True);assert cfg.read_text()==t
    run('restore',chain_in_ntdll=True);assert cfg.read_text()==old_text
    # A value MacGameFix did not write is the user's: kept.
    cfg.write_text(vdf('NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=1 NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=0 %command%'))
    run('status',False,chain_in_ntdll=True)
    run('install',chain_in_ntdll=True)
    assert '"LaunchOptions" "NOTPROTON_ROSETTA_TRAP_BOOST=1 NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=1 NOTPROTON_ENV_WINE_SOFTWARE_ALU_BRIDGE=0 %command%"' in cfg.read_text(),cfg.read_text()
    run('diagnostics-off',chain_in_ntdll=True);assert 'NOTPROTON_ENV_WINE_SOFTWARE_EXCEPTION_STATS=0' in cfg.read_text()
    print('PASS: status is read-only; Steam refusal; quoted options; unrelated apps; idempotence; diagnostics; exact restore; baseline preservation; wrapper refusal; absent field insertion; chain in ntdll: plugin switch only, our variables removed exactly, user values kept')
