# 14. Repository and implementation
#
# This repository, github.com/zap-works/zap, holds the language, the engine and the programs built
# on it.
#
# 14.1 Layout and build
#
# Where each part of the language lives:
#
# - `compiler/zap.zap`, `compiler/`: the compiler: lexer, parser, checker, ownership check
#   on the intermediate form (`irown.zap`), layouts, derived functions (`derive.zap`), the intermediate form and its x64 code
#   (`ir*.zap`), a shader's code in the same form and its SPIR-V and HLSL (`irgpu.zap`,
#   `irspirv.zap`, `irhlsl.zap`), the PE writer, the formatter, the language server.
# - `compiler/targets/`: the code of x64 and arm64, the ELF writer (an executable, or an Android
#   app's shared object), where the tests of another target run (`run.zap`), and an Android app
#   (`android/`: its entry, its manifest, its APK and signature, its run over adb).
# - `compiler/fold/`: constant arithmetic, one for the CPU's compiler and the GPU's.
# - `compiler/shader/`: a shader program's layout (its parameters, bindings and inputs), its
#   packers, SPIR-V's module and its check, DXC.
# - `runtime/`: the runtime (module `rt`): memory, strings, lists, maps, numbers, I/O, formatting,
#   encoding, threads, pools, tests, a system's own parts (`system/linux/`, an Android app's in
#   `system/linux/app/`); read from disk with every program, so a change takes effect at the next
#   compile.
# - `std/`: the standard library: `fs`, `net`, `json`, `image`, `deflate`, `math`,
#   `compare`, `win`, `gpu`, `tensor`, `zapx`; the compiler imports it too.
# - the branch `seed`: the seeds, the compiler built for each target (below).
# - `spec/`: the spec, one file a section (a chapter's opening in its first section's), its prose
#   in comments and its rules as tests.
# - `tests/<area>/`: the suite (basics, numbers, text, containers, memory, generics, vectors, io,
#   programs, errors, shader, fuzz, benchmarks, ir), data files beside the tests.
# - `tools/`: the tools of the repository and `vscode-zap/`.
# - `engine/` and `rhi/`: the engine and its GPU API over Vulkan and Direct3D 12, libraries beside
#   std that any program imports (8, *Modules and dependencies*).
# - `projects/`: the programs on the engine, one dir each, run from the root (`zap run
#   projects/mario/main.zap`); `projects/examples/` check an engine feature on either backend.
#
# main holds no binary. The seeds, the compiler built for each host (windows, linux, linux-arm64;
# Android is a target, not a host), are the files of the one commit of the orphan branch `seed`, a
# dir a host holding its `seed.exe`. A fresh clone's first build, at the repository's root:
#
#     git archive --prefix=build/ origin/seed:<host> | tar -xf -
#     build/seed.exe build compiler/zap.zap
#
# the same two lines in sh, Git Bash and PowerShell (7.4 on), which write `build/seed.exe`
# (runnable, by that name on every system) and then `build/zap.exe` (`build/zap` on Linux). From
# then on the compiler is built like any program, `build/zap.exe build compiler/zap.zap`: `zap
# build` sets the running executable it writes over aside. An executable names its sources from
# the repository's root (or the runtime's, or the working dir), so a build is the same bytes from
# any checkout on any host.
#
# The cycle is the same for any change: edit, build, `zap test` (13.1), promote when it asks,
# commit, push. Its fixed point takes the host's seed from the newest of `seed` (a promotion not
# pushed yet) and `origin/seed`, and in `build/fixedpoint/` the seed builds zap1 from the sources
# (`build/zap.exe` is zap1 when its stamp says the seed built it from these sources), and zap1
# builds zap2; `--full` goes on, zap2 builds zap3, and zap2 is zap3 byte for byte. It runs again
# only when the seed or compiler/, runtime/ or std/ changed since it held, a plain run not
# standing for a full one. It never touches `build/zap.exe`.
#
# The compiler's sources use only what the seeds understand. The seeds change only when the sources
# need what they lack (a language feature the compiler or the std modules it imports start to use,
# a runtime function their sources call): the fixed point's first build fails and says to promote.
# The feature lands first, unused; `zap build --seeds` builds every host's compiler from the
# sources twice, by this zap and then by the host's first build, each a fixed point, cross-built
# from any host, and makes the branch `seed` again, one orphan commit, which is pushed with main
# (`git push -f origin seed`); the use follows. A change to the runtime or the backend alone never
# needs new seeds.
# A new method of a list, string or map is one runtime function named after it, receiver first
# (`pub fn listSorted<T Ord>(xs T[]) T[]` is `xs.sorted()`); its signature and bounds are the
# method's. The checker and backend keep rules only for methods compiled in line (`len`, `push`,
# `pop`, `get`, `m[k] = v`, a part `s[a..b]`, ...). A type's own function (`str.fromCode`,
# `i64.parse`) is the runtime function named after the type the same way; given a list as its
# first argument, it is the one whose name ends in `List` when the runtime has it
# (`Process.output(["git", "log"])` is `processOutputList`, `Process.output("git log")`
# `processOutput`).

test "a method is the runtime function named after it":
	xs = [3, 1, 2]
	expect xs.sorted() == listSorted(xs)
	expect str.fromCode(65) == strFromCode(65)
	expect i64.parse("42") == i64Parse("42")
	words = ["git", "--version"]
	expect Process.output(words).out == processOutputList(words).out
	expect Process.output("git --version").out == processOutput("git --version").out
