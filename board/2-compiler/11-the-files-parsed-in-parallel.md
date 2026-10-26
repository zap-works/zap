---
size: S
---
# The load's rest on the main thread

The parse hardly waits now (skyrim cold: 0.1 s of a 4 s load); what is left of the step:

- [ ] reading each file, hashing its text and naming its cache entry (parseAsk, 0.1 s over
  skyrim's 460 files) and appending each arena to the program's (0.2 s) are the main thread's
- [ ] a module's imports are parsed after it, not beside it: their files could be asked for when
  it is parsed
- [ ] the load's rest on skyrim, warm, main thread (marks between addProgramModule's steps):
  its own modules 1.7 G cycles, the shaders' link 0.37 G (linkShaders walks every declaration
  several times: one walk indexing the GPU files' declarations was begun, uncommitted, in the
  worktree zap-wt-parse2, branch parse2), reachedDirs 0.31 G (readsUnder over the program),
  keepFrom 0.34 G (the kept stages read), runtimeIndex 0.22 G, stageChain 0.20 G (the stages'
  files hashed)
