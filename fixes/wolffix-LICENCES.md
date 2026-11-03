# The Wolf Among Us Remastered fix: licence and binary

`d3d11-wolf.dll` is macprotips' `d3d11.dll` from
[WolfAmongUsFix](https://github.com/macprotips/WolfAmongUsFix) 1.0 (commit
`0518257`, `prebuilt/d3d11.dll`), shipped as published. Its source is beside it:
`wolffix.c`, `wolffix_core.c`, `wolffix_core.h` and `wolffix.def`, unchanged.

| File | sha256 |
| --- | --- |
| `d3d11-wolf.dll` | 1abce312259523d7a14ccac911a564aeda2ff596829b01a054bd886371a6a21b |

To build it from the source, as WolfAmongUsFix's `build.sh` does (needs
`brew install mingw-w64`):

    x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type \
      -Wno-missing-field-initializers -shared -static-libgcc -s -Wl,--no-insert-timestamp \
      -o d3d11-wolf.dll wolffix.c wolffix_core.c wolffix.def -ldxguid

Here, with GCC 16.2.0, that gave the published bytes once, in WolfAmongUsFix's own
checkout, and different bytes on the next runs: two builds in a row differed in
77 bytes, all in the PE header's checksum and in a few call displacements. So the
published build is the one shipped, and `fixes/check-builds.sh` checks it against
the sha256 above, as it does the other binaries this repository does not build.

The source and the DLL are in the public domain:

```
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org/>

---

Scope: everything in this folder: the d3d12.dll shim, the Mac app, the tests and the
vendor reports. No files from the game are included. The fix's two shaders are built on
each user's Mac from their own copy of the game (app/Sources/CShaderFix does the rewrite).
The Mac app also bundles Microsoft's DirectX Shader Compiler tools, which keep their own
license; the app includes it under Contents/Resources/Licenses.
```
