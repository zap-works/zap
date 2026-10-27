---
size: L
priority: P2
---
# Scripts: The smaller costs

effects of the kept stages' functions summarized again each build
(findEffects, 2 ms of a small build) and their facts read whole (1 ms); some 1,900 page faults a
build (fresh big blocks, lists grown into new pages, kept files read into buffers; the heap's
chunks on huge pages took 160 off; 130 mmaps); on Windows every look at a file costs about 50 us
(a dir's listing 100) and a new executable's first start 8 ms more than its next (the antivirus
reads it; a loader that maps it as data took 4.6 ms off); the backend's merge of the same code
(its signatures made once, 1 ms), the jumps' relaxation and the executable's writing (1 ms each).
