---
size: M
---
# coroPrimeSieve 1.34x (C++)

its division loop, about 14 instructions a prime against C++'s
5, and two hyperthreads sharing a core's divider. u32 in the Zap program (C++'s int is never
negative) drops the -1 check; measure with each thread on a core of its own.
