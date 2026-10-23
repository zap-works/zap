# Super Mario 64 rewritten in Zap

Super Mario 64 rewritten in Zap on the engine, frame for frame against the PC port. It needs your
own Super Mario 64 (USA) cartridge dump at `projects/mario/rom/sm64.us.z64`, never committed, nor
anything taken from it; `zap run projects/mario/main.zap` plays.

## The bench against the PC port

`suite.zap` measures this rewrite (`mario/`) against **sm64ex**, the native C port of the
decompiled game (OpenGL 2.1 through SDL2), built from the same ROM with a small harness
(`port/bench.c`). Both sides start in Castle Grounds, look through the same fixed camera at the
same scene with Mario standing, draw one game tick and one frame per frame with no frame limiter
and no vsync, and measure after a 60-frame warm-up:

- the time of N frames (fps, milliseconds a frame),
- the processor time and cycles the process spent in them (all threads: the port mixes its audio on another),
- the peak working set and the private bytes.

The PC port is built in `projects/mario/bench/pc/`, ignored by git, from its own source and the user's own
ROM; nothing of it, and nothing taken from the ROM, is committed here.

### Building the port (Windows, MinGW-w64 GCC, no MSYS2)

From `projects/mario/bench/pc/` (created with `mkdir`):

```sh
git clone --depth 1 https://github.com/sm64pc/sm64ex.git
mkdir deps && cd deps
curl -LO https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-devel-2.32.10-mingw.tar.gz
curl -LO https://github.com/nigels-com/glew/releases/download/glew-2.2.0/glew-2.2.0.tgz
tar xzf SDL2-devel-2.32.10-mingw.tar.gz && tar xzf glew-2.2.0.tgz
mkdir prefix && cp -r SDL2-2.32.10/x86_64-w64-mingw32/* prefix/
sed -i "s|^prefix=.*|prefix=$(cd prefix && pwd -W)|" prefix/bin/sdl2-config
(cd glew-2.2.0 && gcc -O2 -DGLEW_STATIC -Iinclude -c src/glew.c -o glew.o && ar rcs ../prefix/lib/libglew32.a glew.o && cp -r include/GL ../prefix/include/)
# shims: make, cc, python3 and hexdump as the build calls them (hexdump: a Zap program)
mkdir shim && cp "$(which mingw32-make)" shim/make.exe
printf '#!/bin/sh\nexec gcc "$@"\n' > shim/cc
printf '#!/bin/sh\nexec python "$@"\n' > shim/python3
chmod +x shim/*
../../../../../build/zap.exe build ../../port/hexdump.zap && cp build/hexdump.exe shim/
cd ..
../../../../build/zap.exe run ../port/hooks.zap sm64ex
cp ../../rom/sm64.us.z64 sm64ex/baserom.us.z64
cd sm64ex
PATH="$PWD/../deps/shim:$PWD/../deps/prefix/bin:$PATH" mingw32-make -j8 VERSION=us RENDER_API=GL WINDOW_API=SDL2 CC=gcc CXX=g++
cp ../deps/prefix/bin/SDL2.dll build/us_pc/
```

Set the port's window to 1280 x 960 in `%APPDATA%/sm64ex/sm64config.txt` (`window_w`,
`window_h`), the size the rewrite opens.

### Running

```sh
zap test --only bench projects/mario/bench/suite.zap          # 300 frames, one run
zap test --only bench --full projects/mario/bench/suite.zap   # 2000 frames, five runs
```

Each case (`mario-1x`, `mario-4x`: the rewrite without and with 4x multisampling) is the
processor cycles a frame of the rewrite over the port's, the median of the runs; `bench.baseline`
keeps the ratios. Without the cartridge dump or the port built the suite says so and measures
nothing. `zap test projects/mario/bench/trace.zap` sets the rewrite's ticks beside the port's
(`BENCH_TRACE`) under the same conditions.

### The two backends

`zap test --only shots projects/mario/main.zap` draws the static capture (with and without 4x
multisampling) and a walk with the RHI's Vulkan and Direct3D 12 backends (`ZAP_RUN=gpu=d3d12`), each
picture compared with the run before. The shaders' DXIL is made when the game is built, by DXC
from Microsoft's release (`build/deps/dxc/dxc.exe` with its two DLLs, outside git; see `the
language's spec/`, Shaders).
