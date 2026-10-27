---
size: L
priority: P0
---
# Work on the start's partition alone

Work on the start's partition alone, never the whole build: record the profile of the start
(a run of about 1,200 turns of the whole build already in C:/Lucas/dev/zap/build, which still
loads under the runtime before the .load format changed, with the dispatcher's recording on
and `cpu.entered` written as tools/run.zap's --profile does), then `main.zap <exefs>
--profile <file> --build`: the functions the start entered (5,000 to 10,000 of 141,000) in a
few parts, 2-3 min cold and seconds warm, the rest on the interpreter; a fix rebuilds the one
part it touches. The whole build is built once more, at the end of the slice. Rebuilding all
131 parts (25 min) is not done again while a slice is worked on: today it happened twice (a
cpu/core change for the lockstep, and the .load format change of loadelf).
