---
size: S
priority: P3
---
# The program's load spends less time on the main thread

Source files are parsed on every processor already and the parse hardly waits (skyrim cold: 0.1 s
of a 4 s load). What remains of the load is main-thread work, measured on skyrim, warm, with the
compiler's timing output.

- [ ] append each file's arena to the program's on the jobs instead of the main thread (0.2 s of
  skyrim's cold load). Reading each file and naming its cache entry on the jobs was tried and saved
  nothing measurable over noise (cold loads of the compiler and skyrim within 10%), so it was
  reverted; try another cut, and keep it only if the cold load falls beyond that noise
- [ ] ask for a module's imports' files when the module is parsed, not after it, so they are parsed
  beside it; skyrim's cold load shows it
- [x] the shaders' link walked every declaration once per question (moduleOfFile, gpuFilesOf,
  hasGpuFunction, rangeAliasOf, gpuUnit): one walk now indexes the GPU files' declarations
  (gpu.zap's GpuDecls), skyrim's warm load 1.23-1.29 G cycles to 1.02, the same executable
- [ ] the load's rest on skyrim, warm, main thread: `keepFrom` 0.32 G (the kept stages decoded:
  compiler-17), its own modules 0.26 G, the shaders' link 0.19 G, `stageChain` 0.16 G. Keeping its
  files' hashes stamped by path and time (as Go's file hash cache does) read none again but saved
  nothing measurable, so what it spends is not the reads; profile it before trying more
