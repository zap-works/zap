# Working in this repository

The Zap language: the compiler (`compiler/`: zap.zap's `parts` name its slices, a dir each), the
runtime (`runtime/`), the standard library (`std/`), tools and tests; the engine (`engine/`, and
`rhi/`, one GPU API over Vulkan and Direct3D 12) and the programs on it (`projects/`, one dir each;
`projects/examples/` check an engine feature on either backend). `spec/` is the one spec, one
`.zap` file a section whose prose is its comments and whose rules are its tests (`zap test spec`
runs it); `TODO.md` is the plan.

## DRY: the rule above every other

Every piece of knowledge lives in exactly one place: a rule, a computation, a table, a type, a
constant, a message, a fact in the docs. This is never traded away for speed of writing.

- Before writing anything, find the place that already has it (`zap doc find`, a search of the
  repository's sources) and extend that place instead of writing a second one.
- Two pieces of code that do or decide the same thing are a defect: the change that sees them
  folds them into one (a shared function, a parameter, a table) and moves every caller to it. A
  near copy is a copy.
- The right home is the most general one that needs it: two projects' code goes to the engine;
  the engine's and a program's, when not about games, to std or the runtime; what the CPU and the GPU,
  or the compiler and a tool, both decide is decided once and read by both.
- The docs say each thing once: `spec/` states the language, other docs point to it.
- `zap test` guards it: `baselines/dups.baseline` only shrinks, and a new copy fails the check.
- A file has at most 1,000 lines and a function body at most 100: split by what the code does (a
  file of a folder stays in the folder's module). `zap test` guards it (`limits`); a table, or a
  dispatch of one line per arm, carries a `# long: why` comment at the top of the file or above
  the function.

## Docs: two names

Every document is a `README.md` or a `TODO.md`, nothing else. A README.md says what is true now
(what a thing is, how to run it, its layout, what runs and what it measures) and only changes
when the code does; a TODO.md says what is left, numbered in the order it is done, a step
deleted when it lands, never marked done, no dates. The rule for a line: if it stops being true
once the work is done, it is TODO. The root's TODO.md holds the language's, the runtime's, the
std's, the engine's and the tools' steps, what a project asks of them included; a project's own
steps are in projects/<name>/TODO.md, and a bug of the language met there goes to the root with
its workaround. Each dir under projects/ has a README.md; a TODO.md only while something is
left. Reference material a program reads or an agent greps (skyrim's exe tables) is one
README.md in its dir, sections by theme. CLAUDE.md and AGENTS.md are the tools' entry names, not
documents.

## Before writing a helper

- Ask `build/zap.exe doc find <words>` whether the runtime, std, the engine or the spec already
  has it (`zap doc` lists the modules, `zap doc <module>` one module's declarations, `zap doc 6.5` or
  `zap doc loops` a section of the spec).
- An empty answer means it is missing. Add it where it belongs, never as a private copy: a method
  of a built-in type or basic I/O goes to the runtime, anything a program imports by name goes to
  `std/<module>`.
- A public declaration whose name and signature do not say what it does gets a short comment
  above it (`zap doc` shows it; `zap test --only doc` lists the declarations without one).

## Checks

One command checks: `build/zap.exe test` (spec 13.1, its options `zap doc commands`); nothing
else is a check. A fresh clone's first build is the host's seed's (spec 14.1); then the compiler
is built like any program (`build/zap.exe build compiler/zap.zap`), and every change goes edit,
build, test, promote when the test asks, commit, push (spec 14.1).

- `build/zap.exe test <files | folders> [name text]` while working: what was touched (seconds).
  Every verification is a test block: the suite under `tests/` and `std/`, the fuzzers
  (`tests/fuzz/`, a long hunt is the same file run with a seed and a count), and each benchmark's
  check that its C, Rust and Python programs print the same bytes (`tests/benchmarks/problems`,
  the oracle of the compiler).
- `build/zap.exe test <paths>` before a commit, once per batch, on what the batch touched: the
  language's core (`compiler runtime std spec tests`, `--only build,dups,limits,check,tests`) for a
  change under compiler/, runtime/ or std/; `engine` for one under engine/ or rhi/;
  `projects/<name>` for a project. `zap branch land` runs the same for what the merge changed
  (spec 13.1.5): a project is tested only when it changed, and the rest of the repository may
  stay broken until the full run.
- `build/zap.exe test` at the root is the full run: once a day or after a large batch, with the
  agents idle and nothing else heavy running; each project it finds broken becomes a branch of
  its own, landed like any other. A plain run leaves out `fmt` (`--full` or `--only fmt` runs
  it), `doc` and the measures. Performance work starts from `ZAP_RUN=next zap test --only bench` and ends
  with `--full` before the seeds are promoted. The bench measures on this machine (spec 13.1; a
  remote one only when arm64 in ZAP_SETUP names it). A change is measured with
  `ZAP_RUN=ab=build/base/zap.exe zap test --only bench --full <name>`: the compiler from before it
  (and, for a change of the runtime or std, their copies in build/runtime and build/std, which a zap
  in build/base reads) against this one, run in turns and compared by the processor's counts, so
  A/Bs may run side by side; `fresh` in ZAP_RUN measures Zap's programs again, `fresh=all` every
  language's.

Linux and Android: `build/zap.exe test --target <name> <files>` builds on Windows and runs where
the target runs (spec 13.1). Here: no arm64 machine is used (arm64 unset in ZAP_SETUP, its tests
skipped); Android's the emulator `zap37` (the SDK in %LOCALAPPDATA%\Android\Sdk,
started with `emulator -avd zap37 -no-window`), never the user's phone. A module's `linux/` dir
takes the place of its declarations of the same name there (target.zap); its system calls are
named (`extern "syscall write"`), their numbers in compiler/targets/syscalls.zap.

A branch begins with `build/zap.exe branch new <name>` in main's checkout (spec 13.1.5): the
branch from main, checked out at `<main's checkout>-wt-<name>` with a compiler, main's
build/zap.exe when the compiler's sources are main's, else the seed's build. It goes into main by
`build/zap.exe branch land <name>...`, never by a merge by hand: `zap test` run on what the merge
changes (the language's core, engine/, rhi/, projects/<name>; not .md or LICENSE, spec 13.1.5)
in a land checkout beside main's (one per land running, so lands never wait for each other's
suite), main moved only when it passes, and then the branch and its worktree (when clean) removed.
`build/zap.exe branch status` lists the branches beside main's checkout (in main or not, ahead and
behind, uncommitted changes) and the lands running. The push stays by hand.

Diagnostics are not checks: `ZAP_RUN`'s words (`zap doc environment`), and `tools/golden.zap`,
which compares the code a refactor generates with a `build/base.exe` kept before it: alone it
builds the compiler with both (a minute); a dir is only for what the compiler's code does not use.

## The engine and the projects

- What the projects need from a game engine goes to `engine/`, written once for all of them; a
  variable of the environment it reads is declared where it is read (`EnvVariable`, spec 13.2).
  Within a project, one copy: a second use moves the code to a function both call. A project's
  code is not an API, so it needs no comment over every function.
- `engine/tests/examples.zap` runs the examples that check themselves (`indirect`, `compressed`,
  `compute`, `post`, `targets`, `staged`) on both backends (`gpu=vulkan`, `gpu=d3d12` in ZAP_RUN). The
  engine's diagnostics are `ZAP_RUN` words (`gpuinfo`, `gputime`, `draws`).
- A change to what a project draws is checked by `zap test --only shots <project>`: the scripted
  runs of each entry file's header (`zap run ... --step 16 --shot x.png`, `--step` making the
  frames last the same every time) drawn on `vulkan` and `d3d12`, each picture compared with the
  run before (`--update` keeps a changed one when the change is meant). Scripted runs (`--frames`,
  `--shot`, `--replay`, `--bench`, or `headless` in ZAP_RUN) are headless: no window, the frames drawn
  offscreen, the real mouse and keyboard never read, the same pictures as windowed. A header
  line `needs: path` names the user's own game files a run reads; without them the run is skipped
  with a line saying so. `zap test --only size` measures each app's build, and `zap test --only
  bench projects/mario` the rewrite against the PC port. minecraft's scripted run fails when
  memory grows while its frames run.
- The decompilation and recompilation projects share their tools in `projects/recomp/tools/`:
  `decompinfo.zap` prints a function of a Ghidra export laid out as ExportAll.java writes it
  (index.tsv, names.tsv, calls.tsv, strings.tsv, functions/), found by address or name, with its
  community name, callers, callees, the strings it reads and its text (`--dir`, SkyrimSE.exe's in
  C:/tools/skyrim-decomp by default).
- Every test, measurement and capture runs headless unless the user asks otherwise: no window
  on the user's screen, no keys or clicks sent to any program (`SendInput`, focus changes), no
  real game or tool driven through its window. What needs a running game is read from what is
  already captured, from the game's files, or from its executable's export.
- Before reverse engineering, recompiling or decompiling anything, search what the community has
  already done: mods and their sources, GitHub, Reddit, X, modding wikis and Discord archives, SDKs
  and headers, address libraries and symbol databases. Reuse what exists before reinventing it.
- Never commit anything of the games: the ROM, the Ragnarok Online install, the Skate 3 disc, or
  what is extracted or prepared from them (`.gitignore` keeps them out; check `git status`).

## Rules

- Versioned code is Zap. Code in another language is never committed, except what is written to
  compare against (the benchmarks' C, Rust and Python programs) and what a foreign program runs
  inside itself (an emulator's Lua script). A tool is written in Zap; a script in another language
  is throwaway, run once and left out of the repository.
- The compiler's sources use only what the seeds accept (spec 14.1): a feature lands first, the
  seeds are promoted (`zap build --seeds`, by the user; agents never promote), then the compiler
  uses it.
- A change of syntax ships with its migration in the same change: a rewrite of `zap fmt`
  (`compiler/tools/fmt/rewrite.zap`) where the rewrite is one, run over the repository (`zap fmt .`),
  else an idempotent script.
- The tables (the words, the operators, the refused forms, the commands, the environment) are the
  compiler's declarations, printed by `zap doc <table>`: a doc points to them, never copies them.
- Code, comments and docs in English; no emoji. Comments are short and say what the code cannot:
  why, or what a public declaration is for. Never repeat what the code already reads as.
- The language is a scratchbook: each version is written as if it had started that way, and what
  goes is gone as if it never existed: syntax, behaviour, std, commands, options, environment
  words, and the compiler's code that handled them. No hint, no error of its own, no fmt rewrite
  of it, no test of it; writing it gives the ordinary error. Old code is migrated once, when the
  change lands (a fmt rewrite or a script over the repository), then the migration is
  deleted.
- Commit messages are one line.
- No new environment variable. A new setting is a word of ZAP_SETUP (the machine's, set once) or
  of ZAP_RUN (one run's), or an option of the program that needs it.
- Nothing personal is versioned: a host, a device, a person's paths or accounts are named only by
  the word of ZAP_SETUP that points to them (`arm64`, `android`; `zap doc environment` lists them),
  never by their real name; commits are the repository's author (.gitconfig).

## Tokens

- Read slices, not whole files: `grep -n` to find the place, then the lines around it
  (`checkexpr.zap` alone is over 7,000 lines).
- Filter a command's output to what decides: `| tail -3` for a pass, `| grep -E "FAIL|error"`
  for what broke; never a whole suite's log.
- Merge main into a branch when a landed group touched the same files, not on every land.
- A final report is at most 15 lines: what landed, the commits, blockers.
- The coordinator picks the model by the work: Sonnet at low effort for mechanical work (renames,
  migrations, small bugs), Opus for design (ownership, register allocation); groups that touch
  the same files run one after the other, not side by side.
- Each leading session (the language and its tooling, Skyrim, the retro games) runs at most 3
  agents at once, Sonnet for simple work and Opus for complex work; each agent's tests run one
  file at a time, since the machine's memory is shared.
- At most two agents of all sessions change the compiler at once, since each change rebuilds it
  (twice, for the fixed point); the others work in the runtime, std, engine or projects, or
  measure. An agent starts from `zap branch new`, which takes main's compiler, never from the seed.
- Work that only tests or measures on Linux runs on the arm64 host, not here.
- Commands an agent runs never need the user's approval: no `rm` with wildcards (a new scratch
  dir a run instead), one action a command.
