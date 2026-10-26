---
size: S
priority: P0
branch: compiler-11
by: 7e0af12c-313f-49ba-a964-a23c7bc1b530
---
# The load's rest on the main thread

The parse hardly waits now (skyrim cold: 0.1 s of a 4 s load); what is left of the step:

- [ ] appending each arena to the program's (0.2 s of skyrim's cold load) is the main thread's;
  reading each file and naming its cache entry on the jobs instead (the ask holding the path, the
  time noted first) was tried and saved nothing measurable over noise (cold loads of the
  compiler and skyrim within 10%), so reverted
- [ ] a module's imports are parsed after it, not beside it: their files could be asked for when
  it is parsed
- [x] the shaders' link walked every declaration once per question (moduleOfFile, gpuFilesOf,
  hasGpuFunction, rangeAliasOf, gpuUnit): one walk now indexes the GPU files' declarations
  (gpu.zap's GpuDecls), skyrim's warm load 1.23-1.29 G cycles to 1.02, the same executable
- [ ] the load's rest on skyrim, warm, main thread (1.17 G cycles, now 0.93): keepFrom 0.42 G (the
  kept stages decoded: compiler-17), its own modules 0.29 G, the shaders' link 0.15 G, stageChain
  0.10 G (its files' hashes kept stamped by path and time read none again but saved nothing
  measurable: it was never the reads). Two finds so far: fs.walk(sources) read the .gitignore chain
  and normalized the file's path once per ignored rule (stageChain's own-module walks 0.17 G to
  0.09), and the shaders' link built the same GPU files' unit once per call (gpuUnit kept per
  files and place, 0.20 G to 0.13). What is left of stageChain is the walks' own (~1M a walk, the
  .gitignore chain) and a module's walk repeating its submodules'; of the link, shader.prepareShader
  (~3M a call) and the stages' reindex of the declarations after each packer adopted (~0.5M a call)

## Handoff

- Done and committed: the fs.walk(sources) and gpuUnit finds above (skyrim warm load 1.17 G to 0.93 G
  cycles; the language's core checks pass). Measure with a one-line edit of projects/skyrim/main.zap
  and `ZAP_RUN=phases zap build projects/skyrim/main.zap`; temporary threadCycles() prints around the
  steps of addRuntime (modules.zap) found the splits.
- Not tried: the arena append (item 1) and the imports asked for at parse time (item 2); the parse
  hardly waits, so they are worth at most ~0.2 s of a cold load.
- Left: stageChain's per-walk cost (.gitignore chain read each walk, a parent module walking its
  submodules again), shader.prepareShader per call, ownModules 0.29 G, keepFrom (compiler-17).
