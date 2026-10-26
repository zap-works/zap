# <img src="logo.svg" alt="" width="40" align="top"> Zap

Python's look, C's speed, Rust's memory management.

- **Made for agents.** Fewer tokens per program, errors that say how to fix them.
- **Efficient by design.** Lean native code, even on weak devices; recompiled and decompiled games
  prove it.
- **Built for data.** Parallel loops, vectors and tensors are the language itself, not C swept
  under the rug.
- **Safe with no ceremony.** Memory is checked at compile time with nothing written for it: no
  lifetimes, no annotations, no garbage collector.
- **CPU and GPU alike.** A shader is Zap, under the same types and rules; the engine
  (`engine/`) is built on it.
- **One tool, no setup.** `zap` builds, runs, tests, formats and documents. Straight from code to
  machine code, no LLVM in between: every optimization in reach.

```
type Pokemon:
	name str
	kind str
	level i64

team Pokemon[] = [
	("Zapdos", "electric", 53),
	("Moltres", "fire", 50),
	("Articuno", "ice", 50),
]

# on every core at once: the strong ones, strongest
# first, grouped by kind, and each kind's power
team
	.parallel()
	.filter(.level >= 50)
	.sortedBy(-.level, .name)
	.groupBy(.kind)
	.each((kind, ps):
		power = ps.map(.level * .level).sum()
		print("{kind:<9} {ps.map(.name)} power {power}")
	)

# memory checked when compiling, nothing written for it
leader = ref team[0]
team.push(("Mew", "psychic", 70))
# error: cannot change 'team' while 'leader' borrows it
print(leader.name)
```

## Numbers

The problems are inspired by [The Benchmarks Game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/).
One AI agent tuned every language's programs under the same rules: the languages are compared, not
their authors.

### Time and memory

Each Zap program against the best of C, C++ and Rust.

<img src="https://zap-works.github.io/charts/speed.svg" alt="Time and memory of each program against the best of C, C++ and Rust">

### Size of the code

How much code each language needs for the same programs, counted in words and symbols: Zap is 1.00x.

<img src="https://zap-works.github.io/charts/code.svg" alt="Tokens of each language against Zap's">

### Built with Zap

<!-- numbers:built -->
| Built with Zap | lines of Zap |
| :--- | ---: |
| [Mario 64](projects/mario) | 8,580 |
| [Skyrim](projects/skyrim) | 22,010 |
| [FireRed](projects/firered) | 3,575 |
| [Minecraft](projects/minecraft) | 2,446 |
| [Ragnarok](projects/ragnarok) | 4,467 |
| [Excel 1.00](projects/excel1) | 8,984 |
| [Skate 3](projects/skate3) | 3,369 |
| [Engine](engine) | 25,537 |
| [ZapX](projects/site) | 884 |
<!-- /numbers -->

<!-- numbers:compiler -->
| The compiler |  |
| :--- | ---: |
| lines of Zap | 76,841 |
| builds itself in | 6.1 s |
<!-- /numbers -->

## Build

From a clone, `<host>` being windows, linux or linux-arm64:

```
git archive --prefix=build/ origin/seed:<host> | tar -xf -
build/seed.exe build compiler/zap.zap   # -> build/zap.exe (build/zap on Linux)
zap run app.zap                         # compile and run
zap build app.zap                       # build/app.exe
zap test                                # every check
```

It runs on Windows and Linux, x64 and arm64, and builds for Android.

## Engine

A 2D, 2.5D and 3D engine written in Zap, over Vulkan or Direct3D 12, with sound, text, scenes and
shaders written in Zap too: [engine/](engine/README.md).

## Projects

Games and programs on the engine, one dir each under `projects/`, each with its README.md (what it
is and how to run it); what is left is its area of the board (board/). Nothing of the original games is in
the repository: each reads your own copy, and `.gitignore` keeps the dumps and what is taken from
them out of git.

| Project | What it is |
|---|---|
| [mario](projects/mario) | Super Mario 64 rewritten in Zap, frame for frame against the PC port |
| [skyrim](projects/skyrim) | Skyrim Special Edition rewritten in Zap, from your own install |
| [recomp](projects/recomp) | static recompilers: any SNES cartridge, Windows x64 functions, a phone's touch controls |
| [dkc](projects/dkc) | Donkey Kong Country on the SNES recompiler, frame-exact, with a widescreen |
| [lemmings](projects/lemmings) | DOS Lemmings, checked frame by frame against the DOS game |
| [pop](projects/pop) | Prince of Persia (DOS v1.4), SDLPoP's logic, checked against it |
| [firered](projects/firered) | Pokemon FireRed recompiled from your own cartridge dump |
| [excel1](projects/excel1) | Microsoft Excel 1.00 for the Mac on a Mac written in Zap |
| [skate3](projects/skate3) | Skate 3 (Xbox 360) rewritten in Zap, opening in University |
| [ragnarok](projects/ragnarok) | Ragnarok Online LATAM rebuilt in Zap, from your own install |
| [minecraft](projects/minecraft) | a world of blocks |
| [ai](projects/ai) | MNIST, a char transformer and TinyLlama on the GPU, against PyTorch and llama.cpp |
| [lab](projects/lab) | the engine's graphics lab, a scene per key |
| [examples](projects/examples) | the engine's features checked, one dir each |
| [dos](projects/dos) | what the DOS games share: file readers, the OPL3 |
| [zaplink](projects/zaplink) | the user's terminal sessions reached from a phone |
| [site](projects/site), [webgen](projects/webgen) | the language's site and its generator |

## Experimental

A personal project, not fit for production: the language changes often and its history is
rewritten at will. Copy it, change it, make dialects of it.

## License

MIT.
