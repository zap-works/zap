# Scripts against Python

The agents' throwaway scripts (searches, counts, reports, file shuffles) are written in Python;
`zap run file.zap` is to be the quicker and the plainer choice. An unchanged file starts the
executable it kept (0.1 to 0.4 of Python's time); an edited one is built again from the runtime and
std kept checked, lowered and as machine code (spec 14.2), their functions' bodies read from the
kept file only when the build lowers, inlines or instantiates one. The goal is the scripts bench
(`zap test --only bench tests/scripts`): eleven scripts on fixed inputs, Zap edited over Python in
bench.baseline, each process started directly; under 1.00 is the goal. Now: jsonq 1.74, table 1.57,
csvSum 1.51, count 1.43, todo 1.16, loc 1.14, replace 1.13, grep 1.10, gitStat 1.02, gitLog 0.93,
diff 0.26. On the arm64 host (two processors) Python's runs take 21 to 54 ms, Zap's unchanged 3 to
24; an edited table.zap's 34 ms are load 7 (the kept stages' nodes 3: 9,400 of their 38,700
decoded), check 6, code 11, write 1; jsonq.zap's 50 are load 7, check 8, code 21 (main 4, its
derived JSON readers 5 and their passes). A profile of a build's stacks as a tree (stacks by callers under chosen roots) and the derived
functions named by their text rather than their count were begun and reverted unfinished.
The scripts' own gaps are language-4 and runtime-1. The steps, worst first:
