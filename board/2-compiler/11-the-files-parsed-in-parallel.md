---
size: S
priority: P0
branch: compiler-11
by: 5d67fe9c-ad85-4d3c-be59-91c893160f91
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

- Done earlier: fs.walk(sources) and gpuUnit finds (skyrim warm load 1.17 G to 0.93 G cycles).
  Measure with a one-line edit of projects/skyrim/main.zap and `ZAP_RUN=phases zap build`.
- Tried and reverted: passing the GPU units borrowed in shader.prepareShader / gpu.compileStages
  (no unit copies): 640 and 815 M cycles against 637-745, noise. The load is now 0.26-0.31 s of a
  17 s build and nothing in it is above 0.1 s alone.
- Not tried: the arena append (item 1) and the imports asked for at parse time (item 2); the parse
  wait bounds both to ~0.1 s. Left: stageChain's per-walk cost, ownModules, keepFrom (compiler-17).
