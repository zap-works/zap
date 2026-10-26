# Compiler

Now: BotW recompiled (projects/recomp/switch) is 14.1 million lines of Zap in 131 loadable parts
(`zap build --loadable`); a cold part peaks at 0.7 GB and costs about 35 processor-seconds, nearly
all IR passes, so a 16 GB machine saturates at four parts at once (the game 25 minutes cold, about a
minute with the IR cache warm). The SNES recompiler matters most (DKC: about 4,000 small generated
functions and dispatch matches of 1,300 to 2,700 integer arms, 13 to 23 MB a game, rebuilt on every
fix; tools/recompShape.zap measures it): a cold build is 65% per-function passes (on every
processor), the rest the main thread alone (lowering 45% of it, checking 23%, parsing 10%, emitting
8%). The executable size's open items are recompilers-4 and 5.
