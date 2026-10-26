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
- [ ] the load's rest on skyrim, warm, main thread: keepFrom 0.32 G (the kept stages decoded:
  compiler-17), its own modules 0.26 G, the shaders' link 0.19 G, stageChain 0.16 G (its files'
  hashes kept stamped by path and time, as Go's file hash cache, read none again but saved
  nothing measurable: what it spends is not the reads; not profiled further)
