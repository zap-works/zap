---
size: L
---
# SMW speed on the arm64 host

Speed: SMW natively 8.1 ms a frame on the arm64 host (Neoverse N1), 9.2 ms wide at 486 in
Yoshi's Island 1; the S26 is about 3.3 times faster. Left: lines drawn whole when nothing
changes mid-line, the fetch a column at a time instead of a dot, the margins' pixels a tile row
at a time instead of a hook call each, hashing only when asked.
