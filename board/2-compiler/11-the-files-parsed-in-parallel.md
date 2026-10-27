---
size: S
blocked: three agents in a row measured no gain left (the parse wait is about 0.1 s of a 4 s cold load); its Handoff says why. Decide: close it or rethink it
priority: P0
branch: compiler-11
by: 25611521-ebc9-41e4-9965-f7cbab2abe0b
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
  Measure with a one-line edit of projects/skyrim/main.zap and `ZAP_RUN=phases zap build`
  (`phases,nocache` for the cold load: 1.38-1.46 G cycles, 640-680 ms wall).
- Tried and reverted: passing the GPU units borrowed in shader.prepareShader / gpu.compileStages
  (640 and 815 M cycles against 637-745, noise); appendParsed moving each node out by index
  (`n = move part.nodes[i]`) instead of reverse + pop: cold load 1.45-1.65 G against 1.38-1.46, worse.
- Not tried: the imports asked for at parse time (item 2); the parse wait bounds it to ~0.1 s of a
  4 s cold load. The arena append is a renumbering of every node (a bulk extend is plain elements
  only), so only the jobs numbering ahead would shrink it. Left: stageChain's per-walk cost,
  ownModules, keepFrom (compiler-17).
- This pass: no change. Skyrim's cold load (`phases,nocache`) is 1.27 G cycles, 672 ms wall of a
  10 s build; the parse wait is the part items 1 and 2 could shrink (~0.1 s), under the noise of
  earlier A/Bs. Item 2 means asking a module's imports' files (moduleSources search, dir fallbacks,
  error order of ImportCycle/ModuleNotFound) from inside parsedFiles: a restructure of loadModule
  for under 2% of the build, not started.
