# NotProton plugins MacGameFix carries

Four of MacGameFix's fixes, ported to NotProton's plugins by NotProton's creator
(NotProtonNot), in the commit "MacGameFix plugins" (4912693, 2026-11-22) on top of
NotProton's `plugin-pt3` branch. That commit is not in a NotProton release yet, so
MacGameFix carries them until NotProton does. `NotProtonPlugins.swift` keeps them in
NotProton's plugins folder; `build-app.sh` builds the libraries.

| Here | NotProton, at 4912693 |
|---|---|
| `notproton_plugin.h` | `plugin-host/notproton_plugin.h` (the same as `plugin-pt3`) |
| `plugins/d3dmetal-freeze.c` | `plugin-host/plugins/d3dmetal-freeze.c` |
| `plugins/d3dmetal-notifier.c` | `plugin-host/plugins/d3dmetal-notifier.c` |
| `plugins/tcp-noopt.c` | `plugin-host/plugins/tcp-noopt.c` |
| rows in `NotProtonPlugins.swift` | `examples/plugins/40-unreal-video.conf`, `50-d3dmetal-freeze.conf`, `55-d3dmetal-notifier.conf`, `60-red-dead-online.conf` |

The sources are as they are there. Built with `build-app.sh`'s flags, which are
NotProton's Makefile's, each library has the same code as NotProton's own build (checked
with `otool -t` on 2026-11-23). The rows keep NotProton's ids, file names and fields,
with a description and a group (from a NotProton that reads `group`) added.

NotProton's unit tests for the three libraries (`plugin-host/tests/`) are not copied:
they build against NotProton's plugin host, and they stay there.

NotProton is GPL-3.0, as MacGameFix is.
