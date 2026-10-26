---
size: S
---
# The load's rest on the main thread

The parse hardly waits now (skyrim cold: 0.1 s of a 4 s load); what is left of the step:

- [ ] reading each file, hashing its text and naming its cache entry (parseAsk, 0.1 s over
  skyrim's 460 files) and appending each arena to the program's (0.2 s) are the main thread's
- [ ] a module's imports are parsed after it, not beside it: their files could be asked for when
  it is parsed
- [ ] the load's other 3.5 s on skyrim, which is not the parse, is not profiled yet
